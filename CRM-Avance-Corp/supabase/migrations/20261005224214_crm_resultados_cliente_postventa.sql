-- Resultado tipificado de las tareas de postventa por persona.
-- Reutiliza el recibo, la autorización y el orden de candados de F6.
-- Los clientes antiguos siguen pudiendo cerrar durante el despliegue escalonado.
begin;
set local lock_timeout = '5s';

do $migracion$
declare
  v_oid oid := 'crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)'::regprocedure;
  v_anterior text;
  v_nuevo text;
  v_definicion text;
begin
  select prosrc into strict v_anterior from pg_proc where oid = v_oid;
  -- Cuerpo F6 inicial (8b2d...) envuelto por la corrección PT409 del 10/09.
  if md5(v_anterior) <> '4fe2e158e6d359fcc25c64bc6624d2e5' then
    raise exception 'postventa_tarea_fn cambió: revisar el cuerpo vivo antes de reemplazarlo';
  end if;
  v_nuevo := v_anterior;

  v_nuevo := replace(v_nuevo,
    $antes$  v_r jsonb; v_detalle text; v_payload jsonb; v_estado text;$antes$,
    $despues$  v_r jsonb; v_detalle text; v_payload jsonb; v_estado text;
  v_resultado text; v_resultado_reunion text; v_etiqueta text;$despues$);

  v_nuevo := replace(v_nuevo,
    $antes$      or (p_accion='cerrar' and k not in ('detalle','estado','siguiente'))$antes$,
    $despues$      or (p_accion='cerrar' and k not in ('detalle','estado','siguiente','resultado','resultado_reunion','version'))$despues$);

  v_nuevo := replace(v_nuevo,
    $antes$  insert into crm.postventa_escrituras values(pg_current_xact_id(),p_tarea);$antes$,
    $despues$  -- Clasificación opcional solo para el bundle anterior. El formulario nuevo la exige.
  -- Se valida dentro del mismo recibo y antes de cualquier escritura del cierre.
  if p_accion='cerrar' then
    v_estado:=p_datos->>'estado';
    v_resultado:=p_datos->>'resultado';
    v_resultado_reunion:=p_datos->>'resultado_reunion';
    if p_datos ? 'version' and p_datos->'version' is distinct from '2'::jsonb then
      raise exception 'Versión de cierre inválida' using errcode='22023'; end if;
    if v_estado='completada' then
      if p_datos->'version' = '2'::jsonb and (
        (v_t.tipo in ('llamada','whatsapp') and v_resultado is null)
        or (v_t.tipo='reunion' and v_resultado_reunion is null)) then
        raise exception 'Selecciona el resultado de la gestión' using errcode='22023'; end if;
      if v_t.tipo='llamada' then
        if v_resultado is not null and v_resultado not in
          ('no_contesto','volver_a_llamar','agendo_reunion','no_interesado',
           'numero_errado','no_es_la_persona','pide_otro_producto') then
          raise exception 'Resultado de llamada inválido' using errcode='22023'; end if;
        if v_resultado_reunion is not null then
          raise exception 'Resultado comercial solo para citas' using errcode='22023'; end if;
        if v_resultado='agendo_reunion' and
          (p_datos->'siguiente'->>'tipo') is distinct from 'reunion' then
          raise exception 'Agenda la cita que resultó de la llamada' using errcode='22023'; end if;
        if v_resultado='volver_a_llamar' and
          (p_datos->'siguiente'->>'tipo') is distinct from 'llamada' then
          raise exception 'Agenda la siguiente llamada' using errcode='22023'; end if;
      elsif v_t.tipo='whatsapp' then
        if v_resultado is not null and v_resultado not in ('enviado','respondio') then
          raise exception 'Resultado de WhatsApp inválido' using errcode='22023'; end if;
        if v_resultado_reunion is not null then
          raise exception 'Resultado comercial solo para citas' using errcode='22023'; end if;
      elsif v_t.tipo='reunion' then
        if v_resultado is not null then
          raise exception 'Resultado de llamada solo para llamadas' using errcode='22023'; end if;
        if v_resultado_reunion is not null and v_resultado_reunion not in
          ('interesado','seguimiento','propuesta','inicia_registro','no_interesado') then
          raise exception 'Resultado comercial inválido' using errcode='22023'; end if;
      elsif v_resultado is not null or v_resultado_reunion is not null then
        raise exception 'Esta tarea solo registra detalle' using errcode='22023';
      end if;
    elsif v_resultado is not null or v_resultado_reunion is not null then
      raise exception 'Una tarea no realizada no admite resultado comercial' using errcode='22023';
    end if;
    v_etiqueta:=case
      when v_estado='completada' and v_t.tipo='llamada' then case v_resultado
        when 'no_contesto' then 'Llamada · no contestó'
        when 'volver_a_llamar' then 'Llamada · volver a llamar'
        when 'agendo_reunion' then 'Llamada · agendó cita'
        when 'no_interesado' then 'Llamada · no le interesa'
        when 'numero_errado' then 'Llamada · número errado'
        when 'no_es_la_persona' then 'Llamada · no es la persona'
        when 'pide_otro_producto' then 'Llamada · pide otro producto' end
      when v_estado='completada' and v_t.tipo='whatsapp' then case v_resultado
        when 'enviado' then 'WhatsApp · enviado'
        when 'respondio' then 'WhatsApp · respondió' end
      when v_estado='completada' and v_t.tipo='reunion' then
        'Entrevista realizada · ' || case v_resultado_reunion
          when 'interesado' then 'interesado'
          when 'seguimiento' then 'requiere seguimiento'
          when 'propuesta' then 'propuesta presentada'
          when 'inicia_registro' then 'inicia registro'
          when 'no_interesado' then 'no interesado' end
      when v_estado='no_show' then 'Cita · el cliente no asistió'
      when v_estado='cancelada' then 'Tarea cancelada'
    end;
    if v_etiqueta is not null and length(v_etiqueta||' · '||v_detalle)>2000 then
      raise exception 'Acorta el detalle para conservarlo completo en el historial' using errcode='22023';
    end if;
  end if;
  insert into crm.postventa_escrituras values(pg_current_xact_id(),p_tarea);$despues$);

  v_nuevo := replace(v_nuevo,
    $antes$      resultado_reunion=case when tipo='reunion' and v_estado='completada' then 'sin_clasificar' end,$antes$,
    $despues$      resultado_reunion=case when tipo='reunion' and v_estado='completada'
        then coalesce(v_resultado_reunion,'sin_clasificar') end,$despues$);

  v_nuevo := replace(v_nuevo,
    $antes$      coalesce(v_detalle,'Reunión confirmada'),jsonb_build_object('estado',v_t.estado,'siguiente_id',v_sig.id),auth.uid());$antes$,
    $despues$      case when v_etiqueta is null then coalesce(v_detalle,'Reunión confirmada')
        else v_etiqueta||' · '||v_detalle end,
      jsonb_build_object('estado',v_t.estado,'siguiente_id',v_sig.id,
        'resultado',v_resultado,'resultado_reunion',v_resultado_reunion,
        'tipo_tarea',v_t.tipo,'responsable_tarea_id',v_t.vendedor_id,
        'resultado_origen',case when p_accion='cerrar' and v_estado='completada'
          and v_t.tipo in ('llamada','whatsapp','reunion')
          and coalesce(v_resultado,v_resultado_reunion) is null then 'legacy_sin_resultado'
          else 'declarado' end),auth.uid());$despues$);

  if v_nuevo = v_anterior
    or position('v_resultado_reunion' in v_nuevo) = 0
    or position('coalesce(v_resultado_reunion' in v_nuevo) = 0 then
    raise exception 'No se pudieron aplicar todos los cambios al cierre de postventa';
  end if;
  v_definicion := pg_get_functiondef(v_oid);
  if (length(v_definicion) - length(replace(v_definicion,v_anterior,''))) / length(v_anterior) <> 1 then
    raise exception 'Definición ambigua del cierre de postventa';
  end if;
  execute replace(v_definicion,v_anterior,v_nuevo);
  if (select prosrc from pg_proc where oid=v_oid) is distinct from v_nuevo then
    raise exception 'El cierre de postventa no quedó con la huella esperada';
  end if;
end;
$migracion$;

commit;
