-- SOLO RAMA P-0XX. Simula la RPC que usan las dos pantallas del portal.
-- La excepcion final revierte contrato, cronograma, vinculo, PDF y clave.
do $verify$
declare
  v_cliente constant uuid := 'c0000000-0000-4000-8000-000000000005';
  v_actor constant uuid := 'b0000000-0000-4000-8000-000000000002';
  v_cuenta uuid;
  v_contrato jsonb;
  v_cronograma jsonb := '[{"numero_cuota":1,"fecha_programada":"2026-10-25","monto_programado":10,"tipo":"cuota"}]'::jsonb;
  v_resultado jsonb;
  v_repetido jsonb;
  v_id uuid;
begin
  begin
    perform pg_catalog.set_config('request.jwt.claim.sub',
      'b0000000-0000-4000-8000-000000000003', true);
    perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
    -- La semilla S1 omitio datos legales ajenos al backfill. Se completan solo
    -- dentro de esta subtransaccion, sin tocar cuentas ni datos reales.
    update public.perfiles set domicilio = 'CALLE FICTICIA 5'
    where id = v_cliente;
    update public.perfiles
       set dni = '99990002', telefono = '999000002',
           correo = 'p0xx.analista@example.invalid'
     where id = v_actor;
    perform pg_catalog.set_config('request.jwt.claim.sub', v_actor::text, true);
    select cuenta_id into v_cuenta
    from crm.cuentas_bancarias_cliente_fn(v_cliente, 'PEN')
    order by creada_en desc, cuenta_id desc limit 1;
    if v_cuenta is null then
      raise exception 'El analista no ve ninguna cuenta activa de su cliente';
    end if;

    v_contrato := jsonb_build_object(
      'cliente_id', v_cliente,
      'numero_contrato', '2026-01-999998',
      'capital', 1000, 'moneda', 'PEN', 'tasa_anual', 12,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'categoria', 'nuevo', 'fecha_inicio', '2026-09-25',
      'fecha_vencimiento', '2027-09-25', 'titulares', '[]'::jsonb,
      'clave_idempotencia', 'f0000000-0000-4000-8000-000000000001');

    v_resultado := crm.crear_contrato_con_cuenta_pdf_v2(
      v_contrato, v_cronograma,
      jsonb_build_object('tipo', 'existente', 'cuenta_id', v_cuenta));
    v_id := (v_resultado->>'id')::uuid;
    if v_id is null or not exists (
      select 1 from crm.contrato_cuentas_pago cp
      where cp.contrato_id = v_id and cp.cuenta_bancaria_id = v_cuenta
        and cp.creado_por = v_actor
    ) or not exists (
      select 1 from public.cronograma_pagos where contrato_id = v_id
    ) then
      raise exception 'El portal no creo contrato, cronograma y vinculo juntos';
    end if;

    v_repetido := crm.crear_contrato_con_cuenta_pdf_v2(
      v_contrato, v_cronograma,
      jsonb_build_object('tipo', 'existente', 'cuenta_id', v_cuenta));
    if (v_repetido->>'id')::uuid is distinct from v_id
       or (v_repetido->>'idempotente')::boolean is distinct from true then
      raise exception 'El reintento del portal no fue idempotente';
    end if;

    raise exception using errcode = 'P0001', message = 'P0XX_S3_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> 'P0XX_S3_ROLLBACK' then raise; end if;
  end;
end;
$verify$;

select 'PASS: alta portal con cuenta elegida, vinculo y replay idempotente; prueba revertida' as resultado;
