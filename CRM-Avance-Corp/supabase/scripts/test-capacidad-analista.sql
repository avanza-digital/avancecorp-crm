-- Oraculo transaccional autocontenido de capacidad objetivo por analista.

begin;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('13000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cap-v@test.invalid', now(), '{}', '{}', now(), now()),
  ('13000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'cap-s@test.invalid', now(), '{}', '{}', now(), now()),
  ('13000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'cap-g@test.invalid', now(), '{}', '{}', now(), now()),
  ('13000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'cap-d@test.invalid', now(), '{}', '{}', now(), now()),
  ('13000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'cap-i@test.invalid', now(), '{}', '{}', now(), now()),
  ('13000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'cap-g-disabled@test.invalid', now(), '{}', '{}', now(), now()),
  ('13000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'cap-target-disabled@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('13000000-0000-4000-8000-000000000001', 'Capacidad Analista', 'cap-v@test.invalid', 'comercial', true),
  ('13000000-0000-4000-8000-000000000002', 'Capacidad Supervisor', 'cap-s@test.invalid', 'comercial', true),
  ('13000000-0000-4000-8000-000000000003', 'Capacidad Gerencia', 'cap-g@test.invalid', 'directorio', true),
  ('13000000-0000-4000-8000-000000000004', 'Capacidad Directorio', 'cap-d@test.invalid', 'directorio', true),
  ('13000000-0000-4000-8000-000000000005', 'Capacidad Inactivo', 'cap-i@test.invalid', 'comercial', true),
  ('13000000-0000-4000-8000-000000000006', 'Gerencia Portal Inactiva', 'cap-g-disabled@test.invalid', 'directorio', false),
  ('13000000-0000-4000-8000-000000000007', 'Analista Portal Inactivo', 'cap-target-disabled@test.invalid', 'comercial', false);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('13000000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('13000000-0000-4000-8000-000000000001', 'vendedor', '13000000-0000-4000-8000-000000000002', true),
  ('13000000-0000-4000-8000-000000000003', 'gerencia', null, true),
  ('13000000-0000-4000-8000-000000000005', 'vendedor', '13000000-0000-4000-8000-000000000002', false),
  ('13000000-0000-4000-8000-000000000006', 'gerencia', null, true),
  ('13000000-0000-4000-8000-000000000007', 'vendedor', '13000000-0000-4000-8000-000000000002', true);

-- Gerencia configura vendedores y supervisores con cartera propia.
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select * from crm.actualizar_capacidad_leads_objetivo(
  '13000000-0000-4000-8000-000000000001', 25
);
select * from crm.actualizar_capacidad_leads_objetivo(
  '13000000-0000-4000-8000-000000000002', 8
);

do $test$
begin
  if (select capacidad_leads_objetivo from crm.equipo
      where perfil_id = '13000000-0000-4000-8000-000000000001') <> 25 then
    raise exception 'C01 no guardo capacidad del vendedor';
  end if;

  if (select capacidad_leads_objetivo from crm.equipo
      where perfil_id = '13000000-0000-4000-8000-000000000002') <> 8 then
    raise exception 'C02 no guardo capacidad del supervisor';
  end if;

  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000001', 0
    );
    raise exception 'C03 acepto capacidad cero';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000001', 1001
    );
    raise exception 'C04 acepto capacidad sobre el limite';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000005', 10
    );
    raise exception 'C05 configuro miembro inactivo';
  exception
    when no_data_found then null;
  end;

  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000003', 10
    );
    raise exception 'C06 configuro a Gerencia como analista';
  exception
    when no_data_found then null;
  end;

  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000007', 10
    );
    raise exception 'C07 configuro analista con perfil desactivado';
  exception
    when no_data_found then null;
  end;
end;
$test$;
reset role;

-- Un vendedor ve la capacidad de su roster, pero no puede cambiarla.
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000001', 30
    );
    raise exception 'C08 vendedor cambio capacidad';
  exception
    when insufficient_privilege then null;
  end;

  if (select capacidad_leads_objetivo
      from crm.equipo
      where perfil_id = '13000000-0000-4000-8000-000000000001') <> 25 then
    raise exception 'C09 roster no expone capacidad vigente';
  end if;
end;
$test$;
reset role;

-- Un supervisor tampoco puede configurar capacidades.
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000001', 30
    );
    raise exception 'C10 supervisor cambio capacidad';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Directorio conserva lectura global, nunca escritura.
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
begin
  if not exists (
    select 1 from crm.equipo
    where perfil_id = '13000000-0000-4000-8000-000000000001'
      and capacidad_leads_objetivo = 25
  ) then
    raise exception 'C11 Directorio no pudo auditar capacidad';
  end if;

  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000001', 30
    );
    raise exception 'C12 Directorio cambio capacidad';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Una Gerencia desactivada en public.perfiles no conserva autoridad,
-- aunque su fila de crm.equipo siga activa y su JWT aun sea valido.
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000006', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.actualizar_capacidad_leads_objetivo(
      '13000000-0000-4000-8000-000000000001', 30
    );
    raise exception 'C13 Gerencia con perfil desactivado cambio capacidad';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- NULL significa deliberadamente "sin configurar".
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select * from crm.actualizar_capacidad_leads_objetivo(
  '13000000-0000-4000-8000-000000000002', null
);
reset role;

do $test$
begin
  if (select capacidad_leads_objetivo is not null from crm.equipo
      where perfil_id = '13000000-0000-4000-8000-000000000002') then
    raise exception 'C14 no limpio capacidad';
  end if;

  if has_table_privilege('authenticated', 'crm.equipo', 'UPDATE') then
    raise exception 'C15 authenticated recibio UPDATE directo sobre equipo';
  end if;

  if has_function_privilege('anon', 'crm.actualizar_capacidad_leads_objetivo(uuid,integer)', 'EXECUTE') then
    raise exception 'C16 anon puede ejecutar actualizacion';
  end if;

  if not exists (
    select 1
    from public.audit_log
    where tabla = 'crm.equipo'
      and operacion = 'UPDATE'
      and fila_id = '13000000-0000-4000-8000-000000000001'
      and usuario_id = '13000000-0000-4000-8000-000000000003'
      and data_despues ->> 'capacidad_leads_objetivo' = '25'
  ) then
    raise exception 'C17 el cambio de capacidad no quedo auditado';
  end if;
end;
$test$;

select jsonb_build_object(
  'resultado', 'CAPACIDAD_TX_OK',
  'capacidad_vendedor', (select capacidad_leads_objetivo from crm.equipo
                         where perfil_id = '13000000-0000-4000-8000-000000000001'),
  'capacidad_supervisor', (select capacidad_leads_objetivo from crm.equipo
                           where perfil_id = '13000000-0000-4000-8000-000000000002')
) as validacion;

rollback;
