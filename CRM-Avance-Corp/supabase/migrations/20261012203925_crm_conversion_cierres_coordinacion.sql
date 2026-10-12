-- Detalle nominal aprobado por Miguel: Conversiones → Ver cierres.
-- No cambia los conteos, la visibilidad de fichas ni los permisos sobre tablas.
-- Reversa: supabase/scripts/conversion-cierres-coordinacion/reversa.sql.
begin;

create function private.conversion_cierres_coordinacion(
  p_analista uuid, p_desde date, p_hasta date, p_pagina integer
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_es_mes boolean := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (p_desde + interval '1 month - 1 day')::date;
  v_sellado boolean;
  v_resultado jsonb;
begin
  -- DEFINER necesario para leer únicamente los nombres del desglose autorizado.
  if (private.rol_crm((select auth.uid())) in ('coordinador', 'gerencia')) is not true then
    raise exception 'Sin permiso para consultar cierres' using errcode = '42501';
  end if;
  v_sellado := v_es_mes and exists(select 1 from crm.periodos_cerrados where periodo = p_desde);
  if v_sellado then
    return pg_catalog.jsonb_build_object('version', 1, 'analista_id', p_analista,
      'desde', p_desde, 'hasta', p_hasta, 'disponible', false,
      'total', 0, 'pagina', 0, 'por_pagina', 20, 'filas', '[]'::jsonb);
  end if;

  with episodios as materialized (
    -- El mismo núcleo y ventana Lima del agregado. Incluye manuales y aporte cero;
    -- el tope de referidos sigue calculándose con TODO el mes, antes del recorte.
    select e.* from private.conversion_episodios(
      p_desde::timestamp at time zone 'America/Lima',
      (p_hasta + 1)::timestamp at time zone 'America/Lima',
      case when v_es_mes then p_desde end, false, array[p_analista],
      private.peso_referido_conversion(pg_catalog.date_trunc('month', p_hasta)::date)
    ) e where e.tipo in ('cierre', 'operacion') and not e.anulado
  ), cantidad as (
    select count(*)::integer as total from episodios
  ), paginacion as (
    select total, least(p_pagina, greatest(0, (total - 1) / 20)) as pagina from cantidad
  ), pagina as (
    select e.* from episodios e
    order by e.fecha_numerador desc, e.tipo, e.lead_id, e.operacion_id
    limit 20 offset (select pagina * 20 from paginacion)
  ), filas as (
    select e.fecha_numerador, e.tipo, e.lead_id, e.operacion_id,
      pg_catalog.jsonb_build_object(
        'nombre', coalesce(l.nombre_completo, p.nombre_completo, 'Sin nombre'),
        'origen', case when e.tipo = 'operacion' then e.categoria else coalesce(e.origen, 'otro') end,
        'fecha', (e.fecha_numerador at time zone 'America/Lima')::date,
        'registro', case when e.tipo = 'operacion' then 'cartera'
          when coalesce(l.alta_manual, false) then 'manual' else 'sistema' end,
        'aporte', e.aporte_numerador
      ) as fila
    from pagina e
    left join crm.leads l on l.id = e.lead_id
    left join crm.operaciones_cartera o on o.id = e.operacion_id
    left join public.perfiles p on p.id = o.cliente_id
  )
  select pg_catalog.jsonb_build_object('version', 1, 'analista_id', p_analista,
    'desde', p_desde, 'hasta', p_hasta, 'disponible', true,
    'total', g.total, 'pagina', g.pagina, 'por_pagina', 20,
    'filas', coalesce((select pg_catalog.jsonb_agg(f.fila order by
      f.fecha_numerador desc, f.tipo, f.lead_id, f.operacion_id) from filas f), '[]'::jsonb))
  into v_resultado from paginacion g;
  return v_resultado;
end;
$$;

create function crm.conversion_cierres_coordinacion_fn(
  p_analista uuid, p_periodo date default null, p_desde date default null,
  p_hasta date default null, p_pagina integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
begin
  if (private.rol_crm((select auth.uid())) in ('coordinador', 'gerencia')) is not true then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar los cierres'
      using errcode = '42501';
  end if;
  if p_analista is null or p_pagina is null or p_pagina not between 0 and 50000 then
    raise exception 'Analista o página inválidos' using errcode = '22023';
  end if;
  if p_desde is null and p_hasta is null then
    v_desde := coalesce(p_periodo, pg_catalog.date_trunc('month', v_hoy)::date);
    if not pg_catalog.isfinite(v_desde)
       or v_desde <> pg_catalog.date_trunc('month', v_desde)::date
       or v_desde > pg_catalog.date_trunc('month', v_hoy)::date then
      raise exception 'Mes inválido' using errcode = '22023';
    end if;
    v_hasta := (v_desde + interval '1 month - 1 day')::date;
  else
    if p_periodo is not null or p_desde is null or p_hasta is null
       or not pg_catalog.isfinite(p_desde) or not pg_catalog.isfinite(p_hasta)
       or p_desde > p_hasta or p_hasta > v_hoy or p_hasta - p_desde > 365 then
      raise exception 'Rango inválido: indica ambas fechas, hasta 366 días, sin futuro'
        using errcode = '22023';
    end if;
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;
  return private.conversion_cierres_coordinacion(p_analista, v_desde, v_hasta, p_pagina);
end;
$$;

revoke all on function private.conversion_cierres_coordinacion(uuid,date,date,integer)
  from public, anon, authenticated, service_role;
revoke all on function crm.conversion_cierres_coordinacion_fn(uuid,date,date,date,integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_cierres_coordinacion_fn(uuid,date,date,date,integer) to authenticated;
comment on function private.conversion_cierres_coordinacion(uuid,date,date,integer) is
  'Detalle mínimo de conversión para Coordinación/Gerencia activas: nombre (dato personal autorizado), origen, fecha Lima, registro manual/sistema/cartera y aporte. Solo episodios canónicos no anulados, páginas de 20. Mes calendario sellado: sin detalle nominal. Rangos libres: datos vivos, pueden diferir de las fotos. Sin IDs de clientes, contactos, documentos, montos ni acceso a fichas.';
comment on function crm.conversion_cierres_coordinacion_fn(uuid,date,date,date,integer) is
  'Puerta de lectura aprobada por Miguel 12/10/2026: autoriza Coordinación/Gerencia activas, valida mes/rango/página y delega el detalle de cierres de un analista. No modifica datos ni conteos.';
commit;
