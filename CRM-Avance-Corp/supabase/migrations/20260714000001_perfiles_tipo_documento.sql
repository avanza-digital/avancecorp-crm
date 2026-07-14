-- ============================================================================
-- 20260714000001_perfiles_tipo_documento — [PORTAL — excepción con OK de Miguel]
--
-- Diferenciar DNI / CE / Pasaporte en perfiles (2026-07-14). Aplicada a prod por
-- el carril del PORTAL (MCP apply_migration + QA en transacción revertida +
-- advisors), NO por el gate RLS del CRM: es la 2ª excepción `public` documentada
-- (la 1ª fue 20260711000001_portal_rol_comercial).
--
-- POR QUÉ: el sistema asumía un único documento numérico ("dni" 8–12 dígitos) y
-- el alta rechazaba pasaportes alfanuméricos y no distinguía CE. Se agrega el
-- TIPO como columna aditiva; la columna `dni` NO se renombra (pasa a significar
-- "número de documento"; el re-etiquetado es solo de UI).
--
-- Diseño (revisión multi-lente 2026-07-14):
--   - text + CHECK de DOMINIO (patrón del repo, p.ej. perfiles_rol_check); NO enum
--     (ALTER TYPE ... ADD VALUE no es transaccional ni reversible).
--   - NOT NULL DEFAULT 'DNI' → metadata-only en PG11+ y retrocompatible con los
--     writers viejos (frontend/edges en prod que aún no mandan tipo).
--   - SIN CHECK de formato por tipo aquí: durante la ventana migración→edges los
--     writers viejos aún aceptan 8–12 dígitos como "DNI" y lo violarían. El
--     formato vive en _shared/documento.ts (edges) + documento-core.js (frontend);
--     el CHECK de formato en BD queda diferido a una migración posterior
--     (NOT VALID → VALIDATE) cuando todos los writers manden el tipo.
--   - Backfill determinista e idempotente: solo 9–12 dígitos se promueven a CE
--     (los datos históricos son 100% numéricos); la basura corta queda 'DNI' y
--     se corrige a mano — nunca se inventa un tipo que el valor no satisface.
--   - UNIQUE(dni) simple se conserva (perfiles_dni_key): DNI(8) y CE(9–12) son
--     disjuntos por longitud; limitación aceptada y documentada: un pasaporte de
--     8 dígitos colisionaría con un DNI igual (caso teórico).
--
-- Resultado en prod (2026-07-14): 173 perfiles → 166 DNI + 7 CE, 0 nulos.
-- ============================================================================

alter table public.perfiles
  add column if not exists tipo_documento text not null default 'DNI'
    constraint perfiles_tipo_documento_check
    check (tipo_documento in ('DNI','CE','PASAPORTE'));

update public.perfiles
   set tipo_documento = 'CE'
 where dni ~ '^[0-9]{9,12}$'
   and tipo_documento = 'DNI';
