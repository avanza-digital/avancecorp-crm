VERDICT: CHANGES_REQUESTED

SUMMARY:
The core direction is sound: one money source (`private.capital_episodios`, `medida='stock'`), identity/relational context from `private.cartera_f5_fuentes`, conversion from `private.conversion_episodios`, read-only, flag-off. But the attached function bodies show four contract items that cannot be implemented as written against the current readers (cotitulares, empresa dimension, "sin identidad" bucket, vencimientos), plus two call-contract ambiguities (Lima boundaries, `p_periodo`/`p_factor`) that silently change numbers. These should be resolved in the contract before any SQL is drafted. No P0 confirmed; no production DDL is implied by the mandatory fixes except possibly one new reader.

FINDINGS:

[P1] Cotitulares are not obtainable from the published readers, and they are conflated with identity conflicts
File: private.cartera_f5_fuentes
Evidence: both branches return a single `ids.personas[1]` plus `cardinality(ids.personas)=1 as identidad_coherente`. There is no column exposing the full person set. For a contract, the lateral aggregates every `crm.inversionistas i where i.perfil_id=c.cliente_id`: two legitimate co-holders on one source yield `cardinality=2`, i.e. `identidad_coherente=false`.
Impact: (a) the contract clause "los cotitulares cuentan como personas participantes, una vez por persona y empresa" has no data path; (b) every genuine cotitular source is reported as "identidad contradictoria" in the coverage warning, inflating that warning and understating person counts.
Recommendation: either drop cotitulares from F7 scope, or add one narrow reader (e.g. `private.fuente_personas(fuente_id) returns setof uuid`, or an extra `personas uuid[]` column on `cartera_f5_fuentes`) that separates "multiple declared holders" from "contradictory identity". This is the one place where evidence shows the stated scope is impossible without touching the core.

[P1] `personas[1]` is nondeterministic when cardinality > 1
File: private.cartera_f5_fuentes
Evidence: `array_agg(distinct private.inversionista_canonica(x.id))` has no `ORDER BY`; `personas[1]` is therefore an arbitrary element.
Impact: any group-by on `inversionista_id` for incoherent sources produces person distributions (1/2/3 empresas) and "oportunidades" that change between identical runs — fatal for a report gerencia will re-open.
Recommendation: F7 must aggregate persons only where `identidad_coherente` is true, and route the rest to the coverage bucket. State this explicitly in the contract.

[P1] "Fuentes sin identidad" fall into NULL, not false
File: private.cartera_f5_fuentes
Evidence: `array_agg` over zero rows returns NULL; `cardinality(NULL)` is NULL, so `identidad_coherente` is NULL for a source with no person at all (contract with null `cliente_id` and no `crm.inversiones` row, coop with all three ids null).
Impact: the contract requires these to be counted in the coverage warning, but both `where identidad_coherente` and `where not identidad_coherente` drop them. They would vanish silently while their capital still appears in the money total — the exact failure the contract tries to prevent.
Recommendation: contract must specify three explicit buckets (`is true` / `is false` / `is null`) and require the sum of the three to equal the stock total.

[P1] The single money source has no empresa dimension
File: private.capital_episodios (RETURNS TABLE list)
Evidence: the output exposes `contrato_id, cierre_externo_id, lead_id, cliente_id…` but no `cooperativa`/`empresa`. Only `cartera_f5_fuentes` carries `empresa`.
Impact: "cada moneda en su propia fila, Avance/Qorilazo/Prodelco separados" requires a join back to `crm.cierres_externos` (or to `cartera_f5_fuentes`) on `cierre_externo_id`. If that join is to `cartera_f5_fuentes` and `crm.inversiones` admits more than one row per `contrato_id`/`cierre_externo_id`, the join fans out and duplicates capital.
Recommendation: contract must name the resolution rule: `contrato_id is not null → 'avance'`, otherwise join `crm.cierres_externos ce on ce.id = cierre_externo_id` for `ce.cooperativa` — never through `cartera_f5_fuentes` for money. Hypothesis, needs evidence: confirm a unique index on `crm.inversiones(contrato_id)` and `(cierre_externo_id)`; if absent, all person/source counts must use `count(distinct fuente_id)`.

[P1] Vencimientos cannot be served by the production window, and must also pin `medida='stock'`
File: private.capital_episodios
Evidence: all three branches are filtered by `p_ini`/`p_fin` on the production date. A contract closed in 2025 that vence in the next 30 days only appears if the window is `-infinity..+infinity`. Separately, the `desglose_*` branch carries the parent's `c.fecha_vencimiento`, so an unfiltered vencimientos query counts the same contract three times (stock + renovado + adicional).
Impact: either a wrong (empty) vencimientos section, or triple-counted contractual capital.
Recommendation: state in the contract that vencimientos reads the full-history window with `medida='stock'` and is reconciled against the production section only by construction, never by equality. Note the cost: `private.analista_atribuido_cadena()` plus a correlated `metas_vendedor`/`meta_periodos` EXISTS per row over all history, evaluated in the select, the EXISTS and the WHERE — consider `cartera_f5_fuentes` or a narrow dedicated reader for this section instead.

[P1] `p_periodo`/`p_factor` change every referido and renovación weight
File: private.conversion_episodios
Evidence: `case when p_periodo is not null then p_factor else private.peso_referido_conversion(...) end`, in both the `cierre` and `operacion` arms.
Impact: passing `p_periodo` non-null with a default/derived `p_factor` silently overrides the per-period weight for the whole result, with no error.
Recommendation: the contract must fix the call form. For a shadow read of a sealed month, the factor must come from the sealed period; otherwise pass `p_periodo := null` and let the core compute it. Whichever is chosen, the RPC output must echo the factor actually used.

[P1] Flag must gate the data RPC, not only the state RPC
File: proposed `crm.metricas_multiempresa_fn` / `crm.metricas_multiempresa_estado_fn`
Evidence: the contract only states that `metricas_multiempresa_sombra` "nace apagada" and that gerencia membership is re-verified per call.
Impact: a client can call the data RPC directly while the flag is off; the kill switch would not actually stop data flow.
Recommendation: check flag **and** membership inside `metricas_multiempresa_fn`; keep its signature free of any scope parameter and hardcode `p_global := true` after the check, so no caller input reaches `p_global`/`p_visibles` of the SECURITY DEFINER readers.

[P2] Lima-midnight boundary is asymmetric between branches and only half-stated
Evidence: the header contract in `capital_episodios` is explicit — contracts/desgloses partition by **local date**, cooperativas by **instant** (`coalesce(fecha_imputacion at Lima, creado_en) >= p_ini`). If F7 passes anything other than Lima midnights, coop rows near month edges shift by the UTC offset while contracts do not.
Recommendation: the contract must specify literally: `p_ini := date_trunc('month', p_mes) at Lima midnight (timestamptz)`, `p_fin := p_ini + 1 month`, current month capped at tomorrow's Lima midnight, and define "mes futuro inválido" against Lima today.

[P2] Three coexisting definitions of "first"
Evidence: `cartera_f5_fuentes.es_inicial` is `iv.es_primera_conversion` for Avance and `ce.es_cierre_inicial` for coops; F7 adds a computed "primera registrada" ordered by fecha comercial/registro/empresa/id. Also, `iv` is a left join, so `es_inicial` is NULL whenever the relational row does not exist yet — matching the contract's own "incluso si aún no tiene fila relacional" — and `where es_inicial` / `where not es_inicial` both drop those rows.
Recommendation: label the computed metric distinctly, never as "primera inversión", and handle the NULL `es_inicial` bucket explicitly.

[P2] Conversion is perfil-scoped, production is identity-scoped
Evidence: `row_number() over (partition by o0.cliente_id, o0.periodo)` — the one-eligible-operation-per-month limit is per `cliente_id`, not per `private.inversionista_canonica`. The `cierre` arm is per lead.
Impact: the same canonical person with two perfiles can contribute two conversions in a month, contradicting "una inversión posterior no concede otra conversión inicial" as read through the F7 identity lens.
Recommendation: state in the contract that conversion figures remain at core granularity (perfil/lead) and are not identity-deduplicated; do not place them in the same table as identity-deduplicated person counts without that label.

[P2] "Producción" includes full renewal capital
Evidence: `'contrato_' || coalesce(c.categoria,'nuevo')` with `medida='stock'` and `c.capital`; only the `desglose_*` rows are excluded by the stock filter.
Impact: a renewed contract reports its whole capital as production of the month; gerencia will read the total as net new money.
Recommendation: label the metric as capital de cierres del mes (stock) and expose the `categoria` breakdown so nuevo/renovacion/upgrade is visible without re-summing.

[P2] Demo classification is duplicated by literal UUID in two bodies
Evidence: `'a112aead-184a-4979-9041-943978fadae4'` appears hardcoded in both `capital_episodios` (as `medida='nula'`, monto 0) and `cartera_f5_fuentes` (as `es_demo`). Avance demos use `c.es_demo` in `capital_episodios` but are only *exposed*, not filtered, by `cartera_f5_fuentes`.
Impact: F7 becomes the third consumer of a rule kept in sync by hand; parity breaks the first time a new demo appears. Also note F7 must apply `not es_demo` itself when reading `cartera_f5_fuentes`, or demo contracts enter person counts while absent from money.
Recommendation: contract should require F7 to read demo status from one place and to assert, in a test, that the demo row set is identical across both readers.

[P2] `estado` is not comparable across empresas
Evidence: `cartera_f5_fuentes` computes `vigente/vencido/anulado_comercialmente` for coops but passes raw `c.estado` for Avance; `capital_episodios` passes raw `c.estado` for contracts and a two-value `vigente/anulado` for coops.
Impact: an `estado`-based vencimientos filter behaves differently per empresa; an Avance contract past `vence_en` is never labelled `vencido`.
Recommendation: vencimientos must filter on `vence_en` and on empresa-specific liveness rules, not on a uniform `estado`.

[P2] Shadow report is not reproducible; disclose it in the payload
Evidence: `cartera_f5_fuentes` uses `statement_timestamp() at time zone 'America/Lima'` for the `vencido` state. Re-running a sealed month returns different estados.
Recommendation: return `generado_en`, the flag state and the factor used, and keep estado-derived numbers out of the conciliation keys (compare only stock sums, counts and distinct source counts, as the contract already implies).

[P3] `no_contactar` is stated as prose, not enforcement
Recommendation: have the oportunidades output exclude or hard-flag `no_contactar` persons at the SQL level so the rule survives the next consumer.

TEST GAPS:
- Equality test: sum of `medida='stock'` capital per empresa/moneda equals the sum over the identity-joined result — proving the join never fans out or drops rows.
- Partition test: coherente + incoherente + sin-identidad buckets partition the stock row set exactly (catches the NULL `identidad_coherente` gap).
- Determinism test: run `metricas_multiempresa_fn` twice for a sealed month; person distribution and oportunidades must be byte-identical (catches `personas[1]`).
- Boundary test: a coop with `fecha_imputacion` on the 1st at 00:30 Lima and a contract closed on the last day, asserting both land in the intended month under the exact p_ini/p_fin the RPC builds.
- Demo parity test: demo source set from `capital_episodios` equals that from `cartera_f5_fuentes`; the hardcoded UUID contributes zero capital and zero persons.
- Vencimientos test: a renewed contract appears exactly once in the 30-day window (catches the `desglose` triple count); an anulada coop and a demo are absent.
- Cotitular test (only if the reader is extended): a two-holder source counts two persons, one operation, one capital amount.
- Non-write test: assert the RPC performs no writes to `periodos_cerrados`, fotos or ajustes (e.g. run in a transaction and assert no row deltas).
- Authorization test: non-gerencia call rejected; gerencia call with flag OFF rejected on **both** RPCs.

SECURITY RISKS:
- SECURITY DEFINER chain: the new RPC must not expose any parameter reaching `p_global`/`p_visibles`. Grants on the `private.*` helpers and on the new RPCs are not in evidence — verify `revoke ... from anon, authenticated` on privates before install.

REGRESSION RISKS:
- Full-history calls to `capital_episodios` for vencimientos re-evaluate `analista_atribuido_cadena` and the `meta_periodos` subselect per row; measure before install, since the same function serves existing capital/gerencia consumers.
- F7 is read-only, so the main regression surface is shared readers being "fixed" to suit F7. Any change to `cartera_f5_fuentes` should be additive (new column/helper), never a change to `personas[1]` or `identidad_coherente` semantics, which existing F5/F6 consumers may already depend on.

RECOMMENDED NEXT ACTIONS:
1. Decide cotitulares now: drop from F7 scope, or approve one additive extension to `cartera_f5_fuentes` — and in either case separate "multiple holders" from "contradictory identity" in the contract text.
2. Amend the contract with the exact call forms: Lima-midnight p_ini/p_fin, `medida='stock'` for both production and vencimientos, the empresa resolution join, the `p_periodo`/`p_factor` choice, and the three-bucket identity partition including NULL.
3. Add the flag check to `metricas_multiempresa_fn` and freeze its signature at `(p_mes date)` with no scope parameters.
4. Attach the missing evidence before SQL: `private.inversionista_canonica`, `private.analista_atribuido_cadena`, `private.cierre_externo_anulado`, `private.peso_referido_conversion`, the `crm.inversiones` unique constraints, the `contratos.estado` vocabulary, and the current grants.
5. Write the equality/partition/determinism tests as fixtures first; they are the acceptance criteria for the conciliation section.

CONFIDENCE:
MEDIUM — HIGH on the findings derived directly from the three attached bodies; MEDIUM overall because the helper functions, constraints and grants listed in action 4 were not available, so the fan-out and demo-parity items remain hypotheses pending that evidence.
