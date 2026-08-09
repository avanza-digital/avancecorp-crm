# Ledger de migraciones — esquema `crm`

Proyecto: `dctqcbznekcyxhjujuci` (el MISMO del portal — ver condiciones §5 del plan).
Ciclo obligatorio: **branch de Supabase → aplicar → `scripts/test-rls.mjs` → advisors → merge**.
Prohibido `apply_migration` directo a producción. Ninguna migración del CRM altera objetos
de `public` sin OK explícito de Miguel.

**Registro de excepciones a `public`** (corregido el 2026-08-09: esta lista decía «única
excepción documentada: 20260711000001» cuando ya eran siete. El registro había dejado de
funcionar como control — mantenerlo al día es parte de la regla, no un extra):

| Versión | Qué toca de `public` | OK de Miguel |
|---------|----------------------|--------------|
| 20260711000001 | `perfiles_rol_check` acepta `'comercial'` | sí, 2026-07-11 |
| 20260714000001 | `perfiles.tipo_documento` | sí, 2026-07-14 |
| 20260728044338 | trigger sobre `public.perfiles` | sí, 2026-07-27 |
| 20260801092924 | `public.contrato_tiene_pagos` | sí, 2026-08-01 |
| 20260807123000 | funciones `public.*` de gerencia operativa | sí, 2026-08-07 |
| 20260807235933 | `public.crear_contrato`, `public.actualizar_contrato`, wrappers catalogados, `public.contratos.producto_condicion_id` | sí, 2026-08-07 |
| 20260809003923 | `public.actualizar_contrato`, `public.actualizar_numero_contrato` (gate P04) | sí, 2026-08-09 |

## Prehistoria: squash del historial del portal (2026-07-11)

El historial del portal (63 migraciones) empezaba en fixes de abril: el esquema base se creó
por dashboard y nunca fue migración → **ningún branch podía replicarse** (la #1 fallaba sobre
una BD vacía). Con OK de Miguel se hizo **squash**: las 63 filas de
`supabase_migrations.schema_migrations` se reemplazaron por una sola baseline
(`20260708000000_baseline_squash_portal` = dump schema-only de `public` con pg_dump 18.4 +
extras: buckets/policies de storage, publicación realtime, secreto Vault, cron job).
- Respaldo íntegro de las 63 filas: `_DEV_NO_SUBIR/respaldo-schema-migrations-2026-07-11.json`.
- El baseline NO se re-ejecuta en prod (solo replica branches); validado con BEGIN…ROLLBACK
  sobre un branch vacío y luego con rebase real: réplica idéntica (11 contadores de catálogo).
- El esquema real de prod NO se tocó: solo la tabla de bookkeeping.

## Migraciones del ciclo F0

| # | Version | Nombre | Qué hace | Estado |
|---|---------|--------|----------|--------|
| 1 | 20260709000001 | cimientos_crm | Esquemas `crm`+`private`; `crm.equipo` (jerarquía 3 roles + directorio externo); helpers `private.*` (CTE recursivo, lector global); `crm.leads` (dedup vivo tel/DNI, FKs a perfiles/contratos); `crm.actividades` (log inmutable); triggers (inmutabilidad, conversión gated por `crm.op_privilegiada`, normalizar teléfono, timeline, bloquear reasignación, auditoría→audit_log); RLS deny-by-default sin DELETE; vista `crm.clientes_basicos`; `crm.existe_cliente_por_dni` gated; grants+hardening. 11 fixes de revisión adversarial (2026-07-09) | ✅ aplicada en branch `crm-f0` · gate 128/128 · **pendiente de merge** |
| 2 | 20260711000001 | portal_rol_comercial | **[PORTAL — excepción con OK de Miguel]** extiende `perfiles_rol_check` con `'comercial'`: rol de portal NEUTRO (deny-by-default, solo su propia fila) para la fuerza de ventas del CRM. Motivo: el gate demostró que enrolar CRM como 'analista' hereda las policies del portal y filtra columnas bancarias de clientes asignados | ✅ aplicada en branch · **pendiente de merge** |
| 3 | 20260711000002 | fix_clientes_basicos_gate_propio | La vista `security_invoker` quedaba VACÍA para rol comercial (hallazgo del gate). Se pasa a vista de owner con gate interno de staff CRM/lector global | ✅ aplicada en branch (superada en parte por la #4) · **pendiente de merge** |
| 4 | 20260711000003 | hardening_advisors_f0 | Cierra los 3 hallazgos nuevos de advisors: `clientes_basicos` pasa a **función definer gateada (`crm.clientes_basicos_fn`) + vista invoker** (mata el ERROR `security_definer_view`, mismo patrón aceptado que `existe_cliente_por_dni`); `search_path` fijo en `private.normalizar_telefono`; índices FK `creado_por` en las 3 tablas crm | ✅ aplicada en branch · gate re-verificado 128/128 · **pendiente de merge** |
| 5 | 20260711000004 | scope_clientes_y_equipo_desactivado | Cierra 2 hallazgos del **panel adversarial** (2026-07-11): (a) `clientes_basicos_fn` se **scopea por cartera** (gerencia/lector global ven todos; supervisor/vendedor solo clientes cuyo `asesor_perfil_id` ∈ su subárbol) — la 000003 lo había dejado global, exponiendo PII de los 139 clientes a cualquier vendedor; (b) `equipo_select` exige `activo=true` en la rama self → un miembro desactivado ya no lee su propia fila | ✅ aplicada en branch · gate 130/130 · **pendiente de merge** |
| 6 | 20260714000001 | perfiles_tipo_documento | **[PORTAL — excepción con OK de Miguel, 2ª]** agrega `perfiles.tipo_documento` (`text NOT NULL DEFAULT 'DNI'` + CHECK de dominio `DNI/CE/PASAPORTE`) y backfill 9–12 dígitos→CE. SIN CHECK de formato (diferido: los writers viejos lo violarían durante la ventana de deploy). Aplicada DIRECTO a prod por el carril del portal (QA tx revertida + advisors sin hallazgos nuevos), no por el gate del CRM: no toca RLS ni objetos `crm` | ✅ **aplicada en PROD 2026-07-14** (166 DNI + 7 CE) |

## Distribución de leads por capital (2026-07-17)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260717163959 | crm_origenes_landing_formulario | Amplía el dominio persistente con `landing` y `formulario`, conserva `web`/`campania`/`whatsapp` únicamente para lectura histórica y mantiene los cinco orígenes activos del CRM. | ✅ Producción; validada en branch y fusionada el 2026-07-17 |
| 20260717202053 | crm_reconciliar_trigger_reasignacion | **0A, reconciliación pura:** reproduce en el repositorio `private.trg_leads_reasignacion()` y su único trigger `BEFORE UPDATE` tal como ya operan en producción. No incorpora parqueo, INSERT ni ledger; esas reglas comienzan en 0C después de congelar [[Distribución de leads por capital y trazabilidad CRM]]. | ✅ Producción; verificada primero en branch y fusionada el 2026-07-17 |
| 20260717212639 | crm_lead_asignaciones_ledger | **0C, trazabilidad hacia adelante:** introduce el ledger inmutable `crm.lead_asignaciones`, un clasificador único de tenencia vendedor/supervisor, ciclos de reapertura y guards de integridad/concurrencia. El historial humano sigue en `crm.actividades`; SLA se deriva después. Hash SHA-256 exacto: `df5745d9d36fcf57b6197a9d814b4b8e9b5174fd903abae9505a303243077778`. No altera objetos ni interfaz del portal de clientes. | ✅ Producción; `0C_TX_ORACLE_OK`, concurrencia sin solapes y 0 leads al nacer el ledger |
| 20260717215535 | crm_capacidad_leads_objetivo | **4A, expansión compatible:** agrega capacidad objetivo nullable (`1..1000`) solo a vendedor/supervisor y una RPC `SECURITY DEFINER` exclusiva de Gerencia activa para configurarla, sin conceder `UPDATE` directo sobre `crm.equipo`. No cambia el roster ni objetos del portal. | ✅ Producción; `CAPACIDAD_TX_OK` y ACL verificados |
| 20260717222018 | crm_monto_estimado_obligatorio | **4B, contrato de captura:** `crm.leads.monto_estimado` pasa a obligatorio, positivo, máximo `9999999999.99` y hasta 2 decimales. Usa `numeric` sin typmod + CHECK para rechazar `5000.999` en vez de redondearlo; guard fail-closed, lock/timeout y cero backfill inventado. El ledger histórico no se endurece. | ✅ Producción después del frontend compatible; `MONTO_TX_OK` y `NOT NULL` verificados |
| 20260717224252 | crm_metricas_distribucion_leads | **4C, lectura gerencial atómica:** agrega la RPC descriptiva de distribución, capacidad, cohorte por episodio, resultados C/D, SLA, estancamiento y colas. Matriz PEN por rangos exactos; USD separado; no expone ledger, ranking ni recomendaciones. | ✅ Producción; `METRICAS_DISTRIBUCION_TX_OK` y smoke JSON V1 verificados |
| 20260717224435 | crm_metricas_distribucion_acl_copy | Alinea el texto de la RPC con el predicado central `private.es_lector_global()` (`directorio/admin/superadmin`) sin ampliar permisos ni cambiar cálculos. | ✅ Producción; Gerencia/lector global permitidos y vendedor/anon/core directo denegados |
| 20260718152741 | crm_inteligencia_gerencial_hardening | **V2 compatible:** agrega SLA global por ciclo desde ingreso/reapertura, lo fotografía en cada episodio sin reiniciarlo por transferencia/parqueo, conserva SLA operativo por asignación, declara PEN/USD separados sin conversión y mueve V1/V2 a un puente `NOLOGIN` sin acceso a tablas. V1 permanece para rollback. | ✅ **Producción 2026-07-18 (noche)**: branch `crm-agenda-f` → oráculo `METRICAS_DISTRIBUCION_TX_OK` (M01–M23) → advisors sin clases nuevas (security y performance; las RPC nuevas caen en la clase WARN aceptada) → **gate RLS 217/217** → merge → verificado en prod (ambas fn existen, backfill sin NULLs en leads/lead_asignaciones, bridge sin login) → branch borrado. Se aplicó JUNTO a 20260719013000 (Fase F agenda) en una sola pasada de gate. ⚠️ service_role pierde EXECUTE en ambas fn de distribución (por diseño del puente); ninguna edge las llamaba |

## Perfil humano del lead (2026-07-18)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260718000001 | crm_leads_genero_fecha_nacimiento | Agrega `crm.leads.genero` (`text` nullable + CHECK `F/M`) y `crm.leads.fecha_nacimiento` (`date` nullable + CHECK de cordura `1900 ≤ fecha < 2100`), con sus `COMMENT` y los **GRANT por columna** para `authenticated`/`service_role`. Alimenta el avatar de silueta por género, que hasta hoy caía siempre a iniciales. Aditiva pura: no toca RLS, triggers, funciones ni `public`. | ✅ **Producción 2026-07-18** (branch `crm-genero` → merge; columnas+CHECK+GRANT verificados en prod; advisors sin hallazgos nuevos; branch borrado). ⚠️ **Gate RLS omitido con OK explícito de Miguel**: la migración no toca policies ni funciones y las credenciales del gate no estaban a mano; NO sienta precedente para migraciones que sí toquen RLS |

**Trampa que documenta esta migración:** `crm.leads` tiene los privilegios concedidos
**por columna**, no por tabla. Una columna nueva nace SIN `SELECT/INSERT/UPDATE` para
`authenticated`, así que PostgREST la ignora y el campo parece "no existir" aunque esté en el
catálogo. Toda ampliación futura de `crm.leads` debe incluir sus `GRANT` explícitos.

**Por qué la mayoría de edad NO está en un CHECK:** exigiría comparar contra la fecha de hoy y
PostgreSQL solo admite expresiones `IMMUTABLE` en un CHECK. La regla vive en
`app/src/lib/validacion.ts` (`EDAD_MINIMA`, `edadCumplida`), que es la fuente única que ya
comparten `crearLead` y `editarLead`. La base solo descarta lo imposible.

**Diferido con OK de Miguel (2026-07-18):** `public.perfiles` NO se toca en esta pasada, así que
el lead convertido a cliente pierde la silueta. Sería la 3ª excepción del portal.

Advisors del branch: sin hallazgos nuevos atribuibles a esta migración. Los `ERROR`
`security_definer_view` (`clientes_basicos`, `contratos_cartera`) y el `INFO`
`rls_enabled_no_policy` del ledger ya existen **idénticos en producción** (mismas vistas
`postgres`-owned sin `security_invoker`); se verificó comparando `reloptions` y `relowner` entre
branch y prod.

## Agenda comercial — Fase A (2026-07-18)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260718180001 | crm_tareas_agenda | **Motor de próxima acción:** tabla `crm.tareas` (futuro mutable: `pendiente→completada\|cancelada\|no_show`; "vencida" SE DERIVA de `vence_en`, jamás se guarda; FK dual lead/perfil con `num_nonnulls=1`; tenencia espejo del lead derivada por trigger; `confirmada_en` anti no-show; `reagendada_de` encadena reagendas post no-show; contador `reprogramaciones` de sistema). RLS calcada de `leads_*` (lector global solo SELECT, sin DELETE). Triggers de coherencia: reasignar el lead arrastra sus pendientes; lead cerrado/desactivado las cancela. RPC `crm.cerrar_tarea` SECURITY DEFINER transaccional: cierra + INSERT del resultado en `crm.actividades` (tipos manuales; llamada completada EXIGE resultado) + tarea siguiente opcional — el UPDATE directo del cliente solo puede cancelar/reprogramar (flag `crm.op_tarea`). Aditivas legales en `crm.leads`: `no_contactar` + `consentimiento_en/fuente` con GRANT POR COLUMNA. `crm.actividades` NO se toca (sigue log inmutable). Diseño completo en vault "Agenda comercial del CRM (plan v2)". | ✅ **Producción 2026-07-18** por el ciclo COMPLETO: branch `crm-agenda` → oráculo `TAREAS_TX_OK` → **gate RLS de sesiones reales 207/207** (corrido por Miguel; incluye las secciones nuevas de agenda: aislamiento, bandeja, cierre atómico, tarea-sigue-al-lead, directorio, anon) → merge → verificado en prod (19 cols, 3 policies, 4+1 triggers, RPC, 3 cols legales con grant) → branch borrado. Advisors: único hallazgo nuevo = WARN de `cerrar_tarea` (clase ACEPTADA, patrón `convertir_lead`/`metricas_*`) |

Oráculo de la Fase A: `supabase/scripts/test-tareas.sql` (patrón 4A-4C: una transacción que
SIEMPRE revierte; el éxito es el error final `TAREAS_TX_OK`). El gate de sesiones reales
(`test-rls.mjs` + fixtures + seed) se extendió con la matriz de tareas en la misma pasada.

Notas del advisor de 0C: el único hallazgo de seguridad nuevo es `INFO`
`rls_enabled_no_policy` sobre el ledger, deliberado y fail-closed: RLS está activa, no hay
policies, y `anon`/`authenticated`/`service_role` no tienen privilegios directos. Los avisos
de índices no usados del branch son `INFO` esperables en una base sin tráfico; no apareció
ningún ERROR ni WARN atribuible a 0C.

Nota del advisor de 4A: aparece el `WARN`
`authenticated_security_definer_function_executable` para la nueva RPC. Es deliberado:
PostgREST necesita permitir la invocación a `authenticated`, pero la función revoca a
`PUBLIC`/`anon`, exige Gerencia activa tanto en `crm.equipo` como en `public.perfiles`, valida
el objetivo y conserva la tabla sin `UPDATE` directo. El oráculo prueba todos esos gates.

Nota del advisor de 4C: aparece el mismo `WARN`
`authenticated_security_definer_function_executable` para la RPC agregada. Es intencional:
la Data API necesita un endpoint ejecutable por `authenticated`, pero el wrapper exige Gerencia
activa o lector global, revoca a `PUBLIC`/`anon` y el core `private` permanece sin `EXECUTE` para
clientes. El `INFO unused_index` del índice de cohorte es esperable con un branch sin tráfico.

## Gate RLS (2026-07-11, branch `crm-f0`)

`seed:demo` + `test:rls`: **130/130 aserciones** (12 sesiones reales, jerarquía recursiva de
2 niveles, frontera bancaria con rol comercial, scope de cartera de clientes, inmutabilidad, anon).
Iteraciones: 4 fallas de frontera bancaria → #2 (rol comercial); 1 falla (vista vacía) → #3;
2 aserciones nuevas del panel adversarial → #5 (scope de cartera + equipo desactivado).
Advisors del branch: **sin ERROR**; registros nuevos del CRM = 2 WARN
`authenticated_security_definer_function_executable` (`crm.clientes_basicos_fn` y
`crm.existe_cliente_por_dni`), clase ya aceptada en el portal para RPCs gateadas (gate interno
exige staff CRM/lector global). Los 16 WARN de `public.*` con `anon EXECUTE` que aparecen en el
branch eran **drift del baseline**, no de prod (ver abajo).

## Verificación adversarial (panel de 5 escépticos, 2026-07-11)

5 agentes intentaron refutar las garantías del branch antes del merge (seguridad de
`clientes_basicos`, rol comercial, fidelidad del baseline, lógica de F0, completitud del ciclo).
Hallazgos accionados: scope de PII (#5), equipo desactivado (#5), y el drift de grants del
baseline (corregido, ver abajo). Confirmado sin refutar: rol comercial es deny-by-default,
`op_privilegiada` no es fijable por PostgREST, timeline inmutable, CTE recursivo estable.
Hallazgo PRE-EXISTENTE del portal **fuera de alcance CRM** (no se toca por regla): `novedades_update`
permite a cualquier authenticated modificar novedades broadcast (`destinatario_id IS NULL`).

## Fidelidad del baseline (corregido 2026-07-11)

El panel detectó que el branch concedía `EXECUTE` a `anon`/`authenticated` en 16 funciones de
`public` donde prod las revoca (causa: los DEFAULT PRIVILEGES de Supabase conceden EXECUTE en
cada `CREATE FUNCTION` y `REVOKE ... FROM PUBLIC` de pg_dump no borra el grant por-rol). **No es
riesgo de prod** (el merge no toca esas funciones; prod conserva sus ACL). Se corrigió el baseline
(`_DEV_NO_SUBIR/baseline-full.sql` + fila `20260708000000` en prod) con 18 REVOKE explícitos
tomados de las ACL reales de prod, para que **los branches futuros (F1–F5) nazcan fieles**.

## Pasos manuales asociados (una vez, tras el merge)

1. **Exposed schemas en prod**: Dashboard → Settings → API → añadir `crm`
   (queda `public, graphql_public, crm`) — o `PATCH /v1/projects/{ref}/postgrest`.
   En el branch ya se hizo vía API (necesario para el gate).
2. Verificar con `get_advisors` (security + performance) en prod que no aparece nada nuevo.
3. Usuarios reales del CRM: crear con **rol de portal `comercial`** (Auth + `public.perfiles`
   activo + fila en `crm.equipo`). Los analistas reales del portal PUEDEN enrolarse
   conservando su rol analista, sabiendo que mantienen sus poderes de portal.
4. Borrar el branch `crm-f0` (deja de facturar ~$0.32/día).

## Deuda/decisiones anotadas

- El alta/edición de `crm.equipo` no tiene policies a propósito: va por RPC/edge gerencia-gated (F1). Mientras no exista, se administra por SQL de superadmin.
- La conversión lead→cliente (edge `crm-convertir-lead`) llega en F3; el guard de conversión en trigger (`crm.op_privilegiada`) ya la protege.
- Realtime/notificaciones del CRM: F2 (no se añadió nada a la publicación `supabase_realtime`).
- La fila PROPIA de `public.perfiles` es visible para cualquier authenticated (policy
  `perfiles_select` del portal, incluye sus propias columnas bancarias — vacías para staff).
  Es semántica del portal, documentada en el gate; la frontera protegida es la CARTERA.

## Suscripción ICS del calendario (2026-07-18)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260718120243 | crm_agenda_ics_suscripcion | **Google Calendar por suscripción (variante barata de Fase H, sin OAuth):** tabla `crm.agenda_ics` (token uuid secreto por miembro de `crm.equipo`, PK perfil_id, `rotado_en`). RLS: cada quien SU fila en SELECT/INSERT/UPDATE (`perfil_id = auth.uid()`) — el token es privado incluso para su supervisor y los lectores globales; sin policy DELETE (dejar de compartir = rotar). Grants: authenticated select/insert/update; service_role select (la edge). La edge `crm-agenda-ics` (verify_jwt=false; el token ES el control de acceso) sirve las tareas `pendiente+activo` del dueño como ICS: Google lo consume por URL y refresca cada horas. Solo lectura hacia afuera; nada del CRM se puede escribir por el feed. | ✅ **Producción 2026-07-18**: branch `crm-agenda-ics` → oráculo `AGENDA_ICS_TX_OK` (`test-agenda-ics.sql`) → advisors sin hallazgos nuevos (security y performance) → merge (migración + edge) → verificado en prod (3 policies, RLS on, grants exactos, 0 filas). Smoke E2E en el branch: feed 200 con VEVENT correcto (45 min, escapes RFC 5545), token desconocido/malformado → 404. ⚠️ **Gate RLS de sesiones reales omitido con OK explícito de Miguel** (tabla aislada, no toca policies existentes; mismo criterio que `crm_leads_genero_fecha_nacimiento`). **Deuda SALDADA 2026-07-18 (noche):** `agenda_ics` entró a la matriz del gate (`testAgendaIcs` en `test-rls.mjs` + sonda anon + cobertura en `scripts/LEEME.md`; sin fixtures nuevos — la fila es idempotente por PK y la crea la propia sesión) y estrenó en verde en el ciclo `crm-agenda-f` (gate 217/217) |

Oráculo: `supabase/scripts/test-agenda-ics.sql` (patrón 4A-4C; éxito = error final
`AGENDA_ICS_TX_OK`). Frontend: tarjeta "Mi calendario de Google" en Configuración
(genera/copia/rota el enlace) + botón "Añadir a Google Calendar" por tarea en la Agenda.

## Métricas de agenda del manager — Fase F (2026-07-18, noche)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260719013000 | crm_metricas_agenda_fn | **Fase F de la agenda (plan v2):** RPC `crm.metricas_agenda_fn(p_desde date, p_hasta date) returns jsonb` — métricas de EJECUCIÓN por vendedor/supervisor con cartera: toques (5 tipos de contacto manual, `nota` excluida; atribución por `creado_por`), toques_por_día, reuniones realizadas/agendadas, cierres del periodo por `actualizado_en` (completadas / **no asistió** / canceladas — las cerradas son inmutables, así que `actualizado_en` ES el cierre), `pct_completadas` sobre cerradas, suma de `reprogramaciones` de tareas tocadas en el periodo (aproximación documentada), y FOTO actual: pendientes, vencidas derivadas y `leads_sin_accion` (el amarillo del semáforo, por vendedor). Ámbito: `private.vendedor_ids_visibles` (vendedor=él, supervisor=subárbol, gerencia=todos) + `es_lector_global`; gate fail-closed de miembro activo; validación de periodo 22023 (≤366 días, sin futuro, días Lima). SECURITY DEFINER `search_path=''`, patrón clásico de la casa (sin puente: solo lectura agregada del propio ámbito). Grants: EXECUTE solo `authenticated`. Sin tablas, sin policies, sin grants de tablas — cero superficie RLS nueva. | ✅ **Producción 2026-07-18 (noche)**: branch `crm-agenda-f` → oráculo `METRICAS_AGENDA_TX_OK` (`test-metricas-agenda.sql`: valores exactos por vendedor, ámbitos S1/V1/G, 22023, 42501 sin sesión, anon sin EXECUTE; 1 fallo de fixture del propio oráculo corregido en el ciclo — la RPC estaba bien) → advisors sin clases nuevas → **gate RLS 217/217** (mismo ciclo que la V2 de distribución) → merge → verificado en prod → branch borrado |

Oráculo: `supabase/scripts/test-metricas-agenda.sql` (patrón 4A-4C; éxito = error final
`METRICAS_AGENDA_TX_OK`). Frontend: panel "Agenda del equipo" en Hoy→Supervisor y
Hoy→Gerencia (pendiente en el momento del merge; misma sesión).

## Metas comerciales del mes — Fase 1 de funciones de gerencia (2026-07-19)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260719120000 | crm_objetivos_metas | **Metas reales por rol (hasta hoy solo existían en demo):** tabla `crm.objetivos` — UNA fila por (mes, rol vendedor/supervisor/gerencia), `capital_objetivo` SIEMPRE en PEN (numeric 14,2, 0–100M), `ventas_objetivo` (0–1000), `conversion_objetivo` (0–100%), periodo = primer día de mes (CHECK día 1, rango 2026–2100), id uuid propio para que `log_audit_crm` registre `fila_id`, UNIQUE (periodo, rol). Triggers touch + audit. RLS: SELECT para todo el árbol comercial (`rol_crm` no nulo) + lector global; **SIN policies de escritura** — la única puerta es la RPC `crm.fijar_objetivos(p_periodo date, p_objetivos jsonb) returns setof crm.objetivos` (SECURITY DEFINER `search_path=''`): gate de gerencia activa con perfil activo (42501, mismo patrón que capacidad), validación 22023 (periodo/roles/rangos/números basura), upsert parcial por rol sin pisar los demás, `actualizado_por` = actor, devuelve el periodo completo. Grants: tabla SELECT authenticated (+ CRUD service_role para fixtures del gate); RPC EXECUTE authenticated (clase WARN aceptada y documentada). | ✅ **Producción 2026-07-19**: branch `crm-objetivos` → oráculo `OBJETIVOS_TX_OK` (`test-objetivos.sql`: O01–O22 a la primera) → advisors sin clases nuevas (solo la RPC en la clase WARN aceptada + su índice FK nuevo como unused INFO) → **gate RLS 232/232 con `testObjetivos`** (periodo sentinela 2099-12, limpieza pre/post) → merge → verificado en prod → branch borrado |

Oráculo: `supabase/scripts/test-objetivos.sql` (patrón 4A-4C; éxito = token
`OBJETIVOS_TX_OK`). Frontend (misma sesión): `cargarReal` lee las metas del mes
Lima (degrada a cero si el fetch auxiliar cae — jamás tumba el boot),
`fijarObjetivos` en el store (optimista + resync como rollback, espejo
`editarConfiguracion`) y editor "Fijar metas del mes" en Hoy→Gerencia.

## Reparto de la cola de leads — C1 del rol `coordinador` (2026-07-22)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260721120000 | crm_reparto_coordinador_c1 | **Rosa reparte la cola de leads nuevos DESDE el CRM (la vía-hoja quedó descartada):** (a) `equipo_rol_crm_check` acepta `coordinador` (hasta hoy solo vendedor/supervisor/gerencia); (b) `private.vendedor_ids_visibles` gana rama explícita `coordinador → ∅` (antes caía al `else` de vendedor: ∅ implícito y frágil); (c) **las policies de `crm.leads` NO se tocan** — decisión, no omisión: el coordinador tiene ámbito ∅ y todo su trabajo pasa por RPC; (d) `crm.leads_por_repartir()` — cola global (`vendedor_id` y `asignado_supervisor_id` null, etapas abiertas, FIFO), proyección **SIN PII de contacto** (sin teléfono/correo/DNI: Rosa enruta, no contacta) y excluye `no_contactar=true` (Ley 29571); (d-bis) `crm.supervisores_para_reparto()` — destinos activos + conteo de bandeja (el coordinador no puede listar `crm.equipo` por RLS); (e) `crm.repartir_lead(p_lead, p_supervisor)` — `SELECT … FOR UPDATE` + **UPDATE con predicado CAS** anti-carrera; setea `asignado_supervisor_id` dejando `vendedor_id` null (respeta `leads_tenencia_exclusiva` y el guard de tenencia); re-valida `no_contactar` con **SQLSTATE PROPIO `P0429`** (nunca 42501: así el candado del gate no puede pasar en falso con un error de autorización); actividad y auditoría las escriben los triggers, la RPC no inserta nada. Las 3 RPC son SECURITY DEFINER `search_path=''` con gate `coordinador\|gerencia` activos (42501), `revoke public,anon` + `grant authenticated` (clase WARN aceptada). (f) **Endurecimiento de superficies adyacentes** que se abren al dejar `rol_crm` de ser NULL: `crm.existe_cliente_por_dni` (oráculo de enumeración de DNIs) y la policy `objetivos_select` pasan a la allowlist `IN (vendedor,supervisor,gerencia)`, y `crm.metricas_agenda_fn` añade ese filtro a su gate de miembro activo (cuerpo copiado verbatim de prod, único cambio el gate). **`crm.clientes_basicos_fn` NO se tocó**: el plan citaba el cuerpo de `20260711000003`, pero la definición viva es la de `20260711000004` — scopeada POR CARTERA y con 2 columnas añadidas después; reemplazarla habría fallado por cambio de tipo de retorno y, de pasar, habría REVERTIDO el scoping (fuga masiva de PII). Con la definición real el coordinador ya obtiene 0 filas → queda como aserción del gate, no como cambio de SQL. Regresión cero para vendedor/supervisor/gerencia/lector global. | ✅ **Producción 2026-07-23** (migración registrada `20260722151234`): branch `crm-reparto-c1` → oráculo `REPARTO_TX_OK` (`test-reparto.sql`: R01–R27 a la primera) → advisors sin clases nuevas (solo las 3 RPC en la clase WARN aceptada) → gate RLS **283/283** con `testReparto` → merge → verificado en prod (3 RPCs + CHECK con `coordinador`) → deploy FE `index-ConoedHp.js` → Rosa enrolada (`rosa@crmavance.com`, coordinador off-roster) |

Oráculo: `supabase/scripts/test-reparto.sql` (patrón 4A-4C; éxito = token
`REPARTO_TX_OK`). La CARRERA de doble reparto no se prueba ahí (necesita dos
sesiones simultáneas): la cubre `testReparto` en `test-rls.mjs` con
`Promise.allSettled` de coordinador+gerencia sobre el mismo lead.
Frontend (misma sesión): rol `coordinador` off-roster (como `directorio`),
capacidades `repartirCola`/`verCartera`, pantalla `screens/repartir.tsx`,
guards en `lib/vistas.ts` y omisión de `listarEquipo` en el boot del coordinador
(`equipo_visible_fn` puede RAISE para su rol y tumbaría su sesión).

## Descarte de la cola de leads — C1-bis: el código marca, Rosa cierra (2026-07-23)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260723120000 | crm_descarte_coordinador_c1b | **Los leads que piden préstamo dejan de llegar al vendedor, con DOBLE filtro** (sobre 187 leads reales solo 1 pide crédito → un clasificador que cerrara solo destruiría depositantes por falsos positivos; por eso el código MARCA y solo Rosa CIERRA): (a) motivo `pide_credito` en `leads_motivo_descarte_check` (medir la basura de crédito sin contaminar `sin_interes`); (b) columnas `clasificacion_auto` (CHECK `posible_credito`\|null) + sello `descartado_en`/`descartado_por` (FK `public.perfiles` ON DELETE SET NULL, autorizada por Miguel) con grants por columna + 3 índices parciales; (c) `private.redactar_pii(text)` — correo→celular (con separadores)→documento, fuente única de redacción; (d) trigger `zz_sello_descarte` (último BEFORE): clasifica en el INSERT con regla ESTRECHA `\m(prestam\|financiamient)` sobre nota sin tildes (auditoría 2026-07-23: `credit*` marcaba "cooperativa de ahorro y crédito" y `prestar` marcaba "prestar información"), sella el cierre con `statement_timestamp()`+`auth.uid()`, limpia el sello al reabrir y hace `clasificacion_auto` INMUTABLE (dato de medición: sin él no hay matriz de confusión); (e) `leads_por_repartir()` v2 (DROP+CREATE por cambio de retorno, ACL re-emitida): + `clasificacion_auto` y `comentario` = nota REDACTADA y trunca a 400 — Rosa lee la pregunta del cliente, no sus datos de contacto; FIFO y filtros idénticos (la marca resalta en UI, no reordena); (f) `crm.descartar_lead(p_lead, p_motivo, p_nota)` — SOLO cola global (Rosa no cierra trabajo ajeno), FOR UPDATE + UPDATE CAS anti-carrera, idempotente para mismo actor+motivo (`ya_estaba`), nota se APPENDEA (`· DESCARTE: …`), no toca `activo` ni tenencia, descartar a un No Insista SÍ se permite (cerrar no es contactar); (g) `crm.deshacer_descarte(p_lead)` — ventana 24 h, SOLO descartes propios, reabre en `nuevo` (el guard incrementa `ciclo_actual`), choque con índice único vivo → 22023 humano. SQLSTATE: 42501 rol · 22023 argumento · P0002 fuera de cola/carrera/ajeno. Ambas RPC SECURITY DEFINER `search_path=''`, revoke public/anon + grant authenticated (clase WARN aceptada). Auditada ANTES de aplicar: 8 agentes, NO-GO→GO (`302b5c0`). | ✅ **Producción 2026-07-24** (registrada `20260724152923`): branch `crm-descarte-c1b` → oráculo `DESCARTE_TX_OK` (D01–D55) → advisors sin clases nuevas → gate RLS vivo **309/309** → merge → branch borrado. Deploy FE `index-B9S8YLrv.js` |

Oráculo: `supabase/scripts/test-descarte.sql` (patrón 4A-4C; éxito = token
`DESCARTE_TX_OK`; D01–D55: clasificador marca/no-marca y el cliente API no decide,
inmutabilidad de la marca, cola v2 redactada y trunca, gates 42501, contrato
22023/P0002, idempotencia, sello nominal, nota appendeada, deshacer con ventana
—fixture backdateada desactivando el trigger zz DENTRO de la tx— y choque
23505→22023 al reabrir). La CARRERA de descarte la cubre `testDescarte` en
`test-rls.mjs` (Promise.allSettled coordinador+gerencia, motivos distintos) junto
con la vía PostgREST real: marca nacida del INSERT de service_role, comentario
redactado en la proyección v2, inmutabilidad incluso para service_role, ya_estaba,
deshacer personal y estado tras la carrera.

## Vista de descartados de la cola — C1-ter (2026-07-24)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260724203052 | crm_descartados_coordinador_c1c | **La pestaña "Descartados" de Rosa** (pedido de Miguel): hoy el descarte desaparece de su pantalla y el "Deshacer" solo vive 15 s en un toast, pero `crm.deshacer_descarte` da 24 h — sin vista, esa ventana era inalcanzable. RPC nueva `crm.leads_descartados()` (SECURITY DEFINER `search_path=''`, STABLE) que lista los descartes recientes de la COLA GLOBAL (30 días, LIMIT 200, `descartado_en DESC`) con: `clasificacion_auto` (marca del código), `comentario` del cliente y `nota_descarte` de Rosa **REDACTADOS Y TRUNCADOS A 400 POR SEPARADO** (auditoría c1c: c1b appendea `· DESCARTE: …` al comentario → truncar el texto pegado empujaría la razón del cierre fuera del corte, y con ámbito ∅ no hay otra vía de recuperarla; se separan por el marcador `' · DESCARTE: '`), `motivo_descarte`, `descartado_en`, `descartado_por_nombre`, `creado_en`+`categoria_interes` (para avisar qué tan viejo es el lead que, al deshacerse, vuelve al frente del FIFO), y los hints de UI `es_mio` / `puede_deshacer` (propio + 24 h; el servidor RE-VALIDA todo en `deshacer_descarte`). **DOBLE filtro de alcance** (auditoría c1c): (1) tenencia actual nula (excluye descartes de cartera del vendedor, que tienen dueño) y (2) `exists` de rol `coordinador\|gerencia` sobre `descartado_por` — sin (2), un lead que un vendedor descartó y que gerencia liberó luego a la cola reaparecería con el nombre del vendedor. Gate `coordinador\|gerencia` activos (42501). Solo LECTURA sobre `crm.leads` + JOIN de lectura a `public.perfiles` (no altera public). `revoke public,anon` + `grant authenticated` (clase WARN 0029 aceptada). Auditada por workflow adversarial (4 lentes) ANTES de aplicar: veredicto GO, 4 hallazgos incorporados (separación comentario/nota, `creado_en`, filtro de autor, este ledger). | ✅ **Producción 2026-07-24** (registrada `20260724210352`): branch → oráculo `DESCARTADOS_TX_OK` → advisors sin clases nuevas → gate RLS vivo **319/319** → merge → branch borrado. Deploy FE `index-CmAeIm2U.js` |

Oráculo: `supabase/scripts/test-descartados.sql` (patrón 4A-4C; éxito = token
`DESCARTADOS_TX_OK`; V01–V24: gate 42501, alcance doble —L5 con dueño y L6
autor-vendedor NO aparecen—, ventana de 30 días, orden DESC, separación
comentario/nota_descarte, `creado_en`/`categoria_interes`, `es_mio`/`puede_deshacer`
por actor y ventana, e integración con `deshacer_descarte`). Aserciones vivas
adicionales en el bloque (F) de `testDescarte` (`test-rls.mjs`): vía PostgREST real,
gate por rol, `es_mio`/`puede_deshacer` propios vs ajenos, sin PII de contacto.

## El reloj del vendedor — tenencia_desde (2026-07-25)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260725012707 | crm_tenencia_desde_vendedor | **El reloj que mide al ASESOR, no al lead** (pedido de Miguel): con el circuito vivo (origen → hoja → cola de Rosa → bandeja del supervisor → vendedor) un lead pasa DÍAS antes de llegar a un asesor, y la cola lo medía desde `creado_en` → le nacía en ROJO CRÍTICO el primer segundo que lo veía. Columna nueva `crm.leads.tenencia_desde timestamptz` + trigger `trg_leads_zzz_tenencia_desde` → `private.trg_leads_tenencia_desde()` (SECURITY DEFINER, `search_path=pg_catalog`, sin leer ninguna tabla). Es una **PROYECCIÓN de `crm.lead_asignaciones.asignado_en` del episodio ABIERTO**: el ledger sigue SELLADO (RLS on, cero policies, cero grants) — abrirlo al cliente solo para pintar un reloj habría expuesto el historial completo de tenencia. **El trigger ESPEJA la condición del escritor del ledger** (`activo AND etapa operativa AND vendedor_id not null`), no solo el cambio de dueño: la auditoría (hallazgo A1) encontró 5 caminos de divergencia, y uno REPRODUCÍA el bug —un descartado reabierto al MISMO asesor conservaba el reloj viejo—. Mismos instantes que el ledger (`creado_en` en INSERT, `statement_timestamp()` al abrir episodio) → al compartir statement no pueden divergir. Backfill desde el ledger **ANTES** de crear el trigger (si no, la rama `else` lo borraría en el mismo statement) y con `trg_leads_before_update` apagado (si no, `actualizado_en := now()` reordenaría de golpe la cartera de todos los asesores, que el front ordena por esa columna). Índice `idx_leads_tenencia`. `grant select (tenencia_desde) to authenticated, service_role`. **⚠️ El grant NO es lo que protege la columna**: el ACL de `crm.leads` es de TABLA (`relacl` verificado en prod: `authenticated=arw`), así que un `revoke update (columna)` sería no-op silencioso y PostgREST acepta la columna en el body — **la inmutabilidad la sostiene el TRIGGER**, que reimpone `old.tenencia_desde` en todo UPDATE que no abra episodio. El `COMMENT ON COLUMN` lo dice así a propósito (la primera versión afirmaba "sin grant de UPDATE", que era **falso**, y ese texto vive en la BD engañando a la próxima auditoría). Auditada por `auditor-rls` ANTES de aplicar: veredicto NO-GO → 2 críticos + 2 altos + 4 medios corregidos → aplicada. | ✅ **Producción 2026-07-25**: branch `crm-tenencia` → oráculo `TENENCIA_TX_OK` (V01–V30) → advisors sin clases nuevas → gate RLS vivo **326/326** → merge → branch borrado. ⚠️ **prod la registró como versión `20260725015135`, NO como el `20260725012707` del nombre de archivo**: `apply_migration` por MCP sella su propio timestamp. No se corrige renombrando (nunca se edita una migración ya aplicada); la migración es IDEMPOTENTE de punta a punta (`add column if not exists`, `create or replace function`, `drop trigger if exists`, `create index if not exists`, y un backfill que ya no encuentra filas), así que un `db push` que la re-aplique no rompe nada |
| 20260725060657 | crm_avance_automatico_etapa | **La etapa avanza sola cuando el hecho YA ocurrió** (pedido de Miguel, textual: «cuando el vendedor registre una acción de que SÍ contactó a la persona, y el lead está en la primera fase del pipeline, el prospecto se mueva solo de etapa»). Dos triggers AFTER INSERT, ambos **SOLO DE SUBIDA**: (a) `trg_zz_actividades_avance_etapa` sobre `crm.actividades` → `private.trg_actividades_avance_etapa()`: una CONVERSACIÓN sube el lead de `nuevo` a `contactado`. **Solo los 3 tipos bidireccionales** (`llamada_realizada`, `whatsapp_recibido`, `reunion_realizada`), NO los 5 de `TIPOS_CONTACTO`: «no contestó» y «mensaje enviado» son INTENTOS, y avanzar por ellos convertiría ese botón en un *posponer la alarma 48 h* (umbral `nuevo` 24 h → `contactado` 72 h en `private.umbral_estancamiento`) e inflaría la conversión sin que nadie mienta a propósito. Por eso NACE `TIPOS_CONVERSACION` en `tipos.ts` como subconjunto ESTRICTO y separado: `TIPOS_CONTACTO` responde «¿el asesor trabajó?» (mide esfuerzo → SLA y cola), `TIPOS_CONVERSACION` responde «¿el cliente respondió?» (mide embudo → etapa). Jamás fusionarlos. (b) `trg_zz_tareas_avance_etapa` sobre `crm.tareas` → `private.trg_tareas_avance_etapa()`: agendar una reunión sube el lead a `reunion_agendada`, con CINCO guardas — `tipo='reunion'`, `reagendada_de is null` (**la que más importa: el rebote automático tras un no-show NO es progreso; sin ella, plantar al asesor ASCENDERÍA el lead, la mentira más fácil de fabricar del sistema**), `estado='pendiente'`+`activo`, `vence_en > now()` (agendar en el pasado no es agendar), y un `exists` de contacto real (nunca afirmar «reunión agendada» sobre un lead que NADIE tocó, incluido el parkeado que agenda un supervisor). Sube solo desde `nuevo`/`contactado`: desde `propuesta_enviada` sería un RETROCESO que además reiniciaría el SLA de 120 h a 72 h. (c) `CREATE OR REPLACE` de `private.trg_leads_cambio_etapa` (jamás DROP+CREATE: borraría la ACL) para añadir `automatico` al `metadata` de la actividad, alimentado por un `set_config('crm.avance_auto', …, true)` LOCAL a la transacción — sin esa marca el historial atribuiría al vendedor movimientos que él no pidió, y el cliente no puede encenderlo por PostgREST (aserción del gate). **NUNCA BAJAN DE ETAPA**: un `cambio_etapa` es un hecho registrado con autor, no un estado reversible; el retroceso sigue siendo decisión explícita de una persona. La recursión se corta por DOMINIO (los tipos que emite el sistema —`cambio_etapa`/`reasignacion`/`conversion`— jamás están en la lista que dispara), reforzado por el `WHEN` del trigger y por un `if` repetido dentro de la función. Idempotencia por el predicado `etapa='nuevo'` DENTRO del UPDATE (sin ventana entre leer y escribir): tres contactos seguidos escriben UN solo `cambio_etapa`. Sin columnas nuevas → sin GRANTs nuevos y sin `gen:types`. Espejo del front en `app/src/lib/avance-automatico.ts` (fuente única de las dos reglas, y ÚNICA implementación en modo demo, donde `persistir()` sale en seco). **Correcciones de la auditoría `auditor-rls` (veredicto NO-GO → corregido):** **C1 CRÍTICO — escalada cerrada.** El trigger de tareas lleva GATE DE ÁMBITO propio porque la policy `tareas_insert` **nunca consulta `crm.leads`**: valida el `vendedor_id` de la fila NUEVA, que `trg_tareas_before_insert` (SECURITY DEFINER) ya derivó del lead saltándose la RLS. Para un lead de la COLA GLOBAL sale `null` y la rama `supervisor|gerencia AND vendedor_id IS NULL` del WITH CHECK lo deja pasar → **cualquier supervisor** podía ascender leads que `leads_select` ni le deja VER (61 leads en esa cola al auditar). Gate: dueño no nulo + `puede_ver_cartera` o gerencia, con `auth.uid() is null` para sistema. ⚠️ **El hueco de `tareas_insert` es PREVIO y sigue abierto** (un supervisor puede crear tareas sobre leads invisibles): se documenta, no se toca aquí — el gate impide que ARRASTRE una escritura sobre `crm.leads`. **A1 — ciclo de deadlock cerrado.** El trigger hacía que `crm.cerrar_tarea` pasara a bloquear `tareas → leads`, mientras `trg_leads_sync_tareas` bloquea `leads → tareas`: cerrar una tarea mientras el supervisor reasigna el mismo lead daba `40P01`. Se unifica el orden con un `for no key update` sobre el lead al inicio de `cerrar_tarea`. **Verificado contra la BD VIVA** (no contra el repo: el ledger ya documenta que prod puede derivar): `diff` del `prosrc` de producción contra el cuerpo de esta migración = **+15 líneas, −0**. El `prosrc` vivo no tiene comentarios, así que el REPLACE no borra doctrina de la BD. El subselect del lock REPITE el filtro de ámbito del `for update` (2ª pasada, MEDIO-1): si solo buscara por id, un usuario con rol podría tomar un lock sobre el lead de una tarea ajena y, si otra transacción lo tuviera tomado, esperar hasta el `statement_timeout` — un oráculo de temporización sobre si ese lead se está escribiendo. **M1** trigger renombrado a `trg_zz_actividades_avance_etapa`: Postgres ordena por nombre COMPLETO, y `trg_actividades_zz_…` corría ANTES que `trg_audit_actividades` dejando `audit_log` en orden causal invertido. **M2** las tres funciones a `search_path='pg_catalog'` (la convención endurecida del repo; `public` era superficie de shadowing gratis). **M3** `set local lock_timeout='5s'` (CREATE TRIGGER toma SHARE ROW EXCLUSIVE sobre dos tablas calientes). **M4** guarda de reentrada por el propio flag: hoy no hay recursión posible por dominio, pero un futuro webhook de WhatsApp o auto-log de llamadas la abriría. **M5/M6/B2** oráculo: `order by creado_en, id` (la actividad y su `cambio_etapa` comparten `now()`), aserciones V10b/V10c de no-cascada y de no-fuga del flag, y `row_count` en V17 para que no pase en vacío. **B1** los 5 leads transitorios se desactivan al final del gate. **Decisión explícita (N2):** un lead con `no_contactar` SÍ avanza al registrar una conversación — registrar lo que pasó no es aprobarlo (pudo llamar él), y bloquearlo dejaría el dato inconsistente con su propio timeline; lo que la Ley 29571 prohíbe es CONTACTAR, y de eso se ocupa el kill-switch de `motor-siguiente.ts`. Fijado en V23. | ✅ EN PROD (merge 2026-07-26, reescrita por Supabase como `20260726062402`) |
| 20260725221530 | crm_tareas_insert_exige_lead_visible | **Cierra un hueco PREVIO de `tareas_insert`** (lo destapó la auditoría del avance automático como hallazgo C1; corregido por orden de Miguel el 2026-07-25). La policy validaba la TENENCIA de la fila nueva (`vendedor_id`/`asignado_supervisor_id`) pero **nunca consultaba `crm.leads`** — y esos campos no los manda el cliente: los DERIVA `private.trg_tareas_before_insert`, que es SECURITY DEFINER y lee el lead saltándose la RLS. Para un lead de la COLA GLOBAL ambos salen `null` y el WITH CHECK pasaba por la rama `supervisor|gerencia AND vendedor_id IS NULL` → **cualquier supervisor con el UUID podía crear tareas sobre un lead que `leads_select` no le deja ni VER** (61 leads en esa cola al auditar), metiéndose trabajo ajeno en la agenda. `ALTER POLICY` (no DROP+CREATE: conserva nombre, comando, roles y USING, y la tabla no queda ni un instante sin policy) añadiendo `lead_id is null or exists (select 1 from crm.leads l where l.id = lead_id)`. El `exists` NO es SECURITY DEFINER → lo filtra `leads_select`, misma técnica que ya usaba `actividades_insert` y por la que esa vía nunca tuvo el problema. Es un ESTRECHAMIENTO puro: vendedor sobre lead suyo, supervisor sobre su equipo o su bandeja, gerencia sobre cualquiera, tareas de cliente (`lead_id` null), `crm.cerrar_tarea` y `service_role` siguen todos igual. | ✅ EN PROD (merge 2026-07-26, reescrita por Supabase como `20260726062424`) |
| 20260726151751 | crm_anular_autoria_y_retroceso_reunion | **Anular con AUTORÍA, y la reunión que se cae devuelve el lead a su etapa** — dos pedidos de Miguel (2026-07-26), textuales: «si se anula la reu y no se reagenda una en ese mismo momento, debería bajar de etapa» y «separa lo que cancela el sistema y lo que cancela el asesor». Son **la misma pieza**: sin la separación no se puede disparar el retroceso solo cuando lo ordena una persona. (a) Columna `crm.tareas.cancelada_por` (`'asesor'|'sistema'`) con CHECK bicondicional. Grants: `crm.tareas` los tiene A NIVEL DE TABLA, así que la columna nueva es visible para PostgREST sin GRANT extra (≠ `crm.leads`, que los tiene por columna). Backfill a `'sistema'` apagando **por nombre** los 3 triggers que estorban: el BEFORE aborta todo update sobre una tarea cerrada, `trg_tareas_touch` movería `actualizado_en` —el campo por el que la métrica atribuye los cierres a un periodo, así que cada cancelación histórica saltaría al mes en curso— y `log_audit_crm` escribiría un evento de negocio que no ocurrió (**excepción consciente** a «trigger de auditoría en toda tabla `crm.*`»). En prod afectó a 0 filas (verificado: 4 completadas / 2 pendientes / 1 no_show / **0 canceladas**), luego toda cancelación preexistente es por construcción del sistema. (b) `private.trg_tareas_before_update` SELLA la etiqueta (la deriva de CÓMO entró la escritura, jamás del payload) y **cierra un hueco previo**: `cancelada` era el único cierre que no exigía la RPC — cualquiera con una sesión válida podía vaciar su agenda por PATCH a `/rest/v1/tareas` sin quedar etiquetado y saltándose el retroceso. El portazo se limita a sesiones HUMANAS (`auth.uid() is not null`) para no romper service_role/seeds/teardown del gate, que reciben `'sistema'` — la verdad literal: ahí no hay asesor. (c) `private.trg_tareas_before_insert` sella lo mismo al nacer (antes solo estaba a salvo por accidente de secuencia). (d) `private.trg_leads_sync_tareas` marca `'sistema'` vía la GUC LOCAL nueva `crm.cancela_sistema`. (e) **`private.retroceso_por_anular_reunion`**, llamada INLINE al final de `crm.cerrar_tarea`: baja el lead de `reunion_agendada` a `contactado`, o a `nuevo` si NUNCA hubo contacto real en el ciclo vigente. **Es la ÚNICA excepción a «las etapas nunca bajan solas»** de 20260725060657, y solo porque el disparo es humano: la doctrina protege HECHOS, y aquí el hecho es que una persona declaró que la reunión ya no existe — sostener `reunion_agendada` sin reunión viva no conserva un hecho, sostiene uno falso, y el más caro (ese lead deja de aparecer como pendiente de agendar). Cuatro guardas: etapa EXACTAMENTE `reunion_agendada`, ninguna otra reunión pendiente viva, ninguna `reunion_realizada` **del ciclo vigente**, y el gate de ámbito de C1 (dueño + alcance del actor) porque es SECURITY DEFINER y su UPDATE ignora `leads_update`. Helper nuevo `private.inicio_ciclo_lead` (ledger `crm.lead_asignaciones`) para el anclaje al ciclo. (f) `crm.metricas_agenda_fn` separa `canceladas_asesor`/`canceladas_sistema` —`canceladas` sigue siendo el TOTAL— y **saca las del sistema del denominador de `pct_completadas`**, lo que arregla un sesgo vivo desde 20260719013000: convertir un lead cancela sus pendientes por trigger y cada una BAJABA el % del vendedor, o sea que el mejor resultado del embudo le empeoraba la nota. Las del asesor SÍ siguen contando: sacarlas convertiría el botón nuevo en una salida gratis. `version` sigue en 1 (claves aditivas) y el contrato Valibot del front las declara OPCIONALES para que ninguno de los dos órdenes de despliegue rompa el panel. **Auditoría `auditor-rls`: NO-GO → corregido.** **A1 (ALTO):** el CHECK «bicondicional» de la 1ª versión no restringía nada — `null in ('asesor','sistema')` evalúa a NULL y un CHECK solo se viola con FALSE, así que la fila «cancelada sin autor» entraba (confirmado ejecutándolo contra el motor); resuelto con `is not null` explícito. **M1 (MEDIO):** el retroceso era un AFTER UPDATE y corría ANTES de que existiera la reunión reagendada → bajaba y subía, dejando 2 `cambio_etapa` espurios en un log INMUTABLE, y en un lead sin contacto registrado la subida ni lo devolvía (degradaba DOS etapas); resuelto moviéndolo INLINE al final de la RPC, sin perder cobertura (la etiqueta `'asesor'` solo la pone esa RPC) y dejando el orden de bloqueo explícito. **M2** sello en INSERT, **M3** anclaje al ciclo (un lead reabierto habría quedado con el retroceso bloqueado para siempre), **M4** `disable trigger` por nombre en vez de `user` (que FIJA `tgenabled` en 'O' en vez de restaurarlo), **B4** índice retirado (no servía al CTE `cierres`, habría nacido *unused* en advisors), **B5** limitación de la cola global documentada, **M5** documentado en el `comment on column`: la etiqueta dice CÓMO entró la cancelación, no QUIÉN la firmó — un supervisor puede anular la tarea de su vendedor y se agrupa igual por `vendedor_id`, como el resto de métricas. Espejo del front en `app/src/lib/avance-automatico.ts` (`retrocesoPorAnularReunion`, con la divergencia del ciclo documentada) y `lib/agenda-equipo-vista.ts` (`canceladasAsesor`/`canceladasSistema`). Requiere `gen:types`. | ✅ EN PROD (merge 2026-07-26, reescrita por Supabase como `20260726161945`). Ciclo completo verde en el branch `crm-anular-retroceso`: oráculo nuevo `ANULAR_TX_OK` (22 aserciones, incluida V14b = anular+reagendar escribe CERO `cambio_etapa`, y V15c = no se puede mover el embudo de un equipo ajeno), regresión `AVANCE_TX_OK` y `TAREAS_TX_OK` (esta migración reescribe `cerrar_tarea` y los 3 triggers de tareas/leads, así que ambos son suyos), **gate RLS 347/347** (319 antes) y advisors sin clases nuevas. Verificado en prod tras el merge: columna, CHECK con `IS NOT NULL`, ACL de `cerrar_tarea` intacta para authenticated+service_role, los 2 helpers de `private` sin EXECUTE para nadie, y CERO rastro de `trg_zz_tareas_retroceso_etapa` (el trigger de la 1ª versión). Backfill: 0 filas (prod tenía 0 canceladas). `database.types.ts` actualizado a mano —el archivo está CURADO, no es salida cruda del generador: `cancelada_por` va solo en `Row` porque el front nunca la escribe— y el comentario de `Update.estado` corregido, que afirmaba que 'cancelada' pasaba sin la RPC y eso es justo lo que esta migración cerró. Branch borrado. |
| 20260727032429 | crm_anular_ajena_no_penaliza | **Lo que anula el JEFE no se lo cobra el vendedor** — decisión de Miguel (2026-07-26) cerrando lo que quedó abierto al desplegar `20260726151751`: «si el supervisor anula una tarea el vendedor no debería poder hacer nada sobre esa tarea». La mitad literal ya estaba (una tarea cerrada es inmutable por el BEFORE UPDATE y ni siquiera viaja al navegador); faltaba la consecuencia: si no tuvo control sobre ella, no puede pesar en su `pct_completadas`. La migración anterior separó CÓMO entró la cancelación (`'asesor'|'sistema'`) pero no CUÁL persona, y las filas se agrupan por `vendedor_id` — su propio `comment on column` lo dejó anotado como límite conocido (M5), que esta migración levanta y reescribe. **Regla única, sin casos especiales:** una anulación entra en el denominador de alguien SOLO si se puede afirmar que la firmó esa misma persona; el sistema, el jefe y el autor indeterminado quedan fuera, o sea que siempre falla hacia el lado que no castiga a quien no decidió. (a) Columna `crm.tareas.cancelada_por_id uuid`, **SIN FK a `public.perfiles`** y a propósito: no por la regla de «no tocar public» (el hermano `creado_por` sí la tiene, el precedente existe) sino por la métrica — con `on delete set null`, dar de baja a un supervisor vaciaría su firma y MOVERÍA hacia atrás el % de un vendedor que no hizo nada. La integridad no se pierde porque el valor lo sella el trigger desde `auth.uid()` y nunca llega del payload. **Por qué una columna y no un tercer valor `'supervisor'` en `cancelada_por`:** una etiqueta habría que recalcularla cada vez que el lead cambia de dueño (la misma anulación sería propia o ajena según quién tenga el lead HOY); el uuid congela el hecho, y «propia o ajena» se deriva comparándolo con `vendedor_id`, que además es inmutable tras el cierre (`trg_leads_sync_tareas` solo propaga a `estado='pendiente'` y el BEFORE aborta todo update sobre una cerrada). (b) Backfill **desde `public.audit_log`** (`distinct on (fila_id) order by ts`, la primera transición a cancelada), con los 3 triggers de siempre apagados POR NOMBRE y una guarda `to_regclass('public.audit_log')` porque esa tabla la crea el PORTAL, no este repo: un branch sin las migraciones del portal reventaría por una atribución que ahí afecta a 0 filas (plpgsql resuelve los nombres al ejecutar, así que si la rama no entra el UPDATE ni se parsea). En prod atribuye **3 filas, las 3 anuladas por MIGUEL BRICEÑO sobre SUS PROPIAS tareas** → quedan «propias» y el % de nadie se mueve hacia atrás; recuperarlo del historial en vez de asumir era lo correcto aunque asumir hubiera acertado por casualidad. (c) CHECK `tareas_cancelada_por_id_valida` con **CASE y no `or`**, por la trampa que costó el NO-GO de la anterior: `cancelada_por = 'asesor' or cancelada_por_id is null` NO restringe — con la etiqueta a null el primer operando da NULL, `NULL or FALSE` da NULL y un CHECK solo se viola con FALSE, así que una firma huérfana en una fila no cancelada entraría. Deliberadamente **permisivo en la otra mitad** ('asesor' no exige firma): para las filas nuevas la firma está garantizada por construcción (el trigger solo pone 'asesor' en la rama donde `v_uid is not null`), así que el hueco solo cubre historia inatribuible, y prohibirlo convertiría una laguna del pasado en una migración que no aplica. (d) El sello de `trg_tareas_before_update` **se refactoriza a UN booleano** (`v_asesor := (not v_sistema) and v_op and v_uid is not null`) del que salen las dos columnas: «etiquetada como asesor pero sin firma» —o al revés— deja de ser expresable. `trg_tareas_before_insert` sella la firma a null (una tarea que nace cancelada es de sistema: no hay a quién atribuir). (e) `crm.metricas_agenda_fn` añade `canceladas_ajenas` (ADITIVA, `version` sigue en 1) y **el denominador de `pct_completadas` pasa a las PROPIAS**. `is distinct from` y no `<>` para partirlas: en el CTE `vendedor_id` nunca es null pero `cancelada_por_id` sí puede serlo en la historia del backfill, y con `<>` esas filas se caerían de las DOS cuentas dejando `propias + ajenas < canceladas_asesor` sin que nada avise — la invariante «las dos mitades suman el total» es lo que hace la métrica auditable de un vistazo. Espejo del front en `lib/agenda-equipo-vista.ts` (`canceladasAjenas`/`canceladasPropias`, con suelo en 0 porque las dos claves llegan por separado y OPCIONALES: una BD a medio migrar podría mandar la segunda sin la primera y el % se dispararía por encima de 100) y en `screens/hoy/agenda-equipo.tsx`, donde la sub-línea **tenía que cambiar o mentiría por omisión** —el «n anuladas» ya no es el total— y los segmentos de la barra pasan a `propias` para que sumen exactamente el denominador que acompañan. Efecto colateral bueno y no buscado: gerencia ve «n anuladas por un superior (fuera del %)», así que un supervisor limpiándole los números a su vendedor se nota desde arriba. Requiere `gen:types`. **Auditoría `auditor-rls`: NO-GO → corregido.** **A1 (ALTO), y es el hallazgo que cambia el despliegue: ⚠️ ORDEN OBLIGATORIO FRONT → MIGRACIÓN.** El contrato del front es `v.strictObject` y `v.optional` SOLO aplica a claves DECLARADAS: una clave que el esquema no conoce hace fallar la validación entera, así que `canceladas_ajenas` contra el bundle viejo (`index-CwKxqxW2.js`, que no la declara) no degrada el panel «Agenda del equipo» — lo MATA, para supervisor y gerencia. El orden inverso sí es seguro (front nuevo + BD vieja = clave ausente = opcional). Corrige además una afirmación FALSA que esta misma tabla dejó escrita en la fila de `20260726151751` («ninguno de los dos órdenes rompe el panel»): allí se acertó el orden, no se garantizó. **A2 (ALTO) descartado con evidencia:** pedía un cast defensivo por no conocerse el DDL de `public.audit_log` (vive en el portal); se verificaron los tipos CONTRA PROD y quedan escritos en la migración — `usuario_id` es **uuid** (de ahí la asignación sin cast) y `fila_id` es **text** (de ahí el `t.id::text`). **M1 (MEDIO):** faltaba cobertura; se añadieron 8 aserciones al gate vivo `test-rls.mjs` (firma propia = vendedor, el caso central supervisor→ajena, inyección de `cancelada_por_id` por PATCH como no-op silencioso, sistema sin firma, y la invariante global «ninguna anulación de asesor sin firma», que es la garantía que el CHECK permisivo deja fuera) y 2 a `test-metricas-agenda.sql` (la clave presente + `ajenas ≤ asesor`). **M2 (MEDIO):** el denominador solo puede ENCOGER, así que un vendedor con 2 cierres, ambos anulados por su jefe, pasa de `0 %` a `null` — correcto, pero su «—» era idéntico al de quien no registró nada; resuelto pintando el desglose cuando no hay porcentaje pero sí algo que explicar. **B1** cubierto por la invariante del gate; **B2** (no se exporta `canceladas_propias`, el front la reconstruye por resta con suelo en 0) aceptado a sabiendas para no ampliar la superficie del `strictObject`; **B3**: si alguna vez se purga `public.audit_log` (hay precedente en el portal) las anulaciones históricas se quedarían sin firma y la métrica las trataría como AJENAS — cae del lado que no castiga, pero puede subirle el % a alguien sin explicación visible. | ✅ **EN PROD** (merge 2026-07-27, reescrita por Supabase como `20260727034525`; el archivo es `20260727032429`). Branch `crm-anular-ajena` borrado. **Verificado en prod tras el merge**: columna `uuid`, CHECK con la forma `CASE`, **0** FKs a `public`, **0** índices nuevos, **0** anulaciones huérfanas, **0** triggers quedados en `disable`, y EXECUTE de `cerrar_tarea` y `metricas_agenda_fn` intactos. **Backfill: 3 filas, las 3 recuperadas del historial y atribuidas a MIGUEL BRICEÑO sobre SUS PROPIAS tareas** → quedan «PROPIA (le cuenta)», o sea que a nadie se le movió el % hacia atrás. **Orden respetado**: front desplegado ANTES (`index-BWkvzFVX.js`, release `crm-20260727T044929Z-cc30375d6975`) y el merge después; durante la ventana intermedia prod siguió respondiendo con normalidad, que es justo lo que el orden garantiza. Antes del merge estuvo APLICADA Y VERDE en el branch: Oráculo nuevo `supabase/scripts/test-anular-ajena.sql` (éxito = token `AJENA_TX_OK`; V01–V15: el CHECK mirado como candado Y contra el motor, la firma inyectada por INSERT y por UPDATE, la anulación propia / la del jefe / la del sistema, la aritmética del % en los tres casos, que el supervisor no se cobre a sí mismo la tarea ajena que anuló, y el ACL de la columna). **Los CUATRO oráculos en verde**: `AJENA_TX_OK`, y de regresión `ANULAR_TX_OK`, `TAREAS_TX_OK` y `METRICAS_AGENDA_TX_OK`. **Advisors sin clases nuevas** (seguridad y rendimiento; la migración no crea índices ni FKs, así que no puede introducirlas). Lo aplicado se verificó **byte a byte** contra este archivo: md5 de `prosrc` idéntico en las tres funciones. Verificado además en el branch: columna `uuid`, el CHECK con la forma `CASE`, **0** FKs a `public`, **0** índices nuevos, EXECUTE de `metricas_agenda_fn` y `cerrar_tarea` intactos, y **0** triggers quedados en `disable` tras el backfill. Front: 1032 vitest · 63 e2e · lint y typecheck limpios; `database.types.ts` actualizado a mano (archivo CURADO: `cancelada_por_id` va solo en `Row`, el front nunca la escribe). **HALLAZGO COLATERAL, y es deuda de ayer:** `test-metricas-agenda.sql` llevaba roto desde `20260726151751` sin que nadie lo supiera — siembra sus fixtures con `session_replication_role = replica`, así que el BEFORE no sellaba `cancelada_por`, pero el CHECK que esa migración añadió sí la exige, y el oráculo reventaba en los FIXTURES antes de la primera aserción. No se detectó porque aquel ciclo no lo re-corrió. Arreglado aquí dando la columna a mano en el INSERT, con la lección escrita en el propio archivo: **apagar los triggers apaga los SELLOS, no las RESTRICCIONES**. **GATE RLS VIVO: 355/355, cero fallos** (347 antes + 8 nuevas), corrido por Miguel contra la rama. Las 8 salen nombradas en el log, incluida la que define el cambio: «firma != dueño de la tarea: la metrica la clasifica como AJENA y la saca del % del vendedor». ⚠️ Costó dos intentos por algo que NO es de esta migración y que ahora está documentado en `supabase/scripts/LEEME.md`: **el gate NO es re-ejecutable sobre la misma base** — sus fixtures transitorios nacen con `randomUUID()` y el teardown solo los DESACTIVA, así que la 2ª corrida se encuentra los de la 1ª y las dos aserciones que cuentan filas (`directorio ve N lead(s)` y su gemela de conjunto exacto) fallan por acumulación: dieron 2/355 con 7 demo + 23 residuos = 30 vistos. Se limpió la rama (el ledger `crm.lead_asignaciones` va primero por FK RESTRICT y con DOS triggers apagados por nombre, incluido el de inmutabilidad) y la 3ª corrida salió limpia. FALTA, en ESTE orden: **desplegar el FRONT** (`/release-crm`, solo Miguel) → merge → borrar el branch. |

Oráculo: `supabase/scripts/test-tenencia.sql` (éxito = token `TENENCIA_TX_OK`;
V01–V30: alta con y sin dueño, orden de disparo del trigger, parkeo, LA
ASIGNACIÓN sobre un lead envejecido 3 días, invariancia del SLA del cliente,
igualdad exacta con el ledger en cada camino, inmunidad al ruido, transferencia,
CIERRE que apaga el reloj, REAPERTURA que lo estrena, infalsificabilidad desde
una sesión `authenticated` real y el estado honesto de los grants).
⚠️ El oráculo NO asevera "el reloj avanzó" entre dos operaciones:
`statement_timestamp()` no avanza dentro de un batch (MCP/simple-query), donde
heredar y re-sellar dan el MISMO valor — sería falso rojo bajo MCP y falso verde
bajo psql. En su lugar asevera que la columna sigue al EPISODIO ABIERTO (fila
nueva en el ledger). El avance estricto se asevera en `testTenencia` de
`test-rls.mjs`, donde cada llamada PostgREST es su propio statement.
Aserciones vivas en el gate: bloque `testTenencia` (vía PostgREST real): lectura
del reloj por su dueño, asignación que arranca el reloj HOY sobre un lead de la
bandeja, intento de falsificación que responde OK y NO cambia nada, edición que
no lo reinicia, y ámbito ajeno sin fila.

### ⚠️ La migración por sí sola NO alcanzaba: el bug del índice de actividad

Una auditoría de completitud (2026-07-25, 35 agentes con refutación adversarial;
4 hallazgos confirmados de ~30 levantados) descubrió que `tenencia_desde` era
**código muerto en producción**, por un bug PREEXISTENTE en el front:

`colaDe` metía un lead en el bucket `sin_responder` solo si **no tenía NINGUNA
actividad**. Pero cada movimiento de tenencia escribe una actividad automática
`reasignacion` — la emite `private.trg_leads_reasignacion` en el servidor y la
copia optimista del store en el cliente. Resultado: **todo lead que pasaba por
el circuito Rosa → supervisor → vendedor salía de la cola en el instante mismo
en que se asignaba**, porque llegaba con su `reasignacion` puesta. La etapa
`nuevo` no cae en ningún otro bucket, así que desaparecía por completo:

- el vendedor veía «Al día ✦ sin pendientes» sobre un lead que nadie llamó;
- el cronómetro de speed-to-lead (que solo se pinta para `sin_responder`) nunca
  se renderizaba, así que `tenencia_desde` no llegaba a usarse jamás;
- `diasEnEspera` = `max(última actividad, tenencia_desde)` comparaba dos valores
  IDÉNTICOS al microsegundo (la `reasignacion` y el sello comparten el
  `statement_timestamp()` del mismo UPDATE) → el `max()` era un no-op;
- el KPI «Nuevos sin responder» del supervisor y la columna «Sin tocar» de
  Equipo marcaban 0 en verde para siempre.

Verificado en prod: el 100% de las filas de `crm.actividades` eran
`reasignacion`/`cambio_etapa` — jamás se había registrado un contacto humano.

**Fix** (`app/src/lib/tipos.ts` + `inteligencia.ts`): `TIPOS_CONTACTO_K` como
LISTA BLANCA —espejo exacto del índice `crm.actividades_contacto_episodio_idx` y
de `private.metricas_sla_global_core`, no una regla inventada— e
`indexarUltimoContacto()`. La cola y `sinTocar` miden CONTACTO; el timeline de
la ficha y todo lo rotulado «Última actividad» siguen midiendo actividad a
secas. `colaDe` perdió el parámetro `indicePrevio`: los dos índices comparten
tipo (`IndiceUltimaActividad`), nada impedía pasar el equivocado y el compilador
no diría nada — esa ambigüedad es justo lo que mantuvo el bug vivo.
`nota` queda FUERA del contacto por decisión de Miguel: escribir una nota
interna no es haber hablado con la persona.

Los dos cambios se necesitan MUTUAMENTE: arreglar el índice sin `tenencia_desde`
habría devuelto el rojo injusto por la puerta de atrás (el lead reaparecería en
la cola midiendo desde `creado_en`).

## El cliente no puede QUEDAR sin cuenta bancaria — trigger en perfiles (2026-07-28)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260728044338 | crm_perfiles_cuentas_no_vaciar | **Cierra la última puerta del blindaje bancario del 2026-07-27.** Las edges (`crear-cliente` v24, `crm-convertir-lead` v6) ya garantizan que el cliente NACE con al menos una cuenta, pero la pantalla «Corregir» del CRM es un UPDATE crudo a `public.perfiles` bajo RLS: el asesor creador (ventana 5 h de `perfiles_analista_update`) — o el propio cliente sobre su fila — podía VACIAR las 14 columnas y dejar un cliente real al que pagos no puede transferir. ⚠️ **TOCA `public.perfiles` (portal en prod) con OK EXPLÍCITO de Miguel (2026-07-27, chat: «si al trigger»)** — excepción consciente a la regla «ninguna migración toca public». Función `public.perfiles_cuentas_no_vaciar()` (plpgsql, `search_path='public','pg_temp'` como sus hermanas de perfiles, invoker: solo lee OLD/NEW) + trigger `trg_perfiles_cuentas_no_vaciar` **BEFORE UPDATE OF banco, numero_cuenta, banco_usd, numero_cuenta_usd** (un UPDATE de teléfono/nombre ni ejecuta la función). Regla ÚNICA: si `OLD.rol='cliente'` Y tenía al menos una cuenta (banco+n° de UNA moneda) Y el NEW no conserva ninguna → `raise exception` P0001 con mensaje en claro. **Es un TRIGGER de transición y no un CHECK a propósito**: las filas legacy sin cuenta siguen válidas y editables (grandfathering). Editar/corregir/cambiar de banco/quitar UNA moneda con la otra viva: TODO sigue permitido — lo pidió Miguel textual («el asesor debe poder editar esto durante esas 5 horas»). Aplica a TODOS los roles incluido service_role: las edges solo INSERTan y ningún flujo legítimo vacía todo; si el import (`importar-clientes`) alguna vez intentara blanquear, MEJOR error ruidoso que cliente mudo sin cuenta. «Tiene cuenta» = banco + numero_cuenta (lo mínimo transferible); CCI/tipo fuera de la definición por el legacy parcial. Gate: +6 aserciones en `test-rls.mjs` (sección bancaria): service_role vaciando todo → P0001 (la prueba dura: ahí no hay RLS, solo el trigger frena), el cliente vaciándose a sí mismo → bloqueado, full→full permitido y restaurado, quitar solo USD permitido y restaurado. Sin columnas nuevas → sin grants nuevos, sin `gen:types`, sin cambio de front (el mensaje del trigger ya viaja por `actualizarClientePortal` → `aErrorApi`). Orden de despliegue: SERVIDOR solamente (no hay clave nueva en request ni response). | ✅ **EN PROD (2026-07-31, ciclo completo con OK de Miguel «dale el merge»)**. Historia: auditoría `auditor-rls` NO-GO → corregido (**ALTO real: `''` satisfacía `is not null` y vaciaba sin disparar el freno** → `nullif(btrim(...))` en OLD y NEW) → aplicada en el branch `crm-cuentas-no-vaciar` → oráculo `test-perfiles-cuentas.sql` = `CUENTAS_TX_OK` (14 verificaciones, 2026-07-28) → pausa 3 días por PAT vencido → PAT nuevo de Miguel (2026-07-31) → **gate RLS = 358 aserciones, 0 fallos, aprobado** (incl. service_role vaciando → P0001, bypass `''` → P0001, cliente vaciándose → P0001) → advisors sin clases nuevas → `merge_branch` → **verificado en prod con DO-block transaccional (todo revertido): `VERIF_OK null_bloqueado=t blanco_bloqueado=t full_full_paso=true`**; trigger vivo `BEFORE UPDATE OF` las 4 columnas → branch BORRADO (fin de la facturación US$0.01344/h). ⚠️ Nota: prod registró la migración como versión `20260728050047` (timestamp del apply en el branch), mismo nombre `crm_perfiles_cuentas_no_vaciar` — el archivo del repo sigue siendo `20260728044338_…` y NO se renombra |

## Hardening tras auditoría de advisors (2026-08-01)

Triage completo de las 71 alertas de advisors (47 seguridad + 24 rendimiento) verificado
contra la base real, no solo el reporte. De las 41 RPC SECURITY DEFINER expuestas a
`authenticated`, 40 tienen guardia interna correcta (verificadas una a una: 17 de `public`
leídas completas + 24 de `crm` con pase del `auditor-rls`); la única sin guardia era
`contrato_tiene_pagos`. Diferido a propósito: políticas permisivas múltiples (micro-opt,
riesgo > beneficio), 15 índices "sin uso" (features recién estrenadas, re-mirar en octubre),
estrategia de conexiones Auth (solo importa al subir de instancia). `crm.lead_asignaciones`
con RLS sin policies es intencional (deny-all, solo RPCs definer). HIBP queda del lado de
Miguel (toggle del dashboard).

**Deuda registrada por el auditor-rls (2026-08-01), NO bloqueante de este ciclo:**
1. **Drift prod↔repo**: ~11 objetos `crm` (la vista `contratos_cartera` y sus `_fn`,
   `equipo_visible_fn`, `actividades_del_ambito_fn`, `convertir_lead`, las 4 `metricas_*_fn`)
   viven en la historia de migraciones de prod (el branch los replica bien — verificado) pero
   NO existen como archivo en el repo: un replay limpio desde el repo no los recrea, y
   `clientes_basicos` del repo (20260711000003) se creó `security_invoker=true` pero alguien
   la recreó en prod sin el flag (por eso reapareció el ERROR del linter). Versionarlos
   as-built cuando se toquen. **Avance 2026-08-08:** `actividades_del_ambito_fn` reconciliada
   as-built en `20260808163618` (quedan ~10 objetos en drift).
2. **Flags de activo desalineados**: `private.rol_crm` y `vendedor_ids_visibles` solo miran
   `crm.equipo.activo`; un miembro desactivado SOLO en el portal (`perfiles.activo=false`)
   conserva acceso en ~12 de las 24 funciones (las otras 12 exigen ambos flags). Unificar
   (que `rol_crm` exija también `perfiles.activo`) o clavar por procedimiento que el
   offboarding apaga ambos; añadir el caso mixto a la matriz. El fixture `vendInactive`
   apaga los dos a la vez y no cubre el caso.

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260801092924 | crm_hardening_advisors_vistas_pgnet | **(a)** `crm.contratos_cartera` y `crm.clientes_basicos` a `security_invoker = true`: **restaura el patrón aprobado en F0** (20260711000003/000004: función definer gateada + vista invoker, el que mata el ERROR `security_definer_view`); las vistas se habían recreado sin el flag y el ERROR reapareció. Sin cambio de filas visibles: la autorización vive en las `*_fn()`. **(b)** ⚠️ **TOCA `public` con OK explícito de Miguel (2026-08-01, chat: «dale, aplica la migración» tras propuesta detallada)**: `contrato_tiene_pagos` ahora exige `puede_ver_contrato` — era la única RPC expuesta sin guardia; cualquier authenticated (incl. clientes del portal) podía sondear pagos de contratos ajenos por UUID. Devuelve `false` sin excepción → el único llamador (`public_html/js/admin/contratos.js:1422`, pantalla admin) no cambia. Consecuencia clavada en el gate: service_role SIN JWT también recibe `false` (la RPC es para humanos logueados). **(c)** REVOKE de `pg_net` a `anon`/`authenticated`/PUBLIC — ⚠️ **NO-OP en Supabase gestionado** (hallado al verificar en el branch): los grants son de `supabase_admin` y `postgres` no puede revocarlos (ACL intacto tras el revoke). Los statements quedan como declaración de intención (aplican en shadow/CI con superuser). Mitigación real: `net` fuera de los Exposed schemas de la API (config de plataforma — **check visual de Miguel en dashboard**) + los 2 jobs pg_cron que sí usan `net.http_post` (`recordatorio-cuotas-3d`, `ciclo-contratos-diario` — hallazgo del auditor; mi escaneo de `pg_proc` no veía `cron.job`) corren como `postgres`, verificado en `cron.job.username`. **(d)** 3 índices FK (`contratos.cerrado_por`, `contratos.renovado_a_id`, `contrato_titulares.creado_por`). Gate: +6 aserciones nuevas en `test-rls.mjs` (sección bancaria: sonda de pagos dueño/ajeno/service_role con cuota transitoria restaurada). | ✅ **EN PROD (2026-08-01, ciclo completo)**. Historia: auditor-rls sobre el dump de prod (24/24 funciones crm CON guardia; 3 hallazgos accionables, todos resueltos antes del merge) → aplicada en branch `crm-hardening-advisors` → verificación conductual por SQL en el branch (dueño=true / ajeno=false / actor nulo=false; vistas invoker 0 filas para extraño; **policy DELETE probada en vivo con admin fabricado: con pagos el contrato sobrevive, sin pagos se borra**) → advisors del branch: los 2 ERROR muertos, sin clases nuevas → **gate RLS = 363 aserciones, 0 fallos** (355 previas + 8 nuevas; PAT del keychain con permiso explícito de Miguel en settings.local.json) → `merge_branch` (asíncrono: `RUNNING_MIGRATIONS` ~90 s) → verificado en prod: vistas invoker=2, guardia viva, 3 índices, migración registrada, **paridad exacta** (vendedor 28/27, gerencia 270/245), vendedor sondeando contrato ajeno pasó de `true` a `false` y el cliente dueño conserva `true` → advisors de prod: los 2 ERROR muertos → branch BORRADO (fin de US$0.01344/h). Quedan del lado de Miguel: toggle HIBP + confirmar `net` fuera de Exposed schemas (dashboard) |

## Disponibilidad de leads y offboarding canónico (2026-08-03)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260801212050 | p047_enfriamiento_politica_y_rpc_disponibilidad_lead | Tabla de política de enfriamiento, reglas por motivo y RPC consultiva `crm.verificar_disponibilidad_lead`. | ✅ **EN PROD** |
| 20260801212300 | p047b_grants_enfriamiento_politica | ACL explícitas de la política de enfriamiento. | ✅ **EN PROD** |
| 20260801222231 | p047c_estado_en_bolsa_rpc_disponibilidad | Añade el estado `en_bolsa` a P-047 sin alterar sus demás estados. | ✅ **EN PROD** |
| 20260803164348 | crm_offboarding_gate_activos | **P04 — offboarding seguro del CRM.** Un actor humano solo conserva acceso cuando `public.perfiles.activo` y `crm.equipo.activo` están ambos activos. `private.rol_crm` usa allowlist fail-closed; el fallback global solo existe sin fila de equipo; una fila inactiva prevalece. Añade gate RLS RESTRICTIVE a las 8 tablas, `crm.mi_acceso_fn()` para que la app distinga ausencia de revocación, wrapper gateado de P-047 con cuerpo comercial privado idéntico, validación de destinos incluso ante `service_role`, rotación irreversible del token ICS al apagar equipo y feed ICS atómico. Las Edges excluyen destinos/asesores parcialmente inactivos; el ciclo toma el snapshot antes del claim y Web Push se inicializa solo si habrá envío. No contiene DDL sobre `public`. | ✅ **EN PROD 2026-08-03, SERVIDOR Y FRONT** — Supabase la registró como `20260803182426`. Branch `p04-offboarding-activos`: PostgreSQL local `P04_POSTFIX_VALIDATION_OK`; gate PostgREST **434/434**; `P04_HTTP_SMOKE_OK` (ICS 200/404 + rotación, importador activo/inactivo, ciclo `dry_run` + admin revocado); advisors sin clase inesperada y −2 warnings `auth_rls_initplan`; merge verificado con 8/8 gates, ACL y MD5 P-047 `c54b0bae7b6d456dbcf3a376f8987d9f`; Edges en prod `crm-agenda-ics` v3 (`verify_jwt=false`), `crm-importar-leads` v9 (`true`) y `ciclo-contratos` v4 (`false`), fuentes exactas; rama borrada. Front publicado tras la invocación humana de `/release-crm` y verificado contra el manifiesto. |
| 20260804165440 | crm_creacion_lead_atomica | **P-048 — alta manual atómica respecto de los escritores de `crm.leads`.** `crm.crear_lead_si_disponible(...)` toma advisory locks transaccionales y deterministas por teléfono/DNI, reejecuta el cuerpo canónico de P-047 después de esperar y solo inserta si el contacto sigue `libre`; `p_id` conserva la identidad optimista y hace idempotente el reintento inmediato del mismo payload mientras la fila no haya recibido otra mutación de negocio. La RPC es `SECURITY DEFINER`, replica P04/ámbito/destino, deriva autor y bandeja, devuelve únicamente el veredicto discriminado y tiene `EXECUTE` solo para `authenticated` (`anon` y `service_role`, fuera). Un cuerpo privado único de P-047 admite excluir la fila que se edita. Dos triggers legacy comparten las llaves con INSERT y cambios relevantes de `crm.leads`: una sesión humana que todavía use INSERT directo recibe el veto P-047, no puede cambiar teléfono/DNI hacia una identidad bloqueada ni mudar los datos de su propia fila mientras porte `no_contactar` o enfriamiento vigente; el importador sin sesión comparte la serialización pero conserva su semántica especializada. El precheck de P-047 permanece como UX y puede degradar por transporte; la autoridad final es la RPC. **Fronteras deliberadas:** no toca `public`, por lo que un alta o cambio de identidad de `public.perfiles` exactamente concurrente aún puede competir con la lectura `ya_es_cliente`; el importador permite reingresos que la política manual bloquea. El `GRANT INSERT` directo de `authenticated` se mantiene durante adopción por compatibilidad: su revocación se hará en una **segunda migración posterior al despliegue/adopción**, tras comprobar que no sobreviven bundles/clientes antiguos. Oráculo autocontenido `test-creacion-lead-atomica.sql`: ACL públicas/privadas, validaciones, estados, idempotencia, UPDATE de identidad —incluidos vetos propios— y carreras reales por teléfono, DNI, rollback, INSERT legacy y revocación P04 mientras se espera, mediante `dblink`; termina con código 0 y el token `CREACION_LEAD_ATOMICA_TX_OK`. | 🧪 **SOLO LOCAL — ARCHIVO AÚN NO APLICADO NI DESPLEGADO EN PRODUCCIÓN** |

El advisor de seguridad añade la advertencia esperada
`authenticated_security_definer_function_executable` para `crm.mi_acceso_fn()`:
es intencional porque la app necesita consultar su propio estado. La función no
acepta UUID de entrada, deriva y devuelve `auth.uid()`, valida ambos flags y la
app liga la respuesta al UUID obtenido por `getUser()`. `anon` y
`service_role` no tienen `EXECUTE`. Referencia del linter:
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

P-047 conserva exactamente su contrato consultivo y sigue alimentando el feedback
temprano del formulario. P-048 no lo convirtió en escritor: añadió una RPC separada
que reutiliza su cuerpo privado dentro de la transacción de alta. Los índices únicos
continúan como última defensa; la decisión final del alta manual ya no depende del
precheck del navegador sino de la RPC y de los triggers de serialización de
`crm.leads`. Esta ampliación continúa únicamente local hasta completar sus gates.

Front P04 publicado el `2026-08-03T19:10:44Z` mediante la invocación humana
obligatoria de `/release-crm`: release `crm-20260803T185343Z-f1e6042fbefb`,
ZIP SHA-256 `fe93128613fbc35690b054060a5f48d92e7fb81f6d9ef60a5679f65212705a95`.
Producción sirve `assets/index-CfihSZSH.js` (SHA-256
`7dfc133761614c833af61b0014da32c19029e0169556b5578f3cb773bb8919f2`):
HTML, código, CSS, SVG y demás recursos coinciden byte por byte; Hostinger
recomprime los cuatro PNG de marca conservando el payload de píxeles. El ZIP,
fuentes, migraciones, sourcemaps, `.env` y `package.json` no son públicos.

## Cuentas bancarias versionadas por contrato (2026-08-03)

| Version | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260803221622 | crm_cuentas_bancarias_por_contrato | Agrega `crm.cuentas_bancarias` como historial inmutable/versionado y `crm.contrato_cuentas_pago` como vínculo único por contrato. El alta atómica permite elegir una cuenta guardada, fotografiar la cuenta vigente del perfil o registrar una nueva; un snapshot optimista y locks por cuenta cierran carreras. Las tablas permanecen sin acceso directo para sesiones humanas; RPCs gateadas listan cuentas de cartera, crean/corrigen contratos y entregan a Pagos solo la cuenta contractual. Contratos anteriores conservan fallback explícito al perfil; una incoherencia cliente/moneda bloquea el desembolso. No añade verificación bancaria ni modifica objetos de `public`. | ✅ **Producción** 2026-08-03. Branch efímera `frhfezxzdhnhrjiddrzn`: gate RLS 453/453, advisors sin nuevos errores ni WARN de rendimiento; fusionada y eliminada. |
| 20260804144555 | crm_p04_gate_cuentas_bancarias | Restablece la invariante P04 en todas las rutas bancarias del esquema `crm` añadidas después del offboarding: `private.puede_gestionar_cuentas_cliente` exige el gate vivo para todo actor; el wrapper de corrección resuelve y autoriza también contratos legacy sin enlace; Pagos exige admin **y** acceso CRM vivo. El analista conserva además el alcance de cartera; el admin sin fila de equipo conserva el fallback global, pero una membresía CRM revocada prevalece también sobre su rol del portal. Helpers internos sin `EXECUTE` directo para roles API. **Frontera consciente:** no cambia `public.crear_contrato` ni `public.actualizar_contrato`; migrar/retirar el alta administrativa legacy es una decisión separada. | ✅ **Producción 2026-08-04** (Supabase la registró como `20260804154054`). Branch efímera `p04-bank-gate-20260804` (`btzuomyfcjabiiybiidu`): oráculo autocontenido `P04_BANK_GATE_TX_OK` con 23 verificaciones y gate PostgREST **475/475**, incluidas las cuatro RPC, contrato enlazado y legacy, estados mixtos, admin activo/revocado/global y ACL anon. Advisors sin errores ni clases nuevas de seguridad; los tres hashes de definición y todas las ACL coincidieron entre branch y producción tras el merge. Branch fusionada y eliminada. |

## Inteligencia comercial, metas y ranking gerencial (2026-08-06)

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260805180000 | 20260805180000 | crm_inteligencia_comercial_reuniones | ✅ Producción. Contrato global de conversiones/reuniones y campos auditables de reunión. |
| 20260805200000 | 20260806160412 | crm_conversion_vendedor_detalle | ✅ Producción. Añade responsables, capital PEN/USD y tendencia semanal a la RPC gateada de Gerencia. `anon` sin `EXECUTE`; smoke real con 16 responsables. |
| 20260805213000 | 20260805211322 | crm_objetivos_por_vendedor | ✅ Producción. Metas mensuales individuales; la meta organizacional se deriva. RLS activa y escrituras por RPC exclusiva de Gerencia. |

Supabase reescribió dos timestamps al fusionar/aplicar. Es el patrón normal del
proyecto: los archivos locales conservan sus versiones originales y las
equivalencias remotas viven en este ledger. No ejecutar `supabase db push
--include-all` para intentar igualar el historial global, que tiene drift
deliberado.

Frontend publicado como release `crm-20260806T162840Z-a0ba40c3cad5` (SHA-256
`e3c411e10cb45e15069f6c64da50d8e09004bc135f08f799a49ccfb5ae542245`). Incluye
detalle compacto por vendedor y la vista `#/ranking-vendedores`, escalable al
equipo completo, con ranking por conversión y por cumplimiento de meta de
capital PEN. USD permanece separado. Validación final: 1,208 pruebas, lint,
typecheck y build verdes; assets principales verificados byte a byte en
`crm.miavance.com` y ZIP público 404.

## Gerencia operativa global (2026-08-07)

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260807123000 | 20260807180637 | crm_gerencia_operativa | ✅ **EN PRODUCCIÓN 2026-08-07**, con confirmación explícita de Miguel después de revisar el SQL. Retira el veto transversal de solo lectura y habilita a Gerencia activa para operar globalmente leads, actividades, tareas/reuniones, conversión, corrección acotada de clientes, banca y contratos. No la convierte en admin/superadmin del portal. Directorio sigue en lectura; no se abre hard-delete; la conversión exige analista asignado y conserva su atribución; contratos renovados/retirados siguen cerrados salvo superadmin. |

La migración es transaccional y pasó el oráculo autocontenido
`supabase/scripts/test-gerencia-operativa.sql` (`GERENCIA_OPERATIVA_TX_OK`),
incluidos negativos de UPDATE crudo a perfiles, inyección de campos, perfil
staff, actor analista, tarea asignada fuera del equipo, contrato cerrado y
DELETE físico. Verificación remota: función/3 triggers del veto ausentes; cuatro
policies operativas `TO authenticated` con rama Gerencia; nuevas RPC y contratos
sin EXECUTE para `anon`; `authenticated` conserva únicamente las puertas
gateadas. El advisor reporta la clase esperada
`authenticated_security_definer_function_executable` para la RPC nueva: es
intencional, porque `crm.actualizar_cliente_gerencia` valida Gerencia CRM viva,
acepta solo la allowlist del formulario, preserva rol/activo/asesor/autoría y
sella `actualizado_en` en servidor.

Orden de despliegue completado: migración → `crm-convertir-lead` v8 y
`crear-cliente` v26 (`verify_jwt=true`) → frontend release
`crm-20260807T182333Z-ea53f103ab2c` (ZIP SHA-256
`0db76d72defed2e2be33d8da95e8b2ad08bb5e2546e974b0dfe3aef199ff994c`).
Producción sirve `index-mxMTOI1H.js`; HTML y chunks críticos coincidieron byte a
byte, el asset previo y el ZIP responden 404. Smoke autenticado real con CARLOS
VALLES mostró operaciones globales de Cartera y el formulario «Corrección
autorizada por Gerencia», sin guardar datos y con consola limpia.

## Configuración operativa versionada (2026-08-08, producción)

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260807203740 | 20260808160113 | crm_usuarios_jerarquia_autoservicio | ✅ **PRODUCCIÓN.** Añade el contrato de administración de personas y jerarquía: Gerencia crea/edita, activa o desactiva la membresía CRM, organiza la estructura y solicita recuperación; Superadmin Portal conserva en exclusiva la asignación/cambio de `rol_crm`. Agrega `directorio`, auditoría `crm.usuario_eventos`, validación de ciclos/compatibilidad y transferencias atómicas con control optimista. Edge `crm-usuarios` v1 activa con `verify_jwt=true`. |
| 20260807203751 | 20260808160129 | crm_catalogo_productos_versionado | ✅ **PRODUCCIÓN, BRIDGE ABIERTO.** Crea producto estable, versiones y condiciones normalizadas; publica/retira de forma inmutable e integra `public.contratos.producto_condicion_id` con 325 snapshots históricos exactos, FK `ON DELETE RESTRICT` y wrappers de alta/corrección. Gerencia administra el catálogo. `permite_altas_legacy=true`, revisión 1, mientras no exista el primer producto real publicado. |
| 20260807203757 | 20260808160137 | crm_metas_sla_versionados | ✅ **PRODUCCIÓN.** Sustituye los dos modelos antiguos de metas por publicaciones append-only por vendedor, categoría y moneda, con revisión optimista; separa `contratos_confirmados` de `leads_resueltos`. Versiona políticas SLA y sella política/deadlines por ciclo, asignación y etapa. Los archivos legacy quedan inmutables y sus writers antiguos se retiran. |
| 20260807235933 | 20260808160148 | crm_portal_catalogo_productos | ✅ **PRODUCCIÓN.** Publica selector y wrappers catalogados para Admin/Analista, corrige el alcance Portal/CRM, exige interés compuesto anual por años completos e impide cerrar el bridge si faltan callers o una condición publicada. El cierre es irreversible y todavía no se invocó. |

Oráculos transaccionales dedicados, todos con rollback y sin aplicar estado
remoto:

- `supabase/scripts/test-usuarios-jerarquia.sql` →
  `USUARIOS_JERARQUIA_TX_OK`.
- `supabase/scripts/test-productos-inversion.sql` →
  `PRODUCTOS_INVERSION_TX_OK`.
- `supabase/scripts/test-metas-versionadas.sql` →
  `METAS_VERSIONADAS_TX_OK`.
- `supabase/scripts/test-sla-versionado.sql` → `SLA_VERSIONADO_TX_OK`.
- `supabase/scripts/test-metricas-distribucion-leads.sql` →
  `METRICAS_DISTRIBUCION_TX_OK`.

Gate local final en PostgreSQL 16 desechable: replay limpio de
`203740 → 203751 → 203757 → 235933`, cinco tokens SQL verdes, app
1,404/1,404 con cobertura, typecheck, lint y build, Portal 50/50, Edge Usuarios
10/10 y Edge Importador 3/3. Los advisors posteriores no mostraron errores de
seguridad. Supabase confirmó las cuatro migraciones y sus objetos en producción.

El frontend local ya abre los cuatro módulos desde Configuración. El riel
operativo consulta solo los dominios autorizados y resume personas, catálogo,
metas y SLA. El modo demo usa fixtures validados por los mismos contratos
estrictos, rechaza escrituras antes de la API y tiene recorrido E2E de las cuatro
tarjetas para Gerencia y Directorio con cero solicitudes a Supabase.

**Único gate funcional abierto:** CRM y Portal ya están desplegados con callers
catalogados, pero producción tiene cero condiciones no legacy seleccionables.
Debe publicarse el primer producto comercial real, repetir el smoke y recién
entonces ejecutar `crm.cerrar_altas_legacy_productos(1)`. Mientras eso no ocurra,
el bridge queda abierto y no se declara el cierre integral irreversible.

## Índices de lectura de la cartera (2026-08-08, solo local)

Preparación del terreno para que la cartera de leads soporte volumen grande.
Nace del diagnóstico de escalabilidad del 2026-08-08: `listarLeadsDelAmbito`
trae un máximo de 2000 leads ordenados por `actualizado_en desc` **sin ningún
índice que cubra ese orden**, y la búsqueda por nombre/teléfono/DNI usa
`ilike '%…%'` con `pg_trgm` instalado pero sin un solo índice que lo aproveche.

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260808155128 | 20260808170231 | crm_indices_lectura_cartera | ✅ **EN PROD 2026-08-08** (branch crm-f0-escalabilidad → gate 521/521 → advisors sin ERROR → merge; branch borrado). Solo agrega índices: orden de cartera `(actualizado_en desc, id)`, compuesto `(vendedor_id, actualizado_en desc)`, tres GIN trigram para la búsqueda (nombre, teléfono, DNI) y la FK de `enfriamiento_politica` (advisor 0001). ⚠️ Reescrita el mismo día ANTES de aplicarse (permitido: aún sin commit ni aplicar): las 3 FK de `objetivos_vendedores` que también reportaba el advisor murieron cuando la migración de metas versionadas (aplicada en prod 2026-08-08 16:01 UTC por otra sesión) archivó esa tabla; el modelo nuevo nació indexado. No toca policies, funciones, grants, columnas ni datos; ningún objeto de `public`. |

Decisiones que conviene no volver a discutir:

- **El índice de orden NO es parcial a propósito.** Un `where activo = true`
  sería más chico, pero `listarLeadsDelAmbito` no envía ese predicado (confía en
  la RLS) y `leads_select` lo tiene dentro de un `OR` con `es_lector_global()`,
  de donde el planner no puede deducirlo. Con índice parcial, justo la consulta
  que hoy tiene el techo de 2000 se quedaría sin usarlo.
- **No se elimina ningún índice.** El advisor marca varios como no usados, pero
  `crm.tareas` y `crm.actividades` tienen 0 filas y `crm.leads` tiene 1: "nunca
  escaneado" a ese volumen no prueba inutilidad. La poda se decide con tráfico
  real, no con estas estadísticas.
- **`create index` sin CONCURRENTLY** porque las tablas están prácticamente
  vacías. Si esto se replicara contra una base poblada, hay que sacarlo de la
  transacción y usar `concurrently`.

Pendiente del ciclo obligatorio: branch de Supabase → aplicar → `test-rls.mjs` →
advisors → merge. No ejecutado en esta sesión.

## F0 de escalabilidad: as-built + ventana de actividades (2026-08-08)

Contexto en el vault: «Plan de escalabilidad del CRM a data gigante» (F0).
`actividades_del_ambito_fn` era la ÚNICA lectura del CRM sin techo y además
vivía SOLO en producción (drift documentado arriba). Decisión de convertidos
cerrada por Miguel el 2026-08-08: ventana de 45 días (se implementa en F1).

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260808163618 | 20260808170243 | crm_actividades_ambito_asbuilt | ✅ **EN PROD 2026-08-08** (no-op byte a byte verificado por hash md5 antes y después de aplicar). Reconciliación fiel de la función de prod (pg_get_functiondef 2026-08-08 + ACL real `{postgres,authenticated}`). Conserva A PROPÓSITO su search_path legacy y su scoping en WHERE: es reconciliación, no modernización. En prod es no-op byte a byte. |
| 20260808163638 | 20260808170301 | crm_actividades_ambito_ventana | ✅ **EN PROD 2026-08-08** (ventana+límite+índice verificados en prod; ACL intacto). Ventana de seguridad `creado_en >= now()-365d` + `limit 10000` con `order by creado_en desc, id` (si desborda, sobreviven las más recientes — la señal operativa usa la última actividad por lead) + índice `actividades_recientes_idx (creado_en desc, id)` que sirve ese barrido. Firma y retorno idénticos; scoping intacto. La ventana OPERATIVA de 90 días es F4. |

Front acompañante (mismo ciclo): alarma de topes `crm_api.tope_alcanzado` en
las 5 lecturas acotadas (4× MAX_*=2000 + espejo `LIMITE_ACTIVIDADES_AMBITO=10000`),
con 6 tests MSW nuevos. Gate: caso nuevo `testVentanaActividades` (actividad
sembrada a −400 días no viaja para vend1/sup1/gerencia/directorio; la reciente
del mismo lead sí).

Pendiente del ciclo obligatorio: branch → aplicar (155128 → 163618 → 163638) →
seed + gate → advisors → merge. Estados se actualizan al cerrar.

## Reconciliación del gate compartido + prevalencia P04 (2026-08-08)

La corrida F0 fue la PRIMERA corrida completa del gate desde el 2026-08-03: los
ciclos creación atómica (08-04), inteligencia/gerencia (08-05→07) y
configuración operativa/catálogo (08-08) entraron a prod sin pasar la matriz
completa de sesiones reales. Resultado: 14 aserciones desalineadas — 13 de
guion (comportamiento nuevo deliberado que el guion no conocía) y **1 regresión
real de servidor**:

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260808173537 | 20260808173903 | crm_restaurar_prevalencia_p04_banca | ✅ **EN PROD 2026-08-08** (auditor-rls OBSERVADA→condiciones cumplidas; línea P04 verificada en prod). El catálogo (20260807235933) reescribió `private.puede_gestionar_cuentas_cliente` y PERDIÓ el `and private.puede_acceder_crm()` que P04 (20260804144555, gate verde 08-04) exigía antes de todo poder de portal: un analista/admin del portal con membresía CRM REVOCADA recuperaba la banca contractual (PII bancaria). Se reaplica exactamente esa línea sobre la forma vigente (ramas del catálogo intactas). Con las bases de hoy («rol CRM efectivo»), admin/superadmin del portal sin membresía CRM quedan fuera de la banca — coherente con el comment de `es_lector_global`. **Efecto colateral documentado (auditor-rls):** `public.crear_contrato` (canal legacy del portal) es llamador del guard desde el catálogo → el alta legacy queda condicionada a membresía CRM efectiva; verificado en prod: los 20 analistas del portal tienen membresía activa, solo pierden `gloria@` (admin sin fila) y `AdminCorp@` (superadmin) — alineado con el diseño «rol CRM efectivo»; si deben operar, se les da membresía. **Deuda conocida (NO cerrada aquí, tocaría `public`):** la rama admin de `public.actualizar_contrato` no consulta el guard — un admin sin membresía aún corrige TÉRMINOS de contratos (no cuentas); pendiente de OK de Miguel para migración separada. |

Ajustes de GUION de `test-rls.mjs` (misma sesión):
- 3 sondas de tareas aceptan `22023` además de `P0001` (guard reescrito por la
  configuración operativa; mismo bloqueo, código nuevo).
- «sup1 crea un lead que nace asignado» pasa del INSERT directo (revocado desde
  la creación atómica) a `crm.crear_lead_si_disponible` con `p_id`/`p_vendedor_id`.
- El estado «admin global sin membresía CRM» de la matriz bancaria queda
  INVERTIDO al diseño nuevo (banca y Pagos denegados) — deliberado según el
  comment de `es_lector_global`; impacto operativo de la página de Pagos
  anotado en el vault.
- El escenario «tarea pendiente sigue al lead re-encolado» quedó inalcanzable
  (sync de tareas × destino efectivo = 23514): la sonda ahora CLAVA el bloqueo
  atómico. Conflicto documentado en el vault («Conflicto re-encolado vs destino
  efectivo»).
- Sondas de avance de etapa aceptan `23514` (trigger de destino corre antes que
  la policy) y la fabricación por service_role pasa a aseverar que el estado
  gatillo es infabricable.

Deuda que queda ANOTADA (dueño: ciclo de configuración operativa): `seed-demo`
y la matriz P04 de offboarding fabrican estados históricos que el guard de
dependencias (20260807203740) ya no permite escribir; en el branch del gate se
suspende `trg_equipo_validar_usuarios_jerarquia` durante seed+corrida (solo
branch desechable, documentado aquí). Falta una vía sancionada de fabricación
de estados históricos o un rediseño de esos fixtures.


Cierre del ciclo F0 (2026-08-08): gate final **521/521** en branch reseteado
(tercera corrida limpia), advisors de branch y de prod sin ERROR ni hallazgos
nuevos atribuibles, merge verificado objeto por objeto en prod, branch borrado.
`gen:types` ejecutado: F0 no introduce delta de tipos (índices + cuerpo de
función con firma idéntica); el delta grande observado (1145→2879 líneas)
pertenece a la configuración operativa aplicada hoy y su archivo curado — se
dejó intacto para no pisar el trabajo en curso de esa sesión. Front verde:
1410/1410 unit · 73 E2E (38 skipped por sesión real, histórico).

## Meta total por analista + contratos libres (2026-08-08)

La interfaz reduce la configuración a una sola meta mensual PEN por vendedor.
La base conserva las seis dimensiones históricas, pero las publica normalizadas
en `nuevo/PEN`; conversión, contratos y las otras cinco dimensiones quedan en
cero. `crm.cumplimiento_metas_fn` amplía la atribución de contratos confirmados:
lead explícitamente enlazado → autor inmutable del alta, siempre validado
contra el snapshot de vendedores con meta publicado para ese mes. No usa el
asesor actual del cliente porque el offboarding lo reasigna y movería
producción histórica. Así los contratos libres del Portal/CRM dejan de quedar
fuera del cumplimiento sin adjudicar contratos a actores no elegibles.

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260808183527 | 20260808190441 | crm_metas_contratos_libres_atribuidos | ✅ **EN PROD 2026-08-08**. Redefine `crm.cumplimiento_metas_fn` y añade `public.contratos(creado_en)`; firma, ACL, autorización, visibilidad jerárquica y JSON v1 permanecen iguales. Oráculo transaccional `METAS_VERSIONADAS_TX_OK`; gate RLS **521/521**; trigger histórico del fixture reactivado (`tgenabled='O'`) antes del merge; advisors de branch/prod sin `ERROR` ni hallazgos nuevos atribuibles. |

Verificación posterior al merge (solo lectura): agosto tenía 65 contratos
canónicos, 0 con vendedor explícito enlazado, 61 con autor vendedor elegible y
4 fuera de meta individual (supervisores). ACL comprobado: `anon=false`,
`authenticated=true`, `service_role=false`; cuerpo fail-closed e índice exacto
verificados. Los 4 contratos fuera de roster no se reasignan artificialmente a
un subordinado.

Front acompañante: release `crm-20260808T185153Z-6d3bfb75d4d6`, SHA-256 del
ZIP `c01068853df7591b12df07467081f83be29e99a26e230a332fa98386951d0db0`.
Producción sirvió `index-yG0C8pp2.js`, `config-metas-C9BdWeJ8.js` y
`config-sla-DDSk4PR_.js` byte por byte contra el artefacto local.

## P04 distingue revocado de ajeno al CRM (2026-08-09)

Corrección de una regresión que la reconciliación del gate F0 introdujo el mismo
2026-08-08 y que dejó **sin poder trabajar** a personal real del portal.

La migración ORIGINAL de P04 (`20260804144555`, líneas 5-8) declaró por escrito
la semántica pretendida: «Un admin del portal sin membresia CRM **conserva el
fallback global** definido por P04; si tiene una fila en crm.equipo y esa
membresia **se apaga**, la revocacion prevalece». P04 nunca quiso frenar a quien
NUNCA fue del CRM: quiso frenar el OFFBOARDING. Esa distinción se perdió en tres
pasos, ninguno equivocado por sí solo:

1. `20260804144555` escribe `and private.puede_acceder_crm()` cuando
   `es_lector_global()` **aún cubría a admin/superadmin** → el fallback existía y
   el único bloqueado era el revocado. Gate verde 2026-08-04.
2. `20260807203740` («rol CRM efectivo») **estrecha** `es_lector_global()` a
   Directorio con membresía. Nadie lo nota: el catálogo `20260807235933` había
   borrado la línea de P04 del guard, así que el fallback ya no se consultaba.
3. `20260808173537` **repone** la línea sobre esa base estrecha. Correcto en
   intención, pero la composición cambió el sentido: de «bloquea al revocado» a
   «bloquea a todo el que no sea del CRM».

Efecto medido en prod con sesiones simuladas: `gloria@` — admin del portal que da
soporte a los analistas gestionando **Pagos** y creando contratos, sin fila en
`crm.equipo` porque su trabajo vive en el portal — tenía `es_admin()` = true pero
`puede_acceder_crm()` = false, y quedó sin crear contratos, sin corregirlos y sin
la página de Pagos. `AdminCorp@` (superadmin) igual. **Ninguno de los dos está
offboardeado.** Decisión de negocio de Miguel: el offboarding real se hace
eliminando/desactivando el usuario desde administración, y toda función del
portal ya exige `perfiles.activo = true`; la membresía CRM no es ni debe ser el
documento de identidad del personal de portal.

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260809000530 | 20260809002309 | crm_p04_revocado_vs_ajeno_al_crm | ✅ **EN PROD 2026-08-09** (branch `crm-p04-ajeno` → réplica verificada idéntica a prod por hash md5 de las 3 funciones ANTES de aplicar → gate RLS **525/525** → advisors del branch **sin ERROR** (95 avisos, todos de clases preexistentes; la única mención propia es el `WARN authenticated_security_definer_function_executable` ya aceptado de `cuentas_pago_contratos_fn`) → trigger `trg_equipo_validar_usuarios_jerarquia` reactivado (`tgenabled='O'`) antes del merge → merge → verificado en prod → branch borrado). Crea `private.membresia_crm_revocada()` y sustituye el gate `puede_acceder_crm()` por `not membresia_crm_revocada()` en `private.puede_gestionar_cuentas_cliente` y `crm.cuentas_pago_contratos_fn`. Cuerpos copiados VERBATIM de prod salvo esa línea; cero cambios de scoping. |

Verificación posterior al merge (sesiones simuladas, solo lectura):
`gloria@` → banca/contratos **true**, `membresia_crm_revocada` false, y
`puede_acceder_crm()` **sigue false** (no gana ni una tabla `crm.*`: el
`crm_actor_activo_gate` conserva el predicado viejo, como debe ser). Un
`comercial` revocado → detectado revocado **true** y banca **false**: la
invariante de offboarding intacta.

**Delta de autorización, censado en prod (auditoría adversarial previa).** El
cambio es monótono creciente. Como `¬puede_acceder_crm()` implica
`rol_crm() IS NULL`, la rama CRM del guard es inalcanzable dentro del delta ⇒
quien gane algo lo gana por `es_admin()` o `es_analista()`+cartera:

1. **admin/superadmin de portal SIN fila — 2 hoy** (gloria, AdminCorp). Es el objetivo.
2. **analista de portal SIN fila — 0 hoy.** ⚠️ El ledger del 08-08 decía «los 20
   analistas tienen membresía activa»: el conteo real es **19**, y no existe
   ningún analista sin fila. Corregido aquí.
3. **superadmin CON fila ACTIVA de rol ≠ gerencia — 0 hoy. ACEPTADO a propósito**
   (no omisión): `public.es_admin()` incluye a superadmin por diseño DEL PORTAL.
   No contradice `20260807203740:87-89` («queda fuera del gate GLOBAL»):
   `rol_crm()` sigue devolviendo NULL, así que no obtiene ámbito CRM alguno.
4. **perfil con `activo = false` — 0 hoy y CERRADO**: `public.es_admin()` y
   `public.es_analista()` exigen `activo = true` (verificado con
   `pg_get_functiondef` en prod). Clavado además en el gate.

No ganan nada los roles de portal `comercial` ni `directorio`.

**Superficie real:** se reescriben 2 funciones, pero
`private.puede_gestionar_cuentas_cliente` es el gate único de CINCO entradas —
`crm.cuentas_bancarias_cliente_fn`, `crm.crear_contrato_con_cuenta` (+ wrapper
`_producto`), `crm.actualizar_contrato_con_cuenta`, `public.crear_contrato` y
`public.actualizar_contrato` — y `crm.cuentas_bancarias` /
`crm.contrato_cuentas_pago` tienen RLS ON con CERO policies, así que bajo el
guard no hay segunda línea de defensa. Se suma `crm.cuentas_pago_contratos_fn`.
`crm.equipo_visible_fn` y `private.es_directorio_crm_activo` quedan intactas a
propósito (son superficies CRM).

Gate (`test-rls.mjs`, misma sesión): las sondas «admin global sin membresía»
vuelven a POSITIVAS (`assertAdminBankRead`) tras haberse invertido el 08-08, y se
añade una **pareja sobre el mismo actor** — gana la banca sin fila, la pierde en
cuanto existe una fila APAGADA — para que un `not exists(...)` mal escrito no
pueda pasar verde con solo una mitad. Más las sondas de perfil de portal apagado
en la rama admin. La fila fabricada y la desactivación se limpian en el `finally`,
no solo en el camino feliz: una fila apagada superviviente envenena la corrida
siguiente (el lector global cuenta inactivos).

**Deudas anotadas por la auditoría (NO cerradas aquí):**
- ⚠️ **El offboarding CRM es `activo = false`, NUNCA `DELETE`.** Borrar la fila de
  un analista lo vuelve «ajeno» y le DEVUELVE la banca de su cartera; antes
  borrarla lo dejaba igual de bloqueado. No hay policy DELETE para
  `authenticated` y el proceso real desactiva al usuario completo. Pendiente:
  trigger que vete el `DELETE` sobre `crm.equipo`.
- Cobertura de gate pendiente: superadmin con membresía activa no-gerencia (G1),
  analista sin fila sobre SU PROPIO cliente (G3) y las superficies de ESCRITURA
  para admin sin fila / admin revocado (G4).
- `supabase/scripts/test-p04-cuentas-bancarias.sql` quedó desincronizado: sus
  stubs de `es_lector_global`/`rol_crm` son la versión PRE-`20260807203740`, así
  que sus aserciones prueban un mundo que ya no existe.
- ~~Sigue abierta la deuda del 08-08: la rama admin de `public.actualizar_contrato`
  no consulta el guard~~ → cerrada por `20260809003923` (abajo).

## P04 alcanza la corrección de contratos por la vía admin (2026-08-09)

⚠️ **Toca `public`**, con OK explícito de Miguel el 2026-08-09 («ok dale con la
migración de actualizar_contrato»). Ver el registro de excepciones arriba.

Cierra la deuda que el auditor-rls registró el 08-08. El alta ya estaba gateada
(`public.crear_contrato` consulta el guard para TODO actor, admin incluido); la
corrección no. Al auditar apareció una **segunda puerta** que la deuda no
mencionaba y que no sale en ninguna búsqueda por el nombre del guard:

| Función | Qué deja cambiar | Gate previo |
|---|---|---|
| `public.actualizar_contrato` (rama admin) | capital, tasa, fechas, modalidad, cronograma, titulares | **ninguno** (`null`) |
| `public.actualizar_numero_contrato` | N° de contrato, notas, categoría — **sobrevive a cuotas pagadas** | solo `es_admin()` |

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260809003923 | 20260809010408 | crm_p04_correccion_contratos_admin | ✅ **EN PROD 2026-08-09** (branch `crm-p04-correccion` → réplica verificada idéntica por hash → gate RLS **530/530** → advisors **sin ERROR** (95 avisos, mismo total que el branch anterior: ninguna clase nueva) → trigger reactivado antes del merge → merge → verificado en prod → branch borrado). Añade `if private.membresia_crm_revocada() then raise insufficient_privilege` a ambas. Cuerpos VERBATIM de `pg_get_functiondef` en prod (hashes auditados `2a55ddea…` y `c9184d97…`), asertados en el preflight. |

**Fidelidad probada mecánicamente, no afirmada.** Antes y después del merge se
comprobó que al revertir el bloque insertado por `regexp_replace` el cuerpo
reproduce EXACTAMENTE el hash auditado de producción (`true` en ambas
funciones): cero deriva de transcripción en un pegado verbatim de ~180 líneas
sobre `public`. ACL post-merge intactos (`{authenticated}` y
`{authenticated,service_role}`).

Verificación posterior al merge con la sesión real de `gloria@` (payload
inválido dentro de `begin … rollback`, para no tocar contratos reales):
`actualizar_contrato` respondió «El capital debe estar entre 100 y
100,000,000» — es decir, **atravesó la autorización** y murió en la validación
de negocio. Sigue corrigiendo contratos, y no se escribió nada.

Censo del alcance, medido en prod el 2026-08-09: `admins/superadmins con
membresía CRM revocada` = **0**, así que hoy nadie pierde acceso; los 3
revocados son rol de portal `comercial`, que ya caía en la rama `else`.

**Por qué el predicado estrecho y NO el guard completo** (decisión validada por
el auditor): sobre la rama admin, `puede_gestionar_cuentas_cliente` **no añade
scoping alguno** — `es_admin()` satisface el OR por sí solo. Lo único que
sumaría es `cli.rol='cliente' and cli.activo is true`, condiciones sobre el
SUJETO y no sobre el ACTOR: no cierran ninguna fuga entre roles, solo cerrarían
la corrección de contratos históricos de clientes desactivados. Aplicarlo habría
sido meter una regresión funcional en `public` ajena a P04 — la clase de bug
exacta de toda esta saga. Hoy: 0 contratos de clientes inactivos sobre 330.

**Asimetría deliberada, anotada para que nadie la «unifique»:** para un cliente
INACTIVO un admin ya no puede CREAR contrato (guard completo en `crear_contrato`)
pero SÍ puede CORREGIRLO. Crear para alguien dado de baja es un error de negocio;
corregir su historia no lo es.

**Controles que la migración lleva DENTRO de la transacción** (exigidos por la
auditoría porque es una migración a `public`): md5 de ambos cuerpos antes de
reemplazarlos — `actualizar_numero_contrato` **nunca fue definida por una
migración de este repo**, así que la guarda de hash es su única red —, verificación
de que el owner puede ejecutar `private.membresia_crm_revocada()` (la función
legacy estrena llamada a `private`; sin esto fallaría en RUNTIME, no al crear),
reafirmación del `NOT NULL` de `crm.equipo.activo`, y post-condición de `proacl`
sobre ambas funciones.

Gate: pareja completa sobre el mismo actor — admin SIN fila **sigue corrigiendo**
(sondas no destructivas: payload inválido, así que atravesar la autorización y
morir en la validación prueba que el gate dejó pasar sin escribir) y admin con
fila APAGADA no corrige, más una aserción de que la fila del contrato quedó
intacta: «la RPC lanzó excepción» no es lo mismo que «no escribió».

**⚠️ DEUDA P04-b, abierta a propósito** (en una migración a `public`, la
disciplina de alcance vale más que la completitud). Siguen sin la invariante,
todas por vías de admin del Portal:
1. **PRIORITARIA — hard-DELETE de contratos** por PostgREST
   (`public_html/js/admin/contratos.js:1525`), con CASCADE a `cronograma_pagos`
   y `documentos`. Un admin revocado no puede corregir un contrato pero sí
   **borrarlo entero**. Gobernado por una policy DELETE, no por una RPC.
2. `public.cerrar_contrato` (renovado/retirado + traslado de cuotas).
3. UPDATE directo sobre `public.cronograma_pagos` (registrar, importar y revertir
   pagos).
Mientras siga abierto, **no se puede comunicar «la operación contractual está
bajo P04»**: lo está la corrección, no el borrado ni los pagos.

Sube de prioridad, además, el trigger que vete el `DELETE` sobre `crm.equipo`:
ese agujero ya sostiene TRES superficies (banca, Pagos y ahora corrección).

---

## 2026-08-09 · Re-encolar un lead cancela sus tareas y retrocede su etapa

Cierra el conflicto anotado el 2026-08-08 entre dos triggers correctos por
separado: `private.trg_leads_sync_tareas` espejaba la tenencia del lead sobre
sus tareas pendientes, y `private.trg_tareas_destino_efectivo` (metas/SLA
versionados) prohíbe que una tarea pendiente se quede sin destino. Devolver un
lead a la cola global deja su tenencia en NULL ⇒ el espejo propagaba ese NULL
⇒ **23514 abortaba el UPDATE entero**. Efecto real: un lead con cita agendada
**no se podía devolver a la cola**. Decisión de Miguel: opción B — es un bug.

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260809024942 | 20260809034548 | crm_reencolar_cancela_tareas | ✅ **EN PROD 2026-08-09** (branch `crm-reencolar` → réplica verificada en el hash auditado de prod `b10c9f95…` ANTES de aplicar → gate RLS **539/539** sobre branch **reseteado** → advisors **sin ERROR** (95 avisos: 87 WARN + 8 INFO, el mismo total que los dos branches anteriores; ninguna clase nueva y cero menciones a la función tocada) → trigger `trg_equipo_validar_usuarios_jerarquia` reactivado (`tgenabled='O'`) antes del merge → merge → verificado en prod → branch borrado). |

**Dos partes, y la segunda salió de la auditoría.** PARTE 1 cancela las tareas
pendientes con el flag `crm.cancela_sistema` que la propia función YA usa en
convertido/descartado/inactivo: la tarea queda sellada `cancelada_por='sistema'`
sin actor humano y conserva su bandeja anterior como historia. PARTE 2 retrocede
la etapa: cancelar sin bajar de `reunion_agendada` devolvería el lead a la cola
**afirmando una cita que ya no existe** — el «hecho falso más caro» de la
doctrina de `20260726151751`. Se replica la regla exacta de anular reunión
(`contactado` si hay contacto en el ciclo, `nuevo` si no; y **no** retrocede si
ya hubo `reunion_realizada`) porque `private.retroceso_por_anular_reunion` no
era reutilizable: solo la llaman las RPC humanas `cerrar_tarea`/`cerrar_reunion`
—una cancelación por trigger se la salta— y exige tenencia no nula, que en el
re-encolado ya es NULL. El flag `crm.avance_auto` hace que el cambio se registre
como automático en vez de imputárselo a quien devolvió el lead.

**Alcance preciso:** solo cuando vendedor y supervisor pasan AMBOS a NULL. Bajar
de bandeja a vendedor, subir a bandeja o cambiar de bandeja siguen ESPEJANDO
como hasta hoy — ahí la cita debe seguir al lead, no morir.

**Re-entrada auditada trigger por trigger.** El UPDATE de la etapa vuelve a
disparar el mismo AFTER: en la segunda pasada la tenencia no cambia (NULL→NULL)
y la etapa nueva no es terminal, así que ambos `if` son falsos y termina. Se
verificó además que ninguno de los otros triggers de `crm.leads` abre episodio
espurio, duplica actividad ni aborta (`trg_leads_asignaciones` ya cerró el
episodio por orden alfabético AFTER; `trg_leads_00_guard_tenencia` no puede
disparar con ambos ya en NULL; `clasificar_movimiento_tenencia` devuelve
`sin_cambio`). Efecto de negocio anotado: el SLA de etapa se reinicia y el lead
en cola pasa a tener reloj de `nuevo`/`contactado` corriendo.

**Guarda de fidelidad de DOS hashes** (hallazgo de la auditoría): el preflight
distingue el cuerpo auditado de prod (aplicar) del cuerpo exacto de esta
migración (ya aplicada, salir con notice) y aborta ante cualquier otro md5.
Detectar solo la palabra «RE-ENCOLADO» no bastaba: el `CREATE OR REPLACE` vive
FUERA del bloque, así que un cambio futuro que conservara esa palabra habría
sido pisado en silencio por un replay — justo lo que la guarda existe para
impedir. Se preserva además el valor previo de `crm.avance_auto` en vez de
apagarlo a ciegas («quien lo enciende, lo apaga»).

**Un hallazgo bloqueante de la auditoría se refutó con evidencia.** B1 sostenía
que cancelar una tarea `tipo='reunion'` violaría `tareas_cierre_reunion_coherente`
(23514) por dejar `motivo_no_realizada` en NULL, y que eso era además un bug
latente en prod desde el 2026-08-05 en la rama convertido/descartado. Es falso:
`NULL = ANY(array[...])` evalúa a **NULL**, no a false, y un CHECK **solo
rechaza cuando evalúa a FALSE**. Comprobado empíricamente en el branch (la
reunión quedó `cancelada` + `sistema`) y aritméticamente en SQL. Se deja el
`motivo_no_realizada` en NULL a propósito: es el comportamiento vivo de las tres
cancelaciones por sistema preexistentes y ninguna métrica agrega por esa
columna; cambiarlo alteraría la semántica de esas tres rutas y excede el alcance.

**Nadie con rol humano puede re-encolar hoy**: `trg_00_gerencia_solo_lectura`
veta a gerencia todo UPDATE sobre `crm.leads` y `trg_leads_guard_tenencia`
reserva la cola global a gerencia; el único camino vivo es service_role/SQL. La
corrección llega ANTES de que exista la vía humana y de que haya volumen —
estado en prod al aplicar: 1 lead, 0 tareas, así que no puede alterar dato
alguno.

Gate: la sonda cambió de signo (clavaba el bloqueo 23514, ahora clava la
corrección) y el fixture se rehízo porque **no probaba el caso real**: usaba una
tarea suelta sobre un lead en etapa `nuevo`, así que el retroceso no se
ejercitaba nunca y el gate habría dado verde sobre media corrección. Ahora son
cuatro semillas que cubren las cuatro ramas — `nuevo`, `contactado`, la
abstención por `reunion_realizada` y la no-regresión de la reasignación — más la
aserción de que la actividad de retroceso queda sellada como automática.

**Fidelidad probada mecánicamente.** El cuerpo del archivo reproduce EXACTAMENTE
el md5 que la propia migración declara como estado POST
(`6874c23294da0027f25475b4e1fc49d7`), comprobado en el branch antes del merge y
en producción después. La ruta de idempotencia se ejercitó de verdad: la
migración se aplicó dos veces seguidas sobre el mismo branch y la segunda tomó
la rama «reaplicación idéntica» sin abortar ni derivar.

**Verificación funcional en vivo sobre producción**, dentro de
`begin … rollback` y tras comprobar que ninguno de los 26 triggers de
`crm.leads`/`crm.tareas`/`crm.actividades` hace llamadas externas (un rollback
no desharía un webhook ya enviado): se creó un lead en `reunion_agendada` con
una reunión pendiente, se re-encoló —la operación que antes moría con 23514— y
las cuatro aserciones pasaron: etapa `nuevo`, tarea `cancelada` sellada
`sistema` sin actor humano, y la actividad de retroceso marcada como
automática. Producción quedó intacta (1 lead, 0 tareas).

## F1 tanda 1 — métricas al servidor (2026-08-09)

Primera tanda de la fase F1 del plan de escalabilidad («el navegador NUNCA
recibe filas para contarlas»): cuatro RPC de agregados que replican en SQL los
cálculos que el front hacía recorriendo arrays del store, con el predicado
espejo de `leads_select` (visibles + parkeados por bandeja + gerencia + lector
global) y la **ventana de convertidos de 45 días** (decisión de Miguel
2026-08-08) implementada por primera vez. El front aún NO las consume: los
hooks llegan por pantalla en las tandas siguientes; el corte de
`listarLeadsDelAmbito` a la ventana de 45 d va con la primera pantalla migrada
(hacerlo antes degradaría las series y el aviso de duplicado, plan F0§5).

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260809043802 | 20260809051400 | crm_metricas_servidor_tanda1 | ✅ **EN PROD 2026-08-09** (branch `f1-metricas-servidor-tanda1` → gate RLS **593/593** sobre branch recién creado (539+54 casos F1) → oráculo `METRICAS_SERVIDOR_TX_OK` → advisors sin ERROR ni hallazgos nuevos atribuibles (solo el WARN definer-ejecutable que comparten TODAS las RPC de métricas) → trigger `trg_equipo_validar_usuarios_jerarquia` reactivado (`tgenabled='O'`) antes del merge → merge → verificado en prod (md5 de `prosrc` 4/4 idéntico repo↔prod, ACL exacta, definer+stable+`search_path=''`) → branch borrado). |

**Las 4 RPC** (security definer + stable + `search_path=''` + guardia 42501 +
revoke 4 audiencias/grant authenticated + jsonb `version:1`):
- `resumen_cartera_fn()` — totales/capital (asignado·parkeado·ganado, por
  moneda), embudo de 6 etapas, conversión global, descartes por motivo,
  sin_tocar. `asignados_pen/usd` cuenta SOLO abiertos con vendedor (el donut de
  directorio no cuenta parkeados — hallazgo de la auditoría de paridad).
- `cola_accion_fn(p_limite 1..500)` — cascada EXACTA de `colaDe` (un bucket por
  lead, sev critica<media<baja, días desc), `datos_motivo` con los ingredientes
  (el texto lo redacta el front), `ultimo_contacto_en` por item (el dato del
  semáforo del kanban: deja F3 sin migraciones) y bloque `estancados` (umbral 5,
  tope 50). Tubería ESTRECHA: el lead completo se une por PK tras el LIMIT
  (hallazgo de rendimiento: filas anchas materializadas ≈ cientos de MB a 1M).
- `metricas_vendedores_fn()` — filas por miembro visible (sin nombres: el front
  une con su roster, precedente `metricas_conversiones_fn`) + comparativa por
  supervisor activo con reportes DIRECTOS de cualquier rol (espejo del front) y
  parkeados aparte. Una sola pasada agrupada por el ámbito (la versión con
  laterales re-escaneaba 2·S veces — hallazgo de rendimiento).
- `series_comerciales_fn(p_meses 1..24)` — series mensuales Lima ascendentes:
  nuevos, cohorte, cierres, capital POR MONEDA, conversión (1 decimal). SIN
  ventana de 45 d (histórico).

**Contrato de denegación** (fijado antes de codificar): anon → sin EXECUTE;
ajeno al CRM y membresía inactiva → 42501; coordinador → pasa la guardia y
recibe agregados VACÍOS (ámbito ∅ por diseño; su superficie llega en la tanda 2
con `resumen_reparto_fn` + `puede_operar_reparto_crm()`); parámetros fuera de
rango → 22023 tras la guardia.

**Divergencias deliberadas vs el front** (adoptará los números del RPC al
migrar cada pantalla):
1. Mes de cierre de series = sello canónico `coalesce(convertido_en,
   actualizado_en, creado_en)` (cierres-del-mes.ts), no el orden accidental de
   series-comerciales.ts (`actualizado_en` primero movía el cierre de mes).
2. «Sin contacto jamás» sobre TODO el historial (el front solo ve 365 d/10 k).
3. Conversión por origen NO viaja (ya existe en `metricas_conversiones_fn`).
4. Desempate de la cola por `id` (el front conservaba orden de llegada en
   empates exactos — determinismo del server).

**Verificación**: matriz `testMetricasServidor` en test-rls.mjs (oráculo
AUTOCONSISTENTE: los agregados deben cuadrar con lo que la MISMA sesión
SELECTea por RLS + ventana; robusto a residuos transitorios) + sondas anon +
oráculo transaccional `test-metricas-servidor.sql` (token
METRICAS_SERVIDOR_TX_OK: cascada completa de buckets con un lead fabricado por
rama, ventana 45 d en resumen/vendedores y NO en series, 22023, 42501, tríada
`has_function_privilege` + prosecdef + `search_path=""`).

**Notas para Miguel (no bloquean)**:
- El prefiltro de series (`creado_en >= v_ini or contrato_id is not null`) no
  lo sirve ningún índice → seq scan de `crm.leads` por llamada. Aceptable hasta
  ~300 k leads; a 1 M conviene `create index on crm.leads (creado_en)`
  (rompería el «cero índices nuevos» de F0 — decisión pendiente; la vigilancia
  mensual por pg_stat_statements lo detectará si duele antes).
- La paráfrasis del plan F1 incluía `puede_operar_reparto_crm()` en la rama de
  parkeados (el coordinador vería parkeados en estas métricas). Se implementó
  el predicado REAL de `estado_sla_leads_fn` (coordinador ∅, como los fixtures
  declaran por diseño): darle parkeados aquí ampliaría su visibilidad por
  encima de la RLS en una migración de métricas. Si Miguel lo quiere, es un
  cambio de una línea + tests en la tanda 2.
- Optimización futura de la familia entera de RPC de ámbito: capturar
  `vendedor_ids_visibles` en un array del `declare` y filtrar con `= any(...)`
  (indexable) en vez del `in (select fn())` (SubPlan por fila) — hoy toda la
  casa paga el mismo patrón; cambiarlo es decisión aparte, no de esta tanda.

Front acompañante: delta A MANO en `database.types.ts` (4 firmas nuevas,
`Returns: Json`; el regen completo contra prod ROMPE el build — archivo
curado); `npm run check` del app en verde. Sin cambios de pantallas en esta
tanda.
