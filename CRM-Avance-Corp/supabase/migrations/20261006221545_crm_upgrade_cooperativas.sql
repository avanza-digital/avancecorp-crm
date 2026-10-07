-- Upgrade cooperativo: dinero adicional, separado de la reinversión.
-- La inversión original y las reglas económicas existentes no se reescriben.
begin;
set local lock_timeout='5s';
do $preflight$
begin
  if md5(pg_get_functiondef('crm.preparar_reinversion_fn(uuid,uuid,jsonb)'::regprocedure)) <> 'db317253d25bc9115d28bfb388be02a7'
    or md5(pg_get_functiondef('private.postventa_reinversion_guard()'::regprocedure)) <> '67cd2a68660ff4e71767464497c00f02'
    or md5(pg_get_functiondef('private.inversion_solicitud_resultado(uuid,jsonb)'::regprocedure)) <> '9763d1c08124caafc84709c8d7dabfe2' then
    raise exception 'Cambió el contrato de continuidad; revisar antes de aplicar';
  end if;
  if (select md5(pg_get_constraintdef(oid)) from pg_constraint where conrelid='crm.inversionista_gestiones'::regclass and conname='inversionista_gestiones_tipo_check') is distinct from '7a46260f2382a381a50f905b6ce7793b' then
    raise exception 'Cambió el catálogo del historial; revisar antes de aplicar';
  end if;
end $preflight$;

-- La carrera anulación/confirmación puede fallar antes del trigger, al tomar
-- el candado NOWAIT del lead. Traducir también 55P03 al conflicto HTTP 409 de
-- continuidad. La guarda existente conserva el error original de F4 ordinaria.
do $conflicto$
declare d text;
begin
  select pg_get_functiondef('crm.confirmar_inversion_revisada_fn(uuid,integer)'::regprocedure) into d;
  if md5(d)<>'aee09ba800853174532b700774ca048a' then
    raise exception 'Cambió la confirmación financiera; revisar antes de aplicar';
  end if;
  execute replace(d,'exception when serialization_failure then',
    'exception when serialization_failure or lock_not_available then');
end $conflicto$;

alter table crm.inversion_solicitud_origenes add column tipo text not null default 'reinversion'
  constraint inversion_solicitud_origenes_tipo_check check (tipo in ('reinversion','upgrade'));
comment on column crm.inversion_solicitud_origenes.tipo is
  'Operación de continuidad inmutable. Upgrade = aporte adicional a una inversión vigente. Los vínculos anteriores siguen siendo reinversión.';

alter table crm.inversionista_gestiones drop constraint inversionista_gestiones_tipo_check;
alter table crm.inversionista_gestiones add constraint inversionista_gestiones_tipo_check check
  (tipo in ('agenda','cierre','reprogramacion','confirmacion','veto','levantar_veto','responsable','fusion',
    'retiro','reinversion','correccion_contacto','correccion_coopac','upgrade'));

create function private.continuidad_coopac_fuente(p_fuente uuid,p_persona uuid,p_empresa text,p_tipo text)
returns void language plpgsql set search_path='' as $function$
begin
  -- Valida titular canónico y empresa con el mismo candado de fuente de F6.
  perform private.postventa_fuente(p_fuente,p_persona,p_empresa);
  if p_tipo='upgrade' and not exists (
    select 1 from private.cartera_f5_fuentes_reales() f
    where f.fuente_id=p_fuente and f.empresa=p_empresa and not f.es_demo
      and f.estado in ('activo','vigente')
  ) then
    raise exception 'El upgrade requiere una inversión vigente de esta empresa' using errcode='P0409';
  end if;
end $function$;

CREATE OR REPLACE FUNCTION private.preparar_continuidad_coopac(p_clave uuid, p_fuente uuid, p_datos jsonb, p_tipo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_ctx jsonb; v_r jsonb; v_origen uuid; v_existia boolean; v_estado text; v_tipo text;
begin
  -- INVOKER privado: solo las dos puertas DEFINER lo ejecutan con su autoridad.
  -- F3 → F4 → F5/F6 → jerarquía/documentos/persona → clave → fuente.
  if not private.inversiones_escritura_bajo_candado() or not private.postventa_modo() then
    raise exception 'La continuidad de inversiones todavía no está habilitada' using errcode='P0409'; end if;
  if p_tipo is null or p_tipo not in ('reinversion','upgrade') or (p_tipo='upgrade' and p_datos ? 'lead_id')
    or p_clave is null or p_fuente is null or p_datos is null or jsonb_typeof(p_datos)<>'object'
    or p_datos->>'inversionista_id' is null or p_datos->>'empresa' is null
    or p_datos->>'empresa' not in ('qorilazo','prodelco') then
    raise exception 'Datos de continuidad inválidos' using errcode='22023'; end if;
  v_ctx:=private.inversion_persona_autorizada((p_datos->>'inversionista_id')::uuid);
  perform pg_advisory_xact_lock(hashtextextended('f4_solicitud:'||p_clave::text,0));
  select estado into v_estado from crm.inversion_solicitudes where id=p_clave for update;
  v_existia:=found;
  if v_existia then
    select fuente_id,tipo into v_origen,v_tipo from crm.inversion_solicitud_origenes where solicitud_id=p_clave;
    if v_origen is distinct from p_fuente or v_tipo is distinct from p_tipo then
      raise exception 'La clave ya tiene otro origen, tipo de operación o corresponde a una inversión ordinaria' using errcode='P0409'; end if;
    if v_estado<>'confirmada' then
      perform private.continuidad_coopac_fuente(p_fuente,(v_ctx->>'inversionista_id')::uuid,p_datos->>'empresa',p_tipo);
    end if;
    -- F4 conserva su resultado incluso si el origen se anuló después de confirmar.
    return crm.preparar_inversion_fn(p_clave,p_datos)||jsonb_build_object(case when p_tipo='upgrade' then 'upgrade_origen_id' else 'reinversion_origen_id' end,p_fuente);
  end if;
  perform private.continuidad_coopac_fuente(p_fuente,(v_ctx->>'inversionista_id')::uuid,p_datos->>'empresa',p_tipo);
  v_r:=crm.preparar_inversion_fn(p_clave,p_datos);
  insert into crm.inversion_solicitud_origenes(solicitud_id,fuente_id,creado_por,tipo)
    values(p_clave,p_fuente,auth.uid(),p_tipo);
  return v_r||jsonb_build_object(case when p_tipo='upgrade' then 'upgrade_origen_id' else 'reinversion_origen_id' end,p_fuente)
    ||case when p_tipo='upgrade' then jsonb_build_object('upgrade_origen_referencia',
      (select coalesce(c.referencia_externa,c.numero_transaccion) from crm.cierres_externos c where c.id=p_fuente)) else '{}'::jsonb end;
end;

exception when serialization_failure or lock_not_available then
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;
create or replace function crm.preparar_reinversion_fn(p_clave uuid,p_fuente uuid,p_datos jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $function$
begin
  return private.preparar_continuidad_coopac(p_clave,p_fuente,p_datos,'reinversion');
end $function$;

create or replace function crm.preparar_upgrade_fn(p_clave uuid,p_fuente uuid,p_datos jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $function$
begin
  return private.preparar_continuidad_coopac(p_clave,p_fuente,p_datos,'upgrade');
end $function$;

CREATE OR REPLACE FUNCTION private.postventa_reinversion_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_fuente uuid; v_persona uuid; v_tipo text;
begin
  select fuente_id,tipo into v_fuente,v_tipo from crm.inversion_solicitud_origenes where solicitud_id=new.id;
  if not found then return new; end if;
  if old.estado='confirmada' then return new; end if;
  if new.inversionista_id is distinct from old.inversionista_id or new.empresa_id is distinct from old.empresa_id then
    raise exception 'La persona y empresa de origen son inmutables' using errcode='P0409'; end if;
  -- Cancelar una pendiente no cambia identidad/empresa y no requiere origen vigente.
  if v_tipo='upgrade' and old.estado='preparada' and new.estado='cancelada' then return new; end if;
  if not private.postventa_modo() then
    raise exception 'La continuidad de inversiones todavía no está habilitada' using errcode='P0409'; end if;
  v_persona:=private.inversionista_canonica(new.inversionista_id);
  perform private.continuidad_coopac_fuente(v_fuente,v_persona,new.datos->>'empresa',v_tipo);
  if new.estado='confirmada' then
    insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(new.inversionista_id,new.datos->>'empresa',v_tipo,case when v_tipo='upgrade' then 'Upgrade confirmado · aporte adicional' else 'Reinversión confirmada' end,
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
    'reinversion_origen_id',(select o.fuente_id from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id and o.tipo='reinversion'))
    ||case when exists(select 1 from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id and o.tipo='upgrade')
      then jsonb_build_object('upgrade_origen_id',(select o.fuente_id from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id and o.tipo='upgrade'),
        'upgrade_origen_referencia',(select coalesce(c.referencia_externa,c.numero_transaccion) from crm.inversion_solicitud_origenes o
          join crm.cierres_externos c on c.id=o.fuente_id where o.solicitud_id=s.id and o.tipo='upgrade')) else '{}'::jsonb end
    ||case when s.puerta='cliente_existente' then jsonb_build_object('puerta',s.puerta,'analista_cierre_id',s.analista_cierre_id) else '{}'::jsonb end
  from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id where s.id=p_id;
$function$;

revoke all on function private.continuidad_coopac_fuente(uuid,uuid,text,text),
  private.preparar_continuidad_coopac(uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function crm.preparar_upgrade_fn(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function crm.preparar_upgrade_fn(uuid,uuid,jsonb) to authenticated;
comment on function private.continuidad_coopac_fuente(uuid,uuid,text,text) is
  'Valida titular, empresa y candado de la fuente; upgrade exige inversión real vigente. Solo para núcleos y puertas autorizados.';
comment on function private.preparar_continuidad_coopac(uuid,uuid,jsonb,text) is
  'Núcleo INVOKER privado de continuidad cooperativa. Lo ejecutan las puertas DEFINER autenticadas de upgrade y reinversión; conserva origen y tipo en reintentos.';
comment on function crm.preparar_upgrade_fn(uuid,uuid,jsonb) is
  'Puerta autenticada para preparar un aporte adicional vinculado a una inversión cooperativa vigente; delega permisos e idempotencia al núcleo privado.';
notify pgrst,'reload schema';
commit;
