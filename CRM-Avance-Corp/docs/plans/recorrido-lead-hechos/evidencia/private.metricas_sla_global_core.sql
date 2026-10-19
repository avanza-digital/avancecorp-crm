CREATE OR REPLACE FUNCTION private.metricas_sla_global_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with
parametros as (
  select
    (p_desde::timestamp at time zone 'America/Lima') as inicio,
    ((p_hasta + 1)::timestamp at time zone 'America/Lima') as fin,
    p_ahora as ahora
),
ciclos_ledger as (
  select
    la.lead_id,
    la.ciclo_n,
    min(la.sla_global_iniciado_en) as sla_iniciado_en,
    bool_or(la.sla_global_aproximado) as aproximado,
    case
      when l.ciclo_actual = la.ciclo_n
       and l.activo = true
       and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
        then null
      else coalesce(
        max(la.resultado_en) filter (where la.resultado is not null),
        max(la.finalizado_en)
      )
    end as ciclo_finalizado_en,
    greatest(count(*) - 1, 0)::integer as reasignaciones
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  group by
    la.lead_id,
    la.ciclo_n,
    l.ciclo_actual,
    l.activo,
    l.etapa
),
ciclos_sin_episodio as (
  select
    l.id as lead_id,
    l.ciclo_actual as ciclo_n,
    l.sla_global_iniciado_en as sla_iniciado_en,
    l.sla_global_aproximado as aproximado,
    null::timestamptz as ciclo_finalizado_en,
    0::integer as reasignaciones
  from crm.leads l
  where l.activo = true
    and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and not exists (
      select 1
      from crm.lead_asignaciones la
      where la.lead_id = l.id
        and la.ciclo_n = l.ciclo_actual
    )
),
ciclos as (
  select * from ciclos_ledger
  union all
  select * from ciclos_sin_episodio
),
contactos as (
  select
    c.lead_id,
    c.ciclo_n,
    c.sla_iniciado_en,
    c.aproximado,
    c.ciclo_finalizado_en,
    c.reasignaciones,
    min(a.creado_en) as primera_gestion_en
  from ciclos c
  cross join parametros p
  left join crm.actividades a
    on a.lead_id = c.lead_id
   and a.tipo in (
     'llamada_realizada',
     'llamada_no_contestada',
     'whatsapp_enviado',
     'whatsapp_recibido',
     'reunion_realizada'
   )
   and a.creado_en >= c.sla_iniciado_en
   and (c.ciclo_finalizado_en is null or a.creado_en < c.ciclo_finalizado_en)
   and a.creado_en <= p.ahora
  group by
    c.lead_id,
    c.ciclo_n,
    c.sla_iniciado_en,
    c.aproximado,
    c.ciclo_finalizado_en,
    c.reasignaciones
),
medidas as (
  select
    c.*,
    case
      when c.primera_gestion_en is not null
        then extract(epoch from (c.primera_gestion_en - c.sla_iniciado_en)) / 60.0
      else null
    end as primera_gestion_minutos,
    (
      c.primera_gestion_en is not null
      or coalesce(c.ciclo_finalizado_en, p.ahora)
        >= c.sla_iniciado_en + interval '24 hours'
    ) as sla_evaluable,
    (
      c.primera_gestion_en is not null
      and c.primera_gestion_en <= c.sla_iniciado_en + interval '24 hours'
    ) as sla_en_24h
  from contactos c
  cross join parametros p
),
cohorte as (
  select m.*
  from medidas m
  cross join parametros p
  where m.sla_iniciado_en >= p.inicio
    and m.sla_iniciado_en < p.fin
)
select jsonb_build_object(
  'cohorte_ciclos', (select count(*) from cohorte),
  'cohorte_leads_unicos', (select count(distinct lead_id) from cohorte),
  'contactos', (select count(*) from cohorte where primera_gestion_en is not null),
  'sla_evaluables', (select count(*) from cohorte where sla_evaluable),
  'sla_en_24h', (select count(*) from cohorte where sla_en_24h),
  'primer_contacto_mediana_minutos', (
    select round((percentile_cont(0.5) within group (
      order by primera_gestion_minutos
    ))::numeric, 1)
    from cohorte
    where primera_gestion_minutos is not null
  ),
  'sin_contacto_vencidos_actuales', (
    select count(*)
    from medidas m
    cross join parametros p
    where m.ciclo_finalizado_en is null
      and m.primera_gestion_en is null
      and p.ahora >= m.sla_iniciado_en + interval '24 hours'
  ),
  'reasignaciones_cohorte', coalesce((select sum(reasignaciones) from cohorte), 0),
  'ciclos_aproximados_cohorte', (select count(*) from cohorte where aproximado)
);
$function$
