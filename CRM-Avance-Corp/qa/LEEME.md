# qa/ — harness de calidad

## Checklist go/no-go (evidencia local, ~3 min)

Correr desde `CRM-Avance-Corp/app/`. Todo debe dar lo indicado; cualquier
desviación es no-go:

| # | Comando | Evidencia esperada |
| --- | --- | --- |
| 1 | `npm run check` | exit 0 — lint sin avisos, typecheck limpio, `Tests 120 passed`, cobertura ≥ umbrales |
| 2 | `npm run test:e2e` | `6 passed` (primera vez: `npx playwright install chromium`) |
| 3 | `npm run build` | `✓ built` y SIN chunk `demo` en `dist/assets/` |
| 4 | `npm run dup` | `Found 1 clones.` (o menos) |
| 5 | `git log --oneline -7` | commits `be66b58…c760240` del pago de deuda 2026-07-10 |
| 6 | `npx lefthook run pre-commit` | `crm-lint` y `crm-typecheck` en ✔️ |

> **Nota sobre el KPI de tests (aclara el "amarillo" del check 2026-07-10):**
> un escaneo estático cuenta ~100 declaraciones `it(`/`test(` en unit y 3 en
> E2E; el runner ejecuta **120 unit + 6 E2E** porque varios tests son
> parametrizados (`it.each` sobre roles, tablas de casos, y el `for` de roles
> en E2E: 1 declaración → N tests). La cifra canónica es la del runner
> (`vitest run` / `playwright test --list`), que es lo que puede fallar.

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
