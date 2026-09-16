VERDICT:
CHANGES_REQUESTED

SUMMARY:
`ACTIVAR.sql` is a well-constructed single-transaction flip. Every precondition (flags, control row incl. `revision`, member set, 24-account role/auth graph, 211 function fingerprints + owner + ACL, 8 trigger definitions incl. `tgenabled`, source-identity coherence, capture expiry) is re-verified inside the same transaction that writes, ordering is correct for `trg_multiempresa_flags_bloquear_piloto_f8` (F8 off before flags on), the isolation level matches what the triggers demand, and every failure branch aborts with no partial state. The 9-case rehearsal in `f9_apertura_20260915` is genuine and the artifact SHA256s in `ensayo.json` match the rendered files. I found no P0.

What is not yet supported by the evidence is the *rollback* and *blast-radius* half of the claim: `REVERTIR.sql` was only rehearsed against a dataset in which nothing was written during the open window, the advisory-lock acquisition order in both scripts appears to invert the reader order used by `postventa_estado_fn`, and the lock hold time — the PRIMARY's own stated concern — was never measured. Those are the changes I'm asking for; all are pre-flight/rehearsal work, not code defects in the flip itself.

FINDINGS:

---

**[P1] The reversa was never rehearsed against data created while the window was open**

File:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f9/apertura-2026-09-15/ensayo.mjs`

Lines:
75, 80 (and `hechos()` at 11–15)

Problem:
The only rollback evidence is a reversa executed over an untouched dataset. The real rollback scenario — 18 analysts have been writing for hours and Gerencia pulls the switch — is unexercised.

Evidence:
`hechos()` hashes 17 surfaces including `crm.inversiones`, `crm.inversion_titulares`, `crm.inversion_solicitudes`, `crm.inversion_eventos`, `public.contratos`. Line 75 asserts `deepEqual(hechos(),conservadas)` immediately after the successful COMMIT, and line 80 asserts the same after `REVERTIR`. Both pass, which proves that **zero rows were created between activation and reversa**. `ensayo.json:419-436` confirms identical hashes. The reversa therefore only demonstrates "flags flip back on an idle database".

Impact:
Unknown behaviour of the documented safety valve in the only state where it matters. Specifically unverified: (a) `private.cartera_f5_fuentes_reales()` still returns coherent rows for inversiones created under F4/F5 once those flags are OFF — note `crm.cartera_inversionistas_estado_fn` gates `habilitada` on a coherence scan that includes those new rows; (b) `private.inversiones_empresa_coherente()` / `private.inversion_titular_coherente()` do not reject later operations on rows born in the open window; (c) `crm.postventa_estado_fn` degrades cleanly rather than raising for accounts mid-flow.

Recommendation:
In the existing local clone, extend `ensayo.mjs` with a scenario between the COMMIT case (line 76) and the reversa case (line 78): as a `vendedor` actor, create 1–2 inversiones through the real RPC path (`crm.preparar_inversion_fn` → `crm.confirmar_inversion_fn`), then run `REVERTIR` literally and assert (1) reversa returns PASS, (2) the new rows survive byte-for-byte, (3) all 24 accounts get `habilitada=false` from both estado functions without exception, (4) `private.cartera_f5_fuentes_reales()` reports no incoherent source. Record the new hashes in `ensayo.json` alongside `superficies_conservadas`.

---

**[P1] Advisory-lock acquisition order likely inverts the reader order for `postventa_neutral` — deadlock risk, worst on the rollback path (HYPOTHESIS)**

File:
`activar.plantilla.sql` lines 19–23; `revertir.plantilla.sql` lines 11–15

Problem:
Both scripts take `crm_flag_resolver_en_puertas` **before** `crm_flag_postventa_neutral`. A concurrent `crm.postventa_estado_fn()` caller appears to take them in the opposite order.

Evidence:
`crm.postventa_estado_fn` (supplied definition) executes `v_on:=private.postventa_modo();` and only afterwards `crm.cartera_inversionistas_estado_fn()`, which takes `resolver_en_puertas` first (`v_f3:=private.resolver_en_puertas_bajo_candado()`), then `pg_advisory_xact_lock_shared(hashtext('crm_flag_ficha_360_neutral'))`, then `inversiones_escritura`, then `crm_piloto_f8_control`. The comment on `private.trg_multiempresa_flags_serializa_puertas` states flags are read under `pg_advisory_xact_lock_shared('crm_flag_<nombre>')`, which implies `private.postventa_modo()` takes `crm_flag_postventa_neutral` at its start. If so, the reader order is **postventa → resolver → ficha → inversiones → piloto**, while our order is **resolver → ficha → inversiones → postventa → piloto**.

I cannot confirm this without `private.postventa_modo()`; I am flagging it as a hypothesis, not a fact. The script's own comment at line 18 ("Mismo orden que los lectores/escritores") asserts the orders match, but the supplied evidence does not establish where `postventa_neutral` sits.

Impact:
Classic ABBA: reader holds `postventa_neutral(S)` and waits for `resolver_en_puertas(S)` behind our X; we hold `resolver_en_puertas(X)` and wait for `postventa_neutral(X)`. Advisory locks participate in the deadlock detector, so one side aborts (40P01) after `deadlock_timeout`, or our `lock_timeout=3s` fires first (55P03). No partial state either way — but: the probability is *low before activation* (only the 4 F8 members currently reach `postventa_modo()=true`) and **high during the reversa**, when all 23 gestores are hitting postventa. The rollback path is exactly where you least want retries and user-visible 40P01/55P03.

Recommendation:
Retrieve `private.postventa_modo()`, `private.resolver_en_puertas_bajo_candado()` and `private.inversiones_escritura_bajo_candado()` read-only and confirm the lock sequence. If `postventa_modo()` locks first, reorder lines 19–23 and 11–15 to `postventa_neutral, resolver_en_puertas, ficha_360_neutral, inversiones_escritura, crm_piloto_f8_control`, re-render, re-run the rehearsal, and add a scenario that holds `postventa_neutral(S)` in one session and `resolver_en_puertas(S)` in another while `REVERTIR` runs.

---

**[P2] Lock hold time is never measured; the probe loop dominates it and forces user-visible errors, not waits**

File:
`activar.plantilla.sql` lines 19–23, 59–63, 75, 79–97

Problem:
Five exclusive advisory locks are taken at the top of the DO block and held until COMMIT. The 24-account probe loop, which runs *after* the writes and *before* COMMIT, is the dominant cost and has no measured duration.

Evidence:
Counting evaluations of `private.cartera_f5_fuentes_reales()` inside the locked window:
- line 59 (coherence `exists`), line 62 (`count`+`md5`), line 75 (`md5`) → 3
- per probe iteration, `crm.cartera_inversionistas_estado_fn()` reaches its coherence scan once the flags are on → 23 (coordinador raises 42501 before the scan)
- `crm.postventa_estado_fn()` calls `crm.cartera_inversionistas_estado_fn()` again whenever `v_on` (`if v_on then v_on:=(crm.cartera_inversionistas_estado_fn()->>'habilitada')::boolean; end if;`) → 23 more

**≈49 full evaluations**, against 614 production sources vs. 231 in the fixture (`ensayo.json:406`). `ensayo.json` records `apertura.fecha` (statement start) and the run `fin`, but never the DO block's own elapsed time, so there is no baseline to extrapolate from.

Both user-facing functions carry `SET lock_timeout TO '5s'`. Any analyst whose request needs one of the five keys while we hold it therefore does not queue — it **fails after 5s** with 55P03.

Impact:
If the locked window exceeds 5s, live analysts get errors for its whole duration. If it exceeds 30s, `statement_timeout` aborts the activation entirely (fail-safe, but a wasted attempt against a 2h `vence_sql`).

Recommendation:
Two cheap steps before executing. (1) Read-only in production: time `select count(*) from private.cartera_f5_fuentes_reales() f left join crm.inversionistas i on i.id=f.inversionista_id` and multiply by ~49 for a floor estimate. (2) Add `clock_timestamp()` deltas around the probe loop into the `f9.resultado` payload and re-run the rehearsal once to get a measured fixture number, then scale by 614/231. If the projected window exceeds ~3–5s, either move the probe after COMMIT (accepting that a failed probe no longer aborts the flip — a documented tradeoff) or reduce it to one representative account per role plus the coordinator, and schedule the run in a low-traffic window regardless.

---

**[P2] F5 ON expands cartera *reads* to an unenumerated population (`es_lector_global`)**

File:
Production definition of `crm.cartera_inversionistas_estado_fn()`; `config.json` `equipo` (24 entries)

Problem:
The authorization predicate is `v_rol in ('vendedor','supervisor','gerencia') **or** v_lector`, but the config and the probe only enumerate the 24 `crm.equipo` accounts.

Evidence:
`crm.cartera_inversionistas_estado_fn` computes `v_lector:=private.es_lector_global()` and admits on `v_rol in (...) or v_lector`; `private.es_lector_global()` carries `authenticated=X/postgres` in `config.json:886-890`. The probe loop (line 79) iterates only `jsonb_to_recordset(equipo)`. `escritura_habilitada` correctly excludes lectores (`v_cobertura and not v_lector and ...`), and `postventa_estado_fn` excludes them explicitly, so the expansion is read-only — but it is real and uncounted.

Impact:
The stated blast radius ("18 analysts + 3 supervisors + 2 Gerencia") understates who gains multiempresa cartera visibility at COMMIT. There is also a second-order risk in the opposite direction: if any of the 24 enumerated accounts is a lector global in production, `escritura_habilitada` will be `false` for them and the `elsif` at lines 90–93 will abort the whole activation — correct behaviour treated as a failure, burning an attempt.

Recommendation:
Read-only before running: enumerate every account for which `private.es_lector_global()` would return true (retrieve its definition and query the underlying `rol`/flag set directly), confirm none of them is in `config.json` `equipo`, and report that population explicitly as part of the activation's blast radius.

---

**[P2] Rollback is one-way, and `REVERTIR` is not re-runnable — the artifacts cannot reopen after a reversa**

File:
`activar.plantilla.sql` lines 29–31; `revertir.plantilla.sql` lines 16–18, 24–25

Problem:
`REVERTIR` rewrites `crm.piloto_f8_control.motivo` and leaves `activo=false`. Both scripts key their guards off the exact prior value.

Evidence:
- `REVERTIR` line 17 requires `motivo='Apertura general '||referencia||'; ...'`. Line 24 then overwrites it with `'Reversa de apertura ...'`. A second `REVERTIR` therefore fails with P0409.
- `ACTIVAR` line 29 requires `control is distinct from cfg->'control'` to be false, where `cfg.control` has `activo:true`, `motivo:'Piloto F8 ref:F8-20260914-01; ...'`, `revision:1`. After a reversa the row has `activo=false`, the reversa motivo, and `revision=3`. Line 30 additionally requires `private.piloto_f8_modo_activo()`, which returns false once `activo=false`.

Impact:
Re-opening after an emergency rollback requires a fresh capture + fresh artifacts + a fresh rehearsal — i.e. it is not a same-day operation. Separately, `piloto_f8_modo_activo()` at line 30 makes `ACTIVAR.sql` unusable after `vence_en=2026-09-21T18:23:51Z` even if `vence_sql` is refreshed.

Recommendation:
No code change needed — but state both constraints explicitly in the handover to Miguel before executing, so that "we can roll back" is not read as "we can roll back and retry". A one-line note in the reversa header covering re-run behaviour would help the operator under pressure.

---

**[P2] The conservation check can abort spuriously on ordinary concurrent activity**

File:
`activar.plantilla.sql` lines 62–63, 75–76

Problem:
`antes` and `despues` are taken in separate statements under READ COMMITTED, so any inversión/contrato committed in between is visible to the second snapshot and trips line 76.

Evidence:
`begin isolation level read committed` (line 3) gives each statement a fresh snapshot. The five advisory locks cover flags and the piloto control row; they do **not** serialize writes to `crm.inversiones`, `crm.inversion_titulares` or `public.contratos`, which `private.cartera_f5_fuentes_reales()` reads.

Impact:
Fail-safe (clean abort, no partial state) but operationally expensive: a single analyst confirming an inversión during the window kills the attempt, and if the retry lands after `vence_sql=2026-09-16T02:30:09.973Z` (line 16) the whole capture/render/rehearsal cycle must be repeated.

Recommendation:
Run in a genuinely quiet window and plan for at least one retry. This is another argument for shortening the locked window (P2 above) — the exposure between lines 62 and 75 is proportional to it.

---

**[P2] No post-COMMIT verification; the PASS receipt is emitted before the commit**

File:
`activar.plantilla.sql` lines 99–106

Problem:
`select current_setting('f9.resultado')::jsonb evidencia;` (line 105) runs *before* `commit;` (line 106). If the COMMIT itself fails, the operator has already seen a `"estado":"PASS"` JSON blob.

Evidence:
`set_config('f9.resultado',...,true)` is transaction-local, so the read must precede COMMIT; there is no statement after line 106.

Impact:
Misleading receipt on a COMMIT failure. `ON_ERROR_STOP=1` surfaces the error, but the PASS line is already in the transcript and is the thing that gets copied into the evidence file.

Recommendation:
Append a read-only verification block after `commit;` that re-reads `crm.multiempresa_flags`, `crm.piloto_f8_control` (activo/revision/motivo) and runs the estado probe for two or three representative accounts, and treat *that* output as the receipt. Apply the same to `REVERTIR.sql`.

---

**[P3] Function parity verifies the 211 listed functions but not the absence of new ones**

File:
`activar.plantilla.sql` lines 44–51

Evidence:
The loop only asserts that each `cfg->'funciones'` entry still exists with a matching `md5(pg_get_functiondef)`, owner and ACL. A function created in `crm`/`private` between the 00:30 capture and execution — including a SECURITY DEFINER one granted to `authenticated` — passes unnoticed.

Recommendation:
Add a count assertion over the relevant namespaces (`select count(*) from pg_proc where pronamespace in ('crm'::regnamespace,'private'::regnamespace)`) against a captured value. One line, closes the gap.

---

**[P3] `crm.postventa_estado_fn()` is called unguarded inside the probe**

File:
`activar.plantilla.sql` line 85

Evidence:
`f5` is wrapped in `begin ... exception when others then error_f5:=sqlstate; end` (line 84); `f6` is not. `crm.postventa_estado_fn` raises 42501 when `not private.puede_acceder_crm()` and converts `serialization_failure` to PT409.

Impact:
Fail-safe (the transaction aborts) but the operator sees a bare 42501/PT409 rather than the P0409 convention used everywhere else, with no indication of which actor caused it.

Recommendation:
Mirror the `f5` pattern and fold the sqlstate into the existing role assertions, so the abort message names the account.

---

**[P3] Audit attribution and pseudonymisation**

File:
`activar.plantilla.sql` lines 65–69, 95–96; `private.trg_piloto_f8_control_validar`

Evidence:
`auth.uid()` is NULL by design (line 14), so `new.actualizado_por := coalesce(auth.uid(),new.actualizado_por)` keeps `cfg.responsable_id = ebb19751-…`. The `trg_audit_*` rows will therefore attribute an administrative change to a specific person. The `motivo` text ("autorizada por Miguel; ejecución administrativa Codex") is honest and mitigates this, but only for someone who reads it. Separately, `md5('F9-20260915:'||perfil_id)` at line 95 is trivially reversible — the salt is in the file and the 24 UUIDs are in `config.json` in the same directory.

Recommendation:
No change required; just don't describe the `roles` array as pseudonymised evidence. Note the `actualizado_por` attribution convention in the handover.

---

**[P3] Rehearsal disclosures and minor robustness**

Evidence / items:
- `ensayo.json:447-452` `limites` does not mention that `trg_piloto_f8_control_00_validar` was disabled to force `revision=1` (`preparar-banco.mjs:36-40`, `ensayo.mjs:21-24`). The PRIMARY disclosed it in prose; the durable artifact should carry it too.
- The probe asserts the flag-derived `escritura_habilitada` boolean, never an actual write. "18 analysts can write" is a *configuration* claim in production; the behavioural evidence lives in the G7 clone runs. Worth stating plainly rather than letting `escritura_habilitada:true` read as a production write test.
- ACL comparison (lines 48–49) splits `proacl::text` on `,`, which would misparse a grantee name containing a quoted comma. Not applicable to the current 211 entries; noted only so it isn't assumed general.
- `ensayo.mjs:76` labels the case "habilita 23 gestores" while asserting 18 vendedores (line 74); supervisores/gerencia coverage is enforced by `ACTIVAR.sql`'s own `elsif`, not by the test. Cosmetic.

TEST GAPS:
- Reversa over a dataset mutated during the open window (P1-A) — the single most important missing case.
- Cross-order lock contention: hold `postventa_neutral(S)` while `ACTIVAR`/`REVERTIR` run (P1-B). The existing 55P03 case (`ensayo.mjs:60-63`) only covers `resolver_en_puertas` against `ACTIVAR`.
- `REVERTIR` under any contention at all — no concurrency scenario targets it.
- Measured duration of the locked window (no timing instrumentation anywhere in `ensayo.json`).
- No case where a piloto member's `vence_en` has lapsed (`piloto_f8_modo_activo()` false → abort), the most likely real-world reason for a late abort.
- No case asserting that a new/unexpected function in `crm`/`private` is detected (see P3).

ARCHITECTURE RISKS:
- Correctness depends on every reader and writer agreeing on one advisory-lock order. That invariant lives in comments (`activar.plantilla.sql:18`, `trg_multiempresa_flags_serializa_puertas`) rather than in an enforced helper, so it is one new function away from being violated silently. A single `private.tomar_candados_multiempresa()` that encodes the canonical order would make P1-B structurally impossible.
- `crm.postventa_estado_fn` calling `crm.cartera_inversionistas_estado_fn` means every postventa page hit pays a full `cartera_f5_fuentes_reales()` coherence scan. At 614 sources and 23 concurrent users this is the cost driver both for the activation window and for steady-state latency after it.

SECURITY RISKS:
- No privilege escalation in the artifacts: `current_user='postgres'` and `auth.uid() is null` are enforced (line 14), role impersonation is confined to `SET LOCAL ROLE authenticated` with claims reset at line 98, all claim/GUC writes use `is_local=true`, and `search_path=''` with fully-qualified identifiers throughout (`hashtext`/`md5`/`jsonb_*` resolve via the implicit `pg_catalog`). `crear-sql.mjs:11` doubles single quotes correctly for the `'…'::jsonb` literal, and the config payload contains no quotes or newlines.
- The real security delta is the read expansion to `es_lector_global()` accounts (P2-D), which is unenumerated.
- `preparar-banco.mjs` writes only synthetic emails at `@f9.example.invalid` and no password hashes; the trigger disables at lines 15/17 and 36/40 are re-enabled inside the same transaction, so there is no window. Confined to the local clone, guarded by the `current_database()` check at line 9.

REGRESSION RISKS:
- Rollback under load (P1-A, P1-B) is the main one.
- Spurious aborts from concurrent finance writes (P2-F), bounded by `vence_sql`.
- User-facing 55P03 for the duration of the locked window (P2-C) — errors, not waits, because of the functions' own 5s `lock_timeout`.
- Post-activation, every `crm.equipo`-active account with role vendedor/supervisor/gerencia gains write capability simultaneously; there is no staged ramp and no kill switch other than `REVERTIR` (which is itself subject to P1-B).

RECOMMENDED NEXT ACTIONS:
1. Retrieve `private.postventa_modo()`, `private.resolver_en_puertas_bajo_candado()`, `private.inversiones_escritura_bajo_candado()`, `private.es_lector_global()` and `private.cartera_f5_fuentes_reales()` read-only. Confirm or refute the lock order in P1-B and enumerate the lector-global population for P2-D.
2. Extend the rehearsal in the existing clone with (a) inversiones created during the open window before `REVERTIR`, and (b) a cross-order contention case against `REVERTIR`. Add `clock_timestamp()` instrumentation around the probe loop and record the measured window in `ensayo.json`.
3. Time `private.cartera_f5_fuentes_reales()` read-only in production, project ×49, and decide whether to keep the pre-COMMIT probe at full width or reduce it. Re-render and re-hash if any template changes.
4. Add the post-COMMIT verification statement (P2-G) and the `pg_proc` count assertion (P3), then execute in a low-traffic window with a fresh capture if `vence_sql` has lapsed.
5. In the handover to Miguel, state explicitly: the lector-global read expansion, that rollback is one-way and `REVERTIR` is single-use, and that production write capability is evidenced by configuration (G7 covered behaviour on a clone), not by a production write.

CONFIDENCE:
MEDIUM-HIGH on the artifacts themselves — `ACTIVAR.sql`, `REVERTIR.sql`, `config.json`, `crear-sql.mjs` and `ensayo.mjs` were fully supplied and the SHA256s in `ensayo.json` are internally consistent. MEDIUM overall, because P1-B and P2-D depend on five function bodies I do not have, and the production timing floor for P2-C is unmeasured. P1-A is HIGH confidence — it follows directly from the two `deepEqual(hechos(),…)` assertions in `ensayo.mjs`.
