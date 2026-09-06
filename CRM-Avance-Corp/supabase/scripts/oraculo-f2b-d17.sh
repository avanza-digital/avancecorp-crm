#!/usr/bin/env bash
# ORÁCULO F2.b [D-17] — las tres puertas que faltaban (marcar/levantar «No insistir» y la conversión en cooperativa)
# leen la bandera bajo el candado del encendido — SOLO en el BANCO. Presupone b1..b5, D-2/D-3, D-13, D-5 y D-15.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d17.sh   (lee $S/banco-pooler.txt). Sin D-17 = corrida MUTANTE: S1..S3 en rojo.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; sleep 3; done; rojo "bandera: no se pudo poner en $1"; }
uuid() { q "select gen_random_uuid()"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
ms()   { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D17 $3 r$RUN','9${RUN}$2',${4:-null},1000,'landing','nuevo','$V','$V')"; }
marcar()   { run_as "${2:-$V}" "select crm.marcar_no_contactar('$1','ensayo d17')"; }
levantar() { run_as "$G" "select crm.levantar_no_contactar('$1','ensayo d17 levantar')"; }
coop()     { run_as "$V" "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$2','D17 PERSONA','TRX-D17-${RUN}-$3')"; }
resolver() { q "select private.inversionista_resolver('DNI','$1',true,'ensayo-d17')"; }
# retiene una transacción CON SESIÓN N segundos tras ejecutar la sentencia
retener_as() { LOCKF="$S/d17-lock-$RUN-$RANDOM.out"; ( psql "$PG" -qAt -v ON_ERROR_STOP=1 > "$LOCKF" 2>&1 <<EOF
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
$2;
\echo LOCK-OK
select pg_sleep($3);
commit;
EOF
echo "exit=$?" >> "$LOCKF" ) & BG=$!; local i; for i in $(seq 1 100); do grep -q "LOCK-OK" "$LOCKF" 2>/dev/null && return 0; grep -q "ERROR" "$LOCKF" 2>/dev/null && { rojo "retener_as: $(head -c 200 "$LOCKF")"; return 1; }; sleep 0.1; done; rojo "retener_as: sin LOCK-OK en 10 s"; return 1; }
soltado() { wait $BG 2>/dev/null; grep -q "exit=0" "$LOCKF" && return 0; rojo "la sesión que retenía falló: $(grep -v LOCK-OK "$LOCKF" | head -c 200)"; return 1; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
INSTALADA="$(q "select (select count(*) from pg_proc p where p.oid='crm.marcar_no_contactar(uuid,text)'::regprocedure and strpos(p.prosrc,'F2.b [D-17]')>0)")"
[[ "$INSTALADA" == "1" ]] && echo "  D-17 instalada (todo debe salir VERDE)" || echo "  ⚠️ D-17 NO instalada: corrida MUTANTE (S1..S3 en rojo)"
[[ "$(q "select count(*) from pg_trigger where tgrelid='crm.multiempresa_flags'::regclass and tgname='trg_multiempresa_flags_00_serializa_puertas'")" == "1" ]] && ok "premisa: el trigger que serializa el cambio de bandera (D-5) está montado" || rojo "falta D-5"
flag false

echo "== (1) Paridad con la bandera APAGADA: las tres puertas hacen lo de siempre =="
LA="$(uuid)"; lead_de "$LA" 11 A
R="$(marcar "$LA")"; [[ "$(q "select no_contactar from crm.leads where id='$LA'")" == "t" ]] && ok "[P1] OFF: marcar «No insistir» veta el lead (como hoy)" || rojo "P1: $(echo "$R" | head -c 200)"
R="$(levantar "$LA")"; [[ "$(q "select no_contactar from crm.leads where id='$LA'")" == "f" ]] && ok "[P2] OFF: Gerencia levanta el veto del lead (como hoy)" || rojo "P2: $(echo "$R" | head -c 200)"
LB="$(uuid)"; lead_de "$LB" 12 B; DB="7${RUN}1"
R="$(coop "$LB" "$DB" 1)"; [[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LB'")" == "convertido -" ]] && ok "[P3] OFF: la conversión en cooperativa cierra el lead SIN identidad (como hoy)" || rojo "P3: $(echo "$R" | head -c 220)"
R="$(marcar "$LA" "$G")"; [[ "$(q "select no_contactar from crm.leads where id='$LA'")" == "t" ]] && ok "[P4] OFF: Gerencia también marca" || rojo "P4: $(echo "$R" | head -c 160)"
R="$(levantar "$LA")" >/dev/null

echo "== (2) Con la bandera ENCENDIDA: el veto y la coop siguen alcanzando a la PERSONA =="
flag true
DC="7${RUN}2"; IC="$(resolver "$DC")"; LC="$(uuid)"; flag false; lead_de "$LC" 13 C "'$DC'"; flag true
R="$(marcar "$LC")"; [[ "$(q "select no_contactar from crm.inversionistas where id='$IC'")" == "t" ]] && ok "[T1] ON: marcar veta a la PERSONA, no solo al lead" || rojo "T1: $(echo "$R" | head -c 220) · persona=$(q "select no_contactar from crm.inversionistas where id='$IC'")"
R="$(levantar "$LC")"; [[ "$(q "select no_contactar from crm.inversionistas where id='$IC'")" == "f" ]] && ok "[T2] ON: levantar lo quita de la PERSONA" || rojo "T2: $(echo "$R" | head -c 220)"
LD="$(uuid)"; lead_de "$LD" 14 D; DD="7${RUN}3"
R="$(coop "$LD" "$DD" 3)"; ID="$(q "select private.inversionista_por_documento('DNI','$DD')")"; [[ -n "$ID" && "$(q "select inversionista_id from crm.leads where id='$LD'")" == "$ID" ]] && ok "[T3] ON: la conversión en cooperativa RECONOCE a la persona y enlaza el lead" || rojo "T3: $(echo "$R" | head -c 220)"

echo "== (3) El cambio de bandera espera a cada puerta en vuelo (Codex 3.ª ronda) =="
flag false
LE="$(uuid)"; lead_de "$LE" 15 E
retener_as "$V" "select crm.marcar_no_contactar('$LE','ensayo serializacion')" 6 && { T0="$(ms)"; flag true; T1="$(ms)"; (( T1 - T0 >= 4500 )) && ok "[S1] con «marcar No insistir» en vuelo (entró apagada), ENCENDER espera a que termine ($((T1-T0)) ms)" || rojo "S1: el encendido no esperó ($((T1-T0)) ms)"; soltado; }
[[ "$(q "select no_contactar from crm.leads where id='$LE'")" == "t" && "$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")" == "t" ]] && ok "[S1] la llamada terminó apagada (vetó el lead) y la bandera quedó encendida después" || rojo "S1 foto: lead=$(q "select no_contactar from crm.leads where id='$LE'") flag=$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"
retener_as "$G" "select crm.levantar_no_contactar('$LE','ensayo serializacion levantar')" 6 && { T0="$(ms)"; flag false; T1="$(ms)"; (( T1 - T0 >= 4500 )) && ok "[S2] con «levantar» en vuelo (entró encendida), APAGAR espera ($((T1-T0)) ms)" || rojo "S2: el apagado no esperó ($((T1-T0)) ms)"; soltado; }
LF="$(uuid)"; lead_de "$LF" 16 F; DF="7${RUN}4"
retener_as "$V" "select crm.convertir_lead_externo('$LF','qorilazo',1000,'PEN','DNI','$DF','D17 SERIAL','TRX-D17-${RUN}-9')" 6 && { T0="$(ms)"; flag true; T1="$(ms)"; (( T1 - T0 >= 4500 )) && ok "[S3] con la conversión en cooperativa en vuelo, ENCENDER espera ($((T1-T0)) ms)" || rojo "S3: el encendido no esperó ($((T1-T0)) ms)"; soltado; }
[[ "$(q "select etapa||' '||coalesce(inversionista_id::text,'-') from crm.leads where id='$LF'")" == "convertido -" ]] && ok "[S3] la conversión que entró apagada terminó apagada (cerrada, sin identidad)" || rojo "S3 foto: $(q "select etapa, inversionista_id from crm.leads where id='$LF'")"
flag false

echo "== (4) READ COMMITTED obligatorio en las tres =="
LG="$(uuid)"; lead_de "$LG" 17 G
for par in "marcar_no_contactar('$LG','x')|marcar" "levantar_no_contactar('$LG','motivo largo')|levantar" "convertir_lead_externo('$LG','qorilazo',1000,'PEN','DNI','7${RUN}5','D17 RR','TRX-D17-${RUN}-8')|coop"; do
  llamada="${par%%|*}"; nombre="${par##*|}"
  R="$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin isolation level repeatable read; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$G\",\"role\":\"authenticated\"}', true); select crm.$llamada; rollback;" 2>&1)"
  echo "$R" | grep -q "0A000" && ok "[RC] $nombre bajo REPEATABLE READ → 0A000 (también apagada)" || rojo "RC $nombre: $(echo "$R" | head -c 180)"
done

echo "== Limpieza =="
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); update crm.leads set activo=false where nombre_completo like 'D17 % r$RUN' and activo; commit;" >/dev/null 2>&1
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-17: VERDE — apagada, las tres puertas hacen lo de siempre; encendida, veto y coop alcanzan a la persona; encender y apagar esperan a cada puerta en vuelo; READ COMMITTED obligatorio."; else echo "ORÁCULO F2.b D-17: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
