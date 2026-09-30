ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión (LEVEL 3: abre una lectura nueva al rol `coordinador`)

Eres el revisor secundario. Trabajas sin base de datos ni red: todo lo que necesitas juzgar está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps pertinentes, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; distingue hipótesis. Tu tarea principal es REFUTAR: busca la forma en que esto esté mal.

## Contexto (hechos verificados en producción, solo lectura, 30/09/2026)
- CRM Avance Corp (Supabase, esquemas `crm` = puertas, `private` = núcleo). Vocabulario: Tablas → Núcleo → Puerta → Pantalla.
- La coordinadora (rol `coordinador`) solo llega a `#/repartir`. En la pestaña «Supervisión → analistas» veía 62 en formulario para la analista Astrid; el núcleo de conversión dice 65 (divisor total 115 = 65 formulario + 50 landing).
- Fuente del 62, reproducida: `crm.reporte_derivaciones_coordinacion_fn` (reporte de ENTREGAS por fecha de entrega) excluye a propósito el episodio del ledger cerrado con `motivo_cierre='parqueado'` y `supervisor_destino_id = supervisor_origen_id` (devuelto a la bandeja antes de gestionar) y cuenta la re-entrega: atribuye el lead al ÚLTIMO receptor. El núcleo (`private.conversion_episodios`, episodio `recibido`) cuenta UNA llegada por lead por su alta original en Lima, en el PRIMER analista del ledger. Hipótesis «cuenta por dueño actual» refutada (daría 63). Los 8 leads que difieren en setiembre (3 de Astrid, 5 de Merlys) tienen todos ese patrón; no hay otra diferencia.
- Decisión de Miguel: el reporte de entregas NO cambia; la coordinadora recibe el divisor real del núcleo por una PUERTA NUEVA con ámbito de TODA la empresa. No se toca el núcleo ni los pesos, ni los conteos operativos por dueño actual, ni las puertas de conversión existentes (`crm.conversion_mensual_sin_cartera_fn` sigue denegando al coordinador).
- Regla de negocio confirmada: lead reasignado cuenta una sola vez, en quien lo recibió primero; no se le resta. Alta manual: no entra. Referido: pesa 0 en el divisor. Lead sin asignación: cuenta en empresa. Mes sellado: se sirve la foto (`crm.periodos_cerrados` + `crm.cierre_mes_vendedor`), nunca se recalcula.
- Gate canónico del reparto: `private.puede_operar_reparto_crm()` = `private.rol_crm(auth.uid()) in ('coordinador','gerencia')` (rol_crm exige `crm.equipo.activo` y `perfiles.activo` y el par de autoridad). No incluye `directorio` (lector global).
- Núcleo que se compone (huellas md5 de prosrc en prod, iguales en el banco Docker 13/13):
  - `private.conversion_neta_por_vendedor(p_periodo date, p_global boolean, p_visibles uuid[])` → TABLE(analista_id, en_nucleo, divisor, divisor_aproximado, divisor_por_motivo, cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador_bruto, ajuste_pendiente, ajuste_origenes, numerador, conversion_pct, procedencia, referidos_recibidos, referidos_aporta_pct). Lanza 22023 si el mes está sellado. Con p_global=true, p_visibles se ignora. Devuelve también una fila con analista_id NULL (producción sin analista).
  - `private.conversion_episodios(p_ini timestamptz, p_fin timestamptz, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)` → filas tipo 'recibido' con `aporte_divisor` = 1 si origen in ('landing','formulario') y no alta_manual, 0 si no; analista_id = primera asignación del ledger ordenada por (asignado_en, ciclo_n, episodio_n, id); NULL si no hay asignación.
  - `private.roster_conversion_mensual(p_periodo, p_global, p_visibles)` → (vendedor_id, supervisor_id) del roster del mes.
  - `private.peso_referido_conversion(date)`, `private.etiqueta_mes_es(date)`.
- Rama sellada en la puerta mensual existente (`crm.conversion_mensual_sin_cartera_fn`): filas por persona desde `crm.cierre_mes_vendedor` (columnas: periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor, numerador, conversion_pct, …) y total = filas + `cobertura->'fuera_ranking'[*].conversion` + `cobertura->'conversion_sin_analista'`.

## Verificación ya ejecutada (banco Docker propio con el esquema de prod al byte)
- Migración aplicada en un solo mensaje: preflight, dos funciones y postflight en verde.
- Oráculo transaccional (abajo) → ORACULO-DIVISOR-COORDINACION-OK; nada queda escrito. Recorre las puertas REALES del reparto (turno → repartir → derivar → devolver a bandeja → derivar).
- 4 mutantes cazados: (A) núcleo que cuenta por `crm.leads.vendedor_id` → E01d; (B) atribuye al último receptor leyendo `lead_asignaciones` → E01d; (C) duplica formulario → E04c; (D) numerador +1 → E05a. Original restaurado y oráculo verde.
- Registrador fail-closed probado: misma md5 que el archivo, idempotente, rechaza otro cuerpo.
- Front: `npm run check` PASS (319 archivos / 4955 tests, cobertura, build, bundle, dup). E2E Docker `repartir.spec.ts` 31/31 PASS.
- Tipos: bloque `conversion_divisor_coordinacion_fn` generado con `supabase gen types` contra el banco e insertado en `database.types.ts`.

## Preguntas concretas para refutar
1. ¿Puede la puerta filtrar datos fuera del ámbito o PII? ¿Algún oráculo de errores?
2. ¿La composición puede desviarse del núcleo (filas duplicadas por el join con roster/equipo/perfiles, NULLs, empates de nombre)? ¿El `left join crm.equipo` puede multiplicar filas?
3. Mes sellado: ¿la suma de `empresa` reproduce la de la puerta mensual? ¿`sin_analista` en foto?
4. `v_periodo` con `p_periodo` NULL → mes vigente: ¿coherente con el gate-antes-que-validación?
5. Postflight: ¿es tautológico? ¿Qué NO cubre el oráculo (numerador con cierres reales, ajustes de meses pagados, renovación/upgrade)?
6. Front: el candado `conversionCoordinacionConsistente` ¿puede rechazar payloads legítimos (p. ej. analista con divisor > formulario+landing por «aproximado» o referido)? ¿Riesgo de falso rojo en producción?
7. ¿Algo del alcance NO ENTRA se tocó? (núcleo, pesos, reporte de entregas, conteos por dueño actual).

## Archivos

### supabase/migrations/20260930185623_crm_conversion_divisor_coordinacion.sql
```sql
-- ============================================================================
-- CRM · Conversión por analista para Coordinación (el divisor sale del núcleo)
--
-- Por qué. Coordinación veía en «Supervisión → analistas» el reporte de ENTREGAS
-- (`crm.reporte_derivaciones_coordinacion_fn`). Ese reporte cuenta por fecha de
-- entrega y, a propósito, deja de sumar la entrega que volvió a la misma bandeja
-- antes de gestionarse: el lead queda en quien lo recibió DESPUÉS. No es el
-- divisor de conversión. El núcleo (`private.conversion_episodios`, episodio
-- `recibido`) cuenta UNA llegada por lead, por su alta original en Lima, en el
-- PRIMER analista del ledger de asignaciones, y no se la resta aunque el lead se
-- reasigne. Setiembre 2026: Astrid Centenaro 62 en el reporte contra 65 del
-- núcleo por tres leads parqueados y re-entregados el mismo día.
--
-- Decisión de Miguel (30/09/2026): el reporte de entregas NO cambia (es operativo
-- y comparte regla con el de Supervisión); Coordinación recibe el divisor real del
-- núcleo por una puerta nueva, con ámbito de TODA la empresa.
--
-- Capas, sin saltos nuevos:
--   * Núcleo `private.conversion_divisor_empresa(date)`: compone la MISMA pieza que
--     Metas y la puerta mensual (`private.conversion_neta_por_vendedor`: divisor,
--     numerador neto y porcentaje) con el desglose del divisor por origen, que sale
--     de los episodios `recibido` de `private.conversion_episodios`. En un mes
--     SELLADO sirve la foto de `crm.cierre_mes_vendedor` y no recalcula nada.
--     SECURITY DEFINER con `search_path` vacío, sin autorización dentro, ámbito
--     global fijado por contrato; sin ejecutores de la API.
--   * Puerta `crm.conversion_divisor_coordinacion_fn(date)`: autoriza con la puerta
--     canónica del reparto (`private.puede_operar_reparto_crm()`: coordinador o
--     gerencia activas), valida el período y delega. No define el divisor: lo lee.
--
-- Lo que NO toca: el núcleo de conversión y sus pesos, el reporte de entregas, los
-- conteos operativos por dueño actual y las puertas de conversión existentes.
--
-- Reversa exacta:
--   drop function if exists crm.conversion_divisor_coordinacion_fn(date);
--   drop function if exists private.conversion_divisor_empresa(date);
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
begin
  if pg_catalog.to_regprocedure(
       'private.conversion_neta_por_vendedor(date,boolean,uuid[])') is null then
    raise exception 'PREFLIGHT: falta private.conversion_neta_por_vendedor(date,boolean,uuid[])';
  end if;
  if pg_catalog.to_regprocedure(
       'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is null then
    raise exception 'PREFLIGHT: falta private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)';
  end if;
  if pg_catalog.to_regprocedure('private.roster_conversion_mensual(date,boolean,uuid[])') is null then
    raise exception 'PREFLIGHT: falta private.roster_conversion_mensual(date,boolean,uuid[])';
  end if;
  if pg_catalog.to_regprocedure('private.peso_referido_conversion(date)') is null then
    raise exception 'PREFLIGHT: falta private.peso_referido_conversion(date)';
  end if;
  if pg_catalog.to_regprocedure('private.etiqueta_mes_es(date)') is null then
    raise exception 'PREFLIGHT: falta private.etiqueta_mes_es(date)';
  end if;
  if pg_catalog.to_regprocedure('private.puede_operar_reparto_crm()') is null then
    raise exception 'PREFLIGHT: falta la puerta canónica private.puede_operar_reparto_crm()';
  end if;
  if pg_catalog.to_regclass('crm.cierre_mes_vendedor') is null
     or pg_catalog.to_regclass('crm.periodos_cerrados') is null then
    raise exception 'PREFLIGHT: faltan las tablas de la foto del cierre de mes';
  end if;
  -- Nombres libres: esta migración crea, no redefine (una función viva no se
  -- reteclea sin acreditar su cuerpo).
  if pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date)') is not null
     or pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)') is not null then
    raise exception 'PREFLIGHT: la función ya existe; esta migración no la redefine';
  end if;
end;
$preflight$;

-- ----------------------------------------------------------------------------
-- Núcleo: una fila por analista con la cifra del núcleo y su desglose por origen.
-- La fila con `analista_id` nulo es la producción SIN analista atribuible (leads
-- sin asignación): cuenta en la empresa y nunca se inventa un responsable.
-- ----------------------------------------------------------------------------
create function private.conversion_divisor_empresa(p_periodo date)
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
  conversion_pct numeric
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
begin
  if p_periodo is null or p_periodo <> pg_catalog.date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;

  -- Mes SELLADO: se sirve la foto por persona, tal cual se selló. El desglose por
  -- origen no forma parte de la foto y se declara desconocido (null): recalcularlo
  -- sobre datos vivos mentiría sobre el momento del sello.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    return query
    select f.vendedor_id,
           f.nombre_completo,
           f.supervisor_id,
           f.supervisor_nombre,
           true,
           f.divisor,
           null::integer,
           null::integer,
           f.numerador,
           f.conversion_pct
    from crm.cierre_mes_vendedor f
    where f.periodo = p_periodo
    order by f.nombre_completo;
    return;
  end if;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(p_periodo);

  return query
  with neto as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del núcleo, la misma que usa
    -- Metas y la puerta mensual: divisor, numerador neto y porcentaje sobre el neto.
    select n.*
    from private.conversion_neta_por_vendedor(p_periodo, true, null::uuid[]) n
  ),
  por_origen as materialized (
    -- El mismo aporte que suma el divisor, abierto por el origen del lead. Referido
    -- y alta manual aportan 0 en el núcleo, así que aquí tampoco pesan.
    select e.analista_id,
           (sum(e.aporte_divisor) filter (where e.origen = 'formulario'))::integer as divisor_formulario,
           (sum(e.aporte_divisor) filter (where e.origen = 'landing'))::integer as divisor_landing
    from private.conversion_episodios(v_ini, v_fin, p_periodo, true, null::uuid[], v_factor) e
    where e.tipo = 'recibido'
    group by e.analista_id
  ),
  roster as materialized (
    -- El supervisor del MES (roster de metas de ese período), no el de hoy.
    select r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(p_periodo, true, null::uuid[]) r
  )
  select n.analista_id,
         perfil.nombre_completo,
         coalesce(r.supervisor_id, equipo.supervisor_id),
         jefe.nombre_completo,
         n.en_nucleo,
         n.divisor,
         coalesce(o.divisor_formulario, 0),
         coalesce(o.divisor_landing, 0),
         n.numerador,
         n.conversion_pct
  from neto n
  left join por_origen o on o.analista_id is not distinct from n.analista_id
  left join roster r on r.vendedor_id = n.analista_id
  left join crm.equipo equipo on equipo.perfil_id = n.analista_id
  left join public.perfiles perfil on perfil.id = n.analista_id
  left join public.perfiles jefe on jefe.id = coalesce(r.supervisor_id, equipo.supervisor_id)
  order by perfil.nombre_completo nulls last;
end;
$function$;

comment on function private.conversion_divisor_empresa(date) is
  'Núcleo (30/09/2026): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación. Lee private.conversion_neta_por_vendedor (la misma pieza que Metas) y abre el divisor por origen desde los episodios recibidos de private.conversion_episodios; en un mes sellado sirve la foto de crm.cierre_mes_vendedor sin recalcular. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API.';

revoke all on function private.conversion_divisor_empresa(date)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Puerta: autoriza (coordinador o gerencia), valida el período y delega.
-- ----------------------------------------------------------------------------
create function crm.conversion_divisor_coordinacion_fn(p_periodo date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_periodo date := coalesce(p_periodo, pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date);
  v_cierre crm.periodos_cerrados%rowtype;
  v_payload jsonb;
begin
  -- 1) Gate primero: un actor denegado recibe 42501 aunque el período sea inválido.
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista'
      using errcode = '42501';
  end if;

  -- 2) Validación del período.
  if v_periodo <> pg_catalog.date_trunc('month', v_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if v_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = v_periodo;

  with filas as materialized (
    select f.* from private.conversion_divisor_empresa(v_periodo) f
  ),
  fuera_foto as materialized (
    -- Mes sellado: la producción congelada fuera del ranking y la que no tuvo
    -- analista se suman al total de la empresa, igual que en la puerta mensual.
    select e.value as fila
    from pg_catalog.jsonb_array_elements(
      coalesce(v_cierre.cobertura -> 'fuera_ranking', '[]'::jsonb)
    ) e
    where v_cierre.periodo is not null
      and e.value -> 'conversion' <> 'null'::jsonb
    union all
    select pg_catalog.jsonb_build_object('conversion', v_cierre.cobertura -> 'conversion_sin_analista')
    where v_cierre.periodo is not null
      and v_cierre.cobertura ? 'conversion_sin_analista'
  ),
  empresa as (
    select
      (coalesce(sum(f.divisor), 0)
        + coalesce((select sum((x.fila #>> '{conversion,divisor}')::integer) from fuera_foto x), 0))::integer as divisor,
      (coalesce(sum(f.numerador), 0::numeric)
        + coalesce((select sum((x.fila #>> '{conversion,numerador}')::numeric) from fuera_foto x), 0::numeric)) as numerador,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_formulario), 0)::integer end as divisor_formulario,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_landing), 0)::integer end as divisor_landing
    from filas f
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'alcance', 'global',
    'periodo', pg_catalog.jsonb_build_object(
      'mes', pg_catalog.to_char(v_periodo, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(v_periodo),
      'anio', extract(year from v_periodo)::integer,
      'zona', 'America/Lima',
      'desde', v_periodo,
      'hasta', (v_periodo + interval '1 month')::date
    ),
    'sellado', v_cierre.periodo is not null,
    'peso_referido', coalesce(v_cierre.ponderacion_referido, private.peso_referido_conversion(v_periodo)),
    'fuente', pg_catalog.jsonb_build_object(
      'divisor', 'private.conversion_neta_por_vendedor',
      'origen', 'private.conversion_episodios',
      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado'
    ),
    'empresa', (
      select pg_catalog.jsonb_build_object(
        'divisor', e.divisor,
        'numerador', e.numerador,
        'conversion_pct', case when e.divisor > 0
          then pg_catalog.round(100.0 * e.numerador / e.divisor, 2) end,
        'divisor_formulario', e.divisor_formulario,
        'divisor_landing', e.divisor_landing
      )
      from empresa e
    ),
    'sin_analista', case
      when v_cierre.periodo is null then (
        select pg_catalog.jsonb_build_object('divisor', f.divisor, 'numerador', f.numerador)
        from filas f
        where f.analista_id is null
      )
      when v_cierre.cobertura ? 'conversion_sin_analista' then pg_catalog.jsonb_build_object(
        'divisor', (v_cierre.cobertura #>> '{conversion_sin_analista,divisor}')::integer,
        'numerador', (v_cierre.cobertura #>> '{conversion_sin_analista,numerador}')::numeric
      )
    end,
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
          'conversion_pct', f.conversion_pct
        )
        order by f.nombre nulls last, f.analista_id
      )
      from filas f
      where f.analista_id is not null
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.conversion_divisor_coordinacion_fn(date) is
  'Puerta (30/09/2026): conversión por analista de TODA la empresa para Coordinación. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en private.conversion_divisor_empresa: el divisor es el del núcleo (una llegada por lead, en el primer analista asignado), no el reporte de entregas. Mes sellado: sirve la foto. Sin PII de leads.';

revoke all on function crm.conversion_divisor_coordinacion_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_divisor_coordinacion_fn(date)
  to authenticated;

do $postflight$
declare
  v_nucleo regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date)');
  v_puerta regprocedure := pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)');
  v_cuerpo text;
  v_mes date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_filas_nucleo integer;
  v_filas_neto integer;
  v_divisor_nucleo bigint;
  v_divisor_neto bigint;
  v_divisor_origen bigint;
begin
  if v_nucleo is null or v_puerta is null then
    raise exception 'POSTFLIGHT: faltan las dos funciones de la conversión de Coordinación';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
       where p.oid in (v_nucleo, v_puerta)
         and p.prosecdef
         and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']) <> 2 then
    raise exception 'POSTFLIGHT: las dos funciones deben ser STABLE, SECURITY DEFINER y usar search_path vacío';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('anon', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_puerta, 'execute')
     or pg_catalog.has_function_privilege('authenticated', v_nucleo, 'execute')
     or pg_catalog.has_function_privilege('anon', v_nucleo, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_nucleo, 'execute') then
    raise exception 'POSTFLIGHT: ACL inesperada (la puerta solo para authenticated; el núcleo sin ejecutores de la API)';
  end if;

  -- EL CANDADO DE DISPERSIÓN: ninguna de las dos vuelve a contar leads ni el
  -- ledger. Si alguien recalcula el divisor fuera del núcleo, este postflight (y
  -- el oráculo que lo repite) lo rechazan. Se miran los cuerpos sin comentarios.
  for v_cuerpo in
    select pg_catalog.regexp_replace(pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g')
    from pg_catalog.pg_proc p where p.oid in (v_nucleo, v_puerta)
  loop
    if v_cuerpo ~ '\mcrm\.\s*leads\M' or v_cuerpo ~ '\mlead_asignaciones\M' then
      raise exception 'POSTFLIGHT: la conversión de Coordinación no puede leer leads ni el ledger: el divisor solo sale del núcleo';
    end if;
  end loop;
  select pg_catalog.lower(p.prosrc) into v_cuerpo from pg_catalog.pg_proc p where p.oid = v_nucleo;
  if v_cuerpo !~ 'private\.conversion_neta_por_vendedor\(' or v_cuerpo !~ 'private\.conversion_episodios\(' then
    raise exception 'POSTFLIGHT: el núcleo de Coordinación debe leer conversion_neta_por_vendedor y conversion_episodios';
  end if;

  -- PARIDAD con el núcleo en el mes vigente (abierto por definición: aún no se
  -- puede sellar): mismas filas y mismo divisor que la pieza que usa Metas, y el
  -- desglose por origen suma EXACTAMENTE el divisor (referido y alta manual pesan 0).
  select count(*), coalesce(sum(f.divisor), 0), coalesce(sum(f.divisor_formulario + f.divisor_landing), 0)
    into v_filas_nucleo, v_divisor_nucleo, v_divisor_origen
  from private.conversion_divisor_empresa(v_mes) f;
  select count(*), coalesce(sum(n.divisor), 0)
    into v_filas_neto, v_divisor_neto
  from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n;
  if v_filas_nucleo <> v_filas_neto or v_divisor_nucleo <> v_divisor_neto then
    raise exception 'POSTFLIGHT: la composición no reproduce el núcleo (filas %/% divisor %/%)',
      v_filas_nucleo, v_filas_neto, v_divisor_nucleo, v_divisor_neto;
  end if;
  if v_divisor_origen <> v_divisor_nucleo then
    raise exception 'POSTFLIGHT: formulario + landing (%) no suman el divisor (%)',
      v_divisor_origen, v_divisor_nucleo;
  end if;
  if exists (
    select 1
    from private.conversion_divisor_empresa(v_mes) f
    join private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n
      on n.analista_id is not distinct from f.analista_id
    where f.divisor <> n.divisor
       or f.numerador is distinct from n.numerador
       or f.conversion_pct is distinct from n.conversion_pct
  ) then
    raise exception 'POSTFLIGHT: alguna fila difiere del núcleo en divisor, numerador o porcentaje';
  end if;
end;
$postflight$;

commit;
```

### supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
```sql
-- Oráculo transaccional de la conversión por analista para Coordinación
-- (`crm.conversion_divisor_coordinacion_fn` → `private.conversion_divisor_empresa`).
--
-- Qué prueba, con un mundo SINTÉTICO que se siembra aquí mismo y se deshace al final:
--   E01 estructura: propiedades, ACL y el candado de dispersión (ninguna de las
--       dos funciones lee leads ni el ledger: el divisor solo sale del núcleo).
--   E02 autorización: coordinador y gerencia entran; vendedor, supervisor,
--       directorio, coordinador inactivo y anónimo reciben 42501 (antes que 22023).
--   E03 período: mes futuro y día que no es el primero → 22023.
--   E04 regla del divisor recorriendo las PUERTAS REALES del reparto (turno →
--       repartir → derivar → devolver a bandeja → derivar): el lead reasignado
--       cuenta UNA vez en quien lo recibió primero (A→B y A→B→A), no cambia el
--       divisor de B, la alta manual no entra, el referido pesa 0, el lead sin
--       asignar cuenta en la empresa, y el alta a las 23:30 del último día del
--       mes anterior (hora Lima) queda en ESE mes aunque se reparta hoy.
--   E05 paridad pantalla = núcleo: cada fila de la puerta es igual a
--       `private.conversion_neta_por_vendedor`, formulario + landing = divisor,
--       y la empresa suma analistas + sin analista. Gerencia recibe lo mismo.
--   E06 contraste con el reporte de entregas: allí el lead devuelto y
--       re-entregado cuenta en B; en la puerta B sigue en 0.
--   E07 mes sellado: se sirve la foto (`crm.cierre_mes_vendedor`), el desglose
--       por origen va en null y el núcleo vivo rechaza recalcularlo.
--   E08 huellas: los conteos operativos y el núcleo conservan su cuerpo del
--       30/09/2026 (este cambio no los toca).
--
-- Requiere un banco con el esquema de producción, `crm.conversion_pesos`,
-- las políticas SLA y la migración 20260930185623 aplicada. No deja datos.
-- Correr con psql -f (un mensaje por sentencia): `statement_timestamp()` avanza
-- entre llamadas y el oráculo lo tolera.

\set ON_ERROR_STOP on

begin;
set local statement_timeout = '120s';
set local lock_timeout = '5s';
set local timezone = 'America/Lima';

-- ─────────────────────────────────────────────────────────────────────────────
-- E01 · Estructura
-- ─────────────────────────────────────────────────────────────────────────────
do $estructura$
declare
  v_nucleo regprocedure := to_regprocedure('private.conversion_divisor_empresa(date)');
  v_puerta regprocedure := to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)');
  v_cuerpo text;
begin
  if v_nucleo is null or v_puerta is null then
    raise exception 'E01a faltan las funciones de la conversión de Coordinación';
  end if;
  if (select count(*) from pg_proc p where p.oid in (v_nucleo, v_puerta)
        and p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""']) <> 2 then
    raise exception 'E01b deben ser STABLE, SECURITY DEFINER y search_path vacío';
  end if;
  if not has_function_privilege('authenticated', v_puerta, 'execute')
     or has_function_privilege('anon', v_puerta, 'execute')
     or has_function_privilege('service_role', v_puerta, 'execute')
     or has_function_privilege('authenticated', v_nucleo, 'execute')
     or has_function_privilege('anon', v_nucleo, 'execute')
     or has_function_privilege('service_role', v_nucleo, 'execute') then
    raise exception 'E01c ACL inesperada';
  end if;
  for v_cuerpo in
    select regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g')
    from pg_proc p where p.oid in (v_nucleo, v_puerta)
  loop
    if v_cuerpo ~ '\mcrm\.\s*leads\M' or v_cuerpo ~ '\mlead_asignaciones\M' then
      raise exception 'E01d DISPERSIÓN: la conversión de Coordinación vuelve a contar leads o el ledger';
    end if;
  end loop;
  select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_nucleo;
  if v_cuerpo !~ 'private\.conversion_neta_por_vendedor\(' or v_cuerpo !~ 'private\.conversion_episodios\(' then
    raise exception 'E01e el núcleo de Coordinación debe leer conversion_neta_por_vendedor y conversion_episodios';
  end if;
  select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_puerta;
  if v_cuerpo !~ 'private\.puede_operar_reparto_crm\(\)' then
    raise exception 'E01f la puerta debe autorizar con private.puede_operar_reparto_crm()';
  end if;
end;
$estructura$;

-- ─────────────────────────────────────────────────────────────────────────────
-- E08 · Huellas del 30/09/2026 (lo que este cambio NO toca)
-- ─────────────────────────────────────────────────────────────────────────────
do $huellas$
declare
  v_esperadas jsonb := '{
    "private.conversion_neta_por_vendedor(date,boolean,uuid[])": "67d7b57536bad97083630a023caec865",
    "private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)": "9c606dd40fb9e4b0ea816731b04b1cb1",
    "private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)": "6e62d66e1c9536a50657245d6e633f56",
    "private.puede_operar_reparto_crm()": "38c03bf93b5d05873d387823c0dd760a",
    "crm.reporte_derivaciones_coordinacion_fn(date,date)": "033f8aeaba9668e66fe094b84cab4eb7",
    "crm.conversion_mensual_sin_cartera_fn(date)": "f613d94208b035f241c4e13b351c55be"
  }'::jsonb;
  v_firma text;
  v_md5 text;
begin
  for v_firma, v_md5 in select key, value #>> '{}' from jsonb_each(v_esperadas) loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(v_firma)) is distinct from v_md5 then
      raise exception 'E08 % cambió de cuerpo respecto al 30/09/2026 (o no existe): revisar antes de fiarse de este oráculo', v_firma;
    end if;
  end loop;
end;
$huellas$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Siembra sintética (rollback al final). UUIDs reconocibles c0000000-…
-- ─────────────────────────────────────────────────────────────────────────────
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, confirmation_token,
  recovery_token, email_change_token, email_change, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
select x.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       x.correo, '', '', '', '', '', '{"provider":"email"}'::jsonb, '{}'::jsonb, now(), now()
from (values
  ('c0000000-0000-4000-8000-000000000001'::uuid, 'oraculo.coord@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000002'::uuid, 'oraculo.gerencia@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000003'::uuid, 'oraculo.sup1@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000004'::uuid, 'oraculo.sup2@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000005'::uuid, 'oraculo.ana@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000006'::uuid, 'oraculo.bea@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000007'::uuid, 'oraculo.carla@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000008'::uuid, 'oraculo.directorio@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000009'::uuid, 'oraculo.coord.inactiva@avancecorp.test')
) as x(id, correo);

insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd)
values
  ('c0000000-0000-4000-8000-000000000001', 'ORACULO COORDINADORA', 'comercial', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000002', 'ORACULO GERENCIA', 'admin', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000003', 'ORACULO SUPERVISORA UNO', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000004', 'ORACULO SUPERVISOR DOS', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000005', 'ORACULO ANA', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000006', 'ORACULO BEA', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000007', 'ORACULO CARLA', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000008', 'ORACULO DIRECTORIO', 'directorio', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000009', 'ORACULO COORDINADORA INACTIVA', 'comercial', true, 'DNI', false, false, false);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('c0000000-0000-4000-8000-000000000001', 'coordinador', null, true),
  ('c0000000-0000-4000-8000-000000000002', 'gerencia', null, true),
  ('c0000000-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('c0000000-0000-4000-8000-000000000004', 'supervisor', null, true),
  ('c0000000-0000-4000-8000-000000000008', 'directorio', null, true),
  ('c0000000-0000-4000-8000-000000000009', 'coordinador', null, false);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('c0000000-0000-4000-8000-000000000005', 'vendedor', 'c0000000-0000-4000-8000-000000000003', true),
  ('c0000000-0000-4000-8000-000000000006', 'vendedor', 'c0000000-0000-4000-8000-000000000003', true),
  ('c0000000-0000-4000-8000-000000000007', 'vendedor', 'c0000000-0000-4000-8000-000000000004', true);

-- Destinos del turno diario: la agenda solo admite supervisoras declaradas.
insert into private.agenda_reparto_destinos (supervisor_id, alias, orden) values
  ('c0000000-0000-4000-8000-000000000003', 'Oraculo uno', 8),
  ('c0000000-0000-4000-8000-000000000004', 'Oraculo dos', 9);

-- Leads en la COLA GLOBAL (sin dueño ni bandeja), como los deja la landing/hoja.
-- L6 nace a las 23:30 del último día del mes anterior (hora Lima).
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, creado_en, alta_manual)
values
  ('c1000000-0000-4000-8000-000000000001', 'ORACULO LEAD UNO FORMULARIO', '+51900000001', 'formulario', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000002', 'ORACULO LEAD DOS FORMULARIO', '+51900000002', 'formulario', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000003', 'ORACULO LEAD TRES LANDING', '+51900000003', 'landing', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000004', 'ORACULO LEAD CUATRO MANUAL', '+51900000004', 'formulario', 10000, 'PEN', now(), true),
  ('c1000000-0000-4000-8000-000000000005', 'ORACULO LEAD CINCO REFERIDO', '+51900000005', 'referido', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000007', 'ORACULO LEAD SIETE SIN ASIGNAR', '+51900000007', 'formulario', 10000, 'PEN', now(), false);

-- L6 nace a las 23:30 del último día del mes anterior (hora Lima). El servidor
-- sella `creado_en` con su propio reloj en el guard de tenencia (candado
-- correcto: nadie fecha un lead a mano), así que un alta del pasado solo puede
-- sembrarse fuera de banda: se apaga ese guard para UNA sentencia dentro de
-- esta transacción (mismo patrón que la baja histórica del seed del gate) y se
-- vuelve a encender antes de seguir. Solo en un banco; nunca en producción.
alter table crm.leads disable trigger trg_leads_00_guard_tenencia;
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, creado_en, alta_manual)
values ('c1000000-0000-4000-8000-000000000006', 'ORACULO LEAD SEIS BORDE', '+51900000006', 'formulario', 10000, 'PEN',
  (date_trunc('month', now() at time zone 'America/Lima') - interval '30 minutes') at time zone 'America/Lima', false);
alter table crm.leads enable trigger trg_leads_00_guard_tenencia;

do $siembra_ok$
begin
  if (select count(*) from crm.leads where id::text like 'c1000000-%' and vendedor_id is null and asignado_supervisor_id is null) <> 7 then
    raise exception 'S01 los 7 leads sintéticos no quedaron en la cola global';
  end if;
  if (select (creado_en at time zone 'America/Lima')::date from crm.leads where id = 'c1000000-0000-4000-8000-000000000006')
     <> (date_trunc('month', now() at time zone 'America/Lima') - interval '1 day')::date then
    raise exception 'S02 el alta del lead de borde no quedó en el último día del mes anterior (Lima)';
  end if;
  if private.rol_crm('c0000000-0000-4000-8000-000000000001') is distinct from 'coordinador'
     or private.rol_crm('c0000000-0000-4000-8000-000000000002') is distinct from 'gerencia'
     or private.rol_crm('c0000000-0000-4000-8000-000000000005') is distinct from 'vendedor'
     or private.rol_crm('c0000000-0000-4000-8000-000000000008') is distinct from 'directorio'
     or private.rol_crm('c0000000-0000-4000-8000-000000000009') is not null then
    raise exception 'S03 los roles sintéticos no resuelven como se esperaba';
  end if;
end;
$siembra_ok$;

-- Mes SELLADO sintético: dos meses atrás, con foto por persona y cobertura.
insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
values (
  (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date,
  now(), null, true, 0.5, 1,
  '{"medible": true, "modelo_conversion": "llegadas_v2", "fuera_ranking": [], "conversion_sin_analista": {"divisor": 3, "numerador": 0}}'::jsonb
);
insert into crm.cierre_mes_vendedor (
  periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor, divisor_aproximado,
  divisor_por_motivo, cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, conversion_pct,
  estado, referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia, ajuste_numerador, ajuste_pen, ajuste_usd,
  conversion_objetivo
) values (
  (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date,
  'c0000000-0000-4000-8000-000000000005', 'ORACULO ANA', 'c0000000-0000-4000-8000-000000000003', 'ORACULO SUPERVISORA UNO',
  40, 0, '{"llegada": 40}'::jsonb, 4, 0, 0, 4, 10.00, 'sellado', 0, 0, null, '[]'::jsonb, 0, 0, 0,
  8.00
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Recorrido por las puertas REALES del reparto, como usuario autenticado.
-- ─────────────────────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $recorrido$
declare
  v_coord uuid := 'c0000000-0000-4000-8000-000000000001';
  v_sup1 uuid := 'c0000000-0000-4000-8000-000000000003';
  v_sup2 uuid := 'c0000000-0000-4000-8000-000000000004';
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_bea uuid := 'c0000000-0000-4000-8000-000000000006';
  v_carla uuid := 'c0000000-0000-4000-8000-000000000007';
  v_l1 uuid := 'c1000000-0000-4000-8000-000000000001';
  v_l2 uuid := 'c1000000-0000-4000-8000-000000000002';
  v_l3 uuid := 'c1000000-0000-4000-8000-000000000003';
  v_l4 uuid := 'c1000000-0000-4000-8000-000000000004';
  v_l5 uuid := 'c1000000-0000-4000-8000-000000000005';
  v_l6 uuid := 'c1000000-0000-4000-8000-000000000006';
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  -- Turno de hoy: landing → SUP2, formulario → SUP1 (obligatorio desde el 10/09).
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  perform crm.guardar_agenda_reparto_diaria(v_hoy, v_sup2, v_sup1);

  -- Coordinación reparte a las bandejas (L7 se queda en la cola a propósito).
  perform crm.repartir_lead(v_l1, v_sup1);
  perform crm.repartir_lead(v_l2, v_sup1);
  perform crm.repartir_lead(v_l3, v_sup2);
  perform crm.repartir_lead(v_l4, v_sup1);
  perform crm.repartir_lead(v_l5, v_sup1);
  perform crm.repartir_lead(v_l6, v_sup1);

  -- SUP1 entrega; devuelve a la bandeja antes de gestionar; vuelve a entregar.
  perform set_config('request.jwt.claim.sub', v_sup1::text, true);
  perform crm.derivar_leads_equipo_fn(array[v_l1, v_l2, v_l4, v_l5, v_l6], array[v_ana, v_ana, v_ana, v_ana, v_ana]);
  perform crm.revertir_derivacion_equipo_fn(v_l1);
  perform crm.derivar_leads_equipo_fn(array[v_l1], array[v_bea]);          -- L1: ANA → BEA
  perform crm.revertir_derivacion_equipo_fn(v_l2);
  perform crm.derivar_leads_equipo_fn(array[v_l2], array[v_bea]);
  perform crm.revertir_derivacion_equipo_fn(v_l2);
  perform crm.derivar_leads_equipo_fn(array[v_l2], array[v_ana]);          -- L2: ANA → BEA → ANA

  -- SUP2 entrega la landing sin vueltas.
  perform set_config('request.jwt.claim.sub', v_sup2::text, true);
  perform crm.derivar_leads_equipo_fn(array[v_l3], array[v_carla]);
end;
$recorrido$;

-- Las comprobaciones de tenencia y ledger se hacen con la consola (sin RLS):
-- a la coordinadora la RLS no le enseña esos leads, y eso es correcto.
reset role;
do $recorrido_ok$
declare
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_bea uuid := 'c0000000-0000-4000-8000-000000000006';
  v_carla uuid := 'c0000000-0000-4000-8000-000000000007';
  v_l1 uuid := 'c1000000-0000-4000-8000-000000000001';
  v_l2 uuid := 'c1000000-0000-4000-8000-000000000002';
  v_l3 uuid := 'c1000000-0000-4000-8000-000000000003';
begin
  if (select vendedor_id from crm.leads where id = v_l1) is distinct from v_bea
     or (select vendedor_id from crm.leads where id = v_l2) is distinct from v_ana
     or (select vendedor_id from crm.leads where id = v_l3) is distinct from v_carla then
    raise exception 'R01 la tenencia final no es la esperada (L1→BEA, L2→ANA, L3→CARLA)';
  end if;
  if (select count(*) from crm.lead_asignaciones where lead_id = v_l1) <> 2
     or (select count(*) from crm.lead_asignaciones where lead_id = v_l2) <> 3 then
    raise exception 'R02 el ledger no registró los episodios esperados (L1: 2, L2: 3)';
  end if;
  if not exists (
    select 1 from crm.lead_asignaciones a
    where a.lead_id = v_l1 and a.analista_id = v_ana and a.motivo_cierre = 'parqueado'
      and a.supervisor_destino_id = a.supervisor_origen_id
  ) then
    raise exception 'R03 la devolución a la misma bandeja no quedó como «parqueado» del mismo supervisor';
  end if;
end;
$recorrido_ok$;
set local role authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- E02/E03 · Autorización y período
-- ─────────────────────────────────────────────────────────────────────────────
do $autorizacion$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_quien uuid;
  v_etiqueta text;
begin
  for v_quien, v_etiqueta in
    select * from (values
      ('c0000000-0000-4000-8000-000000000005'::uuid, 'vendedor'),
      ('c0000000-0000-4000-8000-000000000003'::uuid, 'supervisor'),
      ('c0000000-0000-4000-8000-000000000008'::uuid, 'directorio'),
      ('c0000000-0000-4000-8000-000000000009'::uuid, 'coordinador inactivo')
    ) as t(id, etiqueta)
  loop
    perform set_config('request.jwt.claim.sub', v_quien::text, true);
    begin
      perform crm.conversion_divisor_coordinacion_fn(v_mes);
      raise exception 'E02 % entró a la conversión de Coordinación', v_etiqueta;
    exception when insufficient_privilege then null;
    end;
    -- Gate ANTES que validación: un mes futuro también da 42501 para el denegado.
    begin
      perform crm.conversion_divisor_coordinacion_fn((v_mes + interval '1 month')::date);
      raise exception 'E02b % con mes futuro no recibió 42501', v_etiqueta;
    exception when insufficient_privilege then null;
    end;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform crm.conversion_divisor_coordinacion_fn(v_mes);
    raise exception 'E02c sin identidad entró a la conversión de Coordinación';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000001', true);
  begin
    perform crm.conversion_divisor_coordinacion_fn((v_mes + interval '1 month')::date);
    raise exception 'E03a el coordinador pudo pedir un mes futuro';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.conversion_divisor_coordinacion_fn(v_mes + 14);
    raise exception 'E03b se aceptó un día que no es el primero del mes';
  exception when sqlstate '22023' then null;
  end;
end;
$autorizacion$;

-- ─────────────────────────────────────────────────────────────────────────────
-- E04/E05/E06 · Regla del divisor, paridad con el núcleo y contraste con entregas
-- ─────────────────────────────────────────────────────────────────────────────
do $divisor$
declare
  v_coord uuid := 'c0000000-0000-4000-8000-000000000001';
  v_ger uuid := 'c0000000-0000-4000-8000-000000000002';
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_bea uuid := 'c0000000-0000-4000-8000-000000000006';
  v_carla uuid := 'c0000000-0000-4000-8000-000000000007';
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mes_previo date := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_pay jsonb;
  v_pay_ger jsonb;
  v_prev jsonb;
  v_reporte jsonb;
  v_fila jsonb;
  v_ana_f int; v_ana_l int; v_ana_d int;
  v_bea_d int; v_carla_d int; v_carla_l int;
  v_bea_entregas int;
begin
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_pay := crm.conversion_divisor_coordinacion_fn(v_mes);

  if (v_pay->>'version')::int <> 1 or v_pay->>'alcance' <> 'global' or (v_pay->>'sellado')::boolean
     or v_pay->'periodo'->>'desde' <> v_mes::text or v_pay->'periodo'->>'zona' <> 'America/Lima' then
    raise exception 'E04a cabecera del payload inesperada: %', v_pay - 'analistas';
  end if;
  if v_pay::text ~ '"(lead_id|telefono|correo|dni|monto_estimado|nota|nombre_completo)"' then
    raise exception 'E04b el payload expone datos de leads o PII de contacto';
  end if;

  select (a->>'divisor_formulario')::int, (a->>'divisor_landing')::int, (a->>'divisor')::int
    into v_ana_f, v_ana_l, v_ana_d
  from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text;
  select coalesce((a->>'divisor')::int, 0) into v_bea_d
  from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_bea::text;
  select (a->>'divisor')::int, (a->>'divisor_landing')::int into v_carla_d, v_carla_l
  from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_carla::text;

  -- ANA recibió primero L1 (→BEA) y L2 (→BEA→ANA): 2 formulario. L4 manual y L5 referido: 0. L6 es del mes anterior.
  if v_ana_f is distinct from 2 or v_ana_l is distinct from 0 or v_ana_d is distinct from 2 then
    raise exception 'E04c ANA esperaba formulario 2 / landing 0 / divisor 2 y tiene %/%/%', v_ana_f, v_ana_l, v_ana_d;
  end if;
  -- BEA recibió L1 y L2 por reasignación: NO cambia su divisor.
  if coalesce(v_bea_d, 0) <> 0 then
    raise exception 'E04d el lead reasignado sumó al divisor de BEA (%)', v_bea_d;
  end if;
  if v_carla_d is distinct from 1 or v_carla_l is distinct from 1 then
    raise exception 'E04e CARLA esperaba 1 landing y tiene divisor % / landing %', v_carla_d, v_carla_l;
  end if;
  -- L7 nunca se asignó: cuenta en la empresa, sin responsable.
  if (v_pay->'sin_analista'->>'divisor')::int is distinct from 1 then
    raise exception 'E04f el lead sin asignar no quedó en «sin analista» (%)', v_pay->'sin_analista';
  end if;
  if (v_pay->'empresa'->>'divisor')::int <> 4
     or (v_pay->'empresa'->>'divisor_formulario')::int <> 3
     or (v_pay->'empresa'->>'divisor_landing')::int <> 1 then
    raise exception 'E04g la empresa esperaba 4 = 3 formulario + 1 landing y tiene %', v_pay->'empresa';
  end if;
  -- Nombres y supervisor del mes salen del perfil y del roster/equipo.
  if not exists (
    select 1 from jsonb_array_elements(v_pay->'analistas') a
    where a->>'analista_id' = v_ana::text and a->>'nombre' = 'ORACULO ANA'
      and a->>'supervisor_id' = 'c0000000-0000-4000-8000-000000000003'
      and a->>'supervisor_nombre' = 'ORACULO SUPERVISORA UNO'
  ) then
    raise exception 'E04h la fila de ANA no trae su nombre y supervisor';
  end if;

  -- Borde de mes: L6 (alta 23:30 del último día del mes anterior, repartido HOY) pesa en el mes anterior, en ANA.
  v_prev := crm.conversion_divisor_coordinacion_fn(v_mes_previo);
  if (select (a->>'divisor_formulario')::int from jsonb_array_elements(v_prev->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 1 then
    raise exception 'E04i el alta de las 23:30 del último día (Lima) no quedó en el mes anterior para ANA: %', v_prev->'analistas';
  end if;

  -- E05a–c se comprueban con la consola (el núcleo privado no tiene ejecutores de la API).
  perform set_config('oraculo.pay', v_pay::text, true);

  -- Gerencia recibe exactamente lo mismo (misma foto, distinto reloj).
  perform set_config('request.jwt.claim.sub', v_ger::text, true);
  v_pay_ger := crm.conversion_divisor_coordinacion_fn(v_mes);
  if (v_pay_ger - 'generado_en') <> (v_pay - 'generado_en') then
    raise exception 'E05d Gerencia no recibió el mismo payload que Coordinación';
  end if;

  -- E06 · Contraste con el reporte de entregas: allí L1 cuenta en BEA (la devolución
  -- a la misma bandeja deja de sumar y la re-entrega sí suma).
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_reporte := crm.reporte_derivaciones_coordinacion_fn(v_hoy, v_hoy);
  select coalesce(sum((e->>'derivados')::int), 0) into v_bea_entregas
  from jsonb_array_elements(v_reporte->'dias') d
  cross join lateral jsonb_array_elements(d->'entregas') e
  where e->>'analista_id' = v_bea::text and e->>'origen' = 'formulario';
  if v_bea_entregas <> 1 then
    raise exception 'E06 el reporte de entregas debía contar L1 en BEA (1) y cuenta %', v_bea_entregas;
  end if;
end;
$divisor$;


-- E05 · Paridad fila a fila con el núcleo (la pieza que usa Metas), con la consola.
reset role;
do $paridad$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_pay jsonb := current_setting('oraculo.pay')::jsonb;
begin
  if exists (
    select 1
    from jsonb_array_elements(v_pay->'analistas') a
    full join (
      select * from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) x
      where x.analista_id is not null
    ) n on n.analista_id = (a->>'analista_id')::uuid
    where a is null
       or n.analista_id is null
       or (a->>'divisor')::int is distinct from n.divisor
       or (a->>'numerador')::numeric is distinct from n.numerador
       or (a->>'conversion_pct')::numeric is distinct from n.conversion_pct
       or (a->>'divisor_formulario')::int + (a->>'divisor_landing')::int <> (a->>'divisor')::int
  ) then
    raise exception 'E05a la pantalla no reproduce el núcleo fila a fila';
  end if;
  -- La fila SIN analista del núcleo (id nulo) es exactamente `sin_analista`.
  if (v_pay->'sin_analista'->>'divisor')::int is distinct from
     (select n.divisor from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n where n.analista_id is null) then
    raise exception 'E05e «sin analista» no es la fila sin analista del núcleo';
  end if;
  if (select coalesce(sum((a->>'divisor')::int), 0) from jsonb_array_elements(v_pay->'analistas') a)
       + coalesce((v_pay->'sin_analista'->>'divisor')::int, 0)
     <> (v_pay->'empresa'->>'divisor')::int then
    raise exception 'E05b la empresa no suma analistas + sin analista';
  end if;
  if (v_pay->'empresa'->>'divisor')::int
     <> (select coalesce(sum(n.divisor), 0) from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n) then
    raise exception 'E05c el total de la empresa no es el del núcleo';
  end if;

end;
$paridad$;
set local role authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- E07 · Mes sellado: foto, sin desglose, sin recalcular
-- ─────────────────────────────────────────────────────────────────────────────
do $sellado$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_pay jsonb;
  v_fila jsonb;
begin
  perform set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000001', true);
  v_pay := crm.conversion_divisor_coordinacion_fn(v_mes);
  if not (v_pay->>'sellado')::boolean then
    raise exception 'E07a el mes sellado no se declaró sellado';
  end if;
  select a into v_fila from jsonb_array_elements(v_pay->'analistas') a
  where a->>'analista_id' = 'c0000000-0000-4000-8000-000000000005';
  if v_fila is null or (v_fila->>'divisor')::int <> 40 or (v_fila->>'numerador')::numeric <> 4
     or (v_fila->>'conversion_pct')::numeric <> 10.00
     or v_fila->'divisor_formulario' <> 'null'::jsonb or v_fila->'divisor_landing' <> 'null'::jsonb then
    raise exception 'E07b la fila sellada no es la foto (40 / 4 / 10.00, sin desglose): %', v_fila;
  end if;
  if (v_pay->'empresa'->>'divisor')::int <> 43 or (v_pay->'sin_analista'->>'divisor')::int <> 3
     or v_pay->'empresa'->'divisor_formulario' <> 'null'::jsonb
     or (v_pay->>'peso_referido')::numeric <> 0.5 then
    raise exception 'E07c la empresa sellada no suma la foto + lo sin analista con su peso: %', v_pay->'empresa';
  end if;
end;
$sellado$;

-- El núcleo vivo se niega a recalcular un mes sellado: la puerta sirve la foto y no lo llama.
reset role;
do $sellado_nucleo$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
begin
  begin
    perform private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]);
    raise exception 'E07d el núcleo recalculó un mes sellado';
  exception when sqlstate '22023' then null;
  end;
end;
$sellado_nucleo$;

select 'ORACULO-DIVISOR-COORDINACION-OK' as resultado;

rollback;
```

### Diff del front (app/src y app/e2e, sin database.types.ts)
```diff
diff --git a/CRM-Avance-Corp/app/e2e/_helpers.ts b/CRM-Avance-Corp/app/e2e/_helpers.ts
index ca9a5d7e..880988a6 100644
--- a/CRM-Avance-Corp/app/e2e/_helpers.ts
+++ b/CRM-Avance-Corp/app/e2e/_helpers.ts
@@ -1776,6 +1776,8 @@ export interface BackendReal {
   supervisoresReparto: Record<string, unknown>[]
   /** Entregas históricas ya agregadas por día, responsable y origen. */
   entregasCoordinacion: EntregaCoordinacionReal[]
+  /** Payload literal de crm.conversion_divisor_coordinacion_fn (el período lo eco-a el handler). */
+  conversionCoordinacion: Record<string, unknown> | null
   /** Agenda de turnos y conteos que devuelve crm.agenda_reparto_diaria(). */
   agendaReparto: Record<string, unknown> | null
   /**
@@ -1944,6 +1946,7 @@ export async function montarBackendReal(
     descartados: init.descartados ?? [],
     supervisoresReparto: init.supervisoresReparto ?? [],
     entregasCoordinacion: init.entregasCoordinacion ?? [],
+    conversionCoordinacion: init.conversionCoordinacion ?? null,
     agendaReparto: init.agendaReparto ?? null,
     fallarProximoReparto: init.fallarProximoReparto ?? null,
     fallarProximoDescarte: init.fallarProximoDescarte ?? null,
@@ -2702,6 +2705,15 @@ export async function montarBackendReal(
         String(body.p_hasta ?? ''),
       ))
     }
+    if (p === '/rest/v1/rpc/conversion_divisor_coordinacion_fn' && method === 'POST') {
+      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
+      const periodo = String(body.p_periodo ?? '')
+      if (!estado.conversionCoordinacion) return json(route, { code: '42501', message: 'No autorizado' }, 403)
+      return json(route, {
+        ...estado.conversionCoordinacion,
+        periodo: { ...(estado.conversionCoordinacion.periodo as Record<string, unknown>), mes: periodo.slice(0, 7), desde: periodo },
+      })
+    }
     if (p === '/rest/v1/rpc/panel_distribucion_reparto') {
       return json(route, {
         version: 1,
diff --git a/CRM-Avance-Corp/app/e2e/repartir.spec.ts b/CRM-Avance-Corp/app/e2e/repartir.spec.ts
index 8254dd77..e03ab24e 100644
--- a/CRM-Avance-Corp/app/e2e/repartir.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/repartir.spec.ts
@@ -205,6 +205,58 @@ test('Supervisión → analistas permite auditar entregas por fecha, analista y
   await expect(origen).toHaveValue('')
 })
 
+test('Conversiones: la coordinadora ve el divisor del núcleo (primer analista), no el reporte de entregas', async ({ page }) => {
+  await aterrizarComoCoordinador(page, {
+    conversionCoordinacion: {
+      version: 1,
+      generado_en: '2026-09-30T18:00:00.000Z',
+      alcance: 'global',
+      periodo: { mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-10-01' },
+      sellado: false,
+      peso_referido: 0.5,
+      fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead' },
+      empresa: { divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79 },
+      sin_analista: { divisor: 2, numerador: 0 },
+      analistas: [
+        {
+          analista_id: '20000000-0000-4000-8000-000000000001', nombre: 'ANA TORRES',
+          supervisor_id: '10000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA NORTE',
+          en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7,
+        },
+        {
+          analista_id: '20000000-0000-4000-8000-000000000002', nombre: 'BRUNO LEÓN',
+          supervisor_id: '10000000-0000-4000-8000-000000000001', supervisor_nombre: 'SUPERVISORA NORTE',
+          en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23,
+        },
+      ],
+    },
+  })
+
+  await page.getByRole('tab', { name: 'Conversiones' }).click()
+  await expect(page.getByRole('heading', { name: 'Conversiones' })).toBeVisible()
+
+  const resumen = page.locator('[aria-label="Resumen de conversión del mes"]')
+  const cifra = (etiqueta: string) => resumen.locator(':scope > div').filter({ hasText: etiqueta })
+  await expect(cifra('Llegadas').getByText('205', { exact: true })).toBeVisible()
+  await expect(cifra('Formulario').getByText('126', { exact: true })).toBeVisible()
+  await expect(cifra('Conversión').getByText('9.83%', { exact: true })).toBeVisible()
+
+  const tabla = page.getByRole('table', { name: 'Conversión por analista' })
+  const ana = tabla.getByRole('row').filter({ hasText: 'ANA TORRES' })
+  await expect(ana).toContainText('65')
+  await expect(ana).toContainText('115')
+  await expect(ana).toContainText('9.70%')
+  await expect(tabla.getByRole('row').filter({ hasText: 'Sin analista asignado' })).toContainText('2')
+  await expect(page.getByText(/Este conteo es distinto del reporte de entregas/)).toBeVisible()
+
+  // El mes elegido viaja como primer día del mes.
+  const mes = page.getByLabel('Mes de conversión')
+  const pedido = page.waitForRequest((req) => req.url().includes('/rpc/conversion_divisor_coordinacion_fn')
+    && (req.postDataJSON() as { p_periodo?: string })?.p_periodo === '2026-08-01')
+  await mes.fill('2026-08')
+  await pedido
+})
+
 test('Coordinación muestra la entrega real antes de que Supervisión la reparta a analistas', async ({ page }) => {
   const hoy = fechaLimaConDesplazamiento(0)
   await aterrizarComoCoordinador(page, {
diff --git a/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts b/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
index 3b0584f1..421a7363 100644
--- a/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-api-reparto-msw.test.ts
@@ -14,6 +14,7 @@ vi.mock('@/lib/supabase', async () => {
 
 import {
   agendaRepartoDiaria,
+  conversionCoordinacion,
   CrmApiError,
   descartarLead,
   deshacerDescarte,
@@ -27,6 +28,7 @@ import {
   supervisoresParaReparto,
 } from './crm-api'
 import { resumenRepartoDesdeCola } from '@/lib/resumen-reparto'
+import { payloadValido as conversionValida } from '@/lib/conversion-coordinacion.test'
 
 const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
 
@@ -663,3 +665,48 @@ describe('listarResumenReparto (msw)', () => {
     expect(fallo).toMatchObject({ code: '42501' })
   })
 })
+
+describe('conversionCoordinacion (crm.conversion_divisor_coordinacion_fn)', () => {
+  it('manda el primer día del mes, acepta numéricos como texto y devuelve el payload parseado', async () => {
+    let cuerpo: unknown = null
+    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), async ({ request }) => {
+      cuerpo = await request.json()
+      const datos = conversionValida()
+      return HttpResponse.json({
+        ...datos,
+        empresa: { ...datos.empresa, numerador: '20.15', divisor: '205' },
+      })
+    }))
+
+    const datos = await conversionCoordinacion('2026-09-01')
+    expect(cuerpo).toEqual({ p_periodo: '2026-09-01' })
+    expect(datos.empresa.divisor).toBe(205)
+    expect(datos.empresa.numerador).toBe(20.15)
+    expect(datos.analistas[0]).toMatchObject({ divisor: 115, divisor_formulario: 65, divisor_landing: 50, conversion_pct: 9.7 })
+  })
+
+  it('rechaza un período que no es el primer día del mes sin tocar la red', async () => {
+    await expect(conversionCoordinacion('2026-09-15')).rejects.toMatchObject({ code: 'PERIODO_INVALIDO' })
+  })
+
+  it('fail-closed: un payload fuera de contrato no se devuelve a medias', async () => {
+    const { analistas: _fuera, ...roto } = conversionValida()
+    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(roto)))
+    await expect(conversionCoordinacion('2026-09-01')).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_CONTRACT' })
+  })
+
+  it('PARIDAD: si formulario + landing no suman el divisor (el 62 del reporte), el paquete se rechaza entero', async () => {
+    const datos = conversionValida()
+    datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: 62 }
+    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(datos)))
+    await expect(conversionCoordinacion('2026-09-01')).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_INCONSISTENTE' })
+  })
+
+  it('el gate de rol (42501) sube con su código y un mensaje entendible', async () => {
+    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () =>
+      HttpResponse.json({ code: '42501', message: 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista' }, { status: 403 })))
+    const fallo = await conversionCoordinacion('2026-09-01').catch((e: unknown) => e)
+    expect(fallo).toBeInstanceOf(CrmApiError)
+    expect(fallo).toMatchObject({ code: '42501', message: 'No tienes permiso para consultar la conversión por analista.' })
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/data/crm-api.ts b/CRM-Avance-Corp/app/src/data/crm-api.ts
index 31202773..e3e15eb3 100644
--- a/CRM-Avance-Corp/app/src/data/crm-api.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-api.ts
@@ -131,6 +131,11 @@ import {
   reporteDerivacionesCoordinacionConsistente,
   type ReporteDerivacionesCoordinacion,
 } from '@/lib/reporte-derivaciones-coordinacion'
+import {
+  ConversionCoordinacionSchema,
+  conversionCoordinacionConsistente,
+  type ConversionCoordinacion,
+} from '@/lib/conversion-coordinacion'
 import { ESTADOS_CONTRATO_PDF, type EstadoContratoPdf } from '@/lib/contrato-pdf-archivo'
 import { ResumenRepartoSchema, type ResumenReparto } from '@/lib/resumen-reparto'
 import { IngresosRepartoMesSchema, inicioDeMes, type IngresosRepartoMes } from '@/lib/ingresos-reparto'
@@ -5597,6 +5602,58 @@ export async function listarMetricasVendedores(
 
 // ── Reportes históricos de derivaciones ──────────────────────────────────────
 
+/**
+ * Conversión por analista de TODA la empresa para Coordinación
+ * (`crm.conversion_divisor_coordinacion_fn`). El divisor es el del núcleo —una
+ * llegada por lead, por su alta original, en el primer analista que la
+ * recibió— y NO el reporte de entregas, que a propósito deja de sumar la
+ * entrega devuelta a la bandeja. El navegador solo pinta lo que el servidor
+ * dice; si las sumas del payload no cierran, se rechaza el paquete entero.
+ */
+export async function conversionCoordinacion(
+  periodo: string,
+  signal?: AbortSignal,
+): Promise<ConversionCoordinacion> {
+  if (!v.safeParse(FechaSchema, periodo).success || !periodo.endsWith('-01')) {
+    throw new CrmApiError('El mes de conversión no es válido.', 'PERIODO_INVALIDO')
+  }
+  lanzarAbortSiCorresponde(signal)
+  let consulta = cliente().schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_periodo: periodo })
+  if (signal) consulta = consulta.abortSignal(signal)
+  const { data, error } = await consulta
+  lanzarAbortSiCorresponde(signal)
+  if (error) {
+    const fallo = new CrmApiError(
+      error.code === '22023'
+        ? 'El mes de conversión no es válido.'
+        : error.code === '42501' || error.code === 'PGRST301'
+          ? 'No tienes permiso para consultar la conversión por analista.'
+          : 'No se pudo cargar la conversión por analista.',
+      error.code || 'POSTGREST_ERROR',
+    )
+    registrarError('crm.reparto.conversion_coordinacion_fallida', fallo, { pg: error.code ?? '' })
+    throw fallo
+  }
+  const resultado = v.safeParse(ConversionCoordinacionSchema, data)
+  if (!resultado.success) {
+    const fallo = new CrmApiError(
+      'La conversión por analista no tiene el formato esperado.',
+      'CONVERSION_COORDINACION_CONTRACT',
+    )
+    registrarError('crm.reparto.conversion_coordinacion_fuera_de_contrato', fallo)
+    throw fallo
+  }
+  if (!conversionCoordinacionConsistente(resultado.output, periodo)) {
+    const fallo = new CrmApiError(
+      'La conversión por analista no reconcilia con el núcleo y no se mostrará.',
+      'CONVERSION_COORDINACION_INCONSISTENTE',
+    )
+    registrarError('crm.reparto.conversion_coordinacion_inconsistente', fallo)
+    throw fallo
+  }
+  return resultado.output
+}
+
 function falloReporteDerivaciones(
   error: { code?: string | null },
   evento: string,
diff --git a/CRM-Avance-Corp/app/src/screens/repartir.test.tsx b/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
index b3d03629..997de6e7 100644
--- a/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/repartir.test.tsx
@@ -8,6 +8,7 @@ import { act, fireEvent, render, screen, waitFor, within } from '@testing-librar
 import userEvent from '@testing-library/user-event'
 import type { AgendaRepartoDiaria, ColaLead, HistorialDerivacion, PanelDistribucionReparto, SupervisorReparto } from '@/lib/tipos'
 import type { ReporteDerivacionesCoordinacion } from '@/lib/reporte-derivaciones-coordinacion'
+import { payloadValido as payloadConversionValido } from '@/lib/conversion-coordinacion.test'
 
 const toastSuccess = vi.fn()
 const toastError = vi.fn()
@@ -83,6 +84,10 @@ let REPORTE_DIARIO: ReporteDerivacionesCoordinacion = {
   }],
 }
 const reporteDiarioMock = vi.fn(async (_desde: string, _hasta: string) => REPORTE_DIARIO)
+const conversionMock = vi.fn(async (periodo: string) => ({
+  ...payloadConversionValido(),
+  periodo: { ...payloadConversionValido().periodo, mes: periodo.slice(0, 7), desde: periodo },
+}))
 let AGENDA: AgendaRepartoDiaria = {
   version: 1,
   fecha_desde: fechaHoyLima,
@@ -111,6 +116,7 @@ vi.mock('@/data/crm-api', async (importActual) => {
     historialDerivaciones: () => historialMock(),
     panelDistribucionReparto: () => panelMock(),
     listarReporteDerivacionesCoordinacion: (desde: string, hasta: string) => reporteDiarioMock(desde, hasta),
+    conversionCoordinacion: (periodo: string) => conversionMock(periodo),
     agendaRepartoDiaria: () => agendaMock(),
     guardarAgendaRepartoDiaria: (fecha: string, landing: string, formulario: string) => guardarAgendaMock(fecha, landing, formulario),
   }
@@ -700,4 +706,22 @@ describe('pantalla Repartir leads', () => {
     expect(screen.getByText('Guarda primero el turno en Coordinación → supervisores.')).toBeInTheDocument()
     expect(repartirMock).not.toHaveBeenCalled()
   })
+
+  it('la pestaña Conversiones pide el divisor del núcleo al servidor y lo pinta tal cual', async () => {
+    const usuario = userEvent.setup()
+    render(<Repartir />)
+    expect(await screen.findByRole('heading', { name: 'Coordinación → supervisores' })).toBeInTheDocument()
+    expect(conversionMock).not.toHaveBeenCalled()
+
+    await usuario.click(screen.getByRole('tab', { name: 'Conversiones' }))
+    expect(await screen.findByRole('heading', { name: 'Conversiones' })).toBeInTheDocument()
+    expect(conversionMock).toHaveBeenCalledTimes(1)
+    expect(conversionMock.mock.calls[0]?.[0]).toMatch(/^\d{4}-\d{2}-01$/)
+
+    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
+    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
+    expect(within(astrid).getAllByRole('cell').map((celda) => celda.textContent))
+      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '11.15', '9.70%'])
+    expect(screen.getByText(/Este conteo es distinto del reporte de entregas/)).toBeInTheDocument()
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/screens/repartir.tsx b/CRM-Avance-Corp/app/src/screens/repartir.tsx
index 90691add..ea2a5e3a 100644
--- a/CRM-Avance-Corp/app/src/screens/repartir.tsx
+++ b/CRM-Avance-Corp/app/src/screens/repartir.tsx
@@ -61,6 +61,7 @@ import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estad
 import { HistorialDerivaciones } from '@/components/app/historial-derivaciones'
 import { PanelDistribucionReparto } from '@/components/app/panel-distribucion-reparto'
 import { AgendaRepartoDiaria } from '@/components/app/agenda-reparto-diaria'
+import { ConversionCoordinacion } from '@/components/app/conversion-coordinacion'
 import { Paginacion } from '@/components/common/paginacion'
 import { paginar } from '@/lib/paginacion'
 import { hoyLimaIso } from '@/lib/distribucion-lecturas'
@@ -909,7 +910,7 @@ function PanelDescartados({ onCambio }: { onCambio: () => void }) {
 }
 
 export function Repartir() {
-  const [tab, setTab] = useState<'coordinacion' | 'panel' | 'cola' | 'descartados' | 'historial'>('coordinacion')
+  const [tab, setTab] = useState<'coordinacion' | 'panel' | 'conversiones' | 'cola' | 'descartados' | 'historial'>('coordinacion')
   // Al deshacer desde Descartados el lead vuelve a la cola: forzamos un remonte
   // de la pestaña Cola (key) para que la relea al volver a ella.
   const [colaKey, setColaKey] = useState(0)
@@ -925,6 +926,7 @@ export function Repartir() {
           {([
             ['coordinacion', 'Coordinación → supervisores'],
             ['panel', 'Supervisión → analistas'],
+            ['conversiones', 'Conversiones'],
             ['cola', 'Cola de nuevos'],
             ['historial', 'Historial'],
             ['descartados', 'Descartados'],
@@ -945,7 +947,7 @@ export function Repartir() {
         </div>
       </div>
 
-      {tab === 'coordinacion' ? <AgendaRepartoDiaria /> : tab === 'panel' ? <PanelDistribucionReparto /> : tab === 'cola' ? <PanelCola key={colaKey} /> : tab === 'historial' ? <HistorialDerivaciones /> : (
+      {tab === 'coordinacion' ? <AgendaRepartoDiaria /> : tab === 'panel' ? <PanelDistribucionReparto /> : tab === 'conversiones' ? <ConversionCoordinacion /> : tab === 'cola' ? <PanelCola key={colaKey} /> : tab === 'historial' ? <HistorialDerivaciones /> : (
         <PanelDescartados
           onCambio={() => { setColaKey((n) => n + 1); refrescarResumenReparto() }}
         />
```

### Diff de la matriz RLS (supabase/scripts/test-rls.mjs)
```diff
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index bd11a9e8..d6edab13 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -9701,6 +9701,62 @@ async function testReparto(sessions, seed) {
   // F2.3b: la puerta v3 tiene grant a `authenticated`, asi que el gate del
   // despachador es LO UNICO que separa a un analista de las metricas de toda
   // la casa. Se prueba con los cuatro roles: dos fuera, dos dentro.
+  // 30/09/2026: conversión por analista para Coordinación. La puerta reutiliza
+  // el gate canónico del reparto (coordinador | gerencia); el resto, 42501. El
+  // divisor es el del NÚCLEO (mismas filas que conversion_neta_por_vendedor),
+  // no el reporte de entregas: formulario + landing = divisor en cada fila.
+  {
+    // Mes vigente en Lima: la puerta rechaza meses futuros y el gate de metas es 2099.
+    const P_MES = { p_periodo: `${new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit' }).format(new Date()).slice(0, 7)}-01` };
+    for (const [rol, cliente] of [
+      ['vendedor', sessions.vend1.client],
+      ['supervisor', sessions.sup1.client],
+      ['directorio (lector global, fuera del gate del reparto)', sessions.directorio.client],
+      ['vendInactive (membresia revocada)', sessions.vendInactive.client],
+    ]) {
+      await expectBlockedMutation(
+        `${rol} no lee la conversion por analista de Coordinacion`,
+        cliente.schema('crm').rpc('conversion_divisor_coordinacion_fn', P_MES),
+        ['42501'],
+      );
+    }
+    await expectBlockedMutation(
+      'coordinador: un mes futuro se rechaza con 22023',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', { p_periodo: '2999-01-01' }),
+      ['22023'],
+    );
+    const convCoord = await positive(
+      'coordinador obtiene la conversion por analista de toda la empresa',
+      coordinador.schema('crm').rpc('conversion_divisor_coordinacion_fn', P_MES),
+    );
+    const convGer = await positive(
+      'gerencia obtiene la misma conversion por analista',
+      gerencia.schema('crm').rpc('conversion_divisor_coordinacion_fn', P_MES),
+    );
+    if (convCoord) {
+      check(convCoord.data?.version === 1 && convCoord.data?.alcance === 'global',
+        'la conversion de Coordinacion declara version 1 y alcance global');
+      check(Array.isArray(convCoord.data?.analistas), 'analistas es SIEMPRE un array');
+      const claves = [...new Set((convCoord.data?.analistas ?? []).flatMap((f) => Object.keys(f)))].sort();
+      check(claves.length === 0 || JSON.stringify(claves) === JSON.stringify([
+        'analista_id', 'conversion_pct', 'divisor', 'divisor_formulario', 'divisor_landing',
+        'en_nucleo', 'nombre', 'numerador', 'supervisor_id', 'supervisor_nombre',
+      ]), 'cada analista trae SOLO las 10 claves del contrato', claves.join(','));
+      check((convCoord.data?.analistas ?? []).every((f) => f.divisor_formulario + f.divisor_landing === f.divisor),
+        'PARIDAD: formulario + landing = divisor en cada analista (mes abierto)');
+      const sumaAnalistas = (convCoord.data?.analistas ?? []).reduce((acc, f) => acc + f.divisor, 0)
+        + (convCoord.data?.sin_analista?.divisor ?? 0);
+      check(sumaAnalistas === convCoord.data?.empresa?.divisor,
+        'PARIDAD: la empresa suma analistas + sin analista');
+      check(!JSON.stringify(convCoord.data).match(/"(lead_id|telefono|correo|dni|monto_estimado|nota)"/),
+        'la conversion de Coordinacion no expone PII ni filas de leads');
+    }
+    if (convCoord && convGer) {
+      const sinReloj = (d) => JSON.stringify({ ...d, generado_en: null });
+      check(sinReloj(convCoord.data) === sinReloj(convGer.data),
+        'gerencia y coordinador reciben el MISMO payload (ambito de toda la empresa)');
+    }
+  }
   for (const [rol, cliente] of [
     ['vendedor', sessions.vend1.client],
     ['supervisor', sessions.sup1.client],
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
