-- SOLO LECTURA (producción). Antes de aplicar 20261018053228 (auditor-rls, P3 y riesgos de regresión):
--   1. ¿Hay orígenes de capital confirmados ACTIVOS sobre cierres iniciales de cooperativa? El reemplazo los rechaza con
--      «requiere revisión»; si hubiera muchos, convendría trasladarlos como hace Avance.
--   2. ¿Queda alguna función viva que filtre crm.cierres_externos solo por creado_en (sin fecha_comercial ni fecha_imputacion)?
--      La fila nueva nace con creado_en = ahora: una lectura así la movería de mes.
-- Uso: supabase db query --linked --file supabase/scripts/reemplazar-inversion-cooperativa/foto-prod.sql
begin read only;
set local search_path = '';
select 'origenes_confirmados_activos_en_cierres_iniciales' as dato, count(*)::text as valor
from crm.origenes_capital_confirmados o join crm.cierres_externos ce on ce.id = o.cierre_externo_id
where o.activo and ce.es_cierre_inicial
union all
select 'cierres_iniciales_vigentes_con_venta', count(*)::text
from crm.cierres_externos ce where ce.es_cierre_inicial and ce.anulado_en is null and ce.lead_id is not null
union all
select 'funciones_que_leen_cierres_externos_por_creado_en_sin_fecha', coalesce(string_agg(p.oid::regprocedure::text, ', ' order by 1), 'ninguna')
from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('crm', 'private', 'public') and p.prosrc ~ 'cierres_externos' and p.prosrc ~ 'creado_en'
  and p.prosrc !~ 'fecha_comercial' and p.prosrc !~ 'fecha_imputacion';
rollback;
