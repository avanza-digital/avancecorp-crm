ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — v2 de la conversión de Coordinación: desglose de cierres (referidos, upgrade, renovación) y rango de fechas (LEVEL 3: redefine una puerta viva y sus núcleos)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia. Tu tarea: REFUTAR.

## Contexto
- Hoy (30/09/2026) se publicó en prod la v1: `crm.conversion_divisor_coordinacion_fn(date)` + `private.conversion_divisor_empresa(date)` + `private.conversion_divisor_empresa_totales(date)` (huellas md5 de prosrc: 4c73a85e…, c62acbc0…, 9b65271a…). Enseña a la coordinadora, por analista y de toda la empresa, llegadas (divisor: una por lead, alta original en Lima, primer analista), numerador neto y %.
- Miguel pidió después: (1) abrir de dónde salen los cierres: formulario, landing, referido (cantidad y aporte al peso, hoy 0,15), oficina (no pesa), upgrade (pesa 1), renovación (cantidad y aporte al peso, hoy 0,15); (2) consultar por RANGO de fechas, no solo por mes.
- Núcleo que se compone (no se toca): `private.conversion_neta_por_vendedor(p_periodo, p_global, p_visibles)` (mes; bruto, ajuste de meses pagados, neto; 22023 si el mes está sellado), `private.conversion_mensual_por_vendedor(p_ini, p_fin, p_global, p_visibles, p_factor)` (rango en vivo; el mismo que usa `crm.metricas_conversiones_equipo_fn` de Gerencia, que valida desde ≤ hasta ≤ hoy, ≤ 365 días y pasa `peso_referido_conversion(date_trunc('month', p_hasta))`), `private.conversion_episodios(p_ini, p_fin, p_periodo, p_global, p_visibles, p_factor)` (episodios `recibido` con `aporte_divisor`, `cierre` con `origen` y `aporte_numerador` = 1 formulario/landing, peso referido, 0 oficina; `operacion` con `categoria` upgrade (aporte 1) / renovacion (aporte = peso del período si p_periodo no es nulo, si no el del mes de cada operación)), `private.conversion_con_ajuste(bruto, pendiente)` (neto con suelo en cero), `private.roster_conversion_mensual`, `private.peso_referido_conversion(date)`, `private.peso_renovacion_conversion(date)`.
- Foto sellada (`crm.cierre_mes_vendedor`): columnas `divisor, numerador, conversion_pct, cierres_no_referidos, cierres_referidos, cartera jsonb {operaciones_upgrade, operaciones_renovacion, …}, origenes_ranking jsonb {disponible, filas:[{origen, leads, cierres, conversion_pct, …}]}`; `crm.periodos_cerrados` con `ponderacion_referido`, `ponderacion_renovacion` (nullable), `cobertura` (fuera_ranking, conversion_sin_analista, modelo_conversion). Hoy prod no tiene ningún mes sellado.
- Verificado (banco Docker con el esquema de prod al byte, huellas iguales): migración v2 aplicada en un mensaje PASS (preflight acredita las tres huellas vivas; postflight: propiedades, ACL incl. public, candado de dispersión, puerta sin tablas, ejecuta la puerta sin JWT → 42501, paridad con el núcleo, INVARIANTE partes = numerador bruto y neto = con_ajuste por fila, empresa suma, y «rango 1 → hoy reproduce el mes»). Oráculo v2 OK sin residuo (E01–E09). Registrador v2 probado (md5 = archivo, idempotente, fail-closed). Validación read-only en PROD con setiembre real: 18 analistas, 0 filas rotas (partes = bruto, referidos y no referidos casan con el núcleo, neto = con_ajuste); Astrid 5 + 2 + 1×0,15 + 4 upgrade = 11,15; Merlys 6 + 1 + 2 = 9; empresa f 65, l 25, referido 19 (2,85), oficina 11, upgrade 24, renovación 3 (0,45); rango 1 → hoy = mes para todos; Astrid 1–15/09: 67 llegadas / 8,15; rango 15/08–15/09: 1661 llegadas, 21 analistas, sin error. Front: vitest 158/158 en los 4 archivos tocados; `npm run check` y E2E Docker en curso.

## Preguntas para refutar
1. Modo rango: ¿la elección de `peso_referido_conversion(mes de hasta)` para todo el rango y la de `p_periodo = null` (renovación por mes de cada operación) puede dar un numerador cuyas partes no sumen? (El postflight lo comprueba solo para 1 → hoy.) ¿Un rango que cruza un mes SELLADO calcula en vivo sin avisar? (La v2 devuelve `sellado=false`, `modo='rango'`, sin ajuste; ¿hay que exponer «cruza mes sellado»?)
2. `conversion_divisor_base`: ¿`coalesce(n.numerador_bruto, 0)` puede romper `numerador = con_ajuste(bruto, ajuste)` cuando bruto es NULL en el núcleo? ¿Existe ese caso (fila solo con deuda, `en_nucleo=false`)?
3. Sellado: `con_desglose` exige `origenes_ranking.disponible` y `cartera` no nulo; el aporte del referido se reconstruye como `referido × ponderacion_referido` y renovación × peso sellado. ¿Puede diferir del numerador sellado (p. ej. cierres de arrastre, ajustes)? El front NO exige partes = bruto en sellado (bruto/ajuste van en null). ¿Correcto o hay que exponer la diferencia?
4. Puerta: `p_periodo` + rango → 22023; una sola fecha → 22023; ≤ 366 días; sin futuro. ¿Algún oráculo de errores o fuga?
5. Front: el candado `conversionCoordinacionConsistente(datos, desde, hasta)` y `motivoConsultaInvalida`: ¿falsos rojos? (mes exacto pedido como rango: la puerta responde `modo='mes'` con nombre → el front lo acepta porque compara desde/hasta; ¿algún caso en que `dias` no cuadre por zona horaria?)
6. ¿Algo del alcance NO ENTRA tocado? (núcleo, pesos, reporte de entregas, conteos por dueño actual, puertas de conversión existentes)

## Archivos

### supabase/migrations/20260930221500_crm_conversion_coordinacion_desglose_cierres.sql
```sql
-- ============================================================================
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
          and f.cartera is not null as con_desglose
      from crm.cierre_mes_vendedor f
      where f.periodo = p_desde
    ),
    por_origen as (
      select f.vendedor_id,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'formulario')::integer as formulario,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'landing')::integer as landing,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'referido')::integer as referido,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'oficina')::integer as oficina
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
           case when f.con_desglose then coalesce((f.cartera ->> 'operaciones_upgrade')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'operaciones_renovacion')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'operaciones_renovacion')::integer, 0) * v_peso_renovacion end,
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
  upgrade integer,
  renovacion integer,
  renovacion_aporte numeric,
  desglose_disponible boolean,
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
      -- solo si TODAS las filas de la foto lo traen (si no, la suma mentiría).
      coalesce(bool_and(f.desglose_disponible), v_cierre.periodo is null) as desglose_disponible,
      coalesce(sum(f.cierres_formulario), 0)::integer as cierres_formulario,
      coalesce(sum(f.cierres_landing), 0)::integer as cierres_landing,
      coalesce(sum(f.cierres_referido), 0)::integer as cierres_referido,
      coalesce(sum(f.cierres_referido_aporte), 0::numeric) as cierres_referido_aporte,
      coalesce(sum(f.cierres_oficina), 0)::integer as cierres_oficina,
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
    case when s.desglose_disponible then s.upgrade end,
    case when s.desglose_disponible then s.renovacion end,
    case when s.desglose_disponible then s.renovacion_aporte end,
    s.desglose_disponible,
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
      'dias', (v_hasta - v_desde) + 1
    ),
    'sellado', v_totales.sellado,
    'peso_referido', v_totales.peso_referido,
    'peso_renovacion', v_totales.peso_renovacion,
    'fuente', pg_catalog.jsonb_build_object(
      'divisor', 'private.conversion_neta_por_vendedor',
      'origen', 'private.conversion_episodios',
      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado'
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
        'oficina', v_totales.cierres_oficina
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
            'oficina', f.cierres_oficina
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
  'Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados). Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.';

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

  -- MODO RANGO sobre datos reales: del 1 del mes vigente a hoy no puede haber
  -- llegadas ni cierres «del futuro», así que el rango en vivo reproduce el mes
  -- (mismas filas, divisor, formulario, landing y partes; bruto = neto porque
  -- el rango no lleva ajuste). Si difiere, la pieza por rango no casa con la mensual.
  if exists (
    select 1
    from private.conversion_divisor_empresa(v_mes, v_fin_mes) m
    full join private.conversion_divisor_empresa(v_mes, v_hoy) r
      on coalesce(r.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(m.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
    where m.analista_id is null and r.analista_id is not null
       or r.analista_id is null and m.analista_id is not null
       or m.divisor is distinct from r.divisor
       or m.divisor_formulario is distinct from r.divisor_formulario
       or m.cierres_formulario + m.cierres_landing + m.cierres_referido + m.upgrade + m.renovacion
          is distinct from r.cierres_formulario + r.cierres_landing + r.cierres_referido + r.upgrade + r.renovacion
       or m.numerador_bruto is distinct from r.numerador_bruto
       or r.numerador is distinct from r.numerador_bruto
       or r.ajuste_pendiente is distinct from 0::numeric
  ) then
    raise exception 'POSTFLIGHT: el modo rango (1 → hoy) no reproduce el mes vigente';
  end if;
end;
$postflight$;

commit;
```

### supabase/scripts/registrar-20260930221500.sql (solo la cola, sin el cuerpo embebido)
```sql
  v_nombre text;
  v_sentencias text[];
  v_definicion text;
begin
  if v_base is null or v_nucleo is null or v_totales is null or v_puerta is null then
    raise exception 'REGISTRO: faltan las funciones v2 de la conversión de Coordinación';
  end if;
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
```

### app/src/lib/conversion-coordinacion.ts (completo)
```ts
import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'

/**
 * Conversión por analista de TODA la empresa, tal como la sirve
 * `crm.conversion_divisor_coordinacion_fn`: el divisor es el del NÚCLEO (una
 * llegada por lead, por su alta original en Lima, en el primer analista que la
 * recibió), no el reporte de entregas; y el numerador se abre en sus partes
 * (cierres por origen y operaciones de cartera) con los mismos episodios que lo
 * suman. El navegador solo pinta: cualquier aritmética que no reconcilie se
 * rechaza antes de mostrarse.
 */
const CierresSchema = v.object({
  formulario: EnteroNoNegativoRpcSchema,
  landing: EnteroNoNegativoRpcSchema,
  referido: EnteroNoNegativoRpcSchema,
  /** Cuánto suman los referidos al numerador (cantidad × peso del referido). */
  referido_aporte: NumeroRpcSchema,
  /** Oficina (walking) no pesa en el numerador; se enseña para no ocultarla. */
  oficina: EnteroNoNegativoRpcSchema,
})

const CarteraSchema = v.object({
  /** Upgrade pesa 1 por operación. */
  upgrade: EnteroNoNegativoRpcSchema,
  renovacion: EnteroNoNegativoRpcSchema,
  /** Cuánto suman las renovaciones al numerador (cantidad × peso de renovación). */
  renovacion_aporte: NumeroRpcSchema,
})

const AnalistaConversionCoordinacionSchema = v.object({
  analista_id: UuidSchema,
  nombre: v.nullable(v.string()),
  supervisor_id: v.nullable(UuidSchema),
  supervisor_nombre: v.nullable(v.string()),
  en_nucleo: v.boolean(),
  divisor: EnteroNoNegativoRpcSchema,
  /** Null solo en un mes sellado: la foto no guarda el desglose por origen. */
  divisor_formulario: v.nullable(EnteroNoNegativoRpcSchema),
  divisor_landing: v.nullable(EnteroNoNegativoRpcSchema),
  numerador: v.nullable(NumeroRpcSchema),
  conversion_pct: v.nullable(NumeroRpcSchema),
  /** Bruto y ajuste de meses ya pagados: null en un mes sellado (la foto guarda el neto). */
  numerador_bruto: v.nullable(NumeroRpcSchema),
  ajuste_pendiente: v.nullable(NumeroRpcSchema),
  /** False solo en un mes sellado cuya foto no trae el desglose. */
  desglose_disponible: v.boolean(),
  cierres: v.nullable(CierresSchema),
  cartera: v.nullable(CarteraSchema),
})

const EmpresaConversionCoordinacionSchema = v.object({
  divisor: EnteroNoNegativoRpcSchema,
  numerador: NumeroRpcSchema,
  conversion_pct: v.nullable(NumeroRpcSchema),
  divisor_formulario: v.nullable(EnteroNoNegativoRpcSchema),
  divisor_landing: v.nullable(EnteroNoNegativoRpcSchema),
  numerador_bruto: v.nullable(NumeroRpcSchema),
  ajuste_pendiente: v.nullable(NumeroRpcSchema),
  desglose_disponible: v.boolean(),
  cierres: v.nullable(CierresSchema),
  cartera: v.nullable(CarteraSchema),
})

export const ConversionCoordinacionSchema = v.object({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  alcance: v.literal('global'),
  /** Mes calendario exacto (`modo: 'mes'`, con nombre) o rango libre inclusivo (`modo: 'rango'`). */
  periodo: v.object({
    modo: v.picklist(['mes', 'rango']),
    mes: v.nullable(v.pipe(v.string(), v.regex(/^\d{4}-\d{2}$/))),
    mes_nombre: v.nullable(TextoNoVacioSchema),
    anio: v.nullable(v.pipe(NumeroRpcSchema, v.integer())),
    zona: v.literal('America/Lima'),
    desde: FechaSchema,
    /** Inclusivo: el último día del mes o la fecha final del rango. */
    hasta: FechaSchema,
    dias: v.pipe(NumeroRpcSchema, v.integer(), v.minValue(1)),
  }),
  sellado: v.boolean(),
  peso_referido: NumeroRpcSchema,
  peso_renovacion: NumeroRpcSchema,
  fuente: v.object({
    divisor: TextoNoVacioSchema,
    origen: TextoNoVacioSchema,
    regla: TextoNoVacioSchema,
  }),
  empresa: EmpresaConversionCoordinacionSchema,
  /** Llegadas sin analista atribuible: cuentan en la empresa, sin responsable inventado. */
  sin_analista: v.nullable(v.object({
    divisor: EnteroNoNegativoRpcSchema,
    numerador: v.nullable(NumeroRpcSchema),
  })),
  analistas: v.array(AnalistaConversionCoordinacionSchema),
})

export type ConversionCoordinacion = v.InferOutput<typeof ConversionCoordinacionSchema>
export type AnalistaConversionCoordinacion = v.InferOutput<typeof AnalistaConversionCoordinacionSchema>
export type CierresConversion = v.InferOutput<typeof CierresSchema>
export type CarteraConversion = v.InferOutput<typeof CarteraSchema>

/** 'YYYY-MM' del mes vigente en Lima. */
export function mesActualLima(ahora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
  }).format(ahora).slice(0, 7)
}

/** Primer día del mes ('YYYY-MM' → 'YYYY-MM-01'); null si el mes no es válido. */
export function periodoDesdeMes(mes: string): string | null {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(mes) ? `${mes}-01` : null
}

/** Último día del mes ('YYYY-MM' → 'YYYY-MM-DD'); null si el mes no es válido. */
export function finDeMes(mes: string): string | null {
  if (!periodoDesdeMes(mes)) return null
  const [anio, numero] = mes.split('-').map(Number) as [number, number]
  return new Date(Date.UTC(anio, numero, 0)).toISOString().slice(0, 10)
}

/** 'YYYY-MM-DD' de hoy en Lima. */
export function hoyLima(ahora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(ahora)
}

/** Lo que la pestaña pide a la puerta: un mes calendario o un rango inclusivo. */
export type ConsultaConversion =
  | { modo: 'mes'; mes: string }
  | { modo: 'rango'; desde: string; hasta: string }

export const RANGO_MAXIMO_DIAS = 366

/** Días inclusivos entre dos fechas 'YYYY-MM-DD' (1 cuando son iguales). */
export function diasInclusivos(desde: string, hasta: string): number {
  return Math.round((Date.parse(`${hasta}T12:00:00Z`) - Date.parse(`${desde}T12:00:00Z`)) / 86_400_000) + 1
}

/**
 * Valida la consulta como estado del formulario, ANTES de tocar la red: la
 * puerta rechazaría lo mismo (22023), pero el error tiene que quedar pegado al
 * campo, no disfrazado de fallo de carga. Devuelve el motivo o null si es válida.
 */
export function motivoConsultaInvalida(consulta: ConsultaConversion, hoy: string): string | null {
  if (consulta.modo === 'mes') {
    if (!periodoDesdeMes(consulta.mes)) return 'Elige un mes válido (año y mes) para consultar la conversión.'
    if (consulta.mes > hoy.slice(0, 7)) return `El mes no puede ser futuro: elige ${hoy.slice(0, 7)} o anterior.`
    return null
  }
  const desdeOk = v.safeParse(FechaSchema, consulta.desde).success
  const hastaOk = v.safeParse(FechaSchema, consulta.hasta).success
  if (!desdeOk || !hastaOk) return 'Elige las dos fechas del rango (desde y hasta).'
  if (consulta.desde > consulta.hasta) return 'La fecha inicial no puede ser posterior a la final.'
  if (consulta.hasta > hoy) return `El rango no admite fechas futuras: hasta ${hoy} como máximo.`
  if (diasInclusivos(consulta.desde, consulta.hasta) > RANGO_MAXIMO_DIAS) return `El rango máximo es de ${RANGO_MAXIMO_DIAS} días.`
  return null
}

/** Fechas inclusivas que la consulta pide (el mes se convierte a su primer y último día). */
export function fechasDeConsulta(consulta: ConsultaConversion): { desde: string; hasta: string } | null {
  if (consulta.modo === 'mes') {
    const desde = periodoDesdeMes(consulta.mes)
    const hasta = finDeMes(consulta.mes)
    return desde && hasta ? { desde, hasta } : null
  }
  return { desde: consulta.desde, hasta: consulta.hasta }
}

/** Tolerancia para sumas de pesos con decimales (0,15 × n) en coma flotante. */
const EPSILON = 1e-6

/** Cuánto suman las partes del numerador: cierres directos, referidos con peso, upgrade y renovación con peso. */
export function sumaDePartes(cierres: CierresConversion, cartera: CarteraConversion): number {
  return cierres.formulario + cierres.landing + cierres.referido_aporte + cartera.upgrade + cartera.renovacion_aporte
}

function desgloseConsistente(fila: {
  sellado: boolean
  desglose_disponible: boolean
  cierres: CierresConversion | null
  cartera: CarteraConversion | null
  numerador_bruto: number | null
  ajuste_pendiente: number | null
  numerador: number | null
}): boolean {
  if (!fila.desglose_disponible) {
    // Solo una foto sellada puede venir sin desglose; y entonces viene sin nada.
    return fila.sellado && fila.cierres === null && fila.cartera === null
  }
  if (fila.cierres === null || fila.cartera === null) return false
  if (fila.sellado) return fila.numerador_bruto === null && fila.ajuste_pendiente === null
  if (fila.numerador_bruto === null || fila.ajuste_pendiente === null || fila.numerador === null) return false
  if (Math.abs(sumaDePartes(fila.cierres, fila.cartera) - fila.numerador_bruto) > EPSILON) return false
  // Neto = bruto menos lo que se arrastra de meses ya pagados, con suelo en cero.
  return Math.abs(Math.max(fila.numerador_bruto - fila.ajuste_pendiente, 0) - fila.numerador) <= EPSILON
}

/**
 * Candado de PARIDAD del lado del navegador. No recalcula nada: comprueba que
 * lo que el servidor dice de cada analista y de la empresa cuadra consigo mismo
 * (formulario + landing = divisor; analistas + sin analista = empresa; las
 * partes de los cierres suman el numerador bruto y el neto es el bruto con el
 * ajuste). Si alguien vuelve a calcular el divisor o el numerador fuera del
 * núcleo y las sumas dejan de cerrar, la pantalla se niega a pintar en vez de
 * enseñar un número inventado.
 */
export function conversionCoordinacionConsistente(
  datos: ConversionCoordinacion,
  desde: string,
  hasta: string,
): boolean {
  const { periodo } = datos
  if (periodo.desde !== desde || periodo.hasta !== hasta) return false
  if (periodo.dias !== diasInclusivos(desde, hasta)) return false
  if (periodo.modo === 'mes') {
    if (periodo.mes === null || !desde.startsWith(periodo.mes) || periodo.mes_nombre === null || periodo.anio === null) return false
  } else if (periodo.mes !== null || periodo.mes_nombre !== null || periodo.anio !== null || datos.sellado) {
    // Un rango libre nunca es una foto sellada ni lleva nombre de mes.
    return false
  }
  if (periodo.modo === 'rango' && (datos.empresa.ajuste_pendiente !== 0
    || datos.analistas.some((a) => a.ajuste_pendiente !== 0))) return false

  const ids = new Set<string>()
  let divisorAnalistas = 0
  let formulario = 0
  let landing = 0
  for (const analista of datos.analistas) {
    if (ids.has(analista.analista_id)) return false
    ids.add(analista.analista_id)
    divisorAnalistas += analista.divisor
    if (!desgloseConsistente({ ...analista, sellado: datos.sellado })) return false
    if (datos.sellado) {
      if (analista.divisor_formulario !== null || analista.divisor_landing !== null) return false
      continue
    }
    if (analista.divisor_formulario === null || analista.divisor_landing === null) return false
    if (analista.divisor_formulario + analista.divisor_landing !== analista.divisor) return false
    formulario += analista.divisor_formulario
    landing += analista.divisor_landing
  }

  if (!desgloseConsistente({ ...datos.empresa, sellado: datos.sellado })) return false
  if (datos.sellado) {
    return datos.empresa.divisor_formulario === null && datos.empresa.divisor_landing === null
  }
  if (datos.empresa.divisor_formulario === null || datos.empresa.divisor_landing === null) return false
  if (datos.empresa.divisor_formulario + datos.empresa.divisor_landing !== datos.empresa.divisor) return false
  if (divisorAnalistas + (datos.sin_analista?.divisor ?? 0) !== datos.empresa.divisor) return false
  if (formulario > datos.empresa.divisor_formulario || landing > datos.empresa.divisor_landing) return false
  return true
}
```

### app/src/components/app/conversion-coordinacion.tsx (completo)
```tsx
import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import { Lock, Percent } from 'lucide-react'
import { conversionCoordinacion } from '@/data/crm-api'
import { useAhora } from '@/lib/ahora'
import {
  hoyLima,
  mesActualLima,
  motivoConsultaInvalida,
  type AnalistaConversionCoordinacion,
  type CarteraConversion,
  type CierresConversion,
  type ConsultaConversion,
  type ConversionCoordinacion as DatosConversion,
} from '@/lib/conversion-coordinacion'
import { porcentajeConversionCanonica } from '@/lib/format'
import { paginar } from '@/lib/paginacion'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'

const POR_PAGINA = 15

interface EstadoConversion {
  datos: DatosConversion | null
  cargando: boolean
  error: string | null
}

/** Enteros del núcleo tal cual; los aportes llevan el peso (hasta 2 decimales). */
function numero(valor: number): string {
  return valor.toLocaleString('es-PE', { maximumFractionDigits: 2 })
}

/**
 * El «—» es MUDO para NVDA/JAWS (la puntuación por defecto no lo pronuncia): se
 * pinta el símbolo, pero el lector oye el motivo, que es lo que distingue «no
 * hubo llegadas» de «el mes está cerrado» o «no aplica».
 */
function SinDato({ motivo }: { motivo: string }) {
  return (
    <>
      <span aria-hidden="true">—</span>
      <span className="sr-only">{motivo}</span>
    </>
  )
}

const MOTIVO_SELLADO = 'sin desglose: mes cerrado'
const MOTIVO_SIN_LLEGADAS = 'sin llegadas'

/** «setiembre de 2026» a partir de 'YYYY-MM', sin depender de la zona del navegador. */
function nombreDelMes(mes: string): string {
  return new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(`${mes}-01T00:00:00Z`))
}

/** «15 de setiembre de 2026» a partir de 'YYYY-MM-DD'; la cadena tal cual si no es una fecha. */
function fechaLarga(iso: string): string {
  const fecha = new Date(`${iso}T00:00:00Z`)
  return Number.isNaN(fecha.getTime())
    ? iso
    : new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }).format(fecha)
}

function Cifra({ valor, motivo }: { valor: number | null; motivo: string }) {
  return valor == null || !Number.isFinite(valor) ? <SinDato motivo={motivo} /> : <>{numero(valor)}</>
}

function Porcentaje({ valor }: { valor: number | null }) {
  return valor == null || !Number.isFinite(valor)
    ? <SinDato motivo={MOTIVO_SIN_LLEGADAS} />
    : <>{porcentajeConversionCanonica(valor)}</>
}

/** «19 · 2,85»: cuántos y cuánto pesan. El lector oye las dos cifras con su nombre. */
function CantidadYAporte({ cantidad, aporte, nombre }: { cantidad: number; aporte: number; nombre: string }) {
  return (
    <>
      <span aria-hidden="true">{numero(cantidad)} · {numero(aporte)}</span>
      <span className="sr-only">{numero(cantidad)} {nombre}, aportan {numero(aporte)}</span>
    </>
  )
}

/** Las seis celdas de «Cierres» de una fila: por origen, cartera y el total ponderado. */
function CeldasCierres({
  cierres,
  cartera,
  numerador,
  bruto,
  ajuste,
  motivo,
}: {
  cierres: CierresConversion | null
  cartera: CarteraConversion | null
  numerador: number | null
  bruto: number | null
  ajuste: number | null
  motivo: string
}) {
  const conAjuste = ajuste != null && ajuste !== 0 && bruto != null
  return (
    <>
      <Td className="text-right tabular-nums">{cierres ? numero(cierres.formulario) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">{cierres ? numero(cierres.landing) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">
        {cierres ? <CantidadYAporte cantidad={cierres.referido} aporte={cierres.referido_aporte} nombre="referidos" /> : <SinDato motivo={motivo} />}
      </Td>
      <Td className="hidden text-right tabular-nums text-muted-foreground xl:table-cell">
        {cierres ? numero(cierres.oficina) : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right tabular-nums">{cartera ? numero(cartera.upgrade) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">
        {cartera ? <CantidadYAporte cantidad={cartera.renovacion} aporte={cartera.renovacion_aporte} nombre="renovaciones" /> : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right font-semibold tabular-nums">
        <Cifra valor={numerador} motivo="sin cierres" />
        {conAjuste ? (
          <span className="block text-[11px] font-normal text-muted-foreground">
            bruto {numero(bruto)} − ajuste {numero(ajuste)}
          </span>
        ) : null}
      </Td>
    </>
  )
}

function FilaAnalista({ analista, sellado }: { analista: AnalistaConversionCoordinacion; sellado: boolean }) {
  return (
    <tr className="border-b border-border last:border-0">
      <Td className="text-base font-medium">{analista.nombre ?? 'Sin nombre'}</Td>
      <Td className="hidden text-muted-foreground lg:table-cell">
        {analista.supervisor_nombre ?? <SinDato motivo="sin supervisor" />}
      </Td>
      <Td className="hidden text-right tabular-nums lg:table-cell">
        {sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={analista.divisor_formulario} motivo={MOTIVO_SIN_LLEGADAS} />}
      </Td>
      <Td className="hidden text-right tabular-nums lg:table-cell">
        {sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={analista.divisor_landing} motivo={MOTIVO_SIN_LLEGADAS} />}
      </Td>
      <Td className="text-right text-base font-extrabold tabular-nums text-primary">{numero(analista.divisor)}</Td>
      <CeldasCierres
        cierres={analista.cierres}
        cartera={analista.cartera}
        numerador={analista.numerador}
        bruto={analista.numerador_bruto}
        ajuste={analista.ajuste_pendiente}
        motivo={MOTIVO_SELLADO}
      />
      <Td className="text-right font-semibold tabular-nums"><Porcentaje valor={analista.conversion_pct} /></Td>
    </tr>
  )
}

/** «117,15 = 90 directos + 2,85 referidos (19 × 0,15) + 24 upgrade + 0,45 renovación (3 × 0,15)». */
function formulaDelNumerador(datos: DatosConversion): string | null {
  const { cierres, cartera, numerador, numerador_bruto: bruto, ajuste_pendiente: ajuste } = datos.empresa
  if (!cierres || !cartera) return null
  const partes = [
    `${numero(cierres.formulario + cierres.landing)} directos (formulario y landing)`,
    `${numero(cierres.referido_aporte)} de referidos (${numero(cierres.referido)} × ${numero(datos.peso_referido)})`,
    `${numero(cartera.upgrade)} de upgrade`,
    `${numero(cartera.renovacion_aporte)} de renovación (${numero(cartera.renovacion)} × ${numero(datos.peso_renovacion)})`,
  ]
  const total = bruto ?? numerador
  const cola = ajuste != null && ajuste !== 0 ? ` − ${numero(ajuste)} de ajuste de meses ya pagados = ${numero(numerador)} netos` : ''
  return `Cierres ponderados ${numero(total)} = ${partes.join(' + ')}${cola}. Oficina (${numero(cierres.oficina)}) no pesa.`
}

/**
 * Conversión del mes por analista, con ámbito de toda la empresa. El divisor es
 * el del NÚCLEO (la misma cifra que Metas y Ranking): una llegada por lead, por
 * su fecha de alta, en el primer analista que la recibió. No es el reporte de
 * entregas. Los cierres se abren en sus partes con los mismos episodios del
 * núcleo. El navegador no calcula nada: pinta lo que el servidor reconcilió.
 */
export function ConversionCoordinacion() {
  const ahora = useAhora()
  const hoy = useMemo(() => hoyLima(new Date(ahora)), [ahora])
  const mesMaximo = useMemo(() => mesActualLima(new Date(ahora)), [ahora])
  const [modo, setModo] = useState<ConsultaConversion['modo']>('mes')
  const [mes, setMes] = useState(mesMaximo)
  const [desde, setDesde] = useState(`${mesMaximo}-01`)
  const [hasta, setHasta] = useState(hoy)
  const [estado, setEstado] = useState<EstadoConversion>({ datos: null, cargando: true, error: null })
  const [pagina, setPagina] = useState(0)
  const abortRef = useRef<AbortController | null>(null)
  const contenidoRef = useRef<HTMLDivElement>(null)
  const focoPendiente = useRef(false)
  const idAyudaMes = useId()
  const consulta = useMemo<ConsultaConversion>(
    () => (modo === 'mes' ? { modo: 'mes', mes } : { modo: 'rango', desde, hasta }),
    [modo, mes, desde, hasta],
  )
  // Consulta inválida = estado del formulario (pegado al campo), nunca un fallo de carga.
  const ayudaMes = motivoConsultaInvalida(consulta, hoy)
  const mesInvalido = ayudaMes !== null
  const claveConsulta = JSON.stringify(consulta)

  const cargar = useCallback(async (conservarError = false) => {
    abortRef.current?.abort()
    const pedida = JSON.parse(claveConsulta) as ConsultaConversion
    if (motivoConsultaInvalida(pedida, hoy)) {
      setEstado({ datos: null, cargando: false, error: null })
      return
    }
    const controlador = new AbortController()
    abortRef.current = controlador
    // Se conserva el error solo al reintentar, para que el botón no se desmonte
    // bajo el foco; la carga se anuncia por el estado persistente.
    setEstado((previo) => ({ datos: null, cargando: true, error: conservarError ? previo.error : null }))
    try {
      const datos = await conversionCoordinacion(pedida, controlador.signal)
      if (controlador.signal.aborted) return
      setEstado({ datos, cargando: false, error: null })
    } catch (error) {
      if (controlador.signal.aborted) return
      setEstado({
        datos: null,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la conversión por analista.',
      })
    }
  }, [claveConsulta, hoy])

  useEffect(() => {
    focoPendiente.current = false // un cambio de período cancela el aterrizaje pendiente
    setPagina(0)
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  // El foco aterriza en el contenido cuando React ya lo pintó (no al resolver la
  // promesa: en ese instante el nodo todavía no existe).
  const reintentar = useCallback(() => {
    focoPendiente.current = true
    void cargar(true)
  }, [cargar])

  const datos = estado.datos
  useEffect(() => {
    if (datos && focoPendiente.current) {
      focoPendiente.current = false
      contenidoRef.current?.focus()
    }
  }, [datos])

  const analistas = useMemo(
    () => paginar(datos?.analistas ?? [], pagina, POR_PAGINA),
    [datos?.analistas, pagina],
  )
  const sinAnalista = datos?.sin_analista && datos.sin_analista.divisor > 0 ? datos.sin_analista : null
  const hayFilas = (datos?.analistas.length ?? 0) > 0 || sinAnalista !== null
  // Un mes cerrado puede tener producción solo «fuera del ranking» (supervisores,
  // perfiles fuera del roster): suma al total y no hay fila que enseñar.
  const produccionSinFilas = datos !== null && !hayFilas && datos.empresa.divisor > 0
  const formula = datos ? formulaDelNumerador(datos) : null

  const etiquetaPeriodo = (d: DatosConversion) => (
    d.periodo.modo === 'mes' && d.periodo.mes_nombre
      ? `${d.periodo.mes_nombre} ${d.periodo.anio}`
      : `del ${fechaLarga(d.periodo.desde)} al ${fechaLarga(d.periodo.hasta)}`
  )
  const mensajeEstado = mesInvalido
    ? ayudaMes
    : estado.cargando
      ? (modo === 'mes' ? `Cargando la conversión de ${nombreDelMes(mes)}…` : `Cargando la conversión del ${fechaLarga(desde)} al ${fechaLarga(hasta)}…`)
      : datos
        ? `Conversión ${datos.periodo.modo === 'mes' ? 'de' : ''} ${etiquetaPeriodo(datos)}: ${numero(datos.empresa.divisor)} llegadas, ${
            datos.empresa.conversion_pct == null ? 'sin conversión calculable' : porcentajeConversionCanonica(datos.empresa.conversion_pct)
          }${datos.sellado ? '. Mes cerrado: se muestra la foto del cierre' : ''}${datos.periodo.modo === 'rango' ? '. Rango libre: cifras en vivo' : ''}.`
        : estado.error ?? ''

  const chips: Array<{ etiqueta: string; valor: React.ReactNode }> = datos ? [
    { etiqueta: 'Llegadas', valor: numero(datos.empresa.divisor) },
    { etiqueta: 'Formulario', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_formulario} motivo={MOTIVO_SIN_LLEGADAS} /> },
    { etiqueta: 'Landing', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_landing} motivo={MOTIVO_SIN_LLEGADAS} /> },
    { etiqueta: 'Conversión', valor: <Porcentaje valor={datos.empresa.conversion_pct} /> },
    { etiqueta: 'Cierres directos', valor: datos.empresa.cierres ? numero(datos.empresa.cierres.formulario + datos.empresa.cierres.landing) : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Referidos', valor: datos.empresa.cierres ? <CantidadYAporte cantidad={datos.empresa.cierres.referido} aporte={datos.empresa.cierres.referido_aporte} nombre="referidos" /> : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Upgrade', valor: datos.empresa.cartera ? numero(datos.empresa.cartera.upgrade) : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Renovación', valor: datos.empresa.cartera ? <CantidadYAporte cantidad={datos.empresa.cartera.renovacion} aporte={datos.empresa.cartera.renovacion_aporte} nombre="renovaciones" /> : <SinDato motivo={MOTIVO_SELLADO} /> },
  ] : []

  return (
    <Card className="overflow-hidden border-primary/15 shadow-[0_18px_45px_-38px_rgba(17,30,61,0.9)]">
      <SectionHead
        icon={Percent}
        title="Conversiones"
        right={estado.cargando ? (
          <span className="text-[11px] font-semibold text-muted-foreground" aria-hidden="true">
            Actualizando…
          </span>
        ) : undefined}
      />
      {/* Un solo estado vivo, SIEMPRE montado: así el lector sí oye cada cambio. */}
      <p role="status" className="sr-only">{mensajeEstado}</p>
      <p className="px-5 pb-3 text-sm text-muted-foreground">
        Llegadas que pesan en la conversión: una por lead, por su fecha de alta, en el primer analista
        que la recibió. Si el lead se reasigna después, no se le resta. Los cierres se abren por origen
        y por cartera con los mismos pesos que Metas y Ranking.
      </p>

      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-border/70 bg-card px-5 py-4">
        <div className="grid gap-1.5">
          <div className="flex flex-wrap items-end gap-3">
            <label className="grid gap-1.5 text-xs font-semibold text-foreground">
              Período
              <Select
                aria-label="Tipo de período"
                value={modo}
                onChange={(event) => setModo(event.target.value === 'rango' ? 'rango' : 'mes')}
                className="w-40"
              >
                <option value="mes">Mes</option>
                <option value="rango">Rango de fechas</option>
              </Select>
            </label>
            {modo === 'mes' ? (
              <label className="grid gap-1.5 text-xs font-semibold text-foreground">
                Mes
                <Input
                  type="month"
                  aria-label="Mes de conversión"
                  min="2025-01"
                  max={mesMaximo}
                  value={mes}
                  aria-invalid={mesInvalido || undefined}
                  aria-describedby={mesInvalido ? idAyudaMes : undefined}
                  onChange={(event) => setMes(event.target.value)}
                  className="w-44"
                />
              </label>
            ) : (
              <>
                <label className="grid gap-1.5 text-xs font-semibold text-foreground">
                  Desde
                  <Input
                    type="date"
                    aria-label="Desde"
                    min="2025-01-01"
                    max={hoy}
                    value={desde}
                    aria-invalid={mesInvalido || undefined}
                    aria-describedby={mesInvalido ? idAyudaMes : undefined}
                    onChange={(event) => setDesde(event.target.value)}
                    className="w-44"
                  />
                </label>
                <label className="grid gap-1.5 text-xs font-semibold text-foreground">
                  Hasta
                  <Input
                    type="date"
                    aria-label="Hasta"
                    min="2025-01-01"
                    max={hoy}
                    value={hasta}
                    aria-invalid={mesInvalido || undefined}
                    aria-describedby={mesInvalido ? idAyudaMes : undefined}
                    onChange={(event) => setHasta(event.target.value)}
                    className="w-44"
                  />
                </label>
              </>
            )}
          </div>
          {mesInvalido ? (
            <p id={idAyudaMes} className="text-sm font-medium text-destructive">{ayudaMes}</p>
          ) : modo === 'rango' ? (
            <p className="text-xs text-muted-foreground">
              Rango libre: cifras en vivo, sin ajustes de meses ya pagados ni fotos de cierre. Un mes completo se trata como ese mes.
            </p>
          ) : null}
        </div>
        {datos?.sellado ? (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-border bg-muted/60 px-2.5 py-1 text-xs font-semibold text-foreground">
            <Lock className="size-3.5" aria-hidden /> Mes cerrado: se muestra la foto del cierre
          </span>
        ) : null}
      </div>

      {mesInvalido ? null : estado.error ? (
        <PanelError mensaje={estado.error} onReintentar={reintentar} reintentando={estado.cargando} />
      ) : estado.cargando ? (
        <PanelCargando filas={5} />
      ) : datos ? (
        // Destino programático del foco tras reintentar: fuera del orden de Tab,
        // sin anillo (no es un control), igual que el patrón de Repartir.
        <div ref={contenidoRef} tabIndex={-1} role="region" aria-label="Conversión del mes" className="outline-none">
          <div
            role="group"
            aria-label="Resumen de conversión del mes"
            className="grid grid-cols-2 border-b border-border/70 bg-primary/[0.025] sm:grid-cols-4"
          >
            {chips.map(({ etiqueta, valor }, indice) => (
              <div
                key={etiqueta}
                className={`px-5 py-3 ${indice % 2 === 1 ? 'border-l border-border/70' : ''} ${indice % 4 !== 0 ? 'sm:border-l sm:border-border/70' : ''} ${indice >= 2 ? 'border-t border-border/70' : ''} ${indice >= 2 && indice < 4 ? 'sm:border-t-0' : ''}`}
              >
                <p className="text-[11px] font-semibold text-muted-foreground">{etiqueta}</p>
                <p className="mt-0.5 text-xl font-extrabold tabular-nums text-primary">{valor}</p>
              </div>
            ))}
          </div>
          {formula ? (
            <p className="border-b border-border/70 px-5 py-2 text-sm text-muted-foreground" data-testid="formula-numerador">
              {formula}
            </p>
          ) : null}

          {!hayFilas ? (
            produccionSinFilas ? (
              <PanelVacio
                icono={Percent}
                titulo="Sin filas por analista en este mes cerrado"
                detalle="La producción quedó fuera del ranking al sellar el mes y se conserva en el total de la empresa."
              />
            ) : (
              <PanelVacio
                icono={Percent}
                titulo="Sin llegadas en este mes"
                detalle="Cuando entren leads por la hoja o la landing aparecerán aquí, en el analista que los recibió primero."
              />
            )
          ) : (
            <>
              <TablaEnvoltura ariaLabel="Conversión por analista">
                <TheadCrm>
                  <Th rowSpan={2} className="align-bottom">Analista</Th>
                  <Th rowSpan={2} className="hidden align-bottom lg:table-cell">Supervisor</Th>
                  <Th colSpan={3} className="text-center">Llegadas</Th>
                  <Th colSpan={7} className="text-center">Cierres</Th>
                  <Th rowSpan={2} className="text-right align-bottom">Conversión</Th>
                </TheadCrm>
                <TheadCrm>
                  <Th className="hidden text-right lg:table-cell">Form.</Th>
                  <Th className="hidden text-right lg:table-cell">Land.</Th>
                  <Th className="text-right">Total</Th>
                  <Th className="text-right">Form.</Th>
                  <Th className="text-right">Land.</Th>
                  <Th className="text-right" title="Cantidad · aporte al peso del referido">Referido</Th>
                  <Th className="hidden text-right xl:table-cell" title="No pesa en la conversión">Oficina</Th>
                  <Th className="text-right">Upgrade</Th>
                  <Th className="text-right" title="Cantidad · aporte al peso de renovación">Renov.</Th>
                  <Th className="text-right">Ponderados</Th>
                </TheadCrm>
                <tbody>
                  {analistas.visibles.map((analista) => (
                    <FilaAnalista key={analista.analista_id} analista={analista} sellado={datos.sellado} />
                  ))}
                  {sinAnalista && analistas.paginaActual === analistas.paginas - 1 ? (
                    <tr className="border-b border-border last:border-0 bg-muted/30">
                      <Td className="text-base font-medium text-muted-foreground">Sin analista asignado</Td>
                      <Td className="hidden lg:table-cell text-muted-foreground"><SinDato motivo="no aplica" /></Td>
                      <Td className="hidden text-right tabular-nums text-muted-foreground lg:table-cell"><SinDato motivo="no aplica" /></Td>
                      <Td className="hidden text-right tabular-nums text-muted-foreground lg:table-cell"><SinDato motivo="no aplica" /></Td>
                      <Td className="text-right text-base font-extrabold tabular-nums text-muted-foreground">{numero(sinAnalista.divisor)}</Td>
                      {Array.from({ length: 5 }, (_, i) => (
                        <Td key={i} className="text-right tabular-nums text-muted-foreground"><SinDato motivo="no aplica" /></Td>
                      ))}
                      <Td className="hidden text-right tabular-nums text-muted-foreground xl:table-cell"><SinDato motivo="no aplica" /></Td>
                      <Td className="text-right tabular-nums text-muted-foreground"><Cifra valor={sinAnalista.numerador} motivo="sin cierres" /></Td>
                      <Td className="text-right tabular-nums text-muted-foreground"><SinDato motivo="no aplica" /></Td>
                    </tr>
                  ) : null}
                </tbody>
              </TablaEnvoltura>
              <div className="border-t border-border px-4 py-2.5">
                <Paginacion
                  paginaActual={analistas.paginaActual}
                  paginas={analistas.paginas}
                  total={datos.analistas.length}
                  onCambio={setPagina}
                  ariaLabel="Paginación de analistas de conversión"
                />
              </div>
            </>
          )}

          <p className="border-t border-border px-5 py-2 text-xs text-muted-foreground">
            Este conteo es distinto del reporte de entregas: aquel cuenta lo entregado por fecha de entrega
            y deja de sumar la entrega que volvió a la bandeja antes de gestionarse.
          </p>
        </div>
      ) : null}
    </Card>
  )
}
```

### app/src/lib/conversion-coordinacion.test.ts (completo)
```ts
// El candado de paridad del navegador: no recalcula nada, pero se niega a
// pintar un payload cuyas sumas no cierran (formulario + landing = divisor;
// analistas + sin analista = empresa; cierres directos + referidos×peso +
// upgrade + renovación×peso = numerador bruto; neto = bruto − ajuste). Es la
// parte del cinturón que hace que «alguien volvió a calcular fuera del núcleo»
// se vea en pantalla como un error, no como un número inventado.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ConversionCoordinacionSchema,
  conversionCoordinacionConsistente,
  diasInclusivos,
  fechasDeConsulta,
  finDeMes,
  mesActualLima,
  motivoConsultaInvalida,
  periodoDesdeMes,
  sumaDePartes,
  type ConversionCoordinacion,
} from './conversion-coordinacion'

const ASTRID = '2ec5954f-0490-44f2-87cd-af6210f3426f'
const MERLYS = '75c0933c-9cce-4e5f-ae0e-2b4bfd557a37'

/** Setiembre 2026 real: Astrid 5 + 2 + 1 × 0,15 + 4 upgrade = 11,15; Merlys 6 + 1 + 2 upgrade = 9. */
export function payloadValido(): ConversionCoordinacion {
  return {
    version: 1,
    generado_en: '2026-09-30T18:00:00.000Z',
    alcance: 'global',
    periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30 },
    sellado: false,
    peso_referido: 0.15,
    peso_renovacion: 0.15,
    fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead' },
    empresa: {
      divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79,
      numerador_bruto: 20.15, ajuste_pendiente: 0, desglose_disponible: true,
      cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1 },
      cartera: { upgrade: 6, renovacion: 0, renovacion_aporte: 0 },
    },
    sin_analista: { divisor: 2, numerador: 0 },
    analistas: [
      {
        analista_id: ASTRID, nombre: 'ASTRID CENTENARO', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA',
        en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7,
        numerador_bruto: 11.15, ajuste_pendiente: 0, desglose_disponible: true,
        cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1 },
        cartera: { upgrade: 4, renovacion: 0, renovacion_aporte: 0 },
      },
      {
        analista_id: MERLYS, nombre: 'MERLYS GARCIA', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA',
        en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23,
        numerador_bruto: 9, ajuste_pendiente: 0, desglose_disponible: true,
        cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0 },
        cartera: { upgrade: 2, renovacion: 0, renovacion_aporte: 0 },
      },
    ],
  }
}

/** Foto sellada: mismos totales, sin desglose de llegadas, bruto y ajuste en null. */
export function payloadSellado(conDesglose = true): ConversionCoordinacion {
  const datos = payloadValido()
  const sellar = <T extends { cierres: unknown; cartera: unknown }>(fila: T) => ({
    ...fila,
    divisor_formulario: null,
    divisor_landing: null,
    numerador_bruto: null,
    ajuste_pendiente: null,
    desglose_disponible: conDesglose,
    cierres: conDesglose ? fila.cierres : null,
    cartera: conDesglose ? fila.cartera : null,
  })
  return {
    ...datos,
    sellado: true,
    empresa: sellar(datos.empresa) as ConversionCoordinacion['empresa'],
    analistas: datos.analistas.map((a) => sellar(a) as ConversionCoordinacion['analistas'][number]),
  }
}

describe('conversionCoordinacionConsistente', () => {
  it('acepta el payload del núcleo (Astrid 65 + 50 = 115 y 5 + 2 + 0,15 + 4 = 11,15; empresa = analistas + sin analista)', () => {
    expect(conversionCoordinacionConsistente(payloadValido(), '2026-09-01', '2026-09-30')).toBe(true)
  })

  it('rechaza un período distinto del pedido', () => {
    expect(conversionCoordinacionConsistente(payloadValido(), '2026-08-01', '2026-08-31')).toBe(false)
  })

  it('rechaza a un analista cuyo formulario + landing no suman su divisor (el 62 del reporte de entregas)', () => {
    const datos = payloadValido()
    datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: 62 }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('rechaza un numerador bruto que no es la suma de sus partes (un upgrade de más)', () => {
    const datos = payloadValido()
    datos.analistas[0] = { ...datos.analistas[0]!, cartera: { upgrade: 5, renovacion: 0, renovacion_aporte: 0 } }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('rechaza un neto que no es el bruto con el ajuste; acepta el ajuste bien aplicado con suelo en cero', () => {
    const datos = payloadValido()
    datos.analistas[1] = { ...datos.analistas[1]!, ajuste_pendiente: 1 } // neto sigue en 9 pero debería ser 8
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)

    const ajustado = payloadValido()
    ajustado.analistas[1] = { ...ajustado.analistas[1]!, ajuste_pendiente: 1, numerador: 8 }
    ajustado.empresa = { ...ajustado.empresa, ajuste_pendiente: 1, numerador: 19.15 }
    expect(conversionCoordinacionConsistente(ajustado, '2026-09-01', '2026-09-30')).toBe(true)

    const conSuelo = payloadValido()
    conSuelo.analistas[1] = { ...conSuelo.analistas[1]!, ajuste_pendiente: 12, numerador: 0 }
    conSuelo.empresa = { ...conSuelo.empresa, ajuste_pendiente: 12, numerador: 8.15 }
    expect(conversionCoordinacionConsistente(conSuelo, '2026-09-01', '2026-09-30')).toBe(true)
  })

  it('tolera los decimales de los pesos (19 referidos × 0,15 = 2,85) sin falso rojo', () => {
    const datos = payloadValido()
    datos.analistas[0] = {
      ...datos.analistas[0]!,
      cierres: { formulario: 65, landing: 25, referido: 19, referido_aporte: 2.85, oficina: 11 },
      cartera: { upgrade: 24, renovacion: 3, renovacion_aporte: 0.45 },
      numerador_bruto: 117.3, numerador: 117.3,
    }
    datos.empresa = { ...datos.empresa, cierres: { formulario: 71, landing: 26, referido: 19, referido_aporte: 2.85, oficina: 11 }, cartera: { upgrade: 26, renovacion: 3, renovacion_aporte: 0.45 }, numerador_bruto: 126.3, numerador: 126.3 }
    expect(sumaDePartes(datos.analistas[0].cierres!, datos.analistas[0].cartera!)).toBeCloseTo(117.3, 6)
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(true)
  })

  it('rechaza una empresa que no suma analistas + sin analista', () => {
    const datos = payloadValido()
    datos.empresa = { ...datos.empresa, divisor: 204, divisor_formulario: 125 }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('rechaza analistas repetidos', () => {
    const datos = payloadValido()
    datos.analistas.push({ ...datos.analistas[1]! })
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('en un mes sellado exige llegadas por origen, bruto y ajuste en null; el desglose puede venir o no', () => {
    expect(conversionCoordinacionConsistente(payloadSellado(true), '2026-09-01', '2026-09-30')).toBe(true)
    expect(conversionCoordinacionConsistente(payloadSellado(false), '2026-09-01', '2026-09-30')).toBe(true)

    const mezclado = payloadValido()
    mezclado.sellado = true
    expect(conversionCoordinacionConsistente(mezclado, '2026-09-01', '2026-09-30')).toBe(false)

    const sinDesgloseConCifras = payloadSellado(false)
    sinDesgloseConCifras.analistas[0] = { ...sinDesgloseConCifras.analistas[0]!, cierres: payloadValido().analistas[0]!.cierres }
    expect(conversionCoordinacionConsistente(sinDesgloseConCifras, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('en un mes abierto no admite desglose ausente ni llegadas por origen en null', () => {
    const sinLlegadas = payloadValido()
    sinLlegadas.analistas[0] = { ...sinLlegadas.analistas[0]!, divisor_formulario: null }
    expect(conversionCoordinacionConsistente(sinLlegadas, '2026-09-01', '2026-09-30')).toBe(false)

    const sinDesglose = payloadValido()
    sinDesglose.analistas[0] = { ...sinDesglose.analistas[0]!, desglose_disponible: false, cierres: null, cartera: null }
    expect(conversionCoordinacionConsistente(sinDesglose, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('tolera sin_analista nulo y analistas con divisor 0 (sin dividir por cero)', () => {
    const datos = payloadValido()
    datos.sin_analista = null
    datos.empresa = {
      divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0,
      numerador_bruto: 0, ajuste_pendiente: 0, desglose_disponible: true,
      cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0 },
      cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
    }
    datos.analistas = [{
      ...datos.analistas[0]!, divisor: 0, divisor_formulario: 0, divisor_landing: 0, numerador: 0, conversion_pct: null,
      numerador_bruto: 0, cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0 },
      cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
    }]
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(true)
  })
})

describe('ConversionCoordinacionSchema', () => {
  it('acepta numéricos como texto (PostgREST) y rechaza claves de contrato ausentes', () => {
    const crudo = JSON.parse(JSON.stringify(payloadValido())) as Record<string, unknown>
    const primero = (crudo.analistas as Record<string, unknown>[])[0]!
    primero.numerador = '11.15'
    ;(primero.cierres as Record<string, unknown>).referido_aporte = '0.15'
    expect(v.safeParse(ConversionCoordinacionSchema, crudo).success).toBe(true)

    const { empresa: _fuera, ...roto } = crudo
    expect(v.safeParse(ConversionCoordinacionSchema, roto).success).toBe(false)
    expect(v.safeParse(ConversionCoordinacionSchema, { ...crudo, version: 2 }).success).toBe(false)
    expect(v.safeParse(ConversionCoordinacionSchema, { ...crudo, alcance: 'equipo' }).success).toBe(false)
    const { peso_renovacion: _sinPeso, ...sinPeso } = crudo
    expect(v.safeParse(ConversionCoordinacionSchema, sinPeso).success).toBe(false)
  })
})

describe('mesActualLima / periodoDesdeMes', () => {
  it('el mes vigente sale de la hora de Lima, no de UTC (23:30 del 30/09 en Lima sigue siendo setiembre)', () => {
    expect(mesActualLima(new Date('2026-10-01T04:30:00Z'))).toBe('2026-09')
    expect(mesActualLima(new Date('2026-10-01T05:00:00Z'))).toBe('2026-10')
  })

  it('convierte el mes al primer día y rechaza meses inválidos', () => {
    expect(periodoDesdeMes('2026-09')).toBe('2026-09-01')
    expect(periodoDesdeMes('2026-13')).toBeNull()
    expect(periodoDesdeMes('')).toBeNull()
    expect(periodoDesdeMes('2026-09-15')).toBeNull()
  })
})

/** Rango libre del 1 al 15 de setiembre: mismo mundo, sin nombre de mes, sin ajuste, nunca sellado. */
export function payloadRango(): ConversionCoordinacion {
  const datos = payloadValido()
  return {
    ...datos,
    periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: 15 },
  }
}

describe('modo rango (v2)', () => {
  it('acepta un rango cuyo período eco-a desde/hasta y los días inclusivos', () => {
    expect(conversionCoordinacionConsistente(payloadRango(), '2026-09-01', '2026-09-15')).toBe(true)
  })

  it('rechaza un rango que no coincide con lo pedido o con los días mal contados', () => {
    expect(conversionCoordinacionConsistente(payloadRango(), '2026-09-01', '2026-09-16')).toBe(false)
    const dias = payloadRango()
    dias.periodo = { ...dias.periodo, dias: 14 }
    expect(conversionCoordinacionConsistente(dias, '2026-09-01', '2026-09-15')).toBe(false)
  })

  it('un rango libre no puede venir sellado, con nombre de mes ni con ajuste', () => {
    const sellado = payloadRango()
    sellado.sellado = true
    expect(conversionCoordinacionConsistente(sellado, '2026-09-01', '2026-09-15')).toBe(false)
    const conMes = payloadRango()
    conMes.periodo = { ...conMes.periodo, mes: '2026-09' }
    expect(conversionCoordinacionConsistente(conMes, '2026-09-01', '2026-09-15')).toBe(false)
    const conAjuste = payloadRango()
    conAjuste.analistas[1] = { ...conAjuste.analistas[1]!, ajuste_pendiente: 1, numerador: 8 }
    conAjuste.empresa = { ...conAjuste.empresa, ajuste_pendiente: 1, numerador: 19.15 }
    expect(conversionCoordinacionConsistente(conAjuste, '2026-09-01', '2026-09-15')).toBe(false)
  })

  it('un mes exacto exige modo mes con nombre; el modo mes sin nombre se rechaza', () => {
    const sinNombre = payloadValido()
    sinNombre.periodo = { ...sinNombre.periodo, mes_nombre: null }
    expect(conversionCoordinacionConsistente(sinNombre, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('helpers de fechas: fin de mes, días inclusivos y fechas de la consulta', () => {
    expect(finDeMes('2026-09')).toBe('2026-09-30')
    expect(finDeMes('2026-02')).toBe('2026-02-28')
    expect(finDeMes('2028-02')).toBe('2028-02-29')
    expect(finDeMes('2026-13')).toBeNull()
    expect(diasInclusivos('2026-09-01', '2026-09-01')).toBe(1)
    expect(diasInclusivos('2026-09-01', '2026-09-30')).toBe(30)
    expect(fechasDeConsulta({ modo: 'mes', mes: '2026-09' })).toEqual({ desde: '2026-09-01', hasta: '2026-09-30' })
    expect(fechasDeConsulta({ modo: 'mes', mes: 'x' })).toBeNull()
    expect(fechasDeConsulta({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })).toEqual({ desde: '2026-09-01', hasta: '2026-09-15' })
  })

  it('motivoConsultaInvalida: mes futuro, fechas cruzadas, futuro y más de 366 días', () => {
    const hoy = '2026-09-30'
    expect(motivoConsultaInvalida({ modo: 'mes', mes: '2026-09' }, hoy)).toBeNull()
    expect(motivoConsultaInvalida({ modo: 'mes', mes: '2026-10' }, hoy)).toMatch(/no puede ser futuro/)
    expect(motivoConsultaInvalida({ modo: 'mes', mes: '' }, hoy)).toMatch(/mes válido/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' }, hoy)).toBeNull()
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-16', hasta: '2026-09-15' }, hoy)).toMatch(/inicial no puede ser posterior/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-01', hasta: '2026-10-01' }, hoy)).toMatch(/fechas futuras/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2025-09-01', hasta: '2026-09-30' }, hoy)).toMatch(/366 días/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '', hasta: '2026-09-15' }, hoy)).toMatch(/dos fechas/)
  })
})
```

### app/src/components/app/conversion-coordinacion.test.tsx (completo)
```tsx
// La pestaña «Conversiones» de Repartir: pinta lo que sirve la puerta del
// núcleo (Astrid 65 + 50 = 115, 11.15, 9,70 %), pide el primer día del mes
// elegido, degrada con reintento cuando la RPC falla, en un mes sellado enseña
// la foto sin desglose por origen y, para el lector de pantalla, cada «—» dice
// su motivo y el estado se anuncia desde una región siempre montada. Sin red.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ConsultaConversion, ConversionCoordinacion as Datos } from '@/lib/conversion-coordinacion'
import { fechasDeConsulta } from '@/lib/conversion-coordinacion'
import { payloadSellado, payloadValido } from '@/lib/conversion-coordinacion.test'

const conversionMock = vi.fn<(consulta: ConsultaConversion) => Promise<Datos>>()
vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    conversionCoordinacion: (consulta: ConsultaConversion) => conversionMock(consulta),
  }
})

import { ConversionCoordinacion } from './conversion-coordinacion'

const mesActual = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit',
}).format(new Date()).slice(0, 7)

/** Eco del período como lo hace la puerta: mes exacto con nombre, o rango sin nombre. */
function conPeriodo(datos: Datos, consulta: ConsultaConversion): Datos {
  const fechas = fechasDeConsulta(consulta)!
  const dias = Math.round((Date.parse(`${fechas.hasta}T12:00:00Z`) - Date.parse(`${fechas.desde}T12:00:00Z`)) / 86_400_000) + 1
  return consulta.modo === 'mes'
    ? { ...datos, periodo: { ...datos.periodo, modo: 'mes', mes: consulta.mes, desde: fechas.desde, hasta: fechas.hasta, dias } }
    : { ...datos, sellado: false, periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: fechas.desde, hasta: fechas.hasta, dias } }
}

/** Lo que OYE el lector: el «—» va oculto y su motivo, en sr-only. */
const textoHablado = (celda: HTMLElement) => (
  Array.from(celda.querySelectorAll('[aria-hidden="true"]')).reduce(
    (texto, mudo) => texto.replace(mudo.textContent ?? '', ''),
    celda.textContent ?? '',
  )
)

beforeEach(() => {
  conversionMock.mockReset()
  conversionMock.mockImplementation(async (consulta) => conPeriodo(payloadValido(), consulta))
})
afterEach(() => vi.clearAllMocks())

describe('ConversionCoordinacion', () => {
  it('pide el mes vigente en Lima y pinta el divisor del núcleo por analista y por origen', async () => {
    render(<ConversionCoordinacion />)

    expect(await screen.findByRole('heading', { name: 'Conversiones' })).toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledWith({ modo: 'mes', mes: mesActual })

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    // Analista · Supervisor · Llegadas (F, L, total) · Cierres (F, L, referido «n · aporte», oficina, upgrade, renovación «n · aporte», ponderados) · %
    expect(within(astrid).getAllByRole('cell').map(textoHablado))
      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '5', '2', '1 referidos, aportan 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
    expect(within(astrid).getAllByRole('cell')[7]?.querySelector('[aria-hidden="true"]')?.textContent).toBe('1 · 0.15')

    const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
    expect(within(merlys).getAllByRole('cell').map(textoHablado))
      .toEqual(['MERLYS GARCIA', 'SUPERVISORA', '60', '28', '88', '6', '1', '0 referidos, aportan 0', '0', '2', '0 renovaciones, aportan 0', '9', '10.23%'])

    // La fila sin analista: se ve «—» pero se oye «no aplica».
    const sinAnalista = within(tabla).getByRole('row', { name: /Sin analista asignado/ })
    const celdas = within(sinAnalista).getAllByRole('cell')
    expect(celdas.map(textoHablado))
      .toEqual(['Sin analista asignado', 'no aplica', 'no aplica', 'no aplica', '2', 'no aplica', 'no aplica', 'no aplica', 'no aplica', 'no aplica', 'no aplica', '0', 'no aplica'])
    expect(celdas[1]?.querySelector('[aria-hidden="true"]')?.textContent).toBe('—')

    // Cabecera agrupada: Llegadas y Cierres con sus columnas.
    expect(within(tabla).getByRole('columnheader', { name: 'Cierres' })).toHaveAttribute('colspan', '7')
    expect(within(tabla).getByRole('columnheader', { name: 'Upgrade' })).toBeInTheDocument()

    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    const cifra = (etiqueta: string) => within(resumen).getByText(etiqueta).nextElementSibling?.textContent
    expect(cifra('Llegadas')).toBe('205')
    expect(cifra('Formulario')).toBe('126')
    expect(cifra('Landing')).toBe('79')
    expect(cifra('Conversión')).toBe('9.83%')
    expect(cifra('Cierres directos')).toBe('14')
    expect(textoHablado(within(resumen).getByText('Referidos').nextElementSibling as HTMLElement)).toBe('1 referidos, aportan 0.15')
    expect(cifra('Upgrade')).toBe('6')
    expect(textoHablado(within(resumen).getByText('Renovación').nextElementSibling as HTMLElement)).toBe('0 renovaciones, aportan 0')
    expect(screen.getByTestId('formula-numerador')).toHaveTextContent(
      'Cierres ponderados 20.15 = 14 directos (formulario y landing) + 0.15 de referidos (1 × 0.15) + 6 de upgrade + 0 de renovación (0 × 0.15). Oficina (1) no pesa.',
    )

    expect(screen.getByRole('status')).toHaveTextContent('Conversión de setiembre 2026: 205 llegadas, 9.83%.')
    expect(screen.getByText(/Este conteo es distinto del reporte de entregas/)).toBeInTheDocument()
    expect(screen.queryByText(/Mes cerrado/)).not.toBeInTheDocument()
  })

  it('al cambiar el mes vuelve a pedir el primer día de ese mes y anuncia la carga y el resultado', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)
    await usuario.type(mes, '2026-08')

    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith({ modo: 'mes', mes: '2026-08' }))
    expect(screen.getByRole('status')).not.toHaveTextContent('2026-08')
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(/^Conversión de setiembre 2026/))
    expect(mes).not.toHaveAttribute('aria-invalid')
  })

  it('un mes vaciado es un error del formulario, no un fallo de red', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    const llamadas = conversionMock.mock.calls.length

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)

    expect(mes).toHaveAttribute('aria-invalid', 'true')
    expect(mes).toHaveAccessibleDescription('Elige un mes válido (año y mes) para consultar la conversión.')
    expect(screen.getByRole('status')).toHaveTextContent('Elige un mes válido (año y mes) para consultar la conversión.')
    expect(screen.queryByText(/Revisa tu conexión/)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledTimes(llamadas)
  })

  it('en un mes sellado enseña la foto y el lector oye por qué no hay desglose por origen', async () => {
    conversionMock.mockImplementation(async (consulta) => conPeriodo(payloadSellado(true), consulta))
    render(<ConversionCoordinacion />)

    // El chip visible y, aparte, el anuncio del estado: el texto está dos veces a propósito.
    expect(await screen.findByText(/Mes cerrado: se muestra la foto del cierre/, { selector: 'span' })).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    expect(within(astrid).getAllByRole('cell').map(textoHablado))
      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', 'sin desglose: mes cerrado', 'sin desglose: mes cerrado', '115', '5', '2', '1 referidos, aportan 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(textoHablado(within(resumen).getByText('Formulario').nextElementSibling as HTMLElement)).toBe('sin desglose: mes cerrado')
    expect(screen.getByRole('status')).toHaveTextContent(/Mes cerrado: se muestra la foto del cierre/)
  })

  it('sin llegadas muestra el vacío honesto y un divisor 0 no rompe nada', async () => {
    conversionMock.mockImplementation(async (consulta) => ({
      ...conPeriodo(payloadValido(), consulta),
      empresa: {
        divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0,
        numerador_bruto: 0, ajuste_pendiente: 0, desglose_disponible: true,
        cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0 },
        cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
      },
      sin_analista: null,
      analistas: [],
    }))
    render(<ConversionCoordinacion />)

    expect(await screen.findByText('Sin llegadas en este mes')).toBeInTheDocument()
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(textoHablado(within(resumen).getByText('Conversión').nextElementSibling as HTMLElement)).toBe('sin llegadas')
    expect(screen.getByRole('status')).toHaveTextContent('0 llegadas, sin conversión calculable')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('si la puerta falla, degrada con el mensaje real, reintenta y aterriza el foco en el contenido', async () => {
    const usuario = userEvent.setup()
    conversionMock.mockRejectedValueOnce(new Error('No tienes permiso para consultar la conversión por analista.'))
    render(<ConversionCoordinacion />)

    expect(await screen.findByText('No tienes permiso para consultar la conversión por analista.', { selector: 'p:not([role="status"])' })).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('No tienes permiso para consultar la conversión por analista.')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()

    await usuario.click(screen.getByRole('button', { name: /Reintentar/ }))
    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    expect(conversionMock).toHaveBeenCalledTimes(2)
    await waitFor(() => expect(document.activeElement).not.toBe(document.body))
    expect(document.activeElement?.contains(tabla)).toBe(true)
  })

  it('un mes futuro tecleado a mano es un error del formulario y no llama a la puerta', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    const llamadas = conversionMock.mock.calls.length

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)
    await usuario.type(mes, '2999-01')

    expect(mes).toHaveAttribute('aria-invalid', 'true')
    expect(mes).toHaveAccessibleDescription(`El mes no puede ser futuro: elige ${mesActual} o anterior.`)
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledTimes(llamadas)
  })

  it('un mes cerrado con producción solo fuera del ranking no dice «sin llegadas»', async () => {
    conversionMock.mockImplementation(async (consulta) => ({
      ...conPeriodo(payloadSellado(false), consulta),
      empresa: {
        divisor: 5, numerador: 1, conversion_pct: 20, divisor_formulario: null, divisor_landing: null,
        numerador_bruto: null, ajuste_pendiente: null, desglose_disponible: false, cierres: null, cartera: null,
      },
      sin_analista: null,
      analistas: [],
    }))
    render(<ConversionCoordinacion />)

    expect(await screen.findByText('Sin filas por analista en este mes cerrado')).toBeInTheDocument()
    expect(screen.queryByText('Sin llegadas en este mes')).not.toBeInTheDocument()
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(within(resumen).getByText('Llegadas').nextElementSibling?.textContent).toBe('5')
  })

  it('cambiar de mes tras un fallo no arrastra el error viejo ni roba el foco al campo', async () => {
    const usuario = userEvent.setup()
    conversionMock.mockRejectedValueOnce(new Error('Caída'))
    render(<ConversionCoordinacion />)
    expect(await screen.findByRole('button', { name: /Reintentar/ })).toBeInTheDocument()

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)
    await usuario.type(mes, '2026-08')

    await screen.findByRole('table', { name: 'Conversión por analista' })
    expect(screen.queryByText('Caída')).not.toBeInTheDocument()
    expect(mes).toHaveFocus()
  })

  it('en un mes cerrado sin desglose en la foto, cada celda de cierres dice por qué', async () => {
    conversionMock.mockImplementation(async (consulta) => conPeriodo(payloadSellado(false), consulta))
    render(<ConversionCoordinacion />)

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    const celdas = within(astrid).getAllByRole('cell').map(textoHablado)
    expect(celdas.slice(5, 11)).toEqual(Array(6).fill('sin desglose: mes cerrado'))
    expect(celdas[11]).toBe('11.15')
    expect(screen.queryByTestId('formula-numerador')).not.toBeInTheDocument()
  })

  it('cuando hay ajuste de meses pagados, la celda de ponderados lo explica', async () => {
    conversionMock.mockImplementation(async (consulta) => {
      const datos = conPeriodo(payloadValido(), consulta)
      datos.analistas[1] = { ...datos.analistas[1]!, ajuste_pendiente: 1, numerador: 8 }
      datos.empresa = { ...datos.empresa, ajuste_pendiente: 1, numerador: 19.15 }
      return datos
    })
    render(<ConversionCoordinacion />)

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
    expect(within(merlys).getAllByRole('cell')[11]).toHaveTextContent('8bruto 9 − ajuste 1')
    expect(screen.getByTestId('formula-numerador')).toHaveTextContent('− 1 de ajuste de meses ya pagados = 19.15 netos')
  })

  it('en modo rango pide las dos fechas inclusivas y anuncia el rango en vivo', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })

    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
    expect(screen.getByText(/Rango libre: cifras en vivo/, { selector: 'p:not([role="status"])' })).toBeInTheDocument()
    const desde = screen.getByLabelText('Desde')
    const hasta = screen.getByLabelText('Hasta')
    await usuario.clear(desde)
    await usuario.type(desde, '2026-09-01')
    await usuario.clear(hasta)
    await usuario.type(hasta, '2026-09-15')

    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' }))
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(/^Conversión\s+del 1 de setiembre de 2026 al 15 de setiembre de 2026:/))
    expect(screen.getByRole('status')).toHaveTextContent('Rango libre: cifras en vivo')
    expect(screen.queryByText(/Mes cerrado/)).not.toBeInTheDocument()
  })

  it('un rango con la fecha inicial después de la final es un error del formulario, sin llamar a la puerta', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith(expect.objectContaining({ modo: 'rango' })))
    const llamadas = conversionMock.mock.calls.length

    const desde = screen.getByLabelText('Desde')
    await usuario.clear(desde)
    await usuario.type(desde, '2026-09-20')
    const hasta = screen.getByLabelText('Hasta')
    await usuario.clear(hasta)
    await usuario.type(hasta, '2026-09-10')

    expect(hasta).toHaveAttribute('aria-invalid', 'true')
    expect(hasta).toHaveAccessibleDescription('La fecha inicial no puede ser posterior a la final.')
    expect(screen.getByRole('status')).toHaveTextContent('La fecha inicial no puede ser posterior a la final.')
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    // Hubo llamadas mientras se tecleaban fechas válidas intermedias; ninguna con el rango cruzado.
    expect(conversionMock.mock.calls.slice(llamadas).every(([c]) => c.modo !== 'rango' || c.desde <= c.hasta)).toBe(true)
  })
})
```

### Diff: crm-api.ts, tests existentes, e2e, test-rls.mjs, oráculo
```diff
diff --git a/CRM-Avance-Corp/app/e2e/_helpers.ts b/CRM-Avance-Corp/app/e2e/_helpers.ts
index 6f1a7fac..6df52fc0 100644
--- a/CRM-Avance-Corp/app/e2e/_helpers.ts
+++ b/CRM-Avance-Corp/app/e2e/_helpers.ts
@@ -2715,12 +2715,21 @@ export async function montarBackendReal(
       ))
     }
     if (p === '/rest/v1/rpc/conversion_divisor_coordinacion_fn' && method === 'POST') {
-      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
-      const periodo = String(body.p_periodo ?? '')
+      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string; p_desde?: string; p_hasta?: string }
       if (!estado.conversionCoordinacion) return json(route, { code: '42501', message: 'No autorizado' }, 403)
+      // Eco del período como lo hace la RPC: mes exacto (con nombre) o rango inclusivo.
+      const desde = String(body.p_desde ?? body.p_periodo ?? '')
+      const [anio, mesNum] = desde.split('-').map(Number)
+      const finDeMes = new Date(Date.UTC(anio, mesNum, 0)).toISOString().slice(0, 10)
+      const hasta = String(body.p_hasta ?? finDeMes)
+      const esMes = desde.endsWith('-01') && hasta === finDeMes
+      const dias = Math.round((Date.parse(`${hasta}T12:00:00Z`) - Date.parse(`${desde}T12:00:00Z`)) / 86_400_000) + 1
+      const base = estado.conversionCoordinacion.periodo as Record<string, unknown>
       return json(route, {
         ...estado.conversionCoordinacion,
-        periodo: { ...(estado.conversionCoordinacion.periodo as Record<string, unknown>), mes: periodo.slice(0, 7), desde: periodo },
+        periodo: esMes
+          ? { ...base, modo: 'mes', mes: desde.slice(0, 7), desde, hasta, dias }
+          : { ...base, modo: 'rango', mes: null, mes_nombre: null, anio: null, desde, hasta, dias },
       })
     }
     if (p === '/rest/v1/rpc/panel_distribucion_reparto') {
diff --git a/CRM-Avance-Corp/app/e2e/repartir.spec.ts b/CRM-Avance-Corp/app/e2e/repartir.spec.ts
index e03ab24e..20de86ea 100644
--- a/CRM-Avance-Corp/app/e2e/repartir.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/repartir.spec.ts
@@ -211,22 +211,34 @@ test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista),
       version: 1,
       generado_en: '2026-09-30T18:00:00.000Z',
       alcance: 'global',
-      periodo: { mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-10-01' },
+      periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30 },
       sellado: false,
-      peso_referido: 0.5,
+      peso_referido: 0.15,
+      peso_renovacion: 0.15,
       fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead' },
-      empresa: { divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79 },
+      empresa: {
+        divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79,
+        numerador_bruto: 20.15, ajuste_pendiente: 0, desglose_disponible: true,
+        cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1 },
+        cartera: { upgrade: 6, renovacion: 0, renovacion_aporte: 0 },
+      },
       sin_analista: { divisor: 2, numerador: 0 },
       analistas: [
         {
           analista_id: '20000000-0000-4000-8000-000000000001', nombre: 'ANA TORRES',
           supervisor_id: '10000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA NORTE',
           en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7,
+          numerador_bruto: 11.15, ajuste_pendiente: 0, desglose_disponible: true,
+          cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1 },
+          cartera: { upgrade: 4, renovacion: 0, renovacion_aporte: 0 },
         },
         {
           analista_id: '20000000-0000-4000-8000-000000000002', nombre: 'BRUNO LEÓN',
           supervisor_id: '10000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA NORTE',
           en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23,
+          numerador_bruto: 9, ajuste_pendiente: 0, desglose_disponible: true,
+          cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0 },
+          cartera: { upgrade: 2, renovacion: 0, renovacion_aporte: 0 },
         },
       ],
     },
@@ -245,7 +257,10 @@ test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista),
   const ana = tabla.getByRole('row').filter({ hasText: 'ANA TORRES' })
   await expect(ana).toContainText('65')
   await expect(ana).toContainText('115')
+  await expect(ana).toContainText('1 · 0.15')
   await expect(ana).toContainText('9.70%')
+  await expect(cifra('Upgrade').getByText('6', { exact: true })).toBeVisible()
+  await expect(page.getByTestId('formula-numerador')).toContainText('6 de upgrade')
   await expect(tabla.getByRole('row').filter({ hasText: 'Sin analista asignado' })).toContainText('2')
   await expect(page.getByText(/Este conteo es distinto del reporte de entregas/)).toBeVisible()
 
@@ -255,6 +270,17 @@ test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista),
     && (req.postDataJSON() as { p_periodo?: string })?.p_periodo === '2026-08-01')
   await mes.fill('2026-08')
   await pedido
+
+  // Rango de fechas: viajan las dos fechas inclusivas y la pantalla lo dice.
+  await page.getByLabel('Tipo de período').selectOption('rango')
+  const pedidoRango = page.waitForRequest((req) => req.url().includes('/rpc/conversion_divisor_coordinacion_fn')
+    && (req.postDataJSON() as { p_desde?: string })?.p_desde === '2026-09-01'
+    && (req.postDataJSON() as { p_hasta?: string })?.p_hasta === '2026-09-15')
+  await page.getByLabel('Desde').fill('2026-09-01')
+  await page.getByLabel('Hasta').fill('2026-09-15')
+  await pedidoRango
+  await expect(page.getByText(/Rango libre: cifras en vivo/).first()).toBeVisible()
+  await expect(tabla.getByRole('row').filter({ hasText: 'ANA TORRES' })).toContainText('115')
 })
 
 test('Coordinación muestra la entrega real antes de que Supervisión la reparta a analistas', async ({ page }) => {
diff --git a/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts b/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
index 421a7363..0e31d03b 100644
--- a/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
@@ -678,34 +678,54 @@ describe('conversionCoordinacion (crm.conversion_divisor_coordinacion_fn)', () =
       })
     }))
 
-    const datos = await conversionCoordinacion('2026-09-01')
+    const datos = await conversionCoordinacion({ modo: 'mes', mes: '2026-09' })
     expect(cuerpo).toEqual({ p_periodo: '2026-09-01' })
     expect(datos.empresa.divisor).toBe(205)
     expect(datos.empresa.numerador).toBe(20.15)
     expect(datos.analistas[0]).toMatchObject({ divisor: 115, divisor_formulario: 65, divisor_landing: 50, conversion_pct: 9.7 })
   })
 
-  it('rechaza un período que no es el primer día del mes sin tocar la red', async () => {
-    await expect(conversionCoordinacion('2026-09-15')).rejects.toMatchObject({ code: 'PERIODO_INVALIDO' })
+  it('rechaza un mes mal formado y un rango cruzado sin tocar la red', async () => {
+    await expect(conversionCoordinacion({ modo: 'mes', mes: '2026-09-15' })).rejects.toMatchObject({ code: 'PERIODO_INVALIDO' })
+    await expect(conversionCoordinacion({ modo: 'rango', desde: '2026-09-16', hasta: '2026-09-15' })).rejects.toMatchObject({ code: 'PERIODO_INVALIDO' })
+  })
+
+  it('en modo rango manda p_desde/p_hasta y exige que el servidor eco-e el rango inclusivo', async () => {
+    let cuerpo: unknown = null
+    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), async ({ request }) => {
+      cuerpo = await request.json()
+      const datos = conversionValida()
+      return HttpResponse.json({
+        ...datos,
+        periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: '15' },
+      })
+    }))
+    const datos = await conversionCoordinacion({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })
+    expect(cuerpo).toEqual({ p_desde: '2026-09-01', p_hasta: '2026-09-15' })
+    expect(datos.periodo).toMatchObject({ modo: 'rango', dias: 15 })
+
+    // Si el servidor devolviera el mes entero para un rango pedido, se rechaza.
+    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(conversionValida())))
+    await expect(conversionCoordinacion({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_INCONSISTENTE' })
   })
 
   it('fail-closed: un payload fuera de contrato no se devuelve a medias', async () => {
     const { analistas: _fuera, ...roto } = conversionValida()
     server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(roto)))
-    await expect(conversionCoordinacion('2026-09-01')).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_CONTRACT' })
+    await expect(conversionCoordinacion({ modo: 'mes', mes: '2026-09' })).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_CONTRACT' })
   })
 
   it('PARIDAD: si formulario + landing no suman el divisor (el 62 del reporte), el paquete se rechaza entero', async () => {
     const datos = conversionValida()
     datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: 62 }
     server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(datos)))
-    await expect(conversionCoordinacion('2026-09-01')).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_INCONSISTENTE' })
+    await expect(conversionCoordinacion({ modo: 'mes', mes: '2026-09' })).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_INCONSISTENTE' })
   })
 
   it('el gate de rol (42501) sube con su código y un mensaje entendible', async () => {
     server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () =>
       HttpResponse.json({ code: '42501', message: 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista' }, { status: 403 })))
-    const fallo = await conversionCoordinacion('2026-09-01').catch((e: unknown) => e)
+    const fallo = await conversionCoordinacion({ modo: 'mes', mes: '2026-09' }).catch((e: unknown) => e)
     expect(fallo).toBeInstanceOf(CrmApiError)
     expect(fallo).toMatchObject({ code: '42501', message: 'No tienes permiso para consultar la conversión por analista.' })
   })
diff --git a/CRM-Avance-Corp/app/src/data/crm-api.ts b/CRM-Avance-Corp/app/src/data/crm-api.ts
index ec71d4bd..46bdf8c7 100644
--- a/CRM-Avance-Corp/app/src/data/crm-api.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-api.ts
@@ -134,6 +134,10 @@ import {
 import {
   ConversionCoordinacionSchema,
   conversionCoordinacionConsistente,
+  fechasDeConsulta,
+  hoyLima,
+  motivoConsultaInvalida,
+  type ConsultaConversion,
   type ConversionCoordinacion,
 } from '@/lib/conversion-coordinacion'
 import { ESTADOS_CONTRATO_PDF, type EstadoContratoPdf } from '@/lib/contrato-pdf-archivo'
@@ -5640,21 +5644,26 @@ export async function listarMetricasVendedores(
  * dice; si las sumas del payload no cierran, se rechaza el paquete entero.
  */
 export async function conversionCoordinacion(
-  periodo: string,
+  consultaPedida: ConsultaConversion,
   signal?: AbortSignal,
 ): Promise<ConversionCoordinacion> {
-  if (!v.safeParse(FechaSchema, periodo).success || !periodo.endsWith('-01')) {
-    throw new CrmApiError('El mes de conversión no es válido.', 'PERIODO_INVALIDO')
+  const fechas = fechasDeConsulta(consultaPedida)
+  const motivo = motivoConsultaInvalida(consultaPedida, hoyLima())
+  if (!fechas || motivo) {
+    throw new CrmApiError(motivo ?? 'El período de conversión no es válido.', 'PERIODO_INVALIDO')
   }
   lanzarAbortSiCorresponde(signal)
-  let consulta = cliente().schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_periodo: periodo })
+  const argumentos = consultaPedida.modo === 'mes'
+    ? { p_periodo: fechas.desde }
+    : { p_desde: fechas.desde, p_hasta: fechas.hasta }
+  let consulta = cliente().schema('crm').rpc('conversion_divisor_coordinacion_fn', argumentos)
   if (signal) consulta = consulta.abortSignal(signal)
   const { data, error } = await consulta
   lanzarAbortSiCorresponde(signal)
   if (error) {
     const fallo = new CrmApiError(
       error.code === '22023'
-        ? 'El mes de conversión no es válido.'
+        ? 'El período de conversión no es válido.'
         : error.code === '42501' || error.code === 'PGRST301'
           ? 'No tienes permiso para consultar la conversión por analista.'
           : 'No se pudo cargar la conversión por analista.',
@@ -5672,7 +5681,7 @@ export async function conversionCoordinacion(
     registrarError('crm.reparto.conversion_coordinacion_fuera_de_contrato', fallo)
     throw fallo
   }
-  if (!conversionCoordinacionConsistente(resultado.output, periodo)) {
+  if (!conversionCoordinacionConsistente(resultado.output, fechas.desde, fechas.hasta)) {
     const fallo = new CrmApiError(
       'La conversión por analista no reconcilia con el núcleo y no se mostrará.',
       'CONVERSION_COORDINACION_INCONSISTENTE',
diff --git a/CRM-Avance-Corp/app/src/screens/repartir.test.tsx b/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
index 997de6e7..9a47dae0 100644
--- a/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
@@ -84,10 +84,15 @@ let REPORTE_DIARIO: ReporteDerivacionesCoordinacion = {
   }],
 }
 const reporteDiarioMock = vi.fn(async (_desde: string, _hasta: string) => REPORTE_DIARIO)
-const conversionMock = vi.fn(async (periodo: string) => ({
-  ...payloadConversionValido(),
-  periodo: { ...payloadConversionValido().periodo, mes: periodo.slice(0, 7), desde: periodo },
-}))
+const conversionMock = vi.fn(async (consulta: { modo: 'mes'; mes: string } | { modo: 'rango'; desde: string; hasta: string }) => {
+  const base = payloadConversionValido()
+  if (consulta.modo === 'rango') {
+    return { ...base, periodo: { modo: 'rango' as const, mes: null, mes_nombre: null, anio: null, zona: 'America/Lima' as const, desde: consulta.desde, hasta: consulta.hasta, dias: 1 } }
+  }
+  const [anio, mesNum] = consulta.mes.split('-').map(Number) as [number, number]
+  const hasta = new Date(Date.UTC(anio, mesNum, 0)).toISOString().slice(0, 10)
+  return { ...base, periodo: { ...base.periodo, mes: consulta.mes, desde: `${consulta.mes}-01`, hasta, dias: Number(hasta.slice(8)) } }
+})
 let AGENDA: AgendaRepartoDiaria = {
   version: 1,
   fecha_desde: fechaHoyLima,
@@ -116,7 +121,7 @@ vi.mock('@/data/crm-api', async (importActual) => {
     historialDerivaciones: () => historialMock(),
     panelDistribucionReparto: () => panelMock(),
     listarReporteDerivacionesCoordinacion: (desde: string, hasta: string) => reporteDiarioMock(desde, hasta),
-    conversionCoordinacion: (periodo: string) => conversionMock(periodo),
+    conversionCoordinacion: (consulta: Parameters<typeof conversionMock>[0]) => conversionMock(consulta),
     agendaRepartoDiaria: () => agendaMock(),
     guardarAgendaRepartoDiaria: (fecha: string, landing: string, formulario: string) => guardarAgendaMock(fecha, landing, formulario),
   }
@@ -716,12 +721,17 @@ describe('pantalla Repartir leads', () => {
     await usuario.click(screen.getByRole('tab', { name: 'Conversiones' }))
     expect(await screen.findByRole('heading', { name: 'Conversiones' })).toBeInTheDocument()
     expect(conversionMock).toHaveBeenCalledTimes(1)
-    expect(conversionMock.mock.calls[0]?.[0]).toMatch(/^\d{4}-\d{2}-01$/)
+    expect(conversionMock.mock.calls[0]?.[0]).toEqual({ modo: 'mes', mes: expect.stringMatching(/^\d{4}-\d{2}$/) })
 
     const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
     const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
-    expect(within(astrid).getAllByRole('cell').map((celda) => celda.textContent))
-      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '11.15', '9.70%'])
+    const celdas = within(astrid).getAllByRole('cell').map((celda) => celda.textContent ?? '')
+    expect(celdas[0]).toBe('ASTRID CENTENARO')
+    expect(celdas.slice(2, 5)).toEqual(['65', '50', '115'])            // llegadas: formulario, landing, total
+    expect(celdas[7]).toContain('1 · 0.15')                              // referidos: cantidad · aporte
+    expect(celdas[9]).toBe('4')                                          // upgrade
+    expect(celdas[11]).toBe('11.15')                                     // cierres ponderados
+    expect(celdas[12]).toBe('9.70%')
     expect(screen.getByText(/Este conteo es distinto del reporte de entregas/)).toBeInTheDocument()
   })
 })
diff --git a/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql b/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
index 3caccf21..11af1f1a 100644
--- a/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
+++ b/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
@@ -22,9 +22,14 @@
 --       por origen va en null y el núcleo vivo rechaza recalcularlo.
 --   E08 huellas: los conteos operativos y el núcleo conservan su cuerpo del
 --       30/09/2026 (este cambio no los toca).
+--   E09 (v2, desglose + rango): el desglose de cierres suma el numerador y casa con
+--       el núcleo; un rango que es el mes exacto se trata como el mes (también sellado);
+--       del 1 a hoy reproduce el mes; rangos inválidos (fechas cruzadas, futuro, > 366
+--       días, mes y rango a la vez) → 22023; un rango parcial no supera al mes.
 --
 -- Requiere un banco con el esquema de producción, `crm.conversion_pesos`,
--- las políticas SLA y la migración 20260930185623 aplicada. No deja datos.
+-- las políticas SLA y las migraciones 20260930185623 y 20260930221500 (v2) aplicadas.
+-- No deja datos.
 -- Correr con psql -f (un mensaje por sentencia): `statement_timestamp()` avanza
 -- entre llamadas y el oráculo lo tolera.
 
@@ -40,16 +45,20 @@ set local timezone = 'America/Lima';
 -- ─────────────────────────────────────────────────────────────────────────────
 do $estructura$
 declare
-  v_nucleo regprocedure := to_regprocedure('private.conversion_divisor_empresa(date)');
-  v_totales regprocedure := to_regprocedure('private.conversion_divisor_empresa_totales(date)');
-  v_puerta regprocedure := to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)');
+  v_base regprocedure := to_regprocedure('private.conversion_divisor_base(date,date)');
+  v_nucleo regprocedure := to_regprocedure('private.conversion_divisor_empresa(date,date)');
+  v_totales regprocedure := to_regprocedure('private.conversion_divisor_empresa_totales(date,date)');
+  v_puerta regprocedure := to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)');
   v_cuerpo text;
 begin
-  if v_nucleo is null or v_totales is null or v_puerta is null then
-    raise exception 'E01a faltan las funciones de la conversión de Coordinación';
+  if v_base is null or v_nucleo is null or v_totales is null or v_puerta is null then
+    raise exception 'E01a faltan las funciones de la conversión de Coordinación (v2)';
   end if;
-  if (select count(*) from pg_proc p where p.oid in (v_nucleo, v_totales, v_puerta)
-        and p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""']) <> 3 then
+  if to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)') is not null then
+    raise exception 'E01h la firma vieja de la puerta sigue viva junto a la nueva';
+  end if;
+  if (select count(*) from pg_proc p where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
+        and p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""']) <> 4 then
     raise exception 'E01b deben ser STABLE, SECURITY DEFINER y search_path vacío';
   end if;
   if not has_function_privilege('authenticated', v_puerta, 'execute')
@@ -58,12 +67,12 @@ begin
      or has_function_privilege('public', v_puerta, 'execute')
      or (select bool_or(has_function_privilege(r, f, 'execute'))
          from unnest(array['authenticated','anon','service_role','public']) r,
-              unnest(array[v_nucleo, v_totales]) f) then
+              unnest(array[v_base, v_nucleo, v_totales]) f) then
     raise exception 'E01c ACL inesperada';
   end if;
   for v_cuerpo in
     select regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g')
-    from pg_proc p where p.oid in (v_nucleo, v_totales, v_puerta)
+    from pg_proc p where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
   loop
     if v_cuerpo ~ '\mcrm\.\s*leads\M' or v_cuerpo ~ '"leads"' or v_cuerpo ~ '\mlead_asignaciones\M' then
       raise exception 'E01d DISPERSIÓN: la conversión de Coordinación vuelve a contar leads o el ledger';
@@ -74,9 +83,13 @@ begin
   if v_cuerpo ~ '\m(from|join)\s+crm\.' or v_cuerpo ~ '\m(from|join)\s+public\.' then
     raise exception 'E01g SALTO DE CAPA: la puerta lee tablas en vez de delegar en el núcleo';
   end if;
+  select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_base;
+  if v_cuerpo !~ 'private\.conversion_neta_por_vendedor\(' or v_cuerpo !~ 'private\.conversion_mensual_por_vendedor\(' then
+    raise exception 'E01e la base debe leer conversion_neta_por_vendedor (mes) y conversion_mensual_por_vendedor (rango)';
+  end if;
   select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_nucleo;
-  if v_cuerpo !~ 'private\.conversion_neta_por_vendedor\(' or v_cuerpo !~ 'private\.conversion_episodios\(' then
-    raise exception 'E01e el núcleo de Coordinación debe leer conversion_neta_por_vendedor y conversion_episodios';
+  if v_cuerpo !~ 'private\.conversion_divisor_base\(' or v_cuerpo !~ 'private\.conversion_episodios\(' then
+    raise exception 'E01e el núcleo debe leer conversion_divisor_base y conversion_episodios';
   end if;
   select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_puerta;
   if v_cuerpo !~ 'private\.puede_operar_reparto_crm\(\)' then
@@ -469,6 +482,7 @@ reset role;
 do $paridad$
 declare
   v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
+  v_fin date := (date_trunc('month', now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date;
   v_pay jsonb := current_setting('oraculo.pay')::jsonb;
 begin
   if exists (
@@ -487,6 +501,21 @@ begin
   ) then
     raise exception 'E05a la pantalla no reproduce el núcleo fila a fila';
   end if;
+  -- v2: cada analista trae desglose y sus partes suman el numerador bruto; el neto lleva el ajuste.
+  if exists (
+    select 1 from jsonb_array_elements(v_pay->'analistas') a
+    where (a->>'desglose_disponible')::boolean is not true
+       or (a->>'numerador_bruto')::numeric is distinct from
+          (a#>>'{cierres,formulario}')::numeric + (a#>>'{cierres,landing}')::numeric + (a#>>'{cierres,referido_aporte}')::numeric
+          + (a#>>'{cartera,upgrade}')::numeric + (a#>>'{cartera,renovacion_aporte}')::numeric
+       or (a->>'numerador')::numeric is distinct from private.conversion_con_ajuste((a->>'numerador_bruto')::numeric, (a->>'ajuste_pendiente')::numeric)
+  ) then
+    raise exception 'E05f el desglose de cierres no suma el numerador en el payload';
+  end if;
+  if v_pay->'periodo'->>'modo' is distinct from 'mes' or (v_pay->'periodo'->>'dias')::int is distinct from (v_fin - v_mes + 1)
+     or (v_pay->'periodo'->>'hasta')::date is distinct from v_fin then
+    raise exception 'E05g el período del payload no describe el mes (modo, dias, hasta inclusivo): %', v_pay->'periodo';
+  end if;
   -- La fila SIN analista del núcleo (id nulo) es exactamente `sin_analista`.
   if (v_pay->'sin_analista'->>'divisor')::int is distinct from
      (select n.divisor from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n where n.analista_id is null) then
@@ -506,6 +535,93 @@ end;
 $paridad$;
 set local role authenticated;
 
+-- ─────────────────────────────────────────────────────────────────────────────
+-- E09 · Modo rango
+-- ─────────────────────────────────────────────────────────────────────────────
+do $rango$
+declare
+  v_coord uuid := 'c0000000-0000-4000-8000-000000000001';
+  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
+  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
+  v_fin date := (date_trunc('month', now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date;
+  v_hoy date := (now() at time zone 'America/Lima')::date;
+  v_mes_sellado date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
+  v_pay_mes jsonb;
+  v_pay jsonb;
+begin
+  perform set_config('request.jwt.claim.sub', v_coord::text, true);
+  v_pay_mes := crm.conversion_divisor_coordinacion_fn(v_mes);
+
+  -- (a) Un rango que es exactamente el mes calendario ES el mes (misma foto, salvo el reloj).
+  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes, v_fin);
+  if (v_pay - 'generado_en') <> (v_pay_mes - 'generado_en') then
+    raise exception 'E09a el rango 1 → fin de mes no es idéntico al mes';
+  end if;
+
+  -- (b) Del 1 a hoy: modo rango (salvo el último día del mes, en que ES el mes),
+  --     reproduce las cifras del mes (nada vive en el futuro), sin ajuste.
+  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes, v_hoy);
+  if v_pay->'periodo'->>'modo' <> (case when v_hoy = v_fin then 'mes' else 'rango' end)
+     or (v_pay->>'sellado')::boolean
+     or (v_pay->'periodo'->>'dias')::int <> (v_hoy - v_mes + 1)
+     or (v_hoy <> v_fin and v_pay->'periodo'->'mes' <> 'null'::jsonb)
+     or (v_pay->'empresa'->>'divisor')::int is distinct from (v_pay_mes->'empresa'->>'divisor')::int
+     or (v_pay->'empresa'->>'numerador')::numeric is distinct from (v_pay_mes->'empresa'->>'numerador')::numeric
+     or (v_pay->'empresa'->>'ajuste_pendiente')::numeric is distinct from 0
+     or (select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 2 then
+    raise exception 'E09b el rango 1 → hoy no reproduce el mes: % vs %', v_pay->'empresa', v_pay_mes->'empresa';
+  end if;
+
+  -- (c) Un rango parcial no puede superar al mes (L1 y L2 nacieron hoy: del 1 a ayer ANA no las tiene).
+  if v_hoy > v_mes then
+    v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes, v_hoy - 1);
+    if coalesce((select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text), 0) <> 0 then
+      raise exception 'E09c el rango que termina ayer atribuye a ANA llegadas de hoy';
+    end if;
+  end if;
+
+  -- (d) Un rango que es exactamente el mes sellado sirve la foto (sellado = true).
+  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes_sellado, (v_mes_sellado + interval '1 month' - interval '1 day')::date);
+  if (v_pay->>'sellado')::boolean is not true or v_pay->'periodo'->>'modo' <> 'mes' then
+    raise exception 'E09d el rango del mes sellado no sirvió la foto: %', v_pay->'periodo';
+  end if;
+
+  -- (e) Rangos inválidos → 22023 (gate primero: sigue siendo la coordinadora).
+  begin
+    perform crm.conversion_divisor_coordinacion_fn(null, v_hoy, v_hoy - 1);
+    raise exception 'E09e aceptó desde > hasta';
+  exception when sqlstate '22023' then null;
+  end;
+  begin
+    perform crm.conversion_divisor_coordinacion_fn(null, v_hoy, v_hoy + 1);
+    raise exception 'E09f aceptó un rango con futuro';
+  exception when sqlstate '22023' then null;
+  end;
+  begin
+    perform crm.conversion_divisor_coordinacion_fn(null, v_hoy - 366, v_hoy);
+    raise exception 'E09g aceptó un rango de más de 366 días';
+  exception when sqlstate '22023' then null;
+  end;
+  begin
+    perform crm.conversion_divisor_coordinacion_fn(v_mes, v_mes, v_hoy);
+    raise exception 'E09h aceptó mes y rango a la vez';
+  exception when sqlstate '22023' then null;
+  end;
+  begin
+    perform crm.conversion_divisor_coordinacion_fn(null, v_mes, null);
+    raise exception 'E09i aceptó un rango con una sola fecha';
+  exception when sqlstate '22023' then null;
+  end;
+  -- Y un vendedor con rango sigue fuera (42501 antes que cualquier validación).
+  perform set_config('request.jwt.claim.sub', v_ana::text, true);
+  begin
+    perform crm.conversion_divisor_coordinacion_fn(null, v_mes, v_hoy);
+    raise exception 'E09j un vendedor entró por el modo rango';
+  exception when insufficient_privilege then null;
+  end;
+end;
+$rango$;
+
 -- ─────────────────────────────────────────────────────────────────────────────
 -- E07 · Mes sellado: foto, sin desglose, sin recalcular
 -- ─────────────────────────────────────────────────────────────────────────────
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index f1998709..578c59b9 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -9734,6 +9734,35 @@ async function testReparto(sessions, seed) {
       'coordinador sin p_periodo recibe el mes vigente en Lima',
       coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn'),
     );
+    // v2: rango de fechas (inclusivo, Lima). Del 1 a hoy reproduce el mes; los
+    // rangos inválidos y «mes + rango a la vez» son 22023; el gate sigue primero.
+    const hoyLima = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
+    const convRango = await positive(
+      'coordinador consulta por rango de fechas (del 1 a hoy)',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
+    );
+    if (convRango && convCoord) {
+      check(['mes', 'rango'].includes(convRango.data?.periodo?.modo) && convRango.data?.periodo?.desde === P_MES.p_periodo
+        && convRango.data?.periodo?.hasta === hoyLima,
+        'el rango eco-a desde/hasta inclusivos y declara el modo', JSON.stringify(convRango.data?.periodo));
+      check(convRango.data?.empresa?.divisor === convCoord.data?.empresa?.divisor,
+        'PARIDAD v2: el rango del 1 a hoy tiene el mismo divisor que el mes');
+    }
+    await expectBlockedMutation(
+      'coordinador: un rango con la fecha inicial posterior a la final se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: hoyLima, p_hasta: P_MES.p_periodo }),
+      ['22023'],
+    );
+    await expectBlockedMutation(
+      'coordinador: mes y rango a la vez se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_periodo: P_MES.p_periodo, p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
+      ['22023'],
+    );
+    await expectBlockedMutation(
+      'vendedor: el modo rango tampoco entra (42501 antes que validar)',
+      sessions.vend1.client.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
+      ['42501'],
+    );
     if (convSinPeriodo) {
       check(convSinPeriodo.data?.periodo?.desde === P_MES.p_periodo,
         'sin p_periodo la puerta sirve el mes vigente', String(convSinPeriodo.data?.periodo?.desde));
@@ -9752,11 +9781,19 @@ async function testReparto(sessions, seed) {
       check(Array.isArray(convCoord.data?.analistas), 'analistas es SIEMPRE un array');
       const claves = [...new Set((convCoord.data?.analistas ?? []).flatMap((f) => Object.keys(f)))].sort();
       check(claves.length === 0 || JSON.stringify(claves) === JSON.stringify([
-        'analista_id', 'conversion_pct', 'divisor', 'divisor_formulario', 'divisor_landing',
-        'en_nucleo', 'nombre', 'numerador', 'supervisor_id', 'supervisor_nombre',
-      ]), 'cada analista trae SOLO las 10 claves del contrato', claves.join(','));
+        'ajuste_pendiente', 'analista_id', 'cartera', 'cierres', 'conversion_pct', 'desglose_disponible',
+        'divisor', 'divisor_formulario', 'divisor_landing', 'en_nucleo', 'nombre', 'numerador',
+        'numerador_bruto', 'supervisor_id', 'supervisor_nombre',
+      ]), 'cada analista trae SOLO las 15 claves del contrato (v2 con desglose)', claves.join(','));
       check((convCoord.data?.analistas ?? []).every((f) => f.divisor_formulario + f.divisor_landing === f.divisor),
         'PARIDAD: formulario + landing = divisor en cada analista (mes abierto)');
+      // v2: el numerador bruto es la suma de sus partes y el neto lleva el ajuste (mes abierto).
+      check((convCoord.data?.analistas ?? []).every((f) => f.desglose_disponible && f.cierres && f.cartera
+        && Math.abs((f.cierres.formulario + f.cierres.landing + f.cierres.referido_aporte + f.cartera.upgrade + f.cartera.renovacion_aporte) - f.numerador_bruto) < 1e-6
+        && Math.abs(Math.max(f.numerador_bruto - f.ajuste_pendiente, 0) - f.numerador) < 1e-6),
+        'PARIDAD v2: cierres + referidos×peso + upgrade + renovación×peso = numerador bruto; neto = bruto − ajuste');
+      check(typeof convCoord.data?.peso_renovacion === 'number' && typeof convCoord.data?.peso_referido === 'number',
+        'la puerta declara los dos pesos vigentes (referido y renovación)');
       const sumaAnalistas = (convCoord.data?.analistas ?? []).reduce((acc, f) => acc + f.divisor, 0)
         + (convCoord.data?.sin_analista?.divisor ?? 0);
       check(sumaAnalistas === convCoord.data?.empresa?.divisor,
```

## Protocolo global (extracto)
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
