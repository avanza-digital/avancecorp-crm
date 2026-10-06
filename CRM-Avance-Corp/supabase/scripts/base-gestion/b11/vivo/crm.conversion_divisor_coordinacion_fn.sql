CREATE OR REPLACE FUNCTION crm.conversion_divisor_coordinacion_fn(p_periodo date DEFAULT NULL::date, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
  v_es_mes boolean;
  v_totales record;
  v_payload jsonb;
begin
  -- 1) Gate primero: un actor denegado recibe 42501 aunque el período sea inválido.
  --    `is not true`: un NULL del gate también deniega.
  if private.puede_operar_reparto_crm() is not true then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista'
      using errcode = '42501';
  end if;

  -- 2) Validación del período: mes (por defecto el vigente) o rango inclusivo.
  if p_desde is null and p_hasta is null then
    v_desde := coalesce(p_periodo, v_mes_actual);
    if v_desde <> pg_catalog.date_trunc('month', v_desde)::date then
      raise exception 'Periodo invalido: debe ser el primer dia del mes'
        using errcode = '22023';
    end if;
    if v_desde > v_mes_actual then
      raise exception 'Periodo invalido: el mes no puede ser futuro'
        using errcode = '22023';
    end if;
    v_hasta := (v_desde + interval '1 month' - interval '1 day')::date;
  else
    if p_periodo is not null then
      raise exception 'Periodo invalido: indica el mes o el rango, no los dos'
        using errcode = '22023';
    end if;
    if p_desde is null or p_hasta is null then
      raise exception 'Periodo invalido: indica ambas fechas del rango'
        using errcode = '22023';
    end if;
    if p_desde > p_hasta then
      raise exception 'Periodo invalido: la fecha inicial no puede ser posterior a la final'
        using errcode = '22023';
    end if;
    if p_hasta > v_hoy then
      raise exception 'Periodo invalido: el rango no admite fechas futuras'
        using errcode = '22023';
    end if;
    if p_hasta - p_desde > 365 then
      raise exception 'Periodo invalido: el rango maximo es de 366 dias'
        using errcode = '22023';
    end if;
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;
  v_es_mes := v_desde = pg_catalog.date_trunc('month', v_desde)::date
    and v_hasta = (pg_catalog.date_trunc('month', v_desde) + interval '1 month' - interval '1 day')::date;

  -- 3) Delegar: el núcleo decide mes/rango y abierto/sellado; aquí solo se da forma.
  select t.* into strict v_totales from private.conversion_divisor_empresa_totales(v_desde, v_hasta) t;

  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'alcance', 'global',
    'periodo', pg_catalog.jsonb_build_object(
      'modo', case when v_es_mes then 'mes' else 'rango' end,
      'mes', case when v_es_mes then pg_catalog.to_char(v_desde, 'YYYY-MM') end,
      'mes_nombre', case when v_es_mes then private.etiqueta_mes_es(v_desde) end,
      'anio', case when v_es_mes then extract(year from v_desde)::integer end,
      'zona', 'America/Lima',
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', (v_hasta - v_desde) + 1,
      'cruza_meses_sellados', v_totales.cruza_sellados
    ),
    'sellado', v_totales.sellado,
    'peso_referido', v_totales.peso_referido,
    'peso_renovacion', v_totales.peso_renovacion,
    'fuente', pg_catalog.jsonb_build_object(
      'divisor', 'private.conversion_neta_por_vendedor',
      'origen', 'private.conversion_episodios',
      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado',
      -- 'foto' = mes sellado servido de crm.cierre_mes_vendedor; 'mensual' = mes abierto
      -- con la pieza de Metas (bruto, ajuste, neto); 'rango_vivo' = tramo libre calculado
      -- en vivo sin ajustes ni fotos (precedente: crm.metricas_conversiones_equipo_fn).
      'modo', case when v_totales.sellado then 'foto' when v_es_mes then 'mensual' else 'rango_vivo' end
    ),
    'empresa', pg_catalog.jsonb_build_object(
      'divisor', v_totales.divisor,
      'numerador', v_totales.numerador,
      'conversion_pct', v_totales.conversion_pct,
      'divisor_formulario', v_totales.divisor_formulario,
      'divisor_landing', v_totales.divisor_landing,
      'numerador_bruto', v_totales.numerador_bruto,
      'ajuste_pendiente', v_totales.ajuste_pendiente,
      'desglose_disponible', v_totales.desglose_disponible,
      'cierres', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'formulario', v_totales.cierres_formulario,
        'landing', v_totales.cierres_landing,
        'referido', v_totales.cierres_referido,
        'referido_aporte', v_totales.cierres_referido_aporte,
        'oficina', v_totales.cierres_oficina,
        'otros', v_totales.cierres_otros
      ) end,
      'cartera', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'upgrade', v_totales.upgrade,
        'renovacion', v_totales.renovacion,
        'renovacion_aporte', v_totales.renovacion_aporte
      ) end
    ),
    'sin_analista', case when v_totales.sin_analista_presente then pg_catalog.jsonb_build_object(
      'divisor', v_totales.sin_analista_divisor,
      'numerador', v_totales.sin_analista_numerador
    ) end,
    'analistas', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'analista_id', f.analista_id,
          'nombre', f.nombre,
          'supervisor_id', f.supervisor_id,
          'supervisor_nombre', f.supervisor_nombre,
          'en_nucleo', f.en_nucleo,
          'divisor', f.divisor,
          'divisor_formulario', f.divisor_formulario,
          'divisor_landing', f.divisor_landing,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'numerador_bruto', f.numerador_bruto,
          'ajuste_pendiente', f.ajuste_pendiente,
          'desglose_disponible', f.desglose_disponible,
          'cierres', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'formulario', f.cierres_formulario,
            'landing', f.cierres_landing,
            'referido', f.cierres_referido,
            'referido_aporte', f.cierres_referido_aporte,
            'oficina', f.cierres_oficina,
            'otros', f.cierres_otros
          ) end,
          'cartera', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'upgrade', f.upgrade,
            'renovacion', f.renovacion,
            'renovacion_aporte', f.renovacion_aporte
          ) end
        )
        order by f.nombre nulls last, f.analista_id
      )
      from private.conversion_divisor_empresa(v_desde, v_hasta) f
      where f.analista_id is not null
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$

