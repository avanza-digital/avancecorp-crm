-- PDF contractual v2: autoridad server-side, reserva durable y términos
-- congelados. Esta migración es aditiva respecto del Portal y puede aplicarse
-- tanto sobre una base sin PDF como sobre el candidato v1 local.
begin;

set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $preflight$
begin
  if to_regclass('public.perfiles') is null
     or to_regclass('public.contratos') is null
     or to_regclass('public.cronograma_pagos') is null
     or to_regclass('public.contrato_titulares') is null
     or to_regclass('crm.cuentas_bancarias') is null
     or to_regclass('crm.contrato_cuentas_pago') is null
     or to_regclass('storage.buckets') is null
     or to_regclass('storage.objects') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('crm.actualizar_cliente_gerencia(uuid,jsonb)') is null
     or to_regprocedure('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)') is null
     or to_regprocedure('crm.convertir_lead(uuid,uuid)') is null
     or to_regrole('service_role') is null then
    raise exception
      'Faltan dependencias del PDF v2, contratos, domicilio o Storage';
  end if;
end;
$preflight$;

-- -------------------------------------------------------------------------
-- 1. Domicilio legal compatible con historia legacy
-- -------------------------------------------------------------------------

alter table public.perfiles
  add column if not exists domicilio text;

comment on column public.perfiles.domicilio is
  'Domicilio legal. Puede ser NULL solo por historia legacy; todo contrato PDF v2 exige una fotografía válida.';

do $domicilio_constraint$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.perfiles'::regclass
      and c.conname = 'perfiles_domicilio_legal_valido'
  ) then
    alter table public.perfiles
      add constraint perfiles_domicilio_legal_valido
      check (
        domicilio is null
        or (
          domicilio = btrim(domicilio)
          and length(domicilio) between 5 and 240
          and domicilio !~ '[[:cntrl:]]'
        )
      );
  end if;
end;
$domicilio_constraint$;

create or replace function private.bloquear_borrado_domicilio_legal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.rol = 'cliente'
     and old.domicilio is not null
     and new.domicilio is null then
    raise exception 'El domicilio legal registrado no se puede borrar'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.bloquear_borrado_domicilio_legal()
  from public, anon, authenticated, service_role;

drop trigger if exists perfiles_domicilio_legal_no_borrar on public.perfiles;
create trigger perfiles_domicilio_legal_no_borrar
before update of domicilio on public.perfiles
for each row execute function private.bloquear_borrado_domicilio_legal();

create or replace function crm.actualizar_cliente_gerencia_con_domicilio(
  p_cliente_id uuid,
  p_patch jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_domicilio text;
  v_actualizado boolean;
begin
  if private.rol_crm((select auth.uid())) is distinct from 'gerencia' then
    raise insufficient_privilege using
      message = 'Solo Gerencia puede corregir clientes fuera de cartera';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object'
     or not p_patch ? 'domicilio'
     or jsonb_typeof(p_patch->'domicilio') <> 'string' then
    raise exception 'El domicilio legal del cliente es obligatorio'
      using errcode = '22023';
  end if;

  v_domicilio := btrim(p_patch->>'domicilio');
  if length(v_domicilio) not between 5 and 240
     or v_domicilio ~ '[[:cntrl:]]' then
    raise exception
      'El domicilio legal debe tener entre 5 y 240 caracteres válidos'
      using errcode = '22023';
  end if;

  v_actualizado := crm.actualizar_cliente_gerencia(
    p_cliente_id,
    p_patch - 'domicilio'
  );
  if not v_actualizado then return false; end if;

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_cliente_id
     and rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

revoke all on function crm.actualizar_cliente_gerencia_con_domicilio(uuid,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_cliente_gerencia_con_domicilio(uuid,jsonb)
  to authenticated;

-- Cierra la firma gerencial antigua cuya comparación con NULL era fail-open.
revoke execute on function crm.actualizar_cliente_gerencia(uuid,jsonb)
  from public, anon, authenticated, service_role;

-- La conversión primero autoriza/cierra el lead y solo después completa el
-- domicilio. Ambas acciones pertenecen a la misma transacción PostgREST.
create or replace function crm.convertir_lead_con_domicilio(
  p_lead_id uuid,
  p_perfil_id uuid,
  p_domicilio text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_domicilio text := btrim(p_domicilio);
  v_resultado jsonb;
  v_accion text := 'conservado';
begin
  if p_domicilio is null
     or length(v_domicilio) not between 5 and 240
     or v_domicilio ~ '[[:cntrl:]]' then
    raise exception
      'El domicilio legal debe tener entre 5 y 240 caracteres válidos'
      using errcode = '22023';
  end if;

  -- Si esta llamada falla, todavía no se ha escrito ningún domicilio.
  v_resultado := crm.convertir_lead(p_lead_id, p_perfil_id);

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_perfil_id
     and rol = 'cliente'
     and domicilio is null;
  if found then v_accion := 'completado'; end if;

  return v_resultado || jsonb_build_object('domicilio_accion', v_accion);
end;
$function$;

revoke all on function crm.convertir_lead_con_domicilio(uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.convertir_lead_con_domicilio(uuid,uuid,text)
  to authenticated;

-- -------------------------------------------------------------------------
-- 2. Bucket privado y tablas documental/job
-- -------------------------------------------------------------------------

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'contratos-generados', 'contratos-generados', false, 10485760,
  array['application/pdf']::text[]
)
on conflict (id) do nothing;

do $bucket_privado$
begin
  if not exists (
    select 1
    from storage.buckets b
    where b.id = 'contratos-generados'
      and b.name = 'contratos-generados'
      and b.public is false
      and b.file_size_limit = 10485760
      and b.allowed_mime_types = array['application/pdf']::text[]
  ) then
    raise exception
      'El bucket contratos-generados no conserva su configuración privada';
  end if;
end;
$bucket_privado$;

-- No se modifica el esquema administrado de Storage. Si el candidato v1 fue
-- ensayado localmente, se retira expresamente su trigger antes de continuar.
drop trigger if exists contrato_pdf_objeto_inmutable on storage.objects;
drop function if exists private.bloquear_mutacion_objeto_contrato_pdf();

create table if not exists private.contrato_pdf_jobs (
  id uuid primary key,
  contrato_id uuid not null unique
    references public.contratos(id) on delete restrict,
  estado text not null default 'pendiente'
    constraint contrato_pdf_jobs_estado_valido check (
      estado in (
        'pendiente', 'procesando', 'subido_verificado', 'sellado',
        'error_reintentable', 'integridad_bloqueada'
      )
    ),
  storage_bucket text not null default 'contratos-generados'
    constraint contrato_pdf_jobs_bucket_valido check (
      storage_bucket = 'contratos-generados'
    ),
  storage_path text not null,
  nombre_archivo text not null
    constraint contrato_pdf_jobs_nombre_valido check (
      nombre_archivo = btrim(nombre_archivo)
      and length(nombre_archivo) between 5 and 255
      and nombre_archivo ~* '\.pdf$'
    ),
  template_version text not null default 'contrato-aep-17-v2'
    constraint contrato_pdf_jobs_template_valido check (
      template_version = 'contrato-aep-17-v2'
    ),
  snapshot jsonb not null
    constraint contrato_pdf_jobs_snapshot_objeto check (
      jsonb_typeof(snapshot) = 'object'
    ),
  sha256 text,
  bytes bigint,
  solicitado_por uuid not null
    references public.perfiles(id) on delete restrict,
  intentos integer not null default 0
    constraint contrato_pdf_jobs_intentos_valido check (intentos >= 0),
  lease_token uuid,
  lease_expira_en timestamptz,
  ultimo_error text,
  creado_en timestamptz not null default statement_timestamp(),
  actualizado_en timestamptz not null default statement_timestamp(),
  subido_en timestamptz,
  sellado_en timestamptz,
  constraint contrato_pdf_jobs_ruta_server_side check (
    storage_path = contrato_id::text || '/v2/' || id::text || '/contrato.pdf'
  ),
  constraint contrato_pdf_jobs_bytes_pareados check (
    (sha256 is null and bytes is null)
    or (
      sha256 ~ '^[a-f0-9]{64}$'
      and bytes > 0
      and bytes <= 10485760
    )
  ),
  constraint contrato_pdf_jobs_lease_coherente check (
    (
      estado in ('procesando', 'subido_verificado')
      and lease_token is not null
      and lease_expira_en is not null
    ) or (
      estado not in ('procesando', 'subido_verificado')
      and lease_token is null
      and lease_expira_en is null
    )
  ),
  constraint contrato_pdf_jobs_subida_coherente check (
    (
      estado in ('pendiente', 'procesando')
      and sha256 is null
      and bytes is null
      and subido_en is null
    ) or (
      estado in ('subido_verificado', 'sellado')
      and sha256 is not null
      and bytes is not null
      and subido_en is not null
    ) or estado in ('error_reintentable', 'integridad_bloqueada')
  ),
  constraint contrato_pdf_jobs_sello_coherente check (
    (estado = 'sellado' and sellado_en is not null)
    or (estado <> 'sellado' and sellado_en is null)
  )
);

create index if not exists contrato_pdf_jobs_estado_idx
  on private.contrato_pdf_jobs (estado, actualizado_en);
create index if not exists contrato_pdf_jobs_solicitado_por_idx
  on private.contrato_pdf_jobs (solicitado_por);

alter table private.contrato_pdf_jobs enable row level security;
alter table private.contrato_pdf_jobs force row level security;
revoke all on table private.contrato_pdf_jobs
  from public, anon, authenticated, service_role;

create table if not exists private.contrato_pdfs (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete restrict,
  job_id uuid,
  storage_bucket text not null default 'contratos-generados',
  storage_path text not null,
  nombre_archivo text not null,
  sha256 text not null,
  bytes bigint not null,
  template_version text not null,
  snapshot jsonb not null,
  generado_por uuid not null references public.perfiles(id) on delete restrict,
  generado_en timestamptz not null default statement_timestamp(),
  constraint contrato_pdfs_unico_por_contrato unique (contrato_id),
  constraint contrato_pdfs_ruta_unica unique (storage_bucket, storage_path)
);

alter table private.contrato_pdfs
  add column if not exists job_id uuid;

alter table private.contrato_pdfs
  drop constraint if exists contrato_pdfs_ruta_fija,
  drop constraint if exists contrato_pdfs_template_version_check,
  drop constraint if exists contrato_pdfs_storage_bucket_check,
  drop constraint if exists contrato_pdfs_nombre_archivo_check,
  drop constraint if exists contrato_pdfs_sha256_check,
  drop constraint if exists contrato_pdfs_bytes_check;

do $ledger_constraints$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_job_fk'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_job_fk
      foreign key (job_id) references private.contrato_pdf_jobs(id)
      on delete restrict;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_job_unico'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_job_unico unique (job_id);
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_bucket_valido'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_bucket_valido
      check (storage_bucket = 'contratos-generados');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_nombre_valido'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_nombre_valido check (
        nombre_archivo = btrim(nombre_archivo)
        and length(nombre_archivo) between 5 and 255
        and nombre_archivo ~* '\.pdf$'
      );
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_hash_bytes_validos'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_hash_bytes_validos check (
        sha256 ~ '^[a-f0-9]{64}$'
        and bytes > 0
        and bytes <= 10485760
      );
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_version_ruta_valida'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_version_ruta_valida check (
        (
          template_version = 'contrato-aep-17-v1'
          and job_id is null
          and storage_path = contrato_id::text || '/contrato.pdf'
        )
        or (
          template_version = 'contrato-aep-17-v2'
          and job_id is not null
          and storage_path =
            contrato_id::text || '/v2/' || job_id::text || '/contrato.pdf'
        )
      );
  end if;
end;
$ledger_constraints$;

create index if not exists contrato_pdfs_generado_por_idx
  on private.contrato_pdfs (generado_por);

alter table private.contrato_pdfs enable row level security;
alter table private.contrato_pdfs force row level security;
revoke all on table private.contrato_pdfs
  from public, anon, authenticated, service_role;

create or replace function private.bloquear_mutacion_contrato_pdf()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'El archivo legal del contrato es inmutable'
    using errcode = '55000';
end;
$function$;

revoke all on function private.bloquear_mutacion_contrato_pdf()
  from public, anon, authenticated, service_role;

drop trigger if exists contrato_pdfs_solo_insert on private.contrato_pdfs;
create trigger contrato_pdfs_solo_insert
before update or delete on private.contrato_pdfs
for each row execute function private.bloquear_mutacion_contrato_pdf();

-- -------------------------------------------------------------------------
-- 3. Snapshot completo y helpers privados
-- -------------------------------------------------------------------------

create or replace function private.puede_leer_contrato_pdf(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.contratos c
      where c.id = p_contrato_id
        and private.puede_gestionar_cuentas_cliente(c.cliente_id)
    );
$function$;

revoke all on function private.puede_leer_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.puede_leer_contrato_pdf_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_resultado boolean;
begin
  if p_actor_id is null then return false; end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_resultado := private.puede_leer_contrato_pdf(p_contrato_id);
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  return v_resultado;
exception when others then
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  raise;
end;
$function$;

revoke all on function private.puede_leer_contrato_pdf_como(uuid,uuid)
  from public, anon, authenticated, service_role;

-- La fila padre es el mutex contractual. Los writers de hijos la bloquean en
-- sus triggers; la reserva la bloquea antes de fotografiar, pero nunca bloquea
-- filas hijas. Así no se mantiene ningún lock durante render/Storage.
create or replace function private.bloquear_fila_contrato_pdf(
  p_contrato_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform 1
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
end;
$function$;

revoke all on function private.bloquear_fila_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

-- La firma v1 se deja intacta durante el despliegue aditivo. El worker v2
-- consume exclusivamente esta fotografía versionada.
create or replace function private.contrato_pdf_snapshot_v2_base(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_contrato public.contratos%rowtype;
  v_cliente public.perfiles%rowtype;
  v_analista public.perfiles%rowtype;
  v_cotitulares jsonb;
  v_cronograma jsonb;
  v_cuenta jsonb;
begin
  select * into strict v_contrato
  from public.contratos c
  where c.id = p_contrato_id;

  select * into strict v_cliente
  from public.perfiles p
  where p.id = v_contrato.cliente_id
    and p.rol = 'cliente';

  if v_contrato.creado_por is null then
    raise exception 'El contrato no identifica al analista que lo creó'
      using errcode = '23514';
  end if;

  select * into strict v_analista
  from public.perfiles p
  where p.id = v_contrato.creado_por;

  if nullif(btrim(v_contrato.numero_contrato), '') is null
     or nullif(btrim(v_cliente.nombre_completo), '') is null
     or nullif(btrim(v_cliente.tipo_documento), '') is null
     or nullif(btrim(v_cliente.dni), '') is null
     or nullif(btrim(v_cliente.domicilio), '') is null
     or nullif(btrim(v_cliente.correo), '') is null
     or nullif(btrim(v_analista.nombre_completo), '') is null
     or nullif(btrim(v_analista.dni), '') is null
     or nullif(btrim(v_analista.telefono), '') is null
     or nullif(btrim(v_analista.correo), '') is null then
    raise exception
      'Faltan datos legales obligatorios del titular o del analista'
      using errcode = '23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'orden', t.orden,
        'nombreCompleto', t.nombre_completo,
        'tipoDocumento', upper(t.tipo_documento),
        'documento', t.documento
      ) order by t.orden, t.id
    ),
    '[]'::jsonb
  ) into v_cotitulares
  from public.contrato_titulares t
  where t.contrato_id = p_contrato_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cp.id,
        'numeroCuota', cp.numero_cuota,
        'fechaProgramada', cp.fecha_programada::text,
        'montoProgramado', cp.monto_programado,
        'tipo', cp.tipo
      ) order by cp.numero_cuota, cp.id
    ),
    '[]'::jsonb
  ) into v_cronograma
  from public.cronograma_pagos cp
  where cp.contrato_id = p_contrato_id;

  if jsonb_array_length(v_cronograma) = 0 then
    raise exception 'El contrato no tiene cronograma contractual'
      using errcode = '23514';
  end if;

  select jsonb_build_object(
    'cuentaId', cb.id,
    'moneda', cb.moneda,
    'banco', cb.banco,
    'tipoCuenta', cb.tipo_cuenta,
    'numeroCuenta', cb.numero_cuenta,
    'cci', cb.cci,
    'titularDistinto', cb.titular_distinto,
    'beneficiarioNombre', cb.beneficiario_nombre,
    'beneficiarioDocumento', cb.beneficiario_dni,
    'origen', cb.origen
  ) into v_cuenta
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = p_contrato_id;

  if v_cuenta is null then
    raise exception 'El contrato no tiene una cuenta de pago contractual'
      using errcode = '23514';
  end if;

  return jsonb_build_object(
    'snapshotVersion', 2,
    'contrato', jsonb_build_object(
      'id', v_contrato.id,
      'numero', v_contrato.numero_contrato,
      'clienteId', v_contrato.cliente_id,
      'capital', v_contrato.capital,
      'moneda', v_contrato.moneda,
      'porcentaje', v_contrato.tasa_anual,
      'modalidad', v_contrato.modalidad,
      'tipoInteres', v_contrato.tipo_interes,
      'categoria', v_contrato.categoria,
      'fechaInicio', v_contrato.fecha_inicio::text,
      'fechaVencimiento', v_contrato.fecha_vencimiento::text,
      'productoCondicionId', v_contrato.producto_condicion_id,
      'creadoPor', v_contrato.creado_por
    ),
    'titular', jsonb_build_object(
      'id', v_cliente.id,
      'nombreCompleto', v_cliente.nombre_completo,
      'tipoDocumento', upper(v_cliente.tipo_documento),
      'documento', v_cliente.dni,
      'domicilio', v_cliente.domicilio,
      'correo', v_cliente.correo
    ),
    'analista', jsonb_build_object(
      'id', v_analista.id,
      'nombreCompleto', v_analista.nombre_completo,
      'documento', v_analista.dni,
      'celular', v_analista.telefono,
      'correo', v_analista.correo
    ),
    'cotitulares', v_cotitulares,
    'cronograma', v_cronograma,
    'cuentaPago', v_cuenta
  );
exception when no_data_found then
  raise exception 'Contrato, titular o analista inexistente'
    using errcode = 'P0002';
end;
$function$;

revoke all on function private.contrato_pdf_snapshot_v2_base(uuid)
  from public, anon, authenticated, service_role;

create or replace function crm.contrato_pdf_snapshot_v2(p_contrato_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.puede_leer_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  return private.contrato_pdf_snapshot_v2_base(p_contrato_id);
end;
$function$;

create or replace function private.contrato_pdf_archivo_base(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_pdf private.contrato_pdfs%rowtype;
begin
  select * into v_pdf
  from private.contrato_pdfs p
  where p.contrato_id = p_contrato_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'contrato_id', v_pdf.contrato_id,
    'job_id', v_pdf.job_id,
    'storage_bucket', v_pdf.storage_bucket,
    'storage_path', v_pdf.storage_path,
    'nombre_archivo', v_pdf.nombre_archivo,
    'sha256', v_pdf.sha256,
    'bytes', v_pdf.bytes,
    'template_version', v_pdf.template_version,
    'generado_en', v_pdf.generado_en
  );
end;
$function$;

revoke all on function private.contrato_pdf_archivo_base(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.contrato_pdf_estado_base(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_job private.contrato_pdf_jobs%rowtype;
  v_archivo jsonb := private.contrato_pdf_archivo_base(p_contrato_id);
  v_reintentable boolean;
  v_ledger_coherente boolean := false;
  v_integridad boolean := false;
begin
  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id;

  if not found then
    if v_archivo is not null then
      return jsonb_build_object(
        'contrato_id', p_contrato_id,
        'job_id', null,
        'estado', 'sellado',
        'storage_bucket', v_archivo->'storage_bucket',
        'storage_path', v_archivo->'storage_path',
        'nombre_archivo', v_archivo->'nombre_archivo',
        'template_version', v_archivo->'template_version',
        'intentos', 0,
        'lease_expira_en', null,
        'reintentable', false,
        'sha256', v_archivo->'sha256',
        'bytes', v_archivo->'bytes',
        'archivo', v_archivo
      );
    end if;
    return jsonb_build_object(
      'contrato_id', p_contrato_id,
      'job_id', null,
      'estado', 'sin_reserva',
      'storage_bucket', 'contratos-generados',
      'storage_path', null,
      'nombre_archivo', null,
      'template_version', null,
      'intentos', 0,
      'lease_expira_en', null,
      'reintentable', true,
      'sha256', null,
      'bytes', null,
      'archivo', null
    );
  end if;

  if v_job.estado = 'integridad_bloqueada' then
    v_integridad := true;
  elsif v_job.estado = 'sellado' and v_archivo is null then
    v_integridad := true;
    v_job.estado := 'integridad_bloqueada';
  elsif v_archivo is not null then
    select exists (
      select 1
      from private.contrato_pdfs p
      where p.contrato_id = v_job.contrato_id
        and p.job_id = v_job.id
        and p.storage_bucket = v_job.storage_bucket
        and p.storage_path = v_job.storage_path
        and p.nombre_archivo = v_job.nombre_archivo
        and p.sha256 = v_job.sha256
        and p.bytes = v_job.bytes
        and p.template_version = v_job.template_version
        and p.snapshot = v_job.snapshot
        and p.generado_por = v_job.solicitado_por
    ) into v_ledger_coherente;

    if v_job.estado <> 'sellado' or not v_ledger_coherente then
      v_integridad := true;
      v_job.estado := 'integridad_bloqueada';
    end if;
  end if;

  v_reintentable := v_job.estado in ('pendiente', 'error_reintentable')
    or (
      v_job.estado in ('procesando', 'subido_verificado')
      and coalesce(v_job.lease_expira_en, '-infinity'::timestamptz) <= now()
    );
  return jsonb_build_object(
    'contrato_id', v_job.contrato_id,
    'job_id', v_job.id,
    'estado', v_job.estado,
    'storage_bucket', v_job.storage_bucket,
    'storage_path', v_job.storage_path,
    'nombre_archivo', v_job.nombre_archivo,
    'template_version', v_job.template_version,
    'intentos', v_job.intentos,
    'lease_expira_en', v_job.lease_expira_en,
    'reintentable', case
      when v_archivo is not null or v_integridad then false
      else v_reintentable
    end,
    'sha256', coalesce(v_archivo->'sha256', to_jsonb(v_job.sha256)),
    'bytes', coalesce(v_archivo->'bytes', to_jsonb(v_job.bytes)),
    'archivo', v_archivo
  ) || case
    when v_integridad then jsonb_build_object(
      'ok', false,
      'codigo', 'PDF_INTEGRIDAD_BLOQUEADA'
    )
    else '{}'::jsonb
  end;
end;
$function$;

revoke all on function private.contrato_pdf_estado_base(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.nombre_archivo_contrato_pdf(
  p_contrato_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select 'Contrato-' || left(
    coalesce(
      nullif(
        regexp_replace(btrim(c.numero_contrato), '[^[:alnum:]_-]+', '-', 'g'),
        ''
      ),
      c.id::text
    ),
    220
  ) || '.pdf'
  from public.contratos c
  where c.id = p_contrato_id;
$function$;

revoke all on function private.nombre_archivo_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.crear_job_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job_id uuid;
  v_snapshot jsonb;
  v_nombre text;
begin
  -- Rechaza UUID ajenos antes de entrar al mutex. Se repite bajo lock para
  -- cerrar un cambio concurrente de cartera o permisos.
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if exists (
    select 1 from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
  ) or exists (
    select 1 from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
  ) then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  v_job_id := gen_random_uuid();
  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, estado, storage_path, nombre_archivo,
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    'contrato-aep-17-v2',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

revoke all on function private.crear_job_contrato_pdf_base(uuid,uuid)
  from public, anon, authenticated, service_role;

-- -------------------------------------------------------------------------
-- 4. Congelación documental desde la reserva (sin bloquear pagos)
-- -------------------------------------------------------------------------

create or replace function private.contrato_documental_congelado(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
  ) or exists (
    select 1
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
  );
$function$;

revoke all on function private.contrato_documental_congelado(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.proteger_contrato_documental()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid := old.id;
  v_cambio_documental boolean := true;
begin
  if tg_op = 'UPDATE' then
    v_cambio_documental := row(
      new.id,
      new.cliente_id,
      new.numero_contrato,
      new.capital,
      new.moneda,
      new.tasa_anual,
      new.modalidad,
      new.tipo_interes,
      new.fecha_inicio,
      new.fecha_vencimiento,
      new.categoria,
      new.producto_condicion_id,
      new.creado_por
    ) is distinct from row(
      old.id,
      old.cliente_id,
      old.numero_contrato,
      old.capital,
      old.moneda,
      old.tasa_anual,
      old.modalidad,
      old.tipo_interes,
      old.fecha_inicio,
      old.fecha_vencimiento,
      old.categoria,
      old.producto_condicion_id,
      old.creado_por
    );
  end if;

  if v_cambio_documental
     and private.contrato_documental_congelado(v_contrato_id) then
    raise exception 'Los términos del contrato están congelados por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function private.proteger_contrato_documental()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_contratos_00_documental_congelado
  on public.contratos;
create trigger trg_contratos_00_documental_congelado
before update or delete on public.contratos
for each row execute function private.proteger_contrato_documental();

create or replace function private.bloquear_contratos_hijo_documental(
  p_contrato_a uuid,
  p_contrato_b uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  for v_id in
    select distinct x.id
    from unnest(array[p_contrato_a, p_contrato_b]::uuid[]) as x(id)
    where x.id is not null
    order by x.id
  loop
    perform private.bloquear_fila_contrato_pdf(v_id);
  end loop;
end;
$function$;

revoke all on function private.bloquear_contratos_hijo_documental(uuid,uuid)
  from public, anon, authenticated, service_role;

create or replace function private.proteger_cronograma_documental()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_anterior uuid := case when tg_op in ('UPDATE', 'DELETE') then old.contrato_id end;
  v_nuevo uuid := case when tg_op in ('INSERT', 'UPDATE') then new.contrato_id end;
  v_cambio_documental boolean := true;
begin
  if tg_op = 'UPDATE' then
    v_cambio_documental := row(
      new.id,
      new.contrato_id,
      new.numero_cuota,
      new.fecha_programada,
      new.monto_programado,
      new.tipo
    ) is distinct from row(
      old.id,
      old.contrato_id,
      old.numero_cuota,
      old.fecha_programada,
      old.monto_programado,
      old.tipo
    );
  end if;

  -- estado, monto_pagado, fecha_pago_real, recordatorios y registrado_por son
  -- operación de cobranza: no entran al snapshot ni esperan este mutex.
  if not v_cambio_documental then return new; end if;

  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if (v_anterior is not null and private.contrato_documental_congelado(v_anterior))
     or (v_nuevo is not null and private.contrato_documental_congelado(v_nuevo)) then
    raise exception 'El cronograma contractual está congelado por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function private.proteger_cronograma_documental()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_cronograma_pagos_00_documental_congelado
  on public.cronograma_pagos;
create trigger trg_cronograma_pagos_00_documental_congelado
before insert or update or delete on public.cronograma_pagos
for each row execute function private.proteger_cronograma_documental();

create or replace function private.proteger_titulares_documentales()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_anterior uuid := case when tg_op in ('UPDATE', 'DELETE') then old.contrato_id end;
  v_nuevo uuid := case when tg_op in ('INSERT', 'UPDATE') then new.contrato_id end;
begin
  if tg_op = 'UPDATE' and new is not distinct from old then return new; end if;

  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if (v_anterior is not null and private.contrato_documental_congelado(v_anterior))
     or (v_nuevo is not null and private.contrato_documental_congelado(v_nuevo)) then
    raise exception 'Los titulares están congelados por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function private.proteger_titulares_documentales()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_contrato_titulares_00_documental_congelado
  on public.contrato_titulares;
create trigger trg_contrato_titulares_00_documental_congelado
before insert or update or delete on public.contrato_titulares
for each row execute function private.proteger_titulares_documentales();

-- -------------------------------------------------------------------------
-- 5. API autenticada: alta atómica, reserva, estado y metadatos de descarga
-- -------------------------------------------------------------------------

create or replace function crm.crear_contrato_con_cuenta_pdf_v2(
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
  v_actor_id uuid := (select auth.uid());
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    p_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  return v_resultado || jsonb_build_object('pdf', v_pdf);
end;
$function$;

create or replace function crm.contrato_pdf_reservar(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return private.crear_job_contrato_pdf_base(p_contrato_id, p_actor_id);
end;
$function$;

create or replace function crm.contrato_pdf_estado_fn(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.puede_leer_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

create or replace function crm.contrato_pdf_archivo_fn(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_estado jsonb;
begin
  if not private.puede_leer_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  v_estado := private.contrato_pdf_estado_base(p_contrato_id);
  if v_estado->>'estado' = 'integridad_bloqueada' then
    raise exception 'El PDF contractual tiene su integridad bloqueada'
      using errcode = '55000';
  end if;
  return private.contrato_pdf_archivo_base(p_contrato_id);
end;
$function$;

-- -------------------------------------------------------------------------
-- 6. API del worker: leases cortos, sin locks durante render ni Storage
-- -------------------------------------------------------------------------

create or replace function crm.contrato_pdf_reclamar(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job private.contrato_pdf_jobs%rowtype;
  v_token uuid;
  v_adquirido boolean := false;
  v_estado_siguiente text;
  v_respuesta jsonb;
begin
  if p_lease_segundos is null
     or p_lease_segundos not between 30 and 300 then
    raise exception 'El lease debe durar entre 30 y 300 segundos'
      using errcode = '22023';
  end if;

  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id;
  if not found then
    raise exception 'El contrato no tiene una reserva PDF v2'
      using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_job.contrato_id);
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id
  for update;

  -- El creador de la reserva es procedencia inmutable, no dueño perpetuo del
  -- trabajo. Un actor que hoy conserva acceso al contrato puede recuperar un
  -- job pendiente o un lease vencido; el mutex y el token impiden robar un
  -- intento vigente.
  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id,
    p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_respuesta := private.contrato_pdf_estado_base(v_job.contrato_id);
  if (v_respuesta->>'estado') = 'integridad_bloqueada'
     and v_job.estado <> 'integridad_bloqueada' then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           sellado_en = null,
           ultimo_error = 'LEDGER_INCOHERENTE',
           actualizado_en = statement_timestamp()
     where id = v_job.id;
    return private.contrato_pdf_estado_base(v_job.contrato_id)
      || jsonb_build_object('adquirido', false);
  end if;

  if v_job.estado in ('sellado', 'integridad_bloqueada') then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  if v_job.estado in ('pendiente', 'error_reintentable') then
    v_adquirido := true;
    v_estado_siguiente := case
      when v_job.sha256 is null then 'procesando'
      else 'subido_verificado'
    end;
  elsif v_job.estado in ('procesando', 'subido_verificado')
        and v_job.lease_expira_en <= statement_timestamp() then
    v_adquirido := true;
    v_estado_siguiente := v_job.estado;
  end if;

  if not v_adquirido then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  v_token := gen_random_uuid();
  update private.contrato_pdf_jobs
     set estado = v_estado_siguiente,
         lease_token = v_token,
         lease_expira_en = statement_timestamp()
           + make_interval(secs => p_lease_segundos),
         intentos = intentos + 1,
         ultimo_error = null,
         actualizado_en = statement_timestamp()
   where id = v_job.id;

  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id;

  return private.contrato_pdf_estado_base(v_job.contrato_id)
    || jsonb_build_object(
      'adquirido', true,
      'lease_token', v_token,
      'snapshot', v_job.snapshot,
      'renderizado_en', v_job.creado_en
    );
end;
$function$;

create or replace function crm.contrato_pdf_marcar_subido(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid,
  p_sha256 text,
  p_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
  v_job private.contrato_pdf_jobs%rowtype;
  v_sha256 text := lower(btrim(p_sha256));
  v_estado jsonb;
begin
  if v_sha256 is null
     or v_sha256 !~ '^[a-f0-9]{64}$'
     or p_bytes is null
     or p_bytes <= 0
     or p_bytes > 10485760 then
    raise exception 'Fingerprint PDF inválido'
      using errcode = '22023';
  end if;

  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = p_job_id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id,
    p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_estado := private.contrato_pdf_estado_base(v_contrato_id);
  if (v_estado->>'estado') = 'integridad_bloqueada'
     and v_job.estado <> 'integridad_bloqueada' then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           sellado_en = null,
           ultimo_error = 'LEDGER_INCOHERENTE',
           actualizado_en = statement_timestamp()
     where id = p_job_id;
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  if v_job.estado = 'integridad_bloqueada' then
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;
  if v_job.estado = 'sellado' then
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  if v_job.estado = 'subido_verificado'
     and v_job.lease_token = p_lease_token
     and v_job.sha256 = v_sha256
     and v_job.bytes = p_bytes then
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  if v_job.lease_token is distinct from p_lease_token then
    raise exception 'El lease PDF ya no pertenece a este intento'
      using errcode = '40001';
  end if;

  if v_job.estado = 'subido_verificado' then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           ultimo_error = 'FINGERPRINT_DIVERGENTE',
           actualizado_en = statement_timestamp()
     where id = p_job_id;
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  if v_job.estado <> 'procesando'
     or v_job.lease_expira_en <= statement_timestamp() then
    raise exception 'El job PDF no tiene un lease activo para subir'
      using errcode = '40001';
  end if;

  update private.contrato_pdf_jobs
     set estado = 'subido_verificado',
         sha256 = v_sha256,
         bytes = p_bytes,
         subido_en = statement_timestamp(),
         ultimo_error = null,
         actualizado_en = statement_timestamp()
   where id = p_job_id;

  return private.contrato_pdf_estado_base(v_contrato_id);
end;
$function$;

create or replace function crm.contrato_pdf_marcar_error(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid,
  p_error_codigo text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
  v_job private.contrato_pdf_jobs%rowtype;
  v_codigo text := upper(btrim(p_error_codigo));
  v_estado jsonb;
begin
  if v_codigo is null or v_codigo !~ '^[A-Z0-9_:-]{1,80}$' then
    raise exception 'Código de error PDF inválido'
      using errcode = '22023';
  end if;

  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = p_job_id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id,
    p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_estado := private.contrato_pdf_estado_base(v_contrato_id);
  if (v_estado->>'estado') = 'integridad_bloqueada'
     and v_job.estado <> 'integridad_bloqueada' then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           sellado_en = null,
           ultimo_error = 'LEDGER_INCOHERENTE',
           actualizado_en = statement_timestamp()
     where id = p_job_id;
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  if v_job.estado in ('sellado', 'integridad_bloqueada') then
    return v_estado;
  end if;
  if v_job.estado = 'error_reintentable' then
    return v_estado;
  end if;

  if v_job.lease_token is distinct from p_lease_token
     or v_job.estado not in ('procesando', 'subido_verificado')
     or v_job.lease_expira_en <= statement_timestamp() then
    raise exception 'El lease PDF ya no pertenece a este intento'
      using errcode = '40001';
  end if;

  update private.contrato_pdf_jobs
     set estado = case
           when v_codigo like 'INTEGRIDAD\_%' escape '\'
             then 'integridad_bloqueada'
           else 'error_reintentable'
         end,
         lease_token = null,
         lease_expira_en = null,
         ultimo_error = v_codigo,
         actualizado_en = statement_timestamp()
   where id = p_job_id;

  return private.contrato_pdf_estado_base(v_contrato_id);
end;
$function$;

create or replace function crm.contrato_pdf_finalizar(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
  v_job private.contrato_pdf_jobs%rowtype;
  v_pdf private.contrato_pdfs%rowtype;
  v_coherente boolean := false;
  v_estado jsonb;
begin
  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = p_job_id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id,
    p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  select * into v_pdf
  from private.contrato_pdfs p
  where p.contrato_id = v_contrato_id;
  if found then
    v_coherente := v_pdf.job_id = v_job.id
      and v_pdf.storage_bucket = v_job.storage_bucket
      and v_pdf.storage_path = v_job.storage_path
      and v_pdf.nombre_archivo = v_job.nombre_archivo
      and v_pdf.sha256 = v_job.sha256
      and v_pdf.bytes = v_job.bytes
      and v_pdf.template_version = v_job.template_version
      and v_pdf.snapshot = v_job.snapshot
      and v_pdf.generado_por = v_job.solicitado_por;

    if not v_coherente then
      if v_job.estado <> 'integridad_bloqueada' then
        update private.contrato_pdf_jobs
           set estado = 'integridad_bloqueada',
               lease_token = null,
               lease_expira_en = null,
               sellado_en = null,
               ultimo_error = 'LEDGER_INCOHERENTE',
               actualizado_en = statement_timestamp()
         where id = p_job_id;
      end if;
      return private.contrato_pdf_estado_base(v_contrato_id);
    end if;

    if v_job.estado = 'integridad_bloqueada' then
      return private.contrato_pdf_estado_base(v_contrato_id);
    end if;
    if v_job.estado <> 'sellado' then
      update private.contrato_pdf_jobs
         set estado = 'sellado',
             lease_token = null,
             lease_expira_en = null,
             ultimo_error = null,
             sellado_en = coalesce(sellado_en, statement_timestamp()),
             actualizado_en = statement_timestamp()
       where id = p_job_id;
    end if;
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  v_estado := private.contrato_pdf_estado_base(v_contrato_id);
  if (v_estado->>'estado') = 'integridad_bloqueada'
     or v_job.estado = 'integridad_bloqueada' then
    if v_job.estado <> 'integridad_bloqueada' then
      update private.contrato_pdf_jobs
         set estado = 'integridad_bloqueada',
             lease_token = null,
             lease_expira_en = null,
             sellado_en = null,
             ultimo_error = 'LEDGER_FALTANTE',
             actualizado_en = statement_timestamp()
       where id = p_job_id;
    end if;
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  if v_job.estado <> 'subido_verificado'
     or v_job.lease_token is distinct from p_lease_token
     or v_job.lease_expira_en <= statement_timestamp() then
    raise exception 'El job PDF no está listo o su lease venció'
      using errcode = '40001';
  end if;

  insert into private.contrato_pdfs (
    contrato_id,
    job_id,
    storage_bucket,
    storage_path,
    nombre_archivo,
    sha256,
    bytes,
    template_version,
    snapshot,
    generado_por,
    generado_en
  ) values (
    v_job.contrato_id,
    v_job.id,
    v_job.storage_bucket,
    v_job.storage_path,
    v_job.nombre_archivo,
    v_job.sha256,
    v_job.bytes,
    v_job.template_version,
    v_job.snapshot,
    v_job.solicitado_por,
    statement_timestamp()
  )
  on conflict do nothing;

  select * into strict v_pdf
  from private.contrato_pdfs p
  where p.contrato_id = v_contrato_id;
  v_coherente := v_pdf.job_id = v_job.id
    and v_pdf.storage_bucket = v_job.storage_bucket
    and v_pdf.storage_path = v_job.storage_path
    and v_pdf.nombre_archivo = v_job.nombre_archivo
    and v_pdf.sha256 = v_job.sha256
    and v_pdf.bytes = v_job.bytes
    and v_pdf.template_version = v_job.template_version
    and v_pdf.snapshot = v_job.snapshot
    and v_pdf.generado_por = v_job.solicitado_por;

  if not v_coherente then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           ultimo_error = 'LEDGER_CONFLICTIVO',
           actualizado_en = statement_timestamp()
     where id = p_job_id;
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;

  update private.contrato_pdf_jobs
     set estado = 'sellado',
         lease_token = null,
         lease_expira_en = null,
         ultimo_error = null,
         sellado_en = statement_timestamp(),
         actualizado_en = statement_timestamp()
   where id = p_job_id;

  return private.contrato_pdf_estado_base(v_contrato_id);
end;
$function$;

-- Defensa en profundidad: ni una futura función SECURITY DEFINER puede
-- reescribir la identidad/snapshot del job o saltar el autómata por accidente.
create or replace function private.proteger_job_contrato_pdf()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_transicion_valida boolean;
  v_reclamo boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'El job documental no se puede eliminar'
      using errcode = '55000';
  end if;

  if row(
    new.id,
    new.contrato_id,
    new.storage_bucket,
    new.storage_path,
    new.nombre_archivo,
    new.template_version,
    new.snapshot,
    new.solicitado_por,
    new.creado_en
  ) is distinct from row(
    old.id,
    old.contrato_id,
    old.storage_bucket,
    old.storage_path,
    old.nombre_archivo,
    old.template_version,
    old.snapshot,
    old.solicitado_por,
    old.creado_en
  ) then
    raise exception 'La identidad y fotografía del job PDF son inmutables'
      using errcode = '55000';
  end if;

  if old.sha256 is not null and row(new.sha256, new.bytes, new.subido_en)
     is distinct from row(old.sha256, old.bytes, old.subido_en) then
    raise exception 'El fingerprint PDF ya registrado es inmutable'
      using errcode = '55000';
  end if;

  v_transicion_valida := new.estado = old.estado
    or (old.estado = 'pendiente' and new.estado in ('procesando', 'integridad_bloqueada'))
    or (old.estado = 'procesando' and new.estado in (
      'subido_verificado', 'error_reintentable', 'integridad_bloqueada'
    ))
    or (old.estado = 'subido_verificado' and new.estado in (
      'sellado', 'error_reintentable', 'integridad_bloqueada'
    ))
    or (old.estado = 'error_reintentable' and new.estado in (
      'procesando', 'subido_verificado', 'integridad_bloqueada'
    ))
    or (old.estado = 'sellado' and new.estado = 'integridad_bloqueada');
  if not v_transicion_valida then
    raise exception 'Transición de estado PDF inválida: % -> %',
      old.estado, new.estado using errcode = '23514';
  end if;

  v_reclamo := new.intentos = old.intentos + 1
    and (
      (old.estado in ('pendiente', 'error_reintentable')
        and new.estado in ('procesando', 'subido_verificado'))
      or (old.estado = new.estado
        and old.estado in ('procesando', 'subido_verificado')
        and old.lease_expira_en <= statement_timestamp())
    );
  if not (new.intentos = old.intentos or v_reclamo) then
    raise exception 'Contador de intentos PDF inválido'
      using errcode = '23514';
  end if;
  if new.intentos = old.intentos + 1 and not v_reclamo then
    raise exception 'El contador PDF solo aumenta al reclamar un lease'
      using errcode = '23514';
  end if;
  if new.actualizado_en < old.actualizado_en then
    raise exception 'La marca temporal del job PDF no puede retroceder'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.proteger_job_contrato_pdf()
  from public, anon, authenticated, service_role;

drop trigger if exists contrato_pdf_jobs_transiciones_validas
  on private.contrato_pdf_jobs;
create trigger contrato_pdf_jobs_transiciones_validas
before update or delete on private.contrato_pdf_jobs
for each row execute function private.proteger_job_contrato_pdf();

-- -------------------------------------------------------------------------
-- 7. Superficie de privilegios y cierre de la vía v1 controlada por browser
-- -------------------------------------------------------------------------

revoke all on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_reservar(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_estado_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_archivo_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_snapshot_v2(uuid)
  from public, anon, authenticated, service_role;

grant execute on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)
  to authenticated;
grant execute on function crm.contrato_pdf_estado_fn(uuid)
  to authenticated;
grant execute on function crm.contrato_pdf_archivo_fn(uuid)
  to authenticated;
grant execute on function crm.contrato_pdf_reservar(uuid,uuid)
  to service_role;
grant execute on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)
  to service_role;
grant execute on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  to service_role;

do $cerrar_registro_v1$
begin
  if to_regprocedure(
    'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid)'
  ) is not null then
    execute 'revoke all on function '
      || 'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid) '
      || 'from public, anon, authenticated, service_role';
  end if;
end;
$cerrar_registro_v1$;

comment on table private.contrato_pdf_jobs is
  'Reserva durable v2; snapshot y ruta server-side inmutables, con lease corto para I/O externo.';
comment on table private.contrato_pdfs is
  'Ledger inmutable compatible con archivos v1 y jobs server-side v2.';
comment on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) is
  'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2.';
comment on function crm.contrato_pdf_reclamar(uuid,uuid,integer) is
  'Entrega un lease corto y el snapshot congelado a un worker service_role.';

do $postflight$
begin
  if not (
    (select c.relrowsecurity and c.relforcerowsecurity
     from pg_catalog.pg_class c
     where c.oid = 'private.contrato_pdf_jobs'::regclass)
    and
    (select c.relrowsecurity and c.relforcerowsecurity
     from pg_catalog.pg_class c
     where c.oid = 'private.contrato_pdfs'::regclass)
  ) then
    raise exception 'Las tablas PDF privadas no tienen RLS forzada';
  end if;

  if has_table_privilege('anon', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('authenticated', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('service_role', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('anon', 'private.contrato_pdfs', 'SELECT')
     or has_table_privilege('authenticated', 'private.contrato_pdfs', 'SELECT')
     or has_table_privilege('service_role', 'private.contrato_pdfs', 'SELECT') then
    raise exception 'Existe acceso directo indebido a tablas PDF privadas';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'storage.objects'::regclass
      and not t.tgisinternal
      and t.tgname = 'contrato_pdf_objeto_inmutable'
  ) then
    raise exception 'El PDF v2 no debe alterar storage.objects con triggers';
  end if;
end;
$postflight$;

commit;
