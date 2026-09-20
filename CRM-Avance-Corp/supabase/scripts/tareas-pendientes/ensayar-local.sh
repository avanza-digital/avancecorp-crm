#!/usr/bin/env bash
# Ensayo LOCAL de 20260919235100 (tareas por cursor) sobre una copia del
# contenedor del banco (`supabase_db_avancecorp-f5-bank`, puerto 58322), creada
# desde una base a paridad 20260917235656 CON el mundo SLA y la restrictiva de
# postventa (que el banco remoto `banco-f7` aún no tiene). Así la migración se
# aplica TAL CUAL, en un solo mensaje como producción (`psql -c`), sin
# divergencias que anotar.
#
#   TEMPLATE=conversion_inversion_base_20260919 DB=tareas_cursor_20260919 \
#     bash supabase/scripts/tareas-pendientes/ensayar-local.sh
#
# Pasos: copia → estado previo → instalación → gate + mutantes + esquema intacto
# → md5 (solo de referencia: los del registrador se miden en prod) → siembra
# (dos tareas de juan con el MISMO vence_en y una borrada) → matriz por rol bajo
# `set role authenticated` + `request.jwt.claims` (invoker ≡ RLS) → keyset de 2
# (+1) contra el oráculo → errores 22023/42501/anon → volumen > 1 000 (1 200
# tareas de vend1 en lotes de 500 (+1) = tabla; EXPLAIN con planificador normal)
# → retirada.
set -euo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
CRM=$(cd "$AQUI/../../.." && pwd)
M="$CRM/supabase/migrations/20260919235100_crm_tareas_pendientes_keyset.sql"
PORT=${PGPORT_BANCO:-58322}
TEMPLATE=${TEMPLATE:-conversion_inversion_base_20260919}
DB=${DB:-tareas_cursor_20260919}
export PGPASSWORD=${PGPASSWORD:-postgres}
P() { psql -h 127.0.0.1 -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1 "$@"; }
Q() { P -d "$DB" -At "$@"; }

echo "== 0. copia $DB desde $TEMPLATE"
# Las copias nacen como supabase_admin (dueño de las plantillas en el
# contenedor); el ensayo corre como postgres, con el owner/ACL de producción.
if [ "$(P -d postgres -Atc "select 1 from pg_database where datname='$DB'")" != "1" ]; then
  psql -h 127.0.0.1 -p "$PORT" -U supabase_admin -X -q -v ON_ERROR_STOP=1 -d postgres \
    -c "create database \"$DB\" template \"$TEMPLATE\""
fi
echo "== 1. estado previo"
Q -c "select 'version='||(select max(version) from supabase_migrations.schema_migrations)
  ||' sla='||(to_regprocedure('private.assert_sla_nucleo()') is not null)
  ||' postventa='||exists(select 1 from pg_policy where polrelid='crm.tareas'::regclass and polname='tareas_postventa_lectura')
  ||' md5_tareas_select='||(select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='crm.tareas'::regclass and polname='tareas_select')
  ||' instalada='||(to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is not null)"

if [ "$(Q -c "select to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is not null")" = "t" ]; then
  echo "   (ya instalada en la copia: se salta la instalación)"
else
  echo "== 2. instalación TAL CUAL, en un solo mensaje"
  P -d "$DB" -c "$(cat "$M")"
fi

echo "== 3. gate, mutantes y esquema intacto"
Q -c "select private.assert_tareas_pendientes()"
Q -c "select private.assert_tareas_pendientes_mutantes()"
Q -c "select 'gate_despues='||left(private.assert_tareas_pendientes(),2)
  ||' policies='||(select array_agg(polname order by polname) from pg_policy where polrelid='crm.tareas'::regclass)::text
  ||' md5_tareas_select='||(select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='crm.tareas'::regclass and polname='tareas_select')
  ||' rls_tareas='||(select relrowsecurity from pg_class where oid='crm.tareas'::regclass)
  ||' rls_leads='||(select relrowsecurity from pg_class where oid='crm.leads'::regclass)
  ||' puerta_definer='||(select prosecdef from pg_proc where oid='crm.tareas_pendientes_fn(integer,timestamptz,uuid)'::regprocedure)
  ||' nucleo_definer='||(select prosecdef from pg_proc where oid='private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure)
  ||' anon_exec='||has_function_privilege('anon','crm.tareas_pendientes_fn(integer,timestamptz,uuid)','EXECUTE')
  ||' usage_private='||has_schema_privilege('authenticated','private','USAGE')
  ||' leads_nombre='||has_column_privilege('authenticated','crm.leads','nombre_completo','SELECT')
  ||' indice_valido='||exists(select 1 from pg_index where indexrelid='crm.tareas_pendientes_keyset_idx'::regclass and indisvalid)"

echo "== 4. md5 de referencia (los del registrador se miden en PROD)"
Q -c "select 'puerta='||md5(pg_get_functiondef('crm.tareas_pendientes_fn(integer,timestamptz,uuid)'::regprocedure))
  ||' nucleo='||md5(pg_get_functiondef('private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure))
  ||' gate='||md5(pg_get_functiondef('private.assert_tareas_pendientes()'::regprocedure))"

echo "== 5. siembra: dos tareas de juan con el MISMO vence_en y una borrada"
JUAN=$(Q -c "select id from crm.leads where nombre_completo='JUAN PEREZ DEMO' limit 1")
VEND1=$(Q -c "select id from auth.users where email='vend1.crm@demo.avancecorp.pe'")
# Ids nuevos por corrida (las de corridas anteriores quedan canceladas, nunca se borran).
Q -c "update crm.tareas set estado='cancelada' where titulo like 'GATE TAREAS CURSOR%' and estado='pendiente'" >/dev/null
Q -c "insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por) values
  (gen_random_uuid(),'$JUAN','tarea','GATE TAREAS CURSOR EMPATE A','2027-03-01T15:00:00Z','$VEND1'),
  (gen_random_uuid(),'$JUAN','tarea','GATE TAREAS CURSOR EMPATE B','2027-03-01T15:00:00Z','$VEND1')"
Q -c "insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por, activo) values
  (gen_random_uuid(),'$JUAN','tarea','GATE TAREAS CURSOR BORRADA','2027-03-01T15:00:00Z','$VEND1', false)" \
  || echo "   (la tarea borrada no se pudo sembrar: se omite esa comprobación)"

sesion() { # $1 = email → sentencias de apertura de sesión del actor (sin salida)
  local uid; uid=$(Q -c "select id from auth.users where email='$1'")
  printf "set local role authenticated; do \$s\$ begin perform set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true); end \$s\$;" "$uid"
}

echo "== 6. matriz por rol: invoker ≡ RLS (misma sesión, misma transacción)"
for par in gerencia:gerencia.crm sup1:sup1.crm sup2:sup2.crm sup1Nested:sup-anidado.crm vend1:vend1.crm vend2:vend2.crm vend3:vend3.crm vend4:vend4.crm vendNested:vend-anidado.crm coordinador:coordinador.crm directorio:directorio.crm; do
  key=${par%%:*}; email="${par##*:}@demo.avancecorp.pe"
  Q -c "begin; $(sesion "$email")
    with rpc as (select e.it, e.n from jsonb_array_elements(crm.tareas_pendientes_fn(1000)->'items') with ordinality as e(it, n)),
         tabla as (select t.id, row_number() over (order by t.vence_en, t.id) as n from crm.tareas t
                   where t.estado='pendiente' and t.activo and (t.lead_id is not null or t.perfil_id is not null))
    select '$key rpc='||(select count(*) from rpc)||' rls='||(select count(*) from tabla)
      ||' iguales_en_orden='||((select array_agg(it->>'id' order by n) from rpc) is not distinct from (select array_agg(id::text order by n) from tabla))
      ||' forma_ok='||coalesce((select bool_and((it->>'estado')='pendiente' and (it->>'activo')::boolean and (it ? 'lead_nombre') and (it ? 'lead_etapa')) from rpc), true)
      ||' borrada_viaja='||exists(select 1 from rpc where it->>'titulo'='GATE TAREAS CURSOR BORRADA');
    rollback;"
done

echo "== 7. lead embebido (vend1 ve las sembradas con nombre y etapa de juan)"
Q -c "begin; $(sesion vend1.crm@demo.avancecorp.pe)
  select 'sembradas='||count(*)||' con_nombre='||bool_and(it->>'lead_nombre'='JUAN PEREZ DEMO')||' con_etapa='||bool_and(it->>'lead_etapa' is not null)
  from jsonb_array_elements(crm.tareas_pendientes_fn(1000)->'items') it where it->>'titulo' like 'GATE TAREAS CURSOR EMPATE%';
  rollback;"

# keyset_vs_oraculo <limite pedido> : pagina como vend1 (ventana = limite-1) y compara con el oráculo de su RLS.
keyset_vs_oraculo() {
  local LIM=$1; local VENT=$((LIM-1))
  local ORACULO; ORACULO=$(Q -c "begin; $(sesion vend1.crm@demo.avancecorp.pe)
    select string_agg(id::text, ',' order by vence_en, id) from crm.tareas where estado='pendiente' and activo and (lead_id is not null or perfil_id is not null); rollback;" | tail -1)
  local PAGINADO=""; local DESPUES_DE=""; local DESPUES_ID=""; local VUELTAS=0; local FILAS N VENTANA ULT
  while [ $VUELTAS -lt 200 ]; do
    VUELTAS=$((VUELTAS+1))
    FILAS=$(Q -F'|' -c "begin; $(sesion vend1.crm@demo.avancecorp.pe)
      select it->>'id', it->>'vence_en' from jsonb_array_elements(crm.tareas_pendientes_fn($LIM, nullif('$DESPUES_DE','')::timestamptz, nullif('$DESPUES_ID','')::uuid)->'items') it; rollback;" | grep '|' || true)
    N=$(printf "%s" "$FILAS" | grep -c '|' || true)
    VENTANA=$(printf "%s\n" "$FILAS" | head -$VENT)
    while IFS='|' read -r id ve; do [ -n "$id" ] && PAGINADO="${PAGINADO:+$PAGINADO,}$id"; done <<< "$VENTANA"
    if [ "$N" -le $VENT ]; then break; fi
    ULT=$(printf "%s\n" "$VENTANA" | tail -1); DESPUES_ID=${ULT%%|*}; DESPUES_DE=${ULT#*|}
  done
  local TOTAL; TOTAL=$(echo "$ORACULO" | tr ',' '\n' | grep -c . || true)
  if [ "$PAGINADO" = "$ORACULO" ]; then echo "   KEYSET OK (limite $LIM, $VUELTAS vueltas): las paginas reconstruyen el oraculo sin repetidos ni huecos ($TOTAL tareas)"; else echo "   KEYSET FALLO (limite $LIM, $VUELTAS vueltas, oraculo $TOTAL)"; fi
}

echo "== 8. keyset de 2 (+1) como vend1 contra el oráculo"
keyset_vs_oraculo 3

echo "== 9. errores esperados"
for caso in "p_limite 0|select crm.tareas_pendientes_fn(0)" "p_limite 1001|select crm.tareas_pendientes_fn(1001)" "cursor a medias (solo fecha)|select crm.tareas_pendientes_fn(10, now(), null)" "cursor a medias (solo id)|select crm.tareas_pendientes_fn(10, null, gen_random_uuid())"; do
  et=${caso%%|*}; sql=${caso#*|}
  r=$(P -d "$DB" -At -c "begin; $(sesion vend1.crm@demo.avancecorp.pe) $sql; rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
  echo "   $et → ${r:-SIN ERROR (MAL)}"
done
for par in vendInactive:vend-inactivo.crm clientBank:cliente-bancario.crm; do
  key=${par%%:*}; email="${par##*:}@demo.avancecorp.pe"
  r=$(P -d "$DB" -At -c "begin; $(sesion "$email") select crm.tareas_pendientes_fn(10); rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
  echo "   $key → ${r:-SIN ERROR (MAL)}"
done
r=$(P -d "$DB" -At -c "begin; set local role anon; select crm.tareas_pendientes_fn(10); rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
echo "   anon → ${r:-SIN ERROR (MAL)}"

echo "== 10. volumen > 1 000: 1 200 tareas de vend1, lotes de 500 (+1) = tabla"
Q -c "insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
  select gen_random_uuid(), '$JUAN', 'tarea', 'GATE TAREAS CURSOR VOLUMEN '||g,
         '2027-04-01T15:00:00Z'::timestamptz + (g % 300) * interval '1 minute', '$VEND1'
  from generate_series(1, 1200) g"
Q -c "analyze crm.tareas"
keyset_vs_oraculo 501

echo "== 11. EXPLAIN con planificador normal (vend1 y gerencia; primera pagina y cursor profundo)"
CURSOR=$(Q -F'|' -c "begin; $(sesion vend1.crm@demo.avancecorp.pe)
  select it->>'vence_en', it->>'id' from jsonb_array_elements(crm.tareas_pendientes_fn(501)->'items') with ordinality e(it, n) where n = 500; rollback;" | grep '|' | head -1)
C_DE=${CURSOR%%|*}; C_ID=${CURSOR#*|}
for u in vend1.crm gerencia.crm; do
  echo "   -- $u, primera pagina:"
  Q -c "begin; $(sesion $u@demo.avancecorp.pe)
    explain (analyze, costs off, timing off, summary off) select crm.tareas_pendientes_fn(501); rollback;" | grep -i "index\|seq scan\|sort\|rows=" | head -4
  echo "   -- $u, consulta del nucleo con cursor profundo:"
  Q -c "begin; $(sesion $u@demo.avancecorp.pe)
    explain (analyze, costs off, timing off, summary off)
    select t.id from crm.tareas t left join crm.leads l on l.id = t.lead_id
    where t.estado='pendiente' and t.activo and (t.lead_id is not null or t.perfil_id is not null)
      and (t.vence_en, t.id) > ('$C_DE'::timestamptz, '$C_ID'::uuid)
    order by t.vence_en, t.id limit 501; rollback;" | grep -i "index\|seq scan\|sort\|limit" | head -5
done

echo "== 12. retirada de las sembradas (cancelación, nunca DELETE; una cerrada no se vuelve a tocar: el trigger lo veta)"
Q -c "update crm.tareas set estado='cancelada' where titulo like 'GATE TAREAS CURSOR%' and estado='pendiente'"
echo "== FIN"
