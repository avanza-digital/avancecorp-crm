-- Roles, estados ON/OFF, revisión concurrente, trazabilidad y fronteras reales.
-- Siempre en el banco sintético; todo se revierte, incluidas sus identidades.
begin;
create temporary table reparto_cuentas(id uuid, nombre text, rol_crm text, rol_portal text) on commit drop;
insert into reparto_cuentas values
  ('17100000-0000-4000-8000-000000000001','Coordinación uno','coordinador','comercial'),
  ('17100000-0000-4000-8000-000000000002','Coordinación dos','coordinador','comercial'),
  ('17100000-0000-4000-8000-000000000003','Gerencia','gerencia','comercial'),
  ('17100000-0000-4000-8000-000000000004','Supervisor uno','supervisor','comercial'),
  ('17100000-0000-4000-8000-000000000005','Supervisor dos','supervisor','comercial'),
  ('17100000-0000-4000-8000-000000000006','Analista','vendedor','comercial'),
  ('17100000-0000-4000-8000-000000000007','Directorio','directorio','directorio'),
  ('17100000-0000-4000-8000-000000000008','Administrador','gerencia','superadmin'),
  ('17100000-0000-4000-8000-000000000009','Supervisor sin dependencias','supervisor','comercial');
insert into auth.users (id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@reparto.test',now(),'{}','{}',now(),now() from reparto_cuentas;
insert into public.perfiles (id,nombre_completo,correo,rol,activo)
select id,nombre,id::text||'@reparto.test',rol_portal,true from reparto_cuentas;
insert into crm.equipo (perfil_id,rol_crm,supervisor_id,activo)
select id,rol_crm,case when rol_crm='vendedor' then '17100000-0000-4000-8000-000000000004'::uuid end,true from reparto_cuentas;
grant select on reparto_cuentas to authenticated;

-- Funciones de aserción efímeras, nunca forman parte del producto.
create function pg_temp.exigir(p_ok boolean, p_mensaje text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FALLO: %',p_mensaje; end if; end $$;
create function pg_temp.rechaza(p_sql text,p_codigo text) returns void language plpgsql as $$
declare v_rechazo boolean := false;
begin
  begin execute p_sql;
  exception when others then
    if sqlstate <> p_codigo then raise exception 'Esperado %, recibido %: %',p_codigo,sqlstate,sqlerrm; end if;
    v_rechazo := true;
  end;
  perform pg_temp.exigir(v_rechazo,'La operación prohibida fue aceptada: '||p_sql);
end $$;

select pg_temp.exigir((select coordinacion_libre from crm.configuracion_reparto),'Instalación inicial encendida por pedido');
select pg_temp.exigir((select relrowsecurity and relforcerowsecurity from pg_class where oid='crm.configuracion_reparto'::regclass),'RLS y FORCE activos');
select pg_temp.exigir(not has_table_privilege('authenticated','crm.configuracion_reparto','SELECT,INSERT,UPDATE,DELETE'),'Sin acceso directo a la tabla');
select pg_temp.exigir(not has_function_privilege('anon','crm.guardar_configuracion_reparto_fn(boolean,integer)','EXECUTE'),'Anónimo sin escritura');
select pg_temp.exigir(not has_function_privilege('service_role','crm.guardar_configuracion_reparto_fn(boolean,integer)','EXECUTE'),'Service role sin escritura');
select pg_temp.exigir(not exists (
  select 1 from unnest(array['anon','service_role']) as roles(rol)
  where has_function_privilege(rol,'crm.configuracion_reparto_fn()','EXECUTE')
    or has_table_privilege(rol,'crm.configuracion_reparto','SELECT,INSERT,UPDATE,DELETE')
),'Anónimo y servicio sin lectura RPC ni acceso a tabla');

-- Gerencia real administra el control; no requiere privilegios del portal.
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000003',true);
set local role authenticated;
select pg_temp.exigir((crm.configuracion_reparto_fn()->>'coordinacion_libre')::boolean,'Gerencia ve ON');
select pg_temp.exigir((crm.guardar_configuracion_reparto_fn(false,1)->>'revision')::integer=2,'Gerencia apaga y versiona');
select pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(true,1)','PT409');
select pg_temp.exigir((crm.guardar_configuracion_reparto_fn(false,2)->>'revision')::integer=2,'Repetición idempotente');
select pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(null,2)','22023');
select pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(true,null)','22023');
select pg_temp.rechaza('select * from crm.configuracion_reparto','42501');
select pg_temp.rechaza('update crm.configuracion_reparto set coordinacion_libre=true','42501');
select pg_temp.exigir(not has_function_privilege(current_user,'private.reparto_libre_habilitado()','EXECUTE'),'Núcleo privado sin EXECUTE directo');
reset role;

insert into private.agenda_reparto_destinos(supervisor_id,alias,orden)
values ('17100000-0000-4000-8000-000000000004','Prueba uno',8),('17100000-0000-4000-8000-000000000005','Prueba dos',9);
-- La transacción revierte también la agenda sintética previa.
delete from private.agenda_reparto_diaria where fecha=(statement_timestamp() at time zone 'America/Lima')::date;
insert into private.agenda_reparto_diaria(fecha,origen,supervisor_id,creado_por,actualizado_por)
values ((statement_timestamp() at time zone 'America/Lima')::date,'landing','17100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000001');
insert into crm.leads(id,nombre_completo,telefono,etapa,origen,activo,no_contactar,creado_por,monto_estimado)
select ('18100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'REPARTO LIBRE '||n,'99177000'||n,'nuevo',
  case when n in (2,4) then 'formulario' else 'landing' end,true,n=5,'17100000-0000-4000-8000-000000000004',10000
from generate_series(1,8) n;

select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000001',true);
set local role authenticated;
select pg_temp.exigir((crm.agenda_reparto_diaria()->>'reparto_libre')::boolean=false,'Coordinadora OFF');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000005')$q$,'22023');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000002','17100000-0000-4000-8000-000000000005')$q$,'22023');
select pg_temp.rechaza('select crm.configuracion_reparto_fn()','42501');
select pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(true,2)','42501');
reset role;
select pg_temp.exigir(not exists(select 1 from crm.leads where id in ('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000002') and asignado_supervisor_id is not null),'OFF rechaza sin mover filas');

select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000003',true);
set local role authenticated;
select pg_temp.exigir((crm.guardar_configuracion_reparto_fn(true,2)->>'revision')::integer=3,'Gerencia activa');
select pg_temp.exigir((crm.agenda_reparto_diaria()->>'reparto_libre')::boolean=false,'ON no amplía permisos operativos de Gerencia');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000003','17100000-0000-4000-8000-000000000005')$q$,'22023');

-- Dos coordinadoras: el permiso es del rol y no de una identidad concreta.
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000001',true);
select pg_temp.exigir((crm.agenda_reparto_diaria()->>'reparto_libre')::boolean,'Coordinadora uno ON');
select pg_temp.exigir((crm.repartir_lead('18100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000005')->>'excepcion_turno')::boolean,'Landing fuera del turno');
select pg_temp.exigir((crm.repartir_lead('18100000-0000-4000-8000-000000000002','17100000-0000-4000-8000-000000000005')->>'excepcion_turno')::boolean,'Formulario sin turno');
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000002',true);
select pg_temp.exigir((crm.agenda_reparto_diaria()->>'reparto_libre')::boolean,'Coordinadora dos ON');
select pg_temp.exigir((crm.repartir_lead('18100000-0000-4000-8000-000000000003','17100000-0000-4000-8000-000000000005')->>'excepcion_turno')::boolean,'Segunda coordinadora deriva libremente');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000004')$q$,'P0002');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000005','17100000-0000-4000-8000-000000000005')$q$,'P0429');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000006','17100000-0000-4000-8000-000000000006')$q$,'22023');
reset role;
select pg_temp.exigir((select count(*)=3 from crm.actividades where lead_id in ('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000002','18100000-0000-4000-8000-000000000003') and tipo='reasignacion' and metadata->>'movimiento'='entra_bandeja' and creado_por in ('17100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000002')),'Auditoría conserva actores reales');
select pg_temp.exigir((select count(*)>=2 from public.audit_log where tabla='crm.configuracion_reparto' and usuario_id='17100000-0000-4000-8000-000000000003' and operacion='UPDATE'),'Cambios de control auditados');

-- El permiso libre no autoriza destinos cuya cuenta o membresía esté inactiva.
update public.perfiles set activo=false where id='17100000-0000-4000-8000-000000000009';
set local role authenticated;
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000006','17100000-0000-4000-8000-000000000009')$q$,'22023');
reset role;
update public.perfiles set activo=true where id='17100000-0000-4000-8000-000000000009';
update crm.equipo set activo=false where perfil_id='17100000-0000-4000-8000-000000000009';
set local role authenticated;
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000006','17100000-0000-4000-8000-000000000009')$q$,'22023');
reset role;
select pg_temp.exigir((select asignado_supervisor_id is null from crm.leads where id='18100000-0000-4000-8000-000000000006'),'Destino inactivo no recibe el lead');
update crm.equipo set activo=true where perfil_id='17100000-0000-4000-8000-000000000009';

-- Los roles distintos de Gerencia no pueden encender, apagar ni consultar el control.
set local role authenticated;
do $test$
declare actor record;
begin
  for actor in select * from reparto_cuentas where rol_crm <> 'gerencia' loop
    perform set_config('request.jwt.claim.sub',actor.id::text,true);
    perform pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(false,3)','42501');
    perform pg_temp.rechaza('select crm.configuracion_reparto_fn()','42501');
  end loop;
end;
$test$;
reset role;

-- Una sesión abierta pierde el permiso al apagarse; el administrador conserva su excepción.
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000003',true);
set local role authenticated;
select crm.guardar_configuracion_reparto_fn(false,3);
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000001',true);
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000005')$q$,'22023');
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000008',true);
select pg_temp.exigir((crm.agenda_reparto_diaria()->>'reparto_libre')::boolean,'Agenda de Superadmin conserva permiso con OFF');
select pg_temp.exigir((crm.repartir_lead('18100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000005')->>'excepcion_turno')::boolean,'Superadmin conserva excepción con OFF');
reset role;

-- Revocación real en cualquiera de las dos capas de vigencia.
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000003',true);
set local role authenticated;
select crm.guardar_configuracion_reparto_fn(true,4);
reset role;
update public.perfiles set activo=false where id='17100000-0000-4000-8000-000000000001';
update crm.equipo set activo=false where perfil_id='17100000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000001',true);
select pg_temp.rechaza('select crm.agenda_reparto_diaria()','42501');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000007','17100000-0000-4000-8000-000000000005')$q$,'42501');
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000002',true);
select pg_temp.rechaza('select crm.agenda_reparto_diaria()','42501');
select pg_temp.rechaza($q$select crm.repartir_lead('18100000-0000-4000-8000-000000000008','17100000-0000-4000-8000-000000000005')$q$,'42501');
reset role;
update public.perfiles set activo=false where id='17100000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000003',true);
set local role authenticated;
select pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(true,4)','42501');
reset role;
update crm.equipo set activo=false where perfil_id='17100000-0000-4000-8000-000000000008';
select set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000008',true);
set local role authenticated;
select pg_temp.rechaza('select crm.guardar_configuracion_reparto_fn(true,4)','42501');
reset role;
select 'REPARTO_LIBRE_TX_OK';
rollback;
