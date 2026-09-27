begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
-- @MIGRACION@
-- @RELOJ_CIERRE@
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-09-26 22:00-05'::timestamptz $$;
create function pg_temp.exigir(p_ok boolean,p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if; end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select set_config('crm.op_privilegiada','on',true);
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
 'id','e0000000-0000-4000-8000-00000000f004','numero_contrato','BANCO-CONVERSION-DEMO-SELLO',
 'producto_condicion_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial',null,
 'creado_en','2026-09-25T17:00:00+00:00'))).*
from public.contratos c where id='e0000000-0000-4000-8000-00000000000a';
update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000f004'
where perfil_id='c0000000-0000-4000-8000-000000000001';
select pg_temp.exigir((select estado='acreditada' from crm.conversion_acreditaciones
 where fuente_id='e0000000-0000-4000-8000-00000000f004'),'credito inicialmente valido');
select public.marcar_contrato_demo('e0000000-0000-4000-8000-00000000f004',true,
 'Prueba retirada de la operacion real antes del sello');
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='fuente_demo'
 from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'estado visible y nucleo coinciden al excluir demo');
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-10-11 09:20-05'::timestamptz $$;
select crm.cerrar_periodo('2026-08-01');
select crm.cerrar_periodo('2026-09-01');
select pg_temp.exigir((select incluida_en_sello=false and sellado_en is not null
 from crm.conversion_acreditaciones where fuente_id='e0000000-0000-4000-8000-00000000f004'),
 'el sello conserva que esta fuente ya no sumaba');
create temp table foto_antes as select * from crm.cierre_mes_vendedor;
select crm.anular_cierre_avance((select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'Anulacion posterior de fuente excluida antes del sello');
select pg_temp.exigir(not exists(select 1 from crm.ajustes_mes_cerrado),
 'fuente excluida antes del sello no genera deuda fantasma');
select pg_temp.exigir(not exists(
 (select * from foto_antes except all select * from crm.cierre_mes_vendedor)
 union all (select * from crm.cierre_mes_vendedor except all select * from foto_antes)),
 'anulacion no modifica la foto');
select 'PASS: exclusion anterior al sello no fabrica deuda' as resultado;
rollback;
