#!/usr/bin/env bash
# ORÁCULO RENTABILIDAD R1 (migración 20260906170000) — SOLO en el BANCO.
# Prueba el núcleo (private.resolver_tasa por su puerta), las solicitudes de tasa (pedir → Gerencia decide: aprobar /
# rechazar / aprobar hasta X → el analista acepta o declina), la política versionada, el ledger legacy, la RLS y que las
# puertas de escritura de contratos siguen byte a byte (un alta con tasa 12 sigue entrando: R1 no bloquea nada).
# Corrido SIN la migración = MUTANTE: B..J salen ROJAS. Con ella, TODO VERDE.
# Uso: S=/ruta/scratchpad ./oraculo-rentabilidad-r1.sh   (lee $S/banco-pooler.txt). RUN de 6 dígitos por corrida.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
V2='f3000000-0000-0000-0000-000000000004'; VI='f3000000-0000-0000-0000-000000000005'
SUP2="f3c00000-0000-0000-0000-${RUN}000003"  # supervisor efímero de V2 (un vendedor activo exige supervisor activo)
PC="f3b00000-0000-0000-0000-${RUN}000004"    # cliente INACTIVO de V
ADM="f3c00000-0000-0000-0000-${RUN}000001"   # admin del Portal, SIN ficha CRM (pide por es_admin)
PA="f3a00000-0000-0000-0000-${RUN}000001"   # cliente de V (siembra f3)
PB="f3b00000-0000-0000-0000-${RUN}000002"   # cliente de V2 (esta corrida)
ROJO=0; VERDE=0
ok()   { echo "  ✅ $*"; VERDE=$((VERDE+1)); }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
run_anon() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role authenticated; select set_config('request.jwt.claims', '{\"role\":\"authenticated\"}', true); $1; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else (('%f' % d).rstrip('0').rstrip('.') if isinstance(d,(int,float)) and not isinstance(d,bool) else d)))" "$1" "$2" 2>/dev/null; }
cnt_as() { run_as "$1" "$2" | tail -1; }
cnt_anon() { run_anon "$1" | tail -1; }
code() { echo "$1" | grep -oE "ERROR:  [0-9A-Z]{5}" | head -1 | awk '{print $2}'; }
espera() { # espera <salida> <sqlstate> <regex mensaje> <etiqueta>
  local c; c="$(code "$1")"
  if [[ "$c" == "$2" ]] && echo "$1" | grep -qiE "$3"; then ok "$4 → $2"; else rojo "$4: esperaba $2 /$3/, salió: $(echo "$1" | tr '\n' ' ' | cut -c1-220)"; fi; }
# alta <actor> <cliente> <numero> <tasa> [capital]
N_ALTA=0
alta() {
  N_ALTA=$((N_ALTA+1)); local cap="${5:-20000}"; local cci; cci="$(printf '002%s%011d' "$RUN" "$N_ALTA")"
  run_as "$1" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$2','numero_contrato','$3','capital',$cap,'moneda','PEN','tasa_anual',$4,
      'modalidad','mensual','tipo_interes','simple','categoria','nuevo','fecha_inicio','2026-03-11','fecha_vencimiento','2027-03-11',
      'notas_internas','oraculo rentabilidad r1 r$RUN'),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','2027-03-11','monto_programado',$cap,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','RENT$RUN$N_ALTA','cci','$cci',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
res() { run_as "$1" "select crm.resolver_tasa_fn('$2','$3',${4:-null})"; }   # res <actor> <cliente> <categoria> ['uuid'|null]
# sol <actor> <cliente> <categoria> <origen|null> <capital> <tasa> [motivo]
sol() { run_as "$1" "select crm.solicitar_tasa_fn(jsonb_build_object('cliente_id','$2','categoria','$3','contrato_origen_id',$4,'capital',$5,'moneda','PEN','modalidad','mensual','tipo_interes','simple','fecha_inicio','2026-10-01','fecha_vencimiento','2027-10-01','tasa_solicitada',$6,'motivo','${7:-Cliente referido con capital fresco; pide mejor tasa}'))"; }
dec() { run_as "$1" "select crm.resolver_solicitud_tasa_fn('$2','$3',${4:-null},${5:-null})"; }   # dec <actor> <id> <decision> [tope] ['motivo']
resp() { run_as "$1" "select crm.responder_tope_tasa_fn('$2',$3,${4:-null})"; }
estado() { q "select estado||'|'||coalesce(tasa_maxima_autorizada::text,'-')||'|'||coalesce(resuelta_por::text,'-') from crm.solicitudes_tasa where id='$1'"; }
GATES_OK="0fd6fa8d1d8f8106cb52662cb64193e0 85614480d6c8939e818342ef3fe63c65 7f2b4976640553a50ab27cf25b30fb36 061c40e345312ca5e515ddd5ee282e5c db2e6d36d46c72250fd6f42022af80be"
GATES_D19="0fd6fa8d1d8f8106cb52662cb64193e0 85614480d6c8939e818342ef3fe63c65 0de7a130ae366cde54035e2c50f213e2 4bf2f691888bee4d3198cccba8acd396 db2e6d36d46c72250fd6f42022af80be"
GATES_R4="a363ad7e514c8eef3257acd7a1a54d44 85614480d6c8939e818342ef3fe63c65 0de7a130ae366cde54035e2c50f213e2 4bf2f691888bee4d3198cccba8acd396 db2e6d36d46c72250fd6f42022af80be"   # con RENTABILIDAD R4 (la puerta del alta declara el origen del upgrade)   # con F2.b D-19 aplicada (banco)
gates() { q "select string_agg(h, ' ' order by o) from (select case p.proname when 'crear_contrato_con_cuenta_pdf_v2' then 1 when 'actualizar_contrato_con_cuenta_pdf_v3' then 2 when 'crear_contrato_con_cuenta' then 3 when 'crear_contrato' then 4 else 5 end o, md5(p.prosrc) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='crm' and p.proname in ('crear_contrato_con_cuenta_pdf_v2','actualizar_contrato_con_cuenta_pdf_v3','crear_contrato_con_cuenta')) or (n.nspname='public' and p.proname in ('crear_contrato','actualizar_contrato'))) x"; }

echo "== Preflight (RUN=$RUN) =="
FLAG_RP="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"
FLAG_IE="$(q "select activo from crm.multiempresa_flags where nombre='inversiones_escritura'")"
restaurar() { psql "$PG" -q -c "update crm.multiempresa_flags set activo='${FLAG_RP:-f}' where nombre='resolver_en_puertas'; update crm.multiempresa_flags set activo='${FLAG_IE:-f}' where nombre='inversiones_escritura';" >/dev/null; }
trap restaurar EXIT
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');" >/dev/null
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
INSTALADA="$(q "select (to_regprocedure('crm.resolver_tasa_fn(uuid,text,uuid)') is not null)")"
if [[ "$INSTALADA" == "t" ]]; then echo "  R1 instalada (todo debe salir VERDE)"; else echo "  ⚠️ R1 NO instalada: corrida MUTANTE (B..J deben salir ROJAS)"; fi
GATES_INI="$(gates)"; [[ "$GATES_INI" == "$GATES_OK" || "$GATES_INI" == "$GATES_D19" || "$GATES_INI" == "$GATES_R4" ]] && ok "premisa: las 5 puertas de escritura llevan un texto conocido (prod 06/09, D-19 o R4)" || rojo "puertas con otro texto: $GATES_INI"
# V2 activo bajo SUP2 (fuera del subárbol de SUP, para probar el ámbito); VI queda inactivo; PB cliente de V2.
sys "insert into auth.users (id) values ('$SUP2'), ('$PB') on conflict (id) do nothing;
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$SUP2','R1 SUPERVISOR DOS r$RUN','comercial','DNI','8${RUN}3') on conflict (id) do update set activo = true;
     insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$SUP2','supervisor',null,true,'$G') on conflict (perfil_id) do update set activo=true, rol_crm='supervisor', supervisor_id=null;
     update public.perfiles set activo=true where id='$V2';
     update crm.equipo set activo=true, supervisor_id='$SUP2', rol_crm='vendedor' where perfil_id='$V2';
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id) values ('$PB','R1 CLIENTE DE V2 r$RUN','cliente','DNI','7${RUN}5','$V2') on conflict (id) do nothing;"
[[ "$(q "select count(*) from public.perfiles where id='$PA' and rol='cliente' and activo and asesor_perfil_id='$V'")" == "1" ]] && ok "fixture: PA cliente de V" || rojo "fixture PA"
[[ "$(q "select count(*) from public.perfiles where id='$PB' and rol='cliente' and activo and asesor_perfil_id='$V2'")" == "1" ]] && ok "fixture: PB cliente de V2" || rojo "fixture PB"
sys "insert into auth.users (id) values ('$PC'), ('$ADM') on conflict (id) do nothing;
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id, activo) values ('$PC','R1 CLIENTE INACTIVO r$RUN','cliente','DNI','7${RUN}6','$V',false) on conflict (id) do update set activo=false;
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$ADM','R1 ADMIN PORTAL r$RUN','admin','DNI','8${RUN}1') on conflict (id) do update set activo=true;"
[[ "$(q "select count(*) from public.perfiles where id='$PC' and rol='cliente' and not activo")" == "1" ]] && ok "fixture: PC cliente INACTIVO" || rojo "fixture PC"
[[ "$(q "select count(*) from public.perfiles p where p.id='$ADM' and p.rol='admin' and p.activo and not exists (select 1 from crm.equipo e where e.perfil_id=p.id)")" == "1" ]] && ok "fixture: ADM admin del Portal sin ficha CRM" || rojo "fixture ADM"
[[ "$(q "select count(*) from crm.equipo where perfil_id='$V2' and activo and supervisor_id='$SUP2'")" == "1" ]] && ok "fixture: V2 activo bajo SUP2 (fuera del subárbol de SUP)" || rojo "fixture V2"
[[ "$(q "select count(*) from crm.equipo where perfil_id='$VI' and not activo")" == "1" ]] && ok "fixture: VI inactivo" || rojo "fixture VI"
O="$(alta "$V" "$PA" "R1-$RUN-C1" 15)"; C1="$(j "$O" id)"; [[ -n "$C1" ]] && ok "fixture: C1 de PA al 15% (${C1:0:8}…)" || rojo "C1 no se creó: ${O:0:200}"
O="$(alta "$V" "$PA" "R1-$RUN-C2" 18)"; C2="$(j "$O" id)"; [[ -n "$C2" ]] && ok "fixture: C2 de PA al 18%" || rojo "C2 no se creó: ${O:0:200}"
O="$(alta "$V2" "$PB" "R1-$RUN-C3" 12)"; C3="$(j "$O" id)"; [[ -n "$C3" ]] && ok "fixture: C3 de PB al 12% (por V2)" || rojo "C3 no se creó: ${O:0:200}"
O="$(alta "$V" "$PA" "R1-$RUN-C5" 18)"; C5="$(j "$O" id)"; [[ -n "$C5" ]] && ok "fixture: C5 de PA al 18% (se vencerá)" || rojo "C5 no se creó: ${O:0:200}"
LEDGER_ANTES="$(q "select count(*) from crm.ledger_rentabilidad")"

echo "== A) Backfill legacy y política v1 =="
PUB1="$(q "select publicada_en from crm.politica_rentabilidad where version=1")"
[[ -n "$PUB1" ]] && ok "política v1 existe (publicada $PUB1)" || rojo "sin política v1"
[[ "$(q "select tasa_base_nueva||'|'||tope_tecnico||'|'||vigencia_solicitud_dias||'|'||modo from crm.politica_rentabilidad where version=1")" == "15|50|7|observacion" ]] && ok "v1 = 15 · 50 · 7 días · observación" || rojo "v1 con otros valores"
[[ "$(q "select count(*) from public.contratos c where c.creado_en < '$PUB1'::timestamptz and not exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id=c.id and l.origen='backfill_legacy')")" == "0" ]] && ok "todo contrato anterior a la migración tiene su fila legacy" || rojo "contratos anteriores sin fila legacy"
[[ "$(q "select count(*) from crm.ledger_rentabilidad l join public.contratos c on c.id=l.contrato_id where l.origen='backfill_legacy' and (l.tasa_final<>c.tasa_anual or l.tasa_base<>c.tasa_anual or l.divergente or l.regla<>'historica_legacy')")" == "0" ]] && ok "cada fila legacy = tasa_anual del contrato, sin divergencia" || rojo "filas legacy incoherentes"
R2="$(q "select (to_regprocedure('crm.observacion_rentabilidad_fn(date,date)') is not null)")"
if [[ "$R2" == "t" ]]; then
  [[ "$(q "select count(*) from crm.ledger_rentabilidad l where l.contrato_id in ('$C1','$C2','$C3') and l.origen='observacion'")" == "3" ]] && ok "con R2 instalada, las 3 altas de fixtures quedaron OBSERVADAS en el ledger" || rojo "R2 instalada pero las altas no se observaron"
else
  [[ "$(q "select count(*) from crm.ledger_rentabilidad l where l.contrato_id in ('$C1','$C2','$C3')")" == "0" ]] && ok "las altas posteriores NO escriben en el ledger (eso es R2)" || rojo "R1 escribió en el ledger en un alta"
fi

echo "== B) EL NÚCLEO por su puerta (V sobre su cliente PA) =="
BASE="$(q "select tasa_base_nueva from (select * from crm.politica_rentabilidad order by vigente_desde desc, version desc limit 1) p")"; [[ -z "$BASE" ]] && BASE="(sin política)"
O="$(res "$V" "$PA" nuevo)"
[[ "$(j "$O" tasa_base)" == "$BASE" && "$(j "$O" regla)" == "primera_inversion" ]] && ok "nuevo → base ${BASE}% · primera_inversion" || rojo "nuevo: $(echo "$O" | cut -c1-200)"
[[ "$(j "$O" contratos_previos)" == "3" && "$(j "$O" prioridad_bandeja)" == "True" ]] && ok "D1: cliente con 3 contratos previos (C1, C2, C5) → sigue en base, prioridad_bandeja=true" || rojo "D1: previos=$(j "$O" contratos_previos) prioridad=$(j "$O" prioridad_bandeja)"
[[ "$(j "$O" politica.modo)" == "observacion" && -n "$(j "$O" politica.version)" ]] && ok "la respuesta trae la política (versión, modo)" || rojo "sin política en la respuesta"
O="$(res "$V" "$PA" renovacion "'$C1'")"; [[ "$(j "$O" tasa_base)" == "15" && "$(j "$O" regla)" == "heredada_renovacion" && "$(j "$O" contrato_origen.numero_contrato)" == "R1-$RUN-C1" ]] && ok "renovación de C1 → hereda 15% · heredada_renovacion · trae el origen" || rojo "renovación C1: $(echo "$O" | cut -c1-200)"
O="$(res "$V" "$PA" renovacion "'$C2'")"; [[ "$(j "$O" tasa_base)" == "18" ]] && ok "renovación de C2 → hereda 18%" || rojo "renovación C2: $(echo "$O" | cut -c1-200)"
O="$(res "$V" "$PA" upgrade "'$C2'")"; [[ "$(j "$O" tasa_base)" == "18" && "$(j "$O" regla)" == "heredada_upgrade" ]] && ok "D2: upgrade sobre C2 (activo, seleccionado) → hereda 18% · heredada_upgrade" || rojo "upgrade C2: $(echo "$O" | cut -c1-200)"
espera "$(res "$V" "$PA" nuevo "'$C1'")" 22023 "primera inversión no lleva" "nuevo con origen"
espera "$(res "$V" "$PA" renovacion)" 22023 "contrato origen" "renovación sin origen"
espera "$(res "$V" "$PA" upgrade)" 22023 "contrato origen" "upgrade sin origen"
espera "$(res "$V" "$PA" renovacion "'$C3'")" P0409 "otro cliente" "origen de OTRO cliente (C3 de PB)"
espera "$(res "$V" "$PA" renovacion "'00000000-0000-4000-8000-000000000001'")" P0002 "no existe" "origen inexistente"
espera "$(res "$V" "$PA" prestamo)" 22023 "categor" "categoría inválida"
E="$(sys "update public.contratos set estado='vencido' where id='$C5'")"; [[ -z "$E" && "$(q "select estado from public.contratos where id='$C5'")" == "vencido" ]] && ok "fixture: C5 pasa a VENCIDO" || rojo "C5 no se pudo vencer: $E"
O="$(res "$V" "$PA" renovacion "'$C5'")"; [[ "$(j "$O" tasa_base)" == "18" ]] && ok "renovación de un contrato VENCIDO → sigue heredando (18%)" || rojo "renovación vencido: $(echo "$O" | cut -c1-160)"
espera "$(res "$V" "$PA" upgrade "'$C5'")" P0409 "solo amplía un contrato activo" "D2: upgrade sobre un contrato VENCIDO"
E="$(sys "update public.contratos set estado='renovado', renovado_a_id='$C2' where id='$C5'")"
if [[ -z "$E" && "$(q "select estado from public.contratos where id='$C5'")" == "renovado" ]]; then
  espera "$(res "$V" "$PA" renovacion "'$C5'")" P0409 "cerrado o renovado" "renovación de un contrato ya RENOVADO"
else
  echo "  ⚠️ (no ensayable en banco: el portal no deja marcar C5 como renovado a mano: ${E:0:120})"
fi

echo "== C) Autoridad = la del alta (decisión B: sin ámbito de cartera) sobre cliente ACTIVO; 42501 uniforme =="
O="$(res "$V" "$PB" nuevo)"; [[ "$(j "$O" tasa_base)" == "$BASE" ]] && ok "V sobre PB (cliente de V2) → ok: la misma autoridad que el alta, sin ámbito de cartera (decisión B)" || rojo "V sobre PB: $(echo "$O" | cut -c1-160)"
O="$(res "$V2" "$PB" nuevo)"; [[ "$(j "$O" tasa_base)" == "$BASE" ]] && ok "V2 sobre su cliente PB → ok" || rojo "V2 sobre PB: $(echo "$O" | cut -c1-160)"
O="$(res "$SUP" "$PA" nuevo)"; [[ "$(j "$O" tasa_base)" == "$BASE" ]] && ok "SUP sobre PA → ok" || rojo "SUP sobre PA: $(echo "$O" | cut -c1-160)"
O="$(res "$SUP2" "$PB" nuevo)"; [[ "$(j "$O" tasa_base)" == "$BASE" ]] && ok "SUP2 sobre PB → ok" || rojo "SUP2 sobre PB: $(echo "$O" | cut -c1-160)"
O="$(res "$G" "$PB" nuevo)"; [[ "$(j "$O" tasa_base)" == "$BASE" ]] && ok "Gerencia sobre PB → ok" || rojo "G sobre PB: $(echo "$O" | cut -c1-160)"
O="$(res "$ADM" "$PA" nuevo)"; [[ "$(j "$O" tasa_base)" == "$BASE" ]] && ok "ADM (admin del Portal, sin ficha CRM) → ok: es_admin pasa puede_registrar_ventas" || rojo "ADM sobre PA: $(echo "$O" | cut -c1-160)"
espera "$(res "$V" "$PC" nuevo)" 42501 "fuera de tu cartera" "cliente INACTIVO (aunque sea de V) → 42501 uniforme (auditor m1)"
espera "$(res "$VI" "$PA" nuevo)" 42501 "fuera de tu cartera" "vendedor INACTIVO"
espera "$(res "$PA" "$PA" nuevo)" 42501 "fuera de tu cartera" "el propio cliente"
espera "$(run_anon "select crm.resolver_tasa_fn('$PA','nuevo',null)")" 42501 "fuera de tu cartera" "sin sesión (uid nulo)"
espera "$(res "$G" "00000000-0000-4000-8000-0000000000aa" nuevo)" 42501 "fuera de tu cartera" "cliente inexistente (Gerencia) → 42501 uniforme, no P0002"

echo "== D) El analista PIDE una tasa superior =="
O="$(sol "$V" "$PA" nuevo null 20000 17)"; S1="$(j "$O" id)"
[[ -n "$S1" && "$(j "$O" estado)" == "pendiente" && "$(j "$O" tasa_base)" == "15" && "$(j "$O" tasa_solicitada)" == "17" ]] && ok "S1: V pide 17% para PA nuevo → pendiente, base 15" || rojo "S1: $(echo "$O" | cut -c1-220)"
[[ "$(j "$O" prioridad_bandeja)" == "True" && "$(j "$O" contratos_previos)" == "3" ]] && ok "S1 lleva prioridad_bandeja (D1) y contratos_previos=3" || rojo "S1 sin prioridad/previos"
[[ "$(q "select (vence_en - solicitada_en) = interval '7 days' from crm.solicitudes_tasa where id='$S1'")" == "t" ]] && ok "S1 vence a los 7 días (política)" || rojo "vence_en distinto de +7d"
HU="$(q "select huella from crm.solicitudes_tasa where id='$S1'")"; [[ -n "$HU" && "$HU" == "$(q "select private.huella_solicitud_tasa('$PA','nuevo',null,null,20000,'PEN','mensual','simple','2026-10-01','2027-10-01')")" ]] && ok "la huella es la del helper único private.huella_solicitud_tasa" || rojo "huella distinta"
espera "$(sol "$V" "$PA" nuevo null 20000 17)" P0409 "solicitud viva" "misma huella otra vez"
espera "$(sol "$V" "$PA" nuevo null 20001 15)" 22023 "superior a la tasa base de 15" "pedir la base (15) → no eleva"
espera "$(sol "$V" "$PA" nuevo null 20001 14)" 22023 "superior a la tasa base" "pedir menos que la base (D4)"
espera "$(sol "$V" "$PA" nuevo null 20001 51)" 22023 "tope técnico" "pedir 51 → tope técnico"
espera "$(sol "$V" "$PA" nuevo null 20001 17 abc)" 22023 "motivo" "motivo corto"
espera "$(sol "$V" "$PA" nuevo null 50 17)" 22023 "capital" "capital fuera de rango"
O="$(sol "$V" "$PB" nuevo null 20000 17)"; [[ -n "$(j "$O" id)" ]] && ok "V pide para PB (cliente de V2) → ok (la autoridad del alta, decisión B)" || rojo "V para PB: $(echo "$O" | cut -c1-160)"
espera "$(sol "$V" "$PC" nuevo null 20000 17)" 42501 "fuera de tu cartera" "pedir para un cliente INACTIVO → 42501"
espera "$(run_anon "select crm.solicitar_tasa_fn('{}'::jsonb)")" 42501 "fuera de tu cartera" "sin sesión con JSON vacío → 42501 (la autoridad va antes que el formato, n2)"
espera "$(res "$VI" "$PA" nuevo)" 42501 "fuera de tu cartera" "vendedor inactivo → 42501 también al pedir"
O="$(sol "$V" "$PA" nuevo null 20008 17.005)"; [[ "$(j "$O" tasa_solicitada)" == "17.01" ]] && ok "17.005 se guarda redondeada a 2 decimales (17.01), la escala de tasa_anual (m5)" || rojo "escala: $(j "$O" tasa_solicitada) — $(echo "$O" | cut -c1-120)"
espera "$(sol "$SUP" "$PA" nuevo null 20000 18)" P0409 "solicitud viva" "D6/m6: el supervisor NO abre otra solicitud sobre la misma intención que la viva de V (S1)"
echo "$(sol "$SUP" "$PA" nuevo null 20000 18)" | grep -q '"propia": false' && ok "…y el DETAIL dice que la viva es de otro (propia=false)" || rojo "sin DETAIL propia=false"
espera "$(sol "$V" "$PA" renovacion "'$C2'" 20000 18)" 22023 "superior a la tasa base de 18" "renovación de C2 pidiendo 18 (= base heredada)"
O="$(sol "$V" "$PA" renovacion "'$C2'" 20000 19)"; S2="$(j "$O" id)"; [[ -n "$S2" && "$(j "$O" tasa_base)" == "18" && "$(j "$O" regla_base)" == "heredada_renovacion" && "$(j "$O" contrato_origen_numero)" == "R1-$RUN-C2" ]] && ok "S2: renovación de C2 pide 19 → base 18 heredada, origen anotado" || rojo "S2: $(echo "$O" | cut -c1-220)"
O="$(sol "$V" "$PA" upgrade "'$C2'" 30000 20)"; S3="$(j "$O" id)"; [[ -n "$S3" && "$(j "$O" regla_base)" == "heredada_upgrade" ]] && ok "S3: upgrade de C2 pide 20 → base 18 heredada_upgrade" || rojo "S3: $(echo "$O" | cut -c1-220)"
O="$(sol "$V" "$PA" nuevo null 20002 17)"; S4="$(j "$O" id)"; [[ -n "$S4" ]] && ok "S4 creada (para los topes inválidos)" || rojo "S4: $(echo "$O" | cut -c1-200)"
O="$(sol "$G" "$PA" nuevo null 20003 17)"; S5="$(j "$O" id)"; [[ -n "$S5" ]] && ok "S5: Gerencia también puede PEDIR (tiene la autoridad del alta)" || rojo "S5: $(echo "$O" | cut -c1-200)"
O="$(sol "$V" "$PA" nuevo null 20004 17)"; S6="$(j "$O" id)"; [[ -n "$S6" ]] && ok "S6 creada (para declinar)" || rojo "S6: $(echo "$O" | cut -c1-200)"
O="$(sol "$V" "$PA" nuevo null 20005 17)"; S7="$(j "$O" id)"; [[ -n "$S7" ]] && ok "S7 creada (para vencer)" || rojo "S7: $(echo "$O" | cut -c1-200)"

echo "== E) Gerencia DECIDE en un clic: aprobar / rechazar / aprobar hasta X (D3, D6) =="
espera "$(dec "$V" "$S1" aprobar)" 42501 "Solo Gerencia" "el analista no resuelve"
espera "$(dec "$SUP" "$S1" aprobar)" 42501 "Solo Gerencia" "el supervisor no resuelve"
O="$(dec "$G" "$S1" aprobar_hasta 16 "'Mercado a 16, no más'")"; [[ "$(j "$O" estado)" == "aprobada_con_tope" && "$(j "$O" tasa_maxima_autorizada)" == "16" && "$(j "$O" resuelta_por)" == "$G" ]] && ok "S1: aprobar hasta 16 → aprobada_con_tope · tope 16 · resuelta por G" || rojo "S1 tope: $(echo "$O" | cut -c1-220)"
O="$(dec "$G" "$S2" aprobar)"; [[ "$(j "$O" estado)" == "aprobada" && "$(j "$O" tasa_maxima_autorizada)" == "19" ]] && ok "S2: aprobar → aprobada · tasa autorizada = pedida (19)" || rojo "S2 aprobar: $(echo "$O" | cut -c1-220)"
O="$(dec "$G" "$S3" rechazar null "'No para upgrade'")"; [[ "$(j "$O" estado)" == "rechazada" && "$(j "$O" motivo_resolucion)" == "No para upgrade" && "$(j "$O" tasa_maxima_autorizada)" == "" ]] && ok "S3: rechazar con motivo → rechazada, sin tope" || rojo "S3 rechazar: $(echo "$O" | cut -c1-220)"
espera "$(dec "$G" "$S1" aprobar)" P0409 "ya no está pendiente" "resolver S1 otra vez"
espera "$(dec "$G" "$S4" aprobar_hasta 15)" 22023 "superar la tasa base de 15" "tope 15 (= base) → D4"
espera "$(dec "$G" "$S4" aprobar_hasta 14)" 22023 "superar la tasa base" "tope 14 (< base)"
espera "$(dec "$G" "$S4" aprobar_hasta 18)" 22023 "no puede superar la tasa pedida de 17" "tope 18 (> pedida)"
espera "$(dec "$G" "$S4" aprobar_hasta)" 22023 "hasta qué tasa" "aprobar_hasta sin tope"
O="$(dec "$G" "$S4" aprobar_hasta 17)"; [[ "$(j "$O" estado)" == "aprobada" && "$(j "$O" tasa_maxima_autorizada)" == "17" ]] && ok "S4: aprobar hasta 17 (= pedida) → aprobada tal cual" || rojo "S4: $(echo "$O" | cut -c1-200)"
espera "$(dec "$G" "$S5" aprobar)" 42501 "no resuelve su propia" "D3: Gerencia NO resuelve la solicitud que ella misma pidió"
espera "$(dec "$G" "$S6" firmar)" 22023 "Decisi" "decisión inválida"
espera "$(dec "$G" "00000000-0000-4000-8000-0000000000bb" aprobar)" P0002 "no encontrada" "solicitud inexistente"
[[ "$(q "select count(*) from public.audit_log where tabla='crm.solicitudes_tasa' and fila_id='$S1' and operacion='UPDATE' and usuario_id='$G'")" -ge 1 ]] && ok "la decisión de G quedó auditada en public.audit_log" || rojo "sin auditoría de la decisión"

echo "== F) El analista RESPONDE al tope: acepta y sigue, o declina (D6) =="
espera "$(resp "$SUP" "$S1" true)" 42501 "fuera de tu ámbito" "el supervisor no responde por V"
espera "$(resp "$G" "$S1" true)" 42501 "fuera de tu ámbito" "Gerencia no acepta en nombre del analista"
O="$(resp "$V" "$S1" true)"; [[ "$(j "$O" estado)" == "aceptada_por_analista" && "$(j "$O" tasa_maxima_autorizada)" == "16" ]] && ok "S1: V acepta el tope 16 → aceptada_por_analista (puede seguir hasta 16)" || rojo "S1 aceptar: $(echo "$O" | cut -c1-200)"
espera "$(resp "$V" "$S1" true)" P0409 "autorización con tope" "responder S1 dos veces"
espera "$(resp "$V" "$S2" true)" P0409 "autorización con tope" "responder a una aprobada SIN tope"
O="$(dec "$G" "$S6" aprobar_hasta 16.004)"; [[ "$(j "$O" estado)" == "aprobada_con_tope" && "$(j "$O" tasa_maxima_autorizada)" == "16" ]] && ok "S6: G aprueba hasta 16.004 → tope 16 (redondeo a 2 decimales, m5)" || rojo "S6 tope: $(echo "$O" | cut -c1-160)"
O="$(resp "$V" "$S6" false "'El cliente no cierra a 16'")"; [[ "$(j "$O" estado)" == "declinada_por_analista" && "$(j "$O" motivo_analista)" == "El cliente no cierra a 16" ]] && ok "S6: V declina con motivo → declinada_por_analista" || rojo "S6 declinar: $(echo "$O" | cut -c1-200)"
O="$(sol "$V" "$PA" nuevo null 20004 17)"; [[ -n "$(j "$O" id)" ]] && ok "tras declinar, V puede pedir de nuevo con la misma huella (la declinada ya no está viva)" || rojo "no pudo volver a pedir: $(echo "$O" | cut -c1-160)"

echo "== G) Vencimiento =="
sys "select set_config('crm.solicitud_tasa_por_puerta','on',true); update crm.solicitudes_tasa set vence_en = now() - interval '1 second' where id='$S7'"
espera "$(dec "$G" "$S7" aprobar)" P0409 "vencida" "resolver una solicitud caducada → P0409 (vencida)"
[[ "$(estado "$S7")" == "pendiente|-|-" ]] && ok "la llamada que lanza no sella (se revierte): la fila aún dice pendiente" || rojo "S7: $(estado "$S7")"
O="$(sol "$V" "$PA" nuevo null 20007 17)"; S8="$(j "$O" id)"; [[ -n "$S8" ]] || rojo "no se pudo crear la solicitud que dispara el vencimiento"
[[ "$(estado "$S7")" == "vencida|-|-" ]] && ok "la siguiente puerta que commitea (pedir = barrido global) sella S7 como vencida" || rojo "S7 tras la siguiente llamada: $(estado "$S7")"
sys "select set_config('crm.solicitud_tasa_por_puerta','on',true); update crm.solicitudes_tasa set vence_en = now() - interval '1 second' where id='$S8'"
O="$(sol "$V" "$PA" nuevo null 20009 17)"; S9="$(j "$O" id)"; [[ -n "$S9" ]] || rojo "S9 no se creó"
[[ "$(estado "$S8")" == "vencida|-|-" ]] && ok "pedir (S9) barrió también S8 (barrido global al pedir)" || rojo "S8: $(estado "$S8")"
[[ "$(q "select count(*) from public.audit_log where tabla='crm.solicitudes_tasa' and fila_id='$S8' and operacion='UPDATE' and usuario_id='$V'")" -ge 1 ]] && ok "m4 (documentado): el sello queda atribuido en audit_log a quien entró (V)" || rojo "sin auditoría del sello"

echo "== H) RLS y escrituras directas =="
[[ "$(cnt_as "$V" "select count(*) from crm.solicitudes_tasa where id in ('$S1','$S5')")" == "1" ]] && ok "V ve la suya (S1) y NO la de Gerencia (S5)" || rojo "V ve: $(cnt_as "$V" "select count(*) from crm.solicitudes_tasa where id in ('$S1','$S5')")"
[[ "$(cnt_as "$SUP" "select count(*) from crm.solicitudes_tasa where id='$S1'")" == "1" ]] && ok "SUP ve la de su analista V" || rojo "SUP no ve S1"
[[ "$(cnt_as "$V2" "select count(*) from crm.solicitudes_tasa where id='$S1'")" == "0" ]] && ok "V2 no ve la de V" || rojo "V2 ve S1"
[[ "$(cnt_as "$G" "select count(*) from crm.solicitudes_tasa where id in ('$S1','$S2','$S3','$S5')")" == "4" ]] && ok "Gerencia ve todas" || rojo "G no ve todas"
[[ "$(cnt_anon "select count(*) from crm.solicitudes_tasa")" == "0" ]] && ok "sin sesión: 0 filas" || rojo "anon ve filas"
O="$(sol "$ADM" "$PA" nuevo null 20010 17)"; SA="$(j "$O" id)"; [[ -n "$SA" ]] && ok "SA: el admin del Portal (sin ficha CRM) pide" || rojo "SA: $(echo "$O" | cut -c1-160)"
[[ -n "$SA" && "$(cnt_as "$G" "select count(*) from crm.solicitudes_tasa where id='$SA'")" == "1" ]] && ok "M1: Gerencia VE la solicitud del admin del Portal (rama gerencia de la policy)" || rojo "M1: Gerencia no ve SA"
[[ -n "$SA" && "$(cnt_as "$V" "select count(*) from crm.solicitudes_tasa where id='$SA'")" == "0" && "$(cnt_as "$SUP" "select count(*) from crm.solicitudes_tasa where id='$SA'")" == "0" ]] && ok "V y SUP no ven la del admin" || rojo "V/SUP ven SA"
[[ -n "$SA" && "$(cnt_as "$ADM" "select count(*) from crm.solicitudes_tasa where id='$SA'")" == "1" ]] && ok "el admin ve la suya" || rojo "ADM no ve SA"
espera "$(run_as "$V" "insert into crm.solicitudes_tasa (politica_id,cliente_id,categoria,capital,moneda,modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,huella,tasa_base,regla_base,tasa_solicitada,motivo,solicitada_por,vence_en) select id,'$PA','nuevo',1000,'PEN','mensual','simple','2026-10-01','2027-10-01','x',15,'primera_inversion',17,'directo directo','$V',now()+interval '1 day' from crm.politica_rentabilidad limit 1")" 42501 "permission denied|denegado" "INSERT directo como V"
espera "$(run_as "$V" "update crm.solicitudes_tasa set tasa_solicitada=30 where id='$S1'")" 42501 "permission denied|denegado" "UPDATE directo como V"
espera "$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update crm.solicitudes_tasa set tasa_solicitada=30 where id='$S1'" 2>&1)" P0409 "solo cambia por sus puertas" "UPDATE como postgres SIN el GUC de la puerta"
espera "$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "delete from crm.solicitudes_tasa where id='$S1'" 2>&1)" P0409 "no se borra" "DELETE como postgres"
espera "$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update crm.ledger_rentabilidad set tasa_final=1 where origen='backfill_legacy'" 2>&1)" P0409 "append-only" "UPDATE del ledger como postgres"
espera "$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "delete from crm.ledger_rentabilidad where origen='backfill_legacy'" 2>&1)" P0409 "append-only" "DELETE del ledger como postgres"
espera "$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update crm.politica_rentabilidad set tasa_base_nueva=1 where version=1" 2>&1)" 55000 "inmutable" "UPDATE de la política v1"
espera "$(run_as "$V" "insert into crm.politica_rentabilidad (version,vigente_desde,tasa_base_nueva) values (999,now(),1)")" 42501 "permission denied|denegado" "INSERT directo en la política como V"
espera "$(run_as "$V" "select private.resolver_tasa('$PA','nuevo',null)")" 42501 "permission denied|denegado" "el núcleo private.resolver_tasa NO es llamable por la API"
TOT="$(q "select count(*) from crm.ledger_rentabilidad where origen='backfill_legacy'")"
[[ "$(cnt_as "$G" "select count(*) from crm.ledger_rentabilidad where origen='backfill_legacy'")" == "$TOT" ]] && ok "Gerencia lee todo el ledger ($TOT filas legacy)" || rojo "G no lee todo el ledger"
ESP_V="$(q "select count(*) from crm.ledger_rentabilidad l join public.perfiles p on p.id=l.cliente_id where l.origen='backfill_legacy' and p.rol='cliente' and (p.asesor_perfil_id='$V' or (p.asesor_perfil_id is null and p.creado_por='$V'))")"
[[ "$(cnt_as "$V" "select count(*) from crm.ledger_rentabilidad where origen='backfill_legacy'")" == "$ESP_V" ]] && ok "V lee solo los contratos de su cartera ($ESP_V filas)" || rojo "V lee $(cnt_as "$V" "select count(*) from crm.ledger_rentabilidad where origen='backfill_legacy'") ≠ $ESP_V"
[[ "$(cnt_anon "select count(*) from crm.ledger_rentabilidad")" == "0" ]] && ok "sin sesión: 0 filas del ledger" || rojo "anon lee ledger"

echo "== I) Gerencia PUBLICA la política (versionada, inmutable) =="
VCUR="$(q "select max(version) from crm.politica_rentabilidad")"
espera "$(run_as "$V" "select crm.publicar_politica_rentabilidad_fn($VCUR, '{\"tasa_base_nueva\":16,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\"}'::jsonb)")" 42501 "Solo Gerencia" "el analista no publica"
O="$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($VCUR, '{\"tasa_base_nueva\":16,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\",\"nota\":\"ensayo r$RUN\"}'::jsonb)")"
[[ "$(j "$O" version)" == "$((VCUR+1))" && "$(j "$O" tasa_base_nueva)" == "16" && "$(j "$O" publicada_por)" == "$G" ]] && ok "G publica v$((VCUR+1)) al 16%" || rojo "publicar: $(echo "$O" | cut -c1-200)"
O="$(res "$V" "$PA" nuevo)"; [[ "$(j "$O" tasa_base)" == "16" && "$(j "$O" politica.version)" == "$((VCUR+1))" ]] && ok "el núcleo sigue a la política: nuevo → 16%" || rojo "núcleo no siguió la política: $(echo "$O" | cut -c1-160)"
espera "$(sol "$V" "$PA" nuevo null 20006 16)" 22023 "superior a la tasa base de 16" "pedir 16 con la política al 16 → no eleva"
espera "$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($VCUR, '{\"tasa_base_nueva\":15,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\"}'::jsonb)")" P0409 "Conflicto de versi" "publicar con la versión vieja → P0409 (hotfix: 40001 colgaba en PostgREST)"
# El modo enforcement lo RECHAZA R1 (0A000)… hasta que R4 lo construye: entonces se admite y hay que volver a
# observacion para no dejar el banco con el candado encendido.
if [[ "$(q "select (to_regprocedure('private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)') is not null)")" == "t" ]]; then
  OUT_ENF="$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($((VCUR+1)), '{\"tasa_base_nueva\":15,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"enforcement\"}'::jsonb)")"
  if echo "$OUT_ENF" | grep -q '"modo": "enforcement"'; then ok "con R4 instalada, Gerencia SÍ puede publicar enforcement"; else rojo "con R4 instalada, publicar enforcement falló: $(echo "$OUT_ENF" | tr '\n' ' ' | cut -c1-200)"; fi
  VCUR=$((VCUR+1))
  OUT_OBS="$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($((VCUR+1)), '{\"tasa_base_nueva\":15,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\"}'::jsonb)")"
  if echo "$OUT_OBS" | grep -q '"modo": "observacion"'; then ok "y volver a observacion apaga el candado sin migración"; else rojo "no se pudo volver a observacion: $(echo "$OUT_OBS" | tr '\n' ' ' | cut -c1-200)"; fi
  VCUR=$((VCUR+1))
else
  espera "$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($((VCUR+1)), '{\"tasa_base_nueva\":15,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"enforcement\"}'::jsonb)")" 0A000 "enforcement" "modo enforcement en R1 → 0A000"
fi
espera "$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($((VCUR+1)), '{\"tasa_base_nueva\":15,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\",\"extra\":1}'::jsonb)")" 22023 "Formato" "clave desconocida → 22023"
espera "$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($((VCUR+1)), '{\"tasa_base_nueva\":20,\"tope_tecnico\":18,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\"}'::jsonb)")" 22023 "fuera de rango" "tope < base → 22023"
O="$(run_as "$G" "select crm.publicar_politica_rentabilidad_fn($((VCUR+1)), '{\"tasa_base_nueva\":15,\"tope_tecnico\":50,\"vigencia_solicitud_dias\":7,\"modo\":\"observacion\",\"nota\":\"vuelta al 15 r$RUN\"}'::jsonb)")"
[[ "$(j "$O" version)" == "$((VCUR+2))" ]] && ok "G vuelve al 15% en v$((VCUR+2)) (la v$((VCUR+1)) queda en la historia)" || rojo "vuelta al 15: $(echo "$O" | cut -c1-160)"
O="$(res "$V" "$PA" nuevo)"; [[ "$(j "$O" tasa_base)" == "15" ]] && ok "nuevo → 15% otra vez" || rojo "núcleo tras volver: $(j "$O" tasa_base)"
[[ "$(q "select count(*) from public.audit_log where tabla='crm.politica_rentabilidad' and operacion='INSERT' and usuario_id='$G'")" -ge 2 ]] && ok "las publicaciones de G quedaron auditadas" || rojo "sin auditoría de la política"

echo "== J) NADA CAMBIÓ EN LAS ALTAS =="
O="$(alta "$V" "$PA" "R1-$RUN-C4" 12)"; C4="$(j "$O" id)"
[[ -n "$C4" && "$(q "select tasa_anual from public.contratos where id='$C4'")" == "12.00" ]] && ok "un alta al 12% sigue entrando tal cual (R1 no impone ni observa todavía)" || rojo "alta al 12%: $(echo "$O" | cut -c1-200) tasa=$(q "select tasa_anual from public.contratos where id='$C4'")"
if [[ "$R2" == "t" ]]; then
  [[ -n "$LEDGER_ANTES" && "$(q "select count(*) from crm.ledger_rentabilidad")" == "$((LEDGER_ANTES+1))" ]] && ok "con R2, el ledger creció exactamente en 1 (la observación del alta al 12%)" || rojo "el ledger creció distinto de +1: $(q "select count(*) from crm.ledger_rentabilidad") vs $LEDGER_ANTES"
else
  [[ -n "$LEDGER_ANTES" && "$(q "select count(*) from crm.ledger_rentabilidad")" == "$LEDGER_ANTES" ]] && ok "el ledger no creció con las altas de esta corrida ($LEDGER_ANTES filas)" || rojo "el ledger creció"
fi
[[ "$(gates)" == "$GATES_INI" ]] && ok "las 5 puertas de escritura siguen byte a byte (como al empezar)" || rojo "puertas cambiadas: $(gates)"

echo
echo "== RESULTADO RUN=$RUN: $VERDE verdes, $ROJO rojos =="
exit $(( ROJO > 0 ))
