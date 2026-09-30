begin;
create function pg_temp.comprobar(ok boolean,caso text) returns void language plpgsql as $f$
begin if ok is not true then raise exception 'FAIL GESTION_COLA_ROLES: %',caso; end if; end $f$;
create temporary table g_personas as select
 (select perfil_id from crm.equipo where activo and rol_crm='supervisor' limit 1) supervisor,
 (select perfil_id from crm.equipo where activo and rol_crm='vendedor' limit 1) vendedor,
 (select perfil_id from crm.equipo where activo and rol_crm='gerencia' limit 1) gerencia;
create temporary table g_caso(id uuid primary key,n integer);
insert into g_caso select gen_random_uuid(),n from generate_series(1,2) n;
create temporary table g_resp(k text primary key,j jsonb);
grant select on g_personas,g_caso to authenticated;
grant select,insert on g_resp to authenticated;
select set_config('request.jwt.claim.sub',supervisor::text,true) is not null from g_personas;
set local role authenticated;
select crm.crear_lead_si_disponible(p_id=>c.id,p_nombre_completo=>'SUPERVISOR SINTETICO '||c.n,
  p_telefono=>'91111111'||c.n,p_origen=>'oficina',p_monto_estimado=>25000,p_moneda=>'PEN',p_vendedor_id=>a.supervisor)
from g_caso c cross join g_personas a;
insert into g_resp select 'nuevo',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_caso where n=1;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(j->'items') f where f.value->>'lead_id'=(select id::text from g_caso where n=1)
  and f.value->>'grupo'='primera_atencion' and f.value->>'estado_trabajo'='pendiente'), 'supervisor atiende su nuevo') from g_resp where k='nuevo';
insert into g_resp select 'llamada',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_interesado','no_le_interesa_invertir') from g_caso where n=1;
insert into g_resp select 'atendido',crm.gestion_diaria_cola_trabajo_fn('tarea_hoy',0,8,'lead:'||id) from g_caso where n=1;
select pg_temp.comprobar(j->>'filtro'='primera_atencion' and exists(select 1 from jsonb_array_elements(j->'items') f
  where f.value->>'lead_id'=(select id::text from g_caso where n=1) and f.value->>'estado_trabajo'='gestionado'
  and f.value#>>'{ultima_gestion,resultado}'='no_interesado'), 'contestó conserva grupo y ancla sigue al grupo') from g_resp where k='atendido';
-- Primera atención + segundo intento que cierra la tarea: el grupo terminado
-- sigue siendo el de entrada, aunque la gestión más reciente cierre otro motivo.
insert into g_resp select 'programar_nuevo',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto',null,null,
  jsonb_build_object('tipo','llamada','titulo','Segundo intento del nuevo','vence_en',clock_timestamp()+interval '30 minutes'))
from g_caso where n=2;
insert into g_resp select 'cerrar_reintento',crm.registrar_llamada_v4(gen_random_uuid(),c.id,'no_contesto',null,null,null,
  (select t.id from crm.tareas t where t.lead_id=c.id and t.estado='pendiente' order by t.vence_en,t.id limit 1))
from g_caso c where c.n=2;
insert into g_resp select 'dos_intentos',crm.gestion_diaria_cola_trabajo_fn('primera_atencion',0,8,'lead:'||id) from g_caso where n=2;
select pg_temp.comprobar(j->>'filtro'='primera_atencion' and exists(select 1 from jsonb_array_elements(j->'items') f
  where f.value->>'lead_id'=(select id::text from g_caso where n=2) and f.value->>'grupo'='primera_atencion'
    and f.value->>'estado_trabajo'='gestionado'), 'reintento cerrado conserva primer grupo') from g_resp where k='dos_intentos';
reset role;
-- Metadata histórica defectuosa sólo dentro del fixture con rollback.
alter table crm.actividades disable trigger user;
update crm.actividades set metadata=jsonb_set(metadata,'{tarea_id}','"tarea-invalida"')
where id=(select (j->>'actividad_id')::uuid from g_resp where k='cerrar_reintento');
alter table crm.actividades enable trigger user;
set local role authenticated;
insert into g_resp select 'metadata_legacy',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_caso where n=2;
select pg_temp.comprobar(j->>'elegido'='lead:'||(select id::text from g_caso where n=2),
  'metadata no UUID no derriba la cola') from g_resp where k='metadata_legacy';
reset role;
-- Reasignación real: conserva el ledger y los relojes causales de la tenencia.
select set_config('request.jwt.claim.sub',gerencia::text,true) is not null from g_personas;
set local role authenticated;
update crm.leads set vendedor_id=(select vendedor from g_personas)
where id=(select id from g_caso where n=1);
reset role;
select set_config('request.jwt.claim.sub',vendedor::text,true) is not null from g_personas;
-- El lead reasignado tiene un compromiso exigible: así la presencia no depende
-- de que el motor considere una reasignación como un primer intento nuevo.
insert into crm.tareas(lead_id,vendedor_id,creado_por,tipo,titulo,vence_en)
select c.id,p.vendedor,p.vendedor,'llamada','Pendiente de la nueva tenencia',statement_timestamp()-interval '1 minute'
from g_caso c cross join g_personas p where c.n=1;
select set_config('request.jwt.claim.sub',vendedor::text,true) is not null from g_personas;
set local role authenticated;
insert into g_resp select 'reasignado',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_caso where n=1;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(j->'items') f where f.value->>'lead_id'=(select id::text from g_caso where n=1)
  and f.value->>'estado_trabajo'='pendiente' and f.value->'ultima_gestion'='null'::jsonb), 'reasignación positiva sin gestión heredada') from g_resp where k='reasignado';
reset role;
create temporary table g_clientes(n integer,id uuid,vence timestamptz);
insert into g_clientes select n,gen_random_uuid(),case when n=2 then least(statement_timestamp()+interval '30 seconds',
  (((statement_timestamp() at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima')-interval '1 millisecond')
  else statement_timestamp()-interval '2 hours' end from generate_series(1,3) n;
-- Fixture de lectura por responsable: incluye una tarea histórica asignada a
-- otro analista. Sólo se altera la tabla CRM sintética, nunca public.
alter table crm.tareas disable trigger user;
insert into crm.tareas(id,perfil_id,vendedor_id,creado_por,tipo,titulo,vence_en)
select c.id,(select id from public.perfiles where rol='cliente' and activo limit 1),case when c.n=3 then p.supervisor else p.vendedor end,p.vendedor,
  'tarea','Cliente sintético dos gestiones',c.vence from g_clientes c cross join g_personas p;
alter table crm.tareas enable trigger user;
grant select on g_clientes to authenticated;
set local role authenticated;
insert into g_resp select 'cliente',crm.gestion_diaria_cola_trabajo_fn('todo',0,200,'tarea:'||id) from g_clientes where n=1;
select pg_temp.comprobar(j->>'elegido'='tarea:'||(select id::text from g_clientes where n=1)
  and (select count(*) from jsonb_array_elements(j->'items') f where f.value->>'tarea_id' in (select id::text from g_clientes where n<3))=2
  and not exists(select 1 from jsonb_array_elements(j->'items') f where f.value->>'tarea_id'=(select id::text from g_clientes where n=3))
  and (j->>'proximo_cambio_en')::timestamptz<=(select vence from g_clientes where n=2),
  'cliente: dos claves, ancla de tarea, sin tareas ajenas y próximo vencimiento') from g_resp where k='cliente';
reset role;
select set_config('request.jwt.claim.sub',supervisor::text,true) is not null from g_personas;
set local role authenticated;
insert into g_resp select 'cliente_supervisor',crm.gestion_diaria_cola_trabajo_fn('todo',0,200,'tarea:'||id) from g_clientes where n=3;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(j->'items') f where f.value->>'tarea_id'=(select id::text from g_clientes where n=3))
  and not exists(select 1 from jsonb_array_elements(j->'items') f where f.value->>'tarea_id' in (select id::text from g_clientes where n<3)),
  'supervisor sólo sus clientes, sin tareas del vendedor') from g_resp where k='cliente_supervisor';
select 'GESTION_COLA_ROLES_OK';
rollback;
