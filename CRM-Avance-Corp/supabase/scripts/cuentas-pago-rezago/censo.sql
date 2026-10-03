-- SOLO LECTURA. Censo de contratos frente al bloqueo de pagos con la regla instalada por
-- 20261001233019 (private.cuenta_pago_diagnostico): cuántos hay de cada caso y cuáles no se
-- pueden pagar, con el mismo mensaje que ve quien registra el pago. Sin datos personales.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/censo.sql
-- Antes de la migración (o tras revertirla) usar censo-sin-funciones.sql.
select jsonb_pretty(jsonb_build_object(
  'medido_en_lima', to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
  'total_contratos', (select count(*) from private.cuenta_pago_diagnostico()),
  'por_caso', (select jsonb_object_agg(s.caso, s.n)
               from (select d.caso, count(*) n from private.cuenta_pago_diagnostico() d group by d.caso) s),
  'no_ok', (select jsonb_agg(jsonb_build_object(
              'contrato', d.numero_contrato, 'moneda', d.moneda, 'estado', d.estado, 'demo', d.es_demo,
              'caso', d.caso, 'cuentas_en_moneda', d.cuentas_en_moneda,
              'cuentas_otra_moneda', d.cuentas_otra_moneda, 'mensaje', d.mensaje)
              order by d.caso, d.numero_contrato)
            from private.cuenta_pago_diagnostico() d
            where d.caso <> 'ok'),
  'vinculos_de_la_carga', (select jsonb_agg(jsonb_build_object(
              'contrato', ct.numero_contrato,
              'vinculado', to_char(b.insertada_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
              'revertido', b.revertida_en is not null) order by ct.numero_contrato)
            from private.backfill_cuentas_p0xx b
            join public.contratos ct on ct.id = b.contrato_id
            where b.tipo = 'vinculo' and b.marca_actor = 'migracion:rezago-vinculos:20261001')
)) as censo;
