-- B4 · Enfriamiento con fechas simuladas (una transacción, impersonación, ROLLBACK al final). Falla el proceso si hay FAIL.
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$ insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
grant execute on function pg_temp.caso(text,text,text) to authenticated;
create function pg_temp.err(p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_caso, p_esperado, 'paso'); exception when others then perform pg_temp.caso(p_caso, p_esperado, sqlstate); end $$;
grant execute on function pg_temp.err(text,text,text) to authenticated;
create temp table f as select
  'b0000000-0000-4000-8000-000000000002'::uuid a, 'b0000000-0000-4000-8000-000000000012'::uuid b, 'b0000000-0000-4000-8000-000000000013'::uuid c,
  'b0000000-0000-4000-8000-0000000000a1'::uuid la, 'b0000000-0000-4000-8000-0000000000b1'::uuid lb, 'b0000000-0000-4000-8000-0000000000c1'::uuid lc,
  (now() at time zone 'America/Lima')::date hoy, now() t0;
grant select on f to authenticated;
create function pg_temp.intento(p_lead uuid, p_res text, p_prox timestamptz default null) returns jsonb language sql as $$
  select crm.registrar_intento_base(gen_random_uuid(), p_lead, p_res, 'b4', p_prox); $$;
grant execute on function pg_temp.intento(uuid,text,timestamptz) to authenticated;

-- ───────── A: 3 intentos sin rellamada → descansa ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
select pg_temp.caso('A: intento 1 no enfría', 'null', coalesce((pg_temp.intento((select la from f), 'no_contesto'))->>'enfriado_hasta', 'null'));
select pg_temp.caso('A: intento 2 no enfría', 'null', coalesce((pg_temp.intento((select la from f), 'numero_errado'))->>'enfriado_hasta', 'null'));
select pg_temp.caso('A: intento 3 sin rellamada → enfriado_hasta = hoy + 30', 'ok', case when (pg_temp.intento((select la from f), 'no_contesto'))->>'enfriado_hasta' = (select (hoy + 30)::text from f) then 'ok' else 'mal' end);
select pg_temp.caso('A: LA ya no está en la base', '0', (select count(*) from crm.obtener_base_gestion() b, f where b.lead_id = f.la)::text);
select pg_temp.err('A: intento sobre LA en descanso → 22023', '22023', format('select pg_temp.intento(%L, %L)', (select la from f), 'no_contesto'));
reset role;
-- Simular que pasan los 30 días: el descanso vence ayer (vía privilegiada del propio esquema).
select set_config('crm.op_base_gestion','on',true); update crm.leads set enfriado_hasta = (select hoy - 1 from f) where id = (select la from f); select set_config('crm.op_base_gestion','off',true);
-- …y que los tres intentos ocurrieron hace 40 días (antes de la ventana nueva, que arranca al vencer el descanso).
update crm.actividades set creado_en = creado_en - interval '40 days' where lead_id = (select la from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select a from f)); set local role authenticated;
select pg_temp.caso('A: pasados los 30 días LA reaparece con el contador en 0 (D13) y su historial íntegro (3 actividades)', 'ok', case when exists (select 1 from crm.obtener_base_gestion() b, f where b.lead_id = f.la and b.intentos = 0) and (select count(*) from crm.actividades, f where lead_id = f.la and metadata->>'evento' = 'intento_base') = 3 then 'ok' else 'mal' end);
select pg_temp.caso('A: tras el descanso, el 1.º intento con rellamada no enfría (D12)', 'ok', case when (pg_temp.intento((select la from f), 'volver_a_llamar', now() + interval '2 days'))->>'enfriado_hasta' = (select (hoy - 1)::text from f) then 'ok' else 'mal' end);
select pg_temp.caso('A: tras el descanso, el 2.º intento sin rellamada tampoco enfría (D13: cupo nuevo)', 'ok', case when (pg_temp.intento((select la from f), 'no_interesado'))->>'enfriado_hasta' = (select (hoy - 1)::text from f) then 'ok' else 'mal' end);
select pg_temp.caso('A: el 3.º intento de la nueva ventana sin rellamada vuelve a enfriar 30 días', 'ok', case when (pg_temp.intento((select la from f), 'no_contesto'))->>'enfriado_hasta' = (select (hoy + 30)::text from f) then 'ok' else 'mal' end);
reset role;
-- ───────── B: D12, el 3.º intento con rellamada no enfría; el 4.º sin rellamada sí ─────────
select pg_temp.sesion((select b from f)); set local role authenticated;
select pg_temp.intento((select lb from f), 'no_contesto'); select pg_temp.intento((select lb from f), 'no_contesto');
select pg_temp.caso('B: 3.º intento = volver_a_llamar → no enfría (D12)', 'null', coalesce((pg_temp.intento((select lb from f), 'volver_a_llamar', now() + interval '1 day'))->>'enfriado_hasta', 'null'));
select pg_temp.caso('B: LB sigue en la base con la rellamada', 'ok', case when exists (select 1 from crm.obtener_base_gestion() x, f where x.lead_id = f.lb and x.proxima_llamada_en is not null) then 'ok' else 'mal' end);
select pg_temp.caso('B: 4.º intento sin rellamada → enfría', 'ok', case when (pg_temp.intento((select lb from f), 'no_contesto'))->>'enfriado_hasta' = (select (hoy + 30)::text from f) then 'ok' else 'mal' end);
reset role;
-- ───────── C: agendó cita nunca enfría (reactiva); reactivar limpia el descanso ─────────
select pg_temp.sesion((select c from f)); set local role authenticated;
select pg_temp.intento((select lc from f), 'no_contesto'); select pg_temp.intento((select lc from f), 'no_contesto');
select pg_temp.caso('C: 3.º intento = agendó cita → reactiva y no enfría', 'ok', case when (select (j->>'reactivado')::bool and j->>'enfriado_hasta' is null and j->>'etapa' = 'contactado' from pg_temp.intento((select lc from f), 'agendo_reunion') j) then 'ok' else 'mal' end);
reset role;
select set_config('crm.op_base_gestion','on',true);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = (select lc from f);  -- vuelve a caer
update crm.leads set enfriado_hasta = (select hoy + 10 from f) where id = (select lc from f);               -- y descansa (simulado)
select set_config('crm.op_base_gestion','off',true);
select pg_temp.sesion((select c from f)); set local role authenticated;
select pg_temp.caso('C: LC en descanso no está en la base', '0', (select count(*) from crm.obtener_base_gestion() x, f where x.lead_id = f.lc)::text);
select pg_temp.caso('C: reactivar LC en descanso → contactado (ciclo 3)', 'ok', case when (select j->>'etapa' = 'contactado' and (j->>'ciclo_n')::int = 3 from crm.reactivar_lead_base(gen_random_uuid(), (select lc from f), 'vuelve') j) then 'ok' else 'mal' end);
-- (sentencia aparte: el orden de evaluación dentro de un mismo CASE no está garantizado)
select pg_temp.caso('C: la reactivación limpió el descanso y reinició el SLA', 'ok', case when exists (select 1 from crm.leads l, f where l.id = f.lc and l.enfriado_hasta is null and l.reactivado_en is not null and l.sla_global_iniciado_en >= f.t0) then 'ok' else 'mal' end);
reset role;
-- ───────── Backfill sin usuario y sin GUC (P2 del auditor): no enfría ─────────
select pg_temp.sesion(null);  -- sin usuario (los claims son de transacción; reset role no los limpia)
insert into crm.actividades (lead_id, tipo, detalle, metadata)
select (select lc from f), 'llamada_no_contestada', 'backfill', jsonb_build_object('evento','intento_base','resultado','no_contesto','intento_n',g,'ciclo_n',3) from generate_series(1,3) g;
select pg_temp.caso('Backfill: 3 intento_base sin usuario ni GUC no ponen a descansar', 'null', coalesce((select enfriado_hasta::text from crm.leads, f where id = f.lc), 'null'));
-- ───────── Resultado ─────────
update r set ok = (obtenido = esperado);
select format('%s %s · esperado %s · obtenido %s', case when ok then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 120)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where not ok)) from r;
do $$ begin if exists (select 1 from r where not ok) then raise exception 'B4: hay casos FAIL'; end if; end $$;
rollback;
