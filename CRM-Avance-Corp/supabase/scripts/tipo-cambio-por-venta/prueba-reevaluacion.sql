-- Solo metadata en rollback: no se agenda ni activa un scheduler. El ciclo
-- SQL es el nativo; la extensión no está instalada en este banco de schema.
do $$ begin
  if to_regclass('cron.job') is not null then raise exception 'El banco debe empezar sin cron.job'; end if;
end $$;
savepoint politica_omitida;
select crm.suspender_capital_valorado_fn();
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()->>'motivo'='politica_desactivada',
  'la solicitud no evalúa cierres con la presentación desactivada');
rollback to savepoint politica_omitida;
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()->>'motivo'='cron_no_configurado',
  'sin cron configurado la reevaluación omite explícitamente y no cierra');
create schema cron;
create table cron.job(jobid bigint primary key,jobname text,active boolean,command text,database text);
grant usage on schema cron to postgres;
grant select on cron.job to postgres;
insert into cron.job values(3,'crm-cierre-mes-diario',false,'select crm.ciclo_cierre_mes();',current_database()),
  (4,'otro-ciclo',true,'select crm.ciclo_cierre_mes();',current_database());
create temp table cron_antes_reevaluacion as select jsonb_agg(to_jsonb(j) order by jobid) as datos from cron.job j;
set local role service_role;
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()->>'motivo'='cron_pausado',
  'el servicio respeta el ciclo pausado aunque otro job esté activo');
reset role;
select pg_temp.comprobar((select datos=(select jsonb_agg(to_jsonb(j) order by jobid) from cron.job j) from cron_antes_reevaluacion)
  and not exists(select 1 from crm.periodos_cerrados),
  'reevaluar no modifica programación ni sellos mientras el ciclo está pausado');
savepoint cron_incompatible;
update cron.job set active=true,command='select crm.ciclo_cierre_mes() where false' where jobid=3;
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()->>'motivo'='cron_incompatible',
  'un comando distinto no autoriza eludir condiciones propias de la programación');
update cron.job set command='select crm.ciclo_cierre_mes();' where jobid=3;
insert into cron.job values(5,'crm-cierre-mes-diario',true,'select crm.ciclo_cierre_mes();',current_database());
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()->>'motivo'='cron_incompatible',
  'una configuración ambigua no permite adivinar qué ciclo ejecutar');
rollback to savepoint cron_incompatible;
savepoint cron_otra_base;
update cron.job set database='otra_base' where jobid=3;
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()->>'motivo'='cron_no_configurado',
  'la programación de otra base no autoriza cerrar esta');
rollback to savepoint cron_otra_base;
set local role authenticated;
do $$ begin
  begin perform crm.reevaluar_cierre_capital_fn(); raise exception 'authenticated pidió el ciclo';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform crm.reevaluar_cierre_capital_fn(); raise exception 'anon pidió el ciclo';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',pg_temp.persona(2)::text,true);
set local role service_role;
do $$ begin
  begin perform crm.reevaluar_cierre_capital_fn(); raise exception 'El servicio con sesión personal pidió el ciclo';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: reevaluar queda reservado al servicio sin identidad personal';
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
