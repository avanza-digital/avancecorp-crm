-- Solo lectura. Ejecutar antes/después del despliegue y archivar ambas salidas.
begin read only;
set local statement_timeout = '30s';

select version();
select template_version, estado, count(*) as cantidad,
       count(*) filter (where sha256 is not null or bytes is not null or subido_en is not null) as con_bytes,
       count(*) filter (where lease_expira_en <= now()) as lease_vencido
from private.contrato_pdf_jobs
group by template_version, estado order by template_version, estado;

select column_default from information_schema.columns
where table_schema = 'private' and table_name = 'contrato_pdf_jobs'
  and column_name = 'template_version';

select c.conrelid::regclass as tabla, c.conname, pg_get_constraintdef(c.oid)
from pg_catalog.pg_constraint c
where c.conname in ('contrato_pdf_jobs_template_valido','contrato_pdfs_version_ruta_valida');

select tgname, tgenabled from pg_catalog.pg_trigger
where tgrelid = 'private.contrato_pdf_jobs'::regclass and not tgisinternal;

select p.oid, p.oid::regprocedure as funcion, p.proowner, p.proacl,
       p.prosecdef, p.proconfig, p.provolatile,
       md5(pg_get_functiondef(p.oid)) as huella_cuerpo,
       strpos(pg_get_functiondef(p.oid), 'contrato-aep-17-v9') > 0 as estampa_v9,
       strpos(pg_get_functiondef(p.oid), 'contrato-aep-17-v10') > 0 as estampa_v10
from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
where n.nspname='private' and p.proname in ('crear_job_contrato_pdf_base','crear_revision_contrato_pdf_base');

-- Huella de TODAS las columnas de cada registro sellado por versión. Incluye
-- snapshot, hash del archivo y fechas sin revelar nombres ni cuentas.
-- En una ventana sin emisiones el antes/después debe coincidir exactamente.
select template_version, count(*) as cantidad,
       md5(string_agg(to_jsonb(p)::text, E'\n' order by id)) as huella_filas
from private.contrato_pdfs p group by template_version order by template_version;

-- No expone números de cuenta. Un snapshot v1 sin cuenta ya era incompatible
-- con el anexo v1: ambos renderers exigen snapshot 2/3 con cuenta textual.
select template_version, snapshot->>'snapshotVersion' as snapshot_version,
       count(*) filter (where snapshot->'cuentaPago'->>'numeroCuenta' is null
         or jsonb_typeof(snapshot->'cuentaPago'->'numeroCuenta') is distinct from 'string'
         or btrim(snapshot->'cuentaPago'->>'numeroCuenta') = '') as cuentas_incompatibles
from private.contrato_pdfs group by template_version, snapshot->>'snapshotVersion';

select conname, pg_get_constraintdef(oid) from pg_catalog.pg_constraint
where conrelid='private.contrato_pdf_anexo_emisiones'::regclass;
select p.oid::regprocedure, pg_get_functiondef(p.oid)
from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
where n.nspname='crm' and p.proname in ('contrato_pdf_anexo_snapshot','contrato_pdf_anexo_emitido');

commit;
