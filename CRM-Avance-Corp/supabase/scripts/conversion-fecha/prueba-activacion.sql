begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
create temp table nucleo_antes as select * from private.conversion_cierres(
 '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null);
-- @MIGRACION@
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-09-26 22:00-05'::timestamptz $$;
create function pg_temp.exigir(p_ok boolean,p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if; end $$;
select pg_temp.exigir(not exists(
 (select * from nucleo_antes except all select * from private.conversion_cierres(
  '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null))
 union all (select * from private.conversion_cierres(
  '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null) except all select * from nucleo_antes)),
 'instalar no vacia ni cambia la lectura anterior');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select pg_temp.exigir((select crm.conversion_estado_lead_v1(id)->>'estado'='pendiente_activacion'
 from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'estado antes de activar no afirma cero credito');

-- Dos vínculos explícitos y dos pendientes sintéticos; sin UUID de producción.
create temp table manifiesto as
select jsonb_build_object('version',1,'politica_desde','2026-09-01','entradas',jsonb_agg(
 jsonb_build_object('lead_id',l.id,'episodio_id',la.id,'analista_id',la.analista_id,
 'origen',l.origen,'perfil_id',l.perfil_id,'inversionista_id',l.inversionista_id,
 'resultado_en',la.resultado_en,'fuente_tipo',case when c.id is not null then 'contrato' end,
 'fuente_id',c.id,'fecha_comercial',c.fecha_cierre_comercial,'confirmado_en',c.creado_en) order by l.id)) as datos
from crm.leads l join crm.lead_asignaciones la on la.lead_id=l.id and la.resultado='convertido'
left join public.contratos c on c.cliente_id=l.perfil_id and c.id in
 ('e0000000-0000-4000-8000-00000000000a','e0000000-0000-4000-8000-00000000000b');
do $$ declare m jsonb; malo jsonb; r jsonb; repetido jsonb; audit_antes bigint;
begin
  select datos into m from manifiesto;
  malo:=jsonb_set(m,'{entradas}',(m->'entradas')-0);
  begin
    perform private.conversion_conciliar_y_activar(malo);
    raise exception 'FAIL: acepto conversion fuera del manifiesto';
  exception when sqlstate 'P0409' then
    if sqlerrm<>'Hay conversiones sin revisar en el manifiesto; actualizar el diagnostico' then raise; end if;
  end;
  perform pg_temp.exigir((select activada_en is null from crm.conversion_politica),'fallo conserva politica anterior');
  perform pg_temp.exigir(not exists(select 1 from crm.conversion_acreditaciones),'fallo no deja conciliacion parcial');
  -- Hacer fallar el último vínculo después de que el primero se insertó:
  -- también ese insert y su auditoría deben revertirse en la subtransacción.
  select jsonb_set(m,'{entradas}',jsonb_agg(case when x->>'fuente_id'='e0000000-0000-4000-8000-00000000000b'
    then x||'{"fecha_comercial":"2020-01-01"}'::jsonb else x end order by ord)) into malo
    from jsonb_array_elements(m->'entradas') with ordinality a(x,ord);
  begin
    perform private.conversion_conciliar_y_activar(malo);
    raise exception 'FAIL: acepto fuente cambiada';
  exception when sqlstate 'PT409' then
    if sqlerrm<>'La fuente contractual cambio desde la revision; no activar' then raise; end if;
  end;
  perform pg_temp.exigir(not exists(select 1 from crm.conversion_acreditaciones),'fallo tardio revierte toda la conciliacion');
  execute $reloj$create or replace function private.conversion_instante_servidor()
    returns timestamptz language sql volatile security invoker set search_path=''
    as 'select ''2026-10-11 00:00-05''::timestamptz'$reloj$;
  begin
    perform private.conversion_conciliar_y_activar(m);
    raise exception 'FAIL: conciliacion inicial fuera de plazo aceptada';
  exception when sqlstate 'P0409' then
    if sqlerrm<>'La conciliacion inicial de septiembre ya esta fuera de plazo' then raise; end if;
  end;
  execute $reloj$create or replace function private.conversion_instante_servidor()
    returns timestamptz language sql volatile security invoker set search_path=''
    as 'select ''2026-09-26 22:00-05''::timestamptz'$reloj$;
  r:=private.conversion_conciliar_y_activar(m);
  perform pg_temp.exigir(r->>'vinculos'='2' and r->>'pendientes'='2','recuentos de activacion');
  select count(*) into audit_antes from public.audit_log where tabla in ('crm.conversion_acreditaciones','crm.conversion_politica');
  repetido:=private.conversion_conciliar_y_activar(m);
  perform pg_temp.exigir(r=repetido,'reintento devuelve activacion original');
  perform pg_temp.exigir((select count(*) from public.audit_log where tabla in ('crm.conversion_acreditaciones','crm.conversion_politica'))=audit_antes,
    'reintento no escribe auditoria adicional');
  perform pg_temp.exigir((select count(*)=2 from private.conversion_cierres(
    '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null)),
    'activacion cambia solo cuando ambos vinculos estan listos');
  begin
    perform private.conversion_conciliar_y_activar(m||'{"otra_version":true}'::jsonb);
    raise exception 'FAIL: segunda activacion distinta aceptada';
  exception when sqlstate 'P0409' then
    if sqlerrm<>'La politica ya fue activada con otro manifiesto' then raise; end if;
  end;
end $$;
-- USAGE existe en producción; exigir la ACL de función, no fallar antes por
-- un permiso ausente del dump. La operación sigue invoker y sin tabla abierta.
grant usage on schema private to authenticated;
select pg_temp.exigir(not has_function_privilege('authenticated',
 'private.conversion_conciliar_y_activar(jsonb)','EXECUTE') and not has_function_privilege('service_role',
 'private.conversion_conciliar_y_activar(jsonb)','EXECUTE') and not has_function_privilege('anon',
 'private.conversion_conciliar_y_activar(jsonb)','EXECUTE'),'activador cerrado a todos los clientes');
-- No ejecutar aquí la llamada denegada: esta imagen local 17.6.1.105 cae con
-- SIGSEGV en la ruta de error de supautils.hint_roles, antes del cuerpo SQL.
-- Reproducción y reporte: https://github.com/supabase/supautils/issues/214
-- ACL efectiva comprobada arriba. Rechazo en ejecución: pendiente de ensayo
-- remoto compatible; no relajar grants ni modificar la configuración local.
select 'PASS: activacion atomica y lectura anterior preservada' as resultado;
rollback;
