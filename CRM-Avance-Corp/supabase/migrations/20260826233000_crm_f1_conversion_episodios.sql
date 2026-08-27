-- F1 del plan «Conversion unica en todo el CRM» (vault; decisiones D1-D7 de
-- Miguel resueltas el 2026-08-26; orden «desarrolla la fase 1»).
--
-- QUE HACE:
--   1. Nace `private.conversion_episodios(...)`: la TABLA-BASE de la conversion.
--      Una fila por episodio — 'recibido' (lead que entra al divisor),
--      'cierre' (incluye los anulados, MARCADOS, con aporte 0) y 'operacion'
--      (cartera elegible, maxima una por cliente/mes). Interna, sin EXECUTE
--      para nadie.
--   2. `private.conversion_mensual_por_vendedor` se REDEFINE como agrupacion
--      sobre esa base. La aritmetica de agregacion se conserva VERBATIM:
--      el resultado debe ser identico fila a fila y byte a byte (prueba de
--      paridad en scripts/test-conversion-episodios.sql; foto antes/despues
--      sobre datos reales en el guion de aplicacion).
--
-- QUE NO CAMBIA: ningun numero de produccion. Los consumidores
-- (`crm.conversion_mensual_sin_cartera_fn`, `crm.conversion_mensual_fn`,
-- `crm.cumplimiento_metas_fn`, cierre de mes, alertas) no se tocan y heredan.
-- La anulacion post-sello sigue descontandose en la LECTURA
-- (`ajuste_pendiente_por_vendedor`), no aqui: en el nucleo se descontaria
-- dos veces.
--
-- p_periodo EXPLICITO (nuevo): desancla el mes de p_ini. El nucleo le pasa
-- su mes derivado (comportamiento identico al vivo); un rango libre (45 dias,
-- semana) pasara su propio periodo o NULL para omitir la pierna de cartera.
-- Eso habilita F2 sin reescribir la base.

-- ---------------------------------------------------------------------------
-- 0. Preflight: solo se reescribe lo que corre VIVO (md5 capturados de prod
--    el 2026-08-26). Si algo se movio, NADA queda aplicado.
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'conversion_mensual_por_vendedor'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric')
     is distinct from '49601295f0ce72a9ec7d795fc014a60e' then
    raise exception 'conversion_mensual_por_vendedor vivo NO es el esperado; re-capturar antes de F1';
  end if;

  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'cierre_externo_anulado'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid')
     is distinct from '25764138a845f5f72e1eeb1d4fdd8ff5' then
    raise exception 'cierre_externo_anulado vivo NO es el esperado; re-capturar antes de F1';
  end if;

  if exists (select 1 from pg_catalog.pg_proc p
              join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'private' and p.proname = 'conversion_episodios') then
    raise exception 'private.conversion_episodios ya existe; F1 no es re-ejecutable a ciegas';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La tabla-base: private.conversion_episodios
-- ---------------------------------------------------------------------------
create function private.conversion_episodios(
  p_ini timestamptz,
  p_fin timestamptz,
  p_periodo date,
  p_global boolean,
  p_visibles uuid[],
  p_factor numeric
)
returns table (
  tipo text,
  analista_id uuid,
  lead_id uuid,
  operacion_id uuid,
  fue_referido boolean,
  aproximado boolean,
  motivo text,
  anulado boolean,
  origen text,
  categoria text,
  mes_origen date,
  monto numeric,
  moneda text,
  fecha_divisor timestamptz,
  fecha_numerador timestamptz,
  aporte_divisor integer,
  aporte_numerador numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
return query
-- Pierna RECIBIDO: un episodio por (analista, lead) con asignacion en la
-- ventana. El origen/motivo son los del PRIMER episodio dentro de la ventana
-- (semantica viva del nucleo); `aproximado` si algun episodio lo fue.
select
  'recibido'::text,
  r.analista_id,
  r.lead_id,
  null::uuid,
  r.fue_referido,
  r.aproximado,
  r.motivo,
  false,
  r.origen_primero,
  null::text,
  null::date,
  null::numeric,
  null::text,
  r.primera_asignacion,
  null::timestamptz,
  case when r.fue_referido then 0 else 1 end,
  0::numeric
from (
  select
    la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] as origen_primero,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado,
    min(la.asignado_en) as primera_asignacion
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
) r

union all

-- Pierna CIERRE: una fila por asignacion convertida con resultado en la
-- ventana. Los cierres ANULADOS (ambos canales, via cierre_externo_anulado)
-- VIAJAN marcados con aporte 0: el nucleo los filtra; Distribucion (F2)
-- podra contarlos sin recalcular nada. El origen aqui es el del EPISODIO
-- (no el primero): semantica viva del nucleo.
select
  'cierre'::text,
  c.analista_id,
  c.lead_id,
  null::uuid,
  c.fue_referido,
  null::boolean,
  null::text,
  c.anulado,
  c.origen,
  null::text,
  c.mes_origen,
  null::numeric,
  null::text,
  null::timestamptz,
  c.fecha_cierre,
  0,
  case when c.anulado then 0
       when c.fue_referido then p_factor
       else 1 end
from (
  select
    la.analista_id, la.lead_id,
    (la.origen = 'referido') as fue_referido,
    la.origen,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    coalesce(la.resultado_en, la.finalizado_en) as fecha_cierre,
    private.cierre_externo_anulado(la.lead_id) as anulado
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
) c

union all

-- Pierna OPERACION: cartera elegible del periodo, MAXIMO UNA por cliente/mes
-- (la primera por fecha_operacion, creado_en, id — criterio vivo). El orden
-- se calcula ANTES del filtro de visibles (semantica viva). Con p_periodo
-- NULL la pierna queda vacia: los rangos libres no tienen mes de cartera.
select
  'operacion'::text,
  o.vendedor_id,
  null::uuid,
  o.id,
  false,
  null::boolean,
  null::text,
  false,
  null::text,
  o.tipo,
  o.periodo,
  -- monto NULL a proposito (Codex P8): sumar capitales seria aritmetica que
  -- el nucleo vivo jamas ejecuto; nadie la consume en F1. F2 decidira su forma.
  null::numeric,
  o.moneda,
  null::timestamptz,
  (o.fecha_operacion::timestamp at time zone 'America/Lima'),
  0,
  1::numeric
from (
  select o0.*,
    row_number() over (
      partition by o0.cliente_id, o0.periodo
      order by o0.fecha_operacion, o0.creado_en, o0.id
    ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.periodo = p_periodo
    and o0.elegible_conversion
) o
where p_periodo is not null
  and o.orden_conversion = 1
  and (p_global or o.vendedor_id = any(p_visibles));
end;
$function$;

comment on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric) is
  'Tabla-base de la conversion unica (F1): una fila por episodio — recibido (aporte_divisor 1 salvo referidos), cierre (anulados MARCADOS con aporte 0; referidos ya ponderados con p_factor) y operacion de cartera (max 1 por cliente/mes). Toda pantalla de conversion debe ser una agrupacion sobre esta relacion; nadie mas cuenta cierres.';

revoke all on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. El nucleo, redefinido como agrupacion sobre la tabla-base.
--    La aritmetica de agregacion es VERBATIM la viva; solo cambian las
--    fuentes de las CTE base (antes: lecturas directas del ledger).
-- ---------------------------------------------------------------------------
create or replace function private.conversion_mensual_por_vendedor(
  p_ini timestamptz,
  p_fin timestamptz,
  p_global boolean,
  p_visibles uuid[],
  p_factor numeric
)
returns table (
  analista_id uuid,
  divisor integer,
  divisor_aproximado integer,
  divisor_por_motivo jsonb,
  cierres_no_referidos integer,
  cierres_referidos integer,
  cierres_de_arrastre integer,
  numerador numeric,
  conversion_pct numeric,
  procedencia jsonb,
  referidos_recibidos integer,
  referidos_aporta_pct numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
return query
with ep as (
  select e.* from private.conversion_episodios(
    p_ini, p_fin,
    date_trunc('month', p_ini at time zone 'America/Lima')::date,
    p_global, p_visibles, p_factor
  ) e
), recibidos as (
  select e.analista_id, e.lead_id, e.fue_referido, e.motivo, e.aproximado
  from ep e where e.tipo = 'recibido'
), cierres as (
  select e.analista_id, e.lead_id, e.fue_referido, e.mes_origen,
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from ep e where e.tipo = 'cierre' and not e.anulado
), motivos as (
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r where not r.fue_referido
  group by r.analista_id, r.motivo
), motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m group by m.analista_id
), agg_div as (
  select r.analista_id,
    count(*) filter (where not r.fue_referido)::int as divisor,
    count(*) filter (where r.aproximado and not r.fue_referido)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r group by r.analista_id
), agg_cie as (
  select c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c group by c.analista_id
), agg_ops as (
  select e.analista_id, count(*)::int as conversiones_clientes
  from ep e where e.tipo = 'operacion'
  group by e.analista_id
), proc as (
  select c.analista_id, c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select c0.analista_id, c0.lead_id, c0.fue_referido,
      case when
        (extract(year from p_ini at time zone 'America/Lima')::int * 12
         + extract(month from p_ini at time zone 'America/Lima')::int)
        - (extract(year from c0.mes_origen)::int * 12
           + extract(month from c0.mes_origen)::int) <= 11
      then c0.mes_origen end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
), proc_json as (
  select p.analista_id,
    jsonb_agg(jsonb_build_object(
      'mes', case when p.mes_cubo is not null then to_char(p.mes_cubo, 'YYYY-MM') end,
      'mes_nombre', case when p.mes_cubo is not null
        then private.etiqueta_mes_es(p.mes_cubo) else 'anteriores' end,
      'anio', case when p.mes_cubo is not null then extract(year from p.mes_cubo)::int end,
      'cierres', p.cierres, 'cierres_referidos', p.cierres_referidos
    ) order by p.mes_cubo desc nulls last) as procedencia
  from proc p group by p.analista_id
)
select
  coalesce(d.analista_id, c.analista_id, o.analista_id),
  coalesce(d.divisor, 0),
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  (coalesce(c.cierres_no_referidos, 0)
   + p_factor * coalesce(c.cierres_referidos, 0)
   + coalesce(o.conversiones_clientes, 0))::numeric,
  case when coalesce(d.divisor, 0) > 0 then round(
    100.0 * (coalesce(c.cierres_no_referidos, 0)
      + p_factor * coalesce(c.cierres_referidos, 0)
      + coalesce(o.conversiones_clientes, 0)) / d.divisor, 2)
  end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when coalesce(d.divisor, 0) > 0 then
    round(100.0 * p_factor * coalesce(c.cierres_referidos, 0) / d.divisor, 2)
  end
from agg_div d
full outer join agg_cie c on c.analista_id = d.analista_id
full outer join agg_ops o on o.analista_id = coalesce(d.analista_id, c.analista_id)
left join motivos_json mj on mj.analista_id = d.analista_id
left join proc_json pj on pj.analista_id = coalesce(d.analista_id, c.analista_id, o.analista_id);
end;
$function$;

comment on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric) is
  'Núcleo único: divisor solo leads no referidos recibidos; numerador = cierres de lead ponderados + máximo una operación elegible de cartera por cliente/mes. Renovación/adicional nunca alteran el divisor. Desde F1 es una agrupación sobre private.conversion_episodios (la tabla-base): la aritmética vive UNA sola vez.';

-- ---------------------------------------------------------------------------
-- 3. Postflight estructural (misma transaccion; si algo no cuadra, rollback).
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_src text;
  v_acl aclitem[];
  v_owner oid;
begin
  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'conversion_mensual_por_vendedor';

  if strpos(v_src, 'conversion_episodios') = 0 then
    raise exception 'el nucleo no consume conversion_episodios; rollback';
  end if;
  if strpos(v_src, 'crm.lead_asignaciones') > 0
     or strpos(v_src, 'crm.operaciones_cartera') > 0 then
    raise exception 'el nucleo sigue leyendo el ledger directo; rollback';
  end if;

  select p.proacl, p.proowner into v_acl, v_owner
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'conversion_episodios';
  if v_acl is null or exists (
    select 1 from pg_catalog.aclexplode(v_acl) a
     where a.grantee <> v_owner
  ) then
    raise exception 'conversion_episodios con EXECUTE fuera del owner; rollback';
  end if;

  if (select p.proowner from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'conversion_episodios')
     is distinct from
     (select p.proowner from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'conversion_mensual_por_vendedor') then
    -- Codex P8: dos DEFINER con owners distintos correrian con identidades
    -- distintas; el ejecutor de la migracion debe ser el owner del nucleo.
    raise exception 'conversion_episodios y el nucleo tienen owners distintos; rollback';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private' and p.proname = 'conversion_episodios'
       and p.prosecdef
       and p.proconfig @> array['search_path=""']::text[]
  ) then
    -- proconfig guarda search_path="" con comillas (leccion RETOMAR-53)
    raise exception 'conversion_episodios sin definer/search_path esperados; rollback';
  end if;
end;
$postflight$;
