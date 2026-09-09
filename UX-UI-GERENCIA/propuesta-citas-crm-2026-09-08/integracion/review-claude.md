VERDICT:
CHANGES_REQUESTED

SUMMARY:
The ACL gate, period validation, definer hardening and the "no deposit inference" contract look sound. Two issues can produce wrong Gerencia numbers or a hard-failing screen; three more are robustness/perf.

FINDINGS:

[P1] Client schema rejects nullable lead columns; one bad row kills the whole month
File: supabase/migrations/20260909003243_crm_citas_gerencia_consulta_detallada.sql:46-52; app/src/data/citas-gerencia.ts:13-17,59-63
Problem: The server emits `nombre`, `telefono`, `origen`, `moneda`, `monto_estimado` raw from `crm.leads` (only `analista_nombre`, `supervisor_nombre`, `modalidad`, `resultado`, `nota` are coalesced). The client requires `v.string()`, `v.picklist(['PEN','USD'])` and `v.pipe(v.number(),v.finite(),v.minValue(0))` — all non-nullable.
Evidence: line 52 `'moneda',t.moneda,'monto_estimado',t.monto_estimado` vs schema line 17; `safeParse` failure at line 59 throws `CITAS_CONTRATO` for the entire response, and the UI hides tables/exports on error.
Impact: A single lead with NULL/negative `monto_estimado`, NULL `telefono`/`origen`, or a `moneda` outside PEN/USD makes all 152 appointments unavailable, with a message that misleadingly blames the period. The 152-row census does not prove these columns are NOT NULL.
Recommendation: Coalesce on the server (`coalesce(l.telefono,'')`, `coalesce(l.monto_estimado,0)`, `case when l.moneda in ('PEN','USD') then l.moneda else 'PEN' end`) or make the client fields nullable; do not leave both ends strict.

[P1] `cierre_posterior` is evaluated over a window narrower than `historial`
File: same migration, lines 34-37 vs 38-43 and 58; app/src/data/citas-gerencia.ts:41-42
Problem: `historial` returns the lead's full appointment history with no lower date bound, but `cierres` only queries `private.conversion_episodios(v_ini, greatest(v_fin,v_ahora), ...)`. Closes that occurred before `v_ini` are invisible.
Evidence: line 58 `c.fecha_numerador>=t.vence_en` can never be true for a pre-month appointment closed before `v_ini`, because such an episode is not in the CTE at all.
Impact: Historical rows shown for lineage render `cerrado=false` and, when `estado='completada'`, `seguimiento=true` (frontend line 42) — the follow-up/no-show funnel the user asked for will list already-closed leads as pending follow-up. Wrong direction for the 27 linked-successor cases.
Recommendation: Widen the episode window to `min(vence_en)` of `historial`, or restrict `cierre_posterior`/`seguimiento` to appointments inside the requested month and mark out-of-window rows explicitly.

[P2] `citas_clientes` uses different filters than the cohort
File: same migration, lines 72-74
Problem: The count omits `creado_en<=v_ahora` and any `crm.leads.activo` correlation, and counts rows, not distinct subjects.
Evidence: `cohorte` (31-33) applies `t.creado_en<=v_ahora and l.activo`; the count does not.
Impact: The client figure is not snapshot-consistent with `generado_en` and is not comparable to the "mean appointments per unique lead" denominator the user defined. Hypothesis (unverified): `perfil_id is not null` may overlap rows already counted as leads.
Recommendation: Apply the same `creado_en<=v_ahora` bound, state in the JSON whether it counts appointments or distinct clients, and rename accordingly.

[P2] `Date.parse` on PostgreSQL timestamptz rendering is implementation-defined
File: app/src/data/citas-gerencia.ts:10,30,37-38
Evidence: `jsonb_build_object('vence_en',t.vence_en,...)` renders ISO with a space separator (`2026-09-08 15:00:00+00`), not `T`. ECMA-262 leaves non-ISO parsing engine-specific.
Impact: Correct in Chromium/jsdom, potentially NaN elsewhere; `Instante` would then reject and fail the whole month via the same `CITAS_CONTRATO` path.
Recommendation: Emit `to_char(t.vence_en at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')` (or `to_jsonb` of an explicitly formatted text) and keep the client check.

[P2] O(n²) successor lookup on the render path
File: app/src/data/citas-gerencia.ts:43
Evidence: `datos.citas.find(...)` runs per row; the contract allows 10000 rows.
Impact: Up to 10^8 comparisons synchronously on the main thread.
Recommendation: Precompute one `Map` keyed by `` `${reagendada_de}|${lead_id}` `` before `map`.

[P3] Comment does not describe the code
File: app/src/data/citas-gerencia.ts:73-74 — the "no reutilizar filas de otro mes" comment sits on `retry:1`; the property that enforces it is the absent `placeholderData`/the key at line 69.

TEST GAPS:
- Row with NULL `telefono`/`monto_estimado`/unexpected `moneda` (expect graceful render, not whole-screen error).
- Lead closed before `v_ini` with an earlier completed appointment (expect no false `seguimiento`).
- Fixture using real PostgREST timestamp text, not JS-generated ISO.
- 10000/10001-row boundary for the `54000` path and client `maxLength`.

CONFIDENCE:
MEDIUM — column nullability, `conversion_episodios` semantics and `CitaConLead` estado union were not in the attached evidence.
