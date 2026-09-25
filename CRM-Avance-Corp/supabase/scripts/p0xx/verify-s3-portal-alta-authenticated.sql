-- SOLO RAMA P-0XX, con semilla ficticia S1. Prueba ACL como authenticated.
-- La transaccion se revierte: no deja contrato, cronograma ni vinculo.
begin;

select pg_catalog.set_config('request.jwt.claim.sub',
  'b0000000-0000-4000-8000-000000000003', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
update public.perfiles set domicilio = 'CALLE FICTICIA 5'
where id = 'c0000000-0000-4000-8000-000000000005';
update public.perfiles
   set dni = '99990002', telefono = '999000002',
       correo = 'p0xx.analista@example.invalid'
 where id = 'b0000000-0000-4000-8000-000000000002';
select pg_catalog.set_config('request.jwt.claim.sub',
  'b0000000-0000-4000-8000-000000000002', true);

set local role authenticated;
do $verify$
declare
  v_cuenta uuid;
  v_resultado jsonb;
begin
  select cuenta_id into v_cuenta
  from crm.cuentas_bancarias_cliente_fn(
    'c0000000-0000-4000-8000-000000000005', 'PEN')
  order by creada_en desc, cuenta_id desc limit 1;
  if v_cuenta is null then
    raise exception 'El analista no ve ninguna cuenta activa de su cliente';
  end if;

  v_resultado := crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object(
      'cliente_id', 'c0000000-0000-4000-8000-000000000005',
      'numero_contrato', '2026-01-999997',
      'capital', 1000, 'moneda', 'PEN', 'tasa_anual', 12,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'categoria', 'nuevo', 'fecha_inicio', '2026-09-25',
      'fecha_vencimiento', '2027-09-25', 'titulares', '[]'::jsonb,
      'clave_idempotencia', 'f0000000-0000-4000-8000-000000000002'),
    '[{"numero_cuota":1,"fecha_programada":"2026-10-25","monto_programado":10,"tipo":"cuota"}]'::jsonb,
    jsonb_build_object('tipo', 'existente', 'cuenta_id', v_cuenta));
  if (v_resultado->>'id') is null then
    raise exception 'La RPC no devolvio contrato';
  end if;
  perform pg_catalog.set_config('p0xx.s3_contrato_id', v_resultado->>'id', true);
  perform pg_catalog.set_config('p0xx.s3_cuenta_id', v_cuenta::text, true);
end;
$verify$;
reset role;

do $verify$
declare
  v_contrato uuid := pg_catalog.current_setting('p0xx.s3_contrato_id')::uuid;
  v_cuenta uuid := pg_catalog.current_setting('p0xx.s3_cuenta_id')::uuid;
begin
  if not exists (
    select 1 from crm.contrato_cuentas_pago cp
    where cp.contrato_id = v_contrato and cp.cuenta_bancaria_id = v_cuenta
      and cp.creado_por = 'b0000000-0000-4000-8000-000000000002'
  ) or not exists (
    select 1 from public.cronograma_pagos where contrato_id = v_contrato
  ) then
    raise exception 'Falta contrato, cronograma o vinculo de la RPC authenticated';
  end if;
end;
$verify$;

rollback;
select 'PASS: alta autenticada con cuenta contractual; transaccion revertida' as resultado;
