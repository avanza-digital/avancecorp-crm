-- SOLO LECTURA. VICTOR ARANGO (001621) y JOSÉ PEDRO MEJÍA (001536): categoría del contrato ORIGINAL borrado (auditoría),
-- correcciones de categoría, operación de cartera del recargado (de qué contrato amplía, si es elegible) y si hoy aporta
-- a la conversión según private.conversion_episodios (la métrica oficial).
begin read only;
with obj as (
  select c.id, c.numero_contrato, c.categoria, c.creado_en, c.cliente_id from public.contratos c
  where c.numero_contrato in ('2026-01-001621', '2026-01-001536')
),
ops as (
  select o.* from private.operaciones_cartera_clasificadas() o where o.contrato_nuevo_id in (select id from obj)
),
epi as (
  select x.operacion_id, x.categoria, x.aporte_numerador, x.analista_id
  from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', now(), null, true, null, 1) x
  where x.tipo = 'operacion' and x.operacion_id in (select id from ops)
)
select obj.numero_contrato, obj.categoria as categoria_hoy, to_char(obj.creado_en at time zone 'America/Lima', 'DD/MM HH24:MI') as recargado,
       (select string_agg(coalesce(a.snapshot #>> '{contrato,categoria}', '?') || ' borrado ' || to_char(a.eliminado_en at time zone 'America/Lima', 'DD/MM HH24:MI'), '; ')
          from crm.contratos_eliminados_auditoria a where a.snapshot #>> '{contrato,numero_contrato}' = obj.numero_contrato) as original_borrado,
       (select string_agg(x.categoria_anterior || '→' || x.categoria_nueva, '; ') from crm.correcciones_categoria_contrato x where x.contrato_id = obj.id) as correcciones,
       (select string_agg(o.tipo || ' periodo=' || o.periodo || ' elegible=' || o.elegible_conversion::text
                 || ' origen=' || coalesce((select c2.numero_contrato from public.contratos c2 where c2.id = o.contrato_origen_id), 'BORRADO ' || left(o.contrato_origen_id::text, 8)), '; ')
          from ops o where o.contrato_nuevo_id = obj.id) as operacion_cartera,
       (select string_agg(e.categoria || ' aporta=' || e.aporte_numerador, '; ') from epi e join ops o on o.id = e.operacion_id where o.contrato_nuevo_id = obj.id) as aporta_conversion
from obj order by obj.numero_contrato;
rollback;
