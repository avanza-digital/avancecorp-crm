-- OPCIONAL · SOLO LECTURA. Registros de configuración de los trinquetes (F7, exenciones analíticas, vigencia, auditoría),
-- alertas abiertas de los vigías, jobs de cron y huellas de funciones crm+private de PRODUCCIÓN, sin personas. Sirve para
-- llevar esos registros a un banco de solo esquema (donde están vacíos). La lectura desde la sesión de Claude fue DENEGADA
-- el 14/10 (clasificador): la corre Miguel con:
--   ! npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/leer-registros-produccion.sql -o json > /tmp/registros-produccion.json
-- No es necesaria para aplicar: el ensayo del paso 1 del LEEME compara la foto de los trinquetes ANTES y DESPUÉS dentro de
-- la propia migración, contra producción.
select jsonb_build_object(
  'f7', (select jsonb_agg(to_jsonb(x) order by x.firma) from private.f7_piezas_en_observacion x),
  'analitica_exenciones', (select jsonb_agg(to_jsonb(x) order by x.objeto) from private.analitica_leads_citas_exenciones x),
  'analitica_tope', (select jsonb_agg(to_jsonb(x)) from private.analitica_leads_citas_tope x),
  'analitica_sello', (select jsonb_agg(to_jsonb(x)) from private.analitica_lc_sello x),
  'vigencia_exenciones', (select jsonb_agg(to_jsonb(x) order by x.objeto) from private.analista_vigencia_exenciones x),
  'vigencia_tope', (select jsonb_agg(to_jsonb(x)) from private.analista_vigencia_tope x),
  'auditoria_exenciones', (select jsonb_agg(to_jsonb(x) order by x.tabla) from private.auditoria_exenciones x),
  'auditoria_condicionada', (select jsonb_agg(to_jsonb(x) order by x.tabla) from private.auditoria_condicionada x),
  'auditoria_sello', (select jsonb_agg(to_jsonb(x)) from private.auditoria_sello x),
  'auditoria_alertas_abiertas', (select count(*) from private.auditoria_alertas where resuelta_en is null),
  'vigia_alertas_abiertas', (select jsonb_agg(jsonb_build_object('fase', fase, 'motivo', left(motivo, 300), 'creado_en', creado_en)
                                              order by creado_en) from private.vigia_alertas where resuelta_en is null),
  'cron', (select jsonb_agg(jsonb_build_object('jobid', jobid, 'jobname', jobname, 'schedule', schedule, 'command', command,
                                               'active', active) order by jobid) from cron.job),
  'meses_sellados', (select jsonb_agg(periodo order by periodo) from crm.periodos_cerrados),
  'plazo_septiembre', (select private.conversion_plazo_hasta(date '2026-09-01')),
  'huellas_funciones', (select jsonb_object_agg(c.esquema, jsonb_build_object('n', c.n, 'md5', c.h)) from (
      select n.nspname as esquema, count(*) as n,
             md5(string_agg(md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::pg_catalog.regprocedure::text)) as h
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('crm', 'private') and p.prokind = 'f'
       group by n.nspname) c)
) as registros;
