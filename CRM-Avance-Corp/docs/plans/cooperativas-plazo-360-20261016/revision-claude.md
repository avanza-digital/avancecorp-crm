VERDICT:
CHANGES_REQUESTED

SUMMARY:
The core arithmetic is correct and consistent between TypeScript and SQL. I checked all seven 30-day cases by hand, including the leap years 2024 and 2028 and the 2027-08-27 UI case. Historic rows are preserved by the `ADD COLUMN … DEFAULT 'calendario'` then `SET DEFAULT 'dias_360'` pattern. The correction path correctly reads the stored convention.

Four things need work before SQL approval or a branch trial:
- **Deployment sequencing:** there is an unaddressed window where new conversions are rejected.
- **Drift guard:** it does not cover the constraint being dropped.
- **Caller privileges:** the new helper's revoked privileges have not been checked against the security context of the three callers.
- **Untested authenticated paths:** the paths whose behavior actually changes, conversion and correction, are never executed.

None of these is P0. The design itself is sound.

FINDINGS:

[P1] Frontend/SQL deploy skew blocks every new cooperative conversion
File: `coopac-condiciones.ts` (`vencimientoCoopac`); migration lines for `private.coopac_validar_condiciones` (3-arg, now `'dias_360'`)
Problem: The client computes `vence_en`. The server validates it by exact equality against the 3-arg helper (stated: "validator compares input vence_en with the existing 3-argument helper, as do new initial conversions").
Evidence: There are two orderings, and both fail:
- New SQL first: old bundles send calendar dates (`2027-09-14`) and the server now expects `2027-09-09`.
- New frontend first: the old server expects calendar dates.

The app ships a PWA (`pwa-gerencia.css`, `version-publicada.css`), so stale bundles can persist after a deploy.
Impact: Every Qorilazo/Prodelco conversion fails with a 22023 mismatch until the user's client updates.
Recommendation:
- Document an explicit sequence: apply SQL, then immediately publish the frontend.
- Verify the published-version or forced-refresh mechanism covers this bundle.
- Confirm the mismatch error tells the user to reload or recalculate, rather than showing a generic message.
- Alternatively, accept both conventions for a short window. That adds complexity, so the documented sequence is preferable.

[P2] Drift guard does not cover the dropped CHECK constraint
File: migration, `do $deriva$` block and `drop constraint cierres_coopac_condiciones_completas`
Problem: The guard checks md5s of the two function bodies only. The migration then drops and re-creates `cierres_coopac_condiciones_completas` from a reconstructed definition.
Evidence: There is no `pg_get_constraintdef` comparison. If production's constraint differs from the snapshot used to write this draft, the extra conditions would be silently lost. That could happen through a hotfix or an extra clause such as a `vence_en >= fecha_comercial` bound.
Impact: Integrity rules on financial maturity dates could be lost without anyone noticing.
Recommendation: Add `md5(pg_get_constraintdef(oid))` for that constraint to `$deriva$`, using a hash read from production.

[P2] New helper's revoked privileges vs. the callers' security context (hypothesis; evidence not supplied)
File: migration, `revoke all on function private.coopac_validar_condiciones_base(...) from public,anon,authenticated`. The 3-arg wrapper is plpgsql with no `SECURITY DEFINER`.
Problem: The 3-arg wrapper runs with the caller's privileges and now calls the 4-arg helper, which has `EXECUTE` revoked from `PUBLIC`.
Evidence: Only `inversionista_corregir_coopac_fn` is shown as `SECURITY DEFINER`. The security mode and owner of these two callers are not supplied:
- `crm.convertir_lead_externo`
- `private.inversion_validar_datos`

The runner bypasses roles entirely, and you explicitly do not claim authenticated RPC success.
Impact: If any caller runs as `authenticated`, conversion or confirmation fails with `42501`. One example is an invoker function reached from a definer function owned by a role other than `postgres`.
Recommendation:
- Attach `prosecdef` and `proowner` for all three callers.
- In the branch trial, run conversion and confirmation as `authenticated` via `set role` plus JWT claims.

[P2] Changed authenticated paths are never executed
File: SQL test runner
Problem: The runner calls the helpers and raw `INSERT`/`UPDATE` only. Three paths are untested:
- `crm.convertir_lead_externo`, a new row with a 360-day `vence_en`.
- Confirmation of a prepared request with an old calendar `vence_en`, which should be rejected and must not be mutated.
- `inversionista_corregir_coopac_fn`, changing the term on a `calendario` row and on a `dias_360` row.

Evidence: Every `DO` block uses direct DML with `session_replication_role=replica`. In particular, the correction call `crm.corregir_cierre_externo(..., v_vence, ...)` receives the new date. Its body is unchanged but its behavior is not verified; it could contain its own date logic.
Impact: The paths whose behavior actually changed are the ones left unverified.
Recommendation: Add these three cases to the Supabase branch trial with real roles and synthetic data. This is proportionate for LEVEL 3.

[P3] Historic rows without conditions stay `calendario` when conditions are first added
File: migration, correction function `else` branch, using `v_ce.base_plazo`
Problem: A pre-migration row with `plazo_meses IS NULL` that Gerencia later gives a term will be computed on a calendar basis.
Evidence: All existing rows get `'calendario'`, and the correction path always uses the stored value.
Impact: This matches "existing contracts retain convention", but it may surprise users if they consider these to be "new" conditions.
Recommendation: Confirm this with the user. Otherwise there is no change needed.

[P3] `CASE base_plazo` has no `ELSE`
File: migration, `cierres_coopac_condiciones_completas`
Problem: An unknown `base_plazo` makes the expression evaluate to `NULL`, which a CHECK treats as passing.
Evidence: This is currently masked by `NOT NULL` and `cierres_coopac_base_plazo`.
Impact: There is no live bug, but the constraint is fragile if the convention set is ever extended.
Recommendation (optional): Add `else null` and a comment, or `and base_plazo in (...)` inside the same CHECK.

[P3] Upper-bound asymmetry between TypeScript and SQL
File: `coopac-condiciones.ts` (`<= 9999` → `null`) vs. the 4-arg helper (no year bound)
Impact: This only matters for absurd dates near year 9999. The server accepts dates the client cannot produce.
Recommendation: Ignore it, or add a matching bound in SQL.

TEST GAPS:
- **Runner snapshot when already installed:** when `ya_instalada` is true, `foto_funciones` is captured after the migration. The ACL/owner and "unrelated functions" checks then compare the database against itself and prove nothing. The pending final whole-runner pass must run on a fresh clone, and its output should be attached.
- **Restored local draft:** `leerIntentoInversion` stores a draft containing `vence_en`. There is no test that a draft saved under the old convention is recalculated rather than resubmitted unchanged. This is a hypothesis; the restore code was not supplied.
- **Correction form preview:** it is not shown whether the form ever displays a client-computed `vencimientoCoopac` date for a `calendario` row. If it does, the preview disagrees with the server result. Please supply the source of the correction form's date display.
- **Other date consumers:** there is no evidence about whether any report or accrual code (e.g. `valorContratoAFecha`) derives cooperative maturity or interest from `plazo_meses` rather than the stored `vence_en`.

ARCHITECTURE RISKS:
- Storing the convention per row is the right design. The 3-arg wrapper, defaulting to new rows, keeps call sites stable.
- Rollback is one-way once `dias_360` rows exist, as the migration header correctly states.

SECURITY RISKS:
- No privileges are expanded, and the revoke list on the new helper is correct.
- The only risk is the `42501` failure described above, which breaks functionality rather than exposing anything.

REGRESSION RISKS:
- Deploy skew or stale PWA bundles, as above.
- The 3 prepared production requests will be rejected on confirmation. Identify them before deployment and notify their owners.
- The revision md5 changes for every row, so open correction forms will get PT409 once. This is expected.

RECOMMENDED NEXT ACTIONS:
1. Add the constraint-definition hash to `$deriva$`.
2. Supply `prosecdef` and owner for the three callers, and test conversion, confirmation and correction as `authenticated` in the branch trial.
3. Write the deploy runbook: SQL then frontend, the PWA refresh path, and a list of the 3 prepared requests to follow up.
4. Run the final whole runner on a fresh clone and attach the output.

CONFIDENCE:
MEDIUM. The arithmetic and preservation logic are high confidence. The P2 privilege item is a hypothesis pending caller metadata.
