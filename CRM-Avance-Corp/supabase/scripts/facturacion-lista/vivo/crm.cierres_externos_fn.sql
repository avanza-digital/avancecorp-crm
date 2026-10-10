CREATE OR REPLACE FUNCTION crm.cierres_externos_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text;
  v_lector     boolean;
  v_global     boolean;
  v_filas      boolean;
  v_alcance    text;
  v_visibles   uuid[];
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini        timestamptz;
  v_fin        timestamptz;
  v_payload    jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_filas := coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'alcance', v_alcance,
    -- Filas para la sección «En cooperativas» de Mi cartera (todo el
    -- histórico del ámbito, más reciente primero). Tope de 200 con total al
    -- lado: sin tope sería la lista sin fin que F2 vino a matar; con tope
    -- mudo, el front sumaría filas truncadas y mentiría en los totales — por
    -- eso los mini-totales NO salen de las filas sino de `totales`.
    'cierres', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'plazo_meses', ce.plazo_meses,
        'tasa_anual', ce.tasa_anual,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_efectivo_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,
        -- Los anulados SÍ viajan en las filas (y NO en los totales): el asesor
        -- tiene que poder entender por qué le bajó el total, no encontrarse un
        -- hueco donde antes había un cierre.
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select ce0.*, ef.analista_id as vendedor_efectivo_id
        from crm.cierres_externos ce0
        cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)
        where v_global or ef.analista_id = any(v_visibles)
        order by ce0.creado_en desc
        limit 200
      ) ce
      left join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_efectivo_id
    ), '[]'::jsonb) end,
    'cierres_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where v_global or private.analista_efectivo_cierre(ce.id) = any(v_visibles)
    ),
    -- Las filas DEL MES pedido: es la vista de revisión de supervisor y gerencia
    -- («Ver cierres del mes»), donde el número de operación se contrasta. NO se
    -- filtra en el cliente sobre `cierres`, que viene tope 200 por antigüedad y
    -- podría no alcanzar el mes entero.
    'cierres_mes', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'plazo_meses', ce.plazo_meses,
        'tasa_anual', ce.tasa_anual,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_efectivo_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select ce0.*, ef.analista_id as vendedor_efectivo_id
        from crm.cierres_externos ce0
        cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)
        where coalesce((ce0.fecha_imputacion::timestamp at time zone 'America/Lima'),ce0.creado_en) >= v_ini and coalesce((ce0.fecha_imputacion::timestamp at time zone 'America/Lima'),ce0.creado_en) < v_fin
          and (v_global or ef.analista_id = any(v_visibles))
        order by ce0.creado_en desc
        limit 200
      ) ce
      left join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_efectivo_id
    ), '[]'::jsonb) end,
    'cierres_mes_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= v_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < v_fin
        and (v_global or private.analista_efectivo_cierre(ce.id) = any(v_visibles))
    ),
    -- Mini-totales de Mi cartera: TODO el histórico del ámbito, por
    -- cooperativa y moneda (PEN/USD jamás sumados). Servidos aquí para que el
    -- front no haga aritmética sobre una lista que puede venir truncada.
    'totales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cooperativa', t.cooperativa,
        'moneda', t.moneda,
        'capital', t.capital,
        'cierres', t.cierres
      ) order by t.cooperativa, t.moneda)
      from (
        select ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        where (v_global or private.analista_efectivo_cierre(ce.id) = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.cooperativa, ce.moneda
      ) t
    ), '[]'::jsonb),
    -- Desglose por empresa del MES pedido, por vendedor × cooperativa ×
    -- moneda, para supervisor y gerencia. La parte «Avance» del desglose la
    -- pone cumplimiento_metas_fn (capital_real ya INCLUYE los externos tras
    -- esta migración): Avance = capital_real − estos agregados, resta de dos
    -- números servidos — no una división en cliente.
    'por_empresa', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', x.vendedor_id,
        'vendedor_nombre', x.nombre,
        'cooperativa', x.cooperativa,
        'moneda', x.moneda,
        'capital', x.capital,
        'cierres', x.cierres
      ) order by x.nombre, x.cooperativa, x.moneda)
      from (
        select ce.vendedor_efectivo_id as vendedor_id, p.nombre_completo as nombre,
               ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from (
          select ce0.*, ef.analista_id as vendedor_efectivo_id
          from crm.cierres_externos ce0
          cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)
        ) ce
        left join public.perfiles p on p.id = ce.vendedor_efectivo_id
        where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= v_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < v_fin
          and (v_global or ce.vendedor_efectivo_id = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.vendedor_efectivo_id, p.nombre_completo, ce.cooperativa, ce.moneda
      ) x
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$
