#!/usr/bin/env bash
# ORÁCULO F2.b sub-lote b2 — «el veto de la persona bloquea reparto, toma, reapertura y
# seguimiento» — SOLO en el BANCO. Ejercita las MUTACIONES por sus puertas públicas con la
# bandera ENCENDIDA sobre leads NO enlazados cuyo documento pertenece a una persona vetada
# (el caso que solo el veto de la PERSONA puede cerrar), y la paridad con la bandera APAGADA.
# Uso: S=/ruta/scratchpad ./oraculo-f2b-b2.sh   (lee $S/banco-pooler.txt)
# Presupone: banco con el lote 190000..260000 + b1 (20260904120000) + b2 (20260904130000).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SU='f3000000-0000-0000-0000-000000000003'; V2='f3000000-0000-0000-0000-000000000004'
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"
L3="f31ead00-0000-0000-0000-${RUN}000003"; L4="f31ead00-0000-0000-0000-${RUN}000004"
DA="7${RUN}5"; DB="7${RUN}6"; DC="7${RUN}7"; DD="7${RUN}8"; DE="7${RUN}9"; T="9${RUN}"; ROJO=0
AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
run_sys() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; $1; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
uuid() { q "select gen_random_uuid()"; }
ins()  { echo "insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id,asignado_supervisor_id,dni) values ('$1','B2 $2 r$RUN','$3',1000,'landing','nuevo',null,$4,$5,'$6')"; }
coop() { echo "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$2','B2 PERSONA','TRX-B2-${RUN}-$3')"; }
inv_de() { q "select private.inversionista_por_documento('DNI','$1')"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select to_regprocedure('private.persona_vetada(uuid)') is not null")" == "t" ]] || { echo "falta b2 en el banco" >&2; exit 2; }
# Leads NO enlazados (nacen con la bandera APAGADA) con el documento de personas que luego se vetan:
flag true
# Cada persona: un lead de la siembra convertido en coop (queda enlazado) → luego se veta.
for par in "$L1:$DA:1" "$L2:$DB:2" "$L3:$DC:3" "$L4:$DD:4"; do IFS=: read -r L D N <<< "$par"; run_as "$V" "$(coop "$L" "$D" "$N")" >/dev/null || rojo "coop $N falló"; done
# [D-13] los sueltos con el documento de las personas a–d nacen DESPUÉS de las conversiones (un suelto vivo con el documento cuenta en «un solo lead»)
flag false
LU1="$(uuid)"; LU2="$(uuid)"; LU3="$(uuid)"; LU4="$(uuid)"
run_sys "$(ins "$LU1" BOLSA "${T}31" null null "$DA")" >/dev/null || rojo "no se pudo crear LU1"
run_sys "$(ins "$LU2" SUPERV "${T}32" null "'$SU'" "$DB")" >/dev/null || rojo "no se pudo crear LU2"
run_sys "$(ins "$LU3" DERIVADO "${T}33" null "'$SU'" "$DC")" >/dev/null || rojo "no se pudo crear LU3"
run_sys "$(ins "$LU4" EN-COLA "${T}34" null null "$DD")" >/dev/null || rojo "no se pudo crear LU4"
[[ "$(q "select count(*) from crm.leads where id in ('$LU1','$LU2','$LU3','$LU4') and inversionista_id is null")" == "4" ]] && ok "4 leads sueltos (sin enlace) con documento, creados con la bandera apagada" || rojo "los leads nacieron enlazados"
flag true
[[ "$(q "select count(*) from crm.inversionista_responsables r join crm.inversionista_identificadores d on d.inversionista_id=r.inversionista_id where r.hasta is null and r.responsable_id='$V' and d.documento_normalizado in ('$DA','$DB','$DC','$DD')")" == "4" ]] && ok "4 personas con responsable de relación V (tramo abierto)" || rojo "tramos de responsable ≠ 4"
# Antes de vetar: S deriva LU3 a V (con bandera ON, persona aún sin veto) y V agenda una tarea en LU3.
R="$(run_as "$SU" "select crm.derivar_leads_equipo_fn(array['$LU3']::uuid[], array['$V']::uuid[])")"; [[ "$(q "select vendedor_id='$V' from crm.leads where id='$LU3'")" == "t" ]] && ok "derivación previa LU3→V (persona sin veto): pasa" || rojo "derivación previa falló: $(echo "$R"|tail -1|cut -c1-120)"
# Persona E: identidad SIN lead → LU5 nace ENLAZADO (b1) y V le agenda una tarea pendiente.
q "select private.inversionista_resolver('DNI','$DE',true,'ensayo_b2')" >/dev/null; LU5="$(uuid)"
run_sys "$(ins "$LU5" ENLAZADO "${T}35" "'$V'" null "$DE")" >/dev/null
[[ "$(q "select inversionista_id is not null from crm.leads where id='$LU5'")" == "t" ]] && ok "LU5 nació enlazado a $DE" || rojo "LU5 no enlazó"
TA="$(uuid)"; R="$(run_as "$V" "insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, estado, creado_por) values ('$TA','$LU5','$V','llamada','B2 tarea','$(q "select (now()+interval '1 day')::text")','pendiente','$V')")"
[[ "$(q "select estado from crm.tareas where id='$TA'")" == "pendiente" ]] && ok "tarea pendiente en LU5" || rojo "no se pudo crear la tarea: $(echo "$R"|tail -1|cut -c1-120)"
# VETO de las 5 personas (por su lead enlazado).
for L in "$L1" "$L2" "$L3" "$L4" "$LU5"; do run_as "$V" "select crm.marcar_no_contactar('$L','ensayo b2')" >/dev/null || rojo "marcar $L falló"; done
[[ "$(q "select count(*) from crm.inversionistas i where i.no_contactar and i.id in (select private.inversionista_por_documento('DNI',d) from unnest(array['$DA','$DB','$DC','$DD','$DE']) d)")" == "5" ]] && ok "5 personas vetadas" || rojo "personas vetadas ≠ 5"
[[ "$(q "select count(*) from crm.leads where id in ('$LU1','$LU2','$LU3','$LU4') and no_contactar=false and inversionista_id is null")" == "4" ]] && ok "los 4 leads sueltos siguen SIN veto propio y sin enlace (solo la persona los veta)" || rojo "los leads sueltos cambiaron"
[[ "$(q "select private.persona_vetada('$LU1') and private.persona_vetada('$LU5')")" == "t" ]] && ok "persona_vetada(): por documento (suelto) y por enlace" || rojo "helper no detecta el veto"

echo "== Mutaciones sobre leads sueltos de personas vetadas → P0429 / veredicto =="
R="$(run_as "$G" "select crm.repartir_lead('$LU1','$SU')")"; echo "$R" | grep -q "P0429" && ok "repartir_lead → P0429" || rojo "repartir pasó: $(echo "$R"|tail -1|cut -c1-120)"
EC="$(run_as "$G" "select count(*) from crm.leads_por_repartir() x where x.id='$LU1'" | tail -1)"
[[ "$EC" == "0" ]] && ok "la cola (leads_por_repartir, como Gerencia) no lista a LU1" || rojo "la cola lista a LU1 ($EC)"
NC="$(run_as "$G" "select count(*) from crm.leads_por_repartir()" | tail -1)"; NR="$(run_as "$G" "select (select sum((e->>'n')::int) from jsonb_array_elements(crm.resumen_reparto_fn()->'cola'->'por_origen') e)" | tail -1)"
[[ "$NC" == "${NR:-0}" ]] && ok "resumen_reparto_fn cuenta lo mismo que la cola ($NC)" || rojo "resumen ($NR) ≠ cola ($NC)"
R="$(run_as "$V" "select crm.tomar_lead_libre('${T}31','$DA')")"; echo "$R" | grep -q "no_contactar" && [[ "$(q "select vendedor_id is null from crm.leads where id='$LU1'")" == "t" ]] && ok "tomar_lead_libre → veredicto no_contactar, sin tomar" || rojo "tomar: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$SU" "select crm.derivar_leads_equipo_fn(array['$LU2']::uuid[], array['$V']::uuid[])")"; echo "$R" | grep -q "P0429" && ok "derivar_leads_equipo_fn → P0429" || rojo "derivar pasó: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$SU" "select crm.revertir_derivacion_equipo_fn('$LU3')")"; echo "$R" | grep -q "P0429" && ok "revertir_derivacion_equipo_fn → P0429" || rojo "revertir pasó: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$V" "insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values ('$LU3','llamada_realizada','B2','{}'::jsonb,'$V')")"; echo "$R" | grep -q "P0429" && ok "actividad humana sobre LU3 → P0429 (seguimiento bloqueado)" || rojo "actividad pasó: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$V" "insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, estado, creado_por) values ('$LU3','$V','llamada','B2 t','$(q "select (now()+interval '1 day')::text")','pendiente','$V')")"; echo "$R" | grep -q "P0429" && ok "tarea humana sobre LU3 → P0429" || rojo "tarea pasó: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$G" "select crm.descartar_lead('$LU4','sin_interes','ensayo b2')")"; [[ "$(q "select etapa from crm.leads where id='$LU4'")" == "descartado" ]] && ok "descartar LU4 desde la cola (cerrar no es contactar): pasa" || rojo "descartar falló: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$G" "select crm.deshacer_descarte('$LU4')")"; echo "$R" | grep -q "P0429" && ok "deshacer_descarte → P0429" || rojo "deshacer pasó: $(echo "$R"|tail -1|cut -c1-120)"

echo "== Marcar cancela tareas pendientes; levantar no las revive; la nota del veto entra =="
[[ "$(q "select estado||'/'||coalesce(cancelada_por,'') from crm.tareas where id='$TA'")" == "cancelada/sistema" ]] && ok "la tarea de LU5 quedó cancelada por 'sistema'" || rojo "tarea: $(q "select estado||'/'||coalesce(cancelada_por,'') from crm.tareas where id='$TA'")"
[[ "$(q "select count(*) from crm.actividades where lead_id='$LU5' and metadata->>'evento'='no_contactar'")" == "1" ]] && ok "la nota de marcar se registró (válvula exime al trigger de gestión)" || rojo "sin nota de marcar"
run_as "$G" "select crm.levantar_no_contactar('$LU5','ensayo b2')" >/dev/null && ok "gerencia levantó el veto de LU5" || rojo "levantar falló"
[[ "$(q "select estado from crm.tareas where id='$TA'")" == "cancelada" ]] && ok "la tarea sigue cancelada tras levantar" || rojo "levantar revivió la tarea"
R="$(run_as "$V" "insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values ('$LU5','llamada_realizada','B2 tras levantar','{}'::jsonb,'$V')")"; [[ -z "$(echo "$R"|grep P0429)" ]] && ok "tras levantar, el seguimiento vuelve" || rojo "seguimiento sigue bloqueado tras levantar"

echo "== Paridad con bandera APAGADA (mismo lead suelto, misma persona vetada) =="
flag false
[[ "$(q "select private.persona_vetada('$LU1')")" == "f" ]] && ok "OFF: persona_vetada() = false" || rojo "OFF: helper activo"
R="$(run_as "$G" "select crm.repartir_lead('$LU1','$SU')")"; [[ "$(q "select asignado_supervisor_id='$SU' from crm.leads where id='$LU1'")" == "t" ]] && ok "OFF: repartir_lead pasa como hoy" || rojo "OFF: repartir falló: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$SU" "select crm.derivar_leads_equipo_fn(array['$LU2']::uuid[], array['$V']::uuid[])")"; [[ "$(q "select vendedor_id='$V' from crm.leads where id='$LU2'")" == "t" ]] && ok "OFF: derivar pasa como hoy" || rojo "OFF: derivar falló: $(echo "$R"|tail -1|cut -c1-120)"
R="$(run_as "$V" "insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values ('$LU3','llamada_realizada','B2 OFF','{}'::jsonb,'$V')")"; [[ -z "$(echo "$R"|grep P0429)" ]] && ok "OFF: actividad pasa como hoy" || rojo "OFF: actividad bloqueada"
flag true

echo "== Marcar/levantar por PERSONA sobre un lead SUELTO (documento exacto) =="
DF="7${RUN}0"; q "select private.inversionista_resolver('DNI','$DF',true,'ensayo_b2f')" >/dev/null
flag false; LU6="$(uuid)"; run_sys "$(ins "$LU6" SUELTO-F "${T}36" "'$V'" null "$DF")" >/dev/null; flag true
[[ "$(q "select inversionista_id is null from crm.leads where id='$LU6'")" == "t" ]] && ok "LU6 suelto (sin enlace) con el documento de la persona F (sin lead)" || rojo "LU6 nació enlazado"
run_as "$V" "select crm.marcar_no_contactar('$LU6','ensayo suelto')" >/dev/null || rojo "marcar sobre suelto falló"
[[ "$(q "select i.no_contactar from crm.inversionistas i where i.id = private.inversionista_por_documento('DNI','$DF')")" == "t" && "$(q "select no_contactar and inversionista_id is null from crm.leads where id='$LU6'")" == "t" ]] && ok "marcar sobre un lead suelto vetó a la PERSONA (por documento) y al lead, sin enlazarlo" || rojo "marcar sobre suelto no llegó a la persona"
run_as "$G" "select crm.levantar_no_contactar('$LU6','ensayo suelto')" >/dev/null || rojo "levantar sobre suelto falló"
[[ "$(q "select i.no_contactar from crm.inversionistas i where i.id = private.inversionista_por_documento('DNI','$DF')")" == "f" && "$(q "select no_contactar from crm.leads where id='$LU6'")" == "f" ]] && ok "levantar sobre el lead suelto levantó a la persona y al lead" || rojo "levantar sobre suelto incompleto"

echo "== Rescate de descartes y notas administrativas =="
# Episodio rescatable REAL: lead con asignación a V, descartado por V (PATCH del front) → lead_asignaciones.resultado='descartado'.
LU7="$(uuid)"; DG="7${RUN}1"
flag false; run_sys "$(ins "$LU7" DESCARTE-V "${T}37" "'$V'" null "$DD")" >/dev/null; flag true
run_as "$V" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LU7'" >/dev/null
EP="$(q "select la.id from crm.lead_asignaciones la where la.lead_id='$LU7' and la.resultado='descartado' order by la.resultado_en desc limit 1")"
[[ -n "$EP" ]] && ok "episodio de descarte real para LU7 (persona vetada D, lead suelto)" || rojo "sin episodio de descarte para LU7: el rescate no se puede ejercitar"
R="$(run_as "$G" "select crm.rescatar_descartes(array['$EP']::uuid[], array['$V']::uuid[], false)")"; echo "$R" | grep -q "P0429" && ok "rescatar_descartes (persona vetada, lead suelto) → P0429" || rojo "rescatar pasó o falló distinto: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-140)"
# OFF: el rescate de un descarte de persona NO vetada debe EJECUTARSE (código real, no saltado).
q "select private.inversionista_resolver('DNI','$DG',true,'ensayo_b2g')" >/dev/null
LU8="$(uuid)"; flag false; run_sys "$(ins "$LU8" DESCARTE-OFF "${T}38" "'$V'" null "$DG")" >/dev/null
run_as "$V" "update crm.leads set etapa='descartado', motivo_descarte='sin_interes' where id='$LU8'" >/dev/null
EP8="$(q "select la.id from crm.lead_asignaciones la where la.lead_id='$LU8' and la.resultado='descartado' order by la.resultado_en desc limit 1")"
R="$(run_as "$G" "select crm.rescatar_descartes(array['$EP8']::uuid[], array['$V']::uuid[], false)")"
[[ "$(q "select etapa from crm.leads where id='$LU8'")" != "descartado" ]] && ok "OFF: rescatar_descartes ejecuta y reabre (la rama transformada corre sin error)" || rojo "OFF: rescatar no reabrió: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-140)"
flag true
R="$(run_as "$V" "insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values ('$LU3','nota','B2 nota administrativa','{}'::jsonb,'$V')")"; [[ -z "$(echo "$R"|grep P0429)" ]] && ok "una NOTA sobre persona vetada entra (no es contacto)" || rojo "nota bloqueada: $(echo "$R"|tail -1|cut -c1-100)"

echo "== Offboarding: sin cambios en este lote (la reasignación del responsable es puerta de Gerencia, b5) =="
[[ "$(q "select strpos(prosrc,'offboarding') from pg_proc where proname='fijar_membresia_activa_fn'")" == "0" ]] && ok "fijar_membresia_activa_fn intacta" || rojo "fijar_membresia_activa_fn transformada"

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b b2: VERDE — el veto de la persona bloquea reparto, derivación, reversión, toma, reapertura y seguimiento; marcar cancela tareas; marcar/levantar por persona sobre leads sueltos; paridad apagada."; exit 0
else echo "ORÁCULO F2.b b2: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
