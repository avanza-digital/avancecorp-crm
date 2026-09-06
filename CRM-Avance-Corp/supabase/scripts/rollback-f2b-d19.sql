-- ============================================================================
-- REVERSA de F2.b [D-19] (20260906200000): restaura byte a byte las 34 funciones (texto vivo de producción, huellas en
-- huellas-d19-prod.txt), suelta private.resolver_en_puertas_bajo_candado() y desregistra la versión. Repetible dos veces.
-- Se niega con la bandera encendida: con ON, quitar el candado es justo el hueco que D-19 cierra.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d19_bandera_bajo_candado'));
do $pre$
begin
  -- La bandera se lee bajo el MISMO candado compartido que usan las puertas: esta migración corre como `postgres`, así
  -- que el drenaje del script de encendido no la ve; sin el candado, un encendido confirmado entre esta lectura y el
  -- CREATE OR REPLACE dejaría aterrizar el lote con la bandera ya encendida.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception 'REVERSA D-19: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'REVERSA D-19: la bandera resolver_en_puertas está ENCENDIDA; apágala antes de revertir';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.actualizar_cliente_gerencia(uuid, jsonb)')), '') not in ('96ca3748c4b455e1dd6207b927684006', 'a984566930994023eb527d777ff5829b') then
    raise exception 'REVERSA D-19: crm.actualizar_cliente_gerencia(uuid, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.alta_cliente_identidad_fn(text, jsonb)')), '') not in ('a567140f4b30079eb1167aae554218b4', 'da08974050e65ecf2d76032d489db48e') then
    raise exception 'REVERSA D-19: crm.alta_cliente_identidad_fn(text, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.convertir_lead(uuid, uuid)')), '') not in ('4e0b2252ebe16cd98c490638d64a3d23', 'a31d2c2a4938afa56febe2a4bd25a1c9') then
    raise exception 'REVERSA D-19: crm.convertir_lead(uuid, uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid)')), '') not in ('7067b835fc8ed45f6c5e7261708f0c28', '05379200b541878371954cf1c4d6dcb6') then
    raise exception 'REVERSA D-19: crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb)')), '') not in ('0de7a130ae366cde54035e2c50f213e2', '7f2b4976640553a50ab27cf25b30fb36') then
    raise exception 'REVERSA D-19: crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.eliminar_cliente_fn(uuid)')), '') not in ('7be05d4584ed15dbd47fc849e51c8f9c', '63077333fcfe0100eb2ce1c4e980c06f') then
    raise exception 'REVERSA D-19: crm.eliminar_cliente_fn(uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.enlazar_lead_inversionista_fn(uuid, uuid, text)')), '') not in ('ae7a1c05cbf1659c2ef39783fb0d034d', '3766ae3484f839218f94dccdde5bb04b') then
    raise exception 'REVERSA D-19: crm.enlazar_lead_inversionista_fn(uuid, uuid, text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid)')), '') not in ('a3db3c1ada3fb4f7a4751364b5509d00', '07b8acd42d6b2eadb18353e0a8d8aaa5') then
    raise exception 'REVERSA D-19: crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.fusionar_inversionistas_fn(uuid, uuid, text, text)')), '') not in ('04de1797b11de93502ecb63487565bf6', '87e25279ed5c3bc8b3418be573499f41') then
    raise exception 'REVERSA D-19: crm.fusionar_inversionistas_fn(uuid, uuid, text, text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reasignar_responsable_relacion_fn(uuid, uuid, text)')), '') not in ('db063e46ca67e7c651c630625411870f', '00e579a03a0faa6a72dfa56f6c3a639c') then
    raise exception 'REVERSA D-19: crm.reasignar_responsable_relacion_fn(uuid, uuid, text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.registrar_reingreso_lead_fn(uuid, text, jsonb)')), '') not in ('2875987459d47958333637736c057ffb', 'b8b041176c5883dd9e39d14cef65b146') then
    raise exception 'REVERSA D-19: crm.registrar_reingreso_lead_fn(uuid, text, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reservar_conversion_lead(uuid, text, text, jsonb)')), '') not in ('a2c2cf70925fced68f75e4d18d7b0da9', '9307f1687b37a32230a08e4377b1b787') then
    raise exception 'REVERSA D-19: crm.reservar_conversion_lead(uuid, text, text, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.saga_conversion_fn(text, jsonb)')), '') not in ('58f723cd9f2b5b0a190c51797c1ec395', 'd2bdbe3d830afb4884065395e5c64a80') then
    raise exception 'REVERSA D-19: crm.saga_conversion_fn(text, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.enlazar_lead_reabierto(uuid, uuid)')), '') not in ('891aa806bff7cd422013d95ab2d88d11', '95d16ba245f33d8e278265d3e19243bd') then
    raise exception 'REVERSA D-19: private.enlazar_lead_reabierto(uuid, uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_enlaza_identidad()')), '') not in ('71807b0e2fa0b2cd8b2a5ca98dbf89a7', '31a10fdc8c86bb3ff2af60e3415750fa') then
    raise exception 'REVERSA D-19: private.trg_leads_zz_enlaza_identidad() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_puente_identidad()')), '') not in ('5e145a28199ca0db7ad31b67f1995e39', '7a64d7b6e92f87a1ffdeb1728faf4d25') then
    raise exception 'REVERSA D-19: private.trg_leads_zz_puente_identidad() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_perfiles_documento_protegido()')), '') not in ('7a7d3744136748fe72d10009482c3d59', '8c1c718ed2bcae0b9999a2173ff00612') then
    raise exception 'REVERSA D-19: private.trg_perfiles_documento_protegido() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.crear_contrato(jsonb, jsonb)')), '') not in ('4bf2f691888bee4d3198cccba8acd396', '061c40e345312ca5e515ddd5ee282e5c') then
    raise exception 'REVERSA D-19: public.crear_contrato(jsonb, jsonb) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.bloquear_personas_de_leads(uuid[], text)')), '') not in ('14727d8ae95fe727f5ddc81f9a92c9fd', '0a00e15b47907d3c79b59920ddd86911') then
    raise exception 'REVERSA D-19: private.bloquear_personas_de_leads(uuid[], text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.identidad_bloquear_documento(text, text)')), '') not in ('31f8f749f404614ac083b47bcfbd083b', 'ad3a36cf8237bef81bef5e7632177e1a') then
    raise exception 'REVERSA D-19: private.identidad_bloquear_documento(text, text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.identidad_bloquear_persona(text, text)')), '') not in ('b3a4fef3be766a70869c5dd8e6b8ede3', 'ecc1fd3672e2466ccd9494e9530bf299') then
    raise exception 'REVERSA D-19: private.identidad_bloquear_persona(text, text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_disponibilidad_atomica()')), '') not in ('ba0fd3ef2e9a16181fb6b944ac002450', '0fc38c3b3b63b4004d45891e9ff92b19') then
    raise exception 'REVERSA D-19: private.trg_leads_disponibilidad_atomica() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_hereda_veto_persona()')), '') not in ('1ee382b97b06bd13e3543d23075eba3e', '927858289e431b0d6dc2a5f42c68e061') then
    raise exception 'REVERSA D-19: private.trg_leads_hereda_veto_persona() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_no_contactar_solo_puerta()')), '') not in ('c8a2204232c07a605a815aac80360238', '595dfbd9c1d06b42638c18cc979a3c23') then
    raise exception 'REVERSA D-19: private.trg_leads_no_contactar_solo_puerta() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_reapertura_solo_rpc()')), '') not in ('ec1e53826887925cad0c41c319e967fb', '5af423f5a32ff7978b51216bf1a31dc7') then
    raise exception 'REVERSA D-19: private.trg_leads_zz_reapertura_solo_rpc() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_tareas_veto_persona_perfil()')), '') not in ('a2243b17cc31e7a06cfb7b0e443975ed', '3826f7b7d9f19fa63b5f2515168c56cf') then
    raise exception 'REVERSA D-19: private.trg_tareas_veto_persona_perfil() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.auth_usuario_por_correo_fn(text)')), '') not in ('13ab2b907ead9b091e328565cb580255', '4fde369f6e9ef37859871410be6338a5') then
    raise exception 'REVERSA D-19: crm.auth_usuario_por_correo_fn(text) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.cliente_eliminable_fn(uuid)')), '') not in ('f8ce7433266b5044dcd4c2c5475f681e', '4f2afd8bddbf354ec956027d9b3aeb18') then
    raise exception 'REVERSA D-19: crm.cliente_eliminable_fn(uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.fusion_previsualizar_fn(uuid, uuid)')), '') not in ('417b8ce74b4e95e7f5ccfbfe70951b21', '27eedf7b16b4d680bc6c7483901630cb') then
    raise exception 'REVERSA D-19: crm.fusion_previsualizar_fn(uuid, uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.impacto_desactivacion_usuario_fn(uuid)')), '') not in ('165bbd6e236197e5627993330c9a317f', '787c48c1a8e80a307fb1285b42f82180') then
    raise exception 'REVERSA D-19: crm.impacto_desactivacion_usuario_fn(uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.leads_por_repartir_implementacion()')), '') not in ('72ad135aa4d6c202623e8a57b34dea63', '0b67ca88bb17b8ac8059d415721504e7') then
    raise exception 'REVERSA D-19: private.leads_por_repartir_implementacion() no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.leads_vetados_persona(uuid[])')), '') not in ('d3bb89258feb3235ba5e3d3b7bf5f9d9', '7f441c688f608017bdb4d398772a2aeb') then
    raise exception 'REVERSA D-19: private.leads_vetados_persona(uuid[]) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.persona_vetada_perfil(uuid)')), '') not in ('b781240fbb6f72df381a1a262e8e9103', '597d76a6aa5f6ca75f0ffb86bd20497e') then
    raise exception 'REVERSA D-19: private.persona_vetada_perfil(uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text, text, uuid)')), '') not in ('683c16fdcb08377af860f1aa0a18f3a1', '3ea1fbae8b35c0f8d2702270dd5c6b8d') then
    raise exception 'REVERSA D-19: private.verificar_disponibilidad_lead_impl(text, text, uuid) no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
end
$pre$;

-- ── 1/34 · crm.actualizar_cliente_gerencia(uuid, jsonb) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.actualizar_cliente_gerencia(p_cliente_id uuid, p_patch jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cliente public.perfiles%rowtype;
begin
  if private.rol_crm((select auth.uid())) <> 'gerencia' then
    raise exception 'Solo Gerencia puede corregir clientes fuera de cartera'
      using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Los datos del cliente son invalidos'
      using errcode = '22023';
  end if;
  if (
    p_patch - array[
      'nombre_completo', 'nombres', 'apellidos', 'tipo_documento',
      'dni', 'telefono',
      'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
      'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
      'titular_distinto_usd', 'beneficiario_nombre_usd',
      'beneficiario_dni_usd', 'actualizado_en'
    ]::text[]
  ) <> '{}'::jsonb then
    raise exception 'El formulario intento modificar campos no permitidos'
      using errcode = '22023';
  end if;

  select *
    into v_cliente
  from public.perfiles
  where id = p_cliente_id
    and rol = 'cliente'
  for update;
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  -- F2.b (b3): el documento de un cliente ENLAZADO a una identidad solo cambia por la
  -- corrección de documento de Gerencia (b5), que realinea identificador, perfil y lead.
  if (p_patch ? 'dni' or p_patch ? 'tipo_documento')
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from crm.inversionistas i where i.perfil_id = p_cliente_id and i.estado <> 'fusionado')
     and ((p_patch ? 'dni' and p_patch->>'dni' is distinct from v_cliente.dni)
          or (p_patch ? 'tipo_documento' and p_patch->>'tipo_documento' is distinct from v_cliente.tipo_documento)) then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige por la corrección de documento (Gerencia)'
      using errcode = 'P0409';
  end if;

  update public.perfiles
     set nombre_completo = case
           when p_patch ? 'nombre_completo'
             then p_patch->>'nombre_completo'
           else nombre_completo
         end,
         nombres = case
           when p_patch ? 'nombres' then p_patch->>'nombres'
           else nombres
         end,
         apellidos = case
           when p_patch ? 'apellidos' then p_patch->>'apellidos'
           else apellidos
         end,
         tipo_documento = case
           when p_patch ? 'tipo_documento'
             then p_patch->>'tipo_documento'
           else tipo_documento
         end,
         dni = case
           when p_patch ? 'dni' then p_patch->>'dni'
           else dni
         end,
         telefono = case
           when p_patch ? 'telefono' then p_patch->>'telefono'
           else telefono
         end,
         banco = case
           when p_patch ? 'banco' then p_patch->>'banco'
           else banco
         end,
         tipo_cuenta = case
           when p_patch ? 'tipo_cuenta' then p_patch->>'tipo_cuenta'
           else tipo_cuenta
         end,
         numero_cuenta = case
           when p_patch ? 'numero_cuenta'
             then p_patch->>'numero_cuenta'
           else numero_cuenta
         end,
         cci = case
           when p_patch ? 'cci' then p_patch->>'cci'
           else cci
         end,
         titular_distinto = case
           when p_patch ? 'titular_distinto'
             then (p_patch->>'titular_distinto')::boolean
           else titular_distinto
         end,
         beneficiario_nombre = case
           when p_patch ? 'beneficiario_nombre'
             then p_patch->>'beneficiario_nombre'
           else beneficiario_nombre
         end,
         beneficiario_dni = case
           when p_patch ? 'beneficiario_dni'
             then p_patch->>'beneficiario_dni'
           else beneficiario_dni
         end,
         banco_usd = case
           when p_patch ? 'banco_usd' then p_patch->>'banco_usd'
           else banco_usd
         end,
         tipo_cuenta_usd = case
           when p_patch ? 'tipo_cuenta_usd'
             then p_patch->>'tipo_cuenta_usd'
           else tipo_cuenta_usd
         end,
         numero_cuenta_usd = case
           when p_patch ? 'numero_cuenta_usd'
             then p_patch->>'numero_cuenta_usd'
           else numero_cuenta_usd
         end,
         cci_usd = case
           when p_patch ? 'cci_usd' then p_patch->>'cci_usd'
           else cci_usd
         end,
         titular_distinto_usd = case
           when p_patch ? 'titular_distinto_usd'
             then (p_patch->>'titular_distinto_usd')::boolean
           else titular_distinto_usd
         end,
         beneficiario_nombre_usd = case
           when p_patch ? 'beneficiario_nombre_usd'
             then p_patch->>'beneficiario_nombre_usd'
           else beneficiario_nombre_usd
         end,
         beneficiario_dni_usd = case
           when p_patch ? 'beneficiario_dni_usd'
             then p_patch->>'beneficiario_dni_usd'
           else beneficiario_dni_usd
         end,
         actualizado_en = now()
   where id = p_cliente_id;

  return true;
end;
$function$;

-- ── 2/34 · crm.alta_cliente_identidad_fn(text, jsonb) (texto vivo de producción) ─────────
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
$function$;

-- ── 3/34 · crm.convertir_lead(uuid, uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.convertir_lead(p_lead_id uuid, p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text := private.rol_crm((select auth.uid()));
  v_lead       crm.leads%rowtype;
  v_dni_perfil text;
  v_tipo_perfil text;
  v_asesor     uuid;
  v_flag       boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_inv        uuid;
  v_lead_canon uuid;
  v_clave      text;
  v_hash       text;
  v_prev       jsonb;
  v_res        jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-18] (Codex #3 del bloque 2): el tramo de responsable se abre con el asesor del perfil «si está activo»,
  -- y eso se leía sin candado: una baja de analista en vuelo (crm.fijar_membresia_activa_fn, que toma el interlock
  -- EXCLUSIVO de jerarquía) podía cerrarle sus tramos mientras esta conversión le abría uno nuevo. Se toma el
  -- interlock COMPARTIDO al ENTRAR —antes de cualquier candado de negocio, el mismo orden que el offboarding:
  -- jerarquía → documento → persona → lead, así que no hay ciclo— y más abajo se revalida `activo` bajo él.
  -- Solo con la bandera ENCENDIDA: es el único caso en que se abre el tramo de responsable (más abajo, bajo
  -- `if v_flag and v_inv is not null`). Apagada, tomarlo haría esperar a TODA conversión detrás de cualquier
  -- titular del exclusivo (offboarding, RPC de jerarquía, alta de vendedor) sin ganar nada (auditor D-18 #2).
  if v_flag then
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  end if;

  -- IDEMPOTENCIA (contrato §8.2, Codex #5): misma clave + mismo payload -> mismo
  -- resultado, sin efectos. Misma clave con otro payload -> P0409.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto, sin idempotencia.)
  if v_flag then
    v_clave := 'conversion:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object('lead', p_lead_id, 'perfil', p_perfil_id));
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Con bandera ON el documento del perfil se lee ANTES del lead para tomar la
  -- identidad primero (orden identidad->lead). Con bandera OFF nada de esto corre
  -- y el perfil se lee DESPUÉS del lock del lead (idéntico a hoy, ver más abajo).
  if v_flag then
    select dni, tipo_documento, asesor_perfil_id
      into v_dni_perfil, v_tipo_perfil, v_asesor
    from public.perfiles
    where id = p_perfil_id
      and rol = 'cliente'
      and activo = true;
    if not found then
      raise exception 'El cliente destino no existe o no esta activo';
    end if;
    -- fail-closed (contrato §4.3): sin documento válido no se confirma identidad.
    if v_dni_perfil is null or pg_catalog.btrim(v_dni_perfil) = '' or v_tipo_perfil is null then
      raise exception 'No se puede convertir sin documento valido del cliente'
        using errcode = '22023';
    end if;
    -- Reusar la identidad del perfil si ya existe (una corrección de documento no
    -- parte a la persona); seguir la canónica si esa identidad está fusionada.
    select coalesce(inv.inversionista_canonico_id, inv.id)
      into v_inv
    from crm.inversionistas inv
    where inv.perfil_id = p_perfil_id
    order by (inv.estado <> 'fusionado') desc, inv.creado_en asc
    limit 1;
    -- Si el perfil aún no tiene identidad, EL PUNTO ÚNICO la resuelve/crea
    -- (advisory documental interno + índice único arbitran la carrera).
    if v_inv is null then
      v_inv := private.inversionista_resolver(v_tipo_perfil, v_dni_perfil, true, 'conversion');
    end if;
    -- Serializar por IDENTIDAD, no solo por documento: dos documentos vigentes de
    -- la misma persona convergen en esta fila y aquí se ordenan (Codex #3).
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b5) [Cx-15, E3-1]: una fusión pudo ganar mientras se esperaba este lock: la
    -- perdedora ya no convierte. Sin advisory documental AQUÍ a propósito: tomarlo después
    -- de la identidad invertiría el orden documento -> identidad que sigue la fusión.
    if exists (select 1 from crm.inversionistas i where i.id = v_inv and i.estado = 'fusionado') then
      raise exception 'La persona fue fusionada mientras se convertía; vuelve a intentarlo'
        using errcode = '40001';
    end if;
  end if;

  -- ── LEAD: ámbito + lock, y revalidación tras esperar ─────────────────────
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  -- Reintento tras éxito (el lead ya se convirtió a ESTE perfil): mismo resultado,
  -- sin efectos. Si la clave no se alcanzó a guardar (caída), se guarda ahora.
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock, INCONDICIONALMENTE (Codex): si otro ya guardó la clave,
    -- se devuelve ESE resultado; si el payload difiere (p.ej. otro perfil para el
    -- mismo lead), idem_leer lanza P0409 aquí, ya serializado — no «lead ya cerrado».
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
    -- Sin clave guardada (conversión previa a este lote) y mismo perfil: mismo hecho.
    if v_lead.perfil_id = p_perfil_id then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id,
                                             'inversionista_id', private.inversionista_canonica(v_lead.inversionista_id));
      perform private.idem_guardar(v_clave, 'conversion_avance', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Con bandera OFF: leer el perfil AHORA (tras el lock del lead), IDÉNTICO a la
  -- versión previa (misma precedencia de errores).
  if not v_flag then
    select dni, asesor_perfil_id
      into v_dni_perfil, v_asesor
    from public.perfiles
    where id = p_perfil_id
      and rol = 'cliente'
      and activo = true;
    if not found then
      raise exception 'El cliente destino no existe o no esta activo';
    end if;
  end if;

  if v_lead.dni is not null
     and v_dni_perfil is not null
     and v_lead.dni <> v_dni_perfil then
    raise exception 'El documento del cliente no coincide con el del lead';
  end if;

  if v_rol <> 'gerencia'
     and (
       v_asesor is null
       or v_asesor not in (
         select private.vendedor_ids_visibles((select auth.uid()))
       )
     )
     and not (
       v_lead.dni is not null
       and v_dni_perfil is not null
       and v_lead.dni = v_dni_perfil
     ) then
    raise exception 'Ese cliente no pertenece a tu cartera';
  end if;

  -- Invariante #6 (un solo lead total): si la identidad YA tiene otro lead, esta
  -- persona no puede abrir un segundo. Mensaje de negocio en vez del choque crudo
  -- con leads_inversionista_uidx. (Una nueva inversión sobre el cliente existente
  -- es F5, no una nueva conversión — decisión de Miguel 03/09.)
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon
    from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id
    limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento de un perfil
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #2): una reserva viva o sellada de ESTE lead pertenece a UNA persona (b4): no se convierte para otra
  -- por la puerta directa; el cierre de la saga trae la misma persona y pasa.
  if v_flag and exists (select 1 from crm.conversion_reservas r
                         where r.lead_id = p_lead_id and r.inversionista_id is not null
                           and r.inversionista_id is distinct from v_inv
                           and (r.efectos_iniciados_en is not null or r.expira_en > pg_catalog.now())) then
    raise exception 'Este lead está reservado para otra persona: espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex v3 B4): una conversión Avance en curso en OTRO lead de la misma persona (reserva viva o sellada)
  -- también rechaza la puerta directa, como ya hace convertir_lead_externo; el cierre de la saga trae su propio lead y pasa.
  if v_flag and v_inv is not null and private.persona_en_conversion(v_inv, p_lead_id) then
    raise exception 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead' using errcode = 'P0409';
  end if;

  -- ── EL CIERRE: etapa + perfil + inversionista_id EN EL MISMO UPDATE ──────
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         perfil_id = p_perfil_id,
         convertido_en = pg_catalog.now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  -- ── Reconocimiento de identidad (reemplaza al trigger 200000, solo bandera) ─
  if v_flag and v_inv is not null then
    -- Vincular perfil<->identidad y registrar el lead canónico.
    update crm.inversionistas set perfil_id = p_perfil_id
      where id = v_inv and perfil_id is null;
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);

    -- Responsable de relación (asesor del perfil), si está activo y la persona no
    -- tiene tramo abierto. (Lo hacía el trigger 200000:125-131.)
    if v_asesor is not null
       -- F2.b [D-18]: bajo el interlock compartido de jerarquía tomado al entrar, y con la fila del equipo FOR SHARE:
       -- si el analista se está dando de baja, o esta conversión espera a que termine, o la baja espera a ésta.
       and exists (select 1 from crm.equipo e where e.perfil_id = v_asesor and e.activo for share of e)
       and not exists (select 1 from crm.inversionista_responsables ir
                        where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_asesor, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_asesor
        where id = v_inv and responsable_relacion_id is null;
    end if;

    -- no_contactar del lead se centraliza en la persona. (Trigger 200000:134-137.)
    if v_lead.no_contactar then
      update crm.inversionistas
        set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;

    -- El contrato/inversión Avance lo crea su propia puerta (crear_contrato), no
    -- esta función: aquí solo se reconoce la persona (contrato §8.2).
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido a cliente',
    pg_catalog.jsonb_build_object('perfil_id', p_perfil_id),
    v_uid
  );

  v_res := pg_catalog.jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'perfil_id', p_perfil_id,
    'inversionista_id', v_inv
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_avance', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$;

-- ── 4/34 · crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.corregir_documento_inversionista_fn(p_inversionista uuid, p_tipo text, p_documento text, p_motivo text, p_identificador_anterior uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_tipo text; v_norm text;
  v_inv crm.inversionistas%rowtype; v_old_id uuid; v_old_tipo text; v_old_norm text; v_n integer; v_otro uuid; v_ahora timestamptz;
  v_perfil_id uuid; v_perfil_dni text; v_perfil_tipo text; v_lead crm.leads%rowtype; v_new_id uuid; v_op_id uuid;
  v_perfil_res text; v_lead_res text; v_k text; v_docs text[]; v_reusa boolean := false;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  v_tipo := pg_catalog.upper(pg_catalog.btrim(coalesce(p_tipo, '')));
  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido' using errcode = '22023';
  end if;
  if (v_tipo = 'DNI' and v_norm !~ '^[0-9]{8}$')
     or (v_tipo = 'CE' and v_norm !~ '^[0-9]{9,12}$')
     or (v_tipo = 'PASAPORTE' and v_norm !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: corrige en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- El identificador que sale, leído SIN lock (solo para calcular los advisories); se revalida bajo la identidad [E3-5].
  -- La unicidad «único de su tipo» solo se exige cuando NO se indica cuál sale [E3-15].
  if p_identificador_anterior is not null then
    select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
    from crm.inversionista_identificadores d
    where d.id = p_identificador_anterior and d.inversionista_id = p_inversionista and d.estado = 'vigente';
    if v_old_id is null then
      raise exception 'El identificador anterior no es un documento vigente de esta persona' using errcode = 'P0409';
    end if;
  else
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n > 1 then
      raise exception 'La persona tiene varios documentos vigentes de tipo %: indica cuál sustituir (p_identificador_anterior)', v_tipo using errcode = '22023';
    elsif v_n = 1 then
      select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
      from crm.inversionista_identificadores d
      where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    end if;
  end if;
  if v_old_tipo = v_tipo and v_old_norm = v_norm then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_norm, v_old_norm] || coalesce((select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista), '{}'));

  -- jerarquía [E3-2] + Gerencia revalidada -> advisories de viejo y nuevo, ordenados -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona (membresía revalidada)' using errcode = '42501';
  end if;
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct k from unnest(array[v_tipo || ':' || v_norm, v_old_tipo || ':' || v_old_norm]) k where k is not null) s;
  foreach v_k in array v_docs loop
    perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
  end loop;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se corregía (estado %); vuelve a intentarlo', v_inv.estado using errcode = '40001';
  end if;
  if v_old_id is not null then
    if not exists (select 1 from crm.inversionista_identificadores d where d.id = v_old_id and d.inversionista_id = p_inversionista
                     and d.estado = 'vigente' and d.tipo_documento = v_old_tipo and d.documento_normalizado = v_old_norm) then
      raise exception 'El documento de la persona cambió mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  if p_identificador_anterior is null then
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n <> (case when v_old_id is null then 0 else 1 end) then
      raise exception 'Los documentos de la persona cambiaron mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  -- el nuevo, ¿ya es vigente de alguien?
  select d.inversionista_id, d.id into v_otro, v_new_id from crm.inversionista_identificadores d
  where d.tipo_documento = v_tipo and d.documento_normalizado = v_norm and d.estado = 'vigente';
  if v_otro is not null and v_otro <> p_inversionista then
    raise exception 'El documento pertenece a otra persona reconocida: fusiona las identidades en vez de corregir' using errcode = 'P0409';
  end if;
  if v_otro = p_inversionista then
    if v_old_id is null then
      return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
    end if;
    v_reusa := true;   -- [E3-15] el destino ya es un vigente propio (p. ej. tras una fusión): sale el anterior y se reutiliza
  else
    v_new_id := null;
  end if;
  -- alta/conversión en curso [E3-7]: claim y reservas (por persona O por lead) bajo lock
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- perfil enlazado FOR UPDATE (escribe) -> cierres -> tareas -> lead (NOWAIT) -> reservas -> contactos -> terceros
  if v_inv.perfil_id is not null then
    select p.id, p.dni, p.tipo_documento into v_perfil_id, v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_inv.perfil_id for update;
  end if;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id = p_inversionista or ce.lead_id in (select private.leads_de_identidades(array[p_inversionista]))
   order by ce.id for update;
  perform 1 from crm.tareas t where t.estado = 'pendiente'
     and t.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by t.id for update;
  perform private.bloquear_leads_nowait(coalesce((select pg_catalog.array_agg(x) from private.leads_de_identidades(array[p_inversionista]) x), '{}'));
  select * into v_lead from crm.leads l where l.inversionista_id = p_inversionista order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by r.lead_id for update;
  if exists (select 1 from crm.conversion_reservas r left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])))
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    raise exception 'Hay una reserva de conversión viva o sellada sin convertir (por persona o por lead): termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- contactos (último recurso del orden) ANTES de mirar a terceros [E3-6]: el trigger los retoma reentrante
  if v_lead.id is not null then
    perform private.bloquear_contactos_lead(array[v_lead.telefono], array[v_lead.dni, case when v_tipo = 'DNI' then v_norm end]);
  else
    perform private.bloquear_contactos_lead(array[]::text[], array[case when v_tipo = 'DNI' then v_norm end]);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  if exists (select 1 from public.perfiles pp
              where pp.rol = 'cliente'
                and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(pp.dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
                and coalesce(nullif(pg_catalog.btrim(pp.tipo_documento), ''), 'DNI') = v_tipo
                and pp.id is distinct from v_inv.perfil_id) then
    raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id
                                  and l.activo = true and l.etapa not in ('convertido', 'descartado')) then
    raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id and l.inversionista_id is not null
                                  and l.inversionista_id <> p_inversionista) then
    raise exception 'Otro lead enlazado a otra persona lleva ese DNI: fusiona o corrige ese lead primero' using errcode = 'P0409';
  end if;
  -- [auditor M2] lo que la excepción del trigger deja de comprobar: OTRO lead con ese DNI vetado o en enfriamiento congela el
  -- documento (el veto de la PROPIA persona no cuenta: corregir su documento es justamente lo que Gerencia está haciendo).
  if v_tipo = 'DNI' and exists (
       select 1 from crm.leads l
       left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
       where l.dni = v_norm and l.id is distinct from v_lead.id
         and (l.inversionista_id is null or l.inversionista_id <> p_inversionista)
         and (l.no_contactar
              or (l.etapa = 'descartado' and l.descartado_en is not null and coalesce(ep.dias, 0) > 0
                  and l.descartado_en + pg_catalog.make_interval(days => ep.dias) > pg_catalog.now()))) then
    raise exception 'Ese DNI está congelado por un veto o un enfriamiento vigente en otro lead: revisión de Gerencia' using errcode = 'P0409';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  perform pg_catalog.set_config('crm.correccion_documento', 'on', true);   -- [auditor M1] la excepción del trigger la exige
  if v_old_id is not null then
    update crm.inversionista_identificadores set estado = 'historico', vigente_hasta = v_ahora where id = v_old_id;
  end if;
  if not v_reusa then
    insert into crm.inversionista_identificadores
      (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
    values (p_inversionista, v_tipo, v_norm, p_documento, 'vigente', true, 'correccion', v_ahora, v_uid)
    returning id into v_new_id;
  else
    -- [Codex B3] el destino reutilizado queda VERIFICADO con la misma política de la corrección
    update crm.inversionista_identificadores set verificado = true, fuente = coalesce(fuente, 'correccion') where id = v_new_id and verificado = false;
  end if;
  v_perfil_res := case when v_inv.perfil_id is null then 'ninguno' else 'sin_cambio' end;
  if v_perfil_id is not null and v_old_id is not null
     and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_perfil_dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_old_norm
     and coalesce(nullif(pg_catalog.btrim(v_perfil_tipo), ''), 'DNI') = v_old_tipo then
    begin
      update public.perfiles set dni = v_norm, tipo_documento = v_tipo where id = v_perfil_id;
    exception when unique_violation then
      raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
    end;
    v_perfil_res := 'actualizado';
  end if;
  v_lead_res := case when v_lead.id is null then 'sin_lead' else 'sin_cambio' end;
  if v_lead.id is not null and v_old_id is not null and v_old_tipo = 'DNI' and v_lead.dni = v_old_norm then
    if v_tipo = 'DNI' then
      begin
        update crm.leads set dni = v_norm where id = v_lead.id;
      exception when unique_violation then
        raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
      end;
      v_lead_res := 'dni';
    else
      update crm.leads set dni = null where id = v_lead.id;
      v_lead_res := 'nulo';
    end if;
  end if;
  insert into crm.inversionista_operaciones
    (tipo, inversionista_id, lead_id, identificador_anterior_id, identificador_nuevo_id, motivo, detalle, por)
  values ('correccion', p_inversionista, v_lead.id, v_old_id, v_new_id, p_motivo,
          pg_catalog.jsonb_build_object('tipo_documento', v_tipo, 'perfil', v_perfil_res, 'lead', v_lead_res, 'reutilizado', v_reusa), v_uid)
  returning id into v_op_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Documento corregido por Gerencia (' || v_tipo || ')',
            pg_catalog.jsonb_build_object('evento', 'correccion_documento', 'operacion_id', v_op_id,
                                          'inversionista_id', p_inversionista, 'lead', v_lead_res),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.correccion_documento', 'off', true);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'corregido', 'inversionista_id', p_inversionista,
    'operacion_id', v_op_id, 'identificador_nuevo_id', v_new_id, 'identificador_anterior_id', v_old_id,
    'reutilizado', v_reusa, 'perfil', v_perfil_res, 'lead', v_lead_res);
end;
$function$;

-- ── 5/34 · crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid                  uuid := (select auth.uid());
  v_cliente_id           uuid;
  v_moneda               text;
  v_tipo_seleccion       text;
  v_cuenta_id            uuid;
  v_cuenta_activa        crm.cuentas_bancarias%rowtype;
  v_banco                text;
  v_tipo_cuenta          text;
  v_numero_cuenta        text;
  v_cci                  text;
  v_titular_distinto     boolean := false;
  v_beneficiario_nombre  text;
  v_beneficiario_dni     text;
  v_cuenta_esperada      jsonb;
  v_origen               text;
  v_resultado            jsonb;
  v_contrato_id          uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;
  if p_cuenta is null or jsonb_typeof(p_cuenta) <> 'object' then
    raise exception using errcode = '22023', message = 'Selecciona la cuenta para el pago de intereses';
  end if;

  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Cliente invalido';
  end;
  v_moneda := upper(btrim(coalesce(p_contrato->>'moneda', '')));
  if v_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda del contrato invalida';
  end if;
  if not (select private.puede_registrar_ventas()) then
    raise exception using errcode = '42501', message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  -- F2.b (E4) [Codex B-2]: la prepuerta de reconocimiento (jerarquía -> documento -> identidad -> perfil) va ANTES
  -- de los locks de cuenta/perfil de este wrapper, con el mismo orden que public.crear_contrato (reentrante allí).
  -- Después del 42501 de arriba: la precedencia para un no autorizado no cambia.
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from public.perfiles p where p.id = v_cliente_id and p.rol = 'cliente' and p.activo) then
    perform private.asegurar_identidad_perfil(v_cliente_id, 'contrato');
  end if;
  v_tipo_seleccion := lower(btrim(coalesce(p_cuenta->>'tipo', '')));

  if v_tipo_seleccion = 'existente' then
    begin
      v_cuenta_id := (p_cuenta->>'cuenta_id')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'Cuenta bancaria invalida';
    end;

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.id = v_cuenta_id
      and cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.activa = true
    for share;
    if not found then
      raise exception using
        errcode = '22023',
        message = 'La cuenta bancaria no esta disponible para este cliente y moneda';
    end if;

  elsif v_tipo_seleccion in ('perfil', 'nueva') then
    if v_tipo_seleccion = 'perfil' then
      select
        btrim(case when v_moneda = 'USD' then p.banco_usd else p.banco end),
        lower(btrim(case when v_moneda = 'USD' then p.tipo_cuenta_usd else p.tipo_cuenta end)),
        upper(btrim(case when v_moneda = 'USD' then p.numero_cuenta_usd else p.numero_cuenta end)),
        btrim(case when v_moneda = 'USD' then p.cci_usd else p.cci end),
        case when v_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end,
        case when v_moneda = 'USD' then p.beneficiario_nombre_usd else p.beneficiario_nombre end,
        case when v_moneda = 'USD' then p.beneficiario_dni_usd else p.beneficiario_dni end
      into v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
           v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni
      from public.perfiles p
      where p.id = v_cliente_id
      -- La fotografia del perfil debe seguir siendo cierta hasta que termine
      -- el alta. Sin este lock, un UPDATE concurrente podia confirmar despues
      -- del SELECT y antes de crear el vinculo contractual.
      for share;
      v_origen := 'perfil';
    else
      v_banco := btrim(coalesce(p_cuenta->>'banco', ''));
      v_tipo_cuenta := lower(btrim(coalesce(p_cuenta->>'tipo_cuenta', '')));
      v_numero_cuenta := upper(btrim(coalesce(p_cuenta->>'numero_cuenta', '')));
      v_cci := btrim(coalesce(p_cuenta->>'cci', ''));
      begin
        v_titular_distinto := coalesce((p_cuenta->>'titular_distinto')::boolean, false);
      exception when invalid_text_representation then
        raise exception using errcode = '22023', message = 'Indicador de beneficiario invalido';
      end;
      v_beneficiario_nombre := p_cuenta->>'beneficiario_nombre';
      v_beneficiario_dni := p_cuenta->>'beneficiario_dni';
      v_origen := 'contrato';
    end if;

    v_banco := btrim(coalesce(v_banco, ''));
    v_tipo_cuenta := lower(btrim(coalesce(v_tipo_cuenta, '')));
    v_numero_cuenta := upper(btrim(coalesce(v_numero_cuenta, '')));
    v_cci := btrim(coalesce(v_cci, ''));
    if v_titular_distinto then
      v_beneficiario_nombre := upper(regexp_replace(btrim(coalesce(v_beneficiario_nombre, '')), '\s+', ' ', 'g'));
      v_beneficiario_dni := btrim(coalesce(v_beneficiario_dni, ''));
    else
      v_beneficiario_nombre := null;
      v_beneficiario_dni := null;
    end if;

    if v_tipo_seleccion = 'perfil' then
      v_cuenta_esperada := jsonb_build_object(
        'banco', v_banco,
        'tipo_cuenta', v_tipo_cuenta,
        'numero_cuenta', v_numero_cuenta,
        'cci', v_cci,
        'titular_distinto', v_titular_distinto,
        'beneficiario_nombre', v_beneficiario_nombre,
        'beneficiario_dni', v_beneficiario_dni
      );
      if jsonb_typeof(p_cuenta->'cuenta_esperada') is distinct from 'object'
         or (p_cuenta->'cuenta_esperada') is distinct from v_cuenta_esperada then
        raise exception using
          errcode = 'P0001',
          message = 'La cuenta actual del cliente cambio. Recarga las cuentas y vuelve a seleccionarla';
      end if;
    end if;

    if length(v_banco) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'Selecciona el banco de la cuenta';
    end if;
    if v_tipo_cuenta not in ('ahorros', 'corriente') then
      raise exception using errcode = '22023', message = 'Selecciona un tipo de cuenta valido';
    end if;
    if v_numero_cuenta !~ '^[A-Za-z0-9-]{1,30}$' then
      raise exception using errcode = '22023', message = 'El numero de cuenta solo puede contener letras, numeros y guiones';
    end if;
    if v_cci !~ '^[0-9]{20}$' then
      raise exception using errcode = '22023', message = 'El CCI debe tener exactamente 20 digitos';
    end if;
    if v_titular_distinto and (
      length(v_beneficiario_nombre) not between 1 and 200
      or v_beneficiario_dni !~ '^[0-9]{8,12}$'
    ) then
      raise exception using errcode = '22023', message = 'Completa correctamente los datos del beneficiario';
    end if;

    -- Serializa dos altas simultaneas del mismo CCI sin bloquear otras cuentas.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_cliente_id::text || '|' || v_moneda || '|' || v_cci, 0)
    );

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.cci = v_cci
      and cb.activa = true
    for update;

    if found
       and lower(v_cuenta_activa.banco) = lower(v_banco)
       and v_cuenta_activa.tipo_cuenta = v_tipo_cuenta
       and v_cuenta_activa.numero_cuenta = v_numero_cuenta
       and v_cuenta_activa.titular_distinto = v_titular_distinto
       and v_cuenta_activa.beneficiario_nombre is not distinct from v_beneficiario_nombre
       and v_cuenta_activa.beneficiario_dni is not distinct from v_beneficiario_dni then
      v_cuenta_id := v_cuenta_activa.id;
    else
      if found then
        update crm.cuentas_bancarias
           set activa = false,
               desactivada_por = v_uid,
               desactivada_en = now()
         where id = v_cuenta_activa.id;
      end if;

      insert into crm.cuentas_bancarias (
        cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
        titular_distinto, beneficiario_nombre, beneficiario_dni,
        activa, origen, creado_por
      ) values (
        v_cliente_id, v_moneda, v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
        v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni,
        true, v_origen, v_uid
      )
      returning id into v_cuenta_id;
    end if;
  else
    raise exception using
      errcode = '22023',
      message = 'Selecciona una cuenta existente o registra una cuenta nueva';
  end if;

  -- public.crear_contrato mantiene su validacion de rol/cartera, numeracion,
  -- contrato, cronograma y co-titulares. La llamada anidada participa de ESTA
  -- transaccion: si el enlace bancario falla, todo (incluida una cuenta nueva)
  -- se revierte.
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador valido';
  end;
  if v_contrato_id is null then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador';
  end if;

  insert into crm.contrato_cuentas_pago (
    contrato_id, cuenta_bancaria_id, creado_por
  ) values (
    v_contrato_id, v_cuenta_id, v_uid
  );

  return v_resultado || jsonb_build_object('cuenta_bancaria_id', v_cuenta_id);
end;
$function$;

-- ── 6/34 · crm.eliminar_cliente_fn(uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.eliminar_cliente_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_pre jsonb; v_nombre text; v_n integer;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el servicio elimina clientes' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el edge usa su ruta de siempre' using errcode = 'P0409';
  end if;
  select p.nombre_completo into v_nombre from public.perfiles p where p.id = p_perfil_id and p.rol = 'cliente' for update;
  if not found then
    raise exception 'El cliente no existe o ya fue eliminado' using errcode = 'P0002';
  end if;
  v_pre := crm.cliente_eliminable_fn(p_perfil_id);
  if coalesce((v_pre->>'eliminable')::boolean, false) is not true then
    raise exception '%', coalesce(v_pre->>'mensaje', 'El cliente no se puede eliminar')
      using errcode = 'P0409', detail = v_pre::text;
  end if;
  -- Un perfil de una saga aún sin enlazar tampoco se borra por aquí.
  if exists (select 1 from crm.multiempresa_idempotencia i
                 where i.clave like 'auth\_persona:%' and i.resultado->>'perfil_id' = p_perfil_id::text
                   and i.resultado->>'estado' <> 'enlazado') then
    raise exception 'Este cliente tiene un alta en curso (identidad unificada): espera a que termine' using errcode = 'P0409';
  end if;
  delete from public.novedades n where n.destinatario_id = p_perfil_id;
  get diagnostics v_n = row_count;
  delete from public.perfiles p where p.id = p_perfil_id;
  return pg_catalog.jsonb_build_object('ok', true, 'nombre', v_nombre, 'comunicados_borrados', v_n);
end;
$function$;

-- ── 7/34 · crm.enlazar_lead_inversionista_fn(uuid, uuid, text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.enlazar_lead_inversionista_fn(p_lead_id uuid, p_inversionista uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_lead0 crm.leads%rowtype; v_lead crm.leads%rowtype; v_cierre crm.cierres_externos%rowtype;
  v_perfil_inv uuid; v_perfil_dni text; v_perfil_tipo text; v_ahora timestamptz; v_veto boolean; v_n_tareas integer := 0;
  v_perfil_completado boolean := false; v_cierre_completado boolean := false; v_op_id uuid;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: enlaza a su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  select * into v_lead0 from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'El lead no existe' using errcode = 'P0002';
  end if;
  if v_lead0.inversionista_id is not null then
    raise exception 'El lead ya está enlazado a una persona' using errcode = 'P0409';
  end if;
  if v_lead0.dni is null then
    raise exception 'El lead no tiene DNI: solo el documento exacto enlaza (corrige el DNI del lead primero)' using errcode = 'P0409';
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_lead0.dni] || coalesce((select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista), '{}'));

  -- jerarquía + Gerencia revalidada -> documento del lead -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona (membresía revalidada)' using errcode = '42501';
  end if;
  perform private.identidad_bloquear_documento('DNI', v_lead0.dni);
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if not private.documento_es_de_identidad(p_inversionista, 'DNI', v_lead0.dni) then
    if private.inversionista_por_documento('DNI', v_lead0.dni) is not null then
      raise exception 'El DNI del lead pertenece a otra persona reconocida: fusiona o corrige primero' using errcode = 'P0409';
    end if;
    raise exception 'El DNI del lead no es un documento vigente y verificado de esta persona: corrige el documento primero' using errcode = 'P0409';
  end if;
  if exists (select 1 from private.leads_de_identidades(array[p_inversionista]) x where x <> p_lead_id) then
    raise exception 'La persona ya tiene su lead (enlace vivo o puente, activo o no): reconciliación de clase E hasta F5' using errcode = 'P0409';
  end if;
  -- unión de enlaces del lead [E3-10]: perfil (FOR SHARE, por DOCUMENTO) -> cierre (por DOCUMENTO) -> puente -> tareas -> lead -> reservas -> claim
  if v_lead0.perfil_id is not null then
    select p.dni, p.tipo_documento into v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_lead0.perfil_id for share;
    select i.id into v_perfil_inv from crm.inversionistas i where i.perfil_id = v_lead0.perfil_id and i.estado <> 'fusionado' limit 1;
    if v_perfil_inv is not null and v_perfil_inv <> p_inversionista then
      raise exception 'El perfil de cliente del lead pertenece a otra persona reconocida: reconciliación (fusión/corrección)' using errcode = 'P0409';
    end if;
    if v_perfil_inv is null then
      if v_inv.perfil_id is not null and v_inv.perfil_id <> v_lead0.perfil_id then
        raise exception 'La persona ya tiene otro perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)' using errcode = 'P0409';
      end if;
      if not private.documento_es_de_identidad(p_inversionista, v_perfil_tipo, v_perfil_dni) then
        raise exception 'El documento del perfil de cliente del lead no es de esta persona: corrige el documento primero' using errcode = 'P0409';
      end if;
    end if;
  end if;
  select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id for update;
  if v_cierre.id is not null then
    if v_cierre.inversionista_id is not null and v_cierre.inversionista_id <> p_inversionista then
      raise exception 'El cierre del lead pertenece a otra persona reconocida: reconciliación' using errcode = 'P0409';
    end if;
    if v_cierre.inversionista_id is null and not private.documento_es_de_identidad(p_inversionista, v_cierre.documento_tipo, v_cierre.documento) then
      raise exception 'El documento del cierre del lead no es de esta persona: reconciliación documental primero' using errcode = 'P0409';
    end if;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id and il.inversionista_id <> p_inversionista) then
    raise exception 'El puente del lead apunta a otra persona: reconciliación' using errcode = 'P0409';
  end if;
  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = p_lead_id order by t.id for update;
  perform private.bloquear_leads_nowait(array[p_lead_id]);
  select * into v_lead from crm.leads where id = p_lead_id;
  if v_lead.inversionista_id is not null or v_lead.perfil_id is distinct from v_lead0.perfil_id or v_lead.dni is distinct from v_lead0.dni then
    raise exception 'El lead cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
              and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))
              and (r.inversionista_id is null or r.inversionista_id <> p_inversionista)) then
    raise exception 'El lead tiene una reserva de conversión viva o sellada (de otra persona o sin persona): termina o deja caducar' using errcode = 'P0409';
  end if;
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de enlazar' using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_inv.no_contactar or v_lead.no_contactar;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inversionista where id = p_lead_id;   -- el trigger zz escribe el puente canónico si no existe
  if v_lead0.perfil_id is not null and v_inv.perfil_id is null then
    update crm.inversionistas set perfil_id = v_lead0.perfil_id where id = p_inversionista;
    v_perfil_completado := true;
  end if;
  if v_cierre.id is not null and v_cierre.inversionista_id is null then
    update crm.cierres_externos set inversionista_id = p_inversionista where id = v_cierre.id;
    v_cierre_completado := true;
  end if;
  if v_veto and not v_inv.no_contactar then
    update crm.inversionistas set no_contactar = true, no_contactar_en = v_ahora, no_contactar_por = v_uid where id = p_inversionista;
  end if;
  if v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(p_lead_id);
    update crm.leads set no_contactar = true where id = p_lead_id;
  end if;
  insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)
  values ('enlace', p_inversionista, p_lead_id, p_motivo,
          pg_catalog.jsonb_build_object('perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado,
                                        'veto', v_veto, 'tareas_canceladas', v_n_tareas, 'lead_activo', v_lead.activo), v_uid)
  returning id into v_op_id;
  if v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Lead enlazado a una persona reconocida (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'operacion_id', v_op_id, 'inversionista_id', p_inversionista, 'veto', v_veto),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', p_inversionista, 'operacion_id', v_op_id,
    'perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado, 'veto', v_veto, 'tareas_canceladas', v_n_tareas);
end;
$function$;

-- ── 8/34 · crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.fijar_membresia_activa_fn(p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_activo_anterior boolean;
  v_version timestamptz;
  v_perfil_activo boolean;
  v_rol_portal text;
  v_rol_reemplazo text;
  v_reemplazo_activo boolean;
  v_reemplazo_portal_activo boolean;
  v_impacto jsonb;
  v_requiere_reemplazo boolean;
  v_evento_objetivo uuid;
  v_flag boolean;                          -- F2.b [D-2]
  v_personas uuid[] := array[]::uuid[];    -- F2.b [D-2]: identidades (no fusionadas) a cargo del saliente
  v_nuevas uuid[] := array[]::uuid[];      -- F2.b [D-2]: las que aparecieron entre el censo y el bloqueo de sus leads
  v_ahora timestamptz;                     -- F2.b [D-2]
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede activar o desactivar membresias CRM';
  end if;
  if p_activo is null or p_version_equipo is null or p_idempotencia is null then
    raise exception 'Estado, version e idempotencia requeridos';
  end if;
  if p_activo is false and p_perfil_id = v_actor then
    raise exception 'Gerencia no puede desactivar su propia membresia';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  -- F2.b [D-2]: la bandera se lee BAJO el interlock exclusivo (las puertas de identidad de b5 lo toman compartido).
  v_flag := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);

  select e.rol_crm, e.activo, e.actualizado_en, p.activo, p.rol
    into v_rol, v_activo_anterior, v_version, v_perfil_activo, v_rol_portal
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
  for update of e;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion in ('membresia_activada','membresia_desactivada')
    and ue.idempotencia = p_idempotencia
  limit 1;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La membresia fue modificada por otra sesion';
  end if;

  if p_activo and v_rol_portal = 'superadmin' and v_rol <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede activarse en CRM como Gerencia';
  end if;

  if v_activo_anterior is not distinct from p_activo then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  if p_activo then
    if v_perfil_activo is not true then
      raise exception 'El perfil esta suspendido en Portal; Gerencia no puede reactivarlo';
    end if;

    update crm.equipo e set activo = true
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_activada', p_perfil_id,
      pg_catalog.jsonb_build_object('estado_nuevo', 'activo'),
      p_idempotencia
    );
  else
    v_impacto := crm.impacto_desactivacion_usuario_fn(p_perfil_id);
    v_requiere_reemplazo := (v_impacto->>'requiere_reemplazo')::boolean;

    if v_requiere_reemplazo and p_reemplazo_id is null then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;
    -- F2.b [D-2]: con la identidad encendida nadie se queda sin responsable: si el saliente tiene personas a cargo,
    -- la baja exige reemplazo (mismo mensaje), aunque la bandera cambiara entre la lectura del impacto y esta.
    if v_flag and p_reemplazo_id is null and exists (select 1 from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))) then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;

    if p_reemplazo_id is not null then
      if p_reemplazo_id = p_perfil_id then
        raise exception 'El reemplazo debe ser otro usuario';
      end if;

      select e.rol_crm, e.activo, p.activo
        into v_rol_reemplazo, v_reemplazo_activo, v_reemplazo_portal_activo
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = p_reemplazo_id
      for update of e;

      if not found
         or v_reemplazo_activo is not true
         or v_reemplazo_portal_activo is not true
         or v_rol_reemplazo is distinct from v_rol then
        raise exception 'El reemplazo no existe, no esta activo o no tiene el mismo rol CRM';
      end if;

      if exists (
        with recursive descendientes as (
          select e.perfil_id
          from crm.equipo e
          where e.supervisor_id = p_perfil_id
          union
          select e.perfil_id
          from crm.equipo e
          join descendientes d on e.supervisor_id = d.perfil_id
        )
        select 1 from descendientes where perfil_id = p_reemplazo_id
      ) then
        raise exception 'El reemplazo no puede pertenecer al subarbol del usuario saliente';
      end if;

      -- F2.b [D-2]: las PERSONAS del saliente (identidades activas con tramo abierto suyo o apuntándole) se bloquean
      -- ANTES que sus leads —la misma arista persona → lead de conversiones y veto; FOR NO KEY UPDATE, que serializa
      -- contra el FOR UPDATE de reasignar/marcar/convertir sin chocar con las FK— y sus tramos abiertos FOR UPDATE.
      if v_flag then
        -- (Codex N2) SIN ESPERAR: el alta de una tarea de cliente toma a la persona y luego a este mismo equipo; esperar
        -- aquí con equipo en la mano sería el abrazo. Si alguien tiene a una persona del saliente → 40001, se reintenta.
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_personas
          from (select i.id from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una persona a cargo del saliente está siendo actualizada; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        perform 1 from crm.inversionista_responsables r
         where r.inversionista_id = any(v_personas) and r.hasta is null
         order by r.id
         for update;
        -- (auditor M5) y las tareas pendientes del saliente ANTES que sus leads (tareas → leads), la misma disciplina que
        -- el veto (b2/D-3), reasignar y cerrar_tarea: el offboarding iba leads → tareas y podía abrazarse con un veto en
        -- curso sobre una persona que no está «a cargo» del saliente. Solo con la identidad encendida (paridad OFF).
        perform 1 from crm.tareas t
         where t.activo is true and t.estado = 'pendiente'
           and (t.vendedor_id = p_perfil_id or t.asignado_supervisor_id = p_perfil_id
                or t.lead_id in (select l.id from crm.leads l
                                  where (l.vendedor_id = p_perfil_id or l.asignado_supervisor_id = p_perfil_id)
                                    and l.activo is true and l.etapa not in ('convertido', 'descartado')))
         order by t.id
         for update;
      end if;

      update crm.equipo e
      set supervisor_id = p_reemplazo_id
      where e.supervisor_id = p_perfil_id and e.activo is true;

      update crm.leads l
      set vendedor_id = p_reemplazo_id
      where l.vendedor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      update crm.leads l
      set asignado_supervisor_id = p_reemplazo_id
      where l.asignado_supervisor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      -- F2.b [D-2] (Codex #3): una conversión en vuelo sobre un lead del saliente (no toma el interlock de jerarquía) pudo
      -- abrir un tramo al saliente DESPUÉS del censo. Con sus leads ya bloqueados por los dos UPDATE de arriba ninguna
      -- conversión suya sigue en vuelo: se repite el censo; lo que apareció se bloquea SIN esperar (persona tras lead es
      -- la arista inversa: si alguien la tiene → 40001, Gerencia reintenta) y se suma al traslado.
      if v_flag then
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_nuevas
          from (select i.id from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))
                   and not (i.id = any(v_personas))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una conversión de un lead del saliente sigue en curso; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        if coalesce(pg_catalog.array_length(v_nuevas, 1), 0) > 0 then
          perform 1 from crm.inversionista_responsables r
           where r.inversionista_id = any(v_nuevas) and r.hasta is null
           order by r.id
           for update;
          v_personas := v_personas || v_nuevas;
        end if;
      end if;

      -- Los triggers de leads sincronizan la agenda normal. Este barrido cubre
      -- ademas tareas independientes y cualquier residuo historico pendiente.
      update crm.tareas t
      set vendedor_id = p_reemplazo_id
      where t.vendedor_id = p_perfil_id
        and t.activo is true and t.estado = 'pendiente';

      update crm.tareas t
      set asignado_supervisor_id = p_reemplazo_id
      where t.asignado_supervisor_id = p_perfil_id
        and t.activo is true and t.estado = 'pendiente';

      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;

      -- F2.b [D-2]: el responsable de relación pasa al reemplazo en la MISMA transacción: se cierra cada tramo abierto
      -- del saliente y se abre otro al reemplazo (motivo 'offboarding', por = Gerencia), y responsable_relacion_id lo
      -- acompaña. Un único v_ahora tomado DESPUÉS de los locks [E3-14]. Con la bandera apagada, nada (paridad).
      if v_flag and coalesce(pg_catalog.array_length(v_personas, 1), 0) > 0 then
        v_ahora := pg_catalog.clock_timestamp();
        update crm.inversionista_responsables r
           set hasta = v_ahora
         where r.inversionista_id = any(v_personas) and r.hasta is null;
        insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
        select s.id, p_reemplazo_id, v_ahora, 'offboarding', v_actor
        from pg_catalog.unnest(v_personas) as s(id);
        update crm.inversionistas i
           set responsable_relacion_id = p_reemplazo_id
         where i.id = any(v_personas);
      end if;
    end if;

    update crm.equipo e set activo = false
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_desactivada', p_perfil_id,
      pg_catalog.jsonb_build_object(
        'reemplazo_id', p_reemplazo_id,
        'subordinados_transferidos', (v_impacto->>'subordinados_activos')::integer,
        'leads_transferidos',
          (v_impacto->>'leads_abiertos')::integer
          + (v_impacto->>'leads_en_bandeja')::integer,
        'tareas_transferidas', (v_impacto->>'tareas_pendientes')::integer,
        'clientes_transferidos', (v_impacto->>'clientes_activos')::integer
      ) || case when v_flag then pg_catalog.jsonb_build_object('personas_transferidas', coalesce(pg_catalog.array_length(v_personas, 1), 0)) else '{}'::jsonb end,  -- F2.b [D-2]
      p_idempotencia
    );
  end if;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'activo_crm', p_activo,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$function$;

-- ── 9/34 · crm.fusionar_inversionistas_fn(uuid, uuid, text, text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.fusionar_inversionistas_fn(p_perdedora uuid, p_canonica uuid, p_motivo text, p_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_row crm.inversionistas%rowtype;
  v_lead crm.leads%rowtype; v_leads uuid[]; v_docs text[]; v_docs2 text[]; v_bloq text[]; v_foto jsonb; v_ahora timestamptz;
  v_veto boolean; v_tramo_p crm.inversionista_responsables%rowtype; v_tramo_c crm.inversionista_responsables%rowtype;
  v_t crm.inversion_titulares%rowtype; v_t2 crm.inversion_titulares%rowtype; v_fusion_id uuid; v_impacto jsonb;
  v_n_ident integer := 0; v_n_cierres integer := 0; v_n_inv integer := 0; v_n_tit integer := 0;
  v_perfiles_fusion uuid[] := '{}';        -- F2.b [D-18] (N6): perfiles cliente de las dos personas (tareas de cliente)
  v_n_tareas_cliente integer := 0;         -- F2.b [D-18] (N6)
  v_n_tit_dup integer := 0; v_n_res integer := 0; v_n_pred integer := 0; v_n_tareas integer := 0; v_n_puente integer := 0;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_perdedora is null or p_canonica is null or p_perdedora = p_canonica then
    raise exception 'Indica dos identidades distintas' using errcode = '22023';
  end if;
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Falta la huella de la previsualización (p_hash)' using errcode = '22023';
  end if;

  -- 1. jerarquía compartida [E3-2] y Gerencia REVALIDADA bajo ella -> 2. documentos vigentes de ambas (sin lock, ordenados)
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades (membresía revalidada)' using errcode = '42501';
  end if;
  v_docs := private.identidad_bloquear_documentos_de(array[p_perdedora, p_canonica]);
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id in (p_perdedora, p_canonica)));
  -- 3. identidades FOR UPDATE por id ascendente (P, C y las predecesoras de P: el aplanado no espera después de las reservas [E3-12])
  for v_row in select * from crm.inversionistas where id in (p_perdedora, p_canonica) order by id for update loop
    if v_row.id = p_perdedora then v_p := v_row; else v_c := v_row; end if;
  end loop;
  if v_p.id is null or v_c.id is null then
    raise exception 'Alguna de las identidades no existe' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.inversionista_canonico_id = p_perdedora and i.id not in (p_perdedora, p_canonica) order by i.id for update;
  select pg_catalog.array_agg(k order by k) into v_docs2
  from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
        from crm.inversionista_identificadores d where d.inversionista_id in (p_perdedora, p_canonica) and d.estado = 'vigente') s;
  if coalesce(v_docs2, '{}') is distinct from v_docs then
    raise exception 'Los documentos de la persona cambiaron mientras se esperaba; vuelve a previsualizar' using errcode = '40001';
  end if;
  -- 4. perfiles FOR SHARE (directos y de los leads [Codex B1]) -> 5. cierres -> 6. inversiones/titulares -> 7. tramos -> 8. tareas -> 9. leads (NOWAIT) -> 10. reservas -> 11. claims
  v_leads := coalesce((select pg_catalog.array_agg(x order by x) from private.leads_de_identidades(array[p_perdedora, p_canonica]) x), '{}');
  perform 1 from public.perfiles p
   where p.id in (v_p.perfil_id, v_c.perfil_id) or p.id in (select l.perfil_id from crm.leads l where l.id = any(v_leads))
   order by p.id for share;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id in (p_perdedora, p_canonica) or ce.lead_id = any(v_leads)
   order by ce.id for update;
  perform 1 from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica) order by i.id for update;
  perform 1 from crm.inversion_titulares t
   where t.inversionista_id in (p_perdedora, p_canonica)
      or t.inversion_id in (select i.id from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica))
   order by t.id for update;
  perform 1 from crm.inversionista_responsables r where r.inversionista_id in (p_perdedora, p_canonica) and r.hasta is null order by r.id for update;
  -- F2.b [D-18] (N6): también las tareas de CLIENTE de las dos personas (por su perfil), que hasta ahora quedaban
  -- vivas cuando la fusión heredaba el veto. Mismo criterio que D-3 y mismo orden (tareas → leads).
  v_perfiles_fusion := array(
    select x from (
      select v_p.perfil_id as x
      union select v_c.perfil_id
      -- Mismo criterio que D-3: el perfil cliente que lleva el documento exacto de la persona, aunque la identidad
      -- lo tenga en NULL (el backfill de F2 deja perfil_id NULL justo cuando otra identidad ya reclamó ese perfil,
      -- que es el caso típico de una fusión). Y el perfil del lead, que el FOR SHARE de arriba ya bloquea.
      union select p.id from public.perfiles p
             where p.rol = 'cliente'
               and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
               and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' ||
                    pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      union select l.perfil_id from crm.leads l where l.id = any(v_leads)
    ) s where s.x is not null order by 1);
  perform 1 from crm.tareas t
   where t.estado = 'pendiente'
     and (t.lead_id = any(v_leads) or (v_perfiles_fusion <> '{}' and t.perfil_id = any(v_perfiles_fusion)))
   order by t.id for update;
  perform private.bloquear_leads_nowait(v_leads);
  select * into v_lead from crm.leads l where l.id = any(v_leads) order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id in (p_perdedora, p_canonica) or r.lead_id = any(v_leads)
   order by r.lead_id for update;
  perform 1 from crm.multiempresa_idempotencia m
   where m.clave in ('auth_persona:' || p_perdedora::text, 'auth_persona:' || p_canonica::text) order by m.clave for update;
  -- 12. huella y bloqueos bajo los locks [E3-4]
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  if private.idem_hash(v_foto) <> p_hash then
    raise exception 'La previsualización caducó (la foto cambió): vuelve a previsualizar' using errcode = 'P0409';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  if pg_catalog.cardinality(v_bloq) > 0 then
    raise exception 'Fusión no viable: %', pg_catalog.array_to_string(v_bloq, ' · ') using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_p.no_contactar or v_c.no_contactar or coalesce(v_lead.no_contactar, false);

  -- 13. hechos bajo la válvula, en este orden
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = p_canonica, fusionado_en = v_ahora where id = p_perdedora;
  update crm.inversionistas set inversionista_canonico_id = p_canonica where inversionista_canonico_id = p_perdedora and id <> p_canonica;
  get diagnostics v_n_pred = row_count;
  if v_c.perfil_id is null and v_p.perfil_id is not null then
    update crm.inversionistas set perfil_id = v_p.perfil_id where id = p_canonica;
  end if;
  if v_veto and not v_c.no_contactar then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(v_p.no_contactar_en, v_ahora),
           no_contactar_por = coalesce(v_p.no_contactar_por, v_uid)
     where id = p_canonica;
  end if;
  select * into v_tramo_p from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tramo_c from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tramo_p.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo_p.id;
    if v_tramo_c.id is null then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
      values (p_canonica, v_tramo_p.responsable_id, v_ahora, 'fusion', v_uid);
      update crm.inversionistas set responsable_relacion_id = v_tramo_p.responsable_id where id = p_canonica;
    end if;
  end if;
  update crm.inversionista_identificadores d set estado = 'historico', vigente_hasta = v_ahora
   where d.inversionista_id = p_perdedora and d.estado = 'vigente';
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
  select p_canonica, d.tipo_documento, d.documento_normalizado, d.documento_original, 'vigente', d.verificado, 'fusion', v_ahora, v_uid
  from crm.inversionista_identificadores d
  where d.inversionista_id = p_perdedora and d.estado = 'historico' and d.vigente_hasta = v_ahora
  order by d.id;
  get diagnostics v_n_ident = row_count;
  -- lead (enlace vivo) y TODO el puente de P (incluidos históricos del backfill)
  if v_lead.id is not null and v_lead.inversionista_id = p_perdedora then
    update crm.leads set inversionista_id = p_canonica where id = v_lead.id;
  end if;
  update crm.inversionista_leads set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_puente = row_count;
  if v_lead.id is not null and v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(v_lead.id);
    update crm.leads set no_contactar = true where id = v_lead.id;
  end if;
  -- F2.b [D-18] (N6): la fusión que hereda el veto cancela TAMBIÉN las tareas de cliente de las dos personas; si no,
  -- la ficha del cliente seguía con seguimientos pendientes de alguien a quien no se debe contactar. Se marca como
  -- cancelación del sistema (misma marca que usa D-3) para que el trigger de tareas no la trate como cierre humano.
  if v_veto and v_perfiles_fusion <> '{}' then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t set estado = 'cancelada'
     where t.estado = 'pendiente' and t.perfil_id = any(v_perfiles_fusion);
    get diagnostics v_n_tareas_cliente = row_count;
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;
  update crm.cierres_externos ce set inversionista_id = p_canonica
   where ce.inversionista_id = p_perdedora
      or (v_lead.id is not null and v_lead.inversionista_id = p_perdedora and ce.lead_id = v_lead.id and ce.inversionista_id is null);
  get diagnostics v_n_cierres = row_count;
  update crm.inversiones set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_inv = row_count;
  for v_t in select * from crm.inversion_titulares where inversionista_id = p_perdedora order by id loop
    v_t2 := null;
    select * into v_t2 from crm.inversion_titulares where inversion_id = v_t.inversion_id and inversionista_id = p_canonica;
    if v_t2.id is not null then
      delete from crm.inversion_titulares where id = v_t.id;
      if v_t.rol = 'principal' and v_t2.rol <> 'principal' then
        update crm.inversion_titulares set rol = 'principal' where id = v_t2.id;
      end if;
      v_n_tit_dup := v_n_tit_dup + 1;
    else
      update crm.inversion_titulares set inversionista_id = p_canonica where id = v_t.id;
      v_n_tit := v_n_tit + 1;
    end if;
  end loop;
  update crm.conversion_reservas set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_res = row_count;
  v_impacto := pg_catalog.jsonb_build_object('lead_id', v_lead.id, 'lead_reapuntado', v_lead.id is not null and v_lead.inversionista_id = p_perdedora,
    'puente', v_n_puente, 'identificadores_reemitidos', v_n_ident, 'tramo_cerrado', v_tramo_p.id, 'tramo_heredado', v_tramo_c.id is null and v_tramo_p.id is not null,
    'perfil_heredado', v_c.perfil_id is null and v_p.perfil_id is not null, 'veto', v_veto, 'tareas_canceladas', v_n_tareas, 'tareas_cliente_canceladas', v_n_tareas_cliente,
    'cierres', v_n_cierres, 'inversiones', v_n_inv, 'titulares', v_n_tit, 'titulares_duplicados_eliminados', v_n_tit_dup,
    'reservas', v_n_res, 'predecesoras_aplanadas', v_n_pred, 'hash', p_hash);
  insert into crm.inversionista_fusiones (canonico_id, fusionado_id, motivo, impacto, por)
  values (p_canonica, p_perdedora, p_motivo, v_impacto, v_uid) returning id into v_fusion_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Fusión de identidades (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'fusion', 'fusion_id', v_fusion_id, 'canonico_id', p_canonica, 'fusionado_id', p_perdedora),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'fusion_id', v_fusion_id, 'canonico_id', p_canonica, 'fusionado_id', p_perdedora, 'impacto', v_impacto);
end;
$function$;

-- ── 10/34 · crm.reasignar_responsable_relacion_fn(uuid, uuid, text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.reasignar_responsable_relacion_fn(p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
  v_rol_nuevo text; v_leads uuid[] := array[]::uuid[]; v_leads_movidos integer := 0; v_perfil_movido boolean := false; v_tenencia text := 'sin_cambios';  -- F2.b [D-2]
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_inversionista is null or p_nuevo_responsable is null then
    raise exception 'Faltan la persona o el nuevo responsable' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  -- jerarquía compartida (el offboarding la toma exclusiva) + Gerencia y destinatario revalidados bajo ella -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación (membresía revalidada)' using errcode = '42501';
  end if;
  if not coalesce(private.rol_crm(p_nuevo_responsable) in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'El nuevo responsable debe ser un miembro activo del equipo comercial (rol efectivo)' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: reasigna en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- F2.b [D-2] (Codex #12): el motivo se revalida contra los documentos BAJO el lock de la persona (la validación de
  -- arriba corre antes del lock y una corrección documental concurrente pudo cambiarlos).
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  -- F2.b [D-2]: capacidad operativa del nuevo responsable. Si puede tener cartera (vendedor/supervisor activo, rol
  -- efectivo), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su documento, D-13)
  -- pasan a su cartera y el perfil cliente de la persona también. Orden: persona (ya) → tramo (ya) → tareas
  -- pendientes → leads → perfil, como el veto (b2) y la fusión (b5). Con Gerencia como nuevo responsable no hay
  -- cartera que mover: solo el tramo (tenencia = 'sin_cambios').
  v_rol_nuevo := private.rol_crm(p_nuevo_responsable);
  if v_rol_nuevo in ('vendedor', 'supervisor') then
    select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_leads
    from (select l.id from crm.leads l
           where l.id in (select x from private.leads_de_personas(array[p_inversionista]) x)
             and l.activo = true
             and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
             and (l.vendedor_id is distinct from p_nuevo_responsable or l.asignado_supervisor_id is not null)
           order by l.id) s;
    -- (Codex N1/N4) tampoco se espera por una TAREA ni por el PERFIL: cerrar_tarea tiene la tarea y va tarea → lead/perfil;
    -- el Portal actualiza el perfil y su trigger va perfil → tareas. Con la persona y el tramo en la mano, todo lo demás
    -- se toma SIN esperar → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads) or (v_inv.perfil_id is not null and t.perfil_id = v_inv.perfil_id))
       order by t.id
       for update nowait;
      if v_inv.perfil_id is not null then
        perform 1 from public.perfiles p where p.id = v_inv.perfil_id for no key update nowait;
      end if;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando una tarea o la ficha de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    -- (Codex #1) tareas → leads es el orden de b2/D-3 y de cerrar_tarea; derivar y repartir van lead → tareas (por el
    -- trigger de sincronización) bajo el mismo interlock compartido. Como la fusión (b5, E3-9): los leads se toman
    -- SIN esperar; si otra sesión tiene uno → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    v_tenencia := 'movida';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  -- F2.b [D-2]: la cartera sigue al responsable (los triggers de leads llevan el ledger de asignaciones, la actividad
  -- «reasignacion», tenencia_desde y las tareas pendientes; el del perfil mueve las tareas de cliente y deja su actividad).
  if v_tenencia = 'movida' then
    if coalesce(pg_catalog.array_length(v_leads, 1), 0) > 0 then
      -- (auditor M2) se REVALIDA bajo los locks: sigue vivo, en etapa abierta y sigue siendo de la persona (un descarte o una
      -- conversión concurrentes solo bloquean el lead; la puerta del DNI de D-13 puede llevarse un suelto a otra persona).
      update crm.leads l
         set vendedor_id = p_nuevo_responsable,
             asignado_supervisor_id = null
       where l.id = any(v_leads)
         and l.activo = true
         and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
         and l.id in (select x from private.leads_de_personas(array[p_inversionista]) x);
      get diagnostics v_leads_movidos = row_count;
    end if;
    if v_inv.perfil_id is not null then
      update public.perfiles p
         set asesor_perfil_id = p_nuevo_responsable,
             actualizado_en = pg_catalog.clock_timestamp()
       where p.id = v_inv.perfil_id and p.rol = 'cliente' and p.activo is true
         and p.asesor_perfil_id is distinct from p_nuevo_responsable;
      v_perfil_movido := found;
    end if;
    -- (auditor N5) «movida» solo si algo se movió de verdad.
    if v_leads_movidos = 0 and not v_perfil_movido then
      v_tenencia := 'sin_cambios';
    end if;
  end if;
  select * into v_lead from crm.leads where inversionista_id = p_inversionista and activo = true order by id limit 1;
  if v_lead.id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Responsable de relación reasignado (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'reasignacion_responsable', 'inversionista_id', p_inversionista,
                                          'anterior', v_tramo.responsable_id, 'nuevo', p_nuevo_responsable, 'tramo_id', v_nuevo_id),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'reasignado', 'inversionista_id', p_inversionista,
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable,
    'tenencia', pg_catalog.jsonb_build_object('estado', v_tenencia, 'leads_movidos', v_leads_movidos, 'perfil_movido', v_perfil_movido));  -- F2.b [D-2]
end;
$function$;

-- ── 11/34 · crm.registrar_reingreso_lead_fn(uuid, text, jsonb) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.registrar_reingreso_lead_fn(p_lead_id uuid, p_origen text, p_datos jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_datos jsonb;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) registra reingresos' using errcode = '42501';
  end if;
  -- Paridad apagada: superficie inerte mientras la identidad no esté activa (Codex E1).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el reingreso no se registra' using errcode = 'P0409';
  end if;
  if p_lead_id is null or not exists (select 1 from crm.leads l where l.id = p_lead_id) then
    raise exception 'Lead inexistente' using errcode = 'P0002';
  end if;
  if p_origen is null or pg_catalog.length(pg_catalog.btrim(p_origen)) not between 1 and 40 then
    raise exception 'Origen inválido' using errcode = '22023';
  end if;
  -- Sin documento en claro en la actividad: solo datos comerciales del formulario.
  v_datos := (
    select coalesce(pg_catalog.jsonb_object_agg(e.key, e.value), '{}'::jsonb)
    from pg_catalog.jsonb_each(coalesce(p_datos, '{}'::jsonb)) e
    where e.key in ('nombre','telefono','telefono_alternativo','correo','capital','moneda','canal','distrito','interes','nota','fila')
  );
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (
    p_lead_id, 'nota',
    'Reingreso por ' || pg_catalog.btrim(p_origen) || ': la persona volvió a dejar sus datos',
    pg_catalog.jsonb_build_object('evento', 'reingreso', 'origen', pg_catalog.btrim(p_origen), 'datos', v_datos),
    null)
  returning id into v_id;
  return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_id);
end;
$function$;

-- ── 12/34 · crm.reservar_conversion_lead(uuid, text, text, jsonb) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.reservar_conversion_lead(p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  v_tope     interval := interval '30 minutes';
  v_tipo     text := coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(p_tipo_documento)), ''), 'DNI');
  v_doc      text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g')), '');
  v_inv      uuid; v_veto boolean; v_otro uuid; v_perfil uuid; v_perfil_activo boolean;
  v_hash     text; v_hash_payload jsonb; v_saga jsonb; v_claim uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: usa la reserva por lead' using errcode = 'P0409';
  end if;
  if v_doc is null then
    raise exception 'El documento es obligatorio para reservar la conversión' using errcode = '22023';
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;

  -- documento -> identidad -> lead (ámbito, VERBATIM de la viva) -> revalidaciones de la persona.
  -- El ámbito va ANTES de cualquier lectura sobre la persona: un vendedor no puede sondear
  -- documentos ajenos con un lead que no es suyo (auditor b4 A1).
  perform private.identidad_bloquear_documento(v_tipo, v_doc);
  v_inv := private.inversionista_resolver(v_tipo, v_doc, true, 'reserva_conversion');
  select i.no_contactar, i.perfil_id into v_veto, v_perfil from crm.inversionistas i where i.id = v_inv for update;
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;


  -- El documento tecleado debe ser el de la persona de ESTE lead (misma regla que convertir_lead, adelantada a antes de Auth).
  if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv then
    raise exception 'El documento no es el de la persona de este lead' using errcode = 'P0409';
  end if;
  -- F2.b [D-10] (Codex #2): el PUENTE de ESTE lead también manda. Un lead que solo está en el puente (sin enlace vivo
  -- ni DNI) pertenece a la persona de su puente; con un documento que resuelve a otra persona no se reserva
  -- (la Gerencia lo corrige o fusiona), igual que ya exige crm.enlazar_lead_inversionista_fn (b5). Por la canónica.
  if exists (select 1 from crm.inversionista_leads il
              where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and v_lead.dni is not null and v_lead.dni <> v_doc then
    raise exception 'El documento no coincide con el del lead' using errcode = 'P0409';
  end if;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- un solo lead TOTAL (invariante #6): la persona no puede tener OTRO lead.
  select l.id into v_otro from crm.leads l where l.inversionista_id = v_inv and l.id <> p_lead_id limit 1;
  -- F2.b [D-10] (Codex B2): si no hay OTRO enlace vivo, «un solo lead» cuenta también el PUENTE (crm.inversionista_leads,
  -- históricos del backfill sin enlace vivo), como ya hacen las dos conversiones desde b5; el propio lead no cuenta.
  -- Espejo de b5 (auditor D-10 M1): el enlace vivo se comprueba PRIMERO (el detalle señala el lead canónico cuando existe)
  -- y un lead ya cerrado conserva las respuestas de hoy (enlazado / «ya esta cerrado», más abajo). Mismo error y mismo
  -- detalle que hoy (el front no cambia).
  if v_otro is null and v_lead.etapa not in ('convertido', 'descartado') then
    -- F2.b [D-13] (Codex #1): también los SUELTOS vivos con un documento vigente de la persona (private.leads_de_personas).
    select x into v_otro from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id order by x limit 1;
  end if;
  if v_otro is not null then
    raise exception 'Esta persona ya tiene su lead: la nueva inversión sobre un cliente existente no es una conversión'
      using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_otro)::text;
  end if;
  if v_perfil is null then
    -- Perfil cliente con ese documento creado antes de la identidad: se reutiliza (dedup de hoy, por identidad).
    select p.id into v_perfil from public.perfiles p
     where p.rol = 'cliente' and p.dni = v_doc and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
     limit 1;
  end if;
  if v_perfil is not null then
    select p.activo into v_perfil_activo from public.perfiles p where p.id = v_perfil;
    if v_perfil_activo is distinct from true then
      raise exception 'Ese cliente existe pero está inactivo en el portal' using errcode = 'P0409';
    end if;
  end if;

  -- Conversión ya consumada cuya respuesta se perdió (Codex E2 #4): la saga manda.
  if v_lead.etapa = 'convertido' and v_lead.perfil_id is not null and v_lead.inversionista_id = v_inv
     and exists (select 1 from crm.multiempresa_idempotencia i where i.clave = 'auth_persona:' || v_inv::text
                 and i.resultado->>'estado' <> 'enlazado' and i.resultado->>'tipo' = 'conversion'
                 and (i.resultado->>'lead_id')::uuid = p_lead_id
                 and coalesce((i.resultado->>'auth_user_id')::uuid, v_lead.perfil_id) = v_lead.perfil_id) then
    update crm.multiempresa_idempotencia
       set resultado = resultado || pg_catalog.jsonb_build_object('estado', 'enlazado', 'perfil_id', v_lead.perfil_id, 'actualizado_en', pg_catalog.now()),
           version = version + 1
     where clave = 'auth_persona:' || v_inv::text;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    if v_lead.etapa = 'convertido' and v_lead.perfil_id is not null then
      return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'estado', 'enlazado', 'reanudar', true,
        'inversionista_id', v_inv, 'perfil_id', v_lead.perfil_id, 'ya_existia', true);
    end if;
    raise exception 'El lead ya esta cerrado';
  end if;
  -- Reserva viva o sellada de OTRO lead de la misma persona (Avance en curso en otro lead).
  if exists (select 1 from crm.conversion_reservas r
              where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                and (r.efectos_iniciados_en is not null or r.expira_en > v_ahora)) then
    raise exception using errcode = 'P0409',
      message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
      hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
  end if;

  -- Una reserva viva o sellada de este lead pertenece a UNA persona: no se cambia de identidad
  -- sin compensar (Codex E2 #5).
  if exists (select 1 from crm.conversion_reservas r
              where r.lead_id = p_lead_id and r.inversionista_id is not null and r.inversionista_id <> v_inv
                and (r.efectos_iniciados_en is not null or r.expira_en > v_ahora)) then
    raise exception 'Este lead ya está reservado para otra persona; espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- Huella canónica SIN documento (Codex E2 #10).
  v_hash_payload := pg_catalog.jsonb_build_object('v', 1, 'inv', v_inv,
    'correo', pg_catalog.lower(coalesce(p_payload->>'correo','')), 'nombre', coalesce(p_payload->>'nombre_completo',''),
    'apellidos', coalesce(p_payload->>'apellidos',''), 'nombres', coalesce(p_payload->>'nombres',''),
    'telefono', coalesce(p_payload->>'telefono',''), 'domicilio', coalesce(p_payload->'domicilio', 'null'::jsonb),
    'bancarios', coalesce(p_payload->'bancarios', 'null'::jsonb));
  v_hash := private.idem_hash(v_hash_payload);

  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en, inversionista_id, hash_payload)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope, v_inv, v_hash)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         inversionista_id = v_inv,
         hash_payload  = v_hash,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;


  -- Persona YA cliente del portal (identidad enlazada o perfil con el documento exacto): sin Auth y
  -- sin saga; el edge convierte con convertir_lead_con_domicilio como hoy (auditor b4 A2).
  if v_perfil is not null then
    update crm.conversion_reservas r set claim_id = null where r.lead_id = p_lead_id;
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira,
      'inversionista_id', v_inv, 'perfil_id', v_perfil, 'ya_existia', true, 'estado', 'ya_existia', 'reanudar', false);
  end if;
  -- Claim de la saga (o reanudación con token / lease vencido).
  v_saga := private.saga_auth_reclamar(v_inv, 'conversion', v_hash_payload, p_lead_id, p_payload->>'token');
  v_claim := (v_saga->>'claim_id')::uuid;
  update crm.conversion_reservas r set claim_id = v_claim where r.lead_id = p_lead_id;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira,
    'inversionista_id', v_inv, 'perfil_id', (v_saga->>'perfil_id')::uuid, 'ya_existia', false)
    || (v_saga - 'inversionista_id' - 'perfil_id');
end;
$function$;

-- ── 13/34 · crm.saga_conversion_fn(text, jsonb) (texto vivo de producción) ─────────
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
$function$;

-- ── 14/34 · private.enlazar_lead_reabierto(uuid, uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.enlazar_lead_reabierto(p_lead_id uuid, p_inv uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_previo text;
begin
  if p_inv is null or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inv where id = p_lead_id and inversionista_id is null;
  update crm.inversionista_leads il set rol = 'canonico'
   where il.lead_id = p_lead_id and il.rol = 'historico'
     and not exists (select 1 from crm.inversionista_leads il2 where il2.inversionista_id = il.inversionista_id and il2.rol = 'canonico');
  perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
end;
$function$;

-- ── 15/34 · private.trg_leads_zz_enlaza_identidad() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_leads_zz_enlaza_identidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
  v_inv uuid;
  v_otro record;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.dni is not distinct from old.dni or v_priv then
      return new;
    end if;
    -- En UPDATE la fila del lead YA está bloqueada: aquí no se toma ningún lock de
    -- identidad (evitaría el orden documento->identidad->lead y podría abrazarse con
    -- marcar/levantar y la conversión). Se RECHAZA, no se enlaza: el documento de una
    -- persona enlazada, o un documento que resuelve a una persona reconocida, solo
    -- cambia por la corrección de Gerencia (bajo válvula, b5). Un DNI que no resuelve
    -- a nadie sigue editándose como hoy.
    if old.inversionista_id is not null
       or exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    -- F2.b [D-13] (Codex v3 B1, auditor v4 A1): con la identidad encendida, el DNI de un lead se FIJA por su puerta
    -- (crm.fijar_dni_lead_fn), que toma el candado del documento y a la persona ANTES de la fila (orden documento ->
    -- persona -> lead), juzga a la persona y enlaza si procede: por la puerta, el trigger deja pasar. El UPDATE directo
    -- (fila ya bloqueada, sin serialización posible con una reserva en vuelo) se rechaza: hacia una persona reconocida
    -- con el mensaje de siempre; hacia un documento sin dueño, «por su puerta».
    if coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off') = 'on' then
      return new;
    end if;
    if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
       and private.inversionista_por_documento('DNI', new.dni) is not null then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    raise exception 'Con la identidad unificada encendida, el DNI de un lead se fija por su puerta (fijar_dni_lead_fn) o lo corrige Gerencia'
      using errcode = 'P0409';
  elsif v_priv and new.inversionista_id is not null then
    -- Una RPC bajo válvula que ya trae el enlace (p. ej. una fusión futura) manda.
    return new;
  end if;

  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- El advisory documental ya lo tomó el trigger 000 en esta misma sentencia.
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  -- F2.b [D-13]: enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas; el enlace vivo primero en
  -- el detalle) y persona EN CONVERSIÓN (reserva por persona viva o sellada de otro lead). Serializado con la reserva por el
  -- candado documental que ya tomó el trigger 000 (inv_resolver:DNI:<doc>, la misma clave que toma la reserva; b1).
  select x as id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from private.leads_de_personas(array[v_inv]) x
  join crm.inversionistas i on i.id = v_inv
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  where x is distinct from new.id
  order by (exists (select 1 from crm.leads l where l.id = x and l.inversionista_id = v_inv)) desc, x
  limit 1;
  if found then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente', 'asesor', v_otro.asesor, 'via', 'identidad', 'lead_id', v_otro.id)::text;
  end if;
  if private.persona_en_conversion(v_inv, new.id)
     or exists (select 1 from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null) then   -- ya cliente (Codex v3 M2)
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente',
              'asesor', coalesce((select p.nombre_completo
                                    from crm.conversion_reservas r
                                    join public.perfiles p on p.id = r.reservado_por
                                    left join crm.leads lr on lr.id = r.lead_id
                                   where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                                     and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
                                   order by r.reservado_en desc limit 1), 'sin asesor asignado'),
              'via', 'identidad',
              'lead_id', (select r.lead_id from crm.conversion_reservas r
                           left join crm.leads lr on lr.id = r.lead_id
                           where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                             and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
                           order by r.reservado_en desc limit 1))::text;
  end if;
  new.inversionista_id := v_inv;
  return new;
end;
$function$;

-- ── 16/34 · private.trg_leads_zz_puente_identidad() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_leads_zz_puente_identidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- «UPDATE OF columna» mira la lista SET de la sentencia, no el valor: un BEFORE
  -- que fija inversionista_id no lo dispararía. Por eso AFTER INSERT OR UPDATE
  -- con comparación de valor.
  if tg_op = 'UPDATE' and new.inversionista_id is not distinct from old.inversionista_id then
    return null;
  end if;
  if new.inversionista_id is null then
    return null;
  end if;
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return null;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
    -- Reapuntes de puente (fusión) los gestiona su propia puerta bajo válvula.
    if v_priv then
      return null;
    end if;
    if exists (select 1 from crm.inversionista_leads il
               where il.lead_id = new.id and il.inversionista_id <> new.inversionista_id) then
      raise exception 'El puente persona<->lead no coincide con el enlace del lead' using errcode = 'P0409';
    end if;
    return null;
  end if;
  if exists (select 1 from crm.inversionista_leads il
             where il.inversionista_id = new.inversionista_id and il.rol = 'canonico' and il.lead_id <> new.id) then
    raise exception 'La persona ya tiene un lead canónico' using errcode = 'P0409';
  end if;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
  values (new.inversionista_id, new.id, 'canonico');
  return null;
end;
$function$;

-- ── 17/34 · private.trg_perfiles_documento_protegido() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_perfiles_documento_protegido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(old.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_new text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_told text := coalesce(nullif(pg_catalog.btrim(old.tipo_documento), ''), 'DNI');
  v_tnew text := coalesce(nullif(pg_catalog.btrim(new.tipo_documento), ''), 'DNI');
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  -- La corrección de Gerencia (crm.corregir_documento_inversionista_fn, b5) fija AMBAS marcas alrededor de sus hechos
  -- (válvula + GUC propia, como el candado de leads) [auditor N2]. SECURITY DEFINER porque los roles del Portal no leen crm.* [N1].
  if coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     and coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false) then
    return new;
  end if;
  if v_old = v_new and v_told = v_tnew then
    return new;   -- mismo documento con otro formato: no es un cambio
  end if;
  -- [Codex B-1] por OLD.id: un UPDATE que envía id+dni no puede esquivar el candado (proteger_campos_inmutables restaura el id DESPUÉS).
  if exists (select 1 from crm.inversionistas i where i.perfil_id = old.id and i.estado <> 'fusionado') then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige desde el CRM (corrección de documento de Gerencia)'
      using errcode = 'P0409';
  end if;
  return new;
end;
$function$;

-- ── 18/34 · public.crear_contrato(jsonb, jsonb) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(current_setting('crm.producto_condicion_id', true), '') is not null;
  v_cliente_id uuid;
  v_numero text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria text := p_contrato->>'categoria';
  v_moneda text := upper(coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'));
  v_capital numeric;
  v_anio integer := extract(year from now() at time zone 'America/Lima')::integer;
  v_contrato_id uuid;
  v_fecha_operacion date;
  v_periodo date;
  v_cuota jsonb;
  v_asesor_id uuid;
  v_asesor_rol text;
  v_operacion_id uuid;
  v_origen_id uuid;
  v_origen public.contratos%rowtype;
  v_capital_renovado numeric;
  v_capital_adicional numeric;
  v_primer_periodo date;
  v_upgrade_elegible boolean;
  v_analista_cierre uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
    v_capital := (p_contrato->>'capital')::numeric;
  exception when invalid_text_representation then
    raise exception 'Cliente o capital inválido' using errcode = '22023';
  end;

  -- Vincula autorización y escritura a la misma versión de la cartera. Una
  -- reasignación concurrente espera este lock; si ganó antes, aquí ya se lee el
  -- nuevo Analista y el anterior queda fuera del gate.
  -- F2.b (E4) [D-1, OK de Miguel 05/09]: con la identidad unificada ENCENDIDA, crear un contrato RECONOCE
  -- a la persona ANTES del FOR SHARE de abajo (jerarquía -> documento -> identidad -> perfil, reentrante).
  -- Solo si el cliente existe activo (así un id inexistente sigue muriendo en el 42501 de siempre).
  -- Sin documento válido o con documento de otra persona reconocida -> P0409 (contrato §4.3, fail-closed).
  -- [auditor A1] la AUTORIDAD se pregunta antes de reconocer: un no autorizado sigue muriendo en el 42501 uniforme
  -- de abajo (sin aprender nada del documento), con ON igual que con OFF.
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and (select private.puede_registrar_ventas())
     and exists (select 1 from public.perfiles p where p.id = v_cliente_id and p.rol = 'cliente' and p.activo) then
    perform private.asegurar_identidad_perfil(v_cliente_id, 'contrato');
  end if;
  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente' and p.activo
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (Nuevo, Renovación o Upgrade)';
  end if;
  if v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;

  -- EL ANALISTA QUE CIERRA (decision 2 del plan P-055). Es de quien VENDIO, no
  -- de quien tecleo: `creado_por` se conserva aparte y no se pisa.
  begin
    v_analista_cierre := nullif(btrim(coalesce(p_contrato->>'analista_cierre_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'El analista que cierra no es valido' using errcode = '22023';
  end;

  if v_analista_cierre is not null then
    -- Elegido a mano: tiene que poder tener ventas. SOLO ACTIVOS (decision de
    -- Miguel, 29/08): una venta NUEVA es de alguien que esta trabajando; la
    -- venta vieja de alguien que se fue entra por la reasignacion de gerencia
    -- (que si acepta inactivos, con motivo y rastro). Y los roles OFF-ROSTER
    -- (coordinador, directorio) no son organigrama comercial por diseno.
    if not exists (
      select 1 from crm.equipo e where e.perfil_id = v_analista_cierre
        and e.activo
        and e.rol_crm in ('vendedor','supervisor','gerencia')
    ) then
      raise exception 'El analista que cierra tiene que estar activo en el equipo comercial'
        using errcode = '22023';
    end if;
  else
    -- No vino. «Si no corresponde a nadie, lo pone a su nombre» (decision 2):
    -- eso solo tiene sentido si quien registra PUEDE tener ventas. Si no puede
    -- -una administrativa, por ejemplo-, tiene que elegir a quien corresponde.
    if not exists (select 1 from crm.equipo e where e.perfil_id = v_uid and e.activo) then
      raise exception 'Elige el analista de la venta'
        using errcode = '22023',
              hint = 'Quien registra no forma parte del equipo comercial, asi que la venta no puede quedar a su nombre.';
    end if;
    v_analista_cierre := v_uid;
  end if;

  -- Las operaciones de cartera necesitan un dueño congelado. No se atribuye a
  -- quien digitó: se atribuye al Analista de perfiles.asesor_perfil_id.
  if v_categoria in ('renovacion', 'upgrade') then
    select e.rol_crm into v_asesor_rol
    from crm.equipo e
    where e.perfil_id = v_asesor_id and e.activo
    for share;
    if v_asesor_id is null
       or not found
       or v_asesor_rol not in ('vendedor', 'supervisor') then
      raise exception using
        errcode = '22023',
        message = 'Asigna un Analista activo al cliente antes de registrar la operación';
    end if;
  end if;

  if v_categoria = 'renovacion' then
    begin
      v_origen_id := (p_contrato->>'contrato_origen_id')::uuid;
      v_capital_renovado := (p_contrato->>'capital_renovado')::numeric;
      v_capital_adicional := coalesce((p_contrato->>'capital_adicional')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Completa contrato anterior, capital renovado y adicional válidos'
        using errcode = '22023';
    end;

    select * into v_origen
    from public.contratos c
    where c.id = v_origen_id
    for update;
    if not found then
      raise exception 'El contrato a renovar no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from v_cliente_id then
      raise exception 'El contrato anterior pertenece a otro cliente' using errcode = '22023';
    end if;
    if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
      raise exception 'El contrato anterior ya fue cerrado o renovado' using errcode = 'P0409';
    end if;
    if v_origen.fecha_vencimiento > (now() at time zone 'America/Lima')::date then
      raise exception 'La renovación solo se registra cuando el contrato llega a su fecha fin'
        using errcode = '22023';
    end if;
    if v_origen.moneda is distinct from v_moneda then
      raise exception 'La renovación debe conservar la moneda del contrato anterior'
        using errcode = '22023';
    end if;
    if (p_contrato->>'fecha_inicio')::date < v_origen.fecha_vencimiento then
      raise exception 'El contrato nuevo no puede iniciar antes del vencimiento anterior'
        using errcode = '22023';
    end if;
    if v_capital_renovado <= 0 or v_capital_renovado > v_origen.capital then
      raise exception 'El capital renovado debe ser mayor a cero y no superar el contrato anterior'
        using errcode = '22023';
    end if;
    if v_capital_adicional < 0 then
      raise exception 'El capital adicional no puede ser negativo' using errcode = '22023';
    end if;
    if v_capital is distinct from (v_capital_renovado + v_capital_adicional) then
      raise exception 'El nuevo capital debe ser capital renovado + capital adicional'
        using errcode = '22023';
    end if;
  end if;

  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por, analista_cierre_id
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid, v_analista_cierre
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;

  if p_cronograma is null or jsonb_typeof(p_cronograma) <> 'array'
     or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacío';
  end if;
  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, estado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric, 'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;
  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(v_contrato_id, p_contrato->'titulares');
  end if;

  if v_categoria in ('renovacion', 'upgrade') then
    v_periodo := date_trunc('month', v_fecha_operacion)::date;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.operaciones_cartera'),
      pg_catalog.hashtext(v_cliente_id::text || '|' || v_periodo::text)
    );

    if v_categoria = 'upgrade' then
      select min(date_trunc('month', c.fecha_cierre_comercial)::date)
        into v_primer_periodo
      from public.contratos c
      where c.cliente_id = v_cliente_id;
      v_upgrade_elegible := v_periodo > v_primer_periodo;
    else
      v_upgrade_elegible := true;
    end if;

    insert into crm.operaciones_cartera (
      cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
      fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
      elegible_conversion, desglose_completo, fuente, creado_por
    ) values (
      v_cliente_id, v_asesor_id, v_categoria, v_origen_id, v_contrato_id,
      v_fecha_operacion, v_periodo, v_moneda,
      case when v_categoria = 'renovacion' then v_capital_renovado end,
      case when v_categoria = 'renovacion' then v_capital_adicional end,
      v_upgrade_elegible, true, 'flujo_cartera', v_uid
    ) returning id into v_operacion_id;
  end if;

  if v_categoria = 'renovacion' then
    update public.cronograma_pagos
       set estado = 'trasladado'
     where contrato_id = v_origen_id and estado in ('pendiente', 'vencido');
    update public.contratos
       set estado = 'renovado', renovado_a_id = v_contrato_id,
           cerrado_en = now(), cerrado_por = v_uid
     where id = v_origen_id;
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero,
    'operacion_id', v_operacion_id,
    'conversion_elegible', case
      when v_categoria in ('renovacion', 'upgrade') then v_upgrade_elegible
    end
  );
end;
$function$;

-- ── 19/34 · private.bloquear_personas_de_leads(uuid[], text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.bloquear_personas_de_leads(p_leads uuid[], p_dni_extra text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_personas uuid[]; v_claves text[]; v_k text;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Codex v4.3 [2]: la comprobación «sigue dentro de lo bloqueado» relee tras esperar y eso solo vale en READ COMMITTED
  -- (en REPEATABLE READ el snapshot viejo esconde a una persona confirmada por otra transacción).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  select pg_catalog.array_agg(distinct p order by p) into v_personas
  from (select private.lead_persona_reabrir(l.id) as p from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[]))
        union select private.inversionista_por_documento('DNI', p_dni_extra) where p_dni_extra is not null) s
  where p is not null;
  select pg_catalog.array_agg(distinct k order by k) into v_claves
  from (select 'DNI:' || l.dni as k from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[])) and l.dni is not null
        union select 'DNI:' || p_dni_extra where p_dni_extra is not null
        union select d.tipo_documento || ':' || d.documento_normalizado
                from crm.inversionista_identificadores d
               where d.inversionista_id = any(coalesce(v_personas, '{}'::uuid[])) and d.estado = 'vigente') s;
  if v_claves is not null then
    foreach v_k in array v_claves loop
      perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
    end loop;
  end if;
  if v_personas is not null then
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share;
  end if;
  -- Codex v4.3 [1]: identidad_bloquear_documento es un no-op si la bandera está APAGADA; si alguien la apagó entre la primera
  -- lectura y los candados, no hay candados reales → no se declara nada bloqueado (el llamador da veredicto fresco / 40001).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Devuelve lo que REALMENTE bloqueó (Codex v4.2, ABA): el llamador, tras tomar la fila, exige que el documento actual
  -- del lead esté entre las claves bloqueadas y su persona entre las bloqueadas; si no, veredicto fresco / 40001.
  return pg_catalog.jsonb_build_object('personas', pg_catalog.to_jsonb(coalesce(v_personas, '{}'::uuid[])),
                                       'claves', pg_catalog.to_jsonb(coalesce(v_claves, '{}'::text[])));
end;
$function$;

-- ── 20/34 · private.identidad_bloquear_documento(text, text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.identidad_bloquear_documento(p_tipo text, p_documento text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_norm text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento,''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return;
  end if;
  if v_norm = '' or p_tipo is null then
    return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('inv_resolver:' || p_tipo || ':' || v_norm));
end;
$function$;

-- ── 21/34 · private.identidad_bloquear_persona(text, text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.identidad_bloquear_persona(p_tipo text, p_documento text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_inv uuid;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return;
  end if;
  v_inv := private.inversionista_por_documento(p_tipo, p_documento);
  if v_inv is null then
    return;
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
end;
$function$;

-- ── 22/34 · private.trg_leads_disponibilidad_atomica() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_leads_disponibilidad_atomica()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_disponibilidad jsonb;
  v_cambio_identidad boolean;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_descartado_por text;
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'UPDATE' then
    if new.telefono is distinct from old.telefono then
      new.telefono := private.normalizar_telefono(new.telefono);
      if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'Telefono invalido';
      end if;
    end if;

    if new.dni is distinct from old.dni then
      new.dni := nullif(pg_catalog.btrim(new.dni), '');
      if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'DNI invalido';
      end if;
    end if;

    v_cambio_identidad := new.telefono is distinct from old.telefono
      or new.dni is distinct from old.dni;

    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );

    -- F2.b (b5) [E3-6]: la corrección de documento de Gerencia (RPC definer bajo válvula Y con su
    -- GUC propia crm.correccion_documento) cambia SOLO el DNI de un lead que conserva su persona; los terceros (otra identidad,
    -- otro cliente del Portal, otro lead vivo) ya los comprobó la RPC bajo sus locks. Ningún
    -- otro escritor bajo válvula cambia el DNI; fuera de esta forma exacta nada cambia.
    if v_priv and coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false)
       and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
       and new.dni is distinct from old.dni and new.telefono is not distinct from old.telefono
       and new.no_contactar = old.no_contactar and new.etapa = old.etapa and new.activo = old.activo
       and new.motivo_descarte is not distinct from old.motivo_descarte
       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;

    v_rol := private.rol_crm(v_actor);
    if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
      raise exception using errcode = '42501', message = 'Acceso CRM revocado';
    end if;

    -- Excluir OLD al validar el destino es correcto para un lead operativo,
    -- pero no debe permitir «mover» un No contactar o un enfriamiento y dejar
    -- libre la identidad anterior. Ambos vetos propios congelan teléfono y DNI
    -- mientras sigan vigentes; levantarlos es una operación separada y auditable.
    if old.no_contactar = true then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = pg_catalog.jsonb_build_object('estado', 'no_contactar')::text;
    end if;

    if old.etapa = 'descartado'
       and old.descartado_en is not null
       and old.motivo_descarte is not null then
      select
        ep.dias,
        old.descartado_en + pg_catalog.make_interval(days => ep.dias),
        p.nombre_completo
      into v_dias, v_disponible_desde, v_descartado_por
      from crm.enfriamiento_politica ep
      left join public.perfiles p on p.id = old.descartado_por
      where ep.motivo = old.motivo_descarte;

      if coalesce(v_dias, 0) > 0
         and v_disponible_desde > pg_catalog.now() then
        raise exception using
          errcode = 'P0481',
          message = 'Contacto no disponible',
          detail = pg_catalog.jsonb_build_object(
            'estado', 'enfriamiento',
            'motivo_descarte', old.motivo_descarte,
            'disponible_desde', v_disponible_desde,
            'descartado_por', v_descartado_por
          )::text;
      end if;
    end if;

    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    return new;
  end if;

  new.telefono := private.normalizar_telefono(new.telefono);
  new.dni := nullif(pg_catalog.btrim(new.dni), '');

  if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'Telefono invalido';
  end if;
  if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'DNI invalido';
  end if;

  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);

  -- Un escritor interno sin sesion humana se serializa, pero conserva su
  -- contrato especializado (por ejemplo crm-importar-leads con service_role).
  if v_actor is null then
    return new;
  end if;

  v_rol := private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La compatibilidad temporal es solo para el alta que ya hacía el bundle
  -- anterior. No abre una vía para fabricar leads terminales o inactivos.
  if new.activo is distinct from true
     or new.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead debe nacer activo y en etapa operativa';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$function$;

-- ── 23/34 · private.trg_leads_hereda_veto_persona() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_leads_hereda_veto_persona()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_inv uuid;
  v_veto boolean;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (contrato §18). Se
  -- normaliza igual que el resolver (este trigger corre ANTES del btrim de 00).
  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    return new;
  end if;
  -- Orden total: documento -> identidad -> (contactos los toma 00 después).
  perform private.identidad_bloquear_documento('DNI', new.dni);
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    return new;
  end if;
  -- Serializa contra marcar/levantar_no_contactar (identidad FOR UPDATE) y relee.
  select i.no_contactar into v_veto
  from crm.inversionistas i
  where i.id = v_inv
  for update;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se abre una oportunidad nueva'
      using errcode = 'P0429',
            detail = pg_catalog.jsonb_build_object('estado', 'no_contactar', 'via', 'identidad')::text;
  end if;
  return new;
end;
$function$;

-- ── 24/34 · private.trg_leads_no_contactar_solo_puerta() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_leads_no_contactar_solo_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;  -- bandera apagada: comportamiento de hoy
  end if;
  if new.no_contactar is distinct from old.no_contactar
     and coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') <> 'on' then
    raise exception 'No contactar se cambia solo por su puerta (marcar_no_contactar / levantar_no_contactar)'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

-- ── 25/34 · private.trg_leads_zz_reapertura_solo_rpc() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_leads_zz_reapertura_solo_rpc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if v_priv or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  if ((old.etapa = 'descartado' and new.etapa is distinct from 'descartado') or (old.activo = false and new.activo = true))
     and coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, un descarte se reabre solo por sus puertas (tomar, rescatar o deshacer): juzgan a la persona y enlazan el lead'
      using errcode = 'P0409';
  end if;
  return new;
end;
$function$;

-- ── 26/34 · private.trg_tareas_veto_persona_perfil() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.trg_tareas_veto_persona_perfil()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_personas uuid[];
begin
  -- F2.b [D-3] (v3/v4, Codex #5/#10/N1): la tarea de PERFIL (cliente) respeta el veto de la PERSONA (contrato §7.3) igual
  -- que la de lead, en un trigger propio de crm.tareas (el trigger de gestión compartido con actividades sigue byte a byte).
  -- Corre ANTES que el resto (00_0): toma a las personas del perfil FOR SHARE —persona → perfil, el orden de reasignar—
  -- SIN ESPERAR: si alguien las tiene (veto, fusión, reasignación, baja) → 40001 y se reintenta (nunca se espera con una
  -- tarea en la mano: cerrar_tarea agenda la siguiente con la tarea bloqueada y marcar espera esa tarea con la persona
  -- bloqueada). Después revalida que lo bloqueado siga siendo lo actual (una fusión pudo mover el perfil de persona).
  -- Writers internos (auth.uid NULL) y la válvula quedan fuera, como en leads.
  if (select auth.uid()) is null
     or new.lead_id is not null or new.perfil_id is null
     or coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  v_personas := array(select x from private.personas_de_perfil(new.perfil_id) x order by 1);
  begin
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share nowait;
  exception when lock_not_available then
    raise exception 'La persona del cliente está siendo actualizada (veto, fusión o reasignación); vuelve a intentarlo'
      using errcode = '40001';
  end;
  if array(select x from private.personas_de_perfil(new.perfil_id) x order by 1) is distinct from v_personas then
    raise exception 'La persona del cliente cambió mientras se agendaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if private.persona_vetada_perfil(new.perfil_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  return new;
end;
$function$;

-- ── 27/34 · crm.auth_usuario_por_correo_fn(text) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.auth_usuario_por_correo_fn(p_correo text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    then pg_catalog.jsonb_build_object('id', null, 'apagada', true)
    else coalesce((
    select pg_catalog.jsonb_build_object('id', u.id, 'claim_id', u.raw_app_meta_data->>'claim_id',
                                         'tiene_perfil', exists (select 1 from public.perfiles p where p.id = u.id))
    from auth.users u
    where pg_catalog.lower(u.email) = pg_catalog.lower(pg_catalog.btrim(p_correo))
    limit 1), pg_catalog.jsonb_build_object('id', null)) end
$function$;

-- ── 28/34 · crm.cliente_eliminable_fn(uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.cliente_eliminable_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n integer;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el servicio consulta si un cliente es eliminable' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.inversionistas i where i.perfil_id = p_perfil_id and i.estado <> 'fusionado') then
    return pg_catalog.jsonb_build_object('eliminable', false, 'motivo', 'identidad',
      'mensaje', 'Este cliente está reconocido como persona (identidad unificada): desactívalo en vez de eliminarlo');
  end if;
  select count(*) into v_n from public.contratos c where c.cliente_id = p_perfil_id;
  if v_n > 0 then
    return pg_catalog.jsonb_build_object('eliminable', false, 'motivo', 'contratos', 'contratos', v_n,
      'mensaje', 'Este cliente tiene contratos: desactívalo en vez de eliminarlo');
  end if;
  return pg_catalog.jsonb_build_object('eliminable', true);
end;
$function$;

-- ── 29/34 · crm.fusion_previsualizar_fn(uuid, uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.fusion_previsualizar_fn(p_perdedora uuid, p_canonica uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_lead crm.leads%rowtype;
  v_bloq text[]; v_adv text[] := '{}'; v_foto jsonb;
  v_tp crm.inversionista_responsables%rowtype; v_tc crm.inversionista_responsables%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia previsualiza una fusión' using errcode = '42501';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  select * into v_p from crm.inversionistas where id = p_perdedora;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if v_p.id is null or v_c.id is null or p_perdedora = p_canonica then
    return pg_catalog.jsonb_build_object('viable', false, 'bloqueos', pg_catalog.to_jsonb(v_bloq),
      'advertencias', '[]'::jsonb, 'hash', null, 'foto', null, 'impacto', null);
  end if;
  if exists (select 1 from crm.inversionista_identificadores a
             join crm.inversionista_identificadores b on b.tipo_documento = a.tipo_documento and b.documento_normalizado <> a.documento_normalizado
             where a.inversionista_id = p_perdedora and b.inversionista_id = p_canonica and a.estado = 'vigente' and b.estado = 'vigente') then
    v_adv := pg_catalog.array_append(v_adv, 'Las dos tienen un documento vigente del mismo tipo: una está mal; corrige el documento después de fusionar (indicando cuál sale)'::text);
  end if;
  if v_p.no_contactar <> v_c.no_contactar
     or exists (select 1 from crm.leads l where l.id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) and l.no_contactar <> (v_p.no_contactar or v_c.no_contactar)) then
    v_adv := pg_catalog.array_append(v_adv, 'Vetos distintos: el resultado es «No contactar» en la persona y el lead, y se cancelan las tareas pendientes del lead'::text);
  end if;
  select * into v_tp from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tc from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tp.responsable_id is not null and v_tc.responsable_id is not null and v_tp.responsable_id <> v_tc.responsable_id then
    v_adv := pg_catalog.array_append(v_adv, 'Responsables de relación distintos: gana el de la canónica; se cierra el tramo de la perdedora'::text);
  elsif v_tp.responsable_id is not null and v_tc.responsable_id is null then
    v_adv := pg_catalog.array_append(v_adv, 'La canónica hereda el responsable de relación de la perdedora'::text);
  end if;
  if exists (select 1 from crm.inversiones where inversionista_id = p_perdedora)
     or exists (select 1 from crm.inversion_titulares where inversionista_id = p_perdedora)
     or exists (select 1 from crm.cierres_externos where inversionista_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora tiene inversiones, titularidades o cierres: se reapuntan a la canónica; el dinero y sus fotos no se tocan'::text);
  end if;
  if exists (select 1 from crm.inversionistas where inversionista_canonico_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora es canónica de otras identidades fusionadas: se aplanan a la nueva canónica'::text);
  end if;
  select * into v_lead from crm.leads where id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) order by id limit 1;
  if v_lead.id is not null and not v_lead.activo then
    v_adv := pg_catalog.array_append(v_adv, 'El lead está inactivo: no se deja nota de actividad (el libro de fusiones es el rastro)'::text);
  end if;
  v_adv := pg_catalog.array_append(v_adv, 'La conversión mensual sigue siendo por lead/cliente hasta Contrato-F3: la fusión no altera cifras ni meses sellados'::text);
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  return pg_catalog.jsonb_build_object(
    'viable', pg_catalog.cardinality(v_bloq) = 0,
    'bloqueos', pg_catalog.to_jsonb(v_bloq),
    'advertencias', pg_catalog.to_jsonb(v_adv),
    'hash', private.idem_hash(v_foto),
    'foto', v_foto,
    'impacto', pg_catalog.jsonb_build_object(
      'leads', (select count(*) from private.leads_de_identidades(array[p_perdedora])),
      'puente', (select count(*) from crm.inversionista_leads where inversionista_id = p_perdedora),
      'tareas_pendientes', (select count(*) from crm.tareas t where t.estado = 'pendiente' and t.lead_id in (select private.leads_de_identidades(array[p_perdedora, p_canonica]))),
      'identificadores', (select count(*) from crm.inversionista_identificadores where inversionista_id = p_perdedora and estado = 'vigente'),
      'tramos', (select count(*) from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null),
      'cierres', (select count(*) from crm.cierres_externos where inversionista_id = p_perdedora),
      'inversiones', (select count(*) from crm.inversiones where inversionista_id = p_perdedora),
      'titulares', (select count(*) from crm.inversion_titulares where inversionista_id = p_perdedora),
      'reservas', (select count(*) from crm.conversion_reservas where inversionista_id = p_perdedora),
      'predecesoras', (select count(*) from crm.inversionistas where inversionista_canonico_id = p_perdedora)));
end;
$function$;

-- ── 30/34 · crm.impacto_desactivacion_usuario_fn(uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION crm.impacto_desactivacion_usuario_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_subordinados integer;
  v_leads integer;
  v_bandeja integer;
  v_tareas integer;
  v_clientes integer;
  v_personas integer := 0;  -- F2.b [D-2]
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);  -- F2.b [D-2]
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede evaluar una baja CRM';
  end if;
  if not exists (select 1 from crm.equipo e where e.perfil_id = p_perfil_id) then
    raise exception 'Membresia CRM no encontrada';
  end if;

  select count(*)::integer into v_subordinados
  from crm.equipo e
  where e.supervisor_id = p_perfil_id and e.activo is true;

  select count(*)::integer into v_leads
  from crm.leads l
  where l.vendedor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_bandeja
  from crm.leads l
  where l.asignado_supervisor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_tareas
  from crm.tareas t
  where (t.vendedor_id = p_perfil_id
      or t.asignado_supervisor_id = p_perfil_id)
    and t.activo is true and t.estado = 'pendiente';

  select count(*)::integer into v_clientes
  from public.perfiles p
  where p.rol = 'cliente' and p.activo is true
    and p.asesor_perfil_id = p_perfil_id;

  -- F2.b [D-2]: con la identidad ENCENDIDA, las PERSONAS cuyo responsable de relación es el saliente (identidades
  -- activas con tramo abierto suyo o apuntándole) también exigen reemplazo: nadie se queda sin responsable. Con la
  -- bandera apagada la respuesta es byte a byte la de hoy (el front la valida con un esquema ESTRICTO: la clave
  -- personas_a_cargo solo aparece con ON, y el front la incorpora en el bloque 4, antes del encendido).
  if v_flag then
    select count(*)::integer into v_personas
    from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id));
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'subordinados_activos', v_subordinados,
      'leads_abiertos', v_leads,
      'leads_en_bandeja', v_bandeja,
      'tareas_pendientes', v_tareas,
      'clientes_activos', v_clientes,
      'personas_a_cargo', v_personas,
      'requiere_reemplazo',
        v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes + v_personas > 0
    );
  end if;
  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id,
    'subordinados_activos', v_subordinados,
    'leads_abiertos', v_leads,
    'leads_en_bandeja', v_bandeja,
    'tareas_pendientes', v_tareas,
    'clientes_activos', v_clientes,
    'requiere_reemplazo',
      v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes > 0
  );
end;
$function$;

-- ── 31/34 · private.leads_por_repartir_implementacion() (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.leads_por_repartir_implementacion()
 RETURNS TABLE(id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamp with time zone, clasificacion_auto text, comentario text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := (select auth.uid());
        v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver la cola de leads por repartir'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en,
         l.clasificacion_auto,
         -- Comentario REDACTADO (correo/celular/documento fuera) y acotado a
         -- 400 caracteres: Rosa necesita leer la pregunta, no los datos de
         -- contacto. Mantiene la premisa "sin PII de contacto" de C1.
         nullif(left(private.redactar_pii(l.nota), 400), '')
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
  where l.activo = true
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                     -- cola global (sin dueño)
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false                               -- Ley 29571: nunca listar 'No Insista'
    and (not v_flag or coalesce(inv.no_contactar, false) = false) -- el veto es de la PERSONA (contrato §7.3)
    and not private.persona_vetada(l.id)                     -- F2.b (b2): también por documento exacto (lead suelto)
  order by l.creado_en asc;                                  -- FIFO justo
end;
$function$;

-- ── 32/34 · private.leads_vetados_persona(uuid[]) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.leads_vetados_persona(p_lead_ids uuid[])
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select l.id
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)
  where l.id = any (coalesce(p_lead_ids, array[]::uuid[]))
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    and (
      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      -- F2.b [D-3]: un lead que está en el PUENTE de una persona vetada (histórico sin enlace vivo) también lo está.
      or exists (select 1
                 from crm.inversionista_leads il
                 join crm.inversionistas p0 on p0.id = il.inversionista_id
                 join crm.inversionistas p  on p.id  = coalesce(p0.inversionista_canonico_id, p0.id)
                 where il.lead_id = l.id and p.no_contactar = true)
      or (l.inversionista_id is null
          and nullif(pg_catalog.btrim(coalesce(l.dni,'')), '') is not null
          and exists (
            select 1
            from crm.inversionista_identificadores idf
            join crm.inversionistas i on i.id = idf.inversionista_id
            where idf.tipo_documento = 'DNI'
              and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(l.dni, '[^A-Za-z0-9]', '', 'g'))
              and idf.estado = 'vigente'
              and idf.verificado = true
              and i.estado <> 'fusionado'
              and i.no_contactar = true))
    )
$function$;

-- ── 33/34 · private.persona_vetada_perfil(uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.persona_vetada_perfil(p_perfil_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- F2.b [D-3]: el veto de la PERSONA visto desde un perfil cliente (tareas de cliente, actividades_cliente): por el
  -- enlace perfil↔identidad (canónica) o por el documento exacto del perfil (identificador vigente y verificado).
  -- Con la bandera apagada es siempre false (paridad con hoy).
  select coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and (
       exists (select 1
               from crm.inversionistas i0
               join crm.inversionistas i on i.id = coalesce(i0.inversionista_canonico_id, i0.id)
               where i0.perfil_id = p_perfil_id and i0.estado <> 'fusionado' and i.no_contactar = true)
       or exists (select 1
                  from public.perfiles p
                  join crm.inversionista_identificadores idf
                    on idf.tipo_documento = coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI')
                   and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
                   and idf.estado = 'vigente' and idf.verificado = true
                  join crm.inversionistas i on i.id = idf.inversionista_id
                  where p.id = p_perfil_id
                    and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
                    and i.estado <> 'fusionado' and i.no_contactar = true)
     )
$function$;

-- ── 34/34 · private.verificar_disponibilidad_lead_impl(text, text, uuid) (texto vivo de producción) ─────────
CREATE OR REPLACE FUNCTION private.verificar_disponibilidad_lead_impl(p_telefono text, p_dni text, p_excluir_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  -- documento normalizado IGUAL que el resolver (documento_normalizado es mayúsculas+alfanumérico)
  v_dni_norm text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_dni,''), '[^A-Za-z0-9]', '', 'g')), '');
  v_asesor_identidad text;
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  if exists (
    select 1
    from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where l.id is distinct from p_excluir_lead_id
      and (l.no_contactar = true or (v_flag and coalesce(inv.no_contactar, false)))
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  )
  -- El veto es de la PERSONA (contrato §7.3): también si el documento EXACTO
  -- pertenece a una identidad vetada, aunque no tenga lead con ese teléfono.
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (el trigger de alta lo
  -- exige; contrato §18: CE/pasaporte se resuelven al convertir).
  or (v_flag and v_dni_norm is not null and exists (
    select 1
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and i.no_contactar = true
  )) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
  into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  -- Un solo lead TOTAL por persona (contrato #6, meta #3): si el DOCUMENTO exacto
  -- ya pertenece a una identidad que TIENE lead (Avance o cooperativa — aunque no
  -- tenga perfil de portal), esa persona ya es cliente / ya tiene su lead: no se
  -- crea otro. Solo el documento vincula (contrato #8). Gateado por bandera.
  if v_flag and v_dni_norm is not null then
    -- F2.b [D-13]: «los leads de una persona» = enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas;
    -- incluye históricos y soft-borrados enlazados, como ya contaba el join sin filtro de activo); una persona EN CONVERSIÓN
    -- (reserva por persona viva o sellada de OTRO lead) o que YA ES CLIENTE (perfil enlazado, activo o no) tampoco recibe
    -- otro lead. `asesor` = responsable de relación, o quien reservó (reserva vigente), o el centinela. Contrato del front intacto.
    select coalesce(resp.nombre_completo, res.nombre_completo, 'sin asesor asignado')
      into v_asesor_identidad
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    left join public.perfiles resp on resp.id = i.responsable_relacion_id
    left join lateral (
      select p.nombre_completo
      from crm.conversion_reservas r
      join public.perfiles p on p.id = r.reservado_por
      left join crm.leads lr on lr.id = r.lead_id
      where r.inversionista_id = i.id and r.lead_id is distinct from p_excluir_lead_id
        and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
      order by r.reservado_en desc
      limit 1
    ) res on true
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and (exists (select 1 from private.leads_de_personas(array[i.id]) x where x is distinct from p_excluir_lead_id)
           or private.persona_en_conversion(i.id, p_excluir_lead_id)
           or i.perfil_id is not null)
    limit 1;
    if found then
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', v_asesor_identidad, 'via', 'identidad');
    end if;
  end if;

  select
    l.id,
    l.tenencia_desde,
    l.vendedor_id,
    l.asignado_supervisor_id,
    coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
  into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde,
      -- La última CONVERSACIÓN real: «¿el cliente RESPONDIÓ?» — espejo de
      -- TIPOS_CONVERSACION (tipos.ts) y del WHEN de
      -- trg_zz_actividades_avance_etapa. Los intentos (llamada_no_contestada,
      -- whatsapp_enviado) NO cuentan: decisión dura de Miguel, 2026-08-16.
      -- NULL si jamás hubo conversación — la tarjeta no pinta la línea.
      'ultima_conversacion_en', (
        select pg_catalog.max(a.creado_en)
        from crm.actividades a
        where a.lead_id = v_lead.id
          and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
      )
    );
  end if;

  select
    l.id,
    l.activo,
    l.motivo_descarte,
    l.descartado_en,
    pd.nombre_completo as descartado_por_nombre
  into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.id is distinct from p_excluir_lead_id
    and l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias
    into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;

    -- ── F2: el descarte VENCIDO se parte (spec §5.6) ─────────────────────────
    -- Un enfriamiento vencido ya NO cae al 'libre' genérico: el contacto es
    -- REUTILIZABLE y su puerta es crm.tomar_lead_libre (el alta lo bloquea
    -- desde F1 — crear duplicaría). Dos excepciones deliberadas del plan:
    --   · activo=false jamás es reutilizable: un soft-borrado no se revive
    --     por esta puerta — cae a 'libre' y el alta crea de cero.
    --   · motivos con 0 días (pide_credito, datos_invalidos): CARENCIA de
    --     24 h SOLO para tomar (Miguel 2026-08-16 — protege el «Deshacer
    --     descarte 24h» del coordinador). Durante la ventana el veredicto
    --     sigue 'libre': el alta manual conserva su comportamiento de hoy.
    if v_lead.activo = true then
      if v_dias = 0
         and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
        return pg_catalog.jsonb_build_object('estado', 'libre');
      end if;
      v_quedo_libre_en := case
        when v_dias > 0 then v_disponible_desde
        else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
      end;
      return pg_catalog.jsonb_build_object(
        'estado', 'reutilizable',
        'motivo_descarte', v_lead.motivo_descarte,
        'descartado_en', v_lead.descartado_en,
        'quedo_libre_en', v_quedo_libre_en,
        'descartado_por', v_lead.descartado_por_nombre,
        'ultima_conversacion_en', (
          select pg_catalog.max(a.creado_en)
          from crm.actividades a
          where a.lead_id = v_lead.id
            and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
        )
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$function$;

do $dep$
declare v_dep text;
begin
  select string_agg(distinct d.classid::regclass::text || ' ' || d.objid::text, ', ')
    into v_dep
    from pg_depend d
   where d.refobjid = to_regprocedure('private.resolver_en_puertas_bajo_candado()') and d.deptype in ('n','a') and d.classid <> 'pg_proc'::regclass;
  if v_dep is not null then
    raise exception 'REVERSA D-19: algo depende de private.resolver_en_puertas_bajo_candado() (%): resuélvelo antes de soltarla', v_dep;
  end if;
end
$dep$;
drop function if exists private.resolver_en_puertas_bajo_candado();

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.actualizar_cliente_gerencia(uuid, jsonb)'::regprocedure
                  and md5(p.prosrc) = 'a984566930994023eb527d777ff5829b'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.actualizar_cliente_gerencia(uuid, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.alta_cliente_identidad_fn(text, jsonb)'::regprocedure
                  and md5(p.prosrc) = 'da08974050e65ecf2d76032d489db48e'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'REVERSA D-19: crm.alta_cliente_identidad_fn(text, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.convertir_lead(uuid, uuid)'::regprocedure
                  and md5(p.prosrc) = 'a31d2c2a4938afa56febe2a4bd25a1c9'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.convertir_lead(uuid, uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid)'::regprocedure
                  and md5(p.prosrc) = '05379200b541878371954cf1c4d6dcb6'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb)'::regprocedure
                  and md5(p.prosrc) = '7f2b4976640553a50ab27cf25b30fb36'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.eliminar_cliente_fn(uuid)'::regprocedure
                  and md5(p.prosrc) = '63077333fcfe0100eb2ce1c4e980c06f'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'REVERSA D-19: crm.eliminar_cliente_fn(uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.enlazar_lead_inversionista_fn(uuid, uuid, text)'::regprocedure
                  and md5(p.prosrc) = '3766ae3484f839218f94dccdde5bb04b'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.enlazar_lead_inversionista_fn(uuid, uuid, text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid)'::regprocedure
                  and md5(p.prosrc) = '07b8acd42d6b2eadb18353e0a8d8aaa5'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamp with time zone, uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fusionar_inversionistas_fn(uuid, uuid, text, text)'::regprocedure
                  and md5(p.prosrc) = '87e25279ed5c3bc8b3418be573499f41'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.fusionar_inversionistas_fn(uuid, uuid, text, text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reasignar_responsable_relacion_fn(uuid, uuid, text)'::regprocedure
                  and md5(p.prosrc) = '00e579a03a0faa6a72dfa56f6c3a639c'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.reasignar_responsable_relacion_fn(uuid, uuid, text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.registrar_reingreso_lead_fn(uuid, text, jsonb)'::regprocedure
                  and md5(p.prosrc) = 'b8b041176c5883dd9e39d14cef65b146'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'REVERSA D-19: crm.registrar_reingreso_lead_fn(uuid, text, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid, text, text, jsonb)'::regprocedure
                  and md5(p.prosrc) = '9307f1687b37a32230a08e4377b1b787'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.reservar_conversion_lead(uuid, text, text, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.saga_conversion_fn(text, jsonb)'::regprocedure
                  and md5(p.prosrc) = 'd2bdbe3d830afb4884065395e5c64a80'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.saga_conversion_fn(text, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.enlazar_lead_reabierto(uuid, uuid)'::regprocedure
                  and md5(p.prosrc) = '95d16ba245f33d8e278265d3e19243bd'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.enlazar_lead_reabierto(uuid, uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_zz_enlaza_identidad()'::regprocedure
                  and md5(p.prosrc) = '31a10fdc8c86bb3ff2af60e3415750fa'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_leads_zz_enlaza_identidad() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_zz_puente_identidad()'::regprocedure
                  and md5(p.prosrc) = '7a64d7b6e92f87a1ffdeb1728faf4d25'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_leads_zz_puente_identidad() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_perfiles_documento_protegido()'::regprocedure
                  and md5(p.prosrc) = '8c1c718ed2bcae0b9999a2173ff00612'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_perfiles_documento_protegido() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.crear_contrato(jsonb, jsonb)'::regprocedure
                  and md5(p.prosrc) = '061c40e345312ca5e515ddd5ee282e5c'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'REVERSA D-19: public.crear_contrato(jsonb, jsonb) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.bloquear_personas_de_leads(uuid[], text)'::regprocedure
                  and md5(p.prosrc) = '0a00e15b47907d3c79b59920ddd86911'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.bloquear_personas_de_leads(uuid[], text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.identidad_bloquear_documento(text, text)'::regprocedure
                  and md5(p.prosrc) = 'ad3a36cf8237bef81bef5e7632177e1a'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.identidad_bloquear_documento(text, text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.identidad_bloquear_persona(text, text)'::regprocedure
                  and md5(p.prosrc) = 'ecc1fd3672e2466ccd9494e9530bf299'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.identidad_bloquear_persona(text, text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_disponibilidad_atomica()'::regprocedure
                  and md5(p.prosrc) = '0fc38c3b3b63b4004d45891e9ff92b19'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_leads_disponibilidad_atomica() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_hereda_veto_persona()'::regprocedure
                  and md5(p.prosrc) = '927858289e431b0d6dc2a5f42c68e061'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path="",lock_timeout=5s'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_leads_hereda_veto_persona() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_no_contactar_solo_puerta()'::regprocedure
                  and md5(p.prosrc) = '595dfbd9c1d06b42638c18cc979a3c23'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_leads_no_contactar_solo_puerta() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_leads_zz_reapertura_solo_rpc()'::regprocedure
                  and md5(p.prosrc) = '5af423f5a32ff7978b51216bf1a31dc7'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_leads_zz_reapertura_solo_rpc() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_tareas_veto_persona_perfil()'::regprocedure
                  and md5(p.prosrc) = '3826f7b7d9f19fa63b5f2515168c56cf'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.trg_tareas_veto_persona_perfil() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.auth_usuario_por_correo_fn(text)'::regprocedure
                  and md5(p.prosrc) = '4fde369f6e9ef37859871410be6338a5'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'REVERSA D-19: crm.auth_usuario_por_correo_fn(text) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.cliente_eliminable_fn(uuid)'::regprocedure
                  and md5(p.prosrc) = '4f2afd8bddbf354ec956027d9b3aeb18'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE,service_role:EXECUTE') then
    raise exception 'REVERSA D-19: crm.cliente_eliminable_fn(uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fusion_previsualizar_fn(uuid, uuid)'::regprocedure
                  and md5(p.prosrc) = '27eedf7b16b4d680bc6c7483901630cb'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.fusion_previsualizar_fn(uuid, uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.impacto_desactivacion_usuario_fn(uuid)'::regprocedure
                  and md5(p.prosrc) = '787c48c1a8e80a307fb1285b42f82180'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'authenticated:EXECUTE,postgres:EXECUTE') then
    raise exception 'REVERSA D-19: crm.impacto_desactivacion_usuario_fn(uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.leads_por_repartir_implementacion()'::regprocedure
                  and md5(p.prosrc) = '0b67ca88bb17b8ac8059d415721504e7'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.leads_por_repartir_implementacion() no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.leads_vetados_persona(uuid[])'::regprocedure
                  and md5(p.prosrc) = '7f441c688f608017bdb4d398772a2aeb'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.leads_vetados_persona(uuid[]) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.persona_vetada_perfil(uuid)'::regprocedure
                  and md5(p.prosrc) = '597d76a6aa5f6ca75f0ffb86bd20497e'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.persona_vetada_perfil(uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.verificar_disponibilidad_lead_impl(text, text, uuid)'::regprocedure
                  and md5(p.prosrc) = '3ea1fbae8b35c0f8d2702270dd5c6b8d'
                  and p.prosecdef = true and p.proowner = 'postgres'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = 'postgres:EXECUTE') then
    raise exception 'REVERSA D-19: private.verificar_disponibilidad_lead_impl(text, text, uuid) no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if to_regprocedure('private.resolver_en_puertas_bajo_candado()') is not null then
    raise exception 'REVERSA D-19: private.resolver_en_puertas_bajo_candado() sigue viva';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906200000';
  raise notice 'REVERSA F2.b D-19 OK (versión 20260906200000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
