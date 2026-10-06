CREATE OR REPLACE FUNCTION private.conversion_mensual_por_vendedor(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(analista_id uuid, divisor integer, divisor_aproximado integer, divisor_por_motivo jsonb, cierres_no_referidos integer, cierres_referidos integer, cierres_de_arrastre integer, numerador numeric, conversion_pct numeric, procedencia jsonb, referidos_recibidos integer, referidos_aporta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
with ep as (
  select e.* from private.conversion_episodios(
    p_ini, p_fin,
    case when date_trunc('month', p_ini at time zone 'America/Lima') =
      date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')
      then date_trunc('month', p_ini at time zone 'America/Lima')::date end,
    p_global, p_visibles, p_factor
  ) e
), recibidos as (
  select e.analista_id, e.lead_id, e.fue_referido, e.motivo, e.aproximado, e.aporte_divisor
  from ep e where e.tipo = 'recibido'
), cierres as (
  select e.analista_id, e.lead_id, e.fue_referido, e.mes_origen,
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from ep e where e.tipo = 'cierre' and not e.anulado
    and e.origen in ('landing', 'formulario', 'referido')
), motivos as (
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r where r.aporte_divisor > 0
  group by r.analista_id, r.motivo
), motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m group by m.analista_id
), agg_div as (
  select r.analista_id,
    sum(r.aporte_divisor)::int as divisor,
    coalesce(sum(r.aporte_divisor) filter (where r.aproximado), 0)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r group by r.analista_id
), agg_cie as (
  select c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c group by c.analista_id
), aportes as (
  select e.analista_id,
    sum(e.aporte_divisor)::int as divisor,
    sum(e.aporte_numerador) as numerador,
    coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.fue_referido), 0) as aporte_referidos
  from ep e group by e.analista_id
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
  a.analista_id,
  a.divisor,
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  a.numerador,
  case when a.divisor > 0 then round(100.0 * a.numerador / a.divisor, 2) end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when a.divisor > 0 then round(100.0 * a.aporte_referidos / a.divisor, 2) end
from aportes a
left join agg_div d on d.analista_id is not distinct from a.analista_id
left join agg_cie c on c.analista_id is not distinct from a.analista_id
left join motivos_json mj on mj.analista_id is not distinct from a.analista_id
left join proc_json pj on pj.analista_id is not distinct from a.analista_id;
end;
$function$

