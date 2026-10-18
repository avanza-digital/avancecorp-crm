-- SOLO LECTURA. Foto exacta de los 5 casos a recuperar (ids y estado), para fijar las constantes y el preflight de la
-- migración de recuperación de ventas recargadas. Una fila por caso.
begin read only;
with r(caso, lead_id, recargado, fcc_destino) as (values
  ('1 JULIO', '0f091c66-89f1-4dc9-9d4a-120da8499a24'::uuid, 'c7e75b21-3f9e-454b-8677-0e1f40b79a03'::uuid, date '2026-10-05'),
  ('2 NANCY', '3851878c-b5fb-4372-b45e-5f89d39afc85'::uuid, '87fd8286-4082-4a9a-af57-5616935c7628'::uuid, date '2026-10-01'),
  ('3 MARIA AURORA', '043ed717-8bf5-4201-99d8-cc0d0ef6233b'::uuid, '6a3153d6-5c4a-4c9f-9767-a8f8b8af689a'::uuid, date '2026-10-16'),
  ('4 VICTOR', '24eaface-ed34-482c-9c19-70987971aac0'::uuid, '13fb9327-f8da-4b28-ab40-3e8728f01a98'::uuid, date '2026-10-15'),
  ('5 JOSE PEDRO', '8276ae9d-9a7c-4720-8248-60c2d99b1afe'::uuid, '25b94389-1a2a-435f-bdb6-1c0421dc8317'::uuid, date '2026-09-30')
)
select r.caso, r.lead_id, l.etapa, l.origen, l.alta_manual, l.perfil_id, l.contrato_id as lead_contrato, l.inversionista_id,
       ca.id as acreditacion_id, ca.fuente_tipo, ca.fuente_id as fuente_actual, ca.estado, ca.periodo_comercial, ca.fecha_comercial,
       ca.acreditado_en, ca.analista_id, ca.episodio_id, ca.origen as acred_origen,
       (select a.id from crm.cierres_avance_anulados a where a.lead_id = r.lead_id) as anulacion_id,
       (select string_agg(ie.id::text, ',') from crm.inversiones_eliminadas ie where ie.lead_id = r.lead_id and ie.conversion_anulada) as copia_anulada_ids,
       (select count(*) from crm.ajustes_mes_cerrado aj where aj.lead_id = r.lead_id) as ajustes_mes_cerrado,
       r.recargado, c.cliente_id as recargado_cliente, c.cliente_id = l.perfil_id as pertenece, c.categoria, c.estado as recargado_estado,
       c.es_demo, c.fecha_inicio, c.fecha_cierre_comercial, c.fuente_cierre_comercial, c.analista_cierre_id, c.creado_en,
       r.fcc_destino,
       (select string_agg(o.lead_id::text, ',') from crm.conversion_acreditaciones o where o.fuente_id = r.recargado) as recargado_acreditado_a,
       (select i.es_primera_conversion from crm.inversiones i where i.contrato_id = r.recargado) as inv_primera_conversion,
       (select i.id from crm.inversiones i where i.contrato_id = r.recargado) as inversion_id,
       (select count(*) from crm.correcciones_categoria_contrato x where x.contrato_id = r.recargado) as correcciones_categoria
from r join crm.leads l on l.id = r.lead_id
left join crm.conversion_acreditaciones ca on ca.lead_id = r.lead_id
left join public.contratos c on c.id = r.recargado
order by r.caso;
rollback;
