-- Vuelta atrás de F1 (conversion_episodios): restaura el núcleo vivo pre-F1
-- VERBATIM (md5 49601295f0ce72a9ec7d795fc014a60e) y retira la tabla-base.
-- Ejecutar SOLO si la paridad en producción se rompiera tras aplicar F1.

CREATE OR REPLACE FUNCTION private.conversion_mensual_por_vendedor(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(analista_id uuid, divisor integer, divisor_aproximado integer, divisor_por_motivo jsonb, cierres_no_referidos integer, cierres_referidos integer, cierres_de_arrastre integer, numerador numeric, conversion_pct numeric, procedencia jsonb, referidos_recibidos integer, referidos_aporta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
with recibidos as (
  select
    la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
), cierres as (
  select
    la.analista_id, la.lead_id, (la.origen = 'referido') as fue_referido,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
    and not private.cierre_externo_anulado(la.lead_id)
), motivos as (
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r where not r.fue_referido
  group by r.analista_id, r.motivo
), motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m group by m.analista_id
), agg_div as (
  select r.analista_id,
    count(*) filter (where not r.fue_referido)::int as divisor,
    count(*) filter (where r.aproximado and not r.fue_referido)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r group by r.analista_id
), agg_cie as (
  select c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c group by c.analista_id
), ops_elegibles as (
  select o.*,
    row_number() over (
      partition by o.cliente_id, o.periodo
      order by o.fecha_operacion, o.creado_en, o.id
    ) as orden_conversion
  from crm.operaciones_cartera o
  where o.periodo = date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o.elegible_conversion
), agg_ops as (
  select o.vendedor_id as analista_id, count(*)::int as conversiones_clientes
  from ops_elegibles o
  where o.orden_conversion = 1
    and (p_global or o.vendedor_id = any(p_visibles))
  group by o.vendedor_id
), proc as (
  select c.analista_id, c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select c0.analista_id, c0.lead_id, c0.fue_referido,
      case when
        (extract(year from p_ini at time zone 'America/Lima')::int * 12
         + extract(month from p_ini at time zone 'America/Lima')::int)
        - (extract(year from c0.mes_origen)::int * 12
           + extract(month from c0.mes_origen)::int) <= 11
      then c0.mes_origen end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
), proc_json as (
  select p.analista_id,
    jsonb_agg(jsonb_build_object(
      'mes', case when p.mes_cubo is not null then to_char(p.mes_cubo, 'YYYY-MM') end,
      'mes_nombre', case when p.mes_cubo is not null
        then private.etiqueta_mes_es(p.mes_cubo) else 'anteriores' end,
      'anio', case when p.mes_cubo is not null then extract(year from p.mes_cubo)::int end,
      'cierres', p.cierres, 'cierres_referidos', p.cierres_referidos
    ) order by p.mes_cubo desc nulls last) as procedencia
  from proc p group by p.analista_id
)
select
  coalesce(d.analista_id, c.analista_id, o.analista_id),
  coalesce(d.divisor, 0),
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  (coalesce(c.cierres_no_referidos, 0)
   + p_factor * coalesce(c.cierres_referidos, 0)
   + coalesce(o.conversiones_clientes, 0))::numeric,
  case when coalesce(d.divisor, 0) > 0 then round(
    100.0 * (coalesce(c.cierres_no_referidos, 0)
      + p_factor * coalesce(c.cierres_referidos, 0)
      + coalesce(o.conversiones_clientes, 0)) / d.divisor, 2)
  end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when coalesce(d.divisor, 0) > 0 then
    round(100.0 * p_factor * coalesce(c.cierres_referidos, 0) / d.divisor, 2)
  end
from agg_div d
full outer join agg_cie c on c.analista_id = d.analista_id
full outer join agg_ops o on o.analista_id = coalesce(d.analista_id, c.analista_id)
left join motivos_json mj on mj.analista_id = d.analista_id
left join proc_json pj on pj.analista_id = coalesce(d.analista_id, c.analista_id, o.analista_id);
end;
$function$;

drop function if exists private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric);

do $verifica$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'conversion_mensual_por_vendedor'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric')
     is distinct from '49601295f0ce72a9ec7d795fc014a60e' then
    raise exception 'el rollback NO restauró el núcleo esperado';
  end if;
end;
$verifica$;
