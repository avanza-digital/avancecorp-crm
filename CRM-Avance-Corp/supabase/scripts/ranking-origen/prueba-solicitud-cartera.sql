-- Banco sintético autorizado con semilla-rama.sql. No usar producción.
begin;
set local session_replication_role=replica;
insert into crm.empresas(id,clave,nombre_legal,nombre_visible,fuente_capital)
values(md5('ranking-empresa-avance')::uuid,'avance','PRUEBA AVANCE','PRUEBA','contratos'),
 (md5('ranking-empresa-qorilazo')::uuid,'qorilazo','PRUEBA QORI','PRUEBA','cierres_externos');
insert into crm.inversionistas(id) values(md5('ranking-persona-cartera')::uuid);
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,
 fecha_inicio,fecha_vencimiento,fecha_cierre_comercial,categoria,analista_cierre_id,creado_por,producto_condicion_id)
select md5('ranking-solicitud-contrato-'||n)::uuid,'RANKING-SOLICITUD-'||n,
 'b0000000-0000-4000-8000-000000000008',monto,'PEN','anual','2026-09-09','2027-09-09','2026-09-09','nuevo',
 'b0000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000005',md5('ranking-condicion')::uuid
from (values(1,35000),(2,10000)) d(n,monto);
insert into storage.buckets(id,name) values('f4-comprobantes','f4-comprobantes');
insert into storage.objects(id,bucket_id,name) values(md5('ranking-comprobante')::uuid,'f4-comprobantes','prueba-ranking.pdf');
insert into crm.cierres_externos(id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,
 numero_transaccion,vendedor_id,creado_por,creado_en,fecha_comercial,fecha_imputacion,inversionista_id,es_cierre_inicial,comprobante_objeto_id,referencia_externa)
values(md5('ranking-solicitud-cierre')::uuid,'qorilazo',20000,'PEN','DNI','12345678','PRUEBA',
 'RANKING-SOLICITUD-COOP','b0000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000005',
 '2026-09-09 12:00-05','2026-09-09','2026-09-09',md5('ranking-persona-cartera')::uuid,false,md5('ranking-comprobante')::uuid,'PRUEBA');
insert into crm.inversiones(id,inversionista_id,empresa_id,contrato_id,cierre_externo_id,fecha_comercial,creado_por)
select md5('ranking-inversion-'||n)::uuid,md5('ranking-persona-cartera')::uuid,
 md5(case when n=3 then 'ranking-empresa-qorilazo' else 'ranking-empresa-avance' end)::uuid,
 case when n<3 then md5('ranking-solicitud-contrato-'||n)::uuid end,
 case when n=3 then md5('ranking-solicitud-cierre')::uuid end,
 '2026-09-09','b0000000-0000-4000-8000-000000000005' from generate_series(1,3) n;
insert into crm.inversion_solicitudes(id,inversionista_id,empresa_id,responsable_esperado_id,hash_payload,
 datos,estado,inversion_id,resultado,creado_por,confirmado_por)
select md5('ranking-solicitud-'||n)::uuid,md5('ranking-persona-cartera')::uuid,
 md5(case when n=3 then 'ranking-empresa-qorilazo' else 'ranking-empresa-avance' end)::uuid,
 'b0000000-0000-4000-8000-000000000005',repeat('a',64),'{}',
 case when n=2 then 'preparada' else 'confirmada' end,
 case when n<>2 then md5('ranking-inversion-'||n)::uuid end,
 case when n<>2 then jsonb_build_object('fuente',jsonb_build_object(
 case when n=3 then 'cierre_id' else 'id' end,
 md5(case when n=3 then 'ranking-solicitud-cierre' else 'ranking-solicitud-contrato-'||n end)::uuid)) end,
 'b0000000-0000-4000-8000-000000000005',
 case when n<>2 then 'b0000000-0000-4000-8000-000000000005'::uuid end from generate_series(1,3) n;
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$ declare j jsonb;begin
 j:=crm.ranking_origen_vendedor_v2_fn('2026-09-01','b0000000-0000-4000-8000-000000000005');
 if not exists(select 1 from jsonb_array_elements(j->'cartera') x where x->>'categoria'='nuevo' and (x->>'pen')::numeric=55000)
 or not exists(select 1 from jsonb_array_elements(j->'filas') x where x->>'origen'='sin_origen' and (x->>'capital_pen')::numeric=10000)
 or (select sum((x->>'capital_pen')::numeric) from jsonb_array_elements(j->'filas') x)<>65000
 then raise exception 'Solicitud no clasifica o cambia capital: %',j;end if;
 raise notice 'PASS: contratos y COOPAC desde cartera → Nueva inversión; solicitud pendiente excluida, capital intacto';
end $$;
reset role;
-- La solicitud ha de acreditar la misma fuente, no basta el espejo.
set local session_replication_role=replica;
update crm.inversion_solicitudes set resultado='{"fuente":{"id":"00000000-0000-4000-8000-000000000001"}}'
where id=md5('ranking-solicitud-1')::uuid;
set local session_replication_role=origin;
do $$begin
 if private.ranking_solicitud_cartera(md5('ranking-solicitud-contrato-1')::uuid,null)
 or private.ranking_solicitud_cartera(md5('ranking-solicitud-contrato-1')::uuid,md5('ranking-solicitud-cierre')::uuid)
 then raise exception 'Aceptó fuente distinta o parámetros ambiguos';end if;
 raise notice 'PASS: fuente exacta obligatoria, no se infiere la procedencia por contacto ni importe';
end $$;
rollback;
