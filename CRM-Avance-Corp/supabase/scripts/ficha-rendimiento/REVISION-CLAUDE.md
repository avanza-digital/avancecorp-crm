# Revisión independiente — 15/09/2026

Primer intento: el wrapper rechazó salida incompleta/sin VERDICT; no es una revisión válida. Segundo intento: wrapper con ocho turnos máximos y evidencia compacta, salida íntegra siguiente. Ambos mediante scripts/claude-review, sin herramientas ni escrituras del revisor.

VERDICT: CHANGES_REQUESTED

SUMMARY:
Within the attached evidence, the candidate preserves correctness and security. The uuid variant returns exactly the same row as the full listing for the canonical identity. It stays owner-only, and both visibility checks in the ficha keep the `where inversionista_id=v_id` filter, so a fusion during the read still denies. I found no P0 or P1 issues. The main problem is that the change probably won't make the ficha faster: nearly all the expensive work is still materialized for the whole portfolio. The local benchmark supports this (analista 237.861 to 238.880 ms), so a Level 3 migration is being added without shown benefit. There are also two minor robustness gaps in the migration.

FINDINGS:

[P2] The filter does not reach the materialized CTEs, so most of the cost remains
File: CRM-Avance-Corp/supabase/migrations/20260915170237_crm_ficha_lectura_individual.sql
Lines: 32-79 (identidades, todas_fuentes, con_historia, perfiles_enlazados, leads_enlazados, bandeja_supervisor), 83
Problem: The `i.id=(select id from destino)` filter only trims `autorizadas`. Every CTE is `as materialized`, which blocks pushdown. So `identidades` still runs `private.inversionista_canonica` (a recursive call) for every row in crm.inversionistas. `private.cartera_f5_fuentes()` still returns all 616 sources, and the demo unions, profiles and leads are still aggregated for the whole portfolio.
Evidence: diagnostico-produccion.json shows the Function Scan of cartera_f5_fuentes (14438 hits) as a heavy node. Only the second node, the CTE Scan `fuentes` with 12278 loops from the `ce` lateral, depends on how many rows `autorizadas` has. The local median improves about 10% for Gerencia and gets slightly worse for Analista.
Impact: The 1045 ms case probably drops only by the lateral's share. The <1 s target may still be missed after publishing a critical migration, and the dual-signature complexity stays.
Recommendation: Before publishing, run EXPLAIN ANALYZE BUFFERS on the new variant on the authorized bench, as Gerencia and as analista, with production volume. If the gain isn't material, restrict the base CTEs to the destination's aliases. For example, build `identidades` from the ids whose canonica is `destino`, and filter `todas_fuentes`, leads and profiles by those ids. Then repeat the 624/320 parity and the three revocation checks. Another option is a `cartera_f5_fuentes` variant filtered by inversionista, like `cartera_f5_fuentes_reales`, which the ficha already filters by `v_id`. Do not keep the change if it doesn't meet the target.

[P3] Passing null means "whole portfolio" in the uuid signature
File: same migration
Lines: 83; line 17/128 of the resulting ficha
Problem: `p_inversionista is null` returns every row. If `private.inversionista_canonica(p_inversionista)` returns null (null input or a nonexistent id, depending on the helper), the ficha calls the variant with null and computes the full listing before filtering `inversionista_id=null`.
Evidence: Line 83 together with the replacement on line 156. The result is still correct (null returns no rows), and the behaviour matches before. Hypothesis: this could be an amplification path for invalid ids.
Impact: Only performance, and it doesn't worsen the baseline. It is still a footgun for future callers of the private helper.
Recommendation: In the ficha, return null when `v_id is null` before querying (that would change the definition, so re-hash it). Or document the null semantics in the helper header.

[P3] No postcondition hash; the final ficha source is not in the repository
File: same migration
Lines: 149-167
Problem: The ficha is produced with dynamic `replace` + `execute`. The migration only checks the ACL of the new variant. It does not check that the three resulting definitions match the tested hashes (f99c0aae…, 0d7aee4c…, d0c6543b…). The final ficha body can't be found in the repo with grep.
Evidence: Lines 158-165 check only aclexplode. REVERSA.sql does require those three hashes, so they are already known.
Impact: `pg_get_functiondef` output can vary between major Postgres versions. A replay from scratch after an upgrade could fail the entry guard, or install text nobody reviewed, without an early signal. Traceability for the ficha also suffers.
Recommendation: Add a final DO block that asserts the three MD5s and the ACL/owner of the zero-argument signature and the ficha. Record the resulting ficha definition in MIGRACIONES.md or as a commented block.

Checks with no findings:
- Equivalence: no CTE depends on the set in `autorizadas`, and the laterals are per row. So the output for a canonical id X equals row X of the full listing.
- The inner `destino` re-canonicalizes `v_id`. After a concurrent fusion it returns the new canonical identity, and the outer filter rejects it, which matches revocacion_fusion PASS.
- ACL: `revoke all` also covers the PUBLIC EXECUTE default. The aclexplode check with `acldefault` detects a null proacl.
- `CREATE OR REPLACE` keeps the owner and ACL of the zero-argument signature and the ficha.
- `auth.uid()` depends on JWT GUCs, not current_user, so the nested SECURITY DEFINER call doesn't change the actor.
- No ambiguous overload, because there are no DEFAULTs.
- The strict input guard plus the exact count of 2 make the replacement deterministic.

TEST GAPS:
- EXPLAIN ANALYZE of the new variant and of the authenticated RPC on production volume (NOT RUN; blocks the performance claim).
- Real revocation races between two sessions: flag changes, reassignment and fusion committed between line 17 and 128. The current tests use local instrumentation.
- A ficha test with a nonexistent `p_inversionista` or a canonica returning null, including a plan or time check.
- Replaying from a clean database with `supabase db reset` on the same Postgres major version as production, to confirm the entry hashes.
- General RLS, advisors, Auth HTTP and remote types (NOT RUN, already declared).

SECURITY RISKS:
- No new exposure found. The variant takes an arbitrary id but is not executable by anon, authenticated or service_role.

REGRESSION RISKS:
- The listing now has an extra non-inlinable SECURITY DEFINER hop. The local impact is negligible, but confirm it on the bench.

RECOMMENDED NEXT ACTIONS:
1. Measure the installed variant on the authorized bench. If it doesn't show a material gain, push the filter into the base CTEs or drop the change.
2. Add a postcondition with the three MD5s and the complete ACLs.
3. Decide how the ficha handles a null `v_id` and re-hash.
4. Run the real two-session race tests and the pending remote checks before publishing.

CONFIDENCE:
MEDIUM. Security and equivalence are HIGH, based on the full sources attached. Performance is LOW, because the variant has no plan on real data.
