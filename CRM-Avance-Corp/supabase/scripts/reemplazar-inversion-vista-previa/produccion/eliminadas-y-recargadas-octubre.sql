-- SOLO LECTURA. Ventas de leads a las que se ELIMINÓ la inversión desde el 01/10/2026 (sin contar reemplazos): si el
-- cliente volvió a tener inversión después (contrato Avance o cierre de cooperativa) y cómo quedó la acreditación del lead.
begin read only;
with elim as (
  select e.lead_id, e.inversionista_id, e.empresa, e.fuente_tipo, e.snapshot #>> '{contrato,numero_contrato}' as numero,
         e.eliminado_en, e.es_conversion, e.conversion_anulada
  from crm.inversiones_eliminadas e
  where e.lead_id is not null and e.reemplazada_por is null
    and e.eliminado_en >= timestamptz '2026-10-01 00:00:00-05'
)
select l.nombre_completo as lead, el.empresa, el.fuente_tipo, coalesce(el.numero, '—') as eliminado,
       to_char(el.eliminado_en at time zone 'America/Lima', 'DD/MM HH24:MI') as eliminado_en,
       el.es_conversion, el.conversion_anulada,
       coalesce((select string_agg(c.numero_contrato || ' ' || to_char(c.creado_en at time zone 'America/Lima', 'DD/MM'), '; ')
          from public.contratos c join crm.inversionistas i on i.perfil_id = c.cliente_id
          where i.id = el.inversionista_id and c.creado_en > el.eliminado_en and not c.es_demo), '') as contratos_despues,
       coalesce((select string_agg(x.cooperativa || ' ' || to_char(x.creado_en at time zone 'America/Lima', 'DD/MM'), '; ')
          from crm.cierres_externos x
          where x.inversionista_id = el.inversionista_id and x.creado_en > el.eliminado_en and x.anulado_en is null), '') as coop_despues,
       coalesce((select string_agg(ca.estado || ' ' || coalesce(ca.periodo_comercial::text, '') || ' ' || ca.fuente_tipo, '; ' order by ca.creado_en)
          from crm.conversion_acreditaciones ca where ca.lead_id = el.lead_id), 'ninguna') as acreditaciones_del_lead,
       l.etapa, l.contrato_id is not null as lead_apunta_a_contrato
from elim el join crm.leads l on l.id = el.lead_id
order by el.eliminado_en;
rollback;
