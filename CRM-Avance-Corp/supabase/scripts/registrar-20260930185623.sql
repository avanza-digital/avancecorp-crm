-- Registrador fail-closed de 20260930185623_crm_conversion_divisor_coordinacion.
-- Ejecutar inmediatamente después de la migración por la misma vía
-- (`db query --linked --file`). Registra el cuerpo literal del archivo y
-- rechaza una versión previa que no coincida.

begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $registrar_conversion_divisor_coordinacion$
declare
  v_nucleo regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date)');
  v_totales regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date)');
  v_puerta regprocedure := pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)');
  v_cuerpo text := $migracion_20260930185623$-- ============================================================================
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
-- y comparte regla con el de Supervisión); Coordinación recibe la conversión real
-- del núcleo por una puerta nueva, con ámbito de TODA la empresa. El OK cubre, por
-- analista y de la empresa, el divisor, su desglose por origen, el numerador neto y
-- el porcentaje (pestaña «Conversiones» de Repartir, aprobada con ese nombre). La
-- puerta oficial `crm.conversion_mensual_sin_cartera_fn` sigue denegando al
-- coordinador: esta puerta es la única lectura de conversión que tiene.
--
-- Capas, sin saltos nuevos (la puerta no lee ninguna tabla):
--   * Núcleo `private.conversion_divisor_empresa(date)`: una fila por analista.
--     Compone la MISMA pieza que Metas y la puerta mensual
--     (`private.conversion_neta_por_vendedor`: divisor, numerador neto y porcentaje)
--     con el desglose del divisor por origen, que sale de los episodios `recibido`
--     de `private.conversion_episodios`. En un mes SELLADO sirve la foto de
--     `crm.cierre_mes_vendedor` y no recalcula nada.
--   * Núcleo `private.conversion_divisor_empresa_totales(date)`: el total de la
--     empresa y lo «sin analista». Mes abierto: suma de las filas del núcleo. Mes
--     sellado: foto por persona + `cobertura.fuera_ranking` + `conversion_sin_analista`
--     de `crm.periodos_cerrados`, la misma suma que hace la puerta mensual oficial.
--   * Puerta `crm.conversion_divisor_coordinacion_fn(date)`: autoriza con la puerta
--     canónica del reparto (`private.puede_operar_reparto_crm()`: coordinador o
--     gerencia activas), valida el período, delega en los dos núcleos y da forma
--     JSON. No define el divisor: lo lee.
--     Coste conocido: el núcleo por analista se evalúa dos veces por llamada (una
--     dentro de los totales y otra para las filas); a este volumen (~200 llegadas
--     al mes) es despreciable y la puerta se consulta una vez por cambio de mes.
--   Los dos núcleos son SECURITY DEFINER con `search_path` vacío, sin autorización
--   dentro y sin ejecutores de la API, por instrucción expresa del encargo del
--   30/09/2026 («funciones nuevas en private: SECURITY DEFINER, search_path vacío,
--   sin autorización dentro, ámbito inyectado por parámetro») y en paridad con
--   `conversion_episodios` y `conversion_mensual_por_vendedor`, que ya son DEFINER.
--
-- Contrato abierto/sellado: en un mes abierto `analistas` trae a toda persona con
-- llegadas o cierres (también supervisores o perfiles fuera del roster); al sellar,
-- la foto solo conserva filas rankeables y lo demás pasa a `cobertura.fuera_ranking`,
-- que aquí suma al total de la empresa pero no aparece como fila. Es la semántica
-- del sello, no de esta puerta.
--
-- Lo que NO toca: el núcleo de conversión y sus pesos, el reporte de entregas, los
-- conteos operativos por dueño actual y las puertas de conversión existentes.
--
-- Reversa exacta:
--   drop function if exists crm.conversion_divisor_coordinacion_fn(date);
--   drop function if exists private.conversion_divisor_empresa_totales(date);
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
     or pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date)') is not null
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
    -- Una fila por analista aunque el roster trajera repetidos: el join no
    -- puede multiplicar la cifra del núcleo.
    select distinct on (r.vendedor_id) r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(p_periodo, true, null::uuid[]) r
    order by r.vendedor_id, r.supervisor_id nulls last
  )
  select n.analista_id,
         perfil.nombre_completo,
         case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end,
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
  left join public.perfiles jefe
    on jefe.id = case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end
  order by perfil.nombre_completo nulls last;
end;
$function$;

comment on function private.conversion_divisor_empresa(date) is
  'Núcleo (30/09/2026): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación. Lee private.conversion_neta_por_vendedor (la misma pieza que Metas) y abre el divisor por origen desde los episodios recibidos de private.conversion_episodios; en un mes sellado sirve la foto de crm.cierre_mes_vendedor sin recalcular. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API.';

revoke all on function private.conversion_divisor_empresa(date)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Núcleo: el total de la empresa y la producción sin analista, abierto o sellado.
-- ----------------------------------------------------------------------------
create function private.conversion_divisor_empresa_totales(p_periodo date)
returns table (
  sellado boolean,
  peso_referido numeric,
  divisor integer,
  numerador numeric,
  conversion_pct numeric,
  divisor_formulario integer,
  divisor_landing integer,
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
begin
  if p_periodo is null or p_periodo <> pg_catalog.date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;

  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;

  return query
  with filas as materialized (
    select f.* from private.conversion_divisor_empresa(p_periodo) f
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
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_landing), 0)::integer end as divisor_landing
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
    coalesce(v_cierre.ponderacion_referido, private.peso_referido_conversion(p_periodo)),
    s.divisor,
    s.numerador,
    case when s.divisor > 0 then pg_catalog.round(100.0 * s.numerador / s.divisor, 2) end,
    s.divisor_formulario,
    s.divisor_landing,
    coalesce((select sa.presente from sin_analista sa limit 1), false),
    (select sa.divisor from sin_analista sa limit 1),
    (select sa.numerador from sin_analista sa limit 1)
  from suma s;
end;
$function$;

comment on function private.conversion_divisor_empresa_totales(date) is
  'Núcleo (30/09/2026): total de la empresa y producción sin analista para la puerta de Coordinación. Mes abierto: suma de private.conversion_divisor_empresa. Mes sellado: foto por persona + cobertura.fuera_ranking + conversion_sin_analista de crm.periodos_cerrados (solo objetos; un JSON null es ausencia), la misma suma que la puerta mensual oficial; nunca recalcula. Sin autorización dentro y sin ejecutores de la API.';

revoke all on function private.conversion_divisor_empresa_totales(date)
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
  v_totales record;
  v_payload jsonb;
begin
  -- 1) Gate primero: un actor denegado recibe 42501 aunque el período sea inválido.
  --    `is not true`: un NULL del gate también deniega.
  if private.puede_operar_reparto_crm() is not true then
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

  -- 3) Delegar: el núcleo decide abierto/sellado y trae las cifras; aquí solo se da forma.
  select t.* into strict v_totales from private.conversion_divisor_empresa_totales(v_periodo) t;

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
    'sellado', v_totales.sellado,
    'peso_referido', v_totales.peso_referido,
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
      'divisor_landing', v_totales.divisor_landing
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
          'conversion_pct', f.conversion_pct
        )
        order by f.nombre nulls last, f.analista_id
      )
      from private.conversion_divisor_empresa(v_periodo) f
      where f.analista_id is not null
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.conversion_divisor_coordinacion_fn(date) is
  'Puerta (30/09/2026): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; la puerta mensual oficial sigue denegando al coordinador). Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en private.conversion_divisor_empresa y private.conversion_divisor_empresa_totales: el divisor es el del núcleo (una llegada por lead, en el primer analista asignado), no el reporte de entregas. Mes sellado: sirve la foto; las filas no rankeables del sello suman al total y no aparecen como analista. Sin PII de leads.';

revoke all on function crm.conversion_divisor_coordinacion_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_divisor_coordinacion_fn(date)
  to authenticated;

do $postflight$
declare
  v_nucleo regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date)');
  v_totales regprocedure := pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date)');
  v_puerta regprocedure := pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)');
  v_cuerpo text;
  v_mes date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_filas_nucleo integer;
  v_filas_neto integer;
  v_divisor_nucleo bigint;
  v_divisor_neto bigint;
  v_divisor_origen bigint;
begin
  if v_nucleo is null or v_totales is null or v_puerta is null then
    raise exception 'POSTFLIGHT: faltan las tres funciones de la conversión de Coordinación';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
       where p.oid in (v_nucleo, v_totales, v_puerta)
         and p.prosecdef
         and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']) <> 3 then
    raise exception 'POSTFLIGHT: las tres funciones deben ser STABLE, SECURITY DEFINER y usar search_path vacío';
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
     or pg_catalog.has_function_privilege('public', v_totales, 'execute') then
    raise exception 'POSTFLIGHT: ACL inesperada (la puerta solo para authenticated; los núcleos sin ejecutores de la API)';
  end if;

  -- La puerta se ejecuta al menos una vez aquí (compila y planifica en esta base):
  -- sin JWT no hay actor y el gate debe responder 42501 antes de tocar nada.
  begin
    perform crm.conversion_divisor_coordinacion_fn();
    raise exception 'POSTFLIGHT: la puerta respondió sin actor autenticado';
  exception when insufficient_privilege then null;
  end;

  -- EL CANDADO DE DISPERSIÓN: ninguna de las dos vuelve a contar leads ni el
  -- ledger. Si alguien recalcula el divisor fuera del núcleo, este postflight (y
  -- el oráculo que lo repite) lo rechazan. Se miran los cuerpos sin comentarios.
  for v_cuerpo in
    select pg_catalog.regexp_replace(pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g')
    from pg_catalog.pg_proc p where p.oid in (v_nucleo, v_totales, v_puerta)
  loop
    if v_cuerpo ~ '\mcrm\.\s*leads\M' or v_cuerpo ~ '"leads"' or v_cuerpo ~ '\mlead_asignaciones\M' then
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
$migracion_20260930185623$;
  v_nombre text;
  v_sentencias text[];
  v_definicion text;
begin
  if v_nucleo is null or v_totales is null or v_puerta is null then
    raise exception 'REGISTRO: faltan las funciones de la conversión de Coordinación';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
       where p.oid in (v_nucleo, v_totales, v_puerta)
         and p.prosecdef and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']) <> 3 then
    raise exception 'REGISTRO: las funciones no conservan STABLE, SECURITY DEFINER y search_path vacío';
  end if;

  select pg_catalog.pg_get_functiondef(v_puerta) into v_definicion;
  if pg_catalog.strpos(v_definicion, 'private.puede_operar_reparto_crm()') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_divisor_empresa(') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_divisor_empresa_totales(') = 0
     or v_definicion ~* '\m(from|join)\s+(crm|public)\.' then
    raise exception 'REGISTRO: la puerta viva no coincide con el contrato esperado (o lee tablas)';
  end if;
  select pg_catalog.pg_get_functiondef(v_nucleo) into v_definicion;
  if pg_catalog.strpos(v_definicion, 'private.conversion_neta_por_vendedor(') = 0
     or pg_catalog.strpos(v_definicion, 'private.conversion_episodios(') = 0
     or v_definicion ~* 'crm\.\s*leads\M' or v_definicion ~* '\mlead_asignaciones\M' then
    raise exception 'REGISTRO: el núcleo vivo no lee el núcleo de conversión o volvió a contar leads';
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
     or pg_catalog.has_function_privilege('public', v_totales, 'execute') then
    raise exception 'REGISTRO: ACL inesperada en la conversión de Coordinación';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values (
    '20260930185623',
    'crm_conversion_divisor_coordinacion',
    array[v_cuerpo]
  )
  on conflict (version) do nothing;

  select migracion.name, migracion.statements
    into v_nombre, v_sentencias
  from supabase_migrations.schema_migrations migracion
  where migracion.version = '20260930185623';

  if v_nombre is distinct from 'crm_conversion_divisor_coordinacion'
     or v_sentencias is distinct from array[v_cuerpo] then
    raise exception 'REGISTRO: la versión 20260930185623 ya existe con otro contenido';
  end if;
end;
$registrar_conversion_divisor_coordinacion$;

commit;

select 'REGISTRO_CONVERSION_DIVISOR_COORDINACION_OK' as resultado,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)')) as huella_puerta,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.conversion_divisor_empresa(date)')) as huella_nucleo,
       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.conversion_divisor_empresa_totales(date)')) as huella_totales;
