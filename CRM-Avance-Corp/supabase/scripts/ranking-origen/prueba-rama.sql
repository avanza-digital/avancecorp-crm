-- Ejecutar con psql, ON_ERROR_STOP, SOLO después de semilla-rama.sql.
-- ROLLBACK mantiene reutilizable el banco. Los RPC corren como authenticated.
begin;
set local timezone='America/Lima';
set local statement_timeout='30s';
do $$ declare m record; n int; begin
if (select count(*) from crm.leads)<>2048 then raise exception 'Semilla incompleta';end if;
for m in select * from crm.meta_periodos loop
with original as(select * from private.produccion_mes_por_vendedor(m.periodo::timestamptz,(m.periodo+interval '1 month')::timestamptz,m.id)),
detalle as(select vendedor_id,categoria,moneda,count(*)::int contratos_real,sum(capital) capital_real from private.ranking_capital_origen_filas(m.periodo::timestamptz,(m.periodo+interval '1 month')::timestamptz,m.id) group by 1,2,3)
select count(*) into n from original o full join detalle d using(vendedor_id,categoria,moneda) where o.contratos_real is distinct from d.contratos_real or o.capital_real is distinct from d.capital_real;
if n<>0 then raise exception 'Paridad rota en %',m.periodo;end if;
end loop;
if has_function_privilege('anon','crm.ranking_origen_vendedor_fn(date,uuid)','EXECUTE') or has_function_privilege('authenticated','private.ranking_origen_live(date,uuid,jsonb)','EXECUTE') then raise exception 'ACL abierta';end if;
raise notice 'PASS: paridad dos meses por vendedor/categoría/moneda y ACL';
end $$;
savepoint casos_origen;
set local session_replication_role=replica;
update crm.leads set contrato_id=md5('ranking-contrato-1')::uuid,origen='formulario' where id=md5('ranking-lead-17')::uuid;
update public.contratos set capital=1000.01 where id=md5('ranking-contrato-1')::uuid;
insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en)
values(md5('ranking-coop')::uuid,md5('ranking-lead-1')::uuid,'qorilazo',500.37,'PEN','DNI','12345678','PRUEBA','RANKING-COOP','b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000003','2026-08-15 12:00:00-05');
set local session_replication_role=origin;
do $$ declare n int;canal text;capital numeric;j jsonb;begin
select count(*),min(origen),sum(f.capital) into n,canal,capital from private.ranking_capital_origen_filas('2026-08-01','2026-09-01',md5('ranking-meta-08')::uuid) f where operacion_id=md5('ranking-contrato-1')::uuid;
if n<>1 or canal<>'sin_origen' or capital<>1000.01 then raise exception 'Capital duplicado o canal ambiguo';end if;
select count(*),min(origen),sum(f.capital) into n,canal,capital from private.ranking_capital_origen_filas('2026-08-01','2026-09-01',md5('ranking-meta-08')::uuid) f where operacion_id=md5('ranking-coop')::uuid;
if n<>1 or canal<>'landing' or capital<>500.37 then raise exception 'Capital cooperativo incorrecto';end if;
select private.ranking_origen_live('2026-08-01','b0000000-0000-4000-8000-000000000002',jsonb_agg(jsonb_build_object('moneda',p.moneda,'capital_real',p.capital_real))) into j from private.produccion_mes_por_vendedor('2026-08-01','2026-09-01',md5('ranking-meta-08')::uuid) p where vendedor_id='b0000000-0000-4000-8000-000000000002';
if (j->>'disponible')::boolean is distinct from true then raise exception 'Capital fraccionario no concilia';end if;
if exists(select 1 from private.ranking_conversion_origen_mes('2026-08-01','2026-09-01','2026-08-01',null) where origen='referido' and conversion_pct is not null) then raise exception 'Referido sin peso afirma tasa';end if;
j:=private.ranking_origen_live('2026-08-01','b0000000-0000-4000-8000-000000000002','[{"moneda":"PEN","capital_real":1}]');
if (j->>'disponible')::boolean is distinct from false then raise exception 'Descuadre publicado';end if;
raise notice 'PASS: ambigüedad sin duplicados, cooperativa, decimales, peso ausente y descuadre fail-closed';
end $$;
rollback to casos_origen;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
do $$ declare j jsonb;begin
j:=crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002');
if (j->>'disponible')::boolean is distinct from true or jsonb_array_length(j->'filas')<4 then raise exception 'RPC gerencia no disponible';end if;
raise notice 'PASS: gerencia obtiene desglose real y cuatro canales';
end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
do $$ begin
if (crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002')->>'disponible')::boolean is distinct from true then raise exception 'Supervisor propio denegado';end if;
raise notice 'PASS: supervisor propio';end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000004',true);
do $$ begin
begin perform crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002');raise exception 'Supervisor ajeno permitido';exception when insufficient_privilege then null;end;
raise notice 'PASS: supervisor ajeno denegado';end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$ begin
begin perform crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000005');raise exception 'Vendedor ajeno permitido';exception when insufficient_privilege then null;end;
raise notice 'PASS: vendedor ajeno denegado';end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000006',true);
do $$ begin
begin perform crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002');raise exception 'Inactivo permitido';exception when insufficient_privilege then null;end;
raise notice 'PASS: inactivo denegado';end $$;
reset role;
-- Deuda sintética de julio: prueba del NETO real, no un payload inventado.
set local session_replication_role=replica;
insert into crm.periodos_cerrados(periodo,ponderacion_referido,ponderacion_renovacion,meta_revision,cobertura)
values('2026-07-01',0.15,0.15,0,'{}');
insert into crm.ajustes_mes_cerrado(vendedor_id,periodo_origen,lead_id,motivo,creado_por,numerador,capital_pen,detalle,pendiente_numerador,pendiente_pen,pendiente_detalle)
values('b0000000-0000-4000-8000-000000000002','2026-07-01',md5('ranking-lead-1')::uuid,'PRUEBA AJUSTE','b0000000-0000-4000-8000-000000000003',1,100,
'[{"categoria":"nuevo","moneda":"PEN","capital":100,"contratos":1}]',1,100,'[{"categoria":"nuevo","moneda":"PEN","capital":100,"contratos":1}]');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
do $$ declare j jsonb; t timestamptz:=clock_timestamp(); j2 jsonb; v_pct numeric;begin
select (f->>'conversion_pct')::numeric into v_pct from jsonb_array_elements(crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002')->'filas') f where f->>'origen'='referido';
j:=crm.ranking_origen_vendedor_fn('2026-09-01','b0000000-0000-4000-8000-000000000002');
-- El payload canónico vivo anuncia la deuda en conversión; el capital se
-- descuenta al sellar. No se inventa un descuento antes de ese momento.
if (j->>'disponible')::boolean is distinct from true then raise exception 'Mes vivo no conciliado: %',j;end if;
j2:=crm.cerrar_periodo('2026-08-01');
if (j2->>'ok')::boolean is distinct from true or (j2->>'vendedores')::int<30 then raise exception 'Cierre real incompleto: %',j2;end if;
raise notice 'PASS: cierre real de % vendedores y 2048 leads en % ms',j2->>'vendedores',extract(epoch from clock_timestamp()-t)*1000;
j2:=crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002');
if (select (f->>'conversion_pct')::numeric from jsonb_array_elements(j2->'filas') f where f->>'origen'='referido') is distinct from v_pct or v_pct is distinct from 15::numeric then raise exception 'Peso de Referido cambió en el sello';end if;
if (j2->>'disponible')::boolean is distinct from true or not exists(select 1 from jsonb_array_elements(j2->'filas') f where f->>'origen'='ajuste' and (f->>'capital_pen')::numeric=-100)
or (select sum((f->>'capital_pen')::numeric) from jsonb_array_elements(j2->'filas') f)<>11900 then raise exception 'La foto sellada no conserva el neto: %',j2;end if;
raise notice 'PASS: RPC sellado concilia S/ 11900 netos, con ajuste real de S/ 100';
end $$;
reset role;
create temporary table ranking_foto as select crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002') j;
set local session_replication_role=replica;
update crm.leads set origen='otro' where creado_en<'2026-09-01'::timestamptz;
set local session_replication_role=origin;
do $$ begin
if (select j from ranking_foto) is distinct from crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002') then raise exception 'RPC sellado reconstruye origen';end if;
begin update crm.cierre_mes_vendedor set origenes_ranking=null where periodo='2026-08-01';raise exception 'Sello editable';exception when sqlstate 'P0409' then null;end;
raise notice 'PASS: foto independiente de origen actual e inmutable';
end $$;
set local session_replication_role=replica;
update crm.cierre_mes_vendedor set origenes_ranking=null where periodo='2026-08-01';
set local session_replication_role=origin;
do $$ begin
if (crm.ranking_origen_vendedor_fn('2026-08-01','b0000000-0000-4000-8000-000000000002')->>'disponible')::boolean is distinct from false then raise exception 'Foto antigua reconstruida';end if;
raise notice 'PASS: foto antigua sin desglose no se reconstruye';end $$;
rollback;
