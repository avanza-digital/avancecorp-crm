CREATE OR REPLACE FUNCTION private.sla_ejecutar_comando(p_operacion uuid, p_comando text, p_sujeto uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid(); v_lead uuid; v_recibo crm.sla_operacion_recibos%rowtype;
  v_respuesta jsonb; v_actividad uuid; v_siguiente uuid; v_fecha timestamptz; v_etapa text;
  v_gesto_sla jsonb;
  v_tarea crm.tareas%rowtype;
begin
  if v_actor is null or private.rol_crm(v_actor) is null
      or private.rol_crm(v_actor) not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_operacion is null or p_sujeto is null or p_comando is null
      or p_comando not in ('registrar_actividad','cerrar_tarea','cerrar_reunion','reprogramar_reunion','reprogramar_tarea')
      or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Operacion de gestion invalida' using errcode='22023';
  end if;
  if p_comando='registrar_actividad' then v_lead:=p_sujeto;
  else select t.lead_id into v_lead from crm.tareas t where t.id=p_sujeto and t.activo;
  end if;
  if private.sla_gestion_permitida(v_actor,v_lead) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
  end if;

  insert into crm.sla_operacion_recibos(actor_id,operacion_id,lead_id,sujeto_id,comando,payload)
  values(v_actor,p_operacion,v_lead,p_sujeto,p_comando,p_payload)
  on conflict(actor_id,operacion_id) do nothing;
  select * into strict v_recibo from crm.sla_operacion_recibos r
  where r.actor_id=v_actor and r.operacion_id=p_operacion for update;
  if v_recibo.comando<>p_comando or v_recibo.sujeto_id<>p_sujeto
      or v_recibo.lead_id<>v_lead or v_recibo.payload is distinct from p_payload then
    raise exception 'Esta operacion ya corresponde a otro contenido' using errcode='23505';
  end if;
  if private.sla_gestion_permitida(v_actor,v_lead) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
  end if;
  if v_recibo.respuesta is not null then return v_recibo.respuesta; end if;

  perform 1 from crm.leads l where l.id=v_lead for update;
  if private.sla_gestion_permitida(v_actor,v_lead) is distinct from true then
    raise exception 'El lead cambio de responsable; recarga la ficha' using errcode='42501';
  end if;
  if p_comando='registrar_actividad' then
    if p_payload->>'tipo' is null or p_payload->>'tipo' not in
       ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota') then
      raise exception 'Tipo de gestion invalido' using errcode='22023';
    end if;
    if exists(select 1 from crm.leads l where l.id=v_lead and l.etapa in ('convertido','descartado')) then
      raise exception 'El lead esta cerrado' using errcode='22023';
    end if;
    v_gesto_sla:=private.sla_gesto_abrir(v_lead);
    insert into crm.actividades(id,lead_id,tipo,detalle,creado_por)
    values(p_operacion,v_lead,p_payload->>'tipo',p_payload->>'detalle',v_actor)
    returning id,creado_en into v_actividad,v_fecha;
    -- El writer de agenda toma del contexto solo lead/perfil. No se inventa
    -- una tarea anterior ni un enlace de reprogramacion para el primer plan.
    v_tarea.lead_id:=v_lead;
    v_siguiente:=private.crear_siguiente_tarea(v_tarea,nullif(p_payload->'siguiente','null'::jsonb),null,v_actor);
    perform private.sla_gesto_cerrar(v_actividad,v_gesto_sla);
    select l.etapa into v_etapa from crm.leads l where l.id=v_lead;
    v_respuesta:=jsonb_build_object('ok',true,'actividad_id',v_actividad,'creado_en',v_fecha,'etapa',v_etapa,'siguiente_id',v_siguiente);
  elsif p_comando='cerrar_tarea' then
    v_respuesta:=crm.cerrar_tarea(p_sujeto,p_payload->>'estado',p_payload->>'resultado_tipo',
      p_payload->>'resultado_detalle',nullif(p_payload->'siguiente','null'::jsonb),
      p_payload->>'resultado_reunion',p_payload->>'motivo_no_realizada');
  elsif p_comando='cerrar_reunion' then
    v_respuesta:=crm.cerrar_reunion(p_sujeto,p_payload->>'estado',p_payload->>'resultado_reunion',
      p_payload->>'motivo_no_realizada',p_payload->>'detalle',nullif(p_payload->'siguiente','null'::jsonb));
  elsif p_comando='reprogramar_reunion' then
    v_respuesta:=crm.reprogramar_reunion(p_sujeto,(p_payload->>'vence_en')::timestamptz,
      (p_payload->>'nueva_id')::uuid);
  else
    select * into v_tarea from crm.tareas t where t.id=p_sujeto and t.lead_id=v_lead
      and t.activo and t.estado='pendiente' and t.tipo<>'reunion' for update;
    if not found then raise exception 'Tarea no disponible' using errcode='22023'; end if;
    v_fecha:=(p_payload->>'vence_en')::timestamptz;
    if v_fecha is null or not isfinite(v_fecha) or v_fecha<timestamptz '2026-01-01Z'
        or v_fecha>=timestamptz '2100-01-01Z' then
      raise exception 'Fecha de tarea invalida' using errcode='22023';
    end if;
    if v_fecha=v_tarea.vence_en then raise exception 'La nueva fecha debe ser distinta' using errcode='22023'; end if;
    update crm.tareas set vence_en=v_fecha,confirmada_en=null where id=p_sujeto;
    v_respuesta:=jsonb_build_object('ok',true,'tarea_id',p_sujeto);
  end if;
  if coalesce((v_respuesta->>'ok')::boolean,false) is not true then
    raise exception 'El servidor no confirmo la gestion' using errcode='23514';
  end if;
  v_respuesta:=v_respuesta||jsonb_build_object('version',2,'operacion_id',p_operacion,'lead_id',v_lead,'comando',p_comando);
  update crm.sla_operacion_recibos set respuesta=v_respuesta,confirmado_en=clock_timestamp()
    where actor_id=v_actor and operacion_id=p_operacion;
  return v_respuesta;
end;
$function$
