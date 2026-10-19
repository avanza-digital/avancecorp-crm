-- Atención presencial explícita: cita inmediata + asistencia + entrevista.
-- Reutiliza el cierre v3 y su próxima acción. No activa exigencia de conversión.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$ begin
  if md5(pg_get_functiondef('private.recorrido_capturar_actividad()'::regprocedure))<>'e51911e9d36bd8d210c90186cae95fbb'
    or md5(pg_get_functiondef('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)'::regprocedure))<>'c0fa9a8ebb04cf84bc41155d4a318e30' then
    raise exception 'Cambio el contrato de captura o cierre; revisar antes de instalar oficina' using errcode='55000';
  end if;
  perform private.assert_sla_nucleo();
end $$;

-- Una GUC por sí sola no acredita el gesto. Debe corresponder al recibo privado
-- pendiente de ESTA transacción, actor y payload íntegro, con tarea/lead enlazados.
create or replace function private.recorrido_capturar_actividad() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  v_ciclo integer; v_hora timestamptz; v_lead crm.leads%rowtype;
  v_writer text:=coalesce(current_setting('crm.recorrido_contexto_writer',true),'off');
  v_oficina jsonb; v_gesto uuid; v_tarea uuid;
begin
  select * into strict v_lead from crm.leads where id=new.lead_id for update;
  v_ciclo:=v_lead.ciclo_actual;
  v_hora:=clock_timestamp();
  if not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id and c.ciclo_n=v_ciclo) then
    if v_lead.origen='base_cargada' and v_lead.etapa='descartado'
      and v_lead.motivo_descarte='base_cargada' and v_lead.activo
      and not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id) then
      v_ciclo:=null;
    else
      raise exception 'Falta el ciclo del recorrido de la actividad' using errcode='23514';
    end if;
  end if;
  v_oficina:=nullif(current_setting('crm.recorrido_oficina',true),'')::jsonb;
  if new.tipo='reunion_realizada' and v_oficina#>>'{payload,lead_id}'=new.lead_id::text
    and v_oficina#>>'{payload,tarea_id}'=new.metadata->>'tarea_id'
    and v_oficina->>'clave'='recorrido_oficina:'||(select auth.uid())::text||':'||(v_oficina->>'operacion_id')
    and exists(select 1 from crm.multiempresa_idempotencia m
      where m.clave=v_oficina->>'clave' and m.tipo='recorrido_oficina'
        and m.creado_por=(select auth.uid()) and m.resultado is null
        and m.hash_payload=private.idem_hash(v_oficina->'payload')) then
    v_gesto:=(v_oficina->>'operacion_id')::uuid;
    v_tarea:=(v_oficina#>>'{payload,tarea_id}')::uuid;
  end if;
  perform set_config('crm.recorrido_contexto_writer','on',true);
  insert into crm.actividad_ciclo_contexto(actividad_id,lead_id,ciclo_n,estado_ciclo,registrado_en,gesto_oficina_id,oficina_tarea_id)
    values(new.id,new.lead_id,v_ciclo,case when v_ciclo is null then 'base_sin_ciclo' else 'ciclo' end,v_hora,v_gesto,v_tarea);
  perform set_config('crm.recorrido_contexto_writer',v_writer,true);
  return null;
end $$;

create function crm.recorrido_atender_oficina_fn(
  p_operacion_id uuid,p_lead_id uuid,p_resultado_reunion text,
  p_detalle text default null,p_siguiente jsonb default null,
  p_capital_estimado numeric default null,p_moneda text default null,
  p_ubicacion text default 'Oficina')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=(select auth.uid());
  v_clave text; v_hash text; v_payload jsonb; v_respuesta jsonb;
  v_lead crm.leads%rowtype; v_tarea uuid; v_cierre uuid;
  v_anterior text:=coalesce(current_setting('crm.recorrido_oficina',true),'');
begin
  if v_actor is null or private.rol_crm(v_actor) is null
    or private.rol_crm(v_actor) not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_operacion_id is null or p_lead_id is null
    or p_resultado_reunion is null or p_resultado_reunion not in
      ('interesado','seguimiento','propuesta','inicia_registro','no_interesado')
    or nullif(btrim(p_ubicacion),'') is null or length(btrim(p_ubicacion))>500
    or length(coalesce(p_detalle,''))>4000
    or (p_siguiente is not null and jsonb_typeof(p_siguiente)<>'object') then
    raise exception 'Registra la entrevista, su resultado y la oficina de atencion' using errcode='22023';
  end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'La atencion necesita aislamiento READ COMMITTED' using errcode='55000';
  end if;
  if private.sla_gestion_permitida(v_actor,p_lead_id) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
  end if;
  v_clave:='recorrido_oficina:'||v_actor::text||':'||p_operacion_id::text;
  -- Identificador estable por operación y actor; no acepta IDs de tareas ajenas.
  v_tarea:=md5(v_clave)::uuid;
  v_payload:=jsonb_build_object('version',1,'lead_id',p_lead_id,'tarea_id',v_tarea,
    'resultado_reunion',p_resultado_reunion,'detalle',nullif(btrim(p_detalle),''),
    'siguiente',p_siguiente,'capital_estimado',p_capital_estimado,'moneda',p_moneda,
    'ubicacion',btrim(p_ubicacion));
  v_hash:=private.idem_hash(v_payload);
  perform pg_advisory_xact_lock(hashtextextended(v_clave,0));
  select * into strict v_lead from crm.leads where id=p_lead_id for update;
  if private.sla_gestion_permitida(v_actor,p_lead_id) is distinct from true then
    raise exception 'El lead cambio de responsable; recarga la ficha' using errcode='42501';
  end if;
  v_respuesta:=private.idem_leer(v_clave,v_hash);
  if v_respuesta is not null then return v_respuesta;end if;
  if v_lead.etapa in ('convertido','descartado') then
    raise exception 'El lead esta cerrado: no admite una visita nueva' using errcode='22023';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna un analista antes de registrar la visita' using errcode='22023';
  end if;
  if v_lead.no_contactar or private.persona_vetada(p_lead_id) then
    raise exception 'La persona tiene la restriccion No insistir' using errcode='P0429';
  end if;

  -- El recibo pendiente no se confirma separado del cierre. Todo revierte si
  -- falla el capital, la siguiente acción, un permiso o cualquier trigger.
  perform private.idem_guardar(v_clave,'recorrido_oficina',v_hash,null,v_actor);
  insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
    values(v_tarea,p_lead_id,'reunion','Atencion en oficina',clock_timestamp(),'presencial',btrim(p_ubicacion),v_actor);
  perform set_config('crm.recorrido_oficina',jsonb_build_object(
    'clave',v_clave,'operacion_id',p_operacion_id,'payload',v_payload)::text,true);
  -- El ID interno es del servidor: no puede colisionar con un comando SLA
  -- elegido por el llamador que espere el lead en el orden inverso.
  v_cierre:=gen_random_uuid();
  v_respuesta:=crm.cerrar_reunion_v3(v_cierre,v_tarea,'completada',p_resultado_reunion,
    null,nullif(btrim(p_detalle),''),p_siguiente,p_capital_estimado,p_moneda);
  perform set_config('crm.recorrido_oficina',v_anterior,true);
  if coalesce((v_respuesta->>'ok')::boolean,false) is not true then
    raise exception 'El servidor no confirmo la entrevista' using errcode='23514';
  end if;
  v_respuesta:=v_respuesta||jsonb_build_object('version',1,'operacion_id',p_operacion_id,
    'comando','recorrido_atender_oficina','origen','oficina','ciclo_n',v_lead.ciclo_actual);
  perform private.idem_guardar(v_clave,'recorrido_oficina',v_hash,v_respuesta,v_actor);
  return v_respuesta;
end $$;

revoke all on function private.recorrido_capturar_actividad() from public,anon,authenticated,service_role;
revoke all on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) from public,anon,service_role;
grant execute on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) to authenticated;
comment on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text)
  is 'Confirma visita presencial real y entrevista en una transaccion. Cita con hora del servidor; cierre v3 y siguiente accion existentes. Replay por actor/operacion con hash integro. No convierte ni modifica el modo del recorrido.';
select private.assert_sla_nucleo();
commit;
