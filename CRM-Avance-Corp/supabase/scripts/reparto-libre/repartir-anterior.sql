CREATE OR REPLACE FUNCTION private.repartir_lead_implementacion(p_lead uuid, p_supervisor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_es_administrador boolean := coalesce(private.es_superadmin_portal_activo(), false);
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

  -- Turno obligatorio para Coordinación desde 2026-09-10. El navegador lo
  -- preselecciona, pero esta es la garantía real: también cubre pestañas
  -- antiguas, llamadas manuales y dos sesiones simultáneas. El Superadmin
  -- activo conserva la excepción operativa solicitada por negocio; su destino
  -- real sigue apareciendo en `fuera_turno` dentro de la agenda/reporte.
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

    if not found and not v_es_administrador then
      raise exception 'Antes de repartir %, guarda el turno de hoy en «Coordinación → supervisores»',
        v_origen_nombre
        using errcode = '22023';
    end if;

    if not v_es_administrador
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
      v_es_administrador
      and v_lead.origen in ('landing', 'formulario')
      and p_supervisor is distinct from v_turno_supervisor
    ),
    'repartido_en', pg_catalog.statement_timestamp()
  );
end;
$function$

;
