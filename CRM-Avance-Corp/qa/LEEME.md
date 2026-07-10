# qa/ — harness de calidad por rol

**Vacía a propósito** (se llena en F5, con smoke tests desde F1).

- Harness de UI por rol (Maestro sobre la app nativa, o Playwright sobre el build web de Expo):
  matriz rol×capacidad derivada de `roles.ts`, aserciones simétricas (presencia para staff Y
  ausencia para vendedor/directorio), captura de errores, read-only contra datos compartidos,
  exit code ≠ 0 si algo falla. (Patrón de `crm-vitanova/qa/qa-vite.mjs`.)
- `aislamiento-jerarquia.sql` — DO block con impersonación por claims JWT + iteración dinámica
  de tablas `crm.*` con RLS + ROLLBACK total: vendedor A no ve cartera de B; supervisor solo su
  subárbol; directorio lee todo y no escribe nada. (Adaptado de
  `crm-vitanova/qa/aislamiento-tenant.sql`, cambiando la dimensión tenant→jerarquía.)
