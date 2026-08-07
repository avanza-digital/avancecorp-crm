-- LEGACY / SOLO HISTORIA PRE-20260807203757.
-- No ejecutar como gate vigente: prueba crm.objetivos + fijar_objetivos(),
-- superficies retiradas. El reemplazo es test-metas-versionadas.sql.
-- Oraculo transaccional autocontenido de metas comerciales (crm.objetivos).
-- Exito = token OBJETIVOS_TX_OK; todo queda en rollback.

begin;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('16000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'obj-g@test.invalid', now(), '{}', '{}', now(), now()),
  ('16000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'obj-v@test.invalid', now(), '{}', '{}', now(), now()),
  ('16000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'obj-s@test.invalid', now(), '{}', '{}', now(), now()),
  ('16000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'obj-d@test.invalid', now(), '{}', '{}', now(), now()),
  ('16000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'obj-g-disabled@test.invalid', now(), '{}', '{}', now(), now()),
  ('16000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'obj-cliente@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('16000000-0000-4000-8000-000000000001', 'Objetivos Gerencia', 'obj-g@test.invalid', 'directorio', true),
  ('16000000-0000-4000-8000-000000000002', 'Objetivos Vendedor', 'obj-v@test.invalid', 'comercial', true),
  ('16000000-0000-4000-8000-000000000003', 'Objetivos Supervisor', 'obj-s@test.invalid', 'comercial', true),
  ('16000000-0000-4000-8000-000000000004', 'Objetivos Directorio', 'obj-d@test.invalid', 'directorio', true),
  ('16000000-0000-4000-8000-000000000005', 'Gerencia Portal Inactiva', 'obj-g-disabled@test.invalid', 'directorio', false),
  ('16000000-0000-4000-8000-000000000006', 'Cliente Sin CRM', 'obj-cliente@test.invalid', 'cliente', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('16000000-0000-4000-8000-000000000001', 'gerencia', null, true),
  ('16000000-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('16000000-0000-4000-8000-000000000002', 'vendedor', '16000000-0000-4000-8000-000000000003', true),
  ('16000000-0000-4000-8000-000000000005', 'gerencia', null, true);

-- ── Gerencia fija las metas del mes (camino feliz + upsert) ──────────────────
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $test$
declare
  v_filas int;
begin
  select count(*) into v_filas
  from crm.fijar_objetivos(
    date '2026-07-01',
    '{"vendedor":{"capital_objetivo":250000,"ventas_objetivo":3,"conversion_objetivo":25},
      "supervisor":{"capital_objetivo":500000,"ventas_objetivo":6,"conversion_objetivo":25},
      "gerencia":{"capital_objetivo":1000000,"ventas_objetivo":12,"conversion_objetivo":28}}'::jsonb
  );
  if v_filas <> 3 then
    raise exception 'O01 fijar_objetivos no devolvio las 3 filas del periodo';
  end if;

  if (select capital_objetivo from crm.objetivos
      where periodo = date '2026-07-01' and rol = 'vendedor') <> 250000 then
    raise exception 'O02 no guardo la meta del vendedor';
  end if;

  -- Upsert parcial: solo vendedor cambia; el resto queda; devuelve el periodo entero.
  select count(*) into v_filas
  from crm.fijar_objetivos(
    date '2026-07-01',
    '{"vendedor":{"capital_objetivo":300000,"ventas_objetivo":4,"conversion_objetivo":30}}'::jsonb
  );
  if v_filas <> 3 then
    raise exception 'O03 el upsert parcial no devolvio el periodo entero';
  end if;
  if (select capital_objetivo from crm.objetivos
      where periodo = date '2026-07-01' and rol = 'vendedor') <> 300000 then
    raise exception 'O03b el upsert parcial no actualizo al vendedor';
  end if;
  if (select capital_objetivo from crm.objetivos
      where periodo = date '2026-07-01' and rol = 'gerencia') <> 1000000 then
    raise exception 'O03c el upsert parcial piso la meta de gerencia';
  end if;

  -- Validaciones (todas 22023).
  begin
    perform crm.fijar_objetivos(date '2026-07-15',
      '{"vendedor":{"capital_objetivo":1}}'::jsonb);
    raise exception 'O04 acepto periodo que no es primer dia de mes';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform crm.fijar_objetivos(date '2026-07-01', '{}'::jsonb);
    raise exception 'O05 acepto payload vacio';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"analista":{"capital_objetivo":1}}'::jsonb);
    raise exception 'O06 acepto un rol desconocido';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"vendedor":{"conversion_objetivo":120}}'::jsonb);
    raise exception 'O07 acepto conversion sobre 100';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"vendedor":{"ventas_objetivo":-1}}'::jsonb);
    raise exception 'O08 acepto ventas negativas';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"vendedor":{"capital_objetivo":-5}}'::jsonb);
    raise exception 'O09 acepto capital negativo';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"vendedor":{"capital_objetivo":"abc"}}'::jsonb);
    raise exception 'O10 acepto numeros basura';
  exception when invalid_parameter_value then null;
  end;
end;
$test$;
reset role;

-- ── Vendedor: lee las metas, no las escribe ──────────────────────────────────
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.objetivos where periodo = date '2026-07-01') <> 3 then
    raise exception 'O11 el vendedor no ve las metas del mes';
  end if;
  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"vendedor":{"capital_objetivo":1}}'::jsonb);
    raise exception 'O12 un vendedor fijo metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── Supervisor: lee, no escribe ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.objetivos where periodo = date '2026-07-01') <> 3 then
    raise exception 'O13 el supervisor no ve las metas del mes';
  end if;
  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"supervisor":{"capital_objetivo":1}}'::jsonb);
    raise exception 'O14 un supervisor fijo metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── Directorio (lector global sin rol CRM): audita, no escribe ───────────────
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.objetivos where periodo = date '2026-07-01') <> 3 then
    raise exception 'O15 Directorio no pudo auditar las metas';
  end if;
  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"gerencia":{"capital_objetivo":1}}'::jsonb);
    raise exception 'O16 Directorio fijo metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── Gerencia con perfil de portal desactivado: sin autoridad ─────────────────
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000005', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.fijar_objetivos(date '2026-07-01',
      '{"gerencia":{"capital_objetivo":1}}'::jsonb);
    raise exception 'O17 Gerencia con perfil desactivado fijo metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── Cliente del portal sin rol CRM: cero filas (fail-closed) ─────────────────
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000006', true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.objetivos) <> 0 then
    raise exception 'O18 un cliente del portal ve las metas comerciales';
  end if;
end;
$test$;
reset role;

-- ── Privilegios duros y auditoria ────────────────────────────────────────────
do $test$
begin
  if has_table_privilege('authenticated', 'crm.objetivos', 'INSERT')
     or has_table_privilege('authenticated', 'crm.objetivos', 'UPDATE')
     or has_table_privilege('authenticated', 'crm.objetivos', 'DELETE') then
    raise exception 'O19 authenticated tiene escritura directa sobre objetivos';
  end if;

  if has_table_privilege('anon', 'crm.objetivos', 'SELECT')
     or has_function_privilege('anon', 'crm.fijar_objetivos(date,jsonb)', 'EXECUTE') then
    raise exception 'O20 anon tiene acceso a las metas';
  end if;

  if not exists (
    select 1 from public.audit_log
    where tabla = 'crm.objetivos'
      and operacion = 'INSERT'
      and usuario_id = '16000000-0000-4000-8000-000000000001'
      and fila_id is not null
      and data_despues ->> 'rol' = 'vendedor'
  ) then
    raise exception 'O21 el alta de metas no quedo auditada';
  end if;

  if not exists (
    select 1 from public.audit_log
    where tabla = 'crm.objetivos'
      and operacion = 'UPDATE'
      and usuario_id = '16000000-0000-4000-8000-000000000001'
      and fila_id is not null
      and data_despues ->> 'capital_objetivo' = '300000.00'
  ) then
    raise exception 'O22 el upsert de metas no quedo auditado';
  end if;
end;
$test$;

select jsonb_build_object(
  'resultado', 'OBJETIVOS_TX_OK',
  'metas', (
    select jsonb_object_agg(rol, jsonb_build_object(
      'capital', capital_objetivo, 'ventas', ventas_objetivo, 'conversion', conversion_objetivo))
    from crm.objetivos where periodo = date '2026-07-01'
  )
) as validacion;

rollback;
