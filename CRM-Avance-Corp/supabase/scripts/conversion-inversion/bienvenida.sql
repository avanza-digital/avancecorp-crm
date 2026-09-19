-- Estado de entrega separado del resultado económico. Un error de correo no
-- revierte ni vuelve a confirmar una inversión. Sin credenciales en el payload.
alter table crm.inversion_solicitudes add column bienvenida jsonb;

create or replace function crm.bienvenida_inversion_estado_fn(p_solicitud uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s crm.inversion_solicitudes%rowtype;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  select * into s from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='42501'; end if;
  perform private.inversion_persona_autorizada(s.inversionista_id);
  if s.estado<>'confirmada' then
    raise exception 'La inversión todavía no está confirmada' using errcode='P0409';
  end if;
  return jsonb_build_object('estado',coalesce(s.bienvenida->>'estado','no_corresponde'));
end $$;
revoke all on function crm.bienvenida_inversion_estado_fn(uuid) from public,anon,service_role;
grant execute on function crm.bienvenida_inversion_estado_fn(uuid) to authenticated;

-- Sólo la Edge obtiene el destinatario congelado y registra la respuesta del
-- proveedor. El usuario no puede fingir un envío ni cambiar el destinatario.
create or replace function crm.bienvenida_inversion_entrega_fn(
  p_solicitud uuid,p_paso text,p_token uuid default null,p_proveedor_id text default null
) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare s crm.inversion_solicitudes%rowtype; b jsonb; token uuid;
begin
  if (select auth.role()) is distinct from 'service_role' then
    raise exception 'Sólo el servicio registra la entrega' using errcode='42501';
  end if;
  select * into s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or s.estado<>'confirmada' or s.lead_origen_id is null then
    raise exception 'Inversión no confirmada' using errcode='P0409';
  end if;
  b:=s.bienvenida;
  if b is null then return jsonb_build_object('estado','no_corresponde'); end if;
  if p_paso='reclamar' then
    if b->>'estado' in ('enviada','verificar_entrega') then
      return jsonb_build_object('estado',b->>'estado');
    end if;
    -- Resend conserva su Idempotency-Key 24 h. Se corta a las 23 h desde
    -- ANTES de la primera llamada: nunca se reenvía con una clave vencida.
    if (b->>'primer_intento')::timestamptz < now()-interval '23 hours' then
      update crm.inversion_solicitudes set bienvenida=b||jsonb_build_object('estado','verificar_entrega') where id=s.id;
      return jsonb_build_object('estado','verificar_entrega');
    end if;
    if (b->>'lease_hasta')::timestamptz > now() then
      return jsonb_build_object('estado','en_proceso');
    end if;
    token:=gen_random_uuid();
    b:=b||jsonb_build_object('estado','en_proceso','token',token,
      'primer_intento',coalesce((b->>'primer_intento')::timestamptz,now()),
      'lease_hasta',now()+interval '1 minute');
    update crm.inversion_solicitudes set bienvenida=b where id=s.id;
    return jsonb_build_object('estado','enviar','token',token,
      'clave','conversion-bienvenida-v1/'||s.id::text,'correo',b->>'correo','nombre',b->>'nombre');
  elsif p_paso='confirmar' then
    if b->>'estado'='enviada' then return jsonb_build_object('estado','enviada'); end if;
    if p_token is null or p_token is distinct from (b->>'token')::uuid
      or nullif(btrim(p_proveedor_id),'') is null or length(p_proveedor_id)>180 then
      raise exception 'Confirmación de entrega inválida' using errcode='P0409';
    end if;
    update crm.inversion_solicitudes set bienvenida=(b-'token'-'lease_hasta')||
      jsonb_build_object('estado','enviada','proveedor_id',p_proveedor_id,'enviada_en',now()) where id=s.id;
    return jsonb_build_object('estado','enviada');
  end if;
  raise exception 'Paso de entrega inválido' using errcode='22023';
end $$;
revoke all on function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) to service_role;
