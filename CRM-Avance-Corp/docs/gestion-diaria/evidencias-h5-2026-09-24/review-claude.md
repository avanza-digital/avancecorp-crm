VERDICT:
CHANGES_REQUESTED

SUMMARY:
Within the supplied evidence, the integrated H2–H4 runtime looks correct on the high-risk axes:

- **RLS and scope.** The pendientes core uses INVOKER, derives the actor from `auth.uid()`, returns an identical 42501 for foreign, inactive and nonexistent analysts, and uses the shared `gestion_diaria_equipo_ambito`.
- **Pagination.** The keyset preserves microseconds and uses strict validation. No findings there.
- **Isolation.** The owner remount is keyed by actor/rol/demo/día, avisos are keyed by day, and revocation purges the pendientes cache.
- **Actions.** Acknowledgment is confirmed by the server, not applied optimistically.

I found no P0 or P1. There is one P2 in the runtime: it tells users of disabled sessions that loading failed. There is one P2 test gap: the H5 test does not fully prove that load is independent of team size. There are also a few P3s.

H6 cannot be called published or accepted. The full Docker suite is still pending, the realidad gate did not run, and hosted advisors plus human acceptance are still outstanding. These are correctly declared as pending.

FINDINGS:

[P2] "Otros pendientes" tells disabled or demo sessions that the data could not be confirmed
File: `app/src/components/gestion-diaria/alertas-del-dia.tsx`
Lines: new hunk, first `if (cortes?.error || !cortes?.datos)` branch
Problem:
- `useAvisosCortes` is only enabled for `!yo.demo && rol === 'supervisor' && !administraSoloRolesCrm(yo) && funcionesLeadsVisibles(...)` (`gestion-diaria-seguimiento-queries.ts`). A demo supervisor can still reach `VistaSupervisor`, because the key includes `yo.demo`.
- In that case the provider supplies `datos = null`, `error = null` and `cargando = false`, since `habilitada` is false.
- `AlertasDelDia` then renders "No pudimos confirmar los otros pendientes del equipo…" together with a retry button. The retry goes through `estado.reintentar`, which calls `cortes?.recargar()`, which does nothing when `!habilitada`.
- In the same dialog, `AvisosEquipo` correctly shows "Los avisos no están disponibles en esta sesión.", so the two tabs disagree.
Evidence: The base code returned `null` when `!cortes?.datos?.diarias`, so the new branch introduces a false error state. The provider's `cargando` and `error` are both gated by `habilitada`.
Impact: A persistent, misleading failure message and a retry button that does nothing. This is a regression against the product rule of not presenting unconfirmed states as failures.
Recommendation: Treat `!datos && !cargando && !error` as "no disponible en esta sesión", matching `AvisosEquipo`. Show the retry button only when `cortes.error` is set. Add a unit case for a demo or disabled context.

[P2] The H5 E2E only counts three RPCs, so an N+1 on any other endpoint would pass
File: `app/e2e/gestion-diaria-horizontal-h5.spec.ts`
Lines: 18–35, 43, 49, 53
Problem: The requirement is "lazy loads independent of team size". The spec counts only `gestion_diaria_equipo_fn`, `registro_actividad_fn` and `gestion_diaria_pendientes_fn`. A per-row request to any other `/rest/v1/` endpoint would go undetected, for example avisos, alertas, a store fetch, or a future helper.
Evidence: The only route handlers are those three. Nothing compares the 1-analyst and 32-analyst runs.
Impact: The main H5 claim is proven only for the endpoints you already expected.
Recommendation:
- Add a `page.on('request')` counter for every `/rest/v1/` request, bucketed by path.
- Write it into `consultas-h5.json`.
- Assert that the 1-analyst and 32-analyst buckets are equal. You can do this in the spec by computing both runs in one test, or in a post-check.

[P3] The negative "no extra request" assertions run without waiting
File: `app/e2e/gestion-diaria-horizontal-h5.spec.ts`
Lines: 56, 59, 70
Problem: `expect(lecturas.registro).toBe(1)` runs immediately after the tab clicks, before any refetch triggered by the click could reach the route. The assertion therefore cannot fail on a delayed duplicate fetch.
Recommendation: Assert after a later positive event, or add a short settle such as `expect.poll` over about 1 second, or `page.waitForLoadState('networkidle')`. Consider also asserting the expected registro count after the header "Actualizar" click (line 61). That click does trigger Registro and Últimas refetches through `actualizacion`, and the count is currently unasserted.

[P3] `expect` inside a route handler may surface as a timeout rather than a clear failure
File: `app/e2e/gestion-diaria-horizontal-h5.spec.ts`
Lines: 28
Problem: If the payload does not match, the handler throws before `fulfill`. The request can then hang, and the failure shows up as a later `toBeVisible` timeout. This is a hypothesis about how Playwright reports errors thrown in handlers.
Recommendation: Record the payloads into an array, fulfill unconditionally, and assert on the array afterwards.

[P3] Double fetch on external refresh for non-shared Registro with a cursor
File: `app/src/components/gestion-diaria/registro-actividad.tsx`
Lines: `claveFiltros = JSON.stringify([filtros, actualizacion])` and the `versionRecarga` effect
Problem:
- In team mode (`compartirPrimeraPagina = false`) with `cursor ≠ null`, a change to `actualizacion` switches the key to the first page. With `staleTime: 0` the observer fetches.
- The effect then calls `refetch({ cancelRefetch: true })`, which cancels that fetch and issues a second one.
Impact: One wasted request per refresh after pagination. It does not affect correctness.
Recommendation: Call `recargar` only when the key did not change, that is when the cursor was already null, or use `cancelRefetch: false` everywhere.

[P3] The bar's count and the tab's list use different definitions
File: `franja-cortes-supervisor.tsx` (the `ultimoConteo` filter) and `alertas-del-dia.tsx` (`filter((a) => !a.corte)`)
Problem: The bar counts `!a.corte && !a.reconocimiento`, but the tab lists every `!a.corte`, including acknowledged alerts. "Otros avisos: 1" can therefore sit next to a list of three items.
Recommendation: Label the bar as "sin reconocer", or use the same filter in both places. Separately, `ultimoConteo.current` is mutated during render. That works, but it is impure under StrictMode or concurrent rendering, so consider `useState` plus an effect.

Lint warning at `tabla-equipo-diaria.tsx:48`: this is the Contacto cell. The visible content is `aria-hidden` and has an `sr-only` alternative (`contextoContacto`), and the level also appears as text, so color is not the only signal. From the markup, a false positive is plausible. However, the warning text and rule id were not supplied, so I cannot confirm it. Attach the exact oxlint output before accepting it as a false positive.

TEST GAPS:
- Demo or disabled avisos context in `AlertasDelDia` and `FranjaCortesSupervisor` (see the first P2).
- No E2E check that header "Actualizar" resets Registro to its first page while keeping its filters. This is intentional per the prop comment, but it differs from the automatic summary refetch and should be pinned.
- A day mismatch in `useAvisosCortes` throws `GESTION_DIARIA_JORNADA`. Client clock skew around 00:00 Lima is not covered. Recovery depends on the 60 s interval and the default retry, and the unit test disables retry.
- The E2E fixtures use non-UUID `analista_id` values (`h5-${i}`). Real IDs are UUIDs, and the pendientes schema requires them. Using UUIDs would keep the E2E closer to the real contract, even though this path does not hit the validator.

ARCHITECTURE RISKS:
- `PanelSupervisorAdaptable` relies on moving a single portal target into `Dialog.Content`, with `onInteractOutside` deciding via DOM containment. This is sound, and its comment documents the no-exit-animation constraint. A future Radix upgrade that changes the `DismissableLayer` or `FocusScope` internals could break it silently, so keep the existing focus and ficha E2E as a regression guard.
- `revocada.current` is reset during render when the identity changes (`gestion-diaria-pendientes-queries.ts`). It works, but it is fragile under concurrent rendering.

SECURITY RISKS:
- None found in the supplied SQL and client code.
- `pendientes_core` checks the role, then the scope (42501), then the parameters (22023), then roster membership (42501). The lead name is resolved under RLS, and a lead that is not visible yields null without dropping the task.
- `gestion_diaria_equipo_ambito` is granted to `authenticated` as INVOKER. It enforces self-only access for supervisors and relies on RLS for gerencia and global readers. Parity is claimed by the local bank but not independently verifiable here.
- Hosted advisors are still pending.

REGRESSION RISKS:
- The first P2: the base rendered nothing in this state, and the new code renders a false error.
- The `alertas-provider` early return for real supervisors now skips the conversion and store refetches when `diarias` is present. This is correct only if the daily source is complete, as the comment claims. The runtime evidence supplied does not include that part of the provider.

RECOMMENDED NEXT ACTIONS:
1. Fix the disabled-session state in `AlertasDelDia` and add a unit test for it.
2. Strengthen the H5 E2E: count every `/rest/v1/` request, compare the 1-analyst and 32-analyst runs, and make the negative assertions wait before checking.
3. Attach the exact lint output for `tabla-equipo-diaria.tsx:48`.
4. Report the final result of the full Docker suite of 275 tests. Keep H6 marked as not published and not accepted until SQL is installed before the frontend and human authorization is given.

CONFIDENCE:
MEDIUM. The runtime diff and SQL were fully visible. The implementations of `Tabs`, `esFocoHuerfano`, the Registro query key, the rest of the alertas-provider and the lint output were not.
