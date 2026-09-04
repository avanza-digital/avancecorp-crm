-- Registrador fail-closed de 20260904153431_reporte_diario_derivaciones_coordinacion.
-- Ejecutar inmediatamente después de la migración por la misma vía
-- (`db query --linked --file`). Registra el cuerpo literal del archivo y
-- rechaza una versión previa que no coincida.

begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $registrar_reporte_coordinacion$
declare
  v_rpc regprocedure := pg_catalog.to_regprocedure(
    'crm.reporte_derivaciones_coordinacion_fn(date,date)'
  );
  v_cuerpo text := $migracion_20260904153431$-- ============================================================================
-- CRM · Reporte diario de derivaciones para Coordinación
--
-- Coordinación necesita rendir cuántos leads entregó Supervisión a cada
-- analista, día por día. La fuente es el ledger inmutable
-- `crm.lead_asignaciones`, no la tenencia actual de `crm.leads`: una
-- transferencia posterior no puede reescribir el reporte histórico.
--
-- El contrato replica la definición vigente del reporte de Supervisión:
--   * solo aperturas `asignado|reasignado` hechas por el supervisor de origen;
--   * una devolución a la misma bandeja, previa a la gestión, deja de sumar;
--   * los cortes de fecha son inclusivos y usan America/Lima.
--
-- La RPC no entrega leads, capital ni PII. Solo fecha, responsables y conteos.
-- ============================================================================

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if pg_catalog.to_regprocedure('private.puede_operar_reparto_crm()') is null then
    raise exception 'PREFLIGHT: falta la puerta canónica private.puede_operar_reparto_crm()';
  end if;
end;
$preflight$;

create or replace function crm.reporte_derivaciones_coordinacion_fn(
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
  v_desde date;
  v_hasta date;
  v_inicio_periodo timestamptz;
  v_fin_periodo timestamptz;
  v_payload jsonb;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar el reporte diario de derivaciones'
      using errcode = '42501';
  end if;

  if p_desde is null and p_hasta is null then
    v_desde := v_hoy - 1;
    v_hasta := v_hoy - 1;
  elsif p_desde is null or p_hasta is null then
    raise exception 'Indica ambas fechas del reporte'
      using errcode = '22023';
  else
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;

  if v_desde > v_hasta then
    raise exception 'La fecha inicial no puede ser posterior a la fecha final'
      using errcode = '22023';
  end if;
  if v_hasta > v_hoy then
    raise exception 'El reporte no admite fechas futuras'
      using errcode = '22023';
  end if;
  if v_hasta - v_desde > 365 then
    raise exception 'El rango máximo del reporte es de 366 días'
      using errcode = '22023';
  end if;

  v_inicio_periodo := v_desde::timestamp at time zone 'America/Lima';
  v_fin_periodo := (v_hasta + 1)::timestamp at time zone 'America/Lima';

  with dias as materialized (
    select serie::date as fecha
    from pg_catalog.generate_series(
      v_desde::timestamp,
      v_hasta::timestamp,
      interval '1 day'
    ) as serie
  ),
  episodios_periodo as materialized (
    select
      (asignacion.asignado_en at time zone 'America/Lima')::date as fecha,
      asignacion.analista_id,
      analista_perfil.nombre_completo as analista_nombre,
      asignacion.supervisor_origen_id as supervisor_id,
      supervisor_perfil.nombre_completo as supervisor_nombre
    from crm.lead_asignaciones asignacion
    join public.perfiles analista_perfil
      on analista_perfil.id = asignacion.analista_id
    join public.perfiles supervisor_perfil
      on supervisor_perfil.id = asignacion.supervisor_origen_id
    where asignacion.asignado_en >= v_inicio_periodo
      and asignacion.asignado_en < v_fin_periodo
      and asignacion.asignado_por = asignacion.supervisor_origen_id
      and asignacion.motivo_apertura in ('asignado', 'reasignado')
      and (
        asignacion.motivo_cierre is distinct from 'parqueado'
        or asignacion.supervisor_destino_id is distinct from asignacion.supervisor_origen_id
      )
  ),
  conteos as materialized (
    select
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre,
      pg_catalog.count(*)::integer as derivados
    from episodios_periodo episodio
    group by
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'periodo', pg_catalog.jsonb_build_object(
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', v_hasta - v_desde + 1,
      'zona', 'America/Lima'
    ),
    'total_derivados', (
      select pg_catalog.count(*)::integer from episodios_periodo
    ),
    'dias', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'fecha', dia.fecha,
          'total_derivados', coalesce((
            select pg_catalog.sum(conteo.derivados)::integer
            from conteos conteo
            where conteo.fecha = dia.fecha
          ), 0),
          'analistas', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'analista_id', conteo.analista_id,
                'analista_nombre', conteo.analista_nombre,
                'supervisor_id', conteo.supervisor_id,
                'supervisor_nombre', conteo.supervisor_nombre,
                'derivados', conteo.derivados
              )
              order by conteo.supervisor_nombre, conteo.analista_nombre,
                conteo.supervisor_id, conteo.analista_id
            )
            from conteos conteo
            where conteo.fecha = dia.fecha
          ), '[]'::jsonb)
        )
        order by dia.fecha desc
      )
      from dias dia
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.reporte_derivaciones_coordinacion_fn(date, date) is
  'Reporte diario, agregado y sin PII de las entregas de Supervisión a analistas. Usa crm.lead_asignaciones y fechas inclusivas de America/Lima; solo Coordinación o Gerencia activas.';

revoke all on function crm.reporte_derivaciones_coordinacion_fn(date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.reporte_derivaciones_coordinacion_fn(date, date)
  to authenticated;

do $postflight$
declare
  v_rpc regprocedure := pg_catalog.to_regprocedure(
    'crm.reporte_derivaciones_coordinacion_fn(date,date)'
  );
begin
  if v_rpc is null then
    raise exception 'POSTFLIGHT: falta crm.reporte_derivaciones_coordinacion_fn(date,date)';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc procedimiento
    where procedimiento.oid = v_rpc
      and procedimiento.prosecdef
      and procedimiento.provolatile = 's'
      and procedimiento.proconfig @> array['search_path=""']
  ) then
    raise exception 'POSTFLIGHT: la RPC debe ser STABLE, SECURITY DEFINER y usar search_path vacío';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', v_rpc, 'execute')
     or pg_catalog.has_function_privilege('anon', v_rpc, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_rpc, 'execute') then
    raise exception 'POSTFLIGHT: ACL inesperada en el reporte diario de Coordinación';
  end if;
end;
$postflight$;

commit;
$migracion_20260904153431$;
  v_nombre text;
  v_sentencias text[];
begin
  if v_rpc is null then
    raise exception 'REGISTRO: falta crm.reporte_derivaciones_coordinacion_fn(date,date)';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc procedimiento
    where procedimiento.oid = v_rpc
      and procedimiento.prosecdef
      and procedimiento.provolatile = 's'
      and procedimiento.proconfig @> array['search_path=""']
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(procedimiento.oid),
        'private.puede_operar_reparto_crm()'
      ) > 0
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(procedimiento.oid),
        'crm.lead_asignaciones'
      ) > 0
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(procedimiento.oid),
        'America/Lima'
      ) > 0
  ) then
    raise exception 'REGISTRO: la RPC viva no coincide con el contrato esperado';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', v_rpc, 'execute')
     or pg_catalog.has_function_privilege('anon', v_rpc, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_rpc, 'execute')
     or pg_catalog.has_function_privilege('public', v_rpc, 'execute') then
    raise exception 'REGISTRO: ACL inesperada en el reporte diario de Coordinación';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values (
    '20260904153431',
    'reporte_diario_derivaciones_coordinacion',
    array[v_cuerpo]
  )
  on conflict (version) do nothing;

  select migracion.name, migracion.statements
    into v_nombre, v_sentencias
  from supabase_migrations.schema_migrations migracion
  where migracion.version = '20260904153431';

  if v_nombre is distinct from 'reporte_diario_derivaciones_coordinacion'
     or v_sentencias is distinct from array[v_cuerpo] then
    raise exception 'REGISTRO: la versión 20260904153431 ya existe con otro contenido';
  end if;
end;
$registrar_reporte_coordinacion$;

commit;
