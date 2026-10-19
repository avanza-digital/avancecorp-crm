-- Oráculo con datos sintéticos, triggers normales y ROLLBACK. Solo banco.mjs local.
begin;
set local statement_timeout='120s';
set local lock_timeout='3s';
create temporary table recorrido_casos(nombre text primary key,id uuid default gen_random_uuid(),tarea uuid default gen_random_uuid());
grant select on recorrido_casos to authenticated,anon,service_role;
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $$
begin if p_ok is not true then raise exception 'RECORRIDO: %',p_mensaje;end if;end $$;
create function pg_temp.rechaza(p_sql text,p_estado text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate=p_estado then return;end if;
    raise exception 'Esperado %, obtenido % (%) en %',p_estado,sqlstate,sqlerrm,p_sql;
  end;
  raise exception 'Debio rechazar con %: %',p_estado,p_sql;
end $$;

-- Un segundo árbol sintético, sin datos de clientes ni perfiles productivos.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,raw_app_meta_data,raw_user_meta_data)
select x.id::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x.correo,'',
  now(),now(),now(),'','','','','{"provider":"email"}'::jsonb,'{}'::jsonb
from (values
  ('b1000000-0000-4000-8000-000000000001','supervisor.recorrido@example.test'),
  ('b1000000-0000-4000-8000-000000000002','analista.recorrido@example.test'),
  ('b1000000-0000-4000-8000-000000000003','coordinador.recorrido@example.test'),
  ('b1000000-0000-4000-8000-000000000004','directorio.recorrido@example.test'),
  ('b1000000-0000-4000-8000-000000000005','revocado.recorrido@example.test'),
  ('b1000000-0000-4000-8000-000000000006','inactivo.recorrido@example.test')) x(id,correo);
insert into public.perfiles(id,nombre_completo,rol,activo,tipo_documento,debe_cambiar_password,titular_distinto,titular_distinto_usd)
values ('b1000000-0000-4000-8000-000000000001','BANCO SUPERVISOR AJENO','analista',true,'DNI',false,false,false),
       ('b1000000-0000-4000-8000-000000000002','BANCO ANALISTA AJENO','analista',true,'DNI',false,false,false),
       ('b1000000-0000-4000-8000-000000000003','BANCO COORDINADOR','comercial',true,'DNI',false,false,false),
       ('b1000000-0000-4000-8000-000000000004','BANCO DIRECTORIO','directorio',true,'DNI',false,false,false),
       ('b1000000-0000-4000-8000-000000000005','BANCO CRM REVOCADO','comercial',true,'DNI',false,false,false),
       ('b1000000-0000-4000-8000-000000000006','BANCO PERFIL INACTIVO','comercial',true,'DNI',false,false,false);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
values ('b1000000-0000-4000-8000-000000000001','supervisor',null,true);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
values ('b1000000-0000-4000-8000-000000000002','vendedor','b1000000-0000-4000-8000-000000000001',true);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
values ('b1000000-0000-4000-8000-000000000003','coordinador',null,true),
       ('b1000000-0000-4000-8000-000000000005','vendedor','b1000000-0000-4000-8000-000000000001',false),
       ('b1000000-0000-4000-8000-000000000006','vendedor','b1000000-0000-4000-8000-000000000001',true);
update public.perfiles set activo=false where id='b1000000-0000-4000-8000-000000000006';
insert into recorrido_casos(nombre) values ('vacio'),('completo'),('futuro'),('inasistencia'),('cancelada'),
  ('reapertura'),('ajeno'),('sin_clasificar'),('historia'),('borrado'),('sin_asignar');
insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,moneda,creado_por)
select id,'BANCO RECORRIDO '||nombre,'98760'||lpad(row_number() over(order by nombre)::text,4,'0'),'landing',
  case when nombre='ajeno' then 'b1000000-0000-4000-8000-000000000002'::uuid
    when nombre='sin_asignar' then null else 'b0000000-0000-4000-8000-000000000002'::uuid end,
  1000,'PEN','b0000000-0000-4000-8000-000000000002'::uuid from recorrido_casos;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
select tarea,id,'reunion','Cita sintetica',clock_timestamp()+case when nombre='futuro' then interval '1 day' else interval '-1 minute' end,
  'presencial','Oficina de prueba','b0000000-0000-4000-8000-000000000002'::uuid
from recorrido_casos where nombre in ('completo','futuro','inasistencia','cancelada','reapertura','sin_clasificar','historia','borrado');

do $$
declare c record;r jsonb; a uuid; antes timestamptz:=clock_timestamp();
begin
  perform pg_temp.exigir(private.assert_sla_nucleo() is not null,'se altero el nucleo SLA');
  perform pg_temp.exigir((select modo='observacion' and cohorte_desde is null from crm.recorrido_control where id),'modo inicial');
  select * into c from recorrido_casos where nombre='vacio';
  insert into crm.actividades(lead_id,tipo,detalle,creado_en,metadata)
    values(c.id,'llamada_no_contestada','Writer interno con fecha antigua',now()-interval '10 days',
      '{"recorrido":{"ciclo_n":999,"gesto_oficina_id":"forjado"}}') returning id into a;
  perform pg_temp.exigir((select ciclo_n=1 and registrado_en>=antes and gesto_oficina_id is null
    from crm.actividad_ciclo_contexto where actividad_id=a),'el cliente no fija ciclo, hora o gesto');
  select resultado into r from private.recorrido_evaluar(array[c.id]);
  perform pg_temp.exigir((r#>>'{pasos,gestionado}')::boolean and not (r#>>'{pasos,contactado}')::boolean
    and not (r->>'habilita_conversion')::boolean,'sin respuesta no equivale a contacto ni habilita');
  perform pg_temp.rechaza(format('update crm.actividad_ciclo_contexto set ciclo_n=9 where actividad_id=%L',a),'42501');
  perform pg_temp.rechaza(format('delete from crm.actividad_ciclo_contexto where actividad_id=%L',a),'42501');
  perform pg_temp.rechaza('truncate crm.actividad_ciclo_contexto','42501');
  perform pg_temp.rechaza('truncate crm.recorrido_control','42501');
  perform set_config('crm.recorrido_contexto_writer','on',true);
  perform pg_temp.rechaza(format('insert into crm.actividad_ciclo_contexto select * from crm.actividad_ciclo_contexto where actividad_id=%L',a),'42501');
  perform set_config('crm.recorrido_contexto_writer','off',true);
  raise notice 'PASS: contexto causal inmutable, reloj del servidor y metadata falsificada sin efecto';

  perform set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
  for c in select * from recorrido_casos where nombre in ('completo','futuro','reapertura','borrado','historia') loop
    r:=crm.cerrar_reunion_v3(gen_random_uuid(),c.tarea,'completada','interesado',null,'Entrevista sintetica',null,1000,'PEN');
    perform pg_temp.exigir((r->>'ok')::boolean,'cierre actual no confirmado');
  end loop;
  select * into c from recorrido_casos where nombre='inasistencia';
  perform crm.cerrar_reunion_v3(gen_random_uuid(),c.tarea,'no_show',null,'cliente_no_asistio','No asistio',null,null,null);
  select * into c from recorrido_casos where nombre='cancelada';
  perform crm.cerrar_reunion_v3(gen_random_uuid(),c.tarea,'cancelada',null,'cancelada_cliente','Cancelo',null,null,null);
  select * into c from recorrido_casos where nombre='sin_clasificar';
  -- La puerta vigente ya rechaza ese resultado. La forma histórica existe en
  -- la tabla y se prepara como fixture privilegiado, con TODOS sus triggers.
  perform pg_temp.rechaza(format('select crm.cerrar_reunion_v2(%L,%L,''completada'',''sin_clasificar'',null,''Cierre antiguo'',null)',
    gen_random_uuid(),c.tarea),'22023');
  perform set_config('request.jwt.claim.sub','',true);
  insert into crm.actividades(lead_id,tipo,metadata,creado_por)
    values(c.id,'reunion_realizada',jsonb_build_object('tarea_id',c.tarea),'b0000000-0000-4000-8000-000000000002') returning id into a;
  perform set_config('crm.op_tarea','on',true);
  update crm.tareas set estado='completada',resultado_actividad_id=a,resultado_reunion='sin_clasificar' where id=c.tarea;
  perform set_config('crm.op_tarea','off',true);

  select resultado into r from private.recorrido_evaluar(array[(select id from recorrido_casos where nombre='completo')]);
  perform pg_temp.exigir((r->>'habilita_conversion')::boolean and not (r#>>'{pasos,contactado}')::boolean,
    'asistencia y entrevista validas deben habilitar SIN llamada/contacto previo separado');
  perform pg_temp.exigir((r#>>'{pasos,asistencia}')::boolean and (r#>>'{pasos,entrevista}')::boolean,'ambos requisitos');
  for c in select * from recorrido_casos where nombre in ('vacio','futuro','inasistencia','cancelada','sin_clasificar') loop
    select resultado into r from private.recorrido_evaluar(array[c.id]);
    perform pg_temp.exigir(not (r->>'habilita_conversion')::boolean,'caso no habilitable: '||c.nombre);
  end loop;
  raise notice 'PASS: asistencia+entrevista vinculadas, sin contacto adicional; futura, no_show, cancelada y sin resultado no habilitan';
  perform set_config('request.jwt.claim.sub','',true);
end $$;

-- Foto histórica anterior a la migración: una cita ya cerrada aún no tenía
-- la relación nueva. Solo prepara ese dato de prueba; no cambia funciones.
set local session_replication_role=replica;
delete from crm.actividad_ciclo_contexto where lead_id=(select id from recorrido_casos where nombre='historia');
set local session_replication_role=origin;
do $$
declare c record;r jsonb;v_dormido uuid:=gen_random_uuid();v_intento uuid:=gen_random_uuid();v_ciclo integer;
begin
  select resultado into r from private.recorrido_evaluar(array[(select id from recorrido_casos where nombre='historia')]);
  perform pg_temp.exigir(r->>'estado'='ambiguo' and not (r->>'habilita_conversion')::boolean,'historia no se acredita por fechas inventadas');
  select * into c from recorrido_casos where nombre='reapertura';
  select ciclo_actual into v_ciclo from crm.leads where id=c.id;
  perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
  update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=c.id;
  perform crm.reabrir_lead_fn(c.id);
  perform pg_temp.exigir((select ciclo_actual=v_ciclo+1 from crm.leads where id=c.id),'reapertura inicia ciclo');
  select resultado into r from private.recorrido_evaluar(array[c.id]);
  perform pg_temp.exigir(not (r->>'habilita_conversion')::boolean,'cita anterior no acredita reapertura');
  select * into c from recorrido_casos where nombre='completo';
  select ciclo_actual into v_ciclo from crm.leads where id=c.id;
  update crm.leads set vendedor_id='b1000000-0000-4000-8000-000000000002' where id=c.id;
  select resultado into r from private.recorrido_evaluar(array[c.id]);
  perform pg_temp.exigir((r->>'habilita_conversion')::boolean and (r->>'ciclo_n')::integer=v_ciclo,'reasignar conserva evidencia');
  update crm.leads set vendedor_id='b0000000-0000-4000-8000-000000000002' where id=c.id;

  -- Base que nace dormida por el writer reservado de importación.
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('crm.op_bases_carga','on',true);
  insert into crm.leads(id,nombre_completo,telefono,origen,etapa,motivo_descarte,vendedor_id,monto_estimado,moneda,creado_por)
    values(v_dormido,'BANCO DORMIDO RECORRIDO','987699990','base_cargada','descartado','base_cargada',
      'b0000000-0000-4000-8000-000000000002',null,'PEN','b0000000-0000-4000-8000-000000000002');
  perform set_config('crm.op_bases_carga','off',true);
  perform pg_temp.exigir(not exists(select 1 from crm.lead_sla_ciclos where lead_id=v_dormido),'base dormida sin ciclo');
  perform set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
  r:=crm.registrar_intento_base_v2(v_intento,v_dormido,'no_contesto','Intento sin activar la base',null,null,null);
  perform pg_temp.exigir((r->>'ok')::boolean and (select ciclo_n is null and estado_ciclo='base_sin_ciclo'
    from crm.actividad_ciclo_contexto where actividad_id=v_intento),'no contesto se guarda sin inventar ciclo');
  v_intento:=gen_random_uuid();
  r:=crm.registrar_intento_base_v2(v_intento,v_dormido,'agendo_reunion','Contacto antes de reactivacion',null,1000,'PEN');
  perform pg_temp.exigir((r->>'reactivado')::boolean,'agendar desde base sigue reactivando');
  perform pg_temp.exigir((select ciclo_n is null from crm.actividad_ciclo_contexto where actividad_id=v_intento),'no reescribir el ciclo del intento previo');
  select resultado into r from private.recorrido_evaluar(array[v_dormido]);
  perform pg_temp.exigir(not (r->>'habilita_conversion')::boolean,'reactivar no simula entrevista');
  perform set_config('request.jwt.claim.sub','',true);
  raise notice 'PASS: historia ambigua, reapertura, reasignacion y llamadas/activacion de base dormida';
end $$;

-- Comprobación con el rol API real: no se usa el bypass del propietario para RLS.
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare r jsonb;ids uuid[];
begin
  select array_agg(id) into ids from recorrido_casos;
  r:=crm.recorrido_leads_fn(ids);
  perform pg_temp.exigir(jsonb_array_length(r->'filas')=9,'vendedor no debe leer ajeno ni sin asignar');
  perform pg_temp.exigir(r->>'modo'='observacion','lectura del modo');
  perform pg_temp.exigir(not exists(select 1 from jsonb_array_elements(r->'filas') f where (f->>'exigible')::boolean),'observacion no exige');
  perform pg_temp.exigir(crm.recorrido_leads_fn('{}'::uuid[])->'filas'='[]'::jsonb,'lote vacio');
  perform pg_temp.rechaza('select crm.recorrido_leads_fn(null::uuid[])','22023');
  perform pg_temp.rechaza('select crm.recorrido_leads_fn(array[null]::uuid[])','22023');
  perform pg_temp.rechaza('select crm.recorrido_leads_fn(array(select gen_random_uuid() from generate_series(1,101)))','22023');
  perform pg_temp.rechaza('select * from crm.actividad_ciclo_contexto','42501');
  perform pg_temp.rechaza('select * from crm.recorrido_control','42501');
  perform pg_temp.rechaza('select * from private.recorrido_evaluar(array[]::uuid[])','42501');
  perform pg_temp.rechaza('select crm.recorrido_configurar_fn(''exigir'',''Intento vendedor'',1)','42501');
  perform set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
  perform pg_temp.exigir(jsonb_array_length(crm.recorrido_leads_fn(ids)->'filas')=9,'supervisor ve solo su arbol');
  perform set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
  perform pg_temp.exigir(jsonb_array_length(crm.recorrido_leads_fn(ids)->'filas')=1,'analista del otro arbol');
  perform set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000003',true);
  perform pg_temp.exigir(jsonb_array_length(crm.recorrido_leads_fn(ids)->'filas')=11,'coordinacion conserva lectura global');
  perform pg_temp.rechaza('select crm.recorrido_configurar_fn(''exigir'',''Intento coordinacion'',1)','42501');
  perform set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000004',true);
  perform pg_temp.exigir(jsonb_array_length(crm.recorrido_leads_fn(ids)->'filas')=11,'directorio conserva lectura global');
  perform pg_temp.rechaza('select crm.recorrido_configurar_fn(''exigir'',''Intento directorio'',1)','42501');
  perform set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000005',true);
  perform pg_temp.rechaza('select crm.recorrido_leads_fn(array[]::uuid[])','42501');
  perform set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000006',true);
  perform pg_temp.rechaza('select crm.recorrido_leads_fn(array[]::uuid[])','42501');
  perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
  perform pg_temp.exigir(jsonb_array_length(crm.recorrido_leads_fn(ids)->'filas')=11,'gerencia ve todos los activos');
  perform pg_temp.rechaza('select crm.recorrido_configurar_fn(''exigir'',''Corte retroactivo'',1,now()-interval ''1 day'')','22023');
  r:=crm.recorrido_configurar_fn('exigir','Ensayo aislado de nuevos ciclos',1);
  perform pg_temp.exigir(r->>'modo'='exigir' and r->>'cohorte_desde' is not null,'exigencia con corte del servidor');
  perform pg_temp.rechaza('select crm.recorrido_configurar_fn(''apagado'',''Revision obsoleta'',1)','40001');
  perform pg_temp.rechaza('select crm.recorrido_configurar_fn(''apagado'',''Cambiar corte anterior'',2,clock_timestamp()+interval ''1 day'')','22023');
  perform pg_temp.exigir(crm.recorrido_configurar_fn('apagado','Reversion de la regla nueva',2)->>'cohorte_desde'=r->>'cohorte_desde','apagar conserva cohorte');
  perform pg_temp.exigir(crm.recorrido_configurar_fn('observacion','Volver al modo de observacion',3)->>'cohorte_desde'=r->>'cohorte_desde','observacion conserva cohorte');
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.rechaza('select crm.recorrido_leads_fn(array[]::uuid[])','42501');
  raise notice 'PASS: roles por arbol, puerta privada cerrada, lotes, modo, revision y cohorte inmutable';
end $$;
reset role;
set local role anon;
select pg_temp.rechaza('select crm.recorrido_leads_fn(array[]::uuid[])','42501');
reset role;
set local role service_role;
select pg_temp.rechaza('select crm.recorrido_leads_fn(array[]::uuid[])','42501');
select pg_temp.rechaza('select * from crm.recorrido_control','42501');
reset role;

-- Una sentencia posterior al corte crea un ciclo realmente nuevo. No se
-- altera iniciado_en ni el reloj del servidor para obtener el resultado.
select set_config('request.jwt.claim.sub','',true);
insert into recorrido_casos(nombre) values ('corte_nuevo');
insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,moneda,creado_por)
select id,'BANCO COHORTE NUEVA','987699980','landing','b0000000-0000-4000-8000-000000000002',
  1000,'PEN','b0000000-0000-4000-8000-000000000002' from recorrido_casos where nombre='corte_nuevo';
set local role authenticated;
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
do $$
declare r jsonb; ids uuid[];
begin
  select array_agg(id) into ids from recorrido_casos where nombre in ('vacio','corte_nuevo');
  perform crm.recorrido_configurar_fn('exigir','Reactivar con el mismo corte',4);
  r:=crm.recorrido_leads_fn(ids);
  perform pg_temp.exigir((select (f->>'exigible')::boolean from jsonb_array_elements(r->'filas') f
    where f->>'lead_id'=(select id::text from recorrido_casos where nombre='corte_nuevo')),'nuevo ciclo incluido');
  perform pg_temp.exigir((select not (f->>'exigible')::boolean from jsonb_array_elements(r->'filas') f
    where f->>'lead_id'=(select id::text from recorrido_casos where nombre='vacio')),'ciclo antiguo no bloqueado retroactivamente');
  perform crm.recorrido_configurar_fn('apagado','Reversion tras verificar el corte',5);
  r:=crm.recorrido_leads_fn(ids);
  perform pg_temp.exigir(not exists(select 1 from jsonb_array_elements(r->'filas') f
    where (f->>'exigible')::boolean),'apagado revierte exigencia para toda cohorte');
  perform set_config('request.jwt.claim.sub','',true);
  raise notice 'PASS: cohorte nueva, exclusion de antiguos y reversion sin cambiar el corte';
end $$;
reset role;

do $$
declare c record;r jsonb; v_copia uuid;
begin
  perform set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
  select * into c from recorrido_casos where nombre='borrado';
  r:=crm.eliminar_lead_error_carga(c.id,'Lead sintetico cargado por error en prueba');
  v_copia:=(r->>'copia_id')::uuid;
  perform pg_temp.exigir(not exists(select 1 from crm.leads where id=c.id),'borrado oficial del lead');
  perform pg_temp.exigir(not exists(select 1 from crm.actividad_ciclo_contexto where lead_id=c.id),'contexto eliminado por puerta');
  perform pg_temp.exigir((select jsonb_array_length(e.copia->'actividad_ciclo_contexto')>0
    and e.copia->>'version'='3' from crm.leads_eliminados e where e.id=v_copia),'copia conserva contexto causal');
  select * into c from recorrido_casos where nombre='sin_asignar';
  perform crm.eliminar_lead_error_carga(c.id,'Registro sin evidencia cargado por error');
  perform pg_temp.exigir(not exists(select 1 from crm.leads where id=c.id),'borrado sin contexto tambien funciona');
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.exigir(private.assert_sla_nucleo() is not null,'guardian SLA al finalizar');
  raise notice 'PASS: eliminacion auditada con y sin contexto, copia v3 y nucleo SLA intacto';
end $$;
rollback;
