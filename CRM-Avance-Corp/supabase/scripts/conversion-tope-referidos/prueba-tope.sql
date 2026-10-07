-- Prueba del tope de referidos (sintética, todo se deshace). Se corre contra un banco con la migración
-- 20261007160937 aplicada, como postgres:  psql -v ON_ERROR_STOP=1 -f prueba-tope.sql
-- Regla: la base del tope son SOLO los cierres no anulados de leads que el sistema asigna (origen landing o formulario) y
-- que no son registro manual (alta_manual); los referidos, las renovaciones, los upgrades y la base cargada no entran en la base.
-- Mundo: tres analistas A, B y C, cierres de octubre (con tope) y de septiembre (sin tope). Los cierres nacen como
-- acreditaciones (la política está activa); la fuente y la anulación se simulan con funciones temporales que solo viven
-- dentro de esta transacción.
begin;
set local session_replication_role = replica;
set local search_path = '';
\i anterior-episodios.sql

create function pg_temp.exigir(p_ok boolean, p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FALLA: %', p_motivo; end if; end $$;

-- Las fuentes de las acreditaciones sintéticas son siempre elegibles.
create or replace function private.conversion_exclusion_fuente(p_tipo text, p_id uuid) returns text
  language sql stable set search_path = '' as $$ select 'elegible'::text $$;

-- Ayudante: un cierre sintético. n-ésimo cierre del analista en el mes, de origen p_origen, el día p_dia.
create function pg_temp.cierre(p_analista uuid, p_origen text, p_mes date, p_dia int) returns uuid language plpgsql as $$
declare v_lead uuid := gen_random_uuid();
begin
  insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, creado_en)
    values (v_lead, 'Sintetico ' || v_lead, '9' || substr(replace(v_lead::text, '-', ''), 1, 8), p_origen, 1000,
            (p_mes - 40)::timestamp at time zone 'America/Lima');
  insert into crm.conversion_acreditaciones (lead_id, episodio_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial,
      confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, politica_desde, motivo)
    values (v_lead, gen_random_uuid(), p_analista, p_origen, 'contrato', gen_random_uuid(), p_mes + (p_dia - 1),
      (p_mes + p_dia)::timestamp at time zone 'America/Lima', (p_mes + p_dia)::timestamp at time zone 'America/Lima',
      (p_mes + p_dia)::timestamp at time zone 'America/Lima', p_mes, private.conversion_plazo_hasta(p_mes),
      'acreditada', '2026-09-01', 'sintetico');
  return v_lead;
end $$;

-- aporte total de un analista en un rango y ámbito
create function pg_temp.aporte(p_a uuid, p_ini date, p_fin date, p_global boolean default true) returns numeric language sql as $$
  select coalesce(sum(e.aporte_numerador), 0)
  from private.conversion_episodios(p_ini::timestamp at time zone 'America/Lima', p_fin::timestamp at time zone 'America/Lima',
       null::date, p_global, array[p_a], 1) e where e.analista_id = p_a and e.tipo <> 'recibido' $$;

create temp table ana as select 'a0000000-0000-4000-8000-00000000000a'::uuid a, 'b0000000-0000-4000-8000-00000000000b'::uuid b, 'c0000000-0000-4000-8000-00000000000c'::uuid c;
create temp table oct as select date '2026-10-01' m;

-- ── Caso 1 · 15 cierres asignados + 5 referidos ⇒ base 15 ⇒ tope ceil(2,25) = 3, cuentan los 3 más antiguos ───────────────────────────────
do $$ declare a uuid := (select a from ana); i int; v_ref uuid[] := '{}'; begin
  for i in 1..15 loop perform pg_temp.cierre(a, case when i % 2 = 0 then 'formulario' else 'landing' end, '2026-10-01', 1 + (i % 6)); end loop;
  for i in 1..5 loop v_ref := v_ref || pg_temp.cierre(a, 'referido', '2026-10-01', 10 + i); end loop;   -- días 11..15
  create temp table ref_a as select unnest(v_ref) lead_id, generate_series(1, 5) orden;
end $$;
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01') = 18,
  'C1: 15 asignados (15) + 3 referidos que cuentan (3) = 18; salió ' || pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01'));
select pg_temp.exigir((select array_agg(e.lead_id order by e.fecha_numerador) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e
                        where e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 1 and e.analista_id = (select a from ana))
                      = (select array_agg(lead_id order by orden) from ref_a where orden <= 3), 'C1: cuentan los 3 referidos MÁS ANTIGUOS');
select pg_temp.exigir((select count(*) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e
                        where e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 0 and e.analista_id = (select a from ana)) = 2,
  'C1: los 2 referidos más recientes valen 0');

-- ── Caso 2 · septiembre NO lleva tope: 15 asignados con 5 referidos valen 15 + 5 × 0,15 ─────────────────────────────────────────
do $$ declare b uuid := (select b from ana); i int; begin
  for i in 1..15 loop perform pg_temp.cierre(b, 'formulario', '2026-09-01', 1 + (i % 6)); end loop;
  for i in 1..5 loop perform pg_temp.cierre(b, 'referido', '2026-09-01', 10 + i); end loop;
end $$;
select pg_temp.exigir(pg_temp.aporte((select b from ana), '2026-09-01', '2026-10-01') = 15.75, 'C2: septiembre sin tope: 15 + 5×0,15 = 15,75; salió ' || pg_temp.aporte((select b from ana), '2026-09-01', '2026-10-01'));

-- ── Caso 3 · sin regresión: septiembre da EXACTAMENTE lo mismo que la función anterior ────────────────────────────────────────
select pg_temp.exigir(not exists (
  (select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_divisor, e.aporte_numerador from private.conversion_episodios('2026-09-01'::timestamptz, '2026-10-01'::timestamptz, '2026-09-01', true, '{}', 0.15) e
   except select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_divisor, e.aporte_numerador from pg_temp.conversion_episodios_anterior('2026-09-01'::timestamptz, '2026-10-01'::timestamptz, '2026-09-01', true, '{}', 0.15) e)
  union all
  (select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_divisor, e.aporte_numerador from pg_temp.conversion_episodios_anterior('2026-09-01'::timestamptz, '2026-10-01'::timestamptz, '2026-09-01', true, '{}', 0.15) e
   except select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_divisor, e.aporte_numerador from private.conversion_episodios('2026-09-01'::timestamptz, '2026-10-01'::timestamptz, '2026-09-01', true, '{}', 0.15) e)),
  'C3: septiembre idéntico a la función anterior (mismas filas y mismos aportes)');
-- y en octubre, los NO referidos son idénticos a la función anterior (solo cambian los referidos)
select pg_temp.exigir(not exists (
  select 1 from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) n
  join pg_temp.conversion_episodios_anterior('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) v
    on v.tipo = n.tipo and v.lead_id is not distinct from n.lead_id and v.operacion_id is not distinct from n.operacion_id
  where not n.fue_referido and n.aporte_numerador is distinct from v.aporte_numerador),
  'C3b: en octubre los no referidos no cambian');

-- ── Caso 4 · redondeo hacia arriba y bordes (la base son los asignados; los referidos no suben su propio tope) ────────────────
-- 17 asignados + 2 referidos: 15 % de 17 = 2,55 ⇒ tope 3 ⇒ cuentan los 2.
do $$ declare c uuid := (select c from ana); i int; begin
  for i in 1..17 loop perform pg_temp.cierre(c, case when i % 2 = 0 then 'formulario' else 'landing' end, '2026-10-01', 1 + (i % 6)); end loop;
  perform pg_temp.cierre(c, 'referido', '2026-10-01', 20); perform pg_temp.cierre(c, 'referido', '2026-10-01', 21);
end $$;
select pg_temp.exigir(pg_temp.aporte((select c from ana), '2026-10-01', '2026-11-01') = 19, 'C4a: 17 asignados, 2 referidos, tope 3 ⇒ cuentan los 2 ⇒ 19');
-- (asignados, referidos, aporte esperado): tope = ceil(15 % × asignados); aporte = asignados + min(referidos, tope).
create temp table borde (n int, refs int, esperado numeric);
insert into borde values (4, 2, 5), (5, 3, 6), (7, 3, 9), (13, 4, 15), (14, 4, 17), (20, 5, 23), (1, 1, 2), (40, 10, 46), (6, 6, 7);
do $$ declare r record; ana_x uuid; i int; mes date := '2026-11-01'; begin
  for r in select * from borde loop
    ana_x := gen_random_uuid();
    for i in 1..r.n loop perform pg_temp.cierre(ana_x, case when i % 2 = 0 then 'formulario' else 'landing' end, mes, 1 + (i % 6)); end loop;
    for i in 1..r.refs loop perform pg_temp.cierre(ana_x, 'referido', mes, 10 + i); end loop;
    perform pg_temp.exigir(pg_temp.aporte(ana_x, '2026-11-01', '2026-12-01') = r.esperado,
      format('C4b: %s asignados con %s referidos ⇒ %s; salió %s', r.n, r.refs, r.esperado, pg_temp.aporte(ana_x, '2026-11-01', '2026-12-01')));
  end loop;
end $$;

-- ── Caso 5 · rango parcial y ámbito: el tope se calcula con el MES COMPLETO ─────────────────────────────────────────────────
-- Analista A (caso 1): los 5 referidos están en los días 11–15. Mirar solo del 1 al 13 debe dar los referidos de esos días
-- según el tope del mes entero (3 cuentan: días 11, 12, 13 ⇒ los 3 primeros), no un tope recalculado sobre el rango.
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-10-14') =
  (select coalesce(sum(e.aporte_numerador), 0) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e
    where e.analista_id = (select a from ana) and e.tipo = 'cierre' and e.fecha_numerador < '2026-10-14'::timestamp at time zone 'America/Lima'),
  'C5a: un rango parcial suma lo mismo que el mes entero recortado a ese rango');
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-10-14', false) = pg_temp.aporte((select a from ana), '2026-10-01', '2026-10-14', true),
  'C5b: el ámbito de un analista da lo mismo que la vista global');
select pg_temp.exigir((select count(distinct e.analista_id) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', false, array[(select a from ana)], 1) e where e.tipo <> 'recibido') = 1,
  'C5b2: con ámbito de un analista solo salen sus filas (aunque el tope se calcule con todos)');
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-10-16') = 18, 'C5c: un rango que cubre todos los cierres = el mes completo');
-- Un rango que contiene SOLO los 5 referidos (días 11 a 15): su tope es el del MES entero (3), no el de lo que se ve (ceil(0,75) = 1).
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-11', '2026-10-16') = 3,
  'C5e: el rango de solo referidos usa el tope del mes completo (3), no uno recalculado sobre lo visible; salió ' || pg_temp.aporte((select a from ana), '2026-10-11', '2026-10-16'));
-- Un rango de DOS meses: cada mes con su regla (septiembre sin tope, octubre con tope)
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-09-01', '2026-11-01') = 18, 'C5d: rango de dos meses suma cada mes con su regla');

-- ── Caso 6 · un cierre anulado no entra en la base ni cuenta: anular un asignado baja la base y el tope ───────────────────────────────
-- A tiene 15 asignados + 5 referidos (tope 3). Anulo 10 asignados ⇒ base 5 ⇒ tope ceil(0,75) = 1 ⇒ 5 asignados + 1 referido = 6.
do $$ declare a uuid := (select a from ana); r record; n int := 0; begin
  for r in select ca.lead_id from crm.conversion_acreditaciones ca where ca.analista_id = a and ca.periodo_comercial = '2026-10-01' and ca.origen <> 'referido' order by ca.fecha_comercial, ca.lead_id loop
    exit when n = 10;
    insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por) values (r.lead_id, 'sintetico', a);
    n := n + 1;
  end loop;
end $$;
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01') = 5 + 1, 'C6: anulados 10 asignados ⇒ 5 asignados + 1 referido (tope 1) = 6; salió ' || pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01'));
delete from crm.cierres_avance_anulados;
-- Anulo el referido MÁS ANTIGUO (día 11): la base sigue en 15 (tope 3) y los referidos vivos son 4 ⇒ cuentan los días 12, 13 y 14.
insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por) select lead_id, 'sintetico', (select a from ana) from ref_a where orden = 1;
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01') = 15 + 3, 'C6b: anulado el primer referido ⇒ entra el 4.º: 15 + 3 = 18; salió ' || pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01'));
delete from crm.cierres_avance_anulados;

-- ── Caso 7 · lo que NO es un cierre de lead asignado no sube el tope ────────────────────────────────────────────────────────────
-- Ayudante: una operación de cartera (upgrade o renovación) del analista en diciembre de 2026.
create function pg_temp.operacion(p_analista uuid, p_tipo text) returns void language plpgsql as $$
begin
  insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion, periodo, moneda, elegible_conversion, fuente, creado_por,
      desglose_completo, contrato_origen_id, capital_renovado, capital_adicional)
  values (gen_random_uuid(), p_analista, p_tipo, gen_random_uuid(), '2026-12-05', '2026-12-01', 'PEN', true, 'flujo_cartera', p_analista,
      true, case when p_tipo = 'upgrade' then null else gen_random_uuid() end, case when p_tipo = 'upgrade' then null else 1000 end, case when p_tipo = 'upgrade' then null else 0 end);
end $$;
create function pg_temp.referidos_que_cuentan(p_analista uuid) returns bigint language sql as $$
  select count(*) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', true, '{}', 1) e
   where e.analista_id = p_analista and e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 1 $$;
create temp table dic as select gen_random_uuid() e, gen_random_uuid() f, gen_random_uuid() g, gen_random_uuid() m, gen_random_uuid() z, gen_random_uuid() y;
do $$ declare d record; i int; begin
  select * into d from dic;
  -- (a) E: 6 asignados + 2 referidos + 2 upgrades + 2 renovaciones. Base 6 ⇒ tope 1. (Con las operaciones en la base serían 12 ⇒ tope 2.)
  for i in 1..6 loop perform pg_temp.cierre(d.e, 'formulario', '2026-12-01', i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(d.e, 'referido', '2026-12-01', 10 + i); end loop;
  for i in 1..2 loop perform pg_temp.operacion(d.e, 'upgrade'); perform pg_temp.operacion(d.e, 'renovacion'); end loop;
  -- (b) F: 6 asignados + 2 referidos + 1 de base cargada. Base 6 ⇒ tope 1. (Con la base cargada en la base serían 7 ⇒ tope 2.)
  for i in 1..6 loop perform pg_temp.cierre(d.f, 'landing', '2026-12-01', i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(d.f, 'referido', '2026-12-01', 10 + i); end loop;
  perform pg_temp.cierre(d.f, 'base_cargada', '2026-12-01', 3);
  -- (c) G: 6 asignados + 2 referidos. Los referidos no suben su propio tope: base 6 ⇒ tope 1. (Contados serían 8 ⇒ tope 2.)
  for i in 1..6 loop perform pg_temp.cierre(d.g, 'formulario', '2026-12-01', i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(d.g, 'referido', '2026-12-01', 10 + i); end loop;
  -- (d) M, el ejemplo aprobado por Miguel: 10 asignados + 4 referidos + 3 renovaciones + 2 upgrades + 1 de base cargada ⇒ tope ceil(1,5) = 2.
  for i in 1..10 loop perform pg_temp.cierre(d.m, case when i % 2 = 0 then 'formulario' else 'landing' end, '2026-12-01', i); end loop;
  for i in 1..4 loop perform pg_temp.cierre(d.m, 'referido', '2026-12-01', 10 + i); end loop;
  for i in 1..3 loop perform pg_temp.operacion(d.m, 'renovacion'); end loop;
  for i in 1..2 loop perform pg_temp.operacion(d.m, 'upgrade'); end loop;
  perform pg_temp.cierre(d.m, 'base_cargada', '2026-12-01', 4);
  -- (e) Z: sin ningún cierre asignado (3 referidos + 1 upgrade + 1 de base cargada) ⇒ base 0 ⇒ tope 0. Y: solo 3 referidos.
  for i in 1..3 loop perform pg_temp.cierre(d.z, 'referido', '2026-12-01', 10 + i); end loop;
  perform pg_temp.operacion(d.z, 'upgrade'); perform pg_temp.cierre(d.z, 'base_cargada', '2026-12-01', 3);
  for i in 1..3 loop perform pg_temp.cierre(d.y, 'referido', '2026-12-01', 10 + i); end loop;
end $$;
select pg_temp.exigir(pg_temp.referidos_que_cuentan((select e from dic)) = 1, 'C7a: upgrades y renovaciones NO suben el tope (6 asignados ⇒ cuenta 1 de 2 referidos)');
select pg_temp.exigir(pg_temp.aporte((select e from dic), '2026-12-01', '2027-01-01') = 6 + 1 + 2 + 2 * 0.15, 'C7a2: 6 + 1 referido + 2 upgrades + 2 renovaciones×0,15 = 9,30; salió ' || pg_temp.aporte((select e from dic), '2026-12-01', '2027-01-01'));
select pg_temp.exigir(pg_temp.referidos_que_cuentan((select f from dic)) = 1, 'C7b: un lead de base cargada NO sube el tope (6 asignados ⇒ cuenta 1 de 2 referidos)');
select pg_temp.exigir(pg_temp.aporte((select f from dic), '2026-12-01', '2027-01-01') = 6 + 1 + 1, 'C7b2: 6 + 1 referido + 1 de base cargada (pesa 1) = 8; salió ' || pg_temp.aporte((select f from dic), '2026-12-01', '2027-01-01'));
select pg_temp.exigir(pg_temp.referidos_que_cuentan((select g from dic)) = 1, 'C7c: los referidos NO suben su propio tope (6 asignados ⇒ cuenta 1 de 2 referidos)');
select pg_temp.exigir(pg_temp.aporte((select g from dic), '2026-12-01', '2027-01-01') = 7, 'C7c2: 6 + 1 referido = 7');
-- (d) el ejemplo aprobado: tope 2, cuentan los 2 referidos más antiguos (días 11 y 12), los 2 más recientes valen 0.
select pg_temp.exigir((select array_agg(e.fecha_numerador order by e.fecha_numerador) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', true, '{}', 1) e
                        where e.analista_id = (select m from dic) and e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 1)
  = array['2026-12-11'::date::timestamp at time zone 'America/Lima', '2026-12-12'::date::timestamp at time zone 'America/Lima'],
  'C7d: ejemplo aprobado: tope 2 y cuentan los 2 referidos más antiguos');
select pg_temp.exigir((select count(*) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', true, '{}', 1) e
                        where e.analista_id = (select m from dic) and e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 0) = 2,
  'C7d2: ejemplo aprobado: los 2 referidos más recientes valen 0');
select pg_temp.exigir(pg_temp.aporte((select m from dic), '2026-12-01', '2027-01-01') = 10 + 2 + 3 * 0.15 + 2 + 1, 'C7d3: 10 + 2 referidos + 3 renovaciones×0,15 + 2 upgrades + 1 de base cargada = 15,45; salió ' || pg_temp.aporte((select m from dic), '2026-12-01', '2027-01-01'));
-- (e) sin cierres asignados la base es 0 y el tope es 0: ningún referido cuenta, y nada de lo demás lo rescata.
select pg_temp.exigir(pg_temp.referidos_que_cuentan((select z from dic)) = 0 and pg_temp.referidos_que_cuentan((select y from dic)) = 0,
  'C7e: base 0 ⇒ tope 0 ⇒ ningún referido cuenta (ni con un upgrade ni con base cargada)');
select pg_temp.exigir(pg_temp.aporte((select z from dic), '2026-12-01', '2027-01-01') = 1 + 1 and pg_temp.aporte((select y from dic), '2026-12-01', '2027-01-01') = 0,
  'C7e2: Z suma solo su upgrade (1) y su base cargada (1); Y, con solo referidos, suma 0');

-- ── Caso 13 · un lead de alta manual (registro manual: regla cerrada) NO sube el tope, pero su cierre sigue sumando entero ───────────
-- H: 6 asignados + 1 landing de ALTA MANUAL + 2 referidos. Base 6 ⇒ tope ceil(0,9) = 1 ⇒ cuenta 1 referido. (Si el alta manual
-- entrara en la base serían 7 ⇒ tope ceil(1,05) = 2 ⇒ contarían los 2.) Su aporte al numerador sigue siendo 1.
create temp table hh as select gen_random_uuid() h;
do $$ declare h uuid := (select h from hh); i int; l uuid; begin
  for i in 1..6 loop perform pg_temp.cierre(h, 'formulario', '2026-12-01', i); end loop;
  l := pg_temp.cierre(h, 'landing', '2026-12-01', 7);
  update crm.leads set alta_manual = true where id = l;
  create temp table hh_manual as select l lead_id;
  for i in 1..2 loop perform pg_temp.cierre(h, 'referido', '2026-12-01', 10 + i); end loop;
end $$;
select pg_temp.exigir(pg_temp.referidos_que_cuentan((select h from hh)) = 1, 'C13a: un lead de alta manual NO sube el tope (6 asignados ⇒ cuenta 1 de 2 referidos)');
select pg_temp.exigir((select e.aporte_numerador from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', true, '{}', 1) e
                        where e.lead_id = (select lead_id from hh_manual) and e.tipo = 'cierre') = 1,
  'C13b: el cierre del alta manual sigue sumando 1 al numerador');
select pg_temp.exigir(pg_temp.aporte((select h from hh), '2026-12-01', '2027-01-01') = 6 + 1 + 1, 'C13c: 6 asignados + 1 alta manual + 1 referido = 8; salió ' || pg_temp.aporte((select h from hh), '2026-12-01', '2027-01-01'));

-- ── Caso 14 · el ámbito {E, F} da a E el mismo aporte que el ámbito {E} (la base de uno no depende de los demás) ─────────────────
select pg_temp.exigir(
  (select coalesce(sum(e.aporte_numerador), 0) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', false, array[(select e from dic), (select f from dic)], 1) e
    where e.analista_id = (select e from dic) and e.tipo <> 'recibido')
  = (select coalesce(sum(e.aporte_numerador), 0) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', false, array[(select e from dic)], 1) e
      where e.analista_id = (select e from dic) and e.tipo <> 'recibido')
  and pg_temp.aporte((select e from dic), '2026-12-01', '2027-01-01', false) = 6 + 1 + 2 + 2 * 0.15,
  'C14: el ámbito {E, F} da a E lo mismo que {E} y que la vista global (9,30)');

-- ── Caso 15 · los cierres SIN analista (analista_id NULL) comparten UN solo tope ─────────────────────────────────────────────────
-- 3 + 3 asignados sin analista y 2 referidos sin analista: una sola partición ⇒ base 6 ⇒ tope 1 ⇒ cuenta UN referido en total.
-- Solo los ve el ámbito global (un actor de equipo o propio no los ve). En producción hay 0 (07/10/2026).
do $$ declare i int; begin
  for i in 1..3 loop perform pg_temp.cierre(null, 'landing', '2026-12-01', i); end loop;
  for i in 1..3 loop perform pg_temp.cierre(null, 'formulario', '2026-12-01', 3 + i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(null, 'referido', '2026-12-01', 10 + i); end loop;
end $$;
select pg_temp.exigir((select count(*) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', true, '{}', 1) e
                        where e.analista_id is null and e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 1) = 1,
  'C15a: los cierres sin analista comparten un solo tope (base 6 ⇒ cuenta 1 de 2 referidos)');
select pg_temp.exigir(not exists (select 1 from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', false, array[(select e from dic)], 1) e where e.analista_id is null),
  'C15b: un ámbito de analista no ve los cierres sin analista');

-- ── Caso 8 · el divisor no cambia ───────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.exigir((select coalesce(sum(e.aporte_divisor), 0) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e)
  = (select coalesce(sum(e.aporte_divisor), 0) from pg_temp.conversion_episodios_anterior('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e), 'C8: el divisor no cambia');

-- ── Caso 9 · el tope de un mes SIN versión de tope (ene–sep) es NULL, y un mes futuro hereda el 15 % ───────────────────────────────
select pg_temp.exigir(private.tope_referidos_conversion('2026-07-01') is null and private.tope_referidos_conversion('2026-09-01') is null
  and private.tope_referidos_conversion('2026-10-01') = 15 and private.tope_referidos_conversion('2027-03-01') = 15, 'C9: topes por mes');

-- ── Caso 10 · empate de fecha comercial: cuenta antes el que se acreditó antes (no el de menor uuid) ──────────────────────────
do $$ declare t uuid := gen_random_uuid(); i int; r record; k int := 0; begin
  for i in 1..8 loop perform pg_temp.cierre(t, 'formulario', '2027-01-01', 10); end loop;
  for i in 1..3 loop perform pg_temp.cierre(t, 'referido', '2027-01-01', 10); end loop;      -- 8 asignados ⇒ tope ceil(1,2) = 2
  -- los tres referidos comparten fecha comercial; se acreditan en el orden CONTRARIO al de su uuid
  for r in select ca.lead_id from crm.conversion_acreditaciones ca where ca.analista_id = t and ca.origen = 'referido' order by ca.lead_id desc loop
    k := k + 1;
    update crm.conversion_acreditaciones set confirmado_en = timestamptz '2027-01-12 10:00-05' + k * interval '1 hour',
      vinculado_en = timestamptz '2027-01-12 10:00-05' + k * interval '1 hour', acreditado_en = timestamptz '2027-01-12 10:00-05' + k * interval '1 hour'
     where lead_id = r.lead_id;
  end loop;
  create temp table emp as select t;
end $$;
select pg_temp.exigir((select array_agg(e.lead_id order by e.lead_id) from private.conversion_episodios('2027-01-01'::timestamptz, '2027-02-01'::timestamptz, '2027-01-01', true, '{}', 1) e
                        where e.analista_id = (select t from emp) and e.fue_referido and e.aporte_numerador = 1)
  = (select array_agg(lead_id order by lead_id) from (select ca.lead_id from crm.conversion_acreditaciones ca where ca.analista_id = (select t from emp) and ca.origen = 'referido' order by ca.acreditado_en limit 2) x),
  'C10: de tres referidos con la misma fecha comercial cuentan los 2 acreditados primero');

-- ── Caso 11 · un rango de dos meses SIN periodo (p_periodo NULL) no cambia agosto/septiembre ni los no referidos de octubre ─────────
select pg_temp.exigir(not exists (
  (select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_numerador from private.conversion_episodios('2026-09-01'::timestamptz, '2026-11-01'::timestamptz, null::date, true, '{}', 1) e
    where e.fecha_numerador < '2026-10-01'::timestamptz and e.tipo <> 'recibido'
   except select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_numerador from pg_temp.conversion_episodios_anterior('2026-09-01'::timestamptz, '2026-11-01'::timestamptz, null::date, true, '{}', 1) e
    where e.fecha_numerador < '2026-10-01'::timestamptz and e.tipo <> 'recibido')
  union all
  (select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_numerador from pg_temp.conversion_episodios_anterior('2026-09-01'::timestamptz, '2026-11-01'::timestamptz, null::date, true, '{}', 1) e
    where e.fecha_numerador < '2026-10-01'::timestamptz and e.tipo <> 'recibido'
   except select e.tipo, e.analista_id, e.lead_id, e.operacion_id, e.aporte_numerador from private.conversion_episodios('2026-09-01'::timestamptz, '2026-11-01'::timestamptz, null::date, true, '{}', 1) e
    where e.fecha_numerador < '2026-10-01'::timestamptz and e.tipo <> 'recibido')),
  'C11a: en un rango que cruza septiembre y octubre, septiembre queda idéntico a la función anterior');
select pg_temp.exigir(not exists (
  select 1 from private.conversion_episodios('2026-09-01'::timestamptz, '2026-11-01'::timestamptz, null::date, true, '{}', 1) n
  join pg_temp.conversion_episodios_anterior('2026-09-01'::timestamptz, '2026-11-01'::timestamptz, null::date, true, '{}', 1) v
    on v.tipo = n.tipo and v.lead_id is not distinct from n.lead_id and v.operacion_id is not distinct from n.operacion_id
  where n.tipo <> 'recibido' and not n.fue_referido and n.aporte_numerador is distinct from v.aporte_numerador),
  'C11b: en ese rango los no referidos no cambian en ningún mes');

-- ── Caso 12 · el CHECK ata el peso al tope ────────────────────────────────────────────────────────────────────────────────────────
do $$ begin
  begin
    insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion) values ('2027-02-01', 1.000, 0.15);
    raise exception 'FALLA: C12: se aceptó una versión con peso 1 y SIN tope';
  exception when check_violation then null; end;
  insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion) values ('2027-02-01', 0.150, 0.15);                                  -- el peso de antes sin tope: permitido
  insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion, tope_referidos_pct) values ('2027-03-01', 1.000, 0.15, 10.00);        -- peso 1 con tope: permitido
end $$;
select pg_temp.exigir(private.tope_referidos_conversion('2027-02-15') is null and private.tope_referidos_conversion('2027-03-15') = 10,
  'C12b: las versiones válidas rigen por mes');

select 'PRUEBA TOPE: PASS' as resultado;
rollback;
