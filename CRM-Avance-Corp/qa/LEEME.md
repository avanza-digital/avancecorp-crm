# qa/ — harness de calidad

Estado 2026-07-10: las pruebas de la APP ya no viven aquí — están en `app/`:

- **Unitarias/integración (120):** `app/src/**/*.test.{ts,tsx}` (Vitest) — mutaciones del
  store, ámbito por rol (espejo RLS), máquina de auth (carreras de logout/cambio de cuenta),
  API de leads contra Supabase simulado (MSW), validación compartida, formato, roles, router,
  observabilidad y seguridad. Gate: `npm run check` (cobertura sobre TODO `src`, umbrales
  anti-regresión).
- **E2E por rol (6):** `app/e2e/` (Playwright sobre la demo) — login por rol, navegación,
  kanban por teclado, focus-trap del drawer, write-gating del directorio. `npm run test:e2e`.

Esta carpeta queda para lo que exige la fase de DB (F5):

- `aislamiento-jerarquia.sql` — DO block con impersonación por claims JWT + iteración dinámica
  de tablas `crm.*` con RLS + ROLLBACK total: vendedor A no ve cartera de B; supervisor solo su
  subárbol; directorio lee todo y no escribe nada. (Adaptado de
  `crm-vitanova/qa/aislamiento-tenant.sql`, cambiando la dimensión tenant→jerarquía.)
- El gate RLS ejecutable contra un branch de Supabase vive en `../supabase/scripts/`
  (`test-rls.mjs` + preflight offline en CI).
