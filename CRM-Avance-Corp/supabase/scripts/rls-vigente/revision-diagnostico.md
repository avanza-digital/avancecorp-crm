VERDICT:
CHANGES_REQUESTED

SUMMARY:
D19 is **not** a false positive, but the fix you propose is only half of the invariant. The controller's `pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'))` is sufficient for the F4–F7 clause — because the flags side takes the *same* key in `private.trg_multiempresa_flags_bloquear_piloto_f8()` — and is provably orthogonal to the F3 clause, because no flags-side path takes `crm_piloto_f8_control` when `resolver_en_puertas` changes. Different key ⇒ no mutual exclusion. So the read `select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'` is genuinely unlocked, and adding the existing helper is warranted.

However, the helper closes only one of the two interleavings. In the reverse order the end state `F8 ON ∧ F3 OFF` is still reachable with no error, because nothing guards *turning F3 off* while F8 is active — the reciprocal guard exists only for F4–F7. With F8 OFF in production and activation being a privileged, non-RPC operation, current production risk is effectively zero; this is a pre-activation correctness fix, not a release blocker.

FINDINGS:

**[P2] D19 true positive: F3 flag read without its lock in `private.trg_piloto_f8_control_validar()`**

File / symbol:
`private.trg_piloto_f8_control_validar()` (attached pg_dump definition)

Problem:
The function reads the F3 flag directly inside the `if new.activo` branch while holding only the `crm_piloto_f8_control` advisory key.

Evidence:
- Controller acquires `pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'))` at the top, then reads
  `if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'),false)`.
- The only writer-side guard that takes `crm_piloto_f8_control` is `private.trg_multiempresa_flags_bloquear_piloto_f8()`, and it is filtered to
  `new.nombre in ('inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')` **and** `v_encendido` (turn-ON only). `resolver_en_puertas` never enters that branch.
- `private.trg_multiempresa_flags_serializa_puertas()` takes `pg_advisory_xact_lock(hashtext('crm_flag_' || new.nombre))` — a different key — for any `activo` change, including F3.
- `private.resolver_en_puertas_bajo_candado()` exists precisely to pair `pg_advisory_xact_lock_shared(hashtext('crm_flag_resolver_en_puertas'))` with the read.

Exact interleaving that the current code allows:
1. T1: `update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas'` → `serializa_puertas` takes EXCLUSIVE `crm_flag_resolver_en_puertas`; T1 stays open.
2. T2: F8 activation → takes EXCLUSIVE `crm_piloto_f8_control` (uncontended; T1 does not hold it).
3. T2's plain `SELECT` is a non-locking MVCC read under READ COMMITTED, so T1's uncommitted update is invisible: T2 reads `activo=true`, passes the F3 precondition, runs the members/`v_huecos` checks and commits F8 ON.
4. T1 commits. End state: **F8 ON with F3 OFF**, and no exception was raised anywhere.

With the helper call added, step 3 blocks on the shared key until T1 commits; the following statement gets a fresh READ COMMITTED snapshot, reads `false`, and raises `P0409`. That is the correct behavior.

Impact:
Today: none in production — F8 is OFF, the branch is only reachable from a privileged `UPDATE crm.piloto_f8_control ... activo=true`, there is no API RPC surface, tables deny by default and no user data is involved. Future: an activation can be admitted against a flag value that is already being revoked, i.e. the precondition check is not honest.

Recommendation:
Replace the direct read with the helper's return value rather than merely `perform`-ing it, so there is a single read under the lock:
`if not private.resolver_en_puertas_bajo_candado() or exists(select 1 from crm.multiempresa_flags where nombre in ('inversiones_escritura', ...) and activo) then`.
Keep it **inside** the `if new.activo` block (see [P3] deactivation/isolation note). Minimal versioned migration containing only `CREATE OR REPLACE FUNCTION`, preserving `SECURITY DEFINER` and `SET search_path TO ''`; no trigger DDL needed. Confirm the controller's definer role holds `EXECUTE` on `private.resolver_en_puertas_bajo_candado()` if `private` has `REVOKE ... FROM PUBLIC`.

**[P2] The lock does not make "F8 ON ⇒ F3 ON" hold; the reverse interleaving and the sequential case remain open (partial hypothesis)**

File / symbol:
`private.trg_multiempresa_flags_bloquear_piloto_f8()`

Problem:
There is no guard on turning F3 **off** while F8 is active, symmetric to the F4–F7 guard.

Evidence:
- `bloquear_piloto_f8` raises `'Apaga F8 antes de activar el rollout global'` only for the four F4–F7 names on turn-ON. `resolver_en_puertas` is absent from that list.
- Reverse interleaving, *with the [P2] fix applied*: T2 takes the shared F3 key and reads `true`; T1's flag UPDATE now blocks on the exclusive key until T2 commits; T2 commits F8 ON; T1 then turns F3 OFF with no check. End state is again F8 ON + F3 OFF, no error.
- The purely sequential case is unguarded regardless of locking: activate F8, commit, then turn F3 off in a later transaction.

Impact:
Hypothesis-dependent. If every F8/F3 door goes through `resolver_en_puertas_bajo_candado()` — which your result "34 named operational functions PASS the helper-call check" strongly suggests — then F3-off closes the doors and a stale `piloto_f8_control.activo=true` row is inert; impact is bookkeeping only and the F3 read in the controller is a one-shot precondition, not an enforcement gate. That reading lowers D19's severity but does not make it a false positive. If any F8-specific gate reads F8 without re-checking F3, this is a real privilege-window bug and should be P1.

Recommendation:
Decide explicitly and record the decision. Either (a) extend `bloquear_piloto_f8` to also reject disabling `resolver_en_puertas` while `crm.piloto_f8_control.activo` (taking `crm_piloto_f8_control` first, as it already does), or (b) document that F3 is the master kill switch and F8 degrades silently, and state that the controller's F3 read is a precondition only. Do not ship the lock as if it established the invariant.

**[P3] Lock-ordering / deadlock risk is low but depends on trigger names not supplied**

Problem:
The fix gives the controller the order `crm_piloto_f8_control` (exclusive) → `crm_flag_resolver_en_puertas` (shared). A deadlock needs another transaction taking those two keys in the opposite order.

Evidence:
- PostgreSQL fires `BEFORE ... FOR EACH ROW` triggers in alphabetical order by *trigger* name. If the trigger names mirror the function names, `..._bloquear_piloto_f8` < `..._serializa_puertas`, so the flags side also acquires control-then-flag — the same order, no cycle.
- The residual cycle requires a single transaction that both turns an F4–F7 flag ON and flips F3, e.g. `update ... where nombre in (...)`: per-row firing means the F3 row may take `crm_flag_resolver_en_puertas` before the F4 row takes `crm_piloto_f8_control`, which is the opposite order.
- Not verifiable from the attached evidence: the `CREATE TRIGGER` statements were not included.

Impact:
Bounded — Postgres detects advisory-lock deadlocks and aborts one transaction with `40P01`; no corruption, and the affected operation is rare and privileged.

Recommendation:
Verify the actual trigger names on `crm.multiempresa_flags`. Document "control key before flag keys" as the canonical order in the migration comment. Optional hardening (out of minimal scope): have `bloquear_piloto_f8` take `crm_piloto_f8_control` unconditionally at the top for any flag change, which makes the global order total and gives the [P2] F3-off guard a natural home.

**[P3] Placing the helper call too early would regress the F8 kill switch**

Evidence:
`resolver_en_puertas_bajo_candado()` raises `0A000` ('La identidad unificada requiere READ COMMITTED') unconditionally. The controller currently enforces READ COMMITTED **only inside `if new.activo`**, so a deactivation (`activo=false`) is allowed under REPEATABLE READ / SERIALIZABLE.

Impact:
Hoisting the helper call above the `if new.activo` block would make the emergency off-switch fail under non-RC isolation.

Recommendation:
Call it inside `if new.activo`, after the existing isolation check — then the helper's own check is provably unreachable there and the error message users see stays the F8 one.

**[P3] `old` usage if the trigger can fire on INSERT (hypothesis — CREATE TRIGGER not attached)**

Evidence:
`new.revision := old.revision + 1;` runs unconditionally for non-DELETE ops, and `if old.activo and (...)` assumes `old` exists. `tg_op` is only tested for `'DELETE'`.

Impact:
If the trigger is declared `BEFORE INSERT OR UPDATE OR DELETE`, an INSERT would either produce `revision = NULL` or fail on unassigned `OLD`. If it is UPDATE/DELETE-only on a singleton row, this is a non-issue.

Recommendation:
Confirm from the `CREATE TRIGGER` statement; no code change if INSERT is not covered.

**[P3] Unqualified `pg_catalog` calls, inconsistent with sibling functions**

Evidence:
`trg_piloto_f8_control_validar` and `trg_multiempresa_flags_bloquear_piloto_f8` use bare `pg_advisory_xact_lock(hashtext(...))`, while `trg_multiempresa_flags_serializa_puertas` and `resolver_en_puertas_bajo_candado` use `pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(...))`.

Impact:
None functionally — `pg_catalog` is implicitly searched first when absent from `search_path`, so `SET search_path TO ''` is safe. Consistency only; worth aligning while the function is already being replaced.

**[P3] D19's detection rule has false negatives that this same function demonstrates**

Evidence:
The scan matches the literal `resolver_en_puertas` in `prosrc`. The very function it flagged also reads `crm.multiempresa_flags` for four other flags via `where nombre in ('inversiones_escritura', ...)`; a literal-per-flag scan gives no coverage there. It would also miss `where nombre = v_nombre`, dynamic SQL, and reads through a view, and it would false-positive on comments or exception-message text containing the flag name.

Recommendation:
Complement D19 with a rule that flags *any* function in `public`/`crm`/`private` referencing `crm.multiempresa_flags` outside an explicit allowlist (the helper, the flags triggers). Keep D19 as-is; treat the new rule as the real invariant test.

TEST GAPS:
- No concurrency test reproducing the [P2] interleaving. Minimum: two sessions, both `READ COMMITTED`; S1 `BEGIN; update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';` (no commit); S2 `BEGIN; update crm.piloto_f8_control set activo=true, ...;` — assert S2 **blocks** (e.g. `lock_timeout='2s'` → `55P03`, or check `pg_locks` for the waiting advisory lock), then commit S1 and assert S2 fails with `P0409` / `'requiere F3 ON'`. Pre-fix the same script must show S2 succeeding — run it against the unpatched function first so the test is proven to fail before it passes.
- No test for the reverse interleaving / sequential case from [P2]: turn F8 on, commit, turn F3 off, assert the intended outcome (rejection or documented degradation).
- No regression test that F8 **deactivation** still succeeds under `REPEATABLE READ` (guards [P3]).
- No happy-path regression after the change: F8 activation with F3 ON, F4–F7 OFF, exactly 1 gerencia / 1 supervisor / 2 vendedores, `v_huecos=0` → success and `revision` incremented by 1.
- One-time check that `hashtext('crm_piloto_f8_control') <> hashtext('crm_flag_resolver_en_puertas')` (int4 space; cheap to assert once).
- No test asserting the F4–F7 clause is still serialized by the control key after the edit (F4 ON concurrent with F8 activation → one of them must fail).

REGRESSION RISKS:
- Error-message identity: if any existing test asserts the exact `0A000` text, routing through the helper could surface `'La identidad unificada requiere READ COMMITTED'` instead of the F8 wording. Placing the call inside `if new.activo` after the existing check avoids this.
- `CREATE OR REPLACE FUNCTION` must be executed by the function owner and must restate `SECURITY DEFINER` and `SET search_path TO ''`; omitting either silently changes the security posture.
- The helper is transactional and reentrant, so the shared lock is held for the remainder of the F8 transaction, which also spans `private.cartera_f5_fuentes_reales()`. Slightly longer hold time for flag writers; negligible for a rare privileged op.

MISSING EVIDENCE (would raise confidence, not blocking):
1. `CREATE TRIGGER` statements on `crm.piloto_f8_control` and `crm.multiempresa_flags` (firing order and INSERT coverage).
2. Definition of `private.cartera_f5_fuentes_reales()` — if it already calls the helper, the transaction ends up holding the shared key anyway, which changes the "no lock at all" framing and pins the acquisition order in practice.
3. Confirmation that every F8-specific gate re-checks F3 through the helper (resolves [P2] severity between P2 and P1).

RECOMMENDED NEXT ACTIONS:
1. Do not waive D19. Apply the minimal `CREATE OR REPLACE FUNCTION` migration using `private.resolver_en_puertas_bajo_candado()`'s return value inside the `if new.activo` block, with a comment stating the canonical lock order (control key → flag key).
2. Write the two-session concurrency test and prove it fails against the unpatched function before it passes against the patched one.
3. Pull the `CREATE TRIGGER` statements and `cartera_f5_fuentes_reales()`; confirm trigger firing order and INSERT coverage.
4. Decide and document the F3-off-while-F8-on question ([P2]); if the answer is "must be rejected", that is a separate change to `bloquear_piloto_f8` with its own test.
5. Treat this as pre-activation work, not release-blocking: with F8 OFF the flawed branch is unreachable, but it must land before any F8 activation.

CONFIDENCE:
MEDIUM-HIGH on the [P2] D19 verdict and the interleaving (derived directly from the three attached definitions and documented READ COMMITTED semantics). MEDIUM on severity of the second [P2], which depends on gate definitions not attached. LOW-MEDIUM on the deadlock analysis, which depends on trigger names not attached.
