\set ON_ERROR_STOP on
\pset pager off

-- Oráculo destructivo únicamente para la base efímera creada por el runner.
do $seguridad$
begin
  if current_database() <> 'crm_contrato_pdf_test' then
    raise exception
      'Este oráculo solo puede ejecutarse en crm_contrato_pdf_test; base actual: %',
      current_database();
  end if;
end;
$seguridad$;

create schema auth;
create schema storage;
create schema private;
create schema crm;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$function$;

create table storage.buckets (
  id text primary key,
  name text not null unique,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null references storage.buckets(id),
  name text not null
);

create table public.perfiles (
  id uuid primary key,
  rol text not null,
  nombre_completo text,
  nombres text,
  apellidos text,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean not null default false,
  beneficiario_nombre text,
  beneficiario_dni text,
  banco_usd text,
  tipo_cuenta_usd text,
  numero_cuenta_usd text,
  cci_usd text,
  titular_distinto_usd boolean not null default false,
  beneficiario_nombre_usd text,
  beneficiario_dni_usd text,
  actualizado_en timestamptz not null default now()
);

create table public.contratos (
  id uuid primary key,
  cliente_id uuid not null references public.perfiles(id),
  creado_por uuid references public.perfiles(id),
  numero_contrato text,
  capital numeric,
  moneda text,
  tasa_anual numeric,
  -- NOT NULL como en produccion (verificado el 2026-08-20 contra
  -- information_schema): el stub las declaraba opcionales y era mas debil que
  -- el mundo real, asi que cualquier regla apoyada en la fecha de firma se
  -- probaba contra un mundo que no existe.
  fecha_inicio date not null,
  fecha_vencimiento date not null
);

create table private.cartera_acl (
  actor_id uuid not null references public.perfiles(id),
  cliente_id uuid not null references public.perfiles(id),
  primary key (actor_id, cliente_id)
);

create table private.crm_roles (
  actor_id uuid primary key references public.perfiles(id),
  rol_crm text not null
);

create function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from private.cartera_acl acl
      where acl.actor_id = (select auth.uid())
        and acl.cliente_id = p_cliente_id
    );
$function$;

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

create function private.rol_crm(p_actor_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select rol_crm
  from private.crm_roles
  where actor_id = p_actor_id;
$function$;

revoke all on function private.rol_crm(uuid)
  from public, anon, authenticated, service_role;

create function crm.actualizar_cliente_gerencia(
  p_cliente_id uuid,
  p_patch jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if private.rol_crm((select auth.uid())) <> 'gerencia' then
    raise exception 'Solo Gerencia puede corregir clientes fuera de cartera'
      using errcode = '42501';
  end if;
  if (p_patch - array['telefono']::text[]) <> '{}'::jsonb then
    raise exception 'El formulario intento modificar campos no permitidos'
      using errcode = '22023';
  end if;
  update public.perfiles
     set telefono = case
       when p_patch ? 'telefono' then p_patch->>'telefono'
       else telefono
     end,
     actualizado_en = now()
   where id = p_cliente_id
     and rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

revoke all on function crm.actualizar_cliente_gerencia(uuid,jsonb)
  from public, anon, service_role;
grant execute on function crm.actualizar_cliente_gerencia(uuid,jsonb)
  to authenticated;
grant usage on schema auth, crm to authenticated, service_role;
grant execute on function auth.uid() to authenticated, service_role;

alter table public.perfiles
  add column activo boolean not null default true,
  add column asesor_perfil_id uuid,
  add column creado_por uuid;

alter table public.contratos
  add column modalidad text not null default 'mensual',
  add column tipo_interes text not null default 'simple',
  add column categoria text default 'nuevo',
  add column estado text not null default 'activo',
  add column producto_condicion_id uuid not null default gen_random_uuid(),
  add column notas_internas text,
  add column creado_en timestamptz not null default now(),
  add column actualizado_en timestamptz not null default now();

create table public.cronograma_pagos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  numero_cuota integer not null,
  fecha_programada date not null,
  monto_programado numeric not null,
  estado text not null default 'pendiente',
  tipo text not null default 'cuota',
  monto_pagado numeric,
  fecha_pago_real date,
  notif_pago_enviada_en timestamptz,
  recordatorio_3d_enviado_en timestamptz,
  registrado_por uuid,
  creado_en timestamptz not null default now(),
  unique (contrato_id, numero_cuota)
);

create table public.contrato_titulares (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  nombre_completo text not null,
  tipo_documento text not null default 'DNI',
  documento text not null,
  orden integer not null,
  creado_por uuid,
  creado_en timestamptz not null default now(),
  unique (contrato_id, orden)
);

create table public.documentos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  storage_path text not null
);

create table crm.cuentas_bancarias (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id),
  moneda text not null,
  banco text not null,
  tipo_cuenta text not null,
  numero_cuenta text not null,
  cci text not null,
  titular_distinto boolean not null default false,
  beneficiario_nombre text,
  beneficiario_dni text,
  origen text not null default 'contrato',
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table crm.contrato_cuentas_pago (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null unique references public.contratos(id) on delete cascade,
  cuenta_bancaria_id uuid not null references crm.cuentas_bancarias(id),
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table crm.leads (
  id uuid primary key,
  vendedor_id uuid not null,
  dni text,
  etapa text not null default 'nuevo',
  activo boolean not null default true,
  perfil_id uuid,
  convertido_en timestamptz
);

create table crm.actividades (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id),
  tipo text not null,
  detalle text,
  metadata jsonb not null default '{}'::jsonb,
  creado_por uuid
);

create function crm.crear_contrato_con_cuenta(
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_contrato_id uuid := coalesce((p_contrato->>'id')::uuid, gen_random_uuid());
  v_cuenta_id uuid := gen_random_uuid();
  v_numero text := coalesce(p_contrato->>'numero_contrato', 'AC-TEST-0001');
  v_cuota jsonb;
  v_titular jsonb;
begin
  if not private.puede_gestionar_cuentas_cliente((p_contrato->>'cliente_id')::uuid) then
    raise insufficient_privilege using message = 'Cliente fuera de cartera';
  end if;

  insert into public.contratos (
    id, cliente_id, creado_por, numero_contrato, capital, moneda, tasa_anual,
    modalidad, tipo_interes, categoria, fecha_inicio, fecha_vencimiento,
    producto_condicion_id
  ) values (
    v_contrato_id, (p_contrato->>'cliente_id')::uuid, v_actor, v_numero,
    (p_contrato->>'capital')::numeric, p_contrato->>'moneda',
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    p_contrato->>'tipo_interes', p_contrato->>'categoria',
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    coalesce((p_contrato->>'producto_condicion_id')::uuid, gen_random_uuid())
  );

  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric,
      coalesce(v_cuota->>'tipo', 'cuota')
    );
  end loop;

  for v_titular in
    select value from jsonb_array_elements(coalesce(p_contrato->'titulares', '[]'::jsonb))
  loop
    insert into public.contrato_titulares (
      contrato_id, nombre_completo, tipo_documento, documento, orden, creado_por
    ) values (
      v_contrato_id, v_titular->>'nombre_completo',
      coalesce(v_titular->>'tipo_documento', 'DNI'),
      v_titular->>'documento', (v_titular->>'orden')::integer, v_actor
    );
  end loop;

  insert into crm.cuentas_bancarias (
    id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
    titular_distinto, beneficiario_nombre, beneficiario_dni, creado_por
  ) values (
    v_cuenta_id, (p_contrato->>'cliente_id')::uuid, p_contrato->>'moneda',
    p_cuenta->>'banco', p_cuenta->>'tipo_cuenta', p_cuenta->>'numero_cuenta',
    p_cuenta->>'cci', coalesce((p_cuenta->>'titular_distinto')::boolean, false),
    p_cuenta->>'beneficiario_nombre', p_cuenta->>'beneficiario_dni', v_actor
  );
  insert into crm.contrato_cuentas_pago (
    contrato_id, cuenta_bancaria_id, creado_por
  ) values (v_contrato_id, v_cuenta_id, v_actor);

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero,
    'cuenta_bancaria_id', v_cuenta_id
  );
end;
$function$;

revoke all on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
  from public, anon, service_role;
grant execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
  to authenticated;

create function crm.convertir_lead(p_lead_id uuid, p_perfil_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_lead crm.leads%rowtype;
  v_dni text;
begin
  select * into v_lead
  from crm.leads
  where id = p_lead_id and activo and vendedor_id = v_actor
  for update;
  if not found or v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'Lead no encontrado o cerrado';
  end if;
  select dni into v_dni
  from public.perfiles
  where id = p_perfil_id and rol = 'cliente' and activo;
  if not found or v_dni is distinct from v_lead.dni then
    raise exception 'Cliente destino invalido';
  end if;
  update crm.leads
  set etapa = 'convertido', perfil_id = p_perfil_id, convertido_en = now()
  where id = p_lead_id;
  insert into crm.actividades (lead_id, tipo, detalle, creado_por)
  values (p_lead_id, 'conversion', 'Convertido a cliente', v_actor);
  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id);
end;
$function$;

revoke all on function crm.convertir_lead(uuid,uuid)
  from public, anon, service_role;
grant execute on function crm.convertir_lead(uuid,uuid) to authenticated;

-- Superficie Portal mínima que la migración de revisiones reusa. El oráculo
-- prueba la misma frontera: vendedor con autoría+5 h, Admin y Superadmin.
create function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.rol in ('admin', 'superadmin')
  );
$function$;

create function public.es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.rol = 'superadmin'
  );
$function$;

create function public.contrato_tiene_pagos(p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.cronograma_pagos cp
    where cp.contrato_id = p_contrato_id
      and (cp.estado = 'pagado' or cp.monto_pagado is not null)
  );
$function$;

create function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_contrato public.contratos%rowtype;
  v_cuota jsonb;
begin
  select * into v_contrato
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  if not public.es_admin() then
    if v_contrato.creado_por is distinct from v_actor then
      raise insufficient_privilege using
        message = 'Solo puedes corregir contratos que tu creaste';
    end if;
    if v_contrato.creado_en <= now() - interval '5 hours' then
      raise insufficient_privilege using
        message = 'La ventana de correccion de 5 horas ya vencio para este contrato';
    end if;
    if not private.puede_gestionar_cuentas_cliente(v_contrato.cliente_id) then
      raise insufficient_privilege using message = 'Cliente fuera de cartera';
    end if;
  end if;

  update public.contratos
     set numero_contrato = coalesce(p_contrato->>'numero_contrato', numero_contrato),
         capital = coalesce((p_contrato->>'capital')::numeric, capital),
         moneda = coalesce(p_contrato->>'moneda', moneda),
         tasa_anual = coalesce((p_contrato->>'tasa_anual')::numeric, tasa_anual),
         modalidad = coalesce(p_contrato->>'modalidad', modalidad),
         tipo_interes = coalesce(p_contrato->>'tipo_interes', tipo_interes),
         categoria = coalesce(p_contrato->>'categoria', categoria),
         fecha_inicio = coalesce((p_contrato->>'fecha_inicio')::date, fecha_inicio),
         fecha_vencimiento = coalesce((p_contrato->>'fecha_vencimiento')::date, fecha_vencimiento),
         notas_internas = case
           when p_contrato ? 'notas_internas' then p_contrato->>'notas_internas'
           else notas_internas
         end
   where id = p_id;

  if p_cronograma is not null and jsonb_array_length(p_cronograma) > 0 then
    delete from public.cronograma_pagos where contrato_id = p_id;
    for v_cuota in select value from jsonb_array_elements(p_cronograma)
    loop
      insert into public.cronograma_pagos (
        contrato_id, numero_cuota, fecha_programada, monto_programado, tipo
      ) values (
        p_id, (v_cuota->>'numero_cuota')::integer,
        (v_cuota->>'fecha_programada')::date,
        (v_cuota->>'monto_programado')::numeric,
        coalesce(v_cuota->>'tipo', 'cuota')
      );
    end loop;
  end if;
  return jsonb_build_object('id', p_id, 'ok', true);
end;
$function$;

create function crm.actualizar_contrato_con_cuenta(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.actualizar_contrato(p_id, p_contrato, p_cronograma);
end;
$function$;

create function public.actualizar_numero_contrato(
  p_id uuid,
  p_numero text,
  p_notas text default null,
  p_categoria text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.es_admin() then
    raise insufficient_privilege using message = 'No autorizado';
  end if;
  update public.contratos
     set numero_contrato = p_numero,
         notas_internas = p_notas,
         categoria = coalesce(p_categoria, categoria)
   where id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return jsonb_build_object('id', p_id, 'ok', true);
end;
$function$;

revoke all on function public.es_admin(), public.es_superadmin(),
  public.contrato_tiene_pagos(uuid),
  public.actualizar_contrato(uuid,jsonb,jsonb),
  public.actualizar_numero_contrato(uuid,text,text,text),
  crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)
  from public, anon, service_role;
grant execute on function public.actualizar_contrato(uuid,jsonb,jsonb),
  public.actualizar_numero_contrato(uuid,text,text,text),
  crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)
  to authenticated;

\ir ../migrations/20260818014534_crm_contrato_pdf_v2_reserva.sql
\ir ../migrations/20260818200741_crm_contratos_correccion_pdf_eliminacion.sql
\ir ../migrations/20260818200743_crm_contrato_pdf_plantilla_v3.sql
\ir ../migrations/20260818204908_crm_contrato_pdf_plantilla_v4_firma.sql
\ir ../migrations/20260818233729_crm_contrato_pdf_plantilla_v5_firma_kirk.sql
\ir ../migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql
\ir ../migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql

create schema test_support;

create function test_support.assert_true(
  p_condicion boolean,
  p_etiqueta text
)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if p_condicion is distinct from true then
    raise exception 'ASSERT_TRUE fallo: %', p_etiqueta;
  end if;
end;
$function$;

create function test_support.assert_raises(
  p_sql text,
  p_mensaje text,
  p_etiqueta text,
  p_sqlstate text default null
)
returns void
language plpgsql
as $function$
declare
  v_fallo boolean := false;
  v_error text;
  v_sqlstate text;
begin
  begin
    execute p_sql;
  exception when others then
    v_fallo := true;
    v_error := sqlerrm;
    get stacked diagnostics v_sqlstate = returned_sqlstate;
  end;

  if not v_fallo then
    raise exception 'ASSERT_RAISES no lanzo error: %', p_etiqueta;
  end if;
  if p_mensaje is not null
     and position(lower(p_mensaje) in lower(v_error)) = 0 then
    raise exception
      'ASSERT_RAISES mensaje inesperado (%): esperado %, recibido %',
      p_etiqueta,
      p_mensaje,
      v_error;
  end if;
  if p_sqlstate is not null and v_sqlstate is distinct from p_sqlstate then
    raise exception
      'ASSERT_RAISES SQLSTATE inesperado (%): esperado %, recibido %',
      p_etiqueta,
      p_sqlstate,
      v_sqlstate;
  end if;
end;
$function$;

grant usage on schema test_support to authenticated, service_role;

-- Actores y cliente compartido por los escenarios v1/v2.
insert into public.perfiles (
  id, rol, nombre_completo, tipo_documento, dni, correo, telefono,
  activo, domicilio
) values
  (
    '11111111-1111-4111-8111-111111111111', 'analista',
    'Ana Analista', 'dni', '70000001', 'ana@example.test', '999111222',
    true, null
  ),
  (
    '22222222-2222-4222-8222-222222222222', 'analista',
    'Oscar Externo', 'dni', '70000002', 'oscar@example.test', '999333444',
    true, null
  ),
  (
    '33333333-3333-4333-8333-333333333333', 'cliente',
    'Carla Cliente', 'dni', '70000003', 'carla@example.test', '999555666',
    true, 'Av. Siempre Viva 742, Miraflores, Lima'
  ),
  (
    '66666666-6666-4666-8666-666666666666', 'analista',
    'Gina Gerencia', 'dni', '70000006', 'gerencia@example.test', '999777888',
    true, null
  ),
  (
    '77777777-7777-4777-8777-777777777777', 'admin',
    'Adriana Admin', 'dni', '70000007', 'admin@example.test', '999777001',
    true, null
  ),
  (
    '88888888-8888-4888-8888-888888888888', 'superadmin',
    'Samuel Superadmin', 'dni', '70000008', 'superadmin@example.test', '999888001',
    true, null
  );

insert into private.cartera_acl (actor_id, cliente_id)
values (
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333'
);
insert into private.crm_roles (actor_id, rol_crm)
values ('66666666-6666-4666-8666-666666666666', 'gerencia');

-- Fixture legacy: se inserta directamente sobre el ledger compatible. No se
-- aplica ni se conserva la migracion insegura v1 en el set desplegable.
insert into public.contratos (
  id, cliente_id, creado_por, numero_contrato, capital, moneda, tasa_anual,
  modalidad, tipo_interes, categoria, fecha_inicio, fecha_vencimiento,
  producto_condicion_id
) values (
  '44444444-4444-4444-8444-444444444444',
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'AEP-2026-LEGACY-0001', 15000, 'PEN', 18.5,
  'mensual', 'simple', 'nuevo', date '2026-08-17', date '2027-08-17',
  '44444444-4444-4444-8444-444444444445'
);
insert into storage.objects (bucket_id, name)
values (
  'contratos-generados',
  '44444444-4444-4444-8444-444444444444/contrato.pdf'
);
insert into private.contrato_pdfs (
  contrato_id, job_id, storage_bucket, storage_path, nombre_archivo,
  sha256, bytes, template_version, snapshot, generado_por
) values (
  '44444444-4444-4444-8444-444444444444',
  null,
  'contratos-generados',
  '44444444-4444-4444-8444-444444444444/contrato.pdf',
  'Contrato-AEP-2026-LEGACY-0001.pdf',
  repeat('a', 64),
  4096,
  'contrato-aep-17-v1',
  '{"snapshotVersion":1}'::jsonb,
  '11111111-1111-4111-8111-111111111111'
);

create extension dblink;

select test_support.assert_true(
  to_regclass('private.contrato_pdf_jobs') is not null,
  'la migracion v2 crea el job durable'
);

select test_support.assert_true(
  to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') is not null,
  'la migracion v2 expone el alta atomica'
);

-- Compatibilidad, aislamiento y grants exactos.
select test_support.assert_true(
  (
    select job_id is null
      and template_version = 'contrato-aep-17-v1'
      and storage_path = contrato_id::text || '/contrato.pdf'
    from private.contrato_pdfs
    where contrato_id = '44444444-4444-4444-8444-444444444444'
  ),
  'ledger v1 previo sobrevive con job nullable'
);

select test_support.assert_true(
  not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'storage.objects'::regclass
      and not t.tgisinternal
      and t.tgname = 'contrato_pdf_objeto_inmutable'
  ),
  'v2 no instala triggers sobre el esquema administrado de Storage'
);

select test_support.assert_true(
  not has_table_privilege('anon', 'private.contrato_pdf_jobs', 'SELECT')
    and not has_table_privilege('authenticated', 'private.contrato_pdf_jobs', 'SELECT')
    and not has_table_privilege('service_role', 'private.contrato_pdf_jobs', 'SELECT')
    and not has_table_privilege('authenticated', 'private.contrato_pdfs', 'SELECT')
    and not has_table_privilege('service_role', 'private.contrato_pdfs', 'SELECT'),
  'jobs y ledger no exponen privilegios directos'
);

select test_support.assert_true(
  has_function_privilege(
    'authenticated',
    'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',
    'EXECUTE'
  )
    and has_function_privilege(
      'authenticated', 'crm.contrato_pdf_estado_fn(uuid)', 'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated', 'crm.contrato_pdf_reclamar(uuid,uuid,integer)', 'EXECUTE'
    )
    and has_function_privilege(
      'service_role', 'crm.contrato_pdf_reclamar(uuid,uuid,integer)', 'EXECUTE'
    )
    and coalesce(not has_function_privilege(
      'service_role',
      to_regprocedure(
        'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid)'
      ),
      'EXECUTE'
    ), true),
  'grants separan usuario, worker y cierran el registro v1'
);

-- Alta moderna: contrato, cronograma, cuenta y job/snapshot en una transaccion.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);

select crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb_build_object(
    'id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'cliente_id', '33333333-3333-4333-8333-333333333333',
    'numero_contrato', 'AEP-2026-V2-0001',
    'capital', 30000,
    'moneda', 'PEN',
    'tasa_anual', 17.5,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', '2026-08-19',
    'fecha_vencimiento', '2027-08-19',
    'producto_condicion_id', 'dddddddd-dddd-4ddd-8ddd-dddddddddd01',
    'titulares', jsonb_build_array(jsonb_build_object(
      'nombre_completo', 'Coti Titular Uno',
      'tipo_documento', 'DNI',
      'documento', '70000111',
      'orden', 1
    ))
  ),
  jsonb_build_array(
    jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', '2026-09-18',
      'monto_programado', 437.50,
      'tipo', 'interes'
    ),
    jsonb_build_object(
      'numero_cuota', 2,
      'fecha_programada', '2026-10-18',
      'monto_programado', 30437.50,
      'tipo', 'capital_interes'
    )
  ),
  jsonb_build_object(
    'banco', 'Banco Test',
    'tipo_cuenta', 'ahorros',
    'numero_cuenta', '001-123456',
    'cci', '12345678901234567890',
    'titular_distinto', false
  )
)::text as alta_v2_uno \gset

select test_support.assert_true(
  (:'alta_v2_uno'::jsonb->>'id')::uuid =
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid
    and :'alta_v2_uno'::jsonb ? 'cuenta_bancaria_id'
    and :'alta_v2_uno'::jsonb->'pdf'->>'estado' = 'pendiente'
    and :'alta_v2_uno'::jsonb->'pdf'->>'storage_path' =
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1/v2/'
      || (:'alta_v2_uno'::jsonb->'pdf'->>'job_id')
      || '/contrato.pdf'
    and :'alta_v2_uno'::jsonb->'pdf'->>'template_version' =
      'contrato-aep-17-v5'
    and :'alta_v2_uno'::jsonb->'pdf'->'archivo' = 'null'::jsonb,
  'alta conserva campos previos y anida el estado PDF inicial'
);

reset role;
select test_support.assert_true(
  (
    select estado = 'pendiente'
      and template_version = 'contrato-aep-17-v5'
      and snapshot->>'snapshotVersion' = '2'
      and jsonb_array_length(snapshot->'cronograma') = 2
      and jsonb_array_length(snapshot->'cotitulares') = 1
      and snapshot->'titular'->>'domicilio' =
        'Av. Siempre Viva 742, Miraflores, Lima'
      and snapshot->'cuentaPago'->>'cci' = '12345678901234567890'
      and storage_path = lower(storage_path)
    from private.contrato_pdf_jobs
    where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  'snapshot v2 completo queda congelado y la ruta UUID es canonica'
);

-- El estado se reautoriza en cada lectura.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.assert_true(
  crm.contrato_pdf_estado_fn(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  )->>'estado' = 'pendiente',
  'cartera autorizada consulta estado sin snapshot ni lease'
);
select test_support.assert_true(
  not (
    crm.contrato_pdf_estado_fn(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    ) ? 'snapshot'
  ),
  'estado autenticado no filtra snapshot'
);
select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-4222-8222-222222222222',
  false
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_estado_fn(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  )$$,
  'fuera de tu cartera',
  'estado rechaza contrato ajeno'
);
reset role;

set role service_role;
select crm.contrato_pdf_reservar(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111'
)::text as reserva_repetida \gset
select test_support.assert_true(
  :'reserva_repetida'::jsonb->>'job_id' =
    :'alta_v2_uno'::jsonb->'pdf'->>'job_id',
  'reserva repetida converge al mismo job'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_reservar(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '22222222-2222-4222-8222-222222222222'
  )$$,
  'fuera de tu cartera',
  'reserva service conserva autorizacion del actor'
);
reset role;

-- PoC: desde la reserva se congelan terminos, estructura y titulares.
select test_support.assert_raises(
  $$update public.contratos
       set capital = capital + 1
     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'congelados',
  'capital no cambia post reserva'
);
select test_support.assert_raises(
  $$update public.contratos
       set numero_contrato = 'AEP-ALTERADO'
     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'congelados',
  'numero no cambia post reserva'
);
update public.contratos
   set notas_internas = 'Cobranza llamo al cliente',
       estado = 'cerrado'
 where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
select test_support.assert_true(
  (
    select notas_internas = 'Cobranza llamo al cliente' and estado = 'cerrado'
    from public.contratos
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ),
  'metadatos operativos del contrato siguen editables'
);

select test_support.assert_raises(
  $$update public.cronograma_pagos
       set monto_programado = monto_programado + 1
     where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       and numero_cuota = 1$$,
  'cronograma contractual',
  'monto programado no cambia post reserva'
);
select test_support.assert_raises(
  $$insert into public.cronograma_pagos (
       contrato_id, numero_cuota, fecha_programada, monto_programado, tipo
     ) values (
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 3,
       date '2026-11-18', 1, 'interes'
     )$$,
  'cronograma contractual',
  'no se agregan cuotas post reserva'
);
select test_support.assert_raises(
  $$delete from public.cronograma_pagos
     where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       and numero_cuota = 2$$,
  'cronograma contractual',
  'no se eliminan cuotas post reserva'
);
update public.cronograma_pagos
   set estado = 'pagado',
       monto_pagado = monto_programado,
       fecha_pago_real = date '2026-09-18',
       notif_pago_enviada_en = now(),
       recordatorio_3d_enviado_en = now(),
       registrado_por = '11111111-1111-4111-8111-111111111111'
 where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
   and numero_cuota = 1;
select test_support.assert_true(
  (
    select estado = 'pagado' and monto_pagado = monto_programado
    from public.cronograma_pagos
    where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      and numero_cuota = 1
  ),
  'cobranza operativa no queda bloqueada'
);

select test_support.assert_raises(
  $$update public.contrato_titulares
       set documento = '79999999'
     where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'titulares',
  'cotitular no cambia post reserva'
);
select test_support.assert_raises(
  $$delete from public.contrato_titulares
     where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'titulares',
  'cotitular no se elimina post reserva'
);

-- Lease: un ganador mientras esta vigente; upload/finalizacion idempotentes.
set role service_role;
select crm.contrato_pdf_reclamar(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_uno \gset
select test_support.assert_true(
  (:'claim_uno'::jsonb->>'adquirido')::boolean
    and :'claim_uno'::jsonb->>'estado' = 'procesando'
    and :'claim_uno'::jsonb ? 'lease_token'
    and :'claim_uno'::jsonb ? 'snapshot'
    and :'claim_uno'::jsonb ? 'renderizado_en',
  'primer claim recibe lease, snapshot y fecha determinista'
);
select crm.contrato_pdf_reclamar(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_ocupado \gset
select test_support.assert_true(
  not (:'claim_ocupado'::jsonb->>'adquirido')::boolean
    and not (:'claim_ocupado'::jsonb ? 'lease_token')
    and not (:'claim_ocupado'::jsonb ? 'snapshot'),
  'claim concurrente logico no roba lease ni filtra snapshot'
);

select crm.contrato_pdf_marcar_subido(
  (:'claim_uno'::jsonb->>'job_id')::uuid,
  (:'claim_uno'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111',
  repeat('1', 64),
  8192
)::text as subida_uno \gset
select crm.contrato_pdf_marcar_subido(
  (:'claim_uno'::jsonb->>'job_id')::uuid,
  (:'claim_uno'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111',
  repeat('1', 64),
  8192
)::text as subida_repetida \gset
select test_support.assert_true(
  :'subida_uno'::jsonb = :'subida_repetida'::jsonb
    and :'subida_uno'::jsonb->>'estado' = 'subido_verificado',
  'marcar subido converge con mismo hash y bytes'
);

select crm.contrato_pdf_finalizar(
  (:'claim_uno'::jsonb->>'job_id')::uuid,
  (:'claim_uno'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111'
)::text as sello_uno \gset
select crm.contrato_pdf_finalizar(
  (:'claim_uno'::jsonb->>'job_id')::uuid,
  (:'claim_uno'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111'
)::text as sello_repetido \gset
select test_support.assert_true(
  :'sello_uno'::jsonb = :'sello_repetido'::jsonb
    and :'sello_uno'::jsonb->>'estado' = 'sellado'
    and :'sello_uno'::jsonb->'archivo'->>'sha256' = repeat('1', 64),
  'finalizacion repetida devuelve metadata identica'
);
reset role;

select test_support.assert_true(
  (
    select count(*) = 1
    from private.contrato_pdfs
    where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      and job_id = (:'claim_uno'::jsonb->>'job_id')::uuid
  ),
  'finalizacion repetida deja un unico ledger'
);

-- ── Anexo de cronograma imprimible (20260929151350) ──────────────────────────
-- La lectura es SOLO de service_role y aplica la regla de lectura del PDF.
select test_support.assert_true(
  not pg_catalog.has_function_privilege('anon', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
    and not pg_catalog.has_function_privilege('authenticated', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
    and pg_catalog.has_function_privilege('service_role', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE'),
  'anexo: la lectura del snapshot sellado es solo de service_role'
);
-- (El permiso se acredita por catalogo: ejecutar una funcion SIN EXECUTE bajo
-- `set role` tumba el Postgres del banco — leccion registrada del 26/09.)

set role service_role;
select crm.contrato_pdf_anexo_snapshot(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111',
  'anexo-cronograma-v1'
)::text as anexo_uno \gset
select crm.contrato_pdf_anexo_snapshot(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111',
  'anexo-cronograma-v1'
)::text as anexo_dos \gset
reset role;
select test_support.assert_true(
  :'anexo_uno'::jsonb->>'contrato_id' = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    and (:'anexo_uno'::jsonb->>'revision')::integer = 1
    and :'anexo_uno'::jsonb->>'sha256' = repeat('1', 64)
    and :'anexo_uno'::jsonb->>'template_version' = :'sello_uno'::jsonb->'archivo'->>'template_version'
    and :'anexo_uno'::jsonb->'snapshot'->>'snapshotVersion' = '2'
    and :'anexo_uno'::jsonb->'snapshot'->'cronograma' is not null
    and (:'anexo_uno'::jsonb->>'generado_en') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?([+-]\d{2}:\d{2}|Z)$'
    and (:'anexo_uno'::jsonb->>'pdf_id')::uuid = (
      select p.id from private.contrato_pdfs p
      where p.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
        and p.job_id = (:'claim_uno'::jsonb->>'job_id')::uuid
    )
    and (select count(*) from jsonb_object_keys(:'anexo_uno'::jsonb)) = 7,
  'anexo: entrega el snapshot sellado vigente con su ficha exacta (fecha legible por la Edge)'
);
select test_support.assert_true(
  :'anexo_uno'::jsonb->'snapshot' = (
    select p.snapshot from private.contrato_pdfs p
    where p.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      and p.job_id = (:'claim_uno'::jsonb->>'job_id')::uuid
  ),
  'anexo: el snapshot es EL del ledger sellado, no uno recalculado'
);
select test_support.assert_true(
  :'anexo_uno'::jsonb = :'anexo_dos'::jsonb,
  'anexo: imprimir de nuevo devuelve exactamente lo mismo'
);
set role service_role;
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '22222222-2222-4222-8222-222222222222',
    'anexo-cronograma-v1'
  )$$,
  'fuera de tu cartera',
  'anexo: respeta la regla de lectura del PDF (actor fuera de cartera)'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    null,
    'anexo-cronograma-v1'
  )$$,
  'fuera de tu cartera',
  'anexo: sin actor no hay lectura'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    '11111111-1111-4111-8111-111111111111',
    'anexo-cronograma-v1'
  )$$,
  'fuera de tu cartera',
  'anexo: un contrato inexistente responde igual que uno ajeno'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '11111111-1111-4111-8111-111111111111',
    'contrato-aep-17-v9'
  )$$,
  'Plantilla del anexo',
  'anexo: solo admite plantillas anexo-cronograma-vN'
);
-- El ledger v1 (sin trabajo server-side) esta sellado pero no lleva snapshot v2.
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    '44444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111',
    'anexo-cronograma-v1'
  )$$,
  'datos congelados',
  'anexo: un sellado v1 no tiene snapshot del que emitir el anexo'
);
reset role;

-- Leer el snapshot NO deja asiento: la bitacora es de anexos EMITIDOS.
select test_support.assert_true(
  (select count(*) = 0 from private.contrato_pdf_anexo_emisiones),
  'anexo: leer el snapshot no deja asiento'
);
-- Emision: la Edge registra el anexo dibujado con su hash y sus bytes.
set role service_role;
select crm.contrato_pdf_anexo_emitido(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111',
  (:'anexo_uno'::jsonb->>'pdf_id')::uuid,
  'anexo-cronograma-v1',
  repeat('c', 64),
  165463
)::text as emision_uno \gset
select crm.contrato_pdf_anexo_emitido(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  '11111111-1111-4111-8111-111111111111',
  (:'anexo_uno'::jsonb->>'pdf_id')::uuid,
  'anexo-cronograma-v1',
  repeat('c', 64),
  165463
)::text as emision_dos \gset
reset role;
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_emitido(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '22222222-2222-4222-8222-222222222222',
    (select p.id from private.contrato_pdfs p
      where p.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      order by p.revision desc limit 1),
    'anexo-cronograma-v1',
    repeat('c', 64),
    165463
  )$$,
  'fuera de tu cartera',
  'anexo: la emision vuelve a autorizar'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_emitido(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '11111111-1111-4111-8111-111111111111',
    (select p.id from private.contrato_pdfs p where p.contrato_id = '44444444-4444-4444-8444-444444444444'),
    'anexo-cronograma-v1',
    repeat('c', 64),
    165463
  )$$,
  'no corresponde a un PDF sellado de este contrato',
  'anexo: la emision exige un sellado v2 de ESTE contrato',
  '23514'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_emitido(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '11111111-1111-4111-8111-111111111111',
    (select p.id from private.contrato_pdfs p
      where p.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      order by p.revision desc limit 1),
    'anexo-cronograma-v1',
    'no-es-un-hash',
    165463
  )$$,
  'Emisión del anexo inválida',
  'anexo: la emision exige hash y bytes validos',
  '22023'
);
select test_support.assert_true(
  (:'emision_uno'::jsonb->>'emision_id') is distinct from (:'emision_dos'::jsonb->>'emision_id')
    and (:'emision_uno'::jsonb->>'revision')::integer = 1
    and (
      select count(*) = 2
      from private.contrato_pdf_anexo_emisiones i
      where i.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
        and i.actor_id = '11111111-1111-4111-8111-111111111111'
        and i.revision = 1
        and i.template_anexo = 'anexo-cronograma-v1'
        and i.template_version_contrato = :'anexo_uno'::jsonb->>'template_version'
        and i.sha256 = repeat('c', 64) and i.bytes = 165463
        and i.pdf_id = (:'anexo_uno'::jsonb->>'pdf_id')::uuid
    )
    and (select count(*) = 2 from private.contrato_pdf_anexo_emisiones),
  'anexo: cada emision deja su asiento con hash y bytes; los rechazos no'
);
select test_support.assert_true(
  not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'private.contrato_pdf_anexo_emisiones'::regclass
      and a.attname in ('snapshot', 'data_antes', 'data_despues')
  ),
  'anexo: la bitacora no guarda el snapshot (datos bancarios)'
);
select test_support.assert_raises(
  $$delete from private.contrato_pdf_anexo_emisiones$$,
  'solo añadir',
  'anexo: la bitacora no se borra ni como owner'
);
select test_support.assert_raises(
  $$update private.contrato_pdf_anexo_emisiones set actor_id = gen_random_uuid()$$,
  'solo añadir',
  'anexo: la bitacora no se reescribe ni como owner'
);
select test_support.assert_raises(
  $$truncate private.contrato_pdf_anexo_emisiones$$,
  'solo añadir',
  'anexo: la bitacora no se vacia ni como owner'
);
-- Huellas de lo instalado, para el pin del registrador (se leen del log del arnés).
select 'ANEXO_MD5 ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) as huella
from pg_catalog.pg_proc p
where p.oid in (
  'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure,
  'crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)'::regprocedure,
  'private.contrato_pdf_anexo_snapshot_base(uuid)'::regprocedure,
  'private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)'::regprocedure
)
order by 1;
select test_support.assert_true(
  not pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_emisiones', 'SELECT')
    and not pg_catalog.has_table_privilege('authenticated', 'private.contrato_pdf_anexo_emisiones', 'SELECT')
    and not pg_catalog.has_table_privilege('anon', 'private.contrato_pdf_anexo_emisiones', 'SELECT'),
  'anexo: ningun rol de la API lee la bitacora directamente'
);

select test_support.assert_raises(
  $$update private.contrato_pdf_jobs
       set snapshot = jsonb_set(snapshot, '{snapshotVersion}', '99')
     where contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'$$,
  'inmutables',
  'snapshot del job no puede reescribirse ni como owner'
);

-- Constructor compacto para aislar escenarios adicionales del automata.
create function test_support.alta_pdf_v2(
  p_id uuid,
  p_numero text,
  p_cliente_id uuid default '33333333-3333-4333-8333-333333333333'
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object(
      'id', p_id,
      'cliente_id', p_cliente_id,
      'numero_contrato', p_numero,
      'capital', 10000,
      'moneda', 'PEN',
      'tasa_anual', 15,
      'modalidad', 'mensual',
      'tipo_interes', 'simple',
      'categoria', 'nuevo',
      'fecha_inicio', '2026-08-19',
      'fecha_vencimiento', '2027-08-19',
      'producto_condicion_id', gen_random_uuid(),
      'titulares', '[]'::jsonb
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', '2026-09-18',
      'monto_programado', 10125,
      'tipo', 'capital_interes'
    )),
    jsonb_build_object(
      'banco', 'Banco Test',
      'tipo_cuenta', 'ahorros',
      'numero_cuenta', '001-987654',
      'cci', '09876543210987654321',
      'titular_distinto', false
    )
  );
$function$;
grant usage on schema test_support to authenticated;
grant execute on function test_support.alta_pdf_v2(uuid,text,uuid)
  to authenticated;

-- Relevo autorizado: solicitado_por conserva la procedencia, pero no puede
-- convertir al creador en un dueño perpetuo del job. Otro actor con acceso
-- actual debe recuperar el pendiente; un actor revocado falla en cada frontera
-- y nadie roba un lease vigente.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  'abababab-abab-4bab-8bab-abababababab',
  'AEP-2026-V2-RELEVO'
)::text as alta_v2_relevo \gset
reset role;

insert into private.cartera_acl (actor_id, cliente_id)
values (
  '66666666-6666-4666-8666-666666666666',
  '33333333-3333-4333-8333-333333333333'
);
delete from private.cartera_acl
where actor_id = '11111111-1111-4111-8111-111111111111'
  and cliente_id = '33333333-3333-4333-8333-333333333333';

set role service_role;
select crm.contrato_pdf_reservar(
  'abababab-abab-4bab-8bab-abababababab',
  '66666666-6666-4666-8666-666666666666'
)::text as reserva_v2_relevo \gset
select test_support.assert_true(
  :'reserva_v2_relevo'::jsonb->>'job_id' =
    :'alta_v2_relevo'::jsonb->'pdf'->>'job_id',
  'actor autorizado reencuentra el job creado por otro actor'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_reclamar(
    'abababab-abab-4bab-8bab-abababababab',
    '11111111-1111-4111-8111-111111111111',
    120
  )$$,
  'fuera de tu cartera',
  'creador revocado no conserva propiedad perpetua del job'
);
select crm.contrato_pdf_reclamar(
  'abababab-abab-4bab-8bab-abababababab',
  '66666666-6666-4666-8666-666666666666',
  120
)::text as claim_v2_relevo \gset
select test_support.assert_true(
  (:'claim_v2_relevo'::jsonb->>'adquirido')::boolean
    and :'claim_v2_relevo'::jsonb ? 'lease_token',
  'segundo actor autorizado reclama el job pendiente'
);
reset role;

insert into private.cartera_acl (actor_id, cliente_id)
values (
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333'
);
set role service_role;
select crm.contrato_pdf_reclamar(
  'abababab-abab-4bab-8bab-abababababab',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_v2_relevo_ocupado \gset
select test_support.assert_true(
  not (:'claim_v2_relevo_ocupado'::jsonb->>'adquirido')::boolean
    and not (:'claim_v2_relevo_ocupado'::jsonb ? 'lease_token'),
  'actor autorizado no roba el lease vigente de otro actor'
);
reset role;

delete from private.cartera_acl
where actor_id = '66666666-6666-4666-8666-666666666666'
  and cliente_id = '33333333-3333-4333-8333-333333333333';
set role service_role;
select test_support.assert_raises(
  format(
    'select crm.contrato_pdf_marcar_subido(%L::uuid,%L::uuid,%L::uuid,%L,%s)',
    :'claim_v2_relevo'::jsonb->>'job_id',
    :'claim_v2_relevo'::jsonb->>'lease_token',
    '66666666-6666-4666-8666-666666666666',
    repeat('7', 64),
    3072
  ),
  'fuera de tu cartera',
  'worker reautoriza al poseedor del lease antes de persistir'
);
reset role;

insert into private.cartera_acl (actor_id, cliente_id)
values (
  '66666666-6666-4666-8666-666666666666',
  '33333333-3333-4333-8333-333333333333'
);
set role service_role;
select crm.contrato_pdf_marcar_subido(
  (:'claim_v2_relevo'::jsonb->>'job_id')::uuid,
  (:'claim_v2_relevo'::jsonb->>'lease_token')::uuid,
  '66666666-6666-4666-8666-666666666666',
  repeat('7', 64),
  3072
)::text as subida_v2_relevo \gset
select crm.contrato_pdf_finalizar(
  (:'claim_v2_relevo'::jsonb->>'job_id')::uuid,
  (:'claim_v2_relevo'::jsonb->>'lease_token')::uuid,
  '66666666-6666-4666-8666-666666666666'
)::text as sello_v2_relevo \gset
select test_support.assert_true(
  :'subida_v2_relevo'::jsonb->>'estado' = 'subido_verificado'
    and :'sello_v2_relevo'::jsonb->>'estado' = 'sellado',
  'actor de relevo autorizado completa subida y sello'
);
reset role;

select test_support.assert_true(
  (
    select j.solicitado_por =
        '11111111-1111-4111-8111-111111111111'::uuid
      and p.generado_por = j.solicitado_por
    from private.contrato_pdf_jobs j
    join private.contrato_pdfs p on p.job_id = j.id
    where j.contrato_id = 'abababab-abab-4bab-8bab-abababababab'
  ),
  'relevo conserva la procedencia inmutable de la reserva'
);
delete from private.cartera_acl
where actor_id = '66666666-6666-4666-8666-666666666666'
  and cliente_id = '33333333-3333-4333-8333-333333333333';

-- Error reintentable, nuevo lease y clasificacion durable de integridad.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  'AEP-2026-V2-0002'
)::text as alta_v2_dos \gset
reset role;

set role service_role;
select crm.contrato_pdf_reclamar(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_error_uno \gset
select crm.contrato_pdf_marcar_error(
  (:'claim_error_uno'::jsonb->>'job_id')::uuid,
  (:'claim_error_uno'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111',
  'RENDER_TIMEOUT'
)::text as error_uno \gset
select crm.contrato_pdf_marcar_error(
  (:'claim_error_uno'::jsonb->>'job_id')::uuid,
  (:'claim_error_uno'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111',
  'RENDER_TIMEOUT'
)::text as error_repetido \gset
select test_support.assert_true(
  :'error_uno'::jsonb = :'error_repetido'::jsonb
    and :'error_uno'::jsonb->>'estado' = 'error_reintentable'
    and (:'error_uno'::jsonb->>'reintentable')::boolean,
  'error transitorio es reintentable e idempotente'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    '11111111-1111-4111-8111-111111111111',
    'anexo-cronograma-v1'
  )$$,
  'no tiene un PDF sellado',
  'anexo: sin PDF sellado (reserva con error reintentable) no hay anexo ni asiento'
);
reset role;
select test_support.assert_true(
  not exists (
    select 1 from private.contrato_pdf_anexo_emisiones
    where contrato_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ),
  'anexo: el intento sin sellado no deja asiento'
);
set role service_role;

select crm.contrato_pdf_reclamar(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_error_dos \gset
select test_support.assert_true(
  (:'claim_error_dos'::jsonb->>'adquirido')::boolean
    and :'claim_error_dos'::jsonb->>'estado' = 'procesando'
    and :'claim_error_dos'::jsonb->>'lease_token' <>
      :'claim_error_uno'::jsonb->>'lease_token',
  'retry rota el token y aumenta un nuevo intento'
);
select test_support.assert_raises(
  format(
    $sql$select crm.contrato_pdf_marcar_subido(
      %L::uuid, %L::uuid,
      '11111111-1111-4111-8111-111111111111', %L, 1000
    )$sql$,
    :'claim_error_uno'::jsonb->>'job_id',
    :'claim_error_uno'::jsonb->>'lease_token',
    repeat('4', 64)
  ),
  'lease PDF',
  'token anterior no puede confirmar bytes'
);

select crm.contrato_pdf_marcar_error(
  (:'claim_error_dos'::jsonb->>'job_id')::uuid,
  (:'claim_error_dos'::jsonb->>'lease_token')::uuid,
  '11111111-1111-4111-8111-111111111111',
  'INTEGRIDAD_OBJETO_DIVERGENTE'
)::text as error_integridad \gset
select test_support.assert_true(
  :'error_integridad'::jsonb->>'estado' = 'integridad_bloqueada'
    and :'error_integridad'::jsonb->>'codigo' =
      'PDF_INTEGRIDAD_BLOQUEADA'
    and not (:'error_integridad'::jsonb->>'reintentable')::boolean,
  'codigo de integridad bloquea durablemente y no reintenta'
);
select crm.contrato_pdf_reclamar(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_bloqueado \gset
select test_support.assert_true(
  not (:'claim_bloqueado'::jsonb->>'adquirido')::boolean
    and :'claim_bloqueado'::jsonb->>'estado' = 'integridad_bloqueada',
  'estado de integridad es terminal'
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    '11111111-1111-4111-8111-111111111111',
    'anexo-cronograma-v1'
  )$$,
  'no tiene un PDF sellado',
  'anexo: un trabajo en integridad_bloqueada no tiene anexo'
);
reset role;

select test_support.assert_true(
  (
    select estado = 'integridad_bloqueada'
      and lease_token is null
      and lease_expira_en is null
      and ultimo_error = 'INTEGRIDAD_OBJETO_DIVERGENTE'
    from private.contrato_pdf_jobs
    where contrato_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ),
  'bloqueo de integridad persiste fuera del payload'
);

-- Lease vencido se recupera; bytes distintos despues de subir se bloquean.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'AEP-2026-V2-0003'
)::text as alta_v2_tres \gset
reset role;

set role service_role;
select crm.contrato_pdf_reclamar(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  '11111111-1111-4111-8111-111111111111',
  120
)::text as claim_vencido_uno \gset
reset role;
update private.contrato_pdf_jobs
   set lease_expira_en = statement_timestamp() - interval '1 second'
 where contrato_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';
set role service_role;
select test_support.assert_raises(
  format(
    'select crm.contrato_pdf_marcar_error(%L::uuid,%L::uuid,%L::uuid,%L)',
    :'claim_vencido_uno'::jsonb->>'job_id',
    :'claim_vencido_uno'::jsonb->>'lease_token',
    '11111111-1111-4111-8111-111111111111',
    'INTEGRIDAD_WORKER_TARDIO'
  ),
  'lease PDF',
  'worker tardio no muta el job con un lease ya vencido',
  '40001'
);
reset role;
select test_support.assert_true(
  (
    select estado = 'procesando'
      and lease_token =
        (:'claim_vencido_uno'::jsonb->>'lease_token')::uuid
    from private.contrato_pdf_jobs
    where contrato_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
  ),
  'rechazo del worker tardio conserva el estado para takeover'
);
insert into private.cartera_acl (actor_id, cliente_id)
values (
  '66666666-6666-4666-8666-666666666666',
  '33333333-3333-4333-8333-333333333333'
);
set role service_role;
select crm.contrato_pdf_reclamar(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  '66666666-6666-4666-8666-666666666666',
  120
)::text as claim_vencido_dos \gset
select test_support.assert_true(
  (:'claim_vencido_dos'::jsonb->>'adquirido')::boolean
    and :'claim_vencido_dos'::jsonb->>'lease_token' <>
      :'claim_vencido_uno'::jsonb->>'lease_token'
    and (:'claim_vencido_dos'::jsonb->>'intentos')::integer = 2,
  'otro actor autorizado recupera el lease vencido con token nuevo'
);
select crm.contrato_pdf_marcar_subido(
  (:'claim_vencido_dos'::jsonb->>'job_id')::uuid,
  (:'claim_vencido_dos'::jsonb->>'lease_token')::uuid,
  '66666666-6666-4666-8666-666666666666',
  repeat('5', 64),
  2048
)::text as subida_tres \gset
select crm.contrato_pdf_marcar_subido(
  (:'claim_vencido_dos'::jsonb->>'job_id')::uuid,
  (:'claim_vencido_dos'::jsonb->>'lease_token')::uuid,
  '66666666-6666-4666-8666-666666666666',
  repeat('6', 64),
  2048
)::text as subida_divergente \gset
select test_support.assert_true(
  :'subida_divergente'::jsonb->>'estado' = 'integridad_bloqueada'
    and :'subida_divergente'::jsonb->>'sha256' = repeat('5', 64)
    and :'subida_divergente'::jsonb->>'codigo' =
      'PDF_INTEGRIDAD_BLOQUEADA',
  'primer fingerprint gana y una divergencia bloquea sin sobreescribirlo'
);
select crm.contrato_pdf_finalizar(
  (:'claim_vencido_dos'::jsonb->>'job_id')::uuid,
  (:'claim_vencido_dos'::jsonb->>'lease_token')::uuid,
  '66666666-6666-4666-8666-666666666666'
)::text as finalizar_bloqueado \gset
select test_support.assert_true(
  :'finalizar_bloqueado'::jsonb->>'estado' = 'integridad_bloqueada',
  'un job bloqueado nunca crea ledger'
);
reset role;
delete from private.cartera_acl
where actor_id = '66666666-6666-4666-8666-666666666666'
  and cliente_id = '33333333-3333-4333-8333-333333333333';
select test_support.assert_true(
  not exists (
    select 1 from private.contrato_pdfs
    where contrato_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
  ),
  'divergencia no sella metadata'
);
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.assert_raises(
  $$select crm.contrato_pdf_archivo_fn(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
  )$$,
  'integridad bloqueada',
  'metadata de descarga no se entrega para un job bloqueado'
);
reset role;

-- Carrera real: dos sesiones esperan el mismo mutex y solo una obtiene lease.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'AEP-2026-V2-0004'
)::text as alta_v2_carrera \gset
reset role;

select dblink_connect(
  'pdf_v2_claim_1',
  'host=host.docker.internal port=55322 dbname=crm_contrato_pdf_test user=postgres password=postgres application_name=pdf_v2_claim_1'
);
select dblink_connect(
  'pdf_v2_claim_2',
  'host=host.docker.internal port=55322 dbname=crm_contrato_pdf_test user=postgres password=postgres application_name=pdf_v2_claim_2'
);

begin;
select 1
from public.contratos
where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1'
for update;
select dblink_send_query(
  'pdf_v2_claim_1',
  $$select crm.contrato_pdf_reclamar(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    '11111111-1111-4111-8111-111111111111',
    120
  )$$
);
select dblink_send_query(
  'pdf_v2_claim_2',
  $$select crm.contrato_pdf_reclamar(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    '11111111-1111-4111-8111-111111111111',
    120
  )$$
);
do $espera_claim_v2$
declare
  v_intento integer;
begin
  for v_intento in 1..100 loop
    if (
      select count(*) = 2
      from pg_catalog.pg_stat_activity
      where application_name in ('pdf_v2_claim_1', 'pdf_v2_claim_2')
        and wait_event_type = 'Lock'
    ) then
      return;
    end if;
    perform pg_sleep(0.02);
  end loop;
  raise exception 'Las sesiones v2 no alcanzaron juntas el mutex contractual';
end;
$espera_claim_v2$;
commit;

create temporary table resultados_claim_v2 (payload jsonb);
insert into resultados_claim_v2
select payload
from dblink_get_result('pdf_v2_claim_1') as resultado(payload jsonb);
insert into resultados_claim_v2
select payload
from dblink_get_result('pdf_v2_claim_2') as resultado(payload jsonb);
select test_support.assert_true(
  (
    select count(*) = 2
      and count(*) filter (
        where (payload->>'adquirido')::boolean
      ) = 1
      and count(*) filter (
        where not (payload->>'adquirido')::boolean
      ) = 1
    from resultados_claim_v2
  )
    and (
      select intentos = 1 and estado = 'procesando'
      from private.contrato_pdf_jobs
      where contrato_id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1'
    ),
  'dos claims concurrentes producen exactamente un ganador'
);
select dblink_disconnect('pdf_v2_claim_1');
select dblink_disconnect('pdf_v2_claim_2');

-- Domicilio: conversion y escritura pertenecen a una transaccion.
insert into public.perfiles (
  id, rol, nombre_completo, tipo_documento, dni, correo, telefono,
  activo, domicilio
) values
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1', 'cliente',
    'Cliente Domicilio Nulo', 'dni', '70100001',
    'nulo@example.test', '999100001', true, null
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2', 'cliente',
    'Cliente Domicilio Fijo', 'dni', '70100002',
    'fijo@example.test', '999100002', true, 'Jr. Domicilio Original 123'
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3', 'cliente',
    'Cliente Conversion Fallida', 'dni', '70100003',
    'falla@example.test', '999100003', true, null
  );

insert into crm.leads (id, vendedor_id, dni) values
  (
    'ffffffff-ffff-4fff-8fff-fffffffffff1',
    '11111111-1111-4111-8111-111111111111', '70100001'
  ),
  (
    'ffffffff-ffff-4fff-8fff-fffffffffff2',
    '11111111-1111-4111-8111-111111111111', '70100002'
  ),
  (
    'ffffffff-ffff-4fff-8fff-fffffffffff3',
    '11111111-1111-4111-8111-111111111111', 'NO-COINCIDE'
  );

insert into private.cartera_acl (actor_id, cliente_id)
values (
  '11111111-1111-4111-8111-111111111111',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3'
);

set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.assert_raises(
  $$select test_support.alta_pdf_v2(
    '99999999-9999-4999-8999-999999999991',
    'AEP-ROLLBACK-SNAPSHOT',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3'
  )$$,
  'Faltan datos legales',
  'snapshot invalido revierte contrato cuenta cronograma y job'
);
select crm.convertir_lead_con_domicilio(
  'ffffffff-ffff-4fff-8fff-fffffffffff1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  '  Av. Domicilio Nuevo 456, Lima  '
)::text as conversion_completa \gset
select crm.convertir_lead_con_domicilio(
  'ffffffff-ffff-4fff-8fff-fffffffffff2',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
  'Av. Domicilio Que No Debe Reemplazar 999'
)::text as conversion_conserva \gset
select test_support.assert_raises(
  $$select crm.convertir_lead_con_domicilio(
    'ffffffff-ffff-4fff-8fff-fffffffffff3',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3',
    'Av. Escritura Que Debe Revertirse 777'
  )$$,
  'invalido',
  'conversion fallida no alcanza la escritura de domicilio'
);
reset role;

select test_support.assert_true(
  not exists (
    select 1 from public.contratos
    where id = '99999999-9999-4999-8999-999999999991'
  )
    and not exists (
      select 1 from private.contrato_pdf_jobs
      where contrato_id = '99999999-9999-4999-8999-999999999991'
    )
    and not exists (
      select 1 from crm.contrato_cuentas_pago
      where contrato_id = '99999999-9999-4999-8999-999999999991'
    ),
  'alta moderna no deja filas parciales si falla la reserva'
);

select test_support.assert_true(
  :'conversion_completa'::jsonb->>'domicilio_accion' = 'completado'
    and (
      select domicilio = 'Av. Domicilio Nuevo 456, Lima'
      from public.perfiles
      where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1'
    )
    and (
      select etapa = 'convertido'
        and perfil_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1'::uuid
      from crm.leads
      where id = 'ffffffff-ffff-4fff-8fff-fffffffffff1'
    ),
  'conversion valida completa domicilio dentro del mismo commit'
);
select test_support.assert_true(
  :'conversion_conserva'::jsonb->>'domicilio_accion' = 'conservado'
    and (
      select domicilio = 'Jr. Domicilio Original 123'
      from public.perfiles
      where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2'
    ),
  'conversion nunca pisa un domicilio previo'
);
select test_support.assert_true(
  (
    select domicilio is null
    from public.perfiles
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3'
  )
    and (
      select activo and etapa = 'nuevo' and perfil_id is null
      from crm.leads
      where id = 'ffffffff-ffff-4fff-8fff-fffffffffff3'
    ),
  'fallo de autorizacion/conversion deja lead y domicilio intactos'
);

-- Revisiones: la RPC mantiene el gate de 5 h, abre la congelación solo dentro
-- de esa llamada y deja un snapshot nuevo como única revisión visible.
insert into private.cartera_acl (actor_id, cliente_id)
values (
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333'
) on conflict do nothing;

set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  '12121212-1212-4121-8121-121212121212',
  'AEP-2026-REV-0001'
)::text as alta_revision \gset
select crm.actualizar_contrato_con_cuenta_pdf_v3(
  '12121212-1212-4121-8121-121212121212',
  jsonb_build_object(
    'numero_contrato', 'AEP-2026-REV-0001',
    'capital', 12000,
    'moneda', 'PEN',
    'tasa_anual', 16,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'upgrade',
    'fecha_inicio', '2026-08-19',
    'fecha_vencimiento', '2027-08-19',
    'notas_internas', 'Corrección validada'
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', '2026-09-18',
    'monto_programado', 12160,
    'tipo', 'capital_interes'
  ))
)::text as correccion_revision \gset
reset role;

select test_support.assert_true(
  (:'correccion_revision'::jsonb->>'ok')::boolean
    and :'correccion_revision'::jsonb->'pdf'->>'estado' = 'pendiente'
    and :'correccion_revision'::jsonb->'pdf'->>'job_id'
      is distinct from :'alta_revision'::jsonb->'pdf'->>'job_id'
    and (
      select count(*) = 2 and min(revision) = 1 and max(revision) = 2
      from private.contrato_pdf_jobs
      where contrato_id = '12121212-1212-4121-8121-121212121212'
    )
    and (
      select revision = 2
        and snapshot->'contrato'->>'capital' = '12000'
        and snapshot->'contrato'->>'porcentaje' = '16'
      from private.contrato_pdf_jobs
      where contrato_id = '12121212-1212-4121-8121-121212121212'
      order by revision desc
      limit 1
    ),
  'correccion valida crea revision 2 con snapshot actualizado'
);
set role service_role;
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    '12121212-1212-4121-8121-121212121212',
    '11111111-1111-4111-8111-111111111111',
    'anexo-cronograma-v1'
  )$$,
  'no tiene un PDF sellado',
  'anexo: con una revision nueva pendiente no se emite el anexo de la anterior'
);
reset role;

select test_support.assert_raises(
  $$update public.contratos
       set capital = capital + 1
     where id = '12121212-1212-4121-8121-121212121212'$$,
  'congelados',
  'la excepcion de correccion no queda abierta despues de la RPC'
);

set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  '13131313-1313-4131-8131-131313131313',
  'AEP-2026-REV-VENCIDA'
);
reset role;
update public.contratos
set creado_en = now() - interval '6 hours'
where id = '13131313-1313-4131-8131-131313131313';
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.assert_raises(
  $$select crm.actualizar_contrato_con_cuenta_pdf_v3(
    '13131313-1313-4131-8131-131313131313',
    jsonb_build_object(
      'numero_contrato', 'AEP-2026-REV-VENCIDA',
      'capital', 13000,
      'moneda', 'PEN',
      'tasa_anual', 15,
      'modalidad', 'mensual',
      'tipo_interes', 'simple',
      'categoria', 'nuevo',
      'fecha_inicio', '2026-08-19',
      'fecha_vencimiento', '2027-08-19',
      'notas_internas', null
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', '2026-09-18',
      'monto_programado', 13125,
      'tipo', 'capital_interes'
    ))
  )$$,
  '5 horas',
  'vendedor no corrige ni crea revision despues de 5 horas',
  '42501'
);
reset role;
select test_support.assert_true(
  (
    select count(*) = 1 and max(revision) = 1
    from private.contrato_pdf_jobs
    where contrato_id = '13131313-1313-4131-8131-131313131313'
  ),
  'correccion rechazada no deja job parcial'
);

-- Eliminación: el navegador directo no puede borrar; la Edge obtiene un
-- manifiesto estable de ambos buckets y el finalizador exige token+actor de la
-- autorización Admin/Superadmin original.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  '14141414-1414-4141-8141-141414141414',
  'AEP-2026-DEL-ADMIN'
);
reset role;
insert into public.documentos (contrato_id, storage_path)
values (
  '14141414-1414-4141-8141-141414141414',
  '14141414-1414-4141-8141-141414141414/anexo.pdf'
);

set role service_role;
select test_support.assert_raises(
  $$select crm.contrato_eliminacion_preparar(
    '14141414-1414-4141-8141-141414141414',
    '11111111-1111-4111-8111-111111111111'
  )$$,
  'Admin o Superadmin',
  'vendedor no prepara eliminación',
  '42501'
);
select crm.contrato_eliminacion_preparar(
  '14141414-1414-4141-8141-141414141414',
  '77777777-7777-4777-8777-777777777777'
)::text as preparar_admin \gset
select test_support.assert_raises(
  $$select crm.contrato_pdf_anexo_snapshot(
    '14141414-1414-4141-8141-141414141414',
    '11111111-1111-4111-8111-111111111111',
    'anexo-cronograma-v1'
  )$$,
  'proceso de eliminación',
  'anexo: un contrato en eliminacion no emite anexo',
  '55000'
);
select test_support.assert_raises(
  $$select crm.contrato_eliminacion_finalizar(
    '14141414-1414-4141-8141-141414141414',
    '99999999-9999-4999-8999-999999999999',
    '77777777-7777-4777-8777-777777777777'
  )$$,
  'preparación',
  'token incorrecto no borra',
  'P0002'
);
select test_support.assert_raises(
  format(
    $$select crm.contrato_eliminacion_finalizar(
      '14141414-1414-4141-8141-141414141414',
      %L::uuid,
      '88888888-8888-4888-8888-888888888888'
    )$$,
    :'preparar_admin'::jsonb->>'token'
  ),
  'preparación',
  'otro actor no puede consumir el token de eliminación',
  'P0002'
);
reset role;

select test_support.assert_raises(
  $$update public.cronograma_pagos
       set estado = 'pagado', monto_pagado = monto_programado
     where contrato_id = '14141414-1414-4141-8141-141414141414'$$,
  'proceso de eliminación',
  'un pago no puede aparecer después de autorizar el borrado Admin',
  '55000'
);
select test_support.assert_raises(
  $$insert into public.documentos (contrato_id, storage_path)
    values (
      '14141414-1414-4141-8141-141414141414',
      '14141414-1414-4141-8141-141414141414/tardio.pdf'
    )$$,
  'proceso de eliminación',
  'el manifiesto Storage no admite documentos tardíos',
  '55000'
);

select test_support.assert_true(
  jsonb_array_length(:'preparar_admin'::jsonb->'objetos') = 2
    and :'preparar_admin'::jsonb->'objetos' @> jsonb_build_array(
      jsonb_build_object(
        'bucket', 'documentos',
        'path', '14141414-1414-4141-8141-141414141414/anexo.pdf'
      )
    )
    and :'preparar_admin'::jsonb->'objetos' @> jsonb_build_array(
      jsonb_build_object(
        'bucket', 'contratos-generados',
        'path', (
          select storage_path
          from private.contrato_pdf_jobs
          where contrato_id = '14141414-1414-4141-8141-141414141414'
          order by revision desc
          limit 1
        )
      )
    ),
  'manifiesto de borrado lista documentos y el PDF del contrato exacto'
);

grant select, delete on public.contratos to authenticated;
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '77777777-7777-4777-8777-777777777777',
  false
);
delete from public.contratos
where id = '14141414-1414-4141-8141-141414141414';
reset role;
select test_support.assert_true(
  exists (
    select 1 from public.contratos
    where id = '14141414-1414-4141-8141-141414141414'
  ),
  'RLS cierra el hard-delete directo incluso para Admin'
);

set role service_role;
select crm.contrato_eliminacion_finalizar(
  '14141414-1414-4141-8141-141414141414',
  (:'preparar_admin'::jsonb->>'token')::uuid,
  '77777777-7777-4777-8777-777777777777'
)::text as finalizar_admin \gset
reset role;
select test_support.assert_true(
  (:'finalizar_admin'::jsonb->>'ok')::boolean
    and not exists (
      select 1 from public.contratos
      where id = '14141414-1414-4141-8141-141414141414'
    )
    and not exists (
      select 1 from private.contrato_pdf_jobs
      where contrato_id = '14141414-1414-4141-8141-141414141414'
    )
    and not exists (
      select 1 from public.documentos
      where contrato_id = '14141414-1414-4141-8141-141414141414'
    )
    and not exists (
      select 1 from private.contrato_eliminaciones
      where contrato_id = '14141414-1414-4141-8141-141414141414'
    ),
  'finalizador borra contrato y toda metadata tras Storage'
);

set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.alta_pdf_v2(
  '15151515-1515-4151-8151-151515151515',
  'AEP-2026-DEL-PAGADO'
);
reset role;
update public.cronograma_pagos
set estado = 'pagado', monto_pagado = monto_programado
where contrato_id = '15151515-1515-4151-8151-151515151515';
set role service_role;
select test_support.assert_raises(
  $$select crm.contrato_eliminacion_preparar(
    '15151515-1515-4151-8151-151515151515',
    '77777777-7777-4777-8777-777777777777'
  )$$,
  'solo Superadmin',
  'Admin no borra contrato con pagos',
  '42501'
);
select crm.contrato_eliminacion_preparar(
  '15151515-1515-4151-8151-151515151515',
  '88888888-8888-4888-8888-888888888888'
)::text as preparar_super \gset
select crm.contrato_eliminacion_finalizar(
  '15151515-1515-4151-8151-151515151515',
  (:'preparar_super'::jsonb->>'token')::uuid,
  '88888888-8888-4888-8888-888888888888'
);
reset role;
select test_support.assert_true(
  not exists (
    select 1 from public.contratos
    where id = '15151515-1515-4151-8151-151515151515'
  ),
  'Superadmin sí elimina contrato con pagos'
);

-- ══ El regimen documental por FECHA DE FIRMA (2026-08-20) ═══════════════════
-- Regla de Miguel: el PDF que emite el sistema ES el contrato, pero solo para lo
-- firmado del 2026-08-19 en adelante. Lo anterior ya tiene su contrato en el
-- formato previo y el sistema NO le emite ninguno, aunque se cargue hoy.
-- Estas pruebas EJECUTAN las cuatro puertas; mirar el catalogo no probaria nada.

reset role;
insert into public.perfiles (
  id, rol, nombre_completo, tipo_documento, dni, correo, telefono,
  activo, domicilio
) values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'cliente',
  'Cliente Historico Sin Domicilio', 'dni', '70200001',
  'historico@example.test', '999200001', true, null
);
insert into private.cartera_acl (actor_id, cliente_id)
values (
  '11111111-1111-4111-8111-111111111111',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
);

set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);

-- (1) Firmado el 18-ago, UN DIA antes de la frontera: el contrato nace y no se
-- reserva documento. Y nace aunque el cliente no tenga domicilio — que es
-- exactamente la carga de historial que hace el equipo todos los dias y que
-- hasta hoy chocaba contra un muro que ese contrato no necesita.
select crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb_build_object(
    'id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
    'cliente_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'numero_contrato', 'AEP-2026-HISTORICO-0001',
    'capital', 20000,
    'moneda', 'PEN',
    'tasa_anual', 15,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', '2026-08-18',
    'fecha_vencimiento', '2027-08-18',
    'producto_condicion_id', 'dddddddd-dddd-4ddd-8ddd-dddddddddd01',
    'titulares', '[]'::jsonb
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', '2027-08-18',
    'monto_programado', 23000,
    'tipo', 'capital_interes'
  )),
  jsonb_build_object(
    'banco', 'Banco Test',
    'tipo_cuenta', 'ahorros',
    'numero_cuenta', '001-200001',
    'cci', '12345678901234500001',
    'titular_distinto', false
  )
)::text as alta_regimen_anterior \gset

select test_support.assert_true(
  (:'alta_regimen_anterior'::jsonb->>'id')::uuid =
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'::uuid
    and :'alta_regimen_anterior'::jsonb->'pdf'->>'estado' = 'sin_reserva'
    and (:'alta_regimen_anterior'::jsonb->'pdf'->>'reintentable')::boolean = false
    and :'alta_regimen_anterior'::jsonb->'pdf'->'job_id' = 'null'::jsonb
    and :'alta_regimen_anterior'::jsonb->'pdf'->'archivo' = 'null'::jsonb,
  'alta del regimen anterior: el contrato nace sin reserva y sin prometer documento'
);

reset role;
select test_support.assert_true(
  not exists (
    select 1 from private.contrato_pdf_jobs
    where contrato_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'
  ),
  'alta del regimen anterior: no nace ningun trabajo de documento'
);

-- (2) El MISMO cliente sin domicilio, firmado el 19-ago: ahi el documento SI se
-- emite, la fotografia contractual exige el domicilio y el servidor frena. La
-- frontera abre y cierra por el mismo sitio.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  false
);
select test_support.assert_raises(
  $sql$
  select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object(
      'id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
      'cliente_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'numero_contrato', 'AEP-2026-HISTORICO-0002',
      'capital', 20000,
      'moneda', 'PEN',
      'tasa_anual', 15,
      'modalidad', 'mensual',
      'tipo_interes', 'simple',
      'categoria', 'nuevo',
      'fecha_inicio', '2026-08-19',
      'fecha_vencimiento', '2027-08-19',
      'producto_condicion_id', 'dddddddd-dddd-4ddd-8ddd-dddddddddd01',
      'titulares', '[]'::jsonb
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', '2027-08-19',
      'monto_programado', 23000,
      'tipo', 'capital_interes'
    )),
    jsonb_build_object(
      'banco', 'Banco Test',
      'tipo_cuenta', 'ahorros',
      'numero_cuenta', '001-200002',
      'cci', '12345678901234500002',
      'titular_distinto', false
    )
  );
  $sql$,
  -- El mundo de este oraculo llega hasta la plantilla v5; la ventana del
  -- domicilio (20260819162752) nombra el campo que falta, pero aqui el mensaje
  -- todavia es el generico de la fotografia contractual. Lo que se prueba es la
  -- FRONTERA, no la redaccion: el 19-ago exige los nueve datos y el 18-ago no.
  'datos legales obligatorios',
  'regimen nuevo: sin domicilio no hay documento y por tanto no hay contrato',
  '23514'
);

-- (3) «Ver contrato PDF» sobre un contrato antiguo NO fabrica nada. Este es el
-- camino por el que nacieron los 21 documentos del 18 y 19 de agosto.
-- Se llama como `service_role` porque es quien la ejecuta de verdad: el
-- navegador pasa por la edge `crm-contrato-pdf-v2`, que usa la clave de
-- servicio. `authenticated` NO tiene EXECUTE sobre esta funcion.
set role service_role;
select crm.contrato_pdf_reservar(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
  '11111111-1111-4111-8111-111111111111'
)::text as reserva_regimen_anterior \gset

select test_support.assert_true(
  :'reserva_regimen_anterior'::jsonb->>'estado' = 'sin_reserva'
    and (:'reserva_regimen_anterior'::jsonb->>'reintentable')::boolean = false
    and :'reserva_regimen_anterior'::jsonb->'job_id' = 'null'::jsonb,
  'reservar sobre un contrato antiguo no acuña documento'
);

reset role;
select test_support.assert_true(
  not exists (
    select 1 from private.contrato_pdf_jobs
    where contrato_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'
  ),
  'reservar sobre un contrato antiguo tampoco deja rastro de trabajo'
);

-- (4) El caso REAL de los dos huerfanos de produccion: dos contratos firmados
-- en marzo y mayo que el 19-ago reservaron documento —porque esta frontera no
-- existia todavia— y llevan desde entonces en `pendiente` con CERO intentos.
-- No se pueden reproducir corrigiendo la fecha (los terminos quedan congelados
-- por su PDF legal en cuanto hay reserva), asi que se siembra la fila tal cual
-- quedo. Con la regla nueva el trabajo queda INERTE (nadie lo reclama) e
-- INVISIBLE (el estado responde `sin_reserva`): la pantalla deja de prometer un
-- documento que no va a llegar. No se borra ni se muta ninguna fila.
reset role;
insert into private.contrato_pdf_jobs (
  id, contrato_id, revision, estado, storage_path, nombre_archivo,
  template_version, snapshot, solicitado_por
) values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccc44',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
  1,
  'pendiente',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc2/v2/cccccccc-cccc-4ccc-8ccc-cccccccccc44/contrato.pdf',
  'Contrato-AEP-2026-HISTORICO-0001.pdf',
  'contrato-aep-17-v5',
  '{"snapshotVersion": 2}'::jsonb,
  '11111111-1111-4111-8111-111111111111'
);

select (
  private.contrato_pdf_estado_base('cccccccc-cccc-4ccc-8ccc-ccccccccccc2')
)::text as estado_huerfano \gset
select test_support.assert_true(
  :'estado_huerfano'::jsonb->>'estado' = 'sin_reserva'
    and (:'estado_huerfano'::jsonb->>'reintentable')::boolean = false
    and :'estado_huerfano'::jsonb->'job_id' = 'null'::jsonb,
  'el trabajo huerfano deja de prometer documento en la pantalla'
);

set role service_role;
select (
  crm.contrato_pdf_reclamar(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
    '11111111-1111-4111-8111-111111111111',
    120
  )
)::text as reclamo_huerfano \gset
select test_support.assert_true(
  (:'reclamo_huerfano'::jsonb->>'adquirido')::boolean = false,
  'nadie puede reclamar el turno de un documento del regimen anterior'
);
reset role;
select test_support.assert_true(
  (
    select intentos = 0 and lease_token is null and estado = 'pendiente'
    from private.contrato_pdf_jobs
    where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccc44'
  ),
  'el reclamo negado no consume intento, no entrega lease y no borra la fila'
);

-- (4 bis) `fecha_inicio` es el inicio del PLAZO, no la firma. Caso REAL de
-- produccion: los contratos 2026-01-000891 y 000892 (REATEGUI PEREZ PEDRO IVAN)
-- se cargaron el 1 de JULIO con el plazo empezando el 1 de julio de 2027. Con la
-- fecha de plazo sola caerian en el regimen NUEVO y el sistema les ofreceria un
-- contrato del formato nuevo a una operacion firmada en julio. El suelo de
-- `creado_en` lo impide.
reset role;
insert into public.contratos (
  id, cliente_id, creado_por, numero_contrato, capital, moneda, tasa_anual,
  modalidad, tipo_interes, categoria, fecha_inicio, fecha_vencimiento,
  producto_condicion_id, creado_en
) values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'AEP-2026-PLAZO-FUTURO', 250000, 'PEN', 15,
  'mensual', 'simple', 'nuevo', date '2027-07-01', date '2028-07-01',
  'dddddddd-dddd-4ddd-8ddd-dddddddddd01',
  timestamptz '2026-07-01 18:04:08+00'
);

select test_support.assert_true(
  private.contrato_documental_regimen('cccccccc-cccc-4ccc-8ccc-ccccccccccc5')
    = 'anterior',
  'un plazo que empieza en 2027 pero registrado en julio es del regimen anterior'
);

select (
  private.contrato_pdf_estado_base('cccccccc-cccc-4ccc-8ccc-ccccccccccc5')
)::text as estado_plazo_futuro \gset
select test_support.assert_true(
  :'estado_plazo_futuro'::jsonb->>'estado' = 'sin_reserva'
    and (:'estado_plazo_futuro'::jsonb->>'reintentable')::boolean = false,
  'y por tanto tampoco se le ofrece fabricar documento'
);

-- (5) Los documentos YA emitidos para operaciones antiguas se quedan como
-- estan: sellados y descargables. Esta regla impide que nazcan mas, no esconde
-- los que hay. El contrato legacy esta firmado el 2026-08-17.
select (
  private.contrato_pdf_estado_base('44444444-4444-4444-8444-444444444444')
)::text as estado_legacy_antiguo \gset
select test_support.assert_true(
  :'estado_legacy_antiguo'::jsonb->>'estado' = 'sellado'
    and :'estado_legacy_antiguo'::jsonb->'archivo' <> 'null'::jsonb,
  'un documento antiguo ya emitido sigue sellado y descargable'
);

-- ── Anexo de cronograma: reversa y reaplicación (recuperación hacia adelante) ──
-- La reversa borra las cuatro funciones y CONSERVA la bitacora; la migracion se
-- vuelve a aplicar encima sin perder asientos (revision de Codex, riesgo de regresion).
\ir ../scripts/anexo-cronograma/reversa-anexo-snapshot.sql
select test_support.assert_true(
  to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is null
    and to_regprocedure('crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)') is null
    and to_regprocedure('private.contrato_pdf_anexo_snapshot_base(uuid)') is null
    and to_regprocedure('private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)') is null
    and to_regclass('private.contrato_pdf_anexo_emisiones') is not null
    and (select count(*) = 2 from private.contrato_pdf_anexo_emisiones),
  'anexo: la reversa borra las funciones y conserva la bitacora'
);
\ir ../migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql
select test_support.assert_true(
  to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null
    and to_regprocedure('crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)') is not null
    and (select count(*) = 2 from private.contrato_pdf_anexo_emisiones),
  'anexo: la migracion se reaplica sobre la bitacora conservada sin perder asientos'
);

\echo CONTRATO_PDF_V2_SQL_OK
