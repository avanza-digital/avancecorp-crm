CREATE OR REPLACE FUNCTION crm.saga_conversion_fn(p_paso text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_claim uuid; v_loc record; v_res jsonb; v_perfil uuid; v_lead uuid; v_inv_conv uuid; v_tipo text; v_doc text;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;
  v_claim := (p_payload->>'claim_id')::uuid;
  if v_claim is null then raise exception 'Falta claim_id' using errcode = '22023'; end if;
  if (p_payload->>'version') is null then raise exception 'Falta version (CAS)' using errcode = '22023'; end if;

  if p_paso = 'registrar_auth' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'auth_creado', (p_payload->>'auth_user_id')::uuid, null, (p_payload->>'version')::integer);
  elsif p_paso = 'compensar_auth' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'reclamado', null, null, (p_payload->>'version')::integer);
  elsif p_paso = 'perfil_creado' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'perfil_creado', null, (p_payload->>'perfil_id')::uuid, (p_payload->>'version')::integer);
  elsif p_paso = 'cerrar' then
    -- CIERRE TRANSACCIONAL (Codex E2 #7): convertir y comprobar que la identidad convertida es la
    -- reservada, o revertir todo. Orden: (convertir_lead) documento -> identidad -> lead -> reserva -> claim.
    select * into v_loc from private.saga_auth_localizar(v_claim);
    if not found then raise exception 'Saga: claim inexistente' using errcode = 'P0002'; end if;
    if v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_payload->>'token') then
      raise exception 'Saga: token inválido' using errcode = '42501';
    end if;
    v_lead   := coalesce((p_payload->>'lead_id')::uuid, (v_loc.estado->>'lead_id')::uuid);
    v_perfil := coalesce((p_payload->>'perfil_id')::uuid, (v_loc.estado->>'perfil_id')::uuid, (v_loc.estado->>'auth_user_id')::uuid);
    if v_lead is null or v_perfil is null then
      raise exception 'Saga: faltan lead o perfil para cerrar' using errcode = 'P0409';
    end if;
    if (v_loc.estado->>'lead_id')::uuid is distinct from v_lead then
      raise exception 'Saga: el lead no es el reservado en este claim' using errcode = 'P0409';
    end if;
    -- El perfil de un claim con Auth es ese Auth: no se cierra con otro perfil (auditor b4 M1).
    if (v_loc.estado->>'auth_user_id') is not null and v_perfil is distinct from (v_loc.estado->>'auth_user_id')::uuid then
      raise exception 'Saga: el perfil no corresponde al usuario de Auth de este claim' using errcode = 'P0409';
    end if;
    -- F2.b (b5) [E3-1]: documento ANTES de identidad (la fusión toma documento -> identidad;
    -- convertir_lead resolverá este mismo documento, reentrante).
    select coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI'), p.dni into v_tipo, v_doc
      from public.perfiles p where p.id = v_perfil;
    if v_doc is null then
      raise exception 'Saga: el perfil del claim no existe o no tiene documento' using errcode = 'P0409';
    end if;
    perform private.identidad_bloquear_documento(v_tipo, v_doc);
    -- Veto revalidado también al cerrar (Codex E2 #11): con veto, la conversión no se consuma.
    perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
    if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
      raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
    end if;
    v_res := crm.convertir_lead_con_domicilio(v_lead, v_perfil, p_payload->>'domicilio');
    v_inv_conv := (v_res->>'inversionista_id')::uuid;
    -- F2.b (b5) [E3-12]: comparación por la CANÓNICA (una fusión posterior no invalida el reintento de un cierre ya consumado).
    if private.inversionista_canonica(v_inv_conv) is distinct from private.inversionista_canonica(v_loc.inversionista_id) then
      raise exception 'La persona convertida no es la persona reservada (el documento cambió): se revierte la conversión'
        using errcode = 'P0409';
    end if;
    return v_res || private.saga_auth_avanzar(v_claim, p_payload->>'token', 'enlazado', null, v_perfil, (p_payload->>'version')::integer)
           || pg_catalog.jsonb_build_object('inversionista_id', private.inversionista_canonica(v_inv_conv));
  end if;
  raise exception 'Paso desconocido: %', p_paso using errcode = '22023';
end;
$function$
