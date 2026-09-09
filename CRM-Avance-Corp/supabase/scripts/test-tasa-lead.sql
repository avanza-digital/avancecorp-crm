-- Solo banco aislado con el fixture sintético de test-tasa-pendiente (run 910908).
-- Las comprobaciones y sus datos se revierten, incluidos Auth, leads y solicitudes.
\set ON_ERROR_STOP on
begin;
set local plpgsql.check_asserts=on;
set local timezone='America/Lima';
insert into auth.users(id) values ('f3000000-0000-0000-0000-000000000004') on conflict do nothing;
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni)
values ('f3000000-0000-0000-0000-000000000004','QA OTRO ANALISTA','comercial','DNI','70000094') on conflict do nothing;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo,creado_por)
values ('f3000000-0000-0000-0000-000000000004','vendedor','f3000000-0000-0000-0000-000000000003',true,'f3000000-0000-0000-0000-000000000002') on conflict do nothing;
update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
values ('d7090000-0000-4000-8000-000000000001','QA TASA LEAD UNO','+51999009001','70909001','otro',20000,'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001'),
 ('d7090000-0000-4000-8000-000000000002','QA TASA LEAD DOS','+51999009002','70909002','otro',20000,'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001');
update public.perfiles set telefono='+51999009999',correo='qa-analista-tasa@example.invalid' where id='f3000000-0000-0000-0000-000000000001';
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
select coalesce(max(version),0)+1,clock_timestamp()-interval '1 hour',15,50,7,'enforcement' from crm.politica_rentabilidad;

create function pg_temp.actor(p_id text) returns void language sql as $$
 select set_config('request.jwt.claims',jsonb_build_object('sub',p_id,'role','authenticated')::text,true);
$$;
create function pg_temp.intencion(p_tasa numeric default 18) returns jsonb language sql as $$
 select jsonb_build_object('categoria','nuevo','contrato_origen_id',null,'producto_condicion_id',null,
   'capital',20000,'moneda','PEN','modalidad','mensual','tipo_interes','simple',
   'fecha_inicio','2026-09-15','fecha_vencimiento','2027-09-15','tasa_anual',p_tasa);
$$;
create function pg_temp.solicitar(p_lead uuid default 'd7090000-0000-4000-8000-000000000001') returns uuid language plpgsql as $$
begin
 return (crm.solicitar_tasa_fn(pg_temp.intencion()||jsonb_build_object('lead_id',p_lead,'tasa_solicitada',18,'motivo','Negociación sintética de prueba local'))->>'id')::uuid;
end;
$$;

do $prueba$
declare
 v_lead uuid:='d7090000-0000-4000-8000-000000000001'; v_s uuid; v_res jsonb; v_i jsonb;
 v_perfil uuid:='d7090000-0000-4000-8000-000000000003'; v_saga jsonb;
 v_antes bigint; v_identidades bigint; v_modo boolean; v_otra uuid;
begin
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 v_res:=crm.resolver_tasa_lead_fn(v_lead);
 assert (v_res->>'tasa_base')::numeric=15 and (v_res->>'cliente_id') is null,'resuelve base sin crear cliente';
 select count(*) into v_antes from public.perfiles;
 v_s:=pg_temp.solicitar();
 assert (select cliente_id is null and lead_id=v_lead from crm.solicitudes_tasa where id=v_s),'solicitud previa a cliente';
 assert (select count(*) from public.perfiles)=v_antes,'solicitar creó un perfil';
 assert exists(select 1 from jsonb_array_elements(crm.solicitudes_tasa_lead_fn(v_lead)) x where (x->>'id')::uuid=v_s and x->>'cliente_nombre'='QA TASA LEAD UNO');
 raise notice 'PASS: tasa central, solicitud y lectura con nombre, sin cliente artificial';

 -- Las dos ramas de identidad se frenan antes de reserva, claim o Auth.
 foreach v_modo in array array[false,true] loop
   update crm.multiempresa_flags set activo=v_modo where nombre='resolver_en_puertas';
   select count(*) into v_identidades from crm.inversionistas;
   begin
     if v_modo then
       perform crm.reservar_conversion_lead(v_lead,'DNI','70909001',jsonb_build_object('condiciones_tasa',pg_temp.intencion(15)));
     else
       perform crm.reservar_conversion_lead_tasa_fn(v_lead,pg_temp.intencion(15));
     end if;
     raise exception 'FAIL: convirtió a la base con solicitud pendiente';
   exception when sqlstate 'P0411' then null; end;
   assert not exists(select 1 from crm.conversion_reservas where lead_id=v_lead),'reserva parcial';
   assert (select count(*) from crm.inversionistas)=v_identidades,'identidad parcial';
 end loop;
 begin
   perform pg_temp.solicitar(); raise exception 'FAIL: segunda pendiente';
 exception when sqlstate 'P0411' then null; end;
 raise notice 'PASS: pendiente bloquea ambas reservas y segunda solicitud, cero efectos parciales';

 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 assert exists(select 1 from jsonb_array_elements(crm.solicitudes_tasa_fn()) x where (x->>'id')::uuid=v_s and x->>'puede_resolver'='true');
 perform crm.resolver_solicitud_tasa_fn(v_s,'aprobar_hasta',17,'Prueba de tope');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 begin
   perform private.validar_tasa_conversion_lead(v_lead,null,pg_temp.intencion(17)); raise exception 'FAIL: tope sin aceptar';
 exception when sqlstate 'P0410' then null; end;
 perform crm.responder_tope_tasa_fn(v_s,true);
 perform private.validar_tasa_conversion_lead(v_lead,null,pg_temp.intencion(17));
 foreach v_i in array array[
   pg_temp.intencion(18),
   pg_temp.intencion(17)||'{"capital":30000}'::jsonb,
   pg_temp.intencion(17)||'{"fecha_inicio":"2026-09-16"}'::jsonb,
   pg_temp.intencion(17)||'{"moneda":"USD"}'::jsonb,
   pg_temp.intencion(17)||'{"modalidad":"anual"}'::jsonb
 ] loop
   begin
     perform private.validar_tasa_conversion_lead(v_lead,null,v_i); raise exception 'FAIL: aprobación usada fuera de sus condiciones';
   exception when sqlstate 'P0410' then null; end;
 end loop;
 raise notice 'PASS: tope exige aceptación, máximo y huella exacta (capital, fecha, moneda y modalidad)';

 update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
 update crm.leads set dni='70909011' where id=v_lead;
 begin
   perform private.validar_tasa_conversion_lead(v_lead,null,pg_temp.intencion(17));
   raise exception 'FAIL: reutilizó aprobación después de cambiar documento';
 exception when sqlstate 'P0409' then null; end;
 update crm.leads set dni='70909001' where id=v_lead;
 update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
 raise notice 'PASS: la aprobación no cambia de persona al editar el documento';

 -- Reserva F4 real y sellado previo a Auth (el alta se simula después del sello, como la edge).
 v_saga:=crm.reservar_conversion_lead(v_lead,'DNI','70909001',jsonb_build_object(
   'correo','qa-tasa-lead@example.invalid','nombre_completo','QA TASA LEAD UNO','domicilio','Calle QA 123',
   'condiciones_tasa',pg_temp.intencion(17)));
 perform crm.marcar_efectos_conversion(v_lead,(v_saga->>'claim_id')::uuid,v_saga->>'token');
 begin
   perform pg_temp.solicitar(); raise exception 'FAIL: solicitud nueva entre sellado y Auth';
 exception when sqlstate 'P0409' then null; end;
 begin
   perform crm.reservar_conversion_lead(v_lead,'DNI','70909001',jsonb_build_object('condiciones_tasa',pg_temp.intencion(15)));
   raise exception 'FAIL: sustituyó intención sellada';
 exception when sqlstate 'P0409' then null; end;
 insert into auth.users(id) values(v_perfil);
 insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id,domicilio,correo)
 values(v_perfil,'QA TASA LEAD UNO','cliente','DNI','70909001','f3000000-0000-0000-0000-000000000001','Calle QA 123','qa-tasa-lead@example.invalid');
 v_res:=crm.convertir_lead(v_lead,v_perfil);
 assert (select cliente_id=v_perfil and lead_id=v_lead and estado='aceptada_por_analista' and consumida_en is null and huella_preconversion is not null from crm.solicitudes_tasa where id=v_s),'no enlazó o consumió prematuramente';
 perform crm.convertir_lead(v_lead,v_perfil);
 assert (select count(*) from crm.solicitudes_tasa where id=v_s)=1,'reintento duplicó solicitud';
 raise notice 'PASS: reserva sellada inmutable, enlaza misma solicitud y reintento idempotente sin consumir';

 -- R4 consume exactamente la autorización enlazada, una única vez.
 v_res:=crm.crear_contrato_con_cuenta_pdf_v2(pg_temp.intencion(17)||jsonb_build_object('cliente_id',v_perfil,'numero_contrato','QA-TASA-LEAD-'||gen_random_uuid()),
   jsonb_build_array(jsonb_build_object('numero_cuota',1,'fecha_programada','2026-10-15','monto_programado',283.33,'tipo','cuota'),
     jsonb_build_object('numero_cuota',2,'fecha_programada','2027-09-15','monto_programado',20000,'tipo','retorno')),
   jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','QA70909001','cci',('004'||lpad('70909001',17,'0')),'titular_distinto',false));
 set constraints all immediate;
 assert (select estado='consumida' and contrato_id=(v_res->>'id')::uuid from crm.solicitudes_tasa where id=v_s),'no consumió al crear contrato';
 assert private.rentabilidad_consumir_autorizacion((select c from public.contratos c where id=(v_res->>'id')::uuid),15,null,null,clock_timestamp()) is null,'reutilizó autorización';
 raise notice 'PASS: el contrato consume la autorización enlazada una sola vez';

 -- Un cliente reconocido conserva el bloqueo aunque su petición no naciera en el lead.
 insert into auth.users(id) values('d7090000-0000-4000-8000-000000000004');
 insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id)
 values('d7090000-0000-4000-8000-000000000004','QA CLIENTE EXISTENTE','cliente','DNI','70909002','f3000000-0000-0000-0000-000000000001');
 v_otra:=(crm.solicitar_tasa_fn(pg_temp.intencion()||jsonb_build_object('cliente_id','d7090000-0000-4000-8000-000000000004',
   'tasa_solicitada',18,'motivo','Segunda inversión sintética'))->>'id')::uuid;
 assert crm.resolver_tasa_lead_fn('d7090000-0000-4000-8000-000000000002')->>'bloqueo_conversion' is not null,'la ficha ocultó el bloqueo del cliente';
 begin
   perform private.validar_tasa_conversion_lead('d7090000-0000-4000-8000-000000000002',null,pg_temp.intencion(15));
   raise exception 'FAIL: eludió pendiente de cliente desde lead';
 exception when sqlstate 'P0411' then null; end;
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 perform crm.resolver_solicitud_tasa_fn(v_otra,'rechazar',null,'Prueba terminada');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 raise notice 'PASS: cliente conocido conserva bloqueo compartido y decisión en bandeja existente';

 -- Rechazo y vencimiento conservan la opción de base.
 v_otra:=pg_temp.solicitar('d7090000-0000-4000-8000-000000000002');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 perform crm.resolver_solicitud_tasa_fn(v_otra,'rechazar',null,'Mantener base');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 perform private.validar_tasa_conversion_lead('d7090000-0000-4000-8000-000000000002',null,pg_temp.intencion(15));
 v_otra:=pg_temp.solicitar('d7090000-0000-4000-8000-000000000002');
 perform set_config('crm.solicitud_tasa_por_puerta','on',true);
 update crm.solicitudes_tasa set solicitada_en=clock_timestamp()-interval '8 days',vence_en=clock_timestamp()-interval '1 second' where id=v_otra;
 perform set_config('crm.solicitud_tasa_por_puerta','off',true);
 perform private.validar_tasa_conversion_lead('d7090000-0000-4000-8000-000000000002',null,pg_temp.intencion(15));
 raise notice 'PASS: rechazo y caducidad permiten base';
end;
$prueba$;

-- RLS con rol real API: ajeno no lee, no solicita ni enumera el lead.
do $revision$
declare
 v_lead uuid:='d7090000-0000-4000-8000-000000000003';
 v_cliente uuid:='d7090000-0000-4000-8000-000000000005';
 v_s uuid; v_res jsonb; v_antes bigint;
begin
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
 select ('d7090000-0000-4000-8000-00000000000'||n)::uuid,'QA REVISION TASA '||n,'+5199900900'||n,
   case when n=4 then null else '7090900'||n end,'otro',20000,
   'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001'
 from generate_series(3,6) n;
 select count(*) into v_antes from crm.solicitudes_tasa;
 begin
   perform pg_temp.solicitar('d7090000-0000-4000-8000-000000000004');
   raise exception 'FAIL: solicitó una aprobación sin identificar a la persona';
 exception when invalid_parameter_value then null; end;
 assert (select count(*) from crm.solicitudes_tasa)=v_antes,'petición sin DNI dejó datos';
 raise notice 'PASS: sin DNI no se envía aprobación ni se crea una solicitud parcial';

 insert into auth.users(id) values(v_cliente);
 insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id,correo)
 values(v_cliente,'QA CLIENTE YA RECONOCIDO','cliente','DNI','70909003','f3000000-0000-0000-0000-000000000001','qa-conocido-tasa@example.invalid');
 v_s:=pg_temp.solicitar(v_lead);
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 perform crm.resolver_solicitud_tasa_fn(v_s,'aprobar');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 v_res:=crm.reservar_conversion_lead(v_lead,'DNI','70909003',jsonb_build_object('condiciones_tasa',pg_temp.intencion(18)));
 assert v_res->>'estado'='ya_existia','no recorrió la rama de cliente conocido';
 perform crm.convertir_lead_con_domicilio(v_lead,v_cliente,'Calle QA existente 123');
 assert (select perfil_id=v_cliente and etapa='convertido' from crm.leads where id=v_lead),'el wrapper no convirtió';
 assert (select cliente_id=v_cliente and lead_id=v_lead and estado='aprobada' from crm.solicitudes_tasa where id=v_s),'perdió autorización de cliente conocido';
 v_res:=crm.crear_contrato_con_cuenta_pdf_v2(pg_temp.intencion(18)||jsonb_build_object('cliente_id',v_cliente,'numero_contrato','QA-TASA-CONOCIDO-'||gen_random_uuid()),
   jsonb_build_array(jsonb_build_object('numero_cuota',1,'fecha_programada','2026-10-15','monto_programado',300,'tipo','cuota'),
     jsonb_build_object('numero_cuota',2,'fecha_programada','2027-09-15','monto_programado',20000,'tipo','retorno')),
   jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','QA70909003','cci',('004'||lpad('70909003',17,'0')),'titular_distinto',false));
 set constraints all immediate;
 assert (select estado='consumida' and contrato_id=(v_res->>'id')::uuid from crm.solicitudes_tasa where id=v_s),'no consumió autorización del cliente conocido';
 raise notice 'PASS: cliente conocido, wrapper de domicilio real, enlace y consumo al contratar';

 v_s:=pg_temp.solicitar('d7090000-0000-4000-8000-000000000005');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 perform crm.resolver_solicitud_tasa_fn(v_s,'aprobar_hasta',17,'Tope antes de reasignar');
 perform set_config('crm.op_privilegiada','on',true);
 update crm.leads set vendedor_id='f3000000-0000-0000-0000-000000000004' where id='d7090000-0000-4000-8000-000000000005';
 perform set_config('crm.op_privilegiada','off',true);
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000004');
 assert exists(select 1 from jsonb_array_elements(crm.solicitudes_tasa_lead_fn('d7090000-0000-4000-8000-000000000005')) x where (x->>'id')::uuid=v_s and x->>'es_mia'='false');
 begin
   perform crm.responder_tope_tasa_fn(v_s,true); raise exception 'FAIL: el nuevo dueño suplantó al solicitante';
 exception when insufficient_privilege then null; end;
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000003');
 assert exists(select 1 from jsonb_array_elements(crm.solicitudes_tasa_fn()) x where (x->>'id')::uuid=v_s),'supervisor del ámbito no ve solicitud';
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
 assert exists(select 1 from jsonb_array_elements(crm.solicitudes_tasa_fn(array['aprobada_con_tope'],200,true)) x where (x->>'id')::uuid=v_s and x->>'puede_responder'='true'),'autor perdió respuesta en su bandeja';
 begin
   perform crm.solicitudes_tasa_lead_fn('d7090000-0000-4000-8000-000000000005'); raise exception 'FAIL: el autor conservó acceso a la ficha reasignada';
 exception when insufficient_privilege then null; end;
 perform crm.responder_tope_tasa_fn(v_s,true);
 perform private.validar_tasa_conversion_lead('d7090000-0000-4000-8000-000000000005',null,pg_temp.intencion(17));
 raise notice 'PASS: reasignación conserva respuesta del autor, ámbito del nuevo analista y lectura del supervisor';

 v_s:=pg_temp.solicitar('d7090000-0000-4000-8000-000000000006');
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 update crm.leads set activo=false where id='d7090000-0000-4000-8000-000000000006';
 assert exists(select 1 from jsonb_array_elements(crm.solicitudes_tasa_fn(array['pendiente'])) x where (x->>'id')::uuid=v_s),'Gerencia perdió pendiente de lead inactivo';
 perform crm.resolver_solicitud_tasa_fn(v_s,'rechazar',null,'Lead inactivo');
 raise notice 'PASS: Gerencia conserva y resuelve solicitudes de leads inactivos';
end;
$revision$;

set local role authenticated;
select pg_temp.actor('f3000000-0000-0000-0000-000000000004');
do $rls$
begin
 assert not exists(select 1 from crm.solicitudes_tasa where lead_id='d7090000-0000-4000-8000-000000000002');
 begin
   perform crm.solicitudes_tasa_lead_fn('d7090000-0000-4000-8000-000000000002'); raise exception 'FAIL: RPC ajena';
 exception when insufficient_privilege then null; end;
 begin
   perform pg_temp.solicitar('d7090000-0000-4000-8000-000000000002'); raise exception 'FAIL: solicitud ajena';
 exception when insufficient_privilege then null; end;
 assert not has_function_privilege('authenticated','private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)','EXECUTE');
 assert not has_function_privilege('anon','crm.solicitudes_tasa_lead_fn(uuid,text[],integer)','EXECUTE');
 assert not has_table_privilege('authenticated','crm.solicitudes_tasa','INSERT');
 assert not has_table_privilege('authenticated','crm.conversion_reservas','UPDATE');
 raise notice 'PASS: RLS y permisos de API, helpers y reservas cerrados';
end;
$rls$;
reset role;

-- La sesión propietaria sí opera; Gerencia nunca resuelve una petición propia.
set local role authenticated;
select pg_temp.actor('f3000000-0000-0000-0000-000000000002');
do $propia$
declare v_s uuid;
begin
 v_s:=pg_temp.solicitar('d7090000-0000-4000-8000-000000000002');
 begin
   perform crm.resolver_solicitud_tasa_fn(v_s,'aprobar'); raise exception 'FAIL: Gerencia se autoaprobó';
 exception when insufficient_privilege then null; end;
 assert jsonb_array_length(crm.solicitudes_tasa_lead_fn('d7090000-0000-4000-8000-000000000002'))>0;
 raise notice 'PASS: sesión API autorizada opera y la autoaprobación sigue prohibida';
end;
$propia$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{}',true);
do $sin_identidad$
begin
 begin
   perform pg_temp.solicitar('d7090000-0000-4000-8000-000000000002'); raise exception 'FAIL: sesión sin identidad solicitó';
 exception when insufficient_privilege then null; end;
 begin
   perform crm.resolver_tasa_lead_fn('d7090000-0000-4000-8000-000000000002'); raise exception 'FAIL: sesión sin identidad consultó';
 exception when insufficient_privilege then null; end;
 raise notice 'PASS: sin identidad autenticada no se puede solicitar ni consultar';
end;
$sin_identidad$;
reset role;
rollback;
