-- Solo lectura. Contraste de relaciones, criterios de conversión y RLS tras revisión.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';
WITH candidatas AS (
 SELECT ca.* FROM crm.conversion_acreditaciones ca
 JOIN public.contratos c ON c.id=ca.fuente_id
 WHERE ca.fuente_tipo='contrato' AND NOT EXISTS (SELECT 1 FROM crm.inversiones i WHERE i.contrato_id=ca.fuente_id)
), por_lead AS (
 SELECT l.id FROM crm.leads l WHERE l.etapa='convertido'
 AND l.convertido_en >= timestamptz '2026-09-01 00:00:00-05'
 AND NOT EXISTS (SELECT 1 FROM crm.conversion_acreditaciones ca WHERE ca.lead_id=l.id)
), por_episodio AS (
 SELECT DISTINCT la.lead_id AS id FROM crm.lead_asignaciones la
 WHERE la.resultado='convertido' AND coalesce(la.resultado_en,la.finalizado_en)>=timestamptz '2026-09-01 00:00:00-05'
 AND NOT EXISTS (SELECT 1 FROM crm.conversion_acreditaciones ca WHERE ca.lead_id=la.lead_id)
)
SELECT jsonb_build_object(
 'medido_en',transaction_timestamp(),
 'relaciones_candidatas',(SELECT jsonb_agg(jsonb_build_object(
 'acreditacion_id',ca.id,'contrato_id',ca.fuente_id,
 'inversiones_del_titular',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'contrato_id',i.contrato_id,'cierre_externo_id',i.cierre_externo_id,'estado',i.estado,'es_primera_conversion',i.es_primera_conversion,'fecha_comercial',i.fecha_comercial)) FROM crm.inversiones i WHERE i.inversionista_id=ca.inversionista_id),'[]'::jsonb),
 'solicitudes_del_lead',coalesce((SELECT jsonb_agg(jsonb_build_object('id',to_jsonb(s)->>'id','estado',s.estado,'inversion_id',s.inversion_id,'puerta',to_jsonb(s)->>'puerta','creado_en',to_jsonb(s)->>'creado_en')) FROM crm.inversion_solicitudes s WHERE s.lead_origen_id=ca.lead_id),'[]'::jsonb),
 'eliminaciones_de_fuente',coalesce((SELECT jsonb_agg(jsonb_build_object('id',ie.id,'inversion_id',ie.inversion_id,'conversion_anulada',ie.conversion_anulada,'reemplazada_por',ie.reemplazada_por,'eliminado_en',ie.eliminado_en)) FROM crm.inversiones_eliminadas ie WHERE ie.fuente_tipo='contrato' AND ie.fuente_id=ca.fuente_id),'[]'::jsonb)
 ) ORDER BY ca.fuente_id) FROM candidatas ca),
 'criterios_sin_acreditacion',jsonb_build_object('por_lead',(SELECT count(*) FROM por_lead),'por_episodio',(SELECT count(*) FROM por_episodio),'solo_por_lead',(SELECT coalesce(jsonb_agg(id),'[]'::jsonb) FROM (SELECT id FROM por_lead EXCEPT SELECT id FROM por_episodio) x),'solo_por_episodio',(SELECT coalesce(jsonb_agg(id),'[]'::jsonb) FROM (SELECT id FROM por_episodio EXCEPT SELECT id FROM por_lead) x)),
 'seguridad_leads',jsonb_build_object(
 'rls',(SELECT jsonb_build_object('activa',relrowsecurity,'forzada',relforcerowsecurity) FROM pg_class WHERE oid='crm.leads'::regclass),
 'policies',(SELECT jsonb_agg(jsonb_build_object('nombre',policyname,'tipo',permissive,'roles',roles,'comando',cmd,'filtro',qual,'with_check',with_check)) FROM pg_policies WHERE schemaname='crm' AND tablename='leads'),
 'anon_select',has_table_privilege('anon','crm.leads','SELECT'),
 'anon_alguna_columna_select',has_any_column_privilege('anon','crm.leads','SELECT'),
 'anon_schema_usage',has_schema_privilege('anon','crm','USAGE'),
 'esquemas_api_rol',(SELECT jsonb_agg(setting) FROM pg_roles r CROSS JOIN LATERAL unnest(r.rolconfig) setting WHERE r.rolname='authenticator' AND setting LIKE 'pgrst.db_schemas=%'),
 'esquemas_api_base',(SELECT jsonb_agg(setting) FROM pg_db_role_setting s CROSS JOIN LATERAL unnest(s.setconfig) setting WHERE setting LIKE 'pgrst.db_schemas=%')
 ),
 'totales',jsonb_build_object('contratos_existentes',(SELECT count(*) FROM candidatas),'septiembre',(SELECT count(*) FROM candidatas WHERE periodo_comercial='2026-09-01'),'fuentes_retiradas',(SELECT count(*) FROM crm.conversion_acreditaciones ca WHERE ca.fuente_tipo='contrato' AND NOT EXISTS (SELECT 1 FROM crm.inversiones i WHERE i.contrato_id=ca.fuente_id) AND NOT EXISTS (SELECT 1 FROM public.contratos c WHERE c.id=ca.fuente_id)))
) AS evidencia;
COMMIT;
