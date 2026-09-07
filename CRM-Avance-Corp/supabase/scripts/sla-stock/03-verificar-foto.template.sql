-- SOLO LECTURA. Sustituir __FOTO_JSON__ por la FOTO ORIGINAL, nunca por otra nueva.
-- Clasifica cada tarea original una vez y cuenta nuevos faltantes por separado.
with original as materialized (
  select * from jsonb_to_recordset('__FOTO_JSON__'::jsonb->'tareas')
    as f(tarea_id uuid,lead_id uuid,ciclo_n integer)
), comparacion as materialized (
  select o.tarea_id,case
    when t.id is null then 'tarea_ya_no_existe'
    when t.lead_id is distinct from o.lead_id then 'tarea_cambio_de_lead'
    when l.id is null then 'lead_ya_no_existe'
    when not (t.activo and t.estado='pendiente' and l.activo
      and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')) then 'salio_del_stock_pendiente'
    when l.ciclo_actual is distinct from o.ciclo_n then 'cambio_de_ciclo'
    when c.tarea_id is null then 'pendiente_sin_contexto'
    when c.lead_id is distinct from o.lead_id or c.ciclo_n is distinct from o.ciclo_n then 'contexto_incoherente'
    when c.fuente='reconstruido' then 'contexto_reconstruido'
    else 'contexto_evento_concurrente' end as resultado
  from original o left join crm.tareas t on t.id=o.tarea_id
  left join crm.leads l on l.id=t.lead_id
  left join crm.tarea_sla_contexto c on c.tarea_id=o.tarea_id
), actual as materialized (
  select t.id as tarea_id,c.tarea_id as contexto_id,
    c.lead_id is distinct from t.lead_id or c.ciclo_n is distinct from l.ciclo_actual as incoherente
  from crm.tareas t join crm.leads l on l.id=t.lead_id
  left join crm.tarea_sla_contexto c on c.tarea_id=t.id
  where l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and t.activo and t.estado='pendiente'
), agregado as (
  select resultado,count(*) as tareas from comparacion group by resultado
)
select jsonb_build_object(
  'verificado_en',clock_timestamp(),
  'original_tareas',(select count(*) from original),
  'original_clasificadas',(select count(*) from comparacion),
  'original_resultados',coalesce((select jsonb_object_agg(resultado,tareas) from agregado),'{}'::jsonb),
  'actual_pendientes_sin_contexto',(select count(*) from actual where contexto_id is null),
  'actual_contextos_incoherentes',(select count(*) from actual where contexto_id is not null and incoherente),
  'nuevos_pendientes_sin_contexto',(select count(*) from actual a where a.contexto_id is null
    and not exists(select 1 from original o where o.tarea_id=a.tarea_id))
) as verificacion;
