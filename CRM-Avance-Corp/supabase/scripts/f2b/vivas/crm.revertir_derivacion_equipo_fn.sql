CREATE OR REPLACE FUNCTION crm.revertir_derivacion_equipo_fn(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_inicio_hoy timestamptz := v_hoy::timestamp at time zone 'America/Lima';
  v_fin_hoy timestamptz := (v_hoy + 1)::timestamp at time zone 'America/Lima';
  v_lead crm.leads%rowtype;
  v_episodio crm.lead_asignaciones%rowtype;
  v_asesor_bloqueado uuid;
begin
  if p_lead_id is null then
    raise exception 'Indica el lead que deseas devolver'
      using errcode = '22023';
  end if;

  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede devolver derivaciones de su equipo'
      using errcode = '42501';
  end if;

  -- Interlock compartido con la jerarquía: offboarding usa la misma clave en
  -- exclusivo antes de tocar equipo/leads. Debe ocurrir antes del row lock.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select l.*
    into v_lead
  from crm.leads l
  where l.id = p_lead_id
  for update;
  if not found then
    raise exception 'El lead ya no está disponible'
      using errcode = 'P0001';
  end if;

  -- Revalida bajo lock el rol que pasó el precheck. Esto impide completar la
  -- devolución si Gerencia desactivó al supervisor mientras esperaba el lead.
  perform 1
  from crm.equipo actor_equipo
  join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
  where actor_equipo.perfil_id = v_actor
    and actor_equipo.rol_crm = 'supervisor'
    and actor_equipo.activo = true
    and actor_perfil.activo = true
  for no key update of actor_equipo, actor_perfil;
  if not found then
    raise exception 'Tu acceso de supervisor cambió; recarga antes de devolver'
      using errcode = '42501';
  end if;

  -- Mismo orden que el guardado masivo: lead → supervisor → asesor. La
  -- membresía y los perfiles quedan estables hasta terminar la devolución.
  select asesor_equipo.perfil_id
    into v_asesor_bloqueado
  from crm.equipo asesor_equipo
  join public.perfiles asesor_perfil on asesor_perfil.id = asesor_equipo.perfil_id
  where asesor_equipo.perfil_id = v_lead.vendedor_id
    and asesor_equipo.rol_crm = 'vendedor'
    and asesor_equipo.supervisor_id = v_actor
    and asesor_equipo.activo = true
    and asesor_perfil.activo = true
  for no key update of asesor_equipo, asesor_perfil;

  if not found then
    raise exception 'Solo puedes devolver una derivación vigente de hoy hecha a un asesor de tu equipo'
      using errcode = 'P0001';
  end if;

  select la.*
    into v_episodio
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id
    and la.analista_id = v_lead.vendedor_id
    and la.asignado_por = v_actor
    and la.supervisor_origen_id = v_actor
    and la.asignado_en >= v_inicio_hoy
    and la.asignado_en < v_fin_hoy
    and la.finalizado_en is null
  order by la.asignado_en desc
  limit 1
  for update of la;

  if not found
     or v_lead.activo is not true
     or v_lead.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception 'Solo puedes devolver una derivación vigente de hoy hecha a un asesor de tu equipo'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from crm.actividades actividad
    where actividad.lead_id = p_lead_id
      and actividad.creado_por = v_episodio.analista_id
      and actividad.creado_en >= v_episodio.asignado_en
  ) or exists (
    select 1
    from crm.tareas tarea
    where tarea.lead_id = p_lead_id
      and tarea.creado_por = v_episodio.analista_id
      and tarea.creado_en >= v_episodio.asignado_en
  ) then
    raise exception 'No puedes devolver este lead porque el asesor ya registró gestión; su historial se conserva'
      using errcode = 'P0001';
  end if;

  perform pg_catalog.set_config('crm.reversion_derivacion_equipo', 'on', true);
  update crm.leads
  set vendedor_id = null,
      asignado_supervisor_id = v_actor
  where id = p_lead_id;
  perform pg_catalog.set_config('crm.reversion_derivacion_equipo', 'off', true);

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'lead_id', p_lead_id,
    'devuelto_a_bandeja', true
  );
end;
$function$

