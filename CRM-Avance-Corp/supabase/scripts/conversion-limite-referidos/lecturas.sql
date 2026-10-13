-- Banco de integración sintético con las puertas reales; termina en rollback.
\set ON_ERROR_STOP on
begin;
\ir ../conversion-tope-referidos/mundo-fase-b.sql
select set_config('request.jwt.claim.sub',(select g::text from ana),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select g::text from ana),'role','authenticated')::text,true);
insert into crm.meta_periodos(id,periodo,revision,publicada_por)
select md5('metas-limite-total')::uuid,'2026-10-01',1,g from ana;
insert into crm.metas_vendedor(meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
select md5('metas-limite-total')::uuid,a,s,15 from ana;

create temp table oficial as select crm.conversion_mensual_fn('2026-10-01') j;
create temp table coordinacion as select crm.conversion_divisor_coordinacion_fn('2026-10-01') j;
create temp table metas as select crm.cumplimiento_metas_fn('2026-10-01') j;
select pg_temp.exigir((select (j#>>'{total,numerador}')::numeric=20.05 and (j#>>'{total,divisor}')::int=110 from oficial),
  'oficial: A 15,75 + B 4,30 / 110 llegadas');
select pg_temp.exigir((select (j#>>'{empresa,numerador}')::numeric=20.05
  and (j#>>'{empresa,cierres,referido_aporte}')::numeric=1.05 from coordinacion),
  'Coordinación: 7 referidos, aporte total 1,05');
select pg_temp.exigir((select (v->>'numerador')::numeric=15.75 and (v->>'resueltos')::numeric=80
  and (v->>'conversion_real')::numeric=19.69
  from metas,lateral jsonb_array_elements(j->'vendedores') v where v->>'vendedor_id'=(select a::text from ana)),
  'Metas: A 15,75 / 80 = 19,69 %');
select pg_temp.exigir((select numerador=15.75 and divisor=80
  from private.conversion_neta_por_vendedor('2026-10-01',false,array[(select a from ana)])),
  'ámbito de analista: mismo límite por persona');
select pg_temp.exigir((select (j#>>'{ponderacion,renovacion}')::numeric=0
  and (j#>>'{ponderacion,tope_referidos_pct}')::numeric=15 from oficial),
  'puerta declara renovación cero y límite 15');
select pg_temp.exigir((select (crm.conversion_mensual_fn('2026-09-01')#>>'{total,numerador}')::numeric=15.6),
  'septiembre: 15 automáticos + 4 referidos × 0,15');

-- No se altera el contrato de ámbito al usar la puerta autenticada del analista.
select set_config('request.jwt.claim.sub',(select a::text from ana),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select a::text from ana),'role','authenticated')::text,true);
set local role authenticated;
select pg_temp.exigir((select (crm.conversion_mensual_fn('2026-10-01')#>>'{total,numerador}')::numeric=15.75),
  'sesión analista: no recibe cierres ni aporte de B');
reset role;
select 'PASS: 7 comprobaciones de lecturas y ámbito' resultado;
rollback;
