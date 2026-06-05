-- ============================================================================
-- FUSIÓN ASESOR → ANALISTA  ·  LIMPIEZA FINAL (paso de BD)
-- ============================================================================
-- Proyecto: Portal Avance Corp · Supabase ref dctqcbznekcyxhjujuci
-- Escrito: 2026-06-05
--
-- QUÉ HACE: elimina por completo el rastro de la tabla `asesores` de la base de
-- datos, una vez que el asesor de cada cliente ya es un ANALISTA del equipo
-- (columna perfiles.asesor_perfil_id).
--
-- ⚠️ NO EJECUTAR HASTA QUE:
--   1) Existan los 3 analistas nuevos (Miguel, Carmen, Lisseth).
--   2) Los 5 clientes que tenían de asesor a "MIGUEL BRICEÑO" estén reasignados
--      al analista Miguel (por la pantalla de Clientes → "Asignar analista", o por
--      el PASO 1 de abajo).
--   3) El frontend nuevo (clientes.js v29, etc.) y la edge importar-clientes estén
--      desplegados.
--
-- Es REVERSIBLE hasta el DROP final: hace un respaldo de la tabla antes de borrarla.
-- Ejecutar de arriba hacia abajo. (Recomendado: revisarlo con Claude antes de correr.)
-- ============================================================================


-- ── PASO 1 (opcional) · Reasignar los clientes legacy que falten ────────────
-- Solo si quedan clientes con asesor_id (tabla vieja) y sin analista nuevo.
-- Reemplaza <ID_ANALISTA_MIGUEL> por el id de perfil del analista Miguel
-- (lo obtienes con:  select id, nombre_completo from perfiles
--                    where rol in ('analista','admin','superadmin') order by 2; )
--
-- UPDATE public.perfiles
--   SET asesor_perfil_id = '<ID_ANALISTA_MIGUEL>', asesor_id = NULL
--   WHERE rol = 'cliente' AND asesor_id IS NOT NULL AND asesor_perfil_id IS NULL;


-- ── PASO 2 · Verificación de seguridad (NO debe quedar nadie colgado) ───────
-- Si esto devuelve > 0, NO continúes: hay clientes con asesor viejo sin migrar.
SELECT count(*) AS clientes_legacy_sin_migrar
FROM public.perfiles
WHERE rol = 'cliente' AND asesor_id IS NOT NULL AND asesor_perfil_id IS NULL;


-- ── PASO 3 · Respaldo de la tabla asesores (por si acaso) ───────────────────
CREATE TABLE IF NOT EXISTS public.asesores_backup_fusion_20260605 AS
  SELECT * FROM public.asesores;


-- ── PASO 4 · Simplificar obtener_mi_asesor (quitar la rama legacy) ──────────
-- Debe ir ANTES de borrar la tabla `asesores` (la función la referencia).
CREATE OR REPLACE FUNCTION public.obtener_mi_asesor()
RETURNS TABLE(nombre_completo text, whatsapp text, correo text, telefono text, cargo text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid           uuid := auth.uid();
  v_asesor_perfil uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  SELECT p.asesor_perfil_id INTO v_asesor_perfil
    FROM public.perfiles p WHERE p.id = v_uid;

  IF v_asesor_perfil IS NOT NULL THEN
    RETURN QUERY
      SELECT a.nombre_completo, a.whatsapp, a.correo, a.telefono, a.cargo
      FROM public.perfiles a
      WHERE a.id = v_asesor_perfil AND a.activo;
  END IF;
END;
$function$;

-- Mantener el endurecimiento de permisos (solo usuarios autenticados).
REVOKE EXECUTE ON FUNCTION public.obtener_mi_asesor() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.obtener_mi_asesor() TO authenticated;


-- ── PASO 5 · Quitar la columna legacy y la tabla ────────────────────────────
-- Al quitar la columna se elimina su FK a `asesores`; luego ya nada referencia
-- la tabla y se puede borrar.
ALTER TABLE public.perfiles DROP COLUMN IF EXISTS asesor_id;
DROP TABLE IF EXISTS public.asesores;   -- arrastra sus triggers y policies


-- ── PASO 6 · Verificación final ─────────────────────────────────────────────
-- (a) la tabla ya no existe:
SELECT to_regclass('public.asesores') AS asesores_existe;      -- esperado: NULL
-- (b) la columna ya no existe:
SELECT count(*) AS columna_asesor_id_existe
FROM information_schema.columns
WHERE table_schema='public' AND table_name='perfiles' AND column_name='asesor_id';  -- esperado: 0
-- (c) todo cliente con asesor lo tiene por el modelo nuevo:
SELECT count(*) AS clientes_con_analista
FROM public.perfiles WHERE rol='cliente' AND asesor_perfil_id IS NOT NULL;

-- FIN. (El respaldo `asesores_backup_fusion_20260605` queda por si hace falta;
--  se puede borrar más adelante con: DROP TABLE public.asesores_backup_fusion_20260605; )
