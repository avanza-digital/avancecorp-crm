-- SOLO LECTURA. ¿Cuentan para la conversión de octubre las ventas de leads eliminadas y vueltas a cargar? Se pregunta
-- a las MISMAS funciones que usa la métrica oficial: private.cierre_anulado y private.conversion_episodios (octubre,
-- vista global, factor 1). anulado = true → esa venta NO cuenta.
begin read only;
with leads_elim as (
  select distinct e.lead_id from crm.inversiones_eliminadas e
  where e.lead_id is not null and e.reemplazada_por is null and e.eliminado_en >= timestamptz '2026-10-01 00:00:00-05'
),
epi as (
  select x.lead_id, bool_or(x.anulado) as anulado_en_episodios, count(*) as episodios
  from private.conversion_episodios(timestamptz '2026-10-01 00:00:00-05', now(), date '2026-10-01', true, null, 1) x
  where x.tipo = 'cierre' and x.lead_id in (select lead_id from leads_elim)
  group by x.lead_id
)
select l.nombre_completo as lead, private.cierre_anulado(l.id) as cierre_anulado,
       coalesce(epi.anulado_en_episodios::text, 'sin episodio') as anulado_en_episodios, coalesce(epi.episodios, 0) as episodios,
       exists (select 1 from crm.cierres_avance_anulados a where a.lead_id = l.id) as en_cierres_anulados
from leads_elim le join crm.leads l on l.id = le.lead_id left join epi on epi.lead_id = le.lead_id
order by l.nombre_completo;
rollback;
