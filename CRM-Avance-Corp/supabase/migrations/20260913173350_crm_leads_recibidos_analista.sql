-- Leads · conteo diario de asignaciones recibidas por el analista autenticado.
--
-- La fuente es el ledger inmutable `crm.lead_asignaciones`, no la cartera
-- actual: un lead transferido, descartado o convertido sigue contando el día
-- en que entró a responsabilidad del analista. El payload no contiene PII.

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if pg_catalog.to_regclass('crm.lead_asignaciones') is null
     or pg_catalog.to_regclass('crm.equipo') is null
     or pg_catalog.to_regclass('public.perfiles') is null then
    raise exception 'Faltan dependencias del reporte de leads recibidos';
  end if;

  -- La consulta filtra por igualdad de analista y rango de asignación. Se
  -- reutiliza el índice canónico del ledger; crear otro sería peso duplicado.
  if not exists (
    select 1
    from pg_catalog.pg_index indice
    join pg_catalog.pg_class clase on clase.oid = indice.indexrelid
    join pg_catalog.pg_namespace espacio on espacio.oid = clase.relnamespace
    where espacio.nspname = 'crm'
      and clase.relname = 'lead_asignaciones_analista_fecha_idx'
      and indice.indrelid = 'crm.lead_asignaciones'::pg_catalog.regclass
      and indice.indisvalid
      and indice.indisready
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 1, true) = 'analista_id'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 2, true) = 'asignado_en'
      and pg_catalog.pg_get_indexdef(indice.indexrelid)
          like '%(analista_id, asignado_en DESC)%'
  ) then
    raise exception 'Falta el índice canónico lead_asignaciones_analista_fecha_idx';
  end if;
end;
$preflight$;

create or replace function crm.leads_recibidos_analista_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_inicio timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
begin
  -- El gate precede a la validación del período para que los errores de fecha
  -- no funcionen como oráculo para actores sin acceso al módulo comercial.
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'vendedor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un analista activo puede consultar sus leads recibidos'
      using errcode = '42501';
  end if;

  if p_desde is null or p_hasta is null then
    raise exception 'Indica ambas fechas del reporte'
      using errcode = '22023';
  end if;
  if p_desde > p_hasta then
    raise exception 'La fecha inicial no puede ser posterior a la fecha final'
      using errcode = '22023';
  end if;
  if p_hasta > v_hoy then
    raise exception 'El reporte no admite fechas futuras'
      using errcode = '22023';
  end if;
  if p_hasta - p_desde > 365 then
    raise exception 'El rango máximo del reporte es de 366 días'
      using errcode = '22023';
  end if;

  v_inicio := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with dias_calendario as materialized (
    select (p_desde + serie.n)::date as fecha
    from pg_catalog.generate_series(0, p_hasta - p_desde) as serie(n)
  ),
  recibidos as materialized (
    select
      (asignacion.asignado_en at time zone 'America/Lima')::date as fecha,
      pg_catalog.count(*)::integer as total,
      pg_catalog.count(*) filter (where asignacion.aproximado)::integer as aproximados
    from crm.lead_asignaciones asignacion
    where asignacion.analista_id = v_actor
      and asignacion.asignado_en >= v_inicio
      and asignacion.asignado_en < v_fin
      -- Una devolución inmediata a la misma bandeja anula esa carga para los
      -- reportes operativos; el episodio permanece intacto en el ledger.
      and (
        asignacion.motivo_cierre is distinct from 'parqueado'
        -- NULL/NULL significa que el episodio quedó sin bandeja conocida, no
        -- que haya vuelto a una misma bandeja identificada.
        or asignacion.supervisor_origen_id is null
        or asignacion.supervisor_destino_id is distinct from asignacion.supervisor_origen_id
      )
    group by (asignacion.asignado_en at time zone 'America/Lima')::date
  ),
  detalle as materialized (
    select
      dia.fecha,
      coalesce(recibidos.total, 0)::integer as total,
      coalesce(recibidos.aproximados, 0)::integer as aproximados
    from dias_calendario dia
    left join recibidos on recibidos.fecha = dia.fecha
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'periodo', pg_catalog.jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'dias', p_hasta - p_desde + 1,
      'zona', 'America/Lima'
    ),
    'total', coalesce((select pg_catalog.sum(d.total) from detalle d), 0),
    'aproximados', coalesce((select pg_catalog.sum(d.aproximados) from detalle d), 0),
    'dias', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'fecha', d.fecha,
          'total', d.total,
          'aproximados', d.aproximados
        )
        order by d.fecha
      )
      from detalle d
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.leads_recibidos_analista_fn(date, date) is
  'Conteo diario de episodios que entraron a responsabilidad del analista autenticado, por asignado_en en America/Lima. Excluye devoluciones inmediatas a la misma bandeja y no expone PII.';

revoke all on function crm.leads_recibidos_analista_fn(date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.leads_recibidos_analista_fn(date, date)
  to authenticated;

do $postflight$
declare
  v_rpc regprocedure := pg_catalog.to_regprocedure(
    'crm.leads_recibidos_analista_fn(date,date)'
  );
begin
  if v_rpc is null then
    raise exception 'POSTFLIGHT: falta crm.leads_recibidos_analista_fn(date,date)';
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
    raise exception 'POSTFLIGHT: ACL inesperada en el reporte de leads recibidos';
  end if;
end;
$postflight$;

commit;
