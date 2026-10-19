-- Solo banco sintético propio. RPC como authenticated, triggers reales; rollback total.
begin;
set local statement_timeout='120s';
set local lock_timeout='3s';
insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing;
select set_config('banco.revision',(select revision::text from crm.recorrido_control where id),true);
create temporary table conversion_casos(nombre text primary key,id uuid default gen_random_uuid(),
  documento text,solicitud uuid default gen_random_uuid(),persona uuid,tarea uuid,actividad uuid,datos jsonb,respuesta jsonb,acceso jsonb);
grant select,update on conversion_casos to authenticated;
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $$
begin if p_ok is not true then raise exception 'CONVERSION: %',p_mensaje;end if;end $$;
create function pg_temp.rechaza(p_sql text,p_estado text,p_texto text default null) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate=p_estado and (p_texto is null or position(p_texto in sqlerrm)>0) then return;end if;
    raise exception 'Esperado % / %, obtenido % (%) en %',p_estado,p_texto,sqlstate,sqlerrm,p_sql;
  end;
  raise exception 'Debio rechazar con %: %',p_estado,p_sql;
end $$;
create function pg_temp.preparar_persona(p_nombre text) returns void language plpgsql as $$
declare c record;r jsonb;
begin
  select * into strict c from conversion_casos where nombre=p_nombre;
  r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO RECORRIDO '||c.nombre);
  update conversion_casos set persona=(r->>'inversionista_id')::uuid where id=c.id;
end $$;
create function pg_temp.oficina(p_nombre text) returns void language plpgsql as $$
declare c record;r jsonb;
begin
  select * into strict c from conversion_casos where nombre=p_nombre;
  r:=crm.recorrido_atender_oficina_fn(gen_random_uuid(),c.id,'interesado','Asistencia y entrevista reales del banco',null,1000,'PEN');
  update conversion_casos set tarea=(r->>'tarea_id')::uuid,actividad=(r->>'actividad_id')::uuid where id=c.id;
end $$;

insert into conversion_casos(nombre,documento) values ('antiguo','98640001'),('observacion','98640002'),('identidad_tardia','98640014');
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
select id,'BANCO RECORRIDO '||nombre,'98764'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',1000,
 'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from conversion_casos;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.preparar_persona('observacion');
select pg_temp.preparar_persona('antiguo');
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
select pg_temp.rechaza(format('select crm.recorrido_configurar_fn(''exigir'',''Fecha digitada con error de siglo'',%s,''2106-01-01'')',
 current_setting('banco.revision')::integer),'22023','proximas 24 horas');
select crm.recorrido_configurar_fn('exigir','Ensayo local de cohortes y primera conversion',current_setting('banco.revision')::integer+0);
reset role;
insert into conversion_casos(nombre,documento) values
 ('sin_hechos','98640003'),('normal_sin_llamada','98640004'),('anulada','98640005'),
 ('sin_resultado','98640006'),('reabierto','98640007'),('acceso','98640008'),('prodelco','98640009'),
 ('solo_etapa','98640010'),('confirmado','98640011'),('nueva_solicitud','98640012'),('futura','98640013');
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
select id,'BANCO RECORRIDO '||nombre,'98765'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',1000,
 'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002'
 from conversion_casos c where not exists(select 1 from crm.leads l where l.id=c.id);
select pg_temp.exigir((select bool_and((r.resultado->>'ciclo_inicio')::timestamptz>=ctl.cohorte_desde)
 from private.recorrido_evaluar(array(select id from conversion_casos where persona is null and nombre<>'identidad_tardia')) r
 cross join crm.recorrido_control ctl),'los nuevos pertenecen a la cohorte de exigencia');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''ANTIGUO SIN ENTREVISTA'')',id,documento),'P0409','Antes de convertir')
 from conversion_casos where nombre='identidad_tardia';
select pg_temp.oficina('identidad_tardia');
select pg_temp.preparar_persona('identidad_tardia');
do $$
declare c record;r jsonb;
begin
  select * into c from conversion_casos where nombre='sin_hechos';
  perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SIN HECHOS'')',c.id,c.documento),'P0409','Antes de convertir');
  select * into c from conversion_casos where nombre='solo_etapa';
  update crm.leads set etapa='propuesta_enviada' where id=c.id;
  perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SOLO ETAPA'')',c.id,c.documento),'P0409','Antes de convertir');
  for c in select * from conversion_casos where nombre in ('normal_sin_llamada','sin_resultado','futura') loop
    insert into crm.tareas(lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
    values(c.id,'reunion','Cita normal del banco',clock_timestamp()+case when c.nombre='futura' then interval '1 day' else interval '-1 minute' end,
      'presencial','Oficina banco','b0000000-0000-4000-8000-000000000002') returning id into c.tarea;
    if c.nombre='futura' then
      update conversion_casos set tarea=c.tarea where id=c.id;
      perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO CITA FUTURA'')',c.id,c.documento),'P0409','Antes de convertir');
      continue;
    end if;
    if c.nombre='sin_resultado' then
      perform pg_temp.rechaza(format('select crm.cerrar_reunion_v3(%L,%L,''completada'',''sin_clasificar'',null,''Sin entrevista'',null,1000,''PEN'')',gen_random_uuid(),c.tarea),'22023','resultado comercial');
      update conversion_casos set tarea=c.tarea where id=c.id;
    else
      r:=crm.cerrar_reunion_v3(gen_random_uuid(),c.tarea,'completada','interesado',null,'Asistio a su cita',null,1000,'PEN');
      update conversion_casos set tarea=c.tarea,actividad=(r->>'actividad_id')::uuid where id=c.id;
      perform pg_temp.preparar_persona(c.nombre);
    end if;
  end loop;
  for c in select * from conversion_casos where nombre in ('anulada','reabierto','acceso','prodelco','confirmado','nueva_solicitud') loop
    perform pg_temp.oficina(c.nombre);perform pg_temp.preparar_persona(c.nombre);
  end loop;
  raise notice 'PASS: identidad bloqueada sin hechos, solo etapa, futura o asistencia sin resultado; cita e entrevista sin llamada previa aceptadas';
end $$;
reset role;
-- Forma histórica permitida por la tabla, nunca por el formulario actual.
select set_config('request.jwt.claim.sub','',true);
do $$
declare c record;a uuid;
begin
  select * into c from conversion_casos where nombre='sin_resultado';
  insert into crm.actividades(lead_id,tipo,metadata,creado_por)
    values(c.id,'reunion_realizada',jsonb_build_object('tarea_id',c.tarea),'b0000000-0000-4000-8000-000000000002') returning id into a;
  perform set_config('crm.op_tarea','on',true);
  update crm.tareas set estado='completada',resultado_actividad_id=a,resultado_reunion='sin_clasificar' where id=c.tarea;
  perform set_config('crm.op_tarea','off',true);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SIN ENTREVISTA'')',id,documento),'P0409','Antes de convertir')
 from conversion_casos where nombre='sin_resultado';
select pg_temp.rechaza(format('update crm.tareas set vence_en=clock_timestamp()-interval ''1 day'' where id=%L',tarea),'22023','ya esta cerrada')
 from conversion_casos where nombre='normal_sin_llamada';
reset role;
select pg_temp.exigir(not exists(select 1 from crm.inversionistas i join crm.inversionista_identificadores d on d.inversionista_id=i.id
  where d.documento_normalizado in ('98640003','98640006','98640010','98640013')),'los rechazos no dejaron identidades a medias');
select pg_temp.exigir((select not (resultado#>>'{pasos,contactado}')::boolean and (resultado->>'habilita_conversion')::boolean
 from private.recorrido_evaluar(array[(select id from conversion_casos where nombre='normal_sin_llamada')])),'contacto previo no es requisito adicional');

-- Datos cooperativos reales de la puerta vigente; solo los bytes de comprobante son fixture.
update conversion_casos set datos=jsonb_build_object('inversionista_id',persona,'lead_id',id,
 'empresa',case when nombre='prodelco' then 'prodelco' else 'qorilazo' end,'monto',1000,'moneda','PEN',
 'fecha_comercial',(clock_timestamp() at time zone 'America/Lima')::date,
 'vence_en',private.coopac_validar_condiciones((clock_timestamp() at time zone 'America/Lima')::date,12,12),
 'plazo_meses',12,'tasa_anual',12,'numero_transaccion','RECORRIDO-'||solicitud,'referencia','BANCO SINTETICO',
 'evidencia',jsonb_build_object('ruta',persona||'/'||solicitud||'/comprobante.pdf')) where persona is not null and nombre<>'acceso';
update conversion_casos set datos=jsonb_build_object('inversionista_id',persona,'lead_id',id,'empresa','avance',
 'contrato',jsonb_build_object('moneda','PEN','capital',1000),'cronograma','[]'::jsonb,'cuenta','{}'::jsonb,
 'alta_portal',jsonb_build_object('correo','recorrido.'||id||'@example.test','nombre_completo','BANCO ACCESO RECORRIDO',
 'telefono','987650099','domicilio','CALLE SINTETICA 123, LIMA')) where nombre='acceso';
update crm.leads set correo=c.datos#>>'{alta_portal,correo}' from conversion_casos c where c.id=crm.leads.id and c.nombre='acceso';
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;
begin
  for c in select * from conversion_casos where persona is not null and nombre<>'nueva_solicitud' loop
    if c.nombre in ('antiguo','observacion') then
      perform pg_temp.rechaza(format('select crm.preparar_inversion_fn(%L,%L)',c.solicitud,c.datos),'P0409','Antes de convertir');
      perform pg_temp.oficina(c.nombre);
    end if;
    r:=crm.preparar_inversion_fn(c.solicitud,c.datos);
    update conversion_casos set respuesta=r where id=c.id;
  end loop;
end $$;
reset role;
insert into storage.objects(bucket_id,name,metadata)
select 'f4-comprobantes',datos#>>'{evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}'::jsonb
 from conversion_casos where datos->>'empresa' in ('qorilazo','prodelco') and nombre<>'nueva_solicitud';
-- Corrección real posterior del historial: nunca se inventa un registro de contexto.
select set_config('request.jwt.claim.sub','',true);
update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp())
 where id in (select actividad from conversion_casos where nombre in ('anulada','nueva_solicitud'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;
begin
  select * into c from conversion_casos where nombre='nueva_solicitud';
  perform pg_temp.rechaza(format('select crm.preparar_inversion_fn(%L,%L)',c.solicitud,c.datos),'P0409','Antes de convertir');
  select * into c from conversion_casos where nombre='anulada';
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',c.solicitud),'P0409','Antes de convertir');
  r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'NO REESCRIBIR NOMBRE AL RETOMAR');
  perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'retoma desde ficha en otra sesion sin bloquear lectura');
  perform pg_temp.exigir((select nombre_completo='BANCO RECORRIDO anulada' from crm.leads where id=c.id),'retoma de borrador no reescribe identidad');
  r:=crm.preparar_inversion_fn(c.solicitud,c.datos);
  perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'borrador recuperable tras invalidacion');
  for c in select * from conversion_casos where nombre in ('antiguo','identidad_tardia','normal_sin_llamada','prodelco','confirmado') loop
    r:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
    update conversion_casos set respuesta=r where id=c.id;
  end loop;
  raise notice 'PASS: primera conversion de ambas cooperativas; antiguos requieren hechos reales, nueva solicitud y confirmacion protegidas; borrador conservado';
end $$;
reset role;
select pg_temp.exigir((select s.estado='preparada' and s.datos=c.datos and s.inversion_id is null and s.recorrido_confirmado is null
 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='anulada'),'rechazo atomico preserva condiciones y comprobante');
select pg_temp.exigir(not exists(select 1 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='nueva_solicitud'),'no solicitud nueva a medias');
select pg_temp.exigir((select bool_and(s.recorrido_confirmado->>'modo'='exigir' and (s.recorrido_confirmado->>'exigible')::boolean
 and s.recorrido_confirmado->>'asistencia_id'=c.actividad::text and s.recorrido_confirmado->>'entrevista_tarea_id'=c.tarea::text
 and l.etapa='convertido') from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id join crm.leads l on l.id=c.id
 where c.nombre in ('normal_sin_llamada','prodelco','confirmado')),'snapshot de la misma cita y conversion efectiva');
select pg_temp.exigir((select (s.recorrido_confirmado->>'exigible')::boolean and s.recorrido_confirmado->>'estado'='completo'
 and s.recorrido_confirmado->>'asistencia_id'=c.actividad::text
 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='antiguo'),'antiguos requieren asistencia y entrevista reales, sin backfill');
select pg_temp.exigir((select (s.recorrido_confirmado->>'exigible')::boolean and s.recorrido_confirmado->>'identidad_vinculada_en' is not null
 and s.recorrido_confirmado->>'asistencia_id'=c.actividad::text
 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='identidad_tardia'),'identidad posterior no exime al lead anterior al inicio de exigencia');
select set_config('request.jwt.claim.sub','',true);
update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp())
 where id=(select actividad from conversion_casos where nombre='confirmado');
select pg_temp.rechaza(format('update crm.inversion_solicitudes set recorrido_confirmado=''{}'' where id=%L',
 (select solicitud from conversion_casos where nombre='confirmado')),'42501','inmutable');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;
begin
  select * into c from conversion_casos where nombre='confirmado';
  r:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
  perform pg_temp.exigir((r->>'reintento')::boolean and r->>'inversion_id'=c.respuesta->>'inversion_id','confirmacion perdida retorna inversion original tras invalidacion');
  r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO RECORRIDO '||c.nombre);
  perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'recuperacion de identidad confirmada no se bloquea');
  -- Una segunda inversión conserva el camino de Cartera, sin imponer otra entrevista.
  c.solicitud:=gen_random_uuid();
  c.datos:=(c.datos-'lead_id')||jsonb_build_object('numero_transaccion','RECORRIDO-'||c.solicitud,
    'evidencia',jsonb_build_object('ruta',c.persona||'/'||c.solicitud||'/comprobante.pdf'));
  perform crm.preparar_inversion_fn(c.solicitud,c.datos);
  update conversion_casos set acceso=jsonb_build_object('adicional',c.solicitud,'datos',c.datos) where nombre='confirmado';
  raise notice 'PASS: replay confirmado y fotografia inmutable; inversion adicional sin nueva entrevista';
end $$;
reset role;
insert into storage.objects(bucket_id,name,metadata)
 select 'f4-comprobantes',acceso#>>'{datos,evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}'::jsonb
 from conversion_casos where nombre='confirmado';
set local role authenticated;
select crm.confirmar_inversion_revisada_fn((acceso->>'adicional')::uuid,0) from conversion_casos where nombre='confirmado';
reset role;
select pg_temp.exigir((select s.lead_origen_id is null and s.recorrido_confirmado is null and s.estado='confirmada'
 from crm.inversion_solicitudes s join conversion_casos c on s.id=(c.acceso->>'adicional')::uuid where c.nombre='confirmado'),'adicional confirmada sin evidencia inicial inventada');

-- Un claim sin Auth no exime. Un alta externa efectivamente creada sí se recupera,
-- aunque después se invalide la entrevista; confirmar sigue bloqueado.
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
update conversion_casos set acceso=crm.acceso_inversion_fn(solicitud,'reclamar',jsonb_build_object('token',repeat('a',48))) where nombre='acceso';
reset role;
select set_config('request.jwt.claim.sub','',true);
update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp())
 where id=(select actividad from conversion_casos where nombre='acceso');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.rechaza(format('select crm.acceso_inversion_fn(%L,''reclamar'',%L)',solicitud,jsonb_build_object('token',repeat('a',48))),'P0409','Antes de convertir')
 from conversion_casos where nombre='acceso';
reset role;
-- Fixture explícito de Auth remoto creado con HTTP perdido. Ningún usuario real.
insert into auth.users(id,email,raw_app_meta_data)
 select gen_random_uuid(),datos#>>'{alta_portal,correo}',jsonb_build_object('provider','email','claim_id',acceso->>'claim_id')
 from conversion_casos where nombre='acceso';
update conversion_casos set acceso=acceso||jsonb_build_object('auth_user_id',u.id)
 from auth.users u where nombre='acceso' and u.raw_app_meta_data->>'claim_id'=acceso->>'claim_id';
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;v_version integer;
begin
  select * into c from conversion_casos where nombre='acceso';
  r:=crm.acceso_inversion_fn(c.solicitud,'reclamar',jsonb_build_object('token',repeat('a',48)));
  perform pg_temp.exigir(r->>'claim_id'=c.acceso->>'claim_id','recupera el mismo claim con Auth efectivamente creado');
  v_version:=(r->>'version')::integer;
  r:=crm.acceso_inversion_fn(c.solicitud,'registrar_auth',jsonb_build_object('token',repeat('a',48),'version',v_version,'auth_user_id',c.acceso->>'auth_user_id'));
  r:=crm.acceso_inversion_fn(c.solicitud,'crear_perfil',jsonb_build_object('token',repeat('a',48),'version',(r->>'version')::integer));
  r:=crm.acceso_inversion_fn(c.solicitud,'enlazar',jsonb_build_object('token',repeat('a',48),'version',(r->>'version')::integer));
  perform pg_temp.exigir(r->>'estado'='enlazado','recuperacion completa sin dejar perfil huerfano');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',c.solicitud),'P0409','Antes de convertir');
  r:=crm.acceso_inversion_fn(c.solicitud,'reclamar',jsonb_build_object('token',repeat('a',48)));
  perform pg_temp.exigir(r->>'estado'='enlazado','replay del acceso concluido tampoco recrea Auth');
  raise notice 'PASS: claim sin Auth no exime; Auth creado con respuesta perdida se recupera, primera conversion sigue bloqueada';
end $$;
reset role;
select pg_temp.exigir((select s.estado='preparada' and s.datos=c.datos and s.inversion_id is null
 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='acceso'),'recuperar acceso preserva borrador sin convertir');

-- Descartar/reabrir inicia otro ciclo: una solicitud previa no conserva permiso.
set local role authenticated;
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=(select id from conversion_casos where nombre='reabierto');
select crm.reabrir_lead_fn(id) from conversion_casos where nombre='reabierto';
select pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',solicitud),'P0409','Antes de convertir')
 from conversion_casos where nombre='reabierto';
reset role;
select pg_temp.exigir((select ciclo_actual=2 from crm.leads where id=(select id from conversion_casos where nombre='reabierto')),'nuevo ciclo real');

-- La defensa de tabla también cubre escritores privilegiados e importaciones.
select set_config('request.jwt.claim.sub','',true);
select set_config('crm.op_privilegiada','on',true);
select pg_temp.rechaza($q$insert into crm.leads(nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por,etapa,creado_en)
 values('BANCO INSERT CONVERTIDO','987659999','oficina',1000,'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','convertido','2000-01-01')$q$,'P0409','Registra primero');
select set_config('crm.op_privilegiada','off',true);
select pg_temp.rechaza(format('update crm.inversion_solicitudes set estado=''confirmada'' where id=%L',
 (select solicitud from conversion_casos where nombre='anulada')),'P0409','Antes de convertir');
do $$begin raise notice 'PASS: ciclo reabierto exige nuevos hechos; escrituras internas no saltan la defensa de tabla';end $$;

-- Daño interno simulado de un lead nuevo: solo este fixture pierde el ciclo.
-- Rehabilitar triggers ANTES de probar: ningún permiso ni writer de producto lo permite.
set local session_replication_role=replica;
delete from crm.lead_sla_ciclos where lead_id=(select id from conversion_casos where nombre='sin_hechos');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO CICLO AUSENTE'')',id,documento),'P0409','Antes de convertir')
 from conversion_casos where nombre='sin_hechos';
select pg_temp.exigir((crm.recorrido_leads_fn(array[(select id from conversion_casos where nombre='sin_hechos')])#>>'{filas,0,exigible}')::boolean,
 'la guia coincide con el servidor cuando falta el ciclo de un lead nuevo');
reset role;

-- Modo observación deja operar y registra su decisión; apagar no reinicia el corte.
set local role authenticated;
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
select crm.recorrido_configurar_fn('observacion','Ensayo observacion sin bloqueo comercial',current_setting('banco.revision')::integer+1);
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select crm.confirmar_inversion_revisada_fn(solicitud,0) from conversion_casos where nombre='observacion';
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
select crm.recorrido_configurar_fn('apagado','Ensayo de rollback conservando el corte',current_setting('banco.revision')::integer+2);
select crm.recorrido_configurar_fn('exigir','Reactivacion del mismo corte sin exenciones',current_setting('banco.revision')::integer+3);
reset role;
select pg_temp.exigir((select s.recorrido_confirmado->>'modo'='observacion' and not (s.recorrido_confirmado->>'exigible')::boolean
 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='observacion'),'observacion confirmada con modo real');

-- Casos nuevos posteriores al corte: prueban el modo, no la exención histórica.
do $$
declare m text;r jsonb;c record;rev integer;f date:=(clock_timestamp() at time zone 'America/Lima')::date;n integer:=0;
begin
  foreach m in array array['observacion','apagado'] loop
    n:=n+1;
    select revision into rev from crm.recorrido_control where id;
    perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
    set local role authenticated;
    perform crm.recorrido_configurar_fn(m,'Modo sin bloqueo para ciclos posteriores al corte',rev);
    reset role;
    insert into conversion_casos(nombre,documento) values('nuevo_'||m,'9864002'||n) returning * into c;
    insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
      values(c.id,'BANCO RECORRIDO '||c.nombre,'98765800'||n,'oficina',1000,'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002');
    perform set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
    set local role authenticated;perform pg_temp.preparar_persona(c.nombre);reset role;
    select * into c from conversion_casos where nombre=c.nombre;
    c.datos:=jsonb_build_object('inversionista_id',c.persona,'lead_id',c.id,'empresa','prodelco','monto',1000,'moneda','PEN',
      'fecha_comercial',f,'vence_en',private.coopac_validar_condiciones(f,12,12),'plazo_meses',12,'tasa_anual',12,
      'numero_transaccion','RECORRIDO-'||c.solicitud,'referencia','BANCO MODO',
      'evidencia',jsonb_build_object('ruta',c.persona||'/'||c.solicitud||'/comprobante.pdf'));
    set local role authenticated;perform crm.preparar_inversion_fn(c.solicitud,c.datos);reset role;
    insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',c.datos#>>'{evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}');
    set local role authenticated;perform crm.confirmar_inversion_revisada_fn(c.solicitud,0);reset role;
    select recorrido_confirmado into r from crm.inversion_solicitudes where id=c.solicitud;
    perform pg_temp.exigir(r->>'modo'=m and not (r->>'exigible')::boolean and r->>'estado'='incompleto'
      and (r->>'ciclo_inicio')::timestamptz>=(r->>'cohorte_desde')::timestamptz,'modo permite ciclo nuevo sin hechos: '||m);
  end loop;
  select revision into rev from crm.recorrido_control where id;
  perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
  set local role authenticated;
  perform crm.recorrido_configurar_fn('exigir','Reactivacion exige hechos a la misma cohorte',rev);
  select * into c from conversion_casos where nombre='solo_etapa';
  perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SOLO ETAPA'')',c.id,c.documento),'P0409','Antes de convertir');
  reset role;
  raise notice 'PASS: observacion y apagado permiten conversion nueva sin hechos; reactivar exige sin reiniciar el corte';
end $$;

set local role anon;
select pg_temp.rechaza('select crm.confirmar_inversion_revisada_fn(gen_random_uuid(),0)','42501');
reset role;
set local role service_role;
select pg_temp.rechaza('select private.recorrido_exigir(gen_random_uuid(),''forjado'')','42501');
reset role;
select pg_temp.exigir(private.assert_sla_nucleo() is not null,'nucleo SLA sin cambios');
rollback;
