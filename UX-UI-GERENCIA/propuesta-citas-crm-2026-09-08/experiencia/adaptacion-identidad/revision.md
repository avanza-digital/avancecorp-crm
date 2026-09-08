# Revisión técnica de la adaptación al CRM

2026-09-08. LEVEL 2. Codex PRIMARY; Claude SECONDARY_REVIEWER mediante `scripts/claude-review`, herramientas y edición deshabilitadas. El primer arranque no completó la revisión dentro del sandbox; el reintento autorizado entregó un dictamen completo. Una consulta entregada, sin segunda cadena de revisión.

## Evaluación del PRIMARY

Claude devolvió CHANGES_REQUESTED. Sus hallazgos condicionados a componentes que no recibió no se tratan como defectos confirmados. Codex consultó las implementaciones compartidas mediante CodeGraph y evaluó las capturas y pruebas del navegador.

- **Progreso superior a 125%:** descartado como defecto. `components/ui/progress.tsx:13` limita internamente a 0–100 con `Math.max(0, Math.min(100, value))`; además el track tiene overflow-hidden. Se conserva el porcentaje real explícito y una barra saturada al objetivo. No se duplica el clamp en el consumidor.
- **Semántica de la ficha:** aceptado como simplificación de accesibilidad. Se retiran aria-expanded/aria-controls y el anuncio de fondo heredados del inspector. Los botones ahora declaran aria-haspopup=dialog y el propio Sheet anuncia su título.
- **Clase vacía y prueba repetida:** eliminada la clase citas-espacio-trabajo. Se sustituye la parametrización modal/no modal por una sola prueba del comportamiento vigente. Quedan 31 pruebas del prototipo, sin perder un escenario funcional distinto.
- **Menú, contexto y movimiento:** verificados. Sidebar devuelve aside directamente, posee colapso y riel móvil propios, sin dependencia de Topbar. AuthContext importa createContext/useContext y tipos solamente; no monta servicios. Sheet incluye una regla de movimiento reducido para panel y overlay en sus líneas 12–14.
- **Filtros:** minmax(0, …) en las columnas y paso a dos filas hasta 1450 px, conservando anchos de lectura. Se añaden 1366 px a la prueba de 1280/1024/768/390.
- **Foco:** scroll-margin-top 64 px en la consulta. Regiones horizontales con tabIndex 0 y prueba de desplazamiento con flecha. Comentarios locales de lint explican por qué una región desplazable necesita foco. La celda de cumplimiento usa como nombre solo el valor, sin repetir el encabezado.
- **Tokens:** el fondo de la barra usa el token muted. Se mantiene el patrón de marcador en 100% sobre escala 125%.
- **Transición entre fichas:** no se introduce un cambio especulativo en el componente compartido. Sheet restaura foco en requestAnimationFrame (línea64); el consumidor existente espera dos frames. La transición recorrido→cita→agenda pasa en Chromium y en la prueba de foco. Debe revisarse de nuevo si cambia el contrato de cierre del Sheet.
- **BASE_URL y publicación:** las rutas absolutas corresponden al servidor local de la vista independiente y abren el CRM en su raíz. La integración/publicación bajo otra base está fuera de este pedido. No se añade lógica de sesión ni se modifica autorización real.

No se solicita otro review solo para obtener PASS. El cierre se fundamenta en código, gates y pruebas de navegador posteriores; la apariencia queda a revisión de Miguel.

## Dictamen recibido

VERDICT:
CHANGES_REQUESTED

SUMMARY:
The visual re-skin is coherent and the business math shown in the diff checks out (40/26 → 1.538 → 51.3%; 2/3 → 66.7%; bar scale 125% → marker at 80%). Two things need fixing before this is done: the fulfillment `Progress` has no upper clamp on a scale the module itself documents as exceedable, and the removal of the non-modal sheet left disclosure semantics (`aria-expanded` / `aria-controls` / a background `role="status"`) behind that are now wrong for an always-modal dialog. Several further items are verification requests I cannot resolve without repository access — they are marked as such rather than asserted.

Note on scope: I have only the six files and the scoped diff you attached. I could not read `sidebar.tsx`, `auth-context.ts`, `ui/progress.tsx`, `ui/sheet.tsx`, `gerencia.css`, `vistas.tsx`, `metas.ts` or `datos.ts`, so findings that depend on them are stated as hypotheses with the exact check to run.

FINDINGS:

**[P1] Fulfillment bar is unclamped on a scale the same file documents as exceedable**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/resultados.tsx`
Lines: 63 (bar), 17 (help text)

Problem:
`value={(fila.cumplimiento ?? 0) / OBJETIVO_CUMPLIMIENTO * 100}` maps 125% → 100 with no upper bound.

Evidence:
`AyudaMetricas` in the same file, line 17, states: *"Cada lead tiene citas enteras: 3 citas son 100% y 4 son 133.3%."* An analyst averaging 4 citas/lead therefore yields `value = 106.6`; a single-lead filtered view yields the same. `DetalleLeads` (line 83) surfaces per-lead percentages on the same scale. Whether this overflows depends on `ui/progress.tsx`: if it clamps internally, this is a non-issue; if it applies `width: value%` or `translateX`, the indicator escapes the 100px–280px `.citas-barra-meta` track (`presentacion.css:83-85`) and can visually pass the "Meta 100%" marker at `left: 80%` in a way that no longer means anything.

Impact:
Misleading metric display for any high-performing analyst or narrow filter. Not reachable in the default 40-cita dataset (total 1.54), which is why the existing tests do not catch it.

Recommendation:
`Math.min(100, ...)` at the call site, or confirm `Progress` clamps and add a test at a >125% cohort. Also consider whether >125% should render a distinct "over target" treatment rather than a silently saturated bar.

**[P1] Disclosure semantics left over from the removed non-modal sheet**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/inasistencias.tsx`
Lines: 74, 81, 87 (and `ficha-recorrido.tsx:28`, `id="citas-recorrido"`)

Problem:
`FichaRecorrido` is now unconditionally modal (`ficha-recorrido.tsx` diff removes `modal={!amplia}`), but the row triggers still advertise a disclosure relationship, and the section still owns a live region describing the dialog.

Evidence:
- `inasistencias.tsx:74` and `:81`: `aria-expanded={leadAbierto === ...}` and `aria-controls={... ? 'citas-recorrido' : undefined}`.
- `inasistencias.tsx:87`: `<p role="status" className="sr-only">{abierta ? 'Mostrando recorrido de ' + abierta.original.nombre : ''}</p>`.
- The diff to `tablero.test.tsx` deleted precisely the assertions that covered these (`aria-expanded="true"` and `'Mostrando recorrido de Mónica Silva'`), so the behaviour is now both wrong and untested.

Impact:
`aria-expanded` implies inline expansion, which no longer happens; `aria-controls` points into a dialog while the trigger itself sits in the background subtree that the modal renders inert/`aria-hidden`, so it cannot be followed. The `role="status"` node is likewise inside that hidden subtree, so per spec its update should not be announced — dead code that, in implementations that do announce it, duplicates the dialog's own name announcement.

Recommendation:
Drop `aria-expanded` and `aria-controls` from both buttons (optionally `aria-haspopup="dialog"`), remove the `role="status"` paragraph, and drop `id="citas-recorrido"` from `SheetBody` if nothing else references it. Let the dialog's own name/focus management do the announcing — which `tablero.test.tsx:39-45` already covers.

**[P2] Undefined CSS class `citas-espacio-trabajo`**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/propuesta.tsx`
Lines: 133

Evidence:
`<div className="citas-espacio-trabajo min-w-0 flex-1">` — no `.citas-espacio-trabajo` rule exists anywhere in `presentacion.css` (the full file is in the evidence).

Impact:
Either an intended rule was dropped during the rewrite (in which case something is visually unfinished) or it is a dead hook. Ambiguous for the next maintainer.

Recommendation:
Remove it, or add the rule it was meant to carry.

**[P2] Test parameterization is now inert and misleading**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/tablero.test.tsx`
Lines: 58-71 (and 35)

Evidence:
The `ficha-recorrido.tsx` diff removes `useSyncExternalStore`, `suscribirsePantalla` and `esPantallaAmplia`; the component no longer reads `matchMedia`. Yet `it.each([true, false])('... amplia=%s')` still stubs `matchMedia` and, after the diff at line 63, asserts the identical outcome in both branches (`expect(...overlay).toBeInTheDocument()`).

Impact:
The suite reads as if it covers responsive sheet behaviour that no longer exists; it runs the same assertions twice. If `Sheet` internally consults `matchMedia`, the stub is also now the only thing pinning that, silently.

Recommendation:
Collapse to a single case and delete the `matchMedia` stubs unless `ui/sheet.tsx` genuinely depends on them — in which case name the parameter for what it actually controls.

**[P2] Sidebar responsive behaviour and layout width — needs verification**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/propuesta.tsx` (132), `presentacion.css` (7)

Problem (hypothesis — I cannot read `sidebar.tsx`):
The previous rail was `hidden ... xl:flex w-[208px]`; the new shared `Sidebar` is rendered unconditionally, and the prototype does not render `Topbar`.

Evidence:
Diff removes the `<aside className="citas-rail sticky top-0 hidden ... xl:flex">` element. `presentacion.css:7` is `.citas-crm > aside { position: sticky; top: 0; height: 100svh; }` — no visibility rule at any breakpoint, and no `.citas-crm > aside` override in the 767px block.

Checks to run:
1. Does `Sidebar` carry its own `hidden md:flex`-style visibility, or does the real app rely on `Topbar` (absent here) to toggle a mobile drawer? If the latter, mobile either shows a permanent 240px column or loses navigation entirely.
2. Is the `Sidebar` root actually an `<aside>` and a direct child? `AuthContext` renders no DOM node, so the child selector holds only if the root element is `<aside>`; otherwise `presentacion.css:7` silently no-ops.
3. `.citas-crm > aside` (specificity 0,1,1) outranks a Tailwind `.fixed` utility (0,1,0). If `Sidebar` is designed as `position: fixed`, this rule overrides it and changes its layout contract.

**[P2] Desktop filter grid uses `1fr`, not `minmax(0, 1fr)`, at a now-narrower effective width**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/presentacion.css`
Lines: 26

Evidence:
`grid-template-columns: minmax(180px, 1.5fr) 1fr 1fr 1.15fr 1fr auto auto` — `1fr` resolves to `minmax(auto, 1fr)`, so a long `<option>`/label sets a floor the track cannot go below. The responsive blocks correctly use `repeat(4, minmax(0, 1fr))` (108, 128), so the pattern is already known in this file. The desktop rule now applies with a persistent ~240px sidebar subtracted, where the old rail was hidden below 1280px — i.e. between 1280px and roughly 1450px viewport this 7-column row now lays out in ~1000px of content, a case the previous layout never hit.

Impact:
Possible horizontal overflow of the workspace at 1280–1450px. This is a class of issue adjacent to the tablet overlap you already found and fixed, at a width your reported browser passes may not have covered.

Recommendation:
`minmax(0, 1.5fr) minmax(0, 1fr) ...` throughout, and verify at exactly 1280px and 1366px.

**[P2] Prototype now imports `@/lib/auth-context` — verify no module-scope side effects**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/marco.tsx`
Lines: 2

Problem (hypothesis — I cannot read `auth-context.ts`):
`AuthContext` is a *value* import, so the entire module and its transitive top-level imports are pulled into the prototype bundle and executed on load. Not mounting `AuthProvider` prevents component-level effects, not module initialization.

Evidence:
Your CodeGraph note establishes that `Sidebar` "does not mount providers/services itself" and that `auth-context.ts` exports the `AuthContextValue` shape — neither statement covers module-scope side effects of `auth-context.ts` or of `Avatar`/`BrandLockup`.

Checks to run:
1. Does `auth-context.ts` (or anything it imports at top level) construct a Supabase/HTTP client, read env vars, or register listeners at module scope? If so, the standalone prototype HTML initializes it on load — the accidental backend coupling you asked about.
2. Does `Avatar` fetch a remote image URL derived from `yo`? Here `yo` has no avatar field, so likely inert, but worth confirming there is no network request.
3. If there is a side effect, extract the context object to a side-effect-free module or define a local context shape for the prototype.

`comprobación de bundle` in `npm run check` may already flag a size delta here; worth reading that output specifically.

**[P2] Modal-to-modal focus handoff is coordinated by double `requestAnimationFrame`**

File: `CRM-Avance-Corp/app/src/prototypes/citas-crm/propuesta.tsx`
Lines: 103-107

Evidence:
`abrirCitaDelRecorrido` closes the recorrido sheet, then waits two rAFs before `setDetalle(cita)`, with the comment *"Termina el retorno de foco del inspector antes de abrir la ficha de cita."* Now that both sheets are always modal, this sequences two focus traps.

Impact:
The ordering is a timing coincidence, not a contract. If `ui/sheet.tsx` restores focus on a `transitionend` or `setTimeout` rather than synchronously on unmount, the restore can land *after* the second dialog opens and pull focus back into the inert background. Critically, jsdom does not run CSS transitions, so `tablero.test.tsx:58-71` would pass in that scenario while the browser fails. Your manual browser pass on the "modal-linked appointment path" is the real evidence that it currently works — I am flagging the fragility, not asserting breakage.

Recommendation:
If `Sheet` exposes it, prevent the close-time focus restore for this transition (`onCloseAutoFocus`-style) instead of racing it, so the behaviour survives future changes to the sheet's animation.

**[P3] Sticky header introduced without `scroll-margin-top` on anchor targets**

File: `presentacion.css:8-21`, `propuesta.tsx:131, 143`

Evidence:
`.citas-cabecera` changed from static `min-height: 84px` to `position: sticky; top: 0; height: 64px`. The skip link targets `#consulta-citas`, and `MenuCRM.navegar` focuses the same element; no `scroll-margin-top` is set anywhere in the file.

Impact:
Skip-link and sidebar "Citas" activation scroll the top of `main` under the 64px sticky header. New regression, since the header was not sticky before.

Recommendation:
`#consulta-citas { scroll-margin-top: 64px }` (12px-inset variant at ≤767px if the header height changes).

**[P3] Reduced-motion escape hatch does not cover the sheet overlay**

File: `presentacion.css:151-153`

Evidence:
The rule scopes to `.citas-crm *` and `.citas-crm-dialogo *`. The overlay is a separate portaled sibling (`[data-slot="sheet-overlay"]`, asserted at `tablero.test.tsx:40, 63`) and carries neither class.

Impact:
Previously the overlay was absent on ≥1536px; now every sheet open renders one, so its fade animation is always reachable under `prefers-reduced-motion: reduce`.

Recommendation:
Confirm the shared overlay already honours reduced motion globally; if not, extend the selector.

**[P3] Hardcoded track colour breaks the token discipline of this file**

File: `presentacion.css:84`

Evidence:
`.citas-barra-meta > div { height: 6px; background: #e8edf2; }` — every other surface in the file uses `var(--gi-line)`, `var(--gi-soft)`, `var(--card)`, `var(--secondary)`. `#e8edf2` is also structurally coupled: it assumes `Progress` renders a `div` root and that the marker `<span>` is the only direct `span` child.

Recommendation:
Use the matching `--gi-*` token, and prefer a `Progress` prop or a data attribute over `> div` / `> span` positional selectors.

**[P3] `aria-label` on `<td>` duplicates the column header**

File: `resultados.tsx:63`

Evidence:
`<td aria-label={... `Cumplimiento: ${numero(fila.cumplimiento, 1)}%`}>` under `<th scope="col">Cumplimiento</th>`.

Impact:
Screen readers announcing header + cell name produce "Cumplimiento, Cumplimiento: 51.3%". Also, an author-supplied name on a cell replaces its content in the accessibility tree, so this must stay in sync with the visible `<strong>` by hand.

Note: wrapping the bar in `aria-hidden="true"` is the right call here — exposing `role="progressbar"` with a 125-normalized `aria-valuenow` would have announced a number that matches nothing on screen. Keep that.

Recommendation:
`aria-label="51.3%"` (value only), or drop the label and let the `<strong>` text serve as the cell content.

**[P3] Scrollable regions are not explicitly keyboard-focusable**

File: `inasistencias.tsx:66`, `resultados.tsx:56`, `presentacion.css:53-54`

Evidence:
Both `.citas-tabla-scroll` containers have `role="region"` + `aria-label` but no `tabIndex={0}`, while the CSS defines `.citas-tabla-scroll:focus-visible { outline: 2px solid var(--accent) }` — styling for a focus state nothing produces. Pre-existing, but amplified: `.citas-tabla-metas` min-width grew 680px → 750px (line 71) and a permanent ~240px sidebar was added, so horizontal scrolling is now reachable at more viewports than before.

Impact:
Keyboard-only users may be unable to scroll the metas table horizontally on browsers that do not auto-focus scroll containers (WCAG 2.1.1).

Recommendation:
Add `tabIndex={0}` to both scroll containers, matching the intent already encoded in the CSS.

**[P3] Minor CSS hygiene**

File: `presentacion.css`

- Lines 44 and 46 both target `.citas-flujo .citas-paso`; merge `min-width: 0` into the first block.
- Lines 121-122 and 139-140 duplicate the 2×2 grid and hidden-arrow rules across the 900px and 767px blocks; the 767px copies are redundant except for `gap: 8px 0`.
- Line 93 `.citas-vista-operativa { padding: 0 20px }` combined with `.citas-tabla th, td { padding: 16px 20px }` (line 55) gives 40px of effective horizontal inset, and insets the `overflow-x` clipping edge 20px from the card border — worth a look in the bandeja/agenda views, which I could not inspect (`vistas.tsx` not attached).

TEST GAPS:

- No coverage of `cumplimiento > 125%` for the bar (the P1 above). A focused test over a cohort with an analyst averaging 4 citas/lead would pin both the clamp and the marker semantics.
- No assertion on the new `aria-label` of the cumplimiento cell, nor that the bar is `aria-hidden` — both are load-bearing a11y decisions with nothing guarding them.
- `MenuCRM` is entirely untested: no test that `PropuestaCitasCRM` renders the shared `Sidebar` without an `AuthProvider`, and none that `navegar('reuniones')` focuses `#consulta-citas` while other vistas do not. The latter is the one branch that distinguishes in-prototype navigation from leaving the page.
- No test that the prototype issues no network request on mount — cheap to add (`vi.stubGlobal('fetch', ...)` + assert not called) and it would durably encode the "no backend coupling" constraint that motivated `marco.tsx`.
- `tablero.test.tsx:17` still asserts the absence of a region named `'Resumen de las citas filtradas'` — a negative assertion about a design that no longer exists. Harmless, but it is not testing anything today.

ARCHITECTURE RISKS:

- `marco.tsx` hand-constructs an `AuthContextValue`. Any field added to that interface breaks the prototype at typecheck time — acceptable and arguably desirable, but it means `auth-context.ts` now has a prototype consumer that its authors will not expect. A short comment there pointing at `marco.tsx` would help; the existing comment lives only on the prototype side.
- `volverAlCRM = () => window.location.assign('/')` and `window.location.assign('/' + hashDe(vista))` hardcode the site root. If the app is ever published under a sub-path — and your recent commit log mentions *"prepara publicación compatible"* — these navigate outside the deployment. Consider `import.meta.env.BASE_URL`.
- Adding `gerencia-inteligencia` to `FichaRecorrido`'s sheet (`ficha-recorrido.tsx:19`) is correct and necessary, since `.citas-ficha-cabecera` consumes `--gi-soft`/`--gi-line` from a portaled node (`presentacion.css:97`). Worth knowing that the other four sheets (`Guia`, `Ficha`, `DetalleLeads`, `AyudaMetricas`) deliberately do not opt in — any future `--gi-*` usage in those will silently fall back to nothing.

SECURITY RISKS:

- None identified in the diff itself. The static identity in `marco.tsx:9-17` grants no capability: `puede_contratar: false`, every action navigates away, and no provider or service is mounted. The only genuine exposure surface is the module-side-effect question in the P2 above, which is a coupling/bundle concern rather than an auth bypass — the prototype has no privileged endpoint to reach.
- Worth stating plainly for the record: `rol: 'gerencia'` here is presentation-only and confers nothing, because no authorization decision in this prototype consults it. That should stay true — if the prototype ever renders a component that gates on `yo.rol`, this constant becomes a misleading precedent.

REGRESSION RISKS:

1. Sidebar visibility below 1280px (P2) — the single most likely place for a visible regression, and the one I can least evaluate from the attached evidence.
2. Filter row overflow at 1280–1450px (P2), a width band that did not previously exist as a case.
3. Modal chaining focus (P2) — currently verified by hand; not durably protected by the test suite given jsdom's lack of transitions.
4. Removal of `citas-con-ficha` means the board no longer reflows when the sheet opens on ≥1536px. Deliberate per your brief; noting only that anyone comparing against the earlier prototype will see it as a change in behaviour, not just in styling.

RECOMMENDED NEXT ACTIONS:

1. Clamp the `Progress` value (or confirm internal clamping) and add a >125% test case.
2. Remove the leftover `aria-expanded` / `aria-controls` / `role="status"` disclosure semantics in `inasistencias.tsx:74, 81, 87` and the now-orphaned `id="citas-recorrido"`.
3. Verify the three unverifiable items with your tools: `Sidebar` responsive behaviour and root element, `auth-context.ts` module-scope side effects, and `Progress` clamping. Report what you find rather than assuming.
4. Resolve `citas-espacio-trabajo` (define or delete), switch the desktop filter grid to `minmax(0, …)`, and add `scroll-margin-top` to `#consulta-citas`.
5. Collapse the inert `it.each([true, false])` parameterization and drop the dead `matchMedia` stubs.
6. Re-run the full `npm run check` after these edits — several touch files with existing assertions.

CONFIDENCE:
MEDIUM

High confidence on the findings derived entirely from the attached files (P1 disclosure leftovers, dead CSS class, inert test parameterization, `1fr` grid, `scroll-margin-top`, CSS hygiene) and on the arithmetic I could verify independently. Medium-to-low on the four items gated behind files I could not read — `Progress` clamping, `Sidebar` responsiveness, `auth-context.ts` side effects, `Sheet` focus-restore timing — which I have framed as checks rather than defects. I make no claim about visual fidelity to the Ranking screenshot; I cannot inspect rendered output, and that judgment is the user's.
