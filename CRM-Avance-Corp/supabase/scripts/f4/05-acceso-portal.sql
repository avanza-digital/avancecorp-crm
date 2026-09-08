-- La inversión conserva su solicitud mientras Auth avanza en el servicio externo.
-- Reutiliza el claim global de F3, su marca de servidor, token, versión y lease.
-- Ningún paso recibe documento, asesor, claim ni perfil elegidos por el cliente.
create or replace function crm.acceso_inversion_fn(p_solicitud uuid,p_paso text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_datos jsonb;
  v_auth_ctx jsonb;
  v_hash_payload jsonb;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_r jsonb;
  v_p public.perfiles%rowtype;
  v_auth uuid;
  v_version integer;
  v_token text;
  v_otras uuid[];
begin
  if p_solicitud is null or p_paso is null or p_paso not in ('reclamar','registrar_auth','crear_perfil','enlazar')
     or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'Solicitud o paso de acceso Avance inválido' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_payload) k where
    k<>'token' and not (p_paso<>'reclamar' and k='version')
    and not (p_paso='registrar_auth' and k='auth_user_id')) then
    raise exception 'El paso de acceso contiene campos no admitidos' using errcode='22023';
  end if;
  v_token:=p_payload->>'token';
  if v_token is not null and v_token !~ '^[a-f0-9]{48}$' then
    raise exception 'Token de recuperación inválido' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'confirmada' then
    v_ctx:=private.inversion_persona_contexto(v_persona);
  end if;
  if not exists(select 1 from crm.empresas e where e.id=v_s.empresa_id and e.clave='avance' and e.activa)
     or v_s.estado='cancelada' then
    raise exception 'Esta solicitud no permite completar acceso Avance' using errcode='P0409';
  end if;
  if v_s.estado='preparada' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; corresponde revisar esta solicitud antes de continuar' using errcode='P0409';
  end if;

  -- Un claim terminal conserva su clave de origen después de una fusión.
  -- Los contextos anteriores a esta ampliación usaban la persona de la solicitud.
  select * into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
    case when v_s.auth_claim_id is null then v_persona::text
      else coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text) end;
  if v_s.auth_claim_id is not null and
    (v_saga.clave is null or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text) then
    raise exception 'El proceso de acceso original requiere conciliación' using errcode='P0409';
  end if;
  -- Un enlace concluido se devuelve aunque se perdiera su respuesta. No reinicia
  -- Auth ni reescribe el perfil, su clave o su responsable.
  if v_ctx->>'perfil_id' is not null and
     (v_saga.clave is null or v_saga.resultado->>'estado'='enlazado') then
    if v_saga.clave is not null and v_saga.resultado->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El acceso y la identidad requieren conciliación' using errcode='P0409';
    end if;
    return jsonb_build_object('estado','enlazado','perfil_id',v_ctx->>'perfil_id',
      'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
  end if;
  if v_s.estado='confirmada' then
    raise exception 'El acceso de la inversión confirmada requiere conciliación' using errcode='P0409';
  end if;
  v_datos:=private.inversion_datos_portal(v_s.datos->'alta_portal');
  v_auth_ctx:=coalesce(v_s.auth_contexto,jsonb_build_object('documento_tipo',v_ctx->>'documento_tipo',
    'documento',v_ctx->>'documento','responsable_id',v_ctx->>'responsable_id','inversionista_id',v_persona));
  if v_auth_ctx->>'documento_tipo' is distinct from v_ctx->>'documento_tipo'
     or v_auth_ctx->>'documento' is distinct from v_ctx->>'documento' then
    raise exception 'El documento cambió durante el alta; corresponde revisar el acceso pendiente' using errcode='P0409';
  end if;
  -- Misma proyección que alta_cliente_identidad_fn; los bancos pertenecen a la
  -- cuenta contractual de esta inversión. El responsable inicial fija la huella.
  v_hash_payload:=jsonb_build_object('v',1,'inv',v_persona,'correo',v_datos->>'correo',
    'nombre',v_datos->>'nombre_completo','apellidos',coalesce(v_datos->>'apellidos',''),
    'nombres',coalesce(v_datos->>'nombres',''),'telefono',coalesce(v_datos->>'telefono',''),
    'domicilio',v_datos->'domicilio','bancarios','null'::jsonb,'asesor',v_auth_ctx->>'responsable_id');

  if p_paso='reclamar' then
    -- Una segunda solicitud no sustituye un alta pendiente de esta persona.
    -- Incluso "reclamado" puede tener Auth creado con respuesta perdida.
    if v_saga.clave is not null and v_saga.resultado->>'estado'<>'enlazado' then
      if exists(select 1 from crm.inversion_solicitudes s where s.id<>v_s.id
        and s.auth_claim_id=(v_saga.resultado->>'claim_id')::uuid) then
        raise exception 'Completa el acceso pendiente desde su solicitud original' using errcode='P0409';
      end if;
      if v_saga.hash_payload is distinct from private.idem_hash(v_hash_payload) then
        raise exception 'La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales' using errcode='P0409';
      end if;
    end if;
    if v_saga.clave is null then
      select array_agg(p.id order by p.id) into v_otras from public.perfiles p
      where p.rol='cliente' and p.tipo_documento=v_ctx->>'documento_tipo'
        and upper(regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g'))=v_ctx->>'documento';
      if coalesce(cardinality(v_otras),0)>1 then
        raise exception 'Hay varios perfiles con ese documento; requiere conciliación' using errcode='P0409';
      elsif cardinality(v_otras)=1 then
        perform private.asegurar_identidad_perfil(v_otras[1],'f4_acceso_portal');
        v_ctx:=private.inversion_persona_contexto(v_persona);
        if v_ctx->>'perfil_id' is distinct from v_otras[1]::text then
          raise exception 'El perfil existente no pertenece a esta persona' using errcode='P0409';
        end if;
        return jsonb_build_object('estado','enlazado','perfil_id',v_otras[1],
          'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
      end if;
    end if;
    v_r:=private.saga_auth_reclamar(v_persona,'alta_cliente',v_hash_payload,null,v_token);
    if v_r->>'estado'='enlazado' and (v_ctx->>'perfil_id' is null
       or v_r->>'perfil_id' is distinct from v_ctx->>'perfil_id') then
      raise exception 'El perfil del acceso requiere conciliación con esta persona' using errcode='P0409';
    end if;
    if v_s.auth_claim_id is not null and v_s.auth_claim_id is distinct from (v_r->>'claim_id')::uuid then
      raise exception 'El proceso de acceso cambió; requiere revisión' using errcode='P0409';
    end if;
    update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,
      auth_contexto=v_auth_ctx,actualizado_en=statement_timestamp() where id=v_s.id;
    return v_r||jsonb_build_object('solicitud_id',v_s.id,'datos_portal',v_datos,
      'documento_tipo',v_auth_ctx->>'documento_tipo','documento',v_auth_ctx->>'documento');
  end if;

  if v_s.auth_claim_id is null or v_saga.clave is null
     or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text then
    raise exception 'Primero reclama el acceso desde esta solicitud' using errcode='P0409';
  end if;
  -- El perfil y el avance de estado se confirman juntos. Una versión antigua
  -- no puede dejar un perfil insertado ni enlazarlo por fuera de su claim.
  select * into v_saga from crm.multiempresa_idempotencia where clave=v_saga.clave for update;
  if v_token is null or v_saga.resultado->>'token_hash' is distinct from private.saga_token_hash(v_token) then
    raise exception 'Token de recuperación inválido' using errcode='42501';
  end if;
  begin v_version:=(p_payload->>'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Versión del acceso inválida' using errcode='22023';
  end;
  if v_version is null or v_saga.version is distinct from v_version then
    raise exception 'El acceso cambió; vuelve a reclamar con tu token' using errcode='40001';
  end if;
  if p_paso='registrar_auth' then
    begin v_auth:=(p_payload->>'auth_user_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de acceso inválido' using errcode='22023';
    end;
  else
    v_auth:=(v_saga.resultado->>'auth_user_id')::uuid;
  end if;
  if not exists(select 1 from auth.users u where u.id=v_auth
    and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
    and lower(u.email)=v_datos->>'correo') then
    raise exception 'El acceso no pertenece a esta solicitud o a su correo' using errcode='P0409';
  end if;
  if p_paso='registrar_auth' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'auth_creado',v_auth,null,v_version);
  end if;
  if v_saga.resultado->>'estado' not in ('auth_creado','perfil_creado') then
    raise exception 'El estado del acceso no permite este paso' using errcode='P0409';
  end if;
  select * into v_p from public.perfiles where id=v_auth for update;
  if not found and p_paso='crear_perfil' then
    insert into public.perfiles(id,rol,activo,nombre_completo,apellidos,nombres,tipo_documento,dni,
      correo,telefono,domicilio,asesor_perfil_id,creado_por,debe_cambiar_password)
    values(v_auth,'cliente',true,v_datos->>'nombre_completo',v_datos->>'apellidos',v_datos->>'nombres',
      v_auth_ctx->>'documento_tipo',v_auth_ctx->>'documento',v_datos->>'correo',v_datos->>'telefono',
      v_datos->>'domicilio',(v_ctx->>'responsable_id')::uuid,(select auth.uid()),true)
    returning * into v_p;
  end if;
  if v_p.id is null or v_p.rol<>'cliente' or v_p.activo is not true
     or v_p.tipo_documento is distinct from v_auth_ctx->>'documento_tipo'
     or v_p.dni is distinct from v_auth_ctx->>'documento'
     or lower(v_p.correo) is distinct from v_datos->>'correo'
     or v_p.asesor_perfil_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El perfil pendiente requiere conciliación con esta persona y su responsable' using errcode='P0409';
  end if;
  if p_paso='crear_perfil' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'perfil_creado',null,v_auth,v_version);
  end if;
  v_r:=private.asegurar_identidad_perfil(v_auth,'f4_acceso_portal');
  if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from v_persona then
    raise exception 'El perfil no corresponde a la persona de la inversión' using errcode='P0409';
  end if;
  return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'enlazado',null,v_auth,v_version)
    ||jsonb_build_object('solicitud_id',v_s.id);
end;
$$;
revoke all on function crm.acceso_inversion_fn(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function crm.acceso_inversion_fn(uuid,text,jsonb) to authenticated;
