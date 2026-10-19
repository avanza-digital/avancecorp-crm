-- Banco sintético. Las RPC se ejecutan como authenticated, con triggers reales.
begin;
set local statement_timeout='120s';
set local lock_timeout='3s';
create temporary table oficina_casos(nombre text primary key,id uuid default gen_random_uuid(),
  operacion uuid default gen_random_uuid(),tarea uuid default gen_random_uuid(),respuesta jsonb);
grant select,update on oficina_casos to authenticated;
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $$
begin if p_ok is not true then raise exception 'OFICINA: %',p_mensaje;end if;end $$;
create function pg_temp.rechaza(p_sql text,p_estado text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate=p_estado then return;end if;
    raise exception 'Esperado %, obtenido % (%) en %',p_estado,sqlstate,sqlerrm,p_sql;
  end;
  raise exception 'Debio rechazar con %: %',p_estado,p_sql;
end $$;
insert into auth.users(id,email,raw_app_meta_data)
values ('b2000000-0000-4000-8000-000000000001','supervisor.oficina@example.test','{"provider":"email"}'),
       ('b2000000-0000-4000-8000-000000000002','analista.oficina@example.test','{"provider":"email"}'),
       ('b2000000-0000-4000-8000-000000000003','coordinacion.oficina@example.test','{"provider":"email"}'),
       ('b2000000-0000-4000-8000-000000000004','directorio.oficina@example.test','{"provider":"email"}');
insert into public.perfiles(id,nombre_completo,rol,activo,tipo_documento,debe_cambiar_password,titular_distinto,titular_distinto_usd)
values ('b2000000-0000-4000-8000-000000000001','BANCO SUPERVISOR OFICINA','comercial',true,'DNI',false,false,false),
       ('b2000000-0000-4000-8000-000000000002','BANCO ANALISTA OFICINA','comercial',true,'DNI',false,false,false),
       ('b2000000-0000-4000-8000-000000000003','BANCO COORDINACION OFICINA','comercial',true,'DNI',false,false,false),
       ('b2000000-0000-4000-8000-000000000004','BANCO DIRECTORIO OFICINA','directorio',true,'DNI',false,false,false);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
values ('b2000000-0000-4000-8000-000000000001','supervisor',null,true),
       ('b2000000-0000-4000-8000-000000000003','coordinador',null,true);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
values ('b2000000-0000-4000-8000-000000000002','vendedor','b2000000-0000-4000-8000-000000000001',true);
insert into oficina_casos(nombre) values ('vendedor'),('supervisor'),('gerencia'),('no_interesado'),
  ('ajeno'),('sin_asignar'),('vetado'),('descartado'),('capital_invalido'),('siguiente_invalida'),('forjado');
insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,moneda,creado_por)
select id,'BANCO OFICINA '||nombre,'98761'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',
  case when nombre='ajeno' then 'b2000000-0000-4000-8000-000000000002'::uuid
    when nombre='sin_asignar' then null else 'b0000000-0000-4000-8000-000000000002'::uuid end,
  1000,'PEN','b0000000-0000-4000-8000-000000000002'::uuid from oficina_casos;
update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=(select id from oficina_casos where nombre='descartado');
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
select tarea,id,'reunion','Cita normal para comprobar marca',clock_timestamp()-interval '1 minute','presencial','Banco',
  'b0000000-0000-4000-8000-000000000002' from oficina_casos where nombre='forjado';

set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;sig jsonb;
begin
  select * into c from oficina_casos where nombre='vendedor';
  sig:=jsonb_build_object('tipo','llamada','titulo','Seguimiento propuesto','vence_en',clock_timestamp()+interval '1 day');
  r:=crm.recorrido_atender_oficina_fn(c.operacion,c.id,'interesado','Visita y entrevista reales',sig,1500,'PEN','Oficina del banco');
  perform pg_temp.exigir((r->>'ok')::boolean and r->>'origen'='oficina' and r->>'operacion_id'=c.operacion::text
    and r->>'version'='1' and r->>'comando'='recorrido_atender_oficina','sobre de confirmacion que acepta el cliente');
  update oficina_casos set respuesta=r where id=c.id;
  perform pg_temp.exigir(crm.recorrido_atender_oficina_fn(c.operacion,c.id,'interesado','Visita y entrevista reales',sig,1500,'PEN','Oficina del banco')=r,'respuesta perdida devuelve el mismo resultado');
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',''Visita y entrevista reales'',%L,2000,''PEN'',''Oficina del banco'')',
    c.operacion,c.id,sig),'P0409');
  perform pg_temp.exigir((select count(*)=2 from crm.tareas where lead_id=c.id),'una visita y una siguiente accion, sin duplicar');
  perform pg_temp.exigir((select monto_estimado=1500 and moneda='PEN' and etapa='propuesta_enviada' from crm.leads where id=c.id),'capital y etapa del cierre vigente');
  -- Un replay no es contacto nuevo: se permite tras el veto sin reescribir.
  perform crm.marcar_no_contactar(c.id,'No insistir tras esta entrevista');
  perform pg_temp.exigir(crm.recorrido_atender_oficina_fn(c.operacion,c.id,'interesado','Visita y entrevista reales',sig,1500,'PEN','Oficina del banco')=r,'replay confirmado tras veto');
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1500,''PEN'')',gen_random_uuid(),c.id),'P0429');

  select * into c from oficina_casos where nombre='no_interesado';
  r:=crm.recorrido_atender_oficina_fn(c.operacion,c.id,'no_interesado','No esta interesado',null,null,null);
  update oficina_casos set respuesta=r where id=c.id;
  perform pg_temp.exigir(r->>'siguiente_id' is null,'Saltar esta vez conserva su salida sin tarea');
  perform pg_temp.exigir((select monto_estimado=1000 from crm.leads where id=c.id),'no inventar capital cuando no hay propuesta');
  select * into c from oficina_casos where nombre='capital_invalido';
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,0,''PEN'')',c.operacion,c.id),'22023');
  select * into c from oficina_casos where nombre='siguiente_invalida';
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,%L,1200,''PEN'')',
    c.operacion,c.id,jsonb_build_object('tipo','llamada','vence_en',clock_timestamp()+interval '1 day')),'P0001');
  select * into c from oficina_casos where nombre='ajeno';
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'42501');
  select * into c from oficina_casos where nombre='descartado';
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'22023');
  select * into c from oficina_casos where nombre='vetado';
  perform crm.marcar_no_contactar(c.id,'No desea mas seguimiento');
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'P0429');

  select * into c from oficina_casos where nombre='forjado';
  perform set_config('crm.recorrido_oficina',jsonb_build_object('operacion_id',c.operacion,
    'clave','recorrido_oficina:b0000000-0000-4000-8000-000000000002:'||c.operacion,
    'payload',jsonb_build_object('lead_id',c.id,'tarea_id',c.tarea))::text,true);
  r:=crm.cerrar_reunion_v3(gen_random_uuid(),c.tarea,'completada','interesado',null,'Cierre normal',null,1000,'PEN');
  update oficina_casos set respuesta=r where id=c.id;
  perform set_config('crm.recorrido_oficina','',true);
  raise notice 'PASS: oficina atomica, proxima accion, replay con capital protegido, veto y rechazos';

  perform set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
  select * into c from oficina_casos where nombre='supervisor';
  r:=crm.recorrido_atender_oficina_fn(c.operacion,c.id,'seguimiento','Atencion del supervisor',null,1400,'PEN');
  update oficina_casos set respuesta=r where id=c.id;
  perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
  select * into c from oficina_casos where nombre='gerencia';
  r:=crm.recorrido_atender_oficina_fn(c.operacion,c.id,'inicia_registro','Atencion de gerencia',null,1700,'USD');
  update oficina_casos set respuesta=r where id=c.id;
  select * into c from oficina_casos where nombre='sin_asignar';
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'22023');
  perform set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'42501');
  perform set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'42501');
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.rechaza(format('select crm.recorrido_atender_oficina_fn(%L,%L,''interesado'',null,null,1200,''PEN'')',c.operacion,c.id),'42501');
  raise notice 'PASS: vendedor propio, supervisor y gerencia; coordinacion/directorio/ajenos/sin sesion rechazados';
end $$;
reset role;
do $$
declare c record; r jsonb;
begin
  for c in select * from oficina_casos where nombre in ('vendedor','supervisor','gerencia','no_interesado') loop
    select resultado into r from private.recorrido_evaluar(array[c.id]);
    perform pg_temp.exigir((r->>'habilita_conversion')::boolean and (r#>>'{pasos,contactado}')::boolean,'visita real acredita asistencia/entrevista y contacto presencial');
    perform pg_temp.exigir((select x.gesto_oficina_id=c.operacion and x.oficina_tarea_id=t.id
      and x.registrado_en>=t.vence_en and x.ciclo_n=l.ciclo_actual
      from crm.actividad_ciclo_contexto x join crm.tareas t on t.id=x.oficina_tarea_id
      join crm.leads l on l.id=x.lead_id where x.actividad_id=(c.respuesta->>'actividad_id')::uuid),'vinculo de oficina, hora y ciclo');
    perform pg_temp.exigir((select count(*)=1 from crm.actividades where lead_id=c.id and tipo='reunion_realizada'),'una asistencia real');
    perform pg_temp.exigir((select dni is null from crm.leads where id=c.id),'la visita no exige identidad de inversion anticipada');
  end loop;
  select * into c from oficina_casos where nombre='forjado';
  perform pg_temp.exigir((select gesto_oficina_id is null from crm.actividad_ciclo_contexto
    where actividad_id=(c.respuesta->>'actividad_id')::uuid),'GUC sin recibo privado no inventa atencion oficina');
  for c in select * from oficina_casos where nombre in ('capital_invalido','siguiente_invalida','ajeno','sin_asignar','vetado','descartado') loop
    perform pg_temp.exigir(not exists(select 1 from crm.tareas where lead_id=c.id),'sin cita a medias: '||c.nombre);
    perform pg_temp.exigir(not exists(select 1 from crm.multiempresa_idempotencia where clave like 'recorrido_oficina:%:'||c.operacion),'sin recibo a medias');
    perform pg_temp.exigir(not exists(select 1 from crm.actividad_ciclo_contexto where lead_id=c.id),'sin asistencia a medias');
  end loop;
  perform pg_temp.exigir(not exists(select 1 from crm.multiempresa_idempotencia where tipo='recorrido_oficina' and resultado is null),'ningun recibo pendiente confirmado');
  perform pg_temp.exigir(private.assert_sla_nucleo() is not null,'nucleo SLA conservado');
  perform pg_temp.exigir((select modo='observacion' from crm.recorrido_control where id),'oficina no activa el guard');
  raise notice 'PASS: vinculo causal privado, fecha del servidor, transaccion integra y nucleo conservado';
end $$;
set local role anon;
select pg_temp.rechaza('select crm.recorrido_atender_oficina_fn(gen_random_uuid(),gen_random_uuid(),''interesado'')','42501');
reset role;
set local role service_role;
select pg_temp.rechaza('select crm.recorrido_atender_oficina_fn(gen_random_uuid(),gen_random_uuid(),''interesado'')','42501');
reset role;
rollback;
