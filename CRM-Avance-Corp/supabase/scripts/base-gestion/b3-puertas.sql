-- B3 · Pruebas de comportamiento de las puertas en el banco (una transacción, impersonación, ROLLBACK al final).
-- Falla el proceso si hay algún FAIL. Actores y leads: fixtures-b2.sql / fixtures-b2-persona.sql.
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
create temp table f as select
  'b0000000-0000-4000-8000-000000000002'::uuid a, 'b0000000-0000-4000-8000-000000000012'::uuid b, 'b0000000-0000-4000-8000-000000000013'::uuid c,
  'b0000000-0000-4000-8000-000000000001'::uuid s1, 'b0000000-0000-4000-8000-000000000011'::uuid s2, 'b0000000-0000-4000-8000-000000000003'::uuid g,
  'b0000000-0000-4000-8000-0000000000a1'::uuid la, 'b0000000-0000-4000-8000-0000000000b1'::uuid lb, 'b0000000-0000-4000-8000-0000000000c1'::uuid lc,
  'b0000000-0000-4000-8000-0000000000a2'::uuid la_veto,
  'b0000000-0000-4000-8000-00000000b301'::uuid lx1, 'b0000000-0000-4000-8000-00000000b302'::uuid lx2, 'b0000000-0000-4000-8000-00000000b303'::uuid lx3,
  '00000000-0000-4000-8000-0000000000b1'::uuid op1, '00000000-0000-4000-8000-0000000000b2'::uuid op2, '00000000-0000-4000-8000-0000000000b3'::uuid op3,
  '00000000-0000-4000-8000-0000000000b4'::uuid op4, '00000000-0000-4000-8000-0000000000b5'::uuid op5, '00000000-0000-4000-8000-0000000000b6'::uuid op6,
  '00000000-0000-4000-8000-0000000000b7'::uuid op7, '00000000-0000-4000-8000-0000000000b8'::uuid op8, '00000000-0000-4000-8000-0000000000b9'::uuid op9,
  now() as t0;
grant select on f to authenticated;
-- Leads extra de A para el orden (deshechos al final): LX1 nuevo→descartado; LX2 nuevo→contactado→descartado; LX3 nuevo→descartado.
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo) values
  ('b0000000-0000-4000-8000-00000000b301','B3 LX1','988770201','70000201','otro','nuevo','b0000000-0000-4000-8000-000000000002',1000,'PEN','b0000000-0000-4000-8000-000000000002',true),
  ('b0000000-0000-4000-8000-00000000b302','B3 LX2','988770202','70000202','otro','nuevo','b0000000-0000-4000-8000-000000000002',1000,'PEN','b0000000-0000-4000-8000-000000000002',true),
  ('b0000000-0000-4000-8000-00000000b303','B3 LX3','988770203','70000203','otro','nuevo','b0000000-0000-4000-8000-000000000002',1000,'PEN','b0000000-0000-4000-8000-000000000002',true);
update crm.leads set etapa = 'contactado' where id = 'b0000000-0000-4000-8000-00000000b302';
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id in ('b0000000-0000-4000-8000-00000000b301','b0000000-0000-4000-8000-00000000b302','b0000000-0000-4000-8000-00000000b303');
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$ insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
grant execute on function pg_temp.caso(text,text,text) to authenticated;
create function pg_temp.err(p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_caso, p_esperado, 'paso'); exception when others then perform pg_temp.caso(p_caso, p_esperado, sqlstate); end $$;
grant execute on function pg_temp.err(text,text,text) to authenticated;

-- ───────── Analista A ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
select pg_temp.caso('A: base = sus 4 descartados sin veto (LA, LX1, LX2, LX3)', '4/0', (select count(*) from crm.obtener_base_gestion())::text || '/' || (select count(*) from crm.obtener_base_gestion() b, f where b.vendedor_id <> f.a or b.lead_id in (f.la_veto))::text);
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op1 from f), (select la from f), 'no_contesto', 'sin respuesta'); perform pg_temp.caso('A: intento 1 no_contesto en LA', 'ok n=1 sin fecha', case when (j->>'ok')::bool and (j->>'intento_n')='1' and j->>'proxima_llamada_en' is null and not (j->>'replay')::bool then 'ok n=1 sin fecha' else j::text end); end $$;
select pg_temp.caso('A: la actividad es llamada_no_contestada con evento intento_base', 'ok', case when exists (select 1 from crm.actividades, f where id = f.op1 and tipo = 'llamada_no_contestada' and metadata->>'evento' = 'intento_base' and metadata->>'resultado' = 'no_contesto' and detalle = 'sin respuesta') then 'ok' else 'falta' end);
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op1 from f), (select la from f), 'no_contesto', 'sin respuesta'); perform pg_temp.caso('A: doble clic (misma operación) → replay, sin duplicar', 'replay 1 actividad', case when (j->>'replay')::bool and (select count(*) from crm.actividades, f where lead_id = f.la and metadata->>'evento'='intento_base') = 1 then 'replay 1 actividad' else j::text end); end $$;
select pg_temp.err('A: misma operación con otro contenido → 23505', '23505', format('select crm.registrar_intento_base(%L, %L, %L)', (select op1 from f), (select la from f), 'no_interesado'));
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op2 from f), (select la from f), 'volver_a_llamar', 'pidió que lo llame', now() + interval '1 minute'); perform pg_temp.caso('A: intento 2 volver_a_llamar (+1 min) fija la rellamada', 'ok n=2 con fecha', case when (j->>'ok')::bool and (j->>'intento_n')='2' and j->>'proxima_llamada_en' is not null then 'ok n=2 con fecha' else j::text end); end $$;
select pg_temp.caso('A: el lead lleva proxima_llamada_en y la metadata la trae en ISO', 'ok', case when exists (select 1 from crm.leads, f where id = f.la and proxima_llamada_en is not null) and exists (select 1 from crm.actividades, f where id = f.op2 and (metadata->>'proxima_llamada_en') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T') then 'ok' else 'falta' end);
select pg_temp.err('A: volver_a_llamar a 11 días → 22023', '22023', format('select crm.registrar_intento_base(%L, %L, %L, null, %L)', (select op3 from f), (select la from f), 'volver_a_llamar', now() + interval '11 days'));
select pg_temp.err('A: volver_a_llamar sin fecha → 22023', '22023', format('select crm.registrar_intento_base(%L, %L, %L)', (select op3 from f), (select la from f), 'volver_a_llamar'));
select pg_temp.err('A: no_contesto con fecha → 22023', '22023', format('select crm.registrar_intento_base(%L, %L, %L, null, %L)', (select op3 from f), (select la from f), 'no_contesto', now() + interval '1 day'));
select pg_temp.err('A: resultado inválido → 22023', '22023', format('select crm.registrar_intento_base(%L, %L, %L)', (select op3 from f), (select la from f), 'interesado'));
select pg_temp.err('A: intento en LB (de B) → P0002', 'P0002', format('select crm.registrar_intento_base(%L, %L, %L)', (select op3 from f), (select lb from f), 'no_contesto'));
select pg_temp.err('A: intento en LA_VETO (no contactar) → P0429', 'P0429', format('select crm.registrar_intento_base(%L, %L, %L)', (select op3 from f), (select la_veto from f), 'no_contesto'));
select pg_temp.err('A: intento en lead inexistente → P0002', 'P0002', format('select crm.registrar_intento_base(%L, %L, %L)', (select op3 from f), gen_random_uuid(), 'no_contesto'));
select pg_temp.caso('A: orden = LA (rellamada hoy) → LX2 (contactado) → LX1/LX3 (nuevo)', 'ok', case when (select array_agg(lead_id order by n) from (select lead_id, row_number() over () n from crm.obtener_base_gestion()) q) = (select array[f.la, f.lx2, f.lx1, f.lx3] from f) or (select array_agg(lead_id order by n) from (select lead_id, row_number() over () n from crm.obtener_base_gestion()) q) = (select array[f.la, f.lx2, f.lx3, f.lx1] from f) then 'ok' else (select string_agg(right(lead_id::text, 4) || ':' || etapa_maxima || ':' || rellamada_hoy::text, ' > ' order by n) from (select lead_id, etapa_maxima, rellamada_hoy, row_number() over () n from crm.obtener_base_gestion()) q) end);
select pg_temp.caso('A: LA trae intentos=2, ultimo=volver_a_llamar, rellamada_hoy, etapa_maxima nuevo; LX2 etapa_maxima contactado', 'ok', case when exists (select 1 from crm.obtener_base_gestion() b, f where b.lead_id = f.la and b.intentos = 2 and b.ultimo_resultado = 'volver_a_llamar' and b.rellamada_hoy and b.etapa_maxima = 'nuevo' and b.gestiona = 'BANCO VENDEDOR') and exists (select 1 from crm.obtener_base_gestion() b, f where b.lead_id = f.lx2 and b.etapa_maxima = 'contactado' and b.intentos = 0) then 'ok' else (select string_agg(right(lead_id::text,4)||':'||etapa_maxima||':'||intentos||':'||coalesce(ultimo_resultado,'-')||':'||rellamada_hoy::text, ' ') from crm.obtener_base_gestion()) end);
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op4 from f), (select la from f), 'no_interesado', 'ya no'); perform pg_temp.caso('A: intento 3 no_interesado consume la rellamada y (B4) pone a LA a descansar 30 días', 'ok n=3 sin fecha descansa', case when (j->>'intento_n')='3' and j->>'proxima_llamada_en' is null and (j->>'enfriado_hasta')::date = (now() at time zone 'America/Lima')::date + 30 and exists (select 1 from crm.leads, f where id = f.la and proxima_llamada_en is null and enfriado_hasta is not null) then 'ok n=3 sin fecha descansa' else j::text end); end $$;
do $$ declare j jsonb; begin j := crm.reactivar_lead_base((select op5 from f), (select lx1 from f), 'el cliente volvió a llamar'); perform pg_temp.caso('A: reactivar LX1 → contactado, reactivado_en, ciclo 2', 'ok', case when j->>'etapa' = 'contactado' and j->>'reactivado_en' is not null and (j->>'ciclo_n')::int = 2 and not (j->>'replay')::bool then 'ok' else j::text end); end $$;
select pg_temp.caso('A: LX1 vivo en contactado, mismo dueño, sin rellamada ni descanso, con la línea en el historial', 'ok', case when exists (select 1 from crm.leads, f where id = f.lx1 and etapa = 'contactado' and vendedor_id = f.a and reactivado_en is not null and proxima_llamada_en is null and enfriado_hasta is null and motivo_descarte is null) and exists (select 1 from crm.actividades, f where id = f.op5 and metadata->>'evento' = 'reactivacion_base' and detalle = 'el cliente volvió a llamar') then 'ok' else 'mal' end);
do $$ declare j jsonb; begin j := crm.reactivar_lead_base((select op5 from f), (select lx1 from f), 'el cliente volvió a llamar'); perform pg_temp.caso('A: doble clic en Reactivar → replay', 'replay', case when (j->>'replay')::bool then 'replay' else j::text end); end $$;
select pg_temp.err('A: reactivar un lead que ya no está en la base → 22023', '22023', format('select crm.reactivar_lead_base(%L, %L)', (select op6 from f), (select lx1 from f)));
select pg_temp.caso('A: LX1 ya no aparece en la base (ni LA, que descansa)', '2', (select count(*) from crm.obtener_base_gestion())::text);
select pg_temp.err('A: intento sobre LA en descanso → 22023', '22023', format('select crm.registrar_intento_base(%L, %L, %L)', gen_random_uuid(), (select la from f), 'no_contesto'));
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op7 from f), (select lx3 from f), 'agendo_reunion', 'quiere reunión el viernes'); perform pg_temp.caso('A: agendó cita en LX3 → reactiva en la misma operación', 'ok reactivado contactado', case when (j->>'reactivado')::bool and j->>'etapa' = 'contactado' then 'ok reactivado contactado' else j::text end); end $$;
select pg_temp.caso('A: LX3 tiene la actividad del intento y la de reactivación', '2', (select count(*) from crm.actividades, f where lead_id = f.lx3 and metadata->>'evento' in ('intento_base','reactivacion_base'))::text);
reset role;
select pg_temp.caso('SLA: LX1 reinició su reloj global al reactivar', 'ok', case when exists (select 1 from crm.leads, f where id = f.lx1 and sla_global_iniciado_en >= f.t0) then 'ok' else 'no reinició' end);
select pg_temp.caso('SLA: LX1 tiene episodio abierto en contactado (ciclo 2)', 'ok', case when exists (select 1 from crm.lead_sla_etapas e, f where e.lead_id = f.lx1 and e.finalizado_en is null and e.etapa = 'contactado' and e.ciclo_n = 2) then 'ok' else 'sin episodio' end);
-- Reactivado y descartado otra vez: vuelve a la base con historial y el contador reinicia.
update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id = (select lx1 from f);
select pg_temp.sesion((select a from f)); set local role authenticated;
select pg_temp.caso('A: LX1 descartado otra vez vuelve a la base con intentos=0 y ciclo 2', 'ok', case when exists (select 1 from crm.obtener_base_gestion() b, f where b.lead_id = f.lx1 and b.intentos = 0 and b.ciclo_n = 2 and b.etapa_maxima = 'contactado') then 'ok' else (select string_agg(right(lead_id::text,4)||':'||etapa_maxima||':'||intentos||':'||ciclo_n, ' ') from crm.obtener_base_gestion() b, f where b.lead_id = f.lx1) end);
select pg_temp.err('A: resumen de Supervisión → 42501', '42501', 'select * from crm.base_gestion_resumen()');
select pg_temp.err('A: forja una «reactivación» por INSERT directo → 42501 (sello)', '42501', format('insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values (%L, %L, %L, %L, %L)', (select la from f), 'nota', 'forja', '{"evento":"reactivacion_base"}', (select a from f)));
select pg_temp.err('A: forja una «respuesta» por INSERT directo → 42501 (sello)', '42501', format('insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values (%L, %L, %L, %L, %L)', (select la from f), 'nota', 'forja', '{"respuesta":{"ok":true}}', (select a from f)));
select pg_temp.err('A: forja un «intento_base» por INSERT directo → 42501', '42501', format('insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values (%L, %L, %L, %L, %L)', (select la from f), 'nota', 'forja', '{"evento":"intento_base","ciclo_n":"1"}', (select a from f)));
reset role;
-- ───────── Analista B ─────────
select pg_temp.sesion((select b from f)); set local role authenticated;
select pg_temp.caso('B: base = solo LB', 'ok', case when (select array_agg(lead_id) from crm.obtener_base_gestion()) = (select array[f.lb] from f) then 'ok' else 'mal' end);
select pg_temp.err('B: intento en LA → P0002', 'P0002', format('select crm.registrar_intento_base(%L, %L, %L)', (select op8 from f), (select la from f), 'no_contesto'));
reset role;
-- ───────── Supervisor 1 ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: base = equipo 1 (LB, LX1, LX2; LA descansa) sin LC', 'ok', case when (select count(*) from crm.obtener_base_gestion()) = 3 and not exists (select 1 from crm.obtener_base_gestion() b, f where b.lead_id = f.lc) then 'ok' else (select count(*)::text from crm.obtener_base_gestion()) end);
select pg_temp.caso('S1: filtro por analista A → solo A', 'ok', case when not exists (select 1 from crm.obtener_base_gestion((select a from f)) b, f where b.vendedor_id <> f.a) and (select count(*) from crm.obtener_base_gestion((select a from f))) = 2 then 'ok' else 'mal' end);
select pg_temp.err('S1: filtro por analista C (otro equipo) → P0002', 'P0002', format('select * from crm.obtener_base_gestion(%L)', (select c from f)));
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op8 from f), (select lb from f), 'numero_errado', 'número de otra persona'); perform pg_temp.caso('S1: registra intento en LB (su equipo)', 'ok', case when (j->>'ok')::bool then 'ok' else j::text end); end $$;
select pg_temp.caso('S1: resumen = A y B con cifras', 'ok', case when exists (select 1 from crm.base_gestion_resumen() x, f where x.vendedor_id = f.a and x.en_base = 2 and x.intentos_hoy = 4 and x.reactivaciones_mes = 2) and exists (select 1 from crm.base_gestion_resumen() x, f where x.vendedor_id = f.b and x.en_base = 1 and x.intentos_hoy = 1) and not exists (select 1 from crm.base_gestion_resumen() x, f where x.vendedor_id = f.c) then 'ok' else (select string_agg(left(vendedor_id::text,8)||':'||en_base||'/'||intentos_hoy||'/'||reactivaciones_mes, ' ') from crm.base_gestion_resumen()) end);
reset role;
-- ───────── Supervisor 2 ─────────
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: base = solo LC', 'ok', case when (select array_agg(lead_id) from crm.obtener_base_gestion()) = (select array[f.lc] from f) then 'ok' else 'mal' end);
select pg_temp.err('S2: intento en LA → P0002', 'P0002', format('select crm.registrar_intento_base(%L, %L, %L)', (select op9 from f), (select la from f), 'no_contesto'));
reset role;
-- ───────── Gerencia ─────────
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('G: base = todos los descartados sin veto ni descanso (4: LA descansa)', '4', (select count(*) from crm.obtener_base_gestion())::text);
do $$ declare j jsonb; begin j := crm.registrar_intento_base((select op9 from f), (select lc from f), 'pide_otro_producto', 'quiere crédito', null); perform pg_temp.caso('G: registra intento en LC', 'ok', case when (j->>'ok')::bool then 'ok' else j::text end); end $$;
select pg_temp.caso('G: resumen incluye a C con el intento de Gerencia atribuido a C', 'ok', case when exists (select 1 from crm.base_gestion_resumen() x, f where x.vendedor_id = f.c and x.en_base = 1 and x.intentos_hoy = 1) then 'ok' else (select string_agg(left(vendedor_id::text,8)||':'||en_base||'/'||intentos_hoy, ' ') from crm.base_gestion_resumen()) end);
reset role;
-- ───────── Resultado ─────────
update r set ok = (obtenido = esperado);
select format('%s %s · esperado %s · obtenido %s', case when ok then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 160)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where not ok)) from r;
do $$ begin if exists (select 1 from r where not ok) then raise exception 'B3: hay casos FAIL'; end if; end $$;
rollback;
