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

-- Dos fuentes nuevas exclusivamente sintéticas, sin PDF ni pagos. La puerta
-- auditada retira contrato e inversión respetando sus FK; HTTP sigue aparte.
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
 'id',f.nueva,'numero_contrato',f.numero,
 'producto_condicion_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial',null,
 'creado_en','2026-09-25T17:00:00+00:00'))).*
from (values
 ('e0000000-0000-4000-8000-00000000000a'::uuid,'e0000000-0000-4000-8000-00000000f005','BANCO-RETIRO-ANTES'),
 ('e0000000-0000-4000-8000-00000000000b'::uuid,'e0000000-0000-4000-8000-00000000f006','BANCO-RETIRO-DESPUES')
) f(original,nueva,numero) join public.contratos c on c.id=f.original;
update crm.leads set contrato_id=case perfil_id
 when 'c0000000-0000-4000-8000-000000000001' then 'e0000000-0000-4000-8000-00000000f005'::uuid
 else 'e0000000-0000-4000-8000-00000000f006'::uuid end
where perfil_id in ('c0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002');
select pg_temp.exigir((select count(*)=2 and bool_and(estado='acreditada') from crm.conversion_acreditaciones),
 'ambas fuentes acreditadas inicialmente');
select crm.contrato_eliminar_auditado('e0000000-0000-4000-8000-00000000f005',
 'b0000000-0000-4000-8000-000000000003');
select pg_temp.exigir((select count(*)=2 from crm.conversion_acreditaciones),'retirar fuente conserva trazabilidad');
select pg_temp.exigir((select count(*)=1 from private.conversion_cierres(
 '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null)),
 'fuente retirada antes del sello no suma');
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-10-11 09:20-05'::timestamptz $$;
select crm.cerrar_periodo('2026-08-01');
select crm.cerrar_periodo('2026-09-01');
select pg_temp.exigir((select bool_and(incluida_en_sello=(fuente_id='e0000000-0000-4000-8000-00000000f006'))
 from crm.conversion_acreditaciones),'sello distingue retiro previo de fuente incluida');
create temp table foto_antes as select * from crm.cierre_mes_vendedor;
select crm.contrato_eliminar_auditado('e0000000-0000-4000-8000-00000000f006',
 'b0000000-0000-4000-8000-000000000003');
select pg_temp.exigir((select bool_and(crm.conversion_estado_lead_v1(lead_id)->>'estado'='fuente_retirada')
 from crm.conversion_acreditaciones),'ambas retiradas se explican sin borrar fotos');
select crm.anular_cierre_avance(id,'Anulacion sintetica despues de retirar fuente')
from crm.leads where perfil_id in ('c0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002')
order by perfil_id;
select pg_temp.exigir((select count(*)=1 and bool_and(a.lead_id=ca.lead_id and a.numerador=1
 and a.capital_pen=0 and a.capital_usd=0) from crm.ajustes_mes_cerrado a cross join
 (select lead_id from crm.conversion_acreditaciones where fuente_id='e0000000-0000-4000-8000-00000000f006') ca),
 'solo la fuente incluida en el sello genera deuda posterior');
select pg_temp.exigir(not exists(
 (select * from foto_antes except all select * from crm.cierre_mes_vendedor)
 union all (select * from crm.cierre_mes_vendedor except all select * from foto_antes)),
 'retiro y anulaciones no reescriben fotos');
select 'PASS: retiro antes y despues del sello conserva evidencia y deuda correcta' as resultado;
rollback;
