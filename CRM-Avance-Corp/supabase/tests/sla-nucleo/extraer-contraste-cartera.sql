-- Solo lectura. Un corte MVCC y un reloj del servidor; no exporta datos de contacto.
with l as materialized (select id,('L-'||row_number() over(order by id)) as nombre_completo,activo,etapa,vendedor_id,asignado_supervisor_id,creado_en,ciclo_actual,tenencia_desde from crm.leads where activo),
equipo as materialized (select perfil_id,rol_crm,supervisor_id,activo from crm.equipo ),
sla_politicas as materialized (select id,version,vigente_desde,primera_gestion_minutos,primer_contacto_minutos from crm.sla_politicas ),
sla_politica_etapas as materialized (select id,politica_id,etapa,maximo_minutos from crm.sla_politica_etapas ),
lead_sla_ciclos as materialized (select id,lead_id,ciclo_n,politica_id,iniciado_en,primera_gestion_limite_en,primer_contacto_limite_en,primera_gestion_en,primer_contacto_en,aproximado from crm.lead_sla_ciclos where lead_id in(select id from l)),
asignaciones as materialized (select id,lead_id,ciclo_n,episodio_n,analista_id,asignado_en,finalizado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en,aproximado from crm.lead_asignaciones where lead_id in(select id from l)),
lead_asignacion_sla_hitos as materialized (select id,lead_asignacion_id,primera_gestion_en,primer_contacto_en from crm.lead_asignacion_sla_hitos where lead_asignacion_id in(select id from asignaciones)),
lead_sla_etapas as materialized (select id,lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en,finalizado_en,aproximado from crm.lead_sla_etapas where lead_id in(select id from l)),
actividades as materialized (select id,lead_id,tipo,creado_en,creado_por from crm.actividades where lead_id in(select id from l) and tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')),
tareas as materialized (select id,lead_id,perfil_id,tipo,'Tarea'::text as titulo,estado,activo,creado_en,creado_por,actualizado_en,vence_en,vendedor_id,asignado_supervisor_id,reagendada_de,reprogramaciones,resultado_actividad_id from crm.tareas where lead_id in(select id from l)),
pendientes as materialized (select * from tareas where activo and estado='pendiente'),
aud_t as materialized (
 select a.fila_id,a.usuario_id,a.ts,a.data_despues from public.audit_log a
 where a.tabla='crm.tareas' and a.operacion='INSERT' and a.fila_id in(select id::text from pendientes)
),
aud_b as materialized (
 select a.fila_id,a.ts from public.audit_log a
 where a.tabla='crm.leads' and a.operacion='UPDATE' and a.fila_id in(select lead_id::text from pendientes)
 and (a.data_despues->>'activo'='false'
   or a.data_despues->>'etapa' in ('descartado','convertido')
   or (coalesce(a.data_despues->>'vendedor_id','')='' and coalesce(a.data_despues->>'asignado_supervisor_id','')=''))
 and (a.data_antes->'activo' is distinct from a.data_despues->'activo'
   or a.data_antes->'etapa' is distinct from a.data_despues->'etapa'
   or a.data_antes->'vendedor_id' is distinct from a.data_despues->'vendedor_id'
   or a.data_antes->'asignado_supervisor_id' is distinct from a.data_despues->'asignado_supervisor_id')
),
evidencia as (
 select t.id,
 (select count(*) from aud_t a where a.fila_id=t.id::text) as insert_audit,
 exists(select 1 from aud_t a where a.fila_id=t.id::text and a.usuario_id is not null
 and a.data_despues->>'lead_id'=t.lead_id::text
 and (a.data_despues->>'creado_en')::timestamptz=t.creado_en
 and a.data_despues->>'creado_por'=a.usuario_id::text
 and abs(extract(epoch from a.ts-t.creado_en))<=60) as insert_humano,
 (select min(ts) from aud_t a where a.fila_id=t.id::text) as insert_en,
 (select count(*) from aud_b a where a.fila_id=t.lead_id::text and a.ts>=t.creado_en) as barreras,
 (t.reagendada_de is null or exists(select 1 from tareas p where p.id=t.reagendada_de and p.lead_id=t.lead_id and p.creado_en<=t.creado_en and p.estado in('reprogramada','no_show'))) as cadena_ok
 from pendientes t
)
select jsonb_build_object(
 't0',statement_timestamp(),'server_version',current_setting('server_version'),
 'v1_md5',md5(pg_get_functiondef('crm.estado_sla_leads_fn()'::regprocedure)),
 'tables',jsonb_build_object('leads',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from l x),
'equipo',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from equipo x),
'sla_politicas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from sla_politicas x),
'sla_politica_etapas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from sla_politica_etapas x),
'lead_sla_ciclos',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from lead_sla_ciclos x),
'lead_asignaciones',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from asignaciones x),
'lead_asignacion_sla_hitos',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from lead_asignacion_sla_hitos x),
'lead_sla_etapas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from lead_sla_etapas x),
'actividades',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from actividades x),
'tareas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from tareas x)),
 'vetos',(select jsonb_agg(jsonb_build_object('id',id,'vetado',private.persona_vetada(id))) from l),
 'evidencia_tareas',(select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from evidencia e),
 'censo',jsonb_build_object('leads_total',(select count(*) from crm.leads),'leads_activos',(select count(*) from l),
 'tareas_pendientes_sistema',(select count(*) from crm.tareas where activo and estado='pendiente'),
 'tareas_pendientes_sin_lead',(select count(*) from crm.tareas where activo and estado='pendiente' and lead_id is null))
) as snapshot;
