VERDICT:
CHANGES_REQUESTED

SUMMARY:
From the attached evidence, the SQL read rewrite (`cartera_f5_personas_visibles`) keeps the same meaning as the original. I found no semantic divergence in authorization, lector/Directorio, supervisor inbox, demo exclusion or fusion resolution. The COOPAC annual-rate and calendar-month semantics are correct and consistent across frontend, the SQL helper and the CHECK. The legacy hash is byte-identical when plazo/tasa are absent. There are no P0/P1 findings.

Several concrete P2 issues should be fixed or verified before the SQL approval request:
- One stated stale-UI contract is not fully met.
- ACL parity for the dropped/recreated RPC is asserted only for `anon`.
- The initial-closure date is computed client-side and can diverge from the server's Lima date.
- The prior per-field accessibility fix (M2) regresses in the COOPAC form.

FINDINGS:

[P2] PostventaPersona mutations stay enabled while the ficha is stale
File: `app/src/components/app/inversionista-ficha.tsx`
Lines: Seguimiento section, `{ficha.capacidades.postventa && <PostventaPersona actor={actor} ficha={ficha} .../>}`
Problem: `desactualizada` gates `InversionDetalle.postventa`, `onDocumento`, `onRecuperarPdf`, `onOperacion`, the new-investment CTA and contact. It does not gate `PostventaPersona`, which receives the stale `ficha` snapshot.
Evidence: The only postventa gating added is `postventa={ficha.capacidades.postventa && !desactualizada}` on `InversionDetalle`. `PostventaPersona` is rendered unconditionally from `ficha.capacidades.postventa`, and `retiroElegido` can still be set from a previous state.
Impact: This contradicts the stated contract that transient errors disable mutation CTAs. Users can start postventa gestiones or retiros against capabilities confirmed before the failure. The server should still enforce authorization, so this is a correctness/UX contract gap, not a security hole.
Recommendation: Gate the component with `ficha.capacidades.postventa && !desactualizada`, or pass a `deshabilitado` prop. Also clear `retiroElegido` when `desactualizada` becomes true. Add an assertion to the existing "fallo transitorio" test.

[P2] ACL parity of `crm.convertir_lead_externo` verified only for `anon`
File: `supabase/migrations/20260914213928_crm_coopac_condiciones_anuales.sql`
Lines: 64 (`drop function ...`), 1153–1156 (revoke/grant)
Problem: DROP+CREATE discards the original `proacl`. The new ACL is `revoke public,anon,authenticated` plus `grant authenticated`. Any explicit grant the old function had (e.g. `service_role`, used by edge/scripts) now depends on schema default privileges in `crm`. The reverse can also happen: a role could gain a grant it did not have.
Evidence: The backend test only checks `has_function_privilege('anon', ..., 'execute') = f`. It never compares `pg_proc.proacl` before and after.
Impact: A silent permission change on a production write RPC, in either direction.
Recommendation: In the guarded replay, capture `proacl` of the old signature and assert that the new signature's `proacl` is equal. If it differs, replicate the exact grants explicitly.

[P2] Initial COOPAC closure: client-computed `venceEn` can be rejected, or break the idempotent retry, around Lima midnight or with a skewed device clock
File: `app/src/components/app/lead-drawer.tsx` (`const fechaCoop = fechaLima(Date.now())`, submit sends `venceEn: condiciones.venceEn`); `app/src/data/crm-api.ts` (`p_vence_en: datos.venceEn`); migration lines 336–342 and 257–264
Problem: The server derives the maturity from `now() at time zone 'America/Lima'` and raises 22023 if `p_vence_en` differs. The client derives it from the device clock at render time.
Evidence:
- `if p_vence_en is not null and p_vence_en is distinct from v_vence then raise ... '22023'`.
- The idempotency hash includes `'vence', p_vence_en` (the client value).
Impact:
- (a) If the device date is wrong, every COOPAC initial closure fails with "El vencimiento debe corresponder…", with no way to fix it from the UI.
- (b) If a response is lost near midnight and the user resubmits after a re-render, `p_vence_en` changes. The hash no longer matches the stored key, so a successful conversion surfaces as a conflict instead of `reintento: true`.
Recommendation: For the new flow, send only `p_plazo_meses`/`p_tasa_anual` and omit `p_vence_en`. The server already derives and stores `v_vence`, and the hash stays stable. Keep the displayed maturity as a preview only. Old bundles keep their current behavior.

[P2] Accessibility regression of the earlier M2 fix in the COOPAC conversion form
File: `app/src/components/app/lead-drawer.tsx` (fieldset around `CondicionesCoopac`); `app/src/components/app/condiciones-coopac.tsx`
Problem: The removed `cx-vence` input carried `aria-invalid`/`aria-describedby="cx-error"` per field. The code comment cites that as finding M2. Now `aria-invalid`/`aria-describedby` sit on a `<fieldset>` (role group). The plazo and tasa inputs receive neither, and `CondicionesCoopac` has no way to forward them.
Evidence:
- `<fieldset aria-label="Condiciones de la inversión" aria-invalid={...} aria-describedby={...}>`.
- The `Input`s in `condiciones-coopac.tsx` have no `aria-invalid`.
- `aria-invalid` is not supported on `group` in ARIA 1.2.
Impact: Field-by-field screen-reader users hear the alert but not which field (plazo or tasa) is wrong, which is exactly what M2 fixed. The F5 additional form (`InversionCooperativa`) has the same gap.
Recommendation: Have `condicionesCoopac` return which field failed (`'plazo' | 'tasa'`). Add an `invalido?: 'plazo'|'tasa'` and `describedBy` prop to `CondicionesCoopac`, and apply them to the specific `Input`.

[P2] (hypothesis) "Renovación pendiente" can stick permanently for any matured COOPAC source
File: migration 1159 lines 891–894 (`continuidad`); `inversionista-ficha.tsx` (`pendiente = vencimiento <= fechaLima(...)`)
Problem: `proximo_vencimiento = coalesce(max(overdue), min(future))` over sources with `estado in ('activo','vigente','vencido')`. In `cartera_f5_fuentes`, a COOPAC source becomes `'vencido'` once `vence_en < today`, and it has no terminal state other than anulado.
Evidence: The `cartera_f5_fuentes` coop estado `case` has no settled/renewed state. `max(...) filter(where vence_en<=today)` wins over any future maturity.
Impact: A client who renewed a matured COOPAC investment as a new cierre would still show "Renovación pendiente" with the old date, hiding the real next maturity. Avance contracts are probably unaffected if they move to a terminal state.
Recommendation: Confirm against the original Ficha 360 rule (`construirVistaCliente360`). If that rule only considered the active/next maturity, restrict the overdue branch accordingly (e.g. an overdue window, or exclude overdue items superseded by a later source of the same company). Add a test with one matured plus one future coop source.

[P3] Post-confirmation maturity correction on new rows fails with a raw CHECK error
File: migration lines 29–38; `crm.corregir_cierre_externo` (not attached)
Problem: For rows with plazo/tasa, any correction that changes `vence_en` (or `fecha_comercial`, if that path allows it) without updating plazo violates `cierres_coopac_condiciones_completas` (23514).
Evidence: The CHECK pins `vence_en = fecha_base + plazo months`. The PRIMARY confirms the corrector allows maturity changes.
Impact: Historical rows (NULL plazo/tasa) are unaffected, so this is not a regression for existing data. On new rows, gerencia gets an opaque error instead of a business message. Data integrity is preserved, which is the right direction.
Recommendation: Not blocking. Before the pilot, either map 23514 for this constraint to a readable message in that RPC's error handling, or document that term corrections on new rows are out of scope. I would not relax the CHECK.

[P3] Stale contact links lose focusability and link semantics
File: `app/src/components/app/ficha-comercial.tsx` (`FichaComercialContacto`, `href={habilitado ? ... : undefined}`)
Evidence: An `<a>` without `href` is neither focusable nor a link. If focus was on "Llamar" when the refetch fails, focus drops to `body`. The existing test only checks focus preservation on the "Copiar correo" button.
Recommendation: When disabled, render a disabled `<button>` or a `<span role="link" aria-disabled="true" tabIndex={0}>`, and keep focus. Also remove `target="_blank"` when there is no `href`.

[P3] `enfocarInversiones` leaks to a different person through the `hashchange` path
File: `app/src/screens/cartera-inversionistas.tsx`
Evidence: `volverAInversiones` is reset only inside `seleccionar()`. The `hashchange` listener calls `setSeleccion` directly. After returning from `InversionNueva`, navigating by hash to another person mounts that person's ficha with `enfocarInversiones=true`.
Recommendation: Call `setVolverAInversiones(false)` in the `cambiar` handler as well.

[P3] Motivo text shown to users who have no investment action
File: `inversionista-ficha.tsx`, `{!ficha.capacidades.nueva_inversion && <p>{motivo_no_operable}</p>}`
Evidence: Previously this text was rendered only inside `onNuevaInversion && ...`. It now appears even when `permiteInversion` is false (e.g. Directorio sees "Acceso de solo lectura").
Recommendation: Gate it with `onNuevaInversion &&` as before, unless the change is intentional.

[P3] No sanity upper bound on the manual annual rate
Files: `coopac-condiciones.ts`, `coopac_validar_condiciones`
Evidence: `tasa > 0` with two decimals is the only rule, so a typo like `120` or `1200` is accepted on both sides.
Recommendation: This is optional and a business decision. Consider a UI confirmation or a bound, such as ≤ 100.

Confirmed OK (no action needed):
- **Personas rewrite parity.** Each CTE maps 1:1 to the prior subqueries: canonical resolution via `identidades`, `con_historia` NULL exclusion through the joins, supervisor inbox, `perfiles_cliente`, and fuentes/demos from a single `cartera_f5_fuentes()` call. Array ordering changes only affect `perfil_ids`/`lead_ids`, which are stripped from the ficha and used only with `= any()`.
  - Hypothesis: the lector branch now additionally requires `p.rol='cliente'`. It is equivalent only if `private.cliente_ids_visibles_crm()` returns only cliente profiles. The bank parity (Directorio = 9) supports this, but it is data-dependent.
- **Legacy idempotency.**
  - Hash: with plazo and tasa both null the added expression is `|| '{}'`, so the hash is unchanged.
  - Pre-lot fallback: the added `is not distinct from` also matches null↔null.
- **Additional investments (F4).** The allowlist is updated in both `preparar_inversion_fn` and `inversion_validar_datos`. Validation runs only when the keys are present, so stored old requests still validate. `confirmar` revalidates stored datos before insert, and the CHECK is the backstop.
- **Calendar semantics.** `date + make_interval(months=>n)` clamps end of month (Jan31→Feb28/29, Feb29+12→Feb28), matching the frontend tests. The rate is stored as an annual percentage with no payment or schedule calculation.
- **Coop-only clients.** No portal-profile path was introduced. `cuentas_perfil_ids` still requires `rol='cliente'` profiles.

TEST GAPS:
- No before/after `proacl` equality check for `convertir_lead_externo` (all roles, including `service_role`).
- No SQL test of a legacy 11-argument call (old bundle), with an idempotency key stored before the migration, returning `reintento: true` afterwards.
- No test that `PostventaPersona` CTAs are disabled while stale.
- No test for a date/clock mismatch between client and server in the initial closure.
- No test of `corregir_cierre_externo` on a row with plazo/tasa (maturity changed vs. unchanged field corrections).
- No `continuidad` test with a matured coop source plus a future source.
- The a11y test for plazo/tasa error association is missing.
- Seed/RLS preflight and gate-realidad were NOT RUN. These remain mandatory gates before merge, not optional.

ARCHITECTURE RISKS:
- `inversionista_ficha_fn` still materializes all visible persons twice per call (pre and post check) and filters afterwards. It is acceptable at current volume (0.2–0.39 s local), but this is the next scaling ceiling.
- Server-side, plazo/tasa are optional for any client, which is the intentional compatibility decision. Enforcement that "new UI requires both" lives only in the frontend. Record the planned removal date for legacy acceptance.

SECURITY RISKS:
- ACL drift on the recreated RPC (see P2).
- The new helper is revoked from `authenticated` and invoked only inside SECURITY DEFINER callers. That is OK.
- No new table or column grants (verified).

REGRESSION RISKS:
- The a11y M2 regression in the COOPAC form.
- The CHECK introduces a hard failure mode on gerencia corrections for new rows.
- `ALTER TABLE ... ADD CONSTRAINT` takes ACCESS EXCLUSIVE and validates the table. It is small, but consider `set local lock_timeout` in both migrations for the production apply.

RECOMMENDED NEXT ACTIONS:
1. Gate `PostventaPersona` (and `retiroElegido`) on `!desactualizada`, and extend the transient-failure test.
2. Add a `proacl` before/after equality assertion for `convertir_lead_externo` to the guarded replay, and fix the grants if they differ.
3. Stop sending `p_vence_en` from the new initial-closure flow and let the server derive it. Keep the UI value as a preview.
4. Restore per-input `aria-invalid`/`aria-describedby` for plazo/tasa in both COOPAC forms.
5. Verify the `continuidad` rule against the original Ficha 360 semantics, and add the matured+future test.
6. Decide how the 23514 message is presented in `corregir_cierre_externo`. Not blocking.
7. Run the seed/RLS preflight and gate-realidad in an environment with `SUPABASE_URL` before requesting exact SQL approval.

CONFIDENCE:
MEDIUM. The SQL and frontend diffs are complete for the reviewed paths. `PostventaPersona`, `FichaComercialSeccion`, `corregir_cierre_externo`, `corregir_solicitud_inversion_fn`, `idem_leer`/`idem_hash`, `cliente_ids_visibles_crm` and the original Ficha 360 model were not attached, so the findings that depend on them are marked as hypotheses.
