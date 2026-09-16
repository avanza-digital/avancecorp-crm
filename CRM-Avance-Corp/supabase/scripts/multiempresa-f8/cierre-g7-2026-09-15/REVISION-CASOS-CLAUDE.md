VERDICT:
CHANGES_REQUESTED

SUMMARY:
The isolation design is sound and I found no path from these scripts to production: `db`, `contenedor`, `apiUrl` are module constants with no env/argv override (`banco-http.mjs:10-11`), both SQL entry points guard on `current_database()` before any write (`roles-general-local.sql:4-6`, `dependencias-local.sql:4`), ports are bound to `127.0.0.1` only (`banco-http.mjs:118`), the production handler's fetch is pinned to the local origin (`banco-http.mjs:58`), and teardown only removes label-verified containers it created (`banco-http.mjs:173-178`). No P0.

The weaknesses are in the **evidence chain and the oracles**, not in safety. Three things stand out: (a) the "matches production" claim ultimately rests on `versiones-casos.json`, whose provenance is not in the attached evidence and which is not hash-bound in `cotejo-casos.json`; (b) several receipt fields that read as measurements are hardcoded literals, and `verificar-evidencia.mjs` asserts on one of them; (c) the newly-exercised, service_role-privileged surface (`crm-inversion-portal` saga recovery) has no negative authorization test. I agree with your framing: these are synthetic trials, not human signoff and not full-schema parity — and the receipts correctly say so.

FINDINGS:

---

**[P1] Saga-recovery surface runs with service_role and has no negative authorization test**

File:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/casos-http.mjs`

Lines:
35-40, 84-101, 110; `banco-http.mjs:56-58`

Problem:
`handlerEnBanco` injects `serviceKey` into `crearHandlerAccesoInversion`, so the handler's own authorization check is the only barrier. Every call in `handlerLlamar` hardcodes `Authorization: 'Bearer '+tokens.supervisor`. There is no case where an anon caller, a `cliente` token, `tokens.ajeno`, or a caller resuming **someone else's** `solicitud_id` is rejected.

Evidence:
`casos-http.mjs:37` — the Authorization header is a constant. `casos-http.mjs:95` extracts a 48-hex resume token from the 503 body and `:100` replays it with the same supervisor identity. No `rechazo(...)` / `assert.equal(status,401|403)` exists anywhere for this handler.

Impact:
The four new recovery paths (`auth`, `registrar_auth`, `crear_perfil`, `enlazar`) are validated only on the happy path. A regression that lets a different analyst resume a pending saga — creating an Auth user, a profile and a contract attributed to someone else's scope — would still produce a 15/15 PASS receipt. This is the highest-value gap given F9 opens the surface to 18 analysts.

Recommendation:
Add, per corte: (1) `handlerLlamar` with `tokens.ajeno` and with no token → expect rejection, counters unchanged; (2) resume with a token from a *different* solicitud → rejection; (3) resume with a syntactically valid but forged 48-hex token → rejection. Assert `contadores()` is unchanged in each.

---

**[P1] The "203 definitions match production" claim rests on an artifact with no attached provenance and no hash binding**

File:
`banco-http.mjs` (`--inventario`), `cotejo-casos.json`, `dependencias-local.sql`

Lines:
`banco-http.mjs:182-193`; `cotejo-casos.json:1-7`; `verificar-evidencia.mjs:106`; `dependencias-local.sql:6-141`

Problem:
`--inventario` asserts the bank equals `versiones-casos.json`, and `dependencias-local.sql` was applied to the bank *specifically to make that comparison pass* ("Se alinearon dependencias de tasas y el límite de plantilla PDF v9", `CASOS-COMPLEMENTARIOS.md:39-40`). So the whole chain reduces to: *is `versiones-casos.json` a faithful, dated, read-only capture of production?* Nothing in the attached evidence shows how it was produced, from which corte, or under which read-only receipt. And `cotejo-casos.json` records only a **count** (`funciones: 203`), not a hash of the inventory it compared against.

Evidence:
`verificar-evidencia.mjs:106` — `assert.equal(ampliadas.length,203); assert.equal(cotejo.funciones,203);` — count only. Contrast with the pattern this repo already uses one line earlier at `:73`: `assert.equal(economico.huella_funciones, createHash('sha256').update(JSON.stringify(funciones)).digest('hex'))` for `versiones-nucleo.json`. The stronger pattern exists and was not applied to the new artifact.

Impact:
`versiones-casos.json` could be edited to match a drifted bank and only its length would be checked at verification time. The claim "coinciden con el inventario productivo" is therefore not independently verifiable from this evidence set.

Recommendation:
Write `huella: sha256(JSON.stringify(inventario))` into `cotejo-casos.json` and assert it in `verificar-evidencia.mjs`, mirroring `:73`. Separately, attach (or point to) the read-only capture receipt for `versiones-casos.json` with its corte timestamp, the same way `conciliacion.json`/`refresco-final.json` carry `corte`.

---

**[P2] `--inventario` leaves a stale PASS receipt on failure**

File:
`banco-http.mjs`

Lines:
189-193

Problem:
`assert.deepEqual` runs *before* `writeFileSync`. On drift, the assertion throws and `cotejo-casos.json` is never rewritten — the previous run's `{"estado":"PASS"}` stays on disk.

Evidence:
`banco-http.mjs:189-190` (assert then write). Compare `casos-http.mjs:11` and `casos-finanzas.mjs:8`, which both write `{estado:'RUNNING'}` first and always rewrite in `finally`. `--inventario` is the only one of the three without that guard.

Impact:
A failed drift check is invisible to `verificar-evidencia.mjs:101`, which reads the stale PASS. There is no freshness check (`cotejo-casos.json.fecha` is never compared to anything).

Recommendation:
Apply the same RUNNING/finally pattern to `--inventario`, and have `verificar-evidencia.mjs` assert `cotejo.fecha` is not older than the other receipts.

---

**[P2] Receipt fields that read as measurements are hardcoded literals, and the verifier asserts on one of them**

File:
`casos-finanzas.mjs`, `casos-http.mjs`, `verificar-evidencia.mjs`

Lines:
`casos-finanzas.mjs:90`; `casos-http.mjs:157`; `verificar-evidencia.mjs:105`

Problem:
`casos-finanzas.mjs:89-90` builds `jsonb_build_object(...,'fotografias',filas,'ajustes_nuevos',1)` — `filas` is measured, `1` is a literal. `verificar-evidencia.mjs:105` then asserts `r.ajustes_nuevos===1`, i.e. it asserts a constant. The real check is `casos-finanzas.mjs:84`, inside the DO block.

The same pattern appears in `casos-http.mjs:157`: `bien('Fichas por tres roles...', {monedas_separadas:true})`. Nothing in `ficha()` verifies currency separation in the sense the label implies — `ficha()` compares per-source `moneda` against `private.cartera_f5_fuentes_reales()` (`:120-127`) and `inversiones_total` is a **count** (`:124`). No assertion exists that PEN and USD amounts are never summed into a shared total. `fixture_explicito:true` (`:190`) is likewise a label, not an outcome.

Impact:
`CASOS-COMPLEMENTARIOS.md:14` ("Las fichas conservan empresa, moneda e importe") is partly backed; the stronger reading — no cross-currency aggregation — is not tested at all, yet the receipt carries a boolean that suggests it is. A reader of `casos-http.json` cannot distinguish measured from declared fields.

Recommendation:
Separate measured values from labels in the receipts (e.g. a `medido` vs `etiquetas` object), remove the vacuous `ajustes_nuevos===1` assertion in favour of re-reading the count outside the DO block, and add a real currency assertion: with the person holding PEN and USD Avance sources, assert the ficha's totals are grouped per currency and that no field equals the naive PEN+USD sum.

Related, lower severity: `verificar-evidencia.mjs:102` `http.resultados.every(r=>r.estado==='PASS')` is tautological — `bien()` only ever pushes `PASS` (`casos-http.mjs:15`); failures throw and never reach the array. The load-bearing assertion is `resultados.length===15`, which is present — but the `every()` reads as stronger evidence than it is.

---

**[P2] The identity-verification block is asserted on a free-text message instead of a SQLSTATE**

File:
`casos-http.mjs`

Lines:
185-188

Problem:
`assert.match(bloqueo.data.message,/verificad|identidad|documento/i)` — this is the one control proving that an unverified identity cannot open an investment, and it matches on substrings that any number of unrelated validations could contain (a duplicate-`documento` error, for instance, matches `/documento/i`).

Evidence:
Every other rejection in this file uses the code path: `rechazo()` at `:17` asserts `r.data.code`, used at `:152` (`'22023'`), `:164` (`'P0409'`), `:166` (`'42501'`). Line 186 is the only message-based assertion.

Impact:
If a different validation starts firing first (e.g. an ordering change in `preparar_inversion_fn`), the test still passes and `CASOS-COMPLEMENTARIOS.md:18` still claims the identity control is proven.

Recommendation:
Assert the specific SQLSTATE via `rechazo()`, keeping the message match only as a secondary check.

---

**[P2] `casos-finanzas.mjs`: non-STRICT `ajeno` selection creates a NULL-vs-NULL false-pass in the reassignment oracle**

File:
`casos-finanzas.mjs`

Lines:
31, 70-72

Problem:
`select perfil_id into ajeno from crm.equipo where rol_crm='vendedor' and activo and perfil_id<>v;` has no `STRICT`. If no second active vendor exists, `ajeno` is NULL. Line 70 then calls `reasignar_analista_contrato(cabeza, NULL, ...)`, and line 72 checks `if relacion is distinct from ajeno` — with both sides NULL this is **false**, so no exception is raised and the case is recorded as PASS.

Evidence:
`:29` uses `into strict g` for gerencia; `:57/:59/:61` use `into strict valor`. Only `:30` (`v`) and `:31` (`ajeno`) omit it — the two whose NULL values silently weaken the oracle.

Impact:
"Reasignar cabeza upgrade mueve atribución viva de su renovación" (`casos-finanzas.json:12`) can report PASS while nothing was actually reassigned. The current copy has two vendors so the run is real, but the oracle is not robust to a fixture change.

Recommendation:
Use `into strict` for both `v` and `ajeno`, and add an explicit pre-assertion `if ajeno is null or ajeno = v then raise exception ...`.

---

**[P2] `rollback_completo:true` is computed from a fingerprint that omits the most sensitive mutated tables**

File:
`casos-finanzas.mjs`

Lines:
12-17, 32, 95-99

Problem:
`huella()` covers `public.contratos`, `crm.inversionistas`, `crm.cierres_externos`, `crm.periodos_cerrados`, `crm.cierre_mes_vendedor`, `auth.users`. The transaction also mutates `crm.multiempresa_flags` (`:32`), `public.perfiles` (`:34`), `crm.inversiones`, `crm.inversion_solicitudes`, `crm.inversion_ajustes_mes_cerrado` and `storage.objects` (`:80`) — none of which are in the fingerprint.

Evidence:
`:32` `update crm.multiempresa_flags set activo=(nombre in(...))` vs `:12-17` (fingerprint table list) vs `:99` `rollback_completo:sinCambios`.

Impact:
The single-transaction structure makes an actual leak unlikely, but the *evidence claim* "todo se revierte" (`:1`, `casos-finanzas.json:27`) is supported only over the covered surface. Flags are precisely the object whose leakage would be most consequential, and they are the one thing the check does not look at.

Recommendation:
Extend `huella()` to include `crm.multiempresa_flags`, `public.perfiles`, `crm.inversiones` and `crm.inversion_ajustes_mes_cerrado`, or narrow the receipt wording to the tables actually fingerprinted.

---

**[P2] Directorio scope is proven on a single sampled row per context**

File:
`roles-general-local.sql`

Lines:
66-75

Problem:
The Directorio check picks `lista#>>'{filas,0,inversionista_id}'` — the **first** row only — and asserts that one ficha contains no non-`avance` empresa and no write capability. It never asserts that `crm.cartera_inversionistas_fn()` itself excludes non-Avance sources for a Directorio.

Evidence:
`:70` takes index 0. `verificar-evidencia.mjs:81` asserts exactly 2 contexts reached this branch. So the claim "Directorio conserva únicamente su lectura Avance" (`CASOS-COMPLEMENTARIOS.md:22`, `APERTURA.md:62`) rests on 2 sampled fichas.

Impact:
A leak affecting rows 2..n of the cartera, or the list payload rather than the ficha, passes undetected.

Recommendation:
Assert directly over the list — `not exists (select 1 from jsonb_array_elements(lista->'filas') f where f->>'empresa' is distinct from 'avance')` — and sample at least first/middle/last fichas, or iterate all of them under the existing `statement_timeout`.

---

**[P2] The ephemeral Auth container inherits the f5 bank's full environment; only three keys are overridden**

File:
`banco-http.mjs`

Lines:
103-115

Problem:
`vars` is built from the source container's entire `Config.Env` and passed through wholesale to `docker run -e`. For `auth`, only `GOTRUE_DB_DATABASE_URL`, `API_EXTERNAL_URL` and `GOTRUE_SITE_URL` are overridden. Any inherited `GOTRUE_SMTP_*`, `GOTRUE_WEBHOOK_URL`, `GOTRUE_MAILER_AUTOCONFIRM=false` or external OAuth secrets are carried into a harness that then creates Auth users (`casos-http.mjs` via `crearHandlerAccesoInversion`) and force-sets passwords (`banco-http.mjs:158`).

Evidence:
`:103` `Object.fromEntries(origen.Config.Env.map(...))`, `:109` overrides only two auth keys, `:120` `for(const [key,value] of Object.entries(vars))args.push('-e',key+'='+value)`.

Impact:
Hypothesis, medium confidence — I cannot read the f5 bank's env from here. If SMTP or webhooks are configured, a test run could produce outbound side effects. Addresses are `@pruebas.example` / `@g7.example.invalid` (reserved TLDs, so delivery would fail), which limits blast radius, but "no external side effects" is currently an assumption rather than a property of the script.

Recommendation:
Whitelist the env keys you need instead of copying all of them, or explicitly force `GOTRUE_MAILER_AUTOCONFIRM=true`, blank `GOTRUE_SMTP_HOST`, and unset `GOTRUE_WEBHOOK_URL` / external provider secrets. Record the effective override list in the receipt.

---

**[P2] Receipts are not bound to the harness that produced them**

File:
`casos-http.mjs`, `casos-finanzas.mjs`, `verificar-evidencia.mjs`

Lines:
`casos-http.mjs:207`, `casos-finanzas.mjs:100`, `verificar-evidencia.mjs:107-108`

Problem:
Both receipts self-hash only their own file (`import.meta.url`). `verificar-evidencia.mjs:107-108` therefore proves the receipt came from the current `casos-http.mjs` / `casos-finanzas.mjs`, but nothing binds `casos-http.json` to the `banco-http.mjs` that provided every isolation guarantee, nor `roles-general-local.json` to `roles-general-local.sql`, nor either to `dependencias-local.sql`.

Evidence:
`verificacion.json:40-50` lists hashes for `banco-http.mjs`, `roles-general-local.sql` and `dependencias-local.sql`, but those hashes are *outputs* of the verifier, not cross-checked inputs to any receipt.

Impact:
`banco-http.mjs` could change (ports, label check, origin pin, owner rewrite, flag handling) without invalidating an existing `casos-http.json` PASS.

Recommendation:
Have `casos-http.mjs` hash `banco-http.mjs` and `dependencias-local.sql` into its receipt; have the roles matrix emit the hash of the `.sql` that produced it; assert all of them in `verificar-evidencia.mjs`.

---

**[P2] Table-level alignments in `dependencias-local.sql` have no comparison oracle, and one is strictly permissive**

File:
`dependencias-local.sql`

Lines:
5, 134-140

Problem:
`--inventario` compares `pg_proc` only (`banco-http.mjs:182-186`). The table DDL at `:134-140` — dropping/recreating the PDF template CHECK, `alter column cliente_id drop not null`, and three `add column if not exists` — is applied to the copy with nothing verifying it matches production. `set local check_function_bodies=off` (`:5`) additionally allows bodies referencing objects that may not exist.

Evidence:
`:136` `alter table crm.solicitudes_tasa alter column cliente_id drop not null;` — this makes the copy *more permissive* than production would be if the constraint is still enforced there.

Impact:
A test that should fail on a NOT NULL violation can pass in the bank. `CASOS-COMPLEMENTARIOS.md:41` correctly disclaims full-schema parity, but these specific alterations are the ones the new cases exercise.

Recommendation:
Extend the inventory to the touched tables — md5 over `pg_attribute` (name/type/notnull/default) and `pg_constraint` (`conname`, `pg_get_constraintdef`) for `crm.solicitudes_tasa`, `crm.conversion_reservas`, `private.contrato_pdf_jobs` — and compare against a captured production baseline, the same way functions are handled.

---

**[P2] Portal alta derives the initial credential from the document number**

File:
`casos-http.mjs`

Lines:
104

Problem:
`http('/auth/v1/token?grant_type=password',{body:{email:datos.alta_portal.correo,password:p.documento}})` succeeds, i.e. the handler creates the portal account with the DNI as its password, and the test codifies that as expected behaviour without comment.

Evidence:
`:42-44` generates `documento` as an 8-digit number; `:78-79` passes `alta_portal` with the real email; `:104` logs in with `p.documento` and `:105` asserts the session belongs to that profile.

Impact:
In production the email is the client's real address and the DNI is semi-public, so the initial portal credential is guessable by anyone holding both. I cannot tell from this evidence whether the product forces rotation on first login — the handler source was not attached, so treat this as an observation, not a proven defect. It is pre-existing product behaviour, outside this task's diff, but F9 widens its exposure.

Recommendation:
Before the F9 opening, confirm whether first-login rotation is enforced. If it is, assert it here (a second login after rotation, or a `must_change_password`-style flag). If it is not, record it as an accepted risk in `APERTURA.md:58-75` rather than leaving it implicit in a test.

---

**[P3] Lower-severity items (grouped)**

- `banco-http.mjs:91` — `assert.equal(sql('select current_database()'),db)` is tautological: `sql()` always passes `-d db`. It reads as a safety guard but can never fail. The real guards are elsewhere and are fine; this one should be dropped or replaced with a check on the container/network identity.
- `casos-http.mjs:26-28` — `capital()` aggregates the row **with** `estado`/`anulado` stripped but orders by `to_jsonb(c)::text` computed on the **full** row. Since `anular_cierre_externo` changes exactly those two fields, the sort key changes across the comparison at `:179`; with more than one episode this can reorder the array and produce a spurious FAIL. Order by a stable key (`medida`, `tipo`, `id`).
- `banco-http.mjs:88, 75-79` — `alter role authenticator in database ... set pgrst.db_schemas` and the ownership rewrites persist in the shared `supabase_db_avancecorp-f5-bank` cluster after `cerrar()`. Scoped to the copy DB, so low risk, but not reverted and not recorded in the receipt.
- `banco-http.mjs:117` — the ephemeral containers join the existing `avancecorp-f5-bank-red` network, so they can reach the original f5 bank services. A dedicated network would make the isolation claim structural rather than configurational.
- `banco-http.mjs:167` — the failure log dump redacts `secreto` and `postgres://` URLs but not the minted `ANON_KEY`/`SERVICE_ROLE_KEY` JWTs, which GoTrue/PostgREST may echo. Locally-minted and 24h-lived, so impact is small, but it contradicts the file header's "sin imprimirlos".
- `casos-finanzas.mjs:85-88` — after the idempotency replay, only the seal hash is re-checked. Nothing re-asserts that `crm.inversion_ajustes_mes_cerrado` still has exactly 1 row or that `crm.inversiones` did not gain one. The case title says "…y reintentar"; that half is under-verified.
- `verificacion.json:6-7 / 15-19` — top-level `fuentes:613, identidades:467` are from the original corte while the headline result is `refresco_final` 614/468. `verificar-evidencia.mjs:15-26` validates both but never asserts the delta is bounded or monotonic. A reader scanning the top of the file gets the stale number.
- `casos-http.mjs:204-205` — flags are restored before `cerrar()`; if the restore throws, containers leak and the receipt stays `RUNNING` (which fails verification, so the direction is safe). Wrap the restore so teardown always runs.
- `casos-http.mjs:139` — `update public.perfiles set telefono='999111222'` is never reverted, unlike the flags. Consistent with "la copia conserva datos sintéticos", but it is an unrecorded fixture mutation.

---

TEST GAPS:

- **Negative authorization on `crm-inversion-portal`** (see P1): no anon / `cliente` / `ajeno` caller, no cross-solicitud or forged resume token.
- **Concurrency on the new recovery path**: `verificar-evidencia.mjs:75-77` shows 5 races exist in `ensayo-local.json`, but none of them cover the four cortes introduced here. Two simultaneous resumes of the same 503 token is exactly where a duplicate Auth user or duplicate inversión would appear; `auth_unico`/`inversion_unica` in the receipt are proven only under sequential replay (`casos-http.mjs:110`).
- **Storage RLS negatives**: `casos-http.mjs:65-66` uploads a comprobante as supervisor (happy path only). No test that `tokens.ajeno` cannot upload to, overwrite, or read `persona/<id>/comprobante.png`.
- **Cross-currency aggregation**: no assertion that PEN and USD are not summed (see P2 above).
- **Cartera-level Directorio scope**, not just one sampled ficha (see P2).
- **Retry after replay in the sealed-month case** (see P3).
- **Solicitud lifecycle**: no test of confirming with a stale `p_revision_datos_esperada` (all calls use `0`, `casos-http.mjs:19`) — the optimistic-concurrency parameter is never exercised in its conflicting state.

ARCHITECTURE RISKS:

- **The bank is cumulative and never reset.** `casos-http.mjs` persists its data; only `casos-finanzas.mjs` and `roles-general-local.sql` roll back. Combined with `CASOS-COMPLEMENTARIOS.md:60-61` ("Las corridas intermedias quedaron FAIL"), the 46 contexts in the roles matrix include residue from failed, non-reproducible runs. Arithmetic supporting this, offered as a hypothesis since I cannot read `roles-general-local.json`: the SQL comment at `:104` puts the base at 15 accounts, plus 6 synthetic contexts = 21; `casos-http.mjs` creates a profile only in `avanceNuevo`, invoked 5 times per clean run (4 cortes + `p3`), which does not reach 46. The matrix's *conclusion* ("all clients stay outside CRM management") remains valid regardless — but `contextos_roles: 46` in `verificacion.json:23` and "46 contextos" in `CASOS-COMPLEMENTARIOS.md:22` are not reproducible figures and should not be cited as a test-size metric.
- **The reproduction sequence is incomplete.** `CASOS-COMPLEMENTARIOS.md:80-89` lists three `node` commands and then describes `roles-general-local.sql` in prose without its exact invocation, and does not state that it must run *after* `casos-http.mjs` (otherwise the `>=21` / `count(*) from public.perfiles` check at `roles-general-local.sql:105-107` yields a different number). `dependencias-local.sql` is not listed at all, despite being a prerequisite for `--inventario` to pass.
- **Oracle self-reference in `ficha()`**: `casos-http.mjs:120-127` validates `inversionista_ficha_fn` against `private.cartera_f5_fuentes_reales()`. Both are product code; a shared defect in the underlying source resolution is invisible to this comparison. Acceptable for a consistency check, but it should not be described as independent verification of the ficha's contents.

SECURITY RISKS:

- Service_role-privileged handler with untested authorization boundaries (P1).
- Unfiltered env inheritance into the ephemeral Auth container — possible outbound mail/webhook side effects from a test harness (P2).
- Portal initial credential derived from the document number (P2, observation).
- Identity-verification control asserted by message regex rather than error code (P2).
- No Storage cross-tenant negative test (test gap).
- Positive: the `authenticated`-role discipline is correct throughout — `roles-general-local.sql:63/80` and `casos-finanzas.mjs:40/42,47/49,64,70,79,81,85` consistently `set local role authenticated` around product calls and `reset role` after, so RLS is genuinely exercised rather than bypassed by `supabase_admin`. `roles-general-local.sql:3` also sets `search_path=''`. That is the right pattern and it is applied consistently.

REGRESSION RISKS:

- No product code changed in this task, so there is no runtime regression surface. The regression risk is **in the evidence**: a stale `cotejo-casos.json` (P2), receipts unbound to `banco-http.mjs` (P2), and count-only verification of `versiones-casos.json` (P1) mean a future drift in the bank or harness can go undetected while `verificacion.json` still reports PASS.
- `dependencias-local.sql:136` makes the copy permissive relative to a possible production NOT NULL, so a future test against this bank could pass where production would reject.

RECOMMENDED NEXT ACTIONS:

1. Close the two P1s before this evidence is used to argue G7 readiness: add negative-authorization cases for `crm-inversion-portal` (unauthorized caller, cross-solicitud token, forged token), and hash-bind `versiones-casos.json` into `cotejo-casos.json` (mirroring the existing `verificar-evidencia.mjs:73` pattern) plus attach the read-only capture receipt that produced it.
2. Fix the evidence-integrity P2s, all small: RUNNING/finally in `--inventario`; `into strict` for `v`/`ajeno` in `casos-finanzas.mjs:30-31`; SQLSTATE instead of regex at `casos-http.mjs:186`; widen `huella()` to cover `multiempresa_flags`/`perfiles`/`inversiones`; bind `banco-http.mjs` + `dependencias-local.sql` hashes into the receipts.
3. Separate measured values from labels in the receipts and drop the vacuous `ajustes_nuevos===1` assertion at `verificar-evidencia.mjs:105`; add a real cross-currency assertion so `monedas_separadas` is earned rather than declared.
4. Complete `CASOS-COMPLEMENTARIOS.md:76-89`: full ordered command list including `dependencias-local.sql` and the exact `roles-general-local.sql` invocation, an explicit statement that the bank accumulates state and is not reset, and a note that `contextos_roles: 46` is descriptive rather than reproducible.
5. Whitelist (rather than copy) the Auth container env, or explicitly neuter SMTP/webhook/autoconfirm, and record the effective overrides in the receipt.
6. Before the F9 opening, resolve the portal-password question (forced rotation or accepted risk in `APERTURA.md`), and keep the remaining blockers you already list at `CASOS-COMPLEMENTARIOS.md:72-74` unchanged — none of the work reviewed here moves them.

On your framing: I agree and would state it explicitly in the final deliverable — these are synthetic trials on an isolated copy, they are not human signoff, not full-schema parity, and not authorization to activate. `verificacion.json:3` ("G7 permanece ABIERTO") and the `limites` arrays in both receipts say this correctly and should be preserved verbatim.

Items I could **not** verify from the attached evidence, listed so you can decide whether to supply them: `versiones-casos.json`, `roles-general-local.json`, `conciliacion.json`, `postflight.json`, `refresco-final.json`, `ensayo-local.json`, `transicion-local.json`, `versiones-nucleo.json`, `complemento.json`, `fichas.json`, `roles.json`, `casos.json`, `guardias.json`, and the handler source `_supabase_functions/functions/crm-inversion-portal/handler.mjs`. I reviewed `verificar-evidencia.mjs` as the contract over those files and my assessment of them is limited to what that script asserts; the handler gap is why the portal-password finding is marked as an observation.

CONFIDENCE:
MEDIUM-HIGH — HIGH for the isolation assessment and for every finding anchored to a line in the attached scripts; MEDIUM for the env-inheritance risk and the 46-contexts arithmetic, which are hypotheses I flagged as such; LOW for anything depending on the thirteen unattached artifacts and the handler source.
