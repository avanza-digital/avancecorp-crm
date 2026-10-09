CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    -- ATR-2: la cadena de upgrade adopta tambien el CAPITAL (contrato 2026-08-30).
    ef.analista_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ef.analista_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  cross join lateral private.analista_efectivo_contrato(c.id, c.analista_cierre_id) as ef(analista_id)
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or ef.analista_id = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    ef.analista_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ef.analista_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) as ef(analista_id)
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or ef.analista_id = any(p_visibles))

  union all

  select
    'cooperativa',
    -- ATR-4 (Miguel 31/08): la sancion de anular es SOLO de conversion. El
    -- capital de una coop anulada EXISTE y se queda: vuelve a 'stock'. UNICA
    -- excepcion DECLARADA: la fila DEMO de Miguel (qorilazo S/100.000, creada
    -- 19/08 y anulada 20/08 con motivo 'DEMO'; vault «Cierre Qorilazo S 100000
    -- es dato demo») — su lead es REAL y el filtro de demos no la caza, asi
    -- que se excluye por id, sellado por la huella de este cuerpo.
    case when ce.anulado_en is null then 'stock'
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 'nula'
         else 'stock' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ef.analista_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ef.analista_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 0::numeric
         else ce.monto end,
    'nuevo',
    date_trunc('month', coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date,
    coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en),
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  cross join lateral private.analista_efectivo_cierre(ce.id) as ef(analista_id)
  where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= p_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < p_fin
    and (p_global or ef.analista_id = any(p_visibles));

$function$
