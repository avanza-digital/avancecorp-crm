-- Banco adversario propuesto para C0.1.
--
-- NO PRODUCCION. Requiere una base DESECHABLE cuyo nombre empiece por
-- `crm_c01_`, esquema completo hasta F2.6 (y, tras integrar main, F1.3
-- 20260827193803) y la propuesta C0.1 ya aplicada en una sesion anterior. Todo
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

-- Actores: gerencia, S1..S4, vendedores A/B/F/C/D, E fuera de roster,
-- coordinador, Directorio y un actor CRM inactivo. Clientes C1..C4 alimentan
-- cartera.
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
  ('c0100000-0000-4000-8000-000000000301', 'C01 COORD', 'c01-co@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000302', 'C01 DIRECTORIO', 'c01-dir@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000303', 'C01 INACTIVO', 'c01-off@test.invalid', 'comercial', true),
  ('c0100000-0000-4000-8000-000000000401', 'C01 CLIENTE 1', 'c01-cl1@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000402', 'C01 CLIENTE 2', 'c01-cl2@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000403', 'C01 CLIENTE 3', 'c01-cl3@test.invalid', 'cliente', true),
  ('c0100000-0000-4000-8000-000000000404', 'C01 CLIENTE 4', 'c01-cl4@test.invalid', 'cliente', true);

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
  ('c0100000-0000-4000-8000-000000000301', 'coordinador', null, true),
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
  ('c0110000-0000-4000-8000-000000000001'::uuid, 'C01 A NOREF REASIGNADO', '51980001001', 'campania', 'convertido', 'c0100000-0000-4000-8000-000000000204'::uuid, interval '1 day', interval '2 days'),
  ('c0110000-0000-4000-8000-000000000002'::uuid, 'C01 A REFERIDO', '51980001002', 'referido', 'convertido', 'c0100000-0000-4000-8000-000000000201'::uuid, interval '1 day', interval '3 days'),
  ('c0110000-0000-4000-8000-000000000003'::uuid, 'C01 B ABIERTO 1', '51980001003', 'campania', 'contactado', 'c0100000-0000-4000-8000-000000000202'::uuid, interval '1 day', null),
  ('c0110000-0000-4000-8000-000000000004'::uuid, 'C01 B ABIERTO 2', '51980001004', 'campania', 'contactado', 'c0100000-0000-4000-8000-000000000202'::uuid, interval '2 days', null),
  ('c0110000-0000-4000-8000-000000000005'::uuid, 'C01 C NOREF', '51980001005', 'campania', 'convertido', 'c0100000-0000-4000-8000-000000000204'::uuid, interval '1 day', interval '2 days'),
  ('c0110000-0000-4000-8000-000000000006'::uuid, 'C01 E FUERA', '51980001006', 'campania', 'convertido', 'c0100000-0000-4000-8000-000000000206'::uuid, interval '1 day', interval '2 days')
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
  ('c0120000-0000-4000-8000-000000000001'::uuid, 'c0110000-0000-4000-8000-000000000001'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'campania', interval '1 day', true, interval '2 days'),
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

-- Cartera: A tiene dos elegibles del MISMO cliente/mes y debe contar uno.
-- C tiene dos clientes y cuenta dos. D tiene divisor cero y una operacion.
insert into crm.operaciones_cartera(
  id, cliente_id, vendedor_id, tipo, contrato_origen_id,
  contrato_nuevo_id, fecha_operacion, periodo, moneda,
  capital_renovado, capital_adicional, elegible_conversion,
  desglose_completo, fuente, creado_por, creado_en
)
select
  x.id, x.cliente_id, x.vendedor_id, 'upgrade', null,
  x.contrato_id, c.mes + 3, c.mes, 'PEN',
  null, null, true, true, 'flujo_cartera',
  'c0100000-0000-4000-8000-000000000001'::uuid,
  c.ini + x.creado
from c01_clock c
cross join (values
  ('c0130000-0000-4000-8000-000000000001'::uuid, 'c0100000-0000-4000-8000-000000000401'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'c0130000-0000-4000-8000-000000000101'::uuid, interval '3 days 1 hour'),
  ('c0130000-0000-4000-8000-000000000002'::uuid, 'c0100000-0000-4000-8000-000000000401'::uuid, 'c0100000-0000-4000-8000-000000000201'::uuid, 'c0130000-0000-4000-8000-000000000102'::uuid, interval '3 days 2 hours'),
  ('c0130000-0000-4000-8000-000000000003'::uuid, 'c0100000-0000-4000-8000-000000000402'::uuid, 'c0100000-0000-4000-8000-000000000204'::uuid, 'c0130000-0000-4000-8000-000000000103'::uuid, interval '3 days 1 hour'),
  ('c0130000-0000-4000-8000-000000000004'::uuid, 'c0100000-0000-4000-8000-000000000403'::uuid, 'c0100000-0000-4000-8000-000000000204'::uuid, 'c0130000-0000-4000-8000-000000000104'::uuid, interval '3 days 2 hours'),
  ('c0130000-0000-4000-8000-000000000005'::uuid, 'c0100000-0000-4000-8000-000000000404'::uuid, 'c0100000-0000-4000-8000-000000000205'::uuid, 'c0130000-0000-4000-8000-000000000105'::uuid, interval '3 days 1 hour')
) as x(id,cliente_id,vendedor_id,contrato_id,creado);

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

do $baseline$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mensual jsonb := crm.conversion_mensual_fn(v_mes);
  v_metricas jsonb := crm.metricas_vendedores_fn();
  v_fila jsonb;
  v_mismatch int;
begin
  if pg_catalog.jsonb_array_length(v_metricas -> 'equipos') < 4 then
    raise exception 'C01-BASE anti-vacuidad: faltan S1..S4';
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
        'operaciones_cartera',
        'nucleo_divisor',
        'nucleo_numerador',
        'nucleo_conversion_pct'
      ]::text[])
  ) then
    raise exception 'C01-BASE fila exacta incompleta';
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
      (e.value ->> 'convertidos')::int as convertidos,
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
     or (v_fila ->> 'nucleo_divisor')::numeric <> 3
     or (v_fila ->> 'nucleo_numerador')::numeric <> 1.15
     or (v_fila ->> 'nucleo_conversion_pct')::numeric <> 38.33
     or (v_fila ->> 'conversion_pct')::int <> 38
     or (v_fila ->> 'convertidos')::int <> 2
     or (v_fila ->> 'operaciones_cartera')::int <> 1
     or (v_fila ->> 'activos')::int <> 2
     or (v_fila ->> 'capital_pen')::numeric <> 2000
     or (v_fila ->> 'capital_usd')::numeric <> 0 then
    raise exception 'C01-BASE S1 incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000102';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric <> 1
     or (v_fila ->> 'nucleo_numerador')::numeric <> 3
     or (v_fila ->> 'nucleo_conversion_pct')::numeric <> 300
     or (v_fila ->> 'convertidos')::int <> 1
     or (v_fila ->> 'operaciones_cartera')::int <> 2 then
    raise exception 'C01-BASE S2 >100/cartera incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000103';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric <> 0
     or (v_fila ->> 'nucleo_numerador')::numeric <> 1
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_conversion_pct') <> 'null'
     or (v_fila ->> 'conversion_pct')::int <> 0
     or (v_fila ->> 'operaciones_cartera')::int <> 1 then
    raise exception 'C01-BASE S3 NULL incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_metricas -> 'equipos') e(value)
  where e.value ->> 'supervisor_id' =
    'c0100000-0000-4000-8000-000000000104';
  if v_fila is null
     or (v_fila ->> 'nucleo_divisor')::numeric <> 0
     or (v_fila ->> 'nucleo_numerador')::numeric <> 0
     or (v_fila ->> 'operaciones_cartera')::int <> 0
     or pg_catalog.jsonb_typeof(v_fila -> 'nucleo_conversion_pct') <> 'null' then
    raise exception 'C01-BASE S4 vacio incorrecto: %', v_fila;
  end if;

  -- E produjo, pero no tiene supervisor valido: solo agregado anonimo.
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') e(value)
    where e.value ->> 'vendedor_id' =
      'c0100000-0000-4000-8000-000000000206'
  ) or (v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::int <> 1 then
    raise exception 'C01-BASE fuera-de-roster mal representado';
  end if;

  -- A demuestra ajuste y deduplicacion; F demuestra suelo por vendedor.
  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') e(value)
  where e.value ->> 'vendedor_id' =
    'c0100000-0000-4000-8000-000000000201';
  if (v_fila ->> 'numerador')::numeric <> 1.15
     or (v_fila ->> 'conversion_pct')::numeric <> 115
     or (v_fila #>> '{cartera,conversiones_clientes}')::int <> 1 then
    raise exception 'C01-BASE A ajuste/cartera incorrecto: %', v_fila;
  end if;

  select e.value into v_fila
  from pg_catalog.jsonb_array_elements(v_mensual -> 'responsables') e(value)
  where e.value ->> 'vendedor_id' =
    'c0100000-0000-4000-8000-000000000203';
  if (v_fila ->> 'numerador')::numeric <> 0
     or pg_catalog.jsonb_typeof(v_fila -> 'conversion_pct') <> 'null' then
    raise exception 'C01-BASE F suelo por vendedor incorrecto: %', v_fila;
  end if;
end
$baseline$;

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
    'alcance'
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

-- Alcances y semantica coordinador.
do $roles$
declare
  v jsonb;
begin
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000101', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_array_length(v -> 'equipos') <> 1
     or v #>> '{equipos,0,supervisor_id}' <>
       'c0100000-0000-4000-8000-000000000101' then
    raise exception 'C01-ROLES supervisor salio de su equipo: %', v -> 'equipos';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000201', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_array_length(v -> 'equipos') <> 0
     or not exists (
       select 1 from pg_catalog.jsonb_array_elements(v -> 'vendedores') e(value)
       where e.value ->> 'vendedor_id' =
         'c0100000-0000-4000-8000-000000000201'
         and (e.value ->> 'nucleo_numerador')::numeric = 1.15
     ) then
    raise exception 'C01-ROLES vendedor incorrecto: %', v;
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000302', true
  );
  v := crm.metricas_vendedores_fn();
  if not exists (
    select 1 from pg_catalog.jsonb_array_elements(v -> 'equipos') e(value)
    where e.value ->> 'supervisor_id' =
      'c0100000-0000-4000-8000-000000000104'
  ) then
    raise exception 'C01-ROLES Directorio no obtuvo alcance global';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    'c0100000-0000-4000-8000-000000000301', true
  );
  v := crm.metricas_vendedores_fn();
  if pg_catalog.jsonb_array_length(v -> 'vendedores') <> 0
     or pg_catalog.jsonb_array_length(v -> 'equipos') <> 0 then
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
end
$roles$;

reset role;

-- El rol anonimo debe morir en la ACL, antes de entrar al cuerpo.
set local role anon;
do $anonimo$
begin
  perform crm.metricas_vendedores_fn();
  raise exception 'C01-ACL anon ejecuto metricas_vendedores_fn';
exception when sqlstate '42501' then null;
end
$anonimo$;
reset role;

-- ACL, owner y atributos de catalogo.
do $catalogo$
declare
  v_owner text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
begin
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
end
$catalogo$;

select 'C0.1_BANCO_ADVERSARIO_OK' as resultado;

rollback;
