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
# V2: segundo vendedor bajo S (reemplazo del offboarding; mismo rol CRM que V).
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into auth.users (id) values ('$V2') on conflict (id) do nothing; insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$V2','F3 VENDEDOR DOS','comercial','DNI','70000094') on conflict (id) do update set activo=true; insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$V2','vendedor','$SU',true,'$SU') on conflict (perfil_id) do update set rol_crm='vendedor', supervisor_id='$SU', activo=true; commit;" >/dev/null 2>&1
# Leads NO enlazados (nacen con la bandera APAGADA) con el documento de personas que luego se vetan:
flag false
LU1="$(uuid)"; LU2="$(uuid)"; LU3="$(uuid)"; LU4="$(uuid)"
run_sys "$(ins "$LU1" BOLSA "${T}31" null null "$DA")" >/dev/null || rojo "no se pudo crear LU1"
run_sys "$(ins "$LU2" SUPERV "${T}32" null "'$SU'" "$DB")" >/dev/null || rojo "no se pudo crear LU2"
run_sys "$(ins "$LU3" DERIVADO "${T}33" null "'$SU'" "$DC")" >/dev/null || rojo "no se pudo crear LU3"
run_sys "$(ins "$LU4" EN-COLA "${T}34" null null "$DD")" >/dev/null || rojo "no se pudo crear LU4"
[[ "$(q "select count(*) from crm.leads where id in ('$LU1','$LU2','$LU3','$LU4') and inversionista_id is null")" == "4" ]] && ok "4 leads sueltos (sin enlace) con documento, creados con la bandera apagada" || rojo "los leads nacieron enlazados"
flag true
# Cada persona: un lead de la siembra convertido en coop (queda enlazado) → luego se veta.
for par in "$L1:$DA:1" "$L2:$DB:2" "$L3:$DC:3" "$L4:$DD:4"; do IFS=: read -r L D N <<< "$par"; run_as "$V" "$(coop "$L" "$D" "$N")" >/dev/null || rojo "coop $N falló"; done
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
NC="$(run_as "$G" "select count(*) from crm.leads_por_repartir()" | tail -1)"; NR="$(run_as "$G" "select (select sum((e->>'n')::int) from jsonb_array_elements(crm.resumen_reparto_fn()->'por_origen') e)" | tail -1)"
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

echo "== Offboarding: el responsable de relación pasa al reemplazo (V2, mismo rol) =="
VER="$(q "select actualizado_en::text from crm.equipo where perfil_id='$V'")"
R="$(run_as "$G" "select crm.fijar_membresia_activa_fn('$V', false, '$V2', '$VER'::timestamptz, gen_random_uuid())")"
echo "$R" | grep -q "perfil_id" && ok "offboarding de V ejecutado" || rojo "offboarding falló: $(echo "$R"|grep -E 'ERROR|MESSAGE'|head -1|cut -c1-160)"
[[ "$(q "select count(*) from crm.inversionista_responsables r where r.responsable_id='$V' and r.hasta is null")" == "0" ]] && ok "V ya no tiene tramos abiertos" || rojo "V conserva tramos abiertos"
[[ "$(q "select count(*) from crm.inversionista_responsables r where r.responsable_id='$V2' and r.hasta is null and r.motivo='offboarding' and r.inversionista_id in (select private.inversionista_por_documento('DNI',d) from unnest(array['$DA','$DB','$DC','$DD']) d)")" == "4" ]] && ok "4 tramos nuevos abiertos a V2 con motivo 'offboarding'" || rojo "tramos a V2 ≠ 4"
[[ "$(q "select count(*) from crm.inversionistas i where i.responsable_relacion_id='$V2' and i.id in (select private.inversionista_por_documento('DNI',d) from unnest(array['$DA','$DB','$DC','$DD']) d)")" == "4" ]] && ok "responsable_relacion_id = V2 en las 4 personas" || rojo "responsable_relacion_id no cambió"
[[ "$(q "select count(*) from crm.inversionista_responsables r where r.hasta is null and r.inversionista_id in (select private.inversionista_por_documento('DNI',d) from unnest(array['$DA','$DB','$DC','$DD']) d)")" == "4" ]] && ok "un solo tramo abierto por persona" || rojo "más de un tramo abierto"
[[ "$(q "select vendedor_id='$V2' from crm.leads where id='$LU3'")" == "t" ]] && ok "el lead suelto de persona vetada (LU3) también se transfirió a V2 (custodia ≠ contacto)" || rojo "LU3 no se transfirió: $(q "select vendedor_id from crm.leads where id='$LU3'")"

psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F2.b b2: VERDE — el veto de la persona bloquea reparto, derivación, reversión, toma, reapertura y seguimiento; marcar cancela tareas; offboarding reasigna; paridad apagada."; exit 0
else echo "ORÁCULO F2.b b2: ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
