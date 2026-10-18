VERDICT:
CHANGES_REQUESTED

SUMMARY:
The SQL migration fails closed in the right places. It checks anchor counts, pins the hashes of the reader, the testigo and the cierres core, compares the census and the function attributes before and after, and keeps the old testigo shape alongside a separate `comercial` testigo. Excluding the protected-role DEFAULT PRIVILEGES is adequate for this migration. I found three accountable problems:

- The valuation reader `private.citas_gerencia_consulta_corte` gets rewritten and re-sealed without its own prosrc hash or declaration check.
- Ambiguity of the commercial date may be counted in different windows in two places.
- The HTTP matrix never checks the payload against the real front contract, never takes the valuation path, and never asserts actual `fecha_comercial` values.

I could not verify the strict date helpers themselves (`fecha-comercial.ts`, `FechaSchema`, `CamposGestionMensualSchema`). Those were not attached, and the capital date check depends on them.

FINDINGS:

[P1] Valuation reader is rewritten and re-sealed without a pinned hash or declaration check
File: `supabase/migrations/20261017043000_crm_citas_fecha_comercial.sql`
Lines: 18–41, 44–51, 364–371
Problem: The preflight pins `md5(prosrc)` only for `citas_gerencia_consulta`, `citas_testigo_mes` and `conversion_cierres`. It requires exactly 2 matching declarations, covering only consulta and testigo. The `$lectores$` loop still rewrites `private.citas_gerencia_consulta_corte(date,date,uuid)`, and lines 364–371 recompute its `huella` and re-seal it.
Evidence:
- `to_regprocedure('private.citas_gerencia_consulta_corte(...)')` is in the rewrite array (line 49) and in the huella update (line 370).
- It is absent from both preflight checks (lines 20–28, 34–39).
Impact: Suppose `consulta_corte` drifted in production, either from the TC-per-sale merge 6f176603 or by hand, while still matching the six anchors. The migration would then bless the drifted body with a fresh declaration and seal. That hides exactly the kind of drift the governance seal exists to catch. This is the capital / financial path.
Recommendation:
- When `to_regprocedure(...) is not null`, pin its expected `md5(prosrc)`, taken from the post-6f176603 production body.
- Require its declaration's huella to match before the rewrite, so the expected count becomes 3 when it exists.
- If no declaration row exists for it, fail rather than silently updating zero rows.

[P2] Commercial-date ambiguity may be counted over different windows
File: `supabase/migrations/20261017043000_crm_citas_fecha_comercial.sql`
Lines: 68–76 (anchor p1), 83–93 (anchor p4), 205–225 (testigo)
Problem: Three places decide whether a lead's commercial date is ambiguous:
- **Top-level `conversiones` (p1):** calls `conversion_cierres('-infinity', v_ahora+1µs, …)`, so it counts over all time.
- **Testigo `nucleo`:** also all time, with `null::uuid[]`.
- **`gestion.conversiones` (p4):** counts `hechos_comerciales` over a `conversion_cierres(` call whose leading arguments are not part of the anchor and were not shown. The comment says "La unicidad es global", but if that call is bounded to the period, the count is only period-local.
Evidence: p4 only replaces the text *around* `private.conversion_cierres(`. The time-window arguments come from the original body, which was not attached.
Impact: Take a lead with one cierre this month and one in an earlier month. Under the hypothesis, `gestion.conversiones` would give it a `fecha_comercial`, while the testigo would exclude it. The front would then raise `testigoCuadra === false`, and the month would show "En revisión" and block CSV export. That is fail-closed, but it is a false block in production.
Recommendation:
- Attach the full p4 call, or confirm its window is `-infinity`.
- Add an SQL or HTTP fixture: a lead with one cierre in September and one in October. Assert `fecha_comercial` is null in both payloads and the testigo excludes it.

[P2] Capital month filter uses `k.fecha`, while sales use the commercial date
File: `app/src/components/citas/avance.ts`
Lines: 97–98, and `app/src/data/citas-gerencia.ts` lines 158–160, 176
Problem: Conversions are bucketed with `ventaComercialDelMes`. Capital is bucketed with `Date.parse(k.fecha)` against Lima-instant bounds. The contract only checks that `k.fecha_comercial !== undefined`. It never checks that `k.fecha_comercial` falls inside the month, or that it is consistent with `k.fecha`.
Evidence: The CSV states `'Criterio del mes de ventas' = 'Fecha comercial'` for every row (`avance-csv.ts:15`). The ticket and projection are computed from capital filtered by `k.fecha`.
Impact (hypothesis; the schema was not attached):
- If `k.fecha` is the registration instant, a late-loaded sale lands in the wrong month for ticket and projection, while the CSV claims the commercial criterion.
- If `k.fecha` is a date-only string, `Date.parse('2026-10-01')` is UTC midnight, which is 19:00 Lima on 09-30. `fechaLima` would then fail the contract (line 176) and the whole module would show `CITAS_CONTRATO`.
Recommendation:
- State, and attach as evidence, what `k.fecha` is in `CamposGestionMensualSchema`.
- When valuation is present, assert `k.fecha_comercial` is inside `[desde, hasta]` in the contract.
- Add a fixture with a late-loaded sale: commercial date in September, registered in October.

[P2] HTTP matrix gaps
File: `supabase/scripts/citas-fecha-comercial/http-cloud.mjs`
Lines: 40–64
Problem and evidence:
- **No real-contract check.** The payload is never parsed with `ConsultaCitasSchema` or run through `cargarCitasGerencia`'s checks. The strict front contract (duplicate leads, capital/valuation consistency, `|monto*tasa − equivalente_pen|`) is never exercised against a real response. A schema mismatch would disable the entire Citas module in production.
- **No reconciliation check.** `calcularAvanceCitas(...).testigoCuadra === true` is never computed on the real payload. That is the actual release gate in the UI (`avance-mensual.tsx:92–98`).
- **Presence, not values.** Line 54 only checks `Object.hasOwn(c,'fecha_comercial')`. It does not assert the expected value per lead, the null for an ambiguous lead, or the null for a supervisor when the cierre belongs to another team (p1 `bool_or(v_rol='gerencia' or …)`).
- **Top level never asserted.** Top-level `r.data.conversiones[].fecha_comercial` is never checked; only `gestion.conversiones` is.
- **Valuation path never taken.** Nothing calls a cutoff, so `consulta_corte` is never reached. There are no saved, pending or absent capital fixtures over HTTP, even though the SQL suite has them.
- **Invalid input not tested.** Calls with an invalid month (mid-month `p_desde` → 22023) are missing.
- **Denied roles unlabelled.** It is unclear which identities 3, 6 and 7 represent. Add an authenticated user without a CRM profile if none of them is that.
Impact: The HTTP matrix mostly tests auth and denial, but not the integration that is actually being released.
Recommendation: Add the checks above, in particular schema plus reconciliation over the real payload for September and October with gerencia, and one call through the valuation reader.

[P3] Postflight anon check covers only v1
File: migration
Lines: 389–391
Problem: Only `crm.citas_gerencia_consulta_fn` is checked for anon. The front calls `citas_gerencia_consulta_v2_fn` first.
Recommendation: Also assert that anon has no EXECUTE on the v2 wrapper. Optionally assert that `authenticated` keeps it, to catch an accidental revoke.

[P3] `cerrado` marker ignores cita status
File: `app/src/data/citas-gerencia.ts`
Lines: 97–99
Problem: In V2, `entrevistaCompatibleConVenta(c.asistencia_registrada_en ?? c.vence_en, …)` applies to cancelled, no_show and pending citas alike. The comment says "con las mismas exclusiones del servidor", but the code applies no status exclusion.
Impact: A cancelled cita dated before the sale shows as `cerrado`. This affects display only, not the testigo.
Recommendation: Confirm this matches the server's exclusions, or gate it on `estado==='completada'`.

TEST GAPS:
- Real-payload `ConsultaCitasSchema` parse plus `testigoCuadra===true` for gerencia, September and October.
- Lead with two non-annulled cierres in different months: null in both payloads, excluded in the testigo, no false "En revisión".
- Late-loaded sale (commercial September, registered October), checked for capital/ticket as well as clients.
- HTTP call through `citas_gerencia_consulta_corte` with saved, pending and absent cutoffs.
- Sale and interview on the same day, interview later that same day: currently counted as compatible, by design; pin it with a test.

ARCHITECTURE RISKS:
- Anchor-based text substitution over `pg_get_functiondef` is brittle. It fails closed, which is acceptable, but every future change to these readers must update the anchors.
- The commercial testigo duplicates the identity and interview CTEs of the old one. Divergence later is likely; consider extracting them once the old testigo is retired.

SECURITY RISKS:
- No regression found in the shown code. `CREATE OR REPLACE` preserves owner, ACL, SECURITY DEFINER and `search_path`, and the attribute snapshot in lines 384–388 verifies this.
- The testigo's gerencia gate is unchanged, and the HTTP suite confirms supervisors receive no `testigo`.
- Excluded DEFAULT PRIVILEGES: the migration creates no persistent objects. Its temp tables live in `pg_temp` and are dropped on commit, and default ACLs do not apply to `CREATE OR REPLACE`. The exclusion is therefore immaterial here.
- Note that the branch is not valid evidence for future migrations that create objects in `public`, and advisory deltas around default ACLs should not be compared.

REGRESSION RISKS:
- The production preflight hashes must equal the post-6f176603 bodies. A successful apply on a branch restored from current production supports this. Re-check the hashes immediately before applying to production.
- A false testigo mismatch, as described in the P2 window finding, would hide the deposit rate, the projection and the CSV for the whole month.

RECOMMENDED NEXT ACTIONS:
1. Pin the prosrc hash and declaration of `consulta_corte` in the preflight. Fail if it exists without a declaration.
2. Attach the full p4 `conversion_cierres(` call and confirm its window is global. Add the two-cierres fixture.
3. Attach `fecha-comercial.ts`, `FechaSchema` and the capital part of `CamposGestionMensualSchema`, and clarify what `k.fecha` means relative to `k.fecha_comercial`.
4. Extend `http-cloud.mjs` with the real-payload schema and reconciliation checks, explicit `fecha_comercial` values, and the valuation path. Add the v2 anon check to the postflight.

CONFIDENCE:
MEDIUM. The SQL and permissions analysis is grounded in the attached code. The P2 window and capital-date findings are hypotheses that depend on code that was not attached.
