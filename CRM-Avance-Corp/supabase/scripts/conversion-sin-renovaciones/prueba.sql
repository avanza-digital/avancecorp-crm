-- Solo banco local desechable con la migración aplicada. Todo termina en rollback.
\set ON_ERROR_STOP on
begin;
\ir ../conversion-tope-referidos/mundo-fase-b.sql
select set_config('request.jwt.claim.sub', (select g::text from ana), true);
select set_config('request.jwt.claims', jsonb_build_object('sub',(select g::text from ana),'role','authenticated')::text, true);
insert into crm.meta_periodos(id,periodo,revision,publicada_por)
  select md5('metas-octubre')::uuid,'2026-10-01',1,g from ana;
insert into crm.metas_vendedor(meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
  select md5('metas-octubre')::uuid,a,s,15 from ana;

create function pg_temp.operacion(p_tipo text, p_mes date, p_dia int, p_cliente text, p_moneda text default 'PEN')
returns uuid language plpgsql as $$
declare v_id uuid := md5(p_tipo || p_mes || p_dia || p_cliente)::uuid; v_a uuid := (select a from ana);
begin
  insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,
    fecha_inicio,fecha_vencimiento,producto_condicion_id,fecha_cierre_comercial,categoria,analista_cierre_id)
  values (md5('contrato|'||v_id)::uuid,'PRUEBA-'||v_id,md5(p_cliente)::uuid,1100,p_moneda,'mensual',
    p_mes+p_dia-1,p_mes+365,md5('producto-prueba')::uuid,p_mes+p_dia-1,p_tipo,v_a);
  insert into crm.operaciones_cartera (id, cliente_id, vendedor_id, tipo, contrato_nuevo_id,
    fecha_operacion, periodo, moneda, elegible_conversion, fuente, creado_por,
    desglose_completo, contrato_origen_id, capital_renovado, capital_adicional)
  values (v_id, md5(p_cliente)::uuid, v_a, p_tipo, md5('contrato|'||v_id)::uuid,
    p_mes+p_dia-1, p_mes, p_moneda, true, 'flujo_cartera', v_a, true,
    case when p_tipo='renovacion' then md5('origen|'||v_id)::uuid end,
    case when p_tipo='renovacion' then 1000 end,
    case when p_tipo='renovacion' then 100 end);
  return v_id;
end $$;
select pg_temp.operacion('renovacion','2026-10-01',2,'renovacion-pen');
select pg_temp.operacion('renovacion','2026-10-01',3,'renovacion-usd','USD');
select pg_temp.operacion('upgrade','2026-10-01',4,'upgrade');
select pg_temp.operacion('renovacion','2026-10-01',5,'mixto');
select pg_temp.operacion('upgrade','2026-10-01',6,'mixto');
select pg_temp.operacion('renovacion','2026-09-01',2,'historico');
select pg_temp.operacion('upgrade','2026-09-01',3,'historico-upgrade');
select pg_temp.operacion('renovacion','2026-11-01',2,'futuro');

create function pg_temp.episodios(p_mes date) returns setof jsonb language sql as $$
  select to_jsonb(e) from private.conversion_episodios(p_mes::timestamp at time zone 'America/Lima',
    (p_mes+interval '1 month')::timestamp at time zone 'America/Lima',p_mes,true,'{}',
    private.peso_referido_conversion(p_mes)) e $$;

-- Control anterior dentro de esta transacción: solamente el peso anterior.
alter table crm.conversion_pesos drop constraint conversion_renovacion_cero_desde_octubre;
update crm.conversion_pesos set peso_renovacion=0.15 where vigente_desde='2026-10-01';
create temp table episodios_antes as select m, e from (values(date '2026-09-01'),('2026-10-01'),('2026-11-01')) v(m), lateral pg_temp.episodios(m) e;
create temp table cartera_antes as select to_jsonb(c) dato from private.metricas_cartera_por_vendedor('2026-10-01') c;
create temp table operaciones_antes as select to_jsonb(o) dato from crm.operaciones_cartera o;
create temp table oficial_antes as select crm.conversion_mensual_fn('2026-10-01') j;
create temp table septiembre_antes as select crm.conversion_mensual_fn('2026-09-01') j;

update crm.conversion_pesos set peso_renovacion=0 where vigente_desde='2026-10-01';
create temp table episodios_despues as select m, e from (values(date '2026-09-01'),('2026-10-01'),('2026-11-01')) v(m), lateral pg_temp.episodios(m) e;
select pg_temp.exigir((select count(*)=4 and bool_and((e->>'aporte_numerador')::numeric=0)
  from episodios_despues where m>='2026-10-01' and e->>'categoria'='renovacion'), '01: renovaciones de octubre y futuras aportan cero');
select pg_temp.exigir((select (e->>'aporte_numerador')::numeric=1 from episodios_despues
  where m='2026-10-01' and e->>'categoria'='upgrade'), '02: upgrade elegible sigue aportando uno');
select pg_temp.exigir((select count(*)=1 and sum((e->>'aporte_numerador')::numeric)=0 from episodios_despues
  where m='2026-10-01' and e->>'operacion_id' in (
    select id::text from crm.operaciones_cartera where cliente_id=md5('mixto')::uuid)),
  '03: se conserva la primera operación por cliente/mes (renovación antes de upgrade)');
select pg_temp.exigir(not exists (
  (select e from episodios_antes where m='2026-09-01' except select e from episodios_despues where m='2026-09-01')
  union all (select e from episodios_despues where m='2026-09-01' except select e from episodios_antes where m='2026-09-01')),
  '04: todas las filas y aportes de septiembre idénticos');
select pg_temp.exigir(not exists (
  (select e from episodios_antes where e->>'categoria' is distinct from 'renovacion' except select e from episodios_despues where e->>'categoria' is distinct from 'renovacion')
  union all (select e from episodios_despues where e->>'categoria' is distinct from 'renovacion' except select e from episodios_antes where e->>'categoria' is distinct from 'renovacion')),
  '05: llegadas, cierres, referidos, tope y upgrades idénticos');
select pg_temp.exigir(not exists (
  (select dato from operaciones_antes except select to_jsonb(o) from crm.operaciones_cartera o)
  union all (select to_jsonb(o) from crm.operaciones_cartera o except select dato from operaciones_antes)),
  '06: ledger e importes PEN/USD intactos (capital renovado y adicional)');
select pg_temp.exigir(not exists (
  (select dato from cartera_antes except select to_jsonb(c) from private.metricas_cartera_por_vendedor('2026-10-01') c)
  union all (select to_jsonb(c) from private.metricas_cartera_por_vendedor('2026-10-01') c except select dato from cartera_antes)),
  '07: cantidades de operaciones y reporte de cartera intactos');
select pg_temp.exigir((select capital_renovado_pen=2000 and capital_renovado_usd=1000
  and capital_adicional_pen=200 and capital_adicional_usd=100
  from private.metricas_cartera_por_vendedor('2026-10-01') where vendedor_id=(select a from ana)),
  '22: capital renovado/adicional no vacío e idéntico en PEN y USD');

create temp table oficial as select crm.conversion_mensual_fn('2026-10-01') j;
create temp table coordinacion as select crm.conversion_divisor_coordinacion_fn('2026-10-01') j;
create temp table metas as select crm.cumplimiento_metas_fn('2026-10-01') j;
select pg_temp.exigir((select (j#>>'{ponderacion,renovacion}')::numeric=0 and (j#>>'{ponderacion,referido}')::numeric=1
  and (j#>>'{ponderacion,tope_referidos_pct}')::numeric=15 from oficial), '08: puerta oficial declara los tres pesos correctos');
select pg_temp.exigir((select (a.j#>>'{total,numerador}')::numeric-(d.j#>>'{total,numerador}')::numeric=0.45
  and a.j#>>'{total,divisor}'=d.j#>>'{total,divisor}' from oficial_antes a, oficial d),
  '09: el total pierde exactamente 3 renovaciones x 0,15, con divisor intacto');
select pg_temp.exigir((select (j->>'peso_renovacion')::numeric=0 and (j#>>'{empresa,cartera,renovacion_aporte}')::numeric=0
  from coordinacion), '10: coordinación declara peso y aporte de renovación cero');
select pg_temp.exigir((select (c.j#>>'{empresa,numerador}')::numeric=(o.j#>>'{total,numerador}')::numeric
  from coordinacion c, oficial o), '11: coordinación coincide con la oficial');
select pg_temp.exigir((select (j - 'generado_en')=(crm.conversion_mensual_fn('2026-09-01') - 'generado_en') from septiembre_antes),
  '12: la puerta de septiembre no cambia');
select pg_temp.exigir((select sum((e->>'aporte_numerador')::numeric)=3 from episodios_despues
  where m='2026-10-01' and e->>'analista_id'=(select a::text from ana) and (e->>'fue_referido')::boolean),
  '13: A conserva 3 referidos válidos con 15 cierres automáticos');
select pg_temp.exigir((select (v->>'numerador')::numeric=19 and (v->>'resueltos')::numeric=80
  and (v->>'conversion_real')::numeric=23.75
  from metas, lateral jsonb_array_elements(j->'vendedores') v where v->>'vendedor_id'=(select a::text from ana)),
  '21: Metas publica 19/80 = 23,75 % para A, sin las tres renovaciones');

-- Sellado real de un mes pasado con peso cero de prueba: el procedimiento no
-- permite sellar octubre mientras está en curso. No se falsea el reloj real.
update crm.conversion_pesos set peso_renovacion=0 where vigente_desde='2026-07-01';
create or replace function private.cierre_mes_ventana_desde(p_periodo date) returns timestamptz
language sql stable set search_path='' as $$ select '2026-01-01'::timestamptz $$;
set local session_replication_role=origin;
create temp table sello as select crm.cerrar_periodo('2026-09-01') j;
set local session_replication_role=replica;
select pg_temp.exigir((select (j->>'ok')::boolean from sello), '14: sellado real con peso de renovación cero');
select pg_temp.exigir((select ponderacion_renovacion=0 from crm.periodos_cerrados where periodo='2026-09-01'),
  '15: la foto guarda renovación cero');
create temp table foto as select crm.conversion_mensual_fn('2026-09-01') j;
update crm.conversion_pesos set peso_renovacion=0.15 where vigente_desde='2026-07-01';
select pg_temp.exigir((select j=crm.conversion_mensual_fn('2026-09-01') from foto),
  '16: una foto sellada permanece idéntica aunque cambie el peso vivo');
rollback;

-- Restricción real y default tras la migración, sin los overrides de arriba.
begin;
do $$ begin
  insert into crm.conversion_pesos(vigente_desde,peso_referido,tope_referidos_pct) values ('2026-12-01',1,15);
  if private.peso_renovacion_conversion('2026-12-01') is distinct from 0 then raise exception '17: default incorrecto'; end if;
  begin
    update crm.conversion_pesos set peso_renovacion=0.15 where vigente_desde='2026-12-01';
    raise exception '18: aceptó reactivar renovaciones';
  exception when check_violation then null;
  end;
  raise notice 'PASS 17–18: default cero y protección de versiones futuras';
end $$;
set local role authenticated;
do $$ begin
  begin
    perform * from crm.conversion_pesos;
    raise exception '19: authenticated puede leer los pesos internos';
  exception when insufficient_privilege then null;
  end;
  begin
    update crm.conversion_pesos set peso_renovacion=0 where vigente_desde='2026-10-01';
    raise exception '20: authenticated puede editar los pesos';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS 19–20: configuración continúa inaccesible desde la API';
end $$;
rollback;
