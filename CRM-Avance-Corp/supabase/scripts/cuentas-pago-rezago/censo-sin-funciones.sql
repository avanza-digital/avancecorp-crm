-- SOLO LECTURA. Censo de contratos frente al bloqueo de pagos, SIN usar ninguna función: sirve
-- antes de la migración 20261001233019, después de revertirla, y como segunda opinión del
-- diagnóstico (private.cuenta_pago_diagnostico) cuando está instalada.
-- No devuelve nombres, documentos, números de cuenta ni CCI: solo número de contrato, moneda,
-- banco y conteos. Un único SELECT; no escribe nada.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/censo-sin-funciones.sql
with clasif as (
  select ct.id, ct.numero_contrato, ct.cliente_id, ct.moneda, ct.estado, ct.es_demo, ct.creado_en,
         q.en_moneda, q.otra_moneda, q.inactivas_en_moneda,
         cb.activa as vinculo_cuenta_activa,
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
           count(*) filter (where a.activa and a.moneda <> ct.moneda) as otra_moneda,
           count(*) filter (where not a.activa and a.moneda = ct.moneda) as inactivas_en_moneda
    from crm.cuentas_bancarias a
    where a.cliente_id = ct.cliente_id
  ) q
), cuotas as (
  select cp.contrato_id,
         count(*) filter (where cp.estado = 'pagado') as pagadas,
         count(*) filter (where cp.estado <> 'pagado') as sin_pagar,
         min(cp.fecha_programada) filter (where cp.estado <> 'pagado') as proxima
  from public.cronograma_pagos cp
  where cp.contrato_id in (select id from clasif where caso <> 'ok')
  group by cp.contrato_id
)
select jsonb_pretty(jsonb_build_object(
  'medido_en_lima', to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
  'total_contratos', (select count(*) from clasif),
  'por_caso', (select jsonb_object_agg(caso, n) from (select caso, count(*) n from clasif group by caso) s),
  'ok_con_cuenta_vinculada_inactiva', (select count(*) from clasif where caso = 'ok' and vinculo_cuenta_activa is false),
  'no_ok', (select jsonb_agg(jsonb_build_object(
              'contrato', c.numero_contrato, 'moneda', c.moneda, 'estado', c.estado, 'demo', c.es_demo,
              'caso', c.caso,
              'creado', to_char((c.creado_en at time zone 'America/Lima')::date, 'YYYY-MM-DD'),
              'cuentas_en_moneda', c.en_moneda, 'cuentas_otra_moneda', c.otra_moneda,
              'inactivas_en_moneda', c.inactivas_en_moneda,
              'cuotas_pagadas', coalesce(k.pagadas, 0), 'cuotas_sin_pagar', coalesce(k.sin_pagar, 0),
              'proxima_cuota', k.proxima,
              -- Para que Operaciones confirme en cuál cobra: banco, de dónde salió la cuenta y
              -- cuántos contratos del cliente ya cobran ahí. Sin número ni CCI.
              'cuentas_activas_en_moneda', (
                 select jsonb_agg(jsonb_build_object(
                          'banco', a.banco, 'origen', a.origen,
                          'creada', to_char((a.creado_en at time zone 'America/Lima')::date, 'YYYY-MM-DD'),
                          'contratos_que_ya_cobran_ahi', (select count(*) from crm.contrato_cuentas_pago l
                                                          where l.cuenta_bancaria_id = a.id))
                        order by a.creado_en)
                 from crm.cuentas_bancarias a
                 where a.cliente_id = c.cliente_id and a.moneda = c.moneda and a.activa)
            ) order by c.caso, c.numero_contrato)
            from clasif c left join cuotas k on k.contrato_id = c.id
            where c.caso <> 'ok'),
  'bloqueo', (select jsonb_build_object('md5_prosrc', md5(p.prosrc), 'definer', p.prosecdef,
                                        'config', p.proconfig, 'acl', p.proacl::text)
              from pg_proc p where p.oid = to_regprocedure('private.exigir_cuenta_pago_cronograma()')),
  'vinculos_de_la_carga', (select jsonb_build_object('vigentes', count(*) filter (where b.revertida_en is null),
                                                     'revertidos', count(b.revertida_en))
                           from private.backfill_cuentas_p0xx b
                           where b.tipo = 'vinculo' and b.marca_actor = 'migracion:rezago-vinculos:20261001')
)) as censo;
