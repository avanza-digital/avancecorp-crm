-- Oraculo transaccional autocontenido del contrato 4B.
-- Exige la migracion aplicada y revierte todos sus fixtures.

begin;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('14000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'monto-v@test.invalid', now(), '{}', '{}', now(), now()),
  ('14000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'monto-s@test.invalid', now(), '{}', '{}', now(), now()),
  ('14000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'monto-g@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('14000000-0000-4000-8000-000000000001', 'Monto Analista', 'monto-v@test.invalid', 'comercial', true),
  ('14000000-0000-4000-8000-000000000002', 'Monto Supervisor', 'monto-s@test.invalid', 'comercial', true),
  ('14000000-0000-4000-8000-000000000003', 'Monto Gerencia', 'monto-g@test.invalid', 'directorio', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('14000000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('14000000-0000-4000-8000-000000000001', 'vendedor', '14000000-0000-4000-8000-000000000002', true),
  ('14000000-0000-4000-8000-000000000003', 'gerencia', null, true);

select set_config('request.jwt.claim.sub', '14000000-0000-4000-8000-000000000003', true);
set local role authenticated;

-- Ausente y NULL fallan por NOT NULL, no por otra regla incidental.
do $test$
begin
  begin
    insert into crm.leads (
      id, nombre_completo, telefono, origen, moneda, vendedor_id, creado_por
    ) values (
      '24000000-0000-4000-8000-000000000001', 'Monto ausente', '999400001',
      'landing', 'PEN', '14000000-0000-4000-8000-000000000001',
      '14000000-0000-4000-8000-000000000003'
    );
    raise exception 'M01 acepto monto ausente';
  exception
    when not_null_violation then null;
  end;

  begin
    insert into crm.leads (
      id, nombre_completo, telefono, origen, monto_estimado, moneda,
      vendedor_id, creado_por
    ) values (
      '24000000-0000-4000-8000-000000000002', 'Monto nulo', '999400002',
      'landing', null, 'PEN', '14000000-0000-4000-8000-000000000001',
      '14000000-0000-4000-8000-000000000003'
    );
    raise exception 'M02 acepto monto nulo';
  exception
    when not_null_violation then null;
  end;
end;
$test$;

-- El CHECK rechaza signo, exceso de decimales y overflow comercial sin redondear.
do $test$
declare
  v_monto numeric;
  v_telefono text;
  v_id uuid;
  v_n integer := 0;
begin
  foreach v_monto in array array[
    0::numeric,
    (-1)::numeric,
    0.001::numeric,
    5000.999::numeric,
    10000000000::numeric
  ] loop
    v_n := v_n + 1;
    v_id := gen_random_uuid();
    v_telefono := '99941' || lpad(v_n::text, 4, '0');
    begin
      insert into crm.leads (
        id, nombre_completo, telefono, origen, monto_estimado, moneda,
        vendedor_id, creado_por
      ) values (
        v_id, 'Monto fuera de contrato', v_telefono, 'landing', v_monto, 'PEN',
        '14000000-0000-4000-8000-000000000001',
        '14000000-0000-4000-8000-000000000003'
      );
      raise exception 'M03 acepto monto fuera de contrato: %', v_monto;
    exception
      when check_violation then null;
    end;
  end loop;
end;
$test$;

-- Bordes validos en ambas monedas. Ambos abren snapshots positivos del ledger.
insert into crm.leads (
  id, nombre_completo, telefono, origen, monto_estimado, moneda,
  vendedor_id, creado_por
)
values
  (
    '24000000-0000-4000-8000-000000000010', 'Monto minimo PEN', '999400010',
    'landing', 0.01, 'PEN', '14000000-0000-4000-8000-000000000001',
    '14000000-0000-4000-8000-000000000003'
  ),
  (
    '24000000-0000-4000-8000-000000000011', 'Monto maximo USD', '999400011',
    'formulario', 9999999999.99, 'USD', '14000000-0000-4000-8000-000000000001',
    '14000000-0000-4000-8000-000000000003'
  );

-- Una representacion con cero decimal adicional no cambia el valor y es valida.
update crm.leads
set monto_estimado = 5000.990
where id = '24000000-0000-4000-8000-000000000010';

do $test$
begin
  begin
    update crm.leads
    set monto_estimado = null
    where id = '24000000-0000-4000-8000-000000000010';
    raise exception 'M04 update acepto NULL';
  exception
    when not_null_violation then null;
  end;

  begin
    update crm.leads
    set monto_estimado = 0
    where id = '24000000-0000-4000-8000-000000000010';
    raise exception 'M05 update acepto cero';
  exception
    when check_violation then null;
  end;

  begin
    update crm.leads
    set monto_estimado = 5000.999
    where id = '24000000-0000-4000-8000-000000000010';
    raise exception 'M06 update redondeo tres decimales';
  exception
    when check_violation then null;
  end;
end;
$test$;

reset role;

do $test$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'crm'
      and table_name = 'leads'
      and column_name = 'monto_estimado'
      and (is_nullable <> 'NO' or numeric_precision is not null or numeric_scale is not null)
  ) then
    raise exception 'M07 catalogo no refleja numeric sin typmod + NOT NULL';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'crm'
      and t.relname = 'leads'
      and c.conname = 'leads_monto_estimado_valido'
      and c.convalidated
  ) then
    raise exception 'M08 constraint validado no existe';
  end if;

  if (select monto_estimado from crm.leads
      where id = '24000000-0000-4000-8000-000000000010') <> 5000.990 then
    raise exception 'M09 update valido no persistio';
  end if;

  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '24000000-0000-4000-8000-000000000010'
      and finalizado_en is null
      and monto_estimado = 0.01
      and moneda = 'PEN'
  ) or not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '24000000-0000-4000-8000-000000000011'
      and finalizado_en is null
      and monto_estimado = 9999999999.99
      and moneda = 'USD'
  ) then
    raise exception 'M10 ledger no fotografio las parejas exactas monto/moneda';
  end if;

  if (select monto_estimado from crm.lead_asignaciones
      where lead_id = '24000000-0000-4000-8000-000000000010'
        and finalizado_en is null) <> 0.01 then
    raise exception 'M11 recalificacion reescribio snapshot del ledger';
  end if;
end;
$test$;

select jsonb_build_object(
  'resultado', 'MONTO_TX_OK',
  'filas_validas', (
    select count(*) from crm.leads
    where id in (
      '24000000-0000-4000-8000-000000000010',
      '24000000-0000-4000-8000-000000000011'
    )
  ),
  'snapshots', (
    select count(*) from crm.lead_asignaciones
    where lead_id in (
      '24000000-0000-4000-8000-000000000010',
      '24000000-0000-4000-8000-000000000011'
    )
  )
) as validacion;

rollback;
