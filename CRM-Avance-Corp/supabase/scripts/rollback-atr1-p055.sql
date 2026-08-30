-- MARCHA ATRAS de P-055 ATR-1 (el upgrade cuenta a quien lo hace).
-- Repone los cuerpos ORIGINALES (literales de maquina, capturados del prosrc
-- VIVO el 30/08 antes de tocar nada) y retira el resolutor. Idempotente.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- 0) PREFLIGHT (auditoria Codex P1-3): esta marcha atras SOLO pisa lo que
--    ATR-1 dejo. Si un hotfix posterior movio cualquiera de los dos nucleos,
--    esto ABORTA en vez de sobrescribirlo en silencio — se re-genera el
--    rollback desde el estado vivo, jamas se pisa a ciegas.
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure;
  if v_h is distinct from '71213ac03eb32e333723399538d35d83' then
    raise exception 'rollback ATR-1: conversion_episodios NO esta en el estado ATR-1 (huella %) — regenerar el rollback, no pisar', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure;
  if v_h is distinct from 'f968879ae7f354a4165f1aebedc685b9' then
    raise exception 'rollback ATR-1: metricas_cartera_por_vendedor NO esta en el estado ATR-1 (huella %) — regenerar el rollback, no pisar', v_h;
  end if;
end $$;

-- 1) Los dos nucleos, de vuelta al byte:
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION private.metricas_cartera_por_vendedor(p_periodo date)
 RETURNS TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
      e.analista_id as vendedor_id,
      e.categoria
    from private.conversion_episodios(
      p_ini => p_periodo::timestamp at time zone 'America/Lima',
      p_fin => (p_periodo + interval '1 month')::timestamp
        at time zone 'America/Lima',
      p_periodo => p_periodo,
      p_global => true,
      p_visibles => '{}'::uuid[],
      p_factor => 0::numeric
    ) e
    where e.tipo = 'operacion'
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (
        where e.categoria = 'renovacion'
      )::int as conversiones_renovacion,
      count(*) filter (
        where e.categoria = 'upgrade'
      )::int as conversiones_upgrade
    from episodios_conversion e
    group by e.vendedor_id
  ), dinero as (
    -- El desglose renovado/adicional, del NUCLEO de capital (pierna desglose,
    -- solo renovaciones: los upgrades no llevan desglose por diseno).
    select
      k.analista_id as vendedor_id,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'PEN'), 0)
        as capital_renovado_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'USD'), 0)
        as capital_renovado_usd,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'PEN'), 0)
        as capital_adicional_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'USD'), 0)
        as capital_adicional_usd
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) k
    where k.tipo like 'desglose_%' and k.categoria = 'renovacion'
      and k.mes_comercial = p_periodo
    group by k.analista_id
  ), economia as (
    select
      o.vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int
        as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int
        as operaciones_upgrade,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo
      )::int as renovaciones_sin_desglose
    from ops o
    group by o.vendedor_id
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
    union
    select d.vendedor_id from dinero d
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(d.capital_renovado_pen, 0),
    coalesce(d.capital_renovado_usd, 0),
    coalesce(d.capital_adicional_pen, 0),
    coalesce(d.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join dinero d using (vendedor_id)
  left join economia e using (vendedor_id)
$function$
;

-- 2) El resolutor, fuera — pero SOLO si de verdad nadie lo nombra ya (auditoria
--    RLS P2-5: Postgres no rastrea dependencias de prosrc; un drop a ciegas
--    dejaria roto en runtime a un llamador nacido despues del publish).
--    strpos y no LIKE: el guion bajo es comodin.
do $$
declare v_n integer;
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema')
     and strpos(p.prosrc, 'analista_atribuido_cadena') > 0;
  if v_n <> 0 then
    raise exception 'rollback ATR-1: % funciones aun nombran al resolutor — re-apuntarlas antes de retirarlo', v_n;
  end if;
end $$;
drop function if exists private.analista_atribuido_cadena(uuid);

-- 3) POSTFLIGHT de la marcha atras: huellas ORIGINALES al byte + guardianes.
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure;
  if v_h is distinct from '34acbfa8f6838b5f0ca6d5aa17d85d2a' then
    raise exception 'rollback ATR-1: conversion_episodios no volvio al byte (huella %)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure;
  if v_h is distinct from 'eeebe4e1385263dbdb6f3fdda81b1b93' then
    raise exception 'rollback ATR-1: metricas_cartera_por_vendedor no volvio al byte (huella %)', v_h;
  end if;
  if to_regprocedure('private.analista_atribuido_cadena(uuid)') is not null then
    raise exception 'rollback ATR-1: el resolutor sigue vivo';
  end if;
  foreach v_h in array array[
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
    'private.metricas_cartera_por_vendedor(date)'
  ] loop
    if (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure)
       is distinct from '{postgres=X/postgres}' then
      raise exception 'rollback ATR-1: proacl de % no es el original (%)', v_h,
        (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure);
    end if;
  end loop;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
