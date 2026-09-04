CREATE OR REPLACE FUNCTION crm.derivar_leads_equipo_fn(p_lead_ids uuid[], p_asesor_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_total integer;
  v_distintos integer;
  v_destinos_solicitados integer;
  v_destinos_validos integer := 0;
  v_leads_encontrados integer := 0;
  v_indice integer;
  v_asesor record;
  v_lead record;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede derivar leads de su equipo'
      using errcode = '42501';
  end if;

  -- Los cambios canónicos de jerarquía/offboarding toman esta misma clave en
  -- modo exclusivo antes de bloquear equipo y luego leads. Aquí basta modo
  -- compartido: varias derivaciones pueden convivir, pero ninguna se cruza
  -- con una baja/traslado y se evita el ciclo equipo → lead / lead → equipo.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  if p_lead_ids is null
     or pg_catalog.array_length(p_lead_ids, 1) is null
     or pg_catalog.array_ndims(p_lead_ids) <> 1
     or pg_catalog.array_lower(p_lead_ids, 1) is distinct from 1
     or pg_catalog.array_length(p_lead_ids, 1) < 1
     or pg_catalog.array_length(p_lead_ids, 1) > 100
     or pg_catalog.array_position(p_lead_ids, null) is not null then
    raise exception 'Selecciona entre 1 y 100 leads válidos para derivar'
      using errcode = '22023';
  end if;

  if p_asesor_ids is null
     or pg_catalog.array_ndims(p_asesor_ids) <> 1
     or pg_catalog.array_lower(p_asesor_ids, 1) is distinct from 1
     or pg_catalog.array_length(p_asesor_ids, 1) is distinct from pg_catalog.array_length(p_lead_ids, 1)
     or pg_catalog.array_position(p_asesor_ids, null) is not null then
    raise exception 'Cada lead debe tener exactamente un asesor destino'
      using errcode = '22023';
  end if;

  v_total := pg_catalog.array_length(p_lead_ids, 1);
  select pg_catalog.count(*)::integer
    into v_distintos
  from (
    select distinct lead_id
    from pg_catalog.unnest(p_lead_ids) as entrada(lead_id)
  ) distintos;
  if v_distintos <> v_total then
    raise exception 'Un mismo lead no se puede derivar dos veces en el mismo guardado'
      using errcode = '22023';
  end if;

  select pg_catalog.count(*)::integer
    into v_destinos_solicitados
  from (
    select distinct asesor_id
    from pg_catalog.unnest(p_asesor_ids) as entrada(asesor_id)
  ) destinos;

  -- Bloqueo determinista: dos supervisores no pueden ganar una carrera sobre
  -- el mismo lead ni dejar un borrador parcialmente aplicado.
  for v_lead in
    select
      l.id,
      l.vendedor_id,
      l.asignado_supervisor_id,
      l.activo,
      l.etapa,
      l.no_contactar
    from crm.leads l
    where l.id = any(p_lead_ids)
    order by l.id
    for update
  loop
    v_leads_encontrados := v_leads_encontrados + 1;
    if v_lead.vendedor_id is not null
       or v_lead.asignado_supervisor_id is distinct from v_actor
       or v_lead.activo is not true
       or v_lead.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
      raise exception 'El lead % ya no está disponible en tu bandeja', v_lead.id
        using errcode = 'P0001';
    end if;
    if v_lead.no_contactar is true then
      raise exception 'El lead % está marcado No Insista y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
  end loop;

  if v_leads_encontrados <> v_total then
    raise exception 'Uno de los leads seleccionados ya no existe'
      using errcode = 'P0001';
  end if;

  -- El precheck evita que un usuario sin rol use la RPC para bloquear filas
  -- ajenas. Esta segunda lectura sí bloquea y vuelve a validar al supervisor:
  -- Gerencia no puede desactivarlo mientras el guardado está en curso.
  perform 1
  from crm.equipo actor_equipo
  join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
  where actor_equipo.perfil_id = v_actor
    and actor_equipo.rol_crm = 'supervisor'
    and actor_equipo.activo = true
    and actor_perfil.activo = true
  for no key update of actor_equipo, actor_perfil;
  if not found then
    raise exception 'Tu acceso de supervisor cambió; recarga antes de derivar'
      using errcode = '42501';
  end if;

  -- Orden global de locks: leads → supervisor → asesores (igual que devolver).
  -- La pertenencia no es una foto optimista: bloqueamos, en orden
  -- determinista, tanto la membresía CRM como el perfil activo. Así Gerencia
  -- no puede mover/desactivar al asesor entre la validación y el UPDATE de los
  -- leads. El trigger de tenencia valida rol/activo, pero no supervisor_id.
  for v_asesor in
    select asesor_equipo.perfil_id
    from crm.equipo asesor_equipo
    join public.perfiles asesor_perfil on asesor_perfil.id = asesor_equipo.perfil_id
    where asesor_equipo.perfil_id = any(p_asesor_ids)
      and asesor_equipo.rol_crm = 'vendedor'
      and asesor_equipo.supervisor_id = v_actor
      and asesor_equipo.activo = true
      and asesor_perfil.activo = true
    order by asesor_equipo.perfil_id
    for no key update of asesor_equipo, asesor_perfil
  loop
    v_destinos_validos := v_destinos_validos + 1;
  end loop;

  if v_destinos_validos <> v_destinos_solicitados then
    raise exception 'Uno de los asesores destino ya no pertenece a tu equipo activo'
      using errcode = '42501';
  end if;

  for v_indice in 1..v_total loop
    update crm.leads
    set vendedor_id = p_asesor_ids[v_indice],
        asignado_supervisor_id = null
    where id = p_lead_ids[v_indice];
  end loop;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'derivados', v_total,
    'lead_ids', pg_catalog.to_jsonb(p_lead_ids)
  );
end;
$function$

