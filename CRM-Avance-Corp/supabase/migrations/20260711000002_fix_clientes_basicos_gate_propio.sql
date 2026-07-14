-- ============================================================================
-- F0-fix: crm.clientes_basicos con gate propio (2026-07-11)
--
-- Hallazgo del gate RLS en el branch: al mover la fuerza de ventas al rol de
-- portal 'comercial' (deny-by-default, migración 20260711000001), la vista
-- security_invoker quedaba VACÍA para el staff del CRM — las policies de
-- public.perfiles ya no les conceden filas de clientes (eso era justo lo que
-- cerramos). Se reemplaza por una vista de OWNER (postgres, bypassa la RLS del
-- portal SOLO dentro de la vista) con gate explícito: staff CRM activo o
-- lector global — espejo del gate de crm.existe_cliente_por_dni.
--
-- Sigue sin exponer columnas bancarias; anon sigue sin usage en el esquema;
-- un cliente del portal (u otro authenticated sin rol CRM) obtiene 0 filas.
-- ============================================================================

drop view crm.clientes_basicos;

create view crm.clientes_basicos as
select id, nombres, apellidos, nombre_completo, dni, correo, telefono,
       asesor_perfil_id, activo, creado_en
from public.perfiles
where rol = 'cliente'
  and ((select private.rol_crm((select auth.uid()))) is not null
       or (select private.es_lector_global()));

comment on view crm.clientes_basicos is
  'Clientes del portal SIN columnas bancarias. Vista de owner con gate propio: solo staff CRM activo o lector global (directorio/admin/superadmin); cualquier otro authenticated obtiene 0 filas.';

grant select on crm.clientes_basicos to authenticated;
