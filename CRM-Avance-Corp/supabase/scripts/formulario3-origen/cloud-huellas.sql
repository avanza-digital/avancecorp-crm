-- Solo conteos/huellas; nunca devuelve datos personales de la copia.
-- El prefijo sintético estaba ausente antes del setup (ver cloud-verificacion.json).
with l as (select * from crm.leads where nombre_completo not like 'PRUEBA F3 NATIVO%')
select jsonb_build_object(
  'leads', (select count(*) from l),
  'datos_leads', (select md5(jsonb_agg(to_jsonb(l)-array['origen','actualizado_en'] order by id)::text) from l),
  'historial', (select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.actividades a join l on l.id=a.lead_id),
  'tareas', (select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.tareas a join l on l.id=a.lead_id),
  'asignaciones', (select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.lead_asignaciones a join l on l.id=a.lead_id),
  'acreditaciones', (select md5(jsonb_agg(to_jsonb(a)-'origen' order by a.id)::text) from crm.conversion_acreditaciones a join l on l.id=a.lead_id),
  'inversiones', (select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.inversiones a),
  'contratos', (select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from public.contratos a),
  'solicitudes', (select md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.inversion_solicitudes a),
  'fotos_vendedores', (select md5(jsonb_agg(to_jsonb(a) order by a.periodo,a.vendedor_id)::text) from crm.cierre_mes_vendedor a),
  'meses_sellados', (select md5(jsonb_agg(to_jsonb(a) order by a.periodo)::text) from crm.periodos_cerrados a)
) as huellas;
