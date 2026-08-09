-- Oráculo transaccional de F1 tandas 1 y 2 (20260809043802 + 20260809144912 +
-- 20260809144920). Éxito = token METRICAS_SERVIDOR_TX_OK; todo queda en rollback.
-- Cubre lo que la matriz .mjs NO puede con los fixtures del seed: la cascada
-- COMPLETA de buckets de cola_accion_fn (una rama por lead fabricado), la
-- ventana de convertidos de 45 días (resumen/vendedores la aplican, series NO),
-- la aritmética exacta de los agregados, los 22023 de parámetros, el 42501 de
-- un autenticado ajeno al CRM, y la tríada de ACL + prosecdef + search_path.
-- Tanda 2: resumen_tareas_fn (dos criterios de vencida + señales de alertas),
-- resumen_cartera_clientes_fn (alarma de renovación con bajas y sin_asesor
-- invisible fuera de gerencia/lector), resumen_reparto_fn (gate coordinador),
-- y la rama de parkeados del coordinador en las 3 RPC de agregados puros
-- (cola_accion_fn queda deliberadamente SIN ella: items con PII, premisa C1).
-- Los esperados del coordinador se calculan como postgres en GUCs `oraculo.*`
-- ANTES de asumir roles: inmunes a residuos de otras suites y con now()
-- congelado por la transacción.
--
-- Fixtures fabricados con triggers apagados (session_replication_role=replica,
-- solo rama desechable): los CHECK sí aplican (motivo_descarte obligatorio en
-- descartados, monedas PEN/USD, teléfonos únicos vivos).

begin;

set local session_replication_role = replica;

-- ── Personas: supervisor S, vendedor V (subárbol de S), portal-only P ────────
insert into public.perfiles(id, nombre_completo, correo, rol, activo) values
  ('7f100000-0000-4000-8000-000000000001', 'ORACULO F1 SUPERVISOR', 'f1-s@test.invalid', 'comercial', true),
  ('7f100000-0000-4000-8000-000000000002', 'ORACULO F1 VENDEDOR', 'f1-v@test.invalid', 'comercial', true),
  ('7f100000-0000-4000-8000-000000000003', 'ORACULO F1 PORTAL PURO', 'f1-p@test.invalid', 'cliente', true);

insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
  ('7f100000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('7f100000-0000-4000-8000-000000000002', 'vendedor', '7f100000-0000-4000-8000-000000000001', true);

-- ── Política SLA fabricada (para el episodio de etapa de L5) ─────────────────
insert into crm.sla_politicas(id, version, vigente_desde, zona_horaria, tipo_reloj,
                              primera_gestion_minutos, primer_contacto_minutos, publicada_en)
values ('7f100000-0000-4000-8000-0000000000aa', 7777, now() - interval '30 days',
        'America/Lima', 'corrido', 1440, 2880, now() - interval '30 days');

-- ── Leads: una rama de la cascada por lead (montos únicos para sumas) ────────
-- L1 sin_responder: nuevo, sin contacto jamás, 60 h en manos de V.
-- L2 insistir: nuevo, intento (no contestó) hace 2 d, tenencia hace 3 d.
-- L3 seguimiento: contactado, contacto hace 4 d.
-- L4 propuesta_sin_respuesta: propuesta_enviada, contacto hace 6 d (único ≥5 d
--    sin plan → también el ÚNICO estancado esperado).
-- L5 sin_avance: contactado, contacto hace 1 d, episodio de etapa sellado
--    iniciado hace 10 d con límite hace 5 d (duración 5 d → ya pasó el doble).
-- L6 plan_vencido: contactado, contacto hace 1 d, tarea pendiente vencida hace 3 d.
-- L7 escudado: contactado, contacto hace 10 d PERO tarea vigente (mañana) → fuera.
-- L8 por_repartir: parkeado en la bandeja de S.
-- L9 convertido FRESCO (10 d, USD): dentro de la ventana de 45 d.
-- L10 convertido VIEJO (60 d, PEN): fuera de resumen/vendedores, DENTRO de series.
-- L11 descartado con motivo.
insert into crm.leads(id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
                      vendedor_id, asignado_supervisor_id, creado_por, creado_en,
                      tenencia_desde, convertido_en, contrato_id, motivo_descarte) values
  ('7f100000-0000-4000-8000-000000000101', 'ORACULO L1 SIN RESPONDER', '51999117101', 'otro', 'nuevo', 1000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '60 hours', now() - interval '60 hours', null, null, null),
  ('7f100000-0000-4000-8000-000000000102', 'ORACULO L2 INSISTIR', '51999117102', 'otro', 'nuevo', 2000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '12 days', now() - interval '3 days', null, null, null),
  ('7f100000-0000-4000-8000-000000000103', 'ORACULO L3 SEGUIMIENTO', '51999117103', 'otro', 'contactado', 4000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '12 days', now() - interval '12 days', null, null, null),
  ('7f100000-0000-4000-8000-000000000104', 'ORACULO L4 PROPUESTA', '51999117104', 'otro', 'propuesta_enviada', 8000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '12 days', now() - interval '12 days', null, null, null),
  ('7f100000-0000-4000-8000-000000000105', 'ORACULO L5 SIN AVANCE', '51999117105', 'otro', 'contactado', 16000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '12 days', now() - interval '12 days', null, null, null),
  ('7f100000-0000-4000-8000-000000000106', 'ORACULO L6 PLAN VENCIDO', '51999117106', 'otro', 'contactado', 32000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '12 days', now() - interval '12 days', null, null, null),
  ('7f100000-0000-4000-8000-000000000107', 'ORACULO L7 CON PLAN VIVO', '51999117107', 'otro', 'contactado', 64000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '20 days', now() - interval '20 days', null, null, null),
  ('7f100000-0000-4000-8000-000000000108', 'ORACULO L8 PARKEADO', '51999117108', 'otro', 'nuevo', 128000, 'PEN',
   null, '7f100000-0000-4000-8000-000000000001', '7f100000-0000-4000-8000-000000000001',
   now() - interval '1 day', null, null, null, null),
  ('7f100000-0000-4000-8000-000000000109', 'ORACULO L9 CONVERTIDO FRESCO', '51999117109', 'otro', 'convertido', 5000, 'USD',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '15 days', now() - interval '15 days', now() - interval '10 days',
   '7f100000-0000-4000-8000-00000000c109', null),
  ('7f100000-0000-4000-8000-000000000110', 'ORACULO L10 CONVERTIDO VIEJO', '51999117110', 'otro', 'convertido', 7000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '70 days', now() - interval '70 days', now() - interval '60 days',
   '7f100000-0000-4000-8000-00000000c110', null),
  ('7f100000-0000-4000-8000-000000000111', 'ORACULO L11 DESCARTADO', '51999117111', 'otro', 'descartado', 3000, 'PEN',
   '7f100000-0000-4000-8000-000000000002', null, '7f100000-0000-4000-8000-000000000002',
   now() - interval '20 days', now() - interval '20 days', null, null, 'sin_interes');

-- ── Actividades (contacto real salvo indicación) ─────────────────────────────
insert into crm.actividades(id, lead_id, tipo, detalle, creado_por, creado_en) values
  ('7f100000-0000-4000-8000-000000000202', '7f100000-0000-4000-8000-000000000102',
   'llamada_no_contestada', 'oraculo intento', '7f100000-0000-4000-8000-000000000002', now() - interval '2 days'),
  ('7f100000-0000-4000-8000-000000000203', '7f100000-0000-4000-8000-000000000103',
   'llamada_realizada', 'oraculo contacto', '7f100000-0000-4000-8000-000000000002', now() - interval '4 days'),
  ('7f100000-0000-4000-8000-000000000204', '7f100000-0000-4000-8000-000000000104',
   'llamada_realizada', 'oraculo contacto', '7f100000-0000-4000-8000-000000000002', now() - interval '6 days'),
  ('7f100000-0000-4000-8000-000000000205', '7f100000-0000-4000-8000-000000000105',
   'llamada_realizada', 'oraculo contacto', '7f100000-0000-4000-8000-000000000002', now() - interval '1 day'),
  ('7f100000-0000-4000-8000-000000000206', '7f100000-0000-4000-8000-000000000106',
   'llamada_realizada', 'oraculo contacto', '7f100000-0000-4000-8000-000000000002', now() - interval '1 day'),
  ('7f100000-0000-4000-8000-000000000207', '7f100000-0000-4000-8000-000000000107',
   'llamada_realizada', 'oraculo contacto', '7f100000-0000-4000-8000-000000000002', now() - interval '10 days');

-- ── Episodio de etapa sellado para L5 (sin_avance) ───────────────────────────
insert into crm.lead_sla_etapas(id, lead_id, ciclo_n, episodio_n, etapa, politica_id,
                                iniciado_en, limite_en, aproximado) values
  ('7f100000-0000-4000-8000-000000000305', '7f100000-0000-4000-8000-000000000105', 1, 1,
   'contactado', '7f100000-0000-4000-8000-0000000000aa',
   now() - interval '10 days', now() - interval '5 days', false);

-- ── Tareas: la vencida de L6 y la vigente de L7 ──────────────────────────────
insert into crm.tareas(id, lead_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_por) values
  ('7f100000-0000-4000-8000-000000000406', '7f100000-0000-4000-8000-000000000106',
   '7f100000-0000-4000-8000-000000000002', 'tarea', 'ORACULO TAREA VENCIDA L6',
   now() - interval '3 days', 'pendiente', true, '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000407', '7f100000-0000-4000-8000-000000000107',
   '7f100000-0000-4000-8000-000000000002', 'tarea', 'ORACULO TAREA VIGENTE L7',
   now() + interval '1 day', 'pendiente', true, '7f100000-0000-4000-8000-000000000002');

-- ── Tanda 2: coordinador CO, clientes con contratos, cola global, T3 ─────────
-- CO opera el reparto; C es cliente EN GESTIÓN del vendedor V con 3 contratos
-- (activo PEN por vencer, activo USD lejano, vencido); CB es cliente DE BAJA
-- de V con contrato activo por vencer (la alarma no se apaga con la baja);
-- CS es cliente activo SIN asesor (solo gerencia/lector deben contarlo).
insert into public.perfiles(id, nombre_completo, correo, rol, activo, asesor_perfil_id) values
  ('7f100000-0000-4000-8000-000000000004', 'ORACULO F1 COORDINADOR', 'f1-co@test.invalid', 'comercial', true, null),
  ('7f100000-0000-4000-8000-000000000005', 'ORACULO CLIENTE GESTION', 'f1-c@test.invalid', 'cliente', true, '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000006', 'ORACULO CLIENTE DE BAJA', 'f1-cb@test.invalid', 'cliente', false, '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000007', 'ORACULO CLIENTE SIN ASESOR', 'f1-cs@test.invalid', 'cliente', true, null);

insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
  ('7f100000-0000-4000-8000-000000000004', 'coordinador', null, true);

-- Contratos K1..K5 (producto_condicion_id apunta a un uuid inerte: la FK está
-- suspendida por replica y el resumen NO une con el catálogo — NOT NULL en
-- prod garantiza que el INNER JOIN de contratos_cartera_fn tampoco descarta).
insert into public.contratos(id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
                             modalidad, tipo_interes, categoria, estado,
                             fecha_inicio, fecha_vencimiento, producto_condicion_id, creado_por) values
  ('7f100000-0000-4000-8000-000000000b01', 'ORACULO-K1', '7f100000-0000-4000-8000-000000000005', 3000, 'PEN', 10,
   'mensual', 'simple', 'nuevo', 'activo',
   (now() at time zone 'America/Lima')::date - 355, (now() at time zone 'America/Lima')::date + 10,
   '7f100000-0000-4000-8000-000000000a03', '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000b02', 'ORACULO-K2', '7f100000-0000-4000-8000-000000000005', 1500, 'USD', 10,
   'mensual', 'simple', 'nuevo', 'activo',
   (now() at time zone 'America/Lima')::date - 100, (now() at time zone 'America/Lima')::date + 200,
   '7f100000-0000-4000-8000-000000000a03', '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000b03', 'ORACULO-K3', '7f100000-0000-4000-8000-000000000005', 9000, 'PEN', 10,
   'mensual', 'simple', 'nuevo', 'vencido',
   (now() at time zone 'America/Lima')::date - 400, (now() at time zone 'America/Lima')::date - 10,
   '7f100000-0000-4000-8000-000000000a03', '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000b04', 'ORACULO-K4', '7f100000-0000-4000-8000-000000000006', 4000, 'PEN', 10,
   'mensual', 'simple', 'renovacion', 'activo',
   (now() at time zone 'America/Lima')::date - 360, (now() at time zone 'America/Lima')::date + 5,
   '7f100000-0000-4000-8000-000000000a03', '7f100000-0000-4000-8000-000000000002'),
  ('7f100000-0000-4000-8000-000000000b05', 'ORACULO-K5', '7f100000-0000-4000-8000-000000000007', 7770, 'PEN', 10,
   'mensual', 'simple', 'nuevo', 'activo',
   (now() at time zone 'America/Lima')::date - 30, (now() at time zone 'America/Lima')::date + 3,
   '7f100000-0000-4000-8000-000000000a03', null);

-- Cola GLOBAL de reparto: G1 (posible crédito, 3 días esperando), G2 (USD,
-- hoy), G3 (no_contactar: JAMÁS en la cola — Ley 29571 — pero SÍ parkeado
-- para los agregados de cartera del coordinador).
insert into crm.leads(id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
                      vendedor_id, asignado_supervisor_id, creado_por, creado_en,
                      clasificacion_auto, no_contactar) values
  ('7f100000-0000-4000-8000-000000000112', 'ORACULO G1 COLA CREDITO', '51999117112', 'landing', 'nuevo', 10000, 'PEN',
   null, null, '7f100000-0000-4000-8000-000000000004', now() - interval '3 days', 'posible_credito', false),
  ('7f100000-0000-4000-8000-000000000113', 'ORACULO G2 COLA USD', '51999117113', 'otro', 'nuevo', 500, 'USD',
   null, null, '7f100000-0000-4000-8000-000000000004', now(), null, false),
  ('7f100000-0000-4000-8000-000000000114', 'ORACULO G3 NO INSISTA', '51999117114', 'otro', 'nuevo', 900, 'PEN',
   null, null, '7f100000-0000-4000-8000-000000000004', now(), null, true);

-- T3: la vencida POR HORA de L3 (26 h: siempre día-Lima anterior → cuenta en
-- ambos criterios de forma determinista). No cambia la cascada de cola_accion:
-- seguimiento (dias>=3) dispara ANTES que plan_vencido.
insert into crm.tareas(id, lead_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_por) values
  ('7f100000-0000-4000-8000-000000000408', '7f100000-0000-4000-8000-000000000103',
   '7f100000-0000-4000-8000-000000000002', 'llamada', 'ORACULO LLAMADA VENCIDA L3',
   now() - interval '26 hours', 'pendiente', true, '7f100000-0000-4000-8000-000000000002');

set local session_replication_role = origin;

-- ── Esperados del coordinador, calculados como postgres (RLS al margen) ──────
-- Inmunes a residuos de otras suites; now() está congelado por la transacción,
-- así que la aritmética de días coincide EXACTA con la de las RPC.
select set_config('oraculo.reparto_total', (
  select count(*)::text from crm.leads l
  where l.activo and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false), true);
select set_config('oraculo.reparto_pen', (
  select coalesce(sum(coalesce(l.monto_estimado, 0)) filter (where l.moneda is distinct from 'USD'), 0)::text
  from crm.leads l
  where l.activo and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false), true);
select set_config('oraculo.reparto_usd', (
  select coalesce(sum(coalesce(l.monto_estimado, 0)) filter (where l.moneda = 'USD'), 0)::text
  from crm.leads l
  where l.activo and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false), true);
select set_config('oraculo.reparto_espera', (
  select coalesce(greatest(floor(extract(epoch from (now() - min(l.creado_en))) / 86400.0), 0)::int, 0)::text
  from crm.leads l
  where l.activo and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false), true);
select set_config('oraculo.reparto_credito', (
  select count(*)::text from crm.leads l
  where l.activo and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false and l.clasificacion_auto = 'posible_credito'), true);
select set_config('oraculo.park_n', (
  select count(*)::text from crm.leads l
  where l.activo and l.vendedor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')), true);
select set_config('oraculo.park_pen', (
  select coalesce(sum(coalesce(l.monto_estimado, 0)) filter (where l.moneda is distinct from 'USD'), 0)::text
  from crm.leads l
  where l.activo and l.vendedor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')), true);
select set_config('oraculo.series_nuevos', (
  select count(*)::text from crm.leads l
  where l.activo and l.vendedor_id is null
    and l.creado_en >= (((date_trunc('month', (now() at time zone 'America/Lima'))::date
                          - make_interval(months => 5))::timestamp) at time zone 'America/Lima')), true);

-- ═════════════════════════════════════════════════════════════════════════════
-- Asserts como el SUPERVISOR S (ve su subárbol + su bandeja)
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000001', true);
set local role authenticated;

-- M01 — resumen_cartera_fn: totales, ventana, capital por moneda, embudo,
-- conversión, descartes, sin_tocar.
do $test$
declare
  v jsonb := crm.resumen_cartera_fn();
  t jsonb := null;
begin
  t := v -> 'totales';
  if (v ->> 'version')::int <> 1 or (v ->> 'ventana_convertidos_dias')::int <> 45 then
    raise exception 'M01a version/ventana incorrectas: %', v;
  end if;
  if (t ->> 'vivos')::int <> 10           -- L10 (convertido viejo) fuera por ventana
     or (t ->> 'abiertos')::int <> 8
     or (t ->> 'asignados')::int <> 7
     or (t ->> 'parkeados')::int <> 1
     or (t ->> 'convertidos')::int <> 1
     or (t ->> 'descartados')::int <> 1
     or (t ->> 'asignados_pen')::int <> 7
     or (t ->> 'asignados_usd')::int <> 0 then
    raise exception 'M01b totales incorrectos: %', t;
  end if;
  if (v -> 'capital' -> 'asignado' ->> 'pen')::numeric <> 127000
     or (v -> 'capital' -> 'asignado' ->> 'usd')::numeric <> 0
     or (v -> 'capital' -> 'parkeado' ->> 'pen')::numeric <> 128000
     or (v -> 'capital' -> 'ganado' ->> 'pen')::numeric <> 0
     or (v -> 'capital' -> 'ganado' ->> 'usd')::numeric <> 5000 then
    raise exception 'M01c capital incorrecto (PEN y USD jamas se suman): %', v -> 'capital';
  end if;
  if (v -> 'conversion' ->> 'base')::int <> 9
     or (v -> 'conversion' ->> 'convertidos')::int <> 1
     or (v -> 'conversion' ->> 'pct')::int <> 11 then
    raise exception 'M01d conversion incorrecta: %', v -> 'conversion';
  end if;
  if (select string_agg((e ->> 'etapa') || ':' || (e ->> 'n'), ',')
        from jsonb_array_elements(v -> 'embudo') e)
     <> 'nuevo:3,contactado:4,reunion_agendada:0,propuesta_enviada:1,convertido:1,descartado:1' then
    raise exception 'M01e embudo incorrecto: %', v -> 'embudo';
  end if;
  if (v -> 'descartes' ->> 'total')::int <> 1
     or (v -> 'descartes' ->> 'sin_motivo')::int <> 0
     or (v -> 'descartes' -> 'por_motivo' -> 0 ->> 'motivo') <> 'sin_interes' then
    raise exception 'M01f descartes incorrectos: %', v -> 'descartes';
  end if;
  if (v ->> 'sin_tocar')::int <> 1 then  -- solo L1 (nadie lo contacto jamas)
    raise exception 'M01g sin_tocar incorrecto: %', v ->> 'sin_tocar';
  end if;
end;
$test$;

-- M02 — cola_accion_fn: la cascada completa, una rama por lead, orden
-- sev→dias desc, estancados solo L4, ultimo_contacto_en presente.
do $test$
declare
  v jsonb := crm.cola_accion_fn(100);
  buckets text;
begin
  if (v -> 'resumen' ->> 'total')::int <> 7 then
    raise exception 'M02a total incorrecto (L7 escudado por plan vigente debe quedar fuera): %', v -> 'resumen';
  end if;
  select string_agg((i ->> 'bucket'), ',' order by ord)
    into buckets
    from jsonb_array_elements(v -> 'items') with ordinality as x(i, ord);
  if buckets <> 'por_repartir,sin_avance,propuesta_sin_respuesta,sin_responder,insistir,seguimiento,plan_vencido' then
    raise exception 'M02b cascada/orden incorrectos: %', buckets;
  end if;
  if (v -> 'resumen' -> 'por_sev' ->> 'critica')::int <> 1
     or (v -> 'resumen' -> 'por_sev' ->> 'media')::int <> 4
     or (v -> 'resumen' -> 'por_sev' ->> 'baja')::int <> 2 then
    raise exception 'M02c severidades incorrectas: %', v -> 'resumen' -> 'por_sev';
  end if;
  -- L8 encabeza (critica); su lead embebido llega con nombre y sin vendedor.
  if (v -> 'items' -> 0 ->> 'lead_id') <> '7f100000-0000-4000-8000-000000000108'
     or (v -> 'items' -> 0 -> 'lead' ->> 'nombre_completo') <> 'ORACULO L8 PARKEADO'
     or (v -> 'items' -> 0 -> 'lead' ->> 'vendedor_id') is not null then
    raise exception 'M02d item por_repartir incorrecto: %', v -> 'items' -> 0;
  end if;
  -- sin_avance lleva la version de la politica sellada; insistir sus datos.
  if (v -> 'items' -> 1 -> 'datos_motivo' ->> 'etapa_politica_version')::int <> 7777 then
    raise exception 'M02e sin_avance sin version sellada: %', v -> 'items' -> 1;
  end if;
  if (v -> 'items' -> 4 -> 'datos_motivo' ->> 'hablo')::boolean is distinct from false
     or (v -> 'items' -> 4 ->> 'ultimo_contacto_en') is null then
    raise exception 'M02f insistir sin ingredientes: %', v -> 'items' -> 4;
  end if;
  -- plan_vencido rescata la tarea muerta MAS VIEJA con su titulo.
  if (v -> 'items' -> 6 -> 'datos_motivo' ->> 'tarea_titulo') <> 'ORACULO TAREA VENCIDA L6' then
    raise exception 'M02g plan_vencido sin su tarea: %', v -> 'items' -> 6;
  end if;
  -- Estancados: SOLO L4 (6 dias sin actividad, sin plan vigente); L7 escudado.
  if jsonb_array_length(v -> 'estancados' -> 'items') <> 1
     or (v -> 'estancados' -> 'items' -> 0 ->> 'lead_id') <> '7f100000-0000-4000-8000-000000000104' then
    raise exception 'M02h estancados incorrectos: %', v -> 'estancados';
  end if;
end;
$test$;

-- M03 — cola_accion_fn respeta p_limite sin mentir en el resumen.
do $test$
declare
  v jsonb := crm.cola_accion_fn(2);
begin
  if jsonb_array_length(v -> 'items') <> 2
     or (v -> 'resumen' ->> 'total')::int <> 7
     or (v -> 'items' -> 0 ->> 'bucket') <> 'por_repartir' then
    raise exception 'M03 p_limite rompe items o resumen: %', v;
  end if;
end;
$test$;

-- M04 — metricas_vendedores_fn: fila de V con la ventana aplicada, equipos de S.
do $test$
declare
  v jsonb := crm.metricas_vendedores_fn();
  fv jsonb;
  eq jsonb;
begin
  select i into fv from jsonb_array_elements(v -> 'vendedores') i
    where i ->> 'vendedor_id' = '7f100000-0000-4000-8000-000000000002';
  if fv is null
     or (fv ->> 'activos')::int <> 7
     or (fv ->> 'capital_pen')::numeric <> 127000
     or (fv ->> 'capital_usd')::numeric <> 0
     or (fv ->> 'convertidos')::int <> 1        -- L9 si, L10 fuera de ventana
     or (fv ->> 'conversion_pct')::int <> 11    -- round(100*1/9)
     or (fv ->> 'sin_tocar')::int <> 1
     or round((fv ->> 'dias_sin_actividad_max')::numeric) <> 10 then
    raise exception 'M04a fila del vendedor incorrecta: %', fv;
  end if;
  if jsonb_array_length(v -> 'equipos') <> 1 then
    raise exception 'M04b equipos debe tener solo a S: %', v -> 'equipos';
  end if;
  eq := v -> 'equipos' -> 0;
  if (eq ->> 'supervisor_id') <> '7f100000-0000-4000-8000-000000000001'
     or (eq ->> 'vendedores')::int <> 1
     or (eq ->> 'activos')::int <> 7
     or (eq ->> 'capital_pen')::numeric <> 127000
     or (eq ->> 'convertidos')::int <> 1
     or (eq ->> 'conversion_pct')::int <> 11
     or (eq ->> 'parkeados')::int <> 1 then
    raise exception 'M04c comparativa incorrecta: %', eq;
  end if;
end;
$test$;

-- M05 — series_comerciales_fn: SIN ventana (L10 cuenta), sumas por moneda
-- separadas, largo p_meses. Sumas sobre toda la serie para no depender del
-- dia del mes en que corra el oraculo.
do $test$
declare
  v jsonb := crm.series_comerciales_fn(6);
begin
  if jsonb_array_length(v -> 'meses') <> 6 then
    raise exception 'M05a largo de serie incorrecto: %', v -> 'meses';
  end if;
  if (select sum((x)::text::int) from jsonb_array_elements(v -> 'nuevos') x) <> 11
     or (select sum((x)::text::int) from jsonb_array_elements(v -> 'cierres') x) <> 2
     or (select sum((x)::text::int) from jsonb_array_elements(v -> 'cohorte_clientes') x) <> 2
     or (select sum((x)::text::numeric) from jsonb_array_elements(v -> 'capital_pen') x) <> 7000
     or (select sum((x)::text::numeric) from jsonb_array_elements(v -> 'capital_usd') x) <> 5000 then
    raise exception 'M05b sumas de la serie incorrectas (la ventana de 45d NO aplica aqui): %', v;
  end if;
end;
$test$;

-- M06 — parámetros inválidos → 22023 (tras la guardia).
do $test$
begin
  begin
    perform crm.cola_accion_fn(0);
    raise exception 'M06a cola acepto p_limite=0';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.cola_accion_fn(501);
    raise exception 'M06b cola acepto p_limite=501';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.series_comerciales_fn(0);
    raise exception 'M06c series acepto p_meses=0';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.series_comerciales_fn(25);
    raise exception 'M06d series acepto p_meses=25';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.cola_accion_fn(null);
    raise exception 'M06e cola acepto p_limite=null';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.series_comerciales_fn(null);
    raise exception 'M06f series acepto p_meses=null';
  exception when sqlstate '22023' then null;
  end;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- M07 — el VENDEDOR V ve solo lo suyo: sin parkeados, sin equipos, sin bandeja.
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $test$
declare
  r jsonb := crm.resumen_cartera_fn();
  c jsonb := crm.cola_accion_fn(100);
  m jsonb := crm.metricas_vendedores_fn();
begin
  if (r -> 'totales' ->> 'parkeados')::int <> 0
     or (r -> 'totales' ->> 'vivos')::int <> 9        -- sus 10 menos L10 (ventana)
     or (r -> 'capital' -> 'parkeado' ->> 'pen')::numeric <> 0 then
    raise exception 'M07a vendedor ve parkeados ajenos: %', r -> 'totales';
  end if;
  if (c -> 'resumen' -> 'por_bucket' ->> 'por_repartir') is not null then
    raise exception 'M07b vendedor recibio por_repartir: %', c -> 'resumen';
  end if;
  if jsonb_array_length(m -> 'vendedores') <> 1
     or jsonb_array_length(m -> 'equipos') <> 0 then
    raise exception 'M07c vendedor debe tener solo su fila y cero equipos: %', m;
  end if;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- M08 — autenticado AJENO al CRM (perfil portal sin fila en crm.equipo): 42501
-- en las 4, ANTES de validar parámetros.
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000003', true);
set local role authenticated;

do $test$
begin
  begin
    perform crm.resumen_cartera_fn();
    raise exception 'M08a ajeno obtuvo resumen';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.cola_accion_fn(0);  -- guardia ANTES que 22023
    raise exception 'M08b ajeno obtuvo cola';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_vendedores_fn();
    raise exception 'M08c ajeno obtuvo vendedores';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.series_comerciales_fn(0);
    raise exception 'M08d ajeno obtuvo series';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- M09 — ACL de catálogo: tríada por función + prosecdef + search_path=''.
-- El revoke a service_role es lo que un copy-paste incompleto rompe en silencio.
-- ═════════════════════════════════════════════════════════════════════════════
do $test$
declare
  fn text;
begin
  foreach fn in array array[
    'crm.resumen_cartera_fn()',
    'crm.cola_accion_fn(integer)',
    'crm.metricas_vendedores_fn()',
    'crm.series_comerciales_fn(integer)'
  ] loop
    if not has_function_privilege('authenticated', fn, 'execute')
       or has_function_privilege('anon', fn, 'execute')
       or has_function_privilege('service_role', fn, 'execute') then
      raise exception 'M09a ACL incorrecta en %', fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname in ('resumen_cartera_fn', 'cola_accion_fn',
                           'metricas_vendedores_fn', 'series_comerciales_fn')
         and p.prosecdef
         and p.proconfig @> array['search_path=""']
         and p.provolatile = 's') <> 4 then
    raise exception 'M09b prosecdef/search_path/stable incompletos en las 4 RPC';
  end if;
end;
$test$;

-- ═════════════════════════════════════════════════════════════════════════════
-- M10 — resumen_tareas_fn como S: stats con DOS criterios de vencida, la
-- vencida más antigua por lead y sin_accion ordenado por capital.
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $test$
declare
  v jsonb := crm.resumen_tareas_fn();
begin
  if (v ->> 'version')::int <> 1 then
    raise exception 'M10a version incorrecta: %', v;
  end if;
  -- T406 (L6 tarea -3d), T407 (L7 tarea +1d), T3 (L3 llamada -26h).
  if (v -> 'pendientes' ->> 'total')::int <> 3
     or (v -> 'pendientes' -> 'por_tipo' ->> 'tarea')::int <> 2
     or (v -> 'pendientes' -> 'por_tipo' ->> 'llamada')::int <> 1
     or (v -> 'pendientes' -> 'por_tipo' ->> 'whatsapp')::int <> 0
     or (v -> 'pendientes' -> 'por_tipo' ->> 'reunion')::int <> 0
     or (v -> 'pendientes' ->> 'de_cliente')::int <> 0 then
    raise exception 'M10b pendientes incorrectos: %', v -> 'pendientes';
  end if;
  -- 26 h > 24 h: T3 venció AYER en Lima siempre → ambos criterios dan 2.
  if (v -> 'pendientes' ->> 'vencidas_hora')::int <> 2
     or (v -> 'pendientes' ->> 'vencidas_dia')::int <> 2 then
    raise exception 'M10c criterios de vencida incorrectos: %', v -> 'pendientes';
  end if;
  -- La más antigua encabeza (L6, 72 h, critica); L3 (26 h) también critica.
  if (v -> 'vencidas' ->> 'leads_total')::int <> 2
     or (v -> 'vencidas' ->> 'leads_criticos')::int <> 2
     or (v -> 'vencidas' -> 'items' -> 0 ->> 'lead_id') <> '7f100000-0000-4000-8000-000000000106'
     or round((v -> 'vencidas' -> 'items' -> 0 ->> 'horas')::numeric) <> 72
     or (v -> 'vencidas' -> 'items' -> 0 ->> 'titulo') <> 'ORACULO TAREA VENCIDA L6'
     or (v -> 'vencidas' -> 'items' -> 0 ->> 'vendedor_id') <> '7f100000-0000-4000-8000-000000000002'
     or (v -> 'vencidas' -> 'items' -> 1 ->> 'lead_id') <> '7f100000-0000-4000-8000-000000000103'
     or round((v -> 'vencidas' -> 'items' -> 1 ->> 'horas')::numeric) <> 26 then
    raise exception 'M10d vencidas incorrectas: %', v -> 'vencidas';
  end if;
  -- sin_accion: L1, L2, L4, L5 (L3/L6/L7 tienen pendiente; L8 sin dueño).
  -- Orden espejo de sinProximaAccion: PEN primero, monto desc → L5 encabeza.
  if (v -> 'sin_accion' ->> 'total')::int <> 4
     or jsonb_array_length(v -> 'sin_accion' -> 'por_vendedor') <> 1
     or (v -> 'sin_accion' -> 'por_vendedor' -> 0 ->> 'vendedor_id') <> '7f100000-0000-4000-8000-000000000002'
     or (v -> 'sin_accion' -> 'por_vendedor' -> 0 ->> 'n')::int <> 4
     or (v -> 'sin_accion' -> 'items' -> 0 ->> 'lead_id') <> '7f100000-0000-4000-8000-000000000105'
     or (v -> 'sin_accion' -> 'items' -> 3 ->> 'lead_id') <> '7f100000-0000-4000-8000-000000000101' then
    raise exception 'M10e sin_accion incorrecto: %', v -> 'sin_accion';
  end if;
end;
$test$;

-- M11 — resumen_cartera_clientes_fn como S: capital solo de la cartera EN
-- GESTIÓN, alarma sobre TODOS (incluida la baja), sin_asesor INVISIBLE para S.
do $test$
declare
  v jsonb := crm.resumen_cartera_clientes_fn();
begin
  if (v ->> 'version')::int <> 1 or (v ->> 'dias_alarma_renovacion')::int <> 30 then
    raise exception 'M11a version/alarma incorrectas: %', v;
  end if;
  -- C en gestión, CB de baja; CS (sin asesor) NO existe para S.
  if (v -> 'clientes' ->> 'en_gestion')::int <> 1
     or (v -> 'clientes' ->> 'de_baja')::int <> 1
     or (v -> 'clientes' ->> 'con_capital')::int <> 1
     or (v -> 'clientes' ->> 'sin_asesor')::int <> 0 then
    raise exception 'M11b clientes incorrectos (sin_asesor debe ser 0 para S): %', v -> 'clientes';
  end if;
  -- K1 (3000 PEN) + K2 (1500 USD); K4 es de la baja → fuera del capital.
  if (v -> 'capital_activo' ->> 'pen')::numeric <> 3000
     or (v -> 'capital_activo' ->> 'usd')::numeric <> 1500 then
    raise exception 'M11c capital incorrecto (PEN y USD jamas se suman): %', v -> 'capital_activo';
  end if;
  -- K1/K2/K4 activos + K3 vencido (K5 pertenece a CS, invisible para S).
  if (v -> 'contratos' -> 'por_estado' ->> 'activo')::int <> 3
     or (v -> 'contratos' -> 'por_estado' ->> 'vencido')::int <> 1
     or (v -> 'contratos' ->> 'por_vencer_30')::int <> 2
     or (v -> 'contratos' ->> 'por_vencer_30_de_baja')::int <> 1 then
    raise exception 'M11d contratos/alarma incorrectos: %', v -> 'contratos';
  end if;
end;
$test$;

-- M12a — resumen_reparto_fn: el SUPERVISOR no opera el reparto → 42501.
do $test$
begin
  begin
    perform crm.resumen_reparto_fn();
    raise exception 'M12a supervisor obtuvo el resumen de reparto';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

-- M12b — el VENDEDOR tampoco.
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $test$
begin
  begin
    perform crm.resumen_reparto_fn();
    raise exception 'M12b vendedor obtuvo el resumen de reparto';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- M13 — el COORDINADOR CO: resumen_reparto_fn con la aritmética de la cola
-- global, la rama de parkeados en resumen/series, y TODO lo demás vacío.
-- Esperados desde los GUC `oraculo.*` (calculados como postgres).
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000004', true);
set local role authenticated;

do $test$
declare
  r jsonb := crm.resumen_reparto_fn();
  c jsonb := crm.resumen_cartera_fn();
  q jsonb := crm.cola_accion_fn(100);
  m jsonb := crm.metricas_vendedores_fn();
  s jsonb := crm.series_comerciales_fn(6);
  t jsonb := crm.resumen_tareas_fn();
  k jsonb := crm.resumen_cartera_clientes_fn();
begin
  -- Reparto: espejo EXACTO de la cola global (G3 no_contactar JAMÁS cuenta).
  if (r -> 'cola' ->> 'total')::int <> current_setting('oraculo.reparto_total')::int
     or (r -> 'cola' -> 'capital' ->> 'pen')::numeric <> current_setting('oraculo.reparto_pen')::numeric
     or (r -> 'cola' -> 'capital' ->> 'usd')::numeric <> current_setting('oraculo.reparto_usd')::numeric
     or (r -> 'cola' ->> 'espera_max_dias')::int <> current_setting('oraculo.reparto_espera')::int
     or (r -> 'cola' ->> 'posible_credito')::int <> current_setting('oraculo.reparto_credito')::int then
    raise exception 'M13a resumen_reparto no cuadra con la cola global: % vs GUCs %/%/%/%/%',
      r -> 'cola', current_setting('oraculo.reparto_total'), current_setting('oraculo.reparto_pen'),
      current_setting('oraculo.reparto_usd'), current_setting('oraculo.reparto_espera'),
      current_setting('oraculo.reparto_credito');
  end if;
  if current_setting('oraculo.reparto_espera')::int < 3 then
    raise exception 'M13b la espera del oraculo deberia incluir los 3 dias de G1';
  end if;
  -- Cartera: la rama de reparto le da TODOS los sin-dueño… y nada más.
  if (c -> 'totales' ->> 'parkeados')::int <> current_setting('oraculo.park_n')::int
     or (c -> 'totales' ->> 'asignados')::int <> 0
     or (c -> 'capital' -> 'parkeado' ->> 'pen')::numeric <> current_setting('oraculo.park_pen')::numeric
     or (c -> 'capital' -> 'asignado' ->> 'pen')::numeric <> 0
     or (c ->> 'sin_tocar')::int <> 0
     or (c -> 'conversion' ->> 'base')::int <> 0 then
    raise exception 'M13c cartera del coordinador incorrecta: %', c;
  end if;
  -- La cola de acción sigue VACÍA (premisa C1: sus items llevan PII).
  if (q -> 'resumen' ->> 'total')::int <> 0 or jsonb_array_length(q -> 'items') <> 0 then
    raise exception 'M13d el coordinador recibio items de cola_accion: %', q -> 'resumen';
  end if;
  -- Vendedores/equipos vacíos (roster ∅; la rama habría sido código muerto).
  if jsonb_array_length(m -> 'vendedores') <> 0 or jsonb_array_length(m -> 'equipos') <> 0 then
    raise exception 'M13e metricas_vendedores del coordinador no vacias: %', m;
  end if;
  -- Series: solo las altas de los sin-dueño.
  if (select sum((x)::text::int) from jsonb_array_elements(s -> 'nuevos') x)
       <> current_setting('oraculo.series_nuevos')::int
     or (select sum((x)::text::int) from jsonb_array_elements(s -> 'cierres') x) <> 0 then
    raise exception 'M13f series del coordinador incorrectas: %', s;
  end if;
  -- Tareas y cartera de clientes: ∅ por diseño.
  if (t -> 'pendientes' ->> 'total')::int <> 0
     or (t -> 'vencidas' ->> 'leads_total')::int <> 0
     or (t -> 'sin_accion' ->> 'total')::int <> 0 then
    raise exception 'M13g resumen_tareas del coordinador no vacio: %', t;
  end if;
  if (k -> 'clientes' ->> 'en_gestion')::int <> 0
     or (k -> 'clientes' ->> 'de_baja')::int <> 0
     or (k -> 'capital_activo' ->> 'pen')::numeric <> 0 then
    raise exception 'M13h cartera de clientes del coordinador no vacia: %', k;
  end if;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- M14 — autenticado AJENO al CRM: 42501 en las 3 nuevas.
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f100000-0000-4000-8000-000000000003', true);
set local role authenticated;

do $test$
begin
  begin
    perform crm.resumen_tareas_fn();
    raise exception 'M14a ajeno obtuvo resumen_tareas';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.resumen_cartera_clientes_fn();
    raise exception 'M14b ajeno obtuvo resumen_cartera_clientes';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.resumen_reparto_fn();
    raise exception 'M14c ajeno obtuvo resumen_reparto';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- M15 — ACL/definer/stable de la tanda 2 + las 2 reemplazadas que no cubría
-- M09. actividades_del_ambito_fn conserva su search_path legacy as-built, por
-- eso la verificación de search_path='' la excluye a propósito.
-- ═════════════════════════════════════════════════════════════════════════════
do $test$
declare
  fn text;
begin
  foreach fn in array array[
    'crm.resumen_tareas_fn()',
    'crm.resumen_cartera_clientes_fn()',
    'crm.resumen_reparto_fn()',
    'crm.estado_sla_leads_fn()',
    'crm.actividades_del_ambito_fn()'
  ] loop
    if not has_function_privilege('authenticated', fn, 'execute')
       or has_function_privilege('anon', fn, 'execute')
       or has_function_privilege('service_role', fn, 'execute') then
      raise exception 'M15a ACL incorrecta en %', fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname in ('resumen_tareas_fn', 'resumen_cartera_clientes_fn',
                           'resumen_reparto_fn', 'estado_sla_leads_fn')
         and p.prosecdef
         and p.proconfig @> array['search_path=""']
         and p.provolatile = 's') <> 4 then
    raise exception 'M15b prosecdef/search_path/stable incompletos en la tanda 2';
  end if;
  if (select count(*) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname = 'actividades_del_ambito_fn'
         and p.prosecdef and p.provolatile = 's') <> 1 then
    raise exception 'M15c actividades_del_ambito_fn perdio definer/stable';
  end if;
end;
$test$;

rollback;

select 'METRICAS_SERVIDOR_TX_OK' as resultado;
