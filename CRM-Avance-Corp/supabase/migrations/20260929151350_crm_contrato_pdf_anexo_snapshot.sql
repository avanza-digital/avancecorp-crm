-- Anexo de cronograma IMPRIMIBLE (decisión de Miguel, 28/09/2026: «todo sigue
-- igual, solo que el añadido es que el analista ahora puede imprimir este
-- anexo»). El contrato PDF no cambia: sigue en contrato-aep-17-v9 y ningún
-- sellado se toca. Esta migración añade UNA lectura para la Edge
-- crm-contrato-pdf-v2 (acción «anexo») y la bitácora de cada impresión.
--
--   · crm.contrato_pdf_anexo_snapshot(p_contrato_id, p_actor_id, p_template)
--     Solo service_role (la llama la Edge con la clave de servicio y el actor
--     de la sesión, como contrato_pdf_reclamar). Misma regla de lectura que el
--     PDF (private.puede_leer_contrato_pdf_como: cartera del cliente o, con D2,
--     quien cerró la venta y su cadena); rechaza contratos en eliminación.
--     Devuelve el snapshot SELLADO vigente —el archivo visible según
--     private.contrato_pdf_estado_base: trabajo más reciente, sellado y
--     coherente con el ledger— con contrato_id, revision, template_version,
--     generado_en y sha256. Distingue con el hint:
--       ANEXO_SIN_PDF_SELLADO  no hay PDF sellado vigente (o hay una revisión
--                              nueva todavía pendiente);
--       ANEXO_SIN_SNAPSHOT     el sellado no lleva snapshot v2 (ledger v1).
--     No escribe en public.contratos ni redefine ninguna función viva.
--
--   · private.contrato_pdf_anexo_impresiones
--     Bitácora de solo añadir: quién, cuándo, contrato, revisión y plantillas.
--     SIN el snapshot (lleva datos bancarios) y fuera de public.audit_log: su
--     CHECK de `operacion` es del portal y public.bandeja_actividad enseñaría
--     el asiento a los clientes. Sin FK a contrato_pdfs/contratos a propósito:
--     la eliminación auditada borra esas filas y la bitácora debe sobrevivir.
--
-- Por qué no se guarda el anexo: se dibuja a demanda desde el snapshot sellado
-- (inmutable) con una versión de plantilla fija ⇒ misma versión desplegada,
-- mismos bytes. Plan v3.1 en el vault («Anexo de cronograma en el contrato PDF -
-- plan v10 (2026-09-28)»), refutado por Codex
-- (docs/encargos/2026-09-28-codex-anexo-imprimible-plan*.md).
--
-- Gate: postflight de abajo + oráculo supabase/scripts/test-contrato-pdf-v2.sql
--   (bloque «Anexo de cronograma imprimible») en el arnés local del PDF.
-- Registro: supabase/scripts/anexo-cronograma/registrar-20260929151350.sql,
--   DESPUÉS de aplicar con `db query --linked --file`.
-- Reversa: supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql (borra
--   la función; CONSERVA la bitácora). Si la Edge ya expone «anexo», revertir
--   primero front y Edge, después la base.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null then
    raise exception 'PREFLIGHT anexo: crm.contrato_pdf_anexo_snapshot ya existe';
  end if;
  if to_regclass('private.contrato_pdf_anexo_impresiones') is not null then
    raise exception 'PREFLIGHT anexo: private.contrato_pdf_anexo_impresiones ya existe';
  end if;
  if to_regprocedure('private.puede_leer_contrato_pdf_como(uuid,uuid)') is null
     or to_regprocedure('private.contrato_pdf_estado_base(uuid)') is null
     or to_regprocedure('private.contrato_en_eliminacion(uuid)') is null
     or to_regclass('private.contrato_pdfs') is null
     or to_regclass('public.perfiles') is null then
    raise exception 'PREFLIGHT anexo: faltan las piezas del PDF v2 de las que depende';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Bitácora de impresiones (solo añadir)
-- ---------------------------------------------------------------------------
create table private.contrato_pdf_anexo_impresiones (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null,
  pdf_id uuid not null,
  revision integer not null,
  template_version_contrato text not null,
  template_anexo text not null,
  actor_id uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default statement_timestamp(),
  constraint contrato_pdf_anexo_impresiones_revision_valida
    check (revision > 0),
  constraint contrato_pdf_anexo_impresiones_template_valida
    check (template_anexo ~ '^anexo-cronograma-v[0-9]{1,3}$')
);
alter table private.contrato_pdf_anexo_impresiones enable row level security;
alter table private.contrato_pdf_anexo_impresiones force row level security;
revoke all on table private.contrato_pdf_anexo_impresiones
  from public, anon, authenticated, service_role;
create index contrato_pdf_anexo_impresiones_contrato_idx
  on private.contrato_pdf_anexo_impresiones (contrato_id, creado_en desc);

create function private.bloquear_mutacion_anexo_impresion()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'La bitácora de impresiones del anexo es de solo añadir'
    using errcode = 'P0409';
end;
$function$;
revoke all on function private.bloquear_mutacion_anexo_impresion()
  from public, anon, authenticated, service_role;

create trigger contrato_pdf_anexo_impresiones_solo_insert
before update or delete on private.contrato_pdf_anexo_impresiones
for each row execute function private.bloquear_mutacion_anexo_impresion();

comment on table private.contrato_pdf_anexo_impresiones is
  'Bitácora de solo añadir de cada impresión del anexo de cronograma: quién, cuándo, contrato, revisión sellada y plantillas. Sin snapshot (datos bancarios). Sin FK a contratos/contrato_pdfs para sobrevivir a la eliminación auditada.';
comment on column private.contrato_pdf_anexo_impresiones.contrato_id is 'Contrato del que se imprimió el anexo (sin FK: sobrevive a la eliminación auditada).';
comment on column private.contrato_pdf_anexo_impresiones.pdf_id is 'Fila de private.contrato_pdfs (sellado) de la que salió el snapshot.';
comment on column private.contrato_pdf_anexo_impresiones.revision is 'Revisión sellada del contrato usada para el anexo.';
comment on column private.contrato_pdf_anexo_impresiones.template_version_contrato is 'Versión de plantilla del contrato sellado (p. ej. contrato-aep-17-v9).';
comment on column private.contrato_pdf_anexo_impresiones.template_anexo is 'Versión de plantilla del anexo que la Edge declaró (anexo-cronograma-vN).';
comment on column private.contrato_pdf_anexo_impresiones.actor_id is 'Quién pidió la impresión (perfil de la sesión). NULL si el perfil se borró.';
comment on column private.contrato_pdf_anexo_impresiones.creado_en is 'Instante de la solicitud del anexo.';
comment on function private.bloquear_mutacion_anexo_impresion() is
  'Rechaza UPDATE/DELETE sobre la bitácora de impresiones del anexo (P0409): solo se añade.';

-- ---------------------------------------------------------------------------
-- 2. La lectura para la Edge
-- ---------------------------------------------------------------------------
create function crm.contrato_pdf_anexo_snapshot(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_template text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_estado jsonb;
  v_pdf private.contrato_pdfs%rowtype;
begin
  -- Autorización PRIMERO: la misma frase para «no existe» y «no es tuyo», como
  -- el resto de puertas del PDF, para no revelar existencia.
  if p_actor_id is null
     or not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  if p_template is null or p_template !~ '^anexo-cronograma-v[0-9]{1,3}$' then
    raise exception 'Plantilla del anexo inválida'
      using errcode = '22023';
  end if;
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  -- El archivo visible es el que dice estado_base: trabajo más reciente,
  -- sellado y coherente con el ledger. Una revisión nueva todavía pendiente, un
  -- trabajo en integridad_bloqueada o un contrato sin reserva NO tienen anexo.
  v_estado := private.contrato_pdf_estado_base(p_contrato_id);
  if (v_estado->>'estado') is distinct from 'sellado' then
    raise exception 'El contrato no tiene un PDF sellado del que emitir el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_PDF_SELLADO';
  end if;

  if (v_estado->>'job_id') is not null then
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
      and p.job_id = (v_estado->>'job_id')::uuid
    order by p.revision desc
    limit 1;
  else
    -- Ledger v1 (sin trabajo server-side): se resuelve por contrato.
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
    order by p.revision desc
    limit 1;
  end if;
  if not found then
    raise exception 'El contrato no tiene un PDF sellado del que emitir el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_PDF_SELLADO';
  end if;
  if v_pdf.snapshot->'snapshotVersion' is distinct from '2'::jsonb then
    raise exception 'El contrato no tiene datos congelados aptos para el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_SNAPSHOT';
  end if;

  insert into private.contrato_pdf_anexo_impresiones (
    contrato_id, pdf_id, revision, template_version_contrato, template_anexo, actor_id
  ) values (
    p_contrato_id, v_pdf.id, v_pdf.revision, v_pdf.template_version, p_template, p_actor_id
  );

  return jsonb_build_object(
    'contrato_id', p_contrato_id,
    'revision', v_pdf.revision,
    'template_version', v_pdf.template_version,
    'generado_en', v_pdf.generado_en,
    'sha256', v_pdf.sha256,
    'snapshot', v_pdf.snapshot
  );
end;
$function$;

revoke all on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)
  to service_role;
comment on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text) is
  'Entrega a la Edge (service_role) el snapshot SELLADO vigente de un contrato para dibujar el anexo de cronograma, con la misma regla de lectura que el PDF, y deja un asiento en la bitácora de impresiones. Hints: ANEXO_SIN_PDF_SELLADO, ANEXO_SIN_SNAPSHOT.';

-- ---------------------------------------------------------------------------
-- 3. Postflight: lo instalado es exactamente lo previsto
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_owner text;
  v_secdef boolean;
  v_config text[];
  v_acl text;
  v_rls boolean;
  v_force boolean;
begin
  select r.rolname, p.prosecdef, p.proconfig, p.proacl::text
    into v_owner, v_secdef, v_config, v_acl
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure;
  if v_owner is distinct from 'postgres' or not v_secdef
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT anexo: owner/secdef/search_path inesperados (%/%/%)', v_owner, v_secdef, v_config;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'POSTFLIGHT anexo: la ACL de la lectura debe ser solo service_role, es %', v_acl;
  end if;
  if pg_catalog.has_function_privilege('authenticated', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE') then
    raise exception 'POSTFLIGHT anexo: la lectura debe ser ejecutable SOLO por service_role';
  end if;

  select c.relrowsecurity, c.relforcerowsecurity into v_rls, v_force
  from pg_catalog.pg_class c
  where c.oid = 'private.contrato_pdf_anexo_impresiones'::regclass;
  if not v_rls or not v_force then
    raise exception 'POSTFLIGHT anexo: la bitácora debe tener RLS activa y forzada';
  end if;
  if pg_catalog.has_table_privilege('anon', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_impresiones', 'INSERT') then
    raise exception 'POSTFLIGHT anexo: la bitácora no puede ser legible ni escribible por los roles de la API';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'private.contrato_pdf_anexo_impresiones'::regclass
      and t.tgname = 'contrato_pdf_anexo_impresiones_solo_insert'
      and not t.tgisinternal and t.tgenabled = 'O'
  ) then
    raise exception 'POSTFLIGHT anexo: falta el candado de solo añadir de la bitácora';
  end if;
  if pg_catalog.obj_description('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure, 'pg_proc') is null
     or pg_catalog.obj_description('private.contrato_pdf_anexo_impresiones'::regclass, 'pg_class') is null then
    raise exception 'POSTFLIGHT anexo: faltan los COMMENT ON';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- Reversa (misma que supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql):
--   begin;
--   drop function if exists crm.contrato_pdf_anexo_snapshot(uuid,uuid,text);
--   notify pgrst, 'reload schema';
--   commit;
--   -- La bitácora private.contrato_pdf_anexo_impresiones se CONSERVA (evidencia).
