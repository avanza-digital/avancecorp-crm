-- Banco del ensayo de la plantilla v9. Reproduce las FORMAS REALES leídas de
-- producción en solo lectura el 08/09/2026: columnas, constraints y trigger de
-- `private.contrato_pdf_jobs` y `private.contrato_pdfs`.
--
-- LÍMITE DECLARADO: los cuerpos de las dos funciones son suplentes con la MISMA
-- envoltura que las vivas (plpgsql, SECURITY DEFINER, search_path="", dueño
-- postgres, ACL {postgres=X/postgres}, una sola aparición del literal). Los
-- cuerpos reales no se copian aquí: la migración los toma en vivo. Producción
-- confirmó que ninguno contiene `$$` ni `$function$`, así que el redondeo por
-- `pg_get_functiondef` no puede romper el entrecomillado.

create schema if not exists private;

create table private.contrato_pdf_jobs (
  id uuid not null,
  contrato_id uuid not null,
  estado text not null default 'pendiente'::text,
  storage_bucket text not null default 'contratos-generados'::text,
  storage_path text not null,
  nombre_archivo text not null,
  template_version text not null default 'contrato-aep-17-v8'::text,
  snapshot jsonb not null,
  sha256 text,
  bytes bigint,
  solicitado_por uuid not null,
  intentos integer not null default 0,
  lease_token uuid,
  lease_expira_en timestamp with time zone,
  ultimo_error text,
  creado_en timestamp with time zone not null default statement_timestamp(),
  actualizado_en timestamp with time zone not null default statement_timestamp(),
  subido_en timestamp with time zone,
  sellado_en timestamp with time zone,
  revision integer not null default 1
);

alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_bucket_valido CHECK ((storage_bucket = 'contratos-generados'::text));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_bytes_pareados CHECK ((((sha256 IS NULL) AND (bytes IS NULL)) OR ((sha256 ~ '^[a-f0-9]{64}$'::text) AND (bytes > 0) AND (bytes <= 10485760))));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_estado_valido CHECK ((estado = ANY (ARRAY['pendiente'::text, 'procesando'::text, 'subido_verificado'::text, 'sellado'::text, 'error_reintentable'::text, 'integridad_bloqueada'::text])));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_intentos_valido CHECK ((intentos >= 0));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_lease_coherente CHECK ((((estado = ANY (ARRAY['procesando'::text, 'subido_verificado'::text])) AND (lease_token IS NOT NULL) AND (lease_expira_en IS NOT NULL)) OR ((estado <> ALL (ARRAY['procesando'::text, 'subido_verificado'::text])) AND (lease_token IS NULL) AND (lease_expira_en IS NULL))));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_nombre_valido CHECK (((nombre_archivo = btrim(nombre_archivo)) AND ((length(nombre_archivo) >= 5) AND (length(nombre_archivo) <= 255)) AND (nombre_archivo ~* '\.pdf$'::text)));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_pkey PRIMARY KEY (id);
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_revision_unica UNIQUE (contrato_id, revision);
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_revision_valida CHECK ((revision > 0));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_ruta_server_side CHECK ((storage_path = ((((contrato_id)::text || '/v2/'::text) || (id)::text) || '/contrato.pdf'::text)));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_sello_coherente CHECK ((((estado = 'sellado'::text) AND (sellado_en IS NOT NULL)) OR ((estado <> 'sellado'::text) AND (sellado_en IS NULL))));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_snapshot_objeto CHECK ((jsonb_typeof(snapshot) = 'object'::text));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_subida_coherente CHECK ((((estado = ANY (ARRAY['pendiente'::text, 'procesando'::text])) AND (sha256 IS NULL) AND (bytes IS NULL) AND (subido_en IS NULL)) OR ((estado = ANY (ARRAY['subido_verificado'::text, 'sellado'::text])) AND (sha256 IS NOT NULL) AND (bytes IS NOT NULL) AND (subido_en IS NOT NULL)) OR (estado = ANY (ARRAY['error_reintentable'::text, 'integridad_bloqueada'::text]))));
alter table private.contrato_pdf_jobs add constraint contrato_pdf_jobs_template_valido CHECK ((template_version = ANY (ARRAY['contrato-aep-17-v2'::text, 'contrato-aep-17-v3'::text, 'contrato-aep-17-v4'::text, 'contrato-aep-17-v5'::text, 'contrato-aep-17-v6'::text, 'contrato-aep-17-v7'::text, 'contrato-aep-17-v8'::text])));

create table private.contrato_pdfs (
  id uuid not null default gen_random_uuid(),
  contrato_id uuid not null,
  job_id uuid,
  storage_bucket text not null default 'contratos-generados'::text,
  storage_path text not null,
  nombre_archivo text not null,
  sha256 text not null,
  bytes bigint not null,
  template_version text not null,
  snapshot jsonb not null,
  generado_por uuid not null,
  generado_en timestamp with time zone not null default statement_timestamp(),
  revision integer not null default 1
);

alter table private.contrato_pdfs add constraint contrato_pdfs_bucket_valido CHECK ((storage_bucket = 'contratos-generados'::text));
alter table private.contrato_pdfs add constraint contrato_pdfs_hash_bytes_validos CHECK (((sha256 ~ '^[a-f0-9]{64}$'::text) AND (bytes > 0) AND (bytes <= 10485760)));
alter table private.contrato_pdfs add constraint contrato_pdfs_job_unico UNIQUE (job_id);
alter table private.contrato_pdfs add constraint contrato_pdfs_nombre_valido CHECK (((nombre_archivo = btrim(nombre_archivo)) AND ((length(nombre_archivo) >= 5) AND (length(nombre_archivo) <= 255)) AND (nombre_archivo ~* '\.pdf$'::text)));
alter table private.contrato_pdfs add constraint contrato_pdfs_pkey PRIMARY KEY (id);
alter table private.contrato_pdfs add constraint contrato_pdfs_revision_unica UNIQUE (contrato_id, revision);
alter table private.contrato_pdfs add constraint contrato_pdfs_revision_valida CHECK ((revision > 0));
alter table private.contrato_pdfs add constraint contrato_pdfs_ruta_unica UNIQUE (storage_bucket, storage_path);
alter table private.contrato_pdfs add constraint contrato_pdfs_version_ruta_valida CHECK ((((template_version = 'contrato-aep-17-v1'::text) AND (job_id IS NULL) AND (storage_path = ((contrato_id)::text || '/contrato.pdf'::text))) OR ((template_version = ANY (ARRAY['contrato-aep-17-v2'::text, 'contrato-aep-17-v3'::text, 'contrato-aep-17-v4'::text, 'contrato-aep-17-v5'::text, 'contrato-aep-17-v6'::text, 'contrato-aep-17-v7'::text, 'contrato-aep-17-v8'::text])) AND (job_id IS NOT NULL) AND (storage_path = ((((contrato_id)::text || '/v2/'::text) || (job_id)::text) || '/contrato.pdf'::text)))));

alter table private.contrato_pdf_jobs enable row level security;
alter table private.contrato_pdf_jobs force row level security;
alter table private.contrato_pdfs enable row level security;
alter table private.contrato_pdfs force row level security;

-- Suplente del trigger de inmutabilidad: bloquea DELETE y la reescritura de
-- identidad, snapshot y huella, que es lo que la migración pone en juego al
-- apagarlo.
create or replace function private.proteger_job_contrato_pdf()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'ledger PDF: no se borran jobs';
  end if;
  if new.id <> old.id or new.contrato_id <> old.contrato_id
     or new.snapshot <> old.snapshot
     or (old.sha256 is not null and new.sha256 is distinct from old.sha256) then
    raise exception 'ledger PDF: identidad o huella inmutables';
  end if;
  return new;
end;
$function$;

create trigger contrato_pdf_jobs_transiciones_validas
  before delete or update on private.contrato_pdf_jobs
  for each row execute function private.proteger_job_contrato_pdf();

-- Suplentes de las dos funciones que estampan la versión (envoltura real).
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
  v_job_id uuid := gen_random_uuid();
begin
  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id, p_contrato_id, 1, 'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    'Contrato-suplente.pdf',
    'contrato-aep-17-v8',
    '{}'::jsonb,
    p_actor_id
  );
  return jsonb_build_object('job_id', v_job_id);
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
begin
  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id, p_contrato_id, 2, 'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    'Contrato-suplente.pdf',
    'contrato-aep-17-v8',
    '{}'::jsonb,
    p_actor_id
  );
  return jsonb_build_object('job_id', v_job_id);
end;
$function$;

revoke all on function private.crear_job_contrato_pdf_base(uuid, uuid) from public;
revoke all on function private.crear_revision_contrato_pdf_base(uuid, uuid) from public;

-- ————————————————————————————————— casos —————————————————————————————————
-- 1. reserva v8 pendiente sin bytes           → debe pasar a v9
-- 2. reserva v8 error_reintentable sin bytes  → debe pasar a v9
-- 3. reserva v8 error_reintentable CON bytes  → debe quedarse en v8
-- 4. reserva v8 procesando con lease vivo     → el preflight debe abortar
-- 5. sellados v2/v5/v6/v8 en contrato_pdfs    → intactos byte a byte
insert into private.contrato_pdf_jobs (id, contrato_id, revision, estado, storage_path, nombre_archivo, template_version, snapshot, solicitado_por)
values
  ('11111111-1111-4111-8111-111111111111','aaaaaaa1-1111-4111-8111-111111111111',1,'pendiente','aaaaaaa1-1111-4111-8111-111111111111/v2/11111111-1111-4111-8111-111111111111/contrato.pdf','Contrato-caso-1.pdf','contrato-aep-17-v8','{"caso":1}'::jsonb,'99999999-9999-4999-8999-999999999999'),
  ('22222222-2222-4222-8222-222222222222','aaaaaaa2-2222-4222-8222-222222222222',1,'error_reintentable','aaaaaaa2-2222-4222-8222-222222222222/v2/22222222-2222-4222-8222-222222222222/contrato.pdf','Contrato-caso-2.pdf','contrato-aep-17-v8','{"caso":2}'::jsonb,'99999999-9999-4999-8999-999999999999');

insert into private.contrato_pdf_jobs (id, contrato_id, revision, estado, storage_path, nombre_archivo, template_version, snapshot, solicitado_por, sha256, bytes, subido_en)
values
  ('33333333-3333-4333-8333-333333333333','aaaaaaa3-3333-4333-8333-333333333333',1,'error_reintentable','aaaaaaa3-3333-4333-8333-333333333333/v2/33333333-3333-4333-8333-333333333333/contrato.pdf','Contrato-caso-3.pdf','contrato-aep-17-v8','{"caso":3}'::jsonb,'99999999-9999-4999-8999-999999999999', repeat('a',64), 12345, now());

insert into private.contrato_pdf_jobs (id, contrato_id, revision, estado, storage_path, nombre_archivo, template_version, snapshot, solicitado_por, sha256, bytes, subido_en, sellado_en)
values
  ('55555555-5555-4555-8555-555555555551','aaaaaaa5-5555-4555-8555-555555555551',1,'sellado','aaaaaaa5-5555-4555-8555-555555555551/v2/55555555-5555-4555-8555-555555555551/contrato.pdf','Contrato-sellado-v5.pdf','contrato-aep-17-v5','{"sellado":"v5"}'::jsonb,'99999999-9999-4999-8999-999999999999', repeat('b',64), 500, now(), now()),
  ('55555555-5555-4555-8555-555555555552','aaaaaaa5-5555-4555-8555-555555555552',1,'sellado','aaaaaaa5-5555-4555-8555-555555555552/v2/55555555-5555-4555-8555-555555555552/contrato.pdf','Contrato-sellado-v8.pdf','contrato-aep-17-v8','{"sellado":"v8"}'::jsonb,'99999999-9999-4999-8999-999999999999', repeat('c',64), 600, now(), now());

insert into private.contrato_pdfs (contrato_id, job_id, storage_path, nombre_archivo, sha256, bytes, template_version, snapshot, generado_por)
values
  ('aaaaaaa5-5555-4555-8555-555555555551','55555555-5555-4555-8555-555555555551','aaaaaaa5-5555-4555-8555-555555555551/v2/55555555-5555-4555-8555-555555555551/contrato.pdf','Contrato-sellado-v5.pdf',repeat('b',64),500,'contrato-aep-17-v5','{"sellado":"v5"}'::jsonb,'99999999-9999-4999-8999-999999999999'),
  ('aaaaaaa5-5555-4555-8555-555555555552','55555555-5555-4555-8555-555555555552','aaaaaaa5-5555-4555-8555-555555555552/v2/55555555-5555-4555-8555-555555555552/contrato.pdf','Contrato-sellado-v8.pdf',repeat('c',64),600,'contrato-aep-17-v8','{"sellado":"v8"}'::jsonb,'99999999-9999-4999-8999-999999999999');
