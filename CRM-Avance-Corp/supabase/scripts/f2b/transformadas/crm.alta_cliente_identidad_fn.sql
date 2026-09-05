CREATE OR REPLACE FUNCTION crm.alta_cliente_identidad_fn(p_paso text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_cap jsonb; v_tipo text; v_doc text; v_inv uuid; v_perfil uuid; v_activo boolean;
  v_claim uuid; v_loc record; v_r jsonb; v_hash_payload jsonb;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el alta con identidad no está activa' using errcode = 'P0409';
  end if;
  if v_uid is not null then
    v_cap := private.puede_alta_cliente();
    if coalesce((v_cap->>'ok')::boolean, false) is not true then
      raise exception 'No autorizado para crear clientes' using errcode = '42501';
    end if;
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;

  if p_paso = 'reclamar' then
    v_tipo := coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(p_payload->>'tipo_documento')), ''), 'DNI');
    -- Misma normalización que el resolver (el lookup del perfil por documento la necesita igual).
    v_doc  := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_payload->>'documento', ''), '[^A-Za-z0-9]', '', 'g')), '');
    if v_doc is null then
      raise exception 'El documento es obligatorio para crear un cliente (identidad unificada)' using errcode = '22023';
    end if;
    -- F2.b (b5) [Codex N2]: jerarquía compartida ANTES del documento (asegurar_identidad_perfil la toma después;
    -- el offboarding la toma exclusiva): nunca documento/identidad -> jerarquía.
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
    perform private.identidad_bloquear_documento(v_tipo, v_doc);
    v_inv := private.inversionista_resolver(v_tipo, v_doc, true, 'alta_cliente');
    perform 1 from crm.inversionistas i where i.id = v_inv for update;
    -- Proyección canónica COMPLETA del alta (Codex E2 #10), sin documento (la identidad, uuid, ya lo aporta):
    v_hash_payload := pg_catalog.jsonb_build_object('v', 1, 'inv', v_inv,
      'correo', pg_catalog.lower(coalesce(p_payload->>'correo','')), 'nombre', coalesce(p_payload->>'nombre_completo',''),
      'apellidos', coalesce(p_payload->>'apellidos',''), 'nombres', coalesce(p_payload->>'nombres',''),
      'telefono', coalesce(p_payload->>'telefono',''), 'domicilio', coalesce(p_payload->'domicilio', 'null'::jsonb),
      'bancarios', coalesce(p_payload->'bancarios', 'null'::jsonb), 'asesor', coalesce(p_payload->>'asesor_id', ''));
    -- (El asesor DERIVADO del que llama no entra en la huella: otra sesión puede reanudar tras el lease.)
    -- 1) La SAGA manda antes que la existencia (Codex E2 #4): un enlace confirmado cuya respuesta se
    --    perdió se reanuda como 'enlazado' con su perfil_id, no como un rechazo.
    if exists (select 1 from crm.multiempresa_idempotencia i where i.clave = 'auth_persona:' || v_inv::text) then
      v_r := private.saga_auth_reclamar(v_inv, 'alta_cliente', v_hash_payload, null, p_payload->>'token');
      return v_r || pg_catalog.jsonb_build_object('asesor_id', coalesce(v_cap->>'asesor_id', p_payload->>'asesor_id'), 'via', coalesce(v_cap->>'via', 'service_role'));
    end if;
    -- 2) Persona ya cliente (identidad con perfil, o perfil suelto con el documento exacto creado con la
    --    bandera apagada, que se ENLAZA): resultado normal, NUNCA excepción (una excepción desharía el enlace).
    select i.perfil_id into v_perfil from crm.inversionistas i where i.id = v_inv;
    if v_perfil is null then
      select p.id into v_perfil from public.perfiles p
       where p.rol = 'cliente'
         and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni,''), '[^A-Za-z0-9]', '', 'g')) = v_doc
         and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
       limit 1;
      if v_perfil is not null then
        perform private.asegurar_identidad_perfil(v_perfil, 'alta_cliente');
      end if;
    end if;
    if v_perfil is not null then
      select p.activo into v_activo from public.perfiles p where p.id = v_perfil;
      -- Un vendedor (vía crm) solo sabe que existe y si está activo: sin ids (anti-pesca, auditor b3 M3).
      if coalesce(v_cap->>'via', '') = 'crm' and coalesce(v_cap->>'asesor_id', '') <> '' then
        return pg_catalog.jsonb_build_object('estado', 'ya_existia', 'activo', coalesce(v_activo, false), 'reanudar', false);
      end if;
      return pg_catalog.jsonb_build_object('estado', 'ya_existia', 'perfil_id', v_perfil, 'activo', coalesce(v_activo, false),
        'inversionista_id', v_inv, 'reanudar', false);
    end if;
    -- 3) Claim nuevo.
    v_r := private.saga_auth_reclamar(v_inv, 'alta_cliente', v_hash_payload, null, p_payload->>'token');
    return v_r || pg_catalog.jsonb_build_object('asesor_id', coalesce(v_cap->>'asesor_id', p_payload->>'asesor_id'), 'via', coalesce(v_cap->>'via', 'service_role'));
  end if;

  v_claim := (p_payload->>'claim_id')::uuid;
  if v_claim is null then raise exception 'Falta claim_id' using errcode = '22023'; end if;

  if p_paso = 'registrar_auth' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'auth_creado', (p_payload->>'auth_user_id')::uuid, null, (p_payload->>'version')::integer);
  elsif p_paso = 'compensar_auth' then
    -- El edge borró el Auth (perfil rechazado por datos): el claim vuelve a 'reclamado'.
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'reclamado', null, null, (p_payload->>'version')::integer);
  elsif p_paso = 'perfil_creado' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'perfil_creado', null, (p_payload->>'perfil_id')::uuid, (p_payload->>'version')::integer);
  elsif p_paso = 'enlazar' then
    -- Sin lock del claim aquí: documento -> identidad -> perfil (asegurar) -> claim (avanzar).
    select * into v_loc from private.saga_auth_localizar(v_claim);
    if not found then raise exception 'Saga: claim inexistente' using errcode = 'P0002'; end if;
    if v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_payload->>'token') then
      raise exception 'Saga: token inválido' using errcode = '42501';
    end if;
    v_perfil := coalesce((v_loc.estado->>'perfil_id')::uuid, (v_loc.estado->>'auth_user_id')::uuid);
    if v_perfil is null then raise exception 'Saga: sin perfil que enlazar' using errcode = 'P0409'; end if;
    if (p_payload->>'perfil_id') is not null and (p_payload->>'perfil_id')::uuid is distinct from v_perfil then
      raise exception 'Saga: el perfil a enlazar es el del claim, no el del payload' using errcode = 'P0409';
    end if;
    v_r := private.asegurar_identidad_perfil(v_perfil, 'alta_cliente');
    -- F2.b (b5) [E3-12]: comparación por la CANÓNICA (un enlace ya consumado se puede reintentar tras una fusión).
    if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from private.inversionista_canonica(v_loc.inversionista_id) then
      raise exception 'El perfil creado no corresponde a la persona reclamada' using errcode = 'P0409';
    end if;
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'enlazado', null, v_perfil, (p_payload->>'version')::integer) || v_r;
  end if;
  raise exception 'Paso desconocido: %', p_paso using errcode = '22023';
end;
$function$
