-- ============================================================================
-- PORTAL (excepción aprobada por Miguel, 2026-07-11): rol 'comercial'.
--
-- Única migración del ciclo CRM que toca un objeto de `public`, con OK
-- explícito. Motivo: el gate RLS de F0 demostró que un miembro del CRM
-- enrolado como 'analista' del portal hereda las policies del portal
-- (perfiles_analista_select / contratos_analista_select) y alcanza columnas
-- bancarias de clientes asignados. La fuerza de ventas necesita un rol de
-- portal NEUTRO: 'comercial' no aparece en ninguna policy → deny-by-default
-- (solo su propia fila vía perfiles_select). Mismo patrón aditivo ya usado
-- para 'analista' (2026-06-03) y 'directorio' (2026-06-06).
-- ============================================================================

alter table public.perfiles drop constraint perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol = any (array['cliente','analista','admin','superadmin','directorio','comercial']));
