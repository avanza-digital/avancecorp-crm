create function pg_temp.exigir(ok boolean, mensaje text) returns text language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',mensaje; end if; return 'PASS: '||mensaje; end $$;
create function pg_temp.rechaza(sql text, codigo text) returns boolean language plpgsql as $$
begin execute sql; return false; exception when others then
 if sqlstate<>codigo then raise; end if; return true; end $$;
create function pg_temp.sellar(contrato uuid, actor uuid) returns jsonb language plpgsql as $$
declare c jsonb;
begin
 c:=crm.contrato_pdf_reclamar(contrato,actor,120);
 perform crm.contrato_pdf_marcar_subido((c->>'job_id')::uuid,(c->>'lease_token')::uuid,actor,repeat('a',64),8192);
 return crm.contrato_pdf_finalizar((c->>'job_id')::uuid,(c->>'lease_token')::uuid,actor);
end $$;
create temporary table anterior as select private.contrato_pdf_snapshot_v2_base(
 'e0000000-0000-4000-8000-000000000099') snapshot;
select pg_temp.exigir((select snapshot->'analista'->>'nombreCompleto'='CREADOR DE PRUEBA' from anterior),
 'reproducción: el snapshot anterior toma al creador aunque el contrato tiene otra analista');
select private.crear_job_contrato_pdf_base('e0000000-0000-4000-8000-000000000099','b0000000-0000-4000-8000-000000000003');
select pg_temp.sellar('e0000000-0000-4000-8000-000000000099','b0000000-0000-4000-8000-000000000003');
create temporary table historico as select to_jsonb(p) fila from private.contrato_pdfs p
 where contrato_id='e0000000-0000-4000-8000-000000000099';
create temporary table condiciones as select to_jsonb(c)-'actualizado_en' fila from public.contratos c
 where id='e0000000-0000-4000-8000-000000000099';
create temporary table permisos as select oid,proacl,prosecdef,proconfig from pg_proc
 where oid in ('private.contrato_pdf_snapshot_v2_base(uuid)'::regprocedure,
 'private.contrato_pdf_anexo_snapshot_base(uuid)'::regprocedure,
 'private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)'::regprocedure);
