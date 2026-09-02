-- ============================================================================
-- Ranking mensual: una sola foto coherente para conversion, capital y cosecha
-- ============================================================================
--
-- Corrige cinco grietas del primer cierre real (agosto 2026):
--   1. produccion_mes_por_vendedor descartaba capital/contratos de un vendedor
--      sin meta, aunque cerrar_periodo si intentaba incluir a quien produjo;
--   2. esa persona quedaba con supervisor/objetivo nulos y detalles vacios, una
--      forma que el contrato fail-closed del frontend rechaza por completo;
--   3. conversion_mensual_fn y cumplimiento_metas_fn volvían a consultar la
--      cartera viva sobre una foto sellada;
--   4. conversion, cumplimiento y cosecha no publicaban un token comun para
--      detectar una lectura N mezclada con N+1 durante publicacion/cierre.
--   5. la produccion atribuida a supervisores u otros perfiles no analistas
--      podia perderse o terminar compitiendo como si fuera de un vendedor.
--
-- No nace ninguna funcion ni formula. Se reemplazan los seis nucleos ya
-- existentes, con la misma firma, seguridad, volatilidad y ACL. La cartera se
-- guarda dentro de la tabla de foto existente.
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: solo sobre la forma viva que se audito el 02/09/2026.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_fila record;
begin
  -- Serializa el preflight con cierres y publicaciones de metas. Sin este
  -- lock, un cierre viejo podia pasar en paralelo y nacer con cartera cero.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );

  if to_regclass('crm.cierre_mes_vendedor') is null then
    raise exception 'Falta crm.cierre_mes_vendedor.';
  end if;

  -- No se reconstruye una foto historica desde datos mutables. Produccion fue
  -- comprobada con cero cierres antes de preparar este cambio; si el ciclo se
  -- adelanto entre la revision y el deploy, se aborta y se vuelve a decidir.
  if exists (select 1 from crm.periodos_cerrados) then
    raise exception using
      errcode = '55000',
      message = 'Ya existen meses cerrados: no se añade cartera a fotos antiguas desde estado vivo.',
      hint = 'Auditar las fotos existentes antes de reintentar esta migracion.';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'crm' and table_name = 'cierre_mes_vendedor'
      and column_name = 'cartera'
  ) then
    raise exception 'crm.cierre_mes_vendedor.cartera ya existe: revisar antes de reaplicar.';
  end if;

  for v_fila in
    select * from (values
      ('private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', '6d5ccff20d28d767ebd6efdf851806ac'),
      ('crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'),
      ('crm.conversion_mensual_sin_cartera_fn(date)',                       'c7a7a103d6665acb9231976a3a2fcfa6'),
      ('crm.conversion_mensual_fn(date)',                                   'abd2bb70c83872e3d4072b62c5c40e29'),
      ('crm.cumplimiento_metas_fn(date)',                                   'baca0a53f3af12f57a2219626379ace0'),
      ('crm.metricas_conversiones_equipo_fn(date,date)',                    'ecb67d4a306ab83330b79f1f750a62c2')
    ) as esperado(firma, huella)
  loop
    if to_regprocedure(v_fila.firma) is null then
      raise exception 'Falta el nucleo %.', v_fila.firma;
    end if;
    if (select md5(p.prosrc) from pg_catalog.pg_proc p
        where p.oid = to_regprocedure(v_fila.firma)) is distinct from v_fila.huella then
      raise exception 'El nucleo % cambio desde la auditoria; revisar antes de aplicar.', v_fila.firma;
    end if;
  end loop;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La tabla existente congela tambien la cartera posventa.
-- ---------------------------------------------------------------------------
alter table crm.cierre_mes_vendedor
  add column cartera jsonb not null default jsonb_build_object(
    'conversiones_clientes', 0,
    'conversiones_renovacion', 0,
    'conversiones_upgrade', 0,
    'operaciones_renovacion', 0,
    'operaciones_upgrade', 0,
    'capital_renovado_pen', 0,
    'capital_renovado_usd', 0,
    'capital_adicional_pen', 0,
    'capital_adicional_usd', 0,
    'renovaciones_sin_desglose', 0
  ),
  alter column supervisor_id set not null,
  alter column supervisor_nombre set not null,
  alter column conversion_objetivo set not null,
  add constraint cierre_mes_vendedor_cartera_objeto_check
    check (jsonb_typeof(cartera) = 'object');

comment on column crm.cierre_mes_vendedor.cartera is
  'Foto inmutable de private.metricas_cartera_por_vendedor al sellar: conversiones y operaciones de renovacion/upgrade, capital renovado/adicional y faltantes de desglose. Nunca se recalcula para un mes cerrado.';

-- ---------------------------------------------------------------------------
-- 2. El nucleo conserva la produccion aunque su dueño no sea rankeable.
-- ---------------------------------------------------------------------------
-- Analista de cierre, vendedor explicito del lead y vendedor FOTO de una
-- cooperativa son atribuciones de negocio: se conservan aunque hoy la persona
-- sea supervisor o haya salido del equipo. El autor del registro sigue siendo
-- solo un fallback y exige rol vendedor, para no regalarle una venta a quien
-- meramente la digitó. Ranking y total se separan mas adelante.
do $parche_produccion$
declare
  v_src text;
  v_old text;
  v_new text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure;

  v_old := $old$
        when base.analista_cierre_id is not null then meta_analista.vendedor_id
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
$old$;
  v_new := $new$
        when base.analista_cierre_id is not null
          then coalesce(meta_analista.vendedor_id, base.analista_cierre_id)
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito
          then coalesce(meta_lead.vendedor_id, base.vendedor_unico)
        else coalesce(meta_autor.vendedor_id, equipo_autor.perfil_id)
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola atribucion en produccion_mes_por_vendedor.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    left join crm.metas_vendedor meta_analista
      on meta_analista.meta_periodo_id=p_periodo_id
     and meta_analista.vendedor_id=base.analista_cierre_id
$old$;
  v_new := v_old || $new$    left join crm.equipo equipo_autor
      on equipo_autor.perfil_id=base.creado_por
     and equipo_autor.rol_crm='vendedor'
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola ancla de membresia en produccion_mes_por_vendedor.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    select
      mv.vendedor_id,
      'nuevo'::text as categoria,
      ce.moneda,
      ce.monto as capital
$old$;
  v_new := $new$
    select
      coalesce(mv.vendedor_id, ce.vendedor_id) as vendedor_id,
      'nuevo'::text as categoria,
      ce.moneda,
      ce.monto as capital
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola proyeccion de cooperativas en produccion_mes_por_vendedor.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin
$old$;
  v_new := $new$
    left join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola validacion de cooperativas en produccion_mes_por_vendedor.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function private.produccion_mes_por_vendedor(p_ini timestamptz, p_fin timestamptz, p_periodo_id uuid) returns table(vendedor_id uuid, categoria text, moneda text, contratos_real integer, capital_real numeric) language sql stable security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche_produccion$;

comment on function private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid) is
  'Nucleo unico de capital y contratos por dueño/categoria/moneda. Conserva las atribuciones explicitas de contrato, lead y cooperativa aunque el dueño no sea rankeable; solo el fallback por autor exige meta o rol vendedor. No decide puestos: cumplimiento y cerrar_periodo separan ranking de produccion fuera de ranking.';

revoke all on function private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. El cierre guarda una fila completa incluso cuando no hubo meta.
-- ---------------------------------------------------------------------------
do $parche_cierre$
declare
  v_src text;
  v_old text;
  v_new text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;

  v_old := $old$
  v_vendedores  integer;
  v_pendiente   date;
$old$;
  v_new := $new$
  v_vendedores  integer;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_pendiente   date;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola declaracion de foto fuera de ranking.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  -- El equipo que resuelve el supervisor de respaldo no puede cambiar mientras
  -- se toma la foto. Los dos advisory locks originales permanecen intactos.
  v_old := $old$
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer
  );
$old$;
  v_new := v_old || $new$
  lock table crm.equipo in share mode;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo candado por periodo en cerrar_periodo.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  ), prod as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), roster as (
$old$;
  v_new := $new$
  ), prod as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as (
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola tabla-base de produccion en cerrar_periodo.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  -- Antes de insertar el sello se congela tambien lo producido por identidades
  -- que no pueden competir como analistas. Vive dentro de `cobertura`, que ya
  -- es parte append-only de la foto del periodo; no nace otra tabla ni otro
  -- calculador. Las fuentes siguen siendo exactamente los tres nucleos vivos.
  v_old := $old$
  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura
  ) values (
$old$;
  v_new := $new$
  with conv as materialized (
    select cm.*
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm
  ), prod as materialized (
    select r.*
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as materialized (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as materialized (
    select distinct mv.vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
    union
    select p.vendedor_id from prod p where p.vendedor_id is not null
    union
    select c.vendedor_id from car c where c.vendedor_id is not null
  ), elegibles as (
    select r.vendedor_id as persona_id from roster r
    union
    select p.persona_id
    from personas p
    join crm.equipo e
      on e.perfil_id = p.persona_id and e.rol_crm = 'vendedor'
    join crm.equipo s
      on s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
  ), fuera as (
    select
      p.persona_id,
      coalesce(nullif(btrim(pf.nombre_completo), ''),
               '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
      coalesce(e.rol_crm, 'fuera_equipo') as rol_crm,
      case
        when e.rol_crm = 'vendedor' then 'analista_sin_supervisor'
        when e.rol_crm = 'supervisor' then 'supervisor'
        when e.rol_crm = 'gerencia' then 'gerencia'
        else 'fuera_estructura'
      end as motivo
    from personas p
    left join crm.equipo e on e.perfil_id = p.persona_id
    left join public.perfiles pf on pf.id = p.persona_id
    where not exists (
      select 1 from elegibles ok where ok.persona_id = p.persona_id
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'persona_id', f.persona_id,
    'nombre', f.nombre,
    'rol_crm', f.rol_crm,
    'motivo', f.motivo,
    'conversion', case when cv.analista_id is null then null else jsonb_build_object(
      'divisor', coalesce(cv.divisor, 0),
      'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
      'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
      'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
      'cierres_referidos', coalesce(cv.cierres_referidos, 0),
      'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
      'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
      'numerador', coalesce(cv.numerador, 0)
    ) end,
    'detalles', det.detalles,
    'cartera', jsonb_build_object(
      'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
      'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
      'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
      'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
    )
  ) order by f.nombre, f.persona_id), '[]'::jsonb)
    into v_fuera_ranking
  from fuera f
  left join conv cv on cv.analista_id = f.persona_id
  left join car on car.vendedor_id = f.persona_id
  left join lateral (
    select jsonb_agg(jsonb_build_object(
      'categoria', d.categoria,
      'moneda', d.moneda,
      'capital_objetivo', 0,
      'capital_real', coalesce(pr.capital_real, 0),
      'capital_cumplimiento_pct', null,
      'contratos_objetivo', 0,
      'contratos_real', coalesce(pr.contratos_real, 0),
      'contratos_cumplimiento_pct', null,
      'capital_ajuste', 0,
      'contratos_ajuste', 0
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], d.categoria
    ), d.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) d(categoria, moneda)
    left join prod pr on pr.vendedor_id = f.persona_id
      and pr.categoria = d.categoria and pr.moneda = d.moneda
  ) det on true;

  v_cobertura := v_cobertura || jsonb_build_object(
    'fuera_ranking', v_fuera_ranking
  );

  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura
  ) values (
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola insercion del sello mensual.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  ), personas as (
    select vendedor_id from roster
    union
    select analista_id from conv
    union
    select vendedor_id from prod where vendedor_id is not null
  )
$old$;
  v_new := $new$
  ), personas as (
    select vendedor_id from roster
    union
    select analista_id from conv
    union
    select vendedor_id from prod where vendedor_id is not null
    union
    select vendedor_id from car where vendedor_id is not null
  ), foto as (
    select
      pe.vendedor_id,
      r.meta_vendedor_id,
      coalesce(r.supervisor_id, supervisor_actual.perfil_id) as supervisor_id,
      coalesce(r.conversion_objetivo, 0::numeric) as conversion_objetivo
    from personas pe
    left join roster r on r.vendedor_id = pe.vendedor_id
    left join crm.equipo vendedor_actual
      on vendedor_actual.perfil_id = pe.vendedor_id
    left join crm.equipo supervisor_actual
      on supervisor_actual.perfil_id = vendedor_actual.supervisor_id
     and supervisor_actual.rol_crm = 'supervisor'
    where r.meta_vendedor_id is not null
       or (
         vendedor_actual.rol_crm = 'vendedor'
         and supervisor_actual.perfil_id is not null
       )
  )
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola poblacion en cerrar_periodo.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles
$old$;
  v_new := $new$
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles, cartera
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola lista de columnas de la foto.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    pe.vendedor_id,
    coalesce(pf.nombre_completo, '(sin ficha)'),
    r.supervisor_id,
    sup.nombre_completo,
$old$;
  v_new := $new$
    pe.vendedor_id,
    coalesce(nullif(btrim(pf.nombre_completo), ''),
             '(sin nombre · ' || left(pe.vendedor_id::text, 8) || ')'),
    pe.supervisor_id,
    coalesce(nullif(btrim(sup.nombre_completo), ''), '(sin ficha)'),
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola identidad de foto en cerrar_periodo.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    r.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb)
  from personas pe
  left join roster r on r.vendedor_id = pe.vendedor_id
  left join conv c on c.analista_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = r.supervisor_id
$old$;
  v_new := $new$
    pe.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb),
    jsonb_build_object(
      'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
      'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
      'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
      'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
    )
  from foto pe
  left join conv c on c.analista_id = pe.vendedor_id
  left join car on car.vendedor_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = pe.supervisor_id
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola proyeccion de foto en cerrar_periodo.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    select jsonb_agg(jsonb_build_object(
      'categoria', d.categoria,
      'moneda', d.moneda,
      'capital_objetivo', d.capital_objetivo,
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when d.capital_objetivo > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', d.contratos_objetivo,
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when d.contratos_objetivo > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      -- Y se DECLARA lo descontado en su propia casilla: la foto tiene que poder
      -- explicar por que ese numero no es el bruto.
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(array['nuevo','renovacion','upgrade'], d.categoria), d.moneda) as detalles
    from crm.metas_vendedor_detalle d
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = d.categoria and pr.moneda = d.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = d.categoria and e->>'moneda' = d.moneda
      limit 1
    ) aj on true
    where d.meta_vendedor_id = r.meta_vendedor_id
$old$;
  v_new := $new$
    select jsonb_agg(jsonb_build_object(
      'categoria', dimensiones.categoria,
      'moneda', dimensiones.moneda,
      'capital_objetivo', coalesce(d.capital_objetivo, 0),
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when coalesce(d.capital_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', coalesce(d.contratos_objetivo, 0),
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when coalesce(d.contratos_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], dimensiones.categoria
    ), dimensiones.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) dimensiones(categoria, moneda)
    left join crm.metas_vendedor_detalle d
      on d.meta_vendedor_id = pe.meta_vendedor_id
     and d.categoria = dimensiones.categoria
     and d.moneda = dimensiones.moneda
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = dimensiones.categoria
     and pr.moneda = dimensiones.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = dimensiones.categoria
        and e->>'moneda' = dimensiones.moneda
      limit 1
    ) aj on true
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo detalle de metas en cerrar_periodo.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function crm.cerrar_periodo(p_periodo date) returns jsonb language plpgsql volatile security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche_cierre$;

comment on function crm.cerrar_periodo(date) is
  'Sella una foto mensual coherente de conversion, cumplimiento, capital y cartera. Conserva los candados global/periodo y los ajustes; incluye al vendedor que produjo sin meta con objetivos cero y congela aparte, dentro de cobertura.fuera_ranking, la produccion de supervisores u otros perfiles no analistas.';

revoke all on function crm.cerrar_periodo(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.cerrar_periodo(date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Conversion y cumplimiento leen cartera viva o foto, nunca una mezcla.
-- ---------------------------------------------------------------------------
-- La eleccion de poblacion pertenece al nucleo sin decoracion. Asi el wrapper
-- publico vuelve a limitarse a cartera/revision y no mantiene una calculadora
-- historica paralela (causa del censo rojo heredado de 20260902070052).
do $parche_conversion_base$
declare
  v_src text;
  v_old text;
  v_new text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure;

  v_old := $old$
  v_motivo_roster text;
  v_payload jsonb;
$old$;
  v_new := $new$
  v_motivo_roster text;
  v_meta_periodo_id uuid;
  v_es_historico_abierto boolean := false;
  v_payload jsonb;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola declaracion en conversion_mensual_sin_cartera_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    with visibles as (
      select f.* from private.cierre_mes_visible(p_periodo, v_uid) f
    ), resumen as (
      -- El total se RECALCULA sumando, nunca promediando porcentajes.
      select
        count(*)::int as analistas,
        coalesce(sum(v.divisor), 0)::int as divisor,
        coalesce(sum(v.divisor_aproximado), 0)::int as divisor_aproximado,
        coalesce(sum(v.cierres_no_referidos), 0)::int as cierres_no_referidos,
        coalesce(sum(v.cierres_referidos), 0)::int as cierres_referidos,
        coalesce(sum(v.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
        coalesce(sum(v.referidos_recibidos), 0)::int as referidos_recibidos,
        coalesce(sum(v.numerador), 0::numeric) as numerador
      from visibles v
    ), motivos as (
      select e.key as motivo, sum(e.value::int)::int as n
      from visibles v, jsonb_each_text(v.divisor_por_motivo) e
      group by e.key
    )
$old$;
  v_new := $new$
    with visibles as (
      select f.* from private.cierre_mes_visible(p_periodo, v_uid) f
    ), fuera_foto as materialized (
      select e.value as fila
      from jsonb_array_elements(
        coalesce(v_cierre.cobertura->'fuera_ranking', '[]'::jsonb)
      ) e
      where v_global and e.value->'conversion' <> 'null'::jsonb
    ), resumen as (
      -- El total suma la foto rankeable y el agregado empresarial congelado.
      -- Las identidades externas nunca se materializan como responsables.
      select
        count(*)::int as analistas,
        (coalesce(sum(v.divisor), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor}')::int)
                      from fuera_foto f), 0))::int as divisor,
        (coalesce(sum(v.divisor_aproximado), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor_aproximado}')::int)
                      from fuera_foto f), 0))::int as divisor_aproximado,
        (coalesce(sum(v.cierres_no_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_no_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_no_referidos,
        (coalesce(sum(v.cierres_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_referidos,
        (coalesce(sum(v.cierres_de_arrastre), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_de_arrastre}')::int)
                      from fuera_foto f), 0))::int as cierres_de_arrastre,
        (coalesce(sum(v.referidos_recibidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,referidos_recibidos}')::int)
                      from fuera_foto f), 0))::int as referidos_recibidos,
        (coalesce(sum(v.numerador), 0::numeric)
          + coalesce((select sum((f.fila#>>'{conversion,numerador}')::numeric)
                      from fuera_foto f), 0::numeric)) as numerador
      from visibles v
    ), motivos as (
      select e.key as motivo, sum(e.value::int)::int as n
      from (
        select v.divisor_por_motivo from visibles v
        union all
        select coalesce(f.fila#>'{conversion,divisor_por_motivo}', '{}'::jsonb)
        from fuera_foto f
      ) dm, jsonb_each_text(dm.divisor_por_motivo) e
      group by e.key
    )
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo resumen cerrado de conversion.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
        -- Y no hay «fuera de roster» en una foto: al sellar, TODO el que produjo
        -- entro con su nombre. Esa es media razon de existir del sello.
        'fuera_de_roster', jsonb_build_object(
          'analistas', 0, 'divisor', 0, 'cierres', 0, 'numerador', 0)
$old$;
  v_new := $new$
        -- La producción de supervisores u otras identidades no rankeables se
        -- conserva en el total, pero no se convierte en una fila de analista.
        'fuera_de_roster', jsonb_build_object(
          'analistas', (select count(*)::int from fuera_foto),
          'divisor', coalesce((select sum(
            (f.fila#>>'{conversion,divisor}')::int) from fuera_foto f), 0)::int,
          'cierres', coalesce((select sum(
            (f.fila#>>'{conversion,cierres_no_referidos}')::int
            + (f.fila#>>'{conversion,cierres_referidos}')::int
          ) from fuera_foto f), 0)::int,
          'numerador', coalesce((select sum(
            (f.fila#>>'{conversion,numerador}')::numeric
          ) from fuera_foto f), 0::numeric))
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo agregado cerrado fuera de ranking.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  -- 4) Mes ABIERTO: exactamente el comportamiento de siempre.
  v_visibles := case when v_global then '{}'::uuid[]
$old$;
  v_new := $new$
  -- 4) Mes ABIERTO. Si es historico durante la ventana de ajuste, manda la
  -- ultima publicacion de ESE mes; el vigente conserva el roster operativo.
  v_es_historico_abierto := p_periodo < v_mes_actual;
  if v_es_historico_abierto then
    select mp.id into v_meta_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;
  end if;

  v_visibles := case when v_global then '{}'::uuid[]
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola apertura en conversion_mensual_sin_cartera_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  if v_alcance = 'propio'
     and not exists (
       select 1 from private.roster_metas_vendedores() r
       where r.vendedor_id = v_uid
     ) then
$old$;
  v_new := $new$
  if v_alcance = 'propio'
     and not (
       (v_es_historico_abierto and exists (
         select 1 from crm.metas_vendedor mv
         where mv.meta_periodo_id = v_meta_periodo_id
           and mv.vendedor_id = v_uid
       ))
       or (not v_es_historico_abierto and exists (
         select 1 from private.roster_metas_vendedores() r
         where r.vendedor_id = v_uid
       ))
     ) then
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola validacion propia en conversion_mensual_sin_cartera_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  with roster as materialized (
    select r.vendedor_id, r.supervisor_id
    from private.roster_metas_vendedores() r
    where v_global or r.vendedor_id = any(v_visibles)
  ),
$old$;
  v_new := $new$
  with roster as materialized (
    select r.vendedor_id, r.supervisor_id
    from private.roster_metas_vendedores() r
    where not v_es_historico_abierto
      and (v_global or r.vendedor_id = any(v_visibles))

    union all

    select mv.vendedor_id, mv.supervisor_id
    from crm.metas_vendedor mv
    where v_es_historico_abierto
      and mv.meta_periodo_id = v_meta_periodo_id
      and (v_global or mv.vendedor_id = any(v_visibles))
  ),
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo roster en conversion_mensual_sin_cartera_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
$old$;
  v_new := $new$
  -- El roster historico ya fue validado por su publicacion mensual. Aplicarle
  -- el rol/actividad de hoy borraria precisamente a una baja de ese mes.
  if v_es_historico_abierto then
    return v_payload;
  end if;
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola salida en conversion_mensual_sin_cartera_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function crm.conversion_mensual_sin_cartera_fn(p_periodo date) returns jsonb language plpgsql stable security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche_conversion_base$;

comment on function crm.conversion_mensual_sin_cartera_fn(date) is
  'Nucleo mensual de conversion: mes vigente con roster operativo, historico abierto con la ultima publicacion de ese mes y cerrado desde la foto sellada. Conserva formula, ambito, ajustes, cobertura y fuentes canonicas; en Gerencia suma al total empresarial la conversion congelada fuera del ranking sin crear responsables.';

revoke all on function crm.conversion_mensual_sin_cartera_fn(date)
  from public, anon, authenticated, service_role;

do $parche_conversion$
declare
  v_src text;
  v_old text;
  v_new text;
  v_inicio integer;
  v_fin integer;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'crm.conversion_mensual_fn(date)'::regprocedure;

  v_old := $old$
  v_base jsonb;
  v_total jsonb;
$old$;
  v_new := $new$
  v_base jsonb;
  v_total jsonb;
  v_cerrado boolean;
  v_revision integer;
  v_cartera_fila record;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola declaracion en conversion_mensual_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  if v_uid is null or not coalesce(
    v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
$old$;
  v_new := $new$
  if v_uid is null or not coalesce(
    v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo gate en conversion_mensual_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
  v_es_historico := p_periodo < v_mes_actual;
$old$;
  v_new := $new$
  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);
  if v_cerrado then
    select pc.meta_revision into v_revision
    from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  else
    select mp.revision into v_revision
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;
  end if;
  v_revision := coalesce(v_revision, 0);
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola lectura base en conversion_mensual_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  -- La rama historica completa ya vive en el nucleo anterior. Se retira del
  -- wrapper entre dos anclas auditadas para no mantener dos formulas.
  v_inicio := strpos(v_src, E'  v_es_historico_abierto := v_es_historico\n');
  v_fin := strpos(v_src, E'  -- Wrapper de cartera PREVIO');
  if v_inicio = 0 or v_fin = 0 or v_fin <= v_inicio then
    raise exception 'No se pudo aislar la rama historica duplicada de conversion_mensual_fn.';
  end if;
  v_src := left(v_src, v_inicio - 1) || substr(v_src, v_fin);

  -- La rama retirada era la única consumidora de estas variables. Dejarlas no
  -- rompe el resultado, pero sí esconde código muerto en el núcleo auditado.
  v_old := $old$
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_meta_periodo_id uuid;
  v_es_historico boolean;
  v_es_historico_abierto boolean;
$old$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo bloque de variables historicas obsoletas.';
  end if;
  v_src := replace(v_src, v_old, '');

  v_old := $old$
  v_total_conversion jsonb;
  v_cobertura jsonb;
$old$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo bloque de agregados historicos obsoletos.';
  end if;
  v_src := replace(v_src, v_old, '');

  v_old := $old$
  -- Wrapper de cartera PREVIO, al literal: su total conserva el ambito vivo
  -- de metricas_cartera_fn y no se redefine por la foto rankeable.
  v_total := crm.metricas_cartera_fn(p_periodo)->'total';

  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
  )
$old$;
  v_new := $new$
  -- Abierto: cartera viva. Cerrado: suma exclusivamente la columna congelada
  -- de las mismas filas que el actor puede ver en la foto mensual.
  if v_cerrado then
    v_total := jsonb_build_object(
      'conversiones_clientes', 0,
      'conversiones_renovacion', 0,
      'conversiones_upgrade', 0,
      'operaciones_renovacion', 0,
      'operaciones_upgrade', 0,
      'capital_renovado_pen', 0,
      'capital_renovado_usd', 0,
      'capital_adicional_pen', 0,
      'capital_adicional_usd', 0,
      'renovaciones_sin_desglose', 0
    );
    for v_cartera_fila in
      select f.cartera from private.cierre_mes_visible(p_periodo, v_uid) f
      union all
      select e.value->'cartera' as cartera
      from crm.periodos_cerrados pc
      cross join lateral jsonb_array_elements(
        coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
      ) e
      where pc.periodo = p_periodo and v_global
    loop
      v_total := jsonb_build_object(
        'conversiones_clientes',
          (v_total->>'conversiones_clientes')::int
          + (v_cartera_fila.cartera->>'conversiones_clientes')::int,
        'conversiones_renovacion',
          (v_total->>'conversiones_renovacion')::int
          + (v_cartera_fila.cartera->>'conversiones_renovacion')::int,
        'conversiones_upgrade',
          (v_total->>'conversiones_upgrade')::int
          + (v_cartera_fila.cartera->>'conversiones_upgrade')::int,
        'operaciones_renovacion',
          (v_total->>'operaciones_renovacion')::int
          + (v_cartera_fila.cartera->>'operaciones_renovacion')::int,
        'operaciones_upgrade',
          (v_total->>'operaciones_upgrade')::int
          + (v_cartera_fila.cartera->>'operaciones_upgrade')::int,
        'capital_renovado_pen',
          (v_total->>'capital_renovado_pen')::numeric
          + (v_cartera_fila.cartera->>'capital_renovado_pen')::numeric,
        'capital_renovado_usd',
          (v_total->>'capital_renovado_usd')::numeric
          + (v_cartera_fila.cartera->>'capital_renovado_usd')::numeric,
        'capital_adicional_pen',
          (v_total->>'capital_adicional_pen')::numeric
          + (v_cartera_fila.cartera->>'capital_adicional_pen')::numeric,
        'capital_adicional_usd',
          (v_total->>'capital_adicional_usd')::numeric
          + (v_cartera_fila.cartera->>'capital_adicional_usd')::numeric,
        'renovaciones_sin_desglose',
          (v_total->>'renovaciones_sin_desglose')::int
          + (v_cartera_fila.cartera->>'renovaciones_sin_desglose')::int
      );
    end loop;
  else
    v_total := crm.metricas_cartera_fn(p_periodo)->'total';
  end if;

  with m as materialized (
    select x.*
    from private.metricas_cartera_por_vendedor(p_periodo) x
    where not v_cerrado
    union all
    select
      f.vendedor_id,
      (f.cartera->>'conversiones_clientes')::int,
      (f.cartera->>'conversiones_renovacion')::int,
      (f.cartera->>'conversiones_upgrade')::int,
      (f.cartera->>'operaciones_renovacion')::int,
      (f.cartera->>'operaciones_upgrade')::int,
      (f.cartera->>'capital_renovado_pen')::numeric,
      (f.cartera->>'capital_renovado_usd')::numeric,
      (f.cartera->>'capital_adicional_pen')::numeric,
      (f.cartera->>'capital_adicional_usd')::numeric,
      (f.cartera->>'renovaciones_sin_desglose')::int
    from private.cierre_mes_visible(p_periodo, v_uid) f
    where v_cerrado
  )
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola cartera viva en conversion_mensual_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  v_base := jsonb_set(v_base, '{responsables}', v_responsables, true);
  v_base := jsonb_set(v_base, '{cartera}', coalesce(v_total, '{}'::jsonb), true);
$old$;
  v_new := $new$
  v_base := jsonb_set(v_base, '{responsables}', v_responsables, true);
  v_base := jsonb_set(v_base, '{revision}', to_jsonb(v_revision), true);
  v_base := jsonb_set(v_base, '{cartera}', coalesce(v_total, '{}'::jsonb), true);
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola salida en conversion_mensual_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function crm.conversion_mensual_fn(p_periodo date) returns jsonb language plpgsql stable security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche_conversion$;

comment on function crm.conversion_mensual_fn(date) is
  'Conversion mensual sobre el nucleo unico. Publica revision y, para un mes cerrado, sirve conversion y cartera exclusivamente desde la misma foto visible; Gerencia suma la cartera congelada fuera del ranking al total empresarial sin crear responsables. Un mes abierto sigue calculandose en vivo.';

revoke all on function crm.conversion_mensual_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_mensual_fn(date) to authenticated, service_role;

do $parche_cumplimiento$
declare
  v_src text;
  v_old text;
  v_new text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'crm.cumplimiento_metas_fn(date)'::regprocedure;

  v_old := $old$
  v_base jsonb;
  v_vendedores jsonb;
$old$;
  v_new := $new$
  v_base jsonb;
  v_vendedores jsonb;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_cerrado boolean;
  v_global boolean;
  v_periodo_id uuid;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola declaracion en cumplimiento_metas_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);

  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
  )
$old$;
  v_new := $new$
  v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);
  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);

  -- Solo Gerencia y el lector global reciben identidades fuera del ranking.
  -- Para un mes cerrado salen del JSON append-only del sello; para uno abierto
  -- se proyectan en vivo desde los mismos nucleos de conversion, produccion y
  -- cartera. Los demás roles reciben siempre un arreglo vacío.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  if v_global and v_cerrado then
    select coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
      into v_fuera_ranking
    from crm.periodos_cerrados pc
    where pc.periodo = p_periodo;
  elsif v_global then
    v_ini := p_periodo::timestamp at time zone 'America/Lima';
    v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
    v_factor := private.peso_referido_conversion(p_periodo);
    select mp.id into v_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;

    with conv as materialized (
      select cm.*
      from private.conversion_mensual_por_vendedor(
        v_ini, v_fin, true, '{}'::uuid[], v_factor
      ) cm
    ), prod as materialized (
      select r.*
      from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
    ), car as materialized (
      select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
      union
      select p.vendedor_id from prod p where p.vendedor_id is not null
      union
      select c.vendedor_id from car c where c.vendedor_id is not null
    ), dentro as (
      select (e.value->>'vendedor_id')::uuid as persona_id
      from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e
    ), fuera as (
      select
        p.persona_id,
        coalesce(nullif(btrim(pf.nombre_completo), ''),
                 '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
        coalesce(eq.rol_crm, 'fuera_equipo') as rol_crm,
        case
          when eq.rol_crm = 'vendedor' and sup.perfil_id is not null
            then 'analista_sin_meta'
          when eq.rol_crm = 'vendedor' then 'analista_sin_supervisor'
          when eq.rol_crm = 'supervisor' then 'supervisor'
          when eq.rol_crm = 'gerencia' then 'gerencia'
          else 'fuera_estructura'
        end as motivo
      from personas p
      left join crm.equipo eq on eq.perfil_id = p.persona_id
      left join crm.equipo sup
        on sup.perfil_id = eq.supervisor_id and sup.rol_crm = 'supervisor'
      left join public.perfiles pf on pf.id = p.persona_id
      where not exists (
        select 1 from dentro d where d.persona_id = p.persona_id
      )
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'persona_id', f.persona_id,
      'nombre', f.nombre,
      'rol_crm', f.rol_crm,
      'motivo', f.motivo,
      'conversion', case when cv.analista_id is null then null else jsonb_build_object(
        'divisor', coalesce(cv.divisor, 0),
        'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
        'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
        'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
        'cierres_referidos', coalesce(cv.cierres_referidos, 0),
        'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
        'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
        'numerador', coalesce(cv.numerador, 0)
      ) end,
      'detalles', det.detalles,
      'cartera', jsonb_build_object(
        'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
        'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
        'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
        'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
        'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
        'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
        'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
        'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
        'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
        'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
      )
    ) order by f.nombre, f.persona_id), '[]'::jsonb)
      into v_fuera_ranking
    from fuera f
    left join conv cv on cv.analista_id = f.persona_id
    left join car on car.vendedor_id = f.persona_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'categoria', d.categoria,
        'moneda', d.moneda,
        'capital_objetivo', 0,
        'capital_real', coalesce(pr.capital_real, 0),
        'capital_cumplimiento_pct', null,
        'contratos_objetivo', 0,
        'contratos_real', coalesce(pr.contratos_real, 0),
        'contratos_cumplimiento_pct', null,
        'capital_ajuste', 0,
        'contratos_ajuste', 0
      ) order by array_position(
        array['nuevo','renovacion','upgrade'], d.categoria
      ), d.moneda) as detalles
      from (values
        ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
        ('renovacion', 'PEN'), ('renovacion', 'USD'),
        ('upgrade', 'PEN'), ('upgrade', 'USD')
      ) d(categoria, moneda)
      left join prod pr on pr.vendedor_id = f.persona_id
        and pr.categoria = d.categoria and pr.moneda = d.moneda
    ) det on true;
  end if;

  with m as materialized (
    select x.*
    from private.metricas_cartera_por_vendedor(p_periodo) x
    where not v_cerrado
    union all
    select
      f.vendedor_id,
      (f.cartera->>'conversiones_clientes')::int,
      (f.cartera->>'conversiones_renovacion')::int,
      (f.cartera->>'conversiones_upgrade')::int,
      (f.cartera->>'operaciones_renovacion')::int,
      (f.cartera->>'operaciones_upgrade')::int,
      (f.cartera->>'capital_renovado_pen')::numeric,
      (f.cartera->>'capital_renovado_usd')::numeric,
      (f.cartera->>'capital_adicional_pen')::numeric,
      (f.cartera->>'capital_adicional_usd')::numeric,
      (f.cartera->>'renovaciones_sin_desglose')::int
    from private.cierre_mes_visible(p_periodo, v_uid) f
    where v_cerrado
  )
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola cartera en cumplimiento_metas_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  return jsonb_set(v_base, '{vendedores}', v_vendedores, true);
$old$;
  v_new := $new$
  v_base := jsonb_set(v_base, '{vendedores}', v_vendedores, true);
  return jsonb_set(v_base, '{fuera_ranking}', v_fuera_ranking, true);
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola salida en cumplimiento_metas_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function crm.cumplimiento_metas_fn(p_periodo date) returns jsonb language plpgsql stable security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche_cumplimiento$;

comment on function crm.cumplimiento_metas_fn(date) is
  'Cumplimiento mensual sobre el nucleo existente. En abierto incorpora conversiones de cartera vivas; en cerrado las incorpora desde la misma foto mensual, sin recalcular el pasado. Solo Gerencia recibe fuera_ranking con la produccion identificada que no pertenece a analistas rankeables.';

revoke all on function crm.cumplimiento_metas_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.cumplimiento_metas_fn(date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Cosecha publica el mismo token mensual de revision/cierre.
-- ---------------------------------------------------------------------------
do $parche_equipo$
declare
  v_src text;
  v_old text;
  v_new text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
  where p.oid = 'crm.metricas_conversiones_equipo_fn(date,date)'::regprocedure;

  v_old := $old$
  v_cerrado boolean := false;
  v_meta_periodo_id uuid;
  v_payload jsonb;
$old$;
  v_new := $new$
  v_cerrado boolean := false;
  v_meta_periodo_id uuid;
  v_revision integer;
  v_cerrado_en timestamptz;
  v_cierre_automatico boolean;
  v_payload jsonb;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola declaracion en metricas_conversiones_equipo_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
  if v_es_mes_historico then
    select exists (
      select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo
    ) into v_cerrado;

    if v_cerrado and not v_global then
      -- El ambito de los episodios tambien debe ser el SELLADO. Cambiar solo
      -- las filas del roster mostraria al vendedor historico con ceros.
      select coalesce(
        array_agg(f.vendedor_id order by f.vendedor_id), '{}'::uuid[]
      ) into v_visibles
      from private.cierre_mes_visible(v_periodo, v_uid) f;
    elsif not v_cerrado then
      -- Misma seleccion de revision vigente que cumplimiento_metas_fn.
      select mp.id into v_meta_periodo_id
      from crm.meta_periodos mp
      where mp.periodo = v_periodo
      order by mp.revision desc
      limit 1;
    end if;
  end if;
$old$;
  v_new := $new$
  -- Para cualquier mes calendario (historico o el vigente) se publica el mismo
  -- token que conversion/cumplimiento. Un rango libre no finge tener revision.
  if v_periodo is not null then
    select pc.meta_revision, pc.cerrado_en, pc.automatico
      into v_revision, v_cerrado_en, v_cierre_automatico
    from crm.periodos_cerrados pc
    where pc.periodo = v_periodo;

    if found then
      v_cerrado := true;
    else
      v_cerrado := false;
      select mp.id, mp.revision into v_meta_periodo_id, v_revision
      from crm.meta_periodos mp
      where mp.periodo = v_periodo
      order by mp.revision desc
      limit 1;
      v_revision := coalesce(v_revision, 0);
    end if;
  end if;

  if v_es_mes_historico and v_cerrado and not v_global then
    -- El ambito de los episodios tambien debe ser el SELLADO. Cambiar solo
    -- las filas del roster mostraria al vendedor historico con ceros.
    select coalesce(
      array_agg(f.vendedor_id order by f.vendedor_id), '{}'::uuid[]
    ) into v_visibles
    from private.cierre_mes_visible(v_periodo, v_uid) f;
  end if;
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro un solo selector mensual en metricas_conversiones_equipo_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  v_old := $old$
    'generado_en', v_ahora,
    'alcance', case when v_global then 'global' else 'equipo' end,
    'periodo', jsonb_build_object(
$old$;
  v_new := $new$
    'generado_en', v_ahora,
    'alcance', case when v_global then 'global' else 'equipo' end,
    'revision', case when v_periodo is null then null else v_revision end,
    'cierre', case
      when v_periodo is null then null
      when v_cerrado then jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cerrado_en,
        'automatico', v_cierre_automatico
      )
      else jsonb_build_object('cerrado', false)
    end,
    'periodo', jsonb_build_object(
$new$;
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'No se encontro una sola cabecera en metricas_conversiones_equipo_fn.';
  end if;
  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function crm.metricas_conversiones_equipo_fn(p_desde date, p_hasta date) returns jsonb language plpgsql stable security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche_equipo$;

comment on function crm.metricas_conversiones_equipo_fn(date,date) is
  'Ranking por cosecha sobre private.conversion_episodios. Para un mes calendario publica revision y cierre de la misma poblacion mensual que conversion/cumplimiento; un rango libre declara ambos como null.';

revoke all on function crm.metricas_conversiones_equipo_fn(date,date)
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_conversiones_equipo_fn(date,date) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. El censo de calculadoras conserva sus excepciones selladas.
-- ---------------------------------------------------------------------------
update private.analitica_leads_citas_exenciones e
set huella = (
  select md5(regexp_replace(regexp_replace(
           lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
           '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
  from pg_catalog.pg_proc p
  where p.oid = to_regprocedure(e.objeto)
)
where e.objeto in (
  'crm.cerrar_periodo(date)',
  'crm.conversion_mensual_sin_cartera_fn(date)',
  'crm.metricas_conversiones_equipo_fn(date,date)',
  'private.produccion_mes_por_vendedor(timestamp with time zone,timestamp with time zone,uuid)'
);

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
declare
  v_fila record;
  v_src text;
  v_acl text[];
begin
  -- Firma, lenguaje, volatilidad, SECURITY DEFINER, search_path y ACL exactos.
  for v_fila in
    select * from (values
      ('private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 's', 'sql',     array['postgres']::text[]),
      ('crm.cerrar_periodo(date)',                                          'v', 'plpgsql', array['authenticated','postgres','service_role']::text[]),
      ('crm.conversion_mensual_sin_cartera_fn(date)',                       's', 'plpgsql', array['postgres']::text[]),
      ('crm.conversion_mensual_fn(date)',                                   's', 'plpgsql', array['authenticated','postgres','service_role']::text[]),
      ('crm.cumplimiento_metas_fn(date)',                                   's', 'plpgsql', array['authenticated','postgres','service_role']::text[]),
      ('crm.metricas_conversiones_equipo_fn(date,date)',                    's', 'plpgsql', array['authenticated','postgres']::text[])
    ) as esperado(firma, volatilidad, lenguaje, ejecutores)
  loop
    select p.prosrc,
           coalesce(array_agg(distinct case
             when a.grantee = 0 then 'PUBLIC' else r.rolname end
             order by case when a.grantee = 0 then 'PUBLIC' else r.rolname end)
             filter (where a.privilege_type = 'EXECUTE'), '{}'::text[])
      into v_src, v_acl
    from pg_catalog.pg_proc p
    left join lateral aclexplode(
      coalesce(p.proacl, acldefault('f', p.proowner))
    ) a on true
    left join pg_catalog.pg_roles r on r.oid = a.grantee
    where p.oid = to_regprocedure(v_fila.firma)
    group by p.prosrc;

    if v_src is null then
      raise exception 'Desaparecio el nucleo %.', v_fila.firma;
    end if;
    if (select p.proowner from pg_proc p where p.oid=to_regprocedure(v_fila.firma))
         <> 'postgres'::regrole
       or (select l.lanname from pg_proc p join pg_language l on l.oid=p.prolang
           where p.oid=to_regprocedure(v_fila.firma)) <> v_fila.lenguaje
       or (select p.prosecdef from pg_proc p where p.oid=to_regprocedure(v_fila.firma)) is not true
       or (select p.provolatile from pg_proc p where p.oid=to_regprocedure(v_fila.firma)) <> v_fila.volatilidad
       or (select p.proconfig from pg_proc p where p.oid=to_regprocedure(v_fila.firma))
            is distinct from array['search_path=""']::text[] then
      raise exception 'Atributos de seguridad inesperados en %.', v_fila.firma;
    end if;
    if v_acl is distinct from v_fila.ejecutores then
      raise exception 'ACL inesperada en %: %.', v_fila.firma, v_acl;
    end if;
  end loop;

  if not exists (
    select 1 from information_schema.columns c
    where c.table_schema='crm' and c.table_name='cierre_mes_vendedor'
      and c.column_name='cartera' and c.is_nullable='NO'
  ) then
    raise exception 'La foto no tiene cartera NOT NULL.';
  end if;
  if exists (
    select 1 from information_schema.columns c
    where c.table_schema='crm' and c.table_name='cierre_mes_vendedor'
      and c.column_name in ('supervisor_id','supervisor_nombre','conversion_objetivo')
      and c.is_nullable <> 'NO'
  ) then
    raise exception 'La identidad/objetivo de la foto sigue admitiendo null.';
  end if;

  select p.prosrc into v_src from pg_proc p
  where p.oid='crm.cerrar_periodo(date)'::regprocedure;
  if v_src !~ 'hashtext\(''crm\.periodos_cerrados''\)::bigint'
     or v_src !~ 'hashtext\(''crm\.periodos_cerrados''\),'
     or v_src !~ 'private\.saldar_ajustes\('
     or v_src !~ 'private\.metricas_cartera_por_vendedor\('
     or v_src !~ 'lock table crm\.equipo in share mode'
     or v_src !~ '''fuera_ranking'', v_fuera_ranking' then
    raise exception 'cerrar_periodo perdio un candado o un nucleo canonico.';
  end if;

  select p.prosrc into v_src from pg_proc p
  where p.oid='crm.cumplimiento_metas_fn(date)'::regprocedure;
  if v_src !~ '''fuera_ranking'''
     or v_src !~ 'private\.produccion_mes_por_vendedor\('
     or v_src !~ 'private\.metricas_cartera_por_vendedor\(' then
    raise exception 'cumplimiento perdio la separacion de produccion fuera del ranking.';
  end if;

  if (select private.assert_analitica_leads_citas()) !~ '^OK:' then
    raise exception 'El censo analitico no quedo verde.';
  end if;
end;
$postflight$;

commit;
