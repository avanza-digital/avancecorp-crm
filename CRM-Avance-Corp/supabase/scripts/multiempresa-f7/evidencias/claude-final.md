VERDICT: CHANGES_REQUESTED

SUMMARY:
The F7 shadow report is well-constructed defensively: transactional install with hash preflight + hardening postflight, flag born OFF, definer helpers revoked from all API roles, two-factor admission (gerencia + active membership) re-checked per call, and a client-side payload integrity gate. I found no P0 and no write path into the core. However, there are two findings I rate P1 — a server-side gap in demo-account isolation, and a join in `primeras`/`mes` that fans out on duplicate source keys that the same function explicitly counts as possible — plus several P2 issues around the reconciliation contract, the client schema's untested coupling to SQL output, polling cost, and a reversal test that is structurally blind to the objects it reverses. The Dialog/Sheet layer fix is sound under the supplied Radix source; the one concern I can substantiate is that it uses DOM order rather than focus containment as the layer-order proxy.

FINDINGS:

[P1] Demo Gerencia accounts are isolated from real group financials only on the client
File:
CRM-Avance-Corp/supabase/migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql
CRM-Avance-Corp/app/src/screens/metricas-multiempresa.tsx
Lines:
migration 29-36; screen 25-26, 31-34
Problem:
`private.metricas_f7_autorizada()` admits any `crm.equipo` row with `e.activo and p.activo and e.rol_crm='gerencia'`. It has no demo-account predicate. The screen is the only thing that stops a demo Gerencia user from seeing real figures: `const demo = yo?.demo === true` and the hook is enabled with `yo?.rol === 'gerencia' && !demo`, with the demo branch rendering `metricasMultiempresaDemo(...)` instead.
Evidence:
migration:32-35 authorization predicate; screen:26 `useMetricasMultiempresa(yo?.id ?? '', yo?.rol === 'gerencia' && !demo, mes)`; screen:33-34 demo branch. The RPC is granted to `authenticated` (migration:222-223), so any holder of a demo Gerencia JWT can call `crm.metricas_multiempresa_fn` directly through PostgREST and receive real Avance/Qorilazo/Prodelco capital, attribution and person counts.
The role fixtures in `supabase/scripts/multiempresa-f7/http.test.mjs:21-32` iterate `fixture.usuarios` and assert gerencia succeeds / everyone else gets 42501; there is no demo-Gerencia fixture, so this path is unexercised.
Impact:
If a Gerencia-role demo account exists (the frontend's dedicated `yo.demo` handling implies the concept is real for users, not only for sources), real multi-company financials are reachable outside the UI. The whole point of a demo login is that it can be exercised in front of non-owners.
Confidence: this is a hypothesis about whether demo *users* with `rol_crm='gerencia'` exist; the missing predicate itself is a fact.
Recommendation:
Confirm how other published definer RPCs (e.g. `crm.metricas_conversiones_fn`) treat `public.perfiles.demo`. If they exclude demo users server-side, add `and not coalesce(p.demo,false)` to `private.metricas_f7_autorizada()` and add a demo-Gerencia fixture asserting 42501 over HTTP. If the repo convention really is client-side-only, say so explicitly in CONTRATO.md so G6 signs off on it knowingly.

[P1] `primeras` ⋈ `mes` fans out when a source has more than one stock episode
File:
CRM-Avance-Corp/supabase/migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql
Lines:
109-123, 206-208
Problem:
`primeras` emits one row per row of `fuentes` (not per source), and `mes` joins `fuentes f left join primeras p using(fuente_tipo,fuente_id)`. If `(fuente_tipo,fuente_id)` is not unique in `fuentes`, the join is an N×N fan-out and `produccion.capital`/`operaciones`, `tipos`, and `atribucion` are all multiplied.
Evidence:
The function itself treats non-uniqueness as possible — lines 206-208 compute `fuentes_duplicadas` by `group by fuente_tipo,fuente_id having count(*)>1`. `private.metricas_f7_fuentes()` returns one row per `medida='stock'` capital episode (line 72/77), keyed by `coalesce(contrato_id,cierre_externo_id)` (line 64), and `tipos_capital` distinguishes `contrato_renovacion` / `contrato_upgrade` (`TIPO_CAPITAL` in `app/src/lib/metricas-multiempresa.ts:39-41`), i.e. multiple stock episode *types* exist per contract lifecycle. Whether a renewal/upgrade reuses `contrato_id` or allocates a new one is not visible in the supplied evidence; the unique partial indexes you verified are on `crm.inversiones.contrato_id`, which constrains the relational table, not the episode ledger.
Note that the existing tests cannot catch this: the parity test (`metricas.test.mjs:53-70`) asserts `r.fuentes_duplicadas === 0` on the synthetic bank, so the bank is by construction in the safe case.
Impact:
Inflated capital and operation counts. The reconciliation would surface a non-zero `diferencia_capital`, so it degrades to "Hay diferencias que requieren revisión" rather than silently wrong money — but the cause would be opaque, and `fuentes_duplicadas` is never rendered (see [P3] below).
Recommendation:
Make `primeras` source-unique regardless of episode multiplicity, e.g. derive it from `select distinct fuente_tipo,fuente_id,inversionista_id,fecha_comercial,creado_en,empresa from fuentes` before `row_number()`. Cheap, semantics-preserving, and removes the fan-out class entirely. Additionally consider raising (or returning a hard `integridad` error) when `fuentes_duplicadas>0` rather than returning arithmetic derived from a state the function has already detected as invalid. Add a bank case with two stock episodes on one source asserting no inflation.

[P2] Demo filtering is asymmetric between `produccion` and `capital_nucleo`
File:
CRM-Avance-Corp/supabase/migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql
Lines:
77 vs 141-146
Problem:
`private.metricas_f7_fuentes()` excludes demo sources via the F5 reader's classification (`and not coalesce(f.es_demo,false)`), but the reconciliation baseline `capital_nucleo` reads `private.capital_episodios(v_ini,v_fin,true,'{}')` with no demo predicate. The two sides of the reconciliation therefore use different demo definitions unless `capital_episodios`' third boolean argument excludes demo with byte-identical semantics to `cartera_f5_fuentes().es_demo`.
Evidence:
Line 77 filters on `f.es_demo` (F5 reader). Line 144-146 has no equivalent filter. `metricas.test.mjs:55-62` computes the expected value with the same unfiltered call and `deepEqual`s it against `produccion` — which passes only because the bank contains no stock episode that is demo under F5 but present in `capital_episodios(...,true,...)`.
Impact:
Any source classified demo by one reader and not the other yields a permanent non-zero `diferencia_capital` for that empresa/moneda — the report would read "Hay diferencias que requieren revisión antes de aceptar el informe" forever, which is exactly the signal G6 will be reading.
Recommendation:
State explicitly (in the migration comment and CONTRATO.md) what the `true` argument to `capital_episodios` means and that it is the same demo universe as `cartera_f5_fuentes().es_demo`; if it is not, apply the same F5 demo exclusion to `capital_nucleo`. Add a bank row that is demo under exactly one reader and assert the expected reconciliation outcome.

[P2] The client integrity gate rejects a núcleo-only group, i.e. the exact discrepancy the reconciliation exists to reveal
File:
CRM-Avance-Corp/app/src/lib/metricas-multiempresa.ts
Lines:
56, 58
Problem:
`if (r.conciliacion.length !== r.produccion.length) return false` and `[...r.atribucion, ...r.tipos_capital, ...r.conciliacion].some(x => !grupos.has(clave(x)))` require every `conciliacion` key to exist in `produccion`. But `conciliacion` is a FULL JOIN (migration:156), so a group present in `capital_nucleo` and absent from `produccion` is legitimate output — it means the núcleo has money the report did not cover.
Evidence:
metricas-multiempresa.ts:56-58; migration:147-156 `from capital_nucleo n full join produccion p using(empresa,moneda)`.
Impact:
When the report loses a whole empresa/moneda group (demo mismatch as in the previous finding, a missing `crm.cierres_externos` row making `empresa` null, an unmapped `cooperativa`), `obtenerMetricasMultiempresa` throws `RESPUESTA_INCOMPLETA` (data/metricas-multiempresa.ts:18-20) and the user sees "No se pudo actualizar el informe" — a transport error — instead of "Hay diferencias que requieren revisión". `estadoConciliacion`'s `'diferencias'` branch is unreachable for this class. This directly contradicts CONTRATO.md:66-67 ("No presentar ausencia de evidencia como diferencia cero").
Recommendation:
Allow `conciliacion` rows with no `produccion` counterpart provided `operaciones_informe === 0 && capital_informe === 0`; keep the strict subset requirement for `atribucion` and `tipos_capital`, and keep the "every produccion group has exactly one conciliacion row" invariant. Add a unit test for a núcleo-only group asserting `informeMultiempresaCompleto === true` and `estadoConciliacion === 'diferencias'`.

[P2] No test validates a real RPC payload against `MetricasMultiempresaSchema`
File:
CRM-Avance-Corp/app/src/lib/metricas-multiempresa.test.ts
CRM-Avance-Corp/supabase/scripts/multiempresa-f7/http.test.mjs
Lines:
test.ts:6 and every case; http.test.mjs:24-31
Problem:
Every frontend assertion runs against `metricasMultiempresaDemo(...)`; the HTTP tests check a handful of fields ad hoc (`produccion.length`, `fuentes_duplicadas`, `diferencia_capital`) and never run the valibot schema or `informeMultiempresaCompleto`. Nothing in the suite couples the client contract to actual SQL output.
Evidence:
`const ejemplo = () => metricasMultiempresaDemo('2026-09-01','2026-09-11')` (test.ts:6) is the sole input for all 8 cases; http.test.mjs imports no schema.
Impact:
Any divergence between the JSON the RPC emits and the schema produces a total outage of the screen for Gerencia with the misleading "El informe llegó incompleto. Vuelve a consultar." — and, with `retry:false` plus `refetchInterval: 30_000`, it retries forever without recovering. Concrete surfaces at risk today:
- `conversion.divisor` is typed `Cantidad` (`v.integer()`, metricas-multiempresa.ts:3, 25) but SQL emits `sum(aporte_divisor)` under a *weighted* factor `v_factor = private.peso_referido_conversion(v_mes)` (migration:105, 158, 195). If the referral weight applies to the divisor (the name "peso_referido" suggests it down-weights referred arrivals in the funnel denominator), the divisor is fractional and the schema hard-rejects the whole payload. The asymmetry is suspicious: `numerador` is `Capital` (fractional-tolerant) and is rendered via `numero(..., 2)`, while `divisor` is integer-only and rendered raw (screen:134). Hypothesis — requires the definition of `private.conversion_episodios`.
- `capital_nucleo`/`capital_informe` are `Capital` (≥0); any negative stock episode (correction/reversal) breaks the payload.
- `generado_en` must satisfy `v.isoTimestamp()` against Postgres' `timestamptz` JSON rendering, which varies with the session `DateStyle`/`TimeZone`.
Recommendation:
Add a test that takes the actual JSON from the local bank RPC and runs `v.parse(MetricasMultiempresaSchema, ...)` + `informeMultiempresaCompleto(...)`. Independently, confirm `aporte_divisor`'s domain and relax `divisor` to `Numero` (rendering it with `numero(..., 2)`) unless it is provably integral.

[P2] The reversal test is blind to the F7 objects it is supposed to reverse
File:
CRM-Avance-Corp/supabase/scripts/multiempresa-f7/metricas.test.mjs
Lines:
8-13, 194-199
Problem:
`huellas()` excludes `proname not like 'metricas_f7_%' and proname not like 'metricas_multiempresa_%'`. The test "F7: reversa apaga solo el informe y conserva núcleos/fuentes" then asserts `huellas()` and `dineroYFotos()` are unchanged — neither of which can observe whether `reversa-operativa.sql` dropped, kept, or altered the four F7 functions.
Evidence:
metricas.test.mjs:13 (exclusion), :194-199 (assertions). `reversa-operativa.sql` was not supplied.
Impact:
The reversal's actual effect on its own objects — the property the test name claims — is unverified. Combined with the plain `insert into crm.multiempresa_flags` at migration:23-24 (no `on conflict`) and `create function` rather than `create or replace`, an uninstall/reinstall cycle through the Supabase branch flow can fail on duplicate key or already-exists depending on what the reversal actually does.
Recommendation:
Assert the post-reversal state of the F7 objects explicitly (expected set of remaining/absent functions, their ACLs and owners), and decide + test the reinstall path: either the reversal removes the flag row, or the migration uses `on conflict (nombre) do update set activo=false, descripcion=excluded.descripcion`. Supply `reversa-operativa.sql` for review.

[P2] Read cost: a full-history aggregation polled every 15/30 s per Gerencia session
File:
CRM-Avance-Corp/app/src/data/metricas-multiempresa.ts
CRM-Avance-Corp/supabase/migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql
Lines:
data:25-33; migration:72, 107-108, 164-172
Problem:
Every call materializes `fuentes` from `private.capital_episodios('-infinity','infinity',true,'{}')` joined to `private.cartera_f5_fuentes()` over all time, then `oportunidades` evaluates, per (active empresa × known person), a correlated `exists` containing the set-returning `private.leads_de_persona_veto(i.id)` — roughly 3N SRF invocations. The client runs this on `refetchInterval: 30_000` with `staleTime: 0, gcTime: 0` (so also on every mount and window focus), and the state RPC on `refetchInterval: 15_000`.
Evidence:
migration:72 (unbounded window), 107-108 (`materialized`), 165-171 (per-person SRF); data:27 and 32. Your own EXPLAIN note says 98 synthetic sources / 28.085 ms is explicitly not a production-scale benchmark.
Impact:
Unbounded growth in cost with portfolio size, multiplied by a 2 req/min per-session poll that nobody asked for — the screen already has an "Actualizar" button (screen:57).
Recommendation:
Drop `refetchInterval` on the data query (manual refresh + `refetchOnWindowFocus: false`), or raise it substantially. Benchmark `oportunidades` with production-order row counts before G6; if the SRF dominates, precompute the veto set once into a CTE and anti-join, instead of correlating per person.

[P2] The state query polls a non-existent function every 15 s until F7 is installed
File:
CRM-Avance-Corp/app/src/data/metricas-multiempresa.ts
Lines:
10-11, 25-28
Problem:
`obtenerEstadoMetricasMultiempresa` maps `PGRST202` (function absent) to `{habilitada:false}` — a good pre-install degradation — but the query keeps polling at 15 s forever, and the nav entry is unconditionally visible to Gerencia (`router.ts` `VISTAS_GERENCIA`, `vistas.ts` `'informes-empresas': null`).
Evidence:
data:11 `if (r.error?.code === 'PGRST202') return {version:1, habilitada:false}`; data:27 `refetchInterval: 15_000`.
Impact:
Since F7 is deliberately not installed in production while G6 is pending, every Gerencia session that lands on this screen generates 4 PostgREST 404s per minute indefinitely — needless load and log noise on the exact deploy window where F7 is supposed to be invisible.
Recommendation:
Back off when the report is unavailable, e.g. `refetchInterval: (q) => (q.state.data?.habilitada ? 15_000 : 300_000)`, so a flag flip is still noticed without hot-polling a missing function.

[P2] `Empresa`/`Moneda` are hard-coded on the client while SQL enumerates `crm.empresas`
File:
CRM-Avance-Corp/app/src/lib/metricas-multiempresa.ts
Lines:
7-8, 38-41
Problem:
`v.picklist(['avance','qorilazo','prodelco'])` and `v.picklist(['PEN','USD'])` are compile-time constants, but `oportunidades` iterates `from crm.empresas e ... where e.activa` (migration:164-172) and `empresa` for a cierre is `ce.cooperativa` (migration:65, 76) — both data-driven.
Evidence:
metricas-multiempresa.ts:7-8; migration:65, 166, 172.
Impact:
Activating a fourth cooperativa, or recording a third currency, is a pure data change today — and it will take the entire report down with "El informe llegó incompleto", not degrade it. Failing closed is defensible, but the failure is indistinguishable from a transport truncation and the user has no recovery.
Recommendation:
Either constrain the SQL side to the three known `clave`s explicitly (so an unexpected empresa raises a named error server-side with a clear message), or relax the client picklist to `v.string()` with an explicit "empresa desconocida" rendering path. At minimum, make `EMPRESA_INFORME[r.empresa]` (screen:72, 98, 106, 123, 141) not render `undefined` for an unmapped key.

[P3] `fuentes_duplicadas` drives the verdict but is never shown
File:
CRM-Avance-Corp/app/src/lib/metricas-multiempresa.ts, CRM-Avance-Corp/app/src/screens/metricas-multiempresa.tsx
Lines:
lib:75; screen:144-147
Problem:
`estadoConciliacion` returns `'diferencias'` when `r.fuentes_duplicadas` is truthy, but the screen renders only the generic sentence "Hay diferencias que requieren revisión antes de aceptar el informe" and never displays the count or the per-group differences.
Impact:
Gerencia is told to review something with zero information about what differs — and a duplicate-source condition looks identical to a genuine capital gap.
Recommendation:
Render `fuentes_duplicadas` and the non-zero `conciliacion` rows (empresa/moneda/diferencia) inside the "Comprobación de cifras" card.

[P3] `P0409` (flag off) is presented as an access denial
File:
CRM-Avance-Corp/app/src/screens/metricas-multiempresa.tsx
Lines:
29, 31-32
Problem:
`cerrado` conflates `42501` (not authorized) with `P0409` (report in preparation), and the branch order puts it ahead of the dedicated "Informe en preparación" panel at lines 39-40.
Evidence:
screen:29 `error.code === '42501' || error.code === 'P0409'`; migration:97 raises `P0409` for the flag being off.
Impact:
If the flag is turned off between the state call and the data call (or the 15 s/30 s polls interleave across a flip), Gerencia is told "Tu acceso actual no permite consultar este informe" — a false statement about their permissions.
Recommendation:
Route `P0409` to the "Informe en preparación" panel and reserve the access-denied copy for `42501`.

[P3] Month input accepts syntactically valid but semantically invalid values
File:
CRM-Avance-Corp/app/src/screens/metricas-multiempresa.tsx
Lines:
54-55
Problem:
`/^\d{4}-\d{2}$/` admits `2026-00` and `2025-99`; the `<= hoy.slice(0,7)` string comparison lets both through (`'2025-99' <= '2026-09'`), and `min="2000-01"` is enforced only by the native control, which Firefox/Safari render as a plain text input for `type="month"`.
Impact:
`p_mes` becomes `'2025-99-01'` → Postgres date parse error (or `22023` from migration:99) → "No se pudo actualizar el informe". Fail-closed but confusing.
Recommendation:
Tighten to `/^\d{4}-(0[1-9]|1[0-2])$/` and enforce the `2000-01` lower bound in the handler.

[P3] `useDialogLayer` uses DOM order, not focus containment, as the layer-order proxy
File:
CRM-Avance-Corp/app/src/components/ui/dialog-layer.ts
Lines:
28-36
Problem:
The scan picks the document-last registered node with `data-state="open"` that follows the current one. Against the supplied Radix 1.1.19 / dismissable-layer 1.1.15 source I could not find a double-close or a swallowed-Escape path — the `evento.defaultPrevented` early return at line 26 correctly neutralises both listener orderings, and Radix's `if (!event.defaultPrevented && onDismiss)` then declines to dismiss the lower layer. So I am not asserting a defect. The residual concern is that DOM order is a proxy for "on top", and it ignores modality: a `modal={false}` Sheet portaled *after* a modal Dialog would be selected as `superior` even though focus is trapped in the Dialog, closing the background panel on Escape. I could not construct a reachable path to that state from the supplied evidence (a modal Dialog blocks the pointer interactions that would open a drawer), so I am marking this as a hypothesis, not a demonstrated bug.
Recommendation (optional hardening, not a blocker):
Prefer the registered node that contains `document.activeElement`, falling back to the current DOM-order scan. That is strictly closer to the reported signature (focus was in the child modal's `select#pv-retiro-estado` while the parent's listener fired), is not weaker in any case the current code handles, and removes the modality assumption.

[P3] `database.types.ts` is now a hand-maintained generated file
File:
CRM-Avance-Corp/app/src/lib/database.types.ts
Lines:
diff at 3356-3359
Problem:
The two new signatures were hand-integrated (your note: to preserve unrelated schemas absent from the synthetic bank), they are inserted out of the file's alphabetical order, and `metricas_multiempresa_estado_fn: { Args: never; ... }` does not match the generated convention used elsewhere in the file.
Impact:
The next full regeneration will reshape and reorder these entries, producing churn and a silent contract change in a file reviewers treat as machine-generated.
Recommendation:
Note the manual edit in the migration/PR description, or regenerate against a bank that contains the full production schema before production install.

TEST GAPS:
- No test runs real RPC output through `MetricasMultiempresaSchema` / `informeMultiempresaCompleto` (see P2). This is the single highest-value missing test.
- No demo-Gerencia fixture in `fixture.usuarios`; `http.test.mjs:21-32` cannot prove demo isolation either way.
- No case with two `medida='stock'` episodes on one `fuente_id` (the fan-out class in P1).
- No case where a source is demo under one reader and not the other (P2), nor a núcleo-only empresa/moneda group (P2) — the latter is currently *impossible* to observe end-to-end because the client rejects the payload.
- The reversal test cannot observe the F7 objects (P2); `reversa-operativa.sql` was not supplied.
- Boundary coverage is asymmetric: `metricas.test.mjs:122-147` tests the Lima start boundary (04:59:59Z vs 05:00:00Z) but not `v_fin` — an episode at exactly `(v_hasta+1) 00:00` Lima, where `fuentes` excludes it via `fecha_imputacion<=v_hoy` (migration:108) but `capital_nucleo` includes it if `capital_episodios` treats its upper bound as inclusive.
- Dialog fix: `dialog.test.tsx` exercises only `modal={false}` nesting (`:26`). If the production drawer is a modal Sheet, the focus-trap path that actually regressed is uncovered. No test asserts the `capas` registry is emptied on unmount, and none covers three stacked layers.
- `tipos_capital` and `atribucion` tables have no empty-state row (screen:98, 141), unlike `TablaCapital` (screen:74); with a currency filter applied they render header-only.

ARCHITECTURE RISKS:
- Two sources of truth for `estado`/`vence_en`: `metricas_f7_fuentes` exposes `e.estado` from `capital_episodios` (migration:68-69) while the vencimientos test computes the expectation from `cartera_f5_fuentes().estado` (metricas.test.mjs:176-178). They agree in the bank; nothing enforces that they keep agreeing.
- The hash preflight (migration:9-19) protects only the install instant. After installation F7 silently inherits any change to the four readers. That is acknowledged in CONTRATO.md, but there is no periodic drift check.
- `participantes` applies `private.inversionista_canonica()` to cotitulares (migration:135) but not to the titular id from the F5 reader (migration:68). Correct only if `cartera_f5_fuentes` already returns canonical ids — the comment at migration:52 asserts it does; worth a one-line test rather than a comment.

SECURITY RISKS:
- The demo-account gap in [P1] is the only exposure I can substantiate.
- Otherwise the posture is good: `search_path=''` with `auth.uid()` schema-qualified, definer helpers revoked from `public/anon/authenticated/service_role` and verified at runtime (metricas.test.mjs:39-41), the postflight enforcing `prosecdef`/`provolatile='s'`/owner/`proconfig` and no PUBLIC grantee (migration:234-243), and no caller-supplied scope argument. `atribucion` exposes only `perfiles.nombre_completo` and analyst ids, which Gerencia already sees elsewhere.

REGRESSION RISKS:
- `useDialogLayer` is now on the Escape path of *every* `Dialog` and `Sheet` (3 + 1 call sites per CodeGraph), so the blast radius of the layer fix is all modals, not just the F6 drawer. The 4 unit tests plus 164 Playwright specs are reasonable coverage, but the modal-Sheet nesting path is untested (above).
- Radix layers that are *not* registered (dropdown/popover/select content, if any exist) remain outside the mitigation. In the reported repro the culprit was a native `<select>` (`@/components/ui/select` renders `<option>` children directly, screen:92), so this is a scope limitation rather than a regression.
- `'informes-empresas'` now appears in the Gerencia sidebar the moment this branch deploys, before G6 sign-off. Non-demo Gerencia sees "Informe en preparación" (graceful), but demo Gerencia sees a fully populated fabricated group report behind a "Vista previa" badge and a "Demostración" banner. That is a product-visibility call, not a defect — flagging it so it is a decision rather than a side effect.

EVIDENCE NOT SUPPLIED (limits several findings to hypotheses):
- `private.capital_episodios`, `private.conversion_episodios`, `private.cartera_f5_fuentes`, `private.peso_referido_conversion`, `private.leads_de_persona_veto`, `private.inversionista_canonica` definitions — needed to resolve the demo asymmetry (P2), the `divisor` domain (P2), the `v_fin` boundary (test gap) and the stock-episode multiplicity question (P1).
- `supabase/scripts/multiempresa-f7/reversa-operativa.sql` and `banco-local.mjs`.
- `app/src/lib/demo-metricas-multiempresa.ts` — the sole fixture for every frontend unit test.
- `app/e2e/multiempresa-f7.spec.ts`.
- `app/src/components/app/ayuda-vendedor-panel.tsx` — modified in the working tree with no diff or rationale attached.
- The diffs for `sidebar.test.tsx`, `vistas.test.ts`, `vistas-gerencia.test.ts`.

RECOMMENDED NEXT ACTIONS:
1. Resolve [P1] demo-Gerencia: check the convention in the other published definer RPCs; add the predicate + an HTTP fixture, or document the client-only boundary in CONTRATO.md for G6.
2. Fix [P1] by making `primeras` source-unique (`select distinct ...` before `row_number()`), and add a two-stock-episode bank case.
3. Add the missing coupling test: real RPC JSON → `MetricasMultiempresaSchema` + `informeMultiempresaCompleto`. Resolve `conversion.divisor`'s integrality while you are there.
4. Relax `informeMultiempresaCompleto` to accept núcleo-only reconciliation groups with zero informe values, and surface `fuentes_duplicadas` + non-zero differences in the UI.
5. Clarify/align the demo predicate between `fuentes` and `capital_nucleo`; extend the reversal test to observe the F7 objects; supply `reversa-operativa.sql`.
6. Drop or lengthen the two `refetchInterval`s and back off the state poll when the report is unavailable; benchmark `oportunidades` at production row counts before G6.
7. Low cost, do opportunistically: month-input regex, `P0409` routing, optional `activeElement` refinement in `useDialogLayer`.

CONFIDENCE:
MEDIUM — HIGH on the client-side findings (P2 reconciliation gate, schema/test coupling, polling, picklists) and on the reversal-test blindness, which are fully determined by the supplied files. MEDIUM on [P1] demo isolation and [P1] fan-out, both of which hinge on definitions not included in the evidence. The Dialog/Sheet fix I reviewed against the installed Radix source you supplied and found no demonstrated defect; my only note there is a hardening suggestion, explicitly marked as a hypothesis.
