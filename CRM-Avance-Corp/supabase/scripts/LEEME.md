# supabase/scripts/ — seed y verificación

**Vacía a propósito** (se llena en F0).

- `test-rls.mjs` — suite de RLS con logins reales (anon key) para los 4 roles CRM
  (vendedor/supervisor/gerencia/directorio) + los 5 del portal: verifica visibilidad exacta,
  aislamiento entre subárboles, directorio sin escritura, y que vendedor NO lee contratos ni
  columnas bancarias. Es el **gate** de cada merge de migraciones. (Adaptado de
  `crm-vitanova/supabase/scripts/test-rls.mjs`.)
- `seed-demo.mjs` — usuarios demo de la jerarquía (1 gerencia, 2 supervisores, 4 vendedores,
  1 directorio) vía service_role, solo en branch/staging.
