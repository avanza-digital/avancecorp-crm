\set ON_ERROR_STOP on
begin;
set local statement_timeout='30s';
\ir fixtures.sql
-- Volumen exclusivamente sintético; los triggers se restauran antes de medir.
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,
 fecha_inicio,fecha_vencimiento,fecha_cierre_comercial,categoria,analista_cierre_id,creado_por,creado_en,producto_condicion_id)
select pg_temp.uid(100000+n),'VOLUMEN-'||n,c.cliente_id,c.capital,c.moneda,c.tasa_anual,c.modalidad,
 c.fecha_inicio,c.fecha_vencimiento,c.fecha_cierre_comercial,'upgrade',c.analista_cierre_id,c.creado_por,c.creado_en,c.producto_condicion_id
from generate_series(1,3000) n cross join public.contratos c where c.id=pg_temp.uid(2010);
insert into crm.operaciones_cartera(id,cliente_id,vendedor_id,tipo,contrato_nuevo_id,fecha_operacion,
 periodo,moneda,elegible_conversion,desglose_completo,fuente,creado_por)
select pg_temp.uid(200000+n),pg_temp.uid(10),pg_temp.uid(4),'upgrade',pg_temp.uid(100000+n),
 '2026-10-05','2026-10-01','PEN',true,true,'flujo_cartera',pg_temp.uid(4) from generate_series(1,3000) n;
set local session_replication_role=origin;
explain (analyze, buffers, timing off)
select count(*) from private.ranking_capital_origen_filas('2026-10-01 00:00:00-05','2026-11-01 00:00:00-05',null);
explain (analyze, buffers, timing off)
select count(*) from private.conversion_episodios('2026-10-01 00:00:00-05','2026-11-01 00:00:00-05','2026-10-01',true,'{}',0.15);
rollback;
