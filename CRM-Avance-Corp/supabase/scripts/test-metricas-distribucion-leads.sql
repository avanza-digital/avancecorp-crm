-- LEGACY / ORACULO HISTORICO PRE-20260807203757.
-- Conserva el contrato V2 original para reproducir su migracion, incluida la
-- medicion fija que ya no sale por el RPC publico. El gate vigente del contrato
-- saneado y del SLA versionado es `test-sla-versionado.sql`.
--
-- Oraculo transaccional autocontenido de la V2 de distribucion por capital.
-- Usa private.metricas_distribucion_leads_core con un reloj fijo y revierte
-- todos los fixtures. La RPC publica se prueba aparte bajo roles reales.

begin;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('15000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'metricas-a@test.invalid', now(), '{}', '{}', now(), now()),
  ('15000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'metricas-b@test.invalid', now(), '{}', '{}', now(), now()),
  ('15000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'metricas-s@test.invalid', now(), '{}', '{}', now(), now()),
  ('15000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'metricas-g@test.invalid', now(), '{}', '{}', now(), now()),
  ('15000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'metricas-d@test.invalid', now(), '{}', '{}', now(), now()),
  ('15000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'metricas-i@test.invalid', now(), '{}', '{}', now(), now()),
  ('15000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'metricas-sa@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('15000000-0000-4000-8000-000000000001', 'Metricas Analista A', 'metricas-a@test.invalid', 'comercial', true),
  ('15000000-0000-4000-8000-000000000002', 'Metricas Analista B', 'metricas-b@test.invalid', 'comercial', true),
  ('15000000-0000-4000-8000-000000000003', 'Metricas Supervisor', 'metricas-s@test.invalid', 'comercial', true),
  ('15000000-0000-4000-8000-000000000004', 'Metricas Gerencia', 'metricas-g@test.invalid', 'directorio', true),
  ('15000000-0000-4000-8000-000000000005', 'Metricas Directorio', 'metricas-d@test.invalid', 'directorio', true),
  ('15000000-0000-4000-8000-000000000006', 'Metricas Analista Inactivo', 'metricas-i@test.invalid', 'comercial', true),
  ('15000000-0000-4000-8000-000000000007', 'Metricas Superadmin Residual', 'metricas-sa@test.invalid', 'superadmin', true);

set local session_replication_role=replica;
insert into crm.equipo (
  perfil_id, rol_crm, supervisor_id, activo, capacidad_leads_objetivo
)
values
  ('15000000-0000-4000-8000-000000000003', 'supervisor', null, true, 2),
  ('15000000-0000-4000-8000-000000000001', 'vendedor', '15000000-0000-4000-8000-000000000003', true, 4),
  ('15000000-0000-4000-8000-000000000002', 'vendedor', '15000000-0000-4000-8000-000000000003', true, 3),
  ('15000000-0000-4000-8000-000000000004', 'gerencia', null, true, null),
  ('15000000-0000-4000-8000-000000000006', 'vendedor', '15000000-0000-4000-8000-000000000003', false, null),
  ('15000000-0000-4000-8000-000000000007', 'vendedor', '15000000-0000-4000-8000-000000000003', true, 8);
set local session_replication_role=origin;

-- Evita que los triggers creen episodios con statement_timestamp(): el oraculo
-- necesita ventanas exactas. CHECK, UNIQUE y EXCLUDE permanecen activos.
set local session_replication_role = replica;

-- Compatibilidad del fixture histórico con las columnas NOT NULL añadidas por
-- el SLA versionado. Los defaults viven solo dentro de esta transacción; el
-- core legacy no usa estos campos y los triggers están suspendidos a propósito.
alter table crm.lead_asignaciones
  alter column sla_politica_asignacion_id
    set default private.sla_politica_vigente(statement_timestamp()),
  alter column primera_gestion_limite_en set default statement_timestamp(),
  alter column primer_contacto_limite_en set default statement_timestamp();

insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, asignado_supervisor_id, activo,
  ciclo_actual, motivo_descarte, creado_por, creado_en,
  sla_global_iniciado_en, sla_global_aproximado
)
values
  -- A -> B. El monto actual fue recalificado, pero B conserva 5 000.01.
  ('25000000-0000-4000-8000-000000000001', 'Lead transferencia', '998500001', 'landing', 'nuevo', 100000, 'PEN', 'nuevo', '15000000-0000-4000-8000-000000000002', null, true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-02 09:00+00', '2026-05-02 09:00+00', false),
  -- Dos ciclos resueltos sobre el mismo lead: D y luego C.
  ('25000000-0000-4000-8000-000000000002', 'Lead reabierto', '998500002', 'landing', 'convertido', 20000.01, 'PEN', 'nuevo', '15000000-0000-4000-8000-000000000001', null, true, 2, null, '15000000-0000-4000-8000-000000000004', '2026-05-03 07:00+00', '2026-05-05 07:00+00', false),
  -- Cartera actual previa al periodo; el snapshot no sigue la recalificacion.
  ('25000000-0000-4000-8000-000000000003', 'Lead cartera anterior', '998500003', 'landing', 'contactado', 100000, 'PEN', 'nuevo', '15000000-0000-4000-8000-000000000001', null, true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-04-01 12:00+00', '2026-04-01 12:00+00', false),
  ('25000000-0000-4000-8000-000000000004', 'Lead sin tocar', '998500004', 'landing', 'nuevo', 1000.01, 'PEN', 'nuevo', '15000000-0000-4000-8000-000000000001', null, true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-16 17:00+00', '2026-05-16 17:00+00', false),
  ('25000000-0000-4000-8000-000000000005', 'Lead USD', '998500005', 'landing', 'propuesta_enviada', 5000, 'USD', 'nuevo', '15000000-0000-4000-8000-000000000002', null, true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-10 12:00+00', '2026-05-10 12:00+00', false),
  -- Por repartir: una cola global y dos en bandeja del supervisor.
  ('25000000-0000-4000-8000-000000000006', 'Cola global PEN', '998500006', 'landing', 'nuevo', 5000, 'PEN', 'nuevo', null, null, true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-16 10:00+00', '2026-05-16 10:00+00', false),
  ('25000000-0000-4000-8000-000000000007', 'Bandeja USD', '998500007', 'landing', 'nuevo', 10000, 'USD', 'nuevo', null, '15000000-0000-4000-8000-000000000003', true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-17 11:00+00', '2026-05-17 11:00+00', false),
  ('25000000-0000-4000-8000-000000000008', 'Bandeja PEN', '998500008', 'landing', 'nuevo', 100000.01, 'PEN', 'nuevo', null, '15000000-0000-4000-8000-000000000003', true, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-17 12:00+00', '2026-05-17 12:00+00', false),
  -- Historia visible de un analista que ya no puede recibir leads.
  ('25000000-0000-4000-8000-000000000009', 'Lead analista inactivo', '998500009', 'landing', 'nuevo', 5000, 'PEN', 'nuevo', null, null, false, 1, null, '15000000-0000-4000-8000-000000000004', '2026-05-07 10:00+00', '2026-05-07 10:00+00', false);

insert into crm.lead_asignaciones (
  lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
  asignado_en, asignado_por, supervisor_origen_id,
  monto_estimado, moneda, origen, categoria_interes,
  sla_global_iniciado_en, sla_global_aproximado,
  finalizado_en, finalizado_por, motivo_cierre,
  analista_destino_id, supervisor_destino_id,
  resultado, resultado_en, motivo_descarte_cierre
)
values
  ('25000000-0000-4000-8000-000000000001', 1, 1, '15000000-0000-4000-8000-000000000001', 'ingreso', '2026-05-02 10:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 1000, 'PEN', 'landing', 'nuevo', '2026-05-02 09:00+00', false, '2026-05-02 12:00+00', '15000000-0000-4000-8000-000000000004', 'transferido', '15000000-0000-4000-8000-000000000002', null, null, null, null),
  ('25000000-0000-4000-8000-000000000001', 1, 2, '15000000-0000-4000-8000-000000000002', 'reasignado', '2026-05-02 12:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 5000.01, 'PEN', 'landing', 'nuevo', '2026-05-02 09:00+00', false, null, null, null, null, null, null, null, null),

  ('25000000-0000-4000-8000-000000000002', 1, 1, '15000000-0000-4000-8000-000000000001', 'ingreso', '2026-05-03 08:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 10000, 'PEN', 'landing', 'nuevo', '2026-05-03 07:00+00', false, '2026-05-04 09:00+00', '15000000-0000-4000-8000-000000000001', 'descartado', null, null, 'descartado', '2026-05-04 09:00+00', 'sin_interes'),
  ('25000000-0000-4000-8000-000000000002', 2, 1, '15000000-0000-4000-8000-000000000001', 'reabierto', '2026-05-05 08:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 20000.01, 'PEN', 'landing', 'nuevo', '2026-05-05 07:00+00', false, '2026-05-06 10:00+00', '15000000-0000-4000-8000-000000000001', 'convertido', null, null, 'convertido', '2026-05-06 10:00+00', null),

  ('25000000-0000-4000-8000-000000000003', 1, 1, '15000000-0000-4000-8000-000000000001', 'ingreso', '2026-04-01 12:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 50000, 'PEN', 'landing', 'nuevo', '2026-04-01 12:00+00', false, null, null, null, null, null, null, null, null),
  ('25000000-0000-4000-8000-000000000004', 1, 1, '15000000-0000-4000-8000-000000000001', 'ingreso', '2026-05-16 17:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 1000.01, 'PEN', 'landing', 'nuevo', '2026-05-16 17:00+00', false, null, null, null, null, null, null, null, null),
  ('25000000-0000-4000-8000-000000000005', 1, 1, '15000000-0000-4000-8000-000000000002', 'ingreso', '2026-05-10 12:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 5000, 'USD', 'landing', 'nuevo', '2026-05-10 12:00+00', false, null, null, null, null, null, null, null, null),
  ('25000000-0000-4000-8000-000000000009', 1, 1, '15000000-0000-4000-8000-000000000006', 'ingreso', '2026-05-07 10:00+00', '15000000-0000-4000-8000-000000000004', '15000000-0000-4000-8000-000000000003', 5000, 'PEN', 'landing', 'nuevo', '2026-05-07 10:00+00', false, '2026-05-07 11:00+00', '15000000-0000-4000-8000-000000000004', 'desactivado', null, null, null, null, null);

insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
values
  -- Exactamente en el cierre de A: no acredita ni a A ni a B.
  ('25000000-0000-4000-8000-000000000001', 'llamada_realizada', 'frontera cierre', '15000000-0000-4000-8000-000000000001', '2026-05-02 12:00+00'),
  -- Exactamente +24 h para B: evaluable y cumple.
  ('25000000-0000-4000-8000-000000000001', 'whatsapp_enviado', 'frontera SLA', '15000000-0000-4000-8000-000000000002', '2026-05-03 12:00+00'),
  -- +24 h + 1 segundo: contacto tardio; entra en mediana, falla SLA.
  ('25000000-0000-4000-8000-000000000002', 'llamada_realizada', 'tardio', '15000000-0000-4000-8000-000000000001', '2026-05-06 08:00:01+00'),
  -- Mantiene fresca la cartera antigua.
  ('25000000-0000-4000-8000-000000000003', 'whatsapp_recibido', 'seguimiento', '15000000-0000-4000-8000-000000000001', '2026-05-17 22:00+00'),
  -- Una nota no cuenta como contacto ni reinicia estancamiento.
  ('25000000-0000-4000-8000-000000000004', 'nota', 'nota administrativa', '15000000-0000-4000-8000-000000000001', '2026-05-17 22:30+00'),
  ('25000000-0000-4000-8000-000000000005', 'reunion_realizada', 'contacto USD', '15000000-0000-4000-8000-000000000002', '2026-05-10 14:00+00');

set local session_replication_role = origin;

-- Fronteras exactas del clasificador PEN.
do $test$
declare
  v_actual text[];
  v_esperado text[] := array[
    'sin_monto', 'sin_monto',
    'pen_0_1000', 'pen_0_1000',
    'pen_1000_5000', 'pen_1000_5000',
    'pen_5000_10000', 'pen_5000_10000',
    'pen_10000_20000', 'pen_10000_20000',
    'pen_20000_50000', 'pen_20000_50000',
    'pen_50000_100000', 'pen_50000_100000',
    'pen_mas_100000', 'pen_mas_100000'
  ];
begin
  select array_agg(private.rango_capital_pen(monto) order by ord)
    into v_actual
  from unnest(array[
    null::numeric, 0, 0.01, 1000, 1000.01, 5000, 5000.01, 10000,
    10000.01, 20000, 20000.01, 50000, 50000.01, 100000,
    100000.01, 9999999999.99
  ]) with ordinality as t(monto, ord);

  if v_actual is distinct from v_esperado then
    raise exception 'M01 rangos incorrectos: %', v_actual;
  end if;
end;
$test$;

do $test$
declare
  v jsonb;
  a jsonb;
  b jsonb;
  i jsonb;
  r jsonb;
begin
  v := private.metricas_distribucion_leads_v2_core(
    date '2026-05-01', date '2026-05-17', timestamptz '2026-05-17 18:00:00-05'
  );

  if v->>'version' <> '2'
     or jsonb_array_length(v->'rangos') <> 8
     or v#>>'{cohorte,desde_inclusivo}' <> '2026-05-01'
     or v#>>'{cohorte,hasta_exclusivo}' <> '2026-05-18'
     or v#>>'{cohorte,zona_horaria}' <> 'America/Lima'
     or v#>>'{cohorte,criterio_sla_global}' <> 'ciclo_sla_global_iniciado_en'
     or v#>>'{cohorte,politica_pausas}' <> 'SIN_DESCUENTO' then
    raise exception 'M02 contrato/periodo invalido: %', v->'cohorte';
  end if;

  select value into a from jsonb_array_elements(v->'analistas')
  where value->>'analista_id' = '15000000-0000-4000-8000-000000000001';
  select value into b from jsonb_array_elements(v->'analistas')
  where value->>'analista_id' = '15000000-0000-4000-8000-000000000002';
  select value into i from jsonb_array_elements(v->'analistas')
  where value->>'analista_id' = '15000000-0000-4000-8000-000000000006';

  if a is null or b is null or i is null then
    raise exception 'M03 faltan analistas activos/inactivo con historia';
  end if;

  if (a#>>'{capacidad,objetivo}')::int <> 4
     or (a#>>'{capacidad,carga_activa}')::int <> 2
     or (a#>>'{capacidad,carga_pen}')::int <> 2
     or (a#>>'{capacidad,carga_usd}')::int <> 0
     or (a#>>'{pen,cartera_actual,episodios}')::int <> 2
     or (a#>>'{pen,cartera_actual,capital}')::numeric <> 51000.01 then
    raise exception 'M04 cartera/capacidad A incorrecta: %', a->'capacidad';
  end if;

  if (a#>>'{pen,cohorte,episodios_recibidos}')::int <> 4
     or (a#>>'{pen,cohorte,leads_unicos_recibidos}')::int <> 3
     or (a#>>'{pen,cohorte,convertidos}')::int <> 1
     or (a#>>'{pen,cohorte,descartados}')::int <> 1
     or (a#>>'{pen,cohorte,ciclos_resueltos}')::int <> 2
     or (a#>>'{pen,cohorte,leads_unicos_resueltos}')::int <> 1 then
    raise exception 'M05 reapertura/atribucion A incorrecta: %', a#>'{pen,cohorte}';
  end if;

  if (a#>>'{operacion,cohorte_episodios}')::int <> 4
     or (a#>>'{operacion,contactos_asignacion}')::int <> 1
     or (a#>>'{operacion,sla_asignacion_evaluables}')::int <> 3
     or (a#>>'{operacion,sla_asignacion_en_24h}')::int <> 0
     or (a#>>'{operacion,transferidos}')::int <> 1
     or (a#>>'{operacion,sin_tocar_actual}')::int <> 1
     or (a#>>'{operacion,estancados_actual}')::int <> 1 then
    raise exception 'M06 operacion A incorrecta: %', a->'operacion';
  end if;

  if (b#>>'{capacidad,carga_activa}')::int <> 2
     or (b#>>'{capacidad,carga_pen}')::int <> 1
     or (b#>>'{capacidad,carga_usd}')::int <> 1
     or (b#>>'{pen,cartera_actual,capital}')::numeric <> 5000.01
     or (b#>>'{usd_no_segmentado,cartera_actual_capital}')::numeric <> 5000
     or (b#>>'{operacion,sla_asignacion_evaluables}')::int <> 2
     or (b#>>'{operacion,sla_asignacion_en_24h}')::int <> 2
     or (b#>>'{operacion,primer_contacto_asignacion_mediana_minutos}')::numeric <> 780 then
    raise exception 'M07 cartera/SLA B incorrectos: %', b;
  end if;

  if i->>'activo' <> 'false'
     or i->>'disponible_para_recibir' <> 'false'
     or (i#>>'{operacion,desactivados}')::int <> 1 then
    raise exception 'M08 inactivo historico incorrecto: %', i;
  end if;

  select value into r from jsonb_array_elements(b#>'{pen,rangos}')
  where value->>'rango_id' = 'pen_5000_10000';
  if (r#>>'{cartera_actual,episodios}')::int <> 1
     or (r#>>'{cartera_actual,capital}')::numeric <> 5000.01 then
    raise exception 'M09 la recalificacion movio el snapshot de B: %', r;
  end if;

  if (v#>>'{por_repartir,total,carga_total}')::int <> 3
     or (v#>>'{por_repartir,total,pen,cantidad}')::int <> 2
     or (v#>>'{por_repartir,total,pen,capital}')::numeric <> 105000.01
     or (v#>>'{por_repartir,total,usd,cantidad}')::int <> 1
     or (v#>>'{por_repartir,total,usd,capital}')::numeric <> 10000
     or (v#>>'{por_repartir,global,carga_total}')::int <> 1
     or jsonb_array_length(v#>'{por_repartir,bandejas}') <> 1 then
    raise exception 'M10 colas incorrectas: %', v->'por_repartir';
  end if;

  if (v#>>'{resumen,leads_operativos_actuales}')::int <> 7
     or (v#>>'{resumen,asignados_actuales}')::int <> 4
     or (v#>>'{resumen,por_repartir_actuales}')::int <> 3
     or (v#>>'{resumen,cohorte_episodios}')::int <> 7
     or (v#>>'{resumen,cohorte_leads_unicos}')::int <> 5
     or (v#>>'{resumen,convertidos_pen}')::int <> 1
     or (v#>>'{resumen,descartados_pen}')::int <> 1
     or (v#>>'{resumen,sla_global_ciclos_cohorte}')::int <> 9
     or (v#>>'{resumen,sla_global_leads_unicos_cohorte}')::int <> 8
     or (v#>>'{resumen,sla_global_contactos}')::int <> 3
     or (v#>>'{resumen,sla_global_evaluables}')::int <> 6
     or (v#>>'{resumen,sla_global_en_24h}')::int <> 2
     or (v#>>'{resumen,primer_contacto_global_mediana_minutos}')::numeric <> 180
     or (v#>>'{resumen,sla_global_sin_contacto_vencidos_actuales}')::int <> 2
     or (v#>>'{resumen,reasignaciones_cohorte}')::int <> 1 then
    raise exception 'M11 conciliacion global incorrecta: %', v->'resumen';
  end if;

  if (v#>>'{calidad,episodios_aproximados_actuales}')::int <> 0
     or (v#>>'{calidad,episodios_sin_monto_actuales}')::int <> 0
     or (v#>>'{calidad,ciclos_sla_global_aproximados_cohorte}')::int <> 0
     or (
       select sum((x#>>'{cartera_actual,episodios}')::int)
       from jsonb_array_elements(a#>'{pen,rangos}') x
     ) <> (a#>>'{pen,cartera_actual,episodios}')::int then
    raise exception 'M12 calidad/invariante de rangos incorrecta';
  end if;
end;
$test$;

-- Gerencia activa y lector global pueden ejecutar el wrapper.
select set_config('request.jwt.claim.sub', '15000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
declare v jsonb; v_agenda jsonb; v_conversiones jsonb;
begin
  v:=crm.metricas_distribucion_leads_v2_fn(date '2026-05-01', date '2026-05-17');
  v_agenda:=crm.metricas_agenda_fn(date '2026-05-01', date '2026-05-17');
  v_conversiones:=crm.metricas_conversiones_fn(date '2026-05-01', date '2026-05-17');
  if v->>'version' <> '2' then
    raise exception 'M13 Gerencia no pudo ejecutar V2';
  end if;
  if not exists(
    select 1 from jsonb_array_elements(v->'analistas') a
    where a.value->>'analista_id'='15000000-0000-4000-8000-000000000007'
      and (a.value->>'activo')::boolean is false
      and (a.value->>'disponible_para_recibir')::boolean is false
  ) then
    raise exception 'M13a Superadmin residual quedo activo/disponible';
  end if;
  if exists(select 1 from jsonb_array_elements(v_agenda->'vendedores') a
       where a.value->>'vendedor_id'='15000000-0000-4000-8000-000000000007')
     or exists(select 1 from jsonb_array_elements(v_conversiones->'responsables') a
       where a.value->>'vendedor_id'='15000000-0000-4000-8000-000000000007') then
    raise exception 'M13c Superadmin residual reaparecio en metricas antiguas';
  end if;
  begin
    perform * from crm.actualizar_capacidad_leads_objetivo(
      '15000000-0000-4000-8000-000000000007',10
    );
    raise exception 'M13d Gerencia configuro capacidad a destino residual';
  exception when no_data_found then null;
  end;
  if crm.metricas_distribucion_leads_fn(date '2026-05-01', date '2026-05-17')->>'version' <> '1' then
    raise exception 'M13b Gerencia perdio el endpoint V1 de rollback';
  end if;
  begin
    perform crm.metricas_distribucion_leads_v2_fn(date '2025-01-01', date '2026-05-17');
    raise exception 'M14 acepto periodo mayor a 366 dias';
  exception when invalid_parameter_value then null;
  end;
end;
$test$;
reset role;

-- La misma membresía residual tampoco recupera autoridad usando el endpoint.
select set_config('request.jwt.claim.sub', '15000000-0000-4000-8000-000000000007', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.metricas_distribucion_leads_v2_fn(date '2026-05-01', date '2026-05-17');
    raise exception 'M16b Superadmin residual consulto metricas gerenciales';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_agenda_fn(date '2026-05-01', date '2026-05-17');
    raise exception 'M16d Superadmin residual consulto agenda gerencial';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_conversiones_fn(date '2026-05-01', date '2026-05-17');
    raise exception 'M16e Superadmin residual consulto conversiones';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_reuniones_fn(date '2026-05-01', date '2026-05-17');
    raise exception 'M16f Superadmin residual consulto reuniones';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.actualizar_capacidad_leads_objetivo(
      '15000000-0000-4000-8000-000000000001',10
    );
    raise exception 'M16g Superadmin residual configuro capacidad';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- El RPC server-to-server devuelve solo destinos efectivos; Edge no consulta
-- public.perfiles/crm.equipo ni reconstruye esta autorización.
set local role service_role;
do $test$
begin
  if (select count(*) from crm.destinos_importacion_por_correo_fn(array[
       'metricas-a@test.invalid','metricas-sa@test.invalid'
     ]))<>1
     or not exists(select 1 from crm.destinos_importacion_por_correo_fn(array[
       'METRICAS-A@TEST.INVALID','METRICAS-SA@TEST.INVALID'
     ]) where perfil_id='15000000-0000-4000-8000-000000000001') then
    raise exception 'M16c importador resolvio destino sin rol efectivo';
  end if;
end;
$test$;
reset role;

select set_config('request.jwt.claim.sub', '15000000-0000-4000-8000-000000000005', true);
set local role authenticated;
do $test$
begin
  if crm.metricas_distribucion_leads_v2_fn(date '2026-05-01', date '2026-05-17')->>'version' <> '2' then
    raise exception 'M15 lector global no pudo ejecutar';
  end if;
end;
$test$;
reset role;

-- Un analista autenticado tiene GRANT al endpoint, pero el gate lo rechaza.
select set_config('request.jwt.claim.sub', '15000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.metricas_distribucion_leads_v2_fn(date '2026-05-01', date '2026-05-17');
    raise exception 'M16 analista consulto metricas gerenciales';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

do $test$
begin
  if has_function_privilege('anon', 'crm.metricas_distribucion_leads_fn(date,date)', 'EXECUTE') then
    raise exception 'M17 anon tiene EXECUTE';
  end if;
  if has_function_privilege(
    'authenticated','crm.destinos_importacion_por_correo_fn(text[])','EXECUTE'
  ) or not has_function_privilege(
    'service_role','crm.destinos_importacion_por_correo_fn(text[])','EXECUTE'
  ) then
    raise exception 'M17c ACL del resolver de importacion incorrecta';
  end if;
  if has_function_privilege('anon', 'crm.metricas_distribucion_leads_v2_fn(date,date)', 'EXECUTE') then
    raise exception 'M17b anon tiene EXECUTE V2';
  end if;
  if has_function_privilege('authenticated', 'private.metricas_distribucion_leads_core(date,date,timestamp with time zone)', 'EXECUTE') then
    raise exception 'M18 authenticated puede saltar el wrapper';
  end if;
  if has_table_privilege('authenticated', 'crm.lead_asignaciones', 'SELECT') then
    raise exception 'M19 authenticated puede leer el ledger';
  end if;
  if has_table_privilege('crm_metricas_bridge', 'crm.lead_asignaciones', 'SELECT') then
    raise exception 'M20 el puente tiene acceso directo al ledger';
  end if;
  if has_function_privilege(
    'authenticated',
    'private.metricas_distribucion_leads_autorizada(date,date,smallint)',
    'EXECUTE'
  ) then
    raise exception 'M21 authenticated puede saltar el puente';
  end if;
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles r on r.oid = p.proowner
    where n.nspname = 'crm'
      and p.proname in ('metricas_distribucion_leads_fn', 'metricas_distribucion_leads_v2_fn')
      and r.rolname = 'crm_metricas_bridge'
    group by r.rolname
    having count(*) = 2
  ) then
    raise exception 'M22 las RPC expuestas no pertenecen al puente restringido';
  end if;
  if exists (
    select 1
    from pg_roles
    where rolname = 'crm_metricas_bridge'
      and (rolcanlogin or rolsuper or rolbypassrls or rolcreaterole or rolcreatedb)
  ) then
    raise exception 'M23 el puente conserva atributos privilegiados';
  end if;
end;
$test$;

select jsonb_build_object(
  'resultado', 'METRICAS_DISTRIBUCION_TX_OK',
  'analistas_fixture', 5,
  'episodios_cohorte', 7,
  'leads_por_repartir', 3
) as validacion;

rollback;
