-- SOLO LECTURA (producción). Antes de aplicar 20261018032400: proyección del REPARTO del tope de referidos en octubre para
-- Astrid (caso 1, Julio César) y Nayra (caso 2, Nancy), tal como lo hace private.conversion_episodios: n referidos del
-- analista y mes × tope %, repartido en orden (fecha comercial, acreditación, lead). Recuperar un referido sube la SUMA del
-- analista exactamente una cuota (lo que exige el postflight de la v3); el aporte individual de cada referido puede moverse
-- (incluso quedar en 0): es la regla vigente de la métrica, no un efecto de la migración. Consulta propuesta por Codex el
-- 18/10/2026 y adaptada a la v3. Uso: supabase db query --linked --file supabase/scripts/recuperar-ventas-recargadas/foto-tope-referidos.sql
begin isolation level repeatable read read only;
set local search_path = '';
with
corte as (select pg_catalog.statement_timestamp() as fin),
casos(lead_id, analista_id, fecha_numerador) as (values
  ('0f091c66-89f1-4dc9-9d4a-120da8499a24'::uuid, '2ec5954f-0490-44f2-87cd-af6210f3426f'::uuid, timestamptz '2026-10-05 00:00:00-05'),
  ('3851878c-b5fb-4372-b45e-5f89d39afc85'::uuid, 'ad36b962-5175-4e4e-b644-e546897c3a85'::uuid, timestamptz '2026-10-01 00:00:00-05')),
pesos as (select private.peso_referido_conversion(date '2026-10-01') as peso, private.tope_referidos_conversion(date '2026-10-01') as pct),
base as materialized (
  select c.lead_id, c.analista_id, c.fecha_numerador, ca.acreditado_en as registrado_en, c.aporte_numerador as bruto
  from private.conversion_cierres(timestamptz '2026-10-01 00:00:00-05', timestamptz '2026-11-01 00:00:00-05', null, true, null, 1, null::uuid[]) c
  left join crm.conversion_acreditaciones ca on ca.lead_id = c.lead_id
  where c.fue_referido and not c.anulado and c.analista_id in (select analista_id from casos)),
versiones as (
  select 'antes'::text as foto, false as recuperado, b.* from base b
  union all select 'despues', false, b.* from base b
  union all select 'despues', true, c.lead_id, c.analista_id, c.fecha_numerador, k.fin, p.peso from casos c cross join corte k cross join pesos p),
ventanas as (
  select v.*, count(*) over (partition by foto, analista_id) as total,
         coalesce(sum(bruto) over (partition by foto, analista_id order by fecha_numerador, registrado_en, lead_id
                                   rows between unbounded preceding and 1 preceding), 0) as previo,
         (select pct from pesos) as pct
  from versiones v),
aportes as (
  select v.*, case when pct is null then bruto else least(bruto, greatest(0::numeric, total * pct / 100.0 - previo)) end as neto
  from ventanas v),
por_lead as (
  select d.analista_id, d.lead_id, d.recuperado, d.fecha_numerador::date as fecha, a.neto as aporte_antes, d.neto as aporte_despues
  from aportes d left join aportes a on a.foto = 'antes' and a.analista_id = d.analista_id and a.lead_id = d.lead_id
  where d.foto = 'despues'),
por_analista as (
  select analista_id,
         count(*) filter (where not recuperado) as referidos_hoy,
         coalesce(sum(aporte_antes), 0) as suma_antes, sum(aporte_despues) as suma_despues,
         count(*) filter (where recuperado) * (select case when pct is null then peso else least(peso, pct / 100.0) end from pesos) as subida_esperada
  from por_lead group by analista_id)
select 'RESUMEN ' || pa.analista_id as fila, pa.referidos_hoy, pa.suma_antes, pa.suma_despues, pa.subida_esperada,
       case when pa.suma_despues = pa.suma_antes + pa.subida_esperada then 'OK: el postflight pasa' else 'REVISAR: la suma no sube una cuota' end as veredicto,
       (select peso from pesos) as peso_referido, (select pct from pesos) as tope_pct
from por_analista pa
union all
select 'lead ' || pl.lead_id || case when pl.recuperado then ' (RECUPERADO)' else '' end, null, pl.aporte_antes, pl.aporte_despues, null,
       'fecha ' || pl.fecha || ' · analista ' || pl.analista_id, null, null
from por_lead pl
order by 1;
rollback;
