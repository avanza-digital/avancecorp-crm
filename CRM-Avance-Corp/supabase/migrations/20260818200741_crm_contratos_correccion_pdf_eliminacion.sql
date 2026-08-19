-- Contratos corregibles con revisión PDF y borrado server-side.
--
-- Invariantes:
--   1. La autorización de la corrección sigue viviendo en las RPC existentes
--      (autor/cartera/ventana de 5 h para vendedor; poderes administrativos).
--   2. Una corrección confirmada fotografía una revisión PDF nueva en la MISMA
--      transacción. El PDF anterior queda como historia inmutable y deja de ser
--      el archivo visible del contrato.
--   3. Nadie borra public.contratos por PostgREST. Admin/Superadmin preparan el
--      borrado; la Edge elimina primero los objetos mediante Storage API y una
--      segunda RPC finaliza la eliminación de la base.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $preflight$
begin
  if to_regclass('public.contratos') is null
     or to_regclass('public.cronograma_pagos') is null
     or to_regclass('public.contrato_titulares') is null
     or to_regclass('public.documentos') is null
     or to_regclass('private.contrato_pdf_jobs') is null
     or to_regclass('private.contrato_pdfs') is null
     or to_regprocedure('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)') is null
     or to_regprocedure('public.actualizar_numero_contrato(uuid,text,text,text)') is null
     or to_regprocedure('public.es_admin()') is null
     or to_regprocedure('public.es_superadmin()') is null
     or to_regrole('service_role') is null then
    raise exception
      'Faltan dependencias de contratos, PDF, documentos o autorización administrativa';
  end if;
end;
$preflight$;

-- -------------------------------------------------------------------------
-- 1. Historial de revisiones: solo la revisión más alta es la vigente
-- -------------------------------------------------------------------------

alter table private.contrato_pdf_jobs
  add column if not exists revision integer not null default 1;

alter table private.contrato_pdfs
  add column if not exists revision integer not null default 1;

alter table private.contrato_pdf_jobs
  drop constraint if exists contrato_pdf_jobs_contrato_id_key;

alter table private.contrato_pdfs
  drop constraint if exists contrato_pdfs_unico_por_contrato;

do $revision_constraints$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdf_jobs'::regclass
      and conname = 'contrato_pdf_jobs_revision_valida'
  ) then
    alter table private.contrato_pdf_jobs
      add constraint contrato_pdf_jobs_revision_valida check (revision > 0);
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdf_jobs'::regclass
      and conname = 'contrato_pdf_jobs_revision_unica'
  ) then
    alter table private.contrato_pdf_jobs
      add constraint contrato_pdf_jobs_revision_unica
      unique (contrato_id, revision);
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_revision_valida'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_revision_valida check (revision > 0);
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'private.contrato_pdfs'::regclass
      and conname = 'contrato_pdfs_revision_unica'
  ) then
    alter table private.contrato_pdfs
      add constraint contrato_pdfs_revision_unica
      unique (contrato_id, revision);
  end if;
end;
$revision_constraints$;

create table private.contrato_eliminaciones (
  contrato_id uuid primary key
    references public.contratos(id) on delete restrict,
  token uuid not null unique default gen_random_uuid(),
  solicitado_por uuid not null
    references public.perfiles(id) on delete restrict,
  objetos jsonb not null default '[]'::jsonb
    constraint contrato_eliminaciones_objetos_array check (
      jsonb_typeof(objetos) = 'array'
      and jsonb_array_length(objetos) <= 1000
    ),
  creado_en timestamptz not null default statement_timestamp()
);

-- La PK cubre la FK contrato_id; esta segunda FK necesita su propio índice
-- para que una baja de perfil no escanee toda la cola durable de eliminaciones.
create index contrato_eliminaciones_solicitado_por_idx
  on private.contrato_eliminaciones (solicitado_por);

comment on table private.contrato_eliminaciones is
  'Mutex durable de borrado: la Edge elimina los objetos listados y solo después confirma el hard-delete contractual.';

alter table private.contrato_eliminaciones enable row level security;
alter table private.contrato_eliminaciones force row level security;
revoke all on table private.contrato_eliminaciones
  from public, anon, authenticated, service_role;

create or replace function private.contrato_en_eliminacion(p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from private.contrato_eliminaciones e
    where e.contrato_id = p_contrato_id
  );
$function$;

create or replace function private.mutacion_documental_autorizada(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    current_setting('crm.contrato_pdf_revision_autorizada', true)
      = p_contrato_id::text,
    false
  ) or coalesce(
    current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
      = p_contrato_id::text,
    false
  );
$function$;

revoke all on function private.contrato_en_eliminacion(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.mutacion_documental_autorizada(uuid)
  from public, anon, authenticated, service_role;

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
  v_job_id uuid;
  v_pdf private.contrato_pdfs%rowtype;
begin
  select j.id into v_job_id
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;

  if v_job_id is not null then
    select * into v_pdf
    from private.contrato_pdfs p
    where p.job_id = v_job_id;
  else
    -- Compatibilidad con el ledger v1, que no tiene job.
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
    order by p.revision desc
    limit 1;
  end if;

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
  v_archivo jsonb;
  v_reintentable boolean;
  v_ledger_coherente boolean := false;
  v_integridad boolean := false;
begin
  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;

  v_archivo := private.contrato_pdf_archivo_base(p_contrato_id);

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
      where p.job_id = v_job.id
        and p.contrato_id = v_job.contrato_id
        and p.revision = v_job.revision
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
  v_revision integer;
begin
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
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
  v_revision := 1;
  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

create or replace function private.crear_revision_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job_id uuid := gen_random_uuid();
  v_revision integer;
  v_snapshot jsonb;
  v_nombre text;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  select greatest(
    coalesce((select max(j.revision) from private.contrato_pdf_jobs j
              where j.contrato_id = p_contrato_id), 0),
    coalesce((select max(p.revision) from private.contrato_pdfs p
              where p.contrato_id = p_contrato_id), 0)
  ) + 1 into v_revision;

  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

revoke all on function private.crear_job_contrato_pdf_base(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.crear_revision_contrato_pdf_base(uuid,uuid)
  from public, anon, authenticated, service_role;

-- -------------------------------------------------------------------------
-- 2. Únicas vías de corrección que pueden abrir la congelación documental
-- -------------------------------------------------------------------------

create or replace function crm.actualizar_contrato_con_cuenta_pdf_v3(
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
  v_actor_id uuid := (select auth.uid());
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;
  if private.contrato_en_eliminacion(p_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  perform set_config(
    'crm.contrato_pdf_revision_autorizada', p_id::text, true
  );
  begin
    -- Esta RPC conserva la autorización autoritativa vigente: para el vendedor,
    -- autor + cartera + menos de 5 horas; para roles administrativos, sus gates.
    perform crm.actualizar_contrato_con_cuenta(
      p_id, p_contrato, p_cronograma
    );
  exception when others then
    perform set_config('crm.contrato_pdf_revision_autorizada', '', true);
    raise;
  end;
  perform set_config('crm.contrato_pdf_revision_autorizada', '', true);

  v_pdf := private.crear_revision_contrato_pdf_base(p_id, v_actor_id);
  return jsonb_build_object('id', p_id, 'ok', true, 'pdf', v_pdf);
end;
$function$;

create or replace function crm.actualizar_numero_contrato_pdf_v3(
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
declare
  v_actor_id uuid := (select auth.uid());
  v_resultado jsonb;
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;
  if private.contrato_en_eliminacion(p_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  perform set_config(
    'crm.contrato_pdf_revision_autorizada', p_id::text, true
  );
  begin
    v_resultado := public.actualizar_numero_contrato(
      p_id, p_numero, p_notas, p_categoria
    );
  exception when others then
    perform set_config('crm.contrato_pdf_revision_autorizada', '', true);
    raise;
  end;
  perform set_config('crm.contrato_pdf_revision_autorizada', '', true);

  v_pdf := private.crear_revision_contrato_pdf_base(p_id, v_actor_id);
  return coalesce(v_resultado, '{}'::jsonb)
    || jsonb_build_object('id', p_id, 'ok', true, 'pdf', v_pdf);
end;
$function$;

revoke all on function crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)
  to authenticated;
grant execute on function crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)
  to authenticated;

-- -------------------------------------------------------------------------
-- 3. Los triggers siguen congelando todo salvo esas RPC y el borrado final
-- -------------------------------------------------------------------------

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
  if private.contrato_en_eliminacion(v_contrato_id)
     and not private.mutacion_documental_autorizada(v_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  if tg_op = 'UPDATE' then
    v_cambio_documental := row(
      new.id, new.cliente_id, new.numero_contrato, new.capital, new.moneda,
      new.tasa_anual, new.modalidad, new.tipo_interes, new.fecha_inicio,
      new.fecha_vencimiento, new.categoria, new.producto_condicion_id,
      new.creado_por
    ) is distinct from row(
      old.id, old.cliente_id, old.numero_contrato, old.capital, old.moneda,
      old.tasa_anual, old.modalidad, old.tipo_interes, old.fecha_inicio,
      old.fecha_vencimiento, old.categoria, old.producto_condicion_id,
      old.creado_por
    );
  end if;

  if v_cambio_documental
     and private.contrato_documental_congelado(v_contrato_id)
     and not private.mutacion_documental_autorizada(v_contrato_id) then
    raise exception 'Los términos del contrato están congelados por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

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
  -- En un CASCADE el padre ya no es visible cuando corre el trigger del hijo;
  -- el token solo lo instala el finalizador server-side que bloqueó ese padre.
  if tg_op = 'DELETE'
     and current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
           = old.contrato_id::text then
    return old;
  end if;

  -- También serializa cambios de pago (estado/monto/fecha real), aunque no
  -- cambien el texto legal: un Admin autorizado sin pagos no puede perder esa
  -- condición después de que la Edge ya retiró los archivos.
  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if (
    v_anterior is not null
    and private.contrato_en_eliminacion(v_anterior)
    and not private.mutacion_documental_autorizada(v_anterior)
  ) or (
    v_nuevo is not null
    and private.contrato_en_eliminacion(v_nuevo)
    and not private.mutacion_documental_autorizada(v_nuevo)
  ) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  if tg_op = 'UPDATE' then
    v_cambio_documental := row(
      new.id, new.contrato_id, new.numero_cuota, new.fecha_programada,
      new.monto_programado, new.tipo
    ) is distinct from row(
      old.id, old.contrato_id, old.numero_cuota, old.fecha_programada,
      old.monto_programado, old.tipo
    );
  end if;
  if not v_cambio_documental then return new; end if;

  if (
    v_anterior is not null
    and private.contrato_documental_congelado(v_anterior)
    and not private.mutacion_documental_autorizada(v_anterior)
  ) or (
    v_nuevo is not null
    and private.contrato_documental_congelado(v_nuevo)
    and not private.mutacion_documental_autorizada(v_nuevo)
  ) then
    raise exception 'El cronograma contractual está congelado por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

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
  if tg_op = 'DELETE'
     and current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
           = old.contrato_id::text then
    return old;
  end if;
  if tg_op = 'UPDATE' and new is not distinct from old then return new; end if;

  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if (
    v_anterior is not null
    and (
      private.contrato_en_eliminacion(v_anterior)
      or private.contrato_documental_congelado(v_anterior)
    )
    and not private.mutacion_documental_autorizada(v_anterior)
  ) or (
    v_nuevo is not null
    and (
      private.contrato_en_eliminacion(v_nuevo)
      or private.contrato_documental_congelado(v_nuevo)
    )
    and not private.mutacion_documental_autorizada(v_nuevo)
  ) then
    raise exception 'Los titulares están congelados por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

create or replace function private.proteger_documento_contrato_eliminacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_anterior uuid := case when tg_op in ('UPDATE', 'DELETE') then old.contrato_id end;
  v_nuevo uuid := case when tg_op in ('INSERT', 'UPDATE') then new.contrato_id end;
begin
  -- En el CASCADE final el padre ya no es visible; solo la RPC finalizadora
  -- instala este token de transacción después de validar actor y manifiesto.
  if tg_op = 'DELETE'
     and current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
           = old.contrato_id::text then
    return old;
  end if;
  -- El manifiesto que recibió la Edge debe permanecer exacto hasta el commit
  -- final. El lock del padre ordena esta carrera igual que cronograma/titulares.
  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if (
    v_anterior is not null
    and private.contrato_en_eliminacion(v_anterior)
  ) or (
    v_nuevo is not null
    and private.contrato_en_eliminacion(v_nuevo)
  ) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function private.proteger_documento_contrato_eliminacion()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_documentos_00_contrato_eliminacion
  on public.documentos;
create trigger trg_documentos_00_contrato_eliminacion
before insert or update or delete on public.documentos
for each row execute function private.proteger_documento_contrato_eliminacion();

create or replace function private.bloquear_mutacion_contrato_pdf()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE'
     and current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
           = old.contrato_id::text then
    return old;
  end if;
  raise exception 'El archivo legal del contrato es inmutable'
    using errcode = '55000';
end;
$function$;

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
    if current_setting('crm.contrato_pdf_eliminacion_autorizada', true)
         = old.contrato_id::text then
      return old;
    end if;
    raise exception 'El job documental no se puede eliminar'
      using errcode = '55000';
  end if;

  if private.contrato_en_eliminacion(old.contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  if row(
    new.id, new.contrato_id, new.revision, new.storage_bucket,
    new.storage_path, new.nombre_archivo, new.template_version, new.snapshot,
    new.solicitado_por, new.creado_en
  ) is distinct from row(
    old.id, old.contrato_id, old.revision, old.storage_bucket,
    old.storage_path, old.nombre_archivo, old.template_version, old.snapshot,
    old.solicitado_por, old.creado_en
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

revoke all on function private.bloquear_mutacion_contrato_pdf()
  from public, anon, authenticated, service_role;
revoke all on function private.proteger_job_contrato_pdf()
  from public, anon, authenticated, service_role;

-- -------------------------------------------------------------------------
-- 4. Worker revision-aware
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
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;
  if not found then
    raise exception 'El contrato no tiene una reserva PDF v2'
      using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_job.contrato_id);
  if private.contrato_en_eliminacion(v_job.contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id, p_actor_id
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
begin
  select j.contrato_id into v_contrato_id
  from private.contrato_pdf_jobs j
  where j.id = p_job_id;
  if not found then
    raise exception 'Job PDF no encontrado' using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  if private.contrato_en_eliminacion(v_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = p_job_id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id, p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  select * into v_pdf
  from private.contrato_pdfs p
  where p.job_id = p_job_id;
  if found then
    v_coherente := v_pdf.contrato_id = v_job.contrato_id
      and v_pdf.revision = v_job.revision
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

  if v_job.estado = 'integridad_bloqueada' then
    return private.contrato_pdf_estado_base(v_contrato_id);
  end if;
  if v_job.estado <> 'subido_verificado'
     or v_job.lease_token is distinct from p_lease_token
     or v_job.lease_expira_en <= statement_timestamp() then
    raise exception 'El job PDF no está listo o su lease venció'
      using errcode = '40001';
  end if;

  insert into private.contrato_pdfs (
    contrato_id, job_id, revision, storage_bucket, storage_path,
    nombre_archivo, sha256, bytes, template_version, snapshot,
    generado_por, generado_en
  ) values (
    v_job.contrato_id, v_job.id, v_job.revision, v_job.storage_bucket,
    v_job.storage_path, v_job.nombre_archivo, v_job.sha256, v_job.bytes,
    v_job.template_version, v_job.snapshot, v_job.solicitado_por,
    statement_timestamp()
  )
  on conflict do nothing;

  select * into strict v_pdf
  from private.contrato_pdfs p
  where p.job_id = p_job_id;
  v_coherente := v_pdf.contrato_id = v_job.contrato_id
    and v_pdf.revision = v_job.revision
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

revoke all on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  to service_role;
grant execute on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  to service_role;

-- -------------------------------------------------------------------------
-- 5. Eliminación: autorización, manifiesto Storage y confirmación final
-- -------------------------------------------------------------------------

create or replace function private.poder_eliminar_contrato_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_admin boolean;
  v_superadmin boolean;
  v_tiene_pagos boolean;
begin
  if p_actor_id is null then
    return jsonb_build_object('admin', false, 'superadmin', false);
  end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_admin := coalesce((select public.es_admin()), false);
  v_superadmin := coalesce((select public.es_superadmin()), false);
  select exists (
    select 1
    from public.cronograma_pagos cp
    where cp.contrato_id = p_contrato_id
      and (cp.estado = 'pagado' or cp.monto_pagado is not null)
  ) into v_tiene_pagos;
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  return jsonb_build_object(
    'admin', v_admin,
    'superadmin', v_superadmin,
    'tiene_pagos', v_tiene_pagos
  );
exception when others then
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  raise;
end;
$function$;

revoke all on function private.poder_eliminar_contrato_como(uuid,uuid)
  from public, anon, authenticated, service_role;

create or replace function crm.contrato_eliminacion_preparar(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_poder jsonb;
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos jsonb;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  v_poder := private.poder_eliminar_contrato_como(
    p_contrato_id, p_actor_id
  );
  if not coalesce((v_poder->>'admin')::boolean, false) then
    raise insufficient_privilege using
      message = 'Solo Admin o Superadmin puede eliminar contratos';
  end if;
  if coalesce((v_poder->>'tiene_pagos')::boolean, false)
     and not coalesce((v_poder->>'superadmin')::boolean, false) then
    raise insufficient_privilege using
      message = 'Este contrato tiene pagos; solo Superadmin puede eliminarlo';
  end if;

  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
  for update;
  if found then
    return jsonb_build_object(
      'contrato_id', v_eliminacion.contrato_id,
      'token', v_eliminacion.token,
      'objetos', v_eliminacion.objetos
    );
  end if;

  if exists (
    select 1
    from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
      and j.estado in ('procesando', 'subido_verificado')
      and j.lease_expira_en > statement_timestamp()
  ) then
    raise exception
      'El PDF se está generando; reintenta la eliminación en unos minutos'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.documentos d
    where d.contrato_id = p_contrato_id
      and (
        d.storage_path is null
        or d.storage_path <> btrim(d.storage_path)
        or length(d.storage_path) not between 5 and 1024
        or left(d.storage_path, length(p_contrato_id::text) + 1)
             <> p_contrato_id::text || '/'
        or strpos(d.storage_path, '..') > 0
        or strpos(d.storage_path, '//') > 0
        or strpos(d.storage_path, E'\\') > 0
        or d.storage_path ~ '[[:cntrl:]]'
      )
  ) then
    raise exception 'Un documento del contrato tiene una ruta Storage inválida'
      using errcode = '23514';
  end if;

  select coalesce(jsonb_agg(objeto order by objeto->>'bucket', objeto->>'path'), '[]'::jsonb)
  into v_objetos
  from (
    select distinct jsonb_build_object(
      'bucket', 'contratos-generados', 'path', x.storage_path
    ) as objeto
    from (
      select j.storage_path
      from private.contrato_pdf_jobs j
      where j.contrato_id = p_contrato_id
      union
      select p.storage_path
      from private.contrato_pdfs p
      where p.contrato_id = p_contrato_id
    ) x
    where x.storage_path is not null

    union

    select distinct jsonb_build_object(
      'bucket', 'documentos', 'path', d.storage_path
    ) as objeto
    from public.documentos d
    where d.contrato_id = p_contrato_id
      and d.storage_path is not null
      and btrim(d.storage_path) <> ''
  ) objetos;

  if jsonb_array_length(v_objetos) > 1000 then
    raise exception 'El contrato supera el límite seguro de archivos para borrar'
      using errcode = '54000';
  end if;

  insert into private.contrato_eliminaciones (
    contrato_id, solicitado_por, objetos
  ) values (
    p_contrato_id, p_actor_id, v_objetos
  ) returning * into v_eliminacion;

  return jsonb_build_object(
    'contrato_id', v_eliminacion.contrato_id,
    'token', v_eliminacion.token,
    'objetos', v_eliminacion.objetos
  );
end;
$function$;

create or replace function crm.contrato_eliminacion_finalizar(
  p_contrato_id uuid,
  p_token uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos integer;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
    and e.token = p_token
    and e.solicitado_por = p_actor_id
  for update;
  if not found then
    raise exception 'La preparación de eliminación no existe o venció'
      using errcode = 'P0002';
  end if;
  v_objetos := jsonb_array_length(v_eliminacion.objetos);

  perform set_config(
    'crm.contrato_pdf_eliminacion_autorizada', p_contrato_id::text, true
  );
  begin
    delete from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id;
    delete from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id;
    delete from private.contrato_eliminaciones e
    where e.contrato_id = p_contrato_id;
    delete from public.contratos c
    where c.id = p_contrato_id;
    if not found then
      raise exception 'Contrato no encontrado' using errcode = 'P0002';
    end if;
  exception when others then
    perform set_config(
      'crm.contrato_pdf_eliminacion_autorizada', '', true
    );
    raise;
  end;
  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);

  return jsonb_build_object(
    'ok', true,
    'contrato_id', p_contrato_id,
    'objetos_eliminados', v_objetos
  );
end;
$function$;

revoke all on function crm.contrato_eliminacion_preparar(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_eliminacion_preparar(uuid,uuid)
  to service_role;
grant execute on function crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)
  to service_role;

-- Cierra definitivamente el hard-delete directo que dejaba objetos huérfanos.
-- La función SECURITY DEFINER anterior es la única vía y vuelve a validar rol.
alter table public.contratos enable row level security;

do $cerrar_delete_directo$
declare
  v_policy record;
begin
  for v_policy in
    select p.policyname
    from pg_catalog.pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'contratos'
      and p.cmd = 'DELETE'
  loop
    execute format(
      'drop policy %I on public.contratos', v_policy.policyname
    );
  end loop;
end;
$cerrar_delete_directo$;

drop policy if exists contratos_delete_solo_servidor on public.contratos;
create policy contratos_delete_solo_servidor
  on public.contratos
  as restrictive
  for delete
  to authenticated
  using (false);

comment on function crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb) is
  'Corrige con la autorización vigente (incluida ventana vendedor de 5 h) y reserva atómicamente una revisión PDF nueva.';
comment on function crm.contrato_eliminacion_preparar(uuid,uuid) is
  'Solo worker service_role: revalida Admin/Superadmin, toma mutex y entrega el manifiesto exacto de Storage.';
comment on function crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) is
  'Solo worker service_role: tras borrar Storage, exige token y actor de la autorización original y elimina ledger, jobs y contrato en una transacción.';

commit;
