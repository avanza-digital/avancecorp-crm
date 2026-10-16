create temporary table catalogo_antes as
select oid,prosrc,proacl,prosecdef,provolatile,proconfig from pg_proc
where pronamespace in ('crm'::regnamespace,'private'::regnamespace);
create temporary table leads_antes as select * from crm.leads;
create temporary table politicas_antes as select * from pg_policy;
set local role authenticated;
select pg_temp.sesion('sup1');
select pg_temp.rechaza('select pg_temp.alta(1)','42501','la regla anterior rechaza referidos del supervisor');
reset role;

-- MIGRACION

select pg_temp.exigir((select md5(prosrc) from pg_proc where oid='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure)='145b30a30e69807a1838c1b960a0675d','huella nueva exacta');
select pg_temp.exigir(not exists(select 1 from catalogo_antes a join pg_proc p using(oid)
  where row(a.proacl,a.prosecdef,a.provolatile,a.proconfig) is distinct from row(p.proacl,p.prosecdef,p.provolatile,p.proconfig)),'ACL y atributos de todas las funciones intactos');
select pg_temp.exigir((select count(*) from catalogo_antes a join pg_proc p using(oid) where a.prosrc is distinct from p.prosrc)=1,'solo cambia una función');
select pg_temp.exigir(not exists((select * from pg_policy except select * from politicas_antes) union all (select * from politicas_antes except select * from pg_policy)),'ninguna policy cambia');
select pg_temp.exigir(not exists(select * from crm.leads except select * from leads_antes),'migración no reescribe leads');

set local role authenticated;
select pg_temp.sesion('sup1');
select pg_temp.exigir(pg_temp.alta(1)->>'estado'='creado','supervisor crea referido sin destino');
select pg_temp.exigir((select vendedor_id=auth.uid() and creado_por=auth.uid() and asignado_supervisor_id is null and origen='referido' and alta_manual from crm.leads where id=md5('referido-1')::uuid),'referido conserva autor y dueño, fuera de reparto');
select pg_temp.exigir(pg_temp.alta(1,'referido',auth.uid())->>'lead_id'=md5('referido-1')::uuid::text,'reintento con dueño explícito confirma la misma alta');
select pg_temp.exigir((select count(*) from crm.leads where id=md5('referido-1')::uuid)=1,'reintento no duplica');
select pg_temp.exigir(pg_temp.alta(2,'referido',auth.uid())->>'estado'='creado','supervisor crea referido con dueño propio explícito');
select pg_temp.exigir(pg_temp.alta(2)->>'lead_id'=md5('referido-2')::uuid::text,'reintento sin destino de alta explícita mantiene identidad');
select pg_temp.rechaza($q$select pg_temp.alta(3,'referido',(select id from actores where clase='vend1'))$q$,'42501','rechaza referido para analista propio');
select pg_temp.rechaza($q$select pg_temp.alta(3,'referido',(select id from actores where clase='vend2'))$q$,'42501','rechaza referido para analista ajeno');
select pg_temp.rechaza($q$select pg_temp.alta(3,'referido',(select id from actores where clase='sup2'))$q$,'42501','rechaza referido para otro supervisor');
select pg_temp.rechaza($q$select pg_temp.alta(1,'oficina')$q$,'22023','misma llave con otro origen rechazada');
select pg_temp.rechaza($q$update crm.leads set origen='oficina' where id=md5('referido-1')::uuid$q$,'P0409','origen del referido permanece inmutable');
select pg_temp.rechaza($q$insert into crm.leads(nombre_completo,telefono,origen,vendedor_id) values('INTENTO DIRECTO','900009999','referido',(select id from actores where clase='vend1'))$q$,'42501','INSERT directo sigue revocado');

do $otros$ declare origen text; n integer:=10; r jsonb; begin
  foreach origen in array array['oficina','landing','formulario','formulario_3'] loop
    r:=pg_temp.alta(n,origen,(select id from actores where clase='vend1'));
    perform pg_temp.exigir(r->>'estado'='creado',origen||' conserva asignación al equipo');
    n:=n+1;
    r:=pg_temp.alta(n,origen);
    perform pg_temp.exigir((select vendedor_id is null and asignado_supervisor_id=auth.uid() from crm.leads where id=(r->>'lead_id')::uuid),origen||' conserva bandeja de reparto');
    n:=n+1;
  end loop;
end $otros$;
select pg_temp.sesion('sin_equipo');
select pg_temp.exigir(pg_temp.alta(30)->>'estado'='creado','supervisor sin analistas crea su referido');
select pg_temp.sesion('vend1');
select pg_temp.exigir(pg_temp.alta(31)->>'estado'='creado','analista conserva su referido propio');
select pg_temp.rechaza($q$select pg_temp.alta(32,'referido',(select id from actores where clase='sup1'))$q$,'42501','analista no crea referido para supervisor');
select pg_temp.exigir(not exists(select 1 from crm.leads where id=md5('referido-1')::uuid),'analista no lee referido del supervisor');
select pg_temp.sesion('sup2');
select pg_temp.exigir(not exists(select 1 from crm.leads where id=md5('referido-1')::uuid),'otro supervisor no lee el referido');
do $roles$ declare rol text; begin
  foreach rol in array array['gerencia','coordinador','directorio','cliente','desconocido'] loop
    perform pg_temp.sesion(rol);
    perform pg_temp.rechaza('select pg_temp.alta(40)','42501','referido denegado a '||rol);
  end loop;
end $roles$;

-- DNI, CE y pasaporte pasan por el mismo control de autoría.
select pg_temp.sesion('sup1');
do $documentos$ declare tipo text; n integer:=50; r jsonb; datos jsonb; begin
  foreach tipo in array array['DNI','CE','PASAPORTE'] loop
    datos:=jsonb_build_object('id',md5('referido-'||n)::uuid,'nombre_completo','REFERIDO DOCUMENTADO',
      'telefono',(900000000+n)::text,'origen','referido','monto_estimado',20000,'moneda','PEN');
    r:=crm.crear_lead_documento_fn(datos,tipo,case tipo when 'CE' then '009616050' else (96000000+n)::text end);
    perform pg_temp.exigir(r->>'estado'='creado','alta con documento '||tipo);
    perform pg_temp.exigir((select vendedor_id=auth.uid() and creado_por=auth.uid() and asignado_supervisor_id is null from crm.leads where id=(r->>'lead_id')::uuid),'dueño propio con documento '||tipo);
    perform pg_temp.exigir(crm.crear_lead_documento_fn(datos,tipo,case tipo when 'CE' then '009616050' else (96000000+n)::text end)=r,'reintento documental '||tipo);
    perform pg_temp.rechaza(format('select crm.crear_lead_documento_fn(%L::jsonb,%L,%L)',
      datos||jsonb_build_object('vendedor_id',(select id from actores where clase='vend1')),tipo,
      case tipo when 'CE' then '009616050' else (96000000+n)::text end),'42501','envoltorio no permite otro dueño: '||tipo);
    n:=n+1;
  end loop;
end $documentos$;
select pg_temp.exigir(crm.crear_lead_si_disponible('REFERIDO DUPLICADO','900000001','referido',20000,'PEN')->>'estado'<>'creado','otro id no duplica el mismo contacto');
reset role;

savepoint baja_perfil;
select pg_temp.sesion('desconocido');
select set_config('crm.op_privilegiada','on',true);
update public.perfiles set activo=false where id=(select id from actores where clase='sup1');
select set_config('crm.op_privilegiada','',true);
select pg_temp.exigir((select not activo from public.perfiles where id=(select id from actores where clase='sup1')),'fixture confirma baja de perfil');
set local role authenticated;
select pg_temp.sesion('sup1');
select pg_temp.rechaza('select pg_temp.alta(60)','42501','perfil inactivo no crea referido con mismo JWT');
rollback to baja_perfil;
savepoint baja_equipo;
select pg_temp.sesion('desconocido');
select set_config('crm.op_privilegiada','on',true);
update crm.equipo set activo=false where perfil_id=(select id from actores where clase='para_baja');
select set_config('crm.op_privilegiada','',true);
select pg_temp.exigir((select not activo from crm.equipo where perfil_id=(select id from actores where clase='para_baja')),'fixture confirma baja de membresía');
set local role authenticated;
select pg_temp.sesion('para_baja');
select pg_temp.rechaza('select pg_temp.alta(61)','42501','membresía inactiva no crea referido con mismo JWT');
rollback to baja_equipo;
savepoint cambio_rol;
select pg_temp.sesion('desconocido');
select set_config('crm.op_privilegiada','on',true);
update crm.equipo set rol_crm='gerencia' where perfil_id=(select id from actores where clase='para_cambio');
select set_config('crm.op_privilegiada','',true);
set local role authenticated;
select pg_temp.sesion('para_cambio');
select pg_temp.rechaza('select pg_temp.alta(62)','42501','cambiar a Gerencia retira el alta de referido con el mismo JWT');
rollback to cambio_rol;

set local role supabase_admin;
-- ACL productiva leída el 16/10: postgres tiene ALL WITH GRANT OPTION en Storage.
grant all on storage.buckets,storage.objects to postgres with grant option;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf']) on conflict(id) do nothing;
set local role postgres;
select pg_temp.sesion('sup1');
do $conversion$ declare r jsonb; c jsonb; persona uuid; solicitud uuid:=gen_random_uuid(); datos jsonb; begin
  execute 'set local role authenticated';
  persona:=(crm.preparar_persona_lead_inversion_fn(md5('referido-1')::uuid,'DNI','96000001','REFERIDO SINTETICO')->>'inversionista_id')::uuid;
  datos:=jsonb_build_object('inversionista_id',persona,'lead_id',md5('referido-1')::uuid,'empresa','qorilazo',
    'monto',20000,'moneda','PEN','fecha_comercial',current_date,'vence_en',(current_date+interval '12 months')::date,
    'plazo_meses',12,'tasa_anual',15,'numero_transaccion','REF-SUP-QA','referencia','CERTIFICADO FICTICIO',
    'evidencia',jsonb_build_object('ruta',persona||'/'||solicitud||'/comprobante.pdf'));
  perform crm.preparar_inversion_fn(solicitud,datos);
  execute 'set local role supabase_admin';
  -- Solo metadatos sintéticos de Storage; las RPC comerciales se invocan como authenticated.
  insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',datos#>>'{evidencia,ruta}',
    '{"size":128,"mimetype":"application/pdf"}'::jsonb);
  execute 'set local role authenticated';
  r:=crm.confirmar_inversion_revisada_fn(solicitud,0);
  perform pg_temp.exigir(r->>'inversion_id' is not null,'referido del supervisor se convierte por la puerta compartida vigente');
  perform pg_temp.exigir(crm.confirmar_inversion_revisada_fn(solicitud,0)->>'inversion_id'=r->>'inversion_id','reintento de conversión no duplica inversión');
  perform pg_temp.exigir((select etapa='convertido' and vendedor_id=auth.uid() from crm.leads where id=md5('referido-1')::uuid),'conversión conserva el supervisor');
  c:=crm.cartera_inversionistas_filtrada_fn(p_texto=>'96000001');
  perform pg_temp.exigir(c->'filas'->0->>'responsable_id'=auth.uid()::text,'Cartera conserva responsable del referido');
  c:=crm.cumplimiento_metas_fn(date_trunc('month',current_date)::date);
  perform pg_temp.exigir(exists(select 1 from jsonb_array_elements(c->'fuera_ranking') f,
    jsonb_array_elements(f->'detalles') d where f->>'persona_id'=auth.uid()::text
    and d->>'moneda'='PEN' and d->>'categoria'='nuevo' and (d->>'capital_real')::numeric=20000
    and (d->>'contratos_real')::int=1),'venta referida aparece en producción propia para aportar al equipo');
end $conversion$;
reset role;

select pg_temp.exigir((select count(*)=1 and sum(aporte_divisor)=0 and sum(aporte_numerador)=0.15
  from private.conversion_episodios(date_trunc('month',now() at time zone 'America/Lima') at time zone 'America/Lima',
    (date_trunc('month',now() at time zone 'America/Lima')+interval '1 month') at time zone 'America/Lima',
    date_trunc('month',current_date)::date,true,null,0.15)
  where tipo='cierre' and lead_id=md5('referido-1')::uuid and analista_id=(select id from actores where clase='sup1')),
  'núcleo conserva el referido del supervisor y su tope mensual, sin duplicar ni sumar divisor');
select pg_temp.exigir((select cierres_referido=1 and cierres_referido_aporte=0.15
  from private.conversion_divisor_empresa_totales(date_trunc('month',current_date)::date,
    (date_trunc('month',current_date)+interval '1 month - 1 day')::date)),
  'total de empresa incluye el referido y su aporte una sola vez');
set local role authenticated;
select pg_temp.sesion('gerencia');
do $reportes$ declare c jsonb; begin
  c:=crm.conversion_mensual_fn(date_trunc('month',current_date)::date);
  perform pg_temp.exigir(jsonb_typeof(c->'responsables')='array' and not exists(
    select 1 from jsonb_array_elements(c->'responsables') f where f->>'vendedor_id'=(select id::text from actores where clase='sup1')),
    'supervisor no entra en filas de conversión de analistas');
  c:=crm.metricas_conversiones_fn(current_date,current_date,'referido');
  perform pg_temp.exigir(c->>'origen_filtrado'='referido' and (c#>>'{cierres_por_semana,cierres}')::int=1,
    'reporte por origen incluye el cierre referido del supervisor');
end $reportes$;
reset role;

-- REVERSA

select pg_temp.exigir((select md5(prosrc) from pg_proc where oid='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure)='b6ec8dddaa8ab81b9248a79f4de3a51f','reversa restaura función exacta');
set local role authenticated;
select pg_temp.sesion('sup1');
select pg_temp.exigir(exists(select 1 from crm.leads where id=md5('referido-1')::uuid),'reversa conserva referidos creados');
select pg_temp.rechaza('select pg_temp.alta(70)','42501','reversa restaura rechazo anterior');
reset role;

-- REAPLICACION

set local role authenticated;
select pg_temp.sesion('sup1');
select pg_temp.exigir(pg_temp.alta(70)->>'estado'='creado','reaplicación habilita de nuevo el alta propia');
reset role;
