begin;
set local statement_timeout='90s';
do $$ begin if current_database() not like 'citas_%' then raise exception 'Solo banco Citas'; end if; end $$;
create function pg_temp.comprobar(ok boolean,mensaje text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',mensaje; end if; raise notice 'PASS: %',mensaje; end $$;
-- @LECTOR_ANTERIOR@
-- @TESTIGO_ANTERIOR@
create function pg_temp.sin_comercial(p jsonb) returns jsonb language sql as $$
 select jsonb_set(jsonb_set(p-'criterio_depositos','{conversiones}',
 (select coalesce(jsonb_agg(c-'fecha_comercial' order by n),'[]') from jsonb_array_elements(p->'conversiones') with ordinality q(c,n))),
 '{gestion,conversiones}',(select coalesce(jsonb_agg(c-'fecha_comercial' order by n),'[]')
 from jsonb_array_elements(p#>'{gestion,conversiones}') with ordinality q(c,n)));
$$;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
set local role authenticated;
create temp table lecturas as select mes,crm.citas_gerencia_consulta_fn(mes,(mes+interval '1 month - 1 day')::date) payload
from unnest(array[date '2026-09-01',date '2026-10-01']) mes;
select jsonb_build_object('fixture',to_char(mes,'YYYY-MM'),'payload',payload) from lecturas;
select pg_temp.comprobar(bool_and(pg_temp.sin_comercial(payload-'testigo')=pg_temp.lector_antes(mes,(mes+interval '1 month - 1 day')::date)),
 'todos los campos anteriores idénticos: orden, población, fechas, capital y ámbito') from lecturas;
select pg_temp.comprobar(bool_and(((payload->'testigo')-'comercial')=pg_temp.testigo_antes(mes,(mes+interval '1 month - 1 day')::date)),
 'testigo heredado exacto en ambos meses; nuevos clientes usan comercial') from lecturas;
select pg_temp.comprobar((select payload#>>'{testigo,comercial,clientes_periodo}'='4'
 and payload#>>'{testigo,comercial,clientes_vinculados}'='2'
 and payload#>>'{testigo,comercial,entrevistas}'='4' from lecturas where mes='2026-09-01'),
 'septiembre: cuatro ventas, mismo día compatible, entrevista posterior excluida');
select pg_temp.comprobar((select payload#>>'{testigo,comercial,clientes_periodo}'='1'
 and payload#>>'{testigo,comercial,clientes_vinculados}'='1'
 and payload#>>'{testigo,clientes_periodo}'='5' from lecturas where mes='2026-10-01'),
 'octubre: una venta comercial frente a cinco registros atribuibles; sin fecha no inventa venta');
select pg_temp.comprobar((select c->>'fecha_comercial'='2026-09-01' and c->>'convertido_en' like '2026-10-06%'
 from lecturas l,jsonb_array_elements(l.payload#>'{gestion,conversiones}') c
 where l.mes='2026-09-01' and c->>'lead_id'='92000000-0000-4000-8000-000000000201'),
 'día uno de septiembre y carga de octubre separados sin convertir fecha comercial a UTC');
reset role;
-- El snapshot no cambia cuando se lee: estas funciones son STABLE y sin DML.
select pg_temp.comprobar((select bool_and(provolatile='s') from pg_proc where oid in(
 'private.citas_gerencia_consulta(date,date)'::regprocedure,'private.citas_testigo_mes(date,date)'::regprocedure)),
 'lectores STABLE conservan semántica de solo lectura');
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select pg_temp.comprobar(not(crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')?'testigo'),
 'supervisor no recibe ningún testigo global');
select pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')#>'{gestion,conversiones}') c
 where c->>'analista_id'='92000000-0000-4000-8000-000000000005'),
 'supervisor no recibe cierres ni fechas del equipo ajeno');
reset role;
do $$ declare n int; begin
 foreach n in array array[3,5,6,7] loop
  perform set_config('request.jwt.claim.sub',('92000000-0000-4000-8000-'||lpad(n::text,12,'0')),true);
  execute 'set local role authenticated';
  begin perform crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30'); raise exception 'Acceso indebido: %',n;
  exception when insufficient_privilege then null; end;
  execute 'reset role';
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 execute 'set local role anon';
 begin perform crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30'); raise exception 'Acceso anónimo indebido';
 exception when insufficient_privilege then null; end;
 execute 'reset role';
 raise notice 'PASS: vendedor, coordinación, inactivo y anónimo denegados';
end $$;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
-- Matriz de configuración y fuente retirada. Sólo postestados sintéticos.
savepoint matriz;
set local session_replication_role=replica;
update crm.control_citas_versiones set configuracion=jsonb_set(configuracion,'{mes_resultado}','"asignacion"');
set local session_replication_role=origin;
select pg_temp.comprobar(crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')#>>'{testigo,comercial,clientes_periodo}'='4'
 and crm.citas_gerencia_consulta_fn('2026-10-01','2026-10-31')#>>'{testigo,comercial,clientes_periodo}'='1',
 'la cohorte de asignación afecta entrevistas, nunca el mes comercial de ventas');
select jsonb_build_object('fixture','cohorte','payload',crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30'));
rollback to matriz;
set local session_replication_role=replica;
update public.contratos set categoria='renovacion' where id='92000000-0000-4000-8000-000000000301';
set local session_replication_role=origin;
select pg_temp.comprobar(crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')#>>'{testigo,comercial,clientes_periodo}'='3',
 'una fuente que deja de ser elegible deja de fabricar venta comercial');
select pg_temp.comprobar(not exists(
 select 1 from jsonb_array_elements(crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')->'conversiones') c
 where c->>'lead_id'='92000000-0000-4000-8000-000000000201' and c->>'fecha_comercial' is not null)
 and not exists(select 1 from jsonb_array_elements(crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')#>'{gestion,conversiones}') c
 where c->>'lead_id'='92000000-0000-4000-8000-000000000201' and c->>'fecha_comercial' is not null),
 'renovación retirada: fecha ausente en recuperación y en gestión, sin criterios divergentes');
select jsonb_build_object('fixture','renovacion','payload',crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30'));

rollback to matriz;
-- Ambigüedad real admitida por el legado: episodio histórico y acreditación
-- del mismo lead. Uno de los dos pertenece al equipo ajeno del supervisor.
savepoint ambiguedad;
set local session_replication_role=replica;
update crm.lead_asignaciones set analista_id='92000000-0000-4000-8000-000000000005',
 asignado_en='2026-08-01 08:00 America/Lima',sla_global_iniciado_en='2026-08-01 08:00 America/Lima',
 primera_gestion_limite_en='2026-08-02 08:00 America/Lima',primer_contacto_limite_en='2026-08-02 08:00 America/Lima',
 finalizado_en='2026-08-31 08:00 America/Lima',motivo_cierre='convertido',resultado='convertido',resultado_en='2026-08-31 08:00 America/Lima'
 where lead_id='92000000-0000-4000-8000-000000000201';
set local session_replication_role=origin;
select pg_temp.comprobar((select count(*)=2 from private.conversion_cierres('-infinity',now(),'2026-09-01',true,'{}',1,
 array['92000000-0000-4000-8000-000000000201'::uuid])), 'el caso de ambigüedad contiene dos hechos reales del núcleo');
do $$ declare actor text; p jsonb; begin
 foreach actor in array array['92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002'] loop
  perform set_config('request.jwt.claim.sub',actor,true);
  execute 'set local role authenticated';
  p:=crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  perform pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(p->'conversiones') c
    where c->>'lead_id'='92000000-0000-4000-8000-000000000201' and c->>'fecha_comercial' is not null)
    and not exists(select 1 from jsonb_array_elements(p#>'{gestion,conversiones}') c
    where c->>'lead_id'='92000000-0000-4000-8000-000000000201' and c->>'fecha_comercial' is not null),
    'ambigüedad global: ambos lectores excluyen fecha tanto en Gerencia como en Supervisión');
  execute 'reset role';
 end loop;
end $$;
rollback to ambiguedad;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
-- Combinaciones de reglas: incluye alta manual propia y distinta atribución.
savepoint configuraciones;
set local session_replication_role=replica;
update crm.leads set alta_manual=true,creado_por=vendedor_id where id='92000000-0000-4000-8000-000000000202';
update crm.lead_asignaciones set analista_id='92000000-0000-4000-8000-000000000005'
where lead_id='92000000-0000-4000-8000-000000000201';
set local session_replication_role=origin;
create temp table matriz_resultado(caso text,payload jsonb);
do $$ declare m text; a text; b text; actividad text; n int:=0; begin
 foreach m in array array['evento','asignacion'] loop
 foreach a in array array['evento','asignacion'] loop
 foreach b in array array['entrevistas','personas_entrevistadas'] loop
 foreach actividad in array array['incluir','excluir'] loop
  n:=n+1;
  perform set_config('session_replication_role','replica',true);
  update crm.control_citas_versiones set configuracion=configuracion||jsonb_build_object(
   'mes_resultado',m,'analista_resultado',a,'base_depositos',b,'actividad_manuales',actividad);
  perform set_config('session_replication_role','origin',true);
  insert into matriz_resultado values('matriz-'||lpad(n::text,2,'0'),crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30'));
 end loop; end loop; end loop; end loop;
end $$;
select jsonb_build_object('fixture',caso,'payload',payload) from matriz_resultado order by caso;
rollback to configuraciones;
-- Latencia de lectura del fixture completo, separada de la medición productiva.
create temp table tiempos(lector text,ms numeric);
do $$ declare i int; t timestamptz; begin
 for i in 1..20 loop
  t:=clock_timestamp();
  perform pg_temp.lector_antes('2026-09-01','2026-09-30'); perform pg_temp.testigo_antes('2026-09-01','2026-09-30');
  insert into tiempos values('anterior',1000*extract(epoch from clock_timestamp()-t));
  t:=clock_timestamp(); perform crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  insert into tiempos values('comercial',1000*extract(epoch from clock_timestamp()-t));
 end loop;
end $$;
select jsonb_build_object('latencia',lector,'muestras',count(*),'mediana_ms',percentile_cont(0.5) within group(order by ms),'max_ms',max(ms)) from tiempos group by lector;
select jsonb_build_object('estado','PASS','meses',2,'compatibilidad','payload heredado exacto','permisos','gerencia/supervisor/vendedor/coordinacion/inactivo/anon');
rollback;
