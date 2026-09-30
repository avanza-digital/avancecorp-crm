-- Registrador fail-closed de 20260930221500_crm_conversion_coordinacion_desglose_cierres.
-- Ejecutar inmediatamente después de la migración por la misma vía
-- (`db query --linked --file`). Registra el cuerpo literal del archivo y
-- rechaza una versión previa que no coincida.

begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $registrar_conversion_desglose$
declare
  v_base regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_base(date,date)');
  v_nucleo regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date,date)');
  v_totales regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date,date)');
  v_puerta regprocedure := pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)');
  v_cuerpo text := $migracion_20260930221500$-- ============================================================================
-- CRM · Conversión de Coordinación: de dónde salen los cierres (referidos,
-- upgrade, renovación) — segunda entrega de la pestaña «Conversiones»
--
-- Por qué. La primera entrega (`20260930185623`, en prod el 30/09) enseña por
-- analista las llegadas (divisor, formulario y landing), el numerador NETO y el
-- porcentaje. Miguel pidió abrir el numerador: cuántos cierres vienen de
-- formulario, landing y referido (y cuánto pesa el referido), cuántos de oficina
-- (no pesan) y cuántas operaciones de cartera (upgrade pesa 1; renovación pesa
-- lo que diga `crm.conversion_pesos`). Todo sale de los MISMOS episodios del
-- núcleo (`private.conversion_episodios`, tipos `cierre` y `operacion`) que ya
-- suman el numerador: aquí solo se agrupan, no se define nada nuevo.
--
-- Y además (mismo pedido de Miguel, 30/09): consultar por RANGO de fechas, no
-- solo por mes. Precedente de la casa: `crm.metricas_conversiones_equipo_fn`
-- (rango inclusivo en Lima, hasta 366 días, sin fechas futuras; un rango que es
-- exactamente un mes calendario se trata como ese mes). En modo rango las cifras
-- se calculan EN VIVO con `private.conversion_mensual_por_vendedor(v_ini, v_fin)`
-- (numerador bruto; los ajustes de meses pagados y las fotos de cierre son
-- conceptos de mes y no aplican), el peso del referido es el del mes de `hasta`
-- (como en la puerta de Gerencia) y el de renovación lo aplica el núcleo por el
-- mes de cada operación.
--
-- Qué cambia. Las tres funciones de la primera entrega se REDEFINEN con más
-- columnas/claves y con firma (desde, hasta) — DROP + CREATE porque cambian tipo
-- de retorno y firma — y aparece un núcleo pequeño, `conversion_divisor_base`,
-- que elige la pieza del núcleo según el modo. El preflight acredita por md5 que
-- los cuerpos vivos son exactamente los publicados el 30/09; si alguien los
-- tocó, esta migración se niega. Contrato de la puerta: aditivo en claves
-- (`version` sigue en 1; el front usa `v.object`, no estricto) salvo `periodo`,
-- que ahora lleva `modo`, `dias` y `hasta` INCLUSIVO (antes era el primer día
-- del mes siguiente); el único consumidor es la pestaña nueva, que se publica
-- con esta migración.
--   * Por analista y para la empresa: `numerador_bruto`, `ajuste_pendiente`,
--     `cierres {formulario, landing, referido, referido_aporte, oficina}`,
--     `cartera {upgrade, renovacion, renovacion_aporte}`, `desglose_disponible`.
--   * Arriba: `peso_renovacion` junto a `peso_referido`; `periodo.modo` ('mes' |
--     'rango'), `periodo.dias`, `periodo.mes*` en null cuando es rango.
--   * Puerta: `crm.conversion_divisor_coordinacion_fn(p_periodo, p_desde, p_hasta)`;
--     sin argumentos = mes vigente; `p_desde`+`p_hasta` = rango (o mes exacto).
--   * Invariante (mes abierto): numerador_bruto = formulario + landing +
--     referido_aporte + upgrade + renovacion_aporte, y numerador (neto) =
--     private.conversion_con_ajuste(numerador_bruto, ajuste_pendiente).
--   * Mes SELLADO: los conteos salen de la foto (`origenes_ranking.filas` y
--     `cartera` de `crm.cierre_mes_vendedor`); los aportes se leen con los pesos
--     sellados; `numerador_bruto`/`ajuste_pendiente` van en null (la foto guarda
--     el neto) y `desglose_disponible` dice si la foto trae el desglose.
--
-- Lo que NO toca: el núcleo de conversión y sus pesos, el reporte de entregas,
-- los conteos por dueño actual y las puertas de conversión existentes.
--
-- Reversa: `drop` de las cuatro funciones de esta migración (puerta (date,date,date),
-- totales (date,date), empresa (date,date), base (date,date)), volver a aplicar
-- los tres `create function` de `20260930185623` y borrar esta versión del registro.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
declare
  v_huellas jsonb := '{
    "crm.conversion_divisor_coordinacion_fn(date)": "4c73a85e9204b0c6b301005e8265aa62",
    "private.conversion_divisor_empresa(date)": "c62acbc0b5dad719babb59a2ac716464",
    "private.conversion_divisor_empresa_totales(date)": "9b65271ae4ff5a5c9c28c33e59200f3b"
  }'::jsonb;
  v_firma text;
  v_md5 text;
  v_viva text;
begin
  -- Una función viva no se reteclea sin acreditar su cuerpo: las tres deben ser
  -- EXACTAMENTE las publicadas el 30/09/2026 (huellas md5 de prosrc).
  for v_firma, v_md5 in select key, value #>> '{}' from pg_catalog.jsonb_each(v_huellas) loop
    select md5(p.prosrc) into v_viva from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure(v_firma);
    if v_viva is null then
      raise exception 'PREFLIGHT: falta % (no está la primera entrega 20260930185623)', v_firma;
    end if;
    if v_viva <> v_md5 then
      raise exception 'PREFLIGHT: % no es el cuerpo publicado el 30/09 (md5 % ≠ %)', v_firma, v_viva, v_md5;
    end if;
  end loop;
  if pg_catalog.to_regprocedure('private.conversion_con_ajuste(numeric,numeric)') is null
     or pg_catalog.to_regprocedure('private.peso_renovacion_conversion(date)') is null then
    raise exception 'PREFLIGHT: faltan private.conversion_con_ajuste o private.peso_renovacion_conversion';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'crm.cierre_mes_vendedor'::regclass and a.attname in ('cartera', 'origenes_ranking') and not a.attisdropped
    having count(*) = 2
  ) then
    raise exception 'PREFLIGHT: crm.cierre_mes_vendedor debe tener cartera y origenes_ranking';
  end if;
  if pg_catalog.to_regprocedure('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)') is null then
    raise exception 'PREFLIGHT: falta private.conversion_mensual_por_vendedor (pieza del modo rango)';
  end if;
  if pg_catalog.to_regprocedure('private.conversion_divisor_base(date,date)') is not null
     or pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date,date)') is not null
     or pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date,date)') is not null
     or pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)') is not null then
    raise exception 'PREFLIGHT: las firmas nuevas ya existen; esta migración no las redefine';
  end if;
end;
$preflight$;

drop function crm.conversion_divisor_coordinacion_fn(date);
drop function private.conversion_divisor_empresa_totales(date);
drop function private.conversion_divisor_empresa(date);

-- ----------------------------------------------------------------------------
-- Núcleo: la pieza del núcleo que corresponde al modo. Un mes calendario
-- exacto y ABIERTO usa la pieza mensual neta (la de Metas: bruto, ajuste de
-- meses pagados y neto). Cualquier otro rango usa la pieza por rango en vivo
-- (bruto = neto: el ajuste es un concepto de mes). Los meses sellados los
-- resuelve `conversion_divisor_empresa` antes de llegar aquí.
-- ----------------------------------------------------------------------------
create function private.conversion_divisor_base(p_desde date, p_hasta date)
returns table (
  analista_id uuid,
  en_nucleo boolean,
  divisor integer,
  numerador_bruto numeric,
  ajuste_pendiente numeric,
  numerador numeric,
  conversion_pct numeric,
  cierres_no_referidos integer,
  cierres_referidos integer
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_ini timestamptz := p_desde::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_es_mes boolean := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  if v_es_mes then
    return query
    select n.analista_id, n.en_nucleo, n.divisor,
           coalesce(n.numerador_bruto, 0::numeric), coalesce(n.ajuste_pendiente, 0::numeric),
           n.numerador, n.conversion_pct, n.cierres_no_referidos, n.cierres_referidos
    from private.conversion_neta_por_vendedor(p_desde, true, null::uuid[]) n;
  else
    -- Rango libre: en vivo, con el peso del referido del mes de `hasta` (como la
    -- puerta de Gerencia) y sin ajustes de meses pagados.
    return query
    select cm.analista_id, true, cm.divisor,
           coalesce(cm.numerador, 0::numeric), 0::numeric,
           coalesce(cm.numerador, 0::numeric), cm.conversion_pct, cm.cierres_no_referidos, cm.cierres_referidos
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, null::uuid[],
      private.peso_referido_conversion(pg_catalog.date_trunc('month', p_hasta)::date)) cm;
  end if;
end;
$function$;

comment on function private.conversion_divisor_base(date, date) is
  'Núcleo (30/09/2026): elige la pieza del núcleo de conversión según el modo. Mes calendario exacto → private.conversion_neta_por_vendedor (bruto, ajuste de meses pagados, neto; la misma pieza que Metas). Rango libre → private.conversion_mensual_por_vendedor en vivo (bruto = neto), peso del referido del mes de hasta. No mira meses sellados: eso lo hace quien la llama. Sin autorización dentro y sin ejecutores de la API.';

revoke all on function private.conversion_divisor_base(date, date)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Núcleo: una fila por analista, con el desglose de los cierres. Mes o rango.
-- ----------------------------------------------------------------------------
create function private.conversion_divisor_empresa(p_desde date, p_hasta date)
returns table (
  analista_id uuid,
  nombre text,
  supervisor_id uuid,
  supervisor_nombre text,
  en_nucleo boolean,
  divisor integer,
  divisor_formulario integer,
  divisor_landing integer,
  numerador numeric,
  conversion_pct numeric,
  numerador_bruto numeric,
  ajuste_pendiente numeric,
  cierres_formulario integer,
  cierres_landing integer,
  cierres_referido integer,
  cierres_referido_aporte numeric,
  cierres_oficina integer,
  cierres_otros integer,
  upgrade integer,
  renovacion integer,
  renovacion_aporte numeric,
  desglose_disponible boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_es_mes boolean;
  v_mes date;
  v_cierre crm.periodos_cerrados%rowtype;
  v_peso_renovacion numeric;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_es_mes := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_mes := pg_catalog.date_trunc('month', p_hasta)::date;

  if v_es_mes then
    select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_desde;
  end if;

  -- Mes SELLADO: la foto por persona tal cual se selló. El desglose de cierres
  -- sale de lo que la foto guarda (origenes_ranking.filas y cartera) con los
  -- pesos sellados; el desglose por origen de las llegadas no está en la foto.
  if v_cierre.periodo is not null then
    v_peso_renovacion := coalesce(
      v_cierre.ponderacion_renovacion,
      case when v_cierre.cobertura ->> 'modelo_conversion' = 'llegadas_v2'
        then v_cierre.ponderacion_referido else 1 end);
    return query
    with foto as (
      select f.*,
        coalesce((f.origenes_ranking ->> 'disponible')::boolean, false)
          and f.cartera ? 'conversiones_upgrade' and f.cartera ? 'conversiones_renovacion' as con_desglose
      from crm.cierre_mes_vendedor f
      where f.periodo = p_desde
    ),
    por_origen as (
      select f.vendedor_id,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'formulario')::integer as formulario,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'landing')::integer as landing,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'referido')::integer as referido,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'oficina')::integer as oficina,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' not in ('formulario', 'landing', 'referido', 'oficina', 'ajuste'))::integer as otros
      from foto f
      cross join lateral pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(f.origenes_ranking -> 'filas') = 'array'
          then f.origenes_ranking -> 'filas' else '[]'::jsonb end) as o(fila)
      where f.con_desglose
      group by f.vendedor_id
    )
    select f.vendedor_id,
           f.nombre_completo,
           f.supervisor_id,
           f.supervisor_nombre,
           true,
           f.divisor,
           null::integer,
           null::integer,
           f.numerador,
           f.conversion_pct,
           null::numeric,
           null::numeric,
           case when f.con_desglose then coalesce(o.formulario, 0) end,
           case when f.con_desglose then coalesce(o.landing, 0) end,
           case when f.con_desglose then coalesce(o.referido, 0) end,
           case when f.con_desglose then coalesce(o.referido, 0) * v_cierre.ponderacion_referido end,
           case when f.con_desglose then coalesce(o.oficina, 0) end,
           case when f.con_desglose then coalesce(o.otros, 0) end,
           -- `conversiones_*` (primera operación ELEGIBLE por cliente y mes) es lo que
           -- suma el numerador; `operaciones_*` cuenta todas y NO sirve aquí.
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_upgrade')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) * v_peso_renovacion end,
           f.con_desglose
    from foto f
    left join por_origen o on o.vendedor_id = f.vendedor_id
    order by f.nombre_completo;
    return;
  end if;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(v_mes);

  return query
  with base as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del núcleo según el modo (ver
    -- conversion_divisor_base): la misma que usa Metas para un mes, la de rango
    -- en vivo para cualquier otro tramo.
    select b.* from private.conversion_divisor_base(p_desde, p_hasta) b
  ),
  episodios as materialized (
    -- Mes exacto: p_periodo = ese mes (peso de renovación del período). Rango:
    -- p_periodo nulo, el núcleo pondera cada operación por su propio mes.
    select e.*
    from private.conversion_episodios(v_ini, v_fin, case when v_es_mes then p_desde end, true, null::uuid[], v_factor) e
  ),
  por_origen as materialized (
    -- El mismo aporte que suma el divisor, abierto por el origen del lead. Referido
    -- y alta manual aportan 0 en el núcleo, así que aquí tampoco pesan.
    select e.analista_id,
           (sum(e.aporte_divisor) filter (where e.origen = 'formulario'))::integer as divisor_formulario,
           (sum(e.aporte_divisor) filter (where e.origen = 'landing'))::integer as divisor_landing
    from episodios e
    where e.tipo = 'recibido'
    group by e.analista_id
  ),
  cierres as materialized (
    -- De dónde salen los cierres: los MISMOS episodios que suman el numerador,
    -- agrupados. Formulario y landing aportan 1 por cierre; referido, su peso;
    -- oficina no pesa; upgrade aporta 1 y renovación su propio peso.
    select e.analista_id,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'formulario'))::integer as cierres_formulario,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'landing'))::integer as cierres_landing,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'referido'))::integer as cierres_referido,
           coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.origen = 'referido'), 0::numeric) as cierres_referido_aporte,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'oficina'))::integer as cierres_oficina,
           -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.
           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina')))::integer as cierres_otros,
           (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'upgrade'))::integer as upgrade,
           (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'))::integer as renovacion,
           coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'), 0::numeric) as renovacion_aporte
    from episodios e
    where e.tipo in ('cierre', 'operacion') and not e.anulado
    group by e.analista_id
  ),
  roster as materialized (
    -- El supervisor del MES de `hasta` (roster de metas de ese período), no el
    -- de hoy. Una fila por analista aunque el roster trajera repetidos.
    select distinct on (r.vendedor_id) r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(v_mes, true, null::uuid[]) r
    order by r.vendedor_id, r.supervisor_id nulls last
  )
  select b.analista_id,
         perfil.nombre_completo,
         case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end,
         jefe.nombre_completo,
         b.en_nucleo,
         b.divisor,
         coalesce(o.divisor_formulario, 0),
         coalesce(o.divisor_landing, 0),
         b.numerador,
         b.conversion_pct,
         b.numerador_bruto,
         b.ajuste_pendiente,
         coalesce(c.cierres_formulario, 0),
         coalesce(c.cierres_landing, 0),
         coalesce(c.cierres_referido, 0),
         coalesce(c.cierres_referido_aporte, 0::numeric),
         coalesce(c.cierres_oficina, 0),
         coalesce(c.cierres_otros, 0),
         coalesce(c.upgrade, 0),
         coalesce(c.renovacion, 0),
         coalesce(c.renovacion_aporte, 0::numeric),
         true
  from base b
  left join por_origen o on o.analista_id is not distinct from b.analista_id
  left join cierres c on c.analista_id is not distinct from b.analista_id
  left join roster r on r.vendedor_id = b.analista_id
  left join crm.equipo equipo on equipo.perfil_id = b.analista_id
  left join public.perfiles perfil on perfil.id = b.analista_id
  left join public.perfiles jefe
    on jefe.id = case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end
  order by perfil.nombre_completo nulls last;
end;
$function$;

comment on function private.conversion_divisor_empresa(date, date) is
  'Núcleo (30/09/2026, v2 con desglose y rango): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Un mes calendario exacto usa la pieza mensual neta (Metas) y, si está sellado, la foto (crm.cierre_mes_vendedor: origenes_ranking y cartera) sin recalcular; cualquier otro rango se calcula en vivo (bruto = neto). Agrupa los episodios de private.conversion_episodios: llegadas por origen (divisor), cierres por origen (formulario, landing, referido con su aporte, oficina sin peso) y cartera (upgrade, renovación con su aporte). numerador_bruto = partes. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API.';

revoke all on function private.conversion_divisor_empresa(date, date)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Núcleo: el total de la empresa y la producción sin analista. Mes o rango.
-- ----------------------------------------------------------------------------
create function private.conversion_divisor_empresa_totales(p_desde date, p_hasta date)
returns table (
  sellado boolean,
  peso_referido numeric,
  peso_renovacion numeric,
  divisor integer,
  numerador numeric,
  conversion_pct numeric,
  divisor_formulario integer,
  divisor_landing integer,
  numerador_bruto numeric,
  ajuste_pendiente numeric,
  cierres_formulario integer,
  cierres_landing integer,
  cierres_referido integer,
  cierres_referido_aporte numeric,
  cierres_oficina integer,
  cierres_otros integer,
  upgrade integer,
  renovacion integer,
  renovacion_aporte numeric,
  desglose_disponible boolean,
  cruza_sellados boolean,
  sin_analista_presente boolean,
  sin_analista_divisor integer,
  sin_analista_numerador numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_cierre crm.periodos_cerrados%rowtype;
  v_es_mes boolean;
  v_mes date;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_es_mes := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_mes := pg_catalog.date_trunc('month', p_hasta)::date;
  if v_es_mes then
    select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_desde;
  end if;

  return query
  with filas as materialized (
    select f.* from private.conversion_divisor_empresa(p_desde, p_hasta) f
  ),
  fuera_foto as materialized (
    -- Mes sellado: la producción congelada fuera del ranking y la que no tuvo
    -- analista se suman al total de la empresa, igual que en la puerta mensual.
    -- Solo un OBJETO cuenta; un JSON null o la ausencia de la clave es ausencia.
    select e.value as fila
    from pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'fuera_ranking') = 'array'
        then v_cierre.cobertura -> 'fuera_ranking' else '[]'::jsonb end
    ) e
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(e.value -> 'conversion') = 'object'
    union all
    select pg_catalog.jsonb_build_object('conversion', v_cierre.cobertura -> 'conversion_sin_analista')
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'conversion_sin_analista') = 'object'
  ),
  suma as (
    select
      (coalesce(sum(f.divisor), 0)
        + coalesce((select sum((x.fila #>> '{conversion,divisor}')::integer) from fuera_foto x), 0))::integer as divisor,
      (coalesce(sum(f.numerador), 0::numeric)
        + coalesce((select sum((x.fila #>> '{conversion,numerador}')::numeric) from fuera_foto x), 0::numeric)) as numerador,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_formulario), 0)::integer end as divisor_formulario,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_landing), 0)::integer end as divisor_landing,
      case when v_cierre.periodo is null then coalesce(sum(f.numerador_bruto), 0::numeric) end as numerador_bruto,
      case when v_cierre.periodo is null then coalesce(sum(f.ajuste_pendiente), 0::numeric) end as ajuste_pendiente,
      -- Desglose de la empresa: suma de las filas con desglose. En un mes sellado
      -- solo si TODAS las filas de la foto lo traen Y el total no incluye producción
      -- congelada fuera de las filas (fuera_ranking / sin analista), que no tiene
      -- desglose: si no, la suma de partes no sería la del numerador.
      coalesce(bool_and(f.desglose_disponible), v_cierre.periodo is null)
        and (v_cierre.periodo is null or not exists (select 1 from fuera_foto)) as desglose_disponible,
      coalesce(sum(f.cierres_formulario), 0)::integer as cierres_formulario,
      coalesce(sum(f.cierres_landing), 0)::integer as cierres_landing,
      coalesce(sum(f.cierres_referido), 0)::integer as cierres_referido,
      coalesce(sum(f.cierres_referido_aporte), 0::numeric) as cierres_referido_aporte,
      coalesce(sum(f.cierres_oficina), 0)::integer as cierres_oficina,
      coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,
      coalesce(sum(f.upgrade), 0)::integer as upgrade,
      coalesce(sum(f.renovacion), 0)::integer as renovacion,
      coalesce(sum(f.renovacion_aporte), 0::numeric) as renovacion_aporte
    from filas f
  ),
  sin_analista as (
    select true as presente, f.divisor, f.numerador
    from filas f
    where v_cierre.periodo is null and f.analista_id is null
    union all
    select true,
      (v_cierre.cobertura #>> '{conversion_sin_analista,divisor}')::integer,
      (v_cierre.cobertura #>> '{conversion_sin_analista,numerador}')::numeric
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'conversion_sin_analista') = 'object'
  )
  select
    v_cierre.periodo is not null,
    coalesce(v_cierre.ponderacion_referido, private.peso_referido_conversion(v_mes)),
    case when v_cierre.periodo is null then private.peso_renovacion_conversion(v_mes)
      else coalesce(v_cierre.ponderacion_renovacion,
        case when v_cierre.cobertura ->> 'modelo_conversion' = 'llegadas_v2'
          then v_cierre.ponderacion_referido else 1 end) end,
    s.divisor,
    s.numerador,
    case when s.divisor > 0 then pg_catalog.round(100.0 * s.numerador / s.divisor, 2) end,
    s.divisor_formulario,
    s.divisor_landing,
    s.numerador_bruto,
    s.ajuste_pendiente,
    case when s.desglose_disponible then s.cierres_formulario end,
    case when s.desglose_disponible then s.cierres_landing end,
    case when s.desglose_disponible then s.cierres_referido end,
    case when s.desglose_disponible then s.cierres_referido_aporte end,
    case when s.desglose_disponible then s.cierres_oficina end,
    case when s.desglose_disponible then s.cierres_otros end,
    case when s.desglose_disponible then s.upgrade end,
    case when s.desglose_disponible then s.renovacion end,
    case when s.desglose_disponible then s.renovacion_aporte end,
    s.desglose_disponible,
    -- Un rango libre que toca meses ya sellados se calcula EN VIVO (como la puerta
    -- de Gerencia) y puede discrepar de la foto: se declara para que la pantalla avise.
    (not v_es_mes) and exists (
      select 1 from crm.periodos_cerrados pc
      where pc.periodo between pg_catalog.date_trunc('month', p_desde)::date and v_mes
    ),
    coalesce((select sa.presente from sin_analista sa limit 1), false),
    (select sa.divisor from sin_analista sa limit 1),
    (select sa.numerador from sin_analista sa limit 1)
  from suma s;
end;
$function$;

comment on function private.conversion_divisor_empresa_totales(date, date) is
  'Núcleo (30/09/2026, v2 con desglose y rango): total de la empresa y producción sin analista para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Mes abierto o rango: suma de private.conversion_divisor_empresa. Mes sellado: foto por persona + cobertura.fuera_ranking + conversion_sin_analista de crm.periodos_cerrados (solo objetos), la misma suma que la puerta mensual oficial; el desglose solo se sirve si todas las filas de la foto lo traen. Nunca recalcula un mes sellado. Sin autorización dentro y sin ejecutores de la API.';

revoke all on function private.conversion_divisor_empresa_totales(date, date)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Puerta: autoriza (coordinador o gerencia), valida el período y delega.
-- ----------------------------------------------------------------------------
create function crm.conversion_divisor_coordinacion_fn(
  p_periodo date default null,
  p_desde date default null,
  p_hasta date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
  v_es_mes boolean;
  v_totales record;
  v_payload jsonb;
begin
  -- 1) Gate primero: un actor denegado recibe 42501 aunque el período sea inválido.
  --    `is not true`: un NULL del gate también deniega.
  if private.puede_operar_reparto_crm() is not true then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista'
      using errcode = '42501';
  end if;

  -- 2) Validación del período: mes (por defecto el vigente) o rango inclusivo.
  if p_desde is null and p_hasta is null then
    v_desde := coalesce(p_periodo, v_mes_actual);
    if v_desde <> pg_catalog.date_trunc('month', v_desde)::date then
      raise exception 'Periodo invalido: debe ser el primer dia del mes'
        using errcode = '22023';
    end if;
    if v_desde > v_mes_actual then
      raise exception 'Periodo invalido: el mes no puede ser futuro'
        using errcode = '22023';
    end if;
    v_hasta := (v_desde + interval '1 month' - interval '1 day')::date;
  else
    if p_periodo is not null then
      raise exception 'Periodo invalido: indica el mes o el rango, no los dos'
        using errcode = '22023';
    end if;
    if p_desde is null or p_hasta is null then
      raise exception 'Periodo invalido: indica ambas fechas del rango'
        using errcode = '22023';
    end if;
    if p_desde > p_hasta then
      raise exception 'Periodo invalido: la fecha inicial no puede ser posterior a la final'
        using errcode = '22023';
    end if;
    if p_hasta > v_hoy then
      raise exception 'Periodo invalido: el rango no admite fechas futuras'
        using errcode = '22023';
    end if;
    if p_hasta - p_desde > 365 then
      raise exception 'Periodo invalido: el rango maximo es de 366 dias'
        using errcode = '22023';
    end if;
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;
  v_es_mes := v_desde = pg_catalog.date_trunc('month', v_desde)::date
    and v_hasta = (pg_catalog.date_trunc('month', v_desde) + interval '1 month' - interval '1 day')::date;

  -- 3) Delegar: el núcleo decide mes/rango y abierto/sellado; aquí solo se da forma.
  select t.* into strict v_totales from private.conversion_divisor_empresa_totales(v_desde, v_hasta) t;

  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'alcance', 'global',
    'periodo', pg_catalog.jsonb_build_object(
      'modo', case when v_es_mes then 'mes' else 'rango' end,
      'mes', case when v_es_mes then pg_catalog.to_char(v_desde, 'YYYY-MM') end,
      'mes_nombre', case when v_es_mes then private.etiqueta_mes_es(v_desde) end,
      'anio', case when v_es_mes then extract(year from v_desde)::integer end,
      'zona', 'America/Lima',
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', (v_hasta - v_desde) + 1,
      'cruza_meses_sellados', v_totales.cruza_sellados
    ),
    'sellado', v_totales.sellado,
    'peso_referido', v_totales.peso_referido,
    'peso_renovacion', v_totales.peso_renovacion,
    'fuente', pg_catalog.jsonb_build_object(
      'divisor', 'private.conversion_neta_por_vendedor',
      'origen', 'private.conversion_episodios',
      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado',
      -- 'foto' = mes sellado servido de crm.cierre_mes_vendedor; 'mensual' = mes abierto
      -- con la pieza de Metas (bruto, ajuste, neto); 'rango_vivo' = tramo libre calculado
      -- en vivo sin ajustes ni fotos (precedente: crm.metricas_conversiones_equipo_fn).
      'modo', case when v_totales.sellado then 'foto' when v_es_mes then 'mensual' else 'rango_vivo' end
    ),
    'empresa', pg_catalog.jsonb_build_object(
      'divisor', v_totales.divisor,
      'numerador', v_totales.numerador,
      'conversion_pct', v_totales.conversion_pct,
      'divisor_formulario', v_totales.divisor_formulario,
      'divisor_landing', v_totales.divisor_landing,
      'numerador_bruto', v_totales.numerador_bruto,
      'ajuste_pendiente', v_totales.ajuste_pendiente,
      'desglose_disponible', v_totales.desglose_disponible,
      'cierres', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'formulario', v_totales.cierres_formulario,
        'landing', v_totales.cierres_landing,
        'referido', v_totales.cierres_referido,
        'referido_aporte', v_totales.cierres_referido_aporte,
        'oficina', v_totales.cierres_oficina,
        'otros', v_totales.cierres_otros
      ) end,
      'cartera', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'upgrade', v_totales.upgrade,
        'renovacion', v_totales.renovacion,
        'renovacion_aporte', v_totales.renovacion_aporte
      ) end
    ),
    'sin_analista', case when v_totales.sin_analista_presente then pg_catalog.jsonb_build_object(
      'divisor', v_totales.sin_analista_divisor,
      'numerador', v_totales.sin_analista_numerador
    ) end,
    'analistas', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'analista_id', f.analista_id,
          'nombre', f.nombre,
          'supervisor_id', f.supervisor_id,
          'supervisor_nombre', f.supervisor_nombre,
          'en_nucleo', f.en_nucleo,
          'divisor', f.divisor,
          'divisor_formulario', f.divisor_formulario,
          'divisor_landing', f.divisor_landing,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'numerador_bruto', f.numerador_bruto,
          'ajuste_pendiente', f.ajuste_pendiente,
          'desglose_disponible', f.desglose_disponible,
          'cierres', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'formulario', f.cierres_formulario,
            'landing', f.cierres_landing,
            'referido', f.cierres_referido,
            'referido_aporte', f.cierres_referido_aporte,
            'oficina', f.cierres_oficina,
            'otros', f.cierres_otros
          ) end,
          'cartera', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'upgrade', f.upgrade,
            'renovacion', f.renovacion,
            'renovacion_aporte', f.renovacion_aporte
          ) end
        )
        order by f.nombre nulls last, f.analista_id
      )
      from private.conversion_divisor_empresa(v_desde, v_hasta) f
      where f.analista_id is not null
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.conversion_divisor_coordinacion_fn(date, date, date) is
  'Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados; si toca meses sellados lo declara en periodo.cruza_meses_sellados y fuente.modo = rango_vivo). Los cierres de orígenes que no pesan (oficina y otros) se cuentan aparte. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.';

revoke all on function crm.conversion_divisor_coordinacion_fn(date, date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_divisor_coordinacion_fn(date, date, date)
  to authenticated;

do $postflight$
declare
  v_base regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_base(date,date)');
  v_nucleo regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date,date)');
  v_totales regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date,date)');
  v_puerta regprocedure := pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)');
  v_cuerpo text;
  v_mes date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_fin_mes date := (pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date;
  v_filas_nucleo integer;
  v_filas_neto integer;
  v_divisor_nucleo bigint;
  v_divisor_neto bigint;
  v_divisor_origen bigint;
  v_rota text;
begin
  if v_base is null or v_nucleo is null or v_totales is null or v_puerta is null then
    raise exception 'POSTFLIGHT: faltan las cuatro funciones de la conversión de Coordinación';
  end if;
  if pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)') is not null
     or pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date)') is not null
     or pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date)') is not null then
    raise exception 'POSTFLIGHT: quedaron las firmas viejas (date) conviviendo con las nuevas';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
       where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
         and p.prosecdef
         and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']) <> 4 then
    raise exception 'POSTFLIGHT: las cuatro funciones deben ser STABLE, SECURITY DEFINER y usar search_path vacío';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('anon', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('public', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('authenticated', v_nucleo, 'execute')
     or pg_catalog.has_function_privilege('anon', v_nucleo, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_nucleo, 'execute')
     or pg_catalog.has_function_privilege('public', v_nucleo, 'execute')
     or pg_catalog.has_function_privilege('authenticated', v_totales, 'execute')
     or pg_catalog.has_function_privilege('anon', v_totales, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_totales, 'execute')
     or pg_catalog.has_function_privilege('public', v_totales, 'execute')
     or pg_catalog.has_function_privilege('authenticated', v_base, 'execute')
     or pg_catalog.has_function_privilege('anon', v_base, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_base, 'execute')
     or pg_catalog.has_function_privilege('public', v_base, 'execute') then
    raise exception 'POSTFLIGHT: ACL inesperada (la puerta solo para authenticated; los núcleos sin ejecutores de la API)';
  end if;

  -- La puerta se ejecuta al menos una vez aquí: sin JWT no hay actor y el gate
  -- debe responder 42501 antes de tocar nada.
  begin
    perform crm.conversion_divisor_coordinacion_fn();
    raise exception 'POSTFLIGHT: la puerta respondió sin actor autenticado';
  exception when insufficient_privilege then null;
  end;

  -- EL CANDADO DE DISPERSIÓN: ninguna de las tres vuelve a contar leads ni el ledger.
  for v_cuerpo in
    select pg_catalog.regexp_replace(pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g')
    from pg_catalog.pg_proc p where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
  loop
    if v_cuerpo ~ '\mcrm\.\s*leads\M' or v_cuerpo ~ '"leads"' or v_cuerpo ~ '\mlead_asignaciones\M' then
      raise exception 'POSTFLIGHT: la conversión de Coordinación no puede leer leads ni el ledger: el divisor solo sale del núcleo';
    end if;
  end loop;
  select pg_catalog.lower(p.prosrc) into v_cuerpo from pg_catalog.pg_proc p where p.oid = v_base;
  if v_cuerpo !~ 'private\.conversion_neta_por_vendedor\(' or v_cuerpo !~ 'private\.conversion_mensual_por_vendedor\(' then
    raise exception 'POSTFLIGHT: la base de Coordinación debe leer conversion_neta_por_vendedor (mes) y conversion_mensual_por_vendedor (rango)';
  end if;
  select pg_catalog.lower(p.prosrc) into v_cuerpo from pg_catalog.pg_proc p where p.oid = v_nucleo;
  if v_cuerpo !~ 'private\.conversion_divisor_base\(' or v_cuerpo !~ 'private\.conversion_episodios\(' then
    raise exception 'POSTFLIGHT: el núcleo de Coordinación debe leer conversion_divisor_base y conversion_episodios';
  end if;
  select pg_catalog.regexp_replace(pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g') into v_cuerpo
    from pg_catalog.pg_proc p where p.oid = v_puerta;
  if v_cuerpo ~ '\m(from|join)\s+(crm|public)\.' then
    raise exception 'POSTFLIGHT: la puerta lee tablas en vez de delegar en el núcleo';
  end if;

  -- PARIDAD con el núcleo en el mes vigente: mismas filas y mismo divisor que la
  -- pieza que usa Metas; formulario + landing = divisor.
  select count(*), coalesce(sum(f.divisor), 0), coalesce(sum(f.divisor_formulario + f.divisor_landing), 0)
    into v_filas_nucleo, v_divisor_nucleo, v_divisor_origen
  from private.conversion_divisor_empresa(v_mes, v_fin_mes) f;
  select count(*), coalesce(sum(n.divisor), 0)
    into v_filas_neto, v_divisor_neto
  from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n;
  if v_filas_nucleo <> v_filas_neto or v_divisor_nucleo <> v_divisor_neto then
    raise exception 'POSTFLIGHT: la composición no reproduce el núcleo (filas %/% divisor %/%)',
      v_filas_nucleo, v_filas_neto, v_divisor_nucleo, v_divisor_neto;
  end if;
  if v_divisor_origen <> v_divisor_nucleo then
    raise exception 'POSTFLIGHT: formulario + landing (%) no suman el divisor (%)', v_divisor_origen, v_divisor_nucleo;
  end if;

  -- LA INVARIANTE NUEVA, sobre los datos reales del mes vigente: en cada fila las
  -- partes suman el numerador bruto, el neto es el bruto con el ajuste, y los
  -- conteos casan con los del núcleo (no referidos = formulario + landing).
  select pg_catalog.string_agg(coalesce(f.analista_id::text, 'sin analista'), ', ')
    into v_rota
  from private.conversion_divisor_empresa(v_mes, v_fin_mes) f
  join private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n
    on n.analista_id is not distinct from f.analista_id
  where f.numerador_bruto is distinct from
          (f.cierres_formulario + f.cierres_landing)::numeric + f.cierres_referido_aporte + f.upgrade::numeric + f.renovacion_aporte
     or f.numerador is distinct from private.conversion_con_ajuste(f.numerador_bruto, f.ajuste_pendiente)
     or f.numerador_bruto is distinct from coalesce(n.numerador_bruto, 0::numeric)
     or f.ajuste_pendiente is distinct from coalesce(n.ajuste_pendiente, 0::numeric)
     or f.cierres_referido is distinct from n.cierres_referidos
     or f.cierres_formulario + f.cierres_landing is distinct from n.cierres_no_referidos
     or f.desglose_disponible is not true;
  if v_rota is not null then
    raise exception 'POSTFLIGHT: el desglose de cierres no reproduce el numerador del núcleo en: %', v_rota;
  end if;
  if exists (
    select 1
    from private.conversion_divisor_empresa_totales(v_mes, v_fin_mes) t
    where t.numerador_bruto is distinct from
            (t.cierres_formulario + t.cierres_landing)::numeric + t.cierres_referido_aporte + t.upgrade::numeric + t.renovacion_aporte
       or t.numerador is distinct from coalesce((select sum(f.numerador) from private.conversion_divisor_empresa(v_mes, v_fin_mes) f), 0::numeric)
       or t.desglose_disponible is not true
  ) then
    raise exception 'POSTFLIGHT: el desglose de la empresa no suma el numerador';
  end if;

  -- MODO RANGO sobre datos reales. (1) Del 1 del mes vigente a hoy no puede haber
  -- llegadas ni cierres «del futuro», así que el rango en vivo reproduce el BRUTO
  -- del mes (mismas filas, divisor, formulario, landing y partes). El último día
  -- del mes ese rango ES el mes (y entonces lleva su ajuste); cualquier otro día
  -- es un rango libre sin ajuste. (2) El rango que cruza el mes anterior es aditivo
  -- en el divisor: llegadas del 15 del mes anterior a hoy = del 15 al fin de ese
  -- mes + del 1 a hoy, analista por analista. Ambas son ciertas cualquier día.
  if exists (
    select 1
    from private.conversion_divisor_empresa(v_mes, v_fin_mes) m
    full join private.conversion_divisor_empresa(v_mes, v_hoy) r
      on coalesce(r.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(m.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
    where (m.analista_id is null and r.analista_id is not null)
       or (r.analista_id is null and m.analista_id is not null and m.en_nucleo)  -- una fila solo con deuda no existe en el rango
       or (m.en_nucleo and (
             m.divisor is distinct from r.divisor
          or m.divisor_formulario is distinct from r.divisor_formulario
          or m.cierres_formulario + m.cierres_landing + m.cierres_referido + m.cierres_oficina + m.cierres_otros + m.upgrade + m.renovacion
             is distinct from r.cierres_formulario + r.cierres_landing + r.cierres_referido + r.cierres_oficina + r.cierres_otros + r.upgrade + r.renovacion
          or m.numerador_bruto is distinct from r.numerador_bruto))
       or (v_hoy <> v_fin_mes and r.analista_id is not null and (r.numerador is distinct from r.numerador_bruto or r.ajuste_pendiente is distinct from 0::numeric))
  ) then
    raise exception 'POSTFLIGHT: el modo rango (1 → hoy) no reproduce el bruto del mes vigente';
  end if;
  if exists (
    with a as (select * from private.conversion_divisor_empresa((v_mes - interval '1 month' + interval '14 days')::date, (v_mes - interval '1 day')::date)),
         b as (select * from private.conversion_divisor_empresa(v_mes, v_hoy)),
         ab as (select * from private.conversion_divisor_empresa((v_mes - interval '1 month' + interval '14 days')::date, v_hoy))
    select 1
    from ab
    left join a on coalesce(a.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(ab.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
    left join b on coalesce(b.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(ab.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
    where ab.divisor is distinct from coalesce(a.divisor, 0) + coalesce(b.divisor, 0)
       or ab.divisor_formulario is distinct from coalesce(a.divisor_formulario, 0) + coalesce(b.divisor_formulario, 0)
       or ab.cierres_formulario + ab.cierres_landing + ab.cierres_referido + ab.cierres_oficina + ab.upgrade + ab.renovacion
          is distinct from coalesce(a.cierres_formulario + a.cierres_landing + a.cierres_referido + a.cierres_oficina + a.upgrade + a.renovacion, 0)
                         + coalesce(b.cierres_formulario + b.cierres_landing + b.cierres_referido + b.cierres_oficina + b.upgrade + b.renovacion, 0)
  ) then
    raise exception 'POSTFLIGHT: el rango que cruza el mes anterior no es aditivo en llegadas y conteos';
  end if;
end;
$postflight$;

commit;
$migracion_20260930221500$;
  v_nombre text;
  v_sentencias text[];
  v_definicion text;
  v_firma text;
  v_md5 text;
begin
  if v_base is null or v_nucleo is null or v_totales is null or v_puerta is null then
    raise exception 'REGISTRO: faltan las funciones v2 de la conversión de Coordinación';
  end if;
  -- Los cuerpos VIVOS tienen que ser exactamente los del artefacto que se registra
  -- (huellas md5 de prosrc medidas al aplicar este mismo archivo en el banco a paridad).
  -- Un cuerpo distinto —aunque conserve propiedades, ACL y referencias— no se registra.
  for v_firma, v_md5 in select key, value #>> '{}' from pg_catalog.jsonb_each('{
    "crm.conversion_divisor_coordinacion_fn(date,date,date)": "b881b83ca8d4dd2f0f081d736828c8c5",
    "private.conversion_divisor_base(date,date)": "0a43b0f3b56026bd2c5bfa4a9d8942d9",
    "private.conversion_divisor_empresa(date,date)": "793a98fc4385fe714fff75290320c564",
    "private.conversion_divisor_empresa_totales(date,date)": "e97995f5ffd9109fce87f2e5dafb11a6"
  }'::jsonb) loop
    if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_firma)) is distinct from v_md5 then
      raise exception 'REGISTRO: el cuerpo vivo de % no es el del artefacto (huella distinta de %)', v_firma, v_md5;
    end if;
  end loop;
  if pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)') is not null then
    raise exception 'REGISTRO: la firma vieja de la puerta sigue viva';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
       where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
         and p.prosecdef and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']) <> 4 then
    raise exception 'REGISTRO: las funciones no conservan STABLE, SECURITY DEFINER y search_path vacío';
  end if;

  select pg_catalog.pg_get_functiondef(v_puerta) into v_definicion;
  if pg_catalog.strpos(v_definicion, 'private.puede_operar_reparto_crm()') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_divisor_empresa(') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_divisor_empresa_totales(') = 0
     or v_definicion ~* '\m(from|join)\s+(crm|public)\.' then
    raise exception 'REGISTRO: la puerta viva no coincide con el contrato esperado (o lee tablas)';
  end if;
  select pg_catalog.pg_get_functiondef(v_base) into v_definicion;
  if pg_catalog.strpos(v_definicion, 'private.conversion_neta_por_vendedor(') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_mensual_por_vendedor(') = 0 then
    raise exception 'REGISTRO: la base viva no lee las dos piezas del núcleo';
  end if;
  select pg_catalog.pg_get_functiondef(v_nucleo) into v_definicion;
  if pg_catalog.strpos(v_definicion, 'private.conversion_divisor_base(') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_episodios(') = 0
     or v_definicion ~* 'crm\.\s*leads\M' or v_definicion ~* '\mlead_asignaciones\M' then
    raise exception 'REGISTRO: el núcleo vivo no lee el núcleo de conversión o volvió a contar leads';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('anon', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('public', v_puerta, 'execute')
     or (select bool_or(pg_catalog.has_function_privilege(r, f, 'execute'))
         from unnest(array['authenticated','anon','service_role','public']) r,
              unnest(array[v_base, v_nucleo, v_totales]) f) then
    raise exception 'REGISTRO: ACL inesperada en la conversión de Coordinación';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values (
    '20260930221500',
    'crm_conversion_coordinacion_desglose_cierres',
    array[v_cuerpo]
  )
  on conflict (version) do nothing;

  select migracion.name, migracion.statements
    into v_nombre, v_sentencias
  from supabase_migrations.schema_migrations migracion
  where migracion.version = '20260930221500';

  if v_nombre is distinct from 'crm_conversion_coordinacion_desglose_cierres'
     or v_sentencias is distinct from array[v_cuerpo] then
    raise exception 'REGISTRO: la versión 20260930221500 ya existe con otro contenido';
  end if;
end;
$registrar_conversion_desglose$;

commit;

select 'REGISTRO_CONVERSION_DESGLOSE_OK' as resultado,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)')) as huella_puerta,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date,date)')) as huella_nucleo,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date,date)')) as huella_totales,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.conversion_divisor_base(date,date)')) as huella_base;
