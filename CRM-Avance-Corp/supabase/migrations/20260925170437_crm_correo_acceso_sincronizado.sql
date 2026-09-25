-- Correo de acceso previo al alta: ficha, revisión y reserva comparten el dato.
-- La creación Auth y la corrección se serializan en solicitud -> saga. No se
-- usa el vencimiento del lease como prueba de que terminó una petición externa.
begin;
set local lock_timeout = '5s';

-- Baseline contrastado con producción en lectura el 25/09/2026.
-- La allowlist admite ese baseline o el candidato final para reaplicación local.
do $preflight$ begin
  if md5(pg_get_functiondef('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'::regprocedure)) not in ('3e09703845f2824054ead959fec40e47','c41aa8ee34da4b3f828289058c41e4f4') then
    raise exception 'Cambió crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text); revisar antes de aplicar' using errcode='P0409';
  end if;
  if md5(pg_get_functiondef('crm.acceso_inversion_fn(uuid,text,jsonb)'::regprocedure)) not in ('e4730d0161710fc8a84fb6dc7635bf47','38229cbb9fde4d9b5e23ee55ca6e6784') then
    raise exception 'Cambió crm.acceso_inversion_fn(uuid,text,jsonb); revisar antes de aplicar' using errcode='P0409';
  end if;
  if md5(pg_get_functiondef('private.inversion_datos_portal(jsonb)'::regprocedure)) not in ('170faaab19c7cc78e187909ffe039adb') then
    raise exception 'Cambió private.inversion_datos_portal(jsonb); revisar antes de aplicar' using errcode='P0409';
  end if;
  if md5(pg_get_functiondef('private.saga_auth_reclamar(uuid,text,jsonb,uuid,text)'::regprocedure)) not in ('ea87dff458d044e376ce11169aa07c1d') then
    raise exception 'Cambió private.saga_auth_reclamar(uuid,text,jsonb,uuid,text); revisar antes de aplicar' using errcode='P0409';
  end if;
  if md5(pg_get_functiondef('private.saga_auth_avanzar(uuid,text,text,uuid,uuid,integer)'::regprocedure)) not in ('217eba2c7f9e1323d3dd82c652e7f48a') then
    raise exception 'Cambió private.saga_auth_avanzar(uuid,text,text,uuid,uuid,integer); revisar antes de aplicar' using errcode='P0409';
  end if;
  if md5(pg_get_functiondef('private.inversion_solicitud_resultado(uuid,jsonb)'::regprocedure)) not in ('2ce92b3e2327a1f7a585f0053cb59bc4','9763d1c08124caafc84709c8d7dabfe2') then
    raise exception 'Cambió private.inversion_solicitud_resultado(uuid,jsonb); revisar antes de aplicar' using errcode='P0409';
  end if;
end $preflight$;


create or replace function private.inversion_correo_normalizado(p_correo text)
returns text language sql immutable set search_path = '' as $$
  select nullif(lower(btrim(p_correo)), '');
$$;

create or replace function private.inversion_payload_acceso(p_persona uuid, p_portal jsonb, p_responsable text)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare d jsonb := private.inversion_datos_portal(p_portal);
begin
  return jsonb_build_object('v',1,'inv',p_persona,'correo',d->>'correo',
    'nombre',d->>'nombre_completo','apellidos',coalesce(d->>'apellidos',''),
    'nombres',coalesce(d->>'nombres',''),'telefono',coalesce(d->>'telefono',''),
    'domicilio',d->'domicilio','bancarios','null'::jsonb,'asesor',p_responsable);
end $$;

-- Privado: sus llamadores ya tienen autorización (RPC) o un UPDATE de ficha
-- admitido por RLS. No toma la identidad: evita invertir identidad -> lead.
-- FALSE significa que el acceso ya existe: una edición de contacto puede seguir,
-- pero la RPC explícita de alta debe informar que ya no cambia credenciales.
create or replace function private.inversion_corregir_reserva_acceso(p_solicitud uuid, p_portal jsonb)
returns boolean language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare s crm.inversion_solicitudes%rowtype; g crm.multiempresa_idempotencia%rowtype;
  persona uuid; anterior text; nuevo text;
begin
  select * into strict s from crm.inversion_solicitudes where id=p_solicitud for update;
  if s.estado <> 'preparada' then
    raise exception 'Sólo se corrigen solicitudes todavía preparadas' using errcode='P0409';
  end if;
  if exists(select 1 from crm.inversionistas i
    where i.id=private.inversionista_canonica(s.inversionista_id) and i.perfil_id is not null) then
    return false;
  end if;
  if s.auth_claim_id is null then
    perform private.inversion_datos_portal(p_portal); return true;
  end if;
  persona := coalesce((s.auth_contexto->>'inversionista_id')::uuid,s.inversionista_id);
  select * into g from crm.multiempresa_idempotencia where clave='auth_persona:'||persona::text for update;
  if not found or g.resultado->>'claim_id' is distinct from s.auth_claim_id::text
     or s.auth_contexto->>'responsable_id' is null
     or persona is distinct from private.inversionista_canonica(s.inversionista_id)
     or exists(select 1 from crm.inversion_solicitudes x where x.id<>s.id and x.auth_claim_id=s.auth_claim_id) then
    raise exception 'El proceso de acceso requiere conciliación antes de corregirlo' using errcode='P0409';
  end if;
  if g.resultado->>'estado' is distinct from 'reclamado'
     or g.resultado->>'auth_user_id' is not null or g.resultado->>'perfil_id' is not null
     or g.resultado->>'auth_insertado_id' is not null
     or exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=s.auth_claim_id::text) then
    return false;
  end if;
  perform private.inversion_datos_portal(p_portal);
  anterior:=private.idem_hash(private.inversion_payload_acceso(persona,s.datos->'alta_portal',s.auth_contexto->>'responsable_id'));
  nuevo:=private.idem_hash(private.inversion_payload_acceso(persona,p_portal,s.auth_contexto->>'responsable_id'));
  if g.hash_payload is distinct from anterior then
    raise exception 'Los datos de acceso y su reserva requieren conciliación' using errcode='P0409';
  end if;
  if nuevo=g.hash_payload then return true; end if;
  update crm.multiempresa_idempotencia set hash_payload=nuevo,version=version+1,
    resultado=jsonb_set(resultado,'{actualizado_en}',to_jsonb(statement_timestamp())) where clave=g.clave;
  return true;
end $$;

-- AFTER INSERT / primera asignación de app_metadata: la unicidad habitual de Auth
-- conserva email_exists. Una petición
-- tardía con otro correo se RECHAZA y revierte su INSERT, nunca se ignora.
-- El marcador se confirma junto con Auth. No avanza estado ni versión CAS:
-- registrar_auth conserva la transición normal, incluso en la Edge anterior.
create or replace function private.inversion_auth_insertado_guard()
returns trigger language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare claim uuid; ids uuid[]; s crm.inversion_solicitudes%rowtype; g crm.multiempresa_idempotencia%rowtype; persona uuid;
begin
  if new.raw_app_meta_data->>'claim_id' is null then return new; end if;
  -- GoTrue puede insertar y después asignar app_metadata en la misma transacción.
  -- Se protege la PRIMERA vinculación al claim; las actualizaciones posteriores
  -- de una cuenta existente (login, password, metadatos) conservan su flujo.
  if tg_op='UPDATE' and old.raw_app_meta_data->>'claim_id' is not distinct from new.raw_app_meta_data->>'claim_id' then return new; end if;
  begin claim:=(new.raw_app_meta_data->>'claim_id')::uuid;
  exception when invalid_text_representation then return new; end;
  select array_agg(id order by id) into ids from crm.inversion_solicitudes where auth_claim_id=claim;
  if coalesce(cardinality(ids),0)=0 then return new; end if;
  if cardinality(ids)<>1 then
    raise exception 'El claim de inversión requiere conciliación' using errcode='P0409';
  end if;
  select * into strict s from crm.inversion_solicitudes where id=ids[1] for update;
  persona:=coalesce((s.auth_contexto->>'inversionista_id')::uuid,s.inversionista_id);
  select * into g from crm.multiempresa_idempotencia where clave='auth_persona:'||persona::text for update;
  if not found or s.estado<>'preparada'
     or s.auth_claim_id::text is distinct from new.raw_app_meta_data->>'claim_id'
     or g.resultado->>'claim_id' is distinct from s.auth_claim_id::text
     or g.resultado->>'estado' is distinct from 'reclamado'
     or g.resultado->>'auth_insertado_id' is not null or g.resultado->>'auth_user_id' is not null
     or g.resultado->>'perfil_id' is not null
     or private.inversion_correo_normalizado(new.email) is distinct from private.inversion_correo_normalizado(s.datos#>>'{alta_portal,correo}')
     or g.hash_payload is distinct from private.idem_hash(private.inversion_payload_acceso(persona,s.datos->'alta_portal',s.auth_contexto->>'responsable_id'))
     or exists(select 1 from auth.users u where u.id<>new.id and u.raw_app_meta_data->>'claim_id'=s.auth_claim_id::text) then
    raise exception 'Los datos del acceso cambiaron; revisa la solicitud antes de continuar' using errcode='P0409';
  end if;
  update crm.multiempresa_idempotencia set resultado=resultado||jsonb_build_object('auth_insertado_id',new.id)
    where clave=g.clave;
  return new;
end $$;

-- La revisión explícita del acceso también queda en la ficha. Antes de elevar
-- el lock compartido del lead se usa NOWAIT: dos correcciones concurrentes
-- devuelven conflicto/reintento en vez de quedarse esperando mutuamente.
create or replace function private.inversion_correo_a_ficha()
returns trigger language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_correo text:=private.inversion_correo_normalizado(new.datos#>>'{alta_portal,correo}');
begin
  if new.estado<>'preparada' or new.lead_origen_id is null or v_correo is null then return new; end if;
  if tg_op='UPDATE' and private.inversion_correo_normalizado(old.datos#>>'{alta_portal,correo}') is not distinct from v_correo then return new; end if;
  if not exists(select 1 from crm.leads l where l.id=new.lead_origen_id
    and private.inversion_correo_normalizado(l.correo) is distinct from v_correo) then return new; end if;
  if new.auth_claim_id is not null and (exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=new.auth_claim_id::text)
    or exists(select 1 from crm.multiempresa_idempotencia g where g.clave='auth_persona:'||coalesce(new.auth_contexto->>'inversionista_id',new.inversionista_id::text) and g.resultado->>'claim_id'=new.auth_claim_id::text
      and (g.resultado->>'auth_insertado_id' is not null or g.resultado->>'estado'<>'reclamado'))) then return new; end if;
  if exists(select 1 from crm.inversionistas i where i.id=private.inversionista_canonica(new.inversionista_id) and i.perfil_id is not null) then return new; end if;
  if pg_trigger_depth()>8 then raise exception 'Sincronización recursiva de correo' using errcode='P0409'; end if;
  perform 1 from crm.leads where id=new.lead_origen_id for no key update nowait;
  update crm.leads l set correo=v_correo where l.id=new.lead_origen_id
    and private.inversion_correo_normalizado(l.correo) is distinct from v_correo;
  return new;
end $$;

-- Decisión comercial: quien tiene permiso RLS para corregir la ficha corrige
-- también su correo de PRIMER acceso pendiente, sin poder emitir inversiones.
-- Importaciones/service sin actor se conservan: no inventamos corregido_por.
-- acceso_inversion_fn exige revisar cualquier diferencia antes de crear Auth.
create or replace function private.inversion_correo_desde_ficha()
returns trigger language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare s crm.inversion_solicitudes%rowtype; d jsonb; k uuid; motivo text:='Actualizar correo de acceso desde la ficha del prospecto';
  correo text:=private.inversion_correo_normalizado(new.correo); actor uuid:=(select auth.uid());
begin
  if actor is null or correo is not distinct from private.inversion_correo_normalizado(old.correo) then return new; end if;
  -- El contacto admite vaciar el correo. Mantener la solicitud y exigir revisión
  -- antes de Auth si no hay un correo apto para el acceso.
  if correo is null or length(correo)>254 or correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return new; end if;
  if pg_trigger_depth()>8 then raise exception 'Sincronización recursiva de correo' using errcode='P0409'; end if;
  for s in select * from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada'
    and datos->>'empresa'='avance' and datos->'alta_portal' is not null order by id for update
  loop
    if correo is not distinct from private.inversion_correo_normalizado(s.datos#>>'{alta_portal,correo}') then continue; end if;
    d:=jsonb_set(s.datos,'{alta_portal,correo}',coalesce(to_jsonb(correo),'null'::jsonb));
    if not private.inversion_corregir_reserva_acceso(s.id,d->'alta_portal') then continue; end if;
    k:=gen_random_uuid();
    insert into crm.inversion_solicitud_correcciones(id,solicitud_id,revision_anterior,revision,hash_peticion,
      hash_anterior,hash_nuevo,datos_anteriores,datos_nuevos,motivo,corregido_por)
    values(k,s.id,s.revision_datos,s.revision_datos+1,
      private.idem_hash(jsonb_build_object('solicitud',s.id,'revision',s.revision_datos,'datos',d,'motivo',motivo)),
      private.idem_hash(s.datos),private.idem_hash(d),s.datos,d,motivo,actor);
    update crm.inversion_solicitudes set datos=d,revision_datos=revision_datos+1,actualizado_en=statement_timestamp() where id=s.id;
  end loop;
  return new;
end $$;

CREATE OR REPLACE FUNCTION crm.corregir_solicitud_inversion_fn(p_solicitud uuid, p_clave uuid, p_revision_datos_esperada integer, p_datos jsonb, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_persona uuid; v_ctx jsonb; v_validacion jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_r crm.inversion_solicitud_correcciones%rowtype;
  v_hash text; v_inicial uuid; v_empresa uuid; v_correo_ficha_distinto boolean;
begin
  if p_clave is null or p_revision_datos_esperada is null or p_revision_datos_esperada<0
    or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Indica clave, versión y contenido de la corrección' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  -- Siempre ámbito/membresía actuales, también al recuperar una corrección.
  v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  perform private.motivo_sin_documento(p_motivo,(select array_agg(documento_normalizado)
    from crm.inversionista_identificadores where inversionista_id=private.inversionista_canonica(v_persona)));
  v_hash:=private.idem_hash(jsonb_build_object('solicitud',p_solicitud,'revision',p_revision_datos_esperada,
    'datos',p_datos,'motivo',btrim(p_motivo)));
  perform pg_advisory_xact_lock(hashtextextended('f4_correccion:'||p_clave::text,0));
  select * into v_r from crm.inversion_solicitud_correcciones where id=p_clave;
  if found then
    if v_r.hash_peticion is distinct from v_hash then
      raise exception 'La clave de corrección ya se usó con otros datos' using errcode='P0409';
    end if;
    return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
      jsonb_build_object('correccion_id',v_r.id,'revision_aplicada',v_r.revision,'reintento',true);
  end if;
  v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if v_s.estado<>'preparada' then
    raise exception 'Sólo se corrigen solicitudes todavía preparadas' using errcode='P0409';
  end if;
  if v_s.revision_datos is distinct from p_revision_datos_esperada then
    raise exception 'Los datos cambiaron; vuelve a revisar la solicitud' using errcode='PT409';
  end if;
  -- Venta cruzada (D7): su atribución no depende del responsable.
  if v_s.puerta<>'cliente_existente' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'Revisa primero el cambio de responsable de esta solicitud' using errcode='P0409';
  end if;
  -- La MONEDA entra en esta lista el 17/09/2026, al abrir dólares en Prodelco.
  -- Motivo concreto: un bundle anterior manda `moneda:'PEN'` fijo, así que al
  -- corregir cualquier otro campo de una solicitud en USD la habría reescrito
  -- como soles, con el mismo importe y sin avisar. La moneda es parte de lo que
  -- el comprobante acredita, no un texto corregible: si está mal, se cancela la
  -- solicitud y se prepara otra.
  if p_datos->'inversionista_id' is distinct from v_s.datos->'inversionista_id'
    or p_datos->'lead_id' is distinct from v_s.datos->'lead_id'
    or p_datos->'empresa' is distinct from v_s.datos->'empresa'
    or p_datos->'moneda' is distinct from v_s.datos->'moneda'
    or p_datos#>'{contrato,cliente_id}' is distinct from v_s.datos#>'{contrato,cliente_id}'
    or p_datos#>'{contrato,analista_cierre_id}' is distinct from v_s.datos#>'{contrato,analista_cierre_id}' then
    raise exception 'La corrección conserva la persona, empresa, moneda y referencias originales del contrato' using errcode='22023';
  end if;
  if p_datos->'evidencia' is distinct from v_s.datos->'evidencia' then
    raise exception 'La corrección conserva la ruta del comprobante de esta solicitud' using errcode='22023';
  end if;
  v_correo_ficha_distinto:=v_s.datos->>'empresa'='avance' and v_s.lead_origen_id is not null
    and jsonb_typeof(p_datos->'alta_portal')='object'
    and exists(select 1 from crm.leads l where l.id=v_s.lead_origen_id
      and private.inversion_correo_normalizado(l.correo) is distinct from private.inversion_correo_normalizado(p_datos#>>'{alta_portal,correo}'));
  if v_s.datos->>'empresa'='avance' and (p_datos->'alta_portal' is distinct from v_s.datos->'alta_portal'
    or (p_datos=v_s.datos and v_correo_ficha_distinto)) then
    if not private.inversion_corregir_reserva_acceso(p_solicitud,p_datos->'alta_portal') then
      raise exception 'El acceso Avance ya fue creado; su correo se cambia desde la gestión de acceso' using errcode='P0409';
    end if;
  end if;
  select responsable_anterior_id into v_inicial from crm.inversion_solicitud_revisiones
    where solicitud_id=p_solicitud order by revision limit 1;
  v_validacion:=v_ctx||jsonb_build_object('responsable_id',coalesce(v_inicial,v_s.responsable_esperado_id))
    ||case when v_s.puerta='cliente_existente' then jsonb_build_object('analista_cierre_id',v_s.analista_cierre_id,'puerta',v_s.puerta) else '{}'::jsonb end;
  v_empresa:=private.inversion_validar_datos(p_solicitud,p_datos,v_validacion);
  if v_empresa is distinct from v_s.empresa_id then
    raise exception 'La empresa cambió; revisa la solicitud' using errcode='PT409';
  end if;
  if p_datos=v_s.datos and not coalesce(v_correo_ficha_distinto,false) then raise exception 'No hay datos distintos que corregir' using errcode='22023'; end if;
  insert into crm.inversion_solicitud_correcciones(id,solicitud_id,revision_anterior,revision,
    hash_peticion,hash_anterior,hash_nuevo,datos_anteriores,datos_nuevos,motivo,corregido_por)
    values(p_clave,p_solicitud,v_s.revision_datos,v_s.revision_datos+1,v_hash,
    private.idem_hash(v_s.datos),private.idem_hash(p_datos),v_s.datos,p_datos,btrim(p_motivo),(select auth.uid()));
  -- La huella original permanece: repetir preparar con su petición original
  -- recupera esta misma solicitud, nunca crea otra ni revierte una corrección.
  update crm.inversion_solicitudes set datos=p_datos,revision_datos=revision_datos+1,
    actualizado_en=statement_timestamp() where id=p_solicitud;
  -- Datos idénticos + ficha distinta es la elección explícita «Conservar correo».
  -- No propagar el correo antiguo al corregir solamente otros campos.
  if v_correo_ficha_distinto and p_datos=v_s.datos then
    perform 1 from crm.leads where id=v_s.lead_origen_id for no key update nowait;
    update crm.leads set correo=private.inversion_correo_normalizado(p_datos#>>'{alta_portal,correo}') where id=v_s.lead_origen_id;
  end if;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
    jsonb_build_object('correccion_id',p_clave,'revision_aplicada',v_s.revision_datos+1,'reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.acceso_inversion_fn(p_solicitud uuid, p_paso text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
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
  v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'confirmada' then
    v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
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
  v_hash_payload:=private.inversion_payload_acceso(v_persona,v_s.datos->'alta_portal',v_auth_ctx->>'responsable_id');

  if p_paso='reclamar' then
    -- Cubre solicitudes anteriores al arreglo e importaciones sin actor. No
    -- cambia una credencial que Auth ya creó aunque se perdiera la respuesta.
    if v_s.lead_origen_id is not null and exists(select 1 from crm.leads l where l.id=v_s.lead_origen_id
      and private.inversion_correo_normalizado(l.correo) is distinct from private.inversion_correo_normalizado(v_datos->>'correo'))
      and v_saga.resultado->>'auth_insertado_id' is null
      and v_saga.resultado->>'auth_user_id' is null
      and not exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
      raise exception 'El correo de la ficha cambió; revisa los datos de acceso antes de continuar' using errcode='P0409';
    end if;
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
        v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
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
    -- El formulario guarda su token ANTES del primer envío. La saga general
    -- emite otro token; aquí conservamos el ya conocido para poder recuperar
    -- también una respuesta perdida del primer reclamo (sin esperar el lease).
    -- saga_auth_reclamar ya verificó el token vigente al retomar. No se altera
    -- el claim, su versión, su dueño ni su huella; las otras puertas no cambian.
    if v_token is not null and v_r->>'estado'<>'enlazado' then
      update crm.multiempresa_idempotencia set resultado=jsonb_set(resultado,'{token_hash}',
        to_jsonb(private.saga_token_hash(v_token)))
        where clave='auth_persona:'||(v_r->>'inversionista_id') and resultado->>'claim_id'=v_r->>'claim_id';
      if not found then
        raise exception 'El proceso de acceso cambió; recupera la solicitud' using errcode='40001';
      end if;
      v_r:=jsonb_set(v_r,'{token}',to_jsonb(v_token));
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
$function$;

CREATE OR REPLACE FUNCTION private.inversion_solicitud_resultado(p_id uuid, p_contexto jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('solicitud_id',s.id,'lead_id',s.lead_origen_id,'estado',s.estado,'inversion_id',s.inversion_id,
    'inversionista_id',p_contexto->>'inversionista_id','inversionista_origen_id',s.inversionista_id,
    'identidad_fusionada',s.inversionista_id::text is distinct from p_contexto->>'inversionista_id',
    'responsable_esperado_id',s.responsable_esperado_id,'responsable_actual_id',p_contexto->>'responsable_id',
    'requiere_revision_responsable',s.estado='preparada' and s.responsable_esperado_id::text is distinct from p_contexto->>'responsable_id'
      and (s.puerta<>'cliente_existente' or (e.requiere_portal and p_contexto->>'perfil_id' is null)),
    'revision_datos',s.revision_datos,'hash_datos',private.idem_hash(s.datos),
    'revision_responsable',coalesce((select max(r.revision) from crm.inversion_solicitud_revisiones r where r.solicitud_id=s.id),0),
    'resultado',case when s.resultado is not null then s.resultado||jsonb_build_object('inversionista_id',p_contexto->>'inversionista_id') end,
    'acceso_creado',p_contexto->>'perfil_id' is not null or (s.auth_claim_id is not null and (
      exists(select 1 from crm.multiempresa_idempotencia g where g.clave='auth_persona:'||coalesce(s.auth_contexto->>'inversionista_id',s.inversionista_id::text)
        and g.resultado->>'claim_id'=s.auth_claim_id::text and (g.resultado->>'auth_insertado_id' is not null or g.resultado->>'auth_user_id' is not null))
      or exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=s.auth_claim_id::text))),
    'necesita_portal',e.requiere_portal and p_contexto->>'perfil_id' is null,
    'comprobante_bucket',case when e.fuente_capital='cierres_externos' then 'f4-comprobantes' else null end,
    'comprobante_ruta',s.datos#>>'{evidencia,ruta}',
    'reinversion_origen_id',(select o.fuente_id from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id))
    ||case when s.puerta='cliente_existente' then jsonb_build_object('puerta',s.puerta,'analista_cierre_id',s.analista_cierre_id) else '{}'::jsonb end
  from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id where s.id=p_id;
$function$;

create index if not exists inversion_solicitudes_auth_claim_idx on crm.inversion_solicitudes(auth_claim_id) where auth_claim_id is not null;
create or replace trigger inversion_auth_insertado_guard after insert or update of raw_app_meta_data on auth.users
  for each row execute function private.inversion_auth_insertado_guard();
create or replace trigger inversion_correo_a_ficha after insert or update of datos on crm.inversion_solicitudes
  for each row execute function private.inversion_correo_a_ficha();
create or replace trigger inversion_correo_desde_ficha after update of correo on crm.leads
  for each row execute function private.inversion_correo_desde_ficha();
revoke all on function private.inversion_correo_normalizado(text),
  private.inversion_payload_acceso(uuid,jsonb,text),
  private.inversion_corregir_reserva_acceso(uuid,jsonb),
  private.inversion_auth_insertado_guard(), private.inversion_correo_a_ficha(),
  private.inversion_correo_desde_ficha() from public,anon,authenticated,service_role;
-- Se conservan los grants existentes de las dos RPC reemplazadas.
notify pgrst, 'reload schema';
commit;
