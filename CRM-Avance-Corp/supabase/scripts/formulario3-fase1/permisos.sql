\set ON_ERROR_STOP on
begin;
\ir fixtures.sql
create temporary table comprobaciones(nombre text);
create function pg_temp.exigir(v boolean,nombre text) returns void language plpgsql as $$
begin
  if v is distinct from true then raise exception 'FAIL: %',nombre; end if;
  insert into comprobaciones values(nombre);
end;
$$;
-- Capturar resultados bajo el rol real sin que el contador conceda permisos al CRM.
grant select,insert on comprobaciones to authenticated,anon,service_role;
insert into crm.leads(id,nombre_completo,telefono,origen,campania_origen,monto_estimado,vendedor_id) values
 ('f3300000-0000-0000-0000-000000000001','Prueba cartera propia','983000001','formulario','Formulario 3',5000,'f3000000-0000-0000-0000-000000000001'),
 ('f3300000-0000-0000-0000-000000000002','Prueba cartera externa','983000002','formulario','Formulario 3',5000,'f3000000-0000-0000-0000-000000000004');

do $acl$
begin
  perform pg_temp.exigir(not has_column_privilege('authenticated','crm.leads','campania_origen','INSERT') and not has_column_privilege('authenticated','crm.leads','campania_origen','UPDATE'),'campaña no editable por authenticated');
  perform pg_temp.exigir(has_column_privilege('authenticated','crm.leads','campania_origen','SELECT'),'campaña legible bajo RLS');
  perform pg_temp.exigir(not has_function_privilege('authenticated','crm.importar_lead_fn(jsonb)','EXECUTE') and not has_function_privilege('anon','crm.importar_lead_fn(jsonb)','EXECUTE'),'puerta solo servidor');
  perform pg_temp.exigir(not has_function_privilege('authenticated','private.registrar_solicitud_cliente_fn(uuid,text,jsonb)','EXECUTE') and not has_function_privilege('service_role','private.registrar_solicitud_cliente_fn(uuid,text,jsonb)','EXECUTE'),'ayudante de cliente sigue privado');
  perform pg_temp.exigir(not has_function_privilege('authenticated','crm.registrar_reingreso_lead_fn(uuid,text,jsonb)','EXECUTE') and not has_function_privilege('anon','crm.registrar_reingreso_lead_fn(uuid,text,jsonb)','EXECUTE') and has_function_privilege('service_role','crm.registrar_reingreso_lead_fn(uuid,text,jsonb)','EXECUTE'),'reingreso mantiene ACL de servidor');
  perform pg_temp.exigir(not has_function_privilege('service_role','private.normalizar_campania_origen(jsonb,text)','EXECUTE'),'normalizador privado sin EXECUTE de API');
end;
$acl$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
-- Medir únicamente las dos fixtures; la branch remota contiene datos anteriores.
select pg_temp.exigir((select count(*)=1 and bool_and(campania_origen='Formulario 3') from crm.leads where id in ('f3300000-0000-0000-0000-000000000001','f3300000-0000-0000-0000-000000000002')),'vendedor lee campaña propia y no otra cartera');
do $escritura$
begin
  begin
    update crm.leads set campania_origen='Alterada' where id='f3300000-0000-0000-0000-000000000001';
    raise exception 'Se permitió UPDATE de campaña';
  exception when insufficient_privilege then perform pg_temp.exigir(true,'PATCH campaña denegado'); end;
  update crm.leads set nota='Edición comercial permitida' where id='f3300000-0000-0000-0000-000000000001';
  perform pg_temp.exigir(found,'las columnas previas conservan UPDATE');
  update crm.leads set nota='No debe llegar' where id='f3300000-0000-0000-0000-000000000002';
  perform pg_temp.exigir(not found,'UPDATE cruzado sigue bloqueado por RLS');
  update crm.leads set etapa='descartado',motivo_descarte='otro' where id='f3300000-0000-0000-0000-000000000001';
  perform crm.reabrir_lead_fn('f3300000-0000-0000-0000-000000000001');
  perform pg_temp.exigir((select etapa='nuevo' and campania_origen='Formulario 3' from crm.leads where id='f3300000-0000-0000-0000-000000000001'),'reapertura humana conserva campaña y misma ficha');
end;
$escritura$;

select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select pg_temp.exigir((select count(*)=1 from crm.leads where id in ('f3300000-0000-0000-0000-000000000001','f3300000-0000-0000-0000-000000000002')),'supervisor mantiene su subárbol');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.exigir((select count(*)=2 from crm.leads where id in ('f3300000-0000-0000-0000-000000000001','f3300000-0000-0000-0000-000000000002')),'gerencia conserva lectura global');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}',true);
select pg_temp.exigir((select count(*)=0 from crm.leads where id in ('f3300000-0000-0000-0000-000000000001','f3300000-0000-0000-0000-000000000002')),'coordinador conserva restricción de lectura directa de leads');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000007","role":"authenticated"}',true);
select pg_temp.exigir((select count(*)=0 from crm.leads where id in ('f3300000-0000-0000-0000-000000000001','f3300000-0000-0000-0000-000000000002')),'miembro inactivo no lee campañas');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
reset role;
-- Simula escritor DEFINER: postgres con sesión humana tampoco puede editar campaña.
do $definer$
begin
  begin
    update crm.leads set campania_origen='Alterada' where id='f3300000-0000-0000-0000-000000000001';
    raise exception 'Una puerta DEFINER humana alteró campaña';
  exception when insufficient_privilege then perform pg_temp.exigir(true,'trigger rechaza escritor elevado con auth.uid humano'); end;
end;
$definer$;
select set_config('request.jwt.claims','{}',true);
set local role service_role;
update crm.leads set campania_origen='Corrección de servidor' where id='f3300000-0000-0000-0000-000000000001';
select pg_temp.exigir((select campania_origen='Corrección de servidor' from crm.leads where id='f3300000-0000-0000-0000-000000000001'),'service_role conserva capacidad de mantenimiento controlado');
reset role;
set local role anon;
do $anon$
begin
  begin
    perform campania_origen from crm.leads;
    raise exception 'Anon leyó campaña';
  exception when insufficient_privilege then perform pg_temp.exigir(true,'anon sin acceso a leads'); end;
end;
$anon$;
reset role;
select count(*) as comprobaciones_rls_aprobadas from comprobaciones;
rollback;
