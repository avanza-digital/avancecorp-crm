begin;

-- =============================================================================
-- Reuniones de clientes: conservar clasificación estructurada en cerrar_tarea
-- =============================================================================
-- La migración 20260824231133 extendió crm.cerrar_tarea para escribir el
-- timeline postventa (crm.actividades_cliente), pero su compatibilidad inicial
-- degradaba toda reunión completada a `sin_clasificar` y toda cancelación a
-- `otro`. El frontend ya captura el resultado/motivo exactos. Esta versión los
-- recibe y persiste dentro de LA MISMA RPC que cierra la tarea, escribe el
-- historial y crea la siguiente acción, por lo que el conjunto sigue siendo
-- una única transacción PostgreSQL.

do $preflight$
declare
  v_def text;
begin
  if to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb)') is null then
    raise exception 'Falta crm.cerrar_tarea de 20260824231133';
  end if;
  if to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)') is not null then
    raise exception 'La firma clasificada de crm.cerrar_tarea ya existe: revisar antes de reaplicar';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.cerrar_tarea(uuid,text,text,text,jsonb)'::regprocedure
  );
  if v_def not ilike '%insert into crm.actividades_cliente%'
     or v_def not ilike '%then ''sin_clasificar''%'
     or v_def not ilike '%then ''otro'' else null end%' then
    raise exception 'crm.cerrar_tarea cambió desde el cuerpo revisado de 20260824231133';
  end if;
end;
$preflight$;

-- Se elimina la firma anterior para no dejar overloads (PostgREST no los
-- resuelve de forma segura). `p_siguiente` conserva la quinta posición y los
-- parámetros nuevos se agregan al final con default: el bundle anterior puede
-- seguir llamando los cinco argumentos mientras se publica el frontend nuevo.
drop function crm.cerrar_tarea(uuid, text, text, text, jsonb);

create function crm.cerrar_tarea(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_tipo text default null,
  p_resultado_detalle text default null,
  p_siguiente jsonb default null,
  p_resultado_reunion text default null,
  p_motivo_no_realizada text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_tarea crm.tareas%rowtype;
  v_act_id uuid;
  v_act_cliente_id uuid;
  v_sig_id uuid;
  v_retroceso text;
  v_detalle text := nullif(btrim(coalesce(p_resultado_detalle, '')), '');
begin
  if v_uid is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre inválido' using errcode = '22023';
  end if;

  select * into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id and t.activo and t.estado = 'pendiente'
    and (
      v_rol = 'gerencia'
      or t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (t.vendedor_id is null and t.asignado_supervisor_id in (
        select private.vendedor_ids_visibles(v_uid)
      ))
    )
  for update;
  if not found then
    raise exception 'Tarea no encontrada, cerrada o fuera de tu ámbito';
  end if;

  if v_tarea.lead_id is not null then
    perform 1 from crm.leads l where l.id = v_tarea.lead_id for no key update;
  else
    perform 1 from public.perfiles p where p.id = v_tarea.perfil_id for share;
  end if;

  if p_resultado_tipo is not null and p_resultado_tipo not in (
    'llamada_realizada','llamada_no_contestada','whatsapp_enviado',
    'whatsapp_recibido','reunion_realizada','nota'
  ) then
    raise exception 'Tipo de resultado inválido' using errcode = '22023';
  end if;
  if v_tarea.tipo = 'llamada' and p_estado = 'completada'
     and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contestó / no contestó)'
      using errcode = '22023';
  end if;

  -- Clasificación de reuniones: mismo contrato cerrado que cerrar_reunion. La
  -- validación ocurre ANTES del INSERT del timeline para que ningún rechazo
  -- deje una actividad huérfana, aun si la RPC se invoca fuera del frontend.
  if v_tarea.tipo <> 'reunion' then
    if p_resultado_reunion is not null or p_motivo_no_realizada is not null then
      raise exception 'Resultado y motivo de reunión solo aplican a reuniones'
        using errcode = '22023';
    end if;
  else
    if p_resultado_reunion is not null and p_resultado_reunion not in (
      'interesado','seguimiento','propuesta','inicia_registro','no_interesado'
    ) then
      raise exception 'Resultado comercial de reunión inválido' using errcode = '22023';
    end if;

    if p_estado = 'completada' then
      -- Compatibilidad de despliegue: el bundle anterior todavía llama los
      -- cinco parámetros. Solo ese payload ausente degrada a sin_clasificar;
      -- el frontend nuevo siempre envía el valor capturado.
      p_resultado_reunion := coalesce(p_resultado_reunion, 'sin_clasificar');
      p_motivo_no_realizada := null;
    elsif p_estado = 'no_show' then
      p_resultado_reunion := null;
      p_motivo_no_realizada := 'cliente_no_asistio';
    elsif p_estado = 'cancelada' then
      p_resultado_reunion := null;
      if p_motivo_no_realizada is null then
        -- Misma ventana de compatibilidad para el bundle anterior: evita que
        -- una publicación escalonada bloquee la agenda, sin inventar uno de
        -- los motivos comerciales específicos.
        p_motivo_no_realizada := 'otro';
        v_detalle := coalesce(
          v_detalle,
          'Compatibilidad: motivo no estructurado por cliente anterior'
        );
      elsif p_motivo_no_realizada not in ('cancelada_cliente','cancelada_empresa','otro') then
        raise exception 'Registra el motivo de cancelación' using errcode = '22023';
      end if;
      if p_motivo_no_realizada = 'otro' and v_detalle is null then
        raise exception 'Describe el otro motivo de cancelación' using errcode = '22023';
      end if;
    end if;
  end if;

  if p_resultado_tipo is not null and v_tarea.lead_id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (v_tarea.lead_id, p_resultado_tipo, v_detalle, v_uid)
    returning id into v_act_id;
  elsif p_resultado_tipo is not null and v_tarea.perfil_id is not null then
    insert into crm.actividades_cliente (
      cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por
    ) values (
      v_tarea.perfil_id, v_tarea.vendedor_id, v_tarea.id, p_resultado_tipo,
      v_detalle, v_uid
    ) returning id into v_act_cliente_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas set
    estado = p_estado,
    resultado_actividad_id = v_act_id,
    resultado_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'completada'
        then p_resultado_reunion else null end,
    motivo_no_realizada = case
      when v_tarea.tipo = 'reunion' and p_estado in ('no_show','cancelada')
        then p_motivo_no_realizada else null end,
    detalle_cierre_reunion = case
      when v_tarea.tipo = 'reunion' then v_detalle else null end
  where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea, p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );
  if p_estado = 'cancelada' and v_tarea.tipo = 'reunion'
     and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(
      v_tarea.lead_id, p_tarea_id, v_uid
    );
  end if;

  return jsonb_build_object(
    'ok', true, 'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'actividad_cliente_id', v_act_cliente_id,
    'siguiente_id', v_sig_id, 'retroceso', v_retroceso
  );
end;
$function$;

comment on function crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text) is
  'Cierra una tarea, escribe su resultado en el timeline correspondiente y crea la siguiente acción en una sola transacción. Para reuniones conserva resultado_reunion o motivo_no_realizada; p_siguiente mantiene la quinta posición por compatibilidad.';

revoke all on function crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)
  to authenticated, service_role;

do $postflight$
declare
  v_def text;
begin
  if to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb)') is not null
     or to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)') is null then
    raise exception 'La sustitución de crm.cerrar_tarea no quedó unívoca';
  end if;
  if pg_catalog.has_function_privilege(
       'anon', 'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)', 'EXECUTE'
     ) then
    raise exception 'Permisos inesperados en crm.cerrar_tarea clasificada';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)'::regprocedure
  );
  if v_def not ilike '%insert into crm.actividades_cliente%'
     or v_def not ilike '%then p_resultado_reunion else null end%'
     or v_def not ilike '%then p_motivo_no_realizada else null end%'
     or v_def not ilike '%private.crear_siguiente_tarea(%' then
    raise exception 'El cierre clasificado perdió historial, clasificación o siguiente acción';
  end if;
end;
$postflight$;

commit;
