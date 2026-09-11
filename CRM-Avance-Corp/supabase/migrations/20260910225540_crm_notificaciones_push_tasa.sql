-- Avisos de tasa del CRM. No modifica objetos del portal.
-- La instalación queda sin envíos hasta configurar crm_push_proyecto en Vault.
begin;

create table crm.dispositivos_push_tasa (
  id uuid primary key default gen_random_uuid(),
  perfil_id uuid not null references crm.equipo(perfil_id),
  sesion_id uuid not null,
  endpoint text not null unique check (length(endpoint) between 20 and 2048),
  p256dh text not null check (p256dh ~ '^[A-Za-z0-9_-]{87}$'),
  auth text not null check (auth ~ '^[A-Za-z0-9_-]{22}$'),
  revision uuid not null default gen_random_uuid(),
  activo boolean not null default true,
  habilitado_en timestamptz not null default now(),
  ultima_prueba_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
alter table crm.dispositivos_push_tasa enable row level security;
revoke all on crm.dispositivos_push_tasa from public, anon, authenticated;
create index dispositivos_push_tasa_perfil_idx on crm.dispositivos_push_tasa(perfil_id);
create trigger trg_audit_dispositivos_push_tasa after insert or update or delete
  on crm.dispositivos_push_tasa for each row execute function
  private.log_audit_sin_secretos('endpoint','p256dh','auth','sesion_id');

create table crm.envios_push_tasa (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references crm.solicitudes_tasa(id),
  dispositivo_id uuid not null references crm.dispositivos_push_tasa(id),
  revision uuid not null,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','enviando','enviado','cancelado','fallido')),
  intentos integer not null default 0 check (intentos between 0 and 8),
  disponible_en timestamptz not null default now(),
  reserva uuid,
  reservado_hasta timestamptz,
  codigo_http integer,
  creado_en timestamptz not null default now(),
  enviado_en timestamptz,
  unique (solicitud_id, dispositivo_id)
);
alter table crm.envios_push_tasa enable row level security;
revoke all on crm.envios_push_tasa from public, anon, authenticated;
create index envios_push_tasa_dispositivo_idx on crm.envios_push_tasa(dispositivo_id);
create index envios_push_tasa_pendientes_idx on crm.envios_push_tasa(disponible_en)
  where estado in ('pendiente','enviando');
create trigger trg_audit_envios_push_tasa after insert or update or delete
  on crm.envios_push_tasa for each row execute function
  private.log_audit_sin_secretos('reserva');

-- Solo los proveedores de Web Push admitidos; también se valida antes del HTTP.
create function private.endpoint_push_tasa_valido(p_endpoint text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(length(p_endpoint) <= 2048 and p_endpoint ~
    '^https://(fcm[.]googleapis[.]com|([a-z0-9-]+[.])+push[.]apple[.]com|updates[.]push[.]services[.]mozilla[.]com|[a-z0-9-]+[.]notify[.]windows[.]com)/[A-Za-z0-9_/?=&%+.,:~!$()*;-]+$', false);
$$;

-- La autorización se vuelve a comprobar al enviar, incluyendo cierre de sesión.
create function private.sesion_push_tasa_vigente(p_perfil uuid, p_sesion uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.rol_crm(p_perfil) = 'gerencia' and exists (
    select 1 from auth.sessions s where s.id = p_sesion and s.user_id = p_perfil
      and (s.not_after is null or s.not_after > now())
  );
$$;

create function private.actor_push_tasa() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_sesion uuid := (auth.jwt()->>'session_id')::uuid;
begin
  if not coalesce(private.sesion_push_tasa_vigente(v_uid,v_sesion),false) then
    raise exception 'Solo Gerencia con sesión vigente puede activar estos avisos' using errcode='42501';
  end if;
  return v_uid;
end;
$$;

create function crm.estado_push_tasa_fn(p_endpoint text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := private.actor_push_tasa(); v_dispositivo jsonb;
begin
  select jsonb_build_object('id',id,'activo',activo and sesion_id=(auth.jwt()->>'session_id')::uuid)
    into v_dispositivo from crm.dispositivos_push_tasa
    where perfil_id=v_uid and endpoint=p_endpoint;
  return jsonb_build_object('dispositivo',v_dispositivo,'configurado',
    exists(select 1 from vault.decrypted_secrets where name='crm_push_proyecto'
      and decrypted_secret ~ '^[a-z]{20}$')
    and exists(select 1 from vault.decrypted_secrets where name='cron_notif_secret'));
end;
$$;

create function crm.registrar_push_tasa_fn(p_endpoint text, p_p256dh text, p_auth text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.actor_push_tasa(); v_id uuid;
  v_sesion uuid := (auth.jwt()->>'session_id')::uuid;
begin
  if not private.endpoint_push_tasa_valido(p_endpoint)
     or coalesce(p_p256dh,'') !~ '^[A-Za-z0-9_-]{87}$'
     or coalesce(p_auth,'') !~ '^[A-Za-z0-9_-]{22}$' then
    raise exception 'Suscripción de notificaciones inválida' using errcode='22023';
  end if;
  -- Serializa el límite por cuenta, también ante registros simultáneos.
  perform 1 from crm.equipo where perfil_id=v_uid for update;
  if (select count(*) from crm.dispositivos_push_tasa where perfil_id=v_uid and activo
      and private.sesion_push_tasa_vigente(perfil_id,sesion_id)
      and endpoint<>p_endpoint) >= 10 then
    raise exception 'Alcanzaste el límite de dispositivos de esta cuenta' using errcode='22023';
  end if;
  if not exists(select 1 from crm.dispositivos_push_tasa where endpoint=p_endpoint)
      and (select count(*) from crm.dispositivos_push_tasa where perfil_id=v_uid)>=100 then
    raise exception 'Contacta a soporte para renovar tus dispositivos de notificaciones' using errcode='22023';
  end if;
  insert into crm.dispositivos_push_tasa as d(perfil_id,sesion_id,endpoint,p256dh,auth)
  values(v_uid,v_sesion,p_endpoint,p_p256dh,p_auth)
  on conflict(endpoint) do update set
    sesion_id=excluded.sesion_id, p256dh=excluded.p256dh, auth=excluded.auth,
    revision=case when d.sesion_id<>excluded.sesion_id or d.p256dh<>excluded.p256dh
      or d.auth<>excluded.auth or not d.activo then gen_random_uuid() else d.revision end,
    habilitado_en=case when d.sesion_id<>excluded.sesion_id or d.p256dh<>excluded.p256dh
      or d.auth<>excluded.auth or not d.activo then now() else d.habilitado_en end,
    activo=true, actualizado_en=now()
  where d.perfil_id=v_uid returning id into v_id;
  if v_id is null then
    raise exception 'Vuelve a activar los avisos desde este dispositivo' using errcode='42501';
  end if;
  return v_id;
end;
$$;

create function crm.desactivar_push_tasa_fn(p_dispositivo_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión' using errcode='42501'; end if;
  -- Permite revocar incluso si el usuario ya perdió Gerencia.
  update crm.dispositivos_push_tasa set activo=false, actualizado_en=now()
    where id=p_dispositivo_id and perfil_id=auth.uid();
  update crm.envios_push_tasa e set estado='cancelado',reserva=null,reservado_hasta=null
    where dispositivo_id=p_dispositivo_id and estado in ('pendiente','enviando')
    and exists(select 1 from crm.dispositivos_push_tasa d
      where d.id=e.dispositivo_id and d.perfil_id=auth.uid());
end;
$$;

create function private.encolar_push_tasa() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado='pendiente' and new.vence_en>now() then
    insert into crm.envios_push_tasa(solicitud_id,dispositivo_id,revision)
    select new.id,d.id,d.revision from crm.dispositivos_push_tasa d
    where d.activo and d.perfil_id<>new.solicitada_por
      and private.sesion_push_tasa_vigente(d.perfil_id,d.sesion_id)
    on conflict(solicitud_id,dispositivo_id) do nothing;
  end if;
  return new;
exception when others then
  -- El aviso auxiliar nunca invalida una solicitud válida. El cron recupera
  -- las filas faltantes; el diagnóstico no incluye claves ni datos del lead.
  raise warning 'No se pudo encolar el aviso de tasa (SQLSTATE %)', sqlstate;
  return new;
end;
$$;
create trigger trg_encolar_push_tasa after insert on crm.solicitudes_tasa
  for each row execute function private.encolar_push_tasa();

-- Recuperación si el trigger falló: solo solicitudes posteriores al opt-in
-- actual. No envía un historial al activar un teléfono nuevo.
create function private.reconciliar_push_tasa() returns void
language sql security definer set search_path = '' as $$
  insert into crm.envios_push_tasa(solicitud_id,dispositivo_id,revision)
  select s.id,d.id,d.revision from crm.solicitudes_tasa s
  join crm.dispositivos_push_tasa d on d.activo and d.habilitado_en<=s.solicitada_en
  where s.estado='pendiente' and s.vence_en>now() and d.perfil_id<>s.solicitada_por
    and private.sesion_push_tasa_vigente(d.perfil_id,d.sesion_id)
    and not exists(select 1 from crm.envios_push_tasa e where e.solicitud_id=s.id and e.dispositivo_id=d.id)
  order by s.solicitada_en,s.id,d.id limit 100
  on conflict(solicitud_id,dispositivo_id) do nothing;
$$;

-- RPC exclusivas de la Edge: el navegador no puede reclamar ni confirmar envíos.
create function crm.tomar_envios_push_tasa_fn(p_limite integer default 10) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_resultado jsonb;
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode='42501';
  end if;
  with invalidos as (
    select e.id from crm.envios_push_tasa e
    where estado in ('pendiente','enviando') and (reservado_hasta is null or reservado_hasta<now()) and not exists (
      select 1 from crm.dispositivos_push_tasa d join crm.solicitudes_tasa s on s.id=e.solicitud_id
      where d.id=e.dispositivo_id and d.revision=e.revision and d.activo
        and private.sesion_push_tasa_vigente(d.perfil_id,d.sesion_id)
        and s.estado='pendiente' and s.vence_en>now() and s.solicitada_por<>d.perfil_id)
    order by e.id limit 100 for update of e skip locked
  )
  update crm.envios_push_tasa e set estado='cancelado', reserva=null,reservado_hasta=null
    from invalidos i where e.id=i.id;
  with agotados as (
    select id from crm.envios_push_tasa where intentos>=8 and estado in ('pendiente','enviando')
      and (reservado_hasta is null or reservado_hasta<now())
    order by id limit 100 for update skip locked
  ) update crm.envios_push_tasa e set estado='fallido',reserva=null,reservado_hasta=null
    from agotados a where a.id=e.id;
  with elegidos as (
    select e.id from crm.envios_push_tasa e
    where e.intentos<8 and e.disponible_en<=now()
      and (e.estado='pendiente' or (e.estado='enviando' and e.reservado_hasta<now()))
      and exists(select 1 from crm.dispositivos_push_tasa d join crm.solicitudes_tasa s on s.id=e.solicitud_id
        where d.id=e.dispositivo_id and d.revision=e.revision and d.activo
          and private.sesion_push_tasa_vigente(d.perfil_id,d.sesion_id)
          and s.estado='pendiente' and s.vence_en>now() and s.solicitada_por<>d.perfil_id)
    order by e.disponible_en,e.id limit greatest(1,least(coalesce(p_limite,10),20))
    for update of e skip locked
  ), tomados as (
    update crm.envios_push_tasa e set estado='enviando',intentos=intentos+1,
      reserva=gen_random_uuid(),reservado_hasta=now()+interval '2 minutes'
    from elegidos x where e.id=x.id returning e.id,e.reserva
  ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'reserva',reserva)),'[]'::jsonb)
    into v_resultado from tomados;
  return v_resultado;
end;
$$;

create function crm.materializar_envio_push_tasa_fn(p_envio_id uuid,p_reserva uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode='42501';
  end if;
  return (select jsonb_build_object('solicitud_id',s.id,'endpoint',d.endpoint,
    'p256dh',d.p256dh,'auth',d.auth,'vence_en',s.vence_en)
    from crm.envios_push_tasa e join crm.dispositivos_push_tasa d on d.id=e.dispositivo_id
    join crm.solicitudes_tasa s on s.id=e.solicitud_id
    where e.id=p_envio_id and e.reserva=p_reserva and e.estado='enviando'
      and e.reservado_hasta>now() and d.activo and d.revision=e.revision
      and private.sesion_push_tasa_vigente(d.perfil_id,d.sesion_id)
      and s.estado='pendiente' and s.vence_en>now() and s.solicitada_por<>d.perfil_id);
end;
$$;

create function crm.confirmar_envio_push_tasa_fn(p_envio_id uuid,p_reserva uuid,
  p_resultado text,p_codigo_http integer default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_envio crm.envios_push_tasa;
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode='42501';
  end if;
  if p_resultado is null or p_resultado not in ('enviado','reintentar','cancelado','invalido','fallido') then
    raise exception 'Resultado inválido' using errcode='22023';
  end if;
  -- Mismo orden de bloqueo que desactivar: dispositivo antes que envío.
  -- Impide un deadlock entre la baja del teléfono y una respuesta 410.
  perform 1 from crm.dispositivos_push_tasa d where d.id=(
    select e.dispositivo_id from crm.envios_push_tasa e where e.id=p_envio_id
  ) for update;
  select * into v_envio from crm.envios_push_tasa where id=p_envio_id
    and reserva=p_reserva and estado='enviando' and reservado_hasta>now() for update;
  if not found then return false; end if;
  update crm.envios_push_tasa set
    estado=case when p_resultado='reintentar' and intentos<8 then 'pendiente'
      when p_resultado in ('reintentar','invalido') then 'fallido' else p_resultado end,
    codigo_http=p_codigo_http,reserva=null,reservado_hasta=null,
    disponible_en=now()+least(30,power(2,intentos-1)) * interval '1 minute',
    enviado_en=case when p_resultado='enviado' then now() else null end
  where id=p_envio_id;
  if p_resultado='invalido' then
    update crm.dispositivos_push_tasa set activo=false,actualizado_en=now()
      where id=v_envio.dispositivo_id and revision=v_envio.revision;
  end if;
  return true;
end;
$$;

create function crm.preparar_prueba_push_tasa_fn(p_dispositivo_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.actor_push_tasa(); v_d crm.dispositivos_push_tasa;
begin
  select * into v_d from crm.dispositivos_push_tasa where id=p_dispositivo_id
    and perfil_id=v_uid and sesion_id=(auth.jwt()->>'session_id')::uuid and activo for update;
  if not found then raise exception 'Activa los avisos en este dispositivo' using errcode='42501'; end if;
  if v_d.ultima_prueba_en>now()-interval '1 minute' then
    raise exception 'Espera un minuto antes de otra prueba' using errcode='P0429';
  end if;
  update crm.dispositivos_push_tasa set ultima_prueba_en=now() where id=v_d.id;
  return jsonb_build_object('endpoint',v_d.endpoint,'p256dh',v_d.p256dh,'auth',v_d.auth);
end;
$$;

-- pg_net entrega fuera de la transacción. Un error HTTP no bloquea al analista.
-- La tarea solo despierta al worker si hay trabajo y configuración de este banco.
-- La firma dura dos minutos y solo autoriza procesar avisos ya encolados. El
-- secreto compartido permanece en Vault: nunca entra en la cola legible de net.
create function crm.verificar_cron_push_tasa_fn(p_firma text,p_instante bigint) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare v_proyecto text; v_secreto text; v_ahora bigint := floor(extract(epoch from now()))::bigint;
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode='42501';
  end if;
  if p_firma is null or p_firma !~ '^[a-f0-9]{64}$' or p_instante is null
      or p_instante<v_ahora-120 or p_instante>v_ahora+30 then return false; end if;
  select decrypted_secret into v_proyecto from vault.decrypted_secrets where name='crm_push_proyecto';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name='cron_notif_secret';
  if v_proyecto is null or v_secreto is null then return false; end if;
  -- Compara hashes de tamaño fijo para no revelar prefijos de la firma válida.
  return extensions.digest(decode(p_firma,'hex'),'sha256') = extensions.digest(
    extensions.hmac('crm-push-tasa:'||v_proyecto||':'||p_instante::text,v_secreto,'sha256'),'sha256');
end;
$$;

create function private.despertar_push_tasa() returns void
language plpgsql security definer set search_path = '' as $$
declare v_proyecto text; v_secreto text; v_instante bigint := floor(extract(epoch from now()))::bigint;
begin
  perform private.reconciliar_push_tasa();
  if not exists(select 1 from crm.envios_push_tasa where
      (estado='pendiente' and disponible_en<=now())
      or (estado='enviando' and reservado_hasta<now())) then return; end if;
  select decrypted_secret into v_proyecto from vault.decrypted_secrets where name='crm_push_proyecto';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name='cron_notif_secret';
  if v_proyecto is null or v_proyecto !~ '^[a-z]{20}$' or v_secreto is null then return; end if;
  perform net.http_post(
    url:='https://'||v_proyecto||'.supabase.co/functions/v1/crm-notificaciones-tasa',
    headers:=jsonb_build_object('Content-Type','application/json',
      'x-cron-instante',v_instante::text,'x-cron-firma',encode(extensions.hmac(
        'crm-push-tasa:'||v_proyecto||':'||v_instante::text,v_secreto,'sha256'),'hex')),
    body:='{"accion":"procesar"}'::jsonb,timeout_milliseconds:=55000);
end;
$$;

revoke all on function private.endpoint_push_tasa_valido(text),
  private.sesion_push_tasa_vigente(uuid,uuid),private.actor_push_tasa(),
  private.encolar_push_tasa(),private.reconciliar_push_tasa(),private.despertar_push_tasa()
  from public,anon,authenticated,service_role;
revoke all on function crm.estado_push_tasa_fn(text),crm.registrar_push_tasa_fn(text,text,text),
  crm.desactivar_push_tasa_fn(uuid),crm.preparar_prueba_push_tasa_fn(uuid),
  crm.tomar_envios_push_tasa_fn(integer),crm.materializar_envio_push_tasa_fn(uuid,uuid),
  crm.confirmar_envio_push_tasa_fn(uuid,uuid,text,integer),
  crm.verificar_cron_push_tasa_fn(text,bigint) from public,anon,authenticated,service_role;
grant execute on function crm.estado_push_tasa_fn(text),crm.registrar_push_tasa_fn(text,text,text),
  crm.desactivar_push_tasa_fn(uuid),crm.preparar_prueba_push_tasa_fn(uuid) to authenticated;
grant execute on function crm.tomar_envios_push_tasa_fn(integer),
  crm.materializar_envio_push_tasa_fn(uuid,uuid),
  crm.confirmar_envio_push_tasa_fn(uuid,uuid,text,integer),
  crm.verificar_cron_push_tasa_fn(text,bigint) to service_role;

select cron.schedule('crm-notificaciones-tasa','* * * * *','select private.despertar_push_tasa()');
notify pgrst,'reload schema';
commit;
