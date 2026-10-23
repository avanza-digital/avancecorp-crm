-- Solo lectura. Las listas contienen datos personales: guardar resultados fuera de Git.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';
WITH ventas AS (
 SELECT ca.id AS acreditacion_id, ca.lead_id, ca.episodio_id, ca.inversionista_id, ca.analista_id,
   coalesce(pc.nombre_completo,l.nombre_completo) AS cliente,
   pa.nombre_completo AS analista_acreditado, pv.nombre_completo AS analista_actual_lead,
   ca.periodo_comercial, ca.fecha_comercial, ca.estado AS estado_acreditacion,
   ca.sellado_en, ca.incluida_en_sello, ca.motivo,
   c.id AS contrato_id, c.numero_contrato, c.estado AS estado_contrato, c.es_demo,
   c.capital, c.moneda, c.categoria, c.fecha_inicio, c.creado_en AS contrato_creado_en,
   l.contrato_id AS contrato_en_lead, l.etapa AS etapa_lead, l.activo AS lead_activo
 FROM crm.conversion_acreditaciones ca
 JOIN public.contratos c ON c.id=ca.fuente_id
 LEFT JOIN crm.leads l ON l.id=ca.lead_id
 LEFT JOIN public.perfiles pc ON pc.id=c.cliente_id
 LEFT JOIN public.perfiles pa ON pa.id=ca.analista_id
 LEFT JOIN public.perfiles pv ON pv.id=l.vendedor_id
 WHERE ca.fuente_tipo='contrato'
   AND NOT EXISTS (SELECT 1 FROM crm.inversiones i WHERE i.contrato_id=ca.fuente_id)
), sin_acreditar AS (
 SELECT l.id AS lead_id, l.nombre_completo AS cliente, p.nombre_completo AS analista_actual,
   l.etapa, l.activo, l.convertido_en, l.creado_en, l.actualizado_en, l.origen,
   l.perfil_id, l.inversionista_id, l.contrato_id,
   (SELECT count(*) FROM public.contratos c WHERE c.cliente_id=l.perfil_id) AS contratos_por_perfil,
   (SELECT count(*) FROM crm.cierres_externos ce WHERE ce.lead_id=l.id AND ce.anulado_en IS NULL) AS cierres_externos_vivos,
   (SELECT count(*) FROM crm.inversiones i WHERE i.inversionista_id=l.inversionista_id) AS inversiones_por_inversionista,
   (SELECT count(*) FROM crm.inversionista_leads il JOIN crm.inversiones i ON i.inversionista_id=il.inversionista_id WHERE il.lead_id=l.id) AS inversiones_por_puente
 FROM crm.leads l LEFT JOIN public.perfiles p ON p.id=l.vendedor_id
 WHERE l.etapa='convertido' AND l.convertido_en >= timestamptz '2026-09-01 00:00:00-05'
 AND NOT EXISTS (SELECT 1 FROM crm.conversion_acreditaciones ca WHERE ca.lead_id=l.id)
), sin_rastro_crm AS (
 SELECT lr.contrato_id, max(lr.numero_contrato) AS numero_contrato, lr.cliente_id,
   p.nombre_completo AS cliente, count(*) AS filas_ledger,
   min(lr.registrado_en) AS primer_registro, max(lr.registrado_en) AS ultimo_registro,
   string_agg(DISTINCT lr.origen, ', ') AS origenes,
   (SELECT count(*) FROM public.audit_log a WHERE a.fila_id=lr.contrato_id::text AND a.tabla IN ('contratos','public.contratos')) AS eventos_bitacora_portal,
   (SELECT count(*) FROM public.audit_log a WHERE a.fila_id=lr.contrato_id::text AND a.tabla IN ('contratos','public.contratos') AND a.operacion='DELETE') AS borrados_bitacora_portal,
   (SELECT count(*) FROM crm.inversiones_eliminadas e WHERE e.fuente_tipo='contrato' AND e.fuente_id=lr.contrato_id) AS eliminaciones_inversion
 FROM crm.ledger_rentabilidad lr LEFT JOIN public.perfiles p ON p.id=lr.cliente_id
 WHERE NOT EXISTS (SELECT 1 FROM public.contratos c WHERE c.id=lr.contrato_id)
 AND NOT EXISTS (SELECT 1 FROM crm.contratos_eliminados_auditoria a WHERE a.contrato_id=lr.contrato_id)
 GROUP BY lr.contrato_id,lr.cliente_id,p.nombre_completo
), referencias_huerfanas AS (
 SELECT l.id AS lead_id,l.nombre_completo AS cliente,p.nombre_completo AS analista,
   l.etapa,l.activo,l.contrato_id,l.perfil_id,l.inversionista_id,l.convertido_en,
   a.eliminado_en,a.snapshot->'contrato'->>'numero_contrato' AS numero_contrato_snapshot,
   (SELECT count(*) FROM public.contratos c WHERE c.cliente_id=l.perfil_id) AS contratos_candidatos_por_perfil
 FROM crm.leads l LEFT JOIN public.perfiles p ON p.id=l.vendedor_id
 LEFT JOIN crm.contratos_eliminados_auditoria a ON a.contrato_id=l.contrato_id
 WHERE l.contrato_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.contratos c WHERE c.id=l.contrato_id)
)
SELECT jsonb_build_object(
 'medido_en',transaction_timestamp(),
 'zona','America/Lima',
 'solo_lectura',current_setting('transaction_read_only'),
 'ventas_sin_inversion',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY periodo_comercial,cliente,numero_contrato) FROM ventas v),'[]'::jsonb),
 'leads_sin_acreditacion',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY convertido_en) FROM sin_acreditar l),'[]'::jsonb),
 'contratos_sin_auditoria_crm',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY numero_contrato) FROM sin_rastro_crm r),'[]'::jsonb),
 'referencias_huerfanas',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY cliente) FROM referencias_huerfanas h),'[]'::jsonb),
 'periodos_cerrados',(SELECT jsonb_agg(to_jsonb(p) ORDER BY periodo) FROM (SELECT periodo,cerrado_en,automatico FROM crm.periodos_cerrados) p)
) AS evidencia;
COMMIT;
