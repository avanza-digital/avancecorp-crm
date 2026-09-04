#!/usr/bin/env bash
# ORÁCULO F2.b sub-lote b1 — «el alta reconoce a la persona» — SOLO en el BANCO.
# Ejercita las PUERTAS de alta (INSERT directo tipo importador sin sesión, alta manual
# crear_lead_si_disponible, UPDATE de dni) con la bandera ENCENDIDA y la paridad con
# la bandera APAGADA. Dos sesiones reales en transacción para las carreras.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-b1.sh   (lee $S/banco-pooler.txt)
# Presupone: banco con F1 + backfill + lote 190000..260000 + 20260904120000 (b1).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
L5="f31ead00-0000-0000-0000-${RUN}000005"
DOC5="7${RUN}3"; DOC7="7${RUN}7"; DOC8="7${RUN}8"; DOC9="7${RUN}9"; DOC0="7${RUN}0"; DOC2="7${RUN}2"
T="9${RUN}"; ROJO=0
AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
run_sys() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; $1; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
ins()  { echo "insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id,dni) values ('$1','B1 $2 r$RUN','$3',1000,'landing','nuevo',null,'$V',$4) returning id"; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }
lead_de() { q "select l.id from crm.leads l where l.inversionista_id = private.inversionista_por_documento('DNI','$1') limit 1"; }
uuid() { q "select gen_random_uuid()"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is not null")" == "t" ]] || { echo "falta b1 en el banco" >&2; exit 2; }
flag true
# Persona CON lead y sin perfil: L5 convertida en coop (DOC5). Personas SIN lead: identidades sembradas por el resolver (DOC7, DOC8, DOC9, DOC0, DOC2).
run_as "$V" "select crm.convertir_lead_externo('$L5','qorilazo',1000,'PEN','DNI','$DOC5','B1 PERSONA CINCO','TRX-B1-${RUN}-5')" >/dev/null && ok "L5 convertido en coop → persona $DOC5 con UN lead" || rojo "no se pudo convertir L5"
for d in $DOC7 $DOC8 $DOC9 $DOC0 $DOC2; do q "select private.inversionista_resolver('DNI','$d',true,'ensayo_b1')" >/dev/null; done
[[ -n "$(inv_de $DOC7)" && -z "$(lead_de $DOC7)" ]] && ok "identidad $DOC7 sembrada SIN lead" || rojo "siembra de identidad falló"

echo "== (b) Persona con lead: un 2.º lead por el camino del importador (sin sesión) → P0481 ya_es_cliente =="
R="$(run_sys "$(ins "$(uuid)" DUP-IMPORT "${T}11" "'$DOC5'")")"
echo "$R" | grep -q "P0481" && echo "$R" | grep -q '"via": *"identidad"\|"via":"identidad"' && echo "$R" | grep -q "$L5" && ok "P0481 con veredicto ya_es_cliente vía identidad y lead_id=L5" || rojo "no rechazó/veredicto incompleto: $(echo "$R"|tail -2|cut -c1-160)"
[[ "$(q "select count(*) from crm.leads where dni='$DOC5'")" == "0" ]] && ok "no se insertó ningún lead con ese DNI" || rojo "se insertó un 2.º lead"

echo "== (c) Persona sin lead: el lead NACE enlazado + puente (AFTER) =="
LA="$(uuid)"; R="$(run_sys "$(ins "$LA" NACE-ENLAZADO "${T}12" "'$DOC7'")")"
[[ "$(q "select inversionista_id = private.inversionista_por_documento('DNI','$DOC7') from crm.leads where id='$LA'")" == "t" ]] && ok "lead con inversionista_id de $DOC7" || rojo "no enlazó: $(echo "$R"|tail -1|cut -c1-120)"
[[ "$(q "select count(*) from crm.inversionista_leads where lead_id='$LA' and rol='canonico'")" == "1" ]] && ok "puente canónico creado por el AFTER" || rojo "sin puente"
R="$(run_sys "$(ins "$(uuid)" DUP-7 "${T}13" "'$DOC7'")")"
echo "$R" | grep -q "P0481" && echo "$R" | grep -q "$LA" && ok "2.º lead para $DOC7 → P0481 con lead_id del primero" || rojo "2.º lead no rechazado: $(echo "$R"|tail -1|cut -c1-120)"

echo "== Sin documento / sin coincidencia → NULL (captación) =="
LB="$(uuid)"; run_sys "$(ins "$LB" SIN-DNI "${T}14" "null")" >/dev/null
[[ "$(q "select inversionista_id is null from crm.leads where id='$LB'")" == "t" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LB'")" == "0" ]] && ok "sin DNI: inversionista_id NULL, sin puente" || rojo "sin DNI tocó identidad"
LC="$(uuid)"; run_sys "$(ins "$LC" DNI-DESCONOCIDO "${T}15" "'6${RUN}1'")" >/dev/null
[[ "$(q "select inversionista_id is null from crm.leads where id='$LC'")" == "t" && "$(q "select count(*) from crm.inversionista_identificadores where documento_normalizado='6${RUN}1'")" == "0" ]] && ok "DNI sin identidad: NULL y NO se creó identidad" || rojo "creó identidad desde el alta"

echo "== UPDATE de dni: enlazado → P0409; suelto → enlaza; humano y sin sesión =="
R="$(run_as "$V" "update crm.leads set dni='$DOC8' where id='$LA'")"; echo "$R" | grep -q "P0409" && ok "cambiar el DNI de un lead ENLAZADO (vendedor) → P0409" || rojo "dejó cambiar el DNI enlazado: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_sys "update crm.leads set dni='$DOC8' where id='$LA'")"; echo "$R" | grep -q "P0409" && ok "… también sin sesión (service_role) → P0409" || rojo "service_role cambió el DNI enlazado"
R="$(run_as "$V" "update crm.leads set dni='$DOC8' where id='$LB'")"
[[ "$(q "select inversionista_id = private.inversionista_por_documento('DNI','$DOC8') from crm.leads where id='$LB'")" == "t" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LB'")" == "1" ]] && ok "lead suelto + DNI de persona sin lead (vendedor) → queda enlazado + puente" || rojo "UPDATE humano no enlazó: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_sys "update crm.leads set dni='$DOC5' where id='$LC'")"; echo "$R" | grep -q "P0481" && ok "lead suelto + DNI de persona CON lead → P0481" || rojo "UPDATE a DNI ocupado no rechazado: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$V" "update crm.leads set nombre_completo='B1 renombrado' where id='$LA'")"; [[ -z "$(echo "$R" | grep -i error)" ]] && ok "UPDATE que no toca dni no dispara nada" || rojo "UPDATE ajeno al dni falló: $(echo "$R"|tail -1|cut -c1-100)"

echo "== (a) Persona vetada → P0429 (y la carrera alta ↔ marcar) =="
run_as "$V" "select crm.marcar_no_contactar('$L5','ensayo b1')" >/dev/null || rojo "marcar falló"
R="$(run_sys "$(ins "$(uuid)" VETADA "${T}16" "'$DOC5'")")"; echo "$R" | grep -q "P0429" && ok "alta de persona vetada → P0429" || rojo "no rechazó a la vetada: $(echo "$R"|tail -1|cut -c1-120)"
run_as "$G" "select crm.levantar_no_contactar('$L5','limpieza ensayo b1')" >/dev/null
# Carrera: A marca el veto y duerme con la identidad bloqueada; B (0,5 s después) intenta el alta → debe ESPERAR y ver el veto.
run_as "$V" "select crm.marcar_no_contactar('$L5','carrera b1'); select pg_sleep(2)" > "$S/b1_race_a.out" & pa=$!
sleep 0.5; R="$(run_sys "$(ins "$(uuid)" CARRERA-VETO "${T}17" "'$DOC5'")")"; wait $pa
echo "$R" | grep -q "P0429" && ok "el alta esperó el lock de la identidad y vio el veto recién puesto" || rojo "el alta no vio el veto concurrente: $(echo "$R"|tail -1|cut -c1-120)"
echo "$R$(cat $S/b1_race_a.out)" | grep -qi deadlock && rojo "DEADLOCK alta↔marcar"
run_as "$G" "select crm.levantar_no_contactar('$L5','limpieza ensayo b1 (2)')" >/dev/null

echo "== Alta manual (RPC) ↔ alta directa ↔ conversión coop: sin deadlock, un solo lead =="
LD="$(uuid)"; LE="$(uuid)"
run_sys "$(ins "$LD" RACE-D "${T}18" "'$DOC9'")" > "$S/b1_r1.out" & p1=$!
run_sys "$(ins "$LE" RACE-E "${T}19" "'$DOC9'")" > "$S/b1_r2.out" & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
cat "$S/b1_r1.out" "$S/b1_r2.out" | grep -qi deadlock && rojo "DEADLOCK entre dos altas directas"
[[ $(( (r1==0) + (r2==0) )) == 1 ]] && ok "dos altas directas simultáneas del mismo DNI → exactamente UNA gana" || rojo "éxitos: $(( (r1==0)+(r2==0) ))"
[[ "$(q "select count(*) from crm.leads where inversionista_id = private.inversionista_por_documento('DNI','$DOC9')")" == "1" ]] && ok "una sola fila enlazada a $DOC9" || rojo "leads enlazados a $DOC9 ≠ 1"
# RPC humana con un DNI cuya persona ya tiene lead → veredicto sin insertar; con DNI de persona sin lead → inserta enlazado.
R="$(run_as "$V" "select crm.crear_lead_si_disponible('B1 RPC OCUPADO','${T}20','landing',1000,'PEN',gen_random_uuid(),null,'$DOC9')")"
echo "$R" | grep -q "ya_es_cliente" && echo "$R" | grep -q "identidad" && ok "crear_lead_si_disponible con DNI ocupado → veredicto ya_es_cliente/identidad (con lead_id)" || rojo "RPC no devolvió el veredicto: $(echo "$R"|tail -1|cut -c1-140)"
R="$(run_as "$V" "select crm.crear_lead_si_disponible('B1 RPC LIBRE','${T}21','landing',1000,'PEN',gen_random_uuid(),null,'$DOC0')")"
[[ "$(q "select count(*) from crm.leads l where l.inversionista_id = private.inversionista_por_documento('DNI','$DOC0')")" == "1" ]] && ok "crear_lead_si_disponible con DNI de persona sin lead → lead enlazado" || rojo "RPC no enlazó: $(echo "$R"|tail -1|cut -c1-140)"
# RPC ↔ coop concurrentes por el mismo documento nuevo (DOC2 tiene identidad sin lead): ninguna se abraza.
LF="$(uuid)"; run_sys "$(ins "$LF" COOP-BASE "${T}22" "null")" >/dev/null
run_as "$V" "select crm.crear_lead_si_disponible('B1 RPC VS COOP','${T}23','landing',1000,'PEN',gen_random_uuid(),null,'$DOC2')" > "$S/b1_r3.out" & p3=$!
run_as "$V" "select crm.convertir_lead_externo('$LF','qorilazo',1000,'PEN','DNI','$DOC2','B1 PERSONA DOS','TRX-B1-${RUN}-2')" > "$S/b1_r4.out" & p4=$!
wait $p3; wait $p4
cat "$S/b1_r3.out" "$S/b1_r4.out" | grep -qi deadlock && rojo "DEADLOCK alta RPC ↔ conversión coop" || ok "alta RPC ↔ conversión coop del mismo documento: sin deadlock"
[[ "$(q "select count(*) from crm.leads where inversionista_id = private.inversionista_por_documento('DNI','$DOC2')")" == "1" ]] && ok "la persona $DOC2 terminó con UN solo lead enlazado" || rojo "leads enlazados a $DOC2: $(q "select count(*) from crm.leads where inversionista_id = private.inversionista_por_documento('DNI','$DOC2')")"

echo "== Reingreso: el cliente que vuelve queda en SU lead (service_role), sin documento en claro =="
R="$(run_sys "select crm.registrar_reingreso_lead_fn('$L5','hoja','{\"nombre\":\"X\",\"telefono\":\"${T}11\",\"dni\":\"$DOC5\",\"capital\":5000}'::jsonb)")"
echo "$R" | grep -q '"ok": *true' && ok "reingreso registrado" || rojo "reingreso falló: $(echo "$R"|tail -1|cut -c1-120)"
[[ "$(q "select count(*) from crm.actividades where lead_id='$L5' and tipo='nota' and metadata->>'evento'='reingreso' and metadata->'datos' ? 'dni' = false and metadata->'datos' ? 'telefono'")" == "1" ]] && ok "actividad nota evento=reingreso, con teléfono y SIN dni" || rojo "actividad de reingreso incorrecta"
R="$(run_as "$V" "select crm.registrar_reingreso_lead_fn('$L5','hoja','{}'::jsonb)")"; echo "$R" | grep -q "42501" && ok "con sesión (authenticated) → 42501" || rojo "authenticated pudo registrar reingreso"

echo "== Paridad con bandera APAGADA =="
flag false
LG="$(uuid)"; R="$(run_sys "$(ins "$LG" OFF-DUP "${T}24" "'$DOC5'")")"
[[ "$(q "select inversionista_id is null from crm.leads where id='$LG'")" == "t" && "$(q "select count(*) from crm.inversionista_leads where lead_id='$LG'")" == "0" ]] && ok "OFF: el importador inserta como hoy (2.º lead, sin enlace, sin puente)" || rojo "OFF: comportamiento distinto: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$V" "update crm.leads set dni='6${RUN}2' where id='$LG'")"; [[ -z "$(echo "$R" | grep -i "P04")" && "$(q "select inversionista_id is null from crm.leads where id='$LG'")" == "t" ]] && ok "OFF: UPDATE de dni sin veredicto de identidad ni enlace" || rojo "OFF: el UPDATE de dni levantó $(echo "$R"|grep -o 'P0[0-9]*'|head -1)"
[[ "$(q "select r->>'estado' from private.verificar_disponibilidad_lead_impl('${T}25','$DOC7',null) r")" != "ya_es_cliente" ]] && ok "OFF: disponibilidad no consulta identidad" || rojo "OFF: disponibilidad consultó identidad"
R="$(run_sys "select crm.registrar_reingreso_lead_fn('$L5','hoja','{}'::jsonb)")"; echo "$R" | grep -q '"ok": *true' && ok "OFF: la RPC de reingreso existe y funciona (el edge no la llama con OFF)" || rojo "reingreso OFF falló"
flag true

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b b1: VERDE — el alta reconoce a la persona por las puertas, sin deadlocks, con paridad apagada."; exit 0
else echo "ORÁCULO F2.b b1: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
