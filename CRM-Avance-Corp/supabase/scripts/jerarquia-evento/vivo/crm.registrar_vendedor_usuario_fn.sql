CREATE OR REPLACE FUNCTION crm.registrar_vendedor_usuario_fn(p_perfil_id uuid, p_correo text, p_nombre_completo text, p_tipo_documento text, p_documento text, p_telefono text, p_whatsapp text, p_cargo text, p_supervisor_id uuid, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_correo text := lower(pg_catalog.btrim(coalesce(p_correo, '')));
  v_tipo text := upper(pg_catalog.btrim(coalesce(p_tipo_documento, '')));
  v_documento text := upper(pg_catalog.btrim(coalesce(p_documento, '')));
  v_auth_correo text;
  v_origen_app text;
  v_perfil public.perfiles%rowtype;
  v_equipo crm.equipo%rowtype;
  v_perfil_nuevo boolean := false;
  v_eventos bigint;
  v_evento_otro_objetivo boolean;
  v_tiene_rol boolean;
  v_tiene_jerarquia boolean;
  v_tiene_activacion boolean;
  v_version timestamptz;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message =
      'Solo Gerencia puede completar altas de vendedores CRM';
  end if;
  if p_perfil_id is null or p_supervisor_id is null
     or p_idempotencia is null then
    raise exception 'Perfil, Supervisor e idempotencia son requeridos';
  end if;
  if v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     or length(v_correo) > 254 then
    raise exception 'Correo invalido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  -- La autoridad se revalida dentro del candado: un actor revocado mientras
  -- esperaba no puede continuar el alta con una decisión obsoleta.
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message =
      'Solo Gerencia puede completar altas de vendedores CRM';
  end if;

  select
    pg_catalog.count(*),
    coalesce(
      pg_catalog.bool_or(ue.objetivo_id is distinct from p_perfil_id), false
    ),
    coalesce(pg_catalog.bool_or(ue.accion = 'rol_asignado'), false),
    coalesce(
      pg_catalog.bool_or(ue.accion = 'jerarquia_actualizada'), false
    ),
    coalesce(
      pg_catalog.bool_or(ue.accion = 'membresia_activada'), false
    )
    into v_eventos, v_evento_otro_objetivo, v_tiene_rol,
         v_tiene_jerarquia, v_tiene_activacion
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.idempotencia = p_idempotencia;
  if v_eventos > 0 then
    if v_evento_otro_objetivo or not v_tiene_rol
       or not v_tiene_jerarquia or not v_tiene_activacion then
      raise exception 'La idempotencia ya fue usada por otra operacion';
    end if;

    select p.* into v_perfil
    from public.perfiles p where p.id = p_perfil_id;
    select lower(u.email), u.raw_app_meta_data->>'origen_app'
      into v_auth_correo, v_origen_app
    from auth.users u where u.id = p_perfil_id;
    select e.* into v_equipo
    from crm.equipo e where e.perfil_id = p_perfil_id;
    if not found
       or v_perfil.id is null
       or v_perfil.activo is not true
       or v_perfil.rol <> 'comercial'
       or lower(v_perfil.correo) is distinct from v_correo
       or upper(pg_catalog.btrim(v_perfil.tipo_documento)) is distinct from v_tipo
       or upper(pg_catalog.btrim(v_perfil.dni)) is distinct from v_documento
       or v_auth_correo is distinct from v_correo
       or v_origen_app is distinct from 'crm'
       or v_equipo.rol_crm <> 'vendedor'
       or v_equipo.activo is not true
       or v_equipo.supervisor_id is distinct from p_supervisor_id then
      raise exception 'La operacion idempotente perdio su membresia';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'estado', 'activo',
      'rol_crm', 'vendedor', 'supervisor_id', p_supervisor_id,
      'activo_crm', true, 'version_equipo', v_equipo.actualizado_en,
      'idempotente', true
    );
  end if;

  perform private.validar_datos_usuario_crm(
    p_nombre_completo, v_tipo, v_documento,
    nullif(pg_catalog.btrim(p_telefono), ''),
    nullif(pg_catalog.btrim(p_whatsapp), ''),
    nullif(pg_catalog.btrim(p_cargo), '')
  );

  select lower(u.email), u.raw_app_meta_data->>'origen_app'
    into v_auth_correo, v_origen_app
  from auth.users u where u.id = p_perfil_id;
  if not found or v_auth_correo is distinct from v_correo then
    raise exception 'La identidad Auth no coincide con el vendedor';
  end if;

  select p.* into v_perfil
  from public.perfiles p
  where p.id = p_perfil_id
  for update;

  if found then
    if lower(v_perfil.correo) is distinct from v_correo then
      raise exception 'La identidad Auth ya pertenece a otro perfil Portal';
    end if;
    -- Una identidad compartida con el Portal conserva exactamente el flujo y
    -- credenciales previos. Esta frontera solo completa cuentas cuyo origen
    -- servidor y perfil prueban que nacieron exclusivamente en el CRM.
    if v_perfil.rol <> 'comercial' or v_origen_app is distinct from 'crm' then
      return pg_catalog.jsonb_build_object(
        'perfil_id', p_perfil_id, 'estado', 'candidato_existente',
        'idempotente', true
      );
    end if;
    if v_perfil.activo is not true then
      raise exception 'El perfil esta suspendido en Portal';
    end if;
    if upper(pg_catalog.btrim(v_perfil.tipo_documento)) is distinct from v_tipo
       or upper(pg_catalog.btrim(v_perfil.dni)) is distinct from v_documento then
      raise exception 'El documento no coincide con la identidad CRM existente';
    end if;
  else
    if v_origen_app is distinct from 'crm' then
      raise exception 'La identidad nueva no pertenece exclusivamente al CRM';
    end if;
    insert into public.perfiles (
      id, nombre_completo, tipo_documento, dni, correo,
      telefono, whatsapp, cargo, rol, activo, debe_cambiar_password,
      creado_por, creado_en, actualizado_en
    ) values (
      p_perfil_id,
      pg_catalog.btrim(p_nombre_completo),
      v_tipo,
      v_documento,
      v_correo,
      nullif(pg_catalog.btrim(p_telefono), ''),
      nullif(pg_catalog.btrim(p_whatsapp), ''),
      nullif(pg_catalog.btrim(p_cargo), ''),
      'comercial', true, false,
      v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
    );
    v_perfil_nuevo := true;
  end if;

  select e.* into v_equipo
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  if found then
    if v_equipo.rol_crm = 'vendedor'
       and v_equipo.activo is true
       and v_equipo.supervisor_id is not distinct from p_supervisor_id then
      return pg_catalog.jsonb_build_object(
        'perfil_id', p_perfil_id, 'estado', 'candidato_existente',
        'rol_crm', v_equipo.rol_crm,
        'supervisor_id', v_equipo.supervisor_id,
        'activo_crm', v_equipo.activo,
        'version_equipo', v_equipo.actualizado_en,
        'idempotente', true
      );
    end if;
    raise exception 'El usuario ya tiene una membresia CRM; usa sus controles de administracion';
  end if;

  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, 'vendedor', p_supervisor_id
  );

  insert into crm.equipo (
    perfil_id, rol_crm, supervisor_id, activo,
    creado_por, creado_en, actualizado_en
  ) values (
    p_perfil_id, 'vendedor', p_supervisor_id, true,
    v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  if v_perfil_nuevo then
    perform private.registrar_evento_usuario(
      'candidato_creado', p_perfil_id,
      pg_catalog.jsonb_build_object('estado', 'activo'),
      p_idempotencia
    );
  end if;
  perform private.registrar_evento_usuario(
    'rol_asignado', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'rol_anterior', null, 'rol_nuevo', 'vendedor'
    ),
    p_idempotencia
  );
  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', null, 'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );
  perform private.registrar_evento_usuario(
    'membresia_activada', p_perfil_id,
    pg_catalog.jsonb_build_object('activo', true),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'estado', 'activo',
    'rol_crm', 'vendedor', 'supervisor_id', p_supervisor_id,
    'activo_crm', true, 'version_equipo', v_version,
    'idempotente', false
  );
end;
$function$
