VERDICT:
CHANGES_REQUESTED

SUMMARY:
The core economic path is sound. Validation and writing are shared, `lead_origen_id` is immutable, and a partial unique index covers each lead. The lead closes inside the same confirm transaction, a BEFORE trigger backstops old bundles, and legacy entry points are cut off. The SQL rollback and HTTP evidence cover the main invariants well: one inversion, one conversion, the seller, and idempotent retries.

I found no P0. There is one P1 I cannot rule out from the evidence given: whether a lead-origin request can be cancelled on the server. There are also several P2 issues in the transition, the welcome email, and the new polling reader. Some findings depend on function bodies that were not attached; those are marked as hypotheses.

FINDINGS:

[P1] A lead-origin request may be impossible to cancel, leaving the lead permanently stuck
File: `supabase/migrations/20260918174540_crm_conversion_inversion_unificada.sql`
Lines: 329-331, 45-46, 578-585
Problem: The request-cancellation RPC (the UI renders `estado==='cancelada'` at `inversion-nueva.tsx:240`) is neither anchored nor replaced by this migration. If it still calls the 1-arg `private.inversion_persona_contexto(p)`, it now raises P0409 for every lead-origin request.
Evidence:
- The 1-arg wrapper passes `p_lead=null` (line 370). With `p_lead is null and v_l.etapa<>'convertido'`, it raises "Completa la conversión inicial" (line 329). By definition, the lead of a `preparada` conversion request is not converted.
- Corrections forbid changing `empresa` or `moneda` (lines 578-585). The comment says the fix is to cancel and prepare another request.
- The unique index (lines 45-46) blocks a second `preparada` request for the same lead.
- `test-conversion.sql:80` claims "cancelación" but never calls a cancel RPC. The browser "cancel/reopen" case appears to close the dialog, not cancel on the server.
Impact: A lead-origin request prepared with the wrong cooperative or currency cannot be corrected, cancelled or replaced. The lead can never convert without manual SQL.
Recommendation: Attach the cancel function body. If it uses the 1-arg context, make it pass `lead_origen_id`, as you did for correct/review/access. Add an HTTP and SQL case: prepare lead-origin (Prodelco PEN), cancel, prepare a new request (Prodelco USD), confirm, and assert one conversion.

[P2] The 15-second polling reader takes write locks, and any transient error replaces the form
File: `supabase/migrations/20260918174540_crm_conversion_inversion_unificada.sql:166-185`, `app/src/components/app/inversion-nueva.tsx:70-77,181-184`
Problem:
- `contexto_conversion_inversion_fn` runs the 2-arg `inversion_persona_contexto`. That takes `FOR UPDATE` on `crm.inversionistas` (line 289), `for share nowait` on the lead (line 325), and `for update nowait` on `conversion_reservas` (line 351).
- The query uses `refetchInterval: 15_000` and `refetchOnWindowFocus: 'always'`.
- On the client, `ficha` is null unless `isSuccess`. In TanStack v5, a failed refetch with cached data sets `status='error'`, so `ficha` becomes null.
Evidence:
- A 55P03 from NOWAIT, or a 5s `lock_timeout` while a confirm or reassignment holds the person row, makes line 181 render `PanelError`. That unmounts `ContratoNuevo` or `InversionCooperativa` mid-edit and loses unsaved input, including the selected receipt file.
- Business-rule failures in the 2-arg context also surface as an error panel rather than `capacidades.nueva_inversion=false` with a reason. Examples: `no_contactar`, an inactive `responsable`, or a person/lead `responsable` mismatch during reassignment. This diverges from the Cartera ficha.
Impact: Lost user input and a UX that diverges from Cartera. The poll also adds lock contention against confirm on the same person.
Recommendation: Make the reader lock-free. Compute capabilities without `FOR UPDATE`/`NOWAIT`, and map rule failures to `nueva_inversion:false` plus `motivo_no_operable`; writers already revalidate under locks. On the client, keep showing the last good `fichaQ.data` on refetch error, and show the error panel only when there is no data.

[P2] Hypothesis: legacy reservation refresh via UPDATE bypasses the INSERT-only cut-off
File: migration lines 18-36
Problem:
- The install check only refuses active or sealed reservations for open leads. Expired, effect-free reservations for open leads are allowed to remain.
- The trigger only blocks `before insert`. If `reservar_conversion_lead` (or the old Edge) refreshes an existing expired row with a plain `UPDATE`, it bypasses the trigger. This does not apply to `INSERT … ON CONFLICT`, which fires the BEFORE INSERT trigger. The same applies to later setting `efectos_iniciados_en`.
- That lets an old-bundle tab reserve, and then the old Edge creates Auth.
- `convertir_lead` is then blocked by `trg_leads_conversion_con_inversion`, leaving an orphan Auth user or profile.
Evidence: Production shows 0 open-lead reservations today, but nothing prevents one from appearing before install. The HTTP test only covers a lead with no prior reservation (`count=0`, `http.test.mjs:52`). The `reservar_conversion_lead` body was not attached.
Impact: A possible orphan portal account created by stale bundles.
Recommendation: Attach the legacy reservation writer, or close both paths:
- add a `BEFORE UPDATE` trigger that rejects extending `expira_en` or setting `efectos_iniciados_en` on open leads, or
- include expired rows of open leads in the install refusal.
Add a test using an expired legacy row.

[P2] Hypothesis: the welcome email can be orphaned with no retry surface
File: `inversion-nueva.tsx:90-93`, migration lines 1184-1188
Problem: Welcome delivery is triggered only by the confirming browser, and only when `origenLead` is set. It is not sent from the Cartera path, and there is no server job.
Evidence:
- If the tab closes or the network drops right after confirm, `bienvenida.estado='pendiente'` persists with `primer_intento` null.
- The lead is now `convertido`. If `lead-drawer.tsx` (not attached) hides "Convertir a cliente" for converted leads, no UI path ever retries.
- `verificar_entrega` also has no resolution RPC or UI, even though the text tells Gerencia to verify.
Impact: Some new clients never receive their portal welcome, and no one sees it.
Recommendation:
- Surface the welcome state and a retry action in the Cartera ficha for lead-origin Avance requests, or allow reopening the confirmed request from the converted lead.
- Add a Gerencia-only RPC to mark `verificar_entrega` as resolved or entregada.
- Test the "confirm, then close tab" flow.

[P2] Rate-request (tasa) handling differs between client and server for CE/Pasaporte
File: `inversion-nueva.tsx:279` vs migration lines 1113-1118
Problem: The client passes `leadOrigenId` to `ContratoNuevo` only when `tipoDocumento==='DNI'`. The server always runs `validar_tasa_conversion_lead` and `enlazar_tasa_lead` for every lead-origin Avance confirm.
Evidence: The HTTP CE and PASAPORTE cases never create a `solicitud_tasa`, so the mismatch is untested.
Impact: For a CE or passport lead with a pending or approved rate request, the form cannot show the approval flow, but confirm fails with P0410/P0411. The reverse is also possible: an approved rate that the UI ignores.
Recommendation: Remove the DNI-only gate, or state why the tasa lead flow is DNI-only and make the server consistent. Add a CE case that has a rate request.

[P2] The new lead trigger may regress other `→ convertido` transitions
File: migration lines 1623-1640
Problem: Every `etapa` change to `convertido` now requires a confirmed lead-origin request with a first-conversion inversion. It also requires `i.inversionista_id = new.inversionista_id`.
Evidence: The 40 historical converted leads have no `lead_origen_id` request.
Impact:
- Any existing flow that moves such a lead out of `convertido` and back will now fail. Possible examples are a Gerencia reopen or correction, an identity merge that rewrites `etapa`, or data repair.
- After an identity fusion, the lead's `inversionista_id` may be the origin id rather than the canonical id. That fails the equality check and blocks confirming a request that was prepared before the fusion.
Recommendation: Enumerate every writer of `crm.leads.etapa`. Consider exempting leads that were converted before install, and compare `inversionista_canonica(new.inversionista_id)`. Add a fusion-between-prepare-and-confirm test.

[P2] The welcome email embeds a credential hint
File: `supabase/functions/crm-inversion-bienvenida/handler.mjs:9`
Evidence: The body says "Tu contraseña temporal es tu número de documento" next to the login email. A Peruvian DNI is low-entropy and often known to third parties.
Impact:
- If the portal Edge really sets password = document, then emailed email plus scheme gives an easy takeover path before first login. `debe_cambiar_password` only protects after the first login.
- If the Edge does not set that password, the email misleads the client.
Recommendation: Confirm the actual password behavior in `crm-inversion-portal` (unchanged, so not attached). Prefer a set-password or magic link over a document-based temporary password. At minimum, make the v1 text match reality before it is frozen by the immutable-v1 rule.

[P3] The token-hash rewrite targets the persona key, not the saga key
File: migration lines 873-878 vs 798-800
Evidence: The saga is looked up by `coalesce(auth_contexto->>'inversionista_id', v_origen)`, but the update uses `'auth_persona:'||v_persona` (canonical) and does not check the affected row count.
Impact: After a fusion, zero rows update, but `v_r.token` is still set to the caller's token. Every later step then fails with 42501 "Token de recuperación inválido".
Recommendation: Use `v_saga.clave`, or the key returned by `saga_auth_reclamar`, and assert `found`.

Separately, confirm with a test that `saga_auth_reclamar` rejects a *different* token after lease expiry when the claim has `auth_user_id` set. Otherwise this overwrite lets a second scoped user adopt an in-flight Auth claim.

[P3] `f4_comprobante_autorizado` now raises instead of returning false for closed leads
File: migration lines 982, 987
Evidence: The 2-arg context raises P0409 when the lead is `convertido` or `descartado` (line 339). Only `insufficient_privilege` is caught.
Impact: Storage policy evaluation for a confirmed lead-origin path errors with 4xx/5xx instead of a clean deny.
Recommendation: Catch the `P0409`/`P0429`/`55P03` class and return false. Also attach `f4_comprobante_visible`: it is anchored but not replaced, so confirm it does not use the 1-arg context. If it does, the 409 recovery path in `subirComprobanteInversion` (download, then compare hashes) breaks for pending conversions.

[P3] Smaller items
- `preparar_inversion_fn:404`: casting `lead_id` outside an exception block gives a raw 22P02. A concurrent insert with a different key can surface a raw 23505 from the unique index instead of P0409.
- `preparar_persona_lead_inversion_fn:100` checks `no_contactar` before the confirmed-recovery branch at line 114. A later No-insistir flag makes recovering the confirmation view fail.
- Lines 147-153: "Continuar a Nueva inversión" durably binds the person, assigns a responsable and rewrites `nombre_completo` with no activity row. A DNI typo then needs a Gerencia identity correction.
- `convertir_lead_externo`: roughly 350 lines are unreachable after the `raise` at line 1266. Consider replacing the body with the idempotent read plus the raise, to cut review surface.

TEST GAPS:
- Server-side cancel of a lead-origin request, then a new request on the same lead (P1).
- Two concurrent `preparar_inversion_fn` calls with *different* keys on the same lead, expecting P0409 rather than 23505.
- Discard a lead while its request is `preparada`: is the request cancellable or recoverable, and what happens if the lead is reopened?
- An expired legacy reservation on an open lead, driven by the old reserve RPC or Edge (UPDATE path).
- A CE or passport lead with a pending or approved rate request.
- An identity fusion between prepare and confirm, covering the trigger equality check and the token_hash key.
- The polling reader during a concurrent confirm or reassignment, asserting the form is not unmounted.
- Confirm, then tab loss: the welcome can still be retried from some UI.
- Full fresh migration apply plus reversal replay, and the final broad E2E (reported as not finished).

ARCHITECTURE RISKS:
- Keeping the "2-arg vs 1-arg context" split correct depends on every caller that reads a lead-origin request passing `lead_origen_id`. Unreplaced callers (cancel, `preparar_reinversion_fn`, `f4_comprobante_visible`) silently get Cartera-only semantics. Consider having the 1-arg wrapper resolve `lead_origen_id` itself when the person's only request is lead-origin, or grep every caller and attach the list.

SECURITY RISKS:
- The welcome email's temporary-password statement (see the P2 above).
- The token adoption in `acceso_inversion_fn` relies on `saga_auth_reclamar` verifying the token in every non-fresh branch. The body was not attached; verify with a test after lease expiry.
- The ACL/grant set on the new functions looks correct: service-only delivery, and authenticated-only for the others.

REGRESSION RISKS:
- Other writers of `leads.etapa`, per the trigger finding.
- Legacy convert and reserve RPCs now raise for stale bundles, which is intended. Make sure the old UI shows the "Actualiza el CRM" message rather than a generic failure.

RECOMMENDED NEXT ACTIONS:
1. Attach or verify the cancel RPC body and fix the P1 if needed. Add the cancel-and-reprepare test.
2. Make `contexto_conversion_inversion_fn` lock-free and error-tolerant, and keep the last good data in `InversionNueva`.
3. Close the legacy reservation UPDATE path, or broaden the install refusal. List every writer of `leads.etapa` and adjust the trigger for pre-existing converted leads and fusion.
4. Give the welcome email a retry and resolution surface outside the confirming tab, and reconcile the password text with the portal Edge.
5. Finish the fresh migration and reversal replay and the broad E2E before any production step.

CONFIDENCE:
MEDIUM. The attached SQL and TSX support these findings directly. The P1 and some P2 items depend on unattached bodies: the cancel RPC, `reservar_conversion_lead`, `saga_auth_reclamar`, `f4_comprobante_visible`, `lead-drawer.tsx` and `crm-inversion-portal`. I have marked those as hypotheses.
