-- SOLO copia local con siembra F3 910908. Se revierte todo el ensayo.
\set ON_ERROR_STOP on
begin;
set local plpgsql.check_asserts=on;
set local timezone='America/Lima';
update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');
create function pg_temp.actor(p_id text default 'f3000000-0000-0000-0000-000000000001') returns void language sql as $$
 select set_config('request.jwt.claims',jsonb_build_object('sub',p_id,'role','authenticated')::text,true);
$$;
create function pg_temp.modo(p_modo text,p_tope numeric default 28) returns void language plpgsql as $$
begin
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 perform crm.publicar_politica_rentabilidad_fn((select max(version) from crm.politica_rentabilidad),
   jsonb_build_object('tasa_base_nueva',15,'tope_tecnico',p_tope,'vigencia_solicitud_dias',1,'modo',p_modo,'nota','Ensayo local del interruptor integral'));
 perform pg_temp.actor();
end;
$$;
create function pg_temp.intencion(p_tasa numeric) returns jsonb language sql as $$
 select jsonb_build_object('categoria','nuevo','capital',20000,'moneda','PEN','modalidad','mensual','tipo_interes','simple',
 'fecha_inicio','2026-10-15','fecha_vencimiento','2027-10-15','tasa_anual',p_tasa);
$$;
create function pg_temp.alta(p_tasa numeric,p_cliente uuid default 'f3a00000-0000-0000-0000-910908000001',p_categoria text default 'nuevo',p_origen uuid default null)
returns uuid language plpgsql as $$
declare v_res jsonb;
begin
 set constraints all deferred;
 v_res:=crm.crear_contrato_con_cuenta_pdf_v2(pg_temp.intencion(p_tasa)||jsonb_build_object(
   'cliente_id',p_cliente,'numero_contrato','QA-MODO-'||gen_random_uuid(),'categoria',p_categoria,'contrato_origen_id',p_origen),
   jsonb_build_array(jsonb_build_object('numero_cuota',1,'fecha_programada','2026-11-15','monto_programado',round(20000*p_tasa/100/12,2),'tipo','cuota'),
     jsonb_build_object('numero_cuota',2,'fecha_programada','2027-10-15','monto_programado',20000,'tipo','retorno')),
   jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','QA'||substr(gen_random_uuid()::text,1,8),
     'cci','004'||lpad(abs(hashtext(gen_random_uuid()::text)::bigint)::text,17,'0'),'titular_distinto',false));
 set constraints all immediate;
 return (v_res->>'id')::uuid;
end;
$$;
select pg_temp.actor();
insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
values ('d7180000-0000-4000-8000-000000000001','QA MODO OBSERVACION','+51999018001','71809001','otro',20000,
 'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001');
create temporary table qa_modo(clave text primary key,id uuid);
grant all on qa_modo to authenticated;

select pg_temp.modo('enforcement');
set local role authenticated;
select pg_temp.actor();
do $pendientes$
begin
 insert into qa_modo values ('solicitud_cliente',(crm.solicitar_tasa_fn(pg_temp.intencion(20)||jsonb_build_object(
 'cliente_id','f3a00000-0000-0000-0000-910908000001','tasa_solicitada',20,'motivo','Prueba aislada de solicitud existente'))->>'id')::uuid);
 insert into qa_modo values ('solicitud_lead',(crm.solicitar_tasa_fn(pg_temp.intencion(20)||jsonb_build_object(
 'lead_id','d7180000-0000-4000-8000-000000000001','tasa_solicitada',20,'motivo','Prueba aislada de solicitud del lead'))->>'id')::uuid);
 begin
   perform pg_temp.alta(15);
   raise exception 'FAIL: enforcement permitió contrato con pendiente';
 exception when sqlstate 'P0411' then null; end;
 begin
   perform crm.reservar_conversion_lead_tasa_fn('d7180000-0000-4000-8000-000000000001',pg_temp.intencion(20));
   raise exception 'FAIL: enforcement permitió convertir con pendiente';
 exception when sqlstate 'P0411' then null; end;
 raise notice 'PASS: candado activo bloquea contrato y conversión con solicitud pendiente';
end;
$pendientes$;
reset role;
select pg_temp.modo('observacion');
set local role authenticated;
select pg_temp.actor();
do $observacion$
declare v_tasa numeric; v_id uuid; v_res jsonb;
begin
 v_res:=crm.resolver_tasa_lead_fn('d7180000-0000-4000-8000-000000000001');
 assert v_res->'politica'->>'modo'='observacion' and (v_res->>'observacion_sin_aprobacion')::boolean;
 assert v_res->>'bloqueo_conversion' is null,'pendiente aún bloquea el lector';
 assert (crm.politica_rentabilidad_fn()->>'observacion_sin_aprobacion')::boolean,'correcciones no leen la capacidad';
 foreach v_tasa in array array[0.01,12.5,15,20,28]::numeric[] loop
   v_id:=pg_temp.alta(v_tasa);
   assert (select tasa_anual=v_tasa from public.contratos where id=v_id),'alteró la tasa elegida';
   insert into qa_modo values('alta_'||v_tasa::text,v_id);
 end loop;
 perform crm.reservar_conversion_lead_tasa_fn('d7180000-0000-4000-8000-000000000001',pg_temp.intencion(20));
 begin
   perform crm.solicitar_tasa_fn(pg_temp.intencion(22)||jsonb_build_object('cliente_id','f3a00000-0000-0000-0000-910908000001','tasa_solicitada',22,'motivo','No debe generar otra solicitud'));
   raise exception 'FAIL: creó solicitud innecesaria';
 exception when sqlstate 'P0410' then assert sqlerrm like '%observación%',sqlerrm; end;
 begin
   perform pg_temp.alta(28.01);
   raise exception 'FAIL: superó tope';
 exception when sqlstate 'P0410' then null; end;
 begin
   perform pg_temp.alta(12.345);
   raise exception 'FAIL: guardó más de dos decimales';
 exception when sqlstate '22023' then null; end;
 raise notice 'PASS: observación acepta cinco tasas, pendiente no bloquea alta/reserva, conserva tope y decimales y evita nuevas solicitudes';
end;
$observacion$;
reset role;
do $traza$
declare v_id uuid; v_tasa numeric;
begin
 assert (select count(*)=2 from crm.solicitudes_tasa where id in (select id from qa_modo where clave like 'solicitud_%') and estado='pendiente' and contrato_id is null),'alteró historial de solicitudes';
 assert (select count(*)=5 from crm.ledger_rentabilidad where contrato_id in (select id from qa_modo where clave like 'alta_%') and origen='observacion' and solicitud_id is null),'no auditó sin consumir aprobaciones';
 foreach v_tasa in array array[0,-1,28.01,12.345,'NaN'::numeric,'Infinity'::numeric] loop
   begin
     perform private.validar_tasa_conversion_lead('d7180000-0000-4000-8000-000000000001',null,pg_temp.intencion(v_tasa));
     raise exception 'FAIL: validó tasa inválida en conversión %',v_tasa;
   exception when sqlstate 'P0410' then null; end;
 end loop;
 perform private.enlazar_tasa_lead('d7180000-0000-4000-8000-000000000001','f3a00000-0000-0000-0000-910908000001');
 assert (select cliente_id is null from crm.solicitudes_tasa where id=(select id from qa_modo where clave='solicitud_lead')),'enlazó autorización ajena a la nueva operación';
 select id into v_id from qa_modo where clave='alta_20';
 begin
   update public.contratos set tasa_anual=21 where id=v_id;
   set constraints all immediate;
   raise exception 'FAIL: rompió inmutabilidad del PDF';
 exception when sqlstate '55000' then null; end;
 raise notice 'PASS: ledger, historial, identidad de solicitudes y PDF conservados; validación de conversión mantiene límites';
end;
$traza$;
select pg_temp.modo('enforcement');
set local role authenticated;
select pg_temp.actor();
do $reactivacion$
begin
 begin
   perform pg_temp.alta(20); raise exception 'FAIL: reactivar no bloqueó la operación pendiente';
 exception when sqlstate 'P0411' then null; end;
 begin
   perform crm.reservar_conversion_lead_tasa_fn('d7180000-0000-4000-8000-000000000001',pg_temp.intencion(20));
   raise exception 'FAIL: reactivar no bloqueó la conversión pendiente';
 exception when sqlstate 'P0411' then null; end;
 raise notice 'PASS: el mismo botón vuelve a activar las dos barreras';
end;
$reactivacion$;
reset role;
-- Publicar el modo en otra sentencia: su vigencia se decide por statement_timestamp.
-- Este ensayo no simula un cambio que aún no era efectivo al inicio del DO.
update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
do $preparar_aprobacion$
declare v_lead uuid:='d7180000-0000-4000-8000-000000000002'; v_s uuid;
begin
 perform pg_temp.actor();
 insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
 values(v_lead,'QA APROBACION EN TRANSICION','+51999018002','71809002','otro',20000,
 'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001');
 v_s:=(crm.solicitar_tasa_fn(pg_temp.intencion(20)||jsonb_build_object('lead_id',v_lead,'tasa_solicitada',20,'motivo','Aprobación previa al apagado'))->>'id')::uuid;
 insert into qa_modo values('aprobacion_transicion',v_s);
 perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
 perform crm.resolver_solicitud_tasa_fn(v_s,'aprobar');
end;
$preparar_aprobacion$;
select pg_temp.modo('observacion');
do $conversion_observacion$
declare v_lead uuid:='d7180000-0000-4000-8000-000000000002';
 v_cliente uuid:='d7180000-0000-4000-8000-000000000003';
begin
 assert (private.politica_rentabilidad_vigente(statement_timestamp())).modo='observacion';
 insert into auth.users(id) values(v_cliente);
 insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id,correo)
 values(v_cliente,'QA CLIENTE TRANSICION','cliente','DNI','71809002','f3000000-0000-0000-0000-000000000001','qa-transicion@example.invalid');
 perform crm.reservar_conversion_lead(v_lead,'DNI','71809002',jsonb_build_object('condiciones_tasa',pg_temp.intencion(20)));
 perform crm.convertir_lead_con_domicilio(v_lead,v_cliente,'Calle QA existente 123');
 assert (select cliente_id=v_cliente and estado='aprobada' from crm.solicitudes_tasa where id=(select id from qa_modo where clave='aprobacion_transicion')),'no conservó aprobación al enlazar identidad';
 perform pg_temp.alta(20,v_cliente);
 assert (select estado='aprobada' and contrato_id is null from crm.solicitudes_tasa where id=(select id from qa_modo where clave='aprobacion_transicion')),'observación consumió una autorización que no se necesita';
end;
$conversion_observacion$;
select pg_temp.modo('enforcement');
do $contratar_despues_de_reactivar$
declare v_id uuid;
begin
 assert (private.politica_rentabilidad_vigente(statement_timestamp())).modo='enforcement';
 v_id:=pg_temp.alta(20,'d7180000-0000-4000-8000-000000000003');
 assert (select estado='consumida' and contrato_id=v_id from crm.solicitudes_tasa where id=(select id from qa_modo where clave='aprobacion_transicion')),'perdió aprobación al reactivar';
 begin
   perform pg_temp.alta(20,'d7180000-0000-4000-8000-000000000003');
   raise exception 'FAIL: reutilizó una aprobación ya consumida en enforcement';
 exception when sqlstate 'P0410' then null; end;
 raise notice 'PASS: observación no consume aprobaciones; reactivar permite un único consumo autorizado';
end;
$contratar_despues_de_reactivar$;

select pg_temp.modo('observacion',35);
with origen as (
 insert into public.contratos(cliente_id,numero_contrato,capital,moneda,tasa_anual,modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,categoria,creado_por)
 values('f3a00000-0000-0000-0000-910908000001','QA-MODO-HERENCIA',20000,'PEN',30,'mensual','simple',
 '2026-10-15','2027-10-15','nuevo','f3000000-0000-0000-0000-000000000001') returning id
) insert into qa_modo select 'origen_historico',id from origen;
set constraints all immediate;
select pg_temp.modo('observacion',28);
do $herencia_y_correccion$
declare v_origen uuid:=(select id from qa_modo where clave='origen_historico'); v_id uuid; v_cat text;
begin
 assert (private.politica_rentabilidad_vigente(statement_timestamp())).tope_tecnico=28;
 foreach v_cat in array array['renovacion','upgrade'] loop
   perform private.validar_tasa_conversion_lead('d7180000-0000-4000-8000-000000000001','f3a00000-0000-0000-0000-910908000001',
     pg_temp.intencion(30)||jsonb_build_object('categoria',v_cat,'contrato_origen_id',v_origen));
 end loop;
 v_id:=pg_temp.alta(30,'f3a00000-0000-0000-0000-910908000001','upgrade',v_origen);
 assert (select tasa_anual=30 from public.contratos where id=v_id),'no heredó tasa histórica sobre el tope nuevo';
 update public.contratos set notas_internas='Conservar tasa histórica' where id=v_origen;
 update public.contratos set tasa_anual=20 where id=v_origen;
 set constraints all immediate;
 assert (select tasa_anual=20 from public.contratos where id=v_origen),'corrección en observación no pasó';
 begin
   update public.contratos set tasa_anual=28.01 where id=v_origen;
   set constraints all immediate;
   raise exception 'FAIL: corrección superó el tope';
 exception when sqlstate 'P0410' then null; end;
 raise notice 'PASS: herencia histórica, corrección dentro del rango y límite de corrección';
end;
$herencia_y_correccion$;
-- Aislar cada defensa del enlace; mutaciones de fixture internas y reversibles.
do $defensas_enlace$
declare v_s uuid:=(select id from qa_modo where clave='solicitud_lead');
 v_lead uuid:='d7180000-0000-4000-8000-000000000001';
 v_cli uuid:='f3a00000-0000-0000-0000-910908000001';
 v_otro uuid:='d7180000-0000-4000-8000-000000000003';
 v_foto jsonb; v_dni text;
begin
 perform set_config('crm.solicitud_tasa_por_puerta','on',true);
 -- (a) otra identidad, sin documento ni intención coincidente con la pendiente del cliente.
 update crm.solicitudes_tasa set cliente_id=v_otro,documento_lead=null,capital=21000 where id=v_s;
 select to_jsonb(s) into v_foto from crm.solicitudes_tasa s where id=v_s;
 perform private.enlazar_tasa_lead(v_lead,v_cli);
 assert (select to_jsonb(s)=v_foto from crm.solicitudes_tasa s where id=v_s),'reasignó solicitud de otra identidad';
 -- (b) documento cambiado, sin cliente ni huella en conflicto.
 update crm.solicitudes_tasa set cliente_id=null,documento_lead='71809999' where id=v_s;
 select to_jsonb(s) into v_foto from crm.solicitudes_tasa s where id=v_s;
 perform private.enlazar_tasa_lead(v_lead,v_cli);
 assert (select to_jsonb(s)=v_foto from crm.solicitudes_tasa s where id=v_s),'enlazó documento desactualizado';
 -- (c) identidad/documentos correctos, conflicto exclusivo con otra solicitud viva.
 v_lead:='d7180000-0000-4000-8000-000000000002';
 v_cli:='d7180000-0000-4000-8000-000000000003';
 select dni into v_dni from public.perfiles where id=v_cli;
 assert (select dni=v_dni from crm.leads where id=v_lead);
 update crm.solicitudes_tasa set cliente_id=v_cli,huella=private.huella_intencion_tasa(v_cli,pg_temp.intencion(20))
 where id=(select id from qa_modo where clave='solicitud_cliente');
 update crm.solicitudes_tasa set lead_id=v_lead,documento_lead=v_dni,capital=20000 where id=v_s;
 select to_jsonb(s) into v_foto from crm.solicitudes_tasa s where id=v_s;
 perform private.enlazar_tasa_lead(v_lead,v_cli);
 assert (select to_jsonb(s)=v_foto from crm.solicitudes_tasa s where id=v_s),'cambió solicitud con huella conflictiva';
 -- Eliminar únicamente la causa de conflicto: la fila compatible debe enlazarse.
 update crm.solicitudes_tasa set capital=21000 where id=v_s;
 perform private.enlazar_tasa_lead(v_lead,v_cli);
 assert (select cliente_id=v_cli and estado='pendiente' from crm.solicitudes_tasa where id=v_s),'no enlazó fila compatible';
 update crm.solicitudes_tasa set cliente_id='f3a00000-0000-0000-0000-910908000001',documento_lead=null where id=v_s;
 perform set_config('crm.solicitud_tasa_por_puerta','off',true);
 raise notice 'PASS: identidad ajena, documento desactualizado y conflicto se saltan sin cambios; compatible se enlaza';
end;
$defensas_enlace$;
select pg_temp.modo('enforcement');
do $defensa_enforcement$
begin
 begin
   perform private.enlazar_tasa_lead('d7180000-0000-4000-8000-000000000002','d7180000-0000-4000-8000-000000000003');
   raise exception 'FAIL: enforcement ignoró identidad ajena';
 exception when sqlstate 'P0409' then assert sqlerrm='La solicitud pertenece a otro cliente'; end;
end;
$defensa_enforcement$;
rollback;
