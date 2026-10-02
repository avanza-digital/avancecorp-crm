-- SOLO LECTURA. Lista de trabajo F6 para Operaciones: los contratos que no se pueden pagar por falta de
-- cuenta de pago, con el cliente, lo vencido y las cuentas candidatas (banco y origen; sin números ni CCI).
-- Misma clasificación que censo-sin-funciones.sql. Un único SELECT; no escribe nada.
with clasif as (
  select ct.id, ct.numero_contrato, ct.cliente_id, ct.moneda, ct.estado, ct.es_demo, ct.capital, ct.creado_en,
         q.en_moneda, q.otra_moneda,
         case
           when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
           when cp.id is not null then 'cuenta_no_corresponde'
           when q.en_moneda = 1 then 'una_cuenta'
           when q.en_moneda > 1 then 'varias_cuentas'
           when q.otra_moneda > 0 then 'otra_moneda'
           else 'sin_cuenta'
         end as caso
  from public.contratos ct
  left join crm.contrato_cuentas_pago cp on cp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  cross join lateral (
    select count(*) filter (where a.activa and a.moneda = ct.moneda) as en_moneda,
           count(*) filter (where a.activa and a.moneda <> ct.moneda) as otra_moneda
    from crm.cuentas_bancarias a where a.cliente_id = ct.cliente_id
  ) q
), cuotas as (
  select cp.contrato_id,
         count(*) filter (where cp.estado <> 'pagado') as sin_pagar,
         count(*) filter (where cp.estado <> 'pagado' and cp.fecha_programada < (now() at time zone 'America/Lima')::date) as vencidas,
         coalesce(sum(cp.monto_programado) filter (where cp.estado <> 'pagado' and cp.fecha_programada < (now() at time zone 'America/Lima')::date), 0) as monto_vencido,
         min(cp.fecha_programada) filter (where cp.estado <> 'pagado') as proxima,
         min(cp.monto_programado) filter (where cp.estado <> 'pagado' and cp.fecha_programada = (select min(x.fecha_programada) from public.cronograma_pagos x where x.contrato_id = cp.contrato_id and x.estado <> 'pagado')) as monto_proxima
  from public.cronograma_pagos cp
  where cp.contrato_id in (select id from clasif where caso <> 'ok')
  group by cp.contrato_id
)
select jsonb_pretty(jsonb_build_object(
  'medido_en_lima', to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
  'por_caso', (select jsonb_object_agg(caso, n) from (select caso, count(*) n from clasif group by caso) s),
  'lista', (select jsonb_agg(jsonb_build_object(
              'contrato', c.numero_contrato, 'moneda', c.moneda, 'estado', c.estado, 'demo', c.es_demo, 'caso', c.caso,
              'capital', c.capital,
              'cliente', coalesce(nullif(trim(p.nombre_completo), ''), trim(concat_ws(' ', p.apellidos, p.nombres))),
              'telefono', coalesce(p.whatsapp, p.telefono), 'correo', p.correo,
              'creado', to_char((c.creado_en at time zone 'America/Lima')::date, 'YYYY-MM-DD'),
              'cuotas_sin_pagar', coalesce(k.sin_pagar, 0), 'cuotas_vencidas', coalesce(k.vencidas, 0),
              'monto_vencido', coalesce(k.monto_vencido, 0), 'proxima_cuota', k.proxima, 'monto_proxima', k.monto_proxima,
              'cuentas_en_moneda', (
                 select jsonb_agg(jsonb_build_object('banco', a.banco, 'tipo', a.tipo_cuenta, 'origen', a.origen,
                          'creada', to_char((a.creado_en at time zone 'America/Lima')::date, 'YYYY-MM-DD'),
                          'contratos_que_ya_cobran_ahi', (select count(*) from crm.contrato_cuentas_pago l where l.cuenta_bancaria_id = a.id))
                        order by a.creado_en)
                 from crm.cuentas_bancarias a where a.cliente_id = c.cliente_id and a.moneda = c.moneda and a.activa),
              'cuentas_otra_moneda', (
                 select jsonb_agg(jsonb_build_object('banco', a.banco, 'moneda', a.moneda) order by a.creado_en)
                 from crm.cuentas_bancarias a where a.cliente_id = c.cliente_id and a.moneda <> c.moneda and a.activa)
            ) order by coalesce(k.vencidas, 0) desc, k.proxima nulls last, c.numero_contrato)
            from clasif c
            join public.perfiles p on p.id = c.cliente_id
            left join cuotas k on k.contrato_id = c.id
            where c.caso <> 'ok')
)) as lista;
