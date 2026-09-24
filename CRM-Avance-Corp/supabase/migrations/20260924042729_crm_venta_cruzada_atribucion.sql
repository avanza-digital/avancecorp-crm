-- Venta cruzada · Fase 3: la venta queda a nombre de quien la cierra.
--
-- QUÉ HACE. Las funciones que operan UNA solicitud pasan su llave (la propia
-- solicitud) a los núcleos de la Fase 2, y la confirmación usa el analista
-- CONGELADO en una venta cruzada en vez de reasignarla al responsable:
--   · crm.solicitud_inversion_fn, crm.corregir_solicitud_inversion_fn,
--     crm.cancelar_solicitud_inversion_fn, crm.acceso_inversion_fn,
--     crm.confirmar_inversion_revisada_fn, crm.revisar_solicitud_inversion_fn,
--     crm.bienvenida_inversion_estado_fn y private.f4_comprobante_autorizado autorizan
--     con inversion_persona_*_para(persona, p_solicitud, NULL). La llave solo abre si la
--     solicitud es una venta cruzada de ESA persona; en las de cartera no cambia nada.
--   · Quién opera una venta cruzada (Miguel, 24/09): corregir, cancelar, confirmar, el
--     alta de Portal, revisar el responsable y subir el comprobante son de su analista,
--     su cadena y Gerencia (private.venta_cruzada_opera). El responsable la ve, no la toca.
--   · El alta de Portal (crm.acceso_inversion_fn) la puede hacer B («también B»,
--     Miguel, 24/09). Conserva su chequeo de responsable, que es la excepción de D7; si el
--     responsable cambió con el acceso pendiente, la cadena de B lo resuelve con
--     crm.revisar_solicitud_inversion_fn, que también recibe la llave.
--   · Confirmar (venta cruzada): el contrato Avance nace con analista_cierre_id =
--     analista congelado y el cierre cooperativo con vendedor_id = analista
--     congelado; el responsable NO se toca ni se exige que coincida (D7); el
--     analista tiene que seguir activo; solo inversión nueva o upgrade (D5).
--   · Corregir (venta cruzada): tampoco exige que el responsable coincida (D7) y
--     valida el analista contra el congelado.
--   · private.inversion_validar_datos: el analista del contrato se compara con el
--     congelado si lo hay (si no, con el responsable, como hoy); la venta cruzada no
--     admite renovación (D5), y su cuenta es una registrada del cliente o una nueva que no
--     pise un CCI activo (D3).
--   · private.inversion_solicitud_resultado: en venta cruzada añade «puerta» y
--     «analista_cierre_id» (el front valida con v.object: tolera claves) y solo pide
--     revisar el responsable si falta el acceso Avance (D7).
--   · private.f4_comprobante_visible: el analista de una venta cruzada (y su cadena)
--     ve el comprobante de ESA solicitud.
--   · private.puede_leer_contrato_pdf (D2): quien cerró la venta, y su cadena de
--     supervisión, LEE el PDF de TODOS los contratos que cerró, incluidos los antiguos,
--     mientras el cliente siga activo.
--   · private.puede_crear_contrato_pdf_como (nueva): cartera P04, como antes de D2, o la
--     confirmación en curso de ESA venta cruzada, que confirmar publica en el GUC
--     crm.venta_cruzada_solicitud. La exigen el alta Avance directa
--     (crm.crear_contrato_con_cuenta_pdf_v2, sea cual sea el régimen documental del
--     contrato) y private.crear_job_contrato_pdf_base antes de crear un trabajo de PDF
--     NUEVO (la reserva de uno existente, que usa la Edge, sigue con la lectura). Sin
--     esto, D2 haría auto-satisfacible el candado de cartera del alta directa: hallazgo
--     P1 de las dos auditorías (la segunda, con un contrato de régimen «anterior»).
-- preparar_reinversion_fn no cambia.
--
-- CONDUCTA. Solicitudes de cartera y conversiones: idéntica (se prueba con
-- conversion-inversion/test-conversion.sql y con el flujo de cartera de la prueba de
-- esta fase). Cambia en: venta cruzada (nueva) y lectura del PDF (D2).
--
-- CUERPOS. Generados por programa desde los cuerpos vivos de prod del 23/09 (anclados
-- por md5), con cada sustitución exigida el número exacto de veces; el postflight
-- exige además la huella exacta de cada cuerpo instalado.
--
-- REQUIERE. Fases 1 y 2 aplicadas. REVERSA: supabase/scripts/venta-cruzada/reversa-fase3.sql.
begin;
set local lock_timeout = '5s';

do $anclas$ declare a record; begin
  if to_regprocedure('private.inversion_persona_autorizada_para(uuid,uuid,uuid)') is null then
    raise exception 'Falta la Fase 2 (20260924032042): aplícala antes';
  end if;
  for a in select * from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)','3889e07b60cb7f944e3a0c9802cbdb97'),
    ('crm.bienvenida_inversion_estado_fn(uuid)','6ebdea65a2e021538d63a41dbd82c1e5'),
    ('crm.cancelar_solicitud_inversion_fn(uuid,integer)','ac30b2b1f9dedf842125bc26a727a65a'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','cdcd1c4736cfd60f31ab25515ea97a09'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)','5c0c1dba4c889d49328a2ffd96244a1e'),
    ('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)','4fc1e308a8b1c263543c2b9271da5af7'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)','01852f10f28110f9c12beb64e5c3d3ba'),
    ('crm.solicitud_inversion_fn(uuid)','e049912bb20453eaf019363c2c09d95a'),
    ('private.crear_job_contrato_pdf_base(uuid,uuid)','9a9c18303271d4c8e0bb7510449ed64d'),
    ('private.f4_comprobante_autorizado(text)','73ebcd343ef95800e23c47c99ae11ad1'),
    ('private.f4_comprobante_visible(text)','37e470aecbb449ee51bd380d88ee0b17'),
    ('private.inversion_solicitud_resultado(uuid,jsonb)','7245290902ab426c095fbf7f73e22971'),
    ('private.inversion_validar_datos(uuid,jsonb,jsonb)','3b28b3807762b4d1bdb9c91c3c473999'),
    ('private.puede_leer_contrato_pdf(uuid)','1a00a0f081755fda27b46b372dad4851')
  ) x(firma, huella) loop
    if to_regprocedure(a.firma) is null
       or md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'La base cambió o la Fase 3 ya está aplicada: %. Revisa antes de instalar.', a.firma;
    end if;
  end loop;
end $anclas$;

-- Permisos y atributos de antes, para comprobar al final que no cambian.
create temporary table vc_fase3_antes on commit drop as
select p.oid, p.oid::regprocedure::text firma, p.proacl::text acl, p.proconfig, p.prosecdef, p.provolatile, pg_get_userbyid(p.proowner) dueno
  from pg_proc p where p.oid in (
    'crm.solicitud_inversion_fn(uuid)'::regprocedure, 'crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'::regprocedure,
    'crm.cancelar_solicitud_inversion_fn(uuid,integer)'::regprocedure, 'crm.confirmar_inversion_revisada_fn(uuid,integer)'::regprocedure,
    'crm.bienvenida_inversion_estado_fn(uuid)'::regprocedure, 'private.crear_job_contrato_pdf_base(uuid,uuid)'::regprocedure,
    'private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure,
    'private.inversion_validar_datos(uuid,jsonb,jsonb)'::regprocedure, 'private.inversion_solicitud_resultado(uuid,jsonb)'::regprocedure,
    'private.puede_leer_contrato_pdf(uuid)'::regprocedure, 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure,
    'crm.acceso_inversion_fn(uuid,text,jsonb)'::regprocedure, 'crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)'::regprocedure);

-- ---------------------------------------------------------------------------
-- 1. Compuerta del PDF NUEVO (auditoría de la Fase 3, P1)
-- ---------------------------------------------------------------------------
-- D2 abre la LECTURA del PDF a quien cerró la venta. Crear el PDF de un contrato nuevo es
-- parte de su alta y sigue exigiendo la cartera (P04), salvo durante la confirmación de
-- una venta cruzada: crm.confirmar_inversion_revisada_fn publica ESA solicitud en un GUC
-- transaccional y aquí se contrasta con la tabla (sigue preparada, quien pregunta opera a
-- su analista y el contrato es de esa persona y de ese analista). El GUC no es la
-- autoridad: sin una solicitud real que case, no abre nada.
create function private.venta_cruzada_confirma_contrato(p_contrato_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1
      from crm.inversion_solicitudes s
      join public.contratos c on c.id = p_contrato_id
      join crm.inversionistas i on i.perfil_id = c.cliente_id and i.estado <> 'fusionado'
     where s.id::text = current_setting('crm.venta_cruzada_solicitud', true)
       and s.puerta = 'cliente_existente' and s.estado = 'preparada'
       and s.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid())))
       and c.analista_cierre_id = s.analista_cierre_id
       and private.inversionista_canonica(i.id) = private.inversionista_canonica(s.inversionista_id))
$$;

create function private.puede_crear_contrato_pdf_como(p_contrato_id uuid, p_actor_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_resultado boolean;
begin
  if p_actor_id is null then return false; end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_resultado := exists (
    select 1 from public.contratos c
     where c.id = p_contrato_id
       and (private.puede_gestionar_cuentas_cliente(c.cliente_id)
            or private.venta_cruzada_confirma_contrato(c.id)));
  perform set_config('request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true);
  return v_resultado;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true);
  raise;
end $$;

-- ---------------------------------------------------------------------------
-- Quién opera una venta cruzada (Miguel, 24/09)
-- ---------------------------------------------------------------------------
-- La venta es de quien la registró (D1): la corrigen, cancelan, confirman, completan su
-- acceso Avance o revisan su responsable su analista, su cadena de supervisión y
-- Gerencia. El responsable del cliente la ve, pero no la toca; si B la abandona, la
-- cancela Gerencia. En una solicitud de cartera no cambia nada.
create function private.venta_cruzada_opera(p_solicitud uuid)
returns boolean language sql stable set search_path = '' as $$
  select not exists (select 1 from crm.inversion_solicitudes s where s.id = p_solicitud and s.puerta = 'cliente_existente')
      or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false)
      or exists (select 1 from crm.inversion_solicitudes s
                  where s.id = p_solicitud and s.puerta = 'cliente_existente'
                    and s.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid()))))
$$;

create function private.venta_cruzada_exigir_operador(p_solicitud uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if not private.venta_cruzada_opera(p_solicitud) then
    raise exception 'Esta venta la gestionan quien la registró, su supervisión o Gerencia' using errcode = '42501';
  end if;
end $$;

revoke all on function private.venta_cruzada_confirma_contrato(uuid) from public, anon, authenticated, service_role;
revoke all on function private.venta_cruzada_opera(uuid) from public, anon, authenticated, service_role;
revoke all on function private.venta_cruzada_exigir_operador(uuid) from public, anon, authenticated, service_role;
revoke all on function private.puede_crear_contrato_pdf_como(uuid,uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Funciones que operan UNA solicitud (generadas desde los cuerpos vivos)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.solicitud_inversion_fn(p_solicitud uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_persona uuid; v_ctx jsonb; v_datos jsonb;
begin
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  select datos into v_datos from crm.inversion_solicitudes where id=p_solicitud for share;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||jsonb_build_object('datos',v_datos);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

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
  v_hash text; v_inicial uuid; v_empresa uuid;
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
  if v_s.auth_claim_id is not null and p_datos->'alta_portal' is distinct from v_s.datos->'alta_portal' then
    raise exception 'El acceso Avance ya está reservado; conserva sus datos de alta' using errcode='P0409';
  end if;
  select responsable_anterior_id into v_inicial from crm.inversion_solicitud_revisiones
    where solicitud_id=p_solicitud order by revision limit 1;
  v_validacion:=v_ctx||jsonb_build_object('responsable_id',coalesce(v_inicial,v_s.responsable_esperado_id))
    ||case when v_s.puerta='cliente_existente' then jsonb_build_object('analista_cierre_id',v_s.analista_cierre_id,'puerta',v_s.puerta) else '{}'::jsonb end;
  v_empresa:=private.inversion_validar_datos(p_solicitud,p_datos,v_validacion);
  if v_empresa is distinct from v_s.empresa_id then
    raise exception 'La empresa cambió; revisa la solicitud' using errcode='PT409';
  end if;
  if p_datos=v_s.datos then raise exception 'No hay datos distintos que corregir' using errcode='22023'; end if;
  insert into crm.inversion_solicitud_correcciones(id,solicitud_id,revision_anterior,revision,
    hash_peticion,hash_anterior,hash_nuevo,datos_anteriores,datos_nuevos,motivo,corregido_por)
    values(p_clave,p_solicitud,v_s.revision_datos,v_s.revision_datos+1,v_hash,
    private.idem_hash(v_s.datos),private.idem_hash(p_datos),v_s.datos,p_datos,btrim(p_motivo),(select auth.uid()));
  -- La huella original permanece: repetir preparar con su petición original
  -- recupera esta misma solicitud, nunca crea otra ni revierte una corrección.
  update crm.inversion_solicitudes set datos=p_datos,revision_datos=revision_datos+1,
    actualizado_en=statement_timestamp() where id=p_solicitud;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
    jsonb_build_object('correccion_id',p_clave,'revision_aplicada',v_s.revision_datos+1,'reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.cancelar_solicitud_inversion_fn(p_solicitud uuid, p_revision_datos_esperada integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare s crm.inversion_solicitudes%rowtype; v_origen uuid; v_ctx jsonb; v_saga jsonb;
begin
  select inversionista_id into v_origen from crm.inversion_solicitudes where id=p_solicitud;
  v_ctx:=private.inversion_persona_autorizada_para(v_origen,p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  select * into s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if s.estado in ('confirmada','cancelada') then
    return private.inversion_solicitud_resultado(s.id,v_ctx);
  end if;
  if p_revision_datos_esperada is null or s.revision_datos<>p_revision_datos_esperada then
    raise exception 'La solicitud cambió; revisa sus datos antes de cancelarla' using errcode='P0409';
  end if;
  if s.auth_claim_id is not null then
    select resultado into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
      coalesce(s.auth_contexto->>'inversionista_id',v_origen::text) for update;
    if v_saga->>'claim_id' is distinct from s.auth_claim_id::text or
      v_saga->>'estado' is distinct from 'enlazado' or v_ctx->>'perfil_id' is null or
      v_saga->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'Completa el acceso Avance pendiente antes de cancelar esta solicitud' using errcode='P0409';
    end if;
  end if;
  update crm.inversion_solicitudes set estado='cancelada',actualizado_en=statement_timestamp() where id=s.id;
  -- El trigger de auditoría conserva quién canceló y los datos originales.
  return private.inversion_solicitud_resultado(s.id,v_ctx);
end $function$;

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

CREATE OR REPLACE FUNCTION crm.confirmar_inversion_revisada_fn(p_solicitud uuid, p_revision_datos_esperada integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_uid uuid := (select auth.uid());
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_e crm.empresas%rowtype;
  v_obj storage.objects%rowtype;
  v_cierre uuid;
  v_contrato uuid;
  v_inversion uuid;
  v_fecha date;
  v_imputacion date;
  v_periodo date;
  v_ahora timestamptz := statement_timestamp();
  v_ajuste boolean := false;
  v_fuente jsonb;
  v_payload_contrato jsonb;
  v_condicion uuid;
  v_config_producto text := current_setting('crm.producto_condicion_id',true);
  v_responsable_inicial uuid;
  v_res jsonb;
  v_config_conversion text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_origen := v_persona;
  v_ctx := private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='PT409';
  end if;
  if v_s.estado='confirmada' then
    v_res:=v_s.resultado;
    select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
    if v_contrato is not null then
      if private.contrato_en_eliminacion(v_contrato) then
        raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
      end if;
      v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
    end if;
    return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
  end if;
  if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
  if p_revision_datos_esperada is distinct from v_s.revision_datos then
    raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='PT409';
  end if;
  v_ctx := private.inversion_persona_contexto_para(v_persona,v_s.lead_origen_id,p_solicitud,null::uuid);
  if v_s.puerta='cliente_existente' then
    -- Venta cruzada: la venta es del analista congelado y no depende del responsable (D7),
    -- pero ese analista tiene que seguir activo para cerrarla.
    if not coalesce(private.rol_crm(v_s.analista_cierre_id) in ('vendedor','supervisor'),false) then
      raise exception 'El analista de esta venta ya no está activo como vendedor o supervisor; cancela la solicitud y regístrala de nuevo' using errcode='P0409';
    end if;
    v_ctx := v_ctx||jsonb_build_object('analista_cierre_id',v_s.analista_cierre_id,'puerta',v_s.puerta);
  elsif v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
  end if;
  select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
  if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
  if v_e.fuente_capital='cierres_externos' then
    -- Se revalida contra el catálogo VIVO: una solicitud preparada cuando la
    -- cooperativa admitía una moneda no se confirma si entretanto se retiró.
    -- `coalesce` por el mismo motivo que en private.inversion_validar_datos.
    if v_s.datos->>'moneda' is null
       or not (v_s.datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
    end if;
    -- Revalida el contenido guardado, también al retomar una solicitud anterior.
    perform private.inversion_validar_datos(v_s.id,v_s.datos,v_ctx);
    select * into v_obj from storage.objects
    where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
    if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
      raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
    end if;
    v_fecha := (v_s.datos->>'fecha_comercial')::date;
    v_periodo := date_trunc('month',v_fecha)::date;
    -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
    -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
    v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
    if v_ajuste then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
        (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
      if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
        raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
      end if;
    end if;
    begin
      insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
        nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
        inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,
        plazo_meses,tasa_anual)
      values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,v_s.datos->>'moneda',
        v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
        upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
        (v_s.datos->>'vence_en')::date,coalesce(v_s.analista_cierre_id,(v_ctx->>'responsable_id')::uuid),v_uid,v_persona,
        v_ahora,v_s.lead_origen_id is not null,v_fecha,v_imputacion,v_obj.id,
        (v_s.datos->>'plazo_meses')::integer,(v_s.datos->>'tasa_anual')::numeric) returning id into v_cierre;
      -- La reclamación histórica del depósito es global para ambas cooperativas.
      insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
      values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
    exception when unique_violation then
      raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
    end;
    v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
      'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste,
      'plazo_meses',(v_s.datos->>'plazo_meses')::integer,'tasa_anual',(v_s.datos->>'tasa_anual')::numeric,
      'vence_en',(v_s.datos->>'vence_en')::date);
  elsif v_e.clave='avance' then
    if v_ctx->>'perfil_id' is null then
      raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
    end if;
    v_payload_contrato := v_s.datos->'contrato';
    if v_s.puerta='cliente_existente' and coalesce(v_payload_contrato->>'categoria','nuevo') not in ('nuevo','upgrade') then
      raise exception 'La venta cruzada registra una inversión nueva o un upgrade; la renovación es del responsable' using errcode='22023';
    end if;
    if v_s.lead_origen_id is not null then
      if coalesce(v_payload_contrato->>'categoria','nuevo')<>'nuevo' then
        raise exception 'La conversión inicial registra una inversión nueva' using errcode='22023';
      end if;
      perform private.validar_tasa_conversion_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid,v_payload_contrato);
      perform private.enlazar_tasa_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid);
    end if;
    select r.responsable_anterior_id into v_responsable_inicial
      from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
    v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
    if v_payload_contrato->>'cliente_id' is not null
       and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
    end if;
    if v_payload_contrato->>'analista_cierre_id' is not null
       and v_payload_contrato->>'analista_cierre_id' is distinct from coalesce(v_s.analista_cierre_id,v_responsable_inicial)::text then
      raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
    end if;
    -- El contenido original conserva su huella. Una revisión explícita cambia
    -- el responsable con quien se confirma, sin reescribir las condiciones.
    v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
      'analista_cierre_id',coalesce(v_s.analista_cierre_id::text,v_ctx->>'responsable_id'));
    -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
    -- documental y operaciones de cartera. Todo participa de esta transacción.
    -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
    -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
    -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
    -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
    perform pg_catalog.set_config('crm.producto_condicion_id',
      coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
    -- Venta cruzada: el alta Avance puede crear el PDF de ESTE contrato aunque el cliente
    -- no sea de la cartera de quien confirma (private.venta_cruzada_confirma_contrato).
    perform pg_catalog.set_config('crm.venta_cruzada_solicitud',case when v_s.puerta='cliente_existente' then v_s.id::text else '' end,true);
    begin
      v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
        v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
        v_s.datos->'cronograma',v_s.datos->'cuenta');
    exception when others then
      perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
      perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
      raise;
    end;
    perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
    perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
    v_contrato := (v_fuente->>'id')::uuid;
    if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
    select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
    v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
  else
    raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
  end if;
  v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,v_s.lead_origen_id is not null);
  if v_ajuste then
    insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
    values(v_inversion,v_periodo,v_imputacion,v_uid);
  end if;
  insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
  v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
    'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
    'revision_datos',v_s.revision_datos);
  if v_s.puerta='cliente_existente' then
    v_res := v_res||jsonb_build_object('puerta',v_s.puerta,'analista_cierre_id',v_s.analista_cierre_id);
  end if;
  update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
    resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
  if v_s.lead_origen_id is not null then
    -- El escritor contractual puede haber enlazado ya su fuente; se reconoce
    -- ESTA inversión como inicial, conservando un único hecho y titular.
    update crm.inversiones set es_primera_conversion=true where id=v_inversion;
    perform set_config('crm.op_privilegiada','on',true);
    update crm.leads set etapa='convertido',convertido_en=statement_timestamp(),
      perfil_id=case when v_e.clave='avance' then (v_ctx->>'perfil_id')::uuid else perfil_id end,
      contrato_id=coalesce(v_contrato,contrato_id)
      where id=v_s.lead_origen_id;
    perform set_config('crm.op_privilegiada',v_config_conversion,true);
    insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
      values(v_s.lead_origen_id,'conversion','Convertido al confirmar su inversión',
        jsonb_build_object('solicitud_id',v_s.id,'inversion_id',v_inversion,'empresa',v_e.clave,
          'contrato_id',v_contrato,'cierre_externo_id',v_cierre),v_uid);
    if v_e.clave='avance' and v_s.auth_claim_id is not null then
      update crm.inversion_solicitudes set bienvenida=jsonb_build_object(
        'estado','pendiente','correo',v_s.datos->'alta_portal'->>'correo',
        'nombre',v_s.datos->'alta_portal'->>'nombre_completo') where id=v_s.id;
    end if;
  end if;
  return v_res;
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.bienvenida_inversion_estado_fn(p_solicitud uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s crm.inversion_solicitudes%rowtype;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  select * into s from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='42501'; end if;
  perform private.inversion_persona_autorizada_para(s.inversionista_id,p_solicitud,null::uuid);
  if s.estado<>'confirmada' then
    raise exception 'La inversión todavía no está confirmada' using errcode='P0409';
  end if;
  return jsonb_build_object('estado',coalesce(s.bienvenida->>'estado','no_corresponde'));
end $function$;

CREATE OR REPLACE FUNCTION private.f4_comprobante_autorizado(p_ruta text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_persona uuid; v_solicitud uuid; v_ctx jsonb; v_s crm.inversion_solicitudes%rowtype;
begin
  if p_ruta is null or p_ruta !~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$' then return false; end if;
  begin v_persona:=split_part(p_ruta,'/',1)::uuid; v_solicitud:=split_part(p_ruta,'/',2)::uuid;
  exception when invalid_text_representation then return false; end;
  v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=v_solicitud),v_solicitud,null::uuid);
  select * into v_s from crm.inversion_solicitudes where id=v_solicitud for share;
  return found and v_s.inversionista_id=v_persona and v_s.estado='preparada'
    and (v_s.puerta='cliente_existente' or v_s.responsable_esperado_id=(v_ctx->>'responsable_id')::uuid)
    and private.venta_cruzada_opera(v_solicitud)
    and v_s.datos#>>'{evidencia,ruta}'=p_ruta;
exception when insufficient_privilege or lock_not_available or sqlstate 'P0409' or sqlstate 'P0429' then return false;
end;
$function$;

CREATE OR REPLACE FUNCTION private.f4_comprobante_visible(p_ruta text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia') and exists (
    select 1 from crm.inversion_solicitudes s join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    where s.datos#>>'{evidencia,ruta}'=p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (s.puerta='cliente_existente' and s.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    )
  ),false);
$function$;

CREATE OR REPLACE FUNCTION private.inversion_validar_datos(p_clave uuid, p_datos jsonb, p_contexto jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_persona uuid:=(p_datos->>'inversionista_id')::uuid;
  v_ctx jsonb:=p_contexto;
  v_e crm.empresas%rowtype;
  v_monto numeric; v_fecha date; v_vence date; v_ruta text;
begin
  if p_clave is null or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Falta la clave o el contenido de la inversión' using errcode='22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_datos) k where k not in (
    'inversionista_id','lead_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal','plazo_meses','tasa_anual'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  select * into v_e from crm.empresas where clave=p_datos->>'empresa' and activa for share;
  if not found or v_e.clave not in ('avance','qorilazo','prodelco') then
    raise exception 'Empresa no disponible para invertir' using errcode='22023';
  end if;
  if v_e.fuente_capital='cierres_externos' then
    begin
      v_monto := (p_datos->>'monto')::numeric;
      v_fecha := (p_datos->>'fecha_comercial')::date;
      v_vence := (p_datos->>'vence_en')::date;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'Revisa el monto y las fechas de la inversión' using errcode='22023';
    end;
    if v_monto is null or v_monto in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
       or v_monto<=0 or v_monto>999999999999.99 or v_monto<>trunc(v_monto,2) then
      raise exception 'El monto debe ser positivo y tener como máximo dos decimales' using errcode='22023';
    end if;
    -- La moneda sale del catálogo de la empresa (v_e ya viene de una fila
    -- activa, con `for share`): Prodelco admite PEN y USD desde el 17/09/2026.
    -- `coalesce` sobre monedas: hoy la columna es NOT NULL (F1), pero si algún
    -- día se relajara, `= any(null)` daría NULL y este candado se abriría solo
    -- mientras los de las cooperativas siguen cerrados. Un array vacío no
    -- admite nada, que es el lado correcto del que fallar.
    if p_datos->>'moneda' is null
       or not (p_datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'Esta cooperativa no registra inversiones en %',
        coalesce(p_datos->>'moneda','la moneda enviada') using errcode='22023';
    end if;
    if v_fecha is null or not isfinite(v_fecha) or v_fecha>(statement_timestamp() at time zone 'America/Lima')::date
       or v_vence is null or not isfinite(v_vence) or v_vence<=v_fecha then
      raise exception 'La fecha comercial no puede ser futura y el vencimiento debe ser posterior' using errcode='22023';
    end if;
    if p_datos ? 'plazo_meses' or p_datos ? 'tasa_anual' then
      if jsonb_typeof(p_datos->'plazo_meses') is distinct from 'number'
        or jsonb_typeof(p_datos->'tasa_anual') is distinct from 'number'
        or (p_datos->>'plazo_meses')::numeric<>trunc((p_datos->>'plazo_meses')::numeric) then
        raise exception 'Completa el plazo en meses enteros y la rentabilidad anual' using errcode='22023';
      end if;
      if private.coopac_validar_condiciones(v_fecha,(p_datos->>'plazo_meses')::integer,
        (p_datos->>'tasa_anual')::numeric) is distinct from v_vence then
        raise exception 'El vencimiento debe corresponder a la fecha de inicio y al plazo' using errcode='22023';
      end if;
    end if;
    if length(btrim(coalesce(p_datos->>'numero_transaccion',''))) not between 1 and 64
       or length(btrim(coalesce(p_datos->>'referencia',''))) not between 1 and 64 then
      raise exception 'El depósito y la referencia son obligatorios, con un máximo de 64 caracteres' using errcode='22023';
    end if;
    v_ruta := p_datos#>>'{evidencia,ruta}';
    if v_ruta is null or v_ruta !~ ('^'||v_persona::text||'/'||p_clave::text||'/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$') then
      raise exception 'El comprobante debe pertenecer a esta persona y solicitud' using errcode='22023';
    end if;
  else
    if jsonb_typeof(p_datos->'contrato') is distinct from 'object'
       or jsonb_typeof(p_datos->'cronograma') is distinct from 'array'
       or jsonb_typeof(p_datos->'cuenta') is distinct from 'object' then
      raise exception 'Avance requiere contrato, cronograma y cuenta de pago' using errcode='22023';
    end if;
    -- Venta cruzada (D3): una cuenta registrada del cliente o una nueva (vacía mientras
    -- se completa el acceso Avance), y la nueva no pisa una cuenta activa del cliente con
    -- el mismo CCI (segunda auditoría, P3).
    if v_ctx->>'puerta'='cliente_existente' then
      if coalesce(p_datos#>>'{cuenta,tipo}','') not in ('','existente','nueva') then
        raise exception 'Elige una cuenta registrada del cliente o registra una nueva' using errcode='22023';
      end if;
      if p_datos#>>'{cuenta,tipo}'='nueva' and exists (select 1 from crm.cuentas_bancarias cb
           where cb.cliente_id=(v_ctx->>'perfil_id')::uuid and cb.activa
             and cb.moneda=upper(btrim(coalesce(p_datos#>>'{contrato,moneda}','')))
             and cb.cci=btrim(coalesce(p_datos#>>'{cuenta,cci}',''))) then
        raise exception 'Esa cuenta ya está registrada para el cliente: elígela de la lista' using errcode='P0409';
      end if;
    end if;
    if p_datos#>>'{contrato,moneda}' is null
       or not (p_datos#>>'{contrato,moneda}'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'Moneda no admitida por Avance' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,cliente_id}' is not null
       and p_datos#>>'{contrato,cliente_id}' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato debe pertenecer a esta persona' using errcode='P0409';
    end if;
    if v_ctx->>'perfil_id' is null or p_datos ? 'alta_portal' then
      perform private.inversion_datos_portal(p_datos->'alta_portal');
    end if;
    if p_datos#>>'{contrato,analista_cierre_id}' is not null
       and p_datos#>>'{contrato,analista_cierre_id}' is distinct from coalesce(v_ctx->>'analista_cierre_id',v_ctx->>'responsable_id') then
      raise exception 'El analista debe corresponder al responsable de la persona al preparar la inversión' using errcode='P0409';
    end if;
    -- Venta cruzada (D5): inversión nueva o upgrade; la renovación es del responsable.
    if v_ctx->>'puerta'='cliente_existente' and coalesce(p_datos#>>'{contrato,categoria}','nuevo') not in ('nuevo','upgrade') then
      raise exception 'La venta cruzada registra una inversión nueva o un upgrade; la renovación es del responsable' using errcode='22023';
    end if;
  end if;
  return v_e.id;
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
    'necesita_portal',e.requiere_portal and p_contexto->>'perfil_id' is null,
    'comprobante_bucket',case when e.fuente_capital='cierres_externos' then 'f4-comprobantes' else null end,
    'comprobante_ruta',s.datos#>>'{evidencia,ruta}',
    'reinversion_origen_id',(select o.fuente_id from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id))
    ||case when s.puerta='cliente_existente' then jsonb_build_object('puerta',s.puerta,'analista_cierre_id',s.analista_cierre_id) else '{}'::jsonb end
  from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id where s.id=p_id;
$function$;

CREATE OR REPLACE FUNCTION private.puede_leer_contrato_pdf(p_contrato_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.contratos c
      where c.id = p_contrato_id
        and (private.puede_gestionar_cuentas_cliente(c.cliente_id)
          -- D2 (Miguel, 23/09): quien cerró la venta, y su cadena de supervisión, lee el
          -- PDF de TODOS los contratos que cerró, incluidos los antiguos, mientras el
          -- cliente siga activo. Solo LECTURA: crear el PDF de un contrato nuevo exige
          -- private.puede_crear_contrato_pdf_como.
          or (coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia'), false)
              and c.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid())))
              and exists (select 1 from public.perfiles cli
                          where cli.id = c.cliente_id and cli.rol = 'cliente' and cli.activo)))
    );
$function$;

CREATE OR REPLACE FUNCTION private.crear_job_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job_id uuid;
  v_snapshot jsonb;
  v_nombre text;
  v_revision integer;
begin
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if exists (
    select 1 from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
  ) or exists (
    select 1 from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
  ) then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  -- Un trabajo NUEVO es parte del alta del contrato: la lectura (D2) no basta.
  if not private.puede_crear_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_job_id := gen_random_uuid();
  v_revision := 1;
  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    'contrato-aep-17-v9',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
  -- Rentabilidad R4 (D2): el contrato que amplía un UPGRADE. Viaja dentro de p_contrato igual que
  -- clave_idempotencia (es del transporte, no del contrato) y NO se le quita: la cadena de abajo solo lo lee en la
  -- rama de renovación, así que recibe exactamente lo que recibía.
  v_origen_upgrade text := nullif(btrim(coalesce(p_contrato->>'contrato_origen_id', '')), '');
begin
  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- El origen declarado se publica en un GUC TRANSACCIONAL para que el candado del servidor
  -- (private.trg_contratos_observar_rentabilidad, al commit) sepa de qué contrato hereda la tasa este upgrade. Va con
  -- el cliente delante para que no pueda aplicarse al contrato de otro, y se REESCRIBE en cada alta (también vacío)
  -- para que un alta posterior de la misma transacción no herede la declaración de la anterior.
  perform set_config(
    'crm.rentabilidad_origen_upgrade',
    case when p_contrato->>'categoria' = 'upgrade' and v_origen_upgrade is not null
         then coalesce(p_contrato->>'cliente_id', '') || '|' || v_origen_upgrade else '' end,
    true);

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  -- Dar de alta un contrato exige su cartera (P04) o ser la confirmación en curso de SU
  -- venta cruzada, sea cual sea su régimen documental: un contrato de régimen «anterior»
  -- no crea PDF y no llega a la compuerta de private.crear_job_contrato_pdf_base
  -- (segunda auditoría de la Fase 3, P1).
  if not private.puede_crear_contrato_pdf_como(v_contrato_id, v_actor_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  if private.inversiones_escritura_bajo_candado() then
    perform private.inversion_cotitulares_vincular(
      (select id from crm.inversiones where contrato_id=v_contrato_id),'alta');
  end if;
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.revisar_solicitud_inversion_fn(p_solicitud uuid, p_responsable_revisado uuid, p_revision_esperada integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_revision crm.inversion_solicitud_revisiones%rowtype;
  v_num integer;
  v_motivo text:=btrim(p_motivo);
  v_perfil uuid;
  v_p public.perfiles%rowtype;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_config text:=current_setting('crm.f4_revision_solicitud',true);
begin
  if p_solicitud is null or p_responsable_revisado is null or p_revision_esperada is null or p_revision_esperada<0 then
    raise exception 'Falta la solicitud, el responsable revisado o su versión' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'preparada' then
    raise exception 'Solo se revisa el responsable de una solicitud pendiente; las inversiones confirmadas conservan su atribución' using errcode='P0409';
  end if;
  if p_responsable_revisado is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable actual ya no coincide con el que revisaste' using errcode='40001';
  end if;
  perform private.motivo_sin_documento(v_motivo,
    (select array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id=v_persona));
  select * into v_revision from crm.inversion_solicitud_revisiones r
    where r.solicitud_id=v_s.id order by r.revision desc limit 1;
  v_num:=coalesce(v_revision.revision,0);
  if p_revision_esperada<>v_num then
    if p_revision_esperada=v_num-1 and v_revision.responsable_nuevo_id=p_responsable_revisado
       and v_s.responsable_esperado_id=p_responsable_revisado and v_revision.motivo=v_motivo then
      return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',true);
    end if;
    raise exception 'La revisión cambió; vuelve a cargar la solicitud' using errcode='40001';
  end if;
  if v_s.responsable_esperado_id=p_responsable_revisado then
    return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('sin_cambios',true);
  end if;
  v_perfil:=(v_ctx->>'perfil_id')::uuid;
  if v_s.auth_claim_id is not null then
    select * into v_saga from crm.multiempresa_idempotencia m
      where m.clave='auth_persona:'||coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text)
        and m.resultado->>'claim_id'=v_s.auth_claim_id::text for update;
    if not found then raise exception 'El proceso de acceso requiere conciliación' using errcode='P0409'; end if;
    -- La corrección canónica solo se permite una vez enlazado el acceso. Su
    -- contexto original queda histórico y no impide revisar al nuevo equipo.
    if v_saga.resultado->>'estado'<>'enlazado' and not private.documento_es_de_identidad(
      v_persona,v_s.auth_contexto->>'documento_tipo',v_s.auth_contexto->>'documento') then
      raise exception 'El documento también cambió; revisa primero el acceso pendiente' using errcode='P0409';
    end if;
    if v_saga.resultado->>'auth_user_id' is not null then
      if not exists(select 1 from auth.users u where u.id=(v_saga.resultado->>'auth_user_id')::uuid
        and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
        raise exception 'El acceso pendiente no tiene la procedencia esperada' using errcode='P0409';
      end if;
      if v_perfil is not null and v_perfil is distinct from (v_saga.resultado->>'auth_user_id')::uuid then
        raise exception 'El perfil y el acceso pertenecen a procesos diferentes' using errcode='P0409';
      end if;
      select id into v_perfil from public.perfiles where id=(v_saga.resultado->>'auth_user_id')::uuid;
      if v_perfil is null and v_saga.resultado->>'estado' in ('perfil_creado','enlazado') then
        raise exception 'El perfil del proceso ya no existe; requiere revisión' using errcode='P0409';
      end if;
    end if;
  end if;
  if v_perfil is not null then
    -- La gestión de tareas puede tener ya una tarea/perfil. No esperar bajo el
    -- candado de persona: el intento se revierte entero y se puede repetir.
    begin
      perform 1 from crm.tareas t where t.perfil_id=v_perfil and t.estado='pendiente'
        order by t.id for update nowait;
      select * into v_p from public.perfiles where id=v_perfil for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando la ficha o sus tareas; vuelve a revisar' using errcode='40001';
    end;
    if not found or v_p.rol<>'cliente' or v_p.activo is not true
       or not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El perfil requiere conciliación con esta persona' using errcode='P0409';
    end if;
  end if;

  insert into crm.inversion_solicitud_revisiones(solicitud_id,revision,responsable_anterior_id,
    responsable_nuevo_id,motivo,revisado_por)
  values(v_s.id,v_num+1,v_s.responsable_esperado_id,p_responsable_revisado,v_motivo,(select auth.uid()));
  update crm.inversion_solicitudes set responsable_esperado_id=p_responsable_revisado,
    actualizado_en=statement_timestamp() where id=v_s.id;
  if v_perfil is not null and v_p.asesor_perfil_id is distinct from p_responsable_revisado then
    perform set_config('crm.f4_revision_solicitud',v_s.id::text,true);
    begin
      update public.perfiles set asesor_perfil_id=p_responsable_revisado where id=v_perfil;
      if (select asesor_perfil_id from public.perfiles where id=v_perfil) is distinct from p_responsable_revisado then
        raise exception 'El perfil no pudo alinearse con su responsable actual' using errcode='P0409';
      end if;
    exception when others then
      perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
      raise;
    end;
    perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
  end if;
  -- No cambia datos/hash/auth_contexto ni token/versión/lease de la saga.
  return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Comentarios (en prod estas funciones no tenían comentario; el de
--    crm.crear_contrato_con_cuenta_pdf_v2 se conserva)
-- ---------------------------------------------------------------------------
comment on function private.venta_cruzada_confirma_contrato(uuid) is
  'Venta cruzada: verdadero solo mientras crm.confirmar_inversion_revisada_fn confirma ESA solicitud (GUC crm.venta_cruzada_solicitud), que sigue preparada, cuyo analista opera quien pregunta y cuyo contrato es de esa persona y de ese analista.';
comment on function private.puede_crear_contrato_pdf_como(uuid,uuid) is
  'Compuerta del alta de un contrato y de su PDF NUEVO: cartera del actor (P04), como antes de D2, o la confirmación en curso de su venta cruzada. D2 abre la lectura, nunca el alta.';
comment on function private.venta_cruzada_opera(uuid) is
  'Venta cruzada: verdadero si quien pregunta puede operarla (su analista, su cadena de supervisión o Gerencia; decisión de Miguel, 24/09). Para una solicitud de cartera siempre es verdadero.';
comment on function private.venta_cruzada_exigir_operador(uuid) is
  'Venta cruzada: 42501 si quien llama no puede operarla (private.venta_cruzada_opera). La exigen corregir, cancelar, confirmar, el alta de Portal y revisar el responsable.';
comment on function crm.acceso_inversion_fn(uuid,text,jsonb) is
  'Completa, por pasos, el acceso Avance del cliente de una solicitud. En venta cruzada lo hace quien opera la venta (Miguel, 24/09); conserva el chequeo de responsable (excepción de D7).';
comment on function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) is
  'Revisa el responsable de una solicitud pendiente y realinea el perfil del cliente. En venta cruzada lo hace quien opera la venta, con la solicitud como llave (excepción de D7).';
comment on function private.crear_job_contrato_pdf_base(uuid,uuid) is
  'Reserva o crea el trabajo del PDF de un contrato. Leerlo exige private.puede_leer_contrato_pdf; crear uno NUEVO exige además private.puede_crear_contrato_pdf_como.';
comment on function private.puede_leer_contrato_pdf(uuid) is
  'Quién lee el PDF de un contrato: la cartera del cliente (P04) o, con D2, quien cerró la venta y su cadena de supervisión mientras el cliente siga activo. Solo lectura.';
comment on function crm.solicitud_inversion_fn(uuid) is
  'Consulta una solicitud de inversión. Autoriza con la solicitud como llave: en venta cruzada, su analista y su cadena; en cartera, la regla de siempre.';
comment on function crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text) is
  'Corrige una solicitud preparada. En venta cruzada la corrige quien la opera, no exige que el responsable coincida (D7) y valida el analista contra el congelado.';
comment on function crm.cancelar_solicitud_inversion_fn(uuid,integer) is
  'Cancela una solicitud preparada (o devuelve el resultado si ya se confirmó). Autoriza con la solicitud como llave; una venta cruzada la cancela quien la opera.';
comment on function crm.confirmar_inversion_revisada_fn(uuid,integer) is
  'Confirma una solicitud y crea su fuente (contrato Avance o cierre cooperativo). En venta cruzada la confirma quien la opera, atribuye al analista congelado, no toca al responsable (D7), exige al analista activo y solo admite nueva o upgrade (D5).';
comment on function crm.bienvenida_inversion_estado_fn(uuid) is
  'Estado de la bienvenida de una solicitud confirmada. Autoriza con la solicitud como llave.';
comment on function private.f4_comprobante_autorizado(text) is
  'Quién sube el comprobante de una solicitud cooperativa. En venta cruzada, quien la opera (la solicitud es la llave) sin exigir que el responsable coincida.';
comment on function private.f4_comprobante_visible(text) is
  'Quién ve el comprobante de una solicitud cooperativa: la cartera del cliente o, en venta cruzada, su analista y su cadena.';
comment on function private.inversion_validar_datos(uuid,jsonb,jsonb) is
  'Valida el contenido de una inversión para su empresa. En venta cruzada compara el analista con el congelado, no admite renovación (D5) y su cuenta es una registrada del cliente o una nueva que no pise un CCI activo (D3).';
comment on function private.inversion_solicitud_resultado(uuid,jsonb) is
  'Forma pública de una solicitud de inversión. En venta cruzada añade puerta y analista_cierre_id y solo pide revisar el responsable si falta el acceso Avance (D7).';

-- ---------------------------------------------------------------------------
-- 4. Postflight
-- ---------------------------------------------------------------------------
do $post$ declare a record; begin
  if (select count(*) from vc_fase3_antes) <> 14 then
    raise exception 'POSTFLIGHT: faltan funciones en la foto de antes';
  end if;
  for a in select b.firma, b.acl, b.proconfig, b.prosecdef, b.provolatile, b.dueno,
                  p.proacl::text acl2, p.proconfig proconfig2, p.prosecdef prosecdef2, p.provolatile provolatile2,
                  pg_get_userbyid(p.proowner) dueno2
             from vc_fase3_antes b join pg_proc p on p.oid = b.oid loop
    if a.acl is distinct from a.acl2 or a.proconfig is distinct from a.proconfig2 or a.prosecdef <> a.prosecdef2
       or a.provolatile <> a.provolatile2 or a.dueno <> a.dueno2 then
      raise exception 'POSTFLIGHT: % cambió de permisos o atributos', a.firma;
    end if;
  end loop;
  if (select p.prosecdef or p.provolatile <> 's' or p.proacl::text is distinct from '{postgres=X/postgres}'
            or p.proconfig::text is distinct from '{"search_path=\"\""}'
        from pg_proc p where p.oid = 'private.venta_cruzada_confirma_contrato(uuid)'::regprocedure)
     or (select not p.prosecdef or p.provolatile <> 'v' or p.proacl::text is distinct from '{postgres=X/postgres}'
            or p.proconfig::text is distinct from '{"search_path=\"\""}'
        from pg_proc p where p.oid = 'private.puede_crear_contrato_pdf_como(uuid,uuid)'::regprocedure)
     or (select p.prosecdef or p.provolatile <> 's' or p.proacl::text is distinct from '{postgres=X/postgres}'
            or p.proconfig::text is distinct from '{"search_path=\"\""}'
        from pg_proc p where p.oid = 'private.venta_cruzada_opera(uuid)'::regprocedure)
     or (select p.prosecdef or p.provolatile <> 'v' or p.proacl::text is distinct from '{postgres=X/postgres}'
            or p.proconfig::text is distinct from '{"search_path=\"\""}'
        from pg_proc p where p.oid = 'private.venta_cruzada_exigir_operador(uuid)'::regprocedure) then
    raise exception 'POSTFLIGHT: la compuerta del PDF nuevo quedó con atributos o permisos distintos';
  end if;
  -- Cada cuerpo instalado es exactamente el probado en el banco (la reversa exige lo mismo).
  for a in select * from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)','e4730d0161710fc8a84fb6dc7635bf47'),
    ('crm.bienvenida_inversion_estado_fn(uuid)','473226b547f0f132cd7e890c8de9f07c'),
    ('crm.cancelar_solicitud_inversion_fn(uuid,integer)','f17eac08c7e2bc4e27fad45616458731'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','aee09ba800853174532b700774ca048a'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)','3e09703845f2824054ead959fec40e47'),
    ('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)','d0b33d8fb1d27ef2da62105b7ccabd88'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)','dc622b938e8d8e9777a033cfa625b11a'),
    ('crm.solicitud_inversion_fn(uuid)','1c5867eaed3a1ea89b2b4626e2c9385e'),
    ('private.crear_job_contrato_pdf_base(uuid,uuid)','b17d1d8509d0c45db0bd75f6b91637e5'),
    ('private.f4_comprobante_autorizado(text)','7cdb9ea79f143edf53f0663b2d37aeae'),
    ('private.f4_comprobante_visible(text)','45fb7ff24d69f7a685cdc45902aedf9e'),
    ('private.inversion_solicitud_resultado(uuid,jsonb)','2ce92b3e2327a1f7a585f0053cb59bc4'),
    ('private.inversion_validar_datos(uuid,jsonb,jsonb)','6025f28475ad10f22ba9d06939da05b6'),
    ('private.puede_crear_contrato_pdf_como(uuid,uuid)','0469caecf7d8f20e222dbe69c700d9db'),
    ('private.puede_leer_contrato_pdf(uuid)','7d4c3bfd35abc10c790b72ea34cb7406'),
    ('private.venta_cruzada_confirma_contrato(uuid)','6d4d0bc855356dcc94c2efdcfcfc6b94'),
    ('private.venta_cruzada_exigir_operador(uuid)','e45df9cbce235fadb20fa207aa690a62'),
    ('private.venta_cruzada_opera(uuid)','7953b8f90592795eaf084528e121bbba')
  ) x(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'POSTFLIGHT: % no quedó con el cuerpo probado', a.firma;
    end if;
  end loop;
end $post$;

commit;
