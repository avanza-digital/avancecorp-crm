-- SOLO LECTURA. Censo: ventas de leads ANULADAS desde el 01/08/2026 y si el cliente tiene HOY una inversión viva
-- cargada después de la anulación (la «recarga»). Con analista, mes de la venta y si la venta se cuenta hoy.
begin read only;
select l.nombre_completo as lead,
       coalesce((select p.nombre_completo from public.perfiles p where p.id = ca.analista_id), '—') as analista,
       to_char(a.anulado_en at time zone 'America/Lima', 'DD/MM HH24:MI') as anulada, left(coalesce(a.motivo, ''), 60) as motivo_anulacion,
       ca.estado as acreditacion, ca.periodo_comercial::text as mes_venta,
       exists (select 1 from public.contratos c where c.id = ca.fuente_id) as fuente_viva,
       (select string_agg(ie.snapshot #>> '{contrato,numero_contrato}', ', ') from crm.inversiones_eliminadas ie where ie.lead_id = l.id) as eliminado,
       coalesce((select string_agg(c.numero_contrato || ' ' || c.categoria || ' ' || to_char(c.creado_en at time zone 'America/Lima', 'DD/MM'), '; ' order by c.creado_en)
          from public.contratos c join crm.inversionistas i on i.perfil_id = c.cliente_id
          where i.id = coalesce(ca.inversionista_id, l.inversionista_id) and c.creado_en >= a.anulado_en and not c.es_demo), '') as avance_despues,
       coalesce((select string_agg(x.cooperativa || ' ' || to_char(x.creado_en at time zone 'America/Lima', 'DD/MM'), '; ')
          from crm.cierres_externos x
          where x.inversionista_id = coalesce(ca.inversionista_id, l.inversionista_id) and x.creado_en >= a.anulado_en and x.anulado_en is null), '') as coop_despues
from crm.cierres_avance_anulados a
join crm.leads l on l.id = a.lead_id
left join crm.conversion_acreditaciones ca on ca.lead_id = a.lead_id
where a.anulado_en >= timestamptz '2026-08-01 00:00:00-05'
order by a.anulado_en;
rollback;
