-- ============================================================================
-- CORRECCIONES DE BASE DE DATOS — PORTAL AVANCE CORP
-- Proyecto Supabase: dctqcbznekcyxhjujuci
-- Origen: AUDITORIA DE PORTAL/auditoria_db_avance_corp.md
-- Fecha: 2026-06-01
--
-- CÓMO USAR:
--   Opción 1 (recomendada por Miguel): Claude lo ejecuta vía MCP de Supabase.
--   Opción 2 (plan B): pegar por partes en el SQL Editor de Supabase y dar RUN.
--
-- ORDEN OBLIGATORIO:
--   PARTE 0  → solo lectura (confirma el estado real antes de tocar nada)
--   PARTE 1  → cambios seguros, sin dependencia de frontend (correr de una)
--   PARTE 2A → preparar columna `novedades.leido` (correr ANTES del deploy)
--   ...deploy del frontend + edge `notificar-pagos` (fuera de este archivo)...
--   PARTE 2B → DROP de la columna (correr SOLO DESPUÉS del deploy y de verificar)
--   PARTE 3  → verificación final
-- ============================================================================


-- ============================================================================
-- PARTE 0 — PRE-VERIFICACIÓN (solo lectura, no cambia nada)
-- ============================================================================

-- (a) Trigger de auditoría en cronograma_pagos — confirmar nombre exacto
SELECT trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'cronograma_pagos';

-- (b) Policies de perfiles y su rol actual (deben pasar de {public} a {authenticated})
SELECT policyname, roles, cmd
FROM pg_policies
WHERE tablename = 'perfiles'
  AND policyname IN ('superadmin_elimina_perfiles', 'admin_crea_perfiles');

-- (c) Volumen actual de audit_log
SELECT COUNT(*) AS total, pg_size_pretty(pg_total_relation_size('audit_log')) AS tamano
FROM audit_log;

-- (d) Índices presentes en cronograma_pagos (debe FALTAR idx_cronograma_estado)
SELECT indexname FROM pg_indexes WHERE tablename = 'cronograma_pagos';

-- (e) Triggers en suscripciones_push (debe FALTAR el de actualizado_en)
SELECT trigger_name FROM information_schema.triggers
WHERE event_object_table = 'suscripciones_push';

-- (f) Estado de la columna novedades.leido (¿NOT NULL? ¿default?)
SELECT column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'novedades' AND column_name = 'leido';


-- ============================================================================
-- PARTE 1 — CAMBIOS SEGUROS (sin dependencia de frontend)
-- Se pueden correr juntos. Todos son idempotentes.
-- ============================================================================

-- BD-2 (ALTA) — Quitar el trigger de auditoría en cronograma_pagos.
-- Razón: registra CADA insert/update/delete de cuotas en audit_log con el JSON
-- completo; con ~15.000 cuotas (1.000 clientes) haría explotar audit_log.
DROP TRIGGER IF EXISTS trg_audit_cronograma ON cronograma_pagos;

-- BD-1 (ALTA) — Limpiar audit_log inflado por ciclos de prueba (11.798 filas).
-- Conserva lo posterior al inicio de operación real. Ajusta la fecha si hace falta.
DELETE FROM audit_log WHERE ts < '2026-05-25T00:00:00Z';
-- Alternativa (solo si NO hay NINGÚN registro real que conservar):
--   TRUNCATE audit_log;

-- BD-4 (MEDIA) — Endurecer 2 policies de perfiles: rol {public} -> {authenticated}.
-- Se usa ALTER POLICY (NO DROP+CREATE) para PRESERVAR EXACTAMENTE las condiciones
-- ya endurecidas (escalada de roles cerrada el 2026-05-24/26). Solo cambia el rol.
ALTER POLICY superadmin_elimina_perfiles ON perfiles TO authenticated;
ALTER POLICY admin_crea_perfiles        ON perfiles TO authenticated;

-- BD-5 (BAJA) — Crear índice por estado en cronograma_pagos (filtros del panel admin
-- por 'pendiente'/'pagado'/'vencido').
CREATE INDEX IF NOT EXISTS idx_cronograma_estado ON cronograma_pagos(estado);

-- BD-6 (BAJA) — Trigger set_actualizado_en en suscripciones_push (las demás tablas
-- ya lo tienen). CREATE OR REPLACE es idempotente en Postgres 14+ (Supabase = PG15).
CREATE OR REPLACE TRIGGER trg_suscripciones_push_actualizado_en
  BEFORE UPDATE ON suscripciones_push
  FOR EACH ROW EXECUTE FUNCTION set_actualizado_en();


-- ============================================================================
-- PARTE 2A — PREPARAR columna novedades.leido (BD-3) — CORRER ANTES DEL DEPLOY
-- ----------------------------------------------------------------------------
-- La columna está deprecada (el front lee de novedades_leidas), pero hasta ahora
-- dos sitios la escribían en su INSERT (admin/novedades.js y la edge notificar-pagos).
-- Ya quitamos esos `leido: false` en el código. Para que el código nuevo (que OMITE
-- leido) no falle mientras la columna todavía existe, le damos un DEFAULT.
-- Esto es retrocompatible: el código viejo que aún mande leido:false sigue funcionando.
-- ============================================================================

ALTER TABLE novedades ALTER COLUMN leido SET DEFAULT false;
ALTER TABLE novedades ALTER COLUMN leido DROP NOT NULL;  -- inocuo si ya es nullable


-- ============================================================================
-- ⛔ AQUÍ SE PAUSA EL SQL.
-- Desplegar PRIMERO a Hostinger:  admin/novedades.html + js/admin/novedades.js
-- y redeploy de la edge:          supabase functions deploy notificar-pagos \
--                                   --project-ref dctqcbznekcyxhjujuci
-- Verificar que (1) crear un comunicado y (2) registrar un pago siguen funcionando.
-- SOLO ENTONCES correr la PARTE 2B.
-- ============================================================================


-- ============================================================================
-- PARTE 2B — DROP de la columna (BD-3) — CORRER SOLO DESPUÉS DEL DEPLOY
-- ============================================================================

ALTER TABLE novedades DROP COLUMN leido;


-- ============================================================================
-- PARTE 3 — VERIFICACIÓN FINAL (solo lectura)
-- ============================================================================

-- BD-2: el trigger de cronograma ya no existe
SELECT trigger_name FROM information_schema.triggers
WHERE event_object_table = 'cronograma_pagos' AND trigger_name = 'trg_audit_cronograma';
-- Esperado: 0 filas

-- BD-1: audit_log reducido
SELECT COUNT(*) AS total, pg_size_pretty(pg_total_relation_size('audit_log')) AS tamano
FROM audit_log;
-- Esperado: total bajo, tamaño chico

-- BD-4: ambas policies en {authenticated}
SELECT policyname, roles FROM pg_policies
WHERE tablename = 'perfiles'
  AND policyname IN ('superadmin_elimina_perfiles', 'admin_crea_perfiles');
-- Esperado: roles = {authenticated} en ambas

-- BD-5: índice creado
SELECT indexname FROM pg_indexes
WHERE tablename = 'cronograma_pagos' AND indexname = 'idx_cronograma_estado';
-- Esperado: 1 fila

-- BD-6: trigger de push creado
SELECT trigger_name FROM information_schema.triggers
WHERE event_object_table = 'suscripciones_push'
  AND trigger_name = 'trg_suscripciones_push_actualizado_en';
-- Esperado: 1 fila

-- BD-3: columna leido eliminada (correr tras la PARTE 2B)
SELECT column_name FROM information_schema.columns
WHERE table_name = 'novedades' AND column_name = 'leido';
-- Esperado: 0 filas
