-- ============================================================================
-- Índice crm.leads(creado_en) — prefiltro de las series comerciales
-- ============================================================================
-- Nota 1 del ledger de la tanda 1 (20260809043802), aprobada por Miguel el
-- 2026-08-09: el prefiltro de series_comerciales_fn
--   (l.creado_en >= v_ini OR l.contrato_id IS NOT NULL)
-- no lo servía ningún índice → seq scan de crm.leads por llamada (aceptable
-- hasta ~300 k, doloroso a 1 M). Con este índice el planner puede resolver el
-- OR por BitmapOr contra idx_leads_contrato (parcial, ya existente desde F0).
-- También sirve el agrupado por mes de alta de cualquier ventana temporal.
--
-- Sin ser CONCURRENTLY a propósito: el ciclo aplica en branch y el merge lo
-- reproduce en prod con la tabla aún pequeña (decenas de filas hoy); si algún
-- día se reindexa a escala, esa operación puntual sí irá aparte.

begin;
set local lock_timeout = '10s';

create index if not exists idx_leads_creado_en
  on crm.leads (creado_en);

comment on index crm.idx_leads_creado_en is
  'Prefiltro temporal de series_comerciales_fn (BitmapOr con idx_leads_contrato) y de cualquier ventana por fecha de alta.';

commit;
