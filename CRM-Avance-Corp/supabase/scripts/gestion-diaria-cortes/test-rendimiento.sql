-- Medición local, no promesa de latencia productiva. Roster más grande de la
-- copia, 6000 llamadas ficticias por analista con lead abierto. Todo ROLLBACK.
begin;
set local statement_timeout = '120s';
do $$ declare d text; begin
  if current_database()<>'gestion_diaria_f4_vista_chvrqh' then raise exception 'Sólo banco local'; end if;
  d:=pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure);
  d:=replace(d,'private.gestion_diaria_equipo_core(','pg_temp.f43_equipo_perf(');
  execute replace(d,'statement_timestamp()','current_setting(''f43.reloj'')::timestamptz');
end $$;
create temporary table f43_perf_roster as
with recursive arbol as (
  select e.perfil_id supervisor, e.perfil_id miembro from crm.equipo e where private.rol_crm(e.perfil_id)='supervisor'
  union select a.supervisor,e.perfil_id from arbol a join crm.equipo e on e.supervisor_id=a.miembro
), vendedores as (select * from arbol where private.rol_crm(miembro)='vendedor'),
mayor as (select supervisor from vendedores group by supervisor order by cardinality(array_agg(miembro)) desc,supervisor limit 1)
select v.* from vendedores v join mayor using(supervisor);
create temporary table f43_perf_resultados(modo text, plan jsonb);
grant select on f43_perf_roster to authenticated;
grant all on f43_perf_resultados to authenticated;
-- Usar el próximo lunes para medir dos cortes y permitir vigencia futura.
select set_config('f43.reloj', ((date_trunc('week',statement_timestamp() at time zone 'America/Lima')::date+7+time '17:00') at time zone 'America/Lima')::text,true);
alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select l.id,'llamada_no_contestada',r.miembro,
  ((current_setting('f43.reloj')::timestamptz at time zone 'America/Lima')::date
    +case when i<=4000 then time '10:00' else time '15:00' end) at time zone 'America/Lima','{}'::jsonb
from f43_perf_roster r join lateral (select id from crm.leads where vendedor_id=r.miembro
  and activo and etapa not in ('convertido','descartado') order by id limit 1) l on true cross join generate_series(1,6000) i;
alter table crm.actividades enable trigger user;
select set_config('request.jwt.claim.sub',supervisor::text,true) from f43_perf_roster limit 1;
set local role authenticated;
do $$ declare p jsonb; begin
  execute 'explain (analyze,buffers,format json) select pg_temp.f43_equipo_perf(null,null)' into p;
  insert into f43_perf_resultados values('OFF',p);
end $$;
reset role;
select set_config('request.jwt.claim.sub',perfil_id::text,true) from crm.equipo where private.rol_crm(perfil_id)='gerencia' limit 1;
insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,motivo,cortes_activos)
select 2,id,(current_setting('f43.reloj')::timestamptz at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima',
  'Fixture: medición rendimiento',true from crm.politica_gestion_diaria where version=1;
select set_config('request.jwt.claim.sub',supervisor::text,true) from f43_perf_roster limit 1;
set local role authenticated;
do $$ declare p jsonb; begin
  if pg_temp.f43_equipo_perf(null,null)#>>'{cortes,estado}' <> 'activo' then
    raise exception 'La medición ON debe evaluar realmente los cortes';
  end if;
  execute 'explain (analyze,buffers,format json) select pg_temp.f43_equipo_perf(null,null)' into p;
  insert into f43_perf_resultados values('ON',p);
end $$;
reset role;
select 'F43_RENDIMIENTO:'||jsonb_build_object('modo',modo,'analistas',(select cardinality(array_agg(miembro)) from f43_perf_roster),
  'llamadas_fixture_por_analista_con_cartera',6000,
  'ms',plan#>'{0,Execution Time}','bloques_hit',plan#>'{0,Plan,Shared Hit Blocks}',
  'bloques_read',plan#>'{0,Plan,Shared Read Blocks}')::text from f43_perf_resultados order by modo;
rollback;
