CREATE OR REPLACE FUNCTION crm.agenda_reparto_diaria(p_desde date DEFAULT ((statement_timestamp() AT TIME ZONE 'America/Lima'::text))::date, p_dias integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload jsonb;
begin
  if p_desde is null or p_dias is null or p_dias < 1 or p_dias > 14 then
    raise exception 'La agenda requiere una fecha y entre 1 y 14 días'
      using errcode = '22023';
  end if;

  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver la agenda de reparto'
      using errcode = '42501';
  end if;

  with
  dias as materialized (
    select serie::date as fecha
    from pg_catalog.generate_series(
      p_desde::timestamp,
      (p_desde + (p_dias - 1))::timestamp,
      interval '1 day'
    ) as serie
  ),
  destinos as materialized (
    select
      destino.supervisor_id,
      destino.alias,
      destino.orden,
      perfil.nombre_completo
    from private.agenda_reparto_destinos destino
    join crm.equipo equipo on equipo.perfil_id = destino.supervisor_id
    join public.perfiles perfil on perfil.id = destino.supervisor_id
    where equipo.rol_crm = 'supervisor'
      and equipo.activo = true
      and perfil.activo = true
  ),
  movimientos as materialized (
    select
      (actividad.creado_en at time zone 'America/Lima')::date as fecha,
      lead.origen,
      coalesce(actividad.metadata ->> 'supervisor_nuevo', '') as supervisor_id,
      perfil.nombre_completo as supervisor_nombre,
      destino.alias as supervisor_alias,
      pg_catalog.count(*)::integer as derivados
    from crm.actividades actividad
    join crm.leads lead on lead.id = actividad.lead_id
    left join public.perfiles perfil
      on perfil.id::text = actividad.metadata ->> 'supervisor_nuevo'
    left join private.agenda_reparto_destinos destino
      on destino.supervisor_id::text = actividad.metadata ->> 'supervisor_nuevo'
    where actividad.tipo = 'reasignacion'
      and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
      and lead.origen in ('landing', 'formulario')
      and actividad.creado_en >= (p_desde::timestamp at time zone 'America/Lima')
      and actividad.creado_en < ((p_desde + p_dias)::timestamp at time zone 'America/Lima')
    group by
      (actividad.creado_en at time zone 'America/Lima')::date,
      lead.origen,
      coalesce(actividad.metadata ->> 'supervisor_nuevo', ''),
      perfil.nombre_completo,
      destino.alias
  ),
  agenda as materialized (
    select
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias as supervisor_alias,
      destino.nombre_completo as supervisor_nombre,
      coalesce(pg_catalog.sum(movimiento.derivados), 0)::integer as derivados,
      coalesce(
        pg_catalog.sum(movimiento.derivados) filter (
          where movimiento.supervisor_id is distinct from plan.supervisor_id::text
        ),
        0
      )::integer as fuera_turno,
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'supervisor_id', nullif(movimiento.supervisor_id, ''),
            'supervisor_nombre', coalesce(
              movimiento.supervisor_nombre,
              'Supervisor no disponible'
            ),
            'supervisor_alias', movimiento.supervisor_alias,
            'derivados', movimiento.derivados,
            'coincide_turno', coalesce(
              movimiento.supervisor_id = plan.supervisor_id::text,
              false
            )
          ) order by coalesce(
            movimiento.supervisor_alias,
            movimiento.supervisor_nombre,
            movimiento.supervisor_id
          )
        ) filter (where movimiento.derivados is not null),
        '[]'::jsonb
      ) as entregas
    from dias dia
    cross join (values ('landing'::text, 1), ('formulario'::text, 2)) as origen(origen, orden)
    left join private.agenda_reparto_diaria plan
      on plan.fecha = dia.fecha
      and plan.origen = origen.origen
    left join destinos destino
      on destino.supervisor_id = plan.supervisor_id
    left join movimientos movimiento
      on movimiento.fecha = dia.fecha
      and movimiento.origen = origen.origen
    group by
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias,
      destino.nombre_completo
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'fecha_desde', p_desde,
    'destinos', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'perfil_id', destino.supervisor_id,
          'nombre', destino.nombre_completo,
          'alias', destino.alias
        ) order by destino.orden
      )
      from destinos destino
    ), '[]'::jsonb),
    'dias', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'fecha', dia.fecha,
          'asignaciones', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'origen', fila.origen,
                'supervisor_id', fila.supervisor_id,
                'supervisor_nombre', fila.supervisor_nombre,
                'supervisor_alias', fila.supervisor_alias,
                'derivados', fila.derivados,
                'fuera_turno', fila.fuera_turno,
                'entregas', fila.entregas
              ) order by fila.orden
            )
            from agenda fila
            where fila.fecha = dia.fecha
          ), '[]'::jsonb)
        ) order by dia.fecha
      )
      from dias dia
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$

;
