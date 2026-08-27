begin;

-- Rollback funcional de 20260825005519.
-- Restaura la firma de cinco parámetros de 20260824231133. No borra ni
-- reescribe actividades o clasificaciones ya persistidas; solo devuelve el
-- comportamiento compatible anterior para cierres futuros.

do $preflight$
declare
  v_def text;
begin
  if to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)') is null then
    raise exception 'No existe la firma clasificada que este rollback revierte';
  end if;
  if to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb)') is not null then
    raise exception 'La firma anterior ya existe: revisar antes de aplicar el rollback';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)'::regprocedure
  );
  if v_def not ilike '%insert into crm.actividades_cliente%'
     or v_def not ilike '%then p_resultado_reunion else null end%'
     or v_def not ilike '%then p_motivo_no_realizada else null end%'
     or v_def not ilike '%private.crear_siguiente_tarea(%' then
    raise exception 'crm.cerrar_tarea clasificada cambió desde el cuerpo revisado';
  end if;
end;
$preflight$;

drop function crm.cerrar_tarea(uuid, text, text, text, jsonb, text, text);

create function crm.cerrar_tarea(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_tipo text default null,
  p_resultado_detalle text default null,
  p_siguiente jsonb default null
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
    raise exception 'Tipo de resultado inválido';
  end if;
  if v_tarea.tipo = 'llamada' and p_estado = 'completada'
     and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contestó / no contestó)';
  end if;

  if p_resultado_tipo is not null and v_tarea.lead_id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (v_tarea.lead_id, p_resultado_tipo,
      nullif(btrim(coalesce(p_resultado_detalle, '')), ''), v_uid)
    returning id into v_act_id;
  elsif p_resultado_tipo is not null and v_tarea.perfil_id is not null then
    insert into crm.actividades_cliente (
      cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por
    ) values (
      v_tarea.perfil_id, v_tarea.vendedor_id, v_tarea.id, p_resultado_tipo,
      nullif(btrim(coalesce(p_resultado_detalle, '')), ''), v_uid
    ) returning id into v_act_cliente_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas set
    estado = p_estado,
    resultado_actividad_id = v_act_id,
    resultado_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'completada'
        then 'sin_clasificar' else null end,
    motivo_no_realizada = case
      when v_tarea.tipo = 'reunion' and p_estado = 'no_show'
        then 'cliente_no_asistio'
      when v_tarea.tipo = 'reunion' and p_estado = 'cancelada'
        then 'otro' else null end,
    detalle_cierre_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'cancelada' then coalesce(
        nullif(btrim(coalesce(p_resultado_detalle, '')), ''),
        'Compatibilidad: motivo no estructurado por cliente anterior')
      when v_tarea.tipo = 'reunion'
        then nullif(btrim(coalesce(p_resultado_detalle, '')), '')
      else null end
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

comment on function crm.cerrar_tarea(uuid,text,text,text,jsonb) is
  'Rollback de 20260825005519: cierre atómico compatible de cinco parámetros; las reuniones futuras vuelven a clasificación genérica.';

revoke all on function crm.cerrar_tarea(uuid,text,text,text,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.cerrar_tarea(uuid,text,text,text,jsonb)
  to authenticated, service_role;

do $postflight$
declare
  v_def text;
begin
  if to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)') is not null
     or to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb)') is null then
    raise exception 'El rollback no dejó una única firma compatible';
  end if;
  if pg_catalog.has_function_privilege(
       'anon', 'crm.cerrar_tarea(uuid,text,text,text,jsonb)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cerrar_tarea(uuid,text,text,text,jsonb)', 'EXECUTE'
     ) then
    raise exception 'Permisos inesperados tras el rollback';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.cerrar_tarea(uuid,text,text,text,jsonb)'::regprocedure
  );
  if v_def not ilike '%insert into crm.actividades_cliente%'
     or v_def not ilike '%then ''sin_clasificar'' else null end%'
     or v_def not ilike '%then ''otro'' else null end%'
     or v_def not ilike '%private.crear_siguiente_tarea(%' then
    raise exception 'El rollback perdió historial, compatibilidad o siguiente acción';
  end if;
end;
$postflight$;

commit;
