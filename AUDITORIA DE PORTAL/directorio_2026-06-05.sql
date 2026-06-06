-- ============================================================
-- Rol DIRECTORIO — panel ejecutivo de solo lectura (Kirk & Carlos)
-- Respaldo de las migraciones aplicadas vía Supabase MCP el 2026-06-05.
-- Plan: docs/superpowers/plans/2026-06-05-directorio-cockpit.md
-- ============================================================

-- ---------- Migración 1: directorio_rol_y_helper ----------
ALTER TABLE public.perfiles DROP CONSTRAINT perfiles_rol_check;
ALTER TABLE public.perfiles ADD CONSTRAINT perfiles_rol_check
  CHECK (rol = ANY (ARRAY['cliente','analista','admin','superadmin','directorio']));

CREATE OR REPLACE FUNCTION public.es_directorio()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles
    WHERE id = auth.uid() AND rol = 'directorio' AND activo = true
  );
$$;

REVOKE EXECUTE ON FUNCTION public.es_directorio() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.es_directorio() TO authenticated;

-- ---------- Migración 2: directorio_rpc_metricas ----------
-- Definiciones confirmadas por Miguel (2026-06-05):
--   intereses = retornos pagados · ranking = asesor del cliente · crecimiento = capital captado por mes (fecha_inicio)
CREATE OR REPLACE FUNCTION public.metricas_directorio()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v jsonb;
  hoy date := (now() AT TIME ZONE 'America/Lima')::date;
  inicio_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Lima'))::date;
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;
  WITH activos AS (SELECT * FROM contratos WHERE estado = 'activo'),
  aum AS (
    SELECT moneda, COALESCE(SUM(capital),0) AS total,
           COALESCE(SUM(capital) FILTER (WHERE fecha_inicio >= inicio_mes),0) AS captado_mes
    FROM activos GROUP BY moneda
  ),
  cuotas AS (
    SELECT cp.*, c.moneda FROM cronograma_pagos cp JOIN contratos c ON c.id = cp.contrato_id
    WHERE c.estado = 'activo'
  ),
  vencidas AS (SELECT * FROM cuotas WHERE estado <> 'pagado' AND fecha_programada < hoy),
  pendientes AS (SELECT * FROM cuotas WHERE estado <> 'pagado')
  SELECT jsonb_build_object(
    'generado_en', now(),
    'aum', (SELECT COALESCE(jsonb_object_agg(moneda, jsonb_build_object(
        'total', total, 'captado_mes', captado_mes,
        'var_pct', CASE WHEN (total - captado_mes) > 0
                        THEN round((captado_mes / (total - captado_mes) * 100)::numeric, 1) ELSE 0 END
      )), '{}'::jsonb) FROM aum),
    'clientes', jsonb_build_object(
      'activos', (SELECT COUNT(DISTINCT cliente_id) FROM activos),
      'nuevos_mes', (SELECT COUNT(*) FROM perfiles WHERE rol='cliente' AND creado_en >= inicio_mes)),
    'contratos', jsonb_build_object(
      'activos', (SELECT COUNT(*) FROM activos),
      'ticket_promedio', (SELECT COALESCE(jsonb_object_agg(moneda, prom),'{}'::jsonb) FROM (
          SELECT moneda, round(AVG(capital)::numeric,2) AS prom FROM activos GROUP BY moneda) t)),
    'cobranza', jsonb_build_object(
      'pct_al_dia', (SELECT CASE WHEN COUNT(*)=0 THEN 100
               ELSE round((COUNT(*) FILTER (WHERE estado='pagado' OR fecha_programada >= hoy)::numeric
                           / COUNT(*) * 100), 1) END FROM cuotas WHERE fecha_programada <= hoy),
      'cuotas_vencidas', (SELECT COUNT(*) FROM vencidas),
      'monto_vencido', (SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
          SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto FROM vencidas GROUP BY moneda) t)),
    'intereses_pagados', (SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT c.moneda, COALESCE(SUM(cp.monto_pagado),0) AS monto
        FROM cronograma_pagos cp JOIN contratos c ON c.id=cp.contrato_id
        WHERE cp.tipo='retorno' AND cp.estado='pagado' GROUP BY c.moneda) t),
    'caja_90d', (SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto
        FROM pendientes WHERE fecha_programada BETWEEN hoy AND (hoy + 90) GROUP BY moneda) t),
    'crecimiento', (SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) FROM (
        SELECT jsonb_build_object('mes', to_char(m, 'YYYY-MM'),
          'PEN', COALESCE((SELECT SUM(capital) FROM contratos WHERE moneda='PEN' AND date_trunc('month',fecha_inicio)=m),0),
          'USD', COALESCE((SELECT SUM(capital) FROM contratos WHERE moneda='USD' AND date_trunc('month',fecha_inicio)=m),0)
        ) AS row
        FROM generate_series(date_trunc('month', hoy) - interval '11 months', date_trunc('month', hoy), interval '1 month') m) s)
  ) INTO v;
  RETURN v;
END; $$;
REVOKE EXECUTE ON FUNCTION public.metricas_directorio() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.metricas_directorio() TO authenticated;

-- ---------- Migración 3: directorio_rpc_detalle ----------
CREATE OR REPLACE FUNCTION public.directorio_top_clientes()
RETURNS TABLE(cliente_id uuid, nombre text, capital_pen numeric, capital_usd numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT p.id, p.nombre_completo,
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0),
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='USD'),0)
  FROM contratos c JOIN perfiles p ON p.id = c.cliente_id
  WHERE c.estado='activo' GROUP BY p.id, p.nombre_completo
  ORDER BY COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0) DESC LIMIT 10;
END; $$;

CREATE OR REPLACE FUNCTION public.directorio_morosidad()
RETURNS TABLE(cliente text, numero_contrato text, numero_cuota int,
              fecha_programada date, monto numeric, moneda text, dias_vencida int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE hoy date := (now() AT TIME ZONE 'America/Lima')::date;
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT p.nombre_completo, c.numero_contrato, cp.numero_cuota, cp.fecha_programada,
         cp.monto_programado, c.moneda, (hoy - cp.fecha_programada)::int
  FROM cronograma_pagos cp JOIN contratos c ON c.id = cp.contrato_id JOIN perfiles p ON p.id = c.cliente_id
  WHERE c.estado='activo' AND cp.estado <> 'pagado' AND cp.fecha_programada < hoy
  ORDER BY cp.fecha_programada ASC;
END; $$;

CREATE OR REPLACE FUNCTION public.directorio_ranking_analistas()
RETURNS TABLE(analista_id uuid, nombre text, capital_pen numeric,
              capital_usd numeric, n_clientes bigint, n_contratos bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT a.id, a.nombre_completo,
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0),
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='USD'),0),
         COUNT(DISTINCT c.cliente_id), COUNT(c.id)
  FROM contratos c JOIN perfiles cli ON cli.id = c.cliente_id JOIN perfiles a ON a.id = cli.asesor_perfil_id
  WHERE c.estado='activo' GROUP BY a.id, a.nombre_completo
  ORDER BY COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0) DESC;
END; $$;

REVOKE EXECUTE ON FUNCTION public.directorio_top_clientes()      FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.directorio_morosidad()         FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.directorio_ranking_analistas() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.directorio_top_clientes()      TO authenticated;
GRANT  EXECUTE ON FUNCTION public.directorio_morosidad()         TO authenticated;
GRANT  EXECUTE ON FUNCTION public.directorio_ranking_analistas() TO authenticated;
