-- SOLO RAMA hhpjiygytwoayxymziqo, con la siembra S1. Toda mutacion se revierte.
begin;
set local lock_timeout = '10s';

do $precondicion$
begin
  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.registrar_cuenta_cliente(uuid,jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege(
       'authenticated', 'private.registrar_cuenta_cliente_hecho(uuid,text,jsonb,uuid)', 'EXECUTE')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'SELECT') then
    raise exception 'S2: permisos de RPC o tabla inesperados';
  end if;
end;
$precondicion$;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data
) values
  ('c0000000-0000-4000-8000-000000000008',
   '00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.s2.alta@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000009',
   '00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.s2.invalido@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb);

set local role service_role;
set local request.jwt.claim.role = 'service_role';
do $alta_atomica$
declare
  v_id uuid;
begin
  v_id := crm.crear_perfil_cliente_con_cuentas(
    '{"id":"c0000000-0000-4000-8000-000000000008","nombre_completo":"P0XX ALTA S2","tipo_documento":"PASAPORTE","dni":"P0XX0008","correo":"p0xx.s2.alta@example.invalid","debe_cambiar_password":true}'::jsonb,
    '[{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TESTALTA8","cci":"00000000000000000018"},{"moneda":"USD","banco":"BCP","tipo_cuenta":"corriente","numero_cuenta":"TESTUSD8","cci":"00000000000000000019"}]'::jsonb,
    'b0000000-0000-4000-8000-000000000003');
  if v_id is distinct from 'c0000000-0000-4000-8000-000000000008'::uuid then
    raise exception 'S2: alta atomica no devolvio cliente';
  end if;
  -- Respuesta HTTP perdida: repetir no crea mas versiones ni altera el perfil.
  perform crm.crear_perfil_cliente_con_cuentas(
    '{"id":"c0000000-0000-4000-8000-000000000008","nombre_completo":"P0XX ALTA S2","tipo_documento":"PASAPORTE","dni":"P0XX0008","correo":"p0xx.s2.alta@example.invalid","debe_cambiar_password":true}'::jsonb,
    '[{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TESTALTA8","cci":"00000000000000000018"},{"moneda":"USD","banco":"BCP","tipo_cuenta":"corriente","numero_cuenta":"TESTUSD8","cci":"00000000000000000019"}]'::jsonb,
    'b0000000-0000-4000-8000-000000000003');
  begin
    perform crm.crear_perfil_cliente_con_cuentas(
      '{"id":"c0000000-0000-4000-8000-000000000009","nombre_completo":"P0XX ALTA INVALIDA","tipo_documento":"PASAPORTE","dni":"P0XX0009","correo":"p0xx.s2.invalido@example.invalid"}'::jsonb,
      '[{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TESTOK9","cci":"00000000000000000020"},{"moneda":"USD","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TESTBAD9","cci":"9"}]'::jsonb,
      'b0000000-0000-4000-8000-000000000003');
    raise exception 'S2: alta con USD invalida fue aceptada';
  exception when invalid_parameter_value then
    null;
  end;
end;
$alta_atomica$;
reset role;
do $alta_integridad$
begin
  if (select count(*) from crm.cuentas_bancarias
      where cliente_id = 'c0000000-0000-4000-8000-000000000008'
        and activa and creado_por = 'b0000000-0000-4000-8000-000000000003') <> 2
     or not exists (
       select 1 from public.perfiles
       where id = 'c0000000-0000-4000-8000-000000000008'
         and creado_por = 'b0000000-0000-4000-8000-000000000003'
         and banco is null and banco_usd is null)
     or exists (
       select 1 from public.perfiles
       where id = 'c0000000-0000-4000-8000-000000000009')
     or exists (
       select 1 from crm.cuentas_bancarias
       where cliente_id = 'c0000000-0000-4000-8000-000000000009')
     or (select count(*) from public.audit_log a
         where a.tabla = 'crm.cuentas_bancarias'
           and a.data_despues->>'cliente_id' = 'c0000000-0000-4000-8000-000000000008'
           and a.data_despues->>'creado_por' = 'b0000000-0000-4000-8000-000000000003') <> 2 then
    raise exception 'S2: alta atomica, reintento o rollback incorrecto';
  end if;
end;
$alta_integridad$;

-- Una respuesta tardia del alta no debe reactivar una cuenta desactivada.
update crm.cuentas_bancarias
   set activa = false,
       desactivada_por = 'b0000000-0000-4000-8000-000000000003',
       desactivada_en = pg_catalog.clock_timestamp()
 where cliente_id = 'c0000000-0000-4000-8000-000000000008' and moneda = 'PEN';
set local role service_role;
set local request.jwt.claim.role = 'service_role';
do $no_resucitar$
begin
  begin
    perform crm.crear_perfil_cliente_con_cuentas(
      '{"id":"c0000000-0000-4000-8000-000000000008","nombre_completo":"P0XX ALTA S2","tipo_documento":"PASAPORTE","dni":"P0XX0008","correo":"p0xx.s2.alta@example.invalid","debe_cambiar_password":true}'::jsonb,
      '[{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TESTALTA8","cci":"00000000000000000018"},{"moneda":"USD","banco":"BCP","tipo_cuenta":"corriente","numero_cuenta":"TESTUSD8","cci":"00000000000000000019"}]'::jsonb,
      'b0000000-0000-4000-8000-000000000003');
    raise exception 'S2: se reactivo una cuenta desactivada';
  exception when sqlstate 'P0409' then null;
  end;
end;
$no_resucitar$;
reset role;
do $sin_resurreccion$
begin
  if exists (select 1 from crm.cuentas_bancarias
      where cliente_id = 'c0000000-0000-4000-8000-000000000008'
        and moneda = 'PEN' and activa) then
    raise exception 'S2: cuenta historica activa tras retry';
  end if;
end;
$sin_resurreccion$;

-- La puerta service_role tampoco acepta un actor CRM revocado.
set local role service_role;
set local request.jwt.claim.role = 'service_role';
do $revocado$
begin
  begin
    update crm.equipo set activo = false
    where perfil_id = 'b0000000-0000-4000-8000-000000000003';
    perform crm.crear_perfil_cliente_con_cuentas(
      '{"id":"c0000000-0000-4000-8000-000000000009","nombre_completo":"P0XX ALTA REVOCADA","tipo_documento":"PASAPORTE","dni":"P0XX0009","correo":"p0xx.s2.invalido@example.invalid"}'::jsonb,
      '[{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TESTOK9","cci":"00000000000000000020"}]'::jsonb,
      'b0000000-0000-4000-8000-000000000003');
    raise exception 'S2: actor revocado pudo crear cuentas';
  exception when insufficient_privilege then null;
  end;
end;
$revocado$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000004';
do $fuera_cartera$
begin
  begin
    perform crm.registrar_cuenta_cliente(
      'c0000000-0000-4000-8000-000000000005',
      '{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TEST6087","cci":"00000000000000000006"}'::jsonb);
    raise exception 'S2: vendedor fuera de cartera pudo registrar cuenta';
  exception when insufficient_privilege then
    null;
  end;
end;
$fuera_cartera$;

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000002';
do $versionar$
declare
  v_igual uuid;
  v_nueva uuid;
  v_reintento uuid;
begin
  v_igual := crm.registrar_cuenta_cliente(
    'c0000000-0000-4000-8000-000000000005',
    '{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TEST6087","cci":"00000000000000000006"}'::jsonb);
  if v_igual is distinct from 'e0000000-0000-4000-8000-000000000003'::uuid then
    raise exception 'S2: la cuenta identica no fue idempotente';
  end if;

  v_nueva := crm.registrar_cuenta_cliente(
    'c0000000-0000-4000-8000-000000000005',
    '{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TEST6088","cci":"00000000000000000006"}'::jsonb);
  v_reintento := crm.registrar_cuenta_cliente(
    'c0000000-0000-4000-8000-000000000005',
    '{"moneda":"PEN","banco":"BCP","tipo_cuenta":"ahorros","numero_cuenta":"TEST6088","cci":"00000000000000000006"}'::jsonb);
  if v_nueva is null or v_nueva = v_igual or v_reintento is distinct from v_nueva then
    raise exception 'S2: version o reintento bancario incorrecto';
  end if;
  if (select count(*) from crm.cuentas_bancarias_cliente_fn(
      'c0000000-0000-4000-8000-000000000005', 'PEN')) <> 1
     or not exists (
       select 1 from crm.cuentas_bancarias_cliente_fn(
         'c0000000-0000-4000-8000-000000000005', 'PEN')
       where cuenta_id = v_nueva and origen = 'portal') then
    raise exception 'S2: lectura vigente no refleja la version portal';
  end if;

  begin
    update public.perfiles set banco = 'OTRO'
    where id = 'c0000000-0000-4000-8000-000000000005';
    raise exception 'S2: perfiles permitio una escritura bancaria';
  exception when invalid_parameter_value then
    null;
  end;
end;
$versionar$;

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000003';
do $gerencia$
begin
  begin
    perform crm.actualizar_cliente_gerencia_con_domicilio(
      'c0000000-0000-4000-8000-000000000005',
      '{"domicilio":"Av. Prueba 123, Lima","banco":"BCP"}'::jsonb);
    raise exception 'S2: Gerencia acepto claves bancarias en el patch';
  exception when invalid_parameter_value then
    if position('registrar_cuenta_cliente' in sqlerrm) = 0 then
      raise exception 'S2: el rechazo bancario no fue claro';
    end if;
  end;
end;
$gerencia$;

reset role;
do $integridad$
begin
  if (select count(*) from crm.cuentas_bancarias
      where cliente_id = 'c0000000-0000-4000-8000-000000000005'
        and moneda = 'PEN' and cci = '00000000000000000006'
        and activa and origen = 'portal'
        and creado_por = 'b0000000-0000-4000-8000-000000000002') <> 1
     or not exists (
       select 1 from crm.cuentas_bancarias
       where id = 'e0000000-0000-4000-8000-000000000003'
         and activa is false
         and desactivada_por = 'b0000000-0000-4000-8000-000000000002')
     or not exists (
       select 1 from crm.contrato_cuentas_pago
       where contrato_id = 'd0000000-0000-4000-8000-000000000006'
         and cuenta_bancaria_id = 'e0000000-0000-4000-8000-000000000003') then
    raise exception 'S2: version, actor o vinculo historico incorrecto';
  end if;
  if exists (
    select 1 from public.perfiles
    where id = 'c0000000-0000-4000-8000-000000000005'
      and (banco is not null or numero_cuenta is not null or cci is not null)
  ) then
    raise exception 'S2: el RPC escribio la banca legado';
  end if;
  if exists (
    select 1 from public.audit_log a
    where a.tabla = 'crm.cuentas_bancarias'
      and (a.data_antes ?| array['numero_cuenta','cci','beneficiario_dni']
        or a.data_despues ?| array['numero_cuenta','cci','beneficiario_dni'])
  ) then
    raise exception 'S2: la auditoria contiene banca sin redactar';
  end if;
end;
$integridad$;
rollback;
