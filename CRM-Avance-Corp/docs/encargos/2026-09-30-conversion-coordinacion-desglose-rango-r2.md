ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión r2 — v2 de la conversión de Coordinación: desglose de cierres y rango de fechas (LEVEL 3)

Segunda vuelta (máximo 2). Eres de disparo único y no ves la base ni la red: todo lo que debes juzgar va transcrito aquí. Responde en español con VERDICT, SUMMARY, FINDINGS P0–P3 (con archivo/línea/diff), riesgos y huecos de prueba, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia. Pide REFUTAR, no confirmar.

## Contexto

Puerta `crm.conversion_divisor_coordinacion_fn(p_periodo date, p_desde date, p_hasta date)` y núcleos `private.conversion_divisor_base/empresa/empresa_totales(date,date)`. Tu r1 (CHANGES_REQUESTED) tuvo cinco hallazgos; además se recibieron una auditoría RLS y una revisión de accesibilidad. Qué se aplicó desde el commit `cb415344` (todo lo de abajo está en el diff y en los archivos completos):

**De tu r1**
- P1-a (navegador aplicaba `max(bruto − ajuste, 0)` a la empresa): ahora la empresa se comprueba como `numerador ≈ Σ analistas.numerador + sin_analista.numerador` y solo `numerador ≤ bruto`; el suelo se comprueba por persona. Prueba `conSuelo` ahora espera 11,15 (y rechaza 8,15).
- P1-b (sellado con `fuera_foto`): `desglose_disponible` de empresa exige que no haya filas fuera de la foto (SQL) y el oráculo E07c lo afirma.
- P2-a (fórmula): en rango no se promete «n × peso»; en sellado se enumeran partes y «numerador sellado» sin «=»; el ajuste de empresa se dice aparte («descontado por analista con suelo en cero») sin afirmar `bruto − ajuste = neto`.
- P2-b (calendario): postflight compara `numerador_bruto` y exige ajuste 0 solo si `v_hoy <> v_fin_mes`; añade aditividad del 15 del mes anterior → hoy. Oráculo E09a usa el mes ANTERIOR como rango exacto; E09b compara bruto; E09b2 rango real 15 del mes anterior → hoy (invariante partes = bruto, ajuste 0, divisor aditivo); E09b3 rango que toca un mes sellado lo declara. `test-rls.mjs`: rango invertido con ayer.
- P2-c (registrador): compara las cuatro huellas vivas `md5(prosrc)` contra las del artefacto probado en el banco antes de registrar (mutante probado: cuerpo alterado → se niega).

**De la auditoría RLS**
- P1-1: la rama sellada leía `cartera.operaciones_*` (todas las operaciones); ahora lee `conversiones_*` (primera elegible por cliente/mes, lo que sumó el numerador) y `con_desglose` exige esas claves. Oráculo E07 siembra la foto con `operaciones_* ≠ conversiones_*` y afirma partes selladas = numerador + ajuste_numerador (4 + 2 = 6) con pesos sellados.
- P2-3: columna `cruza_sellados` en totales → `periodo.cruza_meses_sellados` y `fuente.modo` ('foto' | 'mensual' | 'rango_vivo'); el navegador avisa.
- P3-2: la paridad rango vs mes ignora filas que solo traen deuda (`en_nucleo = false`).
- P3-4: cierres de otros orígenes (web, campaña, whatsapp, otro) se cuentan en `cierres_otros` / `cierres.otros` (no pesan). El navegador enseña «Sin peso» = oficina + otros y la fórmula los enumera.
- P3-5 verificado: el front v1 vivo solo valida `periodo.desde` y `periodo.mes` (no `hasta`), y usa `v.object` (tolera claves nuevas): la pestaña v1 sigue funcionando entre aplicar el SQL y publicar el front.

**De accesibilidad**: cabecera agrupada en UN solo `<thead>` (`TheadCrm` con `segundaFila`, `scope=col/colgroup`); ninguna subcolumna de un grupo se oculta por ancho (los `colSpan` son fijos); fila «sin analista» pasa por `CeldasCierres`; retardo de 350 ms al teclear fechas (cambiar de mes o de tipo consulta al momento) y `FECHA_MINIMA = 2025-01-01`; el error del formulario ya NO desmonta la tabla cargada; `aria-invalid` por campo (`camposInvalidos`); `fieldset` con leyenda; textos «del período» en rango; plural concordado; sin `title` en `th`.

Verificación real: banco Docker a paridad con prod (dump `public,crm,private`): migración COMMIT (preflight acredita v1 por md5, postflight completo), oráculo `ORACULO-DIVISOR-COORDINACION-OK`, registrador OK e idempotente (md5 del registro = md5 del archivo) y fail-closed ante contenido distinto y ante cuerpo vivo alterado; `npm run check` 322 archivos / 5055 pruebas PASS; E2E Docker en curso; `test-rls.mjs` NOT RUN (sin banco con Auth). Huellas del artefacto: puerta b881b83ca8d4dd2f0f081d736828c8c5, base 0a43b0f3b56026bd2c5bfa4a9d8942d9, empresa 793a98fc4385fe714fff75290320c564, totales e97995f5ffd9109fce87f2e5dafb11a6.

## Preguntas para refutar

1. ¿Queda alguna igualdad que el navegador o la fórmula afirmen y que el SQL no garantice (empresa, sellado, rango que cruza meses con pesos distintos)?
2. Rama sellada: ¿`conversiones_*` es la clave correcta en toda foto que `crm.cerrar_periodo` escribe hoy? ¿Y si una foto antigua no las trae (`con_desglose` cae a false: ¿es la salida correcta)?
3. `cruza_sellados`: `between date_trunc('month', p_desde) and v_mes` con `v_mes = date_trunc('month', p_hasta)`. ¿Algún caso en que un rango toque un mes sellado y no lo declare, o lo declare sin tocarlo?
4. Postflight de rango: ¿sigue siendo independiente del día (1.º de mes, último día, mes anterior sellado en prod cuando setiembre se selle)? ¿Puede abortar en falso el día que Miguel lo aplique (hoy 30/09 o mañana 01/10)?
5. Retardo de 350 ms + `claveEstable`: ¿alguna carrera (cambiar a rango y teclear en seguida; volver a mes durante la espera; abortos) que deje datos de otro período bajo un control distinto o dispare una consulta inválida?
6. `camposInvalidos` vs `motivoConsultaInvalida`: ¿pueden discrepar (uno marca campo y el otro no da motivo, o al revés)?
7. Registrador: ¿el chequeo de huellas puede impedir registrar en prod si la migración se aplica tal cual (p. ej., `md5(prosrc)` distinto por CRLF, `#variable_conflict`, o por reescritura del cuerpo al crear)? En el banco coincidieron.

## Archivos completos (estado actual)

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

```

### supabase/scripts/registrar-20260930221500.sql (solo la cola tras el cuerpo embebido)
```sql
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

```

### app/src/lib/conversion-coordinacion.ts
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
  /** Otros orígenes admitidos (web, campaña, whatsapp…): tampoco pesan; se cuentan para no esconderlos. */
  otros: EnteroNoNegativoRpcSchema,
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
    /** Solo en rango: el tramo toca meses ya sellados y se calculó en vivo (puede diferir de la foto). */
    cruza_meses_sellados: v.boolean(),
  }),
  sellado: v.boolean(),
  peso_referido: NumeroRpcSchema,
  peso_renovacion: NumeroRpcSchema,
  fuente: v.object({
    divisor: TextoNoVacioSchema,
    origen: TextoNoVacioSchema,
    regla: TextoNoVacioSchema,
    /** 'foto' (mes sellado), 'mensual' (mes abierto, pieza de Metas) o 'rango_vivo' (tramo libre). */
    modo: v.picklist(['foto', 'mensual', 'rango_vivo']),
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
  if (consulta.desde < FECHA_MINIMA) return `El rango empieza como pronto el ${FECHA_MINIMA}.`
  if (consulta.desde > consulta.hasta) return 'La fecha inicial no puede ser posterior a la final.'
  if (consulta.hasta > hoy) return `El rango no admite fechas futuras: hasta ${hoy} como máximo.`
  if (diasInclusivos(consulta.desde, consulta.hasta) > RANGO_MAXIMO_DIAS) return `El rango máximo es de ${RANGO_MAXIMO_DIAS} días.`
  return null
}

/** Primer día consultable: el CRM no tiene llegadas anteriores y un año tecleado a medias no debe disparar consultas. */
export const FECHA_MINIMA = '2025-01-01'

/** Qué campo del rango está mal, para marcar solo ese con `aria-invalid`. */
export function camposInvalidos(consulta: ConsultaConversion, hoy: string): { desde: boolean; hasta: boolean } {
  if (consulta.modo === 'mes') return { desde: false, hasta: false }
  const desdeOk = v.safeParse(FechaSchema, consulta.desde).success && consulta.desde >= FECHA_MINIMA
  const hastaOk = v.safeParse(FechaSchema, consulta.hasta).success && consulta.hasta <= hoy
  if (!desdeOk || !hastaOk) return { desde: !desdeOk, hasta: !hastaOk }
  const cruzado = consulta.desde > consulta.hasta || diasInclusivos(consulta.desde, consulta.hasta) > RANGO_MAXIMO_DIAS
  return { desde: cruzado, hasta: cruzado }
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
  esEmpresa?: boolean
}): boolean {
  if (!fila.desglose_disponible) {
    // Solo una foto sellada puede venir sin desglose; y entonces viene sin nada.
    return fila.sellado && fila.cierres === null && fila.cartera === null
  }
  if (fila.cierres === null || fila.cartera === null) return false
  if (fila.sellado) return fila.numerador_bruto === null && fila.ajuste_pendiente === null
  if (fila.numerador_bruto === null || fila.ajuste_pendiente === null || fila.numerador === null) return false
  if (Math.abs(sumaDePartes(fila.cierres, fila.cartera) - fila.numerador_bruto) > EPSILON) return false
  // Por persona: neto = bruto menos lo que arrastra de meses ya pagados, con suelo en cero.
  // La empresa se comprueba aparte (suma de netos), porque el suelo es por persona.
  if (fila.esEmpresa) return fila.numerador <= fila.numerador_bruto + EPSILON
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
    if (periodo.cruza_meses_sellados) return false
    if (datos.fuente.modo === 'rango_vivo' || datos.fuente.modo === (datos.sellado ? 'mensual' : 'foto')) return false
  } else if (periodo.mes !== null || periodo.mes_nombre !== null || periodo.anio !== null || datos.sellado || datos.fuente.modo !== 'rango_vivo') {
    // Un rango libre nunca es una foto sellada ni lleva nombre de mes, y siempre se declara como vivo.
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

  if (!desgloseConsistente({ ...datos.empresa, sellado: datos.sellado, esEmpresa: true })) return false
  if (datos.sellado) {
    if (datos.periodo.cruza_meses_sellados) return false
    return datos.empresa.divisor_formulario === null && datos.empresa.divisor_landing === null
  }
  // La empresa suma los NETOS por persona (cada uno con su suelo en cero), nunca
  // aplica un suelo al agregado: 11,15 + max(9 − 12, 0) = 11,15, no 8,15.
  const netoEsperado = datos.analistas.reduce((acc, a) => acc + (a.numerador ?? 0), 0) + (datos.sin_analista?.numerador ?? 0)
  if (Math.abs(netoEsperado - datos.empresa.numerador) > EPSILON) return false
  if (datos.empresa.divisor_formulario === null || datos.empresa.divisor_landing === null) return false
  if (datos.empresa.divisor_formulario + datos.empresa.divisor_landing !== datos.empresa.divisor) return false
  if (divisorAnalistas + (datos.sin_analista?.divisor ?? 0) !== datos.empresa.divisor) return false
  if (formulario > datos.empresa.divisor_formulario || landing > datos.empresa.divisor_landing) return false
  return true
}

```

### app/src/components/app/conversion-coordinacion.tsx
```tsx
import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import { Lock, Percent } from 'lucide-react'
import { conversionCoordinacion } from '@/data/crm-api'
import { useAhora } from '@/lib/ahora'
import {
  FECHA_MINIMA,
  camposInvalidos,
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
/** Tecleando fechas, cada dígito que completa una fecha válida cambiaría la consulta: se espera a que pare. */
const ESPERA_FECHAS_MS = 350

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
const MOTIVO_NO_APLICA = 'no aplica'

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

/** «19 · 2,85»: cuántos y cuánto pesan. El lector oye las dos cifras con su nombre, concordado. */
function CantidadYAporte({ cantidad, aporte, nombre }: { cantidad: number; aporte: number; nombre: { uno: string; varios: string } }) {
  const singular = cantidad === 1
  return (
    <>
      <span aria-hidden="true">{numero(cantidad)} · {numero(aporte)}</span>
      <span className="sr-only">
        {numero(cantidad)} {singular ? nombre.uno : nombre.varios}, {singular ? 'aporta' : 'aportan'} {numero(aporte)}
      </span>
    </>
  )
}

const REFERIDO = { uno: 'referido', varios: 'referidos' }
const RENOVACION = { uno: 'renovación', varios: 'renovaciones' }

/**
 * Las siete celdas de «Cierres» de una fila, en el MISMO orden que la cabecera:
 * formulario, landing, referido, sin peso (oficina y otros), upgrade, renovación
 * y el total ponderado. La fila «sin analista» pasa por aquí con todo a null para
 * que sus celdas nunca se desalineen de la cabecera.
 */
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
        {cierres ? <CantidadYAporte cantidad={cierres.referido} aporte={cierres.referido_aporte} nombre={REFERIDO} /> : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right tabular-nums text-muted-foreground">
        {cierres ? numero(cierres.oficina + cierres.otros) : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right tabular-nums">{cartera ? numero(cartera.upgrade) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">
        {cartera ? <CantidadYAporte cantidad={cartera.renovacion} aporte={cartera.renovacion_aporte} nombre={RENOVACION} /> : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right font-semibold tabular-nums">
        <Cifra valor={numerador} motivo="sin cierres" />
        {conAjuste ? (
          <span className="block text-xs font-normal text-muted-foreground">
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
      <Td className="text-right tabular-nums">
        {sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={analista.divisor_formulario} motivo={MOTIVO_SIN_LLEGADAS} />}
      </Td>
      <Td className="text-right tabular-nums">
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

/**
 * Mes abierto: «117,15 = 90 directos + 2,85 de referidos (19 × 0,15) + 24 de upgrade + 0,45
 * de renovación (3 × 0,15)», y el ajuste aparte (se descuenta por analista, con suelo en
 * cero, así que la empresa no es «bruto − ajuste»). Rango libre: los pesos van por mes de
 * cada episodio, así que se enseña la cantidad sin prometer «n × peso». Mes cerrado: la foto
 * no guarda el bruto, así que se enumeran las partes sin afirmar una igualdad.
 */
function formulaDelNumerador(datos: DatosConversion): string | null {
  const { cierres, cartera, numerador, numerador_bruto: bruto, ajuste_pendiente: ajuste } = datos.empresa
  if (!cierres || !cartera) return null
  const enRango = datos.periodo.modo === 'rango'
  const referidos = `${numero(cierres.referido_aporte)} de referidos (${numero(cierres.referido)}${enRango ? '' : ` × ${numero(datos.peso_referido)}`})`
  const renovacion = `${numero(cartera.renovacion_aporte)} de renovación (${numero(cartera.renovacion)}${enRango ? '' : ` × ${numero(datos.peso_renovacion)}`})`
  const partes = [
    `${numero(cierres.formulario + cierres.landing)} directos (formulario y landing)`,
    referidos,
    `${numero(cartera.upgrade)} de upgrade`,
    renovacion,
  ]
  const sinPeso = `Sin peso: ${numero(cierres.oficina)} de oficina y ${numero(cierres.otros)} de otros orígenes.`
  if (datos.sellado) {
    return `Cierres del mes cerrado: ${partes.join(', ')}. Numerador sellado: ${numero(numerador ?? 0)}. ${sinPeso}`
  }
  const total = bruto ?? numerador ?? 0
  const cola = ajuste != null && ajuste !== 0
    ? ` Ajuste de meses ya pagados: ${numero(ajuste)}, descontado por analista con suelo en cero. Netos: ${numero(numerador ?? 0)}.`
    : ''
  return `Cierres ponderados ${numero(total)} = ${partes.join(' + ')}.${cola} ${sinPeso}`
}

/**
 * Conversión por analista, con ámbito de toda la empresa. El divisor es el del
 * NÚCLEO (la misma cifra que Metas y Ranking): una llegada por lead, por su fecha
 * de alta, en el primer analista que la recibió. No es el reporte de entregas.
 * Los cierres se abren en sus partes con los mismos episodios del núcleo. El
 * navegador no calcula nada: pinta lo que el servidor reconcilió.
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
  const idAyuda = useId()
  const consulta = useMemo<ConsultaConversion>(
    () => (modo === 'mes' ? { modo: 'mes', mes } : { modo: 'rango', desde, hasta }),
    [modo, mes, desde, hasta],
  )
  // Consulta inválida = estado del formulario (pegado al campo), nunca un fallo de carga.
  const ayuda = motivoConsultaInvalida(consulta, hoy)
  const consultaInvalida = ayuda !== null
  const invalidos = camposInvalidos(consulta, hoy)
  const claveConsulta = JSON.stringify(consulta)

  // Cambiar de mes o de tipo de período consulta al momento; teclear fechas espera a que
  // el usuario pare, para no desmontar la tabla ni anunciar una carga por cada dígito.
  const [claveEstable, setClaveEstable] = useState(claveConsulta)
  useEffect(() => {
    if (claveEstable === claveConsulta) return
    const soloFechas = modo === 'rango' && claveEstable.includes('"modo":"rango"')
    if (!soloFechas) {
      setClaveEstable(claveConsulta)
      return
    }
    const temporizador = setTimeout(() => setClaveEstable(claveConsulta), ESPERA_FECHAS_MS)
    return () => clearTimeout(temporizador)
  }, [claveConsulta, claveEstable, modo])

  const cargar = useCallback(async (conservarError = false) => {
    abortRef.current?.abort()
    const pedida = JSON.parse(claveEstable) as ConsultaConversion
    if (motivoConsultaInvalida(pedida, hoy)) {
      // El error del formulario no borra lo último cargado: la tabla sigue mientras se corrige.
      setEstado((previo) => ({ ...previo, cargando: false }))
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
  }, [claveEstable, hoy])

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
  // Lo que se ve es lo último cargado: sus textos van por SU período, no por el control.
  const periodoVisible = datos?.periodo.modo === 'rango' ? 'del período' : 'del mes'
  const tocaSellados = datos?.periodo.cruza_meses_sellados === true

  const etiquetaPeriodo = (d: DatosConversion) => (
    d.periodo.modo === 'mes' && d.periodo.mes_nombre
      ? `${d.periodo.mes_nombre} ${d.periodo.anio}`
      : `del ${fechaLarga(d.periodo.desde)} al ${fechaLarga(d.periodo.hasta)}`
  )
  const mensajeEstado = consultaInvalida
    ? ayuda
    : estado.cargando
      ? (modo === 'mes' ? `Cargando la conversión de ${nombreDelMes(mes)}…` : `Cargando la conversión del ${fechaLarga(desde)} al ${fechaLarga(hasta)}…`)
      : datos
        ? `Conversión ${datos.periodo.modo === 'mes' ? 'de' : ''} ${etiquetaPeriodo(datos)}: ${numero(datos.empresa.divisor)} llegadas, ${
            datos.empresa.conversion_pct == null ? 'sin conversión calculable' : porcentajeConversionCanonica(datos.empresa.conversion_pct)
          }${datos.sellado ? '. Mes cerrado: se muestra la foto del cierre' : ''}${datos.periodo.modo === 'rango' ? '. Rango libre: cifras en vivo' : ''}${
            tocaSellados ? '. Toca meses ya cerrados y puede diferir de su foto' : ''
          }.`
        : estado.error ?? ''

  const chips: Array<{ etiqueta: string; valor: React.ReactNode }> = datos ? [
    { etiqueta: 'Llegadas', valor: numero(datos.empresa.divisor) },
    { etiqueta: 'Formulario', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_formulario} motivo={MOTIVO_SIN_LLEGADAS} /> },
    { etiqueta: 'Landing', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_landing} motivo={MOTIVO_SIN_LLEGADAS} /> },
    { etiqueta: 'Conversión', valor: <Porcentaje valor={datos.empresa.conversion_pct} /> },
    { etiqueta: 'Cierres directos', valor: datos.empresa.cierres ? numero(datos.empresa.cierres.formulario + datos.empresa.cierres.landing) : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Referidos', valor: datos.empresa.cierres ? <CantidadYAporte cantidad={datos.empresa.cierres.referido} aporte={datos.empresa.cierres.referido_aporte} nombre={REFERIDO} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Upgrade', valor: datos.empresa.cartera ? numero(datos.empresa.cartera.upgrade) : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Renovación', valor: datos.empresa.cartera ? <CantidadYAporte cantidad={datos.empresa.cartera.renovacion} aporte={datos.empresa.cartera.renovacion_aporte} nombre={RENOVACION} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
  ] : []

  const claseCampo = 'grid gap-1.5 text-xs font-semibold text-foreground'

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
          <fieldset className="m-0 flex min-w-0 flex-wrap items-end gap-3 border-0 p-0">
            <legend className="sr-only">Período de la conversión</legend>
            <label className={claseCampo}>
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
              <label className={claseCampo}>
                Mes
                <Input
                  type="month"
                  aria-label="Mes de conversión"
                  min={FECHA_MINIMA.slice(0, 7)}
                  max={mesMaximo}
                  value={mes}
                  aria-invalid={consultaInvalida || undefined}
                  aria-describedby={consultaInvalida ? idAyuda : undefined}
                  onChange={(event) => setMes(event.target.value)}
                  className="w-44"
                />
              </label>
            ) : (
              <>
                <label className={claseCampo}>
                  Desde
                  <Input
                    type="date"
                    min={FECHA_MINIMA}
                    max={hoy}
                    value={desde}
                    aria-invalid={invalidos.desde || undefined}
                    aria-describedby={consultaInvalida ? idAyuda : undefined}
                    onChange={(event) => setDesde(event.target.value)}
                    className="w-44"
                  />
                </label>
                <label className={claseCampo}>
                  Hasta
                  <Input
                    type="date"
                    min={FECHA_MINIMA}
                    max={hoy}
                    value={hasta}
                    aria-invalid={invalidos.hasta || undefined}
                    aria-describedby={consultaInvalida ? idAyuda : undefined}
                    onChange={(event) => setHasta(event.target.value)}
                    className="w-44"
                  />
                </label>
              </>
            )}
          </fieldset>
          {consultaInvalida ? (
            <p id={idAyuda} className="text-sm font-medium text-destructive">{ayuda}</p>
          ) : modo === 'rango' ? (
            <p className="text-sm text-muted-foreground">
              Rango libre: cifras en vivo, sin ajustes de meses ya pagados ni fotos de cierre. Un mes completo se trata como ese mes.
              {tocaSellados ? (
                <span className="block font-medium text-foreground">
                  Este rango toca meses ya cerrados: se calcula en vivo y puede diferir de la foto del cierre.
                </span>
              ) : null}
            </p>
          ) : null}
        </div>
        {datos?.sellado ? (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-border bg-muted/60 px-2.5 py-1 text-xs font-semibold text-foreground">
            <Lock className="size-3.5" aria-hidden /> Mes cerrado: se muestra la foto del cierre
          </span>
        ) : null}
      </div>

      {estado.error ? (
        <PanelError mensaje={estado.error} onReintentar={reintentar} reintentando={estado.cargando} />
      ) : estado.cargando ? (
        <PanelCargando filas={5} />
      ) : datos ? (
        // Destino programático del foco tras reintentar: fuera del orden de Tab,
        // sin anillo (no es un control), igual que el patrón de Repartir.
        <div ref={contenidoRef} tabIndex={-1} role="region" aria-label={`Conversión ${periodoVisible}`} className="outline-none">
          <div
            role="group"
            aria-label={`Resumen de conversión ${periodoVisible}`}
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
                titulo={`Sin llegadas en este ${datos.periodo.modo === 'rango' ? 'período' : 'mes'}`}
                detalle="Cuando entren leads por la hoja o la landing aparecerán aquí, en el analista que los recibió primero."
              />
            )
          ) : (
            <>
              <TablaEnvoltura ariaLabel="Conversión por analista">
                {/*
                  Cabecera agrupada en UN solo <thead>. Ninguna subcolumna de un grupo se
                  oculta por ancho: los colSpan son fijos y una celda oculta desalinearía la
                  cabecera del cuerpo; la envoltura desplaza en horizontal si hace falta.
                */}
                <TheadCrm
                  segundaFila={(
                    <>
                      <Th scope="col" className="text-right">Form.</Th>
                      <Th scope="col" className="text-right">Land.</Th>
                      <Th scope="col" className="text-right">Total</Th>
                      <Th scope="col" className="text-right">Form.</Th>
                      <Th scope="col" className="text-right">Land.</Th>
                      <Th scope="col" className="text-right">Referido</Th>
                      <Th scope="col" className="text-right">Sin peso</Th>
                      <Th scope="col" className="text-right">Upgrade</Th>
                      <Th scope="col" className="text-right">Renov.</Th>
                      <Th scope="col" className="text-right">Ponderados</Th>
                    </>
                  )}
                >
                  <Th scope="col" rowSpan={2} className="align-bottom">Analista</Th>
                  <Th scope="col" rowSpan={2} className="hidden align-bottom lg:table-cell">Supervisor</Th>
                  <Th scope="colgroup" colSpan={3} className="text-center">Llegadas</Th>
                  <Th scope="colgroup" colSpan={7} className="text-center">Cierres</Th>
                  <Th scope="col" rowSpan={2} className="text-right align-bottom">Conversión</Th>
                </TheadCrm>
                <tbody>
                  {analistas.visibles.map((analista) => (
                    <FilaAnalista key={analista.analista_id} analista={analista} sellado={datos.sellado} />
                  ))}
                  {sinAnalista && analistas.paginaActual === analistas.paginas - 1 ? (
                    <tr className="border-b border-border last:border-0 bg-muted/30 text-muted-foreground">
                      <Td className="text-base font-medium">Sin analista asignado</Td>
                      <Td className="hidden lg:table-cell"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                      <Td className="text-right tabular-nums"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                      <Td className="text-right tabular-nums"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                      <Td className="text-right text-base font-extrabold tabular-nums">{numero(sinAnalista.divisor)}</Td>
                      <CeldasCierres cierres={null} cartera={null} numerador={sinAnalista.numerador} bruto={null} ajuste={null} motivo={MOTIVO_NO_APLICA} />
                      <Td className="text-right tabular-nums"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
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

          <p className="border-t border-border px-5 py-2 text-sm text-muted-foreground">
            Referido y Renov. (renovación) van como «cantidad · aporte al numerador». «Sin peso» son los
            cierres de oficina y de otros orígenes, que no suman. Este conteo es distinto del reporte de
            entregas: aquel cuenta lo entregado por fecha de entrega y deja de sumar la entrega que volvió
            a la bandeja antes de gestionarse.
          </p>
        </div>
      ) : null}
    </Card>
  )
}

```

## Diff de la migración desde cb415344 (lo que cambió respecto a tu r1)
```diff
diff --git a/CRM-Avance-Corp/supabase/migrations/20260930221500_crm_conversion_coordinacion_desglose_cierres.sql b/CRM-Avance-Corp/supabase/migrations/20260930221500_crm_conversion_coordinacion_desglose_cierres.sql
index cd1e716f..38bdf508 100644
--- a/CRM-Avance-Corp/supabase/migrations/20260930221500_crm_conversion_coordinacion_desglose_cierres.sql
+++ b/CRM-Avance-Corp/supabase/migrations/20260930221500_crm_conversion_coordinacion_desglose_cierres.sql
@@ -191,6 +191,7 @@ returns table (
   cierres_referido integer,
   cierres_referido_aporte numeric,
   cierres_oficina integer,
+  cierres_otros integer,
   upgrade integer,
   renovacion integer,
   renovacion_aporte numeric,
@@ -234,7 +235,7 @@ begin
     with foto as (
       select f.*,
         coalesce((f.origenes_ranking ->> 'disponible')::boolean, false)
-          and f.cartera is not null as con_desglose
+          and f.cartera ? 'conversiones_upgrade' and f.cartera ? 'conversiones_renovacion' as con_desglose
       from crm.cierre_mes_vendedor f
       where f.periodo = p_desde
     ),
@@ -243,7 +244,8 @@ begin
         sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'formulario')::integer as formulario,
         sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'landing')::integer as landing,
         sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'referido')::integer as referido,
-        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'oficina')::integer as oficina
+        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'oficina')::integer as oficina,
+        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' not in ('formulario', 'landing', 'referido', 'oficina', 'ajuste'))::integer as otros
       from foto f
       cross join lateral pg_catalog.jsonb_array_elements(
         case when pg_catalog.jsonb_typeof(f.origenes_ranking -> 'filas') = 'array'
@@ -268,9 +270,12 @@ begin
            case when f.con_desglose then coalesce(o.referido, 0) end,
            case when f.con_desglose then coalesce(o.referido, 0) * v_cierre.ponderacion_referido end,
            case when f.con_desglose then coalesce(o.oficina, 0) end,
-           case when f.con_desglose then coalesce((f.cartera ->> 'operaciones_upgrade')::integer, 0) end,
-           case when f.con_desglose then coalesce((f.cartera ->> 'operaciones_renovacion')::integer, 0) end,
-           case when f.con_desglose then coalesce((f.cartera ->> 'operaciones_renovacion')::integer, 0) * v_peso_renovacion end,
+           case when f.con_desglose then coalesce(o.otros, 0) end,
+           -- `conversiones_*` (primera operación ELEGIBLE por cliente y mes) es lo que
+           -- suma el numerador; `operaciones_*` cuenta todas y NO sirve aquí.
+           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_upgrade')::integer, 0) end,
+           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) end,
+           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) * v_peso_renovacion end,
            f.con_desglose
     from foto f
     left join por_origen o on o.vendedor_id = f.vendedor_id
@@ -315,6 +320,8 @@ begin
            (count(*) filter (where e.tipo = 'cierre' and e.origen = 'referido'))::integer as cierres_referido,
            coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.origen = 'referido'), 0::numeric) as cierres_referido_aporte,
            (count(*) filter (where e.tipo = 'cierre' and e.origen = 'oficina'))::integer as cierres_oficina,
+           -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.
+           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina')))::integer as cierres_otros,
            (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'upgrade'))::integer as upgrade,
            (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'))::integer as renovacion,
            coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'), 0::numeric) as renovacion_aporte
@@ -346,6 +353,7 @@ begin
          coalesce(c.cierres_referido, 0),
          coalesce(c.cierres_referido_aporte, 0::numeric),
          coalesce(c.cierres_oficina, 0),
+         coalesce(c.cierres_otros, 0),
          coalesce(c.upgrade, 0),
          coalesce(c.renovacion, 0),
          coalesce(c.renovacion_aporte, 0::numeric),
@@ -388,10 +396,12 @@ returns table (
   cierres_referido integer,
   cierres_referido_aporte numeric,
   cierres_oficina integer,
+  cierres_otros integer,
   upgrade integer,
   renovacion integer,
   renovacion_aporte numeric,
   desglose_disponible boolean,
+  cruza_sellados boolean,
   sin_analista_presente boolean,
   sin_analista_divisor integer,
   sin_analista_numerador numeric
@@ -448,13 +458,17 @@ begin
       case when v_cierre.periodo is null then coalesce(sum(f.numerador_bruto), 0::numeric) end as numerador_bruto,
       case when v_cierre.periodo is null then coalesce(sum(f.ajuste_pendiente), 0::numeric) end as ajuste_pendiente,
       -- Desglose de la empresa: suma de las filas con desglose. En un mes sellado
-      -- solo si TODAS las filas de la foto lo traen (si no, la suma mentiría).
-      coalesce(bool_and(f.desglose_disponible), v_cierre.periodo is null) as desglose_disponible,
+      -- solo si TODAS las filas de la foto lo traen Y el total no incluye producción
+      -- congelada fuera de las filas (fuera_ranking / sin analista), que no tiene
+      -- desglose: si no, la suma de partes no sería la del numerador.
+      coalesce(bool_and(f.desglose_disponible), v_cierre.periodo is null)
+        and (v_cierre.periodo is null or not exists (select 1 from fuera_foto)) as desglose_disponible,
       coalesce(sum(f.cierres_formulario), 0)::integer as cierres_formulario,
       coalesce(sum(f.cierres_landing), 0)::integer as cierres_landing,
       coalesce(sum(f.cierres_referido), 0)::integer as cierres_referido,
       coalesce(sum(f.cierres_referido_aporte), 0::numeric) as cierres_referido_aporte,
       coalesce(sum(f.cierres_oficina), 0)::integer as cierres_oficina,
+      coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,
       coalesce(sum(f.upgrade), 0)::integer as upgrade,
       coalesce(sum(f.renovacion), 0)::integer as renovacion,
       coalesce(sum(f.renovacion_aporte), 0::numeric) as renovacion_aporte
@@ -490,10 +504,17 @@ begin
     case when s.desglose_disponible then s.cierres_referido end,
     case when s.desglose_disponible then s.cierres_referido_aporte end,
     case when s.desglose_disponible then s.cierres_oficina end,
+    case when s.desglose_disponible then s.cierres_otros end,
     case when s.desglose_disponible then s.upgrade end,
     case when s.desglose_disponible then s.renovacion end,
     case when s.desglose_disponible then s.renovacion_aporte end,
     s.desglose_disponible,
+    -- Un rango libre que toca meses ya sellados se calcula EN VIVO (como la puerta
+    -- de Gerencia) y puede discrepar de la foto: se declara para que la pantalla avise.
+    (not v_es_mes) and exists (
+      select 1 from crm.periodos_cerrados pc
+      where pc.periodo between pg_catalog.date_trunc('month', p_desde)::date and v_mes
+    ),
     coalesce((select sa.presente from sin_analista sa limit 1), false),
     (select sa.divisor from sin_analista sa limit 1),
     (select sa.numerador from sin_analista sa limit 1)
@@ -591,7 +612,8 @@ begin
       'zona', 'America/Lima',
       'desde', v_desde,
       'hasta', v_hasta,
-      'dias', (v_hasta - v_desde) + 1
+      'dias', (v_hasta - v_desde) + 1,
+      'cruza_meses_sellados', v_totales.cruza_sellados
     ),
     'sellado', v_totales.sellado,
     'peso_referido', v_totales.peso_referido,
@@ -599,7 +621,11 @@ begin
     'fuente', pg_catalog.jsonb_build_object(
       'divisor', 'private.conversion_neta_por_vendedor',
       'origen', 'private.conversion_episodios',
-      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado'
+      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado',
+      -- 'foto' = mes sellado servido de crm.cierre_mes_vendedor; 'mensual' = mes abierto
+      -- con la pieza de Metas (bruto, ajuste, neto); 'rango_vivo' = tramo libre calculado
+      -- en vivo sin ajustes ni fotos (precedente: crm.metricas_conversiones_equipo_fn).
+      'modo', case when v_totales.sellado then 'foto' when v_es_mes then 'mensual' else 'rango_vivo' end
     ),
     'empresa', pg_catalog.jsonb_build_object(
       'divisor', v_totales.divisor,
@@ -615,7 +641,8 @@ begin
         'landing', v_totales.cierres_landing,
         'referido', v_totales.cierres_referido,
         'referido_aporte', v_totales.cierres_referido_aporte,
-        'oficina', v_totales.cierres_oficina
+        'oficina', v_totales.cierres_oficina,
+        'otros', v_totales.cierres_otros
       ) end,
       'cartera', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
         'upgrade', v_totales.upgrade,
@@ -648,7 +675,8 @@ begin
             'landing', f.cierres_landing,
             'referido', f.cierres_referido,
             'referido_aporte', f.cierres_referido_aporte,
-            'oficina', f.cierres_oficina
+            'oficina', f.cierres_oficina,
+            'otros', f.cierres_otros
           ) end,
           'cartera', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
             'upgrade', f.upgrade,
@@ -669,7 +697,7 @@ end;
 $function$;
 
 comment on function crm.conversion_divisor_coordinacion_fn(date, date, date) is
-  'Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados). Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.';
+  'Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados; si toca meses sellados lo declara en periodo.cruza_meses_sellados y fuente.modo = rango_vivo). Los cierres de orígenes que no pesan (oficina y otros) se cuentan aparte. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.';
 
 revoke all on function crm.conversion_divisor_coordinacion_fn(date, date, date)
   from public, anon, authenticated, service_role;
@@ -806,27 +834,46 @@ begin
     raise exception 'POSTFLIGHT: el desglose de la empresa no suma el numerador';
   end if;
 
-  -- MODO RANGO sobre datos reales: del 1 del mes vigente a hoy no puede haber
-  -- llegadas ni cierres «del futuro», así que el rango en vivo reproduce el mes
-  -- (mismas filas, divisor, formulario, landing y partes; bruto = neto porque
-  -- el rango no lleva ajuste). Si difiere, la pieza por rango no casa con la mensual.
+  -- MODO RANGO sobre datos reales. (1) Del 1 del mes vigente a hoy no puede haber
+  -- llegadas ni cierres «del futuro», así que el rango en vivo reproduce el BRUTO
+  -- del mes (mismas filas, divisor, formulario, landing y partes). El último día
+  -- del mes ese rango ES el mes (y entonces lleva su ajuste); cualquier otro día
+  -- es un rango libre sin ajuste. (2) El rango que cruza el mes anterior es aditivo
+  -- en el divisor: llegadas del 15 del mes anterior a hoy = del 15 al fin de ese
+  -- mes + del 1 a hoy, analista por analista. Ambas son ciertas cualquier día.
   if exists (
     select 1
     from private.conversion_divisor_empresa(v_mes, v_fin_mes) m
     full join private.conversion_divisor_empresa(v_mes, v_hoy) r
       on coalesce(r.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(m.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
-    where m.analista_id is null and r.analista_id is not null
-       or r.analista_id is null and m.analista_id is not null
-       or m.divisor is distinct from r.divisor
-       or m.divisor_formulario is distinct from r.divisor_formulario
-       or m.cierres_formulario + m.cierres_landing + m.cierres_referido + m.upgrade + m.renovacion
-          is distinct from r.cierres_formulario + r.cierres_landing + r.cierres_referido + r.upgrade + r.renovacion
-       or m.numerador_bruto is distinct from r.numerador_bruto
-       or r.numerador is distinct from r.numerador_bruto
-       or r.ajuste_pendiente is distinct from 0::numeric
+    where (m.analista_id is null and r.analista_id is not null)
+       or (r.analista_id is null and m.analista_id is not null and m.en_nucleo)  -- una fila solo con deuda no existe en el rango
+       or (m.en_nucleo and (
+             m.divisor is distinct from r.divisor
+          or m.divisor_formulario is distinct from r.divisor_formulario
+          or m.cierres_formulario + m.cierres_landing + m.cierres_referido + m.cierres_oficina + m.cierres_otros + m.upgrade + m.renovacion
+             is distinct from r.cierres_formulario + r.cierres_landing + r.cierres_referido + r.cierres_oficina + r.cierres_otros + r.upgrade + r.renovacion
+          or m.numerador_bruto is distinct from r.numerador_bruto))
+       or (v_hoy <> v_fin_mes and r.analista_id is not null and (r.numerador is distinct from r.numerador_bruto or r.ajuste_pendiente is distinct from 0::numeric))
+  ) then
+    raise exception 'POSTFLIGHT: el modo rango (1 → hoy) no reproduce el bruto del mes vigente';
+  end if;
+  if exists (
+    with a as (select * from private.conversion_divisor_empresa((v_mes - interval '1 month' + interval '14 days')::date, (v_mes - interval '1 day')::date)),
+         b as (select * from private.conversion_divisor_empresa(v_mes, v_hoy)),
+         ab as (select * from private.conversion_divisor_empresa((v_mes - interval '1 month' + interval '14 days')::date, v_hoy))
+    select 1
+    from ab
+    left join a on coalesce(a.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(ab.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
+    left join b on coalesce(b.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(ab.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
+    where ab.divisor is distinct from coalesce(a.divisor, 0) + coalesce(b.divisor, 0)
+       or ab.divisor_formulario is distinct from coalesce(a.divisor_formulario, 0) + coalesce(b.divisor_formulario, 0)
+       or ab.cierres_formulario + ab.cierres_landing + ab.cierres_referido + ab.cierres_oficina + ab.upgrade + ab.renovacion
+          is distinct from coalesce(a.cierres_formulario + a.cierres_landing + a.cierres_referido + a.cierres_oficina + a.upgrade + a.renovacion, 0)
+                         + coalesce(b.cierres_formulario + b.cierres_landing + b.cierres_referido + b.cierres_oficina + b.upgrade + b.renovacion, 0)
   ) then
-    raise exception 'POSTFLIGHT: el modo rango (1 → hoy) no reproduce el mes vigente';
+    raise exception 'POSTFLIGHT: el rango que cruza el mes anterior no es aditivo en llegadas y conteos';
   end if;
 end;
 $postflight$;

```

## Diff del resto (oráculo, test-rls, pruebas, tabla.tsx, e2e) desde cb415344
```diff
diff --git a/CRM-Avance-Corp/app/e2e/_helpers.ts b/CRM-Avance-Corp/app/e2e/_helpers.ts
index 6df52fc0..92dc9cb9 100644
--- a/CRM-Avance-Corp/app/e2e/_helpers.ts
+++ b/CRM-Avance-Corp/app/e2e/_helpers.ts
@@ -2725,11 +2725,13 @@ export async function montarBackendReal(
       const esMes = desde.endsWith('-01') && hasta === finDeMes
       const dias = Math.round((Date.parse(`${hasta}T12:00:00Z`) - Date.parse(`${desde}T12:00:00Z`)) / 86_400_000) + 1
       const base = estado.conversionCoordinacion.periodo as Record<string, unknown>
+      const fuente = estado.conversionCoordinacion.fuente as Record<string, unknown>
       return json(route, {
         ...estado.conversionCoordinacion,
+        fuente: { ...fuente, modo: esMes ? 'mensual' : 'rango_vivo' },
         periodo: esMes
-          ? { ...base, modo: 'mes', mes: desde.slice(0, 7), desde, hasta, dias }
-          : { ...base, modo: 'rango', mes: null, mes_nombre: null, anio: null, desde, hasta, dias },
+          ? { ...base, modo: 'mes', mes: desde.slice(0, 7), desde, hasta, dias, cruza_meses_sellados: false }
+          : { ...base, modo: 'rango', mes: null, mes_nombre: null, anio: null, desde, hasta, dias, cruza_meses_sellados: false },
       })
     }
     if (p === '/rest/v1/rpc/panel_distribucion_reparto') {
diff --git a/CRM-Avance-Corp/app/e2e/repartir.spec.ts b/CRM-Avance-Corp/app/e2e/repartir.spec.ts
index 20de86ea..b32ecb54 100644
--- a/CRM-Avance-Corp/app/e2e/repartir.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/repartir.spec.ts
@@ -211,15 +211,15 @@ test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista),
       version: 1,
       generado_en: '2026-09-30T18:00:00.000Z',
       alcance: 'global',
-      periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30 },
+      periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30, cruza_meses_sellados: false },
       sellado: false,
       peso_referido: 0.15,
       peso_renovacion: 0.15,
-      fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead' },
+      fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead', modo: 'mensual' },
       empresa: {
         divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79,
         numerador_bruto: 20.15, ajuste_pendiente: 0, desglose_disponible: true,
-        cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1 },
+        cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1, otros: 0 },
         cartera: { upgrade: 6, renovacion: 0, renovacion_aporte: 0 },
       },
       sin_analista: { divisor: 2, numerador: 0 },
@@ -229,7 +229,7 @@ test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista),
           supervisor_id: '10000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA NORTE',
           en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7,
           numerador_bruto: 11.15, ajuste_pendiente: 0, desglose_disponible: true,
-          cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1 },
+          cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1, otros: 0 },
           cartera: { upgrade: 4, renovacion: 0, renovacion_aporte: 0 },
         },
         {
@@ -237,7 +237,7 @@ test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista),
           supervisor_id: '10000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA NORTE',
           en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23,
           numerador_bruto: 9, ajuste_pendiente: 0, desglose_disponible: true,
-          cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0 },
+          cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
           cartera: { upgrade: 2, renovacion: 0, renovacion_aporte: 0 },
         },
       ],
diff --git a/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.test.tsx b/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.test.tsx
index d2414a3a..5cd44218 100644
--- a/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.test.tsx
@@ -31,7 +31,7 @@ function conPeriodo(datos: Datos, consulta: ConsultaConversion): Datos {
   const dias = Math.round((Date.parse(`${fechas.hasta}T12:00:00Z`) - Date.parse(`${fechas.desde}T12:00:00Z`)) / 86_400_000) + 1
   return consulta.modo === 'mes'
     ? { ...datos, periodo: { ...datos.periodo, modo: 'mes', mes: consulta.mes, desde: fechas.desde, hasta: fechas.hasta, dias } }
-    : { ...datos, sellado: false, periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: fechas.desde, hasta: fechas.hasta, dias } }
+    : { ...datos, sellado: false, fuente: { ...datos.fuente, modo: 'rango_vivo' }, periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: fechas.desde, hasta: fechas.hasta, dias, cruza_meses_sellados: false } }
 }
 
 /** Lo que OYE el lector: el «—» va oculto y su motivo, en sr-only. */
@@ -57,9 +57,9 @@ describe('ConversionCoordinacion', () => {
 
     const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
     const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
-    // Analista · Supervisor · Llegadas (F, L, total) · Cierres (F, L, referido «n · aporte», oficina, upgrade, renovación «n · aporte», ponderados) · %
+    // Analista · Supervisor · Llegadas (F, L, total) · Cierres (F, L, referido «n · aporte», sin peso (oficina + otros), upgrade, renovación «n · aporte», ponderados) · %
     expect(within(astrid).getAllByRole('cell').map(textoHablado))
-      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '5', '2', '1 referidos, aportan 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
+      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '5', '2', '1 referido, aporta 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
     expect(within(astrid).getAllByRole('cell')[7]?.querySelector('[aria-hidden="true"]')?.textContent).toBe('1 · 0.15')
 
     const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
@@ -84,11 +84,11 @@ describe('ConversionCoordinacion', () => {
     expect(cifra('Landing')).toBe('79')
     expect(cifra('Conversión')).toBe('9.83%')
     expect(cifra('Cierres directos')).toBe('14')
-    expect(textoHablado(within(resumen).getByText('Referidos').nextElementSibling as HTMLElement)).toBe('1 referidos, aportan 0.15')
+    expect(textoHablado(within(resumen).getByText('Referidos').nextElementSibling as HTMLElement)).toBe('1 referido, aporta 0.15')
     expect(cifra('Upgrade')).toBe('6')
     expect(textoHablado(within(resumen).getByText('Renovación').nextElementSibling as HTMLElement)).toBe('0 renovaciones, aportan 0')
     expect(screen.getByTestId('formula-numerador')).toHaveTextContent(
-      'Cierres ponderados 20.15 = 14 directos (formulario y landing) + 0.15 de referidos (1 × 0.15) + 6 de upgrade + 0 de renovación (0 × 0.15). Oficina (1) no pesa.',
+      'Cierres ponderados 20.15 = 14 directos (formulario y landing) + 0.15 de referidos (1 × 0.15) + 6 de upgrade + 0 de renovación (0 × 0.15). Sin peso: 1 de oficina y 0 de otros orígenes.',
     )
 
     expect(screen.getByRole('status')).toHaveTextContent('Conversión de setiembre 2026: 205 llegadas, 9.83%.')
@@ -125,7 +125,8 @@ describe('ConversionCoordinacion', () => {
     expect(screen.getByRole('status')).toHaveTextContent('Elige un mes válido (año y mes) para consultar la conversión.')
     expect(screen.queryByText(/Revisa tu conexión/)).not.toBeInTheDocument()
     expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
-    expect(screen.queryByRole('table')).not.toBeInTheDocument()
+    // El error del formulario no borra lo último cargado: la tabla sigue mientras se corrige el campo.
+    expect(screen.getByRole('table', { name: 'Conversión por analista' })).toBeInTheDocument()
     expect(conversionMock).toHaveBeenCalledTimes(llamadas)
   })
 
@@ -138,7 +139,7 @@ describe('ConversionCoordinacion', () => {
     const tabla = screen.getByRole('table', { name: 'Conversión por analista' })
     const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
     expect(within(astrid).getAllByRole('cell').map(textoHablado))
-      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', 'sin desglose: mes cerrado', 'sin desglose: mes cerrado', '115', '5', '2', '1 referidos, aportan 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
+      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', 'sin desglose: mes cerrado', 'sin desglose: mes cerrado', '115', '5', '2', '1 referido, aporta 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
     const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
     expect(textoHablado(within(resumen).getByText('Formulario').nextElementSibling as HTMLElement)).toBe('sin desglose: mes cerrado')
     expect(screen.getByRole('status')).toHaveTextContent(/Mes cerrado: se muestra la foto del cierre/)
@@ -150,7 +151,7 @@ describe('ConversionCoordinacion', () => {
       empresa: {
         divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0,
         numerador_bruto: 0, ajuste_pendiente: 0, desglose_disponible: true,
-        cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0 },
+        cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
         cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
       },
       sin_analista: null,
@@ -254,7 +255,9 @@ describe('ConversionCoordinacion', () => {
     const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
     const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
     expect(within(merlys).getAllByRole('cell')[11]).toHaveTextContent('8bruto 9 − ajuste 1')
-    expect(screen.getByTestId('formula-numerador')).toHaveTextContent('− 1 de ajuste de meses ya pagados = 19.15 netos')
+    // La empresa no es «bruto − ajuste»: el suelo en cero va por analista, así que no se afirma esa igualdad.
+    expect(screen.getByTestId('formula-numerador')).toHaveTextContent('Ajuste de meses ya pagados: 1, descontado por analista con suelo en cero. Netos: 19.15.')
+    expect(screen.getByTestId('formula-numerador')).not.toHaveTextContent('= 19.15')
   })
 
   it('en modo rango pide las dos fechas inclusivas y anuncia el rango en vivo', async () => {
@@ -275,6 +278,50 @@ describe('ConversionCoordinacion', () => {
     await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(/^Conversión\s+del 1 de setiembre de 2026 al 15 de setiembre de 2026:/))
     expect(screen.getByRole('status')).toHaveTextContent('Rango libre: cifras en vivo')
     expect(screen.queryByText(/Mes cerrado/)).not.toBeInTheDocument()
+    // En rango los pesos van por mes de cada episodio: la fórmula no promete «n × peso»,
+    // y los textos hablan «del período», no «del mes».
+    expect(screen.getByTestId('formula-numerador')).toHaveTextContent('0.15 de referidos (1) + 6 de upgrade + 0 de renovación (0)')
+    expect(screen.getByTestId('formula-numerador')).not.toHaveTextContent('×')
+    expect(screen.getByRole('region', { name: 'Conversión del período' })).toBeInTheDocument()
+    expect(screen.getByRole('group', { name: 'Resumen de conversión del período' })).toBeInTheDocument()
+  })
+
+  it('un rango que toca meses ya cerrados lo avisa en pantalla y en el estado vivo', async () => {
+    const usuario = userEvent.setup()
+    conversionMock.mockImplementation(async (consulta) => {
+      const datos = conPeriodo(payloadValido(), consulta)
+      if (consulta.modo === 'rango') datos.periodo = { ...datos.periodo, cruza_meses_sellados: true }
+      return datos
+    })
+    render(<ConversionCoordinacion />)
+    await screen.findByRole('table', { name: 'Conversión por analista' })
+    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
+
+    expect(await screen.findByText(/Este rango toca meses ya cerrados/)).toBeInTheDocument()
+    expect(screen.getByRole('status')).toHaveTextContent('Toca meses ya cerrados y puede diferir de su foto')
+  })
+
+  it('teclear fechas no consulta por cada dígito: espera a que el usuario pare y marca solo el campo que está mal', async () => {
+    const usuario = userEvent.setup()
+    render(<ConversionCoordinacion />)
+    await screen.findByRole('table', { name: 'Conversión por analista' })
+    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
+    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith(expect.objectContaining({ modo: 'rango' })))
+    const llamadas = conversionMock.mock.calls.length
+
+    const desde = screen.getByLabelText('Desde')
+    const hasta = screen.getByLabelText<HTMLInputElement>('Hasta')
+    await usuario.clear(desde)
+    // Un campo vacío es un error del formulario solo en ESE campo, y no borra la tabla ya cargada.
+    expect(desde).toHaveAttribute('aria-invalid', 'true')
+    expect(hasta).not.toHaveAttribute('aria-invalid')
+    expect(screen.getByRole('table', { name: 'Conversión por analista' })).toBeInTheDocument()
+    await usuario.type(desde, '2026-09-03')
+    await usuario.clear(desde)
+    await usuario.type(desde, '2026-09-05')
+    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith({ modo: 'rango', desde: '2026-09-05', hasta: hasta.value }))
+    // Dos fechas completas tecleadas seguidas → una sola consulta (la última), no una por cada valor intermedio.
+    expect(conversionMock.mock.calls.length - llamadas).toBe(1)
   })
 
   it('un rango con la fecha inicial después de la final es un error del formulario, sin llamar a la puerta', async () => {
diff --git a/CRM-Avance-Corp/app/src/components/common/tabla.tsx b/CRM-Avance-Corp/app/src/components/common/tabla.tsx
index 007c5d87..9b3eb542 100644
--- a/CRM-Avance-Corp/app/src/components/common/tabla.tsx
+++ b/CRM-Avance-Corp/app/src/components/common/tabla.tsx
@@ -33,12 +33,18 @@ export function TablaEnvoltura({ ariaLabel, children }: { ariaLabel?: string; ch
 }
 
 /** thead canónico del CRM: UNA fila de cabecera con el estilo de la casa. */
-export function TheadCrm({ children }: { children: ReactNode }) {
+const FILA_THEAD = 'border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground'
+
+/**
+ * UNA cabecera por tabla. `segundaFila` permite cabeceras agrupadas (dos `<tr>`
+ * dentro del MISMO `<thead>`, con `rowSpan`/`colSpan` y `scope` en las celdas):
+ * repetir `TheadCrm` produciría dos `<thead>`, que es HTML inválido.
+ */
+export function TheadCrm({ children, segundaFila }: { children: ReactNode; segundaFila?: ReactNode }) {
   return (
     <thead>
-      <tr className="border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
-        {children}
-      </tr>
+      <tr className={FILA_THEAD}>{children}</tr>
+      {segundaFila ? <tr className={FILA_THEAD}>{segundaFila}</tr> : null}
     </thead>
   )
 }
diff --git a/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts b/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
index 0e31d03b..0214172a 100644
--- a/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
@@ -697,7 +697,8 @@ describe('conversionCoordinacion (crm.conversion_divisor_coordinacion_fn)', () =
       const datos = conversionValida()
       return HttpResponse.json({
         ...datos,
-        periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: '15' },
+        fuente: { ...datos.fuente, modo: 'rango_vivo' },
+        periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: '15', cruza_meses_sellados: false },
       })
     }))
     const datos = await conversionCoordinacion({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })
diff --git a/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.test.ts b/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.test.ts
index 5bd63919..936ee265 100644
--- a/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.test.ts
@@ -8,6 +8,7 @@ import { describe, expect, it } from 'vitest'
 import * as v from 'valibot'
 import {
   ConversionCoordinacionSchema,
+  camposInvalidos,
   conversionCoordinacionConsistente,
   diasInclusivos,
   fechasDeConsulta,
@@ -28,15 +29,15 @@ export function payloadValido(): ConversionCoordinacion {
     version: 1,
     generado_en: '2026-09-30T18:00:00.000Z',
     alcance: 'global',
-    periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30 },
+    periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30, cruza_meses_sellados: false },
     sellado: false,
     peso_referido: 0.15,
     peso_renovacion: 0.15,
-    fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead' },
+    fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead', modo: 'mensual' },
     empresa: {
       divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79,
       numerador_bruto: 20.15, ajuste_pendiente: 0, desglose_disponible: true,
-      cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1 },
+      cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1, otros: 0 },
       cartera: { upgrade: 6, renovacion: 0, renovacion_aporte: 0 },
     },
     sin_analista: { divisor: 2, numerador: 0 },
@@ -45,14 +46,14 @@ export function payloadValido(): ConversionCoordinacion {
         analista_id: ASTRID, nombre: 'ASTRID CENTENARO', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA',
         en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7,
         numerador_bruto: 11.15, ajuste_pendiente: 0, desglose_disponible: true,
-        cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1 },
+        cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1, otros: 0 },
         cartera: { upgrade: 4, renovacion: 0, renovacion_aporte: 0 },
       },
       {
         analista_id: MERLYS, nombre: 'MERLYS GARCIA', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA',
         en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23,
         numerador_bruto: 9, ajuste_pendiente: 0, desglose_disponible: true,
-        cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0 },
+        cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
         cartera: { upgrade: 2, renovacion: 0, renovacion_aporte: 0 },
       },
     ],
@@ -75,6 +76,7 @@ export function payloadSellado(conDesglose = true): ConversionCoordinacion {
   return {
     ...datos,
     sellado: true,
+    fuente: { ...datos.fuente, modo: 'foto' },
     empresa: sellar(datos.empresa) as ConversionCoordinacion['empresa'],
     analistas: datos.analistas.map((a) => sellar(a) as ConversionCoordinacion['analistas'][number]),
   }
@@ -111,21 +113,26 @@ describe('conversionCoordinacionConsistente', () => {
     ajustado.empresa = { ...ajustado.empresa, ajuste_pendiente: 1, numerador: 19.15 }
     expect(conversionCoordinacionConsistente(ajustado, '2026-09-01', '2026-09-30')).toBe(true)
 
+    // El suelo en cero es POR PERSONA: la empresa suma netos (11,15 + 0 = 11,15), no max(bruto − ajuste, 0).
     const conSuelo = payloadValido()
     conSuelo.analistas[1] = { ...conSuelo.analistas[1]!, ajuste_pendiente: 12, numerador: 0 }
-    conSuelo.empresa = { ...conSuelo.empresa, ajuste_pendiente: 12, numerador: 8.15 }
+    conSuelo.empresa = { ...conSuelo.empresa, ajuste_pendiente: 12, numerador: 11.15 }
     expect(conversionCoordinacionConsistente(conSuelo, '2026-09-01', '2026-09-30')).toBe(true)
+    const sueloAlAgregado = payloadValido()
+    sueloAlAgregado.analistas[1] = { ...sueloAlAgregado.analistas[1]!, ajuste_pendiente: 12, numerador: 0 }
+    sueloAlAgregado.empresa = { ...sueloAlAgregado.empresa, ajuste_pendiente: 12, numerador: 8.15 }
+    expect(conversionCoordinacionConsistente(sueloAlAgregado, '2026-09-01', '2026-09-30')).toBe(false)
   })
 
   it('tolera los decimales de los pesos (19 referidos × 0,15 = 2,85) sin falso rojo', () => {
     const datos = payloadValido()
     datos.analistas[0] = {
       ...datos.analistas[0]!,
-      cierres: { formulario: 65, landing: 25, referido: 19, referido_aporte: 2.85, oficina: 11 },
+      cierres: { formulario: 65, landing: 25, referido: 19, referido_aporte: 2.85, oficina: 11, otros: 0 },
       cartera: { upgrade: 24, renovacion: 3, renovacion_aporte: 0.45 },
       numerador_bruto: 117.3, numerador: 117.3,
     }
-    datos.empresa = { ...datos.empresa, cierres: { formulario: 71, landing: 26, referido: 19, referido_aporte: 2.85, oficina: 11 }, cartera: { upgrade: 26, renovacion: 3, renovacion_aporte: 0.45 }, numerador_bruto: 126.3, numerador: 126.3 }
+    datos.empresa = { ...datos.empresa, cierres: { formulario: 71, landing: 26, referido: 19, referido_aporte: 2.85, oficina: 11, otros: 0 }, cartera: { upgrade: 26, renovacion: 3, renovacion_aporte: 0.45 }, numerador_bruto: 126.3, numerador: 126.3 }
     expect(sumaDePartes(datos.analistas[0].cierres!, datos.analistas[0].cartera!)).toBeCloseTo(117.3, 6)
     expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(true)
   })
@@ -171,12 +178,12 @@ describe('conversionCoordinacionConsistente', () => {
     datos.empresa = {
       divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0,
       numerador_bruto: 0, ajuste_pendiente: 0, desglose_disponible: true,
-      cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0 },
+      cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
       cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
     }
     datos.analistas = [{
       ...datos.analistas[0]!, divisor: 0, divisor_formulario: 0, divisor_landing: 0, numerador: 0, conversion_pct: null,
-      numerador_bruto: 0, cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0 },
+      numerador_bruto: 0, cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
       cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
     }]
     expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(true)
@@ -219,7 +226,8 @@ export function payloadRango(): ConversionCoordinacion {
   const datos = payloadValido()
   return {
     ...datos,
-    periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: 15 },
+    periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: 15, cruza_meses_sellados: false },
+    fuente: { ...datos.fuente, modo: 'rango_vivo' },
   }
 }
 
@@ -276,5 +284,31 @@ describe('modo rango (v2)', () => {
     expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-01', hasta: '2026-10-01' }, hoy)).toMatch(/fechas futuras/)
     expect(motivoConsultaInvalida({ modo: 'rango', desde: '2025-09-01', hasta: '2026-09-30' }, hoy)).toMatch(/366 días/)
     expect(motivoConsultaInvalida({ modo: 'rango', desde: '', hasta: '2026-09-15' }, hoy)).toMatch(/dos fechas/)
+    // Un año tecleado a medias (0202-…) queda por debajo del mínimo y no dispara consulta.
+    expect(motivoConsultaInvalida({ modo: 'rango', desde: '0202-09-01', hasta: '2026-09-15' }, hoy)).toMatch(/empieza como pronto/)
+  })
+
+  it('camposInvalidos marca solo el campo que está mal', () => {
+    const hoy = '2026-09-30'
+    expect(camposInvalidos({ modo: 'rango', desde: '', hasta: '2026-09-15' }, hoy)).toEqual({ desde: true, hasta: false })
+    expect(camposInvalidos({ modo: 'rango', desde: '2026-09-01', hasta: '2026-10-01' }, hoy)).toEqual({ desde: false, hasta: true })
+    expect(camposInvalidos({ modo: 'rango', desde: '2026-09-16', hasta: '2026-09-15' }, hoy)).toEqual({ desde: true, hasta: true })
+    expect(camposInvalidos({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' }, hoy)).toEqual({ desde: false, hasta: false })
+    expect(camposInvalidos({ modo: 'mes', mes: '2026-13' }, hoy)).toEqual({ desde: false, hasta: false })
+  })
+
+  it('un rango que declara cruzar meses sellados es válido; un mes no puede declararlo; el modo de la fuente debe casar', () => {
+    const cruza = payloadRango()
+    cruza.periodo = { ...cruza.periodo, cruza_meses_sellados: true }
+    expect(conversionCoordinacionConsistente(cruza, '2026-09-01', '2026-09-15')).toBe(true)
+    const mesCruza = payloadValido()
+    mesCruza.periodo = { ...mesCruza.periodo, cruza_meses_sellados: true }
+    expect(conversionCoordinacionConsistente(mesCruza, '2026-09-01', '2026-09-30')).toBe(false)
+    const fuenteMal = payloadRango()
+    fuenteMal.fuente = { ...fuenteMal.fuente, modo: 'mensual' }
+    expect(conversionCoordinacionConsistente(fuenteMal, '2026-09-01', '2026-09-15')).toBe(false)
+    const fotoAbierta = payloadValido()
+    fotoAbierta.fuente = { ...fotoAbierta.fuente, modo: 'foto' }
+    expect(conversionCoordinacionConsistente(fotoAbierta, '2026-09-01', '2026-09-30')).toBe(false)
   })
 })
diff --git a/CRM-Avance-Corp/app/src/screens/repartir.test.tsx b/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
index 9a47dae0..648a82c8 100644
--- a/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
@@ -87,7 +87,7 @@ const reporteDiarioMock = vi.fn(async (_desde: string, _hasta: string) => REPORT
 const conversionMock = vi.fn(async (consulta: { modo: 'mes'; mes: string } | { modo: 'rango'; desde: string; hasta: string }) => {
   const base = payloadConversionValido()
   if (consulta.modo === 'rango') {
-    return { ...base, periodo: { modo: 'rango' as const, mes: null, mes_nombre: null, anio: null, zona: 'America/Lima' as const, desde: consulta.desde, hasta: consulta.hasta, dias: 1 } }
+    return { ...base, fuente: { ...base.fuente, modo: 'rango_vivo' as const }, periodo: { modo: 'rango' as const, mes: null, mes_nombre: null, anio: null, zona: 'America/Lima' as const, desde: consulta.desde, hasta: consulta.hasta, dias: 1, cruza_meses_sellados: false } }
   }
   const [anio, mesNum] = consulta.mes.split('-').map(Number) as [number, number]
   const hasta = new Date(Date.UTC(anio, mesNum, 0)).toISOString().slice(0, 10)
diff --git a/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql b/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
index 11af1f1a..f328647b 100644
--- a/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
+++ b/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
@@ -215,7 +215,11 @@ begin
 end;
 $siembra_ok$;
 
--- Mes SELLADO sintético: dos meses atrás, con foto por persona y cobertura.
+-- Mes SELLADO sintético: dos meses atrás, con foto por persona y cobertura. La foto por
+-- persona lleva su desglose por origen escrito a mano: el trigger que lo recalcula al
+-- sellar (`trg_cierre_mes_vendedor_10_ranking_origen`, sobre datos vivos) se apaga para
+-- ESTA siembra, porque aquí no hay datos vivos de hace dos meses. Solo en banco.
+alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_10_ranking_origen;
 insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
 values (
   (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date,
@@ -233,13 +237,20 @@ insert into crm.cierre_mes_vendedor (
   periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor, divisor_aproximado,
   divisor_por_motivo, cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, conversion_pct,
   estado, referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia, ajuste_numerador, ajuste_pen, ajuste_usd,
-  conversion_objetivo
+  conversion_objetivo, cartera, origenes_ranking
 ) values (
   (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date,
   'c0000000-0000-4000-8000-000000000005', 'ORACULO ANA', 'c0000000-0000-4000-8000-000000000003', 'ORACULO SUPERVISORA UNO',
-  40, 0, '{"llegada": 40}'::jsonb, 4, 0, 0, 4, 10.00, 'sellado', 0, 0, null, '[]'::jsonb, 0, 0, 0,
-  8.00
+  -- numerador 4 = 2 formulario + 1 landing + 2 referidos × 0,5 (1) + 0 upgrade… no: con la foto de abajo,
+  -- partes = 2 + 1 + 2×0,5 + 1 upgrade + 2×0,5 renovación = 6 y ajuste_numerador 2 → neto 4.
+  40, 0, '{"llegada": 40}'::jsonb, 3, 2, 0, 4, 10.00, 'sellado', 2, 0, null, '[]'::jsonb, 2, 0, 0,
+  8.00,
+  -- `operaciones_*` cuenta TODAS las operaciones; `conversiones_*` solo la primera elegible por
+  -- cliente y mes, que es la que sumó el numerador. Se siembran distintas para cazar la confusión.
+  '{"conversiones_clientes": 3, "conversiones_renovacion": 2, "conversiones_upgrade": 1, "operaciones_renovacion": 5, "operaciones_upgrade": 4, "capital_renovado_pen": 0, "capital_renovado_usd": 0, "capital_adicional_pen": 0, "capital_adicional_usd": 0, "renovaciones_sin_desglose": 0}'::jsonb,
+  '{"disponible": true, "filas": [{"origen": "formulario", "leads": 20, "cierres": 2}, {"origen": "landing", "leads": 15, "cierres": 1}, {"origen": "referido", "leads": 3, "cierres": 2}, {"origen": "oficina", "leads": 2, "cierres": 1}, {"origen": "whatsapp", "leads": 1, "cierres": 1}]}'::jsonb
 );
+alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_10_ranking_origen;
 
 -- ─────────────────────────────────────────────────────────────────────────────
 -- Recorrido por las puertas REALES del reparto, como usuario autenticado.
@@ -546,16 +557,25 @@ declare
   v_fin date := (date_trunc('month', now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date;
   v_hoy date := (now() at time zone 'America/Lima')::date;
   v_mes_sellado date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
+  v_mes_previo date := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
   v_pay_mes jsonb;
   v_pay jsonb;
+  v_pay_prev jsonb;
 begin
   perform set_config('request.jwt.claim.sub', v_coord::text, true);
   v_pay_mes := crm.conversion_divisor_coordinacion_fn(v_mes);
 
-  -- (a) Un rango que es exactamente el mes calendario ES el mes (misma foto, salvo el reloj).
-  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes, v_fin);
-  if (v_pay - 'generado_en') <> (v_pay_mes - 'generado_en') then
-    raise exception 'E09a el rango 1 → fin de mes no es idéntico al mes';
+  -- (a) Un rango que es exactamente un mes calendario ES ese mes (misma foto, salvo el
+  --     reloj). Se usa el mes ANTERIOR, que siempre está completo en el pasado.
+  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes_previo, (v_mes - interval '1 day')::date);
+  if (v_pay - 'generado_en') <> (crm.conversion_divisor_coordinacion_fn(v_mes_previo) - 'generado_en')
+     or v_pay->'periodo'->>'modo' <> 'mes' or v_pay->'fuente'->>'modo' <> 'mensual'
+     or (v_pay->'periodo'->>'cruza_meses_sellados')::boolean is not false then
+    raise exception 'E09a el rango 1 → fin del mes anterior no es idéntico al mes: %', v_pay->'periodo';
+  end if;
+  -- (a2) El mes anterior abierto por rango tiene a ANA con L6 (alta del último día del mes anterior).
+  if (select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 1 then
+    raise exception 'E09a2 el mes anterior por rango no trae la llegada de borde de ANA';
   end if;
 
   -- (b) Del 1 a hoy: modo rango (salvo el último día del mes, en que ES el mes),
@@ -566,10 +586,37 @@ begin
      or (v_pay->'periodo'->>'dias')::int <> (v_hoy - v_mes + 1)
      or (v_hoy <> v_fin and v_pay->'periodo'->'mes' <> 'null'::jsonb)
      or (v_pay->'empresa'->>'divisor')::int is distinct from (v_pay_mes->'empresa'->>'divisor')::int
-     or (v_pay->'empresa'->>'numerador')::numeric is distinct from (v_pay_mes->'empresa'->>'numerador')::numeric
-     or (v_pay->'empresa'->>'ajuste_pendiente')::numeric is distinct from 0
+     or (v_pay->'empresa'->>'numerador_bruto')::numeric is distinct from (v_pay_mes->'empresa'->>'numerador_bruto')::numeric
+     or (v_hoy <> v_fin and ((v_pay->'empresa'->>'ajuste_pendiente')::numeric is distinct from 0
+                             or (v_pay->'empresa'->>'numerador')::numeric is distinct from (v_pay->'empresa'->>'numerador_bruto')::numeric
+                             or v_pay->'fuente'->>'modo' is distinct from 'rango_vivo'))
      or (select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 2 then
-    raise exception 'E09b el rango 1 → hoy no reproduce el mes: % vs %', v_pay->'empresa', v_pay_mes->'empresa';
+    raise exception 'E09b el rango 1 → hoy no reproduce el bruto del mes: % vs %', v_pay->'empresa', v_pay_mes->'empresa';
+  end if;
+
+  -- (b2) Un rango REAL cualquier día del año: del 15 del mes anterior a hoy cruza el
+  --      límite de mes, nunca es «mes exacto» y cae en modo rango_vivo; sus partes
+  --      suman su bruto, no lleva ajuste, y sus llegadas son la suma de las dos piezas.
+  v_pay := crm.conversion_divisor_coordinacion_fn(null, (v_mes_previo + 14)::date, v_hoy);
+  v_pay_prev := crm.conversion_divisor_coordinacion_fn(null, (v_mes_previo + 14)::date, (v_mes - interval '1 day')::date);
+  if v_pay->'periodo'->>'modo' <> 'rango' or v_pay->'fuente'->>'modo' <> 'rango_vivo' or (v_pay->>'sellado')::boolean
+     or (v_pay->'periodo'->>'cruza_meses_sellados')::boolean is not false
+     or (v_pay->'empresa'->>'ajuste_pendiente')::numeric is distinct from 0
+     or (v_pay->'empresa'->>'numerador')::numeric is distinct from (v_pay->'empresa'->>'numerador_bruto')::numeric
+     or (v_pay->'empresa'->>'divisor')::int is distinct from (v_pay_prev->'empresa'->>'divisor')::int + (v_pay_mes->'empresa'->>'divisor')::int
+     or exists (
+       select 1 from jsonb_array_elements(v_pay->'analistas') a
+       where (a->>'numerador_bruto')::numeric is distinct from
+             (a#>>'{cierres,formulario}')::numeric + (a#>>'{cierres,landing}')::numeric + (a#>>'{cierres,referido_aporte}')::numeric
+             + (a#>>'{cartera,upgrade}')::numeric + (a#>>'{cartera,renovacion_aporte}')::numeric
+          or (a->>'ajuste_pendiente')::numeric is distinct from 0
+          or (a->>'numerador')::numeric is distinct from (a->>'numerador_bruto')::numeric) then
+    raise exception 'E09b2 el rango que cruza el mes anterior no cumple la invariante: %', v_pay->'empresa';
+  end if;
+  -- (b3) Un rango libre que TOCA el mes sellado lo declara.
+  v_pay := crm.conversion_divisor_coordinacion_fn(null, (v_mes_sellado + 14)::date, v_hoy);
+  if (v_pay->'periodo'->>'cruza_meses_sellados')::boolean is not true or v_pay->'fuente'->>'modo' <> 'rango_vivo' or (v_pay->>'sellado')::boolean then
+    raise exception 'E09b3 el rango que cruza un mes sellado no lo declara: %', v_pay->'periodo';
   end if;
 
   -- (c) Un rango parcial no puede superar al mes (L1 y L2 nacieron hoy: del 1 a ayer ANA no las tiene).
@@ -640,16 +687,36 @@ begin
   where a->>'analista_id' = 'c0000000-0000-4000-8000-000000000005';
   if v_fila is null or (v_fila->>'divisor')::int is distinct from 40 or (v_fila->>'numerador')::numeric is distinct from 4
      or (v_fila->>'conversion_pct')::numeric is distinct from 10.00
-     or v_fila->'divisor_formulario' is distinct from 'null'::jsonb or v_fila->'divisor_landing' is distinct from 'null'::jsonb then
-    raise exception 'E07b la fila sellada no es la foto (40 / 4 / 10.00, sin desglose): %', v_fila;
+     or v_fila->'divisor_formulario' is distinct from 'null'::jsonb or v_fila->'divisor_landing' is distinct from 'null'::jsonb
+     or v_fila->'numerador_bruto' is distinct from 'null'::jsonb or v_fila->'ajuste_pendiente' is distinct from 'null'::jsonb then
+    raise exception 'E07b la fila sellada no es la foto (40 / 4 / 10.00, sin llegadas por origen ni bruto): %', v_fila;
+  end if;
+  -- El desglose sellado sale de la foto: origenes_ranking.filas (conteos por origen) y
+  -- cartera.conversiones_* (NO operaciones_*), con los pesos SELLADOS (0,5); y sus partes
+  -- reproducen el numerador de la foto más el ajuste que se aplicó al sellar (6 − 2 = 4).
+  if (v_fila->>'desglose_disponible')::boolean is not true
+     or (v_fila#>>'{cierres,formulario}')::int is distinct from 2 or (v_fila#>>'{cierres,landing}')::int is distinct from 1
+     or (v_fila#>>'{cierres,referido}')::int is distinct from 2 or (v_fila#>>'{cierres,referido_aporte}')::numeric is distinct from 1.0
+     or (v_fila#>>'{cierres,oficina}')::int is distinct from 1 or (v_fila#>>'{cierres,otros}')::int is distinct from 1
+     or (v_fila#>>'{cartera,upgrade}')::int is distinct from 1 or (v_fila#>>'{cartera,renovacion}')::int is distinct from 2
+     or (v_fila#>>'{cartera,renovacion_aporte}')::numeric is distinct from 1.0 then
+    raise exception 'E07b2 el desglose sellado no sale de la foto (conversiones_*, pesos sellados): %', v_fila;
+  end if;
+  if (v_fila#>>'{cierres,formulario}')::numeric + (v_fila#>>'{cierres,landing}')::numeric + (v_fila#>>'{cierres,referido_aporte}')::numeric
+     + (v_fila#>>'{cartera,upgrade}')::numeric + (v_fila#>>'{cartera,renovacion_aporte}')::numeric
+     is distinct from (v_fila->>'numerador')::numeric + 2 /* ajuste_numerador sembrado en la foto */ then
+    raise exception 'E07b3 las partes selladas no reproducen numerador + ajuste de la foto: %', v_fila;
   end if;
   -- Empresa = foto por persona (40 / 4) + fuera_ranking con conversión (5 / 1) + sin analista (3 / 0).
   if (v_pay->'empresa'->>'divisor')::int is distinct from 48 or (v_pay->'empresa'->>'numerador')::numeric is distinct from 5
      or (v_pay->'empresa'->>'conversion_pct')::numeric is distinct from round(100.0 * 5 / 48, 2)
      or (v_pay->'sin_analista'->>'divisor')::int is distinct from 3
      or v_pay->'empresa'->'divisor_formulario' is distinct from 'null'::jsonb
-     or (v_pay->>'peso_referido')::numeric is distinct from 0.5 then
-    raise exception 'E07c la empresa sellada no suma foto + fuera_ranking + sin analista: %', v_pay->'empresa';
+     or (v_pay->>'peso_referido')::numeric is distinct from 0.5
+     or (v_pay->'empresa'->>'desglose_disponible')::boolean is not false
+     or v_pay->'empresa'->'cierres' is distinct from 'null'::jsonb
+     or v_pay->'fuente'->>'modo' is distinct from 'foto' then
+    raise exception 'E07c la empresa sellada no suma foto + fuera_ranking + sin analista, o declara un desglose que no cubre el total: %', v_pay->'empresa';
   end if;
   -- Foto con conversion_sin_analista en JSON null: ausencia, no un objeto de nulos.
   v_pay := crm.conversion_divisor_coordinacion_fn((v_mes - interval '1 month')::date);
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index 578c59b9..80eb6e08 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -9734,39 +9734,6 @@ async function testReparto(sessions, seed) {
       'coordinador sin p_periodo recibe el mes vigente en Lima',
       coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn'),
     );
-    // v2: rango de fechas (inclusivo, Lima). Del 1 a hoy reproduce el mes; los
-    // rangos inválidos y «mes + rango a la vez» son 22023; el gate sigue primero.
-    const hoyLima = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
-    const convRango = await positive(
-      'coordinador consulta por rango de fechas (del 1 a hoy)',
-      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
-    );
-    if (convRango && convCoord) {
-      check(['mes', 'rango'].includes(convRango.data?.periodo?.modo) && convRango.data?.periodo?.desde === P_MES.p_periodo
-        && convRango.data?.periodo?.hasta === hoyLima,
-        'el rango eco-a desde/hasta inclusivos y declara el modo', JSON.stringify(convRango.data?.periodo));
-      check(convRango.data?.empresa?.divisor === convCoord.data?.empresa?.divisor,
-        'PARIDAD v2: el rango del 1 a hoy tiene el mismo divisor que el mes');
-    }
-    await expectBlockedMutation(
-      'coordinador: un rango con la fecha inicial posterior a la final se rechaza con 22023',
-      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: hoyLima, p_hasta: P_MES.p_periodo }),
-      ['22023'],
-    );
-    await expectBlockedMutation(
-      'coordinador: mes y rango a la vez se rechaza con 22023',
-      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_periodo: P_MES.p_periodo, p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
-      ['22023'],
-    );
-    await expectBlockedMutation(
-      'vendedor: el modo rango tampoco entra (42501 antes que validar)',
-      sessions.vend1.client.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
-      ['42501'],
-    );
-    if (convSinPeriodo) {
-      check(convSinPeriodo.data?.periodo?.desde === P_MES.p_periodo,
-        'sin p_periodo la puerta sirve el mes vigente', String(convSinPeriodo.data?.periodo?.desde));
-    }
     const convCoord = await positive(
       'coordinador obtiene la conversion por analista de toda la empresa',
       coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', P_MES),
@@ -9806,6 +9773,63 @@ async function testReparto(sessions, seed) {
       check(sinReloj(convCoord.data) === sinReloj(convGer.data),
         'gerencia y coordinador reciben el MISMO payload (ambito de toda la empresa)');
     }
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
+    const ayerLima = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(Date.now() - 86_400_000));
+    await expectBlockedMutation(
+      'coordinador: un rango con la fecha inicial posterior a la final se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: hoyLima, p_hasta: ayerLima }),
+      ['22023'],
+    );
+    await expectBlockedMutation(
+      'coordinador: un rango con fecha futura se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: hoyLima, p_hasta: '2999-01-01' }),
+      ['22023'],
+    );
+    await expectBlockedMutation(
+      'coordinador: un rango de más de 366 días se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: '2020-01-01', p_hasta: hoyLima }),
+      ['22023'],
+    );
+    await expectBlockedMutation(
+      'coordinador: un rango con una sola fecha se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: P_MES.p_periodo }),
+      ['22023'],
+    );
+    const convRangoGer = await positive(
+      'gerencia consulta el mismo rango',
+      gerencia.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_desde: P_MES.p_periodo, p_hasta: hoyLima }),
+    );
+    if (convRango && convRangoGer) {
+      const sinReloj = (d) => JSON.stringify({ ...d, generado_en: null });
+      check(sinReloj(convRango.data) === sinReloj(convRangoGer.data), 'gerencia y coordinador reciben el mismo rango');
+    }
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
+    if (convSinPeriodo) {
+      check(convSinPeriodo.data?.periodo?.desde === P_MES.p_periodo,
+        'sin p_periodo la puerta sirve el mes vigente', String(convSinPeriodo.data?.periodo?.desde));
+    }
   }
   for (const [rol, cliente] of [
     ['vendedor', sessions.vend1.client],

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
