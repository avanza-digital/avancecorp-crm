#!/usr/bin/env bash
# ORÁCULO RENTABILIDAD R4 (migración 20260907093000) — SOLO en el BANCO.
# El candado del servidor: con la política en «enforcement», ninguna vía puede fijar una tasa distinta a la resuelta
# sin una autorización viva de Gerencia para la MISMA huella, de un solo uso. Prueba adversarial (R4.3): bypass por
# SQL directo, doble consumo, huella cambiada, autorización vencida, tope sin aceptar, upgrade sin origen declarado,
# corrección de la tasa, datos demo, y el interruptor en los dos sentidos.
# Corrido SIN la migración = MUTANTE: los bloques C y D salen ROJOS (nada bloquea).
# Uso: S=/ruta/scratchpad ./oraculo-rentabilidad-r4.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
V2='f3000000-0000-0000-0000-000000000004'
SUP2="f3c00000-0000-0000-0000-${RUN}000003"
PA="f3a00000-0000-0000-0000-${RUN}000001"   # cliente de V
PB="f3b00000-0000-0000-0000-${RUN}000002"   # cliente de V2
ROJO=0; VERDE=0
ok()   { echo "  ✅ $*"; VERDE=$((VERDE+1)); }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else (('%f' % d).rstrip('0').rstrip('.') if isinstance(d,(int,float)) and not isinstance(d,bool) else d)))" "$1" "$2" 2>/dev/null; }
code() { echo "$1" | grep -oE "ERROR:  [0-9A-Z]{5}" | head -1 | awk '{print $2}'; }
espera() { local c; c="$(code "$1")"
  if [[ "$c" == "$2" ]] && echo "$1" | grep -qiE "$3"; then ok "$4 → $2"; else rojo "$4: esperaba $2 /$3/, salió: $(echo "$1" | tr '\n' ' ' | cut -c1-260)"; fi; }
# pasa <salida> <etiqueta> [numero_contrato]: el alta pasó DE VERDAD. Un JSON con id no basta: el candado es un
# trigger DIFERIDO, así que psql puede imprimir el id y fallar después en el COMMIT (Codex R4 #10). Se exige: id, cero
# errores en la salida, y —si se da el número— que el contrato exista al terminar la transacción.
pasa() {
  local id; id="$(j "$1" id)"
  if [[ -z "$id" ]]; then rojo "$2: el alta no devolvió id — $(echo "$1" | tr '\n' ' ' | cut -c1-240)"; return; fi
  if [[ -n "$(code "$1")" ]] || echo "$1" | grep -q "^ERROR:"; then rojo "$2: devolvió id pero la transacción falló — $(echo "$1" | tr '\n' ' ' | cut -c1-240)"; return; fi
  if [[ -n "${3:-}" ]] && [[ "$(q "select count(*) from public.contratos where numero_contrato='$3'")" != "1" ]]; then
    rojo "$2: la transacción no dejó el contrato $3 en la base"; return
  fi
  ok "$2"
}
# ok_sql <salida> <etiqueta>: una sentencia suelta que debe terminar sin error.
ok_sql() { if [[ -z "$(code "$1")" ]] && ! echo "$1" | grep -q "^ERROR:"; then ok "$2"; else rojo "$2: $(echo "$1" | tr '\n' ' ' | cut -c1-240)"; fi; }

# alta: ACTOR CLIENTE NUM TASA [CAP] [CATEGORIA] [ORIGEN] [INI] [FIN]
N_ALTA=0
alta() {
  N_ALTA=$((N_ALTA+1))
  local act="$1" cli="$2" num="$3" tasa="$4" cap="${5:-20000}" cat="${6:-nuevo}" org="${7:-}" ini="${8:-2026-03-11}" fin="${9:-2027-03-11}"
  local cci; cci="$(printf '004%s%011d' "$RUN" "$N_ALTA")"
  local extra=""
  [[ -n "$org" ]] && extra=",'contrato_origen_id','$org'"
  [[ "$cat" == "renovacion" ]] && extra="$extra,'capital_renovado',$cap,'capital_adicional',0"
  run_as "$act" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$cli','numero_contrato','$num','capital',$cap,'moneda','PEN','tasa_anual',$tasa,
      'modalidad','mensual','tipo_interes','simple','categoria','$cat','fecha_inicio','$ini','fecha_vencimiento','$fin',
      'notas_internas','oraculo rentabilidad r4 r$RUN'$extra),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','$fin','monto_programado',$cap,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','R4$RUN$N_ALTA','cci','$cci',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
# sol: ACTOR CLIENTE CATEGORIA ORIGEN|null CAPITAL TASA [INI] [FIN]
# sol: ACTOR CLIENTE CATEGORIA ORIGEN|null CAPITAL TASA [INI] [FIN] [CONTRATO_ID|null] — el último es el contexto de
# CORRECCIÓN (R4): sin él el núcleo rechaza el origen de una renovación por «ya renovado».
sol() { run_as "$1" "select crm.solicitar_tasa_fn(jsonb_build_object('cliente_id','$2','categoria','$3','contrato_origen_id',$4,'capital',$5,'moneda','PEN','modalidad','mensual','tipo_interes','simple','fecha_inicio','${7:-2026-03-11}','fecha_vencimiento','${8:-2027-03-11}','contrato_id',${9:-null},'tasa_solicitada',$6,'motivo','Oraculo R4: cliente pide mejor tasa'))"; }
dec()  { run_as "$1" "select crm.resolver_solicitud_tasa_fn('$2','$3',${4:-null},${5:-null})"; }
resp() { run_as "$1" "select crm.responder_tope_tasa_fn('$2',$3,${4:-null})"; }
publicar() { run_as "$G" "select crm.publicar_politica_rentabilidad_fn((select max(version) from crm.politica_rentabilidad), jsonb_build_object('tasa_base_nueva',15,'tope_tecnico',50,'vigencia_solicitud_dias',7,'modo','$1','nota','Oraculo R4 r$RUN: $1'))"; }
modo() { q "select modo from crm.politica_rentabilidad order by version desc limit 1"; }

echo "== Preflight (RUN=$RUN) =="
INSTALADA="$(q "select (to_regprocedure('private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)') is not null)")"
if [[ "$INSTALADA" == "t" ]]; then echo "  R4 instalada (todo debe salir VERDE)"; else echo "  ⚠️ R4 NO instalada: corrida MUTANTE (C y D deben salir ROJOS)"; fi
MODO_INI="$(modo)"
FLAG_RP="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"
FLAG_IE="$(q "select activo from crm.multiempresa_flags where nombre='inversiones_escritura'")"
restaurar() {
  psql "$PG" -q -c "update crm.multiempresa_flags set activo='${FLAG_RP:-f}' where nombre='resolver_en_puertas'; update crm.multiempresa_flags set activo='${FLAG_IE:-f}' where nombre='inversiones_escritura';" >/dev/null 2>&1
  if [[ "$(modo)" != "observacion" ]]; then publicar observacion >/dev/null 2>&1; fi
  echo "  (restaurado: flags y política en $(modo))"
}
trap restaurar EXIT
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');" >/dev/null
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$MODO_INI" == "observacion" ]] && ok "premisa: la política del banco arranca en observacion" || rojo "premisa: la política arranca en $MODO_INI (se restaurará al salir)"

echo
echo "== A · OBSERVACION: el candado está construido pero NO bloquea (regresión de R2/R3) =="
OUT="$(alta "$V" "$PA" "R4$RUN-A1" 22)"
pasa "$OUT" "A1 alta con tasa 22 (lejos de la base 15) PASA en observacion" "R4$RUN-A1"
C_A1="$(j "$OUT" id)"
LED="$(q "select origen||'|'||(tasa_base=15)||'|'||(tasa_final=22)||'|'||regla from crm.ledger_rentabilidad where contrato_id='$C_A1' order by secuencia desc limit 1")"
[[ "$LED" == "observacion|true|true|primera_inversion" ]] && ok "A2 el libro la anota como observacion (base 15, final 22)" || rojo "A2 libro inesperado: $LED"

echo
echo "== B · EL INTERRUPTOR: Gerencia publica enforcement =="
OUT="$(publicar enforcement)"
if [[ "$(j "$OUT" modo)" == "enforcement" ]]; then ok "B1 Gerencia publica modo=enforcement (R1 lo rechazaba con 0A000)"; else rojo "B1 no se pudo publicar enforcement: $(echo "$OUT" | tr '\n' ' ' | cut -c1-240)"; fi
[[ "$(modo)" == "enforcement" ]] && ok "B2 la política vigente queda en enforcement" || rojo "B2 la política sigue en $(modo)"
OUT="$(run_as "$V" "select crm.publicar_politica_rentabilidad_fn((select max(version) from crm.politica_rentabilidad), jsonb_build_object('tasa_base_nueva',15,'tope_tecnico',50,'vigencia_solicitud_dias',7,'modo','observacion'))")"
espera "$OUT" "42501" "Solo Gerencia|No autorizado|autoriz" "B3 un analista NO puede apagar el candado"

echo
echo "== C · EL CANDADO (política en enforcement) =="
OUT="$(alta "$V" "$PA" "R4$RUN-C1" 15)"
pasa "$OUT" "C1 alta a la tasa BASE (15) pasa" "R4$RUN-C1"
C_C1="$(j "$OUT" id)"
LED="$(q "select origen||'|'||coalesce(solicitud_id::text,'-') from crm.ledger_rentabilidad where contrato_id='$C_C1' order by secuencia desc limit 1")"
[[ "$LED" == "enforcement|-" ]] && ok "C2 el libro la anota como enforcement, sin autorización" || rojo "C2 libro inesperado: $LED"
OUT="$(alta "$V" "$PA" "R4$RUN-C3" 22)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C3 alta con tasa 22 sin autorización se RECHAZA"
[[ -z "$(q "select 1 from public.contratos where numero_contrato='R4$RUN-C3'")" ]] && ok "C4 el contrato rechazado NO existe (la transacción entera se deshizo)" || rojo "C4 el contrato rechazado quedó en la base"

# Autorización válida: pedir 18 para el MISMO capital y plazo, Gerencia aprueba, el alta pasa y la consume.
OUT="$(sol "$V" "$PA" nuevo null 20000 18)"; SOL1="$(j "$OUT" id)"
[[ -n "$SOL1" ]] && ok "C5 el analista pide 18% (solicitud ${SOL1:0:8})" || rojo "C5 no se pudo pedir: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"
OUT="$(dec "$G" "$SOL1" aprobar)"; [[ "$(j "$OUT" estado)" == "aprobada" ]] && ok "C6 Gerencia aprueba 18%" || rojo "C6 no se aprobó: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"
OUT="$(alta "$V" "$PA" "R4$RUN-C7" 18)"
pasa "$OUT" "C7 el alta a 18% PASA con la autorización" "R4$RUN-C7"
C_C7="$(j "$OUT" id)"
[[ "$(q "select estado||'|'||coalesce(contrato_id::text,'-') from crm.solicitudes_tasa where id='$SOL1'")" == "consumida|$C_C7" ]] && ok "C8 la autorización queda CONSUMIDA y apunta a ese contrato" || rojo "C8 la solicitud quedó $(q "select estado from crm.solicitudes_tasa where id='$SOL1'")"
LED="$(q "select origen||'|'||coalesce(solicitud_id::text,'-') from crm.ledger_rentabilidad where contrato_id='$C_C7' order by secuencia desc limit 1")"
[[ "$LED" == "enforcement|$SOL1" ]] && ok "C9 el libro guarda QUÉ autorización se usó" || rojo "C9 libro inesperado: $LED"
OUT="$(alta "$V" "$PA" "R4$RUN-C10" 18)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C10 DOBLE CONSUMO: un segundo contrato con la misma autorización se rechaza"

# Huella cambiada tras aprobar: la autorización no aplica a otro capital.
OUT="$(sol "$V" "$PA" nuevo null 20000 19)"; SOL2="$(j "$OUT" id)"
dec "$G" "$SOL2" aprobar >/dev/null
OUT="$(alta "$V" "$PA" "R4$RUN-C11" 19 30000)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C11 HUELLA CAMBIADA: autorizado 20 000, se intenta con 30 000 → rechazo"
OUT="$(alta "$V" "$PA" "R4$RUN-C12" 19 20000)"
pasa "$OUT" "C12 con el capital autorizado (20 000) sí pasa" "R4$RUN-C12"

# Tope sin aceptar: aprobada_con_tope no habilita nada hasta que el analista acepta.
OUT="$(sol "$V" "$PA" nuevo null 21000 20)"; SOL3="$(j "$OUT" id)"
dec "$G" "$SOL3" aprobar_hasta 17 "'Mercado a 17'" >/dev/null
OUT="$(alta "$V" "$PA" "R4$RUN-C13" 17 21000)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C13 TOPE SIN ACEPTAR: aprobada_con_tope no habilita el alta"
resp "$V" "$SOL3" true >/dev/null
OUT="$(alta "$V" "$PA" "R4$RUN-C14" 17 21000)"
pasa "$OUT" "C14 tras ACEPTAR el tope, el alta a 17% pasa" "R4$RUN-C14"
OUT="$(sol "$V" "$PA" nuevo null 22000 20)"; SOL4="$(j "$OUT" id)"
dec "$G" "$SOL4" aprobar_hasta 17 >/dev/null
resp "$V" "$SOL4" false >/dev/null
OUT="$(alta "$V" "$PA" "R4$RUN-C15" 17 22000)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C15 tras DECLINAR el tope, no habilita nada"

# Autorización vencida.
OUT="$(sol "$V" "$PA" nuevo null 23000 18)"; SOL5="$(j "$OUT" id)"
dec "$G" "$SOL5" aprobar >/dev/null
# vence_en > solicitada_en es una restricción de la tabla: para envejecer una autorización hay que mover las dos fechas.
VENC="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.solicitud_tasa_por_puerta','on',true); update crm.solicitudes_tasa set solicitada_en = statement_timestamp() - interval '10 days', resuelta_en = statement_timestamp() - interval '9 days', vence_en = statement_timestamp() - interval '3 days' where id='$SOL5'; commit;" 2>&1)"
[[ "$(q "select vence_en < statement_timestamp() from crm.solicitudes_tasa where id='$SOL5'")" == "t" ]] || rojo "C16 preparación: no se pudo vencer la autorización — $(echo "$VENC" | tr '\n' ' ' | cut -c1-160)"
OUT="$(alta "$V" "$PA" "R4$RUN-C16" 18 23000)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C16 autorización VENCIDA: no habilita"

# Por encima del tope autorizado y por debajo de la base.
OUT="$(sol "$V" "$PA" nuevo null 24000 18)"; SOL6="$(j "$OUT" id)"
dec "$G" "$SOL6" aprobar >/dev/null
OUT="$(alta "$V" "$PA" "R4$RUN-C17" 19 24000)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C17 autorizado hasta 18, se intenta 19 → rechazo"
OUT="$(alta "$V" "$PA" "R4$RUN-C18" 12 24000)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C18 NUNCA por debajo de la base (D4): 12% se rechaza"

# Bypass por SQL directo (sin ninguna puerta, como postgres): el candado vive en el trigger, no en la RPC.
alta_cruda() { sys "insert into public.contratos (cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, categoria, estado, es_demo) values ('$1','$2',20000,'PEN',$3,'mensual','simple','2026-03-11','2027-03-11','nuevo','activo',${4:-false})"; }
OUT="$(alta_cruda "$PA" "R4$RUN-C19" 30)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C19 BYPASS DIRECTO por SQL (sin RPC, como postgres) también se rechaza"
OUT="$(alta_cruda "$PA" "R4$RUN-C19b" 15)"
[[ -z "$(code "$OUT")" ]] && ok "C19b el mismo INSERT directo a la tasa base sí pasa (el candado juzga la tasa, no la vía)" || rojo "C19b bloqueó un insert a la base: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"

# Corrección: cambiar la tasa exige autorización; tocar otra cosa no re-litiga la tasa.
OUT="$(sys "update public.contratos set tasa_anual = 25 where id='$C_C1'")"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "C20 CORRECCIÓN de la tasa sin autorización se rechaza"
OUT="$(sys "update public.contratos set capital = 20500 where id='$C_C1'")"
[[ -z "$(code "$OUT")" ]] && ok "C21 corregir el CAPITAL (sin tocar la tasa) sigue pasando" || rojo "C21 la corrección de capital se bloqueó: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"

# Upgrade: sin origen declarado no pasa; con el origen que eligió el analista, hereda.
ORG="$(q "select id from public.contratos where cliente_id='$PA' and estado='activo' and tasa_anual=15 order by creado_en limit 1")"
OUT="$(alta "$V" "$PA" "R4$RUN-C22" 15 5000 upgrade "" 2026-04-01 2027-04-01)"
espera "$OUT" "P0410" "declarar el contrato que amplía|amplía un contrato activo" "C22 UPGRADE sin origen declarado (D2) se rechaza"
if [[ -n "$ORG" ]]; then
  OUT="$(alta "$V" "$PA" "R4$RUN-C23" 15 5000 upgrade "$ORG" 2026-04-01 2027-04-01)"
  pasa "$OUT" "C23 UPGRADE con el origen declarado pasa a la tasa heredada (15)" "R4$RUN-C23"
  C_C23="$(j "$OUT" id)"
  LED="$(q "select regla||'|'||coalesce(contrato_origen_id::text,'-') from crm.ledger_rentabilidad where contrato_id='$C_C23' order by secuencia desc limit 1")"
  [[ "$LED" == "heredada_upgrade|$ORG" ]] && ok "C24 el libro anota heredada_upgrade con su origen (ya no es sin_regla)" || rojo "C24 libro inesperado: $LED"
  OUT="$(alta "$V" "$PA" "R4$RUN-C25" 20 5000 upgrade "$ORG" 2026-05-01 2027-05-01)"
  espera "$OUT" "P0410" "la fija la política|autorización vigente" "C25 UPGRADE a una tasa distinta de la heredada se rechaza"
else
  rojo "C23..C25: no se encontró contrato origen activo del cliente"
fi

# Datos demo: el candado no los toca (un contrato no NACE marcado; se marca después).
OUT="$(alta "$V" "$PA" "R4$RUN-C26" 15)"
C_C26="$(j "$OUT" id)"
if [[ -n "$C_C26" ]]; then
  # La marca de prueba solo se pone por su puerta, y con autoridad de gerencia.
  run_as "$G" "select public.marcar_contrato_demo('$C_C26', true, 'oraculo rentabilidad r4')" >/dev/null
  [[ "$(q "select es_demo from public.contratos where id='$C_C26'")" == "t" ]] || rojo "C26 preparación: el contrato no quedó marcado como prueba"
  OUT="$(sys "update public.contratos set tasa_anual = 33 where id='$C_C26'")"
  [[ -z "$(code "$OUT")" ]] && ok "C26 los datos DEMO no se bloquean (tasa 33 en un contrato de prueba)" || rojo "C26 el candado bloqueó un demo: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"
else
  rojo "C26: no se pudo crear el contrato de prueba"
fi


echo
echo "== C-bis · LO QUE ENCONTRÓ CODEX EN R4 (todos deben quedar cerrados) =="
# #1 La autorización NO se estira a otra intención: corregir el capital manteniendo la tasa excepcional se rechaza.
OUT="$(sol "$V" "$PA" nuevo null 25000 18)"; SOL7="$(j "$OUT" id)"
dec "$G" "$SOL7" aprobar >/dev/null
OUT="$(alta "$V" "$PA" "R4$RUN-E1" 18 25000)"
pasa "$OUT" "E1 alta a 18% con autorización para 25 000" "R4$RUN-E1"
C_E1="$(j "$OUT" id)"
OUT="$(sys "update public.contratos set capital = 100000 where id='$C_E1'")"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "E2 CODEX #1: subir el capital a 100 000 manteniendo el 18% se RECHAZA (la autorización era para 25 000)"
OUT="$(sys "update public.contratos set notas_internas = 'solo una nota' where id='$C_E1'")"
ok_sql "$OUT" "E3 y tocar algo que no es de la huella (una nota) sigue pasando"
OUT="$(sys "update public.contratos set modalidad = 'trimestral' where id='$C_E1'")"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "E4 CODEX #1: cambiar la MODALIDAD con la tasa excepcional también se rechaza"

# #4 El marcador de «ya observado» no exime de validar: SET CONSTRAINTS ALL IMMEDIATE a mitad de transacción.
OUT="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; select set_config('crm.op_privilegiada','on',true); insert into public.contratos (cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, categoria, estado) values ('$PA','R4$RUN-E5',20000,'PEN',15,'mensual','simple','2026-03-11','2027-03-11','nuevo','activo'); set constraints all immediate; update public.contratos set tasa_anual = 27 where numero_contrato='R4$RUN-E5'; commit;" 2>&1)"
espera "$OUT" "P0410" "la fija la política|autorización vigente" "E5 CODEX #4: alta válida + SET CONSTRAINTS IMMEDIATE + corrección a 27% se rechaza (el marcador no es un pasaporte)"
[[ -z "$(q "select 1 from public.contratos where numero_contrato='R4$RUN-E5'")" ]] && ok "E6 y no quedó nada de esa transacción" || rojo "E6 el contrato de la transacción rechazada quedó en la base"

# #5 La declaración del origen es de UN SOLO USO. Un upgrade no se puede insertar a pelo (otra guarda exige el flujo de
# cartera), así que el ensayo va por la puerta REAL, dos veces en la MISMA transacción: la primera declara su origen y
# la segunda no. Si la declaración se compartiera, la segunda heredaría una tasa que nadie autorizó para ella.
ORG2="$(q "select id from public.contratos where cliente_id='$PA' and estado='activo' and not es_demo and tasa_anual=15 order by creado_en limit 1")"
if [[ -n "$ORG2" ]]; then
  alta_sql() { # alta_sql <numero> <tasa> <capital> <categoria> <origen|vacío> <ini> <fin>
    local extra=""; [[ -n "$5" ]] && extra=",'contrato_origen_id','$5'"
    echo "select crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_build_object('cliente_id','$PA','numero_contrato','$1','capital',$3,'moneda','PEN','tasa_anual',$2,
        'modalidad','mensual','tipo_interes','simple','categoria','$4','fecha_inicio','$6','fecha_vencimiento','$7',
        'notas_internas','oraculo r4 r$RUN'$extra),
      jsonb_build_array(
        jsonb_build_object('numero_cuota',1,'fecha_programada','2026-09-01','monto_programado',100,'tipo','cuota'),
        jsonb_build_object('numero_cuota',2,'fecha_programada','$7','monto_programado',$3,'tipo','retorno')),
      jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','R4$RUN$1','cci','$(printf '004%s%011d' "$RUN" $((N_ALTA+90)))',
        'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
  }
  OUT="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$V\",\"role\":\"authenticated\"}', true); $(alta_sql "R4$RUN-E7" 15 3000 upgrade "$ORG2" 2026-06-01 2027-06-01); $(alta_sql "R4$RUN-E8" 15 3000 upgrade "" 2026-07-01 2027-07-01); commit;" 2>&1)"
  espera "$OUT" "P0410" "declarar el contrato que amplía|la fija la política|amplía un contrato activo" "E7 CODEX #5: dos upgrades en UNA transacción y una sola declaración → el segundo se rechaza (la declaración no se comparte)"
  [[ -z "$(q "select 1 from public.contratos where numero_contrato in ('R4$RUN-E7','R4$RUN-E8')")" ]] && ok "E8 y no quedó ninguno de los dos (la transacción entera se deshizo)" || rojo "E8 quedó algún contrato de la transacción rechazada"
  # Autorreferencia: se prueba la guarda directamente (por la puerta es inalcanzable, el id no existe todavía).
  AUTO="$(q "select id from public.contratos where numero_contrato='R4$RUN-C1'")"
  DEC="$(psql "$PG" -qtA -c "begin; select set_config('crm.rentabilidad_origen_upgrade', '$PA|$AUTO', true); select coalesce(private.rentabilidad_origen_declarado(c.*)::text, 'NULO') from public.contratos c where c.id='$AUTO'; commit;" 2>&1 | grep -E "NULO|[0-9a-f]{8}-" | tail -1)"
  [[ "$DEC" == "NULO" ]] && ok "E9 CODEX #5: un contrato que se declara a SÍ MISMO como origen no obtiene origen (guarda de autorreferencia)" || rojo "E9 la guarda de autorreferencia devolvió: $DEC"
else
  rojo "E7..E9: no se encontró contrato origen activo para el ensayo"
fi

# #6 Un contrato de PRUEBA no presta su tasa a un upgrade real.
DEMO="$(q "select id from public.contratos where cliente_id='$PA' and es_demo and estado='activo' limit 1")"
if [[ -n "$DEMO" ]]; then
  OUT="$(alta "$V" "$PA" "R4$RUN-E10" "$(q "select tasa_anual from public.contratos where id='$DEMO'")" 4000 upgrade "$DEMO" 2026-08-01 2027-08-01)"
  espera "$OUT" "P0410" "declarar el contrato que amplía|la fija la política|amplía un contrato activo" "E10 CODEX #6: un contrato de PRUEBA no puede ser el origen de un upgrade real"
else
  rojo "E10: no había contrato de prueba para el ensayo"
fi

# #3 Se puede PEDIR autorización para corregir la tasa de una renovación (antes el núcleo lo impedía).
REN_ORG="$(q "select c.id from public.contratos c where c.cliente_id='$PA' and c.estado='activo' and not c.es_demo and c.renovado_a_id is null and c.fecha_vencimiento <= (now() at time zone 'America/Lima')::date order by c.creado_en limit 1")"
if [[ -z "$REN_ORG" ]]; then
  # En el banco se envejece un contrato del propio ensayo para poder renovarlo (la fecha no es de la huella del alta).
  REN_ORG="$(q "select c.id from public.contratos c where c.numero_contrato='R4$RUN-C1'")"
  sys "update public.contratos set fecha_vencimiento = (now() at time zone 'America/Lima')::date - 1 where id='$REN_ORG'" >/dev/null
  [[ "$(q "select fecha_vencimiento < (now() at time zone 'America/Lima')::date from public.contratos where id='$REN_ORG'")" == "t" ]] || REN_ORG=""
fi
if [[ -n "$REN_ORG" ]]; then
  OUT="$(alta "$V" "$PA" "R4$RUN-E11" "$(q "select tasa_anual from public.contratos where id='$REN_ORG'")" "$(q "select capital from public.contratos where id='$REN_ORG'")" renovacion "$REN_ORG" 2027-01-01 2028-01-01)"
  C_E11="$(j "$OUT" id)"
  if [[ -n "$C_E11" ]]; then
    ok "E11 renovación creada a la tasa heredada"
    CAPR="$(q "select capital from public.contratos where id='$C_E11'")"
    OUT="$(sol "$V" "$PA" renovacion "'$REN_ORG'" "$CAPR" 30 2027-01-01 2028-01-01 "'$C_E11'")"
    [[ -n "$(j "$OUT" id)" ]] && ok "E12 CODEX #3: se puede PEDIR autorización para corregir la tasa de una renovación" || rojo "E12 no se pudo pedir: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"
  elif echo "$OUT" | grep -q "datos legales obligatorios"; then
    echo "  ⚠ E11..E12: el cliente sembrado no tiene datos legales completos, que la renovación exige para su PDF (bloque saltado; el candado de la renovación se prueba en C22..C25)"
  else
    rojo "E11 no se pudo crear la renovación: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"
  fi
else
  echo "  ⚠ E11..E12: sin contrato vencido para renovar en este banco (bloque saltado)"
fi

# #12 Por debajo de la base no se ofrece pedir permiso: se dice que corrija.
OUT="$(alta "$V" "$PA" "R4$RUN-E13" 9)"
espera "$OUT" "P0410" "no puede quedar por debajo" "E13 CODEX #12: por debajo de la base el mensaje NO invita a pedir autorización (D4)"

# #2 La huella de una CORRECCIÓN legacy coincide: pedir → aprobar → corregir la tasa funciona de punta a punta.
OUT="$(alta "$V" "$PA" "R4$RUN-E14" 15 26000)"
pasa "$OUT" "E14 alta a la base para el ensayo de corrección" "R4$RUN-E14"
C_E14="$(j "$OUT" id)"
OUT="$(sol "$V" "$PA" nuevo null 26000 19 2026-03-11 2027-03-11 "'$C_E14'")"; SOL8="$(j "$OUT" id)"
if [[ -n "$SOL8" ]]; then
  dec "$G" "$SOL8" aprobar >/dev/null
  OUT="$(sys "update public.contratos set tasa_anual = 19 where id='$C_E14'")"
  ok_sql "$OUT" "E15 CODEX #2: la CORRECCIÓN de la tasa de un contrato legacy pasa con su autorización (la huella coincide)"
  [[ "$(q "select estado from crm.solicitudes_tasa where id='$SOL8'")" == "consumida" ]] && ok "E16 y la autorización queda consumida por esa corrección" || rojo "E16 la autorización quedó $(q "select estado from crm.solicitudes_tasa where id='$SOL8'")"
else
  rojo "E15..E16: no se pudo pedir la autorización de la corrección: $(echo "$OUT" | tr '\n' ' ' | cut -c1-200)"
fi

echo
echo "== D · LA VUELTA ATRÁS: publicar observacion apaga el candado sin migración =="
OUT="$(publicar observacion)"
[[ "$(j "$OUT" modo)" == "observacion" ]] && ok "D1 Gerencia publica observacion" || rojo "D1 no se pudo volver a observacion: $(echo "$OUT" | tr '\n' ' ' | cut -c1-240)"
OUT="$(alta "$V" "$PA" "R4$RUN-D2" 24)"
pasa "$OUT" "D2 con el candado apagado, una tasa 24 vuelve a pasar (y queda anotada)" "R4$RUN-D2"
C_D2="$(j "$OUT" id)"
[[ "$(q "select origen from crm.ledger_rentabilidad where contrato_id='$C_D2' order by secuencia desc limit 1")" == "observacion" ]] && ok "D3 y el libro vuelve a decir observacion" || rojo "D3 el libro no volvió a observacion"

echo
echo "== RESULTADO RUN=$RUN: $VERDE verdes, $ROJO rojos =="
[[ $ROJO -eq 0 ]] || exit 1
