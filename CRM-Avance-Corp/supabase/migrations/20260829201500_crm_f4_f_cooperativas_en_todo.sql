-- P-055 FASE 4.f — DECISION A de Miguel (30/08): «las cooperativas cuentan
-- como dinero de la casa» — EN TODO.
--
-- Esta migracion ROMPE la paridad A PROPOSITO, por orden de negocio: era la
-- incoherencia que Codex expuso como P0-2 (el analista cobraba por la venta en
-- cooperativa pero el Directorio no la veia). El oraculo cambia de forma: cada
-- cifra nueva tiene que ser EXACTAMENTE la vieja + las cooperativas, al
-- centimo, medido dentro de esta misma transaccion. Cualquier otro movimiento
-- aborta.
--
-- DONDE ENTRAN (y como):
--   * capital del mes (gerencia)  -> categoria 'cooperativa'; ambito: gerencia
--     ve todo; un vendedor/supervisor ve LAS SUYAS (por analista del cierre,
--     no por asesor del cliente: una coop no tiene perfil de cliente).
--   * vencimientos (gerencia)     -> las vigentes con su vence_en.
--   * AUM + captado + crecimiento (Directorio) -> vigentes.
--   * ranking del Directorio      -> la coop acredita a SU analista (los
--     contratos siguen acreditando al asesor del cliente, sin cambio).
--   * lista del periodo comercial -> en totales y por_categoria como
--     'cooperativa'; la LISTA de contratos sigue siendo de contratos (una coop
--     no tiene numero de contrato que listar).
-- DONDE NO ENTRAN, dicho en voz alta:
--   * top de clientes del Directorio (una coop no tiene cliente de portal que
--     rankear) y el resumen de cartera de clientes (esa pantalla es la gestion
--     operativa de contratos del portal). Si Miguel los quiere ahi, es otra
--     decision de pantalla.

begin;

set local lock_timeout = '5s';

do $preflight$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='crm.metricas_capital_mes_fn(integer)'::regprocedure;
  if v_h <> '5706e85cf72e24df0aa092d7f6cc7130' then raise exception 'capital_mes cambio (%): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='crm.metricas_vencimientos_fn(integer)'::regprocedure;
  if v_h <> '0a3e5db34412e976c6d4d81b9cffa6af' then raise exception 'vencimientos cambio (%): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='crm.contratos_por_periodo_comercial_fn(date)'::regprocedure;
  if v_h <> '87cc8fd9a0675e65afa921bca589ad8a' then raise exception 'periodo cambio (%): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='public.metricas_directorio()'::regprocedure;
  if v_h <> '323d6cc1e54bea05a0bd2fc6b3924677' then raise exception 'directorio cambio (%): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='public.directorio_ranking_analistas()'::regprocedure;
  if v_h <> '155b618bd646b9026f7b14d78cf42ec0' then raise exception 'ranking cambio (%): ABORTA', v_h; end if;
end
$preflight$;

-- ── FOTO "ANTES" + las coops esperadas, para el oraculo de delta ──
create temp table zz_f4f (k text, v numeric) on commit drop;

do $antes$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        n1 numeric; n2 numeric; n3 numeric; n4 numeric;
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select coalesce(sum(capital_colocado),0) into n1
  from crm.metricas_capital_mes_fn(1) where mes=date '2026-08-01' and moneda='PEN';
  select ((public.metricas_directorio()->'aum'->'PEN')->>'total')::numeric into n2;
  select coalesce(sum((x->>'PEN')::numeric),0) into n3
  from jsonb_array_elements(public.metricas_directorio()->'crecimiento') x
  where x->>'mes'='2026-08';
  select coalesce(sum(r.capital_pen),0) into n4 from public.directorio_ranking_analistas() r;
  reset role;
  insert into zz_f4f values ('mes_pen',n1), ('aum_pen',n2), ('crec_ago_pen',n3), ('rank_pen',n4);

  -- lo que DEBE sumarse
  insert into zz_f4f
  select 'coop_ago_pen', coalesce(sum(monto),0) from crm.cierres_externos
  where anulado_en is null and moneda='PEN'
    and date_trunc('month', creado_en at time zone 'America/Lima') = date '2026-08-01';
  insert into zz_f4f
  select 'coop_vig_pen', coalesce(sum(monto),0) from crm.cierres_externos
  where anulado_en is null and moneda='PEN';
  insert into zz_f4f
  select 'coop_rank_pen', coalesce(sum(ce.monto),0) from crm.cierres_externos ce
  join public.perfiles a on a.id = ce.vendedor_id and a.rol = 'analista'
  where ce.anulado_en is null and ce.moneda='PEN';
end
$antes$;

-- ═══════════════════════ LAS CINCO PANTALLAS ═══════════════════════
create or replace function crm.metricas_capital_mes_fn(p_meses integer default 12)
returns table(mes date, moneda text, categoria text, contratos bigint, capital_colocado numeric)
language sql
stable
security definer
set search_path to ''
as $fn$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    e.mes_comercial as mes,
    e.moneda,
    coalesce(e.categoria, case when e.tipo='cooperativa' then 'cooperativa' end) as categoria,
    count(*)::bigint  as contratos,
    sum(e.monto)      as capital_colocado
  from private.capital_episodios(
         ((date_trunc('month', current_date)
            - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date::timestamp
           at time zone 'America/Lima'),
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  left join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.medida = 'stock'
    and (e.tipo like 'contrato_%' or e.tipo = 'cooperativa')
    -- DECISION A (30/08): la coop entra con categoria propia. El ambito de una
    -- coop es su ANALISTA (no tiene perfil de cliente que consultar).
    and (
      a.es_global
      or (e.tipo like 'contrato_%' and (
            cli.asesor_perfil_id = any (a.ids)
            or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 2, 3;
$fn$;

create or replace function crm.metricas_vencimientos_fn(p_dias integer default 90)
returns table(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
language sql
stable
security definer
set search_path to ''
as $fn$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', e.fecha_vencimiento))::date as mes,
    e.moneda,
    count(*)::bigint as contratos_por_vencer,
    sum(e.monto)     as capital_por_vencer
  from private.capital_episodios(
         '-infinity'::timestamptz,
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  left join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.medida = 'stock'
    and ((e.tipo like 'contrato_%' and e.estado = 'activo')
         or (e.tipo = 'cooperativa' and e.estado = 'vigente'))
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      or (e.tipo like 'contrato_%' and (
            cli.asesor_perfil_id = any (a.ids)
            or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$fn$;

create or replace function public.metricas_directorio()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
DECLARE
  v jsonb;
  hoy date := (now() AT TIME ZONE 'America/Lima')::date;
  inicio_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Lima'))::date;
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  WITH episodios AS (
    -- DECISION A (30/08): el Directorio ve el negocio COMPLETO — contratos
    -- Avance y cierres en cooperativas vigentes, de una sola calculadora.
    SELECT * FROM private.capital_episodios(
      '-infinity'::timestamptz, 'infinity'::timestamptz,
      true, '{}'::uuid[])
    WHERE medida = 'stock'
      AND (tipo LIKE 'contrato_%' OR tipo = 'cooperativa')
  ),
  activos AS (
    SELECT contrato_id AS id, cliente_id, moneda, monto AS capital,
           (fecha AT TIME ZONE 'America/Lima')::date AS fecha_cierre_comercial
    FROM episodios
    WHERE estado IN ('activo','vigente')
  ),
  aum AS (
    SELECT moneda,
           COALESCE(SUM(capital),0) AS total,
           COALESCE(SUM(capital) FILTER (WHERE fecha_cierre_comercial >= inicio_mes),0) AS captado_mes
    FROM activos GROUP BY moneda
  ),
  cuotas AS (
    SELECT cp.*, c.moneda
    FROM cronograma_pagos cp JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id
    WHERE c.estado IN ('activo','vencido')
      AND cp.estado <> 'trasladado'
  ),
  vencidas AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado' AND fecha_programada < hoy
  ),
  pendientes AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado'
  )
  SELECT jsonb_build_object(
    'generado_en', now(),
    'aum', (
      SELECT COALESCE(jsonb_object_agg(moneda, jsonb_build_object(
        'total', total,
        'captado_mes', captado_mes,
        'var_pct', CASE WHEN (total - captado_mes) > 0
                        THEN round((captado_mes / (total - captado_mes) * 100)::numeric, 1)
                        ELSE 0 END
      )), '{}'::jsonb) FROM aum
    ),
    'clientes', jsonb_build_object(
      'activos', (SELECT COUNT(DISTINCT cliente_id) FROM activos WHERE cliente_id IS NOT NULL),
      'nuevos_mes', (SELECT COUNT(*) FROM perfiles WHERE rol='cliente' AND creado_en >= inicio_mes)
    ),
    'contratos', jsonb_build_object(
      'activos', (SELECT COUNT(*) FROM activos),
      'ticket_promedio', (
        SELECT COALESCE(jsonb_object_agg(moneda, prom),'{}'::jsonb) FROM (
          SELECT moneda, round(AVG(capital)::numeric,2) AS prom FROM activos GROUP BY moneda
        ) t
      )
    ),
    'cobranza', jsonb_build_object(
      'pct_al_dia', (
        SELECT CASE WHEN COUNT(*)=0 THEN 100
               ELSE round((COUNT(*) FILTER (WHERE estado='pagado' OR fecha_programada >= hoy)::numeric
                           / COUNT(*) * 100), 1) END
        FROM cuotas WHERE fecha_programada <= hoy
      ),
      'cuotas_vencidas', (SELECT COUNT(*) FROM vencidas),
      'monto_vencido', (
        SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
          SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto FROM vencidas GROUP BY moneda
        ) t
      )
    ),
    'intereses_pagados', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT c.moneda, COALESCE(SUM(cp.monto_pagado),0) AS monto
        FROM cronograma_pagos cp JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id=cp.contrato_id
        WHERE cp.tipo IN ('retorno','devolucion') AND cp.estado='pagado'
        GROUP BY c.moneda
      ) t
    ),
    'caja_90d', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto
        FROM pendientes WHERE fecha_programada BETWEEN hoy AND (hoy + 90)
        GROUP BY moneda
      ) t
    ),
    'crecimiento', (
      SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
          'mes', to_char(m, 'YYYY-MM'),
          'PEN', COALESCE((SELECT SUM(e.monto) FROM episodios e
                           WHERE e.moneda='PEN' AND e.mes_comercial = m::date),0),
          'USD', COALESCE((SELECT SUM(e.monto) FROM episodios e
                           WHERE e.moneda='USD' AND e.mes_comercial = m::date),0)
        ) AS row
        FROM generate_series(date_trunc('month', hoy) - interval '11 months',
                             date_trunc('month', hoy), interval '1 month') m
      ) s
    )
  ) INTO v;

  RETURN v;
END;
$fn$;

create or replace function public.directorio_ranking_analistas()
returns table(analista_id uuid, nombre text, capital_pen numeric, capital_usd numeric, n_clientes bigint, n_contratos bigint)
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  -- DECISION A (30/08): los contratos acreditan al asesor del cliente (como
  -- siempre en esta pantalla); las cooperativas acreditan a SU analista.
  SELECT a.id, a.nombre_completo,
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0),
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='USD'),0),
         COUNT(DISTINCT e.cliente_id) FILTER (WHERE e.cliente_id IS NOT NULL),
         COUNT(e.contrato_id)
  FROM private.capital_episodios(
         '-infinity'::timestamptz, 'infinity'::timestamptz,
         true, '{}'::uuid[]) e
  LEFT JOIN perfiles cli ON cli.id = e.cliente_id
  JOIN perfiles a ON a.rol = 'analista'
    AND a.id = CASE WHEN e.tipo = 'cooperativa' THEN e.analista_id
                    ELSE cli.asesor_perfil_id END
  WHERE e.medida = 'stock'
    AND ((e.tipo LIKE 'contrato_%' AND e.estado='activo')
         OR (e.tipo = 'cooperativa' AND e.estado='vigente'))
  GROUP BY a.id, a.nombre_completo
  ORDER BY COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0) DESC;
END;
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

  with hechos as materialized (
    select e.*
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) e
    where e.medida = 'stock'
      and (e.tipo like 'contrato_%' or e.tipo = 'cooperativa')
  ), base as materialized (
    select
      h.contrato_id as id,
      c.numero_contrato,
      h.cliente_id,
      c.fecha_cierre_comercial,
      c.fuente_cierre_comercial,
      c.creado_en,
      c.fecha_inicio,
      h.categoria,
      h.moneda,
      h.monto as capital,
      h.estado
    from hechos h
    join public.contratos c on c.id = h.contrato_id
    where h.tipo like 'contrato_%'
  ), por_categoria as (
    -- DECISION A (30/08): las cooperativas aparecen como su propia categoria.
    select
      coalesce(h.categoria, 'sin_categoria') as categoria,
      h.moneda,
      count(*)::integer as contratos,
      coalesce(sum(h.monto), 0) as capital
    from hechos h
    where h.tipo like 'contrato_%'
    group by 1, 2
    union all
    select 'cooperativa', h.moneda, count(*)::integer, coalesce(sum(h.monto), 0)
    from hechos h where h.tipo = 'cooperativa'
    group by 2
  )
  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'hasta_exclusivo', (p_periodo + interval '1 month')::date,
    'generado_en', now(),
    'totales', jsonb_build_object(
      'contratos', (select count(*)::integer from base),
      'capital_pen', coalesce((select sum(h.monto) from hechos h where h.moneda = 'PEN'), 0),
      'capital_usd', coalesce((select sum(h.monto) from hechos h where h.moneda = 'USD'), 0)
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

-- ═════════════════ ORACULO DE DELTA: viejo + coops, AL CENTIMO ═════════════════
do $delta$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        n1 numeric; n2 numeric; n3 numeric; n4 numeric; esp numeric; v_falla text := '';
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select coalesce(sum(capital_colocado),0) into n1
  from crm.metricas_capital_mes_fn(1) where mes=date '2026-08-01' and moneda='PEN';
  select ((public.metricas_directorio()->'aum'->'PEN')->>'total')::numeric into n2;
  select coalesce(sum((x->>'PEN')::numeric),0) into n3
  from jsonb_array_elements(public.metricas_directorio()->'crecimiento') x
  where x->>'mes'='2026-08';
  select coalesce(sum(r.capital_pen),0) into n4 from public.directorio_ranking_analistas() r;
  reset role;

  esp := (select v from zz_f4f where k='mes_pen') + (select v from zz_f4f where k='coop_ago_pen');
  if n1 is distinct from esp then v_falla := v_falla || format('mes_pen(%s<>%s) ', n1, esp); end if;
  esp := (select v from zz_f4f where k='aum_pen') + (select v from zz_f4f where k='coop_vig_pen');
  if n2 is distinct from esp then v_falla := v_falla || format('aum_pen(%s<>%s) ', n2, esp); end if;
  esp := (select v from zz_f4f where k='crec_ago_pen') + (select v from zz_f4f where k='coop_ago_pen');
  if n3 is distinct from esp then v_falla := v_falla || format('crec_ago(%s<>%s) ', n3, esp); end if;
  esp := (select v from zz_f4f where k='rank_pen') + (select v from zz_f4f where k='coop_rank_pen');
  if n4 is distinct from esp then v_falla := v_falla || format('rank_pen(%s<>%s) ', n4, esp); end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.f: la cifra nueva NO es vieja+coops en [%]: NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.f OK: cada cifra nueva = la vieja + las cooperativas, al centimo';
end
$delta$;

commit;
