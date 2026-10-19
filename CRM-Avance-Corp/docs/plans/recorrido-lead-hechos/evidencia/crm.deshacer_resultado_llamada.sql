CREATE OR REPLACE FUNCTION crm.deshacer_resultado_llamada(p_actividad_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_act crm.actividades%rowtype;
  v_lead crm.leads%rowtype;
  v_tarea crm.tareas%rowtype;
  v_tarea_cancelada boolean := false;
  v_descarte_revertido boolean := false;
  v_cita_no_restaurada boolean := false;
  v_restaurar text;
  v_guc_previo text := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  v_nota uuid;
  v_ahora timestamptz;
  v_bloqueo jsonb;
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_actividad_id is null then
    raise exception 'La actividad es obligatoria' using errcode = '22023';
  end if;
  -- Solo el AUTOR deshace lo suyo; una actividad ajena o inexistente recibe la
  -- misma respuesta (fail-closed, sin revelar existencia).
  -- La fila de la actividad se toma FOR UPDATE: dos «Deshacer» a la vez (doble
  -- clic en el toast, dos pestañas) se serializan aquí y el segundo relee el
  -- sello `deshecho_en` que dejó el primero. Ningún otro escritor actualiza
  -- crm.actividades salvo el núcleo sobre su propia fila recién nacida.
  select * into v_act from crm.actividades a where a.id = p_actividad_id for update;
  if not found or v_act.creado_por is distinct from v_uid then
    raise exception 'Resultado no encontrado o no es tuyo' using errcode = 'P0002';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  if v_act.metadata->>'evento' is distinct from 'resultado_llamada' then
    raise exception 'Esta actividad no es un resultado de llamada' using errcode = '22023';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    raise exception 'Este resultado ya se deshizo' using errcode = '22023';
  end if;
  if v_act.creado_en < v_ahora - interval '24 hours' then
    raise exception 'Solo se puede deshacer dentro de las 24 horas' using errcode = '22023';
  end if;
  if coalesce((v_act.metadata->>'no_insista')::boolean, false) then
    raise exception 'Este resultado marco "No insistir": esa restriccion solo la levanta Gerencia y no se deshace desde aqui'
      using errcode = 'P0429';
  end if;
  -- Ámbito VIGENTE (el lead pudo cambiar de manos). Candados en el orden de la
  -- casa (documento → persona → lead), el mismo que crm.reabrir_lead_fn: si el
  -- descarte va a revertirse, los de identidad se toman ANTES del lead (una
  -- reapertura concurrente del supervisor no puede cruzarse; Codex, 19/09).
  -- Inertes con la identidad apagada. Se revalida ámbito y descarte DESPUÉS.
  if private.sla_gestion_permitida(v_uid, v_act.lead_id) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
  end if;
  if coalesce((v_act.metadata->>'descartado')::boolean, false) then
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Deshacer requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    v_bloqueo := private.bloquear_personas_de_leads(array[v_act.lead_id], null);
  end if;
  select * into v_lead from crm.leads l where l.id = v_act.lead_id for update;
  if private.sla_gestion_permitida(v_uid, v_act.lead_id) is distinct from true then
    raise exception 'El lead cambio de responsable; recarga la ficha' using errcode = '42501';
  end if;
  if v_bloqueo is not null and private.resolver_en_puertas_bajo_candado()
     and not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
    raise exception 'La persona del lead cambio mientras se deshacia; vuelve a intentarlo' using errcode = '40001';
  end if;
  -- La ventana de 24 h se juzga con el reloj DESPUÉS de esperar los candados.
  v_ahora := pg_catalog.clock_timestamp();
  if v_act.creado_en < v_ahora - interval '24 hours' then
    raise exception 'Solo se puede deshacer dentro de las 24 horas' using errcode = '22023';
  end if;

  -- (a) La tarea que ESTE resultado creó, si sigue pendiente: se cancela por la
  --     puerta de cierre (una cita cancelada retrocede la etapa sola).
  if nullif(v_act.metadata->>'siguiente_id', '') is not null then
    select * into v_tarea from crm.tareas t
    where t.id = (v_act.metadata->>'siguiente_id')::uuid and t.lead_id = v_lead.id
      and t.activo and t.estado = 'pendiente';
    if found then
      perform crm.cerrar_tarea(
        v_tarea.id, 'cancelada', null, 'Resultado de llamada deshecho', null, null,
        case when v_tarea.tipo = 'reunion' then 'otro' end);
      v_tarea_cancelada := true;
    end if;
  end if;

  -- (b) El descarte, solo si el vigente es ESTE (mismo sello descartado_en).
  if coalesce((v_act.metadata->>'descartado')::boolean, false)
     and v_lead.etapa = 'descartado'
     and v_lead.descartado_en is not null
     and v_lead.descartado_en = nullif(v_act.metadata->>'descartado_en', '')::timestamptz then
    -- Juzga persona, veto y ámbito; lleva el lead a `nuevo` (D-15) y abre un
    -- ciclo nuevo. Un teléfono/documento ya vivo en OTRO lead (el enfriamiento
    -- de datos_invalidos y pide_credito es de 0 días) se traduce a texto humano;
    -- «ya es cliente» (P0409) y «persona vetada» (P0429) ya lo traen.
    begin
      perform crm.reabrir_lead_fn(v_lead.id);
    exception when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese telefono o documento: el descarte no se puede revertir'
        using errcode = '22023';
    end;
    v_restaurar := v_act.metadata->>'etapa_al_descartar';
    if v_restaurar = 'reunion_agendada' then
      -- La cita la canceló el sistema al descartar y no vuelve: sin cita viva no
      -- hay «reunión agendada» (doctrina de 20260726151751).
      v_restaurar := 'contactado';
      v_cita_no_restaurada := true;
    end if;
    if v_restaurar in ('contactado', 'propuesta_enviada') then
      update crm.leads set etapa = v_restaurar
       where id = v_lead.id and activo = true and etapa = 'nuevo';
    end if;
    v_descarte_revertido := true;
  end if;

  -- (c) Marca en la actividad original + nota en el historial (el log no se borra).
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  update crm.actividades a
     set metadata = a.metadata || pg_catalog.jsonb_build_object('deshecho_en', v_ahora, 'deshecho_por', v_uid)
   where a.id = p_actividad_id;
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (
    v_lead.id, 'nota',
    pg_catalog.format('Resultado de llamada deshecho (%s)%s%s',
      v_act.metadata->>'resultado',
      case when v_tarea_cancelada then ' · tarea siguiente cancelada' else '' end,
      case when v_descarte_revertido then ' · descarte revertido' else '' end),
    pg_catalog.jsonb_build_object(
      'evento', 'resultado_deshecho', 'actividad_id', p_actividad_id,
      'tarea_cancelada', v_tarea_cancelada, 'descarte_revertido', v_descarte_revertido,
      'cita_no_restaurada', v_cita_no_restaurada),
    v_uid)
  returning id into v_nota;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'actividad_id', p_actividad_id,
    'lead_id', v_lead.id,
    'nota_id', v_nota,
    'tarea_cancelada', v_tarea_cancelada,
    'descarte_revertido', v_descarte_revertido,
    'cita_no_restaurada', v_cita_no_restaurada,
    'ciclo_nuevo', (select l.ciclo_actual from crm.leads l where l.id = v_lead.id) > v_lead.ciclo_actual,
    'etapa', (select l.etapa from crm.leads l where l.id = v_lead.id));
end;
$function$
