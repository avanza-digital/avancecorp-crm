begin transaction read only;
set local statement_timeout = '90s';
set local lock_timeout = '5s';
with miembros as materialized (
  select * from crm.equipo where activo
), vigentes as materialized (
  select m.* from miembros m join public.perfiles p on p.id=m.perfil_id
  where p.activo and (p.rol is distinct from 'superadmin' or m.rol_crm='gerencia')
), conteos as (
  select
    (select count(*) from crm.meta_periodos) as metas_publicadas,
    (select count(*) from vigentes v where v.rol_crm='vendedor'
      and not exists(select 1 from vigentes s where s.perfil_id=v.supervisor_id and s.rol_crm='supervisor')) as roster_metas_completo,
    (select count(*) from crm.leads where activo) as leads_en_cartera,
    (select count(*) from crm.actividades) as actividades,
    (select count(*) from crm.tareas where estado='pendiente' and activo) as tareas_pendientes,
    (select count(*) from crm.equipo where activo and rol_crm in ('vendedor','supervisor')) as equipo_operativo,
    (select count(*) from public.perfiles where rol='cliente' and activo and domicilio is null) as clientes_con_domicilio_legal,
    (select count(*) from crm.meta_periodos m where m.periodo <= (select max(periodo) from crm.periodos_cerrados)
      and not exists(select 1 from crm.periodos_cerrados c where c.periodo=m.periodo and m.revision<=c.meta_revision)) as metas_bajo_el_sello
)
select now() as observado_en, to_jsonb(conteos) as valores,
  crm.alarma_conversion_fn() as conversion_un_solo_nucleo,
  current_setting('transaction_read_only') as solo_lectura
from conteos;
rollback;
