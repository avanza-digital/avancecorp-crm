-- Gestión desde la identidad neutral. Candidata: aplicar solo tras el ensayo
-- y la autorización del SQL concreto. No modifica objetos del esquema public.
begin;

alter table crm.inversionista_gestiones drop constraint inversionista_gestiones_tipo_check;
alter table crm.inversionista_gestiones add constraint inversionista_gestiones_tipo_check
  check(tipo in ('agenda','cierre','reprogramacion','confirmacion','veto','levantar_veto',
    'responsable','fusion','retiro','reinversion','correccion_contacto','correccion_coopac'));

create table crm.inversionista_datos_contacto (
  inversionista_id uuid primary key references crm.inversionistas(id),
  nombre_completo text not null check (length(btrim(nombre_completo)) between 2 and 200),
  telefono text check (telefono is null or length(telefono) between 6 and 32),
  domicilio text check (domicilio is null or length(domicilio) <= 500),
  revision integer not null default 1 check (revision > 0),
  actualizado_en timestamptz not null default clock_timestamp(),
  actualizado_por uuid not null references public.perfiles(id)
);
alter table crm.inversionista_datos_contacto owner to postgres;
alter table crm.inversionista_datos_contacto enable row level security;
revoke all on crm.inversionista_datos_contacto from public,anon,authenticated,service_role;
create trigger trg_audit_inversionista_datos_contacto after insert or update or delete
  on crm.inversionista_datos_contacto for each row execute function private.log_audit_crm();

-- Una fusión conserva los datos actuales de sus identidades, sin duplicarlos.
create function private.gestion_contacto(p_persona uuid) returns crm.inversionista_datos_contacto
language sql stable security definer set search_path='' as $$
  select d from crm.inversionista_datos_contacto d
  where private.inversionista_canonica(d.inversionista_id)=p_persona
  order by d.actualizado_en desc,d.inversionista_id limit 1;
$$;
alter function private.gestion_contacto(uuid) owner to postgres;
revoke all on function private.gestion_contacto(uuid) from public,anon,authenticated;

-- Se añade la fuente de contacto al lector canónico, conservando sus filtros,
-- prioridades y la redacción de Directorio. No se duplica la ficha financiera.
do $lector$
declare v_def text; v_original text;
begin
  if (select md5(prosrc) from pg_proc where oid='private.cartera_f5_personas_visibles(uuid)'::regprocedure)
    is distinct from 'd559ddbbfae0474d9eed7d26aedc6d90' then
    raise exception 'El lector canónico cambió; revisar el SQL antes de aplicarlo';
  end if;
  select pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure) into v_original;
  if position('coalesce(nullif(btrim(p.nombre_completo),''''),nullif(btrim(l.nombre_completo),'''')' in v_original)=0
    or position('coalesce(p.telefono,case when not i.lector then l.telefono end)' in v_original)=0
    or position('from autorizadas i' in v_original)=0 then
    raise exception 'El lector de personas cambió; revisar la migración de gestión';
  end if;
  v_def:=replace(v_original,
    'coalesce(nullif(btrim(p.nombre_completo),''''),nullif(btrim(l.nombre_completo),'''')',
    'coalesce(nullif(btrim(p.nombre_completo),''''),case when not i.lector then nullif(btrim(datos.nombre_completo),'''') end,nullif(btrim(l.nombre_completo),'''')');
  v_def:=replace(v_def,'coalesce(p.telefono,case when not i.lector then l.telefono end)',
    'coalesce(p.telefono,case when not i.lector then case when p.id is null and datos.inversionista_id is not null then datos.telefono else l.telefono end end)');
  v_def:=replace(v_def,'todas_fuentes as materialized (',
    'contactos as materialized (
      select distinct on (x.canonica) x.canonica,d0.*
      from crm.inversionista_datos_contacto d0 join identidades x on x.id=d0.inversionista_id
      order by x.canonica,d0.actualizado_en desc,d0.inversionista_id
    ), todas_fuentes as materialized (');
  v_def:=replace(v_def,'from autorizadas i',
    'from autorizadas i left join contactos datos on datos.canonica=i.id and not i.lector');
  if v_def=v_original or position('contactos as materialized (' in v_def)=0 then
    raise exception 'No se pudo incorporar el contacto al lector canónico'; end if;
  execute v_def;
end;
$lector$;

-- Los leads convertidos pueden estar archivados. La corrección económica de
-- El flujo neutral registra la gestión por persona en lugar de seguimiento
-- sobre un lead inactivo. La llamada directa conserva su comportamiento.
do $cierre$
declare v_def text; v_nueva text;
begin
  if (select md5(prosrc) from pg_proc where oid='crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)'::regprocedure)
    is distinct from '1cd53d7eda89b09c9367a66fc4d27692' then
    raise exception 'El escritor de cierres cambió; revisar el SQL antes de aplicarlo';
  end if;
  select pg_get_functiondef('crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)'::regprocedure) into v_def;
  v_nueva:=replace(v_def,'if v_cierre.lead_id is not null then',
    'if v_cierre.lead_id is not null and (coalesce(current_setting(''crm.gestion_neutral'',true),''off'')<>''on'' or exists(select 1 from crm.leads where id=v_cierre.lead_id and activo)) then');
  if v_nueva=v_def then raise exception 'No se pudo adaptar el rastro del cierre'; end if;
  execute v_nueva;
end;
$cierre$;

create function crm.inversionista_gestion_fn(p_inversionista uuid,p_fuente uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_p record; v_id uuid; v_d crm.inversionista_datos_contacto%rowtype;
  v_rol text:=private.rol_crm(auth.uid()); v_lector boolean:=private.es_lector_global();
  v_admin boolean:=public.es_admin() and not private.membresia_crm_revocada();
  v_global boolean; v_global_contrato boolean; v_postventa boolean; v_origen record; v_perfiles jsonb; v_inversion jsonb;
  v_f record; v_c public.contratos%rowtype; v_ce crm.cierres_externos%rowtype;
  v_corregir boolean:=false; v_contrato jsonb; v_documento uuid;
begin
  perform private.cartera_f5_exigir();
  v_postventa:=private.postventa_modo();
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id);
  if not found then raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501'; end if;
  v_global:=not v_lector and (v_rol='gerencia' or v_admin);
  v_global_contrato:=not v_lector and not private.membresia_crm_revocada()
    and (v_rol='gerencia' or public.es_gestor_cartera());
  select * into v_d from private.gestion_contacto(v_id);
  -- Nunca usar una fecha de vinculación, actualización o última inversión.
  select creado_en,creado_por into v_origen from (
    select i.creado_en,i.creado_por,i.id from crm.inversionistas i where private.inversionista_canonica(i.id)=v_id
    union all select p.creado_en,p.creado_por,p.id from public.perfiles p where p.id=any(v_p.perfil_ids)
    union all select l.creado_en,l.creado_por,l.id from crm.leads l where l.id=any(v_p.lead_ids)
    union all select ce.creado_en,ce.creado_por,ce.id from crm.cierres_externos ce
      where private.inversionista_canonica(ce.inversionista_id)=v_id
  ) originales order by creado_en,id limit 1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'nombre',p.nombre_completo,'creado_en',p.creado_en,
    'sin_limite',v_global,
    'puede_corregir',not v_lector and p.rol='cliente' and (v_global or (
      private.es_analista_vigente() and p.creado_en>now()-interval '5 hours'
      and (p.asesor_perfil_id=auth.uid() or (p.asesor_perfil_id is null and p.creado_por=auth.uid())))),
    'domicilio',case when not v_lector then p.domicilio end
  ) order by (p.id=v_p.perfil_id) desc,p.id),'[]') into v_perfiles
  from public.perfiles p where p.id=any(v_p.perfil_ids);
  select id into v_documento from crm.inversionista_identificadores
    where inversionista_id=v_id and estado='vigente' and tipo_documento=v_p.documento_tipo
      and documento_normalizado=v_p.documento order by id limit 1;
  if p_fuente is not null then
    select * into v_f from private.cartera_f5_fuentes_reales() f
      where f.fuente_id=p_fuente and f.inversionista_id=v_id and (not v_lector or f.empresa='avance');
    if not found or not v_f.identidad_coherente then
      raise exception 'La inversión ya no está disponible en esta ficha. Vuelve a comprobarla' using errcode='P0409'; end if;
    if v_f.empresa='avance' then
      select * into strict v_c from public.contratos where id=p_fuente;
      select to_jsonb(c) into v_contrato from (
        select id,numero_contrato,cliente_id,cliente_nombre,asesor_perfil_id,capital,moneda,tasa_anual,
          modalidad,tipo_interes,categoria,estado,fecha_inicio,fecha_vencimiento,notas_internas,creado_por,
          creado_en,producto_condicion_id,producto_id,producto_codigo,producto_version_id,producto_version,
          producto_nombre,producto_version_estado,fecha_cierre_comercial
        from crm.contratos_cartera where id=p_fuente) c;
      if v_contrato is null then raise exception 'El contrato ya no está disponible en esta ficha' using errcode='P0409'; end if;
      v_corregir:=not v_lector and private.puede_registrar_ventas()
        and (v_global_contrato or (private.es_analista_vigente() and v_c.creado_por=auth.uid()
          and v_c.creado_en>now()-interval '5 hours'))
        and private.puede_leer_contrato_pdf_como(p_fuente,auth.uid())
        and (v_c.estado not in ('renovado','retirado') or public.es_superadmin());
      v_inversion:=jsonb_build_object('empresa','avance','fuente_id',p_fuente,'contrato',v_contrato,
        'coopac',null,'puede_corregir',v_corregir,'sin_limite',v_global_contrato,
        'puede_reasignar',not v_lector and (v_rol='gerencia' or v_admin),
        'operaciones',coalesce((select jsonb_agg(jsonb_build_object(
          'id',o.id,'tipo',o.tipo,'moneda',o.moneda,'capital_renovado',o.capital_renovado,
          'capital_adicional',o.capital_adicional,'desglose_completo',o.desglose_completo,'elegible_conversion',o.elegible_conversion,
          'capital_anterior',(select c.capital from public.contratos c where c.id=o.contrato_origen_id),
          'numero_origen',(select c.numero_contrato from public.contratos c where c.id=o.contrato_origen_id),
          'numero_nuevo',(select c.numero_contrato from public.contratos c where c.id=o.contrato_nuevo_id)))
          from crm.operaciones_cartera o where o.cliente_id=any(v_p.perfil_ids)
            and (o.contrato_nuevo_id=p_fuente or o.contrato_origen_id=p_fuente)),'[]'));
    else
      select * into strict v_ce from crm.cierres_externos where id=p_fuente;
      v_inversion:=jsonb_build_object('empresa',v_f.empresa,'fuente_id',p_fuente,'contrato',null,
        'puede_corregir',v_postventa and v_rol='gerencia' and not v_lector and v_ce.anulado_en is null,
        'sin_limite',v_rol='gerencia','puede_reasignar',false,'operaciones','[]'::jsonb,
        'coopac',jsonb_build_object('monto',v_ce.monto,'moneda',v_ce.moneda,
          'numero_transaccion',v_ce.numero_transaccion,'referencia',v_ce.referencia_externa,
          'vence_en',v_ce.vence_en,'nota',v_ce.nota,'creado_en',v_ce.creado_en,
          'fecha_comercial',v_ce.fecha_comercial,'anulado_en',v_ce.anulado_en,
          'motivo_anulacion',v_ce.motivo_anulacion,'plazo_meses',v_ce.plazo_meses,
          'tasa_anual',v_ce.tasa_anual,'revision',md5(to_jsonb(v_ce)::text)));
    end if;
  end if;
  perform private.cartera_f5_exigir();
  return jsonb_build_object('version',1,'inversionista_id',v_id,'perfiles',v_perfiles,
    'contacto',jsonb_build_object('nombre_completo',v_p.nombre,'telefono',v_p.telefono,
      'domicilio',case when not v_lector then v_d.domicilio end,
      'revision',case when not v_lector then md5(jsonb_build_object('datos',to_jsonb(v_d),'nombre',v_p.nombre,'telefono',v_p.telefono)::text) end,
      'creado_en',v_origen.creado_en,'sin_limite',v_global,
      'puede_corregir',v_postventa and not v_lector and cardinality(v_p.perfil_ids)=0 and v_p.estado='activo'
        and (v_global or (v_rol in ('vendedor','supervisor') and v_p.responsable_id=auth.uid()
          and v_origen.creado_por=auth.uid() and v_origen.creado_en>now()-interval '5 hours'))),
    'documento',jsonb_build_object('id',v_documento,'tipo',v_p.documento_tipo,'numero',v_p.documento,
      'puede_corregir',v_admin and not v_lector and v_p.estado='activo'),
    'inversion',v_inversion);
end;
$$;
alter function crm.inversionista_gestion_fn(uuid,uuid) owner to postgres;
revoke all on function crm.inversionista_gestion_fn(uuid,uuid) from public,anon;
grant execute on function crm.inversionista_gestion_fn(uuid,uuid) to authenticated;

create function crm.inversionista_corregir_contacto_fn(p_inversionista uuid,p_clave uuid,p_revision text,p_datos jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_i crm.inversionistas%rowtype; v_ctx jsonb; v_recibo jsonb; v_payload jsonb;
  v_nombre text; v_telefono text; v_domicilio text; v_revision integer;
begin
  v_i:=private.postventa_persona(p_inversionista,false);
  v_ctx:=crm.inversionista_gestion_fn(v_i.id);
  v_payload:=jsonb_build_object('revision',p_revision,'datos',p_datos);
  v_recibo:=private.postventa_recibo(p_clave,v_i.id,'corregir_contacto',v_payload);
  if v_recibo is not null then return v_recibo; end if;
  if not coalesce((v_ctx#>>'{contacto,puede_corregir}')::boolean,false) then
    raise exception 'No puedes corregir estos datos: revisa el responsable y la ventana de cinco horas' using errcode='42501'; end if;
  if p_datos is null or jsonb_typeof(p_datos)<>'object'
    or p_datos-array['nombre_completo','telefono','domicilio']<>'{}'::jsonb then
    raise exception 'Datos de contacto inválidos' using errcode='22023'; end if;
  if jsonb_typeof(p_datos->'nombre_completo') is distinct from 'string'
    or coalesce(jsonb_typeof(p_datos->'telefono'),'null') not in ('string','null')
    or coalesce(jsonb_typeof(p_datos->'domicilio'),'null') not in ('string','null') then
    raise exception 'Datos de contacto inválidos' using errcode='22023'; end if;
  v_nombre:=upper(btrim(p_datos->>'nombre_completo'));
  v_telefono:=nullif(btrim(p_datos->>'telefono'),'');
  v_domicilio:=nullif(btrim(p_datos->>'domicilio'),'');
  if v_nombre is null or length(v_nombre) not between 2 and 200
    or (v_telefono is not null and (length(v_telefono) not between 6 and 32 or v_telefono !~ '^[+0-9 ()-]+$'))
    or length(v_domicilio)>500 then raise exception 'Revisa nombres, teléfono y domicilio' using errcode='22023'; end if;
  if p_revision is distinct from v_ctx#>>'{contacto,revision}' then
    raise exception 'Los datos cambiaron. Vuelve a abrir la corrección antes de guardar' using errcode='PT409'; end if;
  select coalesce(max(d.revision),0)+1 into v_revision from crm.inversionista_datos_contacto d
    where private.inversionista_canonica(d.inversionista_id)=v_i.id;
  insert into crm.inversionista_datos_contacto(inversionista_id,nombre_completo,telefono,domicilio,revision,actualizado_por)
    values(v_i.id,v_nombre,v_telefono,v_domicilio,v_revision,auth.uid())
    on conflict(inversionista_id) do update set nombre_completo=excluded.nombre_completo,
      telefono=excluded.telefono,domicilio=excluded.domicilio,revision=excluded.revision,
      actualizado_en=clock_timestamp(),actualizado_por=auth.uid();
  insert into crm.inversionista_gestiones(inversionista_id,tipo,detalle,metadata,creado_por)
    values(v_i.id,'correccion_contacto','Se corrigieron los datos actuales de contacto',jsonb_build_object('accion','correccion_contacto','revision',v_revision),auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'inversionista_id',v_i.id,'revision',v_revision));
exception when serialization_failure or lock_not_available or deadlock_detected then
  raise exception 'La ficha está cambiando. Vuelve a comprobarla' using errcode='PT409';
end;
$$;
alter function crm.inversionista_corregir_contacto_fn(uuid,uuid,text,jsonb) owner to postgres;
revoke all on function crm.inversionista_corregir_contacto_fn(uuid,uuid,text,jsonb) from public,anon;
grant execute on function crm.inversionista_corregir_contacto_fn(uuid,uuid,text,jsonb) to authenticated;

create function crm.inversionista_corregir_coopac_fn(p_inversionista uuid,p_fuente uuid,p_clave uuid,p_revision text,p_datos jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_i crm.inversionistas%rowtype; v_ce crm.cierres_externos%rowtype;
  v_recibo jsonb; v_vence date; v_plazo integer; v_tasa numeric; v_monto numeric; v_contexto_previo text;
begin
  if private.rol_crm(auth.uid()) is distinct from 'gerencia' or private.es_lector_global() then
    raise exception 'Solo Gerencia corrige inversiones de cooperativas' using errcode='42501'; end if;
  v_i:=private.postventa_persona(p_inversionista,false);
  v_ce:=private.postventa_fuente(p_fuente,v_i.id);
  select * into strict v_ce from crm.cierres_externos where id=p_fuente for update nowait;
  v_recibo:=private.postventa_recibo(p_clave,v_i.id,'corregir_coopac',
    jsonb_build_object('fuente',p_fuente,'revision',p_revision,'datos',p_datos));
  if v_recibo is not null then return v_recibo; end if;
  if p_revision is distinct from md5(to_jsonb(v_ce)::text) then
    raise exception 'La inversión cambió. Vuelve a abrirla antes de corregir' using errcode='PT409'; end if;
  if p_datos is null or jsonb_typeof(p_datos)<>'object' or
    p_datos-array['monto','numero_transaccion','referencia','nota','plazo_meses','tasa_anual','vence_en']<>'{}'::jsonb then
    raise exception 'Datos de inversión inválidos' using errcode='22023'; end if;
  if length(p_datos->>'nota')>2000 then raise exception 'La nota admite hasta 2000 caracteres' using errcode='22023'; end if;
  v_monto:=(p_datos->>'monto')::numeric;
  if v_monto is null or v_monto in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
    or v_monto<=0 or v_monto>999999999999.99 or v_monto<>trunc(v_monto,2) then
    raise exception 'Indica un monto positivo con hasta dos decimales' using errcode='22023'; end if;
  v_plazo:=(p_datos->>'plazo_meses')::integer; v_tasa:=(p_datos->>'tasa_anual')::numeric;
  if v_plazo is null and v_tasa is null and v_ce.plazo_meses is null then
    v_vence:=case when p_datos ? 'vence_en' then (p_datos->>'vence_en')::date else v_ce.vence_en end;
    if v_vence is not null and not isfinite(v_vence) then raise exception 'Vencimiento inválido' using errcode='22023'; end if;
  else
    v_vence:=private.coopac_validar_condiciones(coalesce(v_ce.fecha_comercial,(v_ce.creado_en at time zone 'America/Lima')::date),v_plazo,v_tasa);
  end if;
  -- Las condiciones y el vencimiento cambian juntos para conservar su CHECK.
  perform set_config('crm.op_privilegiada','on',true);
  update crm.cierres_externos set plazo_meses=v_plazo,tasa_anual=v_tasa,vence_en=v_vence where id=p_fuente;
  perform set_config('crm.op_privilegiada','off',true);
  v_contexto_previo:=current_setting('crm.gestion_neutral',true);
  perform set_config('crm.gestion_neutral','on',true);
  perform crm.corregir_cierre_externo(p_fuente,v_monto,v_ce.moneda,v_ce.cooperativa,
    p_datos->>'numero_transaccion',p_datos->>'referencia',v_vence,p_datos->>'nota');
  perform set_config('crm.gestion_neutral',coalesce(v_contexto_previo,'off'),true);
  insert into crm.inversionista_gestiones(inversionista_id,empresa,tipo,detalle,metadata,creado_por)
    values(v_i.id,v_ce.cooperativa,'correccion_coopac','Gerencia corrigió la inversión de cooperativa',
      jsonb_build_object('accion','correccion_coopac','fuente_id',p_fuente,
        'antes',jsonb_build_object('monto',v_ce.monto,'numero_transaccion',v_ce.numero_transaccion,
          'referencia_externa',v_ce.referencia_externa,'nota',v_ce.nota),
        'despues',jsonb_build_object('monto',v_monto,'numero_transaccion',btrim(p_datos->>'numero_transaccion'),
          'referencia_externa',nullif(btrim(p_datos->>'referencia'),''),'nota',nullif(btrim(p_datos->>'nota'),'')),
        'condiciones_antes',jsonb_build_object('plazo_meses',v_ce.plazo_meses,'tasa_anual',v_ce.tasa_anual,'vence_en',v_ce.vence_en),
        'condiciones_despues',jsonb_build_object('plazo_meses',v_plazo,'tasa_anual',v_tasa,'vence_en',v_vence)),auth.uid());
  return private.postventa_responder(p_clave,jsonb_build_object('ok',true,'inversionista_id',v_i.id,'fuente_id',p_fuente));
exception when serialization_failure or lock_not_available or deadlock_detected then
  raise exception 'La inversión está cambiando. Vuelve a comprobarla' using errcode='PT409';
when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
  raise exception 'Revisa el monto, el plazo, la tasa y la fecha de vencimiento' using errcode='22023';
end;
$$;
alter function crm.inversionista_corregir_coopac_fn(uuid,uuid,uuid,text,jsonb) owner to postgres;
revoke all on function crm.inversionista_corregir_coopac_fn(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function crm.inversionista_corregir_coopac_fn(uuid,uuid,uuid,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
