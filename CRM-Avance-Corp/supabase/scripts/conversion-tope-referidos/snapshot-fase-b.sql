-- Instantánea de lo que publican las seis funciones de la Fase B sobre el mundo determinista (mundo-fase-b.sql). Se corre ANTES y
-- DESPUÉS de la migración y se comparan las dos salidas: septiembre (sin tope) debe salir IDÉNTICO; octubre cambia solo donde
-- el tope recorta al referido. Todo se deshace.
--   psql -v ON_ERROR_STOP=1 -qAt -f snapshot-fase-b.sql > antes.txt   (y otra vez > despues.txt; luego diff)
begin;
\i mundo-fase-b.sql
select set_config('request.jwt.claim.sub', (select g::text from ana), true);

select '## ranking_conversion_origen_mes ' || m || ' ' || o.origen || ' ' || o.leads || ' ' || o.cierres || ' ' || coalesce(o.conversion_pct::text, 'null')
  from (values ('2026-09-01'::date), ('2026-10-01')) v(m),
       lateral private.ranking_conversion_origen_mes(v.m::timestamp at time zone 'America/Lima', (v.m + interval '1 month')::timestamp at time zone 'America/Lima', v.m,
         private.peso_referido_conversion(v.m)) o
  join ana on o.vendedor_id = ana.a
  order by m, o.origen;

select '## ranking_origen_live ' || m || ' ' || (select jsonb_agg(x - 'capital_pen' - 'capital_usd' order by x->>'origen') from jsonb_array_elements(
    private.ranking_origen_live(m, (select a from ana), '[]'::jsonb) -> 'filas') x)::text
  from (values ('2026-09-01'::date), ('2026-10-01')) v(m);

select '## conversion_mensual_sin_cartera_fn ' || m || ' ' || (crm.conversion_mensual_sin_cartera_fn(m) - 'generado_en')::text
  from (values ('2026-09-01'::date), ('2026-10-01')) v(m);

select '## conversion_divisor_empresa ' || m || ' ' || to_jsonb(f)::text
  from (values ('2026-09-01'::date, '2026-09-30'::date), ('2026-10-01', '2026-10-31')) v(m, h),
       lateral private.conversion_divisor_empresa(v.m, v.h) f
  where f.analista_id in (select a from ana union select b from ana)
  order by m, f.analista_id;
select '## conversion_divisor_empresa_totales ' || m || ' ' || to_jsonb(t)::text
  from (values ('2026-09-01'::date, '2026-09-30'::date), ('2026-10-01', '2026-10-31')) v(m, h),
       lateral private.conversion_divisor_empresa_totales(v.m, v.h) t order by m;
select '## conversion_divisor_coordinacion_fn ' || m || ' ' || (crm.conversion_divisor_coordinacion_fn(m) - 'generado_en')::text
  from (values ('2026-09-01'::date), ('2026-10-01')) v(m);

select '## metricas_conversiones_implementacion ' || m || ' ' ||
  (select jsonb_build_object('origenes', r -> 'origenes', 'peso_referido', r -> 'peso_referido', 'tope', r -> 'tope_referidos_pct')::text
   from (select private.metricas_conversiones_implementacion(m, least((m + interval '1 month' - interval '1 day')::date, (now() at time zone 'America/Lima')::date), null) r) q)
  from (values ('2026-09-01'::date), ('2026-10-01')) v(m);
rollback;
