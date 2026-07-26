# Ledger de migraciones — esquema `crm`

Proyecto: `dctqcbznekcyxhjujuci` (el MISMO del portal — ver condiciones §5 del plan).
Ciclo obligatorio: **branch de Supabase → aplicar → `scripts/test-rls.mjs` → advisors → merge**.
Prohibido `apply_migration` directo a producción. Ninguna migración del CRM altera objetos
de `public` (única excepción documentada: `20260711000001`, con OK explícito de Miguel).

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
| 20260725060657 | crm_avance_automatico_etapa | **La etapa avanza sola cuando el hecho YA ocurrió** (pedido de Miguel, textual: «cuando el vendedor registre una acción de que SÍ contactó a la persona, y el lead está en la primera fase del pipeline, el prospecto se mueva solo de etapa»). Dos triggers AFTER INSERT, ambos **SOLO DE SUBIDA**: (a) `trg_zz_actividades_avance_etapa` sobre `crm.actividades` → `private.trg_actividades_avance_etapa()`: una CONVERSACIÓN sube el lead de `nuevo` a `contactado`. **Solo los 3 tipos bidireccionales** (`llamada_realizada`, `whatsapp_recibido`, `reunion_realizada`), NO los 5 de `TIPOS_CONTACTO`: «no contestó» y «mensaje enviado» son INTENTOS, y avanzar por ellos convertiría ese botón en un *posponer la alarma 48 h* (umbral `nuevo` 24 h → `contactado` 72 h en `private.umbral_estancamiento`) e inflaría la conversión sin que nadie mienta a propósito. Por eso NACE `TIPOS_CONVERSACION` en `tipos.ts` como subconjunto ESTRICTO y separado: `TIPOS_CONTACTO` responde «¿el asesor trabajó?» (mide esfuerzo → SLA y cola), `TIPOS_CONVERSACION` responde «¿el cliente respondió?» (mide embudo → etapa). Jamás fusionarlos. (b) `trg_zz_tareas_avance_etapa` sobre `crm.tareas` → `private.trg_tareas_avance_etapa()`: agendar una reunión sube el lead a `reunion_agendada`, con CINCO guardas — `tipo='reunion'`, `reagendada_de is null` (**la que más importa: el rebote automático tras un no-show NO es progreso; sin ella, plantar al asesor ASCENDERÍA el lead, la mentira más fácil de fabricar del sistema**), `estado='pendiente'`+`activo`, `vence_en > now()` (agendar en el pasado no es agendar), y un `exists` de contacto real (nunca afirmar «reunión agendada» sobre un lead que NADIE tocó, incluido el parkeado que agenda un supervisor). Sube solo desde `nuevo`/`contactado`: desde `propuesta_enviada` sería un RETROCESO que además reiniciaría el SLA de 120 h a 72 h. (c) `CREATE OR REPLACE` de `private.trg_leads_cambio_etapa` (jamás DROP+CREATE: borraría la ACL) para añadir `automatico` al `metadata` de la actividad, alimentado por un `set_config('crm.avance_auto', …, true)` LOCAL a la transacción — sin esa marca el historial atribuiría al vendedor movimientos que él no pidió, y el cliente no puede encenderlo por PostgREST (aserción del gate). **NUNCA BAJAN DE ETAPA**: un `cambio_etapa` es un hecho registrado con autor, no un estado reversible; el retroceso sigue siendo decisión explícita de una persona. La recursión se corta por DOMINIO (los tipos que emite el sistema —`cambio_etapa`/`reasignacion`/`conversion`— jamás están en la lista que dispara), reforzado por el `WHEN` del trigger y por un `if` repetido dentro de la función. Idempotencia por el predicado `etapa='nuevo'` DENTRO del UPDATE (sin ventana entre leer y escribir): tres contactos seguidos escriben UN solo `cambio_etapa`. Sin columnas nuevas → sin GRANTs nuevos y sin `gen:types`. Espejo del front en `app/src/lib/avance-automatico.ts` (fuente única de las dos reglas, y ÚNICA implementación en modo demo, donde `persistir()` sale en seco). **Correcciones de la auditoría `auditor-rls` (veredicto NO-GO → corregido):** **C1 CRÍTICO — escalada cerrada.** El trigger de tareas lleva GATE DE ÁMBITO propio porque la policy `tareas_insert` **nunca consulta `crm.leads`**: valida el `vendedor_id` de la fila NUEVA, que `trg_tareas_before_insert` (SECURITY DEFINER) ya derivó del lead saltándose la RLS. Para un lead de la COLA GLOBAL sale `null` y la rama `supervisor|gerencia AND vendedor_id IS NULL` del WITH CHECK lo deja pasar → **cualquier supervisor** podía ascender leads que `leads_select` ni le deja VER (61 leads en esa cola al auditar). Gate: dueño no nulo + `puede_ver_cartera` o gerencia, con `auth.uid() is null` para sistema. ⚠️ **El hueco de `tareas_insert` es PREVIO y sigue abierto** (un supervisor puede crear tareas sobre leads invisibles): se documenta, no se toca aquí — el gate impide que ARRASTRE una escritura sobre `crm.leads`. **A1 — ciclo de deadlock cerrado.** El trigger hacía que `crm.cerrar_tarea` pasara a bloquear `tareas → leads`, mientras `trg_leads_sync_tareas` bloquea `leads → tareas`: cerrar una tarea mientras el supervisor reasigna el mismo lead daba `40P01`. Se unifica el orden con un `for no key update` sobre el lead al inicio de `cerrar_tarea`. **Verificado contra la BD VIVA** (no contra el repo: el ledger ya documenta que prod puede derivar): `diff` del `prosrc` de producción contra el cuerpo de esta migración = **+15 líneas, −0**. El `prosrc` vivo no tiene comentarios, así que el REPLACE no borra doctrina de la BD. El subselect del lock REPITE el filtro de ámbito del `for update` (2ª pasada, MEDIO-1): si solo buscara por id, un usuario con rol podría tomar un lock sobre el lead de una tarea ajena y, si otra transacción lo tuviera tomado, esperar hasta el `statement_timeout` — un oráculo de temporización sobre si ese lead se está escribiendo. **M1** trigger renombrado a `trg_zz_actividades_avance_etapa`: Postgres ordena por nombre COMPLETO, y `trg_actividades_zz_…` corría ANTES que `trg_audit_actividades` dejando `audit_log` en orden causal invertido. **M2** las tres funciones a `search_path='pg_catalog'` (la convención endurecida del repo; `public` era superficie de shadowing gratis). **M3** `set local lock_timeout='5s'` (CREATE TRIGGER toma SHARE ROW EXCLUSIVE sobre dos tablas calientes). **M4** guarda de reentrada por el propio flag: hoy no hay recursión posible por dominio, pero un futuro webhook de WhatsApp o auto-log de llamadas la abriría. **M5/M6/B2** oráculo: `order by creado_en, id` (la actividad y su `cambio_etapa` comparten `now()`), aserciones V10b/V10c de no-cascada y de no-fuga del flag, y `row_count` en V17 para que no pase en vacío. **B1** los 5 leads transitorios se desactivan al final del gate. **Decisión explícita (N2):** un lead con `no_contactar` SÍ avanza al registrar una conversación — registrar lo que pasó no es aprobarlo (pudo llamar él), y bloquearlo dejaría el dato inconsistente con su propio timeline; lo que la Ley 29571 prohíbe es CONTACTAR, y de eso se ocupa el kill-switch de `motor-siguiente.ts`. Fijado en V23. | ⏳ PENDIENTE de branch → oráculo `AVANCE_TX_OK` → advisors → gate RLS (con `testAvanceEtapa`) → merge |
| 20260725221530 | crm_tareas_insert_exige_lead_visible | **Cierra un hueco PREVIO de `tareas_insert`** (lo destapó la auditoría del avance automático como hallazgo C1; corregido por orden de Miguel el 2026-07-25). La policy validaba la TENENCIA de la fila nueva (`vendedor_id`/`asignado_supervisor_id`) pero **nunca consultaba `crm.leads`** — y esos campos no los manda el cliente: los DERIVA `private.trg_tareas_before_insert`, que es SECURITY DEFINER y lee el lead saltándose la RLS. Para un lead de la COLA GLOBAL ambos salen `null` y el WITH CHECK pasaba por la rama `supervisor|gerencia AND vendedor_id IS NULL` → **cualquier supervisor con el UUID podía crear tareas sobre un lead que `leads_select` no le deja ni VER** (61 leads en esa cola al auditar), metiéndose trabajo ajeno en la agenda. `ALTER POLICY` (no DROP+CREATE: conserva nombre, comando, roles y USING, y la tabla no queda ni un instante sin policy) añadiendo `lead_id is null or exists (select 1 from crm.leads l where l.id = lead_id)`. El `exists` NO es SECURITY DEFINER → lo filtra `leads_select`, misma técnica que ya usaba `actividades_insert` y por la que esa vía nunca tuvo el problema. Es un ESTRECHAMIENTO puro: vendedor sobre lead suyo, supervisor sobre su equipo o su bandeja, gerencia sobre cualquiera, tareas de cliente (`lead_id` null), `crm.cerrar_tarea` y `service_role` siguen todos igual. | ⏳ PENDIENTE de branch → gate RLS → advisors → merge (mismo ciclo que 20260725060657) |

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
