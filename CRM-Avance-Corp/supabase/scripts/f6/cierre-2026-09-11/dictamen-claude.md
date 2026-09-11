VERDICT: CHANGES_REQUESTED

SUMMARY:
No blocking regression found in the diff. The focus-restore logic and the transport-error mapping are coherent with the attached evidence and tests. Two actionable items remain: an out-of-scope UI change bundled into the release commit with no stated verification, and an over-broad catch-all in `respuestaInversionistas`. Neither is P0; both are cheap to resolve or explicitly accept before publishing.

FINDINGS:

[P2] Catch-all `!code` may mask non-transport server errors
File: CRM-Avance-Corp/app/src/data/inversionistas-api.ts
Lines: ~18-20
Problem: Every error without `code` is reported as "No se pudo recibir la respuesta del servidor", discarding the original `message`.
Evidence: Diff maps `if (!code) throw new CrmApiError('No se pudo recibir…', 'RESPUESTA_NO_RECIBIDA')` before any other branch. The new test only covers `''`/`undefined` with `TypeError: Failed to fetch`; no case asserts a code-less **server** rejection.
Impact: A genuine rejection arriving without `code` would be shown as a connectivity problem and would invite a retry, plus its message is lost for diagnostics. Hypothesis, not verified: I have no evidence of a code-less server-error shape on this path.
Recommendation: Either narrow the condition (e.g. also require absence of `details`/`hint`, or match the fetch-failure message) or preserve the original message as `cause`/detail so support can distinguish cases.

[P2] `input.tsx` file-input styling is unrelated to F6 and unverified
File: CRM-Avance-Corp/app/src/components/ui/input.tsx
Lines: +17
Problem: A global visual change (`h-auto min-h-11`, `file:*`, `text-muted-foreground`) is included in the publication commit.
Evidence: The diff adds it; the request scope is "cierre y publicación de ajustes finales F6"; no test, screenshot, or affected-screen list is attached, and `check:all` does not assert appearance.
Impact: Affects every `type="file"` Input app-wide; a visual regression would ship unnoticed and would be attributed to F6 during rollback triage.
Recommendation: Name the screens it targets and attach one visual check, or exclude it from this release commit.

[P3] Focus restore depends on `requestAnimationFrame` and on a focusable fallback
File: CRM-Avance-Corp/app/src/components/ui/dialog.tsx
Lines: ~42-62
Problem: If `origen` is connected but hidden/inert and `ambito` is null, focus falls to `document.body`; if the tab is backgrounded, the rAF may not run.
Evidence: The fallback branch requires `ambito?.isConnected`; the early return only covers the case where both are disconnected.
Impact: Rare focus loss in non-nested dialogs. Recommendation: fall back to Radix default (do not `preventDefault`) when no valid destination exists.

TEST GAPS:
- New tests use a synthetic `Pantalla`, not the three real callers CodeGraph lists (lead-drawer, lead-nuevo, contacto).
- No test for stacked Dialog-in-Dialog close ordering asserted in the file header.
- No test for the "neither origin nor scope connected" default-restore path.

REGRESSION RISKS:
- Focus restore now bypasses Radix's default for all Dialog consumers, not only F6.

RECOMMENDED NEXT ACTIONS:
1. Decide on the `!code` narrowing or document acceptance.
2. Justify or drop the `input.tsx` change.
3. Proceed with the listed publication steps; they look complete — add an explicit rollback-ZIP restore rehearsal if not already covered.

CONFIDENCE:
MEDIUM
