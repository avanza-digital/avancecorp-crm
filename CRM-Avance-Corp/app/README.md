# CRM Avance Corp — app web

App del CRM comercial (Vite + React 19 + TypeScript estricto + Tailwind v4 + TanStack Query
+ supabase-js). En F1 corre en **modo demo** (datos ficticios en memoria/sessionStorage);
la autenticación contra Supabase es real y el rol sale de `crm.equipo`.

## Comandos

| Comando | Qué hace |
| --- | --- |
| `npm run dev` | Dev server en `:5173` (demo con `VITE_ENABLE_DEMO=true` en `.env`) |
| `npm run check` | **El gate**: lint (oxlint + jsx-a11y) + typecheck + tests con cobertura |
| `npm run test` / `test:run` | Vitest (unitarios/integración, 120 tests) |
| `npm run test:e2e` | Playwright: smoke E2E por rol sobre la demo (primera vez: `npx playwright install chromium`) |
| `npm run build` | `tsc -b` + build de producción (los fixtures demo quedan FUERA del bundle) |
| `npm run dup` | jscpd: detector de copy-paste sobre `src` |
| `npm run gen:types` | Regenera `src/lib/database.types.ts` desde Supabase (requiere `supabase login`) |

`npm install` instala también los hooks de git (Lefthook: lint+typecheck en pre-commit,
tests en pre-push — solo cuando el commit toca esta app).

## Config (`.env`, ver `.env.example`)

- `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` — proyecto del portal (fail-closed: claves
  privilegiadas se rechazan).
- `VITE_ENABLE_DEMO` — solo surte efecto en `npm run dev`; producción lo ignora.
- `VITE_SENTRY_DSN` — opcional; vacío = observabilidad solo en consola y el chunk de Sentry
  ni se descarga. Con DSN, los eventos pasan por el scrub de PII propio antes de salir.

## Dónde vive cada cosa

- `src/lib/tipos.ts` — catálogos del dominio (fuente única: etapas, orígenes, categorías) de
  los que se derivan tipos, sets runtime y labels. `src/lib/semaforo.ts` — paleta única.
- `src/lib/inteligencia.ts` — cálculos comerciales PUROS por rol (cola, métricas, capital
  por moneda, embudo). Las pantallas consumen de aquí, no reimplementan.
- `src/lib/store.tsx` — store demo write-gated; espejo cliente de la RLS jerárquica
  (`ambito`), validación compartida (`validacion.ts`) y errores con `codigo`/`campo`.
- `src/lib/auth-maquina.ts` — máquina XState del acceso (cancela verificaciones en vuelo:
  sin carreras en logout/cambio de cuenta). `auth.tsx` es el wrapper React.
- `src/lib/database.types.ts` + `src/data/crm-api.ts` — frontera Supabase tipada y validada
  en runtime (Valibot): filas fuera de contrato se registran y descartan.
- `e2e/` — smoke Playwright por rol (login demo, navegación, teclado, focus-trap).
