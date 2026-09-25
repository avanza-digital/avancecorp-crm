VERDICT:
CHANGES_REQUESTED

SUMMARY:
The horizontal gerencia integration looks sound in its main paths. The eight KPIs are rendered from `d.actual`, `d.ayer` and `d.referencia` independently of the team filters. Scope and identity keys are correct (`key={yo.id}`, query keys include actor, role and day). Authors outside the active org and the CSV path are preserved. Panel-portal persistence is reused unchanged.

One stated acceptance criterion is not fully met: "revoked access must not expose earlier data." The Hábitos tab and the embedded registro do not react to a denial detected elsewhere. There are also two focus-loss paths and a few minor issues. Nothing here touches SQL, RLS or the API.

(Note: this environment had plan mode active. Per the reviewer protocol I wrote no plan file and made no changes. This is the review only.)

FINDINGS:

[P1] Revocation detected by the pulso does not hide already-loaded Hábitos data
File: `CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx`
Lines: 64–69, 103–104; `data/gestion-diaria-pulso-queries.ts:23–29`
Problem: In the Hábitos tab, `error` only considers `habitos.error` (line 68). The pulso query stays enabled and polls (`refresco`, line 15 of queries). The Hábitos query has `refetchInterval: false` and `refetchOnWindowFocus: false`. If the session loses the gerencia permission while Hábitos is open, the pulso poll receives 42501, but line 104 keeps rendering `habitos.datos`. The only change is that `equipos` becomes `[]`, so every team collapses into "Equipo no disponible".
Evidence: line 68 `activa === 'habitos' ? habitos.error : …`; line 104 `equipos={pulso.datos?.equipos ?? []}`. The e2e revocation test (spec 162–177) only covers the Pulso tab.
Impact: Per-person hábitos data remains visible indefinitely after server-side revocation. This contradicts the requirement.
Recommendation: Derive a single `denegada` flag from `pulso.error`, `detalle.error` and `habitos.error` being `CrmApiError` with code 42501. Make it take precedence in every tab, so that `ErrorConsultaGerencia` renders and nothing else does. Add a unit test covering: Hábitos tab, pulso becomes 42501, then assert the table is gone.

[P2] A denial inside `RegistroActividad` does not propagate to the gerencia view
File: `components/gestion-diaria/espacio-pulso-gerencia.tsx`
Lines: 112, 157 (compare `registro-actividad.tsx:59, 115–123`)
Problem: `RegistroActividad` exposes `onSinPermiso` for exactly this case, but neither the general registro nor the team/analyst registro passes it. A 42501 from `registro_actividad_fn` clears only that list. KPIs, the teams table and the analyst summary stay visible until the next pulso poll (`INTERVALO_REGISTRO_MS`).
Impact: A partial leak window after revocation, and inconsistent behaviour compared with `detalle`, whose denial is already escalated (gerencia.tsx:67–69).
Recommendation: Pass `onSinPermiso` and have it trigger `pulso.recargar()`, or set a local denial flag consumed by the same `denegada` gate from the P1 finding.

[P2] Breadcrumb links inside the panel leave focus on `<body>`
File: `espacio-pulso-gerencia.tsx`
Lines: 115 (breadcrumb nav), 46, 87
Problem: "Toda la operación" and the team link in `gp-ruta` are plain anchors. Unlike `gp-volver` (line 87), they do not clear `oculto` or manage focus.
- Going to `#/gestion-diaria` makes `ruta` undefined. The panel then renders `vacio` (panel-gerencia.tsx:29), or on narrow widths the Radix dialog closes with `onCloseAutoFocus` prevented (panel-supervisor-adaptable.tsx:63). Either way the focused link unmounts and focus drops to body.
- Going to the team link while `oculto === 'equipo:X'` (after an earlier close) closes the panel for the same reason.
Evidence: e2e spec 132–133 clicks exactly this link on mobile and asserts only the URL, not focus.
Impact: Keyboard and screen-reader users lose their position. The approved UX requires focus return.
Recommendation: Route both links through handlers equivalent to `gp-volver` / `abrirEquipo`: clear or set `oculto`, then use `devolverFoco` or focus `tituloTabla`. Assert focus in the mobile e2e.

[P3] Focus origin is recorded as `document.activeElement`, which can be `<body>` in WebKit
File: `reporte-habitos.tsx:90`; `espacio-pulso-gerencia.tsx:53–60`
Problem: On a mouse click, Safari does not focus buttons, so `origen.current` becomes `body`. On close, `destino` is `body`, `focus()` is a no-op, and `document.activeElement === destino`, so the `tituloTabla` fallback never runs.
Impact: Focus is not restored in WebKit (the WebKit run is still pending).
Recommendation: Record `event.currentTarget` in the click handlers. Alternatively, treat `document.body` as "no origin" in `recordarOrigen` and at line 90.

[P3] A team opened on narrow widths stays hidden after widening
File: `espacio-pulso-gerencia.tsx`
Lines: 71, 46
Problem: `abrirEquipo` sets `oculto = equipo:X` when `estrecho` is true. If the window is then widened, the desktop panel keeps showing "Elige un equipo…" even though a team is selected and its analysts table is visible.
Recommendation: Ignore `oculto` for team routes when `!estrecho`, or clear it on the transition from narrow to wide.

[P3] The general registro keeps polling while hidden
File: `espacio-pulso-gerencia.tsx:111–112`
Problem: After the first visit (`generalVisitado`), `RegistroActividad` for the whole operation stays mounted with `hidden`/`inert` and keeps its query active. That is intentional for state preservation, but it adds background load for the whole operation.
Recommendation: Either accept this and document it, or confirm that the registro query pauses when hidden.

TEST GAPS:
- Hábitos tab with pulso (or detalle) returning 42501: data must disappear. Not covered in unit or e2e tests.
- 42501 from `registro_actividad_fn` inside the gerencia view.
- Focus after the breadcrumb links (desktop and dialog), and after mouse-close in WebKit.
- Changing the Hábitos period (`key={dia}:${dias}`) resets search, team filter and selection. Assert this is intended, or preserve the filters.
- Hábitos team labels while pulso is loading or errored (all rows show "Equipo no disponible").
- The WebKit suite and the full Chromium suite are still pending. Closure must not be declared until they run.

SECURITY RISKS:
- Client-side exposure after revocation only (P1/P2). Server scope is unchanged: `useDetallePulso` still sends `p_supervisor_id` undefined/null (e2e line 40), and RPC/RLS are untouched.

REGRESSION RISKS:
- Low for the supervisor view. `PanelSupervisorAdaptable` and `RegistroActividad` are reused unchanged.
- `EspacioPulsoGerencia key={dia}` drops per-team filters when the date changes. This matches "date changes retire stale data" but should be stated in the docs.

RECOMMENDED NEXT ACTIONS:
1. Add a unified 42501 gate across the pulso, detalle, hábitos and registro paths (P1 and first P2), with unit tests.
2. Fix breadcrumb focus handling and the body-as-origin issue, then extend the mobile e2e with focus assertions.
3. Finish the WebKit and full Chromium runs before closure. The removal of Seguimiento stays gated on seven stable production days.

CONFIDENCE:
MEDIUM. The main findings follow directly from the supplied lines. I did not see `protegerEscapeAnidado`, `Tabs`, `TablaEquipoDiaria`, or the remainder of `registro-actividad.tsx`.
