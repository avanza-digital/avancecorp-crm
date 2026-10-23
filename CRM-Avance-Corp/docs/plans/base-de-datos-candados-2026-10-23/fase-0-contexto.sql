-- Solo lectura. Las versiones remotas difieren del nombre del SQL; ver MIGRACIONES.md.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '20s';
WITH candidatas AS (
 SELECT ca.* FROM crm.conversion_acreditaciones ca JOIN public.contratos c ON c.id=ca.fuente_id
 WHERE ca.fuente_tipo='contrato' AND NOT EXISTS (SELECT 1 FROM crm.inversiones i WHERE i.contrato_id=ca.fuente_id)
)
SELECT jsonb_build_object(
 'medido_en',transaction_timestamp(),
 'otras_inversiones',(
 SELECT jsonb_agg(jsonb_build_object('contrato_candidato_id',ca.fuente_id,'inversion_id',i.id,'estado',i.estado,'fecha_comercial',i.fecha_comercial,'contrato_numero',c.numero_contrato,'contrato_categoria',c.categoria,'contrato_estado',c.estado,'cooperativa',ce.cooperativa,'monto',coalesce(c.capital,ce.monto),'moneda',coalesce(c.moneda,ce.moneda),'cierre_anulado_en',ce.anulado_en))
 FROM candidatas ca JOIN crm.inversiones i ON i.inversionista_id=ca.inversionista_id
 LEFT JOIN public.contratos c ON c.id=i.contrato_id LEFT JOIN crm.cierres_externos ce ON ce.id=i.cierre_externo_id),
 'migracion_auditoria',(SELECT jsonb_agg(jsonb_build_object('version',version,'nombre',name)) FROM supabase_migrations.schema_migrations WHERE version IN ('20260916024417','20260916024423')),
 'rango_copias_crm',(SELECT jsonb_build_object('primera',min(eliminado_en),'ultima',max(eliminado_en)) FROM crm.contratos_eliminados_auditoria)
) AS evidencia;
COMMIT;
