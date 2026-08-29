-- P-055 FASE 4.c — El Directorio consume el nucleo.
--
-- TOCA `public` (3 funciones del Directorio del portal): con permiso explicito
-- de Miguel — orden del 29/08, «yo quiero ver todo ya... lo que necesito es
-- crear el sistema», dada sobre el plan de la Fase 4 cuya tanda c es
-- literalmente el portal (hallazgo B1 del auditor RLS: dejarlo ESCRITO).
--
-- Tres funciones reescritas de cuerpo entero: directorio_ranking_analistas,
-- directorio_top_clientes y metricas_directorio. Conservan gate y payload.
-- OJO SEMANTICO CONSERVADO A PROPOSITO: el ranking del Directorio agrupa por
-- el ASESOR DEL CLIENTE con rol de portal 'analista' — asi lo muestra hoy y
-- asi se queda (paridad); si el Directorio debe pasar a agrupar por el
-- analista que cierra, es una decision de pantalla para Miguel, no un
-- efecto colateral de esta migracion.
-- Las piezas de COBRANZA (cuotas) de metricas_directorio no son capital y
-- siguen leyendo cronograma_pagos tal cual.

begin;

set local lock_timeout = '5s';

do $preflight$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'public.directorio_ranking_analistas()'::regprocedure;
  if v_h <> '77301c9272df9a1d1de2a2a754053af3' then
    raise exception 'directorio_ranking_analistas cambio (huella %): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'public.directorio_top_clientes()'::regprocedure;
  if v_h <> 'a7d31c780c0169de2468578edd89a333' then
    raise exception 'directorio_top_clientes cambio (huella %): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'public.metricas_directorio()'::regprocedure;
  if v_h <> 'e560edbfc06324f05340be3f87889906' then
    raise exception 'metricas_directorio cambio (huella %): ABORTA', v_h; end if;
end
$preflight$;

create temp table zz_f4c_antes (fn text, huella text) on commit drop;

do $antes$
declare v_uid uuid; h1 text; h2 text; h3 text;
begin
  -- un actor real con es_directorio() o es_admin(): el ADMINISTRADOR es admin
  v_uid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.analista_id)::text,'[]'))
    into h1 from public.directorio_ranking_analistas() t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.cliente_id)::text,'[]'))
    into h2 from public.directorio_top_clientes() t;
  select md5((public.metricas_directorio() - 'generado_en')::text) into h3;
  reset role;

  insert into zz_f4c_antes values ('ranking',h1), ('top',h2), ('directorio',h3);
end
$antes$;

create or replace function public.directorio_ranking_analistas()
returns table(analista_id uuid, nombre text, capital_pen numeric, capital_usd numeric, n_clientes bigint, n_contratos bigint)
language plpgsql
security definer
set search_path to 'public'
as $fn$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT a.id, a.nombre_completo,
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0),
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='USD'),0),
         COUNT(DISTINCT e.cliente_id), COUNT(e.contrato_id)
  FROM private.capital_episodios(
         (DATE '1900-01-01')::timestamp AT TIME ZONE 'America/Lima',
         (DATE '9999-01-01')::timestamp AT TIME ZONE 'America/Lima',
         true, '{}'::uuid[]) e
  JOIN perfiles cli ON cli.id = e.cliente_id
  JOIN perfiles a ON a.id = cli.asesor_perfil_id AND a.rol = 'analista'
  WHERE e.tipo LIKE 'contrato_%' AND e.estado='activo'
  GROUP BY a.id, a.nombre_completo
  ORDER BY COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0) DESC;
END;
$fn$;

create or replace function public.directorio_top_clientes()
returns table(cliente_id uuid, nombre text, capital_pen numeric, capital_usd numeric)
language plpgsql
security definer
set search_path to 'public'
as $fn$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT p.id, p.nombre_completo,
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0),
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='USD'),0)
  FROM private.capital_episodios(
         (DATE '1900-01-01')::timestamp AT TIME ZONE 'America/Lima',
         (DATE '9999-01-01')::timestamp AT TIME ZONE 'America/Lima',
         true, '{}'::uuid[]) e
  JOIN perfiles p ON p.id = e.cliente_id
  WHERE e.tipo LIKE 'contrato_%' AND e.estado='activo'
  GROUP BY p.id, p.nombre_completo
  ORDER BY COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0) DESC
  LIMIT 10;
END;
$fn$;

create or replace function public.metricas_directorio()
returns jsonb
language plpgsql
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
    SELECT * FROM private.capital_episodios(
      (DATE '1900-01-01')::timestamp AT TIME ZONE 'America/Lima',
      (DATE '9999-01-01')::timestamp AT TIME ZONE 'America/Lima',
      true, '{}'::uuid[])
    WHERE tipo LIKE 'contrato_%'
  ),
  activos AS (
    SELECT contrato_id AS id, cliente_id, moneda, monto AS capital,
           (fecha AT TIME ZONE 'America/Lima')::date AS fecha_cierre_comercial
    FROM episodios WHERE estado = 'activo'
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
      'activos', (SELECT COUNT(DISTINCT cliente_id) FROM activos),
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

do $despues$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        h1 text; h2 text; h3 text; v_falla text := '';
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.analista_id)::text,'[]'))
    into h1 from public.directorio_ranking_analistas() t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.cliente_id)::text,'[]'))
    into h2 from public.directorio_top_clientes() t;
  select md5((public.metricas_directorio() - 'generado_en')::text) into h3;
  reset role;

  if h1 <> (select huella from zz_f4c_antes where fn='ranking') then v_falla := v_falla || 'ranking '; end if;
  if h2 <> (select huella from zz_f4c_antes where fn='top') then v_falla := v_falla || 'top '; end if;
  if h3 <> (select huella from zz_f4c_antes where fn='directorio') then v_falla := v_falla || 'directorio '; end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.c: el payload cambio en [%]: NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.c OK: Directorio identico byte a byte';
end
$despues$;

commit;
