-- ALARMA DE UN SOLO NÚCLEO — SOLO LECTURA, UNA SOLA SENTENCIA.
--
-- Cuatro caminos calculan la conversión del mes vigente: el núcleo directo
-- (private.conversion_episodios), la lectura mensual (crm.conversion_mensual_fn),
-- el rango de ese mes (crm.metricas_conversiones_fn) y la distribución
-- (crm.metricas_distribucion_leads_v3_fn). Tienen que decir lo mismo. La sonda
-- que hoy autoriza pintar el % compara el núcleo consigo mismo y no puede
-- fallar; ésta compara caminos DISTINTOS y sí puede.
--
-- Devuelve una fila: cuadra (boolean) + detalle. Pensada para correr desde
-- gate-realidad.mjs con una sesión de gerencia (impersonada aquí para
-- db query), y para que el mutante (mutante-alarma.sql) la ponga en rojo.
--
-- Uso directo: supabase db query --linked --file supabase/scripts/conversion/alarma.sql
with claims as (
  select set_config('request.jwt.claims', json_build_object(
    'sub', (select p.id from public.perfiles p where private.rol_crm(p.id)='gerencia' and p.activo order by p.id limit 1),
    'role','authenticated')::text, true) as x
), v as (
  select date_trunc('month', (now() at time zone 'America/Lima'))::date as mes,
         (now() at time zone 'America/Lima')::date as hoy
), ventana as (
  select mes, hoy,
         (mes::text||' 00:00')::timestamp at time zone 'America/Lima' as ini,
         ((hoy+1)::text||' 00:00')::timestamp at time zone 'America/Lima' as fin
  from v
), nucleo as (
  select sum(e.aporte_divisor)::numeric as divisor, round(sum(e.aporte_numerador),4) as numerador,
         round(100.0*sum(e.aporte_numerador)/nullif(sum(e.aporte_divisor),0),2) as pct
  from ventana w, private.conversion_episodios(w.ini, w.fin, w.mes, true, null, private.peso_referido_conversion(w.mes)) e
), mensual as (
  select (m.j->'total'->>'divisor')::numeric as divisor, (m.j->'total'->>'numerador')::numeric as numerador,
         (m.j->'total'->>'conversion_pct')::numeric as pct
  from claims, ventana w, lateral (select crm.conversion_mensual_fn(w.mes) as j) m
), rango as (
  select (r.j->'nucleo'->>'divisor')::numeric as divisor, (r.j->'nucleo'->>'numerador')::numeric as numerador,
         (r.j->'nucleo'->>'conversion_pct')::numeric as pct
  from claims, ventana w, lateral (select crm.metricas_conversiones_fn(w.mes, w.hoy, null) as j) r
), distribucion as (
  select (d.j->'resumen'->'conversion'->>'nucleo_divisor')::numeric as divisor,
         (d.j->'resumen'->'conversion'->>'nucleo_numerador')::numeric as numerador,
         (d.j->'resumen'->'conversion'->>'nucleo_conversion_pct')::numeric as pct
  from claims, ventana w, lateral (select crm.metricas_distribucion_leads_v3_fn(w.mes, w.hoy) as j) d
), caminos as (
  select 'nucleo_directo' as camino, * from nucleo
  union all select 'mensual', * from mensual
  union all select 'rango', * from rango
  union all select 'distribucion', * from distribucion
), veredicto as (
  select
    count(distinct divisor) = 1 and count(distinct numerador) = 1 and count(distinct pct) = 1
      and count(*) filter (where divisor is null or numerador is null) = 0 as cuadra,
    count(*) as caminos_leidos,
    jsonb_object_agg(camino, jsonb_build_object('divisor', divisor, 'numerador', numerador, 'pct', pct)) as detalle
  from caminos
)
select (select mes from v) as mes, (select hoy from v) as hasta, cuadra, caminos_leidos, detalle
from veredicto;
