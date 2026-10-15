-- REEXPRESIÓN DE SEPTIEMBRE 2026 — diagnóstico de SOLO LECTURA.
-- El ensayo del 14/10 se negó con «hay ajustes nacidos de septiembre sellado».
-- Esto dice qué nació de septiembre DESPUÉS de su sello (11/10 09:20 Lima):
-- deudas por anulación, inversiones registradas tarde (imputadas a otro mes) y
-- acreditaciones de conversión decididas tras el sello. Sin nombres de clientes.
-- Se ejecuta con: npx supabase db query --linked --file <este archivo>
select jsonb_build_object(
  'sello_septiembre', (select jsonb_build_object(
      'cerrado_en_lima', (pc.cerrado_en at time zone 'America/Lima'), 'automatico', pc.automatico,
      'foto_filas', (select count(*) from crm.cierre_mes_vendedor f where f.periodo = pc.periodo),
      'foto_ajustes_absorbidos', (select count(*) from crm.cierre_mes_vendedor f where f.periodo = pc.periodo
                                    and (f.ajuste_numerador <> 0 or f.ajuste_pen <> 0 or f.ajuste_usd <> 0)))
    from crm.periodos_cerrados pc where pc.periodo = date '2026-09-01'),

  -- Deudas: anular una conversión de septiembre después del sello.
  'deudas_de_septiembre', (select coalesce(jsonb_agg(jsonb_build_object(
      'creado_en_lima', (a.creado_en at time zone 'America/Lima'),
      'analista', p.nombre_completo,
      'lead', left(a.lead_id::text, 8),
      'motivo', a.motivo,
      'numerador', a.numerador, 'capital_pen', a.capital_pen, 'capital_usd', a.capital_usd,
      'pendiente_numerador', a.pendiente_numerador, 'pendiente_pen', a.pendiente_pen,
      'pendiente_usd', a.pendiente_usd, 'saldado', a.saldado_en is not null
    ) order by a.creado_en), '[]'::jsonb)
    from crm.ajustes_mes_cerrado a left join public.perfiles p on p.id = a.vendedor_id
    where a.periodo_origen = date '2026-09-01'),

  -- Inversiones con fecha comercial en septiembre registradas tras el sello:
  -- el sistema las imputó al mes de registro (fecha_imputacion).
  'inversiones_tardias', (select coalesce(jsonb_agg(jsonb_build_object(
      'registrada_en_lima', (ia.creado_en at time zone 'America/Lima'),
      'imputada_a', ia.fecha_imputacion,
      'estado_inversion', i.estado,
      'fuente', case when i.contrato_id is not null then 'contrato' else 'cooperativa' end,
      'contrato', c.numero_contrato,
      'contrato_fecha_comercial', c.fecha_cierre_comercial,
      'cooperativa', ce.cooperativa,
      'cooperativa_fecha_comercial', ce.fecha_comercial,
      'cooperativa_imputacion', ce.fecha_imputacion,
      'cooperativa_anulada', ce.anulado_en is not null,
      'monto', coalesce(c.capital, ce.monto), 'moneda', coalesce(c.moneda, ce.moneda),
      'analista', coalesce(pa.nombre_completo, pv.nombre_completo),
      'registrada_por', pr.nombre_completo
    ) order by ia.creado_en), '[]'::jsonb)
    from crm.inversion_ajustes_mes_cerrado ia
    join crm.inversiones i on i.id = ia.inversion_id
    left join public.contratos c on c.id = i.contrato_id
    left join crm.cierres_externos ce on ce.id = i.cierre_externo_id
    left join public.perfiles pa on pa.id = c.analista_cierre_id
    left join public.perfiles pv on pv.id = ce.vendedor_id
    left join public.perfiles pr on pr.id = ia.creado_por
    where ia.periodo_origen = date '2026-09-01'),

  -- Cooperativa con fecha comercial de septiembre imputada a otro mes (con o sin rastro).
  'cooperativa_septiembre_imputada_fuera', (select jsonb_build_object(
      'casos', count(*), 'pen', coalesce(sum(ce.monto) filter (where ce.moneda = 'PEN'), 0),
      'usd', coalesce(sum(ce.monto) filter (where ce.moneda = 'USD'), 0))
    from crm.cierres_externos ce
    where ce.fecha_comercial between date '2026-09-01' and date '2026-09-30'
      and ce.fecha_imputacion is not null and ce.fecha_imputacion >= date '2026-10-01'
      and ce.anulado_en is null),

  -- Acreditaciones de conversión de septiembre decididas después del sello.
  'acreditaciones_tras_el_sello', (select coalesce(jsonb_agg(jsonb_build_object(
      'estado', ca.estado, 'fuente', ca.fuente_tipo, 'origen', ca.origen,
      'acreditado_en_lima', (ca.acreditado_en at time zone 'America/Lima'),
      'analista', p.nombre_completo, 'lead', left(ca.lead_id::text, 8)
    ) order by ca.acreditado_en), '[]'::jsonb)
    from crm.conversion_acreditaciones ca left join public.perfiles p on p.id = ca.analista_id
    where ca.periodo_comercial = date '2026-09-01'
      and ca.acreditado_en >= (select cerrado_en from crm.periodos_cerrados where periodo = date '2026-09-01')),

  'ciclo_activo', (select active from cron.job where jobid = 3)
) as diagnostico;
