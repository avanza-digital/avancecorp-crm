begin;
set local statement_timeout='20s';
-- El dump sintético heredado omitió ACL. Reponer SOLO los grants reales que
-- usa este test (consulta de catálogo productivo de solo lectura 27/09).
-- No cambiar las policies, el actor gate ni los triggers. Todo hace ROLLBACK.
grant usage on schema crm,private to authenticated;
grant select(id,perfil_id,contrato_id) on crm.leads to authenticated;
grant update(contrato_id) on crm.leads to authenticated;
-- @MIGRACION@
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-09-26 22:00-05'::timestamptz $$;
create function pg_temp.exigir(p_ok boolean,p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if; end $$;
select private.conversion_acreditar_fuente(
 (select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'contrato','e0000000-0000-4000-8000-00000000000a','Fuente para lectura autorizada');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='acreditada'
 from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'analista consulta su acreditacion');
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='pendiente_fuente'
 from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000002'),
 'pendiente sin fuente no parece acreditado');
-- El grant por columna no basta: el BEFORE real restaura el vínculo. No se
-- activa crm.op_privilegiada en esta sesión de cliente.
update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000000b'
where perfil_id='c0000000-0000-4000-8000-000000000001';
select pg_temp.exigir((select contrato_id is null from crm.leads
 where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'cliente no puede escoger otra fuente con update directo');
do $$ begin
  begin
    perform crm.conversion_estado_lead_v1('ffffffff-ffff-4fff-8fff-ffffffffffff');
    raise exception 'FAIL: ID inexistente aceptado';
  exception when insufficient_privilege then
    if sqlerrm<>'Lead no disponible en tu ambito' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='acreditada'
 from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'supervisor consulta su subarbol');
reset role;

-- Un vendedor activo fuera del ámbito no obtiene detalles por UUID.
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select set_config('crm.op_privilegiada','on',true);
create temp table objetivo as select id from crm.leads
 where perfil_id='c0000000-0000-4000-8000-000000000001';
grant select on objetivo to authenticated;
update crm.leads set vendedor_id='b0000000-0000-4000-8000-000000000001' where id in (select id from objetivo);
select set_config('crm.op_privilegiada','off',true);
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$ begin
  begin
    perform crm.conversion_estado_lead_v1((select id from objetivo));
    raise exception 'FAIL: vendedor accede a lead ajeno';
  exception when insufficient_privilege then
    if sqlerrm<>'Lead no disponible en tu ambito' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
set local role authenticated;
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='acreditada' from objetivo),
 'gerencia consulta estado sin reatribuir analista');
reset role;
update crm.equipo set activo=false where perfil_id='b0000000-0000-4000-8000-000000000003';
set local role authenticated;
do $$ begin
  begin
    perform crm.conversion_estado_lead_v1((select id from objetivo));
    raise exception 'FAIL: miembro revocado accede al estado';
  exception when insufficient_privilege then
    if sqlerrm<>'Sin acceso al CRM' then raise; end if;
  end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform crm.conversion_estado_lead_v1('ffffffff-ffff-4fff-8fff-ffffffffffff');
    raise exception 'FAIL: anon invoca puerta de estado';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select 'PASS: lectura de estado y ambito real' as resultado;
rollback;
