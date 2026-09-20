#!/usr/bin/env bash
# Ensayo LOCAL de 20260920014500 (actividad reciente) sobre una copia del
# contenedor del banco (`supabase_db_avancecorp-f5-bank`, puerto 58322), creada
# desde una base a paridad 20260917235656 CON el mundo SLA. La copia no tiene la
# Fase 1 (`nombre_de_autor`, que esta migración exige), así que se instala
# antes la 20260919185718 TAL CUAL (ya está en producción) y después esta, las
# dos en un solo mensaje como producción (`psql -c`), sin divergencias.
#
#   TEMPLATE=conversion_inversion_base_20260919 DB=sin_topes_f3_20260920 \
#     bash supabase/scripts/actividades-recientes/ensayar-local.sh
#
# Pasos: copia → estado previo → Fase 1 → Fase 3 → gate + mutantes + esquema
# intacto → md5 (referencia) → matriz por rol bajo `set role authenticated` +
# `request.jwt.claims` (invoker ≡ RLS, orden y lead/autor) → errores
# 22023/42501/anon → EXPLAIN.
set -euo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
CRM=$(cd "$AQUI/../../.." && pwd)
M1="$CRM/supabase/migrations/20260919185718_crm_actividades_de_lead.sql"
M3="$CRM/supabase/migrations/20260920014500_crm_actividades_recientes.sql"
PORT=${PGPORT_BANCO:-58322}
TEMPLATE=${TEMPLATE:-conversion_inversion_base_20260919}
DB=${DB:-sin_topes_f3_20260920}
export PGPASSWORD=${PGPASSWORD:-postgres}
P() { psql -h 127.0.0.1 -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1 "$@"; }
Q() { P -d "$DB" -At "$@"; }

echo "== 0. copia $DB desde $TEMPLATE"
if [ "$(P -d postgres -Atc "select 1 from pg_database where datname='$DB'")" != "1" ]; then
  psql -h 127.0.0.1 -p "$PORT" -U supabase_admin -X -q -v ON_ERROR_STOP=1 -d postgres \
    -c "create database \"$DB\" template \"$TEMPLATE\""
fi
echo "== 1. estado previo"
Q -c "select 'version='||(select max(version) from supabase_migrations.schema_migrations)
  ||' sla='||(to_regprocedure('private.assert_sla_nucleo()') is not null)
  ||' fase1='||(to_regprocedure('private.nombre_de_autor(uuid)') is not null)
  ||' md5_actividades_select='||(select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='crm.actividades'::regclass and polname='actividades_select')
  ||' instalada='||(to_regprocedure('crm.actividades_recientes_fn(integer)') is not null)"

if [ "$(Q -c "select to_regprocedure('private.nombre_de_autor(uuid)') is not null")" != "t" ]; then
  echo "== 2a. Fase 1 (20260919185718) TAL CUAL, en un solo mensaje"
  P -d "$DB" -c "$(cat "$M1")"
fi
if [ "$(Q -c "select to_regprocedure('crm.actividades_recientes_fn(integer)') is not null")" = "t" ]; then
  echo "   (Fase 3 ya instalada en la copia: se salta la instalación)"
else
  echo "== 2b. Fase 3 (20260920014500) TAL CUAL, en un solo mensaje"
  P -d "$DB" -c "$(cat "$M3")"
fi

echo "== 3. gate, mutantes y esquema intacto"
Q -c "select private.assert_actividades_recientes()"
Q -c "select private.assert_actividades_recientes_mutantes()"
Q -c "select 'gate_despues='||left(private.assert_actividades_recientes(),2)
  ||' policies='||(select array_agg(polname order by polname) from pg_policy where polrelid='crm.actividades'::regclass)::text
  ||' md5_actividades_select='||(select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='crm.actividades'::regclass and polname='actividades_select')
  ||' rls_actividades='||(select relrowsecurity from pg_class where oid='crm.actividades'::regclass)
  ||' rls_leads='||(select relrowsecurity from pg_class where oid='crm.leads'::regclass)
  ||' puerta_definer='||(select prosecdef from pg_proc where oid='crm.actividades_recientes_fn(integer)'::regprocedure)
  ||' nucleo_definer='||(select prosecdef from pg_proc where oid='private.actividades_recientes_core(integer)'::regprocedure)
  ||' anon_exec='||has_function_privilege('anon','crm.actividades_recientes_fn(integer)','EXECUTE')
  ||' usage_private='||has_schema_privilege('authenticated','private','USAGE')
  ||' autor_exec='||has_function_privilege('authenticated','private.nombre_de_autor(uuid)','EXECUTE')
  ||' gate_fase1='||left(private.assert_actividades_de_lead(),2)"

echo "== 4. md5 de referencia (los del registrador se miden en PROD)"
Q -c "select 'puerta='||md5(pg_get_functiondef('crm.actividades_recientes_fn(integer)'::regprocedure))
  ||' nucleo='||md5(pg_get_functiondef('private.actividades_recientes_core(integer)'::regprocedure))
  ||' gate='||md5(pg_get_functiondef('private.assert_actividades_recientes()'::regprocedure))"

sesion() { # $1 = email → sentencias de apertura de sesión del actor (sin salida)
  local uid; uid=$(Q -c "select id from auth.users where email='$1'")
  printf "set local role authenticated; do \$s\$ begin perform set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true); end \$s\$;" "$uid"
}

echo "== 5. matriz por rol: invoker ≡ RLS (las 8 mas recientes, mismo orden, lead y autor)"
for par in gerencia:gerencia.crm sup1:sup1.crm sup2:sup2.crm sup1Nested:sup-anidado.crm vend1:vend1.crm vend2:vend2.crm vend3:vend3.crm vend4:vend4.crm vendNested:vend-anidado.crm coordinador:coordinador.crm directorio:directorio.crm; do
  key=${par%%:*}; email="${par##*:}@demo.avancecorp.pe"
  Q -c "begin; $(sesion "$email")
    with rpc as (select e.it, e.n from jsonb_array_elements(crm.actividades_recientes_fn(8)->'items') with ordinality as e(it, n)),
         tabla as (select a.id, row_number() over (order by a.creado_en desc, a.id asc) as n from crm.actividades a order by a.creado_en desc, a.id asc limit 8)
    select '$key rpc='||(select count(*) from rpc)||' rls='||(select count(*) from tabla)
      ||' iguales_en_orden='||((select array_agg(it->>'id' order by n) from rpc) is not distinct from (select array_agg(id::text order by n) from tabla))
      ||' con_autor='||coalesce((select bool_and(length(it->>'autor_nombre') > 0) from rpc), true)
      ||' con_lead='||coalesce((select bool_and(it->>'lead_nombre' is not null) from rpc), true)
      ||' claves_ok='||coalesce((select bool_and(it ?& array['id','lead_id','lead_nombre','tipo','detalle','autor_nombre','creado_en']) from rpc), true);
    rollback;"
done

echo "== 6. errores esperados"
for caso in "p_limite 0|select crm.actividades_recientes_fn(0)" "p_limite 51|select crm.actividades_recientes_fn(51)"; do
  et=${caso%%|*}; sql=${caso#*|}
  r=$(P -d "$DB" -At -c "begin; $(sesion vend1.crm@demo.avancecorp.pe) $sql; rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
  echo "   $et → ${r:-SIN ERROR (MAL)}"
done
for par in vendInactive:vend-inactivo.crm clientBank:cliente-bancario.crm; do
  key=${par%%:*}; email="${par##*:}@demo.avancecorp.pe"
  r=$(P -d "$DB" -At -c "begin; $(sesion "$email") select crm.actividades_recientes_fn(8); rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
  echo "   $key → ${r:-SIN ERROR (MAL)}"
done
r=$(P -d "$DB" -At -c "begin; set local role anon; select crm.actividades_recientes_fn(8); rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
echo "   anon → ${r:-SIN ERROR (MAL)}"

echo "== 7. EXPLAIN de la consulta del nucleo como vend1 y gerencia (planificador normal)"
for u in vend1.crm gerencia.crm; do
  echo "   -- $u:"
  Q -c "begin; $(sesion $u@demo.avancecorp.pe)
    explain (analyze, costs off, timing off, summary off)
    select a.id, l.nombre_completo from crm.actividades a left join crm.leads l on l.id = a.lead_id
    order by a.creado_en desc, a.id asc limit 8; rollback;" | grep -i "index\|seq scan\|sort\|limit" | head -4
done
echo "== FIN"
