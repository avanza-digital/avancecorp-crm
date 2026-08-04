\set ON_ERROR_STOP on

-- Oraculo transaccional y autocontenido para el gate bancario posterior a P04.
-- Construye solo la frontera de autorizacion necesaria, demuestra primero la
-- regresion de la version 20260803221622 y luego ejecuta LA migracion real.
-- Todo termina en ROLLBACK.

begin;

-- Roles API minimos. Son transaccionales y desaparecen con el ROLLBACK final.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema auth;
create schema crm;
create schema private;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table public.perfiles (
  id uuid primary key,
  rol text not null,
  activo boolean not null,
  asesor_perfil_id uuid,
  creado_por uuid
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  activo boolean not null
);

create table public.contratos (
  id uuid primary key,
  cliente_id uuid not null references public.perfiles(id),
  moneda text not null
);

create table crm.cuentas_bancarias (
  id uuid primary key,
  cliente_id uuid not null references public.perfiles(id),
  moneda text not null,
  banco text not null,
  tipo_cuenta text not null,
  numero_cuenta text not null,
  cci text not null,
  titular_distinto boolean not null,
  beneficiario_nombre text,
  beneficiario_dni text
);

create table crm.contrato_cuentas_pago (
  contrato_id uuid primary key references public.contratos(id),
  cuenta_bancaria_id uuid not null references crm.cuentas_bancarias(id)
);

create table private.actualizaciones_legacy (
  contrato_id uuid not null
);

create function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo = true
      and p.rol in ('admin', 'superadmin')
  );
$$;

create function public.es_analista()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo = true
      and p.rol = 'analista'
  );
$$;

create function private.rol_crm(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_uid
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('vendedor', 'supervisor', 'gerencia');
$$;

create function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo = true
      and p.rol in ('directorio', 'admin', 'superadmin')
  )
  and not exists (
    select 1
    from crm.equipo e
    where e.perfil_id = (select auth.uid())
  );
$$;

create function private.puede_acceder_crm()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global();
$$;

-- Version vulnerable desplegada el 2026-08-03: solo mira el rol del portal.
create function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo = true
        and (
          (select public.es_admin())
          or (
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid()))
            )
          )
        )
    );
$$;

-- Stub observable del escritor del portal. Permite demostrar que el wrapper
-- vulnerable llegaba a delegar el contrato legacy aun con CRM revocado.
create function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.actualizaciones_legacy (contrato_id) values (p_id);
end;
$$;

-- Version vulnerable del wrapper: el INNER JOIN deja FOUND=false para legacy
-- y la llamada a public.actualizar_contrato queda fuera del gate.
create function crm.actualizar_contrato_con_cuenta(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cliente_id      uuid;
  v_cliente_cuenta  uuid;
  v_moneda_actual   text;
  v_moneda_cuenta   text;
  v_moneda_nueva    text;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;

  select ct.cliente_id, cb.cliente_id, ct.moneda, cb.moneda
    into v_cliente_id, v_cliente_cuenta, v_moneda_actual, v_moneda_cuenta
  from public.contratos ct
  join crm.contrato_cuentas_pago ccp on ccp.contrato_id = ct.id
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ct.id = p_id;

  if found then
    if not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
      raise exception using errcode = '42501', message = 'Contrato no encontrado o fuera de tu cartera';
    end if;
    if v_cliente_id is distinct from v_cliente_cuenta
       or v_moneda_actual is distinct from v_moneda_cuenta then
      raise exception using errcode = 'P0001', message = 'Cuenta inconsistente';
    end if;
    v_moneda_nueva := upper(btrim(coalesce(p_contrato->>'moneda', v_moneda_actual)));
    if v_moneda_nueva is distinct from v_moneda_cuenta then
      raise exception using errcode = '22023', message = 'Moneda inmutable';
    end if;
  end if;

  perform public.actualizar_contrato(p_id, p_contrato, p_cronograma);
end;
$$;

-- Version vulnerable del resolver de Pagos: es_admin() sin el gate P04.
create function crm.cuentas_pago_contratos_fn(p_contrato_ids uuid[])
returns table (
  contrato_id uuid,
  cuenta_bancaria_id uuid,
  moneda text,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean,
  beneficiario_nombre text,
  beneficiario_dni text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.es_admin()) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;

  return query
  select
    ccp.contrato_id,
    cb.id,
    cb.moneda,
    cb.banco,
    cb.tipo_cuenta,
    cb.numero_cuenta,
    cb.cci,
    cb.titular_distinto,
    cb.beneficiario_nombre,
    cb.beneficiario_dni
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = any(p_contrato_ids);
end;
$$;

insert into public.perfiles (id, rol, activo) values
  ('11111111-1111-4111-8111-111111111111', 'analista', true),
  ('33333333-3333-4333-8333-333333333333', 'admin', true),
  ('44444444-4444-4444-8444-444444444444', 'analista', true),
  ('55555555-5555-4555-8555-555555555555', 'admin', true);
insert into public.perfiles (id, rol, activo, asesor_perfil_id, creado_por) values
  (
    '22222222-2222-4222-8222-222222222222',
    'cliente',
    true,
    '11111111-1111-4111-8111-111111111111',
    '11111111-1111-4111-8111-111111111111'
  );
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('11111111-1111-4111-8111-111111111111', 'vendedor', true),
  ('44444444-4444-4444-8444-444444444444', 'vendedor', true),
  ('55555555-5555-4555-8555-555555555555', 'gerencia', true);

insert into public.contratos (id, cliente_id, moneda) values
  (
    '66666666-6666-4666-8666-666666666661',
    '22222222-2222-4222-8222-222222222222',
    'PEN'
  ),
  (
    '66666666-6666-4666-8666-666666666662',
    '22222222-2222-4222-8222-222222222222',
    'PEN'
  );
insert into crm.cuentas_bancarias (
  id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
  titular_distinto, beneficiario_nombre, beneficiario_dni
) values (
  '77777777-7777-4777-8777-777777777777',
  '22222222-2222-4222-8222-222222222222',
  'PEN',
  'BANCO ORACULO',
  'ahorros',
  '19100000000001',
  '00219100000000000001',
  false,
  null,
  null
);
-- Solo el primer contrato esta enlazado; el segundo representa el fallback.
insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values (
  '66666666-6666-4666-8666-666666666661',
  '77777777-7777-4777-8777-777777777777'
);

select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  true
);

do $$
declare
  v_count integer;
begin
  if not private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'PRE01: el analista activo debia pasar antes del fix';
  end if;

  update crm.equipo
  set activo = false
  where perfil_id = '11111111-1111-4111-8111-111111111111';

  if not private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'PRE02: no se reprodujo la regresion equipo=false/perfil=true';
  end if;

  perform crm.actualizar_contrato_con_cuenta(
    '66666666-6666-4666-8666-666666666662',
    '{"moneda":"PEN"}'::jsonb,
    '[]'::jsonb
  );
  select count(*) into v_count from private.actualizaciones_legacy;
  if v_count <> 1 then
    raise exception 'PRE03: el wrapper legacy vulnerable no delego la escritura';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '55555555-5555-4555-8555-555555555555',
    true
  );
  update crm.equipo
  set activo = false
  where perfil_id = '55555555-5555-4555-8555-555555555555';
  select count(*) into v_count
  from crm.cuentas_pago_contratos_fn(
    array['66666666-6666-4666-8666-666666666661'::uuid]
  );
  if v_count <> 1 then
    raise exception 'PRE04: el resolver admin vulnerable no expuso la cuenta';
  end if;

  update crm.equipo
  set activo = true
  where perfil_id = '11111111-1111-4111-8111-111111111111';
  update crm.equipo
  set activo = true
  where perfil_id = '55555555-5555-4555-8555-555555555555';
  perform set_config(
    'request.jwt.claim.sub',
    '11111111-1111-4111-8111-111111111111',
    true
  );
end;
$$;

\ir ../migrations/20260804144555_crm_p04_gate_cuentas_bancarias.sql

do $$
declare
  v_count integer;
begin
  -- true / true: la operacion legitima se conserva.
  if not private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V01: true/true debe conservar acceso';
  end if;

  -- true / false: el JWT sigue identificando al actor, pero el estado vivo
  -- de crm.equipo revoca la superficie bancaria.
  update crm.equipo
  set activo = false
  where perfil_id = '11111111-1111-4111-8111-111111111111';
  if private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V02: equipo CRM inactivo con perfil activo paso';
  end if;
  begin
    perform crm.actualizar_contrato_con_cuenta(
      '66666666-6666-4666-8666-666666666662',
      '{"moneda":"PEN"}'::jsonb,
      '[]'::jsonb
    );
    raise exception 'V02A: el contrato legacy salto el gate P04';
  exception
    when insufficient_privilege then null;
  end;
  select count(*) into v_count from private.actualizaciones_legacy;
  if v_count <> 1 then
    raise exception 'V02B: el wrapper bloqueado alcanzo el escritor legacy';
  end if;

  -- false / true: tampoco basta una membresia CRM si el perfil fue suspendido.
  update crm.equipo
  set activo = true
  where perfil_id = '11111111-1111-4111-8111-111111111111';
  update public.perfiles
  set activo = false
  where id = '11111111-1111-4111-8111-111111111111';
  if private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V03: perfil inactivo con equipo CRM activo paso';
  end if;

  -- false / false.
  update crm.equipo
  set activo = false
  where perfil_id = '11111111-1111-4111-8111-111111111111';
  if private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V04: ambos flags inactivos pasaron';
  end if;

  -- La cartera sigue siendo obligatoria aun con ambos flags restaurados.
  update public.perfiles
  set activo = true
  where id = '11111111-1111-4111-8111-111111111111';
  update crm.equipo
  set activo = true
  where perfil_id = '11111111-1111-4111-8111-111111111111';
  perform set_config(
    'request.jwt.claim.sub',
    '44444444-4444-4444-8444-444444444444',
    true
  );
  if private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V05: analista ajeno a la cartera paso';
  end if;

  -- La rama admin pertenece al portal y no exige enrolamiento CRM.
  perform set_config(
    'request.jwt.claim.sub',
    '33333333-3333-4333-8333-333333333333',
    true
  );
  if not private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V06: el admin legitimo del portal perdio acceso';
  end if;
  select count(*) into v_count
  from crm.cuentas_pago_contratos_fn(
    array['66666666-6666-4666-8666-666666666661'::uuid]
  );
  if v_count <> 1 then
    raise exception 'V06A: Pagos no resolvio la cuenta para el admin global';
  end if;

  -- Un admin con membresia CRM activa tambien conserva su poder.
  perform set_config(
    'request.jwt.claim.sub',
    '55555555-5555-4555-8555-555555555555',
    true
  );
  if not private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V07: el admin con membresia CRM activa perdio acceso';
  end if;
  select count(*) into v_count
  from crm.cuentas_pago_contratos_fn(
    array['66666666-6666-4666-8666-666666666661'::uuid]
  );
  if v_count <> 1 then
    raise exception 'V07A: Pagos no resolvio la cuenta para el admin CRM activo';
  end if;

  -- Si existe membresia, apagarla prevalece sobre el fallback global admin.
  update crm.equipo
  set activo = false
  where perfil_id = '55555555-5555-4555-8555-555555555555';
  if private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V08: admin con membresia CRM revocada paso';
  end if;
  begin
    perform crm.cuentas_pago_contratos_fn(
      array['66666666-6666-4666-8666-666666666661'::uuid]
    );
    raise exception 'V08A: Pagos expuso la cuenta al admin CRM revocado';
  exception
    when insufficient_privilege then null;
  end;

  -- Sin identidad no existe operacion humana.
  perform set_config('request.jwt.claim.sub', '', true);
  if private.puede_gestionar_cuentas_cliente(
    '22222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'V09: una sesion sin identidad paso';
  end if;

  if has_function_privilege(
    'authenticated',
    'private.puede_gestionar_cuentas_cliente(uuid)',
    'EXECUTE'
  ) then
    raise exception 'V10: authenticated conserva EXECUTE directo sobre el helper';
  end if;
  if has_function_privilege(
    'service_role',
    'private.puede_gestionar_cuentas_cliente(uuid)',
    'EXECUTE'
  ) then
    raise exception 'V11: service_role conserva EXECUTE directo sobre el helper';
  end if;
  if not has_function_privilege(
    'authenticated',
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'V12: authenticated perdio el wrapper de correccion';
  end if;
  if not has_function_privilege(
    'authenticated',
    'crm.cuentas_pago_contratos_fn(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'V13: authenticated perdio el resolver de Pagos';
  end if;
  if has_function_privilege(
    'service_role',
    'crm.cuentas_pago_contratos_fn(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'V14: service_role conserva EXECUTE sobre el resolver humano';
  end if;
  if has_function_privilege(
    'anon',
    'private.puede_gestionar_cuentas_cliente(uuid)',
    'EXECUTE'
  ) then
    raise exception 'V15: anon conserva EXECUTE directo sobre el helper';
  end if;
  if has_function_privilege(
    'anon',
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'V16: anon conserva EXECUTE sobre el wrapper de correccion';
  end if;
  if has_function_privilege(
    'anon',
    'crm.cuentas_pago_contratos_fn(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'V17: anon conserva EXECUTE sobre el resolver de Pagos';
  end if;
  if has_function_privilege(
    'service_role',
    'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'V18: service_role conserva EXECUTE sobre el wrapper humano';
  end if;
end;
$$;

select 'P04_BANK_GATE_TX_OK' as resultado;

rollback;
