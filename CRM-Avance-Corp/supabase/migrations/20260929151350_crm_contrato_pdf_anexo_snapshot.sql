-- Anexo de cronograma IMPRIMIBLE (decisión de Miguel, 28/09/2026: «todo sigue
-- igual, solo que el añadido es que el analista ahora puede imprimir este
-- anexo»). El contrato PDF no cambia: sigue en contrato-aep-17-v9 y ningún
-- sellado se toca. Esta migración añade las piezas de servidor de la acción
-- «anexo» de la Edge crm-contrato-pdf-v2, en cuatro capas: puertas en `crm`
-- que autorizan y delegan, núcleo en `private` que toca las tablas.
--
--   · crm.contrato_pdf_anexo_snapshot(p_contrato_id, p_actor_id, p_template)
--     PUERTA, solo service_role (la llama la Edge con la clave de servicio y el
--     actor de la sesión, como contrato_pdf_reclamar). Misma regla de lectura
--     que el PDF (private.puede_leer_contrato_pdf_como: cartera del cliente o,
--     con D2, quien cerró la venta y su cadena); rechaza contratos en
--     eliminación; valida la plantilla y delega en el núcleo.
--   · private.contrato_pdf_anexo_snapshot_base(p_contrato_id)
--     NÚCLEO. Bloquea la fila del contrato (mismo mutex que reclamar) y, bajo ese
--     bloqueo, resuelve el archivo VIGENTE según private.contrato_pdf_estado_base
--     (trabajo más reciente, sellado y coherente con el ledger) y devuelve su
--     snapshot con contrato_id, pdf_id, revision, template_version, generado_en
--     y sha256. Hints: ANEXO_SIN_PDF_SELLADO (sin sellado vigente, revisión
--     nueva pendiente o integridad bloqueada) y ANEXO_SIN_SNAPSHOT (sellado sin
--     snapshot v2: ledger v1). No escribe.
--   · crm.contrato_pdf_anexo_emitido(p_contrato_id, p_actor_id, p_pdf_id,
--     p_template, p_sha256, p_bytes)
--     PUERTA, solo service_role. La Edge la llama DESPUÉS de dibujar el anexo,
--     con el hash y el tamaño de los bytes que va a entregar; vuelve a
--     autorizar y delega en el núcleo, que deja el asiento. Un render fallido
--     no deja asiento: la bitácora acredita anexos EMITIDOS, no solicitudes.
--   · private.contrato_pdf_anexo_emitido_base(...) NÚCLEO del asiento.
--   · private.contrato_pdf_anexo_emisiones
--     Bitácora de solo añadir (UPDATE, DELETE y TRUNCATE rechazados también al
--     dueño): quién, cuándo, contrato, revisión sellada, plantillas, sha256 y
--     bytes del anexo. SIN el snapshot (lleva datos bancarios) y fuera de
--     public.audit_log: su CHECK de `operacion` es del portal y
--     public.bandeja_actividad enseñaría el asiento a los clientes. Sin FK
--     (ni a contratos, ni a contrato_pdfs, ni a perfiles) a propósito: la
--     eliminación auditada borra esas filas y una FK a perfiles con SET NULL
--     chocaría con el candado de solo añadir; el asiento conserva los
--     identificadores tal cual y sobrevive a todo.
--
-- Por qué no se guarda el anexo: se dibuja a demanda desde el snapshot sellado
-- (inmutable) con una versión de plantilla fija ⇒ misma versión desplegada,
-- mismos bytes; el hash queda en la bitácora. Plan v3.1 en el vault («Anexo de
-- cronograma en el contrato PDF - plan v10 (2026-09-28)»); revisiones de Codex
-- (plan y código) y auditor-rls aplicadas.
--
-- Gate: postflight de abajo + oráculo supabase/scripts/test-contrato-pdf-v2.sql
--   (bloques «Anexo de cronograma imprimible») en el arnés local del PDF.
-- Registro: supabase/scripts/anexo-cronograma/registrar-20260929151350.sql,
--   DESPUÉS de aplicar con `db query --linked --file`.
-- Reversa: supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql (borra
--   las cuatro funciones; CONSERVA la bitácora, que esta migración tolera al
--   reaplicarse). Si la Edge ya expone «anexo», revertir primero front y Edge.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null
     or to_regprocedure('crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)') is not null
     or to_regprocedure('private.contrato_pdf_anexo_snapshot_base(uuid)') is not null
     or to_regprocedure('private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)') is not null then
    raise exception 'PREFLIGHT anexo: alguna de las funciones del anexo ya existe';
  end if;
  if to_regprocedure('private.puede_leer_contrato_pdf_como(uuid,uuid)') is null
     or to_regprocedure('private.contrato_pdf_estado_base(uuid)') is null
     or to_regprocedure('private.contrato_en_eliminacion(uuid)') is null
     or to_regprocedure('private.bloquear_fila_contrato_pdf(uuid)') is null
     or to_regclass('private.contrato_pdfs') is null then
    raise exception 'PREFLIGHT anexo: faltan las piezas del PDF v2 de las que depende';
  end if;
  -- La bitácora puede existir de una aplicación anterior revertida (la reversa
  -- la conserva): entonces debe tener exactamente la forma esperada.
  if to_regclass('private.contrato_pdf_anexo_emisiones') is not null then
    -- to_regclass, no el cast literal: el cast se resuelve al planificar y
    -- fallaría cuando la tabla todavía no existe.
    if (
      select count(*) from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass('private.contrato_pdf_anexo_emisiones')
        and a.attnum > 0 and not a.attisdropped
        and a.attname in ('id','contrato_id','pdf_id','revision','template_version_contrato',
                          'template_anexo','sha256','bytes','actor_id','creado_en')
    ) <> 10 then
      raise exception 'PREFLIGHT anexo: existe private.contrato_pdf_anexo_emisiones con otra forma';
    end if;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Bitácora de anexos emitidos (solo añadir)
-- ---------------------------------------------------------------------------
create table if not exists private.contrato_pdf_anexo_emisiones (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null,
  pdf_id uuid not null,
  revision integer not null,
  template_version_contrato text not null,
  template_anexo text not null,
  sha256 text not null,
  bytes bigint not null,
  actor_id uuid not null,
  creado_en timestamptz not null default statement_timestamp(),
  constraint contrato_pdf_anexo_emisiones_revision_valida
    check (revision > 0),
  constraint contrato_pdf_anexo_emisiones_template_valida
    check (template_anexo ~ '^anexo-cronograma-v[0-9]{1,3}$'),
  constraint contrato_pdf_anexo_emisiones_hash_bytes_validos
    check (sha256 ~ '^[a-f0-9]{64}$' and bytes between 1 and 10485760)
);
alter table private.contrato_pdf_anexo_emisiones enable row level security;
alter table private.contrato_pdf_anexo_emisiones force row level security;
revoke all on table private.contrato_pdf_anexo_emisiones
  from public, anon, authenticated, service_role;
create index if not exists contrato_pdf_anexo_emisiones_contrato_idx
  on private.contrato_pdf_anexo_emisiones (contrato_id, creado_en desc);

create or replace function private.bloquear_mutacion_anexo_emision()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'La bitácora de anexos emitidos es de solo añadir'
    using errcode = 'P0409';
end;
$function$;
revoke all on function private.bloquear_mutacion_anexo_emision()
  from public, anon, authenticated, service_role;

drop trigger if exists contrato_pdf_anexo_emisiones_solo_insert
  on private.contrato_pdf_anexo_emisiones;
create trigger contrato_pdf_anexo_emisiones_solo_insert
before update or delete on private.contrato_pdf_anexo_emisiones
for each row execute function private.bloquear_mutacion_anexo_emision();
drop trigger if exists contrato_pdf_anexo_emisiones_sin_vaciar
  on private.contrato_pdf_anexo_emisiones;
create trigger contrato_pdf_anexo_emisiones_sin_vaciar
before truncate on private.contrato_pdf_anexo_emisiones
for each statement execute function private.bloquear_mutacion_anexo_emision();

comment on table private.contrato_pdf_anexo_emisiones is
  'Bitácora de solo añadir (UPDATE/DELETE/TRUNCATE rechazados también al dueño) de cada anexo de cronograma EMITIDO por la Edge: quién, cuándo, contrato, revisión sellada, plantillas, sha256 y bytes del anexo. Un render fallido no deja asiento. Sin snapshot (datos bancarios) y sin FK (sobrevive a la eliminación auditada y al borrado de perfiles).';
comment on column private.contrato_pdf_anexo_emisiones.id is 'Identificador del asiento.';
comment on column private.contrato_pdf_anexo_emisiones.contrato_id is 'Contrato del que se emitió el anexo (sin FK: sobrevive a la eliminación auditada).';
comment on column private.contrato_pdf_anexo_emisiones.pdf_id is 'Fila de private.contrato_pdfs (sellado) de la que salió el snapshot (sin FK).';
comment on column private.contrato_pdf_anexo_emisiones.revision is 'Revisión sellada del contrato usada para el anexo.';
comment on column private.contrato_pdf_anexo_emisiones.template_version_contrato is 'Versión de plantilla del contrato sellado (p. ej. contrato-aep-17-v9).';
comment on column private.contrato_pdf_anexo_emisiones.template_anexo is 'Versión de plantilla del anexo que la Edge dibujó (anexo-cronograma-vN).';
comment on column private.contrato_pdf_anexo_emisiones.sha256 is 'SHA-256 de los bytes del anexo entregados al navegador.';
comment on column private.contrato_pdf_anexo_emisiones.bytes is 'Tamaño en bytes del anexo entregado.';
comment on column private.contrato_pdf_anexo_emisiones.actor_id is 'Quién pidió el anexo (perfil de la sesión). Se conserva tal cual, sin FK.';
comment on column private.contrato_pdf_anexo_emisiones.creado_en is 'Instante de la emisión.';
comment on function private.bloquear_mutacion_anexo_emision() is
  'Rechaza UPDATE/DELETE/TRUNCATE sobre la bitácora de anexos emitidos (P0409): solo se añade.';

-- ---------------------------------------------------------------------------
-- 2. Núcleo: el snapshot sellado vigente, bajo el bloqueo del contrato
-- ---------------------------------------------------------------------------
create function private.contrato_pdf_anexo_snapshot_base(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_estado jsonb;
  v_pdf private.contrato_pdfs%rowtype;
begin
  -- Mismo mutex que reclamar/crear_job: nadie cuela una revisión nueva entre
  -- leer el estado y leer el ledger (revisión de Codex, P1).
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  -- El archivo visible es el que dice estado_base: trabajo más reciente,
  -- sellado y coherente con el ledger. Una revisión nueva pendiente, un trabajo
  -- en integridad_bloqueada o un contrato sin reserva NO tienen anexo.
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

  return jsonb_build_object(
    'contrato_id', p_contrato_id,
    'pdf_id', v_pdf.id,
    'revision', v_pdf.revision,
    'template_version', v_pdf.template_version,
    'generado_en', v_pdf.generado_en,
    'sha256', v_pdf.sha256,
    'snapshot', v_pdf.snapshot
  );
end;
$function$;
revoke all on function private.contrato_pdf_anexo_snapshot_base(uuid)
  from public, anon, authenticated, service_role;
comment on function private.contrato_pdf_anexo_snapshot_base(uuid) is
  'Núcleo del anexo: bajo el bloqueo del contrato, devuelve el snapshot SELLADO vigente (estado_base) con pdf_id, revision, template_version, generado_en y sha256. Hints: ANEXO_SIN_PDF_SELLADO, ANEXO_SIN_SNAPSHOT. No escribe.';

-- ---------------------------------------------------------------------------
-- 3. Núcleo: el asiento de emisión
-- ---------------------------------------------------------------------------
create function private.contrato_pdf_anexo_emitido_base(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_pdf_id uuid,
  p_template text,
  p_sha256 text,
  p_bytes bigint
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_pdf private.contrato_pdfs%rowtype;
  v_id uuid;
begin
  -- El pdf_id tiene que ser un sellado de ESTE contrato con snapshot v2: la
  -- Edge no puede registrar una emisión sobre otra fila.
  select * into v_pdf
  from private.contrato_pdfs p
  where p.id = p_pdf_id and p.contrato_id = p_contrato_id;
  if not found or v_pdf.snapshot->'snapshotVersion' is distinct from '2'::jsonb then
    raise exception 'La emisión no corresponde a un PDF sellado de este contrato'
      using errcode = '23514';
  end if;
  insert into private.contrato_pdf_anexo_emisiones (
    contrato_id, pdf_id, revision, template_version_contrato,
    template_anexo, sha256, bytes, actor_id
  ) values (
    p_contrato_id, v_pdf.id, v_pdf.revision, v_pdf.template_version,
    p_template, p_sha256, p_bytes, p_actor_id
  )
  returning id into v_id;
  return jsonb_build_object(
    'emision_id', v_id,
    'contrato_id', p_contrato_id,
    'revision', v_pdf.revision
  );
end;
$function$;
revoke all on function private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)
  from public, anon, authenticated, service_role;
comment on function private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint) is
  'Núcleo del asiento de emisión del anexo: exige que pdf_id sea un sellado v2 del contrato y añade la fila a la bitácora.';

-- ---------------------------------------------------------------------------
-- 4. Puertas (solo service_role): autorizan, validan y delegan
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
  return private.contrato_pdf_anexo_snapshot_base(p_contrato_id);
end;
$function$;
revoke all on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)
  to service_role;
comment on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text) is
  'Puerta (service_role) del anexo de cronograma: misma regla de lectura que el PDF, rechaza eliminación y plantilla inválida, y delega en private.contrato_pdf_anexo_snapshot_base. Hints: ANEXO_SIN_PDF_SELLADO, ANEXO_SIN_SNAPSHOT.';

create function crm.contrato_pdf_anexo_emitido(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_pdf_id uuid,
  p_template text,
  p_sha256 text,
  p_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_actor_id is null
     or not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  if p_template is null or p_template !~ '^anexo-cronograma-v[0-9]{1,3}$' then
    raise exception 'Plantilla del anexo inválida'
      using errcode = '22023';
  end if;
  if p_pdf_id is null
     or p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$'
     or p_bytes is null or p_bytes not between 1 and 10485760 then
    raise exception 'Emisión del anexo inválida'
      using errcode = '22023';
  end if;
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  return private.contrato_pdf_anexo_emitido_base(
    p_contrato_id, p_actor_id, p_pdf_id, p_template, p_sha256, p_bytes
  );
end;
$function$;
revoke all on function crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)
  to service_role;
comment on function crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint) is
  'Puerta (service_role) que registra un anexo EMITIDO: la Edge la llama tras dibujarlo con el sha256 y los bytes que entrega; vuelve a autorizar y delega en private.contrato_pdf_anexo_emitido_base.';

-- ---------------------------------------------------------------------------
-- 5. Postflight: lo instalado es exactamente lo previsto
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_firma text;
  v_owner text;
  v_secdef boolean;
  v_config text[];
  v_acl text;
  v_rls boolean;
  v_force boolean;
begin
  foreach v_firma in array array[
    'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)',
    'crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint)'
  ] loop
    select r.rolname, p.prosecdef, p.proconfig, p.proacl::text
      into v_owner, v_secdef, v_config, v_acl
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = v_firma::regprocedure;
    if v_owner is distinct from 'postgres' or not v_secdef
       or v_config is distinct from array['search_path=""']::text[] then
      raise exception 'POSTFLIGHT anexo: % con owner/secdef/search_path inesperados', v_firma;
    end if;
    if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
      raise exception 'POSTFLIGHT anexo: la ACL de % debe ser solo service_role, es %', v_firma, v_acl;
    end if;
    if pg_catalog.has_function_privilege('authenticated', v_firma, 'EXECUTE')
       or pg_catalog.has_function_privilege('anon', v_firma, 'EXECUTE')
       or not pg_catalog.has_function_privilege('service_role', v_firma, 'EXECUTE') then
      raise exception 'POSTFLIGHT anexo: % debe ser ejecutable SOLO por service_role', v_firma;
    end if;
    if pg_catalog.obj_description(v_firma::regprocedure, 'pg_proc') is null then
      raise exception 'POSTFLIGHT anexo: falta el COMMENT ON de %', v_firma;
    end if;
  end loop;
  foreach v_firma in array array[
    'private.contrato_pdf_anexo_snapshot_base(uuid)',
    'private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)',
    'private.bloquear_mutacion_anexo_emision()'
  ] loop
    select r.rolname, p.prosecdef, p.proconfig, p.proacl::text
      into v_owner, v_secdef, v_config, v_acl
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = v_firma::regprocedure;
    if v_owner is distinct from 'postgres' or v_secdef
       or v_config is distinct from array['search_path=""']::text[]
       or v_acl is distinct from '{postgres=X/postgres}' then
      raise exception 'POSTFLIGHT anexo: el núcleo % debe ser invoker, de postgres y sin ejecutores de la API (%/%/%)', v_firma, v_secdef, v_config, v_acl;
    end if;
  end loop;

  select c.relrowsecurity, c.relforcerowsecurity into v_rls, v_force
  from pg_catalog.pg_class c
  where c.oid = 'private.contrato_pdf_anexo_emisiones'::regclass;
  if not v_rls or not v_force then
    raise exception 'POSTFLIGHT anexo: la bitácora debe tener RLS activa y forzada';
  end if;
  if pg_catalog.has_table_privilege('anon', 'private.contrato_pdf_anexo_emisiones', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'private.contrato_pdf_anexo_emisiones', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_emisiones', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_emisiones', 'INSERT') then
    raise exception 'POSTFLIGHT anexo: la bitácora no puede ser legible ni escribible por los roles de la API';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'private.contrato_pdf_anexo_emisiones'::regclass
        and t.tgname in ('contrato_pdf_anexo_emisiones_solo_insert', 'contrato_pdf_anexo_emisiones_sin_vaciar')
        and not t.tgisinternal and t.tgenabled = 'O') <> 2 then
    raise exception 'POSTFLIGHT anexo: faltan los candados de solo añadir de la bitácora';
  end if;
  if pg_catalog.obj_description('private.contrato_pdf_anexo_emisiones'::regclass, 'pg_class') is null
     or exists (
       select 1 from pg_catalog.pg_attribute a
       where a.attrelid = 'private.contrato_pdf_anexo_emisiones'::regclass
         and a.attnum > 0 and not a.attisdropped
         and pg_catalog.col_description(a.attrelid, a.attnum) is null
     ) then
    raise exception 'POSTFLIGHT anexo: faltan COMMENT ON de la bitácora';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- Reversa (misma que supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql):
--   begin;
--   drop function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text);
--   drop function crm.contrato_pdf_anexo_emitido(uuid,uuid,uuid,text,text,bigint);
--   drop function private.contrato_pdf_anexo_snapshot_base(uuid);
--   drop function private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint);
--   notify pgrst, 'reload schema';
--   commit;
--   -- La bitácora private.contrato_pdf_anexo_emisiones se CONSERVA (evidencia);
--   -- esta migración la tolera si se vuelve a aplicar.
