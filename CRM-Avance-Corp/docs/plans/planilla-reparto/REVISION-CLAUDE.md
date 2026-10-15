VERDICT:
CHANGES_REQUESTED

SUMMARY:
The client-side matrix is mostly sound. It has a single-flight lock (`candado`), abort-aware loads, strict validation of agenda windows, FIFO with frozen IDs, and it stops on the first failure instead of retrying. The backend claims (row lock, actor/target checks, `no_contactar`, free-mode check) could not be verified because the `repartir_lead` and agenda RPC bodies were not attached, so they are treated as given. The actionable problems are in the UI. Expected business rejections are reported as "uncertain". A review-time validation error hides the matrix being edited. Totals depend on a pending-queue read whose completeness is not shown. Plan order depends on which cell was edited first.

FINDINGS:

[P2] Deterministic backend rejections are reported as "uncertain" and stop the batch
File: CRM-Avance-Corp/app/src/lib/planilla-reparto.ts
Lines: 103-109
Problem: `catch {}` discards the error. Every failure becomes "No se confirmó esta entrega. Puede haberse registrado…".
Evidence: The backend rejects leads that are already assigned, not in an allowed stage, `no_contactar`, or when free mode is off (per PRIMARY). With two coordinators, or the other reparto screen, both FIFO plans start from the same oldest leads. A collision on the first lead is the expected case, not an edge case.
Impact: The coordinator is told the delivery may have been recorded and to check history, but it definitively was not. The rest of the plan is abandoned even when only that one lead was taken.
Recommendation: Have `repartirLead` surface a typed error that separates a definitive rejection (a known SQLSTATE or code from the RPC) from transport or unknown failures. Report definitive rejections as "rechazada: <motivo>", in their own count. Either continue or stop with a precise message. Keep the "uncertain" path only for network or timeout errors.

[P2] A validation error during "Revisar reparto" hides the whole matrix
File: CRM-Avance-Corp/app/src/components/app/planilla-reparto.tsx
Lines: 113, 160
Problem: `revisar()` sends every failure to `setError`, and the main block renders only when `!error`.
Evidence: Line 160 is `... datos && !error ? <> ... </> : null`. Errors such as "Las cantidades superan los pendientes…", "Prepara al menos una entrega." or a destination that became inactive all set `error`.
Impact: The inputs the user must adjust vanish. The only way back is "Actualizar", which keeps `borrador` but leaves the user editing blind until the reload finishes. That is poor UX for a recoverable validation error.
Recommendation: Keep load errors (`error`) separate from plan or review errors, for example a `errorRevision` shown next to the button like `errorPlan`. Hide the table only when the data could not be loaded.

[P2] Truthfulness of "Pendientes disponibles" depends on the queue read being complete (hypothesis, not verified)
File: CRM-Avance-Corp/app/src/data/planilla-reparto.ts:7, `leadsPorRepartir` in crm-api (not attached)
Problem: All totals and the FIFO plan assume `leadsPorRepartir` returns the entire unassigned queue.
Evidence: No evidence was attached about a limit, PostgREST `max-rows`, or pagination. The agenda gets strict completeness checks (lines 20-22), but the queue gets none.
Impact: If the read is capped, the "Pendientes disponibles", "Pendientes después del plan" and per-origin counts are understated. FIFO stays correct only if the server also orders by `creado_en, id`, and the entry-date filter silently misses leads.
Recommendation: Attach the `leadsPorRepartir` and RPC definition. If it is capped, return a total or truncation flag and refuse to plan when the read is truncated, in the same spirit as the agenda check.

[P3] FIFO allocation across supervisors follows the order cells were edited
File: CRM-Avance-Corp/app/src/lib/planilla-reparto.ts
Lines: 81-91
Problem: `Object.entries(borrador)` iterates in insertion order. Whichever supervisor's cell was typed first gets the oldest leads of each origin.
Impact: Lead age across supervisors becomes arbitrary and not reproducible. This is a fairness issue for SLA and aging.
Recommendation: Iterate destinations in a defined order, such as display order or round-robin interleaving per origin. Document the choice and add a test for it.

[P3] Stopping at midnight is reported as a manual stop
File: CRM-Avance-Corp/app/src/components/app/planilla-reparto.tsx:124; planilla-reparto.ts:102
Evidence: `continuar` combines unmount, `detener` and `hoyLimaIso() === fechaPlan`. All three return "Envío detenido."
Impact: The user sees a stop they did not request.
Recommendation: Return a stop reason, such as `'manual' | 'cambio_de_dia'`, and adjust the message.

[P3] Possible render crash on an invalid `creado_en` (hypothesis)
File: planilla-reparto.ts:51
Evidence: `hoyLimaIso(new Date(lead.creado_en))` runs inside render. If `hoyLimaIso` uses `Intl.DateTimeFormat.format`, an Invalid Date throws `RangeError`.
Impact: One bad row would bring down the whole screen. This is unverified because `hoyLimaIso` was not attached.
Recommendation: Guard against non-finite dates, or check that the crm-api parser already rejects them.

[P3] "Desglose por día" rows grow with days × supervisors
File: planilla-reparto.tsx:185
Evidence: `filasPlanilla` returns every supervisor for each day, including zero rows. Up to 366 days times N supervisors.
Impact: Large DOM and slow renders on long ranges.
Recommendation: Hide all-zero rows or limit the breakdown view to short ranges.

[P3] Minor UX issues
- `cantidadFila` uses `Number(texto) || 0`, so inputs like "1.5" or "-2" show fractional or negative totals until `errorPlan` blocks them (lines 91-92). Clamp the display to valid integers.
- The 366-day mode does up to 27 sequential agenda requests (data file lines 17-18) with no progress indicator. This is acceptable, but worth a note in the loading copy.

TEST GAPS:
- A definitive rejection mid-plan, such as the second lead already taken by another coordinator, versus a network failure. Assert distinct messages and counts.
- An error from `revisar()` keeps the matrix and the `borrador` visible.
- Allocation order does not depend on edit order, once fixed.
- Stop caused by a day change, with its own message.
- Queue completeness or truncation handling.
- Invalid or missing `creado_en` in the queue.
- The 23 existing tests were not attached, so their coverage claims could not be checked.

ARCHITECTURE RISKS:
- Totals rest on two independent reads, the queue and the per-window agendas, done in parallel with no shared snapshot. Counts can be off by in-flight deliveries. That is acceptable because `revisar()` re-reads and the backend is authoritative, but the copy should not imply a snapshot.

SECURITY RISKS:
- None found client-side. Authorization depends entirely on `repartir_lead`, whose body was not provided. Confirm that `supervisoresParaReparto` and the agenda only expose data the coordinator role may see.

REGRESSION RISKS:
- `repartir.tsx` and its test were modified, but no diff was attached. The integration (`onCambio` and `onOcupado` wiring, tab switching through `activo`) could not be reviewed.

RECOMMENDED NEXT ACTIONS:
1. Classify `repartirLead` errors into definitive versus uncertain, and report each truthfully.
2. Separate review-time errors from load errors so the matrix stays visible.
3. Attach or verify the `leadsPorRepartir` limits and ordering, and the `repartir_lead` / agenda SQL bodies.
4. Make allocation order deterministic and add the tests listed above.

CONFIDENCE:
MEDIUM. The attached UI and lib code were reviewed fully. The backend, crm-api, `repartir.tsx` diff and tests were not available.
