-- B2 · Pruebas de permisos en el banco, bajo rol `authenticated` con impersonación (ambas formas del claim).
-- Toda la corrida va en UNA transacción que termina en ROLLBACK: no deja rastro. Una línea por caso: PASS/FAIL.
-- Nunca llamar bajo `set role` a una función sin EXECUTE para authenticated (cuelga PG 17.6).
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
-- Actores y leads de fixtures-b2.sql
create temp table f as select
  'b0000000-0000-4000-8000-000000000002'::uuid as a, 'b0000000-0000-4000-8000-000000000012'::uuid as b,
  'b0000000-0000-4000-8000-000000000013'::uuid as c, 'b0000000-0000-4000-8000-000000000001'::uuid as s1,
  'b0000000-0000-4000-8000-000000000011'::uuid as s2, 'b0000000-0000-4000-8000-000000000003'::uuid as g,
  'b0000000-0000-4000-8000-0000000000a1'::uuid as la, 'b0000000-0000-4000-8000-0000000000b1'::uuid as lb,
  'b0000000-0000-4000-8000-0000000000c1'::uuid as lc, 'b0000000-0000-4000-8000-0000000000a2'::uuid as la_veto,
  'b0000000-0000-4000-8000-0000000000d1'::uuid as ld;
grant select on f to authenticated;

-- ───────── Analista A ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'A lee su descartado LA', '1', count(*)::text from crm.leads, f where id = f.la;
insert into r(caso, esperado, obtenido) select 'A NO lee LB (mismo equipo) ni LC (otro equipo)', '0', count(*)::text from crm.leads, f where id in (f.lb, f.lc);
insert into r(caso, esperado, obtenido) select 'A ve enfriado_hasta/reactivado_en de LA (NULL,NULL)', 'ok', case when count(*) = 1 then 'ok' else 'sin fila' end from (select enfriado_hasta, reactivado_en from crm.leads, f where id = f.la) q;
do $$ declare n int; begin update crm.leads set nota = 'B2 nota A' where id = (select la from f); get diagnostics n = row_count; insert into r(caso,esperado,obtenido) values ('A edita nota en LA', '1', n::text); end $$;
do $$ declare n int; begin update crm.leads set nota = 'B2 intruso' where id = (select lb from f); get diagnostics n = row_count; insert into r(caso,esperado,obtenido) values ('A NO edita LB (0 filas)', '0', n::text); end $$;
do $$ begin insert into crm.actividades (lead_id, tipo, detalle, creado_por) select la, 'nota', 'B2 nota A', a from f; insert into r(caso,esperado,obtenido) values ('A registra actividad en LA', 'ok', 'ok'); exception when others then insert into r(caso,esperado,obtenido) values ('A registra actividad en LA', 'ok', sqlstate); end $$;
do $$ begin insert into crm.actividades (lead_id, tipo, detalle, creado_por) select lb, 'nota', 'B2 intruso', a from f; insert into r(caso,esperado,obtenido) values ('A NO registra actividad en LB', '42501', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO registra actividad en LB', '42501', sqlstate); end $$;
insert into r(caso, esperado, obtenido) select 'A lee la actividad de LA, no la de LB', '1/0', (select count(*) from crm.actividades, f where lead_id = f.la and detalle = 'B2 nota A')::text || '/' || (select count(*) from crm.actividades, f where lead_id = f.lb)::text;
do $$ begin update crm.leads set enfriado_hasta = current_date where id = (select la from f); insert into r(caso,esperado,obtenido) values ('A NO escribe enfriado_hasta (sello)', '42501', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO escribe enfriado_hasta (sello)', '42501', sqlstate); end $$;
do $$ begin update crm.leads set vendedor_id = (select b from f) where id = (select la from f); insert into r(caso,esperado,obtenido) values ('A NO reasigna LA', 'error', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO reasigna LA', 'error', 'error ' || sqlstate); end $$;
do $$ begin update crm.leads set etapa = 'nuevo', motivo_descarte = null where id = (select la from f); insert into r(caso,esperado,obtenido) values ('A NO reabre LA por UPDATE (solo por puerta)', 'P0409', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO reabre LA por UPDATE (solo por puerta)', 'P0409', sqlstate); end $$;
do $$ begin perform crm.levantar_no_contactar((select la_veto from f), 'intento'); insert into r(caso,esperado,obtenido) values ('A NO levanta no_contactar', '42501', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO levanta no_contactar', '42501', sqlstate); end $$;
reset role;
-- ───────── Analista B (mismo equipo que A) ─────────
select pg_temp.sesion((select b from f)); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'B NO lee LA (mismo supervisor no basta)', '0', count(*)::text from crm.leads, f where id = f.la;
insert into r(caso, esperado, obtenido) select 'B lee su LB', '1', count(*)::text from crm.leads, f where id = f.lb;
reset role;
-- ───────── Supervisor 1 (equipo de A y B) ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'S1 lee LA y LB, no LC', '2/0', (select count(*) from crm.leads, f where id in (f.la, f.lb))::text || '/' || (select count(*) from crm.leads, f where id = f.lc)::text;
do $$ begin perform crm.levantar_no_contactar((select lc from f), 'fuera'); insert into r(caso,esperado,obtenido) values ('S1 NO levanta en LC (otro equipo)', 'P0002', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('S1 NO levanta en LC (otro equipo)', 'P0002', sqlstate); end $$;
do $$ declare j jsonb; begin j := crm.levantar_no_contactar((select la_veto from f), 'cliente pidió volver'); insert into r(caso,esperado,obtenido) values ('S1 levanta LA_VETO (persona con LD en equipo 2 por mismo DNI)', 'ok o 42501', 'ok leads=' || (j->>'leads_afectados')); exception when others then insert into r(caso,esperado,obtenido) values ('S1 levanta LA_VETO (persona con LD en equipo 2 por mismo DNI)', 'ok o 42501', sqlstate || ' ' || left(sqlerrm, 60)); end $$;
reset role;
-- ───────── Supervisor 2 (equipo de C) ─────────
select pg_temp.sesion((select s2 from f)); set local role authenticated;
do $$ begin perform crm.levantar_no_contactar((select la_veto from f), 'ajeno'); insert into r(caso,esperado,obtenido) values ('S2 NO levanta LA_VETO (de A, equipo 1)', 'P0002', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('S2 NO levanta LA_VETO (de A, equipo 1)', 'P0002', sqlstate); end $$;
reset role;
-- ───────── Gerencia ─────────
select pg_temp.sesion((select g from f)); set local role authenticated;
do $$ declare j jsonb; begin j := crm.levantar_no_contactar((select ld from f), 'gerencia levanta'); insert into r(caso,esperado,obtenido) values ('G levanta LD', 'ok', 'ok leads=' || (j->>'leads_afectados')); exception when others then insert into r(caso,esperado,obtenido) values ('G levanta LD', 'ok', sqlstate || ' ' || left(sqlerrm, 60)); end $$;
insert into r(caso, esperado, obtenido) select 'historial dice por Gerencia con rol', 'ok', case when exists (select 1 from crm.actividades, f where lead_id = f.ld and detalle = 'Levantado No contactar por Gerencia' and metadata->>'rol' = 'gerencia') then 'ok' else 'falta' end;
reset role;
-- ───────── Resultado ─────────
update r set ok = case when esperado = 'ok o 42501' then obtenido like 'ok%' or obtenido like '42501%'
                       when esperado = 'error' then obtenido like 'error%'
                       when esperado = 'ok' then obtenido like 'ok%'
                       else obtenido = esperado end;
select format('%s %s · esperado %s · obtenido %s', case when ok then 'PASS' else 'FAIL' end, caso, esperado, obtenido) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where not ok)) from r;
rollback;
