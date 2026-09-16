VERDICT:
CHANGES_REQUESTED

SUMMARY:
The functional core of the fix is right: taking the F3 shared lock (`private.resolver_en_puertas_bajo_candado()`) before the `crm_piloto_f8_control` exclusive lock closes the D-19 window the previous review found, the A/B evidence (3/5 → 5/5 on the same file) is a legitimate discriminating signal, and the F4/F5/F6/F7 read is correctly left *without* its own per-flag lock (the `crm_piloto_f8_control` lock already serializes it against `trg_multiempresa_flags_bloquear_piloto_f8`, and adding those locks would invert the order). However, the change introduces a **new lock-order inversion** that did not exist before it, the migration's before/after pinning is weaker than advertised (`prosrc`-only + containment), and several of the repaired assertions in `test-rls.mjs` are materially weaker than the ones they replace. None of this is a P0 and none of it requires a redesign, but the P1 and the P2s are actionable before publication.

FINDINGS:

---

**[P1] New lock-order inversion: F8 activation vs. any transaction that touches F3 after F4–F7 or after the F8 control row**

File:
`CRM-Avance-Corp/supabase/migrations/20260916040442_crm_piloto_f8_activacion_serializada.sql`

Lines:
32–39 (`v_f3:=private.resolver_en_puertas_bajo_candado();` then `pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'))`)

Problem:
The F8 control trigger now acquires locks in the order `flag_resolver_en_puertas (SHARED)` → `crm_piloto_f8_control (EXCLUSIVE)`, while the flag path acquires them in the opposite order in two reachable cases. Before this migration the F8 trigger took only the `crm_piloto_f8_control` lock, so no cycle was possible.

Evidence:

*Variant A — one statement that turns F3 and an F4–F7 flag ON together.*
`trg_multiempresa_flags_serializa_puertas` takes `pg_advisory_xact_lock('crm_flag_'||new.nombre)` per row, and `trg_multiempresa_flags_bloquear_piloto_f8` then takes `pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'))` for `inversiones_escritura|ficha_360_neutral|postventa_neutral|metricas_multiempresa_sombra` when `v_encendido`. Row processing order inside a multi-row UPDATE is not defined. With `update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura')` and the F4 row processed first:

```
T: flag_inversiones_escritura (X) -> crm_piloto_f8_control (X) -> waits flag_resolver_en_puertas (X)
B: flag_resolver_en_puertas (S)  -> waits crm_piloto_f8_control (X)
```

*Variant B — the emergency sequence "F3 OFF + F8 OFF" in one transaction.* The BEFORE ROW trigger on `crm.piloto_f8_control` runs after `GetTupleForTrigger` has already taken the tuple lock on the singleton row, so:

```
T2: flag_resolver_en_puertas (X)      -> waits tuple lock on crm.piloto_f8_control
B:  tuple lock on crm.piloto_f8_control -> waits flag_resolver_en_puertas (S)
```

Impact:
PostgreSQL detects both cycles and aborts one side with `40P01`; there is no corruption and the outcome is fail-closed. But in Variant B the transaction most likely to be aborted is the **kill sequence**, which is the one an operator least wants to see fail, and in Variant A a plain rollout command becomes non-deterministically abortable while a pilot activation is in flight. Neither interleaving is covered by `f8-candado.test.mjs`.

Recommendation:
Reordering inside the trigger does not fix it (Variant B's cycle is through the tuple lock, which is acquired before any trigger body runs), so do not attempt a local swap. Pick one:
1. Minimum, proportionate to a "minimal product change": add the two interleavings to `f8-candado.test.mjs` asserting a clean `40P01` with no state change on either side, and document the operational constraint "never toggle `resolver_en_puertas` in the same transaction as an F4–F7 activation or an F8 control write".
2. Robust: give every rollout writer (both flag triggers, the F8 control trigger, and the activation path) a single `crm_rollout_flags` advisory lock taken *first*, before any per-flag / per-row lock. These are rare admin operations; the serialization cost is irrelevant.

Note this is a bounded, detected failure mode — accepting it with (1) is a defensible PRIMARY decision; shipping it silently untested is not.

---

**[P2] The before/after "exact MD5 + ACL" guard cannot detect a dropped function attribute**

File:
same migration

Lines:
10–13 (preflight), 121–123 (postflight)

Problem:
The preflight pins `md5(prosrc)`, which is the **body only** — `proconfig`, volatility, cost and parallel safety are not part of `prosrc`. The postflight then checks `proconfig @> array['search_path=""']`, i.e. *containment*, not equality, and pins the md5 of the body it just wrote (self-fulfilling).

Evidence:
`private.postventa_modo()` in the same subsystem carries `SET "lock_timeout" TO '5s'` in addition to `search_path`. If the deployed `trg_piloto_f8_control_validar()` carried any second GUC, this `CREATE OR REPLACE` drops it and **both** guards still pass: the preflight never saw `proconfig`, and `@>` is satisfied by `{search_path=""}` alone.

Impact:
The claim "exact before/after MD5 + ACL checks" overstates what the migration verifies. A silent loss of a timeout or volatility setting on a SECURITY DEFINER trigger in the F8 path would ship undetected.

Recommendation:
Use the idiom already present in the repo's own harness — `md5(pg_get_functiondef(p.oid))` (see `testIdentidadF2bD10`, pre-diff) — in the preflight, and change the postflight to `proconfig = array['search_path=""']` (equality) plus `provolatile`/`proparallel` assertions.

---

**[P2] `v_f3` is fail-OPEN if the trigger ever fires outside UPDATE, and the migration never asserts the trigger's timing/events**

File:
same migration

Lines:
28, 32–38, 70–76, 119–133

Problem:
`v_f3` is declared without a default and assigned **only** under `tg_op='UPDATE' and new.activo`. The gate at line 70 is `if not v_f3 or exists(...)`. With `v_f3` NULL and no F4–F7 flag on, the condition is `NULL or false` = NULL, the `if` does not fire, and **F8 activates without any F3 check**.

Evidence:
Today this is unreachable only because the trigger is `BEFORE DELETE OR UPDATE` (confirmed indirectly: `f8-candado.test.mjs:103` inserts into `crm.piloto_f8_control` successfully, which would fail at line 114 `old.revision + 1` if the trigger fired on INSERT). The postflight (121–133) verifies the function body, `prosecdef`, owner, `proconfig` and the ACL — it never verifies `pg_trigger.tgtype`, `tgfoid` or `tgenabled='O'`. Adding INSERT to the trigger later, or re-pointing it, silently converts a fail-closed gate into a fail-open one.

Impact:
Latent privilege-escalation-by-configuration on the single control that keeps the pilot from being activated with the kill switch off.

Recommendation:
Two one-liners: `v_f3 boolean := false;` (or `if v_f3 is not true then raise ...`), and a postflight assertion that the trigger on `crm.piloto_f8_control` is exactly BEFORE `DELETE OR UPDATE`, enabled, and bound to this function. The harness already uses the `tgenabled='O'` check in `testIdentidadF2bE4`.

---

**[P2] D-10: a byte-identity pin was replaced by a probe that only proves the function reaches lead validation**

File:
`CRM-Avance-Corp/supabase/scripts/test-rls.mjs` (`testIdentidadF2bD10`)

Problem:
Removed:
```js
check(cuenta('1 argumento intacta', `select (md5(pg_get_functiondef(p.oid)) in ('a0671…','c9fc6…'))::int …`) === 1,
  'D-10 la reserva de 1 argumento (camino de hoy) sigue byte a byte …');
```
Replaced by `reservar_conversion_lead(LEAD_INEXISTENTE)` expecting `['P0001','P0002']` / `/no encontrado|no existe/i` with the flag OFF and `P0409` / `/por persona/i` with it ON.

Evidence:
The removed assertion's stated purpose in its own message is that the production path stays byte-identical. The replacement passes for *any* implementation that validates the lead id first — a change to the reservation semantics downstream of that validation is invisible to it, and accepting either of two errcodes and either of two message fragments widens it further.

Impact:
This is exactly the "weakened expectation" class the review was asked to look for: a matrix failure was resolved by loosening the check rather than by re-pinning it.

Recommendation:
Keep the behavioural pair (it is a genuine improvement) **and** restore a definition pin — either the refreshed `md5(pg_get_functiondef(...))` set, or the `strpos(p.prosrc, 'F2.b [D-…]') > 0` marker idiom used elsewhere in the same file, which survives whitespace churn.

---

**[P2] The retired correo API took the confirmation and detector coverage with it**

File:
`CRM-Avance-Corp/supabase/scripts/test-rls.mjs` (`testCorreoAccesoCliente`)

Problem:
The rewrite drops, with no replacement, the two assertions that protected the *second half* of the flow:
- `confirmar_correccion_correo_fn` → `42501` for gerencia ("el acuse tambien es del superadmin: si lo pudiera cerrar cualquiera, el detector de desviaciones se podria silenciar sin arreglar nada");
- `desviaciones_correo_cliente_fn` → empty for gerencia, "no una lista de correos".

Evidence:
The new block exercises only `preparar_correccion_correo_acceso_fn`, the `correcciones_correo_acceso` table (read/insert) and the `perfiles.correo` UPDATE shortcut. The RPC name `preparar_…` implies a confirm counterpart that is now entirely uncovered, and no deviation-detector call remains in the function.

Impact:
The half of the feature whose whole purpose is detecting/closing drift is unverified. Whether the successors still exist cannot be determined from the attached evidence — if they do, their authorization is untested; if they don't, the "detector" premise of the design is gone and that is a product decision that should be stated, not absorbed into a test rewrite.

Recommendation:
Either restore equivalents against the vigente RPCs, or state explicitly in the migration/PR notes that the acuse+detector were retired together with the old API.

Confidence on this one is MEDIUM: the successor RPC names were not attached.

---

**[P2] The new fixture restore disables a security trigger instead of using the RPC its own comment points at**

File:
`CRM-Avance-Corp/supabase/scripts/test-rls.mjs` (`testLectorGlobalNoVeBorrados`, `finally`)

Problem:
```js
// … una reapertura de negocio exige su RPC. No cambiar la bandera global ni sus permisos.
ejecutarFueraDeBanda('restaurar fixture de lectura de borrados', `
  alter table crm.leads disable trigger trg_leads_zz_reapertura_solo_rpc;
  update crm.leads set activo=true where id='${leadSonda}';
  alter table crm.leads enable trigger trg_leads_zz_reapertura_solo_rpc;`);
```
The comment says the reopening requires its RPC, and the code then bypasses that exact control.

Evidence/Impact:
1. `ALTER TABLE … DISABLE TRIGGER` takes `ACCESS EXCLUSIVE` on `crm.leads`, serialising against the rest of the suite.
2. If `ejecutarFueraDeBanda` does not send the three statements as one implicit transaction, or the process is interrupted between them, `trg_leads_zz_reapertura_solo_rpc` stays **disabled** in the bank — a silently weakened control for every subsequent run. (Hypothesis: I could not read `ejecutarFueraDeBanda`; if it is a single simple-query round trip the window closes on failure but not on process death.)
3. Making the harness routinely disable protective triggers to restore fixtures is a precedent that erodes the suite's own guarantees.

Recommendation:
Restore via the reapertura RPC (self-documenting and it exercises the supported path), or pick a probe lead that the suite is allowed to leave deactivated. If the disable/enable stays, wrap it in an explicit transaction and add a post-suite assertion that `tgenabled='O'` for that trigger.

---

**[P3] The DELETE path depends on undocumented short-circuit evaluation of `AND`**

File: same migration, lines 32 and 40–42.
`if tg_op='UPDATE' and new.activo then` now references `new` **before** the `if tg_op = 'DELETE' then raise` guard. In a BEFORE DELETE trigger `NEW` is unassigned; the statement only survives because PostgreSQL's executor happens to short-circuit `BoolExpr` at runtime, which the documentation explicitly says not to rely on (Expression Evaluation Rules). If it ever evaluates the right operand, the DELETE fails with `record "new" is not assigned yet` (also `55000`) instead of `El control F8 es permanente; solo se apaga`. No test in the attached suite performs a DELETE on `crm.piloto_f8_control`.
Recommendation: nest the conditions (`if tg_op='UPDATE' then if new.activo then … end if; end if;`) or move the DELETE guard above line 32, and add the DELETE-rejection assertion.

**[P3] `esperaAdvisory` cannot tell which advisory lock is being waited on, and evaluates the predicate twice**

File: `f8-candado.test.mjs:79–85`.
The predicate filters `l.locktype='advisory' and not l.granted` with no `classid`/`objid` discrimination, so the message "La activación debe esperar el candado F3" is not what is actually asserted (in test 2 it happens to be unambiguous because the blocker only holds the F3 flag lock; in tests 3/5 it is not). Additionally `esperar(() => esperando() || …)` followed by `return esperando()` issues a second `psql` round trip, so a lock granted in between turns a correct run red.
Recommendation: match the key, e.g. `((l.classid::bigint << 32) | l.objid) = pg_catalog.hashtext('crm_flag_resolver_en_puertas')`, and capture the first evaluation's result instead of re-polling.

**[P3] Test 3 never asserts that the committed F8 activation survived the F3 shutdown**

File: `f8-candado.test.mjs:143–160`. The test proves the gates close and that both transactions commit, but the stated invariant — "turning F3 OFF after a committed F8 activation must remain allowed" and F8 stays activated — is only half checked. One line closes it: `assert.equal(sql('select activo::int from crm.piloto_f8_control'), '1');`.

**[P3] `testFacturacionDiaria` J: the NULL-month assertion is vacuous when the current Lima month is empty**

`JSON.stringify(ordenar(nulo)) === JSON.stringify(ordenar(actual))` passes trivially when both are `[]`, which is the likely state for a seed anchored in a fixed month. The old assertion at least pinned "NULL → empty". Add `nulo.length > 0` (or an explicit "both empty ⇒ inconclusive" branch) so the change from "empty" to "current month" is actually observed.

**[P3] Conversión D8: stale message and a relaxed cross-check**

`deltaTotal('analistas') === 0` now sits under the message "…INCLUYENDO al productor fuera de roster (+2 divisor, +${deltaAnalistaFueraRoster} analista segun el ledger)", and `deltaAnalistaFueraRoster` survives only in the logged JSON. Likewise `Number(total.analistas) === suyas.length` drops the `+ num(fuera.analistas)` reconciliation. The divisor reconciliation still holds, so this is maintainability rather than coverage, but the message now describes a different assertion than the code.

**[P3] E4: the null-DNI handling was dropped in the restore assertion**

Old: `dni is not distinct from ${dniActual ? `'${dniActual}'` : 'null'}`. New: `dni='${dniActual}'`, which becomes `dni='null'` if the bank client has no document. It fails closed (red, not green), but it converts a supported fixture state into a confusing failure.

**[P3] Migration filename is dated ahead of the release branch**

`20260916040442_…` on a branch named `…-20260915` and a working tree dated 2026-09-15. A future-dated timestamp sorts after migrations legitimately created later today on other branches.

**[P3] Catalog calls are unqualified inside a SECURITY DEFINER / `search_path=''` function**

Lines 33, 39, 47, 51, 56–57 use `current_setting`, `pg_advisory_xact_lock`, `hashtext`, `statement_timestamp` bare. Not exploitable (`pg_catalog` is implicitly first), but `private.resolver_en_puertas_bajo_candado()` — the function this migration now calls — deliberately writes `pg_catalog.current_setting`, `pg_catalog.hashtext`, `pg_catalog.pg_advisory_xact_lock_shared`. Two adjacent styles for the same hardening invariant.

TEST GAPS:
- No test for the two deadlock interleavings in [P1] (mixed F3 + F4-ON statement; F3-OFF + F8-OFF transaction).
- No test for `DELETE` on `crm.piloto_f8_control` — the branch at lines 40–42 and the [P3] `NEW`-reference hazard are entirely uncovered.
- No test for two concurrent F8 activations (both take the `crm_piloto_f8_control` exclusive lock; the second's `old.activo`/`P0409 ventana` path is unexercised).
- No assertion anywhere that the trigger set on `crm.piloto_f8_control` has the expected timing/events — the premise the whole fix rests on (see [P2]).
- `confirmar_…` / deviation-detector authorization for the vigente correo API (see [P2]).
- `convertir_lead_externo` gained two parameters (`…,integer,numeric`); they appear only inside signature strings in D-17/D-13 — no validation/authorization coverage of the new arguments.
- The new per-responsable metrics fields (`citas_realizadas`, `leads_con_cita_real`, `cierres_por_semana`) are asserted by key name only; no scoping assertion that a non-gerencia caller cannot see other analysts' counts.
- Demo contracts: the rewrite proves `atribucion_contrato_fn` returns `null` and the flag persists, but not that the contract leaves the aggregate listing, which is what the message claims.
- `testCierresExternos`: the NaN-monto probe moved to `vend3` + `leadAjeno`, so it no longer demonstrates "la validación del monto corre ANTES del gate de etapa" — the comment above it is now stale and the ordering property is untested.
- Suite re-runnability (hypothesis, diff truncated): `testIdentidadMultiempresa` now performs a real `convertir_lead` for `bankProfileId`; the visible cleanup deletes `crm.inversionistas` only for `IDS_IDENTIDAD.clienteNuevo`. If the identity row created for `bankProfileId` is not removed, the second consecutive run fails at the new `positive('#2 preparar la primera conversión…')` step.

ARCHITECTURE RISKS:
- There is now no single serialization point for rollout state. Three independent lock families (`crm_flag_*`, `crm_piloto_f8_control`, and the control row's tuple lock) are acquired in different orders by different paths, and the ordering is only locally consistent. Every future gate that reads a flag and the pilot state adds another opportunity for [P1]. A single `crm_rollout_flags` lock taken first by all writers would make the invariant checkable rather than reasoned.
- The F8 preconditions (window, roster of 4, identity gaps) are validated **once**, at activation. Whether they are re-evaluated later depends on `private.piloto_f8_control_activo()`, which was not attached — if it checks only `activo`, an F8 activation that survives an F3 OFF/ON cycle can outlive its `vence_en` window. Hypothesis; needs the function body to confirm.

SECURITY RISKS:
- [P2] fail-open `v_f3` NULL path plus the absent trigger-shape assertion: the single control preventing pilot activation with the kill switch off is protected by trigger configuration that the migration does not verify.
- [P2] the harness now disables a protective trigger on `crm.leads` as part of normal teardown.
- [P2] loss of authorization coverage on the correo confirmation/detector surface.
- Positive note: the postflight ACL check (no EXECUTE for `anon`/`authenticated`/`service_role`, no `grantee=0`) and the preflight's fail-closed behaviour when `to_regprocedure` returns NULL are both correct.

REGRESSION RISKS:
- [P1] is a behaviour regression relative to the pre-migration function for concurrent admin operations.
- Re-running the migration aborts on the preflight (old md5 no longer matches). Intended for a run-once migration, but any runner that retries a partially failed batch will report a confusing "El control F8 cambió" instead of a no-op.
- `f8-candado.test.mjs` hard-fails at import time when `CRM_BANCO_PSQL_URL` is unset (`assert(url, …)` at module scope) and lives in a new `supabase/scripts/rls-vigente/` directory. If it is not wired into the documented verification command, the only evidence that this fix works is a manual run.

RECOMMENDED NEXT ACTIONS:
1. Resolve [P1]: at minimum add the two interleavings to `f8-candado.test.mjs` asserting a clean `40P01` with no partial state, and document the "do not toggle F3 in the same transaction as an F4–F7 activation or an F8 control write" constraint next to the trigger. Consider the single rollout lock if activation will ever run concurrently with flag changes in production.
2. Harden the migration guards: `v_f3 boolean := false;` (or an `is not true` check), a postflight assertion on the trigger's timing/events/`tgenabled`, `proconfig` equality instead of containment, and a `pg_get_functiondef` pin in the preflight.
3. Restore the two pins that were traded away: a definition pin for the 1-arg `reservar_conversion_lead` alongside the new behavioural probe, and authorization coverage for the confirmation/detector half of the correo flow (or state explicitly that it was retired).
4. Replace the `disable trigger` fixture restore with the reapertura RPC, and run the full matrix **twice consecutively against the same bank**, reporting both results — several changed tests now create persistent objects out of band.
5. Confirm the new concurrency file is registered in the verification gate, and state whether `private.piloto_f8_control_activo()` re-checks `vence_en`.

CONFIDENCE:
MEDIUM-HIGH on the migration findings — the full function text, both flag triggers, `resolver_en_puertas_bajo_candado`, the trigger order and the A/B test output were attached, which is enough to reason about the lock graph end to end. MEDIUM on the `test-rls.mjs` findings: the diff is complete but the server-side definitions it now encodes (`corregir_documento_cliente_admin_fn`, `preparar_correccion_correo_acceso_fn`, the conversion RPC's new `crm.leads.creado_en` divisor, `atribucion_contrato_fn`'s demo behaviour, `piloto_f8_control_activo`) were not attached, so I can verify the assertions are internally coherent but not that they encode an intended contract rather than an accommodated drift. Items marked hypothesis above should be treated as leads to verify, not as established facts.
