-- Banco sintético de semilla-rama.sql. Ejecutar exclusivamente en rama autorizada.
begin;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,
  fecha_inicio,fecha_vencimiento,fecha_cierre_comercial,categoria,analista_cierre_id,creado_por,producto_condicion_id)
select md5('ranking-desglose-'||n)::uuid,'RANKING-DESGLOSE-'||n,
  'b0000000-0000-4000-8000-000000000008',monto,moneda,'anual',
  '2026-09-09','2027-09-09','2026-09-09',categoria,
  'b0000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000005',md5('ranking-condicion')::uuid
from (values(1,577554,'PEN','nuevo'),(2,29000,'USD','upgrade'),(3,11000,'USD','upgrade')) d(n,monto,moneda,categoria);
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
  fecha_operacion,periodo,moneda,elegible_conversion,desglose_completo,fuente,creado_por)
select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,'2026-09-01',moneda,
  false,true,'flujo_cartera',creado_por from public.contratos where numero_contrato like 'RANKING-DESGLOSE-%';
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
do $$ declare v1 jsonb; v2 jsonb; d jsonb;begin
 v1:=crm.ranking_origen_vendedor_fn('2026-09-01','b0000000-0000-4000-8000-000000000005');
 v2:=crm.ranking_origen_vendedor_v2_fn('2026-09-01','b0000000-0000-4000-8000-000000000005');
 if v1 <> (v2-'cartera')||jsonb_build_object('version',1) then raise exception 'v1 cambió';end if;
 select x into d from jsonb_array_elements(v2->'cartera') x where x->>'categoria'='upgrade';
 if d is distinct from '{"categoria":"upgrade","pen":577554,"usd":40000}'::jsonb then raise exception 'Caso captura incorrecto: %',v2;end if;
 if (select sum((x->>'pen')::numeric) from jsonb_array_elements(v2->'cartera') x)<>577554 then raise exception 'Duplicación';end if;
 raise notice 'PASS: captura 577554 PEN + 40000 USD, ledger no elegible para conversión y v1 idéntica';
end $$;
reset role;
-- Un enlace de otro cliente no prueba que sea cartera; no se atribuye por importe.
set local session_replication_role=replica;
update crm.operaciones_cartera set cliente_id='b0000000-0000-4000-8000-000000000007'
where contrato_nuevo_id=md5('ranking-desglose-1')::uuid;
set local session_replication_role=origin;
do $$ declare j jsonb;begin
 j:=crm.ranking_origen_vendedor_v2_fn('2026-09-01','b0000000-0000-4000-8000-000000000005');
 if not exists(select 1 from jsonb_array_elements(j->'filas') x where x->>'origen'='sin_origen' and (x->>'capital_pen')::numeric=577554)
 or not exists(select 1 from jsonb_array_elements(j->'cartera') x where x->>'categoria'='upgrade' and (x->>'pen')::numeric=0 and (x->>'usd')::numeric=40000)
 then raise exception 'Aceptó vínculo de cliente distinto: %',j;end if;
 if private.ranking_cartera_desglose('2026-09-01','b0000000-0000-4000-8000-000000000005',
 '{"disponible":true,"filas":[{"origen":"cartera","capital_pen":1,"capital_usd":40000}]}') is not null then raise exception 'Aceptó importes no conciliados';end if;
 raise notice 'PASS: vínculo inválido rechazado; no publica importes parciales';
end $$;
rollback;
