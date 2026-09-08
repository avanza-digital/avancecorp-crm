-- Las puertas Avance conservan su autoridad y cálculo. Estos observadores
-- completan el enlace relacional en la misma transacción de TODAS las altas.
create or replace function private.f4_contrato_reconocer()
returns trigger language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
begin
  if private.inversiones_escritura_bajo_candado() then
    perform private.asegurar_identidad_perfil(new.cliente_id,'contrato');
  end if;
  return new;
end;
$$;
revoke all on function private.f4_contrato_reconocer() from public,anon,authenticated,service_role;
create trigger trg_contratos_000_f4_reconocer before insert on public.contratos
  for each row execute function private.f4_contrato_reconocer();

create or replace function private.f4_contrato_vincular()
returns trigger language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_persona uuid;
begin
  if private.inversiones_escritura_bajo_candado() then
    select id into v_persona from crm.inversionistas
    where perfil_id=new.cliente_id and estado<>'fusionado';
    if v_persona is null then raise exception 'F4: falta la identidad del contrato' using errcode='P0409'; end if;
    perform private.inversion_vincular_fuente(v_persona,new.id,null,new.creado_por,false);
  end if;
  return new;
end;
$$;
revoke all on function private.f4_contrato_vincular() from public,anon,authenticated,service_role;
create trigger trg_contratos_f4_vincular after insert on public.contratos
  for each row execute function private.f4_contrato_vincular();
