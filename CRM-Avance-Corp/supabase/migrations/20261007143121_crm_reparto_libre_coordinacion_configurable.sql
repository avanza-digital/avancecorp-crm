-- Reparto libre de Coordinación, gobernado por Gerencia.
-- Pedido de Miguel: permitirlo a todo el rol y ofrecer un botón de activación.
-- Arranca encendido por ese pedido. Apagarlo restaura el turno obligatorio.
-- Las RPC existentes conservan firmas, permisos, veto No Insista y auditoría.
begin;
set local lock_timeout = '5s';

do $preflight$
begin
  if md5(pg_get_functiondef('private.repartir_lead_implementacion(uuid,uuid)'::regprocedure))
       <> 'e549e5cf52d588c926a2eb3b466fc2cd'
     or md5(pg_get_functiondef('crm.agenda_reparto_diaria(date,integer)'::regprocedure))
       <> '164aed8ed9b1732624afa7e7dc87230c' then
    raise exception 'Las funciones de reparto cambiaron: revisar antes de instalar';
  end if;
end;
$preflight$;

create table crm.configuracion_reparto (
  id uuid primary key default gen_random_uuid(),
  singleton boolean not null default true unique check (singleton),
  coordinacion_libre boolean not null default false,
  revision integer not null default 1 check (revision > 0),
  actualizado_en timestamptz not null default statement_timestamp(),
  actualizado_por uuid references public.perfiles(id) on delete restrict
);
alter table crm.configuracion_reparto enable row level security;
alter table crm.configuracion_reparto force row level security;
revoke all on table crm.configuracion_reparto from public, anon, authenticated, service_role;
create trigger audit_configuracion_reparto
  after insert or update or delete on crm.configuracion_reparto
  for each row execute function private.log_audit_crm();
comment on table crm.configuracion_reparto is
  'Permiso global de reparto libre para Coordinación. Solo Gerencia lo modifica mediante RPC; sin acceso directo.';

insert into crm.configuracion_reparto (coordinacion_libre) values (true);

-- SECURITY DEFINER justificado: lee la configuración sin abrir la tabla a
-- ningún cliente. La identidad/rol se resuelve en el servidor y exige vigencia.
create function private.reparto_libre_habilitado()
returns boolean
language sql stable security definer set search_path = ''
as $function$
  select coalesce(
    private.es_superadmin_portal_activo()
    or (
      private.rol_crm((select auth.uid())) = 'coordinador'
      and (select c.coordinacion_libre from crm.configuracion_reparto c where c.singleton)
    ), false
  );
$function$;
revoke all on function private.reparto_libre_habilitado()
  from public, anon, authenticated, service_role;
comment on function private.reparto_libre_habilitado() is
  'Permiso efectivo para ignorar el turno: Superadmin activo o Coordinación activa con control encendido.';

-- SECURITY DEFINER: solo Gerencia activa puede leer/administrar este control.
create function private.configuracion_reparto()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_config crm.configuracion_reparto%rowtype;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede administrar el reparto libre';
  end if;
  select * into strict v_config from crm.configuracion_reparto where singleton;
  return pg_catalog.jsonb_build_object(
    'version', 1, 'coordinacion_libre', v_config.coordinacion_libre,
    'revision', v_config.revision, 'actualizado_en', v_config.actualizado_en
  );
end;
$function$;
revoke all on function private.configuracion_reparto()
  from public, anon, authenticated, service_role;

create function private.guardar_configuracion_reparto(p_libre boolean, p_revision integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_config crm.configuracion_reparto%rowtype;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede administrar el reparto libre';
  end if;
  if p_libre is null or p_revision is null or p_revision < 1 then
    raise exception 'Indica el estado y la revisión de la configuración' using errcode = '22023';
  end if;
  select * into strict v_config from crm.configuracion_reparto where singleton for update;
  if v_config.revision <> p_revision then
    raise exception 'Otra sesión cambió el reparto libre. Revisa el estado actual e inténtalo de nuevo.'
      using errcode = 'PT409';
  end if;
  if v_config.coordinacion_libre is distinct from p_libre then
    update crm.configuracion_reparto
    set coordinacion_libre = p_libre, revision = revision + 1,
        actualizado_en = pg_catalog.statement_timestamp(), actualizado_por = (select auth.uid())
    where singleton;
  end if;
  return private.configuracion_reparto();
end;
$function$;
revoke all on function private.guardar_configuracion_reparto(boolean,integer)
  from public, anon, authenticated, service_role;

-- Puertas sin lógica de dominio; los núcleos privados repiten la autorización.
create function crm.configuracion_reparto_fn()
returns jsonb
language sql stable security definer set search_path = ''
as $function$ select private.configuracion_reparto(); $function$;
create function crm.guardar_configuracion_reparto_fn(p_libre boolean, p_revision integer)
returns jsonb
language sql security definer set search_path = ''
as $function$ select private.guardar_configuracion_reparto(p_libre, p_revision); $function$;
revoke all on function crm.configuracion_reparto_fn(),
  crm.guardar_configuracion_reparto_fn(boolean,integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.configuracion_reparto_fn(),
  crm.guardar_configuracion_reparto_fn(boolean,integer) to authenticated;
comment on function private.configuracion_reparto() is 'Lectura del control de reparto, solo Gerencia activa.';
comment on function private.guardar_configuracion_reparto(boolean,integer) is 'Cambio auditado del control de reparto, solo Gerencia activa; revisión evita sobrescribir cambios concurrentes.';
comment on function crm.configuracion_reparto_fn() is 'Estado vigente del reparto libre de Coordinación, solo Gerencia activa.';
comment on function crm.guardar_configuracion_reparto_fn(boolean,integer) is 'Activa o desactiva el reparto libre de Coordinación, solo Gerencia activa.';

CREATE OR REPLACE FUNCTION private.repartir_lead_implementacion(p_lead uuid, p_supervisor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_reparto_libre boolean := private.reparto_libre_habilitado();
  v_hoy date := (pg_catalog.statement_timestamp() at time zone 'America/Lima')::date;
  v_lead crm.leads%rowtype;
  v_sup_nombre text;
  v_turno_supervisor uuid;
  v_turno_nombre text;
  v_origen_nombre text;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador', 'gerencia')
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads'
      using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios'
      using errcode = '22023';
  end if;

  select perfil.nombre_completo into v_sup_nombre
  from crm.equipo equipo
  join public.perfiles perfil on perfil.id = equipo.perfil_id
  where equipo.perfil_id = p_supervisor
    and equipo.rol_crm = 'supervisor'
    and equipo.activo = true
    and perfil.activo = true;

  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads lead
  where lead.id = p_lead
    and lead.activo = true
    and lead.vendedor_id is null
    and lead.asignado_supervisor_id is null
    and lead.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
  for update;

  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;

  -- F2.b (b2): el veto pertenece a la persona, no solo a esta fila de lead.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede repartir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  -- Gerencia puede habilitar el reparto libre para todo Coordinación.
  -- El permiso se verifica en cada llamada; el Superadmin conserva su excepción.
  -- La agenda y la trazabilidad siguen contando el destino real de cada entrega.
  if v_lead.origen in ('landing', 'formulario') then
    perform pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtextextended('agenda-reparto:' || v_hoy::text, 0)
    );

    select
      agenda.supervisor_id,
      coalesce(destino.alias, perfil.nombre_completo)
    into v_turno_supervisor, v_turno_nombre
    from private.agenda_reparto_diaria agenda
    left join private.agenda_reparto_destinos destino
      on destino.supervisor_id = agenda.supervisor_id
    left join public.perfiles perfil
      on perfil.id = agenda.supervisor_id
    where agenda.fecha = v_hoy
      and agenda.origen = v_lead.origen;

    v_origen_nombre := case v_lead.origen
      when 'landing' then 'Landing'
      else 'Formulario'
    end;

    if not found and not v_reparto_libre then
      raise exception 'Antes de repartir %, guarda el turno de hoy en «Coordinación → supervisores»',
        v_origen_nombre
        using errcode = '22023';
    end if;

    if not v_reparto_libre
       and p_supervisor is distinct from v_turno_supervisor then
      raise exception 'Según el turno de hoy, % corresponde a %. El destino no se cambió',
        v_origen_nombre,
        coalesce(v_turno_nombre, 'la supervisora programada')
        using errcode = '22023';
    end if;
  end if;

  update crm.leads
  set asignado_supervisor_id = p_supervisor
  where id = p_lead
    and activo = true
    and vendedor_id is null
    and asignado_supervisor_id is null;

  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return pg_catalog.jsonb_build_object(
    'lead_id', p_lead,
    'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre,
    'repartido_por', v_actor,
    'excepcion_turno', (
      v_reparto_libre
      and v_lead.origen in ('landing', 'formulario')
      and p_supervisor is distinct from v_turno_supervisor
    ),
    'repartido_en', pg_catalog.statement_timestamp()
  );
end;
$function$
;

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
    'reparto_libre', private.reparto_libre_habilitado(),
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

notify pgrst, 'reload schema';
commit;
