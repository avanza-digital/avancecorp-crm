-- Solo antes de registrar el primer upgrade. Con upgrades reales, revertir
-- únicamente el frontend: conservar este esquema y la clasificación histórica.
begin;
set local lock_timeout='5s';
lock table crm.inversion_solicitud_origenes,crm.inversionista_gestiones in access exclusive mode;
do $$ begin
  if exists(select 1 from crm.inversion_solicitud_origenes where tipo='upgrade')
    or exists(select 1 from crm.inversionista_gestiones where tipo='upgrade') then
    raise exception 'Hay upgrades registrados: conservar el backend y revertir solo el frontend';
  end if;
end $$;
CREATE OR REPLACE FUNCTION crm.preparar_reinversion_fn(p_clave uuid, p_fuente uuid, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_ctx jsonb; v_r jsonb; v_origen uuid; v_existia boolean; v_estado text;
begin
  -- F3 → F4 → F5/F6 → jerarquía/documentos/persona → clave → fuente.
  if not private.inversiones_escritura_bajo_candado() or not private.postventa_modo() then
    raise exception 'La reinversión todavía no está habilitada' using errcode='P0409'; end if;
  if p_clave is null or p_fuente is null or p_datos is null or jsonb_typeof(p_datos)<>'object'
    or p_datos->>'inversionista_id' is null or p_datos->>'empresa' is null
    or p_datos->>'empresa' not in ('qorilazo','prodelco') then
    raise exception 'Datos de reinversión inválidos' using errcode='22023'; end if;
  v_ctx:=private.inversion_persona_autorizada((p_datos->>'inversionista_id')::uuid);
  perform pg_advisory_xact_lock(hashtextextended('f4_solicitud:'||p_clave::text,0));
  select estado into v_estado from crm.inversion_solicitudes where id=p_clave for update;
  v_existia:=found;
  if v_existia then
    select fuente_id into v_origen from crm.inversion_solicitud_origenes where solicitud_id=p_clave;
    if v_origen is distinct from p_fuente then
      raise exception 'La clave ya tiene otro origen o corresponde a una inversión ordinaria' using errcode='P0409'; end if;
    if v_estado<>'confirmada' then
      perform private.postventa_fuente(p_fuente,(v_ctx->>'inversionista_id')::uuid,p_datos->>'empresa');
    end if;
    -- F4 conserva su resultado incluso si el origen se anuló después de confirmar.
    return crm.preparar_inversion_fn(p_clave,p_datos)||jsonb_build_object('reinversion_origen_id',p_fuente);
  end if;
  perform private.postventa_fuente(p_fuente,(v_ctx->>'inversionista_id')::uuid,p_datos->>'empresa');
  v_r:=crm.preparar_inversion_fn(p_clave,p_datos);
  insert into crm.inversion_solicitud_origenes(solicitud_id,fuente_id,creado_por)
    values(p_clave,p_fuente,auth.uid());
  return v_r||jsonb_build_object('reinversion_origen_id',p_fuente);
end;

exception when serialization_failure then
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;
CREATE OR REPLACE FUNCTION private.postventa_reinversion_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_fuente uuid; v_persona uuid;
begin
  select fuente_id into v_fuente from crm.inversion_solicitud_origenes where solicitud_id=new.id;
  if not found then return new; end if;
  if old.estado='confirmada' then return new; end if;
  if not private.postventa_modo() then
    raise exception 'La reinversión todavía no está habilitada' using errcode='P0409'; end if;
  v_persona:=private.inversionista_canonica(new.inversionista_id);
  if new.inversionista_id is distinct from old.inversionista_id or new.empresa_id is distinct from old.empresa_id then
    raise exception 'La persona y empresa de origen son inmutables' using errcode='P0409'; end if;
  perform private.postventa_fuente(v_fuente,v_persona,new.datos->>'empresa');
  if new.estado='confirmada' then
    insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(new.inversionista_id,new.datos->>'empresa','reinversion','Reinversión confirmada',
      jsonb_build_object('solicitud_id',new.id,'origen_id',v_fuente,'inversion_id',new.inversion_id),auth.uid());
  end if;
  return new;
end;

exception when serialization_failure then
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
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
drop function crm.preparar_upgrade_fn(uuid,uuid,jsonb);
drop function private.preparar_continuidad_coopac(uuid,uuid,jsonb,text);
drop function private.continuidad_coopac_fuente(uuid,uuid,text,text);
alter table crm.inversion_solicitud_origenes drop column tipo;
alter table crm.inversionista_gestiones drop constraint inversionista_gestiones_tipo_check;
alter table crm.inversionista_gestiones add constraint inversionista_gestiones_tipo_check CHECK ((tipo = ANY (ARRAY['agenda'::text, 'cierre'::text, 'reprogramacion'::text, 'confirmacion'::text, 'veto'::text, 'levantar_veto'::text, 'responsable'::text, 'fusion'::text, 'retiro'::text, 'reinversion'::text, 'correccion_contacto'::text, 'correccion_coopac'::text])));
notify pgrst,'reload schema';
commit;
