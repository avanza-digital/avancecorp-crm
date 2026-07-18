-- Distribucion de leads por capital · V1 descriptiva para Gerencia.
--
-- Una sola RPC devuelve una fotografia atomica: cartera/capacidad actuales,
-- cohorte de episodios, SLA, rangos PEN y colas por repartir. No emite ranking,
-- score ni recomendaciones. El ledger permanece sin SELECT por Data API.

begin;

create or replace function private.rango_capital_pen(p_monto numeric)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select case
    when p_monto is null or p_monto <= 0 then 'sin_monto'
    when p_monto <= 1000 then 'pen_0_1000'
    when p_monto <= 5000 then 'pen_1000_5000'
    when p_monto <= 10000 then 'pen_5000_10000'
    when p_monto <= 20000 then 'pen_10000_20000'
    when p_monto <= 50000 then 'pen_20000_50000'
    when p_monto <= 100000 then 'pen_50000_100000'
    else 'pen_mas_100000'
  end;
$function$;

create or replace function private.umbral_estancamiento(p_etapa text)
returns interval
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select case p_etapa
    when 'nuevo' then interval '24 hours'
    when 'contactado' then interval '72 hours'
    when 'reunion_agendada' then interval '72 hours'
    when 'propuesta_enviada' then interval '120 hours'
    else null
  end;
$function$;

create index if not exists lead_asignaciones_cohorte_idx
  on crm.lead_asignaciones (asignado_en);

create or replace function private.metricas_distribucion_leads_core(
  p_desde date,
  p_hasta date,
  p_ahora timestamptz
)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
with
parametros as (
  select
    (p_desde::timestamp at time zone 'America/Lima') as inicio,
    ((p_hasta + 1)::timestamp at time zone 'America/Lima') as fin,
    p_ahora as ahora
),
rangos(orden, rango_id, etiqueta, desde_exclusivo, hasta_inclusivo) as (
  values
    (1, 'pen_0_1000'::text, 'Hasta S/ 1 mil'::text, 0::numeric, 1000::numeric),
    (2, 'pen_1000_5000', 'S/ 1 mil a 5 mil', 1000::numeric, 5000::numeric),
    (3, 'pen_5000_10000', 'S/ 5 mil a 10 mil', 5000::numeric, 10000::numeric),
    (4, 'pen_10000_20000', 'S/ 10 mil a 20 mil', 10000::numeric, 20000::numeric),
    (5, 'pen_20000_50000', 'S/ 20 mil a 50 mil', 20000::numeric, 50000::numeric),
    (6, 'pen_50000_100000', 'S/ 50 mil a 100 mil', 50000::numeric, 100000::numeric),
    (7, 'pen_mas_100000', 'Mas de S/ 100 mil', 100000::numeric, null::numeric),
    (8, 'sin_monto', 'Sin monto valido', null::numeric, null::numeric)
),
episodios_relevantes as (
  select
    la.*,
    private.rango_capital_pen(la.monto_estimado) as rango_id
  from crm.lead_asignaciones la
  cross join parametros p
  where la.finalizado_en is null

  union all

  select
    la.*,
    private.rango_capital_pen(la.monto_estimado) as rango_id
  from crm.lead_asignaciones la
  cross join parametros p
  where la.finalizado_en is not null
    and la.asignado_en >= p.inicio
    and la.asignado_en < p.fin
),
contactos as (
  select
    er.id as episodio_id,
    min(a.creado_en) as primer_contacto_en,
    max(a.creado_en) as ultimo_contacto_en
  from episodios_relevantes er
  cross join parametros p
  left join crm.actividades a
    on a.lead_id = er.lead_id
   and a.creado_por = er.analista_id
   and a.tipo in (
     'llamada_realizada',
     'llamada_no_contestada',
     'whatsapp_enviado',
     'whatsapp_recibido',
     'reunion_realizada'
   )
   and a.creado_en >= er.asignado_en
   and (er.finalizado_en is null or a.creado_en < er.finalizado_en)
   and a.creado_en <= p.ahora
  group by er.id
),
episodios as (
  select
    er.*,
    c.primer_contacto_en,
    c.ultimo_contacto_en,
    case
      when c.primer_contacto_en is not null
        then extract(epoch from (c.primer_contacto_en - er.asignado_en)) / 60.0
      else null
    end as primer_contacto_minutos,
    (
      c.primer_contacto_en is not null
      or coalesce(er.finalizado_en, p.ahora) >= er.asignado_en + interval '24 hours'
    ) as sla_evaluable,
    (
      c.primer_contacto_en is not null
      and c.primer_contacto_en <= er.asignado_en + interval '24 hours'
    ) as sla_en_24h
  from episodios_relevantes er
  join contactos c on c.episodio_id = er.id
  cross join parametros p
),
cohorte as (
  select e.*
  from episodios e
  cross join parametros p
  where e.asignado_en >= p.inicio
    and e.asignado_en < p.fin
),
abiertos as (
  select e.*, l.etapa
  from episodios e
  join crm.leads l on l.id = e.lead_id
  where e.finalizado_en is null
),
equipo_base as (
  select
    e.perfil_id as analista_id,
    coalesce(nullif(trim(p.nombre_completo), ''), 'Analista sin nombre') as nombre,
    e.rol_crm as rol,
    e.supervisor_id,
    sp.nombre_completo as supervisor_nombre,
    coalesce(e.activo = true and p.activo = true, false) as activo,
    coalesce(e.activo = true and p.activo = true, false) as disponible_para_recibir,
    e.capacidad_leads_objetivo as capacidad_objetivo
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  left join public.perfiles sp on sp.id = e.supervisor_id
  where e.rol_crm in ('vendedor', 'supervisor')
    and (
      (e.rol_crm = 'vendedor' and e.activo = true and p.activo = true)
      or e.capacidad_leads_objetivo is not null
      or exists (
        select 1
        from crm.lead_asignaciones historia
        where historia.analista_id = e.perfil_id
      )
    )
),
cartera_total as (
  select
    a.analista_id,
    count(*) as carga_activa,
    count(*) filter (where a.moneda = 'PEN') as carga_pen,
    count(*) filter (where a.moneda = 'USD') as carga_usd,
    coalesce(sum(a.monto_estimado) filter (where a.moneda = 'PEN'), 0) as capital_pen,
    coalesce(sum(a.monto_estimado) filter (where a.moneda = 'USD'), 0) as capital_usd,
    count(*) filter (where a.primer_contacto_en is null) as sin_tocar_actual,
    count(*) filter (
      where private.umbral_estancamiento(a.etapa) is not null
        and p.ahora >= coalesce(a.ultimo_contacto_en, a.asignado_en)
          + private.umbral_estancamiento(a.etapa)
    ) as estancados_actual
  from abiertos a
  cross join parametros p
  group by a.analista_id
),
cartera_pen_rangos as (
  select
    a.analista_id,
    a.rango_id,
    count(*) as episodios,
    coalesce(sum(a.monto_estimado), 0) as capital
  from abiertos a
  where a.moneda = 'PEN'
  group by a.analista_id, a.rango_id
),
cohorte_pen_total as (
  select
    c.analista_id,
    count(*) as episodios_recibidos,
    count(distinct c.lead_id) as leads_unicos_recibidos,
    count(*) filter (where c.resultado = 'convertido') as convertidos,
    count(*) filter (where c.resultado = 'descartado') as descartados,
    count(*) filter (where c.resultado in ('convertido', 'descartado')) as ciclos_resueltos,
    count(distinct c.lead_id) filter (
      where c.resultado in ('convertido', 'descartado')
    ) as leads_unicos_resueltos
  from cohorte c
  where c.moneda = 'PEN'
  group by c.analista_id
),
cohorte_pen_rangos as (
  select
    c.analista_id,
    c.rango_id,
    count(*) as episodios_recibidos,
    count(distinct c.lead_id) as leads_unicos_recibidos,
    count(*) filter (where c.resultado = 'convertido') as convertidos,
    count(*) filter (where c.resultado = 'descartado') as descartados,
    count(distinct c.lead_id) filter (
      where c.resultado in ('convertido', 'descartado')
    ) as leads_unicos_resueltos
  from cohorte c
  where c.moneda = 'PEN'
  group by c.analista_id, c.rango_id
),
cohorte_usd as (
  select
    c.analista_id,
    count(*) as episodios_recibidos,
    count(distinct c.lead_id) as leads_unicos_recibidos,
    count(*) filter (where c.resultado = 'convertido') as convertidos,
    count(*) filter (where c.resultado = 'descartado') as descartados
  from cohorte c
  where c.moneda = 'USD'
  group by c.analista_id
),
operacion_cohorte as (
  select
    c.analista_id,
    count(*) as episodios,
    count(*) filter (where c.primer_contacto_en is not null) as contactos,
    count(*) filter (where c.sla_evaluable) as sla_evaluables,
    count(*) filter (where c.sla_en_24h) as sla_en_24h,
    round((percentile_cont(0.5) within group (
      order by c.primer_contacto_minutos
    ))::numeric, 1) as primer_contacto_mediana_minutos,
    count(*) filter (where c.motivo_cierre = 'transferido') as transferidos,
    count(*) filter (where c.motivo_cierre = 'parqueado') as parqueados,
    count(*) filter (where c.motivo_cierre = 'desactivado') as desactivados
  from cohorte c
  group by c.analista_id
),
cola_actual as (
  select
    l.*,
    private.rango_capital_pen(l.monto_estimado) as rango_id
  from crm.leads l
  where l.activo = true
    and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and l.vendedor_id is null
),
cola_total as (
  select
    count(*) as carga_total,
    count(*) filter (where moneda = 'PEN') as pen_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'PEN'), 0) as pen_capital,
    count(*) filter (where moneda = 'USD') as usd_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'USD'), 0) as usd_capital
  from cola_actual
),
cola_pen_rangos as (
  select rango_id, count(*) as cantidad, coalesce(sum(monto_estimado), 0) as capital
  from cola_actual
  where moneda = 'PEN'
  group by rango_id
),
cola_global_total as (
  select
    count(*) as carga_total,
    count(*) filter (where moneda = 'PEN') as pen_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'PEN'), 0) as pen_capital,
    count(*) filter (where moneda = 'USD') as usd_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'USD'), 0) as usd_capital
  from cola_actual
  where asignado_supervisor_id is null
),
cola_global_pen_rangos as (
  select rango_id, count(*) as cantidad, coalesce(sum(monto_estimado), 0) as capital
  from cola_actual
  where asignado_supervisor_id is null and moneda = 'PEN'
  group by rango_id
),
bandeja_totales as (
  select
    asignado_supervisor_id as supervisor_id,
    count(*) as carga_total,
    count(*) filter (where moneda = 'PEN') as pen_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'PEN'), 0) as pen_capital,
    count(*) filter (where moneda = 'USD') as usd_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'USD'), 0) as usd_capital
  from cola_actual
  where asignado_supervisor_id is not null
  group by asignado_supervisor_id
),
bandeja_pen_rangos as (
  select
    asignado_supervisor_id as supervisor_id,
    rango_id,
    count(*) as cantidad,
    coalesce(sum(monto_estimado), 0) as capital
  from cola_actual
  where asignado_supervisor_id is not null and moneda = 'PEN'
  group by asignado_supervisor_id, rango_id
),
analistas_json as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'analista_id', eb.analista_id,
      'nombre', eb.nombre,
      'rol', eb.rol,
      'supervisor_id', eb.supervisor_id,
      'supervisor_nombre', eb.supervisor_nombre,
      'activo', eb.activo,
      'disponible_para_recibir', eb.disponible_para_recibir,
      'capacidad', jsonb_build_object(
        'objetivo', eb.capacidad_objetivo,
        'carga_activa', coalesce(ct.carga_activa, 0),
        'carga_pen', coalesce(ct.carga_pen, 0),
        'carga_usd', coalesce(ct.carga_usd, 0)
      ),
      'pen', jsonb_build_object(
        'cartera_actual', jsonb_build_object(
          'episodios', coalesce(ct.carga_pen, 0),
          'capital', coalesce(ct.capital_pen, 0)
        ),
        'cohorte', jsonb_build_object(
          'episodios_recibidos', coalesce(cpt.episodios_recibidos, 0),
          'leads_unicos_recibidos', coalesce(cpt.leads_unicos_recibidos, 0),
          'convertidos', coalesce(cpt.convertidos, 0),
          'descartados', coalesce(cpt.descartados, 0),
          'ciclos_resueltos', coalesce(cpt.ciclos_resueltos, 0),
          'leads_unicos_resueltos', coalesce(cpt.leads_unicos_resueltos, 0)
        ),
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cartera_actual', jsonb_build_object(
              'episodios', coalesce(cpr.episodios, 0),
              'capital', coalesce(cpr.capital, 0)
            ),
            'cohorte', jsonb_build_object(
              'episodios_recibidos', coalesce(cr.episodios_recibidos, 0),
              'leads_unicos_recibidos', coalesce(cr.leads_unicos_recibidos, 0),
              'convertidos', coalesce(cr.convertidos, 0),
              'descartados', coalesce(cr.descartados, 0),
              'leads_unicos_resueltos', coalesce(cr.leads_unicos_resueltos, 0)
            )
          ) order by r.orden)
          from rangos r
          left join cartera_pen_rangos cpr
            on cpr.analista_id = eb.analista_id and cpr.rango_id = r.rango_id
          left join cohorte_pen_rangos cr
            on cr.analista_id = eb.analista_id and cr.rango_id = r.rango_id
        )
      ),
      'usd_no_segmentado', jsonb_build_object(
        'cartera_actual_episodios', coalesce(ct.carga_usd, 0),
        'cartera_actual_capital', coalesce(ct.capital_usd, 0),
        'cohorte_episodios_recibidos', coalesce(cu.episodios_recibidos, 0),
        'cohorte_leads_unicos', coalesce(cu.leads_unicos_recibidos, 0),
        'convertidos', coalesce(cu.convertidos, 0),
        'descartados', coalesce(cu.descartados, 0)
      ),
      'operacion', jsonb_build_object(
        'cohorte_episodios', coalesce(oc.episodios, 0),
        'contactos', coalesce(oc.contactos, 0),
        'sla_evaluables', coalesce(oc.sla_evaluables, 0),
        'sla_en_24h', coalesce(oc.sla_en_24h, 0),
        'primer_contacto_mediana_minutos', oc.primer_contacto_mediana_minutos,
        'transferidos', coalesce(oc.transferidos, 0),
        'parqueados', coalesce(oc.parqueados, 0),
        'desactivados', coalesce(oc.desactivados, 0),
        'sin_tocar_actual', coalesce(ct.sin_tocar_actual, 0),
        'estancados_actual', coalesce(ct.estancados_actual, 0)
      )
    ) order by coalesce(eb.supervisor_nombre, ''), eb.nombre, eb.analista_id), '[]'::jsonb) as valor
  from equipo_base eb
  left join cartera_total ct on ct.analista_id = eb.analista_id
  left join cohorte_pen_total cpt on cpt.analista_id = eb.analista_id
  left join cohorte_usd cu on cu.analista_id = eb.analista_id
  left join operacion_cohorte oc on oc.analista_id = eb.analista_id
),
bandejas_json as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'supervisor_id', bt.supervisor_id,
      'supervisor_nombre', coalesce(nullif(trim(p.nombre_completo), ''), 'Supervisor sin nombre'),
      'supervisor_activo', coalesce(e.activo = true and p.activo = true, false),
      'carga_total', bt.carga_total,
      'pen', jsonb_build_object(
        'cantidad', bt.pen_cantidad,
        'capital', bt.pen_capital,
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cantidad', coalesce(bpr.cantidad, 0),
            'capital', coalesce(bpr.capital, 0)
          ) order by r.orden)
          from rangos r
          left join bandeja_pen_rangos bpr
            on bpr.supervisor_id = bt.supervisor_id and bpr.rango_id = r.rango_id
        )
      ),
      'usd', jsonb_build_object('cantidad', bt.usd_cantidad, 'capital', bt.usd_capital)
    ) order by p.nombre_completo, bt.supervisor_id), '[]'::jsonb) as valor
  from bandeja_totales bt
  left join crm.equipo e on e.perfil_id = bt.supervisor_id and e.rol_crm = 'supervisor'
  left join public.perfiles p on p.id = bt.supervisor_id
),
resumen as (
  select jsonb_build_object(
    'leads_operativos_actuales', (
      select count(*) from crm.leads l
      where l.activo = true
        and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    ),
    'asignados_actuales', (select count(*) from abiertos),
    'por_repartir_actuales', (select count(*) from cola_actual),
    'capital_pen_asignado_actual', coalesce((select sum(monto_estimado) from abiertos where moneda = 'PEN'), 0),
    'capital_usd_asignado_actual', coalesce((select sum(monto_estimado) from abiertos where moneda = 'USD'), 0),
    'cohorte_episodios', (select count(*) from cohorte),
    'cohorte_leads_unicos', (select count(distinct lead_id) from cohorte),
    'convertidos_pen', (select count(*) from cohorte where moneda = 'PEN' and resultado = 'convertido'),
    'descartados_pen', (select count(*) from cohorte where moneda = 'PEN' and resultado = 'descartado'),
    'sla_evaluables', (select count(*) from cohorte where sla_evaluable),
    'sla_en_24h', (select count(*) from cohorte where sla_en_24h)
  ) as valor
),
calidad as (
  select jsonb_build_object(
    'episodios_aproximados_actuales', (select count(*) from abiertos where aproximado),
    'episodios_aproximados_cohorte', (select count(*) from cohorte where aproximado),
    'episodios_sin_monto_actuales', (
      select count(*) from abiertos where monto_estimado is null or monto_estimado <= 0
    ),
    'episodios_sin_monto_cohorte', (
      select count(*) from cohorte where monto_estimado is null or monto_estimado <= 0
    )
  ) as valor
)
select jsonb_build_object(
  'version', 1,
  'generado_en', p_ahora,
  'cohorte', jsonb_build_object(
    'desde_inclusivo', p_desde,
    'hasta_inclusivo', p_hasta,
    'hasta_exclusivo', p_hasta + 1,
    'criterio', 'episodio_asignado_en',
    'zona_horaria', 'America/Lima'
  ),
  'alcances', jsonb_build_object(
    'matriz', 'PEN',
    'capacidad', 'TODAS_LAS_MONEDAS',
    'operacion_sla', 'TODAS_LAS_MONEDAS'
  ),
  'rangos', (
    select jsonb_agg(jsonb_build_object(
      'id', r.rango_id,
      'orden', r.orden,
      'etiqueta', r.etiqueta,
      'desde_exclusivo', r.desde_exclusivo,
      'hasta_inclusivo', r.hasta_inclusivo
    ) order by r.orden)
    from rangos r
  ),
  'resumen', resumen.valor,
  'analistas', analistas_json.valor,
  'por_repartir', jsonb_build_object(
    'total', jsonb_build_object(
      'carga_total', ct.carga_total,
      'pen', jsonb_build_object(
        'cantidad', ct.pen_cantidad,
        'capital', ct.pen_capital,
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cantidad', coalesce(cpr.cantidad, 0),
            'capital', coalesce(cpr.capital, 0)
          ) order by r.orden)
          from rangos r
          left join cola_pen_rangos cpr on cpr.rango_id = r.rango_id
        )
      ),
      'usd', jsonb_build_object('cantidad', ct.usd_cantidad, 'capital', ct.usd_capital)
    ),
    'global', jsonb_build_object(
      'responsabilidad', 'gerencia',
      'carga_total', cgt.carga_total,
      'pen', jsonb_build_object(
        'cantidad', cgt.pen_cantidad,
        'capital', cgt.pen_capital,
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cantidad', coalesce(cgpr.cantidad, 0),
            'capital', coalesce(cgpr.capital, 0)
          ) order by r.orden)
          from rangos r
          left join cola_global_pen_rangos cgpr on cgpr.rango_id = r.rango_id
        )
      ),
      'usd', jsonb_build_object('cantidad', cgt.usd_cantidad, 'capital', cgt.usd_capital)
    ),
    'bandejas', bandejas_json.valor
  ),
  'calidad', calidad.valor
)
from parametros p
cross join resumen
cross join calidad
cross join analistas_json
cross join cola_total ct
cross join cola_global_total cgt
cross join bandejas_json;
$function$;

create or replace function crm.metricas_distribucion_leads_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
begin
  if v_actor is null or not (
    exists (
      select 1
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = v_actor
        and e.rol_crm = 'gerencia'
        and e.activo = true
        and p.activo = true
    )
    or private.es_lector_global()
  ) then
    raise exception 'Solo Gerencia o Directorio puede consultar estas metricas'
      using errcode = '42501';
  end if;

  if p_desde is null
     or p_hasta is null
     or p_desde > p_hasta
     or p_hasta > v_hoy
     or (p_hasta - p_desde) > 365 then
    raise exception 'Periodo invalido: usa fechas hasta hoy y un maximo de 366 dias'
      using errcode = '22023';
  end if;

  return private.metricas_distribucion_leads_core(p_desde, p_hasta, v_ahora);
end;
$function$;

comment on function crm.metricas_distribucion_leads_fn(date, date) is
  'Fotografia descriptiva de distribucion, capacidad, resultados y SLA por episodio; exclusiva de Gerencia/Directorio.';

revoke all on function private.rango_capital_pen(numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.umbral_estancamiento(text)
  from public, anon, authenticated, service_role;
revoke all on function private.metricas_distribucion_leads_core(date, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function crm.metricas_distribucion_leads_fn(date, date)
  from public, anon;
grant execute on function crm.metricas_distribucion_leads_fn(date, date)
  to authenticated;

commit;
