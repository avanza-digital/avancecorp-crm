CREATE OR REPLACE FUNCTION crm.cerrar_reunion(p_tarea_id uuid, p_estado text, p_resultado_reunion text DEFAULT NULL::text, p_motivo_no_realizada text DEFAULT NULL::text, p_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_tarea crm.tareas%rowtype;
  v_lead_bloqueado uuid;
  v_op_tarea_previa text := current_setting('crm.op_tarea',true);
  v_act_id uuid;
  v_sig_id uuid;
  v_retroceso text;
  v_gesto_sla jsonb;
begin
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null
     or p_estado not in ('completada', 'no_show', 'cancelada') then
    raise exception 'Estado de reunion invalido' using errcode = '22023';
  end if;
  if p_estado = 'completada'
     and (
       p_resultado_reunion is null
       or p_resultado_reunion not in (
         'interesado', 'seguimiento', 'propuesta',
         'inicia_registro', 'no_interesado'
       )
     ) then
    raise exception 'Registra el resultado comercial de la reunion'
      using errcode = '22023';
  end if;
  if p_estado = 'no_show' then
    p_motivo_no_realizada := 'cliente_no_asistio';
  elsif p_estado = 'cancelada'
        and (
          p_motivo_no_realizada is null
          or p_motivo_no_realizada not in (
            'cancelada_cliente', 'cancelada_empresa', 'otro'
          )
        ) then
    raise exception 'Registra el motivo de cancelacion'
      using errcode = '22023';
  end if;
  if p_estado = 'cancelada'
     and p_motivo_no_realizada = 'otro'
     and nullif(btrim(coalesce(p_detalle, '')), '') is null then
    raise exception 'Describe el otro motivo de cancelacion'
      using errcode = '22023';
  end if;

  select id into v_lead_bloqueado
  from crm.leads
  where id = (
    select t.lead_id
    from crm.tareas t
    where t.id = p_tarea_id
      and t.tipo = 'reunion'
      and t.activo
      and t.estado = 'pendiente'
      and (
        v_rol = 'gerencia'
        or t.vendedor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
        or (
          t.vendedor_id is null
          and t.asignado_supervisor_id in (
            select private.vendedor_ids_visibles(v_uid)
          )
        )
      )
  )
  for update;

  select *
    into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id
    and t.tipo = 'reunion'
    and t.activo
    and t.estado = 'pendiente'
    and (
      v_rol = 'gerencia'
      or t.vendedor_id in (
        select private.vendedor_ids_visibles(v_uid)
      )
      or (
        t.vendedor_id is null
        and t.asignado_supervisor_id in (
          select private.vendedor_ids_visibles(v_uid)
        )
      )
    )
  for update;
  if not found then
    raise exception 'Reunion no encontrada, cerrada o fuera de tu ambito';
  end if;
  -- El ámbito puede cambiar entre las dos lecturas. Nunca completar el
  -- camino tarea→lead si el precheck no consiguió el primer lock.
  if v_tarea.lead_id is not null and v_lead_bloqueado is distinct from v_tarea.lead_id then
    raise exception 'El ámbito de la tarea cambió; vuelve a intentarlo' using errcode='P0409';
  end if;

  v_gesto_sla:=private.sla_gesto_abrir(v_tarea.lead_id);
  if p_estado = 'completada' and v_tarea.lead_id is not null then
    insert into crm.actividades (
      lead_id, tipo, detalle, metadata, creado_por
    ) values (
      v_tarea.lead_id,
      'reunion_realizada',
      nullif(btrim(coalesce(p_detalle, '')), ''),
      jsonb_build_object(
        'modalidad', v_tarea.modalidad_reunion,
        'resultado_reunion', p_resultado_reunion,
        'tarea_id', v_tarea.id
      ),
      v_uid
    )
    returning id into v_act_id;
  elsif p_estado = 'no_show'
        and v_tarea.lead_id is not null
        and btrim(coalesce(p_detalle, '')) <> '' then
    insert into crm.actividades (
      lead_id, tipo, detalle, metadata, creado_por
    ) values (
      v_tarea.lead_id,
      'nota',
      btrim(p_detalle),
      jsonb_build_object(
        'evento', 'reunion_no_show',
        'tarea_id', v_tarea.id
      ),
      v_uid
    )
    returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = p_estado,
         resultado_actividad_id = v_act_id,
         resultado_reunion = case
           when p_estado = 'completada' then p_resultado_reunion
         end,
         motivo_no_realizada = case
           when p_estado in ('no_show', 'cancelada')
             then p_motivo_no_realizada
         end,
         detalle_cierre_reunion =
           nullif(btrim(coalesce(p_detalle, '')), '')
   where id = p_tarea_id;
  perform set_config('crm.op_tarea', coalesce(v_op_tarea_previa,'off'), true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea,
    p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );

  if p_estado = 'cancelada' and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(
      v_tarea.lead_id, p_tarea_id, v_uid
    );
  end if;

  perform private.sla_gesto_cerrar(v_act_id,v_gesto_sla);
  return jsonb_build_object(
    'ok', true,
    'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'siguiente_id', v_sig_id,
    'retroceso', v_retroceso
  );
end;
$function$
