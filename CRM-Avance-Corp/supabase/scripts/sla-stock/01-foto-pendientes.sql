-- SOLO LECTURA. Guardar el JSON íntegro en archivo privado ANTES de reconstruir.
-- Contiene exclusivamente IDs/contexto técnico; publicar sólo `resumen`.
with pendientes as materialized (
  select t.id as tarea_id,t.lead_id,l.ciclo_actual as ciclo_n,c.tarea_id as contexto_id,
    c.lead_id as contexto_lead_id,c.ciclo_n as contexto_ciclo_n
  from crm.tareas t join crm.leads l on l.id=t.lead_id
  left join crm.tarea_sla_contexto c on c.tarea_id=t.id
  where l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and t.activo and t.estado='pendiente'
), faltantes as materialized (
  select tarea_id,lead_id,ciclo_n from pendientes where contexto_id is null
)
select jsonb_build_object(
  'capturado_en',clock_timestamp(),
  'control',(select jsonb_build_object('modo',modo,'revision',revision,'primera_activacion_en',primera_activacion_en)
             from crm.sla_operacion_control where id),
  'resumen',jsonb_build_object(
    'tareas_pendientes_abiertas',(select count(*) from pendientes),
    'tareas_sin_contexto',(select count(*) from faltantes),
    'leads_sin_contexto',(select count(distinct lead_id) from faltantes),
    'contextos_incoherentes',(select count(*) from pendientes where contexto_id is not null
      and (contexto_lead_id is distinct from lead_id or contexto_ciclo_n is distinct from ciclo_n))),
  'lead_ids',coalesce((select jsonb_agg(lead_id order by lead_id) from (select distinct lead_id from faltantes) x),'[]'::jsonb),
  'tareas',coalesce((select jsonb_agg(to_jsonb(f) order by lead_id,tarea_id) from faltantes f),'[]'::jsonb)
) as foto;
