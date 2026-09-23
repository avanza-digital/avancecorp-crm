# F4 — segunda revisión recuperada, 22/09/2026

Dictamen recibido por wrapper aislado, exit 0. **CHANGES_REQUESTED**, no PASS.
Se agotaron las dos consultas justificadas: la resolución continúa por evidencia del PRIMARY.

Corrección de conteo del paquete enviado: la primera corrida nativa tuvo 231 PASS,
26 SKIPPED y 1 FAIL; la siguiente 232 PASS, 26 SKIPPED y cero fallos. Nunca 257 PASS.
E2E Docker exigido por Main: 232 PASS, 26 SKIPPED, cero fallos (9,0 minutos).

## Dictamen literal

VERDICT:
CHANGES_REQUESTED

SUMMARY:
The rol-puente design, ACLs, CAS and serialization look sound in the evidence provided. Server clock usage is consistent, and "tasa baja" is forced to NULL on both server and client. I found no P0.

There is one concrete frontend defect: a single failed `presentar` call can hide the whole cortes list with no working recovery. I also found release and contract risks that need evidence or a small fix before publication:

- legacy ledger compatibility with SLA-derived groups
- strict client invariants coupling the cortes popup to the secondary context
- SLA recomputation inside the per-supervisor lock
- production role/grant preconditions

I don't credit the gates still running (lint/typecheck/build re-run, full E2E 258, SQL gate scripts) as PASS.

FINDINGS:

[P1] Legacy ledger reconocer/posponer on SLA-derived groups is unverified (evidence needed)
File: `app/src/lib/gestion-diaria-alertas.ts:42-50`, `app/src/lib/alertas-provider.tsx:229,321-341`, migration `20260922184459…avisos.sql:73-77,199-215`
Problem:
- For `tarea_vencida` and `por_repartir`, `alertaDiariaAAlertaCRM` now passes `miembros` = lead ids from `private.gestion_diaria_alertas_sla()`. This comes from `f.value #>> '{lead,id}'` in `20260922204125…:22`.
- Those ids go to the legacy path `reconocerAlertaSupervisor` → `crm.alertas_reconocimientos_sellar()`. Only the part of that trigger before the anchor is visible to me.
- The body of `aplicarReconocimientos` and the legacy branch's member validation are not attached.
Evidence: The comment at `gestion-diaria-alertas.ts:37` says "Solo tareas/reparto conservan el libro previo". Nothing attached shows that the legacy trigger accepts lead ids for `tarea_vencida`, which previously may have used task ids. Nothing shows that pre-existing asientos (legacy member ID space) compare correctly in "empeoró".
Impact (hypothesis, MEDIUM confidence): Either reconocer/posponer from "Otros pendientes" is rejected by the trigger, or every legacy acknowledged group reappears as "worsened" after deploy.
Recommendation: Attach the legacy trigger body after the anchor and `aplicarReconocimientos`. Add one HTTP/Auth test: a supervisor reconoces and pospones `grupo:tarea_vencida:<uid>` with SLA-derived members, and the result is reflected in both list and campana. If the ID space changed, document the one-time reappearance or normalize it.

[P2] A presentation error hides the whole Gestión Diaria cortes/pendientes section, and "Actualizar" does not clear it
File: `app/src/lib/gestion-diaria-avisos-provider.tsx:17,78,95,100,119`, `app/src/components/gestion-diaria/avisos-equipo.tsx:10-13`
Evidence:
- `error = consulta.error ?? errorPresentacion` (line 119). `AvisosEquipo` returns only the error block when `contexto.error` is set, so the cortes list and `<AlertasDelDia/>` are not rendered.
- `errorPresentacion` is cleared only at line 95, after a later successful presentation path.
- If the next tick finds no presentable aviso, `if (!aviso) return` (line 78) exits before that. This happens when the jornada has closed, gerencia paused the channel, or the aviso was resolved elsewhere.
- It also exits early at line 90 if the user is typing.
- `recargar` (line 52) only refetches the query; it never resets `errorPresentacion`.
Impact: One network blip on the POST leaves the supervisor without the cortes list and without "Otros pendientes" for the rest of the session. The "Actualizar avisos" button doesn't recover. The campana also keeps showing "No se pudieron confirmar los avisos…".

This violates "pendientes siguen visibles tras jornada" and list/campana consistency. The GET is healthy, and the campana still shows the cortes.
Recommendation:
- Keep presentation errors separate from `error`, for example as a non-blocking notice.
- Clear the error on every successful GET, in `recargar`, and when the retried aviso is no longer presentable.
- Add a test for: presentar fails → channel paused or jornada closes → list is visible again after Actualizar.

[P2] Strict client-side cross-invariants make the cortes popup fail closed on edge cases in the secondary context
File: `app/src/lib/gestion-diaria-avisos.ts:48-60`, `app/src/lib/gestion-diaria-alertas.ts:8-9,14-17,22-26`
Evidence:
- Any mismatch in `diarias`/`contexto` makes `AvisosCortesSchema` fail. That triggers `contrato()` in `gestion-diaria-seguimiento-api.ts:16`, `datos` becomes null, and there is no popup, no cortes list and no reconocer.
- Mismatch 1: `(e.llamadas > 0) === (e.primera_llamada_en !== null)`. `horarioConfirmado` (`gestion-diaria-equipo.ts:145-149`) documents that `gestion_diaria_llamadas` counts `llamada_realizada` differently for different fields. An analyst whose only calls are `numero_errado`/`no_es_la_persona` may produce `llamadas=0` with a non-null `primera_llamada_en`. This is a hypothesis; the definition of `gestion_diaria_llamadas` is not attached.
- Mismatch 2: SLA buckets are not whitelisted server-side (`20260922204125…:28-35`), while the client picklist is closed (`TipoDiaria`). A new bucket from the núcleo kills cortes.
Impact: A data edge case in the new context disables the already-validated cortes feature.
Recommendation:
- Confirm with a fixture that has only non-useful calls.
- Whitelist buckets in `gestion_diaria_alertas_sla`.
- Consider validating `diarias`/`contexto` independently so that their failure degrades only that section.

[P2] SLA núcleo recomputed inside the per-supervisor advisory lock, twice per action
File: `20260922204125…:72,94-95`, `20260922184459…:171,177,229,243,259-260`
Evidence:
- After the composition, every call to `private.gestion_diaria_avisos` runs `gestion_diaria_contexto` → `sla_operacion_autorizada(null,true)` + `gestion_diaria_llamadas`.
- `reconocer_corte` calls it in the trigger (`sellar`) and again in its return, both while holding `pg_advisory_xact_lock(194204,…)`. `presentar` calls it under the lock too.
- The GET also runs it every 60 s and on every focus, per tab.
- The SLA part also ignores `p_ahora`: it uses the real clock while the cortes part uses the injected clock. This is minor, but the ensayos mix clocks.
Impact:
- Lock hold time and latency scale with the size of the SLA portfolio.
- If `sla_operacion_autorizada` raises, the cortes write paths fail too. Whether it raises in some SLA state is not attached.
- Latency above about 30 s pushes the popup past the 90 s staleness cutoff (`provider:66`).
Recommendation:
- Give the write paths (`sellar`, `presentar`, `reconocer` return) a variant that skips context, or compute the context after the lock.
- Measure p95 with realistic volume before publishing.

[P2] Production preconditions for the rol puente are not demonstrated
File: `20260922184459…:19-22,150-152`
Evidence: `create role`, `grant authenticated to …`, `grant usage on schema … auth …` and `alter function … owner to crm_gestion_diaria_lector` all require postgres to hold CREATEROLE, ADMIN on `authenticated`, and GRANT OPTION on schema `auth`. Only the local bank is reported as PASS. Hosted Supabase restricts `postgres` on `auth` differently from local images (hypothesis).
Impact: The transaction rolls back safely, but the release blocks in production.
Recommendation: Before publishing, run a read-only preflight in production, for example:
- `pg_has_role('postgres','authenticated','USAGE WITH ADMIN OPTION')`
- `has_schema_privilege('postgres','auth','USAGE WITH GRANT OPTION')`
- `rolcreaterole`

Also document that this cluster role must exist in restores and branches.

[P3] Direct RPC can publish hours outside the jornada; only the client enforces them
File: `20260922185138…:79-82` vs `app/src/lib/politica-gestion-diaria.ts:23-26`
Evidence:
- The server only validates the `HH:MM` format.
- The ranges 09:00 < c1 < 13:00, c2 > c1, c2 < 18:00 and bien > atención appear only in valibot.
- The 23514 test covers `piso` only.
- There is no test for a `p_vigente_desde` that is not Lima midnight; the table/trigger checks are not attached.
Recommendation: Confirm the table checks, or add them to `publicar`. Add both variants to `test-seguimiento.sql`.

[P3] Echo checks can reject a publish that succeeded
File: `app/src/data/gestion-diaria-seguimiento-api.ts:74-80,89-91`
Evidence:
- The comparison is strict, `eco.configuracion[campo] !== enviado`. With `step="any"`, a numeric column with limited scale would round the value and fail the check (hypothesis; column types not attached).
- `p.motivo.trim()` (JS, Unicode) and `btrim` (ASCII space only) differ for NBSP or tabs.
Impact: A contract error after a real commit, followed by 40001 on retry.
Recommendation: Send `motivo` already trimmed, and compare numbers with the server's scale.

[P3] A presentation consumed server-side can be lost without being seen
File: `provider:19-24,66-69,115`
Evidence:
- Solicitud UUIDs live only in memory.
- The popup is removed on any refetch error (`datos` null) or when data is more than 90 s stale, for example after the tab was hidden.
- A reload between POST commit and response loses the reservation, and `puede_presentar` stays false afterwards.

This is intended by design ("entregas solo acreditan presentación"), but it means a transient error can erase the only presentation.
Recommendation: Persist the pending reservation in `sessionStorage` keyed by actor/alert/entrega. Retire the popup only on 42501/contract errors, not on transient ones. Or document the trade-off explicitly.

[P3] Minor
- The popup text "Puedes posponer una sola vez…" is shown on the reaviso, where `puede_posponer` is false (`provider:142`).
- `presentarCorte` has no timeout; a hung request blocks `enVuelo` indefinitely (`provider:83`).
- On a `presentar` that returns null because of a race with pause/resume, `procesadas` blocks the aviso for the whole session (`provider:85`).
- On load, supervisors query `resumenSla` until `diarias` arrives and then switch representation (`alertas-provider.tsx:132`), which causes flicker and an extra request.

TEST GAPS:
- Presentation error followed by channel pause or jornada close: the list must be visible again and Actualizar must clear the error.
- HTTP reconocer/posponer of a legacy group (`tarea_vencida`/`por_repartir`) with SLA-derived members, plus the behavior of pre-existing asientos.
- A fixture analyst with only `numero_errado` calls, validating that `ContextoDiarioSchema` passes.
- Missing mutants for the core of the rol puente:
  - `alter function private.gestion_diaria_avisos(timestamptz) owner to postgres`
  - `alter role crm_gestion_diaria_lector bypassrls`
  - `revoke authenticated from crm_gestion_diaria_lector`
  - a change to the body of `alertas_reconocimientos_sellar`
- Direct RPC with out-of-range hours or a `vigente_desde` that is not midnight.
- Latency of `reconocer`/`presentar` with a realistic SLA volume.

ARCHITECTURE RISKS:
- Cortes, SLA and context are coupled in one payload and one contract, so failure in one disables the others.
- The trigger is extended with `replace()` over its source plus hashes. The gates cover it, but every future legacy change requires recalculating the chain of hashes (`20260922204125…:91-101`).

SECURITY RISKS:
- None material. Specifically:
  - Lector has NOBYPASSRLS, cannot log in, and its membership is limited to postgres.
  - The new tables have no API privileges.
  - The `crm.*` wrappers are the only entry points, and none of them accepts a clock.
  - A spoofed direct INSERT is re-sealed by the trigger.
- `NOT IN` against `vendedor_ids_visibles` in `gestion_diaria_contexto:55` relaxes if it ever returns NULL. It is harmless today because the ids come from the server.

REGRESSION RISKS:
- Deploying the frontend before the migrations makes every supervisor see a permanent cortes error. Publish the migrations first, or tolerate a missing RPC.
- Possible one-time reappearance of legacy-acknowledged groups (see P1).

RECOMMENDED NEXT ACTIONS:
1. Fix the `errorPresentacion` stuck state (P2) with its test.
2. Attach the legacy trigger body and `aplicarReconocimientos` and the `gestion_diaria_llamadas` definition, or run the HTTP test for a legacy group and the non-useful-calls fixture (P1/P2).
3. Whitelist SLA buckets server-side, and remove SLA recomputation from the write paths under lock, or measure it.
4. Run a read-only production preflight for the role, ADMIN and GRANT OPTION preconditions, then close the gates still in progress (lint/typecheck/build, E2E 258, SQL scripts) before publishing.

CONFIDENCE:
MEDIUM

## Evaluación y correcciones del PRIMARY

- Aceptado error de presentación: ahora aviso no bloqueante, lista conservada y
  Actualizar lo limpia. Prueba de fallo seguido de pausa del canal PASS.
- Precondición hosted confirmada: postgres tiene CREATEROLE y ADMIN authenticated,
  pero no GRANT OPTION de USAGE en auth. Auth/uid se heredan de authenticated;
  se eliminó el GRANT redundante antes de versionar el candidato. Herencia
  probada revocando temporalmente el permiso directo en el banco, con ROLLBACK.
- Legado usa ids de lead, no de tarea: `alertas.ts` grupo de tareas (miembros),
  `reconocimientos-alertas.ts` compara conjuntos y severidad; el trigger legacy
  valida formato e identidad. No cambia el espacio de ids. Prueba HTTP/Auth y
  navegador con dos supervisores y sesiones nuevas PASS: reconocer/posponer,
  lista y campana. Evidencia `gd-f4-legado-http.json` del banco.
- Solo llamadas no útiles: el núcleo `gestion_diaria_llamadas` cuenta TODOS los
  ids en llamadas y primera/última, excluye no útiles solo en útiles/contestadas.
  La hipótesis de cero llamadas con primera llamada no nula no corresponde al SQL.
  Fixture de dos llamadas por RPC (`numero_errado` y `no_es_la_persona`) PASS:
  llamadas 2, útiles/contestadas 0, primera/última no nulas.
- Límites horarios, orden de umbrales y medianoche Lima ya están en los CHECK
  de `politica_gestion_diaria` de etapa 3. `numeric` no tiene escala declarada.
  Pruebas RPC directas de horas inválidas y vigencia fuera de medianoche PASS:
  23514, sin nueva versión. No se duplicaron validaciones SQL.
- Aceptado normalizar `motivo.trim()` ANTES de enviar, evitando diferencia con btrim.
- Aceptado timeout de 30 s al reclamar presentación y texto de reaviso correcto.
- Medición READ ONLY de SLA en tres equipos productivos (2.148 leads activos
  globales): 2.430,047 / 25,743 / 2.224,554 ms. No es p95. Se acepta separar
  contexto/SLA del núcleo que usan las escrituras bajo lock: cuarto candidato
  instalado localmente. Inyección de fallo SLA: presentar/reconocer PASS y GET
  completo falla, como se esperaba. Las tres muestras no acreditan p95 de carga.
- Nuevos mutantes: owner del lector, membresía authenticated y cuerpo del sello.
  Añadido BYPASSRLS: 25 mutantes PASS. Gate completo posterior: 4.153 tests PASS,
  además de lint, typecheck, build, cobertura y E2E Docker.
- Categorías SLA actuales son seis; gates sellan el núcleo. No se adopta un
  filtro que descarte silenciosamente una categoría futura. Cambiar ese contrato
  requiere actualizar su consumidor y probarlo; error explícito conserva fail-closed.
- Reserva perdida tras cerrar/recargar pestaña: entrega significa intento único
  confirmado por servidor, no garantía de visualización humana. La lista sigue
  disponible; no se promete exactly-once visual en un navegador que se cerró.
