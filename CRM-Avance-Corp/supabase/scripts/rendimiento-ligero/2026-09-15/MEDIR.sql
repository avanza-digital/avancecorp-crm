-- Plantilla del método usado. Ejecutar con psql y parámetros actor_uuid/persona_uuid.
-- Requiere conexión administrativa autorizada. No equivale a login JWT/HTTP.
-- Ejemplo: psql <conexión administrada> -v actor_uuid=<uuid> -v persona_uuid=<uuid> -f MEDIR.sql
-- Sin claves, UUID reales, clientes ni importes en este archivo.
-- Una ficha por transacción: puede adquirir su bloqueo operativo hasta ROLLBACK.
-- lock_timeout protege esta consulta al adquirir locks, no a otros que esperen.
\set ON_ERROR_STOP on
begin isolation level read committed;
set local statement_timeout = '8s';
set local lock_timeout = '1s';
set local idle_in_transaction_session_timeout = '10s';
set local application_name = 'avancecorp_perf_ligero';
select set_config('request.jwt.claims',
  jsonb_build_object('sub', :'actor_uuid', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', :'actor_uuid', true);
select set_config('avancecorp_perf.persona', :'persona_uuid', true);
set local role authenticated;

with inicio as materialized (
  select clock_timestamp() as t0
), lectura as materialized (
  select crm.inversionista_ficha_fn(
    current_setting('avancecorp_perf.persona')::uuid, 1, 1
  ) as dato, t0 from inicio
), fin as materialized (
  select dato, t0, clock_timestamp() as t1 from lectura
)
select round((extract(epoch from t1-t0)*1000)::numeric,3) as tiempo_sql_ms,
  octet_length(dato::text) as bytes_json,
  dato is not null as presente,
  dato->>'inversiones_total' as inversiones_total
from fin;
rollback;
