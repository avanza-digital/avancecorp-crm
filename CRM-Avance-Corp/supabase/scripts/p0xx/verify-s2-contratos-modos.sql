-- SOLO RAMA hhpjiygytwoayxymziqo. Las altas de prueba se revierten.
begin;
set local lock_timeout = '10s';
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000002';
set local request.jwt.claim.role = 'authenticated';

do $modos$
declare
  v_modo text;
  v_cliente uuid;
  v_moneda text;
  v_cuenta jsonb;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_cuenta_id uuid;
begin
  foreach v_modo in array array['existente', 'nueva', 'perfil'] loop
    case v_modo
      when 'existente' then
        v_cliente := 'c0000000-0000-4000-8000-000000000005';
        v_moneda := 'PEN';
        v_cuenta := jsonb_build_object(
          'tipo', 'existente',
          'cuenta_id', 'e0000000-0000-4000-8000-000000000003');
      when 'nueva' then
        v_cliente := 'c0000000-0000-4000-8000-000000000001';
        v_moneda := 'PEN';
        v_cuenta := jsonb_build_object(
          'tipo', 'nueva', 'banco', 'BCP', 'tipo_cuenta', 'ahorros',
          'numero_cuenta', 'TESTMODENEW', 'cci', '00000000000000000030',
          'titular_distinto', false);
      when 'perfil' then
        v_cliente := 'c0000000-0000-4000-8000-000000000006';
        v_moneda := 'PEN';
        v_cuenta := jsonb_build_object(
          'tipo', 'perfil',
          'cuenta_esperada', jsonb_build_object(
            'banco', 'BCP', 'tipo_cuenta', 'ahorros',
            'numero_cuenta', 'TESTPROFILE6', 'cci', '00000000000000000008',
            'titular_distinto', false,
            'beneficiario_nombre', null, 'beneficiario_dni', null));
    end case;

    v_resultado := crm.crear_contrato_con_cuenta(
      jsonb_build_object(
        'cliente_id', v_cliente, 'capital', 1000, 'moneda', v_moneda,
        'tasa_anual', 12, 'modalidad', 'mensual', 'tipo_interes', 'simple',
        'categoria', 'nuevo', 'fecha_inicio', '2026-09-25',
        'fecha_vencimiento', '2027-09-25',
        'analista_cierre_id', 'b0000000-0000-4000-8000-000000000002'),
      '[{"numero_cuota":1,"fecha_programada":"2026-10-25","monto_programado":10,"tipo":"cuota"}]'::jsonb,
      v_cuenta);
    v_contrato_id := (v_resultado->>'id')::uuid;
    v_cuenta_id := (v_resultado->>'cuenta_bancaria_id')::uuid;
    if v_contrato_id is null or v_cuenta_id is null or not exists (
      select 1 from crm.contrato_cuentas_pago cp
      join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
      where cp.contrato_id = v_contrato_id
        and cp.cuenta_bancaria_id = v_cuenta_id
        and cp.creado_por = 'b0000000-0000-4000-8000-000000000002'
        and cb.cliente_id = v_cliente and cb.moneda = v_moneda
    ) then
      raise exception 'S2: modo % sin vinculo coherente', v_modo;
    end if;
    raise notice 'S2: modo % OK', v_modo;
  end loop;
end;
$modos$;
rollback;
select 'PASS: existente, nueva y perfil; transaccion revertida' as verificacion;
