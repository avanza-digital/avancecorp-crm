CREATE OR REPLACE FUNCTION crm.cerrar_tarea(p_tarea_id uuid, p_estado text, p_resultado_tipo text DEFAULT NULL::text, p_resultado_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb, p_resultado_reunion text DEFAULT NULL::text, p_motivo_no_realizada text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_tarea crm.tareas%rowtype;
  v_lead_bloqueado uuid;
  v_op_tarea_previa text := current_setting('crm.op_tarea',true);
  v_act_id uuid;
  v_act_cliente_id uuid;
  v_sig_id uuid;
  v_retroceso text;
  v_gesto_sla jsonb;
  v_detalle text := nullif(btrim(coalesce(p_resultado_detalle, '')), '');
begin
  if v_uid is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre inválido' using errcode = '22023';
  end if;

  -- Mismo orden para clientes antiguos y comandos con recibo: lead primero,
  -- tarea despues. Lock fuerte desde el inicio, sin escalado compartido.
  select l.id into v_lead_bloqueado from crm.leads l
  where l.id=(select t.lead_id from crm.tareas t
    where t.id=p_tarea_id and t.activo and t.estado='pendiente'
      and (v_rol='gerencia'
        or t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
        or (t.vendedor_id is null and t.asignado_supervisor_id in
          (select private.vendedor_ids_visibles(v_uid)))))
  for update;

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
  -- El ámbito puede cambiar entre las dos lecturas. Nunca completar el
  -- camino tarea→lead si el precheck no consiguió el primer lock.
  if v_tarea.lead_id is not null and v_lead_bloqueado is distinct from v_tarea.lead_id then
    raise exception 'El ámbito de la tarea cambió; vuelve a intentarlo' using errcode='P0409';
  end if;

  if v_tarea.lead_id is not null then
    perform 1 from crm.leads l where l.id = v_tarea.lead_id for update;
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

  v_gesto_sla:=private.sla_gesto_abrir(v_tarea.lead_id);
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
  perform set_config('crm.op_tarea', coalesce(v_op_tarea_previa,'off'), true);

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

  perform private.sla_gesto_cerrar(v_act_id,v_gesto_sla);
  return jsonb_build_object(
    'ok', true, 'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'actividad_cliente_id', v_act_cliente_id,
    'siguiente_id', v_sig_id, 'retroceso', v_retroceso
  );
end;
$function$
