-- Corrección de correos de CLIENTES por admin/superadmin (15/09/2026).
-- La Admin API de Auth cambia email + identidad. El trigger incluye perfil
-- y acuse en ESA MISMA transacción: un rechazo revierte las tres piezas.
-- Requiere aprobación para los triggers sobre auth.users y public.perfiles.
-- Sustituye la propuesta no instalada 20260908221500/20260908221501.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create table crm.correcciones_correo_acceso (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null,
  por uuid not null,
  correo_anterior text not null,
  correo_nuevo text not null,
  motivo text not null check (length(motivo) between 3 and 500),
  creado_en timestamptz not null default now(),
  auth_confirmado_en timestamptz,
  transaccion_confirmada xid8
);
-- Sin FK: el rastro sobrevive a la eliminación de una cuenta.
alter table crm.correcciones_correo_acceso enable row level security;
alter table crm.correcciones_correo_acceso force row level security;
revoke all on crm.correcciones_correo_acceso from public, anon, authenticated, service_role;
grant select on crm.correcciones_correo_acceso to authenticated;
create policy correcciones_correo_acceso_lectura on crm.correcciones_correo_acceso
  for select to authenticated using (public.es_admin());
create trigger trg_audit_correcciones_correo_acceso
  after insert or update or delete on crm.correcciones_correo_acceso
  for each row execute function private.log_audit_crm();

-- Solo la Edge puede preparar una operación, DESPUÉS de verificar el JWT.
create function crm.preparar_correccion_correo_acceso_fn(
  p_cliente_id uuid, p_actor_id uuid, p_correo text, p_motivo text
) returns uuid language plpgsql security definer set search_path = '' set lock_timeout='5s' as $$
declare
  v_correo text := lower(btrim(coalesce(p_correo, '')));
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_anterior text;
  v_id uuid;
begin
  if p_cliente_id = p_actor_id or not exists (
    select 1 from public.perfiles where id=p_actor_id
      and activo and rol in ('admin','superadmin')
  ) then
    raise exception 'Solo un administrador activo puede corregir el correo de un cliente' using errcode='42501';
  end if;
  if length(v_correo) > 254 or v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'El correo electrónico no es válido' using errcode='22023';
  end if;
  if length(v_motivo) not between 3 and 500 then
    raise exception 'El motivo debe tener entre 3 y 500 caracteres' using errcode='22023';
  end if;
  select coalesce(u.email,'') into v_anterior
    from public.perfiles p join auth.users u on u.id=p.id
    where p.id=p_cliente_id and p.rol='cliente';
  if not found then
    raise exception 'El cliente no existe o no tiene cuenta de acceso' using errcode='P0002';
  end if;
  if exists (select 1 from public.perfiles where id<>p_cliente_id and lower(correo)=v_correo)
     or exists (select 1 from auth.users where id<>p_cliente_id and lower(email)=v_correo) then
    raise exception 'Ese correo ya pertenece a otra cuenta' using errcode='23505';
  end if;
  insert into crm.correcciones_correo_acceso(cliente_id,por,correo_anterior,correo_nuevo,motivo)
    values(p_cliente_id,p_actor_id,v_anterior,v_correo,v_motivo) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function crm.preparar_correccion_correo_acceso_fn(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function crm.preparar_correccion_correo_acceso_fn(uuid,uuid,text,text) to service_role;

-- GoTrue puede escribir email y app_metadata en sentencias separadas dentro
-- de una transacción. Se valida el ESTADO FINAL al commit, no una fila intermedia.
create function private.sincronizar_correo_cliente_auth() returns trigger
language plpgsql security definer set search_path = '' set lock_timeout='5s' as $$
declare
  v_actual auth.users%rowtype;
  v_marca text;
  v_previa text := old.raw_app_meta_data->>'correccion_correo_acceso_id';
  v_rastro crm.correcciones_correo_acceso%rowtype;
  v_rol text;
  v_guc text := current_setting('crm.correccion_correo_acceso_id',true);
begin
  select * into v_actual from auth.users where id=new.id;
  if not found then return new; end if;
  v_marca := v_actual.raw_app_meta_data->>'correccion_correo_acceso_id';
  if v_actual.email is not distinct from old.email and v_marca is not distinct from v_previa then
    return new;
  end if;
  select rol into v_rol from public.perfiles where id=new.id for update;
  if v_marca is not distinct from v_previa then
    if v_rol='cliente' then
      raise exception 'El correo de acceso se corrige desde Administración' using errcode='42501';
    end if;
    return new;
  end if;
  if v_rol is distinct from 'cliente' or v_marca is null then
    raise exception 'La corrección de correo solo admite cuentas de clientes' using errcode='42501';
  end if;
  select * into v_rastro from crm.correcciones_correo_acceso
    where id=v_marca::uuid and cliente_id=new.id for update;
  if not found or v_rastro.correo_nuevo is distinct from lower(v_actual.email) then
    raise exception 'La corrección de correo no corresponde a esta cuenta' using errcode='42501';
  end if;
  if v_rastro.auth_confirmado_en is not null then
    -- Las sentencias intermedias de GoTrue pueden encolar más de un evento.
    if v_rastro.transaccion_confirmada = pg_current_xact_id() then return new; end if;
    raise exception 'La corrección de correo ya fue utilizada' using errcode='42501';
  end if;
  perform 1 from public.perfiles where id=v_rastro.por and activo
    and rol in ('admin','superadmin') for share;
  if not found then
    raise exception 'El administrador ya no tiene permiso para corregir el correo' using errcode='42501';
  end if;
  if v_actual.email_confirmed_at is null or not exists (
    select 1 from auth.identities where user_id=new.id and provider='email'
      and lower(identity_data->>'email')=lower(v_actual.email)
  ) then
    raise exception 'La identidad de correo no quedó confirmada' using errcode='23514';
  end if;
  perform set_config('crm.correccion_correo_acceso_id',v_marca,true);
  update public.perfiles set correo=lower(v_actual.email), actualizado_en=now() where id=new.id;
  update crm.correcciones_correo_acceso
    set correo_anterior=coalesce(old.email,''), auth_confirmado_en=now(),
        transaccion_confirmada=pg_current_xact_id() where id=v_rastro.id;
  perform set_config('crm.correccion_correo_acceso_id',coalesce(v_guc,''),true);
  return new;
end;
$$;
revoke all on function private.sincronizar_correo_cliente_auth() from public,anon,authenticated,service_role;
create constraint trigger trg_auth_correo_cliente_atomico
  after update on auth.users deferrable initially deferred
  for each row when (old.email is distinct from new.email or
    old.raw_app_meta_data->>'correccion_correo_acceso_id' is distinct from new.raw_app_meta_data->>'correccion_correo_acceso_id')
  execute function private.sincronizar_correo_cliente_auth();

create function private.proteger_correo_cliente_acceso() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_marca text := nullif(current_setting('crm.correccion_correo_acceso_id',true),'');
begin
  if (old.rol='cliente' or new.rol='cliente') and new.correo is distinct from old.correo then
    if v_marca is null or not exists (
      select 1 from crm.correcciones_correo_acceso r join auth.users u on u.id=r.cliente_id
      where r.id=v_marca::uuid and r.cliente_id=new.id and r.auth_confirmado_en is null
        and r.correo_nuevo=new.correo and lower(u.email)=new.correo
        and u.raw_app_meta_data->>'correccion_correo_acceso_id'=v_marca
    ) then
      raise exception 'El correo de acceso se corrige desde Administración' using errcode='42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.proteger_correo_cliente_acceso() from public,anon,authenticated,service_role;
create trigger trg_perfiles_correo_acceso_protegido
  before update of correo on public.perfiles
  for each row execute function private.proteger_correo_cliente_acceso();

comment on table crm.correcciones_correo_acceso is
  'Correcciones de acceso de clientes. auth_confirmado_en se sella dentro de la transacción de Auth que actualiza el perfil; NULL es un intento pendiente o rechazado, nunca un éxito.';
notify pgrst,'reload schema';
commit;
