-- Corrige el plazo visible cuando el alta suma meses y ajusta el vencimiento
-- al último día de un mes más corto (por ejemplo, 31/08 + 6 meses = 28/02).
--
-- La v7 mantiene legibles e inmutables los PDFs históricos. Las reservas v5/v6
-- que aún no tienen bytes ni lease pasan a v7. Para los siete PDFs v5 ya
-- sellados que contienen el plazo incorrecto se crea una revisión 2 pendiente,
-- copiando exactamente el snapshot original; nunca se sobrescribe el PDF v5.
--
-- Esta migración es autosuficiente respecto de v6 porque esa frontera está viva
-- en producción aunque su migración 20260901115030 no figura en el registro
-- remoto. En un replay local, v6 se aplica antes y v7 la sustituye normalmente.

set local lock_timeout = '10s';
set local statement_timeout = '120s';

alter table private.contrato_pdf_jobs
  drop constraint if exists contrato_pdf_jobs_template_valido;

alter table private.contrato_pdf_jobs
  alter column template_version set default 'contrato-aep-17-v7',
  add constraint contrato_pdf_jobs_template_valido check (
    template_version in (
      'contrato-aep-17-v2',
      'contrato-aep-17-v3',
      'contrato-aep-17-v4',
      'contrato-aep-17-v5',
      'contrato-aep-17-v6',
      'contrato-aep-17-v7'
    )
  );

alter table private.contrato_pdfs
  drop constraint if exists contrato_pdfs_version_ruta_valida;

alter table private.contrato_pdfs
  add constraint contrato_pdfs_version_ruta_valida check (
    (
      template_version = 'contrato-aep-17-v1'
      and job_id is null
      and storage_path = contrato_id::text || '/contrato.pdf'
    )
    or (
      template_version in (
        'contrato-aep-17-v2',
        'contrato-aep-17-v3',
        'contrato-aep-17-v4',
        'contrato-aep-17-v5',
        'contrato-aep-17-v6',
        'contrato-aep-17-v7'
      )
      and job_id is not null
      and storage_path =
        contrato_id::text || '/v2/' || job_id::text || '/contrato.pdf'
    )
  );

-- Los únicos UPDATE permitidos son reservas que todavía no representan bytes.
-- El trigger de inmutabilidad se desactiva solo dentro de esta transacción.
alter table private.contrato_pdf_jobs
  disable trigger contrato_pdf_jobs_transiciones_validas;

update private.contrato_pdf_jobs
set template_version = 'contrato-aep-17-v7',
    actualizado_en = statement_timestamp()
where template_version in ('contrato-aep-17-v5', 'contrato-aep-17-v6')
  and estado in ('pendiente', 'error_reintentable')
  and lease_token is null
  and lease_expira_en is null
  and sha256 is null
  and bytes is null
  and subido_en is null;

alter table private.contrato_pdf_jobs
  enable trigger contrato_pdf_jobs_transiciones_validas;

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

  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
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
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    'contrato-aep-17-v7',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

revoke all on function private.crear_job_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;

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

  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
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
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    'contrato-aep-17-v7',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

revoke all on function private.crear_revision_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Reserva revisiones corregidas solo para los siete PDFs sellados identificados
-- por la auditoría. En un banco limpio, donde ninguno existe, el bloque no-op.
do $block$
declare
  v_esperado record;
  v_contrato_id uuid;
  v_anterior record;
  v_job_id uuid;
  v_presentes integer;
  v_insertados integer := 0;
begin
  select count(*)::integer
  into v_presentes
  from public.contratos c
  where c.numero_contrato = any (array[
    '2026-01-001324',
    '2026-01-001332',
    '2026-01-001337',
    '2026-01-001342',
    '2026-01-001343',
    '2026-01-001344',
    '2026-01-001348'
  ]::text[]);

  if v_presentes = 0 then
    return;
  end if;
  if v_presentes <> 7 then
    raise exception
      'PREFLIGHT v7: se esperaban 7 contratos afectados y existen %',
      v_presentes;
  end if;

  for v_esperado in
    select *
    from (values
      ('2026-01-001324'::text, '2026-08-31'::text, '2027-02-28'::text),
      ('2026-01-001332'::text, '2026-08-29'::text, '2027-02-28'::text),
      ('2026-01-001337'::text, '2026-08-29'::text, '2027-02-28'::text),
      ('2026-01-001342'::text, '2026-08-31'::text, '2027-02-28'::text),
      ('2026-01-001343'::text, '2026-08-31'::text, '2027-02-28'::text),
      ('2026-01-001344'::text, '2026-08-31'::text, '2027-02-28'::text),
      ('2026-01-001348'::text, '2026-08-31'::text, '2027-02-28'::text)
    ) as esperado(numero_contrato, fecha_inicio, fecha_vencimiento)
    order by numero_contrato
  loop
    select c.id
    into strict v_contrato_id
    from public.contratos c
    where c.numero_contrato = v_esperado.numero_contrato;

    perform private.bloquear_fila_contrato_pdf(v_contrato_id);

    select
      j.nombre_archivo,
      j.snapshot,
      j.solicitado_por
    into strict v_anterior
    from private.contrato_pdf_jobs j
    join private.contrato_pdfs p
      on p.contrato_id = j.contrato_id
     and p.revision = j.revision
     and p.job_id = j.id
    where j.contrato_id = v_contrato_id
      and j.revision = 1
      and j.estado = 'sellado'
      and j.template_version = 'contrato-aep-17-v5'
      and p.template_version = 'contrato-aep-17-v5'
      and p.sha256 = j.sha256
      and p.bytes = j.bytes
      and p.snapshot = j.snapshot
      and j.snapshot #>> '{contrato,fechaInicio}' = v_esperado.fecha_inicio
      and j.snapshot #>> '{contrato,fechaVencimiento}' =
        v_esperado.fecha_vencimiento
      and not exists (
        select 1
        from private.contrato_pdf_jobs posterior
        where posterior.contrato_id = v_contrato_id
          and posterior.revision > 1
      )
      and not exists (
        select 1
        from private.contrato_pdfs posterior
        where posterior.contrato_id = v_contrato_id
          and posterior.revision > 1
      );

    v_job_id := gen_random_uuid();
    insert into private.contrato_pdf_jobs (
      id,
      contrato_id,
      revision,
      estado,
      storage_path,
      nombre_archivo,
      template_version,
      snapshot,
      solicitado_por
    ) values (
      v_job_id,
      v_contrato_id,
      2,
      'pendiente',
      v_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
      v_anterior.nombre_archivo,
      'contrato-aep-17-v7',
      v_anterior.snapshot,
      v_anterior.solicitado_por
    );

    v_insertados := v_insertados + 1;
  end loop;

  if v_insertados <> 7 then
    raise exception
      'POSTCHECK v7: se esperaban 7 revisiones nuevas y se insertaron %',
      v_insertados;
  end if;
end;
$block$;
