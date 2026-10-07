-- Prueba del tope de referidos (sintética, todo se deshace). Se corre contra un banco con la migración
-- 20261007160937 aplicada, como postgres:  psql -v ON_ERROR_STOP=1 -f prueba-tope.sql
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

-- ── Caso 1 · el ejemplo de Miguel: 20 cierres, 5 referidos ⇒ tope 3, cuentan los 3 más antiguos ───────────────────────────────
do $$ declare a uuid := (select a from ana); i int; v_ref uuid[] := '{}'; begin
  for i in 1..15 loop perform pg_temp.cierre(a, case when i % 2 = 0 then 'formulario' else 'landing' end, '2026-10-01', 1 + (i % 6)); end loop;
  for i in 1..5 loop v_ref := v_ref || pg_temp.cierre(a, 'referido', '2026-10-01', 10 + i); end loop;   -- días 11..15
  create temp table ref_a as select unnest(v_ref) lead_id, generate_series(1, 5) orden;
end $$;
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01') = 18,
  'C1: 15 no referidos (15) + 3 referidos que cuentan (3) = 18; salió ' || pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01'));
select pg_temp.exigir((select array_agg(e.lead_id order by e.fecha_numerador) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e
                        where e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 1 and e.analista_id = (select a from ana))
                      = (select array_agg(lead_id order by orden) from ref_a where orden <= 3), 'C1: cuentan los 3 referidos MÁS ANTIGUOS');
select pg_temp.exigir((select count(*) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e
                        where e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 0 and e.analista_id = (select a from ana)) = 2,
  'C1: los 2 referidos más recientes valen 0');

-- ── Caso 2 · septiembre NO lleva tope: los mismos 20 cierres con 5 referidos valen 15 + 5 × 0,15 ───────────────────────────────
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

-- ── Caso 4 · redondeo hacia arriba y bordes ─────────────────────────────────────────────────────────────────────────────────
-- 19 cierres (2 referidos): 15 % = 2,85 ⇒ tope 3 ⇒ cuentan los 2.  | 7 cierres con 2 referidos: 1,05 ⇒ tope 2 ⇒ cuentan 2.
-- 6 cierres con 2 referidos: 0,9 ⇒ tope 1 ⇒ cuenta 1.        | 1 cierre referido: tope 1 ⇒ cuenta.
do $$ declare c uuid := (select c from ana); i int; begin
  for i in 1..17 loop perform pg_temp.cierre(c, 'formulario', '2026-10-01', 1 + (i % 6)); end loop;
  perform pg_temp.cierre(c, 'referido', '2026-10-01', 20); perform pg_temp.cierre(c, 'referido', '2026-10-01', 21);
end $$;
select pg_temp.exigir(pg_temp.aporte((select c from ana), '2026-10-01', '2026-11-01') = 19, 'C4a: 19 cierres, 2 referidos, tope 3 ⇒ cuentan los 2 ⇒ 19');
create temp table borde (n int, refs int, esperado numeric);
insert into borde values (6, 2, 5), (7, 2, 7), (20, 5, 18), (13, 4, 11), (1, 1, 1), (2, 2, 1), (40, 10, 36);
do $$ declare r record; ana_x uuid; i int; mes date := '2026-11-01'; begin
  for r in select * from borde loop
    ana_x := gen_random_uuid();
    for i in 1..(r.n - r.refs) loop perform pg_temp.cierre(ana_x, 'formulario', mes, 1 + (i % 6)); end loop;
    for i in 1..r.refs loop perform pg_temp.cierre(ana_x, 'referido', mes, 10 + i); end loop;
    perform pg_temp.exigir(pg_temp.aporte(ana_x, '2026-11-01', '2026-12-01') = r.esperado,
      format('C4b: %s cierres con %s referidos ⇒ %s; salió %s', r.n, r.refs, r.esperado, pg_temp.aporte(ana_x, '2026-11-01', '2026-12-01')));
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

-- ── Caso 6 · un cierre anulado no entra en la base ni cuenta: anular un NO referido baja la base y el tope ──────────────────────────────
-- A tiene 20 cierres (tope 3). Anulo 7 cierres no referidos ⇒ quedan 13 cierres (8 + 5 ref): tope ceil(1,95) = 2.
do $$ declare a uuid := (select a from ana); r record; n int := 0; begin
  for r in select ca.lead_id from crm.conversion_acreditaciones ca where ca.analista_id = a and ca.periodo_comercial = '2026-10-01' and ca.origen <> 'referido' order by ca.fecha_comercial, ca.lead_id loop
    exit when n = 7;
    insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por) values (r.lead_id, 'sintetico', a);
    n := n + 1;
  end loop;
end $$;
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01') = 8 + 2, 'C6: anuladas 7 ⇒ 8 no referidos + 2 referidos (tope 2) = 10; salió ' || pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01'));
delete from crm.cierres_avance_anulados;
-- Anulo el referido MÁS ANTIGUO (día 11): la base baja a 19 (tope ceil(2,85) = 3) y los referidos vivos son 4 ⇒ cuentan los días 12, 13 y 14.
insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por) select lead_id, 'sintetico', (select a from ana) from ref_a where orden = 1;
select pg_temp.exigir(pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01') = 15 + 3, 'C6b: anulado el primer referido ⇒ entra el 4.º: 15 + 3 = 18; salió ' || pg_temp.aporte((select a from ana), '2026-10-01', '2026-11-01'));
delete from crm.cierres_avance_anulados;

-- ── Caso 7 · la base incluye operaciones de cartera (upgrade y renovación) ───────────────────────────────────────────────────
do $$ declare d uuid := gen_random_uuid(); i int; begin
  -- 6 cierres (1 referido) + 4 operaciones (2 upgrade, 2 renovación) = 10 cierres ⇒ tope ceil(1,5) = 2 ⇒ los 2 referidos cuentan
  for i in 1..4 loop perform pg_temp.cierre(d, 'formulario', '2026-12-01', i); end loop;
  perform pg_temp.cierre(d, 'referido', '2026-12-01', 10); perform pg_temp.cierre(d, 'referido', '2026-12-01', 11);
  for i in 1..4 loop
    insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion, periodo, moneda, elegible_conversion, fuente, creado_por,
        desglose_completo, contrato_origen_id, capital_renovado, capital_adicional)
    values (gen_random_uuid(), d, case when i <= 2 then 'upgrade' else 'renovacion' end, gen_random_uuid(), '2026-12-05', '2026-12-01', 'PEN', true, 'flujo_cartera', d,
        true, case when i <= 2 then null else gen_random_uuid() end, case when i <= 2 then null else 1000 end, case when i <= 2 then null else 0 end);
  end loop;
  create temp table dd as select d;
end $$;
-- sin operaciones la base sería 6 ⇒ tope 1 ⇒ cuenta 1 referido; con las 4 operaciones es 10 ⇒ tope 2 ⇒ cuentan los 2.
select pg_temp.exigir((select count(*) from private.conversion_episodios('2026-12-01'::timestamptz, '2027-01-01'::timestamptz, '2026-12-01', true, '{}', 1) e
                        where e.analista_id = (select d from dd) and e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador = 1) = 2,
  'C7: las operaciones de cartera cuentan en la base del tope');
select pg_temp.exigir(pg_temp.aporte((select d from dd), '2026-12-01', '2027-01-01') = 4 + 2 + 2 * 1 + 2 * 0.15, 'C7b: 4 + 2 referidos + 2 upgrade + 2 renovaciones×0,15');

-- ── Caso 8 · el divisor no cambia ───────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.exigir((select coalesce(sum(e.aporte_divisor), 0) from private.conversion_episodios('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e)
  = (select coalesce(sum(e.aporte_divisor), 0) from pg_temp.conversion_episodios_anterior('2026-10-01'::timestamptz, '2026-11-01'::timestamptz, '2026-10-01', true, '{}', 1) e), 'C8: el divisor no cambia');

-- ── Caso 9 · el tope de un mes SIN versión de tope (ene–sep) es NULL, y un mes futuro hereda el 15 % ───────────────────────────────
select pg_temp.exigir(private.tope_referidos_conversion('2026-07-01') is null and private.tope_referidos_conversion('2026-09-01') is null
  and private.tope_referidos_conversion('2026-10-01') = 15 and private.tope_referidos_conversion('2027-03-01') = 15, 'C9: topes por mes');

-- ── Caso 10 · empate de fecha comercial: cuenta antes el que se acreditó antes (no el de menor uuid) ──────────────────────────
do $$ declare t uuid := gen_random_uuid(); i int; r record; k int := 0; begin
  for i in 1..4 loop perform pg_temp.cierre(t, 'formulario', '2027-01-01', 10); end loop;
  for i in 1..3 loop perform pg_temp.cierre(t, 'referido', '2027-01-01', 10); end loop;      -- 7 cierres ⇒ tope ceil(1,05) = 2
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

select 'PRUEBA TOPE: 22 grupos de aserciones PASS' as resultado;
rollback;
