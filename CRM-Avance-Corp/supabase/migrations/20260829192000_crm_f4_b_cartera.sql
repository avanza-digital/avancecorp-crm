-- P-055 FASE 4.b — Cartera y ficha consumen el nucleo.
--
-- Tres funciones reescritas de cuerpo entero, con el oraculo dentro:
--   crm.resumen_cartera_clientes_fn      (el resumen de la pantalla Cartera)
--   crm.contratos_por_periodo_comercial_fn (la lista del periodo, gerencia)
--   private.metricas_cartera_por_vendedor  (la economia renovado/adicional)
-- crm.metricas_cartera_fn NO se toca: consume a la tercera y hereda el nucleo
-- por transitividad (queda anotado en el ledger).
-- En la lista del periodo, los datos DESCRIPTIVOS del contrato (numero, fechas,
-- fuente) se leen por JOIN al contrato POR ID; el capital, la moneda y la
-- categoria vienen del nucleo: los hechos de dinero tienen UNA fuente.

begin;

set local lock_timeout = '5s';

do $preflight$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'crm.resumen_cartera_clientes_fn()'::regprocedure;
  if v_h <> '59570c4d2a84577019566aace193e03c' then
    raise exception 'resumen_cartera_clientes_fn cambio (huella %): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'crm.contratos_por_periodo_comercial_fn(date)'::regprocedure;
  if v_h <> '3ab7ad716e3518c4b228b360543ac3c4' then
    raise exception 'contratos_por_periodo_comercial_fn cambio (huella %): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure;
  if v_h <> 'a5ec29bd68511a286a3d2ea4d316a9be' then
    raise exception 'metricas_cartera_por_vendedor cambio (huella %): ABORTA', v_h; end if;
end
$preflight$;

create temp table zz_f4b_antes (quien text, fn text, huella text) on commit drop;

do $antes$
declare v_uid_ger uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; v_uid_vend uuid;
        h1 text; h2 text; h3 text;
begin
  select e.perfil_id into v_uid_vend from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.activo and e.rol_crm='vendedor' and p.activo
  order by e.perfil_id limit 1;
  create temp table zz_f4b_vend on commit drop as select v_uid_vend as uid;

  -- la de vendedor-nucleo no tiene gate propio (es private): foto directa
  insert into zz_f4b_antes
  select 'srv','cartera_por_vendedor',
         md5(coalesce(jsonb_agg(to_jsonb(t) order by t.vendedor_id)::text,'[]'))
  from private.metricas_cartera_por_vendedor(date '2026-08-01') t;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_ger, 'role','authenticated')::text);
  set local role authenticated;
  select md5((crm.resumen_cartera_clientes_fn() - 'generado_en')::text) into h1;
  select md5((crm.contratos_por_periodo_comercial_fn(date '2026-08-01') - 'generado_en')::text) into h2;
  reset role;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_vend, 'role','authenticated')::text);
  set local role authenticated;
  select md5((crm.resumen_cartera_clientes_fn() - 'generado_en')::text) into h3;
  reset role;

  insert into zz_f4b_antes values
    ('gerencia','resumen',h1), ('gerencia','periodo',h2), ('vendedor','resumen',h3);
end
$antes$;

-- ---------------------------------------------------------------- REEMPLAZOS --
create or replace function crm.resumen_cartera_clientes_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_hoy_lima date;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_hoy_lima := (v_ahora at time zone 'America/Lima')::date;

  with clientes_ambito as materialized (
    select p.id, p.activo, p.asesor_perfil_id
    from public.perfiles p
    where p.rol = 'cliente'
      and (
        v_lector
        or v_rol = 'gerencia'
        or p.asesor_perfil_id = any(v_visibles)
      )
  ),
  contratos_ambito as materialized (
    -- Los hechos, del NUCLEO; el ambito por cliente, de esta pantalla.
    select e.contrato_id as id, e.estado, e.moneda, coalesce(e.monto, 0) as capital,
           e.fecha_vencimiento, cli.activo as cliente_activo, cli.id as cliente_id
    from private.capital_episodios(
           (date '1900-01-01')::timestamp at time zone 'America/Lima',
           (date '9999-01-01')::timestamp at time zone 'America/Lima',
           true, '{}'::uuid[]) e
    join clientes_ambito cli on cli.id = e.cliente_id
    where e.tipo like 'contrato_%'
  ),
  con_capital as (
    select count(distinct ca.cliente_id)::int as n
    from contratos_ambito ca
    where ca.estado = 'activo' and ca.cliente_activo
  ),
  por_estado as (
    select coalesce(jsonb_object_agg(x.estado, x.n), '{}'::jsonb) as j
    from (select ca.estado, count(*)::int as n
          from contratos_ambito ca group by ca.estado) x
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'zona', 'America/Lima',
    'dias_alarma_renovacion', 30,
    'clientes', jsonb_build_object(
      'en_gestion', count(*) filter (where cl.activo),
      'de_baja', count(*) filter (where not cl.activo),
      'con_capital', (select n from con_capital),
      'sin_asesor', count(*) filter (where cl.activo and cl.asesor_perfil_id is null)
    ),
    'capital_activo', jsonb_build_object(
      'pen', coalesce((select round(sum(ca.capital), 2) from contratos_ambito ca
                       where ca.estado = 'activo' and ca.cliente_activo
                         and ca.moneda is distinct from 'USD'), 0),
      'usd', coalesce((select round(sum(ca.capital), 2) from contratos_ambito ca
                       where ca.estado = 'activo' and ca.cliente_activo
                         and ca.moneda = 'USD'), 0)
    ),
    'contratos', jsonb_build_object(
      'por_estado', (select j from por_estado),
      'por_vencer_30', coalesce((select count(*)::int from contratos_ambito ca
                                 where ca.estado = 'activo'
                                   and ca.fecha_vencimiento is not null
                                   and ca.fecha_vencimiento >= v_hoy_lima
                                   and ca.fecha_vencimiento <= v_hoy_lima + 30), 0),
      'por_vencer_30_de_baja', coalesce((select count(*)::int from contratos_ambito ca
                                         where ca.estado = 'activo'
                                           and not ca.cliente_activo
                                           and ca.fecha_vencimiento is not null
                                           and ca.fecha_vencimiento >= v_hoy_lima
                                           and ca.fecha_vencimiento <= v_hoy_lima + 30), 0)
    )
  )
  into v_payload
  from clientes_ambito cl;

  return v_payload;
end;
$fn$;

create or replace function crm.contratos_por_periodo_comercial_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_lector boolean := private.es_lector_global();
  v_payload jsonb;
begin
  if v_uid is null
     or not coalesce(v_rol = 'gerencia' or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null
     or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes'
      using errcode = '22023';
  end if;

  with base as materialized (
    -- El hecho (capital, moneda, categoria, mes) sale del NUCLEO; lo
    -- descriptivo del contrato, por JOIN a su fila por id.
    select
      e.contrato_id as id,
      c.numero_contrato,
      e.cliente_id,
      c.fecha_cierre_comercial,
      c.fuente_cierre_comercial,
      c.creado_en,
      c.fecha_inicio,
      e.categoria,
      e.moneda,
      e.monto as capital,
      e.estado
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) e
    join public.contratos c on c.id = e.contrato_id
    where e.tipo like 'contrato_%'
  ), por_categoria as (
    select
      coalesce(b.categoria, 'sin_categoria') as categoria,
      b.moneda,
      count(*)::integer as contratos,
      coalesce(sum(b.capital), 0) as capital
    from base b
    group by coalesce(b.categoria, 'sin_categoria'), b.moneda
  )
  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'hasta_exclusivo', (p_periodo + interval '1 month')::date,
    'generado_en', now(),
    'totales', jsonb_build_object(
      'contratos', (select count(*)::integer from base),
      'capital_pen', coalesce((
        select sum(b.capital) from base b where b.moneda = 'PEN'
      ), 0),
      'capital_usd', coalesce((
        select sum(b.capital) from base b where b.moneda = 'USD'
      ), 0)
    ),
    'por_categoria', coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoria', pc.categoria,
        'moneda', pc.moneda,
        'contratos', pc.contratos,
        'capital', pc.capital
      ) order by pc.categoria, pc.moneda)
      from por_categoria pc
    ), '[]'::jsonb),
    'contratos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'numero_contrato', b.numero_contrato,
        'cliente_id', b.cliente_id,
        'fecha_cierre_comercial', b.fecha_cierre_comercial,
        'fuente_cierre_comercial', b.fuente_cierre_comercial,
        'fecha_registro', b.creado_en,
        'fecha_inicio', b.fecha_inicio,
        'categoria', b.categoria,
        'moneda', b.moneda,
        'capital', b.capital,
        'estado', b.estado
      ) order by b.fecha_cierre_comercial, b.creado_en, b.id)
      from base b
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$fn$;

create or replace function private.metricas_cartera_por_vendedor(p_periodo date)
returns table(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer,
              conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer,
              capital_renovado_pen numeric, capital_renovado_usd numeric,
              capital_adicional_pen numeric, capital_adicional_usd numeric,
              renovaciones_sin_desglose integer)
language sql
stable
security definer
set search_path to ''
as $fn$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
      e.analista_id as vendedor_id,
      e.categoria
    from private.conversion_episodios(
      p_ini => p_periodo::timestamp at time zone 'America/Lima',
      p_fin => (p_periodo + interval '1 month')::timestamp
        at time zone 'America/Lima',
      p_periodo => p_periodo,
      p_global => true,
      p_visibles => '{}'::uuid[],
      p_factor => 0::numeric
    ) e
    where e.tipo = 'operacion'
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (
        where e.categoria = 'renovacion'
      )::int as conversiones_renovacion,
      count(*) filter (
        where e.categoria = 'upgrade'
      )::int as conversiones_upgrade
    from episodios_conversion e
    group by e.vendedor_id
  ), dinero as (
    -- El desglose renovado/adicional, del NUCLEO de capital (pierna desglose,
    -- solo renovaciones: los upgrades no llevan desglose por diseno).
    select
      k.analista_id as vendedor_id,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'PEN'), 0)
        as capital_renovado_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'USD'), 0)
        as capital_renovado_usd,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'PEN'), 0)
        as capital_adicional_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'USD'), 0)
        as capital_adicional_usd
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) k
    where k.tipo like 'desglose_%' and k.categoria = 'renovacion'
      and k.mes_comercial = p_periodo
    group by k.analista_id
  ), economia as (
    select
      o.vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int
        as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int
        as operaciones_upgrade,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo
      )::int as renovaciones_sin_desglose
    from ops o
    group by o.vendedor_id
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
    union
    select d.vendedor_id from dinero d
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(d.capital_renovado_pen, 0),
    coalesce(d.capital_renovado_usd, 0),
    coalesce(d.capital_adicional_pen, 0),
    coalesce(d.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join dinero d using (vendedor_id)
  left join economia e using (vendedor_id)
$fn$;

-- ------------------------------------------------------------------ ORACULO --
do $despues$
declare v_uid_ger uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; v_uid_vend uuid;
        h1 text; h2 text; h3 text; h4 text; v_falla text := '';
begin
  select uid into v_uid_vend from zz_f4b_vend;

  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.vendedor_id)::text,'[]')) into h4
  from private.metricas_cartera_por_vendedor(date '2026-08-01') t;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_ger, 'role','authenticated')::text);
  set local role authenticated;
  select md5((crm.resumen_cartera_clientes_fn() - 'generado_en')::text) into h1;
  select md5((crm.contratos_por_periodo_comercial_fn(date '2026-08-01') - 'generado_en')::text) into h2;
  reset role;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_vend, 'role','authenticated')::text);
  set local role authenticated;
  select md5((crm.resumen_cartera_clientes_fn() - 'generado_en')::text) into h3;
  reset role;

  if h4 <> (select huella from zz_f4b_antes where quien='srv' and fn='cartera_por_vendedor') then v_falla := v_falla || 'cartera_por_vendedor '; end if;
  if h1 <> (select huella from zz_f4b_antes where quien='gerencia' and fn='resumen') then v_falla := v_falla || 'resumen/gerencia '; end if;
  if h2 <> (select huella from zz_f4b_antes where quien='gerencia' and fn='periodo') then v_falla := v_falla || 'periodo/gerencia '; end if;
  if h3 <> (select huella from zz_f4b_antes where quien='vendedor' and fn='resumen') then v_falla := v_falla || 'resumen/vendedor '; end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.b: el payload cambio en [%]: NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.b OK: cartera identica byte a byte';
end
$despues$;

commit;
