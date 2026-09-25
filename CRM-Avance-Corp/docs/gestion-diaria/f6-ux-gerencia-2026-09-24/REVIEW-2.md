VERDICT:
PASS

SUMMARY:
The accepted findings are resolved in the supplied source. No mandatory changes remain within this scope.

- **Sticky denial.** The view-level 42501 gate is correctly sticky (`gerencia.tsx:57-58, 73-75`). It takes precedence in both tabs (line 110), and it survives tab, date and refetch transitions because `VistaGerencia` is only remounted by `key={yo.id}`. Both registro readers feed it through `onSinPermiso={sinPermiso}` (`espacio-pulso-gerencia.tsx:130, 175`). "Verificar sesión" only calls `window.location.reload()` (`error-consulta-gerencia.tsx:8`), so a cached failed query cannot dismiss the gate.
- **Breadcrumbs.** Both now go through handlers: `volverOperacion` at 87-92, and `abrirEquipo(grupo, e.currentTarget)` at 133.
- **Mouse-origin in WebKit.** Origins now come from `currentTarget`, and `body` is excluded (`espacio-pulso-gerencia.tsx:61-64`, `comparacion-equipos-gerencia.tsx:56`, `reporte-habitos.tsx:90`).
- **Narrow-to-wide.** The transition clears `oculto` for team routes (51-55).

The items below are advisory. One is a timing hypothesis that the pending WebKit run should confirm or refute.

(Plan mode was signalled in this environment. Per the reviewer protocol I wrote no plan file and made no changes.)

FINDINGS:

[P2] Breadcrumb focus on narrow widths relies on rAF running after the hashchange commit (hypothesis)
File: `components/gestion-diaria/espacio-pulso-gerencia.tsx`
Lines: 84-85, 90-91; `panel-supervisor-adaptable.tsx:42-46, 63`
Problem:
- Both handlers assign `window.location.hash` and then schedule `requestAnimationFrame(() => tituloTabla.current?.focus())`.
- The route store only re-renders on the `hashchange` event (`gerencia.tsx:32, 61`), and that event is dispatched as a queued task.
- If the animation frame runs before that task, the dialog is still modal on narrow widths. `tituloTabla` sits outside `Dialog.Content`, so Radix's trapped focus scope pulls focus back inside.
- The dialog then closes in the hash-driven commit. `onCloseAutoFocus` is prevented, and `focoInterno` (the breadcrumb link) has unmounted, so it fails `isConnected`. Focus would end on `<body>`.
Evidence: The ordering between the task and rAF is not guaranteed by spec. The Chromium e2e passes (spec 133-135), which is consistent with Chromium usually flushing the task first. The 9-case WebKit run is still pending.
Impact: Keyboard and screen-reader users could lose their position after a mobile breadcrumb, in some engines or under load.
Recommendation: If WebKit or repeated runs show flakiness, focus after the commit rather than on a timer. For example, set a `focoPendiente` ref in the handler and consume it in a `useLayoutEffect` keyed on `clave`/`abierto`. Alternatively, update the route store synchronously before focusing. If WebKit passes, leave the code as is.

[P3] Focus is lost when the denial gate replaces focused content
File: `screens/gestion-diaria/gerencia.tsx:110`
Problem: A denial can arrive while focus is inside the content that unmounts, for example the registro "Actualizar" button (spec 290). When that content is replaced by `ErrorConsultaGerencia`, focus drops to `<body>`. `role="alert"` announces the message but gives no focus target.
Recommendation: When `revocada` becomes true, move focus to "Verificar sesión" or to a `tabIndex={-1}` heading, but only if `document.activeElement` is `body` or disconnected. Add a focus assertion to spec 291.

[P3] Queries keep running while the view is denied
File: `gerencia.tsx:67-69`
Problem: After `revocada`, the pulso keeps polling. Switching to Hábitos enables `useHabitosGerencia` (`activa === 'habitos'`), which sends a request whose result can never be shown. The period `Select` (line 109) also stays interactive and triggers further requests.
Impact: The requests are wasteful and repeatedly return 403 to the server. There is no data exposure.
Recommendation: Pass `enabled && !revocada` to the hooks, and hide the period control when `sinPermiso` is true. This is optional.

[P3] Clicking "Ver pulso y registro" with a modifier key still switches tabs
File: `reporte-habitos.tsx:117`
Problem: `onClick={alAbrirAnalista}` runs even on ctrl- or cmd-click. The current window switches to Pulso while the link also opens in a new tab. The other anchors guard with `navegarEnVentana`. This likely predates the current fixes.
Recommendation: Apply the same modifier guard.

TEST GAPS:
- The unit tests mock `RegistroActividad` (`gerencia.test.tsx:21`), so the real `onSinPermiso` invocation is not exercised there. The only real-component coverage is the general-registro e2e (spec 284-300), and there is no e2e for 42501 from the scoped (team/analyst) registro. If `RegistroActividad` calls `onSinPermiso` during render instead of in an effect, React will warn about updating a parent while rendering a child. I could not verify this because the source was not supplied.
- No unit assertion that the denial persists after a date change (`cambiarDia`). Only the tab switch is covered (test 158-169).
- No focus assertion after the team breadcrumb (`abrirEquipo` from `gp-ruta`) on desktop or narrow widths.
- The narrow-to-wide e2e (spec 302-308) checks only visibility. It does not check that no dialog remains or where focus ends up.
- The WebKit 9-case run and the final full suite are still pending and are required before closure, as you stated.

SECURITY RISKS:
- None new. The gate is client-side presentation only, and server-side RPC/RLS scope is unchanged. After "Verificar sesión", data reappears only if the server authorizes the fresh queries. If only the registro is revoked, the pulso will render again until a registro request is denied again. That is correct, because the server is the source of truth. This assumes the query cache is in-memory, not persisted to storage, as you stated; I have not seen the query client configuration.

REGRESSION RISKS:
- Low. `PanelSupervisorAdaptable`, `Tabs` and the supervisor view are unchanged.
- Calling `setRevocada` during render (line 74) is the supported derived-state pattern and cannot loop, because it is guarded by `!revocada`.

RECOMMENDED NEXT ACTIONS:
1. Run the 9-case WebKit suite. If the mobile breadcrumb focus is flaky, switch to focus-after-commit (P2).
2. Optionally move focus to "Verificar sesión" on denial and pause queries while `revocada` (P3).
3. Add e2e coverage for a scoped-registro 42501, and run the final full check before closure. Document the reset of Hábitos filters on date or period change, and the accepted hidden registro polling.

CONFIDENCE:
MEDIUM. The fixes follow directly from the supplied source. The P2 finding is a timing hypothesis. I did not see `RegistroActividad`, the query hooks, `PanelGerencia`, `TablaEquipoDiaria` or the query client configuration.
