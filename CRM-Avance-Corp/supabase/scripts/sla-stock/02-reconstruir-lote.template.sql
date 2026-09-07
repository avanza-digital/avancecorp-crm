-- ESCRITURA EXPLÍCITA. Ejecutar sólo bajo modo legado, después de N2 y antes de R4.
-- Sustituir __LEAD_IDS_JSON__ por JSON de hasta200 UUID de la foto privada.
-- Una transacción por lote. La salida contiene únicamente conteos agregados.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
with lote as materialized (
  select array(select jsonb_array_elements_text('__LEAD_IDS_JSON__'::jsonb)::uuid) as ids
), resultado as materialized (
  select r.* from lote l cross join lateral private.sla_reconstruir_contextos_lote(l.ids) r
), agregado as (
  select resultado,count(*) as tareas from resultado group by resultado
)
select jsonb_build_object(
  'leads_solicitados',(select cardinality(ids) from lote),
  'tareas_evaluadas',(select count(*) from resultado),
  'resultados',coalesce((select jsonb_object_agg(resultado,tareas) from agregado),'{}'::jsonb)
) as lote;
commit;
