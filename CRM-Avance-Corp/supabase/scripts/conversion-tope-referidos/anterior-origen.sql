-- La función ANTERIOR de la Fase B (private.ranking_conversion_origen_mes, texto vivo del 07/10/2026) como pg_temp: la vara de la igualdad.
-- Su cuerpo llama a private.conversion_cierres, no al núcleo con tope. Se incluye con \i dentro de una transacción.
CREATE FUNCTION pg_temp.ranking_conversion_origen_mes_anterior(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_factor numeric)
 RETURNS TABLE(vendedor_id uuid, origen text, leads integer, cierres integer, conversion_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with llegadas as (
    select f.vendedor_id, f.origen, count(*)::integer as leads
    from private.ranking_llegadas_origen_filas(p_ini, p_fin) f
    group by f.vendedor_id, f.origen
  ), cierres as (
    select c.analista_id as vendedor_id, c.origen,
      count(*)::integer as cierres,
      sum(case when c.origen = 'referido' then p_factor else 1::numeric end) as numerador
    from private.conversion_cierres(
      p_ini, p_fin, p_periodo, true, '{}'::uuid[], p_factor, null::uuid[]
    ) c
    where c.tipo = 'cierre' and not c.anulado
      and c.origen in ('landing', 'formulario', 'referido', 'oficina')
      and c.analista_id is not null
    group by c.analista_id, c.origen
  )
  select coalesce(l.vendedor_id, c.vendedor_id), coalesce(l.origen, c.origen),
    coalesce(l.leads, 0), coalesce(c.cierres, 0),
    case when coalesce(l.leads, 0) > 0
      and (coalesce(l.origen, c.origen) <> 'referido' or p_factor is not null)
      then round(100 * coalesce(c.numerador, 0) / l.leads, 2)
    end
  from llegadas l full join cierres c
    on c.vendedor_id = l.vendedor_id and c.origen = l.origen;
$function$;
