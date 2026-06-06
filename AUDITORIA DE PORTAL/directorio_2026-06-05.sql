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
-- (pendiente — se añade al aplicar la Tarea 2)

-- ---------- Migración 3: directorio_rpc_detalle ----------
-- (pendiente — se añade al aplicar la Tarea 3)
