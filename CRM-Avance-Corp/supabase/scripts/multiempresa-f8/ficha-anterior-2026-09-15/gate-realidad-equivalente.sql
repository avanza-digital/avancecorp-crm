begin read only;
with equipo_vigente as (
  select e.perfil_id,e.rol_crm,e.supervisor_id
  from crm.equipo e join public.perfiles p on p.id=e.perfil_id
  where e.activo and p.activo and (p.rol<>'superadmin' or e.rol_crm='gerencia')
), medidas as (
  select 'metas_publicadas' clave,count(*)::bigint valor from crm.meta_periodos
  union all select 'roster_metas_completo',count(*) from equipo_vigente e
    where e.rol_crm='vendedor' and not exists (select 1 from equipo_vigente s where s.perfil_id=e.supervisor_id and s.rol_crm='supervisor')
  union all select 'leads_en_cartera',count(*) from crm.leads where activo
  union all select 'actividades',count(*) from crm.actividades
  union all select 'tareas_pendientes',count(*) from crm.tareas where estado='pendiente' and activo
  union all select 'equipo_operativo',count(*) from crm.equipo where activo and rol_crm in ('vendedor','supervisor')
  union all select 'clientes_con_domicilio_legal',count(*) from public.perfiles where rol='cliente' and activo and domicilio is null
  union all select 'metas_bajo_el_sello',count(*) from crm.meta_periodos m
    left join crm.periodos_cerrados c on c.periodo=m.periodo
    where m.periodo <= (select max(periodo) from crm.periodos_cerrados) and (c.periodo is null or m.revision>c.meta_revision)
)
select clave,valor,case clave
when 'metas_publicadas' then valor=0
when 'roster_metas_completo' then valor>0
when 'leads_en_cartera' then valor<5
when 'actividades' then valor=0
when 'tareas_pendientes' then valor=0
when 'equipo_operativo' then valor<2
else valor>0 end as diverge
from medidas order by clave;
rollback;
