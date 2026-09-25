-- Lectura equivalente a los nueve supuestos de gate-realidad.mjs.
-- No sustituye la ejecución del CLI por PostgREST ni instala F5 en producción.
begin transaction isolation level repeatable read read only;
set local timezone='America/Lima';
select set_config('gd_f5.realidad',jsonb_build_object(
 'fecha',statement_timestamp(),
 'metas_publicadas',(select count(*) from crm.meta_periodos),
 'roster_metas_completo',(select count(*) from crm.equipo e where private.rol_crm(e.perfil_id)='vendedor' and private.rol_crm(e.supervisor_id) is distinct from 'supervisor'),
 'leads_en_cartera',(select count(*) from crm.leads where activo),
 'actividades',(select count(*) from crm.actividades),
 'tareas_pendientes',(select count(*) from crm.tareas where estado='pendiente' and activo),
 'equipo_operativo',(select count(*) from crm.equipo where activo and rol_crm in ('vendedor','supervisor')),
 'clientes_con_domicilio_legal',(select count(*) from public.perfiles where rol='cliente' and activo and domicilio is null),
 'metas_bajo_el_sello',(select count(*) from crm.meta_periodos m left join crm.periodos_cerrados c on c.periodo=m.periodo where m.periodo<=(select max(periodo) from crm.periodos_cerrados) and (c.periodo is null or m.revision>c.meta_revision))
)::text,true);
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
select jsonb_build_object('realidad',current_setting('gd_f5.realidad')::jsonb,'conversion_un_solo_nucleo',crm.alarma_conversion_fn()) as auditoria;
rollback;
