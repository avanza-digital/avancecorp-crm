-- Banco derivado de ranking_enlaces_20260926, solo fixtures sintéticos.
-- Todos los cambios (incluida la migración) se deshacen al terminar.
begin;
set local statement_timeout = '40s';
set local lock_timeout = '3s';
select set_config('crm.op_privilegiada','on',true);

create function pg_temp.exigir(ok boolean, mensaje text) returns void
language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'FAIL: %',mensaje; end if;
  raise notice 'PASS: %',mensaje;
end $$;
select pg_temp.exigir(current_database()='ranking_cartera_20260926','destino sintético exclusivo');
select pg_temp.exigir((select count(*)=3 from public.contratos where numero_contrato in ('BANCO-A1','BANCO-A2','BANCO-A3')),'fixtures de tres upgrades presentes');
select pg_temp.exigir(exists(select 1 from pg_index i
 join pg_attribute a on a.attrelid=i.indrelid and a.attname='contrato_nuevo_id'
 where i.indrelid='crm.operaciones_cartera'::regclass and i.indisunique
 and i.indisvalid and i.indisready and i.indnkeyatts=1
 and i.indkey[0]=a.attnum and i.indpred is null),
 'índice único de contrato nuevo disponible para EXISTS');

-- Conservar los términos válidos del fixture: 22000 + 30000 + 18000.
-- El caso productivo 150000 se concilia por lectura aparte, no se copia PII.
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
  fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
  date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
from public.contratos where numero_contrato in ('BANCO-A1','BANCO-A2','BANCO-A3');

-- Un cierre cooperativo real en el banco evita una comparación vacía de esa rama.
insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
  nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en)
values('79119955-54e8-441b-8298-dcbc9ed20291','qorilazo',1000,'PEN','DNI','12345678',
  'Prueba cartera','CARTERA-LOCAL-20260926','b0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000003','2026-09-15 12:00:00-05');

create temp table contexto as select id as meta from crm.meta_periodos
where periodo=date '2026-09-01' order by revision desc limit 1;
create function pg_temp.filas() returns table(vendedor_id uuid,origen text,moneda text,
 capital numeric,categoria text,operacion_id uuid) language sql as $$
 select f.* from contexto x cross join lateral private.ranking_capital_origen_filas(
 '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05',x.meta) f
$$;
create function pg_temp.invariantes() returns jsonb language sql as $$
 select jsonb_build_object(
 'contratos',(select jsonb_agg(to_jsonb(x) order by id) from public.contratos x),
 'leads',(select jsonb_agg(to_jsonb(x) order by id) from crm.leads x),
 'ledger',(select jsonb_agg(to_jsonb(x) order by id) from crm.operaciones_cartera x),
 'fuentes',(select jsonb_agg(to_jsonb(x) order by id) from crm.cierres_externos x),
 'inversiones',(select jsonb_agg(to_jsonb(x) order by id) from crm.inversiones x),
 'auditoria',(select count(*) from public.audit_log),
 'produccion',(select jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text) from contexto x
   cross join lateral private.produccion_mes_por_vendedor('2026-09-01 00:00:00-05','2026-10-01 00:00:00-05',x.meta) f),
 'conversion',(select jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text) from private.conversion_cierres(
   '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05','2026-09-01',true,'{}'::uuid[],0.15,null::uuid[]) f),
 'canales',(select jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text) from private.ranking_conversion_origen_mes(
   '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05','2026-09-01',0.15) f),
 'sellos',(select jsonb_agg(to_jsonb(s) order by periodo,vendedor_id) from crm.cierre_mes_vendedor s))
$$;
create temp table antes as select pg_temp.invariantes() as datos;
create temp table filas_antes as select * from pg_temp.filas();
create temp table permisos_antes as select proowner,proacl,proconfig,prorettype,proargtypes,proallargtypes,proargmodes,proargnames,prosecdef,provolatile
from pg_proc where oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure;
create temp table esperado as
select f.* from filas_antes f;
-- Oráculo independiente y explícito para este banco, no repite el CASE del candidato.
update esperado set origen='cartera' where operacion_id in
 ('e0000000-0000-4000-8000-00000000000a','e0000000-0000-4000-8000-00000000000b',
  'e0000000-0000-4000-8000-000000000010','e0000000-0000-4000-8000-00000000000d',
  'e0000000-0000-4000-8000-00000000000f');
select pg_temp.exigir((select count(*)=5 and count(distinct e.moneda)=2
 and count(*) filter(where e.moneda='PEN')=3 and count(*) filter(where e.moneda='USD')=2
 from esperado e join filas_antes a using(operacion_id) where e.origen<>a.origen),
 'cinco diferencias esperadas no vacías, en PEN y USD');

-- @MIGRACION@

select pg_temp.exigir((select datos=pg_temp.invariantes() from antes),
 'contratos, leads, ledger, auditoría, capital, conversión, canales y sellos idénticos');
select pg_temp.exigir(not exists((select * from esperado except all select * from pg_temp.filas())
 union all (select * from pg_temp.filas() except all select * from esperado)),
 'solo cinco cambios de canal, sin duplicar filas ni mover vendedores');
select pg_temp.exigir((select sum(f.capital)=70000 and count(*)=3 and bool_and(f.origen='cartera' and f.moneda='PEN' and f.categoria='nuevo')
 from pg_temp.filas() f join public.contratos c on c.id=f.operacion_id
 where c.numero_contrato in ('BANCO-A1','BANCO-A2','BANCO-A3')),
 'tres upgrades PEN: Cartera por 70000 del fixture sin recategorizar contrato');
select pg_temp.exigir(not exists(select 1 from crm.inversiones where contrato_id='e0000000-0000-4000-8000-00000000000a')
 and (select count(*)=2 from crm.inversiones where contrato_id in
 ('e0000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-000000000010')),
 'misma clasificación con un contrato sin espejo y dos con espejo');
select pg_temp.exigir((select count(*)=1 and sum(capital)=1000 and bool_and(origen='landing') from pg_temp.filas() f
 join crm.cierres_externos ce on ce.id=f.operacion_id),'COOPAC conserva origen y monto');
select pg_temp.exigir(not exists(select 1 from pg_temp.filas() group by operacion_id having count(*)>1),
 'una fila por operación');
select pg_temp.exigir((select row(p.proowner,p.proacl,p.proconfig,p.prorettype,p.proargtypes,p.proallargtypes,p.proargmodes,p.proargnames,p.prosecdef,p.provolatile)
 is not distinct from row(a.*) from pg_proc p cross join permisos_antes a
 where p.oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure),
 'firma, owner, ACL, volatilidad y search_path intactos');
select pg_temp.exigir(not has_function_privilege('anon','private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)','execute')
 and not has_function_privilege('authenticated','private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)','execute')
 and not has_function_privilege('service_role','private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)','execute'),
 'helper cerrado a anon, authenticated y service_role');

-- Lead tardío explícitamente enlazado gana incluso si existe ledger upgrade.
savepoint casos;
update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000000a'
where perfil_id='c0000000-0000-4000-8000-000000000001';
select pg_temp.exigir((select origen='referido' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000a'),
 'lead tardío enlazado conserva Referido sobre ledger');
-- Dos leads directos de canales distintos conservan sin_origen, no Cartera.
update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000000a'
where id='803b9178-8918-4484-b892-b5168df6f72e';
select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000a'),
 'origen directo ambiguo no se maquilla como Cartera');

-- Fallback anterior y fallback ambiguo, sin enlaces directos.
-- El guard conserva creado_en del lead. Crear un contrato posterior válido,
-- con su snapshot legacy coherente y fecha comercial inferida por el servidor.
do $$ declare c public.contratos%rowtype; d jsonb; cols text; vals text;
begin
 select * into strict c from public.contratos where numero_contrato='BANCO-A2';
 c.id:='e0000000-0000-4000-8000-000000000021';
 c.numero_contrato:='CARTERA-FALLBACK';
 c.fecha_vencimiento:=c.fecha_vencimiento + (date '2026-09-25'-c.fecha_inicio);
 c.fecha_inicio:='2026-09-25';
 c.creado_en:='2026-09-25 12:00:00-05';
 c.fecha_cierre_comercial:=null;
 c.fuente_cierre_comercial:=null;
 c.producto_condicion_id:=private.crear_snapshot_producto_legacy(c.id,c.categoria,
  c.moneda,c.modalidad,c.tipo_interes,c.capital,c.tasa_anual,c.fecha_inicio,c.fecha_vencimiento);
 d:=to_jsonb(c);
 select string_agg(quote_ident(attname),',' order by attnum),
 string_agg('r.'||quote_ident(attname),',' order by attnum) into cols,vals
 from pg_attribute where attrelid='public.contratos'::regclass
 and attnum>0 and not attisdropped and attgenerated='';
 execute format('insert into public.contratos(%s) select %s from jsonb_populate_record(null::public.contratos,$1) r',cols,vals) using d;
end $$;
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
 date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
from public.contratos where numero_contrato='CARTERA-FALLBACK';
select pg_temp.exigir((select origen='formulario' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000021'),
 'origen anterior por perfil conserva precedencia');
update crm.leads set perfil_id='c0000000-0000-4000-8000-000000000002',origen='referido'
where id='255a6b9c-f49e-4dc4-8d06-01e61be27274';
select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000021'),
 'fallback ambiguo no se maquilla como Cartera');

-- Contrato repetido sin ledger no basta (B1-JUL), ni un lead tardío sin enlace (B2-1).
select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000e'),
 'sin ledger válido no se infiere continuidad');

-- Ledger discordante: reemplazo exclusivamente sintético dentro de savepoint.
-- Se usa la válvula existente de eliminación, sin apagar el trigger inmutable.
savepoint discrepancia;
select set_config('crm.elimina_operacion_cartera','on',true);
delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
 date_trunc('month',fecha_cierre_comercial)::date,'USD',false,'flujo_cartera',creado_por
from public.contratos where numero_contrato='BANCO-A3';
select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000010'),
 'ledger de otra moneda no clasifica');
rollback to discrepancia;
savepoint discrepancia;
select set_config('crm.elimina_operacion_cartera','on',true);
delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial+1,
 date_trunc('month',fecha_cierre_comercial+1)::date,moneda,false,'flujo_cartera',creado_por
from public.contratos where numero_contrato='BANCO-A3';
select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000010'),
 'ledger de otra fecha no clasifica');
rollback to discrepancia;

savepoint discrepancia;
select set_config('crm.elimina_operacion_cartera','on',true);
delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select 'c0000000-0000-4000-8000-000000000004',analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
 date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
from public.contratos where numero_contrato='BANCO-A3';
select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000010'),
 'ledger de otro cliente no clasifica');
rollback to discrepancia;

savepoint renovacion;
select set_config('crm.elimina_operacion_cartera','on',true);
delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-00000000000d';
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,contrato_origen_id,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por,capital_renovado,capital_adicional)
select cliente_id,analista_cierre_id,'renovacion',id,'e0000000-0000-4000-8000-00000000000c',fecha_cierre_comercial,
 date_trunc('month',fecha_cierre_comercial)::date,moneda,true,'flujo_cartera',creado_por,capital,0
from public.contratos where numero_contrato='BANCO-B1-SEP';
select pg_temp.exigir((select origen='cartera' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000d')
 and exists(select 1 from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-00000000000d' and tipo='renovacion'),
 'renovación legada acreditada también clasifica');
rollback to renovacion;

-- No existe un tercer tipo válido: CHECK limita el ledger a upgrade/renovación.
-- Probar la frontera real, sin retirar constraints para inventar otro estado.
savepoint tipo_invalido;
select set_config('crm.elimina_operacion_cartera','on',true);
delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
do $$ declare rechazado boolean:=false; begin
 begin
  insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
   fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
  select cliente_id,analista_cierre_id,'otro',id,fecha_cierre_comercial,
   date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
  from public.contratos where numero_contrato='BANCO-A3';
 exception when check_violation then rechazado:=true;
 end;
 perform pg_temp.exigir(rechazado,'ledger rechaza un tipo fuera de upgrade/renovación');
end $$;
rollback to tipo_invalido;

rollback to casos;
-- @REVERSION@
select pg_temp.exigir((select md5(prosrc)='52ecf49a1c698e135a531b38ab75e291' from pg_proc
 where oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure),
 'reversión restaura definición exacta anterior');
select pg_temp.exigir(not exists((select * from filas_antes except all select * from pg_temp.filas())
 union all (select * from pg_temp.filas() except all select * from filas_antes)),
 'reversión restaura resultados anteriores');
select pg_temp.exigir((select datos=pg_temp.invariantes() from antes),'reversión no modifica datos ni métricas');
rollback;
