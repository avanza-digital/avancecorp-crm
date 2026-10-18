-- SOLO LECTURA. Para las ventas de octubre eliminadas y vueltas a cargar: a qué fuente apunta hoy la acreditación del
-- lead (¿al contrato vivo o al eliminado?), su estado y cuándo se acreditó, y la anulación que dejó la eliminación.
begin read only;
select l.nombre_completo as lead, ca.estado, ca.periodo_comercial::text as periodo, ca.fuente_tipo,
       left(ca.fuente_id::text, 8) as fuente,
       exists (select 1 from public.contratos c where c.id = ca.fuente_id) as fuente_viva,
       (select c.numero_contrato from public.contratos c where c.id = ca.fuente_id) as numero_fuente,
       to_char(ca.acreditado_en at time zone 'America/Lima', 'DD/MM HH24:MI') as acreditado_en,
       to_char(e.eliminado_en at time zone 'America/Lima', 'DD/MM HH24:MI') as eliminado_en,
       left(e.fuente_id::text, 8) as eliminado_id, left(coalesce(e.anulacion::text, ''), 160) as anulacion,
       to_char(l.convertido_en at time zone 'America/Lima', 'DD/MM HH24:MI') as lead_convertido_en, left(ca.analista_id::text, 8) as analista
from crm.inversiones_eliminadas e
join crm.leads l on l.id = e.lead_id
left join crm.conversion_acreditaciones ca on ca.lead_id = e.lead_id
where e.lead_id is not null and e.reemplazada_por is null and e.eliminado_en >= timestamptz '2026-10-01 00:00:00-05'
order by e.eliminado_en;
rollback;
