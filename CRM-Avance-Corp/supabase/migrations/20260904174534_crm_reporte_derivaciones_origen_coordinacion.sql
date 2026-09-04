-- ============================================================================
-- CRM · Origen en el reporte diario de derivaciones para Coordinación
--
-- Extiende de forma aditiva el contrato ya publicado: conserva `analistas`
-- para que el frontend anterior siga funcionando y añade `entregas`, cuyo
-- grano es fecha + supervisor + analista + origen. El origen sale de la foto
-- inmutable del ledger, nunca de la ficha actual del lead.
-- ============================================================================

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if pg_catalog.to_regprocedure(
    'crm.reporte_derivaciones_coordinacion_fn(date,date)'
  ) is null then
    raise exception 'PREFLIGHT: falta crm.reporte_derivaciones_coordinacion_fn(date,date)';
  end if;

  if pg_catalog.to_regprocedure('private.puede_operar_reparto_crm()') is null then
    raise exception 'PREFLIGHT: falta la puerta canónica private.puede_operar_reparto_crm()';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_attribute atributo
    where atributo.attrelid = 'crm.lead_asignaciones'::regclass
      and atributo.attname = 'origen'
      and not atributo.attisdropped
      and atributo.attnotnull
  ) then
    raise exception 'PREFLIGHT: crm.lead_asignaciones.origen debe existir y ser NOT NULL';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_ledger
    where trigger_ledger.tgrelid = 'crm.lead_asignaciones'::pg_catalog.regclass
      and trigger_ledger.tgname = 'trg_lead_asignaciones_00_inmutables'
      and not trigger_ledger.tgisinternal
      and trigger_ledger.tgenabled <> 'D'
  ) then
    raise exception 'PREFLIGHT: el trigger inmutable del ledger no existe o está deshabilitado';
  end if;
end;
$preflight$;

-- El reporte de Coordinación parte del rango de fecha sin fijar un supervisor.
-- El índice previo del reporte de Supervisión empieza por supervisor_origen_id
-- y no sirve como acceso principal para esta consulta global.
create index if not exists lead_asignaciones_reporte_coordinacion_fecha_idx
  on crm.lead_asignaciones (asignado_en desc)
  include (
    analista_id,
    supervisor_origen_id,
    asignado_por,
    origen,
    motivo_cierre,
    supervisor_destino_id
  )
  where motivo_apertura in ('asignado', 'reasignado');

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
      supervisor_perfil.nombre_completo as supervisor_nombre,
      asignacion.origen
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
  conteos_analista as materialized (
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
  ),
  conteos_origen as materialized (
    select
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre,
      episodio.origen,
      pg_catalog.count(*)::integer as derivados
    from episodios_periodo episodio
    group by
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre,
      episodio.origen
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
            from conteos_analista conteo
            where conteo.fecha = dia.fecha
          ), 0),
          -- Compatibilidad con el consumidor publicado el 2026-09-04.
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
            from conteos_analista conteo
            where conteo.fecha = dia.fecha
          ), '[]'::jsonb),
          -- Nuevo contrato: el mismo total, abierto por el origen histórico.
          'entregas', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'analista_id', conteo.analista_id,
                'analista_nombre', conteo.analista_nombre,
                'supervisor_id', conteo.supervisor_id,
                'supervisor_nombre', conteo.supervisor_nombre,
                'origen', conteo.origen,
                'derivados', conteo.derivados
              )
              order by conteo.supervisor_nombre, conteo.analista_nombre,
                conteo.origen, conteo.supervisor_id, conteo.analista_id
            )
            from conteos_origen conteo
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
  'Reporte diario agregado sin PII de leads; incluye nombres e identificadores de colaboradores y el origen histórico. Fechas inclusivas de America/Lima; solo Coordinación o Gerencia activas.';

revoke all on function crm.reporte_derivaciones_coordinacion_fn(date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.reporte_derivaciones_coordinacion_fn(date, date)
  to authenticated;

do $postflight$
declare
  v_rpc regprocedure := pg_catalog.to_regprocedure(
    'crm.reporte_derivaciones_coordinacion_fn(date,date)'
  );
  v_definicion text;
begin
  if v_rpc is null then
    raise exception 'POSTFLIGHT: falta crm.reporte_derivaciones_coordinacion_fn(date,date)';
  end if;

  select pg_catalog.pg_get_functiondef(v_rpc)
    into v_definicion;

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

  if pg_catalog.strpos(v_definicion, '''entregas''') = 0
     or pg_catalog.strpos(v_definicion, 'asignacion.origen') = 0 then
    raise exception 'POSTFLIGHT: la RPC no conserva el desglose por origen del ledger';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index indice
    join pg_catalog.pg_class clase on clase.oid = indice.indexrelid
    join pg_catalog.pg_namespace espacio on espacio.oid = clase.relnamespace
    join pg_catalog.pg_am acceso on acceso.oid = clase.relam
    where espacio.nspname = 'crm'
      and clase.relname = 'lead_asignaciones_reporte_coordinacion_fecha_idx'
      and indice.indrelid = 'crm.lead_asignaciones'::pg_catalog.regclass
      and indice.indisvalid
      and indice.indisready
      and not indice.indisunique
      and acceso.amname = 'btree'
      and indice.indnkeyatts = 1
      and indice.indnatts = 7
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 1, true) = 'asignado_en'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 2, true) = 'analista_id'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 3, true) = 'supervisor_origen_id'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 4, true) = 'asignado_por'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 5, true) = 'origen'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 6, true) = 'motivo_cierre'
      and pg_catalog.pg_get_indexdef(indice.indexrelid, 7, true) = 'supervisor_destino_id'
      and pg_catalog.pg_get_indexdef(indice.indexrelid)
          like '%(asignado_en DESC) INCLUDE (analista_id, supervisor_origen_id, asignado_por, origen, motivo_cierre, supervisor_destino_id)%'
      and pg_catalog.pg_get_expr(indice.indpred, indice.indrelid)
          = '(motivo_apertura = ANY (ARRAY[''asignado''::text, ''reasignado''::text]))'
  ) then
    raise exception 'POSTFLIGHT: el índice de fecha falta, está inválido o no coincide con su contrato';
  end if;
end;
$postflight$;

commit;
