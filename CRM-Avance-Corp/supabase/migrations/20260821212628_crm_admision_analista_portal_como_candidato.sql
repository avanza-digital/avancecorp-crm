-- Un Analista existente del Portal es la identidad equivalente a Vendedor del
-- CRM. Antes solo el perfil neutro `comercial` podía entrar como candidato:
-- crear primero al analista en el Portal y luego intentar incorporarlo al CRM
-- terminaba en "La identidad Auth ya pertenece a otro perfil Portal".
--
-- La admisión queda deliberadamente limitada a `analista`: no convierte ni
-- expone como candidatos a clientes, administradores, directorio o superadmin.
-- Se conserva la separación de autoridades: Superadmin asigna el rol CRM y
-- Gerencia organiza la jerarquía y activa la membresía.

create or replace function crm.usuarios_administrables_fn(
  p_busqueda text default null,
  p_limite integer default 50,
  p_desde integer default 0
)
returns table (
  perfil_id uuid,
  nombre_completo text,
  tipo_documento text,
  documento text,
  correo text,
  telefono text,
  whatsapp text,
  cargo text,
  tipo_cuenta text,
  estado text,
  rol_crm text,
  supervisor_id uuid,
  activo_crm boolean,
  activo_portal boolean,
  version_perfil timestamptz,
  version_equipo timestamptz,
  total bigint
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_es_gerencia boolean := private.es_gerencia_crm_activa();
  v_es_superadmin boolean := private.es_superadmin_portal_activo();
  v_es_directorio boolean := private.es_directorio_crm_activo();
  v_solo_directorio boolean;
  v_q text := nullif(lower(pg_catalog.btrim(p_busqueda)), '');
begin
  if not private.puede_listar_usuarios_crm() then
    raise insufficient_privilege using message = 'No autorizado para listar usuarios CRM';
  end if;

  if p_limite not between 1 and 100 or p_desde not between 0 and 100000 then
    raise exception 'Paginacion invalida';
  end if;

  v_solo_directorio := v_es_directorio
    and not v_es_gerencia
    and not v_es_superadmin;

  return query
  select
    p.id,
    case when v_solo_directorio then
      'Usuario CRM · '
        || upper(pg_catalog.right(pg_catalog.replace(p.id::text, '-', ''), 8))
    else p.nombre_completo end,
    case when v_es_gerencia then p.tipo_documento end,
    case when v_es_gerencia then p.dni end,
    case when v_es_gerencia then p.correo end,
    case when v_es_gerencia then p.telefono end,
    case when v_es_gerencia then p.whatsapp end,
    case when v_es_gerencia then p.cargo end,
    case when p.rol = 'comercial' then 'solo_crm' else 'compartida_portal' end,
    case
      when p.activo is not true then 'suspendido_portal'
      when e.perfil_id is null then 'pendiente_rol'
      when e.activo is not true then 'inactivo_crm'
      else 'activo'
    end,
    e.rol_crm,
    case when v_es_gerencia then e.supervisor_id end,
    e.activo,
    p.activo,
    case when v_es_gerencia then p.actualizado_en end,
    case when not v_solo_directorio then e.actualizado_en end,
    count(*) over ()
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where (
    e.perfil_id is not null
    or p.rol in ('comercial', 'analista')
  )
    and (
      v_q is null
      or (
        not v_solo_directorio
        and lower(coalesce(p.nombre_completo, '')) like '%' || v_q || '%'
      )
      or (
        v_es_gerencia and (
          lower(coalesce(p.correo, '')) like '%' || v_q || '%'
          or lower(coalesce(p.dni, '')) like '%' || v_q || '%'
        )
      )
      or (
        v_solo_directorio and (
          lower(
            'Usuario CRM · '
              || upper(pg_catalog.right(
                pg_catalog.replace(p.id::text, '-', ''), 8
              ))
          ) like '%' || v_q || '%'
          or lower(coalesce(e.rol_crm, 'sin rol')) like '%' || v_q || '%'
          or lower(case
            when p.activo is not true then 'suspendido portal'
            when e.perfil_id is null then 'pendiente rol'
            when e.activo is not true then 'inactivo crm'
            else 'activo'
          end) like '%' || v_q || '%'
        )
      )
    )
  order by case when v_solo_directorio
    then p.id::text
    else lower(coalesce(p.nombre_completo, ''))
  end, p.id
  limit p_limite offset p_desde;
end;
$$;

comment on function crm.usuarios_administrables_fn(text, integer, integer) is
  'Roster CRM por autoridad: admite candidatos comerciales y Analistas Portal; Gerencia obtiene datos operativos; Superadmin identidad minima para roles; Directorio seudonimos/rol/estado sin PII, jerarquia ni versiones.';

create or replace function crm.buscar_candidato_por_correo_fn(p_correo text)
returns uuid
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_correo text := lower(pg_catalog.btrim(coalesce(p_correo, '')));
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede preparar altas CRM';
  end if;

  if v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Correo invalido';
  end if;

  select p.id into v_id
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where lower(p.correo) = v_correo
    and (p.rol in ('comercial', 'analista') or e.perfil_id is not null)
  limit 1;

  return v_id;
end;
$$;

create or replace function crm.actualizar_usuario_administrable_fn(
  p_perfil_id uuid,
  p_nombre_completo text,
  p_tipo_documento text,
  p_documento text,
  p_telefono text,
  p_whatsapp text,
  p_cargo text,
  p_version_perfil timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_tipo text := upper(pg_catalog.btrim(coalesce(p_tipo_documento, '')));
  v_documento text := upper(pg_catalog.btrim(coalesce(p_documento, '')));
  v_fila public.perfiles%rowtype;
  v_nueva_version timestamptz := pg_catalog.clock_timestamp();
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede editar usuarios CRM';
  end if;
  if p_idempotencia is null or p_version_perfil is null then
    raise exception 'Idempotencia y version de perfil requeridas';
  end if;

  perform private.validar_datos_usuario_crm(
    p_nombre_completo, v_tipo, v_documento,
    nullif(pg_catalog.btrim(p_telefono), ''),
    nullif(pg_catalog.btrim(p_whatsapp), ''),
    nullif(pg_catalog.btrim(p_cargo), '')
  );

  select p.* into v_fila
  from public.perfiles p
  where p.id = p_perfil_id
    and (
      p.rol in ('comercial', 'analista')
      or exists (select 1 from crm.equipo e where e.perfil_id = p.id)
    )
  for update;

  if not found then
    raise exception 'Usuario CRM no encontrado';
  end if;
  if exists (
    select 1 from crm.usuario_eventos ue
    where ue.actor_id = v_actor
      and ue.accion = 'perfil_actualizado'
      and ue.idempotencia = p_idempotencia
      and ue.objetivo_id = p_perfil_id
  ) then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'version_perfil', v_fila.actualizado_en,
      'idempotente', true
    );
  elsif exists (
    select 1 from crm.usuario_eventos ue
    where ue.actor_id = v_actor
      and ue.accion = 'perfil_actualizado'
      and ue.idempotencia = p_idempotencia
  ) then
    raise exception 'La idempotencia ya fue usada para otro usuario';
  end if;
  if v_fila.actualizado_en is distinct from p_version_perfil then
    raise exception using errcode = '40001', message = 'El usuario fue modificado por otra sesion';
  end if;

  update public.perfiles p
  set nombre_completo = pg_catalog.btrim(p_nombre_completo),
      tipo_documento = v_tipo,
      dni = v_documento,
      telefono = nullif(pg_catalog.btrim(p_telefono), ''),
      whatsapp = nullif(pg_catalog.btrim(p_whatsapp), ''),
      cargo = nullif(pg_catalog.btrim(p_cargo), ''),
      actualizado_en = v_nueva_version
  where p.id = p_perfil_id;

  select p.actualizado_en into v_nueva_version
  from public.perfiles p where p.id = p_perfil_id;

  perform private.registrar_evento_usuario(
    'perfil_actualizado', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'campos', pg_catalog.jsonb_build_array(
        'nombre_completo','tipo_documento','documento','telefono','whatsapp','cargo'
      )
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'version_perfil', v_nueva_version,
    'idempotente', false
  );
end;
$$;

create or replace function crm.asignar_rol_usuario_fn(
  p_perfil_id uuid,
  p_rol_crm text,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_perfil_rol text;
  v_perfil_activo boolean;
  v_tiene_equipo boolean := false;
  v_rol_anterior text;
  v_supervisor uuid;
  v_activo boolean;
  v_version timestamptz;
  v_accion text;
  v_evento_objetivo uuid;
begin
  if not private.es_superadmin_portal_activo() then
    raise insufficient_privilege using message = 'Solo Superadmin puede asignar roles CRM';
  end if;
  if p_rol_crm not in ('vendedor','supervisor','gerencia','coordinador','directorio') then
    raise exception 'Rol CRM no permitido';
  end if;
  if p_idempotencia is null then
    raise exception 'Idempotencia requerida';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select p.rol, p.activo into v_perfil_rol, v_perfil_activo
  from public.perfiles p where p.id = p_perfil_id
  for update;
  if not found or v_perfil_activo is not true then
    raise exception 'El perfil no existe o esta suspendido en Portal';
  end if;
  if v_perfil_rol = 'superadmin' and p_rol_crm <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede recibir el rol CRM Gerencia';
  end if;

  select true, e.rol_crm, e.supervisor_id, e.activo, e.actualizado_en
    into v_tiene_equipo, v_rol_anterior, v_supervisor, v_activo, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  v_tiene_equipo := found;

  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion in ('rol_asignado','rol_cambiado')
    and ue.idempotencia = p_idempotencia
  limit 1;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    if not v_tiene_equipo then
      raise exception 'La operacion idempotente perdio su membresia';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'rol_crm', v_rol_anterior,
      'activo_crm', v_activo, 'version_equipo', v_version,
      'idempotente', true
    );
  end if;

  if not v_tiene_equipo then
    if v_perfil_rol not in ('comercial', 'analista') then
      raise exception 'Solo un candidato CRM pendiente o Analista Portal puede recibir su primer rol';
    end if;
    if p_version_equipo is not null then
      raise exception using errcode = '40001', message = 'La membresia cambio antes de asignar el rol';
    end if;

    insert into crm.equipo (
      perfil_id, rol_crm, supervisor_id, activo,
      creado_por, creado_en, actualizado_en
    ) values (
      p_perfil_id, p_rol_crm, null, false,
      v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
    );
    v_accion := 'rol_asignado';
  else
    if p_version_equipo is null or v_version is distinct from p_version_equipo then
      raise exception using errcode = '40001', message = 'La membresia fue modificada por otra sesion';
    end if;
    if v_rol_anterior = p_rol_crm then
      return pg_catalog.jsonb_build_object(
        'perfil_id', p_perfil_id, 'rol_crm', v_rol_anterior,
        'activo_crm', v_activo, 'version_equipo', v_version,
        'idempotente', true
      );
    end if;

    if v_rol_anterior = 'gerencia' and v_activo is true
       and not exists (
         select 1 from crm.equipo e
         join public.perfiles p on p.id = e.perfil_id and p.activo is true
         where e.perfil_id <> p_perfil_id
           and e.rol_crm = 'gerencia' and e.activo is true
       ) then
      raise exception 'No se puede retirar el rol a la ultima Gerencia activa';
    end if;

    update crm.equipo e
    set rol_crm = p_rol_crm
    where e.perfil_id = p_perfil_id;
    v_accion := 'rol_cambiado';
  end if;

  select e.activo, e.actualizado_en into v_activo, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  perform private.registrar_evento_usuario(
    v_accion, p_perfil_id,
    pg_catalog.jsonb_build_object(
      'rol_anterior', v_rol_anterior,
      'rol_nuevo', p_rol_crm
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'rol_crm', p_rol_crm,
    'activo_crm', v_activo, 'version_equipo', v_version,
    'idempotente', false
  );
end;
$$;

comment on function crm.asignar_rol_usuario_fn(uuid, text, timestamptz, uuid) is
  'Unica escritura de rol_crm para la app. Solo Superadmin Portal. Admite candidato comercial o Analista Portal; no acepta ni cambia supervisor/activo y el alta nace inactiva.';
