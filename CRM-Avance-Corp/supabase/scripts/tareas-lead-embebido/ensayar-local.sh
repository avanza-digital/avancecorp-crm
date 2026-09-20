#!/usr/bin/env bash
# Ensayo LOCAL de 20260920045202 (lead embebido completo en las tareas por
# cursor, Fase 4b «sin topes») sobre una copia del contenedor del banco
# (`supabase_db_avancecorp-f5-bank`, puerto 58322), creada desde una base a
# paridad 20260917235656 CON el mundo SLA. La copia no trae la Fase 2, así que
# el guion instala ANTES 20260919235100 tal cual (ya en producción) y DESPUÉS
# esta migración; las dos en un solo mensaje como producción (`psql -c`).
#
#   TEMPLATE=conversion_inversion_base_20260919 DB=lead_embebido_20260920 \
#     bash supabase/scripts/tareas-lead-embebido/ensayar-local.sh
#
# Pasos: copia → Fase 2 → estado previo → instalación → gate + los 18 mutantes
# (los 17 de la Fase 2 con el cuerpo nuevo + el de las columnas nuevas) + esquema intacto →
# md5 (solo de referencia) → matriz por rol (invoker ≡ RLS, forma con las 7
# claves del lead: 10) → valores embebidos = crm.leads bajo la MISMA sesión
# (vend1 y gerencia) → tarea re-apuntada a vend1 con lead NO visible → claves nulas → errores
# 22023/42501/anon → EXPLAIN → retirada.
set -euo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
CRM=$(cd "$AQUI/../../.." && pwd)
F2="$CRM/supabase/migrations/20260919235100_crm_tareas_pendientes_keyset.sql"
M="$CRM/supabase/migrations/20260920045202_crm_tareas_pendientes_lead_embebido.sql"
PORT=${PGPORT_BANCO:-58322}
TEMPLATE=${TEMPLATE:-conversion_inversion_base_20260919}
DB=${DB:-lead_embebido_20260920}
export PGPASSWORD=${PGPASSWORD:-postgres}
P() { psql -h 127.0.0.1 -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1 "$@"; }
Q() { P -d "$DB" -At "$@"; }

echo "== 0. copia $DB desde $TEMPLATE"
if [ "$(P -d postgres -Atc "select 1 from pg_database where datname='$DB'")" != "1" ]; then
  psql -h 127.0.0.1 -p "$PORT" -U supabase_admin -X -q -v ON_ERROR_STOP=1 -d postgres \
    -c "create database \"$DB\" template \"$TEMPLATE\""
fi
if [ "$(Q -c "select to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is not null")" != "t" ]; then
  echo "== 0b. Fase 2 (20260919235100) TAL CUAL, en un solo mensaje"
  P -d "$DB" -c "$(cat "$F2")"
fi
echo "== 1. estado previo"
Q -c "select 'version='||(select max(version) from supabase_migrations.schema_migrations)
  ||' sla='||(to_regprocedure('private.assert_sla_nucleo()') is not null)
  ||' md5_nucleo_f2='||md5(pg_get_functiondef('private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure))
  ||' gate='||left(private.assert_tareas_pendientes(),2)
  ||' claves_lead_antes='||(select count(*) from jsonb_object_keys(coalesce(private.tareas_pendientes_core(1,null,null)->'items'->0,'{}'::jsonb)) k where k like 'lead_%')"

if [ "$(Q -c "select (private.tareas_pendientes_core(1,null,null)->'items'->0) ? 'lead_telefono_alternativo'")" = "t" ]; then
  echo "   (ya instalada en la copia: se salta la instalación)"
else
  echo "== 2. instalación TAL CUAL, en un solo mensaje"
  P -d "$DB" -c "$(cat "$M")"
fi

echo "== 3. gate, los 17 mutantes de la Fase 2 + el de las columnas nuevas, y esquema intacto"
Q -c "select private.assert_tareas_pendientes()"
Q -c "select private.assert_tareas_pendientes_mutantes()"
Q -c "select 'gate_despues='||left(private.assert_tareas_pendientes(),2)
  ||' base='||left(private.assert_tareas_pendientes_base(),2)
  ||' md5_tareas_select='||(select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='crm.tareas'::regclass and polname='tareas_select')
  ||' rls_tareas='||(select relrowsecurity from pg_class where oid='crm.tareas'::regclass)
  ||' rls_leads='||(select relrowsecurity from pg_class where oid='crm.leads'::regclass)
  ||' nucleo_definer='||(select prosecdef from pg_proc where oid='private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure)
  ||' nucleo_owner='||(select pg_get_userbyid(proowner) from pg_proc where oid='private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure)
  ||' nucleo_acl='||(select proacl::text from pg_proc where oid='private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure)
  ||' claves_lead='||(select count(*) from jsonb_object_keys(coalesce(private.tareas_pendientes_core(1,null,null)->'items'->0,'{}'::jsonb)) k where k like 'lead_%')"

echo "== 4. md5 de referencia (los del registrador se miden en PROD)"
Q -c "select 'puerta='||md5(pg_get_functiondef('crm.tareas_pendientes_fn(integer,timestamptz,uuid)'::regprocedure))
  ||' nucleo='||md5(pg_get_functiondef('private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure))
  ||' gate='||md5(pg_get_functiondef('private.assert_tareas_pendientes()'::regprocedure))"

sesion() { # $1 = email → sentencias de apertura de sesión del actor (sin salida)
  local uid; uid=$(Q -c "select id from auth.users where email='$1'")
  printf "set local role authenticated; do \$s\$ begin perform set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true); end \$s\$;" "$uid"
}

echo "== 5. siembra: una tarea de juan (vend1) para el contraste de valores"
JUAN=$(Q -c "select id from crm.leads where nombre_completo='JUAN PEREZ DEMO' limit 1")
VEND1=$(Q -c "select id from auth.users where email='vend1.crm@demo.avancecorp.pe'")
Q -c "update crm.tareas set estado='cancelada' where titulo like 'GATE LEAD EMBEBIDO%' and estado='pendiente'" >/dev/null
Q -c "insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por) values
  (gen_random_uuid(),'$JUAN','tarea','GATE LEAD EMBEBIDO JUAN','2027-04-01T15:00:00Z','$VEND1')"

echo "== 6. matriz por rol: invoker ≡ RLS y forma con las 7 claves del lead"
for par in gerencia:gerencia.crm sup1:sup1.crm sup2:sup2.crm sup1Nested:sup-anidado.crm vend1:vend1.crm vend2:vend2.crm vend3:vend3.crm vend4:vend4.crm vendNested:vend-anidado.crm coordinador:coordinador.crm directorio:directorio.crm; do
  key=${par%%:*}; email="${par##*:}@demo.avancecorp.pe"
  Q -c "begin; $(sesion "$email")
    with rpc as (select e.it, e.n from jsonb_array_elements(crm.tareas_pendientes_fn(1000)->'items') with ordinality as e(it, n)),
         tabla as (select t.id, row_number() over (order by t.vence_en, t.id) as n from crm.tareas t
                   where t.estado='pendiente' and t.activo and (t.lead_id is not null or t.perfil_id is not null))
    select '$key rpc='||(select count(*) from rpc)||' rls='||(select count(*) from tabla)
      ||' iguales_en_orden='||((select array_agg(it->>'id' order by n) from rpc) is not distinct from (select array_agg(id::text order by n) from tabla))
      ||' forma_ok='||coalesce((select bool_and(it ?& array['lead_nombre','lead_etapa','lead_telefono','lead_monto_estimado','lead_moneda','lead_vendedor_id','lead_supervisor_id','lead_correo','lead_no_contactar','lead_telefono_alternativo']) from rpc), true);
    rollback;"
done

echo "== 7. valores embebidos = crm.leads bajo la MISMA sesión (vend1 y gerencia)"
for email in vend1.crm@demo.avancecorp.pe gerencia.crm@demo.avancecorp.pe; do
  Q -c "begin; $(sesion "$email")
    select '${email%%@*}: con_lead='||count(*)
      ||' iguales='||bool_and(it->>'lead_nombre' is not distinct from l.nombre_completo and it->>'lead_etapa' is not distinct from l.etapa
                       and it->>'lead_telefono' is not distinct from l.telefono
                       and (it->>'lead_monto_estimado')::numeric is not distinct from l.monto_estimado
                       and it->>'lead_moneda' is not distinct from l.moneda
                       and (it->>'lead_vendedor_id')::uuid is not distinct from l.vendedor_id
                       and (it->>'lead_supervisor_id')::uuid is not distinct from l.asignado_supervisor_id
                       and it->>'lead_correo' is not distinct from l.correo
                       and (it->>'lead_no_contactar')::boolean is not distinct from l.no_contactar
                       and it->>'lead_telefono_alternativo' is not distinct from l.telefono_alternativo)
      ||' sembrada_con_telefono='||bool_or(it->>'titulo'='GATE LEAD EMBEBIDO JUAN' and it->>'lead_telefono' is not null)
    from jsonb_array_elements(crm.tareas_pendientes_fn(1000)->'items') it
    join crm.leads l on l.id = (it->>'lead_id')::uuid;
    rollback;"
done

echo "== 8. tarea visible con lead NO visible → claves del lead nulas, la tarea viaja"
# La tenencia diverge DESPUÉS de crear la tarea (reasignación sin re-apuntar,
# re-apunte por inversionista_id…): el BEFORE INSERT copia la tenencia del lead,
# así que se siembra sobre un lead de OTRO analista y luego, como postgres (sin
# RLS), se re-apunta la tarea a vend1. vend1 la recibe con el lead en nulo; el
# dueño del lead la sigue viendo con valores (auditor-rls 20/09).
OTRO=$(Q -c "select l.id from crm.leads l join crm.equipo e on e.perfil_id = l.vendedor_id where l.vendedor_id is distinct from '$VEND1' and e.rol_crm = 'vendedor' and e.activo and l.activo limit 1")
DUENO=$(Q -c "select vendedor_id from crm.leads where id = '$OTRO'")
AJENA=$(Q -c "select gen_random_uuid()")
Q -c "insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por) values
  ('$AJENA','$OTRO','tarea','GATE LEAD EMBEBIDO AJENO','2027-04-02T15:00:00Z','$DUENO')" \
  && Q -c "update crm.tareas set vendedor_id = '$VEND1' where id = '$AJENA'" \
  && Q -c "begin; $(sesion vend1.crm@demo.avancecorp.pe)
    select 'vend1: ajena_viaja='||count(*)||' lead_nulo='||coalesce(bool_and(it->>'lead_nombre' is null and it->>'lead_telefono' is null and it->>'lead_monto_estimado' is null and it->>'lead_correo' is null and it->>'lead_vendedor_id' is null), false)
    from jsonb_array_elements(crm.tareas_pendientes_fn(1000)->'items') it where it->>'id'='$AJENA';
    rollback;" \
  && Q -c "begin; $(sesion "$(Q -c "select email from auth.users where id = '$DUENO'")")
    select 'dueno: la_ve='||count(*)||' con_valores='||coalesce(bool_and(it->>'lead_nombre' is not null and it->>'lead_telefono' is not null), false)
    from jsonb_array_elements(crm.tareas_pendientes_fn(1000)->'items') it where it->>'id'='$AJENA';
    rollback;" \
  || echo "   (no se pudo sembrar la tarea ajena: se omite esa comprobación)"

echo "== 9. errores esperados (sin cambios respecto a la Fase 2)"
for lim in 0 1001; do
  r=$(P -d "$DB" -At -c "begin; $(sesion vend1.crm@demo.avancecorp.pe) select crm.tareas_pendientes_fn($lim); rollback;" 2>&1 | grep -o "22023\|ERROR:.*" | head -1 || true)
  echo "   p_limite=$lim → $r"
done
r=$(P -d "$DB" -At -c "begin; $(sesion vend-inactivo.crm@demo.avancecorp.pe) select crm.tareas_pendientes_fn(10); rollback;" 2>&1 | grep -o "42501\|ERROR:.*" | head -1 || true)
echo "   vendInactive → $r"
r=$(P -d "$DB" -At -c "begin; set local role anon; select crm.tareas_pendientes_fn(10); rollback;" 2>&1 | grep -i "ERROR" | head -1 || true)
echo "   anon → $r"

echo "== 10. EXPLAIN (vend1 y gerencia, primera página)"
for email in vend1.crm@demo.avancecorp.pe gerencia.crm@demo.avancecorp.pe; do
  echo "   -- ${email%%@*}"
  P -d "$DB" -At -c "begin; $(sesion "$email")
    explain (analyze, buffers, format text)
    select t.id, l.nombre_completo, l.telefono, l.monto_estimado, l.moneda, l.vendedor_id, l.asignado_supervisor_id
    from crm.tareas t left join crm.leads l on l.id = t.lead_id
    where t.estado='pendiente' and t.activo and (t.lead_id is not null or t.perfil_id is not null)
    order by t.vence_en asc, t.id asc limit 501; rollback;" | grep -E "Index|Seq Scan|Execution Time|rows=" | head -6
done

echo "== 11. retirada de las sembradas (cancelación, nunca DELETE)"
Q -c "update crm.tareas set estado='cancelada' where titulo like 'GATE LEAD EMBEBIDO%' and estado='pendiente'"
echo "== FIN"
