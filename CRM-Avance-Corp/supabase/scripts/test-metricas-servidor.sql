-- Oráculo transaccional de F1 tanda 1 (20260809043802_crm_metricas_servidor_tanda1).
-- Éxito = token METRICAS_SERVIDOR_TX_OK; todo queda en rollback.
-- Cubre lo que la matriz .mjs NO puede con los fixtures del seed: la cascada
-- COMPLETA de buckets de cola_accion_fn (una rama por lead fabricado), la
-- ventana de convertidos de 45 días (resumen/vendedores la aplican, series NO),
-- la aritmética exacta de los agregados, los 22023 de parámetros, el 42501 de
-- un autenticado ajeno al CRM, y la tríada de ACL + prosecdef + search_path.
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

set local session_replication_role = origin;

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

rollback;

select 'METRICAS_SERVIDOR_TX_OK' as resultado;
