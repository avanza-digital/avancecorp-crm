VERDICT:
CHANGES_REQUESTED

SUMMARY:
The branch reconstruction is careful. It is guarded to the branch host, runs in a single transaction, uses a closure guard, and has a strong parity methodology. I found no P0 in the attached reconstruction code. The weak point is the production path. The merge, which is the only step that writes to production, has never been exercised with these artifacts. Several assumptions about what `merge_branch` transports, how it executes the ledger rows, and version identity have no evidence attached. These should be closed before the merge. Each one is either cheap to verify or cheap to fix.

FINDINGS:

[P1] Merge semantics are asserted, not evidenced ("does not transport schema reconstruction")
File: publication plan, step 2; `paridad-diferencias-final.json`
Lines: n/a (plan)
Problem: The review assumes `merge_branch` only replays the ledger delta and Edge Functions. Nothing attached shows how merge decides what to apply. If the merge flow computes or includes a branch→parent schema diff, the six residual differences could reach production as DDL. Those differences are the CHECK regrouping, pg_net 0.20.4/`extensions`, the `issue_pg_graphql_access` event trigger, and the absent `supabase_realtime_messages_publication`. Some Branching flows do diff-based change detection when a branch contains untracked changes (hypothesis, medium confidence).
Evidence: The branch was mutated entirely outside migrations: restore SQL, `ALTER EXTENSION`, `CREATE EXTENSION unaccent`, cron, grants. The PRIMARY text says "Reconstruction SQL was never added to migration ledger". That is exactly the condition under which diff-based merge would see changes.
Impact: Possible unintended production DDL on managed objects, such as dropping the Realtime messages publication or relocating pg_net.
Recommendation: Before merging, get read-only evidence of the merge payload. Use the Management API branch diff endpoint or the dashboard merge preview for branch `60b904c8…`. Confirm it contains only the two F8 migrations and no pg_net, publication, event trigger or constraint changes. If you cannot obtain a preview, cite official documentation for ledger-only merge semantics. If neither is available, treat it as NOT VERIFIED and escalate to the user before merging.

[P1] Production execution path of the ledger rows is untested
File: PRIMARY evidence, "statements[1] contains byte-for-byte full approved SQL (including original BEGIN/COMMIT)"
Problem: In the branch, the DDL was applied by direct psql and the ledger rows were inserted by hand. In production, merge will execute the `statements` array through Supabase's own executor, which has never run these rows. CLI-produced ledger rows normally hold one parsed statement per array element. A single element with many commands plus explicit `BEGIN`/`COMMIT` can behave differently depending on the executor:
- Under the extended protocol, multi-command strings are rejected. That fails safe.
- If the executor wraps the migration in its own transaction, the inner `COMMIT` ends that transaction early. The ledger insert then stops being atomic with the DDL, which risks "applied but not recorded" or the reverse (hypothesis).
Evidence: Compare the format of the 287 original rows. Check whether their `statements` arrays are split per statement and whether they include `BEGIN`/`COMMIT` elements. That comparison is not attached. Also, the claim "recorded atomically with DDL" is hard to reconcile with an inner `COMMIT`, and the script that did the recording is not attached.
Impact: A partial or unrecorded application in production, with difficult recovery.
Recommendation:
1. Attach the psql script used to apply and record the two migrations.
2. Show that the new rows' `statements` shape matches the existing rows produced by CLI/merge. Ideally take a recent row created by a real merge or `db push` and match its splitting and BEGIN/COMMIT handling.
3. If the shapes differ, regenerate the rows in the CLI's format (keeping the SHA of the concatenated file) before merging.

[P1] Ledger versions differ from repository filenames
File: `sql-aprobadas.json`
Problem: Production will record `20260915010349` and `20260915010350`, but the repo files are `20260914213634_…` and `20260914213928_…`.
Evidence: `sql-aprobadas.json` shows `version` ≠ `version_archivo` for both rows.
Impact: After merge, `supabase migration list` and `db push` against production will report a remote version missing locally and a local version not applied. Future branch replays or pushes could try to re-apply the F8 SQL or stop on history mismatch. The migration LEEME/MIGRACIONES bookkeeping will also no longer match production.
Recommendation: Use the filename versions in the branch ledger. If renumbering was needed, for example because the parent already has a later version, document why. Plan the reconciliation in the same deployment turn, either renaming files per LEEME rules or running a documented `migration repair`. Either way, `migration list` must be clean after merge.

[P2] Deploy window and rollback compatibility for changed RPC signatures
File: PRIMARY evidence, "Remote generated types match changed cierres_externos and convertir_lead_externo blocks"; plan steps 2→3
Problem: The migrations change the `convertir_lead_externo` type block, and the DB merge happens before the ZIP is published. Nothing attached shows that the current production frontend (`32d57b5b3e15`) still works against the new signatures. That includes PostgREST named-argument resolution and any new required parameters or changed return shape. It applies to the window between merge and publish, and again if the frontend rollback is used.
Evidence: The 62 HTTP cases compare reads (ficha/cartera) and legacy retry hashes. No old-frontend write call (F3/F4 conversion) against the migrated DB is shown.
Impact: Conversion or close writes could fail in production for the window, or indefinitely after a frontend rollback, because there is no DB rollback path.
Recommendation: Attach the before/after function signatures and confirm new parameters have defaults and the old payloads still resolve. Alternatively, run one old-contract write in the branch inside a rolled-back transaction. State explicitly that the DB has no rollback beyond forward-fix.

[P2] Edge parity check compares whole objects; a pass is suspicious given the observed tool aliasing
File: `operar-banco.py`
Lines: 95–101
Problem: `assert result[PARENT]==result[BRANCH]` compares the full CLI JSON. That JSON normally includes per-project fields such as `id`, `created_at` and `updated_at`, which rarely match across two projects. A 19/19 exact match is consistent with the same data being returned for both refs, which is the failure already seen with the MCP connector.
Evidence: Line 99 has no normalization. The PRIMARY reports a 404 for a deleted ref, but has not shown that the live branch ref returns branch-specific values.
Impact: The protection against "a stale Edge bundle merged over a newer parent" could be vacuous.
Recommendation: In the final comparison, show at least one field that must differ between the projects (function `id`, or the project ref in the response). Compare only `slug`, `ezbr_sha256`, `version`, `verify_jwt`, `entrypoint_path` and `import_map`.

[P2] `--linked` combined with `--project-ref` may target the linked project
File: `operar-banco.py`
Lines: 55, 92
Problem: `db query --linked --project-ref …` and `db advisors --linked --project-ref …` rely on `--project-ref` overriding `--linked`. If the linked project (parent) wins, the "antes/despues" advisors were read from production rather than the branch.
Evidence: This is the same aliasing class as the MCP issue. Line 94 prints `BRANCH` even when `label=='parent'`, so the log does not prove the target.
Impact: The advisors 209→210 delta may not describe the branch.
Recommendation: Prove the target, for example with an advisors item or query result that exists only in the branch, such as the Auth fixture count through `db query`. Fix the log label.

[P3] The continuidad oracle mirrors the implementation and can flake
File: `http-comparar.mjs`
Lines: 9, 29–33
Problem: Two issues:
- The expected `proximo_vencimiento` rule ("latest past, else first future", filtered by `activo|vigente|vencido`) is re-implemented in the test instead of coming from the spec. `hoy` is computed at comparison time, not at request time, so the test fails near Lima midnight or when the before and after runs straddle a day.
- Pages ≥2 are only checked for the new fields. Historical parity is compared only for the captured keys.
Impact: Low. The test could miss a semantic error and could flake.
Recommendation: Capture the request timestamp with each response. Also confirm that the multi-page fichas had page-2+ captures in `antes`.

[P3] Branch secrets in /tmp
File: `operar-banco.py`
Lines: 20, 61, 130
Problem: `rama-privada.json` holds the branch service role and DB URL. `auth-fixture-password.txt` exists, and `ultimo-error-privado.txt` may echo connection details.
Recommendation: Delete these files after branch deletion and confirm the deletion in the evidence record.

TEST GAPS:
- The merge path (ledger row execution by Supabase's executor) is never exercised; see P1.
- Performance evidence comes from 500 people/1,700 leads via PSQL, not PostgREST with a JWT and role `statement_timeout`, and is not compared with production volume. The post-merge real Cartera check should record latency, not only correctness.
- No old-frontend write against the migrated DB; see P2.
- `resultado-remoto.json` parity shows duplicate role rows (supervisor 1/17, vendedor 1/17) without actor identity, which makes the evidence ambiguous.
- The generic `test:rls` matrix was NOT RUN. This is stated honestly and the targeted evidence is reasonable, but it should remain NOT RUN in the final report.

ARCHITECTURE RISKS:
- The branch was not built from migrations. Any tooling that assumes branch ≡ replay(ledger) will be misled by the reconstruction; see the first P1.
- TOCTOU between the final guards and the merge: another task can change parent migrations or Edge Functions in that window. After merge, verify the parent ledger ordering (287 + any foreign additions + our 2) and the Edge hashes.

SECURITY RISKS:
- Host and user asserts in `branch_env` (lines 39–42) correctly prevent parent writes via psql.
- The production write goes through `merge_branch` (MCP), even though that connector already misreported project identity. The `branch_id` makes the target intrinsic, but post-merge verification should confirm the target independently via CLI.

REGRESSION RISKS:
- Production migration history drift (P1 versions) will break the next migration workflow rather than this deploy.
- Managed-object drift could land in production if merge is diff-based (first P1).

RECOMMENDED NEXT ACTIONS:
1. Obtain a read-only merge preview or diff for the branch and confirm it contains only the two F8 migrations plus identical Edge bundles.
2. Compare the new ledger rows' `statements` format with existing CLI-created rows, and resolve the `BEGIN`/`COMMIT` and atomicity question. Align versions with filenames or plan an explicit repair.
3. Re-run the Edge comparison on normalized fields, with proof of distinct project responses. Prove the `--linked`/`--project-ref` targeting.
4. Confirm the old frontend is compatible with the new RPC signatures, and state explicitly that the DB has no rollback.

CONFIDENCE:
MEDIUM. The reconstruction code review has high confidence. The findings about merge semantics and executor behavior are hypotheses tied to the attached evidence, because the merge implementation itself was not attached.
