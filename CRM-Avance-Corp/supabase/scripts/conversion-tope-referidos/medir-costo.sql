-- Costo del núcleo con y sin tope, con 6.000 cierres de octubre repartidos entre 60 analistas (todo se deshace).
--   psql -v ON_ERROR_STOP=1 -f medir-costo.sql      (desde esta carpeta; carga anterior-episodios.sql)
begin;
set local session_replication_role = replica;
set local search_path = '';
\i /tmp/anterior-episodios.sql
create or replace function private.conversion_exclusion_fuente(p_tipo text, p_id uuid) returns text
  language sql stable set search_path = '' as $$ select 'elegible'::text $$;
create temp table an as select ('a0000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid id from generate_series(1, 60) g;
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, creado_en)
  select ('11111111-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'Costo ' || g, '9' || lpad(g::text, 8, '0'),
         case when g % 8 = 0 then 'referido' when g % 2 = 0 then 'formulario' else 'landing' end, 1000, '2026-08-20'::timestamptz
    from generate_series(1, 6000) g;
insert into crm.conversion_acreditaciones (lead_id, episodio_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial, confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, politica_desde, motivo)
  select l.id, gen_random_uuid(), (select id from an offset (g % 60)::int limit 1), l.origen, 'contrato', gen_random_uuid(), date '2026-10-01' + (g % 6)::int,
         '2026-10-03'::timestamptz, '2026-10-03'::timestamptz, '2026-10-03'::timestamptz, '2026-10-01', private.conversion_plazo_hasta('2026-10-01'), 'acreditada', '2026-09-01', 'costo'
    from (select l.id, l.origen, row_number() over () g from crm.leads l where l.nombre_completo like 'Costo %') l;
analyze crm.conversion_acreditaciones; analyze crm.leads;
do $$ declare t0 timestamptz; n int; a uuid := 'a0000000-0000-4000-8000-000000000007'; i int; res text := ''; begin
  for i in 1..3 loop
    t0 := clock_timestamp(); select count(*) into n from pg_temp.conversion_episodios_anterior('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1);
    res := res || format('anterior mes global %s ms (%s filas) | ', round(extract(milliseconds from clock_timestamp() - t0)::numeric), n);
    t0 := clock_timestamp(); select count(*) into n from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1);
    res := res || format('nueva mes global %s ms (%s) | ', round(extract(milliseconds from clock_timestamp() - t0)::numeric), n);
    t0 := clock_timestamp(); select count(*) into n from pg_temp.conversion_episodios_anterior('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', false, array[a], 1);
    res := res || format('anterior un analista %s ms | ', round(extract(milliseconds from clock_timestamp() - t0)::numeric));
    t0 := clock_timestamp(); select count(*) into n from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', false, array[a], 1);
    res := res || format('nueva un analista %s ms', round(extract(milliseconds from clock_timestamp() - t0)::numeric));
    t0 := clock_timestamp(); select count(*) into n from pg_temp.conversion_episodios_anterior('1900-01-01'::timestamptz, '2100-01-01'::timestamptz, null::date, true, '{}', 1);
    res := res || format(' | historia completa anterior %s ms', round(extract(milliseconds from clock_timestamp() - t0)::numeric));
    t0 := clock_timestamp(); select count(*) into n from private.conversion_episodios('1900-01-01'::timestamptz, '2100-01-01'::timestamptz, null::date, true, '{}', 1);
    res := res || format(' | historia completa nueva %s ms', round(extract(milliseconds from clock_timestamp() - t0)::numeric));
    raise notice 'vuelta %: %', i, res; res := '';
  end loop;
end $$;
rollback;
