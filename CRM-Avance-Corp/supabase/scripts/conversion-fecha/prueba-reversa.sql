begin;
set local statement_timeout='30s';
create temp table funciones_antes as
select p.oid::regprocedure::text as firma,md5(pg_get_functiondef(p.oid)) as huella
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='private' and p.proname in ('conversion_cierres','cierre_mes_ventana_desde','registrar_ajuste_si_mes_cerrado'))
 or (n.nspname='crm' and p.proname='corregir_fecha_cierre_comercial');
-- @MIGRACION@
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-09-26 22:00-05'::timestamptz $$;
select private.conversion_acreditar_fuente((select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'contrato','e0000000-0000-4000-8000-00000000000a','Fuente sintetica antes de reversa');
create temp table acreditacion_antes as select * from crm.conversion_acreditaciones;
-- @REVERSA@
create function pg_temp.exigir(p_ok boolean,p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if; end $$;
select pg_temp.exigir(not exists(select 1 from funciones_antes
 where huella is distinct from md5(pg_get_functiondef(to_regprocedure(firma)))),'reversa restaura cuerpos exactos');
select pg_temp.exigir(not exists(
 (select * from acreditacion_antes except all select * from crm.conversion_acreditaciones)
 union all (select * from crm.conversion_acreditaciones except all select * from acreditacion_antes)),
 'reversa conserva hechos acreditados para auditoria');
select pg_temp.exigir((select activada_en is null from crm.conversion_politica),'reversa deja politica inactiva');
select pg_temp.exigir(to_regprocedure('private.conversion_conciliar_y_activar(jsonb)') is null,
 'reversa impide activar sobre lectores anteriores');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='pendiente_activacion'
 from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'bundle nuevo conserva puerta compatible despues de reversa');
select 'PASS: reversa compatible sin borrar hechos' as resultado;
rollback;
