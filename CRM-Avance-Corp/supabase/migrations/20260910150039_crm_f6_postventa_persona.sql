-- F6. Candidata: ensayar en banco aislado y revisar antes de instalar.
-- No activa ninguna fase, no migra tareas históricas ni modifica capital.
begin;
set local lock_timeout = '5s';

insert into crm.multiempresa_flags(nombre,activo,descripcion)
values ('postventa_neutral',false,'Gestiones, agenda y solicitudes de postventa por persona')
on conflict(nombre) do nothing;

alter table crm.tareas add column inversionista_id uuid references crm.inversionistas(id);
alter table crm.tareas add column postventa_revision integer;
alter table crm.tareas drop constraint tareas_un_solo_sujeto;
alter table crm.tareas add constraint tareas_un_solo_sujeto
  check(num_nonnulls(lead_id,perfil_id,inversionista_id)=1);
alter table crm.tareas add constraint tareas_revision_postventa
  check((inversionista_id is null and postventa_revision is null)
    or (inversionista_id is not null and postventa_revision is not null and postventa_revision>=1));
create index tareas_persona_pendiente on crm.tareas(inversionista_id,vence_en,id)
  where inversionista_id is not null and activo and estado='pendiente';
grant select(inversionista_id,postventa_revision) on crm.tareas to authenticated;

create table crm.inversionista_gestiones (
  id uuid primary key default gen_random_uuid(),
  inversionista_id uuid not null references crm.inversionistas(id),
  tarea_id uuid references crm.tareas(id),
  empresa text check(empresa in ('avance','qorilazo','prodelco')),
  tipo text not null check(tipo in ('agenda','cierre','reprogramacion','confirmacion',
    'veto','levantar_veto','responsable','fusion','retiro','reinversion')),
  detalle text not null check(length(btrim(detalle)) between 1 and 2000),
  metadata jsonb not null default '{}' check(jsonb_typeof(metadata)='object'),
  creado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default clock_timestamp()
);
alter table crm.inversionista_gestiones enable row level security;
revoke all on crm.inversionista_gestiones from public,anon,authenticated,service_role;
create index inversionista_gestiones_persona_fecha
  on crm.inversionista_gestiones(inversionista_id,creado_en desc,id);
create trigger trg_audit_inversionista_gestiones after insert or update or delete
  on crm.inversionista_gestiones for each row execute function private.log_audit_crm();

-- Recibos propios: un cierre postventa no avanza el pipeline ni consume un recibo SLA.
create table crm.postventa_operaciones (
  actor_id uuid not null references public.perfiles(id),
  clave uuid not null,
  inversionista_id uuid not null references crm.inversionistas(id),
  comando text not null,
  payload jsonb not null check(jsonb_typeof(payload)='object'),
  respuesta jsonb,
  creado_en timestamptz not null default clock_timestamp(),
  primary key(actor_id,clave)
);
alter table crm.postventa_operaciones enable row level security;
revoke all on crm.postventa_operaciones from public,anon,authenticated,service_role;
create trigger trg_audit_postventa_operaciones after insert or update or delete
  on crm.postventa_operaciones for each row execute function private.log_audit_crm();

-- Contexto efímero y privado de la transacción. Una GUC falsificada no lo sustituye.
create table crm.postventa_escrituras (
  transaccion xid8 not null,
  tarea_id uuid not null,
  primary key(transaccion,tarea_id)
);
alter table crm.postventa_escrituras enable row level security;
revoke all on crm.postventa_escrituras from public,anon,authenticated,service_role;
create trigger trg_audit_postventa_escrituras after insert or update or delete
  on crm.postventa_escrituras for each row execute function private.log_audit_crm();

create function private.postventa_modo() returns boolean
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_f3 boolean; v_flag record; v_total integer:=0; v_on boolean:=true;
begin
  v_f3:=private.resolver_en_puertas_bajo_candado();
  -- NOWAIT: quien apaga varias banderas puede tener F5 y esperar el lock F3.
  for v_flag in select nombre,activo from crm.multiempresa_flags
    where nombre in ('ficha_360_neutral','postventa_neutral') order by nombre for share nowait
  loop v_total:=v_total+1; v_on:=v_on and v_flag.activo; end loop;
  return v_f3 and v_total=2 and v_on;
exception when lock_not_available then
  raise exception 'Está cambiando la disponibilidad de postventa; vuelve a intentar' using errcode='40001';
end;
$$;

create function crm.postventa_estado_fn() returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_rol text; v_on boolean;
begin
  v_rol:=private.rol_crm(auth.uid());
  if auth.uid() is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_on:=private.postventa_modo();
  v_rol:=private.rol_crm(auth.uid());
  v_on:=v_on and coalesce(v_rol in ('vendedor','supervisor','gerencia'),false)
    and not private.es_lector_global();
  if v_on then v_on:=(crm.cartera_inversionistas_estado_fn()->>'habilitada')::boolean; end if;
  return jsonb_build_object('version',1,'habilitada',v_on);
end;
$$;

create function private.postventa_visible_actor(p_persona uuid, p_actor uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  -- RLS/ICS también se ejecutan en GET de solo lectura: candado asesor F3,
  -- sin FOR SHARE. Las escrituras usan además el modo F5/F6 bloqueado.
  if not private.resolver_en_puertas_bajo_candado() then return false; end if;
  return (select coalesce(
    private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
    and exists(select 1 from crm.multiempresa_flags where nombre='ficha_360_neutral' and activo)
    and exists(select 1 from crm.multiempresa_flags where nombre='postventa_neutral' and activo)
    and exists(select 1 from crm.inversionistas i where i.id=private.inversionista_canonica(p_persona)
      and (private.rol_crm(p_actor)='gerencia'
        -- El feed ICS identifica al actor por su token, sin auth.uid().
        or i.responsable_relacion_id=p_actor
        or i.responsable_relacion_id in (select private.vendedor_ids_visibles(p_actor)))),false));
end;
$$;
create function private.postventa_visible(p_persona uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.postventa_visible_actor(p_persona,auth.uid());
$$;
create policy tareas_postventa_lectura on crm.tareas as restrictive for select to authenticated
  using(inversionista_id is null or private.postventa_visible(inversionista_id));
create policy tareas_postventa_insert on crm.tareas as restrictive for insert to authenticated
  with check(inversionista_id is null);
create policy tareas_postventa_update on crm.tareas as restrictive for update to authenticated
  using(inversionista_id is null) with check(inversionista_id is null);

create function private.postventa_persona(p_persona uuid,p_contacto boolean default false) returns crm.inversionistas
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_id uuid; v_i crm.inversionistas%rowtype; v_docs text[]; v_ahora text[];
begin
  if auth.uid() is null or private.rol_crm(auth.uid()) is null
    or private.rol_crm(auth.uid()) not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode='42501'; end if;
  if not private.postventa_modo() then
    raise exception 'La postventa por persona todavía no está habilitada' using errcode='P0409'; end if;
  perform private.cartera_f5_exigir();
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_id:=private.inversionista_canonica(p_persona);
  v_docs:=private.identidad_bloquear_documentos_de(array[v_id]);
  select * into v_i from crm.inversionistas where id=v_id for update;
  if not found or not private.postventa_visible(v_id) then
    raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501'; end if;
  if private.inversionista_canonica(p_persona) is distinct from v_id then
    raise exception 'La identidad cambió; vuelve a cargar la ficha' using errcode='40001'; end if;
  select coalesce(array_agg(k order by k),'{}') into v_ahora
    from (select distinct tipo_documento||':'||documento_normalizado k
      from crm.inversionista_identificadores where inversionista_id=v_id and estado='vigente') d;
  if v_docs is distinct from v_ahora then
    raise exception 'El documento cambió; vuelve a cargar la ficha' using errcode='40001'; end if;
  if v_i.estado<>'activo' then
    raise exception 'La persona no está activa' using errcode='P0409'; end if;
  if p_contacto and (v_i.no_contactar or exists(select 1 from crm.leads l
    where l.id in (select private.leads_de_persona_veto(v_id)) and l.no_contactar)) then
    raise exception 'Esta persona pidió no ser contactada' using errcode='P0429'; end if;
  return v_i;
exception when lock_not_available then
  raise exception 'La identidad está siendo actualizada; vuelve a intentar' using errcode='40001';
end;
$$;

create function private.postventa_recibo(p_clave uuid,p_persona uuid,p_comando text,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare v_r crm.postventa_operaciones%rowtype;
begin
  if p_clave is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Operación incompleta' using errcode='22023'; end if;
  insert into crm.postventa_operaciones(actor_id,clave,inversionista_id,comando,payload)
    values(auth.uid(),p_clave,p_persona,p_comando,p_payload) on conflict(actor_id,clave) do nothing;
  select * into strict v_r from crm.postventa_operaciones
    where actor_id=auth.uid() and clave=p_clave for update;
  if v_r.inversionista_id<>p_persona or v_r.comando<>p_comando or v_r.payload is distinct from p_payload then
    raise exception 'La clave ya corresponde a otra operación' using errcode='P0409'; end if;
  return v_r.respuesta;
end;
$$;
create function private.postventa_responder(p_clave uuid,p_respuesta jsonb) returns jsonb
language plpgsql set search_path='' as $$
begin
  update crm.postventa_operaciones set respuesta=p_respuesta where actor_id=auth.uid() and clave=p_clave;
  return p_respuesta;
end;
$$;

create function private.postventa_tarea_guard() returns trigger
language plpgsql set search_path='' as $$
declare v_i crm.inversionistas%rowtype;
begin
  if (tg_op='INSERT' and new.inversionista_id is null)
    or (tg_op='UPDATE' and old.inversionista_id is null and new.inversionista_id is null) then return new; end if;
  if current_user<>'postgres' then
    raise exception 'Las gestiones por persona se guardan desde la agenda de postventa' using errcode='42501'; end if;
  if not exists(select 1 from crm.postventa_escrituras
    where transaccion=pg_current_xact_id() and tarea_id=new.id) then
    raise exception 'Usa el comando de postventa para esta tarea' using errcode='42501'; end if;
  if num_nonnulls(new.lead_id,new.perfil_id,new.inversionista_id)<>1
    or new.inversionista_id is null then raise exception 'Sujeto inválido' using errcode='22023'; end if;
  if tg_op='UPDATE' and (old.inversionista_id is distinct from new.inversionista_id
      or old.id is distinct from new.id) then
    raise exception 'La identidad original de la tarea es inmutable' using errcode='42501'; end if;
  -- Nunca esperar por una persona teniendo ya la tarea.
  select * into v_i from crm.inversionistas
    where id=private.inversionista_canonica(new.inversionista_id) for share nowait;
  if not found then raise exception 'Persona no disponible' using errcode='42501'; end if;
  if tg_op='INSERT' then
    if v_i.estado<>'activo' or v_i.no_contactar or exists(select 1 from crm.leads l
      where l.id in (select private.leads_de_persona_veto(v_i.id)) and l.no_contactar) then
      raise exception 'La persona no admite nuevas gestiones' using errcode='P0429'; end if;
    new.vendedor_id:=v_i.responsable_relacion_id;
    new.asignado_supervisor_id:=null;
    new.postventa_revision:=1;
    if new.reagendada_de is not null and not exists(select 1 from crm.tareas t
      where t.id=new.reagendada_de and t.inversionista_id is not null
        and private.inversionista_canonica(t.inversionista_id)=v_i.id) then
      raise exception 'La tarea anterior corresponde a otra persona' using errcode='22023'; end if;
  else new.postventa_revision:=old.postventa_revision+1;
  end if;
  return new;
exception when lock_not_available then
  raise exception 'La persona está siendo actualizada; vuelve a intentar' using errcode='40001';
end;
$$;
create trigger trg_tareas_000_postventa before insert or update on crm.tareas
  for each row execute function private.postventa_tarea_guard();

create function private.postventa_insertar_tarea(p_id uuid,p_persona uuid,p_datos jsonb,p_anterior uuid default null) returns crm.tareas
language plpgsql set search_path='' as $$
declare v_t crm.tareas%rowtype;
begin
  if p_datos is null or jsonb_typeof(p_datos)<>'object' or exists(select 1 from jsonb_object_keys(p_datos) k
    where k not in ('tipo','titulo','nota','vence_en','duracion_min','modalidad_reunion','ubicacion_reunion','enlace_reunion')) then
    raise exception 'Datos de agenda inválidos' using errcode='22023'; end if;
  if not isfinite((p_datos->>'vence_en')::timestamptz) or (p_datos->>'vence_en')::timestamptz<=clock_timestamp() then
    raise exception 'Elige una fecha futura para la gestión' using errcode='22023'; end if;
  if p_datos->>'tipo'='reunion' and (p_datos->>'modalidad_reunion' is null
    or p_datos->>'modalidad_reunion' not in ('presencial','virtual')) then
    raise exception 'Indica cómo se realizará la reunión' using errcode='22023'; end if;
  insert into crm.postventa_escrituras values(pg_current_xact_id(),p_id);
  insert into crm.tareas(id,inversionista_id,tipo,titulo,nota,vence_en,duracion_min,
    modalidad_reunion,ubicacion_reunion,enlace_reunion,reagendada_de,creado_por)
  values(p_id,p_persona,p_datos->>'tipo',btrim(p_datos->>'titulo'),nullif(btrim(p_datos->>'nota'),''),
    (p_datos->>'vence_en')::timestamptz,(p_datos->>'duracion_min')::integer,
    p_datos->>'modalidad_reunion',p_datos->>'ubicacion_reunion',p_datos->>'enlace_reunion',p_anterior,auth.uid())
  returning * into v_t;
  delete from crm.postventa_escrituras where transaccion=pg_current_xact_id() and tarea_id=p_id;
  return v_t;
end;
$$;

-- Contrato explícito: no incorpora automáticamente futuras columnas internas.
-- Los perfiles son enlaces de lectura, nunca otro sujeto físico de la tarea.
create function private.postventa_tarea_json(p_t crm.tareas) returns jsonb
language sql stable strict set search_path='' as $$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',array(select i.perfil_id from crm.inversionistas i
      where i.perfil_id is not null and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
      order by i.perfil_id),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$$;

create function crm.postventa_agendar_fn(p_clave uuid,p_inversionista uuid,p_datos jsonb,p_actor uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_i crm.inversionistas%rowtype; v_t crm.tareas%rowtype; v_r jsonb;
begin
  if p_actor is distinct from auth.uid() then raise exception 'La sesión cambió; vuelve a abrir la ficha' using errcode='42501'; end if;
  v_i:=private.postventa_persona(p_inversionista);
  v_r:=private.postventa_recibo(p_clave,p_inversionista,'agendar',p_datos);
  if v_r is not null then return v_r; end if;
  v_i:=private.postventa_persona(p_inversionista,true);
  if v_i.responsable_relacion_id is null or not private.es_destino_crm_activo(
    v_i.responsable_relacion_id,array['vendedor','supervisor','gerencia']) then
    raise exception 'Asigna un responsable activo antes de agendar' using errcode='P0409'; end if;
  v_t:=private.postventa_insertar_tarea(p_clave,v_i.id,p_datos);
  insert into crm.inversionista_gestiones(inversionista_id,tarea_id,tipo,detalle,creado_por)
    values(v_i.id,v_t.id,'agenda','Próxima gestión: '||v_t.titulo,auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'tarea',private.postventa_tarea_json(v_t)));
end;
$$;

-- Un solo comando para cerrar, confirmar y reprogramar. Persona ANTES de tarea.
create function crm.postventa_tarea_fn(p_clave uuid,p_tarea uuid,p_revision integer,p_accion text,p_datos jsonb default '{}',p_actor uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_persona uuid; v_i crm.inversionistas%rowtype; v_t crm.tareas%rowtype; v_sig crm.tareas%rowtype;
  v_r jsonb; v_detalle text; v_payload jsonb; v_estado text;
  v_previo text:=current_setting('crm.op_tarea',true);
begin
  if p_actor is distinct from auth.uid() then raise exception 'La sesión cambió; vuelve a abrir la ficha' using errcode='42501'; end if;
  select inversionista_id into v_persona from crm.tareas where id=p_tarea and activo;
  if v_persona is null then raise exception 'Tarea no disponible' using errcode='42501'; end if;
  v_i:=private.postventa_persona(v_persona);
  if p_accion is null or p_accion not in ('cerrar','reprogramar','confirmar') or p_revision is null
    or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Operación de agenda inválida' using errcode='22023'; end if;
  v_payload:=jsonb_build_object('tarea',p_tarea,'revision',p_revision,'accion',p_accion,'datos',p_datos);
  v_r:=private.postventa_recibo(p_clave,v_persona,'tarea',v_payload);
  if v_r is not null then return v_r; end if;
  select * into v_t from crm.tareas where id=p_tarea for update nowait;
  if not v_t.activo or v_t.estado<>'pendiente' or v_t.postventa_revision<>p_revision then
    raise exception 'La tarea cambió; recarga la agenda' using errcode='P0409'; end if;
  v_detalle:=nullif(btrim(p_datos->>'detalle'),'');
  if exists(select 1 from jsonb_object_keys(p_datos) k
    where (p_accion='confirmar')
      or (p_accion='cerrar' and k not in ('detalle','estado','siguiente'))
      or (p_accion='reprogramar' and k not in ('detalle','vence_en'))) then
    raise exception 'Campos de cierre inválidos' using errcode='22023'; end if;
  if p_accion<>'confirmar' and (v_detalle is null or length(v_detalle) not between 3 and 2000) then
    raise exception 'Describe la gestión (3 a 2000 caracteres)' using errcode='22023'; end if;
  if p_accion<>'cerrar' and (v_i.no_contactar or exists(select 1 from crm.leads l
    where l.id in (select private.leads_de_persona_veto(v_i.id)) and l.no_contactar)) then
    raise exception 'Esta persona pidió no ser contactada' using errcode='P0429'; end if;
  insert into crm.postventa_escrituras values(pg_current_xact_id(),p_tarea);
  perform set_config('crm.op_tarea','on',true);
  if p_accion='cerrar' then
    v_estado:=p_datos->>'estado';
    if v_estado is null or v_estado not in ('completada','cancelada','no_show')
      or (v_estado='no_show' and v_t.tipo<>'reunion') then
      raise exception 'Estado de cierre inválido' using errcode='22023'; end if;
    if v_estado='cancelada' and nullif(p_datos->'siguiente','null'::jsonb) is not null then
      raise exception 'Una cancelación no programa otro contacto' using errcode='22023'; end if;
    update crm.tareas set estado=v_estado,
      resultado_reunion=case when tipo='reunion' and v_estado='completada' then 'sin_clasificar' end,
      motivo_no_realizada=case when tipo='reunion' and v_estado='no_show' then 'cliente_no_asistio'
        when tipo='reunion' and v_estado='cancelada' then 'otro' end,
      detalle_cierre_reunion=case when tipo='reunion' then v_detalle end
    where id=p_tarea returning * into v_t;
    if nullif(p_datos->'siguiente','null'::jsonb) is not null then
      v_sig:=private.postventa_insertar_tarea(gen_random_uuid(),v_i.id,p_datos->'siguiente',
        case when v_estado='no_show' then p_tarea end);
    end if;
  elsif p_accion='confirmar' then
    if v_t.tipo<>'reunion' then raise exception 'Solo se confirman reuniones' using errcode='22023'; end if;
    update crm.tareas set confirmada_en=clock_timestamp() where id=p_tarea returning * into v_t;
  else
    if (p_datos->>'vence_en')::timestamptz is null
      or (p_datos->>'vence_en')::timestamptz=v_t.vence_en
      or not isfinite((p_datos->>'vence_en')::timestamptz)
      or (p_datos->>'vence_en')::timestamptz<=clock_timestamp() then
      raise exception 'Elige otra fecha futura' using errcode='22023'; end if;
    if v_t.tipo='reunion' then
      update crm.tareas set estado='reprogramada',motivo_no_realizada='reprogramada',detalle_cierre_reunion=v_detalle
        where id=p_tarea;
      v_sig:=private.postventa_insertar_tarea(gen_random_uuid(),v_i.id,jsonb_build_object(
        'tipo',v_t.tipo,'titulo',v_t.titulo,'nota',v_t.nota,'vence_en',p_datos->>'vence_en',
        'duracion_min',v_t.duracion_min,'modalidad_reunion',v_t.modalidad_reunion,
        'ubicacion_reunion',v_t.ubicacion_reunion,'enlace_reunion',v_t.enlace_reunion),p_tarea);
      select * into v_t from crm.tareas where id=p_tarea;
    else update crm.tareas set vence_en=(p_datos->>'vence_en')::timestamptz,confirmada_en=null
      where id=p_tarea returning * into v_t;
    end if;
  end if;
  perform set_config('crm.op_tarea',coalesce(v_previo,'off'),true);
  delete from crm.postventa_escrituras where transaccion=pg_current_xact_id() and tarea_id=p_tarea;
  insert into crm.inversionista_gestiones(inversionista_id,tarea_id,tipo,detalle,metadata,creado_por)
    values(v_persona,p_tarea,case p_accion when 'cerrar' then 'cierre' when 'confirmar' then 'confirmacion' else 'reprogramacion' end,
      coalesce(v_detalle,'Reunión confirmada'),jsonb_build_object('estado',v_t.estado,'siguiente_id',v_sig.id),auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'tarea',private.postventa_tarea_json(v_t),
    'siguiente',case when v_sig.id is not null then private.postventa_tarea_json(v_sig) end));
exception when lock_not_available then
  raise exception 'La tarea está cambiando; vuelve a intentar' using errcode='40001';
end;
$$;

create function crm.postventa_agenda_fn() returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_r jsonb;
begin
  begin
    if not (crm.postventa_estado_fn()->>'habilitada')::boolean then return '[]'::jsonb; end if;
  exception when serialization_failure or lock_not_available then
    -- Una transición de F6 no impide leer la agenda anterior. Otros errores
    -- (red, autorización, contrato) se conservan y no se disfrazan de vacío.
    return '[]'::jsonb;
  end;
  select coalesce(jsonb_agg(private.postventa_tarea_json(t) order by (t).vence_en,(t).id),'[]')
    into v_r from (select t from crm.tareas t
      where t.inversionista_id is not null and t.activo and t.estado='pendiente'
        and private.postventa_visible(t.inversionista_id)
      order by t.vence_en,t.id limit 2000) pagina;
  if not (crm.postventa_estado_fn()->>'habilitada')::boolean then
    raise exception 'La postventa ya no está disponible' using errcode='42501'; end if;
  return v_r;
end;
$$;

create function crm.postventa_perfil_fn(p_perfil uuid) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_id uuid;
begin
  if not (crm.postventa_estado_fn()->>'habilitada')::boolean then
    return jsonb_build_object('habilitada',false,'inversionista_id',null); end if;
  select p.inversionista_id into v_id from private.cartera_f5_personas_visibles() p
    where p_perfil=any(p.perfil_ids) and private.postventa_visible(p.inversionista_id);
  return jsonb_build_object('habilitada',true,'inversionista_id',v_id);
end;
$$;

-- Integración con veto, reasignación y fusión aun con F6 apagada: una reversa
-- impide gestiones nuevas pero no deja tareas huérfanas ni ignora un veto antiguo.
create function private.postventa_sincronizar(p_persona uuid) returns integer
language plpgsql set search_path='' as $$
declare v_i crm.inversionistas%rowtype; v_t crm.tareas%rowtype; v_n integer:=0; v_veto boolean;
  v_op text:=current_setting('crm.op_tarea',true); v_sistema text:=current_setting('crm.cancela_sistema',true);
begin
  select * into v_i from crm.inversionistas where id=private.inversionista_canonica(p_persona) for share nowait;
  v_veto:=v_i.no_contactar or exists(select 1 from crm.leads l
    where l.id in (select private.leads_de_persona_veto(v_i.id)) and l.no_contactar);
  for v_t in select * from crm.tareas t where t.inversionista_id is not null and t.activo
    and t.estado='pendiente' and private.inversionista_canonica(t.inversionista_id)=v_i.id
    and (v_veto or t.vendedor_id is distinct from v_i.responsable_relacion_id)
    order by t.id for update nowait
  loop
    insert into crm.postventa_escrituras values(pg_current_xact_id(),v_t.id);
    perform set_config('crm.op_tarea','on',true);
    perform set_config('crm.cancela_sistema','on',true);
    update crm.tareas set vendedor_id=v_i.responsable_relacion_id,asignado_supervisor_id=null,
      estado=case when v_veto then 'cancelada' else estado end,
      motivo_no_realizada=case when v_veto and tipo='reunion' then 'otro' else motivo_no_realizada end,
      detalle_cierre_reunion=case when v_veto and tipo='reunion' then 'No contactar: cancelación del sistema' else detalle_cierre_reunion end
    where id=v_t.id;
    perform set_config('crm.op_tarea',coalesce(v_op,'off'),true);
    perform set_config('crm.cancela_sistema',coalesce(v_sistema,'off'),true);
    delete from crm.postventa_escrituras where transaccion=pg_current_xact_id() and tarea_id=v_t.id;
    v_n:=v_n+1;
  end loop;
  return v_n;
exception when lock_not_available then
  raise exception 'La agenda de la persona está cambiando; vuelve a intentar' using errcode='40001';
end;
$$;

create function private.postventa_cambio_persona() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform private.postventa_sincronizar(new.id);
  if new.responsable_relacion_id is distinct from old.responsable_relacion_id then
    insert into crm.inversionista_gestiones(inversionista_id,tipo,detalle,metadata,creado_por)
    values(new.id,'responsable','Responsable de relación actualizado',jsonb_build_object(
      'anterior_id',old.responsable_relacion_id,'responsable_id',new.responsable_relacion_id),auth.uid());
  end if;
  if new.inversionista_canonico_id is distinct from old.inversionista_canonico_id then
    insert into crm.inversionista_gestiones(inversionista_id,tipo,detalle,metadata,creado_por)
    values(new.id,'fusion','Identidad integrada en su ficha canónica',
      jsonb_build_object('canonico_id',new.inversionista_canonico_id),auth.uid());
  end if;
  return new;
end;
$$;
create trigger trg_inversionistas_postventa after update of no_contactar,responsable_relacion_id,inversionista_canonico_id
  on crm.inversionistas for each row execute function private.postventa_cambio_persona();

create function crm.postventa_veto_fn(p_clave uuid,p_inversionista uuid,p_vetar boolean,p_motivo text,p_actor uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_i crm.inversionistas%rowtype; v_r jsonb; v_docs text[]; v_leads uuid[]; v_perfiles uuid[]; v_gestion uuid;
  v_priv text:=current_setting('crm.op_privilegiada',true);
  v_op text:=current_setting('crm.op_tarea',true); v_sistema text:=current_setting('crm.cancela_sistema',true);
begin
  if p_actor is distinct from auth.uid() then raise exception 'La sesión cambió; vuelve a abrir la ficha' using errcode='42501'; end if;
  v_i:=private.postventa_persona(p_inversionista);
  if p_vetar is null then raise exception 'Indica la acción de contacto' using errcode='22023'; end if;
  if not p_vetar and private.rol_crm(auth.uid())<>'gerencia' then
    raise exception 'Solo Gerencia puede levantar el veto' using errcode='42501'; end if;
  select coalesce(array_agg(documento_normalizado),'{}') into v_docs
    from crm.inversionista_identificadores where private.inversionista_canonica(inversionista_id)=v_i.id;
  perform private.motivo_sin_documento(p_motivo,v_docs);
  v_r:=private.postventa_recibo(p_clave,p_inversionista,'veto',jsonb_build_object('vetar',p_vetar,'motivo',p_motivo));
  if v_r is not null then return v_r; end if;
  v_leads:=array(select private.leads_de_persona_veto(v_i.id));
  v_perfiles:=array(select i.perfil_id from crm.inversionistas i
    where private.inversionista_canonica(i.id)=v_i.id and i.perfil_id is not null
    union select p.id from public.perfiles p where p.rol='cliente' and exists(
      select 1 from crm.inversionista_identificadores d where d.inversionista_id=v_i.id and d.estado='vigente'
        and d.tipo_documento=coalesce(nullif(btrim(p.tipo_documento),''),'DNI')
        and d.documento_normalizado=upper(regexp_replace(p.dni,'[^A-Za-z0-9]','','g'))));
  perform 1 from crm.tareas t where t.estado='pendiente' and (t.lead_id=any(v_leads)
    or t.perfil_id=any(v_perfiles) or private.inversionista_canonica(t.inversionista_id)=v_i.id)
    order by t.id for update nowait;
  perform 1 from crm.leads where id=any(v_leads) order by id for update nowait;
  perform set_config('crm.op_privilegiada','on',true);
  update crm.inversionistas set no_contactar=p_vetar,
    no_contactar_en=case when p_vetar then coalesce(no_contactar_en,clock_timestamp()) end,
    no_contactar_por=case when p_vetar then coalesce(no_contactar_por,auth.uid()) end where id=v_i.id;
  update crm.leads set no_contactar=p_vetar where id=any(v_leads) and no_contactar is distinct from p_vetar;
  -- Incondicional: re-vetar limpia pendientes, aunque el booleano no cambie.
  if p_vetar then
    perform private.postventa_sincronizar(v_i.id);
    perform set_config('crm.op_tarea','on',true);
    perform set_config('crm.cancela_sistema','on',true);
    update crm.tareas set estado='cancelada',
      motivo_no_realizada=case when tipo='reunion' then 'otro' end,
      detalle_cierre_reunion=case when tipo='reunion' then 'No contactar: cancelación del sistema' end
      where estado='pendiente' and (lead_id=any(v_leads) or perfil_id=any(v_perfiles));
    perform set_config('crm.op_tarea',coalesce(v_op,'off'),true);
    perform set_config('crm.cancela_sistema',coalesce(v_sistema,'off'),true);
  end if;
  insert into crm.inversionista_gestiones(inversionista_id,tipo,detalle,metadata,creado_por)
    values(v_i.id,case when p_vetar then 'veto' else 'levantar_veto' end,
      case when p_vetar then 'No contactar: ' else 'Veto levantado: ' end||btrim(p_motivo),
      jsonb_build_object('leads_afectados',cardinality(v_leads)),auth.uid()) returning id into v_gestion;
  -- El lead explica su cancelación; la ficha unificada reconoce el enlace y
  -- muestra una sola gestión, sin duplicar esta nota de compatibilidad.
  insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
    select l.id,'nota',case when p_vetar then 'No contactar: ' else 'Veto levantado: ' end||btrim(p_motivo),
      jsonb_build_object('evento','no_contactar','accion',case when p_vetar then 'marcar' else 'levantar' end,
        'inversionista_id',v_i.id,'postventa_gestion_id',v_gestion),auth.uid()
    from crm.leads l where l.id=any(v_leads);
  perform set_config('crm.op_privilegiada',coalesce(v_priv,'off'),true);
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'no_contactar',p_vetar));
exception when lock_not_available then
  raise exception 'Hay una gestión en curso; vuelve a intentar' using errcode='40001';
end;
$$;

create function private.postventa_fuente(p_fuente uuid,p_persona uuid,p_empresa text default null) returns crm.cierres_externos
language plpgsql set search_path='' as $$
declare v_c crm.cierres_externos%rowtype; v_f record;
begin
  -- Persona ya bloqueada por el llamador. No invertir fuente → persona.
  select * into v_c from crm.cierres_externos where id=p_fuente for share nowait;
  if not found or v_c.anulado_en is not null or (p_empresa is not null and v_c.cooperativa<>p_empresa) then
    raise exception 'La inversión de origen no está disponible' using errcode='P0409'; end if;
  select * into v_f from private.cartera_f5_fuentes() f
    where f.fuente_id=p_fuente and f.empresa=v_c.cooperativa;
  if not found or not v_f.identidad_coherente
    or private.inversionista_canonica(v_f.inversionista_id) is distinct from p_persona then
    raise exception 'La inversión no corresponde a esta persona' using errcode='42501'; end if;
  return v_c;
exception when lock_not_available then
  raise exception 'La inversión de origen está cambiando; vuelve a intentar' using errcode='40001';
end;
$$;

create table crm.postventa_retiros (
  id uuid primary key,
  inversionista_id uuid not null references crm.inversionistas(id),
  fuente_id uuid not null references crm.cierres_externos(id),
  empresa text not null check(empresa in ('qorilazo','prodelco')),
  estado text not null default 'solicitada' check(estado in ('solicitada','en_revision','revisada','rechazada','cancelada')),
  motivo text not null check(length(btrim(motivo)) between 3 and 2000),
  resolucion text check(length(btrim(resolucion)) between 3 and 2000),
  revision integer not null default 1 check(revision>=1),
  creado_por uuid not null references public.perfiles(id),
  revisado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default clock_timestamp(),
  actualizado_en timestamptz not null default clock_timestamp()
);
alter table crm.postventa_retiros enable row level security;
revoke all on crm.postventa_retiros from public,anon,authenticated,service_role;
create unique index postventa_retiro_activo on crm.postventa_retiros(fuente_id)
  where estado in ('solicitada','en_revision');
create index postventa_retiros_persona on crm.postventa_retiros(inversionista_id,creado_en desc,id);
create trigger trg_audit_postventa_retiros after insert or update or delete
  on crm.postventa_retiros for each row execute function private.log_audit_crm();

create function crm.postventa_solicitar_retiro_fn(p_clave uuid,p_inversionista uuid,p_fuente uuid,p_motivo text,p_actor uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_i crm.inversionistas%rowtype; v_c crm.cierres_externos%rowtype; v_r jsonb; v_retiro crm.postventa_retiros%rowtype;
begin
  if p_actor is distinct from auth.uid() then raise exception 'La sesión cambió; vuelve a abrir la ficha' using errcode='42501'; end if;
  -- Solicitud recibida del cliente: no levanta el veto ni autoriza contacto.
  v_i:=private.postventa_persona(p_inversionista);
  if p_motivo is null or length(btrim(p_motivo)) not between 3 and 1900 then
    raise exception 'Describe la solicitud (3 a 1900 caracteres)' using errcode='22023'; end if;
  v_r:=private.postventa_recibo(p_clave,p_inversionista,'solicitar_retiro',jsonb_build_object('fuente',p_fuente,'motivo',p_motivo));
  if v_r is not null then return v_r; end if;
  v_c:=private.postventa_fuente(p_fuente,v_i.id);
  if exists(select 1 from crm.postventa_retiros where fuente_id=p_fuente and estado in ('solicitada','en_revision')) then
    raise exception 'Esta inversión ya tiene una solicitud de retiro abierta' using errcode='P0409'; end if;
  insert into crm.postventa_retiros(id,inversionista_id,fuente_id,empresa,motivo,creado_por)
    values(p_clave,v_i.id,p_fuente,v_c.cooperativa,btrim(p_motivo),auth.uid()) returning * into v_retiro;
  insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(v_i.id,v_c.cooperativa,'retiro','Solicitud de retiro: '||btrim(p_motivo),
      jsonb_build_object('solicitud_id',p_clave,'fuente_id',p_fuente,'estado','solicitada'),auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'retiro',to_jsonb(v_retiro)));
end;
$$;

create function crm.postventa_revisar_retiro_fn(p_clave uuid,p_retiro uuid,p_revision integer,p_estado text,p_detalle text,p_actor uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_id uuid; v_i crm.inversionistas%rowtype; v_r jsonb; v_retiro crm.postventa_retiros%rowtype;
begin
  if p_actor is distinct from auth.uid() then raise exception 'La sesión cambió; vuelve a abrir la ficha' using errcode='42501'; end if;
  select inversionista_id into v_id from crm.postventa_retiros where id=p_retiro;
  v_i:=private.postventa_persona(v_id);
  if p_estado is null or p_estado not in ('en_revision','revisada','rechazada','cancelada') then
    raise exception 'Estado administrativo inválido' using errcode='22023'; end if;
  if p_estado<>'cancelada' and private.rol_crm(auth.uid())<>'gerencia' then
    raise exception 'Solo Gerencia revisa las solicitudes de retiro' using errcode='42501'; end if;
  if p_detalle is null or length(btrim(p_detalle)) not between 3 and 1900 or p_revision is null then
    raise exception 'Describe la revisión (3 a 1900 caracteres)' using errcode='22023'; end if;
  v_r:=private.postventa_recibo(p_clave,v_id,'revisar_retiro',jsonb_build_object(
    'retiro',p_retiro,'revision',p_revision,'estado',p_estado,'detalle',p_detalle));
  if v_r is not null then return v_r; end if;
  select * into v_retiro from crm.postventa_retiros where id=p_retiro for update nowait;
  if v_retiro.revision<>p_revision or v_retiro.estado not in ('solicitada','en_revision')
    or (p_estado in ('revisada','rechazada') and v_retiro.estado<>'en_revision')
    or p_estado=v_retiro.estado then
    raise exception 'La solicitud cambió o la transición no es válida; recarga la ficha' using errcode='P0409'; end if;
  update crm.postventa_retiros set estado=p_estado,resolucion=btrim(p_detalle),revision=revision+1,
    revisado_por=auth.uid(),actualizado_en=clock_timestamp() where id=p_retiro returning * into v_retiro;
  insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(v_id,v_retiro.empresa,'retiro','Revisión de retiro: '||btrim(p_detalle),
      jsonb_build_object('solicitud_id',p_retiro,'estado',p_estado),auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'retiro',to_jsonb(v_retiro)));
exception when lock_not_available then
  raise exception 'La solicitud está siendo revisada; vuelve a intentar' using errcode='40001';
end;
$$;

create function crm.postventa_ficha_fn(p_inversionista uuid) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_id uuid; v_r jsonb;
begin
  if not (crm.postventa_estado_fn()->>'habilitada')::boolean then
    return jsonb_build_object('version',1,'habilitada',false,'retiros','[]'::jsonb); end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  if not private.postventa_visible(v_id) then raise exception 'Persona fuera de tu ámbito' using errcode='42501'; end if;
  select jsonb_build_object('version',1,'habilitada',true,'retiros',coalesce((select jsonb_agg(to_jsonb(r)
    order by r.creado_en desc,r.id) from crm.postventa_retiros r
    where private.inversionista_canonica(r.inversionista_id)=v_id),'[]'::jsonb)) into v_r;
  if not private.postventa_visible(v_id) then raise exception 'Tu ámbito cambió' using errcode='42501'; end if;
  return v_r;
end;
$$;

create function crm.postventa_vencimientos_fn(p_empresa text default null,p_pagina integer default 1) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_r jsonb;
begin
  if not (crm.postventa_estado_fn()->>'habilitada')::boolean then
    return jsonb_build_object('version',1,'habilitada',false,'filas','[]'::jsonb,'total',0,'pagina',1,'tamano',25); end if;
  if p_pagina is null or p_pagina<1 or p_pagina>100000 or (p_empresa is not null
    and p_empresa not in ('avance','qorilazo','prodelco')) then
    raise exception 'Filtro de vencimientos inválido' using errcode='22023'; end if;
  with base as materialized (
    select f.fuente_id,f.inversionista_id,f.empresa,f.numero,f.capital,f.moneda,f.vence_en,p.nombre
    from private.cartera_f5_fuentes() f
    join private.cartera_f5_personas_visibles() p on p.inversionista_id=f.inversionista_id
    where private.postventa_visible(f.inversionista_id) and f.identidad_coherente and not f.es_demo
      and f.estado in ('activo','vigente','vencido') and f.vence_en is not null
      and f.vence_en<=(clock_timestamp() at time zone 'America/Lima')::date+30
      and (p_empresa is null or f.empresa=p_empresa)
  ), pagina as (select * from base order by vence_en,empresa,fuente_id limit 25 offset (p_pagina-1)*25)
  select jsonb_build_object('version',1,'habilitada',true,'pagina',p_pagina,'tamano',25,
    'total',(select count(*) from base),'filas',coalesce((select jsonb_agg(to_jsonb(p)
      order by vence_en,empresa,fuente_id) from pagina p),'[]'::jsonb)) into v_r;
  return v_r;
end;
$$;

create table crm.inversion_solicitud_origenes (
  solicitud_id uuid primary key references crm.inversion_solicitudes(id),
  fuente_id uuid not null references crm.cierres_externos(id),
  creado_por uuid not null references public.perfiles(id),
  creado_en timestamptz not null default clock_timestamp()
);
alter table crm.inversion_solicitud_origenes enable row level security;
revoke all on crm.inversion_solicitud_origenes from public,anon,authenticated,service_role;
create trigger trg_audit_inversion_solicitud_origenes after insert or update or delete
  on crm.inversion_solicitud_origenes for each row execute function private.log_audit_crm();

create function crm.preparar_reinversion_fn(p_clave uuid,p_fuente uuid,p_datos jsonb) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_ctx jsonb; v_r jsonb; v_origen uuid; v_existia boolean; v_estado text;
begin
  -- F3 → F4 → F5/F6 → jerarquía/documentos/persona → clave → fuente.
  if not private.inversiones_escritura_bajo_candado() or not private.postventa_modo() then
    raise exception 'La reinversión todavía no está habilitada' using errcode='P0409'; end if;
  if p_clave is null or p_fuente is null or p_datos is null or jsonb_typeof(p_datos)<>'object'
    or p_datos->>'inversionista_id' is null or p_datos->>'empresa' is null
    or p_datos->>'empresa' not in ('qorilazo','prodelco') then
    raise exception 'Datos de reinversión inválidos' using errcode='22023'; end if;
  v_ctx:=private.inversion_persona_autorizada((p_datos->>'inversionista_id')::uuid);
  perform pg_advisory_xact_lock(hashtextextended('f4_solicitud:'||p_clave::text,0));
  select estado into v_estado from crm.inversion_solicitudes where id=p_clave for update;
  v_existia:=found;
  if v_existia then
    select fuente_id into v_origen from crm.inversion_solicitud_origenes where solicitud_id=p_clave;
    if v_origen is distinct from p_fuente then
      raise exception 'La clave ya tiene otro origen o corresponde a una inversión ordinaria' using errcode='P0409'; end if;
    if v_estado<>'confirmada' then
      perform private.postventa_fuente(p_fuente,(v_ctx->>'inversionista_id')::uuid,p_datos->>'empresa');
    end if;
    -- F4 conserva su resultado incluso si el origen se anuló después de confirmar.
    return crm.preparar_inversion_fn(p_clave,p_datos)||jsonb_build_object('reinversion_origen_id',p_fuente);
  end if;
  perform private.postventa_fuente(p_fuente,(v_ctx->>'inversionista_id')::uuid,p_datos->>'empresa');
  v_r:=crm.preparar_inversion_fn(p_clave,p_datos);
  insert into crm.inversion_solicitud_origenes(solicitud_id,fuente_id,creado_por)
    values(p_clave,p_fuente,auth.uid());
  return v_r||jsonb_build_object('reinversion_origen_id',p_fuente);
end;
$$;

create function private.postventa_reinversion_guard() returns trigger
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_fuente uuid; v_persona uuid;
begin
  select fuente_id into v_fuente from crm.inversion_solicitud_origenes where solicitud_id=new.id;
  if not found then return new; end if;
  if old.estado='confirmada' then return new; end if;
  if not private.postventa_modo() then
    raise exception 'La reinversión todavía no está habilitada' using errcode='P0409'; end if;
  v_persona:=private.inversionista_canonica(new.inversionista_id);
  if new.inversionista_id is distinct from old.inversionista_id or new.empresa_id is distinct from old.empresa_id then
    raise exception 'La persona y empresa de origen son inmutables' using errcode='P0409'; end if;
  perform private.postventa_fuente(v_fuente,v_persona,new.datos->>'empresa');
  if new.estado='confirmada' then
    insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(new.inversionista_id,new.datos->>'empresa','reinversion','Reinversión confirmada',
      jsonb_build_object('solicitud_id',new.id,'origen_id',v_fuente,'inversion_id',new.inversion_id),auth.uid());
  end if;
  return new;
end;
$$;
create trigger trg_solicitudes_zz_postventa before update of datos,estado,inversionista_id,empresa_id
  on crm.inversion_solicitudes for each row execute function private.postventa_reinversion_guard();

-- Integración acotada: private.trg_tareas_destino_efectivo()
do $base$ begin
  if md5(pg_get_functiondef('private.trg_tareas_destino_efectivo()'::regprocedure))<>'5501b87138be72a30912dff23c7b1dde' then
    raise exception 'La base cambió: revisar private.trg_tareas_destino_efectivo() antes de instalar F6';
  end if;
end $base$;
CREATE OR REPLACE FUNCTION private.trg_tareas_destino_efectivo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- F6: el destino neutral proviene de la persona y puede ser Gerencia o
  -- una cola sin responsable. Las rutas lead/perfil conservan su contrato.
  if new.inversionista_id is not null then
    if new.activo and new.estado='pendiente' and new.vendedor_id is not null
      and not private.es_destino_crm_activo(new.vendedor_id,array['vendedor','supervisor','gerencia']) then
      raise exception 'El responsable de postventa no está activo' using errcode='23514';
    end if;
    return new;
  end if;
  if new.activo is true and new.estado='pendiente' then
    if new.vendedor_id is null and new.asignado_supervisor_id is null then
      raise exception 'La tarea pendiente requiere un destino CRM efectivo'
        using errcode='23514';
    end if;
    if new.vendedor_id is not null and not private.es_destino_crm_activo(
      new.vendedor_id,array['vendedor','supervisor']
    ) then
      raise exception 'El responsable de la tarea no tiene rol CRM efectivo'
        using errcode='23514';
    end if;
    if new.asignado_supervisor_id is not null and not private.es_destino_crm_activo(
      new.asignado_supervisor_id,array['supervisor']
    ) then
      raise exception 'La bandeja de la tarea no pertenece a un Supervisor efectivo'
        using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$
;

-- Integración acotada: private.agenda_ics_feed_implementacion(uuid,timestamp with time zone)
do $base$ begin
  if md5(pg_get_functiondef('private.agenda_ics_feed_implementacion(uuid,timestamp with time zone)'::regprocedure))<>'17d9c116e300a18d9dd57b02fa3230a5' then
    raise exception 'La base cambió: revisar private.agenda_ics_feed_implementacion(uuid,timestamp with time zone) antes de instalar F6';
  end if;
end $base$;
CREATE OR REPLACE FUNCTION private.agenda_ics_feed_implementacion(p_token uuid, p_desde timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with miembro as materialized (
    select a.perfil_id
    from crm.agenda_ics a
    join crm.equipo e on e.perfil_id = a.perfil_id and e.activo = true
    join public.perfiles p on p.id = a.perfil_id and p.activo = true
    where a.token = p_token
  ),
  filas as (
    select t.id, t.tipo, t.titulo, t.nota, t.vence_en, t.duracion_min,
           t.modalidad_reunion, t.ubicacion_reunion, t.enlace_reunion
    from crm.tareas t
    join miembro m on m.perfil_id = t.vendedor_id
    where t.estado = 'pendiente' and t.activo and t.vence_en >= p_desde
      and (t.inversionista_id is null or (
        private.postventa_visible_actor(t.inversionista_id,m.perfil_id)
        and exists(select 1 from crm.inversionistas i
          where i.id=private.inversionista_canonica(t.inversionista_id)
            and i.responsable_relacion_id=m.perfil_id and not i.no_contactar)))
    order by t.vence_en limit 500
  )
  select jsonb_build_object(
    'autorizado', exists (select 1 from miembro),
    'tareas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', f.id, 'tipo', f.tipo, 'titulo', f.titulo, 'nota', f.nota,
      'vence_en', f.vence_en, 'duracion_min', f.duracion_min,
      'modalidad_reunion', f.modalidad_reunion,
      'ubicacion_reunion', f.ubicacion_reunion,
      'enlace_reunion', f.enlace_reunion
    ) order by f.vence_en) from filas f), '[]'::jsonb)
  );
$function$
;

-- Integración acotada: crm.marcar_no_contactar(uuid,text)
do $$ begin if md5(pg_get_functiondef('crm.marcar_no_contactar(uuid,text)'::regprocedure)) <> 'be49e976a0c760c23d08bc66e81f23c9' then raise exception 'La base cambió: revisar crm.marcar_no_contactar antes de instalar F6'; end if; end $$;
CREATE OR REPLACE FUNCTION crm.marcar_no_contactar(p_lead_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean;
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia'), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);

  -- ORDEN: identidad PRIMERO (sin bloquear el lead aún), luego leads.
  -- Con bandera APAGADA la RPC actúa solo sobre el lead (como el UPDATE directo de hoy).
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;

  -- F2.b (b2) [Codex E1 #2]: orden identidad -> TAREAS -> leads. crm.cerrar_tarea va
  -- tarea -> lead; cancelar las pendientes después de bloquear los leads formaría un ciclo.
  if v_flag then
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads)  /* F2.b [D-3]: enlace ∪ puente ∪ sueltos, y también las tareas de CLIENTE */
            or t.perfil_id = any(v_perfiles))
       order by t.id
       for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está cerrando una tarea de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (vendedor_id is null and asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;
  -- Revalidar tras esperar: si la identidad cambió (fusión/corrección), reintentar.
  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(no_contactar_en, pg_catalog.now()),
           no_contactar_por = coalesce(no_contactar_por, v_uid)
     where id = v_inv and no_contactar = false;
    -- Todos los leads de la persona heredan el veto (id asc = orden determinista).
    for v_lead in
      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
    loop
      if not v_lead.no_contactar then
        update crm.leads set no_contactar = true where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también hereda el veto.
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    get diagnostics v_n = row_count;
  end if;
  -- F2.b (b2): con la bandera encendida se cancelan las tareas PENDIENTES de todos
  -- los leads de la persona (selladas como sistema). Levantar el veto NO las revive.
  if v_flag then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.estado = 'pendiente'
       and (t.lead_id = any(v_leads)  /* F2.b [D-3]: enlace ∪ puente ∪ sueltos, y también las tareas de CLIENTE */
            or t.perfil_id = any(v_perfiles));
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;

  -- F6: también el re-veto cancela la agenda neutral; no depende de que cambie el booleano.
  if v_flag and v_inv is not null then perform private.postventa_sincronizar(v_inv); end if;

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  -- La nota se inserta BAJO la válvula: el trigger de gestión exime la válvula del veto (F2.b b2).
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota',
          'Marcado como No contactar' || case when v_flag and v_inv is not null then ' (persona completa)' else '' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'marcar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', nullif(pg_catalog.btrim(coalesce(p_motivo,'')), '')),
          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$
;

-- Integración acotada: private.inversion_solicitud_resultado(uuid,jsonb)
do $base$ begin
  if md5(pg_get_functiondef('private.inversion_solicitud_resultado(uuid,jsonb)'::regprocedure))<>'8dfe4fb7ee03e0726432d2561425e346' then
    raise exception 'La base cambió: revisar private.inversion_solicitud_resultado(uuid,jsonb) antes de instalar F6';
  end if;
end $base$;
CREATE OR REPLACE FUNCTION private.inversion_solicitud_resultado(p_id uuid, p_contexto jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('solicitud_id',s.id,'estado',s.estado,'inversion_id',s.inversion_id,
    'inversionista_id',p_contexto->>'inversionista_id','inversionista_origen_id',s.inversionista_id,
    'identidad_fusionada',s.inversionista_id::text is distinct from p_contexto->>'inversionista_id',
    'responsable_esperado_id',s.responsable_esperado_id,'responsable_actual_id',p_contexto->>'responsable_id',
    'requiere_revision_responsable',s.estado='preparada' and s.responsable_esperado_id::text is distinct from p_contexto->>'responsable_id',
    'revision_datos',s.revision_datos,'hash_datos',private.idem_hash(s.datos),
    'revision_responsable',coalesce((select max(r.revision) from crm.inversion_solicitud_revisiones r where r.solicitud_id=s.id),0),
    'resultado',case when s.resultado is not null then s.resultado||jsonb_build_object('inversionista_id',p_contexto->>'inversionista_id') end,
    'necesita_portal',e.requiere_portal and p_contexto->>'perfil_id' is null,
    'comprobante_bucket',case when e.fuente_capital='cierres_externos' then 'f4-comprobantes' else null end,
    'comprobante_ruta',s.datos#>>'{evidencia,ruta}',
    'reinversion_origen_id',(select o.fuente_id from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id))
  from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id where s.id=p_id;
$function$
;

-- Integración acotada: crm.inversionista_ficha_fn(uuid,integer,integer)
do $base$ begin
  if md5(pg_get_functiondef('crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure))<>'b77830ba58d4a9f9e01a69d25939697d' then
    raise exception 'La base cambió: revisar crm.inversionista_ficha_fn(uuid,integer,integer) antes de instalar F6';
  end if;
end $base$;
CREATE OR REPLACE FUNCTION crm.inversionista_ficha_fn(p_inversionista uuid, p_pagina_inversiones integer DEFAULT 1, p_pagina_historial integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
  if p_pagina_inversiones is null or p_pagina_inversiones<1 or p_pagina_inversiones>1000000
    or p_pagina_historial is null or p_pagina_historial<1 or p_pagina_historial>1000000 then
    raise exception 'Página inválida' using errcode='22023';
  end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles() where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available then v_postventa:=false;
    end;
  end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
    exception when sqlstate 'P0409' or sqlstate 'P0429' then v_motivo:=sqlerrm;
      when lock_not_available or deadlock_detected then
        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector then 'Acceso de solo lectura' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes() f where f.inversionista_id=v_id
      and (not v_lector or f.empresa='avance')
  ), pagina as materialized (
    select * from fuentes order by empresa,moneda,creado_en desc,fuente_id
    limit 25 offset (p_pagina_inversiones-1)*25
  ), historial as materialized (
    select a.id,'lead'::text origen,a.tipo,a.detalle,a.creado_en,null::text empresa
      from crm.actividades a where a.lead_id=any(v_p.lead_ids) and not v_lector
        and not (v_postventa and exists(select 1 from crm.inversionista_gestiones g
          where g.id::text=a.metadata->>'postventa_gestion_id'
            and private.inversionista_canonica(g.inversionista_id)=v_id))
    union all
    -- Directorio ya lee actividades_cliente y tareas de clientes Avance por
    -- sus policies publicadas; se excluyen aquí los antecedentes de leads.
    select a.id,'cliente',a.tipo,a.detalle,a.creado_en,'avance'::text empresa
      from crm.actividades_cliente a where a.cliente_id=any(v_p.perfil_ids)
    union all
    select g.id,'postventa',g.tipo,g.detalle,g.creado_en,g.empresa
      from crm.inversionista_gestiones g where v_postventa
        and private.inversionista_canonica(g.inversionista_id)=v_id
  ), tareas as materialized (
    select t.id,t.tipo,t.titulo,t.vence_en,t.estado,t.inversionista_id,t.postventa_revision
    from crm.tareas t where t.activo and (t.perfil_id=any(v_p.perfil_ids)
      or (not v_lector and t.lead_id=any(v_p.lead_ids))
      or (v_postventa and private.inversionista_canonica(t.inversionista_id)=v_id))
  )
  select jsonb_build_object('version',1,
    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      'contrato',case when f.empresa='avance' then (select jsonb_build_object(
        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
        ||case when private.contrato_pdf_archivo_base(f.fuente_id) is not null then
          jsonb_build_array(jsonb_build_object('id',f.fuente_id,'nombre','Contrato vigente','tipo','contrato_pdf'))
          else '[]'::jsonb end
        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
      'proxima_cuota',case when f.empresa='avance' then (
        select jsonb_build_object('fecha',c.fecha_programada,'moneda',f.moneda,
          'monto',c.monto_programado,'estado',c.estado,'tipo',c.tipo)
        from public.cronograma_pagos c where c.contrato_id=f.fuente_id and c.estado='pendiente'
        order by c.fecha_programada,c.numero_cuota,c.id limit 1) end,
      'numero_transaccion',case when not v_lector and f.empresa<>'avance' then
        (select ce.numero_transaccion from crm.cierres_externos ce where ce.id=f.fuente_id) end)
      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f),'[]'),
    'inversiones_total',(select count(*) from fuentes),'pagina_inversiones',p_pagina_inversiones,
    'totales',coalesce((select jsonb_agg(x.d order by x.empresa,x.moneda) from (
      select f.empresa,f.moneda,jsonb_build_object('empresa',f.empresa,'moneda',f.moneda,'cantidad',count(*),
        'capital_registrado',coalesce(sum(f.capital) filter(where not f.es_demo),0),
        'capital_activo',case when f.empresa='avance' then coalesce(sum(f.capital)
          filter(where not f.es_demo and f.estado='activo'
            and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end) d
      from fuentes f group by f.empresa,f.moneda) x),'[]'),
    'historial',coalesce((select jsonb_agg(to_jsonb(h) order by h.creado_en desc,h.id,h.origen) from (
      select * from historial order by creado_en desc,id,origen limit 25 offset (p_pagina_historial-1)*25) h),'[]'),
    'historial_total',(select count(*) from historial),'pagina_historial',p_pagina_historial,
    'tareas',coalesce((select jsonb_agg(to_jsonb(t) order by t.vence_en,t.id) from (
      select * from tareas where estado='pendiente' order by vence_en,id limit 25) t),'[]'),
    'tareas_total',(select count(*) from tareas where estado='pendiente')) into v_resultado;
  perform private.cartera_f5_exigir();
  if not exists(select 1 from private.cartera_f5_personas_visibles() p where p.inversionista_id=v_id) then
    return null;
  end if;
  perform private.cartera_f5_registrar('ficha',v_id);
  return v_resultado;
end;
$function$
;

create function crm.postventa_operacion_estado_fn(p_clave uuid,p_actor uuid default auth.uid()) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if p_actor is distinct from auth.uid() then raise exception 'La sesión cambió; vuelve a abrir la ficha' using errcode='42501'; end if;
  if auth.uid() is null or not coalesce(private.rol_crm(auth.uid()) in ('vendedor','supervisor','gerencia'),false) then
    raise exception 'No autorizado' using errcode='42501'; end if;
  -- Solo informa si TU envío quedó confirmado, incluso durante una reversa.
  -- No revela persona, contenido, respuesta ni pertenencia actual a otra cartera.
  -- Ausencia no prueba cancelación: un envío anterior podría seguir en curso.
  return jsonb_build_object('registrada',exists(select 1 from crm.postventa_operaciones
    where actor_id=auth.uid() and clave=p_clave and respuesta is not null));
end;
$$;


-- F6: la baja transfiere tareas neutrales al actualizar la persona, con el
-- contexto privado del trigger. Los barridos antiguos solo reciben lead/perfil.
do $base$ begin
  if md5(pg_get_functiondef('crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)'::regprocedure))<>'98ed607a6ba5bf78f42e7c130bf56ad9' then
    raise exception 'Cambió la baja de membresías; revisar la integración F6';
  end if;
end $base$;
CREATE OR REPLACE FUNCTION crm.fijar_membresia_activa_fn(p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_activo_anterior boolean;
  v_version timestamptz;
  v_perfil_activo boolean;
  v_rol_portal text;
  v_rol_reemplazo text;
  v_reemplazo_activo boolean;
  v_reemplazo_portal_activo boolean;
  v_impacto jsonb;
  v_requiere_reemplazo boolean;
  v_evento_objetivo uuid;
  v_flag boolean;                          -- F2.b [D-2]
  v_personas uuid[] := array[]::uuid[];    -- F2.b [D-2]: identidades (no fusionadas) a cargo del saliente
  v_nuevas uuid[] := array[]::uuid[];      -- F2.b [D-2]: las que aparecieron entre el censo y el bloqueo de sus leads
  v_ahora timestamptz;                     -- F2.b [D-2]
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede activar o desactivar membresias CRM';
  end if;
  if p_activo is null or p_version_equipo is null or p_idempotencia is null then
    raise exception 'Estado, version e idempotencia requeridos';
  end if;
  if p_activo is false and p_perfil_id = v_actor then
    raise exception 'Gerencia no puede desactivar su propia membresia';
  end if;

  -- F2.b [D-19] (auditor M1): primero el candado de la BANDERA, después el interlock de jerarquía. El orden global
  -- es BANDERA → JERARQUÍA → documento → persona → lead; invertirlo aquí encolaba un ciclo blando con el encendido.
  v_flag := private.resolver_en_puertas_bajo_candado();
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select e.rol_crm, e.activo, e.actualizado_en, p.activo, p.rol
    into v_rol, v_activo_anterior, v_version, v_perfil_activo, v_rol_portal
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
  for update of e;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion in ('membresia_activada','membresia_desactivada')
    and ue.idempotencia = p_idempotencia
  limit 1;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La membresia fue modificada por otra sesion';
  end if;

  if p_activo and v_rol_portal = 'superadmin' and v_rol <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede activarse en CRM como Gerencia';
  end if;

  if v_activo_anterior is not distinct from p_activo then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  if p_activo then
    if v_perfil_activo is not true then
      raise exception 'El perfil esta suspendido en Portal; Gerencia no puede reactivarlo';
    end if;

    update crm.equipo e set activo = true
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_activada', p_perfil_id,
      pg_catalog.jsonb_build_object('estado_nuevo', 'activo'),
      p_idempotencia
    );
  else
    v_impacto := crm.impacto_desactivacion_usuario_fn(p_perfil_id);
    v_requiere_reemplazo := (v_impacto->>'requiere_reemplazo')::boolean;

    if v_requiere_reemplazo and p_reemplazo_id is null then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;
    -- F2.b [D-2]: con la identidad encendida nadie se queda sin responsable: si el saliente tiene personas a cargo,
    -- la baja exige reemplazo (mismo mensaje), aunque la bandera cambiara entre la lectura del impacto y esta.
    if v_flag and p_reemplazo_id is null and exists (select 1 from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))) then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;

    if p_reemplazo_id is not null then
      if p_reemplazo_id = p_perfil_id then
        raise exception 'El reemplazo debe ser otro usuario';
      end if;

      select e.rol_crm, e.activo, p.activo
        into v_rol_reemplazo, v_reemplazo_activo, v_reemplazo_portal_activo
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = p_reemplazo_id
      for update of e;

      if not found
         or v_reemplazo_activo is not true
         or v_reemplazo_portal_activo is not true
         or v_rol_reemplazo is distinct from v_rol then
        raise exception 'El reemplazo no existe, no esta activo o no tiene el mismo rol CRM';
      end if;

      if exists (
        with recursive descendientes as (
          select e.perfil_id
          from crm.equipo e
          where e.supervisor_id = p_perfil_id
          union
          select e.perfil_id
          from crm.equipo e
          join descendientes d on e.supervisor_id = d.perfil_id
        )
        select 1 from descendientes where perfil_id = p_reemplazo_id
      ) then
        raise exception 'El reemplazo no puede pertenecer al subarbol del usuario saliente';
      end if;

      -- F2.b [D-2]: las PERSONAS del saliente (identidades activas con tramo abierto suyo o apuntándole) se bloquean
      -- ANTES que sus leads —la misma arista persona → lead de conversiones y veto; FOR NO KEY UPDATE, que serializa
      -- contra el FOR UPDATE de reasignar/marcar/convertir sin chocar con las FK— y sus tramos abiertos FOR UPDATE.
      if v_flag then
        -- (Codex N2) SIN ESPERAR: el alta de una tarea de cliente toma a la persona y luego a este mismo equipo; esperar
        -- aquí con equipo en la mano sería el abrazo. Si alguien tiene a una persona del saliente → 40001, se reintenta.
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_personas
          from (select i.id from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una persona a cargo del saliente está siendo actualizada; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        perform 1 from crm.inversionista_responsables r
         where r.inversionista_id = any(v_personas) and r.hasta is null
         order by r.id
         for update;
        -- (auditor M5) y las tareas pendientes del saliente ANTES que sus leads (tareas → leads), la misma disciplina que
        -- el veto (b2/D-3), reasignar y cerrar_tarea: el offboarding iba leads → tareas y podía abrazarse con un veto en
        -- curso sobre una persona que no está «a cargo» del saliente. Solo con la identidad encendida (paridad OFF).
        perform 1 from crm.tareas t
         where t.activo is true and t.estado = 'pendiente'
           and (t.vendedor_id = p_perfil_id or t.asignado_supervisor_id = p_perfil_id
                or t.lead_id in (select l.id from crm.leads l
                                  where (l.vendedor_id = p_perfil_id or l.asignado_supervisor_id = p_perfil_id)
                                    and l.activo is true and l.etapa not in ('convertido', 'descartado')))
         order by t.id
         for update;
      end if;

      update crm.equipo e
      set supervisor_id = p_reemplazo_id
      where e.supervisor_id = p_perfil_id and e.activo is true;

      update crm.leads l
      set vendedor_id = p_reemplazo_id
      where l.vendedor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      update crm.leads l
      set asignado_supervisor_id = p_reemplazo_id
      where l.asignado_supervisor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      -- F2.b [D-2] (Codex #3): una conversión en vuelo sobre un lead del saliente (no toma el interlock de jerarquía) pudo
      -- abrir un tramo al saliente DESPUÉS del censo. Con sus leads ya bloqueados por los dos UPDATE de arriba ninguna
      -- conversión suya sigue en vuelo: se repite el censo; lo que apareció se bloquea SIN esperar (persona tras lead es
      -- la arista inversa: si alguien la tiene → 40001, Gerencia reintenta) y se suma al traslado.
      if v_flag then
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_nuevas
          from (select i.id from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))
                   and not (i.id = any(v_personas))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una conversión de un lead del saliente sigue en curso; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        if coalesce(pg_catalog.array_length(v_nuevas, 1), 0) > 0 then
          perform 1 from crm.inversionista_responsables r
           where r.inversionista_id = any(v_nuevas) and r.hasta is null
           order by r.id
           for update;
          v_personas := v_personas || v_nuevas;
        end if;
      end if;

      -- Los triggers de leads sincronizan la agenda normal. Este barrido cubre
      -- ademas tareas independientes y cualquier residuo historico pendiente.
      update crm.tareas t
      set vendedor_id = p_reemplazo_id
      where t.vendedor_id = p_perfil_id and t.inversionista_id is null
        and t.activo is true and t.estado = 'pendiente';

      update crm.tareas t
      set asignado_supervisor_id = p_reemplazo_id
      where t.asignado_supervisor_id = p_perfil_id and t.inversionista_id is null
        and t.activo is true and t.estado = 'pendiente';

      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;

      -- F2.b [D-2]: el responsable de relación pasa al reemplazo en la MISMA transacción: se cierra cada tramo abierto
      -- del saliente y se abre otro al reemplazo (motivo 'offboarding', por = Gerencia), y responsable_relacion_id lo
      -- acompaña. Un único v_ahora tomado DESPUÉS de los locks [E3-14]. Con la bandera apagada, nada (paridad).
      if v_flag and coalesce(pg_catalog.array_length(v_personas, 1), 0) > 0 then
        v_ahora := pg_catalog.clock_timestamp();
        update crm.inversionista_responsables r
           set hasta = v_ahora
         where r.inversionista_id = any(v_personas) and r.hasta is null;
        insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
        select s.id, p_reemplazo_id, v_ahora, 'offboarding', v_actor
        from pg_catalog.unnest(v_personas) as s(id);
        update crm.inversionistas i
           set responsable_relacion_id = p_reemplazo_id
         where i.id = any(v_personas);
      end if;
    end if;

    update crm.equipo e set activo = false
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_desactivada', p_perfil_id,
      pg_catalog.jsonb_build_object(
        'reemplazo_id', p_reemplazo_id,
        'subordinados_transferidos', (v_impacto->>'subordinados_activos')::integer,
        'leads_transferidos',
          (v_impacto->>'leads_abiertos')::integer
          + (v_impacto->>'leads_en_bandeja')::integer,
        'tareas_transferidas', (v_impacto->>'tareas_pendientes')::integer,
        'clientes_transferidos', (v_impacto->>'clientes_activos')::integer
      ) || case when v_flag then pg_catalog.jsonb_build_object('personas_transferidas', coalesce(pg_catalog.array_length(v_personas, 1), 0)) else '{}'::jsonb end,  -- F2.b [D-2]
      p_idempotencia
    );
  end if;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'activo_crm', p_activo,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$function$
;

-- Todas las puertas y helpers cierran grants en la misma transacción.
do $privilegios$
declare f record;
begin
  for f in select p.oid::regprocedure::text firma,n.nspname,p.proname from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('crm','private') and
      (p.proname like 'postventa_%' or p.proname='preparar_reinversion_fn')
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.firma);
    if f.nspname='crm' or f.proname='postventa_visible' then
      execute format('grant execute on function %s to authenticated',f.firma);
    end if;
  end loop;
end;
$privilegios$;
notify pgrst,'reload schema';
commit;
