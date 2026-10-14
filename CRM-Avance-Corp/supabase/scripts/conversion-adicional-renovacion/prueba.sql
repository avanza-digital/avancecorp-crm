-- Ensayo sintético sobre esquema vigente, solo en banco propio. Todo se revierte.
-- Requiere la migración candidata aplicada. Los dobles del fixture se declaran
-- en mundo-fase-b.sql; las operaciones y las puertas de lectura usan código real.
\set ON_ERROR_STOP on
begin;
create temp table funcion_nueva as
select pg_get_functiondef('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure) as sql;
\ir ../conversion-tope-referidos/mundo-fase-b.sql
create temp table resultados(caso text);
grant insert on resultados to authenticated;
create or replace function pg_temp.exigir(p_ok boolean,p_motivo text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'FALLA: %',p_motivo; end if;
  insert into resultados values(p_motivo);
end $$;
select set_config('request.jwt.claim.sub',(select g::text from ana),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select g::text from ana),'role','authenticated')::text,true);
insert into crm.meta_periodos(id,periodo,revision,publicada_por)
select md5('metas-adicional')::uuid,'2026-10-01',
  (select coalesce(max(revision),0)+1 from crm.meta_periodos where periodo='2026-10-01'),g from ana;
insert into crm.metas_vendedor(meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
select md5('metas-adicional')::uuid,a,s,15 from ana;

create function pg_temp.op(
  clave text,cliente text,tipo text,fecha date,adicional numeric,
  moneda text default 'PEN',elegible boolean default true,analista uuid default null)
returns uuid language plpgsql as $$
declare
  v_id uuid:=md5('adicional-op|'||clave)::uuid;
  v_a uuid:=coalesce(analista,(select a from ana));
begin
  insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,
    fecha_inicio,fecha_vencimiento,producto_condicion_id,fecha_cierre_comercial,categoria,analista_cierre_id)
  values(md5('contrato|'||v_id)::uuid,'PRUEBA-AD-'||clave,md5(cliente)::uuid,
    5000+coalesce(adicional,0),moneda,'mensual',fecha,fecha+365,md5('producto-prueba')::uuid,fecha,tipo,v_a);
  insert into crm.operaciones_cartera(id,cliente_id,vendedor_id,tipo,contrato_nuevo_id,
    fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por,
    desglose_completo,contrato_origen_id,capital_renovado,capital_adicional,creado_en)
  values(v_id,md5(cliente)::uuid,v_a,tipo,md5('contrato|'||v_id)::uuid,
    fecha,date_trunc('month',fecha)::date,moneda,elegible,
    case when tipo='renovacion' and adicional is null then 'backfill_agosto_2026' else 'flujo_cartera' end,v_a,
    tipo='upgrade' or adicional is not null,
    case when tipo='renovacion' and adicional is not null then md5('origen|'||v_id)::uuid end,
    case when tipo='renovacion' and adicional is not null then 5000 end,
    case when tipo='renovacion' then adicional end,
    fecha::timestamp at time zone 'America/Lima');
  return v_id;
end $$;
select pg_temp.op('usd','usd','renovacion','2026-10-06',7000,'USD');
select pg_temp.op('pen','pen','renovacion','2026-10-07',1);
select pg_temp.op('cero','cero','renovacion','2026-10-07',0);
select pg_temp.op('nulo','nulo','renovacion','2026-10-07',null);
select pg_temp.op('upgrade-primero','duplicado1','upgrade','2026-10-02',0);
select pg_temp.op('renovacion-despues','duplicado1','renovacion','2026-10-03',100);
select pg_temp.op('renovacion-primero','duplicado2','renovacion','2026-10-02',100);
select pg_temp.op('upgrade-despues','duplicado2','upgrade','2026-10-03',0);
select pg_temp.op('pura-primero','duplicado3','renovacion','2026-10-02',0);
select pg_temp.op('adicional-despues','duplicado3','renovacion','2026-10-03',100);
select pg_temp.op('no-elegible','no-elegible','upgrade','2026-10-02',0,'USD',false);
select pg_temp.op('elegible-despues','no-elegible','upgrade','2026-10-03',0);
select pg_temp.op('antes-corte','corte','renovacion','2026-09-30',100);
select pg_temp.op('desde-corte','corte','renovacion','2026-10-01',100);
select pg_temp.op('enero','enero','renovacion','2026-01-02',100);
select pg_temp.op('futuro','usd','renovacion','2026-11-01',7000,'USD');
select pg_temp.op('otro-analista','otro','renovacion','2026-10-06',100,'PEN',true,(select b from ana));

create function pg_temp.ep(p_mes date) returns setof jsonb language sql as $$
select to_jsonb(e) from private.conversion_episodios(
  p_mes::timestamp at time zone 'America/Lima',
  (p_mes+interval '1 month')::timestamp at time zone 'America/Lima',
  p_mes,true,'{}',private.peso_referido_conversion(p_mes)) e $$;
\ir nucleo-anterior.sql
create temp table antes as
select d::date mes,e from generate_series(date '2026-01-01',date '2026-11-01',interval '1 month') d,
lateral pg_temp.ep(d::date) e;
create temp table oficial_antes as select crm.conversion_mensual_fn('2026-10-01') j;
create temp table cartera_antes as select to_jsonb(c) j from private.metricas_cartera_por_vendedor('2026-10-01') c;
create temp table pesos_antes as select to_jsonb(p) j from crm.conversion_pesos p;
create temp table operaciones_antes as select to_jsonb(o) j from crm.operaciones_cartera o;
do $$ begin execute(select sql from funcion_nueva); end $$;
create temp table despues as
select d::date mes,e from generate_series(date '2026-01-01',date '2026-11-01',interval '1 month') d,
lateral pg_temp.ep(d::date) e;

select pg_temp.exigir(not exists(
  (select * from antes where mes<'2026-10-01' except all select * from despues where mes<'2026-10-01')
  union all
  (select * from despues where mes<'2026-10-01' except all select * from antes where mes<'2026-10-01')),
  '01: enero a setiembre conservan exactamente todos sus episodios');
select pg_temp.exigir(not exists(
  (select mes,e from antes where e->>'tipo'<>'operacion' except all
   select mes,e from despues where e->>'tipo'<>'operacion')
  union all
  (select mes,e from despues where e->>'tipo'<>'operacion' except all
   select mes,e from antes where e->>'tipo'<>'operacion')),
  '02: divisor, cierres de leads y referido sin cambios');
select pg_temp.exigir((select count(*)=5 and bool_and(e->>'categoria'='upgrade' and (e->>'aporte_numerador')::numeric=1)
  from despues where mes='2026-10-01' and e->>'operacion_id' in (
    md5('adicional-op|usd')::uuid::text,md5('adicional-op|pen')::uuid::text,
    md5('adicional-op|renovacion-primero')::uuid::text,md5('adicional-op|desde-corte')::uuid::text,
    md5('adicional-op|otro-analista')::uuid::text)),
  '03: adicional PEN, USD, mínimo positivo y fecha de vigencia aportan 1 como upgrade');
select pg_temp.exigir((select count(*)=3 and bool_and(e->>'categoria'='renovacion' and (e->>'aporte_numerador')::numeric=0)
  from despues where mes='2026-10-01' and e->>'operacion_id' in (
    md5('adicional-op|cero')::uuid::text,md5('adicional-op|nulo')::uuid::text,md5('adicional-op|pura-primero')::uuid::text)),
  '04: renovación pura y sin desglose continúan en cero');
select pg_temp.exigir(not exists(select 1 from despues where e->>'operacion_id' in (
    md5('adicional-op|renovacion-despues')::uuid::text,md5('adicional-op|upgrade-despues')::uuid::text,
    md5('adicional-op|adicional-despues')::uuid::text,md5('adicional-op|no-elegible')::uuid::text)),
  '05: no duplica cliente/mes ni salta la primera operación; excluye no elegible');
select pg_temp.exigir((select (e->>'aporte_numerador')::numeric=1 from despues
  where e->>'operacion_id'=md5('adicional-op|elegible-despues')::uuid::text),
  '06: una operación no elegible anterior no consume el lugar');
select pg_temp.exigir((select (e->>'aporte_numerador')::numeric=1 and e->>'categoria'='upgrade' from despues
  where e->>'operacion_id'=md5('adicional-op|futuro')::uuid::text),
  '07: mismo cliente puede aportar en otro mes');
select pg_temp.exigir(not exists(
  select 1 from antes a full join despues d on a.mes=d.mes and a.e->>'operacion_id'=d.e->>'operacion_id'
  where coalesce(a.e->>'tipo',d.e->>'tipo')='operacion'
    and (a.e is null or d.e is null or (a.e-'categoria'-'aporte_numerador')<>(d.e-'categoria'-'aporte_numerador'))),
  '08: mismos episodios, fechas y atribución; solo cambian categoría y aporte');
select pg_temp.exigir((select count(*)=1 and sum(aporte_numerador)=1
  from private.conversion_episodios('2026-10-02 00:00 America/Lima','2026-10-03 00:00 America/Lima',
    null,true,'{}',1) where operacion_id=md5('adicional-op|renovacion-primero')::uuid),
  '09: rango parcial conserva el punto en la fecha de la primera operación');
select pg_temp.exigir(not exists(select 1
  from private.conversion_episodios('2026-10-03 00:00 America/Lima','2026-10-04 00:00 America/Lima',
    null,true,'{}',1) where operacion_id=md5('adicional-op|upgrade-despues')::uuid),
  '10: rango posterior no vuelve a escoger la segunda operación del mes');
select pg_temp.exigir((select count(*)=1 and sum(aporte_numerador)=1
  from private.conversion_episodios('2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',
    null,false,array[(select b from ana)],1) where tipo='operacion'),
  '11: ámbito del otro analista conserva únicamente su operación');
select pg_temp.exigir(not exists(
  (select * from pesos_antes except select to_jsonb(p) from crm.conversion_pesos p)
  union all (select to_jsonb(p) from crm.conversion_pesos p except select * from pesos_antes)),
  '12: pesos de renovación y referido idénticos');
select pg_temp.exigir(not exists(
  (select * from operaciones_antes except select to_jsonb(o) from crm.operaciones_cartera o)
  union all (select to_jsonb(o) from crm.operaciones_cartera o except select * from operaciones_antes)),
  '13: operaciones y capital original idénticos');
create temp table oficial_despues as select crm.conversion_mensual_fn('2026-10-01') j;
select pg_temp.exigir((select sum((d->>'numerador')::numeric-(a->>'numerador')::numeric)=5
  and bool_and(d->'divisor'=a->'divisor')
  from oficial_despues od cross join oficial_antes oa,
  jsonb_array_elements(od.j->'responsables') d,jsonb_array_elements(oa.j->'responsables') a
  where d->>'vendedor_id'=a->>'vendedor_id'
    and d->>'vendedor_id' in ((select ana.a::text from ana),(select ana.b::text from ana))),
  '14: puerta oficial suma cinco puntos a los dos actores sintéticos y conserva sus divisores');
select pg_temp.exigir(not exists(
  select 1 from cartera_antes a full join
    (select to_jsonb(c) j from private.metricas_cartera_por_vendedor('2026-10-01') c) d
    on a.j->>'vendedor_id'=d.j->>'vendedor_id'
  where (a.j-'conversiones_renovacion'-'conversiones_upgrade')<>(d.j-'conversiones_renovacion'-'conversiones_upgrade')
    or a.j is null or d.j is null),
  '15: cartera solo reclasifica el aporte; preserva operaciones e importes PEN/USD');
select pg_temp.exigir((select (crm.conversion_divisor_coordinacion_fn('2026-10-01')#>'{empresa,numerador}')=j#>'{total,numerador}'
  from oficial_despues),'16: Coordinación coincide con la oficial');
select pg_temp.exigir((select (crm.metricas_conversiones_fn('2026-10-01',
  least(date '2026-10-31',(now() at time zone 'America/Lima')::date))#>'{nucleo,numerador}')=j#>'{total,numerador}'
  from oficial_despues),'17: métricas de conversiones coinciden con la oficial');
select pg_temp.exigir((select (v->>'numerador')::numeric=(r->>'numerador')::numeric
  from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-10-01')->'vendedores') v,
  oficial_despues d,jsonb_array_elements(d.j->'responsables') r
  where v->>'vendedor_id'=(select a::text from ana) and r->>'vendedor_id'=v->>'vendedor_id'),
  '18: Metas coincide por analista');
select pg_temp.exigir((select proacl::text='{postgres=X/postgres}' and prosecdef and provolatile='s'
  and proconfig=array['search_path=""']
  from pg_proc where oid='private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure),
  '19: ACL, SECURITY DEFINER, STABLE y search_path conservados');
select pg_temp.exigir(not has_function_privilege('anon',
  'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','EXECUTE')
  and not has_function_privilege('authenticated',
  'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','EXECUTE'),
  '20: núcleo inaccesible directamente para anon y authenticated');
select set_config('request.jwt.claim.sub',(select a::text from ana),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select a::text from ana),'role','authenticated')::text,true);
set local role authenticated;
select pg_temp.exigir((select (j#>>'{total,numerador}')::numeric=21.75
  and jsonb_array_length(j->'responsables')=1 from (select crm.conversion_mensual_fn('2026-10-01') j) f),
  '21: sesión real de rol analista conserva ámbito y sus cuatro puntos adicionales');
reset role;
select pg_temp.exigir((select count(*)=2
  and bool_and(case when operacion_id=md5('adicional-op|antes-corte')::uuid
    then categoria='renovacion' and aporte_numerador=private.peso_renovacion_conversion('2026-09-01')
    else categoria='upgrade' and aporte_numerador=1 end)
  from private.conversion_episodios('2026-09-15 00:00 America/Lima','2026-10-15 00:00 America/Lima',
    null,true,'{}',1)
  where operacion_id in (md5('adicional-op|antes-corte')::uuid,md5('adicional-op|desde-corte')::uuid)),
  '22: rango que cruza setiembre/octubre aplica la regla del mes de cada operación');
select jsonb_build_object('estado','PASS','comprobaciones',count(*),'casos',jsonb_agg(caso order by caso)) as resultado from resultados;
rollback;
