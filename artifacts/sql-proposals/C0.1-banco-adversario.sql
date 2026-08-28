-- Banco adversario propuesto para C0.1.
--
-- NO PRODUCCION. Requiere una base DESECHABLE cuyo nombre empiece por
-- `crm_c01_`, esquema completo hasta F2.6 (y, tras integrar main, F1.3b
-- 20260827220132) y la propuesta C0.1 ya aplicada en una sesion anterior. Todo
-- este archivo corre dentro de una transaccion y termina en ROLLBACK, pero la
-- barrera por nombre sigue siendo obligatoria.
--
-- Este artefacto NO vive aun en supabase/scripts y NO debe ejecutarse contra
-- ninguna base compartida. El procedimiento de runner esta en
-- C0.1-banco-runner-plan.md.

\set ON_ERROR_STOP on

begin;

do $safety$
begin
  if pg_catalog.current_database() !~ '^crm_c01_[a-z0-9_]+$' then
    raise exception
      'BANCO C0.1 SOLO DESECHABLE: base % no cumple crm_c01_*',
      pg_catalog.current_database();
  end if;
  if current_user <> 'postgres' then
    raise exception 'BANCO C0.1 requiere postgres local para fixture aislado';
  end if;
  if pg_catalog.to_regprocedure('crm.metricas_vendedores_fn()') is null
     or pg_catalog.to_regprocedure('crm.conversion_mensual_fn(date)') is null
     or pg_catalog.to_regclass('crm.ajustes_mes_cerrado') is null
     or pg_catalog.to_regclass('crm.operaciones_cartera') is null
     or pg_catalog.to_regclass('crm.sla_politicas') is null then
    raise exception 'BANCO C0.1: esquema completo/propuesta no disponibles';
  end if;
end
$safety$;

set local session_replication_role = replica;

-- Reloj unico del fixture: siempre el mes Lima vigente que consulta la RPC.
create temporary table c01_clock on commit drop as
select
  date_trunc('month', now() at time zone 'America/Lima')::date as mes,
  date_trunc('month', now() at time zone 'America/Lima')::date
    ::timestamp at time zone 'America/Lima' as ini;

-- Actores: gerencia, S1..S4, vendedores A/B/F/G/C/D, E fuera de roster,
-- coordinador, Directorio CRM, Directorio solo Portal, Admin/Superadmin solo
-- Portal y un actor CRM inactivo. Clientes C1..C4 alimentan cartera.
insert into public.perfiles(
  id, nombre_completo, correo, rol, activo
) values
  ('c0100000-0000-4000-8000-000000000001', 'C01 GERENCIA', 'c01-g@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000101', 'C01 S1', 'c01-s1@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000102', 'C01 S2', 'c01-s2@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000103', 'C01 S3', 'c01-s3@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000104', 'C01 S4', 'c01-s4@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000201', 'C01 A', 'c01-a@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000202', 'C01 B', 'c01-b@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000203', 'C01 F', 'c01-f@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000204', 'C01 C', 'c01-c@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000205', 'C01 D', 'c01-d@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000206', 'C01 E FUERA ROSTER', 'c01-e@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000207', 'C01 G SIN ACTIVIDAD', 'c01-g0@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000301', 'C01 COORD', 'c01-co@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000302', 'C01 DIRECTORIO', 'c01-dir@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000303', 'C01 INACTIVO', 'c01-off@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000304', 'C01 DIRECTORIO PORTAL', 'c01-dir-portal@test.invalid', 'directorio', true),
  ('c0100000-0000-4000-8000-000000000305', 'C01 ADMIN PORTAL', 'c01-admin@test.invalid', 'admin', true),
  ('c0100000-0000-4000-8000-000000000306', 'C01 SUPERADMIN PORTAL', 'c01-superadmin@test.invalid', 'superadmin', true),
  ('c0100000-0000-4000-8000-000000000401', 'C01 CLIENTE 1', 'c01-cl1@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000402', 'C01 CLIENTE 2', 'c01-cl2@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000403', 'C01 CLIENTE 3', 'c01-cl3@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000404', 'C01 CLIENTE 4', 'c01-cl4@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000405', 'C01 CLIENTE 5', 'c01-cl5@test.invalid', 'cliente', true);

insert into crm.equipo(
  perfil_id, rol_crm, supervisor_id, activo
) values
  ('c0100000-0000-4000-8000-000000000001', 'gerencia', null, true),
  ('c0100000-0000-4000-8000-000000000101', 'supervisor', null, true),
  ('c0100000-0000-4000-8000-000000000102', 'supervisor', null, true),
  ('c0100000-0000-4000-8000-000000000103', 'supervisor', null, true),
  ('c0100000-0000-4000-8000-000000000104', 'supervisor', null, true),
  ('c0100000-0000-4000-8000-000000000201', 'vendedor', 'c0100000-0000-4000-8000-000000000101', true),
  ('c0100000-0000-4000-8000-000000000202', 'vendedor', 'c0100000-0000-4000-8000-000000000101', true),
  ('c0100000-0000-4000-8000-000000000203', 'vendedor', 'c0100000-0000-4000-8000-000000000101', true),
  ('c0100000-0000-4000-8000-000000000204', 'vendedor', 'c0100000-0000-4000-8000-000000000102', true),
  ('c0100000-0000-4000-8000-000000000205', 'vendedor', 'c0100000-0000-4000-8000-000000000103', true),
  ('c0100000-0000-4000-8000-000000000206', 'vendedor', null, true),
  ('c0100000-0000-4000-8000-000000000207', 'vendedor', 'c0100000-0000-4000-8000-000000000101', true),
  -- Un directo activo no-vendedor de S1 conserva el alcance operativo legacy
  -- (conteo, activos y capital), pero nunca entra al roster de conversion.
  ('c0100000-0000-4000-8000-000000000301', 'coordinador', 'c0100000-0000-4000-8000-000000000101', true),
  ('c0100000-0000-4000-8000-000000000302', 'directorio', null, true),
  ('c0100000-0000-4000-8000-000000000303', 'vendedor', 'c0100000-0000-4000-8000-000000000101', false);

-- Fijar 0,15 solo dentro de la transaccion del banco.
insert into crm.conversion_pesos(vigente_desde, peso_referido)
select mes, 0.15 from c01_clock
on conflict (vigente_desde)
do update set peso_referido = excluded.peso_referido;

-- Leads del nucleo. A-L1 queda actualmente bajo C para probar que el cierre
-- sigue acreditado al ledger de A, no al propietario actual.
insert into crm.leads(
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, creado_por, creado_en, convertido_en, activo
)
select
  x.id, x.nombre, x.telefono, x.origen, x.etapa, 1000, 'PEN',
  x.vendedor_id, 'c0100000-0000-4000-8000-000000000001'::uuid,
  c.ini + x.alta, case when x.etapa = 'convertido' then c.ini + x.cierre end,
  true
from c01_clock c
cross join (values
  ('c0110000-0000-4000-8000-000000000001'::uuid, 'C01 A NOREF REASIGNADO', '51980001001', 'campania', 'convertido', 'c0100000-0000-4000-8000-000000000204'::uuid, interval '0 day', interval '2 days'),
  ('c0110000-0000-4000-8000-000000000002'::uuid, 'C01 A REFERIDO', '51980001002', 'referido', 'convertido', 'c0100000-0000-4000-8000-000000000201'::uuid, interval '1 day', interval '3 days'),
  ('c0110000-0000-4000-8000-000000000003'::uuid, 'C01 B ABIERTO 1', '51980001003', 'campania', 'contactado', 'c0100000-0000-4000-8000-000000000202'::uuid, interval '1 day', null),
  ('c0110000-0000-4000-8000-000000000004'::uuid, 'C01 B ABIERTO 2', '51980001004', 'campania', 'contactado', 'c0100000-0000-4000-8000-000000000202'::uuid, interval '2 days', null),
  ('c0110000-0000-4000-8000-000000000005'::uuid, 'C01 C NOREF', '51980001005', 'campania', 'convertido', 'c0100000-0000-4000-8000-000000000204'::uuid, interval '1 day', interval '2 days'),
  ('c0110000-0000-4000-8000-000000000006'::uuid, 'C01 E FUERA', '51980001006', 'campania', 'convertido', 'c0100000-0000-4000-8000-000000000206'::uuid, interval '1 day', interval '2 days'),
  ('c0110000-0000-4000-8000-000000000009'::uuid, 'C01 COORD ABIERTO', '51980001009', 'campania', 'contactado', 'c0100000-0000-4000-8000-000000000301'::uuid, interval '2 days', null)
) as x(id,nombre,telefono,origen,etapa,vendedor_id,alta,cierre);

-- Leads antiguos que anclan los dos ajustes pendientes. No generan episodios
-- del mes vivo.
insert into crm.leads(
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, creado_por, creado_en, convertido_en, activo
)
select
  x.id, x.nombre, x.telefono, 'campania', 'convertido', 1000, 'PEN',
  x.vendedor_id, 'c0100000-0000-4000-8000-000000000001'::uuid,
  c.ini - interval '90 days', c.ini - interval '80 days', true
from c01_clock c
cross join (values
  ('c0110000-0000-4000-8000-000000000007'::uuid, 'C01 AJUSTE A', '51980001007', 'c0100000-0000-4000-8000-000000000201'::uuid),
  ('c0110000-0000-4000-8000-000000000008'::uuid, 'C01 AJUSTE F', '51980001008', 'c0100000-0000-4000-8000-000000000203'::uuid)
) as x(id,nombre,telefono,vendedor_id);

insert into crm.lead_asignaciones(
  id, lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
  asignado_en, monto_estimado, moneda, origen,
  finalizado_en, motivo_cierre, resultado, resultado_en,
  sla_global_iniciado_en, sla_global_aproximado,
  sla_politica_asignacion_id,
  primera_gestion_limite_en, primer_contacto_limite_en
)
select
  x.id, x.lead_id, 1, 1, x.analista_id, 'ingreso',
  c.ini + x.alta, 1000, 'PEN', x.origen,
  case when x.cierra then c.ini + x.cierre end,
  case when x.cierra then 'convertido' end,
  case when x.cierra then 'convertido' end,
  case when x.cierra then c.ini + x.cierre end,
  c.ini + x.alta, false, p.id,
  c.ini + x.alta
    + p.primera_gestion_minutos * interval '1 minute',
  c.ini + x.alta
    + p.primer_contacto_minutos * interval '1 minute'
from c01_clock c
cross join (values
  ('c0120000-0000-4000-8000-000000000001'::uuid, 'c0110000-0000-4000-8000-000000000001'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'campania', interval '0 day', true, interval '2 days'),
  ('c0120000-0000-4000-8000-000000000002'::uuid, 'c0110000-0000-4000-8000-000000000002'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'referido', interval '1 day', true, interval '3 days'),
  ('c0120000-0000-4000-8000-000000000003'::uuid, 'c0110000-0000-4000-8000-000000000003'::uuid, 'c0100000-0000-4000-8000-000000000202'::uuid, 'campania', interval '1 day', false, null),
  ('c0120000-0000-4000-8000-000000000004'::uuid, 'c0110000-0000-4000-8000-000000000004'::uuid, 'c0100000-0000-4000-8000-000000000202'::uuid, 'campania', interval '2 days', false, null),
  ('c0120000-0000-4000-8000-000000000005'::uuid, 'c0110000-0000-4000-8000-000000000005'::uuid, 'c0100000-0000-4000-8000-000000000204'::uuid, 'campania', interval '1 day', true, interval '2 days'),
  ('c0120000-0000-4000-8000-000000000006'::uuid, 'c0110000-0000-4000-8000-000000000006'::uuid, 'c0100000-0000-4000-8000-000000000206'::uuid, 'campania', interval '1 day', true, interval '2 days')
) as x(id,lead_id,analista_id,origen,alta,cierra,cierre)
cross join lateral (
  select
    sp.id,
    sp.primera_gestion_minutos,
    sp.primer_contacto_minutos
  from crm.sla_politicas sp
  where sp.vigente_desde <= c.ini + x.alta
  order by sp.vigente_desde desc, sp.version desc
  limit 1
) p;

-- Cartera: A tiene renovacion + upgrade elegibles del MISMO cliente/mes y
-- debe contar solo la renovacion, que ocurrio primero. C tiene una renovacion
-- USD y un upgrade PEN de clientes distintos. D aporta una renovacion legacy
-- sin desglose; E, un upgrade fuera de roster. Asi los tres conteos y las
-- siete magnitudes economicas tienen oraculos no vacuos sin alterar 38,33/300/
-- NULL ni la identidad global ya cubierta por este banco.
insert into crm.operaciones_cartera(
  id, cliente_id, vendedor_id, tipo, contrato_origen_id,
  contrato_nuevo_id, fecha_operacion, periodo, moneda,
  capital_renovado, capital_adicional, elegible_conversion,
  desglose_completo, fuente, creado_por, creado_en
)
select
  x.id, x.cliente_id, x.vendedor_id, x.tipo, x.contrato_origen_id,
  x.contrato_id, c.mes + 3, c.mes, x.moneda,
  x.capital_renovado, x.capital_adicional, true,
  x.desglose_completo, x.fuente,
  'c0100000-0000-4000-8000-000000000001'::uuid,
  c.ini + x.creado
from c01_clock c
cross join (values
  ('c0130000-0000-4000-8000-000000000001'::uuid, 'c0100000-0000-4000-8000-000000000401'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'renovacion', 'c0130000-0000-4000-8000-000000000201'::uuid, 'c0130000-0000-4000-8000-000000000101'::uuid, 'PEN', 800::numeric, 200::numeric, true, 'flujo_cartera', interval '3 days 1 hour'),
  ('c0130000-0000-4000-8000-000000000002'::uuid, 'c0100000-0000-4000-8000-000000000401'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'upgrade', null::uuid, 'c0130000-0000-4000-8000-000000000102'::uuid, 'PEN', null::numeric, null::numeric, true, 'flujo_cartera', interval '3 days 2 hours'),
  ('c0130000-0000-4000-8000-000000000003'::uuid, 'c0100000-0000-4000-8000-000000000402'::uuid, 'c0100000-0000-4000-8000-000000000204'::uuid, 'renovacion', 'c0130000-0000-4000-8000-000000000203'::uuid, 'c0130000-0000-4000-8000-000000000103'::uuid, 'USD', 1200::numeric, 300::numeric, true, 'flujo_cartera', interval '3 days 1 hour'),
  ('c0130000-0000-4000-8000-000000000004'::uuid, 'c0100000-0000-4000-8000-000000000403'::uuid, 'c0100000-0000-4000-8000-000000000204'::uuid, 'upgrade', null::uuid, 'c0130000-0000-4000-8000-000000000104'::uuid, 'PEN', null::numeric, null::numeric, true, 'flujo_cartera', interval '3 days 2 hours'),
  ('c0130000-0000-4000-8000-000000000005'::uuid, 'c0100000-0000-4000-8000-000000000404'::uuid, 'c0100000-0000-4000-8000-000000000205'::uuid, 'renovacion', null::uuid, 'c0130000-0000-4000-8000-000000000105'::uuid, 'USD', null::numeric, null::numeric, false, 'backfill_agosto_2026', interval '3 days 1 hour'),
  -- E esta fuera del roster, pero su operacion sigue entrando al total global
  -- anonimo. Prueba que cartera no desaparezca por no tener fila publicable.
  ('c0130000-0000-4000-8000-000000000006'::uuid, 'c0100000-0000-4000-8000-000000000405'::uuid, 'c0100000-0000-4000-8000-000000000206'::uuid, 'upgrade', null::uuid, 'c0130000-0000-4000-8000-000000000106'::uuid, 'PEN', null::numeric, null::numeric, true, 'flujo_cartera', interval '3 days 1 hour')
) as x(
  id, cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_id,
  moneda, capital_renovado, capital_adicional, desglose_completo, fuente,
  creado
);

-- Dos deudas de 1. A absorbe una desde bruto 2,15 y queda en 1,15. F no
-- produjo: su neto queda en cero. Sumar bruto y restar ambas deudas al final
-- daria 0,15 para S1; sumar netos por vendedor debe dar 1,15.
insert into crm.ajustes_mes_cerrado(
  id, vendedor_id, periodo_origen, lead_id, motivo, creado_por,
  numerador, capital_pen, capital_usd, detalle,
  pendiente_numerador, pendiente_pen, pendiente_usd,
  pendiente_detalle, saldado_en
)
select
  x.id, x.vendedor_id, (c.mes - interval '1 month')::date,
  x.lead_id, 'fixture C0.1',
  'c0100000-0000-4000-8000-000000000001'::uuid,
  1, 0, 0, '[]'::jsonb, 1, 0, 0, '[]'::jsonb, null
from c01_clock c
cross join (values
  ('c0140000-0000-4000-8000-000000000001'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'c0110000-0000-4000-8000-000000000007'::uuid),
  ('c0140000-0000-4000-8000-000000000002'::uuid, 'c0100000-0000-4000-8000-000000000203'::uuid, 'c0110000-0000-4000-8000-000000000008'::uuid)
) as x(id,vendedor_id,lead_id);

set local session_replication_role = origin;

-- Oraculo fijo de cartera. No se calcula desde la funcion bajo prueba: nace
-- directamente del fixture de seis operaciones y permite contrastar por
-- separado el helper privado y la RPC publica.
create temporary table c01_cartera_esperada (
  vendedor_id uuid primary key,
  conversiones_clientes integer not null,
  conversiones_renovacion integer not null,
  conversiones_upgrade integer not null,
  operaciones_renovacion integer not null,
  operaciones_upgrade integer not null,
  capital_renovado_pen numeric not null,
  capital_renovado_usd numeric not null,
  capital_adicional_pen numeric not null,
  capital_adicional_usd numeric not null,
  renovaciones_sin_desglose integer not null
) on commit drop;

insert into c01_cartera_esperada values
  ('c0100000-0000-4000-8000-000000000201', 1, 1, 0, 1, 1, 800, 0, 200, 0, 0),
  ('c0100000-0000-4000-8000-000000000204', 2, 1, 1, 1, 1, 0, 1200, 0, 300, 0),
  ('c0100000-0000-4000-8000-000000000205', 1, 1, 0, 1, 0, 0, 0, 0, 0, 1),
  ('c0100000-0000-4000-8000-000000000206', 1, 0, 1, 0, 1, 0, 0, 0, 0, 0);

-- El segundo contraste corre como el consumidor real `authenticated`. El
-- permiso existe solo sobre esta tabla temporal y desaparece con el ROLLBACK.
grant select on c01_cartera_esperada to authenticated;

do $cartera_privada$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_total record;
  v_mismatch integer;
begin
  if (select count(*) from crm.operaciones_cartera o
      where o.periodo = v_mes and o.tipo = 'renovacion')
       is distinct from 3::bigint then
    raise exception 'C01-CARTERA fixture sin tres renovaciones adversarias';
  end if;

  select
    coalesce(sum(m.conversiones_clientes), 0)::integer
      as conversiones_clientes,
    coalesce(sum(m.conversiones_renovacion), 0)::integer
      as conversiones_renovacion,
    coalesce(sum(m.conversiones_upgrade), 0)::integer
      as conversiones_upgrade,
    coalesce(sum(m.operaciones_renovacion), 0)::integer
      as operaciones_renovacion,
    coalesce(sum(m.operaciones_upgrade), 0)::integer
      as operaciones_upgrade,
    coalesce(sum(m.capital_renovado_pen), 0) as capital_renovado_pen,
    coalesce(sum(m.capital_renovado_usd), 0) as capital_renovado_usd,
    coalesce(sum(m.capital_adicional_pen), 0) as capital_adicional_pen,
    coalesce(sum(m.capital_adicional_usd), 0) as capital_adicional_usd,
    coalesce(sum(m.renovaciones_sin_desglose), 0)::integer
      as renovaciones_sin_desglose
  into v_total
  from private.metricas_cartera_por_vendedor(v_mes) m;

  if v_total.conversiones_clientes is distinct from 5
     or v_total.conversiones_renovacion is distinct from 3
     or v_total.conversiones_upgrade is distinct from 2
     or v_total.operaciones_renovacion is distinct from 3
     or v_total.operaciones_upgrade is distinct from 3
     or v_total.capital_renovado_pen is distinct from 800::numeric
     or v_total.capital_renovado_usd is distinct from 1200::numeric
     or v_total.capital_adicional_pen is distinct from 200::numeric
     or v_total.capital_adicional_usd is distinct from 300::numeric
     or v_total.renovaciones_sin_desglose is distinct from 1 then
    raise exception
      'C01-CARTERA helper altero conteos/economia preservada: %',
      pg_catalog.row_to_json(v_total);
  end if;

  with actual as materialized (
    select * from private.metricas_cartera_por_vendedor(v_mes)
  )
  select count(*) into v_mismatch
  from c01_cartera_esperada e
  full join actual m using (vendedor_id)
  where e.vendedor_id is null
     or m.vendedor_id is null
     or row(
       m.conversiones_clientes,
       m.conversiones_renovacion,
       m.conversiones_upgrade,
       m.operaciones_renovacion,
       m.operaciones_upgrade,
       m.capital_renovado_pen,
       m.capital_renovado_usd,
       m.capital_adicional_pen,
       m.capital_adicional_usd,
       m.renovaciones_sin_desglose
     ) is distinct from row(
       e.conversiones_clientes,
       e.conversiones_renovacion,
       e.conversiones_upgrade,
       e.operaciones_renovacion,
       e.operaciones_upgrade,
       e.capital_renovado_pen,
       e.capital_renovado_usd,
       e.capital_adicional_pen,
       e.capital_adicional_usd,
       e.renovaciones_sin_desglose
     );

  if v_mismatch <> 0 then
    raise exception
      'C01-CARTERA helper no coincide con oraculo por vendedor: % diferencias',
      v_mismatch;
  end if;
end
$cartera_privada$;

-- Adaptador test-only del wrapper. El nombre real se restaura por ROLLBACK.
-- Mantener este banco en una sesion distinta de la que aplico la propuesta
-- evita reutilizar un plan PL/pgSQL que apunte al OID previo al rename.
alter function crm.conversion_mensual_fn(date)
  rename to conversion_mensual_c01_real_fn;

create function crm.conversion_mensual_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $mutator$
declare
  v jsonb := crm.conversion_mensual_c01_real_fn(p_periodo);
  v_mode text := coalesce(
    nullif(pg_catalog.current_setting('c01.mutante', true), ''),
    'ninguno'
  );
  v_a jsonb;
  v_rows jsonb;
begin
  if v_mode = 'ninguno' then
    return v;
  end if;

  -- Mutantes de cobertura/total. Los siete primeros son estados de datos
  -- declarados y deben degradar sin 55000; los restantes son contrato corrupto
  -- y deben fallar cerrados. `doble_redondeo` es la excepcion: un caso valido
  -- calibrado para distinguir porcentaje servido de una nueva division legacy.
  case v_mode
    when 'mes_parcial' then
      return pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(
          v, '{cobertura,medible}', 'false'::jsonb, false
        ),
        '{cobertura,motivo_no_medible}', '"mes_parcial"'::jsonb, false
      );
    when 'sin_ledger' then
      return pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(
          v, '{cobertura,medible}', 'false'::jsonb, false
        ),
        '{cobertura,motivo_no_medible}', '"sin_ledger"'::jsonb, false
      );
    when 'anterior_al_ledger' then
      return pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(
          v, '{cobertura,medible}', 'false'::jsonb, false
        ),
        '{cobertura,motivo_no_medible}', '"anterior_al_ledger"'::jsonb, false
      );
    when 'sin_supervisor' then
      return pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(
          v, '{cobertura,medible}', 'false'::jsonb, false
        ),
        '{cobertura,motivo_no_medible}', '"sin_supervisor"'::jsonb, false
      );
    when 'supervisor_inactivo' then
      return pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(
          v, '{cobertura,medible}', 'false'::jsonb, false
        ),
        '{cobertura,motivo_no_medible}', '"supervisor_inactivo"'::jsonb, false
      );
    when 'supervisor_no_es_supervisor' then
      return pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(
          v, '{cobertura,medible}', 'false'::jsonb, false
        ),
        '{cobertura,motivo_no_medible}',
        '"supervisor_no_es_supervisor"'::jsonb,
        false
      );
    when 'cierres_sin_episodio' then
      return pg_catalog.jsonb_set(
        v, '{cobertura,cierres_sin_episodio}', '1'::jsonb, false
      );
    when 'cobertura_ausente' then
      return v - 'cobertura';
    when 'cobertura_tipo' then
      return pg_catalog.jsonb_set(v, '{cobertura}', '[]'::jsonb, false);
    when 'divisor_por_motivo_tipo' then
      return pg_catalog.jsonb_set(
        v, '{cobertura,divisor_por_motivo}', '[]'::jsonb, false
      );
    when 'sonda_negativa' then
      return pg_catalog.jsonb_set(
        v, '{cobertura,cierres_sin_episodio}', '-1'::jsonb, false
      );
    when 'sonda_fraccional' then
      return pg_catalog.jsonb_set(
        v, '{cobertura,cierres_sin_episodio}', '0.5'::jsonb, false
      );
    when 'motivo_incoherente' then
      return pg_catalog.jsonb_set(
        v, '{cobertura,motivo_no_medible}', '"mes_parcial"'::jsonb, false
      );
    when 'total_ausente' then
      return v - 'total';
    when 'total_incoherente' then
      return pg_catalog.jsonb_set(
        v, '{total,conversion_pct}', '999'::jsonb, false
      );
    when 'doble_redondeo' then
      -- S1 pasa de 1,15/3 a 1,1549/3. El porcentaje exacto es 38,4966...:
      -- el nucleo sirve 38,50 y el legacy debe redondear ESE valor a 39. Una
      -- division nueva desde numerador/divisor produciria 38 y queda expuesta.
      select pg_catalog.jsonb_agg(
        case when e.value ->> 'vendedor_id' =
          'c0100000-0000-4000-8000-000000000201'
        then e.value || pg_catalog.jsonb_build_object(
          'numerador', 1.1549::numeric,
          'conversion_pct', 115.49::numeric
        ) else e.value end
        order by e.ord
      ) into v_rows
      from pg_catalog.jsonb_array_elements(v -> 'responsables')
           with ordinality e(value, ord);

      v := pg_catalog.jsonb_set(
        v, '{responsables}', v_rows, false
      );
      v := pg_catalog.jsonb_set(
        v,
        '{total,numerador}',
        pg_catalog.to_jsonb(
          (v #>> '{total,numerador}')::numeric + 0.0049::numeric
        ),
        false
      );
      return pg_catalog.jsonb_set(
        v,
        '{total,conversion_pct}',
        pg_catalog.to_jsonb(round(
          100.0 * (v #>> '{total,numerador}')::numeric
          / (v #>> '{total,divisor}')::numeric,
          2
        )),
        false
      );
    else
      null;
  end case;

  select e.value into v_a
  from pg_catalog.jsonb_array_elements(v -> 'responsables') e(value)
  where e.value ->> 'vendedor_id' =
    'c0100000-0000-4000-8000-000000000201';

  if v_mode <> 'alcance' and v_a is null then
    raise exception 'BANCO C0.1 vacuo: A no esta en responsables';
  end if;

  case v_mode
    when 'duplicado' then
      v_rows := (v -> 'responsables') || pg_catalog.jsonb_build_array(v_a);
    when 'duplicado_case' then
      -- El UUID es la identidad, no su representacion textual. Una guarda que
      -- agrupara solo el texto crudo dejaria pasar esta segunda fila.
      v_rows := (v -> 'responsables') || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_set(
          v_a,
          '{vendedor_id}',
          pg_catalog.to_jsonb(
            pg_catalog.upper(v_a ->> 'vendedor_id')
          ),
          false
        )
      );
    when 'parcial' then
      select pg_catalog.jsonb_agg(
        case when e.value ->> 'vendedor_id' =
          'c0100000-0000-4000-8000-000000000201'
        then e.value - 'cartera' else e.value end
        order by e.ord
      ) into v_rows
      from pg_catalog.jsonb_array_elements(v -> 'responsables')
           with ordinality e(value, ord);
    when 'faltante' then
      select coalesce(pg_catalog.jsonb_agg(e.value order by e.ord), '[]'::jsonb)
        into v_rows
      from pg_catalog.jsonb_array_elements(v -> 'responsables')
           with ordinality e(value, ord)
      where e.value ->> 'vendedor_id' <>
        'c0100000-0000-4000-8000-000000000201';
    when 'supervisor' then
      select pg_catalog.jsonb_agg(
        case when e.value ->> 'vendedor_id' =
          'c0100000-0000-4000-8000-000000000201'
        then e.value || pg_catalog.jsonb_build_object(
          'supervisor_id', 'c0100000-0000-4000-8000-000000000102'
        ) else e.value end
        order by e.ord
      ) into v_rows
      from pg_catalog.jsonb_array_elements(v -> 'responsables')
           with ordinality e(value, ord);
    when 'extra_rol' then
      v_rows := (v -> 'responsables') || pg_catalog.jsonb_build_array(
        v_a || pg_catalog.jsonb_build_object(
          'vendedor_id', 'c0100000-0000-4000-8000-000000000104',
          'supervisor_id', 'c0100000-0000-4000-8000-000000000104'
        )
      );
    when 'extra_fuera' then
      v_rows := (v -> 'responsables') || pg_catalog.jsonb_build_array(
        v_a || pg_catalog.jsonb_build_object(
          'vendedor_id', 'c0100000-0000-4000-8000-000000000206',
          'supervisor_id', 'c0100000-0000-4000-8000-000000000101'
        )
      );
    when 'alcance' then
      return pg_catalog.jsonb_set(
        v, '{alcance}', '"propio"'::jsonb, true
      );
    else
      raise exception 'Mutante C0.1 desconocido: %', v_mode;
  end case;

  return pg_catalog.jsonb_set(v, '{responsables}', v_rows, true);
end
$mutator$;

revoke all on function crm.conversion_mensual_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_mensual_fn(date)
  to authenticated, service_role;

-- Gerencia: caso real y oraculo dinamico.
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'c0100000-0000-4000-8000-000000000001',
  true
);
select pg_catalog.set_config('c01.mutante', 'ninguno', true);
set local role authenticated;

do $cartera_rpc$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v jsonb := crm.metricas_cartera_fn(v_mes);
  v_mismatch integer;
begin
  if v ->> 'alcance' is distinct from 'global'
     or pg_catalog.jsonb_typeof(v -> 'total') is distinct from 'object'
     or pg_catalog.jsonb_typeof(v -> 'responsables') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v -> 'responsables') is distinct from 4
     or (v #>> '{total,conversiones_clientes}')::integer
       is distinct from 5
     or (v #>> '{total,conversiones_renovacion}')::integer
       is distinct from 3
     or (v #>> '{total,conversiones_upgrade}')::integer
       is distinct from 2
     or (v #>> '{total,operaciones_renovacion}')::integer
       is distinct from 3
     or (v #>> '{total,operaciones_upgrade}')::integer
       is distinct from 3
     or (v #>> '{total,capital_renovado_pen}')::numeric
       is distinct from 800::numeric
     or (v #>> '{total,capital_renovado_usd}')::numeric
       is distinct from 1200::numeric
     or (v #>> '{total,capital_adicional_pen}')::numeric
       is distinct from 200::numeric
     or (v #>> '{total,capital_adicional_usd}')::numeric
       is distinct from 300::numeric
     or (v #>> '{total,renovaciones_sin_desglose}')::integer
       is distinct from 1 then
    raise exception
      'C01-CARTERA RPC altero conteos/economia preservada: %', v;
  end if;

  with actual as (
    select
      (r.value ->> 'vendedor_id')::uuid as vendedor_id,
      (r.value ->> 'conversiones_clientes')::integer
        as conversiones_clientes,
      (r.value ->> 'conversiones_renovacion')::integer
        as conversiones_renovacion,
      (r.value ->> 'conversiones_upgrade')::integer
        as conversiones_upgrade,
      (r.value ->> 'operaciones_renovacion')::integer
        as operaciones_renovacion,
      (r.value ->> 'operaciones_upgrade')::integer as operaciones_upgrade,
      (r.value ->> 'capital_renovado_pen')::numeric as capital_renovado_pen,
      (r.value ->> 'capital_renovado_usd')::numeric as capital_renovado_usd,
      (r.value ->> 'capital_adicional_pen')::numeric as capital_adicional_pen,
      (r.value ->> 'capital_adicional_usd')::numeric as capital_adicional_usd,
      (r.value ->> 'renovaciones_sin_desglose')::integer
        as renovaciones_sin_desglose
    from pg_catalog.jsonb_array_elements(v -> 'responsables') r(value)
  )
  select count(*) into v_mismatch
  from c01_cartera_esperada e
  full join actual a using (vendedor_id)
  where e.vendedor_id is null
     or a.vendedor_id is null
     or row(
       a.conversiones_clientes,
       a.conversiones_renovacion,
       a.conversiones_upgrade,
       a.operaciones_renovacion,
       a.operaciones_upgrade,
       a.capital_renovado_pen,
       a.capital_renovado_usd,
       a.capital_adicional_pen,
       a.capital_adicional_usd,
       a.renovaciones_sin_desglose
     ) is distinct from row(
       e.conversiones_clientes,
       e.conversiones_renovacion,
       e.conversiones_upgrade,
       e.operaciones_renovacion,
       e.operaciones_upgrade,
       e.capital_renovado_pen,
       e.capital_renovado_usd,
       e.capital_adicional_pen,
       e.capital_adicional_usd,
       e.renovaciones_sin_desglose
     );

  if v_mismatch <> 0 then
    raise exception
      'C01-CARTERA RPC no coincide con oraculo por vendedor: % diferencias',
      v_mismatch;
  end if;
end
$cartera_rpc$;

do $baseline$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mensual jsonb := crm.conversion_mensual_fn(v_mes);
  v_metricas jsonb := crm.metricas_vendedores_fn();
  v_fila jsonb;
  v_mismatch int;
  v_avg_coalesce numeric;
  v_avg_sin_null numeric;
  v_por_conteo numeric;
  v_suma_equipos int;
  v_filas_divisor numeric;
  v_filas_numerador numeric;
  v_filas_cierres int;
  v_filas_cartera int;
begin
  if pg_catalog.jsonb_typeof(v_metricas -> 'equipos') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v_metricas -> 'equipos')
        is distinct from 4 then
    raise exception 'C01-BASE anti-vacuidad: no llegaron exactamente S1..S4';
  end if;

  if v_metricas -> 'cobertura_conversion'
       is distinct from v_mensual -> 'cobertura'
     or pg_catalog.jsonb_typeof(v_metricas -> 'nucleo_total')
        is distinct from 'object'
     or not ((v_metricas -> 'nucleo_total') ?& array[
       'nucleo_convertidos',
       'operaciones_cartera',
       'nucleo_divisor',
       'nucleo_numerador',
       'nucleo_conversion_pct'
     ]::text[])
     or (v_metricas #>> '{nucleo_total,nucleo_convertidos}')::int
        is distinct from (
          (v_mensual #>> '{total,cierres_no_referidos}')::int
          + (v_mensual #>> '{total,cierres_referidos}')::int
        )
     or (v_metricas #>> '{nucleo_total,operaciones_cartera}')::int
        is distinct from
          (v_mensual #>> '{total,cartera,conversiones_clientes}')::int
     or (v_metricas #>> '{nucleo_total,nucleo_divisor}')::numeric
        is distinct from (v_mensual #>> '{total,divisor}')::numeric
     or (v_metricas #>> '{nucleo_total,nucleo_numerador}')::numeric
        is distinct from (v_mensual #>> '{total,numerador}')::numeric
     or (v_metricas #>> '{nucleo_total,nucleo_conversion_pct}')::numeric
        is distinct from (v_mensual #>> '{total,conversion_pct}')::numeric then
    raise exception 'C01-BASE cobertura/total literal no coincide con wrapper';
  end if;

  select coalesce(sum((e.value ->> 'nucleo_convertidos')::int), 0)
    into v_suma_equipos
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where pg_catalog.jsonb_typeof(e.value -> 'nucleo_convertidos') = 'number';

  if v_suma_equipos >=
       (v_metricas #>> '{nucleo_total,nucleo_convertidos}')::int then
    raise exception
      'C01-BASE fuera-de-roster no quedo exclusivamente en el total (% vs %)',
      v_suma_equipos,
      v_metricas #>> '{nucleo_total,nucleo_convertidos}';
  end if;

  select
    coalesce(sum((e.value ->> 'divisor')::numeric), 0),
    coalesce(sum((e.value ->> 'numerador')::numeric), 0),
    coalesce(sum(
      (e.value ->> 'cierres_no_referidos')::int
      + (e.value ->> 'cierres_referidos')::int
    ), 0)::int,
    coalesce(sum(
      (e.value #>> '{cartera,conversiones_clientes}')::int
    ), 0)::int
  into
    v_filas_divisor,
    v_filas_numerador,
    v_filas_cierres,
    v_filas_cartera
  from pg_catalog.jsonb_array_elements(
    v_mensual -> 'responsables'
  ) e(value);

  -- La identidad global es filas publicables + agregado anonimo fuera de
  -- roster. La cartera de E agrega exactamente una operacion adicional y
  -- prueba que ese conteo tambien nace del nucleo aun sin fila visible.
  if (v_mensual #>> '{cobertura,fuera_de_roster,analistas}')::int
       is distinct from 1
     or (v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::numeric
       is distinct from 1
     or (v_mensual #>> '{cobertura,fuera_de_roster,cierres}')::int
       is distinct from 1
     or (v_mensual #>> '{cobertura,fuera_de_roster,numerador}')::numeric
       is distinct from 2
     or (v_mensual #>> '{total,divisor}')::numeric is distinct from
       v_filas_divisor
       + (v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::numeric
     or (
       (v_mensual #>> '{total,cierres_no_referidos}')::int
       + (v_mensual #>> '{total,cierres_referidos}')::int
     ) is distinct from
       v_filas_cierres
       + (v_mensual #>> '{cobertura,fuera_de_roster,cierres}')::int
     or (v_mensual #>> '{total,numerador}')::numeric is distinct from
       v_filas_numerador
       + (v_mensual #>> '{cobertura,fuera_de_roster,numerador}')::numeric
     or (v_mensual #>> '{total,cartera,conversiones_clientes}')::int
       is distinct from v_filas_cartera + 1 then
    raise exception
      'C01-BASE total no equivale a filas + fuera-de-roster: %',
      v_mensual;
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
    where e.value ->> 'supervisor_id' in (
      'c0100000-0000-4000-8000-000000000101',
      'c0100000-0000-4000-8000-000000000102',
      'c0100000-0000-4000-8000-000000000103',
      'c0100000-0000-4000-8000-000000000104'
    )
      and not (e.value ?& array[
        'nucleo_convertidos',
        'operaciones_cartera',
        'nucleo_divisor',
        'nucleo_numerador',
        'nucleo_conversion_pct'
      ]::text[])
  ) then
    raise exception 'C01-BASE fila exacta incompleta';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_metricas -> 'vendedores') e(value)
    where not (e.value ?& array[
      'nucleo_convertidos',
      'operaciones_cartera',
      'nucleo_divisor',
      'nucleo_numerador',
      'nucleo_conversion_pct'
    ]::text[])
  ) then
    raise exception 'C01-BASE fila de vendedor exacta incompleta';
  end if;

  -- Las cinco claves forman un solo bundle: o todas son NULL (fila operativa
  -- fuera del roster mensual), o las cuatro magnitudes son números coherentes
  -- y solo el porcentaje puede ser NULL cuando divisor=0.
  if exists (
    select 1
    from (
      select e.value
      from pg_catalog.jsonb_array_elements(v_metricas -> 'vendedores') e(value)
      union all
      select e.value
      from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
      union all
      select v_metricas -> 'nucleo_total'
    ) f
    where pg_catalog.jsonb_typeof(f.value) is distinct from 'object'
      or not coalesce(f.value ?& array[
        'nucleo_convertidos',
        'operaciones_cartera',
        'nucleo_divisor',
        'nucleo_numerador',
        'nucleo_conversion_pct'
      ]::text[], false)
      or not coalesce((
      (
        pg_catalog.jsonb_typeof(f.value -> 'nucleo_convertidos') = 'null'
        and pg_catalog.jsonb_typeof(f.value -> 'operaciones_cartera') = 'null'
        and pg_catalog.jsonb_typeof(f.value -> 'nucleo_divisor') = 'null'
        and pg_catalog.jsonb_typeof(f.value -> 'nucleo_numerador') = 'null'
        and pg_catalog.jsonb_typeof(f.value -> 'nucleo_conversion_pct') = 'null'
      )
      or (
        pg_catalog.jsonb_typeof(f.value -> 'nucleo_convertidos') = 'number'
        and pg_catalog.jsonb_typeof(f.value -> 'operaciones_cartera') = 'number'
        and pg_catalog.jsonb_typeof(f.value -> 'nucleo_divisor') = 'number'
        and pg_catalog.jsonb_typeof(f.value -> 'nucleo_numerador') = 'number'
        and (f.value ->> 'nucleo_convertidos')::numeric >= 0
        and (f.value ->> 'nucleo_convertidos')::numeric =
          trunc((f.value ->> 'nucleo_convertidos')::numeric)
        and (f.value ->> 'operaciones_cartera')::numeric >= 0
        and (f.value ->> 'operaciones_cartera')::numeric =
          trunc((f.value ->> 'operaciones_cartera')::numeric)
        and (f.value ->> 'nucleo_divisor')::numeric >= 0
        and (f.value ->> 'nucleo_divisor')::numeric =
          trunc((f.value ->> 'nucleo_divisor')::numeric)
        and (f.value ->> 'nucleo_numerador')::numeric >= 0
        and case
          when (f.value ->> 'nucleo_divisor')::numeric = 0 then
            pg_catalog.jsonb_typeof(f.value -> 'nucleo_conversion_pct') = 'null'
          else
            pg_catalog.jsonb_typeof(f.value -> 'nucleo_conversion_pct') = 'number'
            and (f.value ->> 'nucleo_conversion_pct')::numeric = round(
              100.0 * (f.value ->> 'nucleo_numerador')::numeric
              / (f.value ->> 'nucleo_divisor')::numeric,
              2
            )
        end
      )
    ), false)
  ) then
    raise exception 'C01-BASE bundle exacto parcial o incoherente';
  end if;

  -- Oraculo dinamico: responsabilidades canonicas agrupadas sobre todos los
  -- supervisores activos. S4 queda con ceros/NULL por LEFT JOIN.
  with canon as (
    select
      (r.value ->> 'supervisor_id')::uuid as supervisor_id,
      sum((r.value ->> 'divisor')::numeric) as divisor,
      sum((r.value ->> 'numerador')::numeric) as numerador,
      sum(
        (r.value ->> 'cierres_no_referidos')::int
        + (r.value ->> 'cierres_referidos')::int
      )::int as convertidos,
      sum(
        (r.value #>> '{cartera,conversiones_clientes}')::int
      )::int as operaciones
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) r(value)
    where r.value ->> 'supervisor_id' is not null
    group by 1
  ),
  supervisores as (
    select e.perfil_id as supervisor_id
    from crm.equipo e
    where e.rol_crm = 'supervisor' and e.activo
  ),
  esperado as (
    select
      s.supervisor_id,
      coalesce(c.divisor, 0::numeric) as divisor,
      coalesce(c.numerador, 0::numeric) as numerador,
      coalesce(c.convertidos, 0) as convertidos,
      coalesce(c.operaciones, 0) as operaciones,
      case when coalesce(c.divisor, 0) > 0
        then round(100.0 * c.numerador / c.divisor, 2) end as pct
    from supervisores s
    left join canon c using (supervisor_id)
  ),
  obtenido as (
    select
      (e.value ->> 'supervisor_id')::uuid as supervisor_id,
      (e.value ->> 'nucleo_divisor')::numeric as divisor,
      (e.value ->> 'nucleo_numerador')::numeric as numerador,
      (e.value ->> 'nucleo_convertidos')::int as convertidos,
      (e.value ->> 'operaciones_cartera')::int as operaciones,
      case when pg_catalog.jsonb_typeof(
        e.value -> 'nucleo_conversion_pct'
      ) = 'number'
      then (e.value ->> 'nucleo_conversion_pct')::numeric end as pct
    from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  )
  select count(*) into v_mismatch
  from esperado x
  full join obtenido g using (supervisor_id)
  where g.supervisor_id is null
     or x.supervisor_id is null
     or g.divisor is distinct from x.divisor
     or g.numerador is distinct from x.numerador
     or g.convertidos is distinct from x.convertidos
     or g.operaciones is distinct from x.operaciones
     or g.pct is distinct from x.pct;

  if v_mismatch <> 0 then
    raise exception 'C01-BASE oraculo dinamico: % diferencias', v_mismatch;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000101';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric is distinct from 3
     or (v_fila ->> 'nucleo_numerador')::numeric is distinct from 1.15
     or (v_fila ->> 'nucleo_conversion_pct')::numeric is distinct from 38.33
     or (v_fila ->> 'conversion_pct')::int is distinct from 38
     or (v_fila ->> 'convertidos')::int is distinct from 2
     or (v_fila ->> 'nucleo_convertidos')::int is distinct from 2
     or (v_fila ->> 'operaciones_cartera')::int is distinct from 1
     or (v_fila ->> 'vendedores')::int is distinct from 5
     or (v_fila ->> 'activos')::int is distinct from 3
     or (v_fila ->> 'capital_pen')::numeric is distinct from 3000
     or (v_fila ->> 'capital_usd')::numeric is distinct from 0 then
    raise exception 'C01-BASE S1 incorrecto: %', v_fila;
  end if;

  select
    round(avg(coalesce(
      case when pg_catalog.jsonb_typeof(r.value -> 'conversion_pct') = 'number'
        then (r.value ->> 'conversion_pct')::numeric end,
      0
    )), 2),
    round(avg(
      case when pg_catalog.jsonb_typeof(r.value -> 'conversion_pct') = 'number'
        then (r.value ->> 'conversion_pct')::numeric end
    ), 2),
    round(100.0 * sum((r.value ->> 'numerador')::numeric) / count(*), 2)
  into v_avg_coalesce, v_avg_sin_null, v_por_conteo
  from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') r(value)
  where r.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000101';

  if v_avg_coalesce is null
     or v_avg_sin_null is null
     or v_por_conteo is null
     or (v_fila ->> 'nucleo_conversion_pct')::numeric in (
       v_avg_coalesce, v_avg_sin_null, v_por_conteo
     ) then
    raise exception
      'C01-BASE fixture vacuo contra AVG/COUNT (%/%/% vs %)',
      v_avg_coalesce,
      v_avg_sin_null,
      v_por_conteo,
      v_fila ->> 'nucleo_conversion_pct';
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000102';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric is distinct from 1
     or (v_fila ->> 'nucleo_numerador')::numeric is distinct from 3
     or (v_fila ->> 'nucleo_conversion_pct')::numeric is distinct from 300
     or (v_fila ->> 'convertidos')::int is distinct from 1
     or (v_fila ->> 'nucleo_convertidos')::int is distinct from 1
     or (v_fila ->> 'operaciones_cartera')::int is distinct from 2 then
    raise exception 'C01-BASE S2 >100/cartera incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000103';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric is distinct from 0
     or (v_fila ->> 'nucleo_numerador')::numeric is distinct from 1
     or (v_fila ->> 'nucleo_convertidos')::int is distinct from 0
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_conversion_pct')
        is distinct from 'null'
     or (v_fila ->> 'conversion_pct')::int is distinct from 0
     or (v_fila ->> 'operaciones_cartera')::int is distinct from 1 then
    raise exception 'C01-BASE S3 NULL incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000104';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric is distinct from 0
     or (v_fila ->> 'nucleo_numerador')::numeric is distinct from 0
     or (v_fila ->> 'nucleo_convertidos')::int is distinct from 0
     or (v_fila ->> 'operaciones_cartera')::int is distinct from 0
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_conversion_pct')
        is distinct from 'null' then
    raise exception 'C01-BASE S4 vacio incorrecto: %', v_fila;
  end if;

  -- E produjo, pero no tiene supervisor valido: queda fuera de responsables y
  -- equipos, declarado en cobertura e incluido únicamente en el total global.
  -- La fila OPERATIVA puede existir, pero todo su bundle mensual exacto debe ser
  -- NULL: ausencia jamás se convierte en cero disponible.
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') e(value)
    where e.value ->> 'vendedor_id' =
      'c0100000-0000-4000-8000-000000000206'
  ) or (v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::int
       is distinct from 1 then
    raise exception 'C01-BASE fuera-de-roster mal representado';
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'vendedores') e(value)
  where e.value ->> 'vendedor_id' =
    'c0100000-0000-4000-8000-000000000206';
  if v_fila is null
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_convertidos')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_fila -> 'operaciones_cartera')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_divisor')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_numerador')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_conversion_pct')
        is distinct from 'null' then
    raise exception 'C01-BASE fuera-de-roster fabrico ceros: %', v_fila;
  end if;

  -- A demuestra ajuste y deduplicacion; F demuestra suelo por vendedor.
  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') e(value)
  where e.value ->> 'vendedor_id' =
    'c0100000-0000-4000-8000-000000000201';
  if (v_fila ->> 'numerador')::numeric is distinct from 1.15
     or (v_fila ->> 'conversion_pct')::numeric is distinct from 115
     or (v_fila #>> '{cartera,conversiones_clientes}')::int
        is distinct from 1 then
    raise exception 'C01-BASE A ajuste/cartera incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') e(value)
  where e.value ->> 'vendedor_id' =
    'c0100000-0000-4000-8000-000000000203';
  if (v_fila ->> 'numerador')::numeric is distinct from 0
     or pg_catalog.jsonb_typeof(v_fila -> 'conversion_pct')
        is distinct from 'null' then
    raise exception 'C01-BASE F suelo por vendedor incorrecto: %', v_fila;
  end if;
end
$baseline$;

-- Caso de borde que mata la reimplementacion legacy por division. Mantiene el
-- baseline comercial 38,33/300/NULL intacto y solo calibra el adaptador durante
-- esta llamada.
do $doble_redondeo$
declare
  v jsonb;
  v_s1 jsonb;
  v_directo numeric;
begin
  perform pg_catalog.set_config('c01.mutante', 'doble_redondeo', true);
  v := crm.metricas_vendedores_fn();

  select e.value into v_s1
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000101';

  if v_s1 is not null then
    v_directo := round(
      100.0 * (v_s1 ->> 'nucleo_numerador')::numeric
      / (v_s1 ->> 'nucleo_divisor')::numeric
    );
  end if;

  if v_s1 is null
     or (v_s1 ->> 'nucleo_divisor')::numeric is distinct from 3
     or (v_s1 ->> 'nucleo_numerador')::numeric
       is distinct from 1.1549
     or (v_s1 ->> 'nucleo_conversion_pct')::numeric
       is distinct from 38.50
     or (v_s1 ->> 'conversion_pct')::numeric is distinct from 39
     or v_directo is distinct from 38
     or (v_s1 ->> 'conversion_pct')::numeric
       is not distinct from v_directo then
    raise exception
      'C01-DOBLE-REDONDEO legacy no proyecto round(nucleo servido): % / directo %',
      v_s1,
      v_directo;
  end if;

  perform pg_catalog.set_config('c01.mutante', 'ninguno', true);
end
$doble_redondeo$;

-- Política de publicación del wrapper: parcial se ve con aviso; ausencia de
-- ledger, motivos de roster y sonda rota conservan operación pero dejan el
-- bundle exacto completo en NULL.
do $publicacion$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mode text;
  v jsonb;
  v_b jsonb;
  v_wrapper jsonb;
begin
  perform pg_catalog.set_config('c01.mutante', 'mes_parcial', true);
  v_wrapper := crm.conversion_mensual_fn(v_mes);
  v := crm.metricas_vendedores_fn();
  if v -> 'cobertura_conversion' is distinct from v_wrapper -> 'cobertura'
     or pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v -> 'equipos') is distinct from 4
     or (v #>> '{cobertura_conversion,medible}')::boolean
       is distinct from false
     or v #>> '{cobertura_conversion,motivo_no_medible}'
        is distinct from 'mes_parcial'
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,nucleo_divisor}')
        is distinct from 'number'
     or not exists (
       select 1
       from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value)
       where e.value ->> 'vendedor_id' =
         'c0100000-0000-4000-8000-000000000201'
         and pg_catalog.jsonb_typeof(e.value -> 'nucleo_divisor') = 'number'
     ) then
    raise exception 'C01-PUBLICACION mes parcial no quedo provisional';
  end if;

  foreach v_mode in array array[
    'sin_ledger',
    'anterior_al_ledger',
    'sin_supervisor',
    'supervisor_inactivo',
    'supervisor_no_es_supervisor',
    'cierres_sin_episodio'
  ] loop
    perform pg_catalog.set_config('c01.mutante', v_mode, true);
    v_wrapper := crm.conversion_mensual_fn(v_mes);
    v := crm.metricas_vendedores_fn();

    if v -> 'cobertura_conversion' is distinct from v_wrapper -> 'cobertura'
       or pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
       or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array'
       or pg_catalog.jsonb_array_length(v -> 'equipos') is distinct from 4
       or exists (
      select 1
      from (
        select e.value
        from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value)
        union all
        select e.value
        from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value)
        union all
        select v -> 'nucleo_total'
      ) f(value)
      where pg_catalog.jsonb_typeof(f.value) is distinct from 'object'
         or not coalesce(f.value ?& array[
           'nucleo_convertidos',
           'operaciones_cartera',
           'nucleo_divisor',
           'nucleo_numerador',
           'nucleo_conversion_pct'
         ]::text[], false)
         or pg_catalog.jsonb_typeof(f.value -> 'nucleo_convertidos')
            is distinct from 'null'
         or pg_catalog.jsonb_typeof(f.value -> 'operaciones_cartera')
            is distinct from 'null'
         or pg_catalog.jsonb_typeof(f.value -> 'nucleo_divisor')
            is distinct from 'null'
         or pg_catalog.jsonb_typeof(f.value -> 'nucleo_numerador')
            is distinct from 'null'
         or pg_catalog.jsonb_typeof(f.value -> 'nucleo_conversion_pct')
            is distinct from 'null'
    ) then
      raise exception 'C01-PUBLICACION % filtro un exacto', v_mode;
    end if;

    select e.value into v_b
    from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value)
    where e.value ->> 'vendedor_id' =
      'c0100000-0000-4000-8000-000000000202';
    if v_b is null
       or (v_b ->> 'activos')::int is distinct from 2
       or (v_b ->> 'capital_pen')::numeric is distinct from 2000 then
      raise exception 'C01-PUBLICACION % borro la foto operativa: %', v_mode, v_b;
    end if;

    if v_mode = 'cierres_sin_episodio'
       and (v #>> '{cobertura_conversion,cierres_sin_episodio}')::int
           is distinct from 1 then
      raise exception 'C01-PUBLICACION perdio conteo de sonda';
    end if;
  end loop;

  perform pg_catalog.set_config('c01.mutante', 'ninguno', true);
  v_wrapper := crm.conversion_mensual_fn(v_mes);
  v := crm.metricas_vendedores_fn();
  if v -> 'cobertura_conversion' is distinct from v_wrapper -> 'cobertura'
     or pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v -> 'equipos') is distinct from 4
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,nucleo_divisor}')
       is distinct from 'number' then
    raise exception 'C01-PUBLICACION reset no restauro el nucleo';
  end if;
end
$publicacion$;

-- Un miembro CRM activo con perfil público inactivo no pertenece al roster
-- canónico. El equipo mixto debe perder TODO el bundle, no publicar el parcial
-- de los demás integrantes ni ceros creíbles.
reset role;
update public.perfiles
set activo = false
where id = 'c0100000-0000-4000-8000-000000000202';
set local role authenticated;

do $perfil_off$
declare
  v jsonb := crm.metricas_vendedores_fn();
  v_s1 jsonb;
begin
  select e.value into v_s1
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000101';

  if v_s1 is null
     or pg_catalog.jsonb_typeof(v_s1) is distinct from 'object'
     or not coalesce(v_s1 ?& array[
       'nucleo_convertidos',
       'operaciones_cartera',
       'nucleo_divisor',
       'nucleo_numerador',
       'nucleo_conversion_pct'
     ]::text[], false)
     or pg_catalog.jsonb_typeof(v_s1 -> 'nucleo_convertidos')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_s1 -> 'operaciones_cartera')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_s1 -> 'nucleo_divisor')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_s1 -> 'nucleo_numerador')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v_s1 -> 'nucleo_conversion_pct')
        is distinct from 'null' then
    raise exception 'C01-PERFIL-OFF publico un equipo parcial: %', v_s1;
  end if;
end
$perfil_off$;

reset role;
update public.perfiles
set activo = true
where id = 'c0100000-0000-4000-8000-000000000202';

update public.perfiles
set activo = false
where id = 'c0100000-0000-4000-8000-000000000104';
set local role authenticated;

do $supervisor_off$
declare
  v jsonb := crm.metricas_vendedores_fn();
begin
  if pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v -> 'equipos') is distinct from 3
     or (
       select count(distinct e.value ->> 'supervisor_id')
       from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value)
       where e.value ->> 'supervisor_id' in (
         'c0100000-0000-4000-8000-000000000101',
         'c0100000-0000-4000-8000-000000000102',
         'c0100000-0000-4000-8000-000000000103'
       )
     ) is distinct from 3
     or exists (
       select 1
       from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value)
       where e.value ->> 'supervisor_id' not in (
         'c0100000-0000-4000-8000-000000000101',
         'c0100000-0000-4000-8000-000000000102',
         'c0100000-0000-4000-8000-000000000103'
       )
     ) then
    raise exception
      'C01-SUPERVISOR-OFF no conservo exactamente S1-S3: %',
      v -> 'equipos';
  end if;
end
$supervisor_off$;

reset role;
update public.perfiles
set activo = true
where id = 'c0100000-0000-4000-8000-000000000104';
set local role authenticated;

-- Contratos mensuales corruptos: todos deben morir fail-closed con 55000.
do $cobertura$
declare
  v_mode text;
begin
  foreach v_mode in array array[
    'duplicado',
    'duplicado_case',
    'parcial',
    'faltante',
    'supervisor',
    'extra_rol',
    'extra_fuera',
    'alcance',
    'cobertura_ausente',
    'cobertura_tipo',
    'divisor_por_motivo_tipo',
    'sonda_negativa',
    'sonda_fraccional',
    'motivo_incoherente',
    'total_ausente',
    'total_incoherente'
  ] loop
    perform pg_catalog.set_config('c01.mutante', v_mode, true);
    begin
      perform crm.metricas_vendedores_fn();
      raise exception 'C01-COBERTURA mutante % sobrevivio', v_mode;
    exception
      when sqlstate '55000' then null;
    end;
  end loop;
  perform pg_catalog.set_config('c01.mutante', 'ninguno', true);
end
$cobertura$;

-- Alcances exactos por rol y semantica coordinador.
do $roles$
declare
  v jsonb;
  v_vendedores text[];
  v_equipos text[];
  v_actor text;
  v_global_vendedores constant text[] := array[
    'c0100000-0000-4000-8000-000000000001',
    'c0100000-0000-4000-8000-000000000101',
    'c0100000-0000-4000-8000-000000000102',
    'c0100000-0000-4000-8000-000000000103',
    'c0100000-0000-4000-8000-000000000104',
    'c0100000-0000-4000-8000-000000000201',
    'c0100000-0000-4000-8000-000000000202',
    'c0100000-0000-4000-8000-000000000203',
    'c0100000-0000-4000-8000-000000000204',
    'c0100000-0000-4000-8000-000000000205',
    'c0100000-0000-4000-8000-000000000206',
    'c0100000-0000-4000-8000-000000000207',
    'c0100000-0000-4000-8000-000000000303'
  ]::text[];
  v_global_equipos constant text[] := array[
    'c0100000-0000-4000-8000-000000000101',
    'c0100000-0000-4000-8000-000000000102',
    'c0100000-0000-4000-8000-000000000103',
    'c0100000-0000-4000-8000-000000000104'
  ]::text[];
begin
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000001', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array' then
    raise exception 'C01-ROLES gerencia no devolvio arrays';
  end if;
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'vendedor_id'
        order by e.value ->> 'vendedor_id'),
      array[]::text[]
    )
    into v_vendedores
  from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value);
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'supervisor_id'
        order by e.value ->> 'supervisor_id'),
      array[]::text[]
    )
    into v_equipos
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value);
  if v_vendedores is distinct from v_global_vendedores
     or v_equipos is distinct from v_global_equipos then
    raise exception
      'C01-ROLES gerencia derivo (vendedores=%, equipos=%)',
      v_vendedores,
      v_equipos;
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000101', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array' then
    raise exception 'C01-ROLES supervisor no devolvio arrays';
  end if;
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'vendedor_id'
        order by e.value ->> 'vendedor_id'),
      array[]::text[]
    )
    into v_vendedores
  from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value);
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'supervisor_id'
        order by e.value ->> 'supervisor_id'),
      array[]::text[]
    )
    into v_equipos
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value);
  if v_vendedores is distinct from array[
       'c0100000-0000-4000-8000-000000000101',
       'c0100000-0000-4000-8000-000000000201',
       'c0100000-0000-4000-8000-000000000202',
       'c0100000-0000-4000-8000-000000000203',
       'c0100000-0000-4000-8000-000000000207',
       'c0100000-0000-4000-8000-000000000303'
     ]::text[]
     or v_equipos is distinct from array[
       'c0100000-0000-4000-8000-000000000101'
     ]::text[] then
    raise exception
      'C01-ROLES supervisor derivo (vendedores=%, equipos=%)',
      v_vendedores,
      v_equipos;
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000201', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array' then
    raise exception 'C01-ROLES vendedor no devolvio arrays';
  end if;
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'vendedor_id'
        order by e.value ->> 'vendedor_id'),
      array[]::text[]
    )
    into v_vendedores
  from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value);
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'supervisor_id'
        order by e.value ->> 'supervisor_id'),
      array[]::text[]
    )
    into v_equipos
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value);
  if v_vendedores is distinct from array[
       'c0100000-0000-4000-8000-000000000201'
     ]::text[]
     or v_equipos is distinct from array[]::text[]
     or not exists (
       select 1 from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value)
       where e.value ->> 'vendedor_id' =
         'c0100000-0000-4000-8000-000000000201'
         and (e.value ->> 'nucleo_convertidos')::int = 2
         and (e.value ->> 'nucleo_numerador')::numeric = 1.15
     ) then
    raise exception 'C01-ROLES vendedor incorrecto: %', v;
  end if;

  -- Directorio CRM explicito y Directorio solo Portal deben resolver al mismo
  -- conjunto global exacto; no basta con contar cuatro equipos.
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000302', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array' then
    raise exception 'C01-ROLES Directorio CRM no devolvio arrays';
  end if;
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'vendedor_id'
        order by e.value ->> 'vendedor_id'),
      array[]::text[]
    )
    into v_vendedores
  from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value);
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'supervisor_id'
        order by e.value ->> 'supervisor_id'),
      array[]::text[]
    )
    into v_equipos
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value);
  if v_vendedores is distinct from v_global_vendedores
     or v_equipos is distinct from v_global_equipos then
    raise exception
      'C01-ROLES Directorio CRM derivo (vendedores=%, equipos=%)',
      v_vendedores,
      v_equipos;
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000304', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array' then
    raise exception 'C01-ROLES Directorio Portal no devolvio arrays';
  end if;
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'vendedor_id'
        order by e.value ->> 'vendedor_id'),
      array[]::text[]
    )
    into v_vendedores
  from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value);
  select coalesce(
      pg_catalog.array_agg(e.value ->> 'supervisor_id'
        order by e.value ->> 'supervisor_id'),
      array[]::text[]
    )
    into v_equipos
  from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value);
  if v_vendedores is distinct from v_global_vendedores
     or v_equipos is distinct from v_global_equipos then
    raise exception
      'C01-ROLES Directorio Portal derivo (vendedores=%, equipos=%)',
      v_vendedores,
      v_equipos;
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000301', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_typeof(v) is distinct from 'object'
     or not (v ?& array[
       'vendedores',
       'equipos',
       'cobertura_conversion',
       'nucleo_total'
     ]::text[])
     or pg_catalog.jsonb_typeof(v -> 'vendedores') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v -> 'vendedores') is distinct from 0
     or pg_catalog.jsonb_typeof(v -> 'equipos') is distinct from 'array'
     or pg_catalog.jsonb_array_length(v -> 'equipos') is distinct from 0
     or pg_catalog.jsonb_typeof(v -> 'cobertura_conversion')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v -> 'nucleo_total') is distinct from 'object'
     or not coalesce((v -> 'nucleo_total') ?& array[
       'nucleo_convertidos',
       'operaciones_cartera',
       'nucleo_divisor',
       'nucleo_numerador',
       'nucleo_conversion_pct'
     ]::text[], false)
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,nucleo_convertidos}')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,operaciones_cartera}')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,nucleo_divisor}')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,nucleo_numerador}')
        is distinct from 'null'
     or pg_catalog.jsonb_typeof(v #> '{nucleo_total,nucleo_conversion_pct}')
        is distinct from 'null' then
    raise exception 'C01-ROLES coordinador no quedo vacio: %', v;
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000303', true
  );
  begin
    perform crm.metricas_vendedores_fn();
    raise exception 'C01-ROLES actor inactivo sobrevivio';
  exception when sqlstate '42501' then null;
  end;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000999', true
  );
  begin
    perform crm.metricas_vendedores_fn();
    raise exception 'C01-ROLES actor ajeno sobrevivio';
  exception when sqlstate '42501' then null;
  end;

  foreach v_actor in array array[
    'c0100000-0000-4000-8000-000000000305',
    'c0100000-0000-4000-8000-000000000306'
  ]::text[] loop
    perform pg_catalog.set_config(
      'request.jwt.claim.sub', v_actor, true
    );
    begin
      perform crm.metricas_vendedores_fn();
      raise exception
        'C01-ROLES Admin/Superadmin Portal sobrevivio: %',
        v_actor;
    exception when sqlstate '42501' then null;
    end;
  end loop;
end
$roles$;

reset role;

-- Los roles sin EXECUTE deben morir en la ACL aun con una identidad de Gerencia
-- valida. Asi el 42501 no puede venir del gate interno por un JWT residual.
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'c0100000-0000-4000-8000-000000000001',
  true
);
set local role anon;
do $anonimo$
begin
  perform crm.metricas_vendedores_fn();
  raise exception 'C01-ACL anon ejecuto metricas_vendedores_fn';
exception when sqlstate '42501' then null;
end
$anonimo$;
reset role;

set local role service_role;
do $servicio$
begin
  perform crm.metricas_vendedores_fn();
  raise exception 'C01-ACL service_role ejecuto metricas_vendedores_fn';
exception when sqlstate '42501' then null;
end
$servicio$;
reset role;

-- ACL, owner y atributos de catalogo.
do $catalogo$
declare
  v_owner text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
begin
  -- Allowlist directa exacta: owner postgres + authenticated, sin grants
  -- heredados accidentalmente a PUBLIC u otro rol.
  if not exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) a
    join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and g.rolname = 'authenticated'
      and a.privilege_type = 'EXECUTE'
      and not a.is_grantable
  ) or exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) a
    left join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and a.privilege_type = 'EXECUTE'
      and coalesce(g.rolname, 'PUBLIC')
          not in ('postgres', 'authenticated')
  ) then
    raise exception 'C01-ACL directa no coincide con allowlist exacta';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.metricas_vendedores_fn()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.metricas_vendedores_fn()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'crm.metricas_vendedores_fn()', 'EXECUTE'
     ) then
    raise exception 'C01-ACL allowlist incorrecta';
  end if;

  select r.rolname, p.prosecdef, p.provolatile, p.proconfig
    into v_owner, v_secdef, v_volatility, v_config
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure;

  if v_owner is distinct from 'postgres'
     or not v_secdef
     or v_volatility is distinct from 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'C01-CATALOGO owner/definer/stable/search_path incorrectos';
  end if;

  if not pg_catalog.has_schema_privilege(
       'authenticated', 'crm', 'USAGE'
     )
     or not pg_catalog.has_schema_privilege(
       'authenticated', 'private', 'USAGE'
     )
     or not pg_catalog.has_schema_privilege(
       'service_role', 'crm', 'USAGE'
     )
     or not pg_catalog.has_schema_privilege(
       'service_role', 'private', 'USAGE'
     )
     or pg_catalog.has_schema_privilege('anon', 'crm', 'USAGE')
     or pg_catalog.has_schema_privilege('anon', 'private', 'USAGE')
     or pg_catalog.has_schema_privilege('authenticated', 'crm', 'CREATE')
     or pg_catalog.has_schema_privilege('authenticated', 'private', 'CREATE')
     or pg_catalog.has_schema_privilege('service_role', 'crm', 'CREATE')
     or pg_catalog.has_schema_privilege('service_role', 'private', 'CREATE')
     or pg_catalog.has_schema_privilege('anon', 'crm', 'CREATE')
     or pg_catalog.has_schema_privilege('anon', 'private', 'CREATE') then
    raise exception 'C01-ACL efectiva de esquemas crm/private incorrecta';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_namespace n
    cross join lateral pg_catalog.aclexplode(
      coalesce(n.nspacl, pg_catalog.acldefault('n', n.nspowner))
    ) a
    where n.nspname in ('crm', 'private')
      and a.grantee = 0
      and a.privilege_type in ('USAGE', 'CREATE')
  ) then
    raise exception 'C01-ACL PUBLIC conserva privilegios en crm/private';
  end if;
end
$catalogo$;

select 'C0.1_BANCO_ADVERSARIO_OK' as resultado;

rollback;
