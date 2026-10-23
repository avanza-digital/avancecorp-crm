-- El enmascarado de texto libre es parcial; guardar resultados solo en carpeta privada.
-- Solo lectura. Resolver los casos por condición, sin identificadores personales fijos.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';
SELECT jsonb_build_object(
 'medido_en',transaction_timestamp(),
 'leads_detalle',(
 SELECT jsonb_agg(jsonb_build_object(
   'lead_id',l.id,
   'cliente_en_perfil',p.nombre_completo,
   'contratos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'numero',c.numero_contrato,'estado',c.estado,'es_demo',c.es_demo,'capital',c.capital,'moneda',c.moneda,'fecha_inicio',c.fecha_inicio,'fecha_cierre_comercial',c.fecha_cierre_comercial,'categoria',c.categoria,'creado_en',c.creado_en,'analista_cierre_id',c.analista_cierre_id)) FROM public.contratos c WHERE c.cliente_id=l.perfil_id),'[]'::jsonb),
   'inversiones',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'contrato_id',i.contrato_id,'cierre_externo_id',i.cierre_externo_id,'estado',i.estado,'fecha_comercial',i.fecha_comercial,'es_primera_conversion',i.es_primera_conversion,'creado_en',i.creado_en)) FROM crm.inversiones i WHERE i.inversionista_id=l.inversionista_id),'[]'::jsonb),
   'cierres_externos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',ce.id,'cooperativa',ce.cooperativa,'monto',ce.monto,'moneda',ce.moneda,'es_cierre_inicial',ce.es_cierre_inicial,'creado_en',ce.creado_en,'anulado_en',ce.anulado_en,'motivo_anulacion',ce.motivo_anulacion,'fecha_comercial',ce.fecha_comercial)) FROM crm.cierres_externos ce WHERE ce.lead_id=l.id),'[]'::jsonb),
   'episodios',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'analista',pa.nombre_completo,'asignado_en',a.asignado_en,'motivo_apertura',a.motivo_apertura,'finalizado_en',a.finalizado_en,'motivo_cierre',a.motivo_cierre,'resultado',a.resultado,'resultado_en',a.resultado_en) ORDER BY a.asignado_en) FROM crm.lead_asignaciones a LEFT JOIN public.perfiles pa ON pa.id=a.analista_id WHERE a.lead_id=l.id),'[]'::jsonb),
   'actividades',coalesce((SELECT jsonb_agg(jsonb_build_object('tipo',a.tipo,'fecha',a.creado_en,'autor',pa.nombre_completo,'detalle',left(regexp_replace(regexp_replace(a.detalle,'[0-9]{8,}','[numero oculto]','g'),'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}','[correo oculto]','g'),600)) ORDER BY a.creado_en) FROM crm.actividades a LEFT JOIN public.perfiles pa ON pa.id=a.creado_por WHERE a.lead_id=l.id),'[]'::jsonb),
   'cambios_etapa',coalesce((SELECT jsonb_agg(jsonb_build_object('fecha',a.ts,'operacion',a.operacion,'autor',pa.nombre_completo,'antes',a.data_antes->>'etapa','despues',a.data_despues->>'etapa','contrato_antes',a.data_antes->>'contrato_id','contrato_despues',a.data_despues->>'contrato_id') ORDER BY a.ts) FROM public.audit_log a LEFT JOIN public.perfiles pa ON pa.id=a.usuario_id WHERE a.fila_id=l.id::text AND a.tabla IN ('leads','crm.leads') AND (a.data_antes->>'etapa' IS DISTINCT FROM a.data_despues->>'etapa')),'[]'::jsonb)
 ) ORDER BY l.convertido_en)
 FROM crm.leads l LEFT JOIN public.perfiles p ON p.id=l.perfil_id WHERE l.id IN (SELECT ls.id FROM crm.leads ls WHERE ls.etapa='convertido' AND ls.convertido_en >= timestamptz '2026-09-01 00:00:00-05' AND NOT EXISTS (SELECT 1 FROM crm.conversion_acreditaciones ca WHERE ca.lead_id=ls.id))
 ),
 'borrados_portal',(
 SELECT jsonb_agg(jsonb_build_object('contrato_id',a.fila_id,'auditoria_id',a.id,'tabla',a.tabla,'operacion',a.operacion,'fecha',a.ts,'actor_id',a.usuario_id,'actor',pa.nombre_completo,'numero_contrato',a.data_antes->>'numero_contrato','estado_antes',a.data_antes->>'estado','cliente_id',a.data_antes->>'cliente_id') ORDER BY a.ts)
 FROM public.audit_log a LEFT JOIN public.perfiles pa ON pa.id=a.usuario_id
 WHERE a.fila_id IN (SELECT DISTINCT lr.contrato_id::text FROM crm.ledger_rentabilidad lr WHERE NOT EXISTS (SELECT 1 FROM public.contratos c WHERE c.id=lr.contrato_id) AND NOT EXISTS (SELECT 1 FROM crm.contratos_eliminados_auditoria ce WHERE ce.contrato_id=lr.contrato_id)) AND a.tabla IN ('contratos','public.contratos') AND a.operacion='DELETE'
 ),
 'octubre_inversiones_recientes',(
 SELECT jsonb_agg(jsonb_build_object('numero_contrato',c.numero_contrato,'contrato_id',c.id,'fecha_comercial',ca.fecha_comercial,'estado_acreditacion',ca.estado,'inversion_creada_en',i.creado_en,'inversion_id',i.id) ORDER BY i.creado_en)
 FROM crm.conversion_acreditaciones ca JOIN public.contratos c ON c.id=ca.fuente_id
 JOIN crm.inversiones i ON i.contrato_id=c.id
 WHERE ca.fuente_tipo='contrato' AND ca.periodo_comercial='2026-10-01' AND i.creado_en>=timestamptz '2026-10-22 21:03:00-05'
 ),
 'roles_lectores_datos',(
 SELECT jsonb_build_object(
 'select_tabla_authenticated',has_table_privilege('authenticated','crm.leads','SELECT'),
 'columnas_sensibles', (SELECT jsonb_agg(jsonb_build_object('columna',c,'lectura',has_column_privilege('authenticated','crm.leads',c,'SELECT'))) FROM unnest(ARRAY['dni','fecha_nacimiento','genero']) c),
 'policies_select',(SELECT jsonb_agg(jsonb_build_object('nombre',policyname,'roles',roles,'filtro',qual)) FROM pg_policies WHERE schemaname='crm' AND tablename='leads' AND cmd IN ('SELECT','ALL'))
 ))
) AS evidencia;
COMMIT;
