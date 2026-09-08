-- Procedencia documental inmutable. No concede acceso Portal ni atribución comercial.
create table crm.inversion_cotitular_origenes (
  id uuid primary key default gen_random_uuid(),
  contrato_titular_id uuid not null unique references public.contrato_titulares(id) on delete restrict,
  inversion_id uuid not null references crm.inversiones(id),
  persona_origen_id uuid not null references crm.inversionistas(id),
  identificador_origen_id uuid not null references crm.inversionista_identificadores(id),
  fuente_snapshot jsonb not null,
  identificador_snapshot jsonb not null,
  hash_fuente text not null,
  vinculado_por uuid references public.perfiles(id),
  origen_registro text not null check(origen_registro in ('alta','conciliacion','administracion')),
  operador_sql text not null default session_user,
  vinculado_en timestamptz not null default statement_timestamp()
);
create index inversion_cotitular_origen_inversion_idx on crm.inversion_cotitular_origenes(inversion_id);
create index inversion_cotitular_origen_persona_idx on crm.inversion_cotitular_origenes(persona_origen_id);
create index inversion_cotitular_origen_identificador_idx on crm.inversion_cotitular_origenes(identificador_origen_id);
create index inversion_cotitular_origen_actor_idx on crm.inversion_cotitular_origenes(vinculado_por);
alter table crm.inversion_cotitular_origenes enable row level security;
revoke all on crm.inversion_cotitular_origenes from public,anon,authenticated,service_role;
create trigger trg_audit_cotitular_origen after insert on crm.inversion_cotitular_origenes
  for each row execute function private.log_audit_sin_secretos('fuente_snapshot','identificador_snapshot','hash_fuente');

create or replace function private.f4_proteger_origen_cotitular()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_schema='crm' then
    raise exception 'La procedencia del cotitular conserva su registro original' using errcode='P0409';
  end if;
  if tg_op='UPDATE' and to_jsonb(new)=to_jsonb(old) then return new; end if;
  if exists(select 1 from crm.inversion_cotitular_origenes where contrato_titular_id=old.id) then
    raise exception 'El titular documental tiene procedencia neutral; conserva el documento original' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.f4_proteger_origen_cotitular() from public,anon,authenticated,service_role;
create trigger trg_cotitular_origen_inmutable before update or delete on crm.inversion_cotitular_origenes
  for each row execute function private.f4_proteger_origen_cotitular();
create trigger trg_titular_procedencia_inmutable before update or delete on public.contrato_titulares
  for each row execute function private.f4_proteger_origen_cotitular();

-- Sólo consume identidades verificadas. Un documento histórico reutilizado por
-- otra persona queda en revisión: nunca se adivina quién firmó el contrato.
create or replace function private.inversion_cotitular_estado(p_titular uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_t public.contrato_titulares%rowtype;
  v_o crm.inversion_cotitular_origenes%rowtype;
  v_d crm.inversionista_identificadores%rowtype;
  v_i uuid; v_p uuid; v_norm text; v_base jsonb; v_duenos integer;
begin
  select * into v_t from public.contrato_titulares where id=p_titular;
  if not found then raise exception 'Titular no encontrado' using errcode='P0002'; end if;
  select id into v_i from crm.inversiones where contrato_id=v_t.contrato_id;
  v_base:=jsonb_build_object('titular_id',v_t.id,'orden',v_t.orden,'inversion_id',v_i);
  select * into v_o from crm.inversion_cotitular_origenes where contrato_titular_id=v_t.id;
  if found then
    v_p:=private.inversionista_canonica(v_o.persona_origen_id);
    if v_o.inversion_id is distinct from v_i or v_o.hash_fuente is distinct from private.idem_hash(to_jsonb(v_t))
      or not exists(select 1 from crm.inversion_titulares where inversion_id=v_i and inversionista_id=v_p) then
      return v_base||jsonb_build_object('estado','revision','motivo','procedencia_incoherente');
    end if;
    return v_base||jsonb_build_object('estado','vinculado','inversionista_id',v_p,
      'persona_origen_id',v_o.persona_origen_id,'origen_registro',v_o.origen_registro);
  end if;
  if v_i is null or not private.contrato_documental_congelado(v_t.contrato_id) then
    return v_base||jsonb_build_object('estado','pendiente','motivo','sin_inversion_o_snapshot');
  end if;
  v_norm:=upper(regexp_replace(coalesce(v_t.documento,''),'[^A-Za-z0-9]','','g'));
  select count(distinct private.inversionista_canonica(inversionista_id)) into v_duenos
    from crm.inversionista_identificadores where tipo_documento=v_t.tipo_documento and documento_normalizado=v_norm and verificado;
  if v_duenos>1 then
    return v_base||jsonb_build_object('estado','revision','motivo','documento_reutilizado');
  end if;
  select d.* into v_d from crm.inversionista_identificadores d join crm.inversionistas p on p.id=d.inversionista_id
    where d.tipo_documento=v_t.tipo_documento and d.documento_normalizado=v_norm and d.estado='vigente'
      and d.verificado and p.estado='activo' and private.inversionista_canonica(p.id)=p.id;
  if not found then
    return v_base||jsonb_build_object('estado','pendiente','motivo','identidad_verificada_pendiente');
  end if;
  return v_base||jsonb_build_object('estado','disponible','inversionista_id',v_d.inversionista_id,
    'identificador_id',v_d.id);
end;
$$;
revoke all on function private.inversion_cotitular_estado(uuid) from public,anon,authenticated,service_role;

create or replace function private.inversion_cotitulares_vincular(p_inversion uuid,p_origen_registro text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  v_i crm.inversiones%rowtype; v_t public.contrato_titulares%rowtype;
  v_d crm.inversionista_identificadores%rowtype; v_s jsonb; v_res jsonb:='[]'; v_p uuid;
begin
  if current_user<>'postgres' or p_origen_registro not in ('alta','conciliacion','administracion') then
    raise exception 'Operación interna' using errcode='42501';
  end if;
  select * into v_i from crm.inversiones where id=p_inversion for update nowait;
  if not found then raise exception 'Inversión no encontrada' using errcode='P0002'; end if;
  if v_i.contrato_id is null then return v_res; end if;
  perform 1 from public.contratos where id=v_i.contrato_id for share nowait;
  for v_t in select * from public.contrato_titulares where contrato_id=v_i.contrato_id order by orden,id loop
    begin
      perform 1 from public.contrato_titulares where id=v_t.id for update nowait;
      v_s:=private.inversion_cotitular_estado(v_t.id);
      if v_s->>'estado'='disponible' then
        -- Misma clave que F3; no esperar una corrección/fusión que necesita la
        -- persona principal ya bloqueada por el alta de esta inversión.
        if not pg_try_advisory_xact_lock(hashtext('inv_resolver:'||v_t.tipo_documento||':'||
          upper(regexp_replace(coalesce(v_t.documento,''),'[^A-Za-z0-9]','','g')))) then
          raise lock_not_available;
        end if;
        v_p:=(v_s->>'inversionista_id')::uuid;
        perform 1 from crm.inversionistas where id=v_p for update nowait;
        v_s:=private.inversion_cotitular_estado(v_t.id);
        if v_s->>'estado'='disponible' and (v_s->>'inversionista_id')::uuid=v_p then
          select * into strict v_d from crm.inversionista_identificadores where id=(v_s->>'identificador_id')::uuid;
          insert into crm.inversion_titulares(inversion_id,inversionista_id,rol,creado_por)
            values(v_i.id,v_p,'cotitular',(select auth.uid())) on conflict(inversion_id,inversionista_id) do nothing;
          insert into crm.inversion_cotitular_origenes(contrato_titular_id,inversion_id,persona_origen_id,
            identificador_origen_id,fuente_snapshot,identificador_snapshot,hash_fuente,vinculado_por,origen_registro)
            values(v_t.id,v_i.id,v_p,v_d.id,to_jsonb(v_t),to_jsonb(v_d),private.idem_hash(to_jsonb(v_t)),(select auth.uid()),p_origen_registro);
          v_s:=private.inversion_cotitular_estado(v_t.id);
        end if;
      end if;
    exception when lock_not_available or deadlock_detected then
      v_s:=jsonb_build_object('titular_id',v_t.id,'orden',v_t.orden,'inversion_id',v_i.id,
        'estado','pendiente','motivo','identidad_ocupada');
    end;
    -- El lector comercial no recibe identificadores privados ni huellas.
    v_res:=v_res||jsonb_build_array(v_s-'identificador_id');
  end loop;
  return v_res;
end;
$$;
revoke all on function private.inversion_cotitulares_vincular(uuid,text) from public,anon,authenticated,service_role;

create or replace function crm.inversion_cotitulares_fn(p_inversion uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_i crm.inversiones%rowtype; v_res jsonb;
begin
  select * into v_i from crm.inversiones where id=p_inversion;
  if not found then raise exception 'Inversión no encontrada' using errcode='P0002'; end if;
  perform private.inversion_persona_autorizada(v_i.inversionista_id);
  select coalesce(jsonb_agg(private.inversion_cotitular_estado(t.id)-'identificador_id' order by t.orden,t.id),'[]') into v_res
    from public.contrato_titulares t where t.contrato_id=v_i.contrato_id;
  return v_res;
end;
$$;
revoke all on function crm.inversion_cotitulares_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.inversion_cotitulares_fn(uuid) to authenticated;

create or replace function crm.conciliar_cotitulares_inversion_fn(p_inversion uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_p uuid;
begin
  select inversionista_id into v_p from crm.inversiones where id=p_inversion;
  if not found then raise exception 'Inversión no encontrada' using errcode='P0002'; end if;
  perform private.inversion_persona_autorizada(v_p);
  return private.inversion_cotitulares_vincular(p_inversion,'conciliacion');
end;
$$;
revoke all on function crm.conciliar_cotitulares_inversion_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.conciliar_cotitulares_inversion_fn(uuid) to authenticated;

create or replace function private.inversion_cotitulares_historicos(p_inversion uuid)
returns jsonb language plpgsql security invoker set search_path='' set lock_timeout='5s' as $$
begin
  if session_user not in ('postgres','supabase_admin') or current_user<>'postgres' then
    raise exception 'Operación administrativa SQL' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  if exists(select 1 from crm.multiempresa_flags where nombre='inversiones_escritura' and activo) then
    raise exception 'La conciliación histórica requiere F4 apagada' using errcode='P0409';
  end if;
  return private.inversion_cotitulares_vincular(p_inversion,'administracion');
end;
$$;
revoke all on function private.inversion_cotitulares_historicos(uuid) from public,anon,authenticated,service_role;
