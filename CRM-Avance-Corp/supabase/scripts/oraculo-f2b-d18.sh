#!/usr/bin/env bash
# ORÁCULO F2.b [D-18] — las dos deudas del bloque 2 — SOLO en el BANCO.
#  (a) la conversión Avance no abre tramo con un analista que se está dando de baja (interlock de jerarquía);
#  (b) la fusión que hereda el veto cancela también las tareas de CLIENTE.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-d18.sh. Sin D-18 = corrida MUTANTE: J1/J1b/J4/J5 y N6 en ROJO. J2 y J3 salen
# VERDES también en el mutante: son guardas de REGRESIÓN (que el camino feliz siga abriendo tramo, y que un asesor ya
# inactivo al empezar no lo reciba), no prueba de lo que D-18 añade (auditor D-18 #10).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
ROJO=0; AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
# statement_timeout explícito: PostgREST lo trae del rol y `set local role` NO aplica los GUC de login, así que sin
# esto el oráculo sería ciego a una espera que en producción moriría por timeout (auditor D-18 #7c).
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local statement_timeout='8s'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR" ; }
flag() { local i; for i in 1 2 3 4 5; do psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null 2>&1; [[ "$(psql "$PG" -qtA -c "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'" 2>/dev/null)" == "$( [[ "$1" == "true" ]] && echo t || echo f )" ]] && return 0; sleep 3; done; rojo "bandera: no se pudo poner en $1"; }
uuid() { q "select gen_random_uuid()"; }
# El banco es COMPARTIDO: otra sesión puede mover la bandera en mitad de una medida y el oráculo mediría otra cosa.
on_ok() { [[ "$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")" == "t" ]] || { echo "  ⚠️ la bandera se había movido (otra sesión): se vuelve a encender"; flag true; }; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
v=d.get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
ms()   { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
lead_de() { sys "insert into crm.leads (id,nombre_completo,telefono,dni,monto_estimado,origen,etapa,creado_por,vendedor_id) values ('$1','D18 $3 r$RUN','9${RUN}$2',${4:-null},1000,'landing','nuevo','$V','$V')"; }
sim_perfil(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D18 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$V',true); commit;" 2>&1 | grep -E "ERROR"; }
sim_perfil_asesor(){ psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$1') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo) values ('$1','D18 CLIENTE $2 r$RUN','cliente','DNI','$2','$3','$4',true); commit;" 2>&1 | grep -E "ERROR"; }
resolver() { q "select private.inversionista_resolver('DNI','$1',true,'ensayo-d18')"; }
convertir() { run_as "$V" "select crm.convertir_lead('$1','$2')"; }
retener_sys() { LOCKF="$S/d18-lock-$RUN-$RANDOM.out"; ( psql "$PG" -qAt -v ON_ERROR_STOP=1 > "$LOCKF" 2>&1 <<EOF
begin;
$1;
\echo LOCK-OK
select pg_sleep($2);
commit;
EOF
echo "exit=$?" >> "$LOCKF" ) & BG=$!; local i; for i in $(seq 1 100); do grep -q "LOCK-OK" "$LOCKF" 2>/dev/null && return 0; grep -q "ERROR" "$LOCKF" 2>/dev/null && { rojo "retener: $(head -c 200 "$LOCKF")"; return 1; }; sleep 0.1; done; rojo "retener: sin LOCK-OK"; return 1; }
retener_as() { LOCKF="$S/d18-lock-$RUN-$RANDOM.out"; ( psql "$PG" -qAt -v ON_ERROR_STOP=1 > "$LOCKF" 2>&1 <<EOF
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
$2;
\echo LOCK-OK
select pg_sleep($3);
commit;
EOF
echo "exit=$?" >> "$LOCKF" ) & BG=$!; local i; for i in $(seq 1 100); do grep -q "LOCK-OK" "$LOCKF" 2>/dev/null && return 0; grep -q "ERROR" "$LOCKF" 2>/dev/null && { rojo "retener_as: $(head -c 200 "$LOCKF")"; return 1; }; sleep 0.1; done; rojo "retener_as: sin LOCK-OK en 10 s"; return 1; }
soltado() { wait $BG 2>/dev/null; grep -q "exit=0" "$LOCKF" && return 0; rojo "la sesión que retenía falló"; return 1; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
INST="$(q "select (select count(*) from pg_proc p where p.oid='crm.convertir_lead(uuid,uuid)'::regprocedure and strpos(p.prosrc,'F2.b [D-18]')>0)")"
[[ "$INST" == "1" ]] && echo "  D-18 instalada (todo debe salir VERDE)" || echo "  ⚠️ D-18 NO instalada: corrida MUTANTE (J1/J2/N6 en rojo)"
flag true

echo "== (a) La conversión y la baja del analista comparten el interlock de jerarquía =="
on_ok
LJ="$(uuid)"; lead_de "$LJ" 31 J; AUJ="$(uuid)"; DJ="8${RUN}1"; sim_perfil "$AUJ" "$DJ" "j$RUN@x.pe"
# el interlock EXCLUSIVO retenido por «la baja» (lo mismo que toma fijar_membresia_activa_fn) frena la conversión
retener_sys "select pg_advisory_xact_lock(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0))" 3 && {
  T0="$(ms)"; R="$(convertir "$LJ" "$AUJ")"; T1="$(ms)"
  (( T1 - T0 >= 2000 )) && ok "[J1] con la jerarquía retenida (baja de analista en curso), la conversión ESPERA ($((T1-T0)) ms) en vez de abrir tramo a ciegas" || rojo "J1: no esperó ($((T1-T0)) ms) · $(echo "$R" | head -c 150)"
  soltado; }
[[ "$(q "select etapa from crm.leads where id='$LJ'")" == "convertido" ]] && ok "[J1] soltada la jerarquía, la conversión termina bien" || rojo "J1 resultado: $(q "select etapa from crm.leads where id='$LJ'")"
IJ="$(q "select private.inversionista_por_documento('DNI','$DJ')")"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IJ' and hasta is null")" == "1" ]] && ok "[J2] con el analista ACTIVO, la conversión sí abre el tramo de responsable" || rojo "J2: $(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IJ'")"
# analista de baja ⇒ no se abre tramo
LK="$(uuid)"; lead_de "$LK" 32 K; AUK="$(uuid)"; DK="8${RUN}2"; sim_perfil "$AUK" "$DK" "k$RUN@x.pe"
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id='$V'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
R="$(run_as "$G" "select crm.convertir_lead('$LK','$AUK')")"; IK="$(q "select private.inversionista_por_documento('DNI','$DK')")"
if [[ "$(q "select etapa from crm.leads where id='$LK'")" == "convertido" ]]; then
  [[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IK' and hasta is null")" == "0" ]] && ok "[J3] con el asesor DE BAJA, la conversión NO le abre tramo de responsable" || rojo "J3: abrió tramo a un analista inactivo"
else echo "  (J3 omitido: la conversión no llegó a cerrar: $(echo "$R" | head -c 120))"; fi
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=true where perfil_id='$V'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1

# J1b — el interlock hace ESPERAR, así que la conversión necesita corte: con la jerarquía retenida más de 5 s tiene que
# morir con 55P03 (lock_timeout de la propia función) en vez de colgarse hasta el timeout de PostgREST (auditor D-18 #2).
on_ok
LT="$(uuid)"; lead_de "$LT" 35 T; AUT="$(uuid)"; DT="8${RUN}5"; sim_perfil "$AUT" "$DT" "t$RUN@x.pe"
retener_sys "select pg_advisory_xact_lock(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0))" 8 && {
  T0="$(ms)"; R="$(convertir "$LT" "$AUT")"; T1="$(ms)"
  if echo "$R" | grep -qi "lock timeout\|55P03"; then ok "[J1b] con la jerarquía retenida más que el lock_timeout, la conversión CORTA a los $((T1-T0)) ms (55P03) en vez de colgarse"
  else rojo "J1b: no cortó ($((T1-T0)) ms) · $(echo "$R" | head -c 160)"; fi
  soltado; }

# J4 — el offboarding REAL (crm.fijar_membresia_activa_fn), no una imitación del candado: la conversión espera a que
# termine y después NO le abre tramo al analista que acaba de irse (auditor D-18 #7a).
# Analista PROPIO de J4, sin cartera: así la baja real no exige reemplazo (el offboarding lo pide cuando hay dependencias).
on_ok
V4="$(uuid)"
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$V4') on conflict do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, activo) values ('$V4','D18 ANALISTA J4 r$RUN','comercial','DNI','79${RUN}',true) on conflict (id) do update set activo=true; insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$V4','vendedor','$SUP',true,'$SUP') on conflict (perfil_id) do update set activo=true; commit;" 2>&1 | grep -E "ERROR" | head -1
LM="$(uuid)"; lead_de "$LM" 36 M; AUM="$(uuid)"; DM="8${RUN}6"; sim_perfil_asesor "$AUM" "$DM" "m$RUN@x.pe" "$V4"
VEQ="$(q "select actualizado_en from crm.equipo where perfil_id='$V4'")"
# El offboarding exige reemplazo activo del mismo rol en cuanto el analista tiene cartera (aquí, el cliente de J4).
retener_as "$G" "select crm.fijar_membresia_activa_fn('$V4', false, '$V'::uuid, '$VEQ'::timestamptz, gen_random_uuid())" 3 && {
  T0="$(ms)"; R="$(run_as "$G" "select crm.convertir_lead('$LM','$AUM')")"; T1="$(ms)"
  (( T1 - T0 >= 2000 )) && ok "[J4] con el offboarding REAL en vuelo, la conversión espera ($((T1-T0)) ms)" || rojo "J4: no esperó al offboarding real ($((T1-T0)) ms) · $(echo "$R" | head -c 160)"
  soltado; }
IM="$(q "select private.inversionista_por_documento('DNI','$DM')")"
# La baja con reemplazo TRASPASA la cartera: lo correcto no es «ningún tramo», sino que el tramo sea del REEMPLAZO y
# nunca del saliente. Si la conversión no hubiera esperado, habría abierto el tramo a nombre de quien ya se fue.
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IM' and responsable_id='$V4' and hasta is null")" == "0" ]] && ok "[J4] y con la baja ya confirmada NO abre tramo al analista saliente" || rojo "J4: abrió tramo al analista saliente pese a la baja REAL recién confirmada"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IM' and responsable_id='$V' and hasta is null")" == "1" ]] && ok "[J4] el tramo queda a nombre del REEMPLAZO que eligió la baja" || rojo "J4: el tramo no quedó en el reemplazo · $(q "select responsable_id::text from crm.inversionista_responsables where inversionista_id='$IM' and hasta is null")"

# J5 — un escritor de crm.equipo que NO toma el interlock (el caso que el advisory no cubre): el `for share of e` de la
# conversión tiene que frenarla igual, por candado de FILA (auditor D-18 #7b).
on_ok
LN="$(uuid)"; lead_de "$LN" 37 N; AUN="$(uuid)"; DN="8${RUN}7"; sim_perfil "$AUN" "$DN" "n$RUN@x.pe"
retener_sys "select set_config('crm.op_privilegiada','on',true); update crm.equipo set capacidad_leads_objetivo = capacidad_leads_objetivo where perfil_id='$V'" 3 && {
  T0="$(ms)"; R="$(run_as "$G" "select crm.convertir_lead('$LN','$AUN')")"; T1="$(ms)"
  (( T1 - T0 >= 2000 )) && ok "[J5] un escritor de crm.equipo que NO toma el interlock también frena la conversión ($((T1-T0)) ms): el freno es el candado de FILA" || rojo "J5: no esperó al escritor de fila ($((T1-T0)) ms) · $(echo "$R" | head -c 160)"
  soltado; }
IN="$(q "select private.inversionista_por_documento('DNI','$DN')")"
[[ "$(q "select count(*) from crm.inversionista_responsables where inversionista_id='$IN' and hasta is null")" == "1" ]] && ok "[J5] y con el analista todavía activo, el tramo se abre" || rojo "J5: no abrió tramo con el analista activo"

on_ok

echo "== (b) La fusión con veto cancela también las tareas de CLIENTE (N6) =="
DP="8${RUN}3"; DC2="8${RUN}4"; IP="$(resolver "$DP")"; IC2="$(resolver "$DC2")"
AUP="$(uuid)"; sim_perfil "$AUP" "$DP" "p$RUN@x.pe"; sys "update crm.inversionistas set perfil_id='$AUP' where id='$IP'"
sys "update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='$G' where id='$IP'"
TAREA="$(uuid)"; sys "insert into crm.tareas (id, perfil_id, tipo, titulo, vence_en, estado, creado_por, vendedor_id) values ('$TAREA','$AUP','llamada','D18 TAREA DE CLIENTE r$RUN', now() + interval '2 days', 'pendiente','$V','$V')"
[[ "$(q "select estado from crm.tareas where id='$TAREA'")" == "pendiente" ]] && ok "fixture: persona P vetada, con ficha de cliente y una tarea de CLIENTE pendiente" || rojo "fixture tarea: $(q "select estado from crm.tareas where id='$TAREA'")"
R="$(run_as "$G" "select crm.fusion_previsualizar_fn('$IP','$IC2')")"; HASH="$(j "$R" hash)"
R="$(run_as "$G" "select crm.fusionar_inversionistas_fn('$IP','$IC2','ensayo d18 n6','$HASH')")"
if echo "$R" | grep -q "tareas_cliente_canceladas"; then
  N="$(python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
print((d.get('impacto') or {}).get('tareas_cliente_canceladas'))" "$R" 2>/dev/null)"
  [[ "$(q "select estado from crm.tareas where id='$TAREA'")" == "cancelada" && "$N" == "1" ]] && ok "[N6] la fusión que hereda el veto CANCELA la tarea de cliente y lo informa (impacto.tareas_cliente_canceladas=1)" || rojo "N6: tarea=$(q "select estado from crm.tareas where id='$TAREA'") contador=$N · $(echo "$R" | head -c 200)"
else rojo "N6: la respuesta no trae tareas_cliente_canceladas · $(echo "$R" | head -c 220)"; fi

echo "== Limpieza =="
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); update crm.leads set activo=false where nombre_completo like 'D18 % r$RUN' and activo; delete from crm.tareas where titulo like 'D18 %r$RUN'; commit;" >/dev/null 2>&1
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b D-18: VERDE — la conversión espera a la baja del analista y no abre tramo a un inactivo; la fusión con veto cancela las tareas de cliente."; else echo "ORÁCULO F2.b D-18: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
