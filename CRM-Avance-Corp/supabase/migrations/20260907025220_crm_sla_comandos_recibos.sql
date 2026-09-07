-- SLA N3: confirmacion idempotente de gestiones y cierres. Ninguna activacion.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $preflight$
begin
  if to_regprocedure('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)') is null then
    raise exception 'Instalar primero el nucleo SLA N1';
  end if;
  if to_regprocedure('private.sla_gesto_abrir(uuid)') is null
    or to_regprocedure('private.sla_gesto_cerrar(uuid,jsonb)') is null then
    raise exception 'Instalar primero los comandos del nucleo SLA N2';
  end if;
  if md5(pg_get_functiondef('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)'::regprocedure)) <> '82bd6cdf3c9fb09fd3bffb0d1270d2cb'
     or md5(pg_get_functiondef('crm.cerrar_reunion(uuid,text,text,text,text,jsonb)'::regprocedure)) <> '6b0b8c06a3d6d2020edc7da24348504f'
     or md5(pg_get_functiondef('crm.reprogramar_reunion(uuid,timestamptz,uuid)'::regprocedure)) <> '60a1a117cfb5cd46b879bb912da2499d' then
    raise exception 'Deriva de los writers de agenda: revisar antes de instalar SLA N3';
  end if;
end;
$preflight$;

create table crm.sla_operacion_recibos (
  actor_id uuid not null references public.perfiles(id) deferrable initially deferred,
  operacion_id uuid not null,
  lead_id uuid not null references crm.leads(id) deferrable initially deferred,
  sujeto_id uuid not null,
  comando text not null check (comando in ('registrar_actividad','cerrar_tarea','cerrar_reunion','reprogramar_reunion','reprogramar_tarea')),
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  respuesta jsonb check (jsonb_typeof(respuesta)='object'),
  creado_en timestamptz not null default clock_timestamp(),
  confirmado_en timestamptz,
  primary key (actor_id,operacion_id),
  check ((respuesta is null)=(confirmado_en is null))
);
-- Las FKs son diferidas: reservar antes del lock del lead no debe adquirir un
-- KEY SHARE implicito que obligue a dos gestiones a escalar su lock a la vez.
create index sla_operacion_recibos_lead_idx on crm.sla_operacion_recibos(lead_id);
alter table crm.sla_operacion_recibos enable row level security;
revoke all on crm.sla_operacion_recibos from public,anon,authenticated,service_role;

create function private.trg_sla_recibo_guard() returns trigger
language plpgsql security invoker set search_path='' as $function$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'Los recibos de gestion no se borran' using errcode='55000';
  end if;
  if tg_op='UPDATE' and (old.respuesta is not null or new.respuesta is null
      or (to_jsonb(new)-'respuesta'-'confirmado_en') is distinct from
         (to_jsonb(old)-'respuesta'-'confirmado_en')) then
    raise exception 'El recibo solo puede confirmarse una vez' using errcode='55000';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_sla_recibo_guard() from public,anon,authenticated,service_role;
create trigger sla_recibo_guard before insert or update or delete on crm.sla_operacion_recibos
  for each row execute function private.trg_sla_recibo_guard();
create trigger sla_recibo_truncate_guard before truncate on crm.sla_operacion_recibos
  for each statement execute function private.trg_sla_recibo_guard();
create trigger audit_sla_operacion_recibos after insert or update or delete on crm.sla_operacion_recibos
  for each row execute function private.log_audit_crm();

-- Al COMMIT ya terminó el SECURITY DEFINER de la RPC. Este trigger debe
-- comprobar la tabla privada con su owner; no se abre SELECT al cliente.
create function private.trg_sla_recibo_confirmado() returns trigger
language plpgsql security definer set search_path='' as $function$
begin
  if not exists(select 1 from crm.sla_operacion_recibos r
    where r.actor_id=new.actor_id and r.operacion_id=new.operacion_id and r.respuesta is not null) then
    raise exception 'Una gestion no puede confirmar sin recibo' using errcode='23514';
  end if;
  return null;
end;
$function$;
revoke all on function private.trg_sla_recibo_confirmado() from public,anon,authenticated,service_role;
create constraint trigger sla_recibo_confirmado after insert or update on crm.sla_operacion_recibos
  deferrable initially deferred for each row execute function private.trg_sla_recibo_confirmado();

-- Ventana de escritura del dominio: reutiliza autoridad CRM vigente. Se
-- comprueba de nuevo despues de esperar por el recibo y bajo el lock del lead.
create function private.sla_gestion_permitida(p_actor uuid,p_lead uuid) returns boolean
language sql stable security invoker set search_path='' as $function$
  select p_actor is not null and exists (
    select 1 from crm.leads l
    where l.id=p_lead and l.activo
      and private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
      and (private.rol_crm(p_actor)='gerencia' or l.vendedor_id=p_actor
        or (private.rol_crm(p_actor)='supervisor'
          and (l.vendedor_id in (select private.vendedor_ids_visibles(p_actor))
            or (l.vendedor_id is null and l.asignado_supervisor_id in
              (select private.vendedor_ids_visibles(p_actor))))))
  );
$function$;
revoke all on function private.sla_gestion_permitida(uuid,uuid) from public,anon,authenticated,service_role;

create function private.sla_ejecutar_comando(p_operacion uuid,p_comando text,p_sujeto uuid,p_payload jsonb)
returns jsonb language plpgsql volatile security invoker set search_path='' as $function$
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
$function$;
revoke all on function private.sla_ejecutar_comando(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;

create function crm.registrar_actividad_v2(p_operacion_id uuid,p_lead_id uuid,p_tipo text,p_detalle text default null,p_siguiente jsonb default null)
returns jsonb language sql volatile security definer set search_path='' as $function$
 select private.sla_ejecutar_comando(p_operacion_id,'registrar_actividad',p_lead_id,
   jsonb_build_object('tipo',p_tipo,'detalle',nullif(btrim(p_detalle),''),'siguiente',p_siguiente));
$function$;
create function crm.cerrar_tarea_v2(p_operacion_id uuid,p_tarea_id uuid,p_estado text,
 p_resultado_tipo text default null,p_resultado_detalle text default null,p_siguiente jsonb default null,
 p_resultado_reunion text default null,p_motivo_no_realizada text default null)
returns jsonb language sql volatile security definer set search_path='' as $function$
 select private.sla_ejecutar_comando(p_operacion_id,'cerrar_tarea',p_tarea_id,
   jsonb_build_object('estado',p_estado,'resultado_tipo',p_resultado_tipo,
     'resultado_detalle',nullif(btrim(p_resultado_detalle),''),'siguiente',p_siguiente,
     'resultado_reunion',p_resultado_reunion,'motivo_no_realizada',p_motivo_no_realizada));
$function$;
create function crm.cerrar_reunion_v2(p_operacion_id uuid,p_tarea_id uuid,p_estado text,
 p_resultado_reunion text default null,p_motivo_no_realizada text default null,
 p_detalle text default null,p_siguiente jsonb default null)
returns jsonb language sql volatile security definer set search_path='' as $function$
 select private.sla_ejecutar_comando(p_operacion_id,'cerrar_reunion',p_tarea_id,
   jsonb_build_object('estado',p_estado,'resultado_reunion',p_resultado_reunion,
     'motivo_no_realizada',p_motivo_no_realizada,'detalle',nullif(btrim(p_detalle),''),'siguiente',p_siguiente));
$function$;
create function crm.reprogramar_reunion_v2(p_operacion_id uuid,p_tarea_id uuid,p_vence_en timestamptz,p_nueva_id uuid default null)
returns jsonb language sql volatile security definer set search_path='' as $function$
 select private.sla_ejecutar_comando(p_operacion_id,'reprogramar_reunion',p_tarea_id,
   jsonb_build_object('vence_en',p_vence_en,'nueva_id',p_nueva_id));
$function$;
create function crm.reprogramar_tarea_v2(p_operacion_id uuid,p_tarea_id uuid,p_vence_en timestamptz)
returns jsonb language sql volatile security definer set search_path='' as $function$
 select private.sla_ejecutar_comando(p_operacion_id,'reprogramar_tarea',p_tarea_id,
   jsonb_build_object('vence_en',p_vence_en));
$function$;

revoke all on function crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text) from public,anon,authenticated,service_role;
revoke all on function crm.cerrar_reunion_v2(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function crm.reprogramar_reunion_v2(uuid,uuid,timestamptz,uuid) from public,anon,authenticated,service_role;
revoke all on function crm.reprogramar_tarea_v2(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb),
 crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text),
 crm.cerrar_reunion_v2(uuid,uuid,text,text,text,text,jsonb),
 crm.reprogramar_reunion_v2(uuid,uuid,timestamptz,uuid),
 crm.reprogramar_tarea_v2(uuid,uuid,timestamptz) to authenticated;

-- Conserva firma/owner/ACL, alinea locks del writer cerrar_tarea
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
$function$;

-- Conserva firma/owner/ACL, alinea locks del writer cerrar_reunion
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
$function$;

-- Conserva firma/owner/ACL, alinea locks del writer reprogramar_reunion
CREATE OR REPLACE FUNCTION crm.reprogramar_reunion(p_tarea_id uuid, p_vence_en timestamp with time zone, p_nueva_id uuid DEFAULT NULL::uuid)
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
  v_nueva_id uuid := coalesce(p_nueva_id, gen_random_uuid());
begin
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_vence_en is null
     or p_vence_en < timestamptz '2026-01-01 00:00Z'
     or p_vence_en >= timestamptz '2100-01-01 00:00Z' then
    raise exception 'Fecha de reunion invalida' using errcode = '22023';
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
  if p_vence_en = v_tarea.vence_en then
    raise exception 'La nueva fecha debe ser distinta'
      using errcode = '22023';
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = 'reprogramada',
         motivo_no_realizada = 'reprogramada',
         detalle_cierre_reunion = 'Reprogramada a ' || p_vence_en::text
   where id = p_tarea_id;
  perform set_config('crm.op_tarea', coalesce(v_op_tarea_previa,'off'), true);

  insert into crm.tareas (
    id, lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
    modalidad_reunion, ubicacion_reunion, enlace_reunion,
    reagendada_de, reprogramaciones, creado_por
  ) values (
    v_nueva_id,
    v_tarea.lead_id,
    v_tarea.perfil_id,
    'reunion',
    v_tarea.titulo,
    v_tarea.nota,
    p_vence_en,
    v_tarea.duracion_min,
    v_tarea.modalidad_reunion,
    v_tarea.ubicacion_reunion,
    v_tarea.enlace_reunion,
    v_tarea.id,
    v_tarea.reprogramaciones + 1,
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'tarea_anterior_id', p_tarea_id,
    'tarea_nueva_id', v_nueva_id,
    'reprogramaciones', v_tarea.reprogramaciones + 1
  );
end;
$function$;


create function private.assert_sla_comandos() returns text
language plpgsql stable security definer set search_path='' as $function$
declare v_firma text;v_id oid;
begin
  foreach v_firma in array array[
    'crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb)',
    'crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)',
    'crm.cerrar_reunion_v2(uuid,uuid,text,text,text,text,jsonb)',
    'crm.reprogramar_reunion_v2(uuid,uuid,timestamptz,uuid)',
    'crm.reprogramar_tarea_v2(uuid,uuid,timestamptz)'
  ] loop
    v_id:=to_regprocedure(v_firma);
    if v_id is null or not exists(select 1 from pg_proc p where p.oid=v_id
      and p.prosecdef and p.proowner='postgres'::regrole::oid
      and p.provolatile='v' and p.proconfig @> array['search_path=""']) then
      raise exception 'Contrato SLA de comando alterado: %',v_firma;end if;
    if not has_function_privilege('authenticated',v_id,'EXECUTE')
      or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
        where p.oid=v_id and a.grantee not in ('postgres'::regrole::oid,'authenticated'::regrole::oid)) then
      raise exception 'ACL SLA de comando alterado: %',v_firma;end if;
  end loop;
  if not exists(select 1 from pg_class where oid='crm.sla_operacion_recibos'::regclass and relrowsecurity)
    or exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      where c.oid='crm.sla_operacion_recibos'::regclass and a.grantee<>'postgres'::regrole::oid) then
    raise exception 'Los recibos SLA deben permanecer privados con RLS';end if;
  if (select count(*) from pg_constraint c where c.conrelid='crm.sla_operacion_recibos'::regclass
        and c.contype='f' and c.condeferrable and c.condeferred)<>2 then
    raise exception 'Las FKs de recibos SLA deben ser diferidas para conservar el orden de locks';end if;
  if not exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
    where t.tgrelid='crm.sla_operacion_recibos'::regclass and t.tgname='sla_recibo_confirmado'
      and t.tgenabled in ('O','A') and t.tgdeferrable and t.tginitdeferred
      and p.oid='private.trg_sla_recibo_confirmado()'::regprocedure and p.prosecdef
      and p.proowner='postgres'::regrole::oid and p.proconfig @> array['search_path=""']) then
    raise exception 'Confirmacion SLA diferida sin autoridad privada al COMMIT';end if;
  foreach v_firma in array array['private.trg_sla_recibo_confirmado()',
    'private.trg_sla_recibo_guard()','private.sla_gestion_permitida(uuid,uuid)',
    'private.sla_ejecutar_comando(uuid,text,uuid,jsonb)'] loop
    if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=to_regprocedure(v_firma) and a.grantee<>'postgres'::regrole::oid) then
      raise exception 'Puerta privada de recibos expuesta: %',v_firma;end if;
  end loop;
  if (select count(*) from pg_trigger t where t.tgrelid='crm.sla_operacion_recibos'::regclass
    and t.tgname in ('sla_recibo_guard','sla_recibo_truncate_guard') and t.tgenabled in ('O','A')
    and t.tgfoid='private.trg_sla_recibo_guard()'::regprocedure)<>2 then
    raise exception 'Candados de recibo incompletos';end if;
  -- Estas fuentes sellan el orden de bloqueos de los tres clientes v1.
  if (select md5(p.prosrc) from pg_proc p where p.oid='crm.cerrar_reunion(uuid,text,text,text,text,jsonb)'::regprocedure) is distinct from '8ccb961e63d5bcc4bd459af12c7d1dd0' then raise exception 'Writer agenda v1 cambió después de sellar locks SLA';end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid='crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)'::regprocedure) is distinct from '8df5076b6dd5376bcb7825ae4b6c9d3a' then raise exception 'Writer agenda v1 cambió después de sellar locks SLA';end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid='crm.reprogramar_reunion(uuid,timestamp with time zone,uuid)'::regprocedure) is distinct from 'a5983405f6f1f7b47c94e4228ca64e47' then raise exception 'Writer agenda v1 cambió después de sellar locks SLA';end if;
  return 'OK: comandos SLA privados, idempotentes y confirmados al commit';
end;
$function$;
revoke all on function private.assert_sla_comandos() from public,anon,authenticated,service_role;
select private.assert_sla_comandos();
select private.assert_analista_vigencia();
select private.assert_analitica_leads_citas();
select private.assert_auditoria();
select private.assert_f7_piezas_cerradas();

commit;
