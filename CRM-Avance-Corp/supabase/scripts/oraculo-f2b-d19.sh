#!/usr/bin/env bash
# ORÁCULO F2.b [D-19] — toda escritura lee la bandera bajo el candado del encendido — SOLO en el BANCO.
# Lo que tiene que probar: (1) apagada, las escrituras hacen lo de siempre; (2) con una escritura EN VUELO —RPC o
# UPDATE DIRECTO del front— encender y apagar ESPERAN a que termine (que es lo que el drenaje no garantizaba);
# (3) READ COMMITTED es obligatorio; (4) ya no queda ninguna escritora ni disparador sin candado. La POSICIÓN del
# candado dentro del ayudante la comprueba la suite por texto (a esta granularidad un candado tardío es casi
# indistinguible en conducta, y la defensa real es que el ayudante sea UN SOLO SITIO revisable).
# Ojo con los documentos: la siembra F3 usa 7RUN1, así que aquí van con prefijo 6.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d19.sh. Sin D-19 = corrida MUTANTE (E1..E4 en rojo).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin; set timezone='America/Lima'; set local statement_timeout='8s'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
run_rr() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -c "begin isolation level repeatable read; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; sleep 3; done; rojo "bandera: no se pudo poner en $1"; }
# Un SOLO intento, sin reintento ni sleep: si esto tarda, es que el candado lo hizo esperar (auditor D-19 M2).
flag1() { psql "$PG" -q -v ON_ERROR_STOP=1 -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1 || { rojo "flag1: el UPDATE de la bandera falló (no vale como espera)"; return 1; }; }
uuid() { q "select gen_random_uuid()"; }
# Banco COMPARTIDO: otra sesión puede mover la bandera en mitad de una medida.
estado() { local e; e="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"; [[ "$e" == "$1" ]] || { echo "  ⚠️ la bandera se había movido (otra sesión): se repone"; flag "$( [[ "$1" == "t" ]] && echo true || echo false )"; }; }
ms()   { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D19 $3 r$RUN','9${RUN}$2',null,1000,'landing','nuevo','$V','$V')"; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D19 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
retener_as() { LOCKF="$S/d19-lock-$RUN-$RANDOM.out"; ( psql "$PG" -qAt -v ON_ERROR_STOP=1 > "$LOCKF" 2>&1 <<EOF
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
$2;
\echo LOCK-OK
select pg_sleep($3);
commit;
EOF
echo "exit=$?" >> "$LOCKF" ) & BG=$!; local i; for i in $(seq 1 150); do grep -q "LOCK-OK" "$LOCKF" 2>/dev/null && return 0; grep -q "ERROR" "$LOCKF" 2>/dev/null && { rojo "retener_as: $(head -c 200 "$LOCKF")"; return 1; }; sleep 0.1; done; rojo "retener_as: sin LOCK-OK en 15 s"; return 1; }
soltado() { wait $BG 2>/dev/null; grep -q "exit=0" "$LOCKF" && return 0; rojo "la sesión que retenía falló: $(grep -v LOCK-OK "$LOCKF" | head -c 200)"; return 1; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
INST="$(q "select (to_regprocedure('private.resolver_en_puertas_bajo_candado()') is not null)::int")"
[[ "$INST" == "1" ]] && echo "  D-19 instalada (todo debe salir VERDE)" || echo "  ⚠️ D-19 NO instalada: corrida MUTANTE (E1..E4 en rojo)"
flag false

echo "== (1) Apagada, las escrituras hacen lo de siempre =="
estado f
L1="$(uuid)"; lead_de "$L1" 41 A; AU1="$(uuid)"; D1="6${RUN}1"; sim_perfil "$AU1" "$D1" "a$RUN@x.pe"
R="$(run_as "$V" "select crm.convertir_lead('$L1','$AU1')")"
[[ "$(q "select etapa from crm.leads where id='$L1'")" == "convertido" ]] && ok "[P1] con la bandera APAGADA la conversión hace exactamente lo de siempre" || rojo "P1: la conversión apagada cambió · $(echo "$R" | head -c 160)"

echo "== (2) Con una escritura EN VUELO, encender y apagar ESPERAN =="
estado f
L2="$(uuid)"; lead_de "$L2" 42 B; AU2="$(uuid)"; D2="6${RUN}2"; sim_perfil "$AU2" "$D2" "b$RUN@x.pe"
retener_as "$V" "select crm.convertir_lead('$L2','$AU2')" 4 && {
  T0="$(ms)"; flag1 true; T1="$(ms)"
  (( T1 - T0 >= 2500 )) && ok "[E1] con una CONVERSIÓN en vuelo (entró apagada), ENCENDER espera a que termine ($((T1-T0)) ms)" || rojo "E1: el encendido no esperó a la conversión ($((T1-T0)) ms)"
  soltado; }
estado t
L3="$(uuid)"; lead_de "$L3" 43 C; AU3="$(uuid)"; D3="6${RUN}3"; sim_perfil "$AU3" "$D3" "c$RUN@x.pe"
retener_as "$V" "select crm.convertir_lead('$L3','$AU3')" 4 && {
  T0="$(ms)"; flag1 false; T1="$(ms)"
  (( T1 - T0 >= 2500 )) && ok "[E2] con una CONVERSIÓN en vuelo (entró encendida), APAGAR espera ($((T1-T0)) ms)" || rojo "E2: el apagado no esperó ($((T1-T0)) ms)"
  soltado; }
# El offboarding es la otra puerta que escribe y leía la bandera suelta.
estado f
VEQ="$(q "select actualizado_en from crm.equipo where perfil_id='$SUP'")"
retener_as "$G" "select crm.fijar_membresia_activa_fn('$SUP', true, null, '$VEQ'::timestamptz, gen_random_uuid())" 4 && {
  T0="$(ms)"; flag1 true; T1="$(ms)"
  (( T1 - T0 >= 2500 )) && ok "[E3] con un OFFBOARDING en vuelo, ENCENDER espera ($((T1-T0)) ms)" || rojo "E3: el encendido no esperó al offboarding ($((T1-T0)) ms)"
  soltado; }
flag false

# E-DIRECTO — el caso que faltaba y que destapó el auditor (#A1): el front NO siempre pasa por una RPC. Un
# `update crm.leads set etapa=...` por PostgREST dispara validadores BEFORE (disponibilidad, herencia de veto,
# puerta de «no contactar») que leían la bandera SIN candado: el encendido no los esperaba y podían confirmar
# habiendo juzgado con el valor viejo. Con D-19 esos disparadores toman el compartido, así que el encendido espera.
estado f
LD="$(uuid)"; lead_de "$LD" 45 E
retener_as "$V" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LD'" 4 && {
  T0="$(ms)"; flag1 true; T1="$(ms)"
  (( T1 - T0 >= 2500 )) && ok "[E5] con una ESCRITURA DIRECTA a crm.leads en vuelo (el camino del front, sin RPC), ENCENDER espera ($((T1-T0)) ms)" || rojo "E5: el encendido NO esperó a la escritura directa ($((T1-T0)) ms): los disparadores de crm.leads siguen leyendo la bandera sin candado"
  soltado; }
[[ "$(q "select etapa from crm.leads where id='$LD'")" == "descartado" ]] && ok "[E5] y la escritura directa terminó bien (apagada hace lo de siempre)" || rojo "E5: la escritura directa no cuajó"
flag1 false

echo "== (3) READ COMMITTED obligatorio (también apagada) =="
estado f
L4="$(uuid)"; lead_de "$L4" 44 D; AU4="$(uuid)"; D4="6${RUN}4"; sim_perfil "$AU4" "$D4" "d$RUN@x.pe"
R="$(run_rr "$V" "select crm.convertir_lead('$L4','$AU4')")"
echo "$R" | grep -q "0A000\|READ COMMITTED" && ok "[E4] la conversión bajo REPEATABLE READ se niega con 0A000 en vez de decidir con una foto vieja" || rojo "E4: no exigió READ COMMITTED · $(echo "$R" | head -c 160)"
[[ "$(q "select etapa from crm.leads where id='$L4'")" == "nuevo" ]] && ok "[E4] y no dejó nada escrito" || rojo "E4: escribió pese al 0A000"

echo "== (4) El censo y los permisos =="
SIN="$(q "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private','public') and strpos(p.prosrc,'resolver_en_puertas')>0 and strpos(p.prosrc,'crm_flag_resolver_en_puertas')=0 and strpos(p.prosrc,'resolver_en_puertas_bajo_candado')=0")"
[[ "$SIN" == "0" ]] && ok "[C1] no queda NINGUNA función que lea la bandera sin su candado compartido (ni escritora, ni disparador, ni consulta)" || rojo "C1: quedan $SIN funciones leyendo la bandera sin candado"
[[ "$(q "select (has_function_privilege('authenticated','private.resolver_en_puertas_bajo_candado()','EXECUTE') or has_function_privilege('anon','private.resolver_en_puertas_bajo_candado()','EXECUTE'))::int")" == "0" ]] && ok "[C2] el ayudante no es llamable por authenticated ni anon (lo usan las DEFINER de postgres)" || rojo "C2: el ayudante quedó expuesto a la API"
[[ "$(q "select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid='private.resolver_en_puertas_bajo_candado()'::regprocedure and a.grantee=0")" == "0" ]] && ok "[C3] PUBLIC no tiene nada sobre el ayudante" || rojo "C3: PUBLIC puede ejecutar el ayudante"
[[ "$(q "select (has_function_privilege('authenticated','public.crear_contrato(jsonb,jsonb)','EXECUTE') and has_function_privilege('service_role','public.crear_contrato(jsonb,jsonb)','EXECUTE'))::int")" == "1" ]] && ok "[C4] public.crear_contrato conserva sus permisos (authenticated y service_role): el Portal sigue dando de alta" || rojo "C4: cambiaron los permisos de public.crear_contrato"

echo "== Limpieza =="
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); update crm.leads set activo=false where nombre_completo like 'D19 % r$RUN' and activo; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-19: VERDE — apagada no cambia nada; con una escritura en vuelo el encendido y el apagado esperan; READ COMMITTED obligatorio; ninguna función lee la bandera sin su candado."; else echo "ORÁCULO F2.b D-19: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
