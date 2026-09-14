-- Solo copia local desechable con el fixture F3 910908. Todo dato es sintético.
\set ON_ERROR_STOP on
set timezone='America/Lima';
set plpgsql.check_asserts=on;
create temporary table qa_tasa_baja(clave text primary key, id uuid);
begin;
update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
select coalesce(max(version),0)+1,clock_timestamp()-interval '1 minute',15,28,1,'enforcement' from crm.politica_rentabilidad;
create function pg_temp.actor(p_id text default 'f3000000-0000-0000-0000-000000000001') returns void language sql as $$
 select set_config('request.jwt.claims',jsonb_build_object('sub',p_id,'role','authenticated')::text,true);
$$;
create function pg_temp.intencion(p_tasa numeric) returns jsonb language sql as $$
 select jsonb_build_object('categoria','nuevo','capital',20000,'moneda','PEN','modalidad','mensual','tipo_interes','simple',
 'fecha_inicio','2026-09-15','fecha_vencimiento','2027-09-15','tasa_anual',p_tasa);
$$;
create function pg_temp.alta(p_tasa numeric,p_cliente uuid default 'f3a00000-0000-0000-0000-910908000001',p_categoria text default 'nuevo',p_origen uuid default null)
returns uuid language plpgsql as $$
declare v_res jsonb;
begin
 set constraints all deferred;
 v_res:=crm.crear_contrato_con_cuenta_pdf_v2(pg_temp.intencion(p_tasa)||jsonb_build_object(
   'cliente_id',p_cliente,'numero_contrato','QA-BAJA-'||gen_random_uuid(),'categoria',p_categoria,'contrato_origen_id',p_origen),
   jsonb_build_array(jsonb_build_object('numero_cuota',1,'fecha_programada','2026-10-15','monto_programado',round(20000*p_tasa/100/12,2),'tipo','cuota'),
     jsonb_build_object('numero_cuota',2,'fecha_programada','2027-09-15','monto_programado',20000,'tipo','retorno')),
   jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','QA'||substr(gen_random_uuid()::text,1,8),
     'cci','004'||lpad(abs(hashtext(gen_random_uuid()::text)::bigint)::text,17,'0'),'titular_distinto',false));
 set constraints all immediate;
 return (v_res->>'id')::uuid;
end;
$$;
-- El template F3 no trae filas de este catálogo. Reponemos únicamente el par
-- estándar de la migración F5.b (20260830170000), sin apagar ningún guard.
insert into private.pares_autoridad(rol_portal,rol_crm,razon)
values('analista','vendedor','El par estandar del equipo comercial: la misma persona con sus dos nombres.')
on conflict do nothing;
update public.perfiles set rol='analista',activo=true,telefono='+51999013991',correo='qa-analista-baja@example.invalid'
where id='f3000000-0000-0000-0000-000000000001';
update public.perfiles set domicilio='Calle QA 123',correo='qa-cliente-baja@example.invalid'
where id='f3a00000-0000-0000-0000-910908000001';
select pg_temp.actor();
insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
values ('d7130000-0000-4000-8000-000000000001','QA TASA INFERIOR','+51999013001','71309001','otro',20000,
 'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001');
grant all on qa_tasa_baja to authenticated;
commit;

begin;
set local role authenticated;
select pg_temp.actor();
do $limites$
declare v_tasa numeric; v_id uuid; v_res jsonb;
begin
 v_res:=crm.resolver_tasa_lead_fn('d7130000-0000-4000-8000-000000000001');
 assert (v_res->>'tasa_base')::numeric=15 and (v_res->>'tasa_minima_sin_autorizacion')::numeric=0.01,'mínimo común para lead';
 v_res:=crm.resolver_tasa_fn('f3a00000-0000-0000-0000-910908000001','nuevo');
 assert (v_res->>'tasa_minima_sin_autorizacion')::numeric=0.01,'mínimo de cliente existente en nueva inversión';
 assert private.es_analista_vigente(),'el fixture debe ser un analista vigente';
 foreach v_tasa in array array[0.01,1,12,12.5,13.99,14.99,15]::numeric[] loop
   v_id:=pg_temp.alta(v_tasa);
   assert v_id is not null,'el alta no devolvió contrato';
   assert (select tasa_anual=v_tasa from public.contratos where id=v_id),
     format('lectura de contrato propio: esperado=%s, actual=%s, uid=%s, analista=%s, cliente_visible=%s',
       v_tasa,(select tasa_anual from public.contratos where id=v_id),auth.uid(),private.es_analista_vigente(),
       (select count(*) from public.perfiles where id='f3a00000-0000-0000-0000-910908000001'));
   insert into qa_tasa_baja values(v_tasa::text,v_id);
 end loop;
 begin
   perform pg_temp.alta(15.01); raise exception 'FAIL: supera base sin autorización';
 exception when sqlstate 'P0410' then null; end;
 foreach v_tasa in array array[12.345,0.011,14.999]::numeric[] loop
   begin
     perform pg_temp.alta(v_tasa); raise exception 'FAIL: redondeó una tasa con más de dos decimales';
   exception when sqlstate '22023' then
     assert sqlerrm='La tasa anual admite hasta dos decimales. Revisa el valor antes de guardar.',sqlerrm;
   end;
 end loop;
 begin
   perform pg_temp.alta(0); raise exception 'FAIL: tasa cero';
 exception when sqlstate 'P0001' then
   assert sqlerrm='La tasa anual debe estar entre 0 y 50%',sqlerrm;
 end;
 begin
   perform pg_temp.alta(-1); raise exception 'FAIL: tasa negativa';
 exception when sqlstate 'P0001' then
   assert sqlerrm='La tasa anual debe estar entre 0 y 50%',sqlerrm;
 end;
 raise notice 'PASS: API authenticated acepta siete tasas positivas, conserva el valor y bloquea exceso, cero y negativo';
end;
$limites$;
commit;

begin;
select pg_temp.actor();
do $traza$
declare v_id uuid; v_fila record;
begin
 for v_fila in select q.clave::numeric as esperada,c.tasa_anual as actual from qa_tasa_baja q
   left join public.contratos c on c.id=q.id loop
   assert v_fila.actual is not distinct from v_fila.esperada,
     'tasa alterada al guardar: esperada='||v_fila.esperada||', actual='||coalesce(v_fila.actual::text,'NULL');
 end loop;
 select id into v_id from qa_tasa_baja where clave='12.5';
 assert exists(select 1 from crm.ledger_rentabilidad where contrato_id=v_id and tasa_base=15 and tasa_final=12.5
   and solicitud_id is null and detalle->>'tasa_inferior_sin_excepcion'='true'),'falta auditoría de tasa menor';
 assert not exists(select 1 from crm.solicitudes_tasa where contrato_id in (select id from qa_tasa_baja)),'creó solicitud innecesaria';
 raise notice 'PASS: ledger conserva base, tasa elegida, actor y motivo sin una solicitud artificial';
 -- Un PDF legal conserva su protección de cambios directos.
 begin
   update public.contratos set tasa_anual=12 where id=v_id;
   set constraints all immediate;
   raise exception 'FAIL: rebajó un contrato congelado';
 exception when sqlstate '55000' then
   assert sqlerrm='Los términos del contrato están congelados por su PDF legal',sqlerrm;
 end;
 -- Aislamos el observador en un contrato sin PDF, sin desactivar ningún trigger.
 insert into public.contratos(cliente_id,numero_contrato,capital,moneda,tasa_anual,modalidad,tipo_interes,
   fecha_inicio,fecha_vencimiento,categoria,creado_por)
 values('f3a00000-0000-0000-0000-910908000001','QA-BAJA-CORRECCION',20000,'PEN',12.5,'mensual','simple',
   '2026-09-15','2027-09-15','nuevo','f3000000-0000-0000-0000-000000000001') returning id into v_id;
 set constraints all immediate;
 insert into qa_tasa_baja values('correccion',v_id);
end;
$traza$;
commit;

-- Distinta transacción del alta: evita que la deduplicación del observador oculte una corrección.
begin;
select pg_temp.actor();
do $correccion$
declare v_id uuid;
begin
 select id into v_id from qa_tasa_baja where clave='correccion';
 begin
   update public.contratos set tasa_anual=12 where id=v_id;
   set constraints all immediate;
   raise exception 'FAIL: rebajó un contrato ya emitido';
 exception when sqlstate 'P0410' then null; end;
 set constraints all deferred;
 update public.contratos set capital=21000 where id=v_id;
 set constraints all immediate;
 assert (select tasa_anual=12.5 from public.contratos where id=v_id),'una corrección cambió la tasa';
 raise notice 'PASS: correcciones conservan la tasa pactada y no conceden permiso para rebajarla';
end;
$correccion$;
rollback;

begin;
set local role authenticated;
select pg_temp.actor();
do $herencia$
declare v_id uuid; v_categoria text; v_res jsonb;
begin
 select id into v_id from qa_tasa_baja where clave='15';
 foreach v_categoria in array array['renovacion','upgrade'] loop
   v_res:=crm.resolver_tasa_fn('f3a00000-0000-0000-0000-910908000001',v_categoria,v_id);
   assert (v_res->>'tasa_minima_sin_autorizacion')::numeric=15,'alteró el mínimo heredado';
 end loop;
 begin
   perform pg_temp.alta(12.5,'f3a00000-0000-0000-0000-910908000001','upgrade',v_id);
   raise exception 'FAIL: amplió la rebaja a un upgrade';
 exception when sqlstate 'P0410' then null; end;
 raise notice 'PASS: renovaciones y upgrades mantienen la base heredada y el candado';
end;
$herencia$;
rollback;

begin;
select pg_temp.actor();
do $conversion$
declare v_tasa numeric; v_saga jsonb; v_perfil uuid:='d7130000-0000-4000-8000-000000000002'; v_id uuid;
begin
 foreach v_tasa in array array[0, -1, 15.01, 12.345, 'NaN'::numeric, 'Infinity'::numeric] loop
   begin
     perform private.validar_tasa_conversion_lead('d7130000-0000-4000-8000-000000000001',null,pg_temp.intencion(v_tasa));
     raise exception 'FAIL: validó tasa inválida para convertir: %',v_tasa;
   exception when sqlstate 'P0410' then null; end;
 end loop;
 update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
 v_saga:=crm.reservar_conversion_lead('d7130000-0000-4000-8000-000000000001','DNI','71309001',
   jsonb_build_object('correo','qa-baja@example.invalid','nombre_completo','QA TASA INFERIOR','domicilio','Calle QA 123','condiciones_tasa',pg_temp.intencion(12.5)));
 perform crm.marcar_efectos_conversion('d7130000-0000-4000-8000-000000000001',(v_saga->>'claim_id')::uuid,v_saga->>'token');
 insert into auth.users(id) values(v_perfil);
 insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id,domicilio,correo)
 values(v_perfil,'QA TASA INFERIOR','cliente','DNI','71309001','f3000000-0000-0000-0000-000000000001','Calle QA 123','qa-baja@example.invalid');
 perform crm.convertir_lead('d7130000-0000-4000-8000-000000000001',v_perfil);
 v_id:=pg_temp.alta(12.5,v_perfil);
 assert (select tasa_anual=12.5 from public.contratos where id=v_id),'conversión perdió la tasa';
 assert not exists(select 1 from crm.solicitudes_tasa where lead_id='d7130000-0000-4000-8000-000000000001'),'solicitud no requerida';
 raise notice 'PASS: reserva, sellado, identidad, conversión y contrato a 12.5 sin solicitud de Gerencia';
end;
$conversion$;
rollback;

begin;
do $acceso$
declare v_rol text;
begin
 foreach v_rol in array array['anon','authenticated','service_role'] loop
   assert not has_function_privilege(v_rol,'private.rentabilidad_minimo_alta(text,numeric)','EXECUTE'),'helper expuesto';
 end loop;
 assert (select prosecdef=false and proconfig=array['search_path=""'] from pg_proc where oid='private.rentabilidad_minimo_alta(text,numeric)'::regprocedure),'helper sin aislamiento';
 raise notice 'PASS: helper privado sin permisos de API ni elevación de privilegios';
end;
$acceso$;
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin
   perform crm.resolver_tasa_fn('f3a00000-0000-0000-0000-910908000001','nuevo');
   raise exception 'FAIL: identidad ausente';
 exception when insufficient_privilege then null; end;
 raise notice 'PASS: sin identidad no se obtiene un rango autorizado';
end $$;
rollback;
