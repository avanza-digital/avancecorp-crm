-- READ ONLY. Misma evaluación sin contexto nuevo (todavía no instalado).
-- Solo devuelve agregados. No modifica ni clasifica persistentemente leads.
begin transaction read only; set local statement_timeout='20s'; select jsonb_object_agg(estado,n) as censo from (select resultado->>'estado' as estado,count(*) n from (with leads as materialized (
  select l.id,l.ciclo_actual,l.etapa,l.vendedor_id,l.activo,c.iniciado_en,
    (select count(*)=1 and min(h.ciclo_n)=1 from crm.lead_sla_ciclos h where h.lead_id=l.id) unico_ciclo
  from crm.leads l left join crm.lead_sla_ciclos c on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  where l.activo and l.etapa not in ('convertido','descartado')
), actividades as materialized (
  select a.id,a.lead_id,a.tipo,a.metadata,a.creado_en,x.registrado_en,x.gesto_oficina_id,x.oficina_tarea_id,
    case when x.actividad_id is not null then x.ciclo_n=l.ciclo_actual
      when l.unico_ciclo and l.ciclo_actual=1 then true
      when exists(select 1 from crm.tarea_sla_contexto tc where tc.tarea_id::text=a.metadata->>'tarea_id'
          and tc.lead_id=a.lead_id and tc.ciclo_n=l.ciclo_actual) then true
      when exists(select 1 from crm.lead_sla_etapa_ajustes aj join crm.lead_sla_etapas e on e.id=aj.etapa_sla_id
          where aj.origen_actividad_id=a.id and e.lead_id=a.lead_id and e.ciclo_n=l.ciclo_actual) then true
      else false end del_ciclo
  from leads l join crm.actividades a on a.lead_id=l.id
    left join (select null::uuid actividad_id,null::integer ciclo_n,null::timestamptz registrado_en,null::uuid gesto_oficina_id,null::uuid oficina_tarea_id where false) x on x.actividad_id=a.id
  where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
    and not (a.metadata ? 'deshecho_en')
), citas as materialized (
  select t.id,t.lead_id,t.estado,t.vence_en,t.resultado_reunion,t.resultado_actividad_id,
    tc.ciclo_n=l.ciclo_actual del_ciclo,
    a.id asistencia_id,
    -- La evidencia nueva tiene hora de recepción real; no confía en backdates.
    -- Historia sin sello se conserva como ambigua para la política de antiguos.
    a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en asistencia_valida,
    a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en
      and t.resultado_reunion in ('interesado','seguimiento','propuesta','inicia_registro','no_interesado') entrevista_valida
  from leads l join crm.tareas t on t.lead_id=l.id
    left join crm.tarea_sla_contexto tc on tc.tarea_id=t.id and tc.lead_id=l.id
    left join actividades a on a.id=t.resultado_actividad_id and a.lead_id=l.id and a.del_ciclo
      and a.tipo='reunion_realizada' and a.metadata->>'tarea_id'=t.id::text and t.estado='completada'
  where t.tipo='reunion' and t.activo and t.estado in ('pendiente','completada')
), hechos as (
  select l.*,
    (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo order by a.registrado_en nulls last,a.id limit 1) gestion_id,
    (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo
      and (a.tipo in ('llamada_realizada','whatsapp_recibido') or a.gesto_oficina_id is not null)
      order by a.registrado_en nulls last,a.id limit 1) contacto_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo
      order by t.entrevista_valida desc nulls last,t.vence_en,t.id limit 1) cita_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.entrevista_valida
      order by t.vence_en,t.id limit 1) entrevista_tarea_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.asistencia_valida
      order by t.entrevista_valida desc,t.vence_en,t.id limit 1) asistencia_tarea_id,
    (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.estado='pendiente'
      order by t.vence_en,t.id limit 1) pendiente_tarea_id,
    exists(select 1 from citas t where t.lead_id=l.id and
      (t.del_ciclo is null or (t.del_ciclo and t.estado='completada' and t.asistencia_id is not null
         and exists(select 1 from actividades a where a.id=t.asistencia_id and a.registrado_en is null)))) historico_ambiguo
  from leads l
)
select h.id,jsonb_build_object(
  'lead_id',h.id,'ciclo_n',h.ciclo_actual,'ciclo_inicio',h.iniciado_en,
  'aplica',h.activo and h.etapa not in ('convertido','descartado'),
  'estado',case when h.entrevista_tarea_id is not null then 'completo'
    when h.iniciado_en is null or h.historico_ambiguo then 'ambiguo' else 'incompleto' end,
  'habilita_conversion',h.entrevista_tarea_id is not null,
  'pasos',jsonb_build_object('gestionado',h.gestion_id is not null,'contactado',h.contacto_id is not null,
    'cita_agendada',h.cita_id is not null,'asistencia',h.asistencia_tarea_id is not null,'entrevista',h.entrevista_tarea_id is not null),
  'evidencias',jsonb_build_object('gestion_id',h.gestion_id,'contacto_id',h.contacto_id,'cita_id',h.cita_id,
    'entrevista_tarea_id',h.entrevista_tarea_id,
    'asistencia_tarea_id',h.asistencia_tarea_id,
    'asistencia_id',(select t.asistencia_id from citas t where t.id=h.asistencia_tarea_id)),
  'pendiente',case when h.entrevista_tarea_id is not null then 'listo'
    when h.vendedor_id is null then 'asignar_analista'
    when h.pendiente_tarea_id is not null then case when
      (select t.vence_en>clock_timestamp() from citas t where t.id=h.pendiente_tarea_id) then 'esperar_cita' else 'cerrar_entrevista' end
    when h.historico_ambiguo or h.iniciado_en is null then 'revisar_historial'
    when h.asistencia_tarea_id is not null then 'revisar_entrevista' else 'agendar_cita' end,
  'tarea_pendiente_id',h.pendiente_tarea_id,
  'cita_pendiente_en',(select t.vence_en from citas t where t.id=h.pendiente_tarea_id)
)
from hechos h) evaluado(lead_id,resultado) group by 1) contado; rollback;
