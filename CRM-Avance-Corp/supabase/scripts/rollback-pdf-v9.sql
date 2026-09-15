-- Reversa de la plantilla v9 (co-titulares en comparecencia y firmas) → v8.
--
-- ⚠️ ORDEN OBLIGATORIO Y EDGE DE REVERSA (hallazgo P1 de Codex, 08/09/2026)
--
-- NO se vuelve al artefacto anterior de la edge. La edge v8 original NO sabe
-- LEER la v9: si ya se selló algún PDF v9, redesplegar aquel binario dejaría
-- esos contratos sin descarga («PDF_VERSION_NO_SOPORTADA»). La edge de reversa
-- es la del ÁRBOL ACTUAL con tres cambios:
--   1. CONTRATO_PDF_TEMPLATE_VERSION = 'contrato-aep-17-v8'
--   2. versionJobLegible() sigue admitiendo v9 (además de v2/v5/v6/v7/v8)
--   3. template-v2.ts de la v8, que es la del commit 6175616 («CRM: agranda la
--      letra del contrato PDF (plantilla v8)», 08/09/2026):
--        git show 6175616:CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/template-v2.ts
--      porque una reserva re-estampada a v8 debe rendir bytes v8: sin
--      co-titulares en la comparecencia ni en las firmas.
--
-- Secuencia: 1) desplegar esa edge de reversa · 2) ejecutar este archivo.
--
-- Lo que este archivo NO hace, a propósito:
--   · no toca ningún PDF sellado (ni v8 ni v9): los bytes firmados son
--     inmutables y se siguen sirviendo tal cual;
--   · no revierte reservas v9 que ya tengan bytes, lease o subida pendiente;
--   · no estrecha los CHECK: dejar la v9 admitida es aditivo e inofensivo, y
--     estrecharlos rompería cualquier fila v9 ya sellada (misma decisión que la
--     v6 documentó en su día).

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = pg_catalog, pg_temp;

select pg_catalog.pg_advisory_xact_lock(hashtext('crm.contrato_pdf.plantilla'));
lock table private.contrato_pdf_jobs in access exclusive mode;
lock table private.contrato_pdfs in access exclusive mode;

-- Mismo preflight que la ida: una reserva v9 en vuelo quedaría varada contra una
-- edge que ya estampa v8.
do $block$
declare
  v_en_vuelo integer;
  v_vencidas integer;
begin
  select count(*)::integer,
         count(*) filter (where j.lease_expira_en <= now())::integer
  into v_en_vuelo, v_vencidas
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v9'
    and j.estado in ('procesando', 'subido_verificado');

  if v_en_vuelo <> 0 then
    raise exception
      'REVERSA v9: % reservas v9 en vuelo (% con lease vencido); resolverlas antes de revertir',
      v_en_vuelo, v_vencidas;
  end if;
end;
$block$;

-- El default vuelve a v8. Revertir las funciones sin revertir el default dejaría
-- creando reservas v9 a cualquier inserción que dependa de él (P1 de Codex).
alter table private.contrato_pdf_jobs
  alter column template_version set default 'contrato-aep-17-v8';

alter table private.contrato_pdf_jobs
  disable trigger contrato_pdf_jobs_transiciones_validas;

update private.contrato_pdf_jobs
set template_version = 'contrato-aep-17-v8',
    actualizado_en = statement_timestamp()
where template_version = 'contrato-aep-17-v9'
  and estado in ('pendiente', 'error_reintentable')
  and lease_token is null
  and lease_expira_en is null
  and sha256 is null
  and bytes is null
  and subido_en is null;

alter table private.contrato_pdf_jobs
  enable trigger contrato_pdf_jobs_transiciones_validas;

-- Las funciones vuelven a estampar la v8 por el mismo mecanismo de la ida: el
-- cuerpo VIVO, cambiando solo el literal. Así la reversa no retrocede ningún
-- cambio que otra migración haya hecho a esos cuerpos mientras tanto.
do $block$
declare
  v_esperado constant text[] := array[
    'crear_job_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid)',
    'crear_revision_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid)'
  ];
  v_encontrado text[];
  v_oids oid[];
  v_oid oid;
  v_def text;
  v_ocurrencias integer;
begin
  select coalesce(
           array_agg(
             p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
             order by p.proname
           ),
           array[]::text[]
         ),
         coalesce(array_agg(p.oid order by p.proname), array[]::oid[])
  into v_encontrado, v_oids
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v9') > 0;

  if v_encontrado <> v_esperado then
    raise exception
      'REVERSA v9: las funciones que estampan la v9 son % y se esperaban %',
      v_encontrado, v_esperado;
  end if;

  foreach v_oid in array v_oids loop
    v_def := pg_catalog.pg_get_functiondef(v_oid);
    v_ocurrencias := (
      length(v_def) - length(replace(v_def, 'contrato-aep-17-v9', ''))
    ) / length('contrato-aep-17-v9');
    if v_ocurrencias <> 1 then
      raise exception
        'REVERSA v9: % tiene % ocurrencias del literal v9, se esperaba 1',
        v_oid::regprocedure, v_ocurrencias;
    end if;
    execute replace(v_def, 'contrato-aep-17-v9', 'contrato-aep-17-v8');
  end loop;
end;
$block$;

do $block$
declare
  v_default text;
  v_v9 integer;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid)
  into v_default
  from pg_catalog.pg_attrdef d
  join pg_catalog.pg_attribute a
    on a.attrelid = d.adrelid and a.attnum = d.adnum
  where d.adrelid = 'private.contrato_pdf_jobs'::regclass
    and a.attname = 'template_version';

  if v_default is null or strpos(v_default, 'contrato-aep-17-v8') = 0 then
    raise exception 'REVERSA v9: el default quedo en %', coalesce(v_default, '<null>');
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'private.contrato_pdf_jobs'::regclass
      and t.tgname = 'contrato_pdf_jobs_transiciones_validas'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ) then
    raise exception 'REVERSA v9: el trigger de transiciones no quedo habilitado';
  end if;

  select count(*)::integer into v_v9
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v9') > 0;

  if v_v9 <> 0 then
    raise exception 'REVERSA v9: % funciones siguen estampando la v9', v_v9;
  end if;

  raise notice 'CONTRATO_PDF_V9_ROLLBACK_OK (los PDFs sellados v9 siguen intactos y descargables)';
end;
$block$;

commit;
