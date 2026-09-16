# CRM Avance Corp — memoria del subproyecto

CRM interno de Avance Corp. Deploy en **crm.miavance.com** (Hostinger). Comparte el
proyecto Supabase del portal (`dctqcbznekcyxhjujuci`) con esquema **`crm`** dedicado.

## Idioma y estilo

- **Todo en español**: identificadores, comentarios, commits, docs. SQL en snake_case español.
- Commits estilo `CRM: <resumen imperativo>` (o `CRM C1:` etc. cuando hay fase).
- Diseño: navy `#111e3d` + azul `#2563eb`, tema claro, Plus Jakarta Sans, sin verde.
- Soft-delete `activo = false`, nunca hard-delete.

## Mapa del código

| Ruta | Qué es |
|------|--------|
| `app/` | Front: React 19 + TS + Vite + Tailwind 4 + TanStack Query + XState + Valibot |
| `app/src/lib/` | Dominio y lógica pura (cada módulo con su `.test.ts` al lado) |
| `app/src/screens/` | Pantallas por rol (comercial / coordinador / gerencia) |
| `app/e2e/` | Specs Playwright (smoke por rol, modo demo) |
| `supabase/migrations/` | Migraciones del esquema `crm` + ledger `MIGRACIONES.md` |
| `supabase/scripts/` | `test-rls.mjs` (matriz RLS), `seed-demo.mjs`, fixtures |
| `supabase/functions/` | Fuentes versionadas de las Edge Functions propias del CRM |
| `scripts/` | `crear-artefacto-release.mjs` (ZIP + manifiesto SHA-256), Apps Script de leads |
| `../../_supabase_functions/functions/` | Edges compartidas/legadas del portal; los espejos CRM deben quedar byte a byte iguales |

## Comandos

- En `app/`: `npm run check` (oxlint + typecheck + coverage) · `npm run test:e2e` · `npm run gen:types`
- En raíz CRM: `npm run test:rls:preflight` · `npm run seed:preflight` · `npm run release:crm`
- Gates ya montados (no duplicar): Lefthook pre-commit (lint+typecheck) y pre-push (tests);
  CI GitHub Actions `crm-app-quality` y `crm-rls-preflight`.
- Los Apps Script (`scripts/*.gs`) van dentro de `npm run check:scripts`: gate de llamadas
  huérfanas, las dos suites del puente y **`npm run test:mutantes`** — por cada defensa, un
  mutante que la neutraliza; si sobrevive, esa defensa NO está probada y el gate falla.

## ⚠️ El gate de REALIDAD (`npm run gate:realidad`) — correr ANTES de arreglar una pantalla

Tres veces en dos días un cambio pasó el gate entero (1.500+ tests, e2e, RLS) y **no
hizo nada en producción**, siempre por la misma razón: los tests montan el mundo del
FIXTURE (metas publicadas, cartera poblada, gate de leads abierto) y producción es
otro mundo. El bug no estaba en el código: estaba en el mundo que el código asumía.

`supabase/scripts/gate-realidad.mjs` mide esa distancia y dice, por cada supuesto
incumplido, **qué pantallas se están probando hoy contra un mundo que no existe**.
Al 2026-08-10 fallan 4 de 5: sin metas publicadas, 1 lead, 0 actividades, 0 tareas.

**Regla:** antes de dar por bueno un arreglo de UI, escribe el test **en el estado
que hay en producción** (el vacío/degradado), no solo con el fixture lleno. Si el
arreglo depende de un dato que en prod no existe, no es un arreglo. El caso canónico
está en `screens/hoy/vendedor.test.tsx` («ESTADO DE PRODUCCIÓN (sin metas publicadas)»).

## Reglas de migraciones (no negociables — detalle en `supabase/migrations/LEEME.md`)

- **Nunca editar una migración ya commiteada**: se crea una nueva (`/nueva-migracion`).
- Formato `AAAAMMDDHHMMSS_crm_<tema>.sql`; ledger `MIGRACIONES.md` SIEMPRE actualizado.
- Ciclo: **branch de Supabase → aplicar → gate `test-rls.mjs` → advisors → merge**.
  Prohibido `apply_migration` directo a producción.
- Ninguna migración del CRM toca objetos de `public` (portal en prod) sin OK explícito de Miguel.
- RLS ON en el mismo statement de creación; deny-by-default; sin policy DELETE.
- ⚠️ `crm.leads` tiene **grants POR COLUMNA**: toda columna nueva necesita sus
  `GRANT SELECT/INSERT/UPDATE` explícitos o PostgREST la ignora en silencio.
- Tras cambios de esquema: `npm run gen:types` en `app/` para regenerar `database.types.ts`.

## Accesibilidad

`.oxlintrc.json` apaga 5 reglas de jsx-a11y por falsos positivos **documentados** (cards con
`role=button` + teclado, combobox WAI-ARIA — rol correcto Y elemento no interactivo—,
`autoFocus` solo en modales). No apagar reglas
nuevas por comodidad; los componentes nuevos deben respetar esos mismos patrones
(revisión: subagente `revisor-a11y`).

## Seguridad / RLS

Tres roles con visibilidad distinta (comercial / coordinador / gerencia), PII de leads
(DNI, fecha de nacimiento, género) y ledger inmutable de asignaciones. Toda migración que
toque policies, funciones o grants pasa por el subagente `auditor-rls` antes del gate.

## Deploy

`npm run release:crm` genera ZIP + manifiesto SHA-256 en `releases/` (no versionado).
La publicación a crm.miavance.com se hace SOLO vía el skill de release, con
invocación humana: `/release-crm` en Claude o `$release-crm` en Codex. El modelo
no puede auto-invocarlo. La adaptación de Codex está en
[`.agents/skills/release-crm/SKILL.md`](../.agents/skills/release-crm/SKILL.md);
ambas invocaciones autorizan el mismo flujo, sin pedir el comando del otro entorno.
