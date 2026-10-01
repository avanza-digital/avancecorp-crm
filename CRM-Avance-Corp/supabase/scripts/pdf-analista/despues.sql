create temporary table nuevo as select private.contrato_pdf_snapshot_v2_base(
 'e0000000-0000-4000-8000-000000000099') snapshot;
select pg_temp.exigir((select snapshot->>'snapshotVersion'='3'
 and snapshot->'contrato'->>'creadoPor'='b0000000-0000-4000-8000-000000000002'
 and snapshot->'contrato'->>'analistaId'='b0000000-0000-4000-8000-000000000001'
 and snapshot->'analista'->>'id'=snapshot->'contrato'->>'analistaId'
 and snapshot->'analista'->>'nombreCompleto'='ANALISTA ASIGNADA'
 and snapshot->'analista'->>'correo'='asignada@example.test'
 and snapshot->'analista'->>'celular'='999333444' from nuevo),
 'identidad y contacto completos de la asignada; creador preservado');
select pg_temp.exigir((select (n.snapshot-'snapshotVersion'-'analista') #- '{contrato,analistaId}'
 = a.snapshot-'snapshotVersion'-'analista' from nuevo n cross join anterior a),
 'titular, cuenta, cotitulares, cronograma y condiciones idénticos');
select pg_temp.exigir(not exists(select 1 from permisos a join pg_proc p using(oid)
 where (a.proacl,a.prosecdef,a.proconfig) is distinct from (p.proacl,p.prosecdef,p.proconfig)),
 'ACL, SECURITY DEFINER y search_path intactos');
select pg_temp.exigir(private.contrato_pdf_anexo_snapshot_base('e0000000-0000-4000-8000-000000000099')
 ->'snapshot'->>'snapshotVersion'='2','anexo de la revisión histórica sigue disponible');
-- La misma puerta que usa el formulario: una revisión con iguales metadatos.
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
set local role authenticated;
select crm.actualizar_numero_contrato_pdf_v3('e0000000-0000-4000-8000-000000000099',
 '2026-01-009991',null,'nuevo');
reset role;
select pg_temp.sellar('e0000000-0000-4000-8000-000000000099','b0000000-0000-4000-8000-000000000003');
select pg_temp.exigir((select count(*)=2 from private.contrato_pdfs where contrato_id='e0000000-0000-4000-8000-000000000099'),
 'revisión nueva emitida sin borrar la anterior');
select pg_temp.exigir((select h.fila=to_jsonb(p) from historico h join private.contrato_pdfs p on p.id=(h.fila->>'id')::uuid),
 'ledger histórico byte a byte intacto');
select pg_temp.exigir((select a.fila=to_jsonb(c)-'actualizado_en' from condiciones a cross join public.contratos c
 where c.id='e0000000-0000-4000-8000-000000000099'),'contrato y número conservados');
select pg_temp.exigir(private.contrato_pdf_anexo_snapshot_base('e0000000-0000-4000-8000-000000000099')
 ->'snapshot'->>'snapshotVersion'='3','anexo acepta la revisión nueva');
select crm.contrato_pdf_anexo_emitido('e0000000-0000-4000-8000-000000000099',
 'b0000000-0000-4000-8000-000000000003',
 (select id from private.contrato_pdfs where contrato_id='e0000000-0000-4000-8000-000000000099' and revision=2),
 'anexo-cronograma-v1',repeat('b',64),8192);
select pg_temp.exigir((select count(*)=1 from private.contrato_pdf_anexo_emisiones), 'anexo v3 registra su emisión');
select pg_temp.exigir(pg_temp.rechaza($q$update private.contrato_pdf_jobs set snapshot='{}'::jsonb
 where contrato_id='e0000000-0000-4000-8000-000000000099'$q$,'55000'), 'snapshots siguen inmutables');
select pg_temp.exigir(pg_temp.rechaza($q$select private.crear_revision_contrato_pdf_base(
 'e0000000-0000-4000-8000-000000000099','c0000000-0000-4000-8000-000000000004')$q$,'42501'),
 'actor ajeno no puede reservar una revisión');
select pg_temp.exigir(not has_function_privilege('anon','crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)','EXECUTE')
 and not has_function_privilege('authenticated','private.contrato_pdf_snapshot_v2_base(uuid)','EXECUTE'),
 'sin acceso anónimo a corrección ni acceso directo autenticado al snapshot');
-- Sin responsable no se sustituye silenciosamente por el creador.
savepoint sin_asignado;
-- Estado legado inválido inyectado por el dueño del banco, no una puerta de usuario.
select set_config('crm.reasignando_analista','on',true);
update public.contratos set analista_cierre_id=null where id='e0000000-0000-4000-8000-000000000099';
select pg_temp.exigir(pg_temp.rechaza($q$select private.contrato_pdf_snapshot_v2_base(
 'e0000000-0000-4000-8000-000000000099')$q$,'23514'),'sin analista se rechaza');
rollback to savepoint sin_asignado;
savepoint contacto_incompleto;
update public.perfiles set correo=null where id='b0000000-0000-4000-8000-000000000001';
select pg_temp.exigir(pg_temp.rechaza($q$select private.contrato_pdf_snapshot_v2_base(
 'e0000000-0000-4000-8000-000000000099')$q$,'23514'),'contacto incompleto se rechaza');
rollback to savepoint contacto_incompleto;
select 'SNAPSHOT:'||snapshot::text from nuevo;
