-- Prueba del SELLO y la DEUDA con el tope de referidos (sintética, todo se deshace). Banco con la migración 20261007160937.
--   psql -v ON_ERROR_STOP=1 -f prueba-sello-deuda.sql
-- Mundo: un analista con 12 cierres en octubre (8 no referidos + 4 referidos ⇒ tope ceil(1,8) = 2) y otro con 3 referidos en
-- septiembre-2026 sin tope. Se sella con INSERT directo en crm.periodos_cerrados (el trigger del sello es lo que se prueba).
begin;
set local session_replication_role = replica;
set local search_path = '';

create function pg_temp.exigir(p_ok boolean, p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FALLA: %', p_motivo; end if; end $$;

create or replace function private.conversion_exclusion_fuente(p_tipo text, p_id uuid) returns text
  language sql stable set search_path = '' as $$ select 'elegible'::text $$;

create function pg_temp.cierre(p_analista uuid, p_origen text, p_mes date, p_dia int) returns uuid language plpgsql as $$
declare v_lead uuid := gen_random_uuid(); v_ep uuid; v_fecha timestamptz := (p_mes + p_dia)::timestamp at time zone 'America/Lima';
begin
  insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, creado_en, etapa, convertido_en)
    values (v_lead, 'Sintetico ' || v_lead, '9' || substr(replace(v_lead::text, '-', ''), 1, 8), p_origen, 1000,
            (p_mes - 40)::timestamp at time zone 'America/Lima', 'convertido', v_fecha);
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
      sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en,
      resultado, resultado_en, finalizado_en, motivo_cierre)
    values (v_lead, 1, 1, p_analista, 'asignado', v_fecha - interval '20 days', 'PEN', p_origen,
      v_fecha - interval '20 days', gen_random_uuid(), v_fecha, v_fecha, 'convertido', v_fecha, v_fecha, 'convertido') returning id into v_ep;
  insert into crm.conversion_acreditaciones (lead_id, episodio_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial,
      confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, politica_desde, motivo)
    values (v_lead, v_ep, p_analista, p_origen, 'contrato', gen_random_uuid(), p_mes + (p_dia - 1),
      v_fecha, v_fecha, v_fecha, p_mes, private.conversion_plazo_hasta(p_mes), 'acreditada', '2026-09-01', 'sintetico');
  return v_lead;
end $$;

create temp table mundo (lead_id uuid, analista uuid, origen text, mes date, dia int);
do $$ declare a uuid := 'a0000000-0000-4000-8000-00000000000a'; i int; l uuid; begin
  for i in 1..8 loop l := pg_temp.cierre(a, 'formulario', '2026-10-01', i); insert into mundo values (l, a, 'formulario', '2026-10-01', i); end loop;
  for i in 1..4 loop l := pg_temp.cierre(a, 'referido', '2026-10-01', 10 + i); insert into mundo values (l, a, 'referido', '2026-10-01', 10 + i); end loop;
  a := 'b0000000-0000-4000-8000-00000000000b';
  for i in 1..3 loop l := pg_temp.cierre(a, 'referido', '2026-09-01', 5 + i); insert into mundo values (l, a, 'referido', '2026-09-01', 5 + i); end loop;
end $$;

-- ── El sello de OCTUBRE con tope: la foto guarda 15 ─────────────────────────────────────────────────────────────────────────────
set local session_replication_role = origin;
insert into crm.periodos_cerrados (periodo, ponderacion_referido, ponderacion_renovacion, tope_referidos_pct, meta_revision, cobertura, automatico)
  values ('2026-10-01', 1.000, 0.15, 15.00, 1, '{}'::jsonb, true);
select pg_temp.exigir((select tope_referidos_pct from crm.periodos_cerrados where periodo = '2026-10-01') = 15, 'S1: la foto guarda el tope');
select pg_temp.exigir((select count(*) from crm.conversion_acreditaciones ca join mundo m using (lead_id) where m.mes = '2026-10-01' and m.origen = 'formulario' and ca.incluida_en_sello) = 8,
  'S2: los 8 no referidos quedan incluidos en el sello');
select pg_temp.exigir((select array_agg(m.dia order by m.dia) from crm.conversion_acreditaciones ca join mundo m using (lead_id) where m.mes = '2026-10-01' and m.origen = 'referido' and ca.incluida_en_sello) = array[11, 12],
  'S3: solo los 2 referidos más antiguos (tope 2) quedan incluidos en el sello');
select pg_temp.exigir((select count(*) from crm.conversion_acreditaciones ca join mundo m using (lead_id) where m.mes = '2026-10-01' and m.origen = 'referido' and ca.incluida_en_sello is false) = 2,
  'S4: los 2 referidos que pasaron del tope quedan FUERA del sello');

-- Para la deuda se desactivan los triggers de FK (el analista sintético no es un perfil real), pero se deja ACTIVO lo demás.
set local session_replication_role = replica;
-- ── La deuda: anular un referido que sí pesó cobra 1; anular uno que no pesó no cobra nada ──────────────────────────────────────────
-- (la llamada y la lectura van en sentencias distintas: una subconsulta no ve lo que escribe la función de su misma sentencia)
set local session_replication_role = replica;
create temp table ajuste_res (caso text, id uuid);
insert into ajuste_res select 'D1', private.registrar_ajuste_si_mes_cerrado((select lead_id from mundo where mes = '2026-10-01' and dia = 11), 'sintetico', 'a0000000-0000-4000-8000-00000000000a');
insert into ajuste_res select 'D2', private.registrar_ajuste_si_mes_cerrado((select lead_id from mundo where mes = '2026-10-01' and dia = 14), 'sintetico', 'a0000000-0000-4000-8000-00000000000a');
insert into ajuste_res select 'D3', private.registrar_ajuste_si_mes_cerrado((select lead_id from mundo where mes = '2026-10-01' and dia = 3 and origen = 'formulario'), 'sintetico', 'a0000000-0000-4000-8000-00000000000a');
select pg_temp.exigir((select id from ajuste_res where caso = 'D1') is not null
  and (select numerador from crm.ajustes_mes_cerrado where lead_id = (select lead_id from mundo where mes = '2026-10-01' and dia = 11)) = 1.000,
  'D1: anular un referido que SÍ contaba genera una deuda de 1');
select pg_temp.exigir((select id from ajuste_res where caso = 'D2') is null
  and not exists (select 1 from crm.ajustes_mes_cerrado where lead_id = (select lead_id from mundo where mes = '2026-10-01' and dia = 14)),
  'D2: anular un referido que pasó del tope NO genera deuda');
select pg_temp.exigir((select id from ajuste_res where caso = 'D3') is not null
  and (select numerador from crm.ajustes_mes_cerrado where lead_id = (select lead_id from mundo where mes = '2026-10-01' and dia = 3 and origen = 'formulario')) = 1,
  'D3: anular un cierre no referido cobra 1, como siempre');

-- ── Un mes SIN tope (septiembre) se sella como siempre: todos incluidos y el referido cobra 0,15 ────────────────────────────────────────
set local session_replication_role = origin;
insert into crm.periodos_cerrados (periodo, ponderacion_referido, ponderacion_renovacion, tope_referidos_pct, meta_revision, cobertura, automatico)
  values ('2026-09-01', 0.150, 0.15, null, 1, '{}'::jsonb, true);
set local session_replication_role = replica;
select pg_temp.exigir((select count(*) from crm.conversion_acreditaciones ca join mundo m using (lead_id) where m.mes = '2026-09-01' and ca.incluida_en_sello) = 3,
  'S5: sin tope, los 3 referidos de septiembre quedan incluidos');
insert into ajuste_res select 'D4', private.registrar_ajuste_si_mes_cerrado((select lead_id from mundo where mes = '2026-09-01' and dia = 7), 'sintetico', 'b0000000-0000-4000-8000-00000000000b');
select pg_temp.exigir((select id from ajuste_res where caso = 'D4') is not null
  and (select numerador from crm.ajustes_mes_cerrado where lead_id = (select lead_id from mundo where mes = '2026-09-01' and dia = 7)) = 0.150,
  'D4: un mes sin tope cobra el peso de siempre (0,15)');

select 'PRUEBA SELLO Y DEUDA: 9 aserciones PASS' as resultado;
rollback;
