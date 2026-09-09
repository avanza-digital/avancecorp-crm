VERDICT:
CHANGES_REQUESTED

SUMMARY:
The reader preserves the gerencia guard, ACL and `search_path = ''`, and the conversion set is de-duplicated by construction (one row per `crm.leads.id`, cohort-restricted via `v_filas`). No inflation vector found in the frontend either: `movimientos` is keyed by `conversion-${leadId}` and `convertidos` counts leads. Two substantive gaps remain: the reader does not verify that `perfil_id` is a *client* profile, and the annulment predicate is inconsistent with the one used two CTEs above.

FINDINGS:

[P1] Conversion is credited without checking the linked profile is a client
File: supabase/migrations/20260909015744_crm_citas_deposito_por_conversion_cliente.sql
Lines: 88
Problem: The rule is "converted into a client", but the filter is only `l.perfil_id is not null`.
Evidence: The authoritative `crm.convertir_lead(uuid,uuid)` validates `public.perfiles.rol='cliente'` before setting `perfil_id`; the reader does not re-assert it. Comment on line 81-82 claims the external path is excluded, but the exclusion mechanism is only nullability of `perfil_id`.
Impact: Any other write path that populates `leads.perfil_id` with a non-`cliente` (or inactive) profile while `etapa='convertido'` inflates the count. Hypothesis — I cannot see all writers of `leads.perfil_id`; confidence MEDIUM.
Recommendation: `join public.perfiles pc on pc.id=l.perfil_id and pc.rol='cliente' and pc.activo`. This makes the reader independent of write-path discipline and is free at this cardinality.

[P2] Two different annulment predicates in one function
File: same migration
Lines: 47 vs 90
Problem: `cierre_posterior` uses `private.cierre_externo_anulado(la.lead_id)`; `conversiones` uses `private.cierre_anulado(l.id)`.
Evidence: Lines 47 and 90; only `cierre_anulado` was supplied.
Impact: The same lead can render `cerrado=true` yet produce no conversion event (or vice versa), which is hard to explain in the UI and hard to maintain. Also, per the quoted definition `cierre_anulado` is a plain `EXISTS` over `crm.cierres_avance_anulados`, with no comparison to `l.convertido_en`: a lead annulled once and then genuinely re-converted is excluded forever (undercount, not inflation).
Recommendation: State in the comment why the predicates differ, or gate the annulment on `anulado_en <= l.convertido_en` if re-conversion is reachable.

[P3] `montos` silently degrades to zero for the new source
File: app/src/components/citas/depositos.ts
Lines: 20-26, 89
Problem: `montosDepositados` skips `conversion_cliente`, so `montos` is `{PEN:0,USD:0}` whenever every deposit comes from V2.
Evidence: Line 22 early-return; line 89 feeds it into the returned object.
Impact: If any consumer renders `montos`, users see "0" next to a non-zero `convertidos`, reading as a real amount rather than "not available". The consumers (`ficha-recorrido.tsx`, `inasistencias.tsx`) were not attached, so I cannot confirm. Consider returning `null` when no monetary source exists.

[P3] `fecha > asistioEn` is strict at millisecond resolution
File: depositos.ts:73 — `Date.parse` truncates to ms; a conversion recorded in the same millisecond as `asistencia_registrada_en` is dropped. Low likelihood, worth a comment.

TEST GAPS:
- No case where `perfil_id` points to a non-`cliente`/inactive profile (covers the P1 vector; the script only covers `perfil_id is null`, n=4).
- Annulment is only exercised via `crm.cierres_avance_anulados` (line 27-28); the `cierres_externos` branch of `cierre_anulado` is untested.
- No assertion that `cierre_posterior` and the conversion set agree for the same lead.

REGRESSION RISKS:
- A deployed V1 frontend would reject a V2 payload at citas-gerencia.ts:74-78 ("respuesta incompleta"). Migration and bundle must ship together; local-only scope noted.

RECOMMENDED NEXT ACTIONS:
1. Add the `perfiles.rol='cliente'` join and a negative test.
2. Justify or unify the two annulment predicates.
3. Confirm no UI renders `montos` as an amount under V2.

CONFIDENCE:
MEDIUM
