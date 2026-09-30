-- REVERSA de 20260926182748_portal_retira_admin_pagos_resumen: recrea `public.admin_pagos_resumen()`
-- con el cuerpo EXACTO que tenía en producción el 26/09/2026 (md5 del prosrc: 6deebbc3c2536fe5f75de2ea8a598a31)
-- y sus grants (authenticated y service_role; postgres es el dueño). Solo hace falta si alguna pantalla
-- antigua volviera a necesitarla; la pantalla de Pagos actual no la usa.
begin;
CREATE OR REPLACE FUNCTION public.admin_pagos_resumen()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  WITH resumen AS (
    SELECT
      c.id AS contrato_id,
      c.numero_contrato,
      COALESCE(p.nombre_completo, '—') AS cliente,
      c.moneda,
      c.capital,
      c.estado AS estado_contrato,
      count(cp.id)                                                                            AS total_cuotas,
      count(*) FILTER (WHERE cp.estado = 'pagado')                                            AS pagadas,
      count(*) FILTER (WHERE cp.estado NOT IN ('pagado','trasladado') AND cp.fecha_programada <  CURRENT_DATE)   AS vencidas,
      count(*) FILTER (WHERE cp.estado NOT IN ('pagado','trasladado') AND cp.fecha_programada >= CURRENT_DATE)   AS pendientes,
      COALESCE(sum(cp.monto_programado) FILTER (WHERE cp.estado NOT IN ('pagado','trasladado') AND cp.fecha_programada <  CURRENT_DATE), 0) AS adeudado,
      COALESCE(sum(cp.monto_pagado)     FILTER (WHERE cp.estado  = 'pagado'), 0)              AS pagado_total,
      COALESCE(sum(cp.monto_programado) FILTER (WHERE cp.estado NOT IN ('pagado','trasladado')), 0)              AS pendiente_total
    FROM (SELECT * FROM contratos WHERE NOT es_demo) c
    LEFT JOIN cronograma_pagos cp ON cp.contrato_id = c.id
    LEFT JOIN perfiles p ON p.id = c.cliente_id
    GROUP BY c.id, c.numero_contrato, p.nombre_completo, c.moneda, c.capital, c.estado
    HAVING count(cp.id) > 0  -- solo contratos con cronograma
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',              r.contrato_id,
      'numero_contrato', r.numero_contrato,
      'cliente',         r.cliente,
      'moneda',          r.moneda,
      'capital',         r.capital,
      'estado_contrato', r.estado_contrato,
      'totalCuotas',     r.total_cuotas,
      'pagadas',         r.pagadas,
      'vencidas',        r.vencidas,
      'pendientes',      r.pendientes,
      'adeudado',        r.adeudado,
      'pagadoTotal',     r.pagado_total,
      'pendienteTotal',  r.pendiente_total,
      'completo',        (r.pendientes = 0 AND r.vencidas = 0),
      'proxima',         (
        SELECT jsonb_build_object(
          'id',                cp.id,
          'numero_cuota',      cp.numero_cuota,
          'fecha_programada',  cp.fecha_programada,
          'monto_programado',  cp.monto_programado,
          'estado',            cp.estado,
          'tipo',              cp.tipo,
          'fecha_pago_real',   cp.fecha_pago_real
        )
        FROM cronograma_pagos cp
        WHERE cp.contrato_id = r.contrato_id AND cp.estado NOT IN ('pagado','trasladado')
        ORDER BY (cp.fecha_programada < CURRENT_DATE) DESC, cp.fecha_programada ASC
        LIMIT 1
      )
    )
  ), '[]'::jsonb)
  FROM resumen r;
$function$;
grant execute on function public.admin_pagos_resumen() to authenticated, service_role;
do $chk$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.admin_pagos_resumen()')) is distinct from '6deebbc3c2536fe5f75de2ea8a598a31' then
    raise exception 'REVERSA: el cuerpo recreado no coincide con el original (md5 6deebbc3…)';
  end if;
end $chk$;
commit;
