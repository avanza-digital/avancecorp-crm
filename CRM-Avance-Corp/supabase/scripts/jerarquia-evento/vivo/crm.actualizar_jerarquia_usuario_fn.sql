CREATE OR REPLACE FUNCTION crm.actualizar_jerarquia_usuario_fn(p_perfil_id uuid, p_supervisor_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_supervisor_anterior uuid;
  v_version timestamptz;
  v_evento_objetivo uuid;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede organizar la jerarquia CRM';
  end if;
  if p_version_equipo is null or p_idempotencia is null then
    raise exception 'Version e idempotencia requeridas';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select e.rol_crm, e.supervisor_id, e.actualizado_en
    into v_rol, v_supervisor_anterior, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia = p_idempotencia;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'supervisor_id', v_supervisor_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La jerarquia fue modificada por otra sesion';
  end if;

  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, v_rol, p_supervisor_id
  );

  if v_supervisor_anterior is not distinct from p_supervisor_id then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'supervisor_id', p_supervisor_id,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  update crm.equipo e
  set supervisor_id = p_supervisor_id
  where e.perfil_id = p_perfil_id;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', v_supervisor_anterior,
      'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'supervisor_id', p_supervisor_id,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$function$
