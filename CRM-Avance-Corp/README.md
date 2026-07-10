# CRM-Avance-Corp

CRM interno de **Avance Corp S.A.C.** (grupo MasCapital) para la fuerza comercial:
jerarquía **vendedor → supervisor → gerencia → directorio/auditoría**, sobre el dominio de
inversiones (contratos de Asociación en Participación, PEN/USD).

## Qué es esta carpeta

El proyecto del CRM, creado en el encargo **P-054** (2026-07-09). Contiene la **app web
funcional en modo demo** (F1: paneles por rol, kanban, ficha de lead, alta, búsqueda,
inteligencia comercial), la migración del esquema `crm`, y los gates de calidad
(lint estricto + typecheck + 120 tests unitarios + 6 E2E por rol + cobertura sobre todo `src`).

- **`PLAN-CRM-AVANCE-CORP.md`** ← EMPEZAR POR AQUÍ. Inventario, matriz de clasificación,
  decisión arquitectónica, reconciliación y fases.
- **`docs/recon/`** — 10 informes técnicos del reconocimiento multi-agente (citas archivo:línea).
- **`app/`** — la app web del CRM (Vite + React 19 + TS + Tailwind v4). `npm run dev` → :5173.
- **`supabase/`** — migraciones del esquema `crm`, edge functions `crm-*` y scripts de test RLS.
- **`qa/`** — harness de QA por rol y prueba de aislamiento jerárquico.

## De dónde viene

Se reutiliza como **esqueleto arquitectónico** el CRM VITANOVA de Clínica Álvarez
(`avanzadigitald/cliente-clinica-alvarez`, copia local en
`AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/`): auth, jerarquía de roles, patrón RLS,
estructura de módulos y patrones de UI — **NO su modelo de datos** (clínico) ni su capa de
datos frontend (ver deuda técnica en `docs/recon/07`). Política de la casa: el repo fuente es
**referencia de solo lectura; se copia/adapta, nunca se modifica**.

## Decisiones ya tomadas (ver sustento en el plan)

- **Mismo proyecto Supabase que el portal** (`dctqcbznekcyxhjujuci`), esquema `crm` dedicado,
  con 7 condiciones no negociables (§5 del plan).
- **Plataforma (P-055):** "web ahora, app después" — **Vite + React 19 + TS + Tailwind v4**
  + TanStack React Query + supabase-js (la variante Expo queda para una fase futura).
- **Deploy:** subdominio **`crm.miavance.com`** en Hostinger (build de Vite `app/dist/`,
  publicado vía API de Hostinger por MCP, igual que el portal).
- **Diseño:** navy `#111e3d` + azul `#2563eb`, fondo blanco, tema claro, sin verde,
  Plus Jakarta Sans. Español snake_case. Soft-delete `activo = false`, nunca hard-delete.

## Estado

🔨 **P-055 en curso** (plan aprobado 2026-07-09). Hecho: F1 de UI en modo demo con login real
(rol vía `crm.equipo`), rediseño a calidad VITANOVA con el logo real, el sprint "CRM vivo"
(ficha de lead, alta, kanban interactivo, búsqueda) y el **pago de deuda técnica de la
auditoría 2026-07-10** (ver nota del vault `Deuda técnica CRM fuera de DB 2026-07-10`):
auth con máquina de estados XState (carrera de logout cerrada), frontera Supabase tipada y
validada en runtime (Valibot), dominio centralizado sin duplicaciones, accesibilidad real en
modales (Radix) y teclado en el kanban, gate de cobertura sobre todo `src`, E2E por rol con
Playwright, hooks de pre-commit/pre-push (Lefthook) y Sentry opcional con scrub de PII.
Pendiente: aplicar el SQL de F0 en un branch de Supabase (`supabase/migrations/`), conectar
datos reales y desplegar a `crm.miavance.com`.
