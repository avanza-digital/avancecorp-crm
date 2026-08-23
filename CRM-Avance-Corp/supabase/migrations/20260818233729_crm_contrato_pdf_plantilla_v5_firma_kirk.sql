-- Versiona la presentación del contrato para reproducir el bloque de firma de
-- Kirk y restaurar los numerales e incisos del modelo Word. Los PDFs v1-v4
-- sellados permanecen inmutables; solo las reservas v4 sin bytes ni lease
-- activo avanzan a v5.

alter table private.contrato_pdf_jobs
  drop constraint if exists contrato_pdf_jobs_template_valido;

alter table private.contrato_pdf_jobs
  alter column template_version set default 'contrato-aep-17-v5',
  add constraint contrato_pdf_jobs_template_valido check (
    template_version in (
      'contrato-aep-17-v2',
      'contrato-aep-17-v3',
      'contrato-aep-17-v4',
      'contrato-aep-17-v5'
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
        'contrato-aep-17-v5'
      )
      and job_id is not null
      and storage_path =
        contrato_id::text || '/v2/' || job_id::text || '/contrato.pdf'
    )
  );

alter table private.contrato_pdf_jobs
  disable trigger contrato_pdf_jobs_transiciones_validas;

update private.contrato_pdf_jobs
set template_version = 'contrato-aep-17-v5',
    actualizado_en = statement_timestamp()
where template_version = 'contrato-aep-17-v4'
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
    'contrato-aep-17-v5',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

revoke all on function private.crear_job_contrato_pdf_base(uuid,uuid)
  from public, anon, authenticated, service_role;
