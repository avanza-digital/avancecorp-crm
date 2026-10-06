begin;
set local statement_timeout='120s';
-- Completa la identidad neutral de los perfiles sintéticos antiguos de la
-- plantilla SOLO en esta transacción local. No modifica contratos ni RPC.
insert into crm.inversionistas(perfil_id)
  select distinct c.cliente_id from public.contratos c
  where not exists(select 1 from crm.inversionistas i where i.perfil_id=c.cliente_id);
update crm.multiempresa_flags set activo=true where nombre in
  ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral','postventa_neutral');
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png'])
  on conflict(id) do nothing;
create function pg_temp.exigir(ok boolean,mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'UPGRADE: %',mensaje; end if; end $$;
create function pg_temp.como(actor uuid,p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub',actor::text,true);
  execute 'set local role authenticated';
  execute p_sql into r;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  return r;
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  raise;
end $$;
create function pg_temp.rechaza(actor uuid,p_sql text,codigo text) returns void language plpgsql as $$
begin
  begin perform pg_temp.como(actor,p_sql);
  exception when others then
    if sqlstate=codigo then return; end if;
    raise exception 'Esperado %, recibido %: %',codigo,sqlstate,sqlerrm;
  end;
  raise exception 'La operación debió rechazar con %',codigo;
end $$;
create temporary table resultados(caso text,estado text) on commit drop;

do $ensayo$
<<casos>>
declare
  actor uuid; ajeno uuid; gerente uuid; supervisor uuid; supervisor_ajeno uuid; director uuid;
  lead uuid; persona uuid; origen uuid; id uuid; normal uuid; origen_otra_persona uuid; rol_actor uuid; rol_id uuid;
  pendiente uuid; confirmada jsonb; r jsonb; d jsonb; d_inicial jsonb; antes jsonb;
  empresa text; moneda text; fecha date:=(statement_timestamp() at time zone 'America/Lima')::date; inicio_vencido date;
begin
  select perfil_id,supervisor_id into actor,supervisor from crm.equipo where private.rol_crm(perfil_id)='vendedor' and supervisor_id is not null order by perfil_id limit 1;
  select perfil_id into ajeno from crm.equipo where private.rol_crm(perfil_id)='vendedor' and perfil_id<>actor order by perfil_id limit 1;
  select perfil_id into gerente from crm.equipo where private.rol_crm(perfil_id)='gerencia' limit 1;
  select perfil_id into supervisor_ajeno from crm.equipo where private.rol_crm(perfil_id)='supervisor' and perfil_id<>supervisor limit 1;
  select p.id into director from public.perfiles p where p.rol='directorio' limit 1;
  perform pg_temp.exigir(actor is not null and ajeno is not null and gerente is not null,'faltan actores locales');
  for empresa,moneda in select * from (values('qorilazo','PEN'),('prodelco','PEN'),('prodelco','USD')) x(e,m) loop
    lead:=gen_random_uuid(); id:=gen_random_uuid();
    insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
      values(lead,'PERSONA SINTETICA UPGRADE','9'||lpad(floor(random()*1e8)::text,8,'0'),1000,'propuesta_enviada',actor,actor,'oficina');
    r:=pg_temp.como(actor,format('select crm.preparar_persona_lead_inversion_fn(%L,%L,%L,%L)',
      lead,'DNI',case when empresa='qorilazo' then '49980001' when moneda='PEN' then '49980002' else '49980003' end,'PERSONA SINTETICA UPGRADE'));
    persona:=(r->>'inversionista_id')::uuid;
    d_inicial:=jsonb_build_object('inversionista_id',persona,'lead_id',lead,'empresa',empresa,'monto',1000,'moneda',moneda,
      'fecha_comercial',fecha,'vence_en',(fecha+interval '12 months')::date,'plazo_meses',12,'tasa_anual',18,
      'numero_transaccion','UPGRADE-INICIAL-'||id,'referencia','INICIAL SINTETICA',
      'evidencia',jsonb_build_object('ruta',persona||'/'||id||'/comprobante.pdf'));
    perform pg_temp.como(actor,format('select crm.preparar_inversion_fn(%L,%L)',id,d_inicial));
    insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d_inicial#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}');
    r:=pg_temp.como(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',id));
    origen:=(r#>>'{fuente,cierre_id}')::uuid;
    select to_jsonb(c) into antes from crm.cierres_externos c where c.id=origen;
    id:=gen_random_uuid();
    d:=(d_inicial-'lead_id')||jsonb_build_object('monto',250,'numero_transaccion','UPGRADE-ADICIONAL-'||id,
      'referencia','APORTE SINTETICO','evidencia',jsonb_build_object('ruta',persona||'/'||id||'/comprobante.pdf'));
    if exists(select 1 from crm.cierres_externos c where c.id=origen_otra_persona and c.cooperativa=casos.empresa) then
      perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',id,origen_otra_persona,d),'42501');
    end if;
    r:=pg_temp.como(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',id,origen,d));
    perform pg_temp.exigir(r->>'upgrade_origen_id'=origen::text and r->>'reinversion_origen_id' is null,'tipo de preparación');
    perform pg_temp.exigir(r=pg_temp.como(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',id,origen,d)),'idempotencia preparación');
    perform pg_temp.exigir(pg_temp.como(actor,format('select crm.solicitud_inversion_fn(%L)',id))->>'upgrade_origen_id'=origen::text,'recuperación de origen');
    perform pg_temp.rechaza(actor,format('select crm.preparar_reinversion_fn(%L,%L,%L)',id,origen,d),'P0409');
    perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',id,gen_random_uuid(),d),'P0409');
    perform pg_temp.rechaza(ajeno,format('select crm.preparar_upgrade_fn(%L,%L,%L)',gen_random_uuid(),origen,d),'42501');
    perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',gen_random_uuid(),origen,d||jsonb_build_object('empresa',case when empresa='qorilazo' then 'prodelco' else 'qorilazo' end)),'P0409');
    perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',gen_random_uuid(),origen,d||jsonb_build_object('lead_id',lead)),'22023');
    perform pg_temp.rechaza(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',id),'P0409');
    perform pg_temp.rechaza(actor,format('select crm.confirmar_inversion_revisada_fn(%L,7)',id),'PT409');
    insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}');
    confirmada:=pg_temp.como(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',id));
    r:=pg_temp.como(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',id));
    perform pg_temp.exigir(r->>'inversion_id'=confirmada->>'inversion_id','confirmación duplicada');
    perform pg_temp.exigir((select to_jsonb(c)=antes from crm.cierres_externos c where c.id=origen),'origen modificado');
    perform pg_temp.exigir((select c.monto=250 and c.moneda=casos.moneda and not c.es_cierre_inicial from crm.cierres_externos c where c.id=(r#>>'{fuente,cierre_id}')::uuid),'aporte o clasificación incorrectos');
    perform pg_temp.exigir((select not es_primera_conversion from crm.inversiones i where i.id=(r->>'inversion_id')::uuid),'upgrade contó como cliente nuevo');
    perform pg_temp.exigir((select count(*)=1 from crm.inversionista_gestiones where tipo='upgrade' and metadata->>'solicitud_id'=casos.id::text),'historial upgrade');
    perform pg_temp.exigir(not exists(select 1 from crm.inversionista_gestiones where tipo='reinversion' and metadata->>'solicitud_id'=casos.id::text),'upgrade etiquetado reinversión');
    r:=pg_temp.como(actor,format('select crm.inversionista_ficha_fn(%L,1,1)',persona));
    perform pg_temp.exigir(exists(select 1 from jsonb_array_elements(r->'historial') h where h->>'tipo'='upgrade' and h->>'detalle'='Upgrade confirmado · aporte adicional'),'ficha sin historial de upgrade');
    perform pg_temp.exigir((r->>'inversiones_total')::integer=2,'ficha no muestra ambas inversiones');
    perform pg_temp.exigir(pg_temp.como(actor,format('select crm.solicitud_inversion_fn(%L)',id))->>'upgrade_origen_referencia'='INICIAL SINTETICA','referencia de origen al retomar');
    for rol_actor in select unnest(array[supervisor,gerente]) loop
      rol_id:=gen_random_uuid();
      perform pg_temp.como(rol_actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',rol_id,origen,
        d||jsonb_build_object('evidencia',jsonb_build_object('ruta',persona||'/'||rol_id||'/comprobante.pdf'))));
    end loop;
    perform pg_temp.rechaza(supervisor_ajeno,format('select crm.preparar_upgrade_fn(%L,%L,%L)',gen_random_uuid(),origen,d),'42501');
    perform pg_temp.rechaza(director,format('select crm.preparar_upgrade_fn(%L,%L,%L)',gen_random_uuid(),origen,d),'42501');
    insert into resultados values(empresa||' '||moneda||': aporte, origen intacto, idempotencia, comprobante, tipo y permisos','PASS');

    normal:=gen_random_uuid();
    d:=d||jsonb_build_object('numero_transaccion','NORMAL-'||normal,'evidencia',jsonb_build_object('ruta',persona||'/'||normal||'/comprobante.pdf'));
    perform pg_temp.como(actor,format('select crm.preparar_inversion_fn(%L,%L)',normal,d));
    perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',normal,origen,d),'P0409');
    pendiente:=gen_random_uuid();
    d:=d||jsonb_build_object('numero_transaccion','REINVERSION-'||pendiente,'evidencia',jsonb_build_object('ruta',persona||'/'||pendiente||'/comprobante.pdf'));
    r:=pg_temp.como(actor,format('select crm.preparar_reinversion_fn(%L,%L,%L)',pendiente,origen,d));
    perform pg_temp.exigir(r->>'reinversion_origen_id'=origen::text and r->>'upgrade_origen_id' is null,'reinversión reclasificada');
    perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',pendiente,origen,d),'P0409');
    insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}');
    r:=pg_temp.como(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',pendiente));
    origen_otra_persona:=(r#>>'{fuente,cierre_id}')::uuid;
    perform pg_temp.exigir((select count(*)=1 from crm.inversionista_gestiones where tipo='reinversion' and metadata->>'solicitud_id'=pendiente::text),'regresión historial reinversión');

    pendiente:=gen_random_uuid();
    d:=d||jsonb_build_object('numero_transaccion','PENDIENTE-'||pendiente,'evidencia',jsonb_build_object('ruta',persona||'/'||pendiente||'/comprobante.pdf'));
    perform pg_temp.como(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',pendiente,origen,d));
    insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}');
    perform pg_temp.como(gerente,format('select crm.anular_cierre_externo(%L,%L)',origen,'Anulación sintética para validar continuidad'));
    perform pg_temp.rechaza(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',pendiente),'P0409');
    perform pg_temp.exigir((select estado='preparada' and inversion_id is null from crm.inversion_solicitudes s where s.id=pendiente),'confirmación fallida dejó efectos');
    perform pg_temp.exigir(pg_temp.como(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',id,origen,
      (select s.datos from crm.inversion_solicitudes s where s.id=casos.id)))->>'inversion_id'=confirmada->>'inversion_id','confirmada no recuperable tras anular origen');
    r:=pg_temp.como(actor,format('select crm.cancelar_solicitud_inversion_fn(%L,0)',pendiente));
    perform pg_temp.exigir(r->>'estado'='cancelada','no se puede cancelar con origen anulado');
    insert into resultados values(empresa||' '||moneda||': reinversión intacta, sin reclasificación, anulación, recuperación y cancelación','PASS');
  end loop;

  -- Origen vencido creado por las puertas reales, sin editar capital ni falsear
  -- el reloj o reemplazar funciones. Reinvertir permanece disponible.
  lead:=gen_random_uuid(); id:=gen_random_uuid();
  insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
    values(lead,'PERSONA SINTETICA VENCIDA','9'||lpad(floor(random()*1e8)::text,8,'0'),1000,'propuesta_enviada',actor,actor,'oficina');
  r:=pg_temp.como(actor,format('select crm.preparar_persona_lead_inversion_fn(%L,%L,%L,%L)',lead,'DNI','49980004','PERSONA SINTETICA VENCIDA'));
  persona:=(r->>'inversionista_id')::uuid;
  inicio_vencido:=(fecha-interval '13 months')::date;
  d_inicial:=jsonb_build_object('inversionista_id',persona,'lead_id',lead,'empresa','qorilazo','monto',1000,'moneda','PEN',
    'fecha_comercial',inicio_vencido,'vence_en',(inicio_vencido+interval '12 months')::date,'plazo_meses',12,'tasa_anual',18,
    'numero_transaccion','VENCIDA-INICIAL-'||id,'referencia','VENCIDA SINTETICA',
    'evidencia',jsonb_build_object('ruta',persona||'/'||id||'/comprobante.pdf'));
  perform pg_temp.como(actor,format('select crm.preparar_inversion_fn(%L,%L)',id,d_inicial));
  insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d_inicial#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}');
  r:=pg_temp.como(actor,format('select crm.confirmar_inversion_revisada_fn(%L,0)',id));
  origen:=(r#>>'{fuente,cierre_id}')::uuid;
  id:=gen_random_uuid();
  d:=(d_inicial-'lead_id')||jsonb_build_object('fecha_comercial',fecha,'vence_en',(fecha+interval '12 months')::date,
    'numero_transaccion','CONTINUIDAD-VENCIDA-'||id,'evidencia',jsonb_build_object('ruta',persona||'/'||id||'/comprobante.pdf'));
  perform pg_temp.rechaza(actor,format('select crm.preparar_upgrade_fn(%L,%L,%L)',id,origen,d),'P0409');
  r:=pg_temp.como(actor,format('select crm.preparar_reinversion_fn(%L,%L,%L)',id,origen,d));
  perform pg_temp.exigir(r->>'reinversion_origen_id'=origen::text,'reinversión vencida bloqueada');
  insert into resultados values('Inversión vencida: upgrade rechazado y reinversión disponible','PASS');
end $ensayo$;

select pg_temp.exigir(not has_function_privilege('anon','crm.preparar_upgrade_fn(uuid,uuid,jsonb)','execute'),'anon ejecuta upgrade');
select pg_temp.exigir(not has_function_privilege('service_role','crm.preparar_upgrade_fn(uuid,uuid,jsonb)','execute'),'service ejecuta sin operador');
select pg_temp.exigir(has_function_privilege('authenticated','crm.preparar_upgrade_fn(uuid,uuid,jsonb)','execute'),'falta acceso RPC');
select pg_temp.exigir(not has_function_privilege('authenticated','private.preparar_continuidad_coopac(uuid,uuid,jsonb,text)','execute'),'helper expuesto');
select pg_temp.exigir(not has_table_privilege('authenticated','crm.inversion_solicitud_origenes','insert,update,delete'),'escritura directa de origen');
insert into resultados values('ACL: RPC autenticada, helpers privados y origen sin escritura directa','PASS');
select estado||': '||caso from resultados;
rollback;
