CREATE OR REPLACE FUNCTION crm.facturacion_diaria_fn(p_mes date DEFAULT NULL::date)
 RETURNS TABLE(dia date, tipo text, moneda text, analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text, operaciones bigint, capital numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with
  mes as (
    -- Se normaliza en vez de rechazar: una fecha a mitad de mes solo puede querer
    -- decir ese mes. Y sin argumento vale el mes EN CURSO de Lima — un NULL que
    -- devolviera vacío en silencio sería indistinguible de «no se vendió nada».
    select coalesce(
      date_trunc('month', p_mes),
      date_trunc('month', (now() at time zone 'America/Lima'))
    )::date as ini
  )
  select
    ep.dia,
    ep.tipo,
    ep.moneda,
    ep.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    ep.supervisor_id as supervisor_id,
    coalesce(ps.nombre_completo, 'Sin supervisor') as supervisor_nombre,
    count(*)::bigint as operaciones,
    sum(ep.monto) as capital
  from mes m
  cross join lateral private.facturacion_operaciones_visibles(
    (m.ini::timestamp at time zone 'America/Lima'),
    (((m.ini + interval '1 month')::date)::timestamp at time zone 'America/Lima')
  ) ep
  left join public.perfiles pf on pf.id = ep.analista_id
  left join public.perfiles ps on ps.id = ep.supervisor_id
  group by ep.dia, ep.tipo, ep.moneda, ep.analista_id, pf.nombre_completo,
           ep.supervisor_id, ps.nombre_completo
  -- PEN y USD no comparten escala: la moneda ordena ANTES que el importe, para no
  -- rankear US$ 10 000 por debajo de S/ 50 000.
  order by ep.dia, ep.moneda, sum(ep.monto) desc;
$function$
