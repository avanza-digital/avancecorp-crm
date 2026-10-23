-- Solo lectura. Distinguir un contrato existente de una fuente retirada antes de proponer un alta.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '20s';
WITH pendientes AS (
 SELECT ca.*, c.id AS contrato_vivo
 FROM crm.conversion_acreditaciones ca LEFT JOIN public.contratos c ON c.id=ca.fuente_id
 WHERE ca.fuente_tipo='contrato' AND NOT EXISTS (SELECT 1 FROM crm.inversiones i WHERE i.contrato_id=ca.fuente_id)
)
SELECT jsonb_build_object(
 'medido_en',transaction_timestamp(),
 'conteo_por_estado_contrato',(SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT periodo_comercial,estado,contrato_vivo IS NOT NULL AS contrato_existe,count(*) FROM pendientes GROUP BY 1,2,3 ORDER BY 1,2,3) t),
 'fuentes_retiradas',(SELECT jsonb_agg(jsonb_build_object(
 'acreditacion_id',ca.id,'lead_id',ca.lead_id,'cliente',l.nombre_completo,'analista',p.nombre_completo,
 'contrato_id',ca.fuente_id,'numero_contrato',a.snapshot->'contrato'->>'numero_contrato','fecha_comercial',ca.fecha_comercial,'periodo_comercial',ca.periodo_comercial,'estado_acreditacion',ca.estado,'sellado_en',ca.sellado_en,'incluida_en_sello',ca.incluida_en_sello,'eliminado_en',a.eliminado_en,
 'eliminacion_inversion',(SELECT jsonb_agg(jsonb_build_object('id',ie.id,'motivo',ie.motivo,'eliminado_en',ie.eliminado_en,'conversion_anulada',ie.conversion_anulada,'reemplazada_por',ie.reemplazada_por)) FROM crm.inversiones_eliminadas ie WHERE ie.fuente_tipo='contrato' AND ie.fuente_id=ca.fuente_id)
 ) ORDER BY l.nombre_completo) FROM pendientes ca LEFT JOIN crm.leads l ON l.id=ca.lead_id LEFT JOIN public.perfiles p ON p.id=ca.analista_id LEFT JOIN crm.contratos_eliminados_auditoria a ON a.contrato_id=ca.fuente_id WHERE ca.contrato_vivo IS NULL),
 'funciones_conversion',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'nombre',p.proname,'firma',pg_get_function_identity_arguments(p.oid))) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('crm','private') AND p.proname ~ '(conversion.*(fuente|hecho|acreditar|sincron|demo)|demo.*(lead|perfil))')
) AS evidencia;
COMMIT;
