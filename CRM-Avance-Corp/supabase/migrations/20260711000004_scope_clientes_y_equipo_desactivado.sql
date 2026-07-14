-- ============================================================================
-- F0-fix (hallazgos del panel adversarial 2026-07-11): dos cierres de scope.
--
-- 1. [media, REGRESIÓN introducida por 000003] crm.clientes_basicos_fn tenía
--    como único gate "staff CRM o lector global" → CUALQUIER vendedor raso veía
--    nombre/DNI/correo/teléfono de TODOS los clientes del portal (139 reales en
--    prod). La vista original (security_invoker) scopeaba por cartera. Se
--    restaura el principio del plan: gerencia/directorio/admin ven todos; un
--    supervisor/vendedor solo ve clientes cuyo asesor está en su subárbol
--    (vendedor_ids_visibles). El dedup por DNI sigue disponible para todo el
--    staff vía crm.existe_cliente_por_dni (booleano, sin PII).
--
-- 2. [media] crm.equipo.equipo_select filtraba la fila PROPIA a un miembro
--    DESACTIVADO (rama self sin `activo`). Una fila CRM inactiva es revocación:
--    no debe leer su rol_crm/supervisor_id/creado_por. gerencia y supervisores
--    siguen viéndolo (rama vendedor_ids_visibles, que no filtra activo del lado
--    "visto") para poder reasignar su cartera.
-- ============================================================================

-- 1) clientes_basicos_fn: scope por cartera para no-globales
create or replace function crm.clientes_basicos_fn()
returns table (
  id uuid, nombres text, apellidos text, nombre_completo text, dni text,
  correo text, telefono text, asesor_perfil_id uuid, activo boolean,
  creado_en timestamptz
)
language sql stable security definer
set search_path = private, public
as $$
  select p.id, p.nombres, p.apellidos, p.nombre_completo, p.dni, p.correo,
         p.telefono, p.asesor_perfil_id, p.activo, p.creado_en
  from public.perfiles p
  where p.rol = 'cliente'
    and (
      (select private.es_lector_global())
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
      or p.asesor_perfil_id in (
           select private.vendedor_ids_visibles((select auth.uid()))
         )
    );
$$;

revoke all on function crm.clientes_basicos_fn() from public, anon;
grant execute on function crm.clientes_basicos_fn() to authenticated;

comment on view crm.clientes_basicos is
  'Clientes del portal SIN columnas bancarias, SCOPEADOS por cartera: lector global (directorio/admin/superadmin) y gerencia ven todos; supervisor/vendedor solo clientes cuyo asesor_perfil_id está en su subárbol; cualquier otro authenticated obtiene 0 filas. Vista invoker sobre crm.clientes_basicos_fn() (definer con gate).';

-- 2) equipo_select: la rama self exige activo = true
alter policy equipo_select on crm.equipo
  using (
    (perfil_id = (select auth.uid()) and activo = true)
    or perfil_id in (select private.vendedor_ids_visibles((select auth.uid())))
    or (select private.es_lector_global())
  );
