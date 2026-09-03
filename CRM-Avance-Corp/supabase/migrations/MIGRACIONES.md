# Ledger de migraciones — esquema `crm`

Proyecto: `dctqcbznekcyxhjujuci` (el MISMO del portal — ver condiciones §5 del plan).
Ciclo obligatorio: **branch de Supabase → `npm run seed:demo` → aplicar → oráculo(s) →
`scripts/test-rls.mjs` → advisors → merge**. ⚠️ El **seed va ANTES de aplicar**, y no es una
comodidad: aplicar sobre un branch vacío deja las sondas de comportamiento del postflight en su
rama de aviso y la migración pasa en verde sin ejercitar nada. El porqué, con el precedente que
ya costó un ciclo, en «⚠️ El orden del ciclo estaba mal» justo debajo.
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
| 20260818014534 | `public.perfiles.domicilio` (columna), `perfiles_domicilio_legal_valido` (CHECK), `perfiles_domicilio_legal_no_borrar` (trigger) — **fila añadida a posteriori el 2026-08-19**: la migración alteró `public` y no se registró | pendiente de confirmar |
| 20260819162752 | sin DDL, pero **cambia quién escribe** `public.perfiles.domicilio` saltándose la RLS del portal: antes solo Gerencia, ahora toda la cartera CRM | sí, 2026-08-19 |
| 20260824170630 | `public.contratos.fecha_cierre_comercial`, `fuente_cierre_comercial`, índice/trigger de protección y `public.metricas_directorio()` | sí, 2026-08-24 |
| 20260828190000 | trigger de auditoría NUEVO sobre `public.contrato_titulares` (I/U/D) y NUEVO sobre `public.cronograma_pagos` solo para alta y baja (el de UPDATE, con su `WHEN`, no se toca) | sí, 2026-08-28 (Fase 1 del P-055) |
| 20260828190500 | 2 CHECK anti-NaN en `public.cronograma_pagos` (`monto_programado`, `monto_pagado`) | sí, 2026-08-28 (Fase 1 del P-055) |
| 20260828191000 | REVOKE de TRUNCATE/REFERENCES/TRIGGER/MAINTAIN a `anon` y `authenticated` en 10 tablas de `public`; `alter default privileges`; REVOKE EXECUTE a `public`/`anon` de 5 RPC de administración con re-grant explícito a `authenticated` y `service_role` | sí, 2026-08-28 (Fase 1 del P-055) |

## ⚠️ El orden del ciclo estaba mal: el seed va ANTES de aplicar (2026-08-11)

Hasta hoy este fichero prescribía **«branch → aplicar → gate → advisors → merge»**, y en las
notas de pendientes se escribió tal cual: «branch → aplicar (155128 → 163618 → 163638) →
**seed + gate** → advisors → merge» (sección de índices de lectura, 2026-08-08). Ese orden
está **mal**, y el auditor lo marcó como bloqueante antes de dejar aplicar el ciclo del
2026-08-11.

**Por qué.** Un branch de Supabase replica el **esquema**, no los datos: nace VACÍO. Si las
migraciones se aplican ahí y solo después se siembra, entonces, en el momento en que corre el
postflight, no hay ni un lead, ni un episodio, ni un cierre. Todas las sondas de comportamiento
—las que existen precisamente para demostrar que la regla nueva hace lo que dice— caen en su
rama de aviso («no hay datos suficientes para comprobarlo») y la migración **pasa en verde sin
haber ejercitado ni una sola rama**. Lo que se verifica en ese escenario es que el SQL compila,
no que la regla funcione.

**El precedente, que ya costó un ciclo entero a este proyecto** (20260810163458): la suite daba
**732/732 en verde** mientras publicar metas era **imposible desde que existe la pantalla**,
porque no había un solo caso **positivo** de la acción principal. Aplicar antes de sembrar
reproduce ese mismo fallo por otra vía: no es que falte el caso positivo en la suite, es que el
mundo donde correría el caso positivo todavía no existe. Y el `gate:realidad` dice lo mismo
desde otro ángulo: los tests montan el mundo del fixture y producción es otro mundo — aquí el
mundo del branch al aplicar no es ninguno de los dos, es el vacío.

**El orden correcto, que es el que manda a partir de ahora:**

1. `create_branch` (branch de Supabase).
2. **`npm run seed:demo` contra el branch** — el mundo poblado primero. El seed corre contra el
   esquema VIEJO (el que replicó el branch), así que solo vale para migraciones que no exigen
   estructura nueva para sembrar; si alguna la exigiera, se siembra en dos pasadas y se dice
   aquí cuál y por qué.
3. **Aplicar** las migraciones, en orden de timestamp.
4. **Leer el postflight fila por fila**: cada sonda tiene que decir OK **con datos**. Una sonda
   en su rama de aviso («0 filas, no se pudo comprobar») es un **FALLO del ciclo**, no un pase.
   Esta lectura es parte del ciclo, no una cortesía.
5. Oráculo(s) de la migración (`supabase/scripts/test-*.sql`) + `npm run test:rls`.
6. `get_advisors` (seguridad y rendimiento).
7. `merge_branch` → verificación en prod → borrar el branch.

**Corolario para quien ESCRIBE una migración**: una sonda que dependa de datos de ambiente va
después del seed; una sonda que **fabrica su propio caso** dentro de una subtransacción que se
deshace vale en cualquier orden — pero entonces tiene que **fallar** si no consigue fabricarlo,
nunca avisar. Un postflight que solo mira catálogos (`pg_constraint`, `pg_trigger`,
`pg_get_functiondef`) no prueba que un agujero esté cerrado: solo una inserción **rechazada** lo
prueba.

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
| 20260804165440 | crm_creacion_lead_atomica | **P-048 — alta manual atómica respecto de los escritores de `crm.leads`.** `crm.crear_lead_si_disponible(...)` toma advisory locks transaccionales y deterministas por teléfono/DNI, reejecuta el cuerpo canónico de P-047 después de esperar y solo inserta si el contacto sigue `libre`; `p_id` conserva la identidad optimista y hace idempotente el reintento inmediato del mismo payload mientras la fila no haya recibido otra mutación de negocio. La RPC es `SECURITY DEFINER`, replica P04/ámbito/destino, deriva autor y bandeja, devuelve únicamente el veredicto discriminado y tiene `EXECUTE` solo para `authenticated` (`anon` y `service_role`, fuera). Un cuerpo privado único de P-047 admite excluir la fila que se edita. Dos triggers legacy comparten las llaves con INSERT y cambios relevantes de `crm.leads`: una sesión humana que todavía use INSERT directo recibe el veto P-047, no puede cambiar teléfono/DNI hacia una identidad bloqueada ni mudar los datos de su propia fila mientras porte `no_contactar` o enfriamiento vigente; el importador sin sesión comparte la serialización pero conserva su semántica especializada. El precheck de P-047 permanece como UX y puede degradar por transporte; la autoridad final es la RPC. **Fronteras deliberadas:** no toca `public`, por lo que un alta o cambio de identidad de `public.perfiles` exactamente concurrente aún puede competir con la lectura `ya_es_cliente`; el importador permite reingresos que la política manual bloquea. El `GRANT INSERT` directo de `authenticated` se mantiene durante adopción por compatibilidad: su revocación se hará en una **segunda migración posterior al despliegue/adopción**, tras comprobar que no sobreviven bundles/clientes antiguos. Oráculo autocontenido `test-creacion-lead-atomica.sql`: ACL públicas/privadas, validaciones, estados, idempotencia, UPDATE de identidad —incluidos vetos propios— y carreras reales por teléfono, DNI, rollback, INSERT legacy y revocación P04 mientras se espera, mediante `dblink`; termina con código 0 y el token `CREACION_LEAD_ATOMICA_TX_OK`. | ✅ **EN PROD** — Supabase la registró como `20260804213726` (mismo patrón que P04: timestamp remoto distinto del archivo local). La fila decía «SOLO LOCAL» desde el deploy: deuda de documentación cazada por Codex el 2026-08-16 y zanjada contra producción viva (schema_migrations + impl de 3 args con md5 `7063fc89…` + alta manual 20260811210049 también registrada). |

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
| 20260818014534 | `public.perfiles.domicilio` (columna), `perfiles_domicilio_legal_valido` (CHECK), `perfiles_domicilio_legal_no_borrar` (trigger) — **fila añadida a posteriori el 2026-08-19**: la migración alteró `public` y no se registró | pendiente de confirmar |
| 20260819162752 | sin DDL, pero **cambia quién escribe** `public.perfiles.domicilio` saltándose la RLS del portal: antes solo Gerencia, ahora toda la cartera CRM | sí, 2026-08-19 |

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

## F1 tanda 2 — cierre del servidor de métricas (2026-08-09)

Cierra la superficie SERVIDOR de la fase F1 y ejecuta las **3 notas del ledger
de la tanda 1, aprobadas las 3 por Miguel el 2026-08-09** (índice `creado_en`,
parkeados del coordinador, optimización `= any(array)`). El front sigue SIN
consumir ninguna RPC de F1: los hooks llegan por pantalla (F1b).

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260809144912 | 20260809151422 | crm_metricas_servidor_tanda2 | ✅ **EN PROD 2026-08-09** (ciclo completo, ver abajo) |
| 20260809144920 | 20260809151423 | crm_ambito_any_array_parkeados_coordinador | ✅ **EN PROD 2026-08-09** (ciclo completo, ver abajo) |
| 20260809144930 | 20260809151436 | crm_indice_leads_creado_en | ✅ **EN PROD 2026-08-09** (ciclo completo, ver abajo) |
| 20260810024404 | 20260810031353 | crm_metricas_conversiones_equipo | ✅ **EN PROD 2026-08-09** — ciclo completo: branch `conversion-equipo-supervisor` → aplicar (postflight OK: definer + stable + `search_path=""` + ACL exacta `{authenticated}`, sin `service_role` ni `anon`) → **reset del branch** para correr sobre datos limpios (los `TRANSIENT` de la primera pasada contaminaban el oráculo del directorio, y `crm.lead_asignaciones` es inmutable: no se pueden borrar a mano) → seed → gate RLS **675/675** (+12 casos nuevos) → advisors **0 ERROR** (único WARN sobre la RPC: el `definer-ejecutable` que comparten todas las de métricas, ya aceptado) → trigger `trg_equipo_validar_usuarios_jerarquia` **reactivado (`tgenabled='O'`) ANTES del merge** → merge. **Hallazgo del ciclo, y era del TEST no de la función**: la suite calculaba la ventana con la fecha de la máquina (UTC) mientras la RPC valida `p_hasta > v_hoy` en `America/Lima`; de madrugada UTC el «hoy» local ya es mañana allá y las cinco llamadas legítimas se rechazaban con 22023 — la validación funcionando como debe. (decisión #10, parte b2: el ranking de conversión del supervisor). Crea `crm.metricas_conversiones_equipo_fn(date,date)` recalculando el desglose por vendedor RESTRINGIDO a `private.vendedor_ids_visibles` — **no** reutiliza `metricas_conversiones_fn` porque cinco de sus nueve claves son agregados de TODA la empresa que no se pueden desagregar a posteriori, y porque su implementación privada conserva un gate de gerencia dentro del cuerpo. Payload mínimo (`responsables` con `vendedor_id`/`leads`/`clientes`/`conversion_pct` + `alcance` servido), sin PII y sin tocar `public`. **Auditada por `auditor-rls`: sin fugas de ámbito.** Correcciones ya aplicadas de esa auditoría: `activo is true` en el predicado (espejo de `leads_select`; sin él un supervisor que apaga un lead lo seguía contando en su propio denominador), postflight con las TRES patas (definer + stable + revoke a `service_role`) y `vendedor_ids_visibles` calculado solo cuando recorta. ✅ Ámbito CERRADO por Miguel: DUEÑO ACTUAL («su gente de hoy, con toda su historia»). Casos del gate añadidos (suite `testMetricasConversionEquipo`). ⚠️ Deuda que queda viva: `crm.metricas_conversiones_fn` (la GLOBAL) sigue SIN un solo caso en `test-rls.mjs`. Contrato de front ya listo y commiteado (`app/src/lib/metricas-conversiones-equipo.ts`, `510ce87`). Detalle en la nota del vault «Ranking de conversion del supervisor (RPC pendiente)». |

**Ciclo (2026-08-09):** branch `f1-metricas-servidor-tanda2` → migraciones por
Management API (⚠️ trampa nueva: dos en el mismo segundo colisionan la PK de
`schema_migrations` — la 3ª se reintenta sola) → seed idempotente
(`seed:demo`; ⚠️ el branch nace VACÍO: correr el seed ANTES del gate) → gate
RLS **648/648** (593 previas + 55 de la tanda 2, verde a la primera) → oráculo
`METRICAS_SERVIDOR_TX_OK` (M01–M15; 1 reintento: `facebook` no está en
`leads_origen_check`, se cambió a `landing`) → advisors 0 ERROR (las 9 solo en
la clase WARN definer aceptada) → trigger `trg_equipo_validar_usuarios_jerarquia`
reactivado (`'O'`) → paridad prod re-verificada ANTES del merge (6/6 md5
intactos) → merge → verificado en prod (md5 branch↔prod **9/9**, ACL exacta
`{authenticated}`, definer+stable+`search_path` correctos, índice presente,
3 migraciones registradas) → branch borrado.

**20260809144912 — las 3 RPC nuevas** (patrón canónico completo: definer +
stable + `search_path=''` + guardia 42501 + revoke 4 audiencias/grant
authenticated + jsonb `version:1`; nacen ya con `= any(v_visibles)`):
- `resumen_tareas_fn()` — stats de la agenda (pendientes por tipo, `de_cliente`,
  y los DOS criterios de vencida por separado: `vencidas_hora` para los chips,
  `vencidas_dia` para el plan muerto de colaDe) + señales de alertas: la
  vencida MÁS ANTIGUA por lead abierto (criterio hora, tope 50, `horas` para
  que el front decida severidad) y `sin_accion` (abiertos con dueño sin tarea
  pendiente, con conteo por vendedor para la alerta del supervisor y items
  ordenados PEN-primero/monto desc, tope 50). Ámbito = espejo de la RLS
  `tareas_select` acotado a pendiente+activa; leads por el predicado canónico
  con rama de bandeja (SIN rama de coordinador).
- `resumen_cartera_clientes_fn()` — espejo de `resumenCartera` (cartera-vista):
  clientes en_gestion/de_baja/con_capital, capital activo por moneda SOLO de la
  cartera en gestión, alarma `por_vencer_30` sobre TODOS los visibles con
  desglose `_de_baja`, `por_estado` para los chips de F2, y bucket `sin_asesor`
  que solo se llena para gerencia/lector (por construcción del predicado, no
  por un case). 100 % canónica: MISMO predicado que `clientes_basicos_fn`
  (SIN la rama `creado_por` de contratos_cartera_fn), `search_path=''`.
- `resumen_reparto_fn()` — espejo del StatStrip de repartir.tsx: total de la
  cola GLOBAL, capital por moneda, `espera_max_dias` (enteros), `posible_credito`
  y `por_origen`. Gate `private.puede_operar_reparto_crm()` (coordinador y
  gerencia; **el lector global recibe 42501**, coherente con
  `leads_por_repartir`). Predicado idéntico a la implementación de la cola
  (sin dueño total, etapas abiertas, `no_contactar=false` — Ley 29571). Sin PII.

**20260809144920 — la familia de ámbito a `= any(array)` + parkeados del
coordinador** (cuerpos as-built con paridad md5 repo↔prod verificada 6/6 antes
de editar; diff mecánico cuerpo a cuerpo con SOLO los cambios declarados):
- Optimización: `col in (select vendedor_ids_visibles())` (SubPlan por fila,
  jamás usa índice) → captura única en `v_visibles uuid[]` + `col = any(...)`
  (indexable). Alcance DELIBERADO: solo las 6 que ESCANEAN leads/actividades
  (`resumen_cartera_fn`, `cola_accion_fn`, `metricas_vendedores_fn`,
  `series_comerciales_fn`, `estado_sla_leads_fn`, `actividades_del_ambito_fn`).
  Quedan fuera a propósito: `configuracion_metas_fn`/`cumplimiento_metas_fn`/
  `metricas_agenda_implementacion` (su `in (select)` filtra tablas del tamaño
  del ROSTER — regla de exclusión del plan) y `clientes_basicos_fn`/
  `contratos_cartera_fn` (F2 las re-arquitectura con keyset; además la
  definición viva de `clientes_basicos_fn` NO está versionada — drift del
  ledger 20260721120000 — y la regla F0 prohíbe modificar sin versionar antes).
- Parkeados del coordinador (**cambio de scoping, no solo de rendimiento**):
  la rama pasa a `(vendedor_id is null and (asignado_supervisor_id =
  any(visibles) or puede_operar_reparto_crm()))` SOLO en `resumen_cartera_fn`
  y `series_comerciales_fn` — el coordinador ve los AGREGADOS de todos los
  sin-dueño (cola global + bandejas), su negocio. NO la reciben:
  `cola_accion_fn` (items con PII de contacto; premisa C1 «enruta, no
  contacta» — su agregado es `resumen_reparto_fn`), `metricas_vendedores_fn`
  (hallazgo del auditor: todo su payload agrega por dueño con vendedor — la
  rama habría sido código muerto), ni `estado_sla_leads_fn`/
  `actividades_del_ambito_fn` (filas, no agregados).
- `actividades_del_ambito_fn` conserva su `search_path` legacy as-built
  (deuda declarada; canonizarlo será su propia migración).
- ACL re-asentada idéntica en las 6 (regla permanente #9).

**20260809144930 — índice `crm.leads(creado_en)`**: el prefiltro de las series
(`creado_en >= v_ini OR contrato_id IS NOT NULL`) deja de ser seq scan — el
planner puede resolver el OR por BitmapOr contra `idx_leads_contrato` (F0).

**Contrato de denegación tanda 2** (fijado antes de codificar tests): anon →
sin EXECUTE; ajeno al CRM y membresía inactiva → 42501 en las 3; coordinador →
pasa la guardia con agregados VACÍOS en tareas/cartera-clientes y es titular en
reparto; vendedor/supervisor/directorio → 42501 SOLO en `resumen_reparto_fn`.

**Divergencias deliberadas vs el front** (se suman a las 4 de la tanda 1):
5. `sin_accion` usa el anti-join canónico del servidor (mismo criterio que
   `metricas_agenda_implementacion`): el front solo ve las tareas de su RLS,
   así que una tarea ajena sobre su lead podía inflar su «sin próxima acción».
   El auditor deja constancia (NOTA) de la inferencia de 1 bit que esto
   permite (el lead desaparece de la lista si ALGUIEN le puso tarea) — aceptada.
6. Los topes de listas (50) son señales para alertas, no listados.

**Verificación**: auditoría adversarial previa (auditor-rls: 0 BLOQUEANTES,
2 MAYORES de proceso resueltos —matriz y este ledger—, 1 MENOR aplicado —rama
muerta retirada de metricas_vendedores_fn—, 5 notas) · matriz
`testMetricasServidor` ampliada (autoconsistente: resumen_tareas contra el
SELECT RLS de tareas+leads de la misma sesión; cartera-clientes contra
`clientes_basicos_fn`+`contratos_cartera_fn`; reparto contra
`leads_por_repartir`; el coordinador contra los sin-dueño que ve gerencia,
leídos adyacentes) · oráculo TX ampliado (M10–M15: dos criterios de vencida
deterministas —26 h—, alarma de renovación con bajas, `sin_asesor` invisible
para supervisor, cola global con GUCs `oraculo.*` calculados como postgres
—inmunes a residuos—, 42501 del ajeno, tríada ACL de las 5 tocadas).

---

## F2 tramo 1 — cursor keyset de la cartera (2026-08-10)

Primer tramo de la fase F2 del plan de escalabilidad: la cartera deja de
descargarse entera para recortarse en el navegador. Una RPC pagina por keyset
`(actualizado_en desc, id asc)` con los tres filtros (etapa / vendedor / texto)
resueltos en el servidor, y la UI cambia de páginas numeradas a «Cargar más»
—con cursor no existe «la página 7», existe «lo siguiente a lo que ya tengo», y
saltar a una arbitraria exigiría el `count: 'exact'` que esta fase elimina.

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260810141953 | 20260810145041 | crm_cartera_keyset | ✅ **EN PROD 2026-08-10** (branch `f2-cartera-keyset` → gate RLS **732/732** (675 + 57 casos F2) → oráculo `CARTERA_KEYSET_TX_OK` → advisors **0 ERROR** (seguridad y rendimiento; la función no engrosa siquiera el WARN definer-ejecutable, ver abajo) → trigger `trg_equipo_validar_usuarios_jerarquia` reactivado (`tgenabled='O'`, 0 triggers en disable) antes del merge → merge → verificado en prod (md5 de `prosrc` `437a9ef581ba4bdd5e5975fdd8ed538e` idéntico branch↔prod, `prosecdef=false`, `stable`, `search_path=""`, ACL exacta `{authenticated}`) → branch borrado). |

**`crm.cartera_pagina_fn(p_limite, p_antes_de, p_antes_id, p_etapa,
p_vendedor_id, p_sin_asignar, p_texto)` — `returns table` de 25 columnas** (las
24 de `COLUMNAS_LEAD` más `ultimo_contacto_en`).

### La decisión del ciclo: SECURITY INVOKER, y por qué rompe el patrón

Las 8 RPC de F1 son `security definer` porque devuelven AGREGADOS: números que
no identifican a nadie, y re-implementar el predicado de visibilidad es el
precio de agregarlos de una pasada. Esta devuelve **filas de leads con PII**
(nombre, teléfono, DNI, fecha de nacimiento). Con `definer`, un solo error en el
predicado copiado abriría la cartera entera de la empresa a cualquier vendedor;
con `invoker` la única fuente de verdad del alcance es `leads_select` — la misma
policy que ya recortaba la lectura que esta función sustituye.

Se conserva la **guardia de admisión 42501** (uid nulo o ajeno al CRM) para que
el contrato de denegación siga siendo uniforme y un revocado no reciba una lista
vacía indistinguible de «no tienes leads» (P04: revocado ≠ ajeno al CRM). O sea:
**admisión propia, alcance de la RLS**.

La auditoría (`auditor-rls`) confirmó la tesis con el SQL en la mano: no hay
camino por el que devuelva una fila que `leads_select` no dé, y
`actividades_select` es **co-extensiva** con `leads_select` (literalmente el
mismo predicado envuelto en un `exists`), así que `ultimo_contacto_en` no puede
mentir por asimetría de RLS. Efecto colateral bueno: al no ser definer, es la
primera RPC del CRM que **no aparece** en el WARN `authenticated_security_
definer_function_executable` que comparten las otras 92.

⚠️ Nota que hay que recordar el día que se toque el ACL: con `invoker`, los
grants **por columna** de `crm.leads` sí importarían (el chequeo se hace contra
el ACL del invocante). Hoy ese ACL es de TABLA, así que no hay columna invisible
— pero si algún día se pasa a grants por columna, esta RPC se rompe con
`permission denied` mientras las definer de F1 seguirían funcionando.

### El hallazgo MAYOR de la auditoría, y su medición

El recorte de ámbito llega desde la policy como `vendedor_id in (select
private.vendedor_ids_visibles(...))`: un SubPlan hasheado, es decir **filtro,
nunca index qual**. Sin nada más, un vendedor con 20 leads sobre un millón
obligaría a recorrer el índice global hasta juntar 50 coincidencias EN CADA
PÁGINA — justo el trabajo que F2 existe para matar. El cuerpo captura el array
de visibles una vez y **repite el predicado como `= any(...)`** (misma técnica
que la tanda 2 de F1). Es redundante a propósito y la asimetría es lo que lo
hace seguro: bajo `invoker`, un error ahí solo puede OCULTAR filas.

**Medido con EXPLAIN en el branch, bajo sesión `authenticated` real** (no como
`postgres`, que no ve la RLS):
- gerencia / lector global → `Index Scan using leads_orden_cartera_idx` (el
  orden se sirve por índice; la RLS queda como Filter).
- vendedor → `Index Scan using idx_leads_vendedor_creado_en` con **Index Cond**
  sobre `vendedor_id` (ya no Filter) + Sort del subconjunto propio. Sin la pista
  el ámbito no habría llegado nunca al índice.

### Divergencias deliberadas (documentadas también en la cabecera del archivo)

1. **Teléfono/DNI exigen 3 dígitos** (el filtro local viejo reaccionaba desde 1):
   `%9%` sobre dos columnas es un escaneo completo en cada tecla. El **nombre**
   se acepta desde 2 caracteres, por compatibilidad con `listarLeads`.
2. `%`, `_` y `\` del usuario se **escapan**: son literales que se teclean, no
   comodines que pueda inyectar. Los `ilike` declaran `escape` explícito para no
   depender de `standard_conforming_strings`.
3. **No se filtra `activo = true`** — igual que `listarLeadsDelAmbito`: se confía
   en la RLS. Consecuencia anotada y NO corregida de tapadillo: el **directorio**
   (lector global) ve soft-borrados en las filas que sus tiles no cuentan. Es el
   comportamiento de hoy; alinearlo cambiaría lo que ve un rol de auditoría sin
   que nadie lo haya pedido.
4. **Coordinador**: sus tiles cuentan los sin-dueño de la cola global y aquí
   recibe 0 filas. No es visible en producto — ese rol tiene `verLeads: false` y
   la vista `cartera` no se le abre; su destino es «Repartir». Comprobado antes
   de darlo por bueno, que es la lección del ciclo anterior.

### El keyset ordena por una columna MUTABLE

`actualizado_en` se reescribe en cada UPDATE. Un lead editado durante el scroll
puede **repetirse** (el front deduplica por id) o **saltarse** (si cruza hacia
delante del cursor, no aparece en las páginas siguientes). Lo segundo es
indetectable desde el cliente y se acepta igual: cerrarlo exigiría congelar un
snapshot, o sea servir datos viejos. Quien acaba de tocar ese lead es quien lo
mueve, y lo tiene delante en la primera página.

### Verificación

- **Auditoría adversarial previa** (`auditor-rls`): 0 BLOQUEANTES de seguridad;
  4 MAYORES (ledger ausente, la pista de ámbito, la falta de oráculo TX, y la
  cobertura de la rama de dígitos), 3 MEDIOS y 6 MENORES — todos aplicados o
  documentados aquí.
- **Matriz `testCarteraKeyset`** (`test-rls.mjs`, 6 roles): oráculo = el propio
  SELECT del actor leído adyacente; prefijo fila a fila y en orden; paginación de
  2 en 2 sin repetidos ni huecos; filtros contra su propio SELECT; el filtro por
  un vendedor ajeno devuelve vacío **porque la RLS recortó antes**; el prefijo
  telefónico común a TODA la tabla sigue devolviendo solo el ámbito propio; un
  **cursor válido pero ajeno** no amplía nada; el coordinador recibe **0 filas y
  no 42501**; `ultimo_contacto_en` contrastado contra el max de actividades de
  contacto que ve el propio actor, con su check de no vacuidad; y el mismo
  contacto leído por vendedor, supervisor y gerencia da **el mismo instante**.
- **Oráculo `test-cartera-keyset.sql`** (token `CARTERA_KEYSET_TX_OK`, todo en
  rollback): lo que la matriz no puede con el seed — el **empate exacto de
  `actualizado_en`** (4 leads con el mismo sello: el caso que el desempate por id
  existe para resolver), el recorrido completo de 2 en 2 reconstruyendo el
  conjunto, `prosecdef=false` aseverado sobre `pg_proc` (sin esto, un
  `create or replace` futuro que heredara el `definer` de las hermanas de F1
  pasaría inadvertido), la ACL, la ventana de 45 d, `ultimo_contacto_en` con una
  NOTA posterior al contacto (si el lateral tomara la última fila del timeline,
  devolvería la nota), los tres metacaracteres de LIKE como literales, los seis
  22023 y el 42501 del ajeno.
- **Front**: `npm run check` **1564** ✔ (+42) · e2e **81** ✔ (los 4 specs nuevos
  de cartera quedan bajo el skip de `FUNCIONES_LEADS_APROBADAS`, escritos ya
  contra el contrato nuevo para que resuciten probando la cartera que existe).
- `database.types.ts`: la firma se añadió **A MANO** (deuda conocida: `gen:types`
  con la CLI 2.113 reformatea el archivo entero y rompe 100+ tipos).

### Trampas del ciclo que conviene no volver a pagar

- **El gate NO es re-ejecutable sobre la misma base**: la 2.ª corrida arrastró
  los leads transitorios de la 1.ª y las dos aserciones que cuentan filas de
  `directorio` fallaron por acumulación (7 esperados, 33 vistos). Se limpiaron
  los no-fixture por SQL (`lead_asignaciones` primero por FK, con
  `session_replication_role=replica`) y se re-sembró.
- **Un fixture no es un invariante**: la primera versión aseveraba
  `ultimo_contacto_en === null` «porque las actividades del seed son notas» —
  cierto al arrancar la suite, falso al final: tests anteriores registran
  contactos reales sobre ese mismo lead. Se reemplazó por un oráculo
  autoconsistente. Un test que depende de que nadie más toque los datos no es un
  test, es una carrera.

---

## F2 tramo 1 (corrección) — la cartera del directorio deja de mezclar borrados (2026-08-10)

`20260810141953` dejó la divergencia **anotada y sin corregir a propósito**, para
que la decidiera Miguel; la decidió el mismo día: «arregla lo del directorio».

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260810151433 | 20260810152201 | crm_cartera_keyset_solo_activos | ✅ **EN PROD 2026-08-10** (branch `f2-cartera-solo-activos` → gate RLS **732/732** → oráculo `CARTERA_KEYSET_TX_OK` con los casos K10a–K10f nuevos → **prueba de no vacuidad**: en la misma transacción se comprobó que la RLS del directorio SÍ le entrega el lead soft-borrado (`t`) y que la RPC ya NO (`f`) — el defecto era real y el filtro actúa exactamente donde debe → advisors **0 ERROR** → trigger de jerarquía reactivado (0 en disable) → merge → verificado en prod (md5 `e52ed18ecf4a109abc09ccc3cb567b4d` idéntico branch↔prod, `prosecdef=false`, ACL exacta) → branch borrado). Front: check **1566** ✔ · e2e **81** ✔. |

**El defecto**: `crm.cartera_pagina_fn` no filtraba `activo` —copiando a
`listarLeadsDelAmbito`, que tampoco lo hace— mientras `crm.resumen_cartera_fn`
lo filtra SIEMPRE. Para vendedor, supervisor, gerencia y coordinador daba lo
mismo: su rama de `leads_select` ya exige `activo = true`. Pero el **directorio**
es lector global y su rama del OR (`or private.es_lector_global()`) no lo exige,
así que veía en las **filas** los soft-borrados que sus propios **tiles** nunca
contaron. Una pantalla que dice una cosa arriba y otra abajo.

**El arreglo**: `and l.activo is true` en el WHERE, vía `create or replace` con
la firma idéntica. Todo lo demás —invoker, guardia 42501, pista de ámbito,
keyset, filtros, escapes— es byte a byte lo aplicado horas antes.

**Lo que NO cambia, y es lo que había que no romper**: un lead **DESCARTADO** no
es un lead **BORRADO**. Los descartes del flujo comercial conservan
`activo = true` (los cierra la `etapa`, no el soft-delete) y siguen en la cartera
con su motivo para todos los roles. Lo que desaparece de la vista del directorio
son los que `crm.descartar_lead` cierra sobre la cola global — que ningún otro
rol veía ya.

**Simetría demo/real**: el espejo `filtrarCarteraLocal` y el arnés E2E
`carteraPaginaReal` aplican el mismo filtro. En demo no había leads con
`activo = false` (el `descartar` del store solo toca la etapa), así que el
cambio no altera lo que se enseña — pero deja la regla escrita en los dos lados.

**Nota para F3**: `leads_orden_cartera_idx` se creó DELIBERADAMENTE no parcial
(`20260808155128`) porque `listarLeadsDelAmbito` no enviaba `activo = true`. Esta
RPC sí lo envía; cuando esa lectura muera con el store, el índice podrá pasar a
`where activo = true` y encoger. No se toca mientras las dos convivan.

**La regla que queda**: una divergencia que solo afecta a UN rol es igual de real
que una que afecta a todos, y el rol raro suele ser el lector global — es el
único cuya rama de la policy es distinta. Comprobar tiles↔filas **rol por rol**,
no «en general».

---

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260810163458 | 20260810163458 | crm_roster_metas_fuente_unica | ✅ **EN PROD 2026-08-10** (branch `roster-metas` → gate RLS **745/745** → oráculo `METAS_VERSIONADAS_TX_OK` con M15–M18 nuevos → advisors **0 ERROR** en seguridad y rendimiento → trigger de jerarquía reactivado (0 en disable) → merge → branch borrado). **Prueba de no vacuidad en producción**, en `begin/rollback`: antes → `23514` y publicación imposible; después → roster **16**, excluidos **1** (`IVETT TEEVIN`, motivo `sin_supervisor`) y `revision 1` creada. Verificado además: `authenticated` **no** alcanza los helpers de `private` (`has_function_privilege` = false) y el WARN de definer-ejecutable sigue en **92**, sin sumar los dos nuevos. Front: check **1577/1577**. |

**El defecto**: publicar metas era **imposible**, y lo era desde que existe la
pantalla — por eso `crm.meta_periodos` llevaba **0 filas** en producción. El
editor y el publicador tenían dos definiciones distintas del roster del mes:

- `crm.configuracion_metas_fn` mostraba los vendedores activos **con supervisor
  activo** (join interno contra `crm.equipo s`) → **16** en producción;
- `crm.publicar_metas_vendedores` exigía una meta por **cada** vendedor activo
  → **17**, y antes de eso abortaba con `23514` si a alguno le faltaba el
  supervisor.

Una sola analista sin supervisor (IVETT TEEVIN) bloqueaba el mes **entero**: el
editor ofrecía 16 metas y el servidor exigía 17. Reproducido en producción
dentro de `begin/rollback`: sin supervisor → `23514`; asignándoselo en la misma
transacción → publica `revision 1`. Ningún test lo cazó porque el fixture
siembra a todos los vendedores con supervisor.

**El arreglo**: `private.roster_metas_vendedores()` define **una sola vez** a
quién se le puede fijar meta, y las dos funciones la comparten. Lo que el editor
ofrece es exactamente lo que el servidor acepta.

**La decisión de fondo**: un vendedor sin supervisor **no cabe** en
`crm.metas_vendedor` — `supervisor_id` es `NOT NULL` con FK. Exigir su meta era
pedir algo que el esquema no puede almacenar, así que queda fuera del roster y
**deja de bloquear al resto**. Pero no en silencio: `configuracion_metas_fn`
devuelve ahora `sin_supervisor` y la pantalla lo dice con nombre y con el camino
a Configuración → Usuarios. Ocultar la exclusión habría cambiado un bug ruidoso
por uno mudo — alguien sin meta y nadie enterado hasta fin de mes.

**Alcance de la lista**: `sin_supervisor` solo se rellena para **gerencia** y
**lector global**. A un supervisor no le corresponde enumerar analistas fuera de
su subárbol, así que recibe `[]` (M18 del oráculo).

**Orden de deploy — FRONT PRIMERO**: la clave es nueva en la **respuesta** de la
RPC y el contrato del front es `strictObject`, donde una clave desconocida
rompería la pantalla de metas entera. El schema la declara `v.optional(..., [])`
para tolerar al servidor viejo; `metas-versionadas.test.ts` fija las dos mitades
del acuerdo. Ver [[crm-orden-deploy-front-primero]].

**Lo que NO cambia**: el control de concurrencia (advisory lock por periodo +
`lock table` sobre `perfiles` y `equipo` + `expected_revision`), la
inmutabilidad append-only, la auditoría y el `42501` de «solo Gerencia publica».
Y sigue siendo imposible colar una meta para alguien fuera del roster: con los
totales iguales y ninguna clave faltante, tampoco puede sobrar (M17).

**Tres motivos, no uno** (hallazgo del `auditor-rls`): quedar fuera del roster
tiene tres causas con tres arreglos distintos — `sin_supervisor`,
`supervisor_inactivo` y `supervisor_no_es_supervisor`. Agruparlas bajo una sola
etiqueta mandaría a gerencia a «asignarle supervisor» a alguien que en pantalla
ya tiene uno: el mismo error de usar un predicado como proxy de varias preguntas
que costó el incidente [[crm-p04-revocado-vs-ajeno]]. Como la función nace en
esta migración, el `motivo` va en su firma desde el principio y no hace falta
`drop`.

**`nombre_completo` es NULLABLE y podía tumbar la pantalla entera** (hallazgo
del `auditor-rls`): el contrato del front exige texto no vacío dentro de un
`strictObject`, así que un solo nombre en blanco no habría dejado a gerencia sin
una fila, sino **sin pantalla de metas**. Y la población de riesgo es la misma:
al registro al que nadie le puso supervisor tampoco suele ponerle nombre. Se
blinda en el servidor con `coalesce(nullif(btrim(...),''), '(sin nombre · …)')`,
tanto en los excluidos como en el roster y su supervisor.

**Se estrecha un lock que congelaba el PORTAL** (hallazgo del `auditor-rls`,
heredado de `20260807203757`): el cuerpo hacía
`lock table public.perfiles in share mode`, de modo que **cada publicación de
metas del CRM bloqueaba las altas y ediciones de perfil del portal en
producción**. Se sustituye por un `select … for share` acotado a las filas del
equipo comercial (21), que da el mismo aislamiento sobre lo único que puede
cambiar `private.rol_crm` a mitad de transacción. `crm.equipo` sigue en
`share mode`, y sin fila ahí nadie entra al roster. Alineado con
[[crm-portal-separados]].

**Deuda viva que ESTA migración no cierra** (hallazgo A2 del `auditor-rls`):
`crm.cumplimiento_metas_fn` construye su universo desde `crm.metas_vendedor`, así
que un analista fuera del roster **no aparece en el cumplimiento del mes y sus
contratos no se atribuyen a nadie**. Antes el `23514` lo tapaba abortando la
publicación entera — pero como publicar era imposible, esa garantía nunca llegó a
ejercerse. Se documenta y **la pantalla lo dice** («su producción no se atribuye
en el cumplimiento del mes»); cerrar el agujero en la RPC de cumplimiento queda
como trabajo aparte.

**Cobertura nueva** — el hallazgo más incómodo de la auditoría: `test-rls.mjs`
solo tenía casos **negativos** de publicación, y por eso el gate daba 732/732
mientras publicar era imposible. Ahora se publica de verdad (leyendo la revisión
vigente, para que siga siendo re-ejecutable), se comprueba el ida y vuelta del
capital, y se añaden roster incompleto, clave ajena y CAS perdido. El roster
degradado —los tres motivos— se ejercita en `test-metas-versionadas.sql`
(M15–M18), que sí puede fabricarlo.

**Los mensajes dejan de nombrar al vendedor** (hallazgo de Codex): las cinco
excepciones del bucle interpolaban el UUID del analista, que viaja al cliente con
el `22023` y de ahí a Sentry — y el scrub de `observabilidad.ts` limpia correos,
JWT y bearer, **no UUID**. Nadie los necesitaba: el payload lo construye el
propio front, así que un fallo de formato es un bug del cliente, no un dato que
gerencia deba leer. Heredado de `20260807203757`; se cierra aquí porque el cuerpo
se reescribe entero.

**Riesgo conocido y aceptado — pestañas ya abiertas** (hallazgo de Codex): «front
primero» protege las cargas nuevas, no una pestaña que siga viva con el bundle
anterior. Cuando esa pestaña vuelva a llamar a `configuracion_metas_fn`, su
`strictObject` viejo verá `sin_supervisor` como clave desconocida. **No rompe el
CRM**: `store.tsx` envuelve esa lectura en un `catch` que marca
`objetivosError` y degrada (`crm.metas.configuracion_boot_degradada`), así que el
usuario ve el aviso de degradación hasta que recargue. Verificado en
`store.tsx:709-714`.

**Trampa del gate, medida en vivo**: la primera versión del caso de CAS mandaba
el payload completo y **colgaba**. Con `pg_stat_activity` se vio la causa exacta:
tres llamadas a `publicar_metas_vendedores` en cola sobre el **mismo advisory
lock** del periodo (`wait_event = advisory`), porque una publicación lenta en una
instancia de branch se pasa del timeout del gateway, el gateway reintenta y el
reintento vuelve a encolarse. Se prueba el CAS con `p_metas = {}`, que además es
**más estricto**: el chequeo de revisión precede al del roster, así que un
payload vacío debe morir en `40001` y no en `22023` — si alguien invierte ese
orden, el caso lo caza.

**La regla que queda**: cuando **dos** funciones deciden sobre el mismo conjunto
—una para ofrecerlo y otra para aceptarlo— ese conjunto se define **una vez**.
Dos copias del mismo predicado no divergen el día que se escriben: divergen el
día que los datos estrenan un caso que ninguna de las dos contemplaba. Y el
corolario: una suite sin un solo caso **positivo** de la acción principal no
prueba que la acción funcione, por muchos negativos que acumule.

## Conversión mensual ponderada, integridad del ledger y sello del origen (2026-08-11)

Tres migraciones de un mismo ciclo, y una sola frase las une: **el origen de un
lead pasa a tener consecuencia económica**. Con la regla cerrada el 2026-08-10
por la noche (T10), un lead `referido` **sale del divisor** y su cierre pondera
0,15 en el numerador — así que mover un origen mueve el porcentaje de alguien, y
un cierre mal contado mueve su sueldo. La **A** construye la métrica, la **E**
hace imposibles en el almacenamiento las dos filas que la métrica no sabría
contar, y la **D** sella la columna de la que sale «era referido».

Contexto en el vault: «Conversión mensual — plan de implementación» (§3.1 y
§3.4) e [[Conversion mensual - definicion cerrada]]. La unificación de
`cumplimiento_metas_fn` (**migración B**) NO está en este ciclo: va **la última,
después del front**.

| Versión local | Versión remota | Nombre | Estado |
|---------------|----------------|--------|--------|
| 20260811154434 | 20260811154434 | crm_conversion_mensual_ponderada | ✅ **EN PROD 2026-08-11** (merge del branch `conversion-mensual-a-e-d-f` tras ciclo completo en verde). 1 tabla + 4 funciones + 4 índices, servidor primero; nadie la lee hasta el release del front. |
| 20260811190310 | 20260811190310 | crm_ledger_cierres_integros | ✅ **EN PROD 2026-08-11**. El CHECK `cierre_no_trivaluado` (ojo: `pg_get_constraintdef` lo enseña normalizado como `NOT (... IS DISTINCT FROM ...)`) + el único parcial «una conversión por lead». Verificados ambos en prod tras el merge. |
| 20260811190324 | 20260811190324 | crm_origen_inmutable | ✅ **EN PROD 2026-08-11**. La versión **simple**: el origen sellado en UPDATE, sin ventana de gerencia ni carve-out del ledger; `crm.op_privilegiada` como único escape. Sello verificado en el cuerpo vivo de `private.leads_before_update` tras el merge. |
| ~~20260811164017~~ | — | ~~crm_origen_inmutable_correccion_gerencia~~ | ❌ **DESCARTADA Y BORRADA DEL ÁRBOL el 2026-08-11, jamás aplicada** (bloqueada por `auditor-rls` + Codex: la ventana de 24 h podía cruzar la medianoche de fin de mes y reescribir un mes cerrado, y la corrección no alcanzaba a los episodios terminales). El preflight (0.2) de `20260811190324` aborta si detecta que llegó a aplicarse en algún branch. |
| 20260811210049 | 20260811210049 | crm_alta_manual_origen_restringido | ✅ **EN PROD 2026-08-11**. **La regla D8 de Miguel** («referido, Wallking y OTRO esto puede registrar el vendedor; landing y formulario se carga solo» + «solo los vendedores a su propio nombre»): el alta manual solo admite `referido`/`oficina`/`otro`, y `referido` exige rol **vendedor** (la autoasignación ya la forzaba el bloque de destino). Cuerpo reproducido íntegro desde producción (md5 vigilado en preflight). Toca un camino de **escritura** (el alta), pero solo AÑADE denegaciones. Ventana declarada: el form del front ofrece LANDING/FORMULARIO hasta el release del paso 2. Casos CONV-23a..d en el oráculo. |
| 20260812000259 | 20260812000259 | crm_cierres_externos | ✅ **EN PROD 2026-08-13, aplicada DIRECTO con `supabase/scripts/aplicar-cierres-externos-prod.sh` autorizado por Miguel** — el merge de branches está roto del lado de Supabase (3 de 3 proyectos de branch sin registrar en su Management API → el workflow muere con 404 antes de aplicar nada; ticket de soporte en curso, branch `cierres-externos-v3` ref `evfoicrvxjxedjxhjgnj` vivo a propósito hasta que cierre). El guion aplica en UNA transacción (preflight de anclas md5 + 11 veredictos de postflight) y registró la migración en `schema_migrations` con su contenido íntegro; verificación en prod: 3 tablas nuevas · DEFINER 159→**167** · registrada=1. Antes del pase, Codex dio un TERCER NO-GO (carrera MVCC en la lectura de la reserva → `for update` con orden `leads→conversion_reservas`; reintento del dueño tras sellar; tope absoluto con `least`; `depositos_reclamados` append-only para que un número corregido no quede libre) y el TERCER ciclo quedó en verde: oráculo **28 casos** CIERRES_EXTERNOS_OK · regresión 53/236 **idénticos** · **RLS 914/914** · advisors 0 ERROR. **Edge `crm-convertir-lead` REDESPLEGADA el 2026-08-13 (v10)**, fuente local hallada byte a byte en el sourcemap del bundle y orden ejecutable verificado (reserva→sello→createUser→convertir_lead→correo). Trampa del guion: Cloudflare bloquea el User-Agent por defecto de `urllib` en `api.supabase.com` (403 código 1010) → mandar UA propio. **⚠️ ORDEN DE PUBLICACIÓN OBLIGATORIO: (1) ✅ migración, (2) ✅ REDESPLIEGUE de la edge `crm-convertir-lead`, (3) 🟡 release del front — ÚNICO paso pendiente.** Los dos sentidos duelen: si la edge sale ANTES, `crm.reservar_conversion_lead` no existe y toda conversión Avance moriría —por eso la edge degrada explícitamente ante `PGRST202`—; y si la migración se mergea y **la edge NUNCA se redespliega, el arreglo del usuario de portal huérfano queda PUESTO PERO INERTE** y nadie se entera (la edge vive fuera de este repo, en `_supabase_functions/`). Gate del ciclo anterior: oráculo CIERRES_EXTERNOS_OK (22 casos CEXT) + regresión CONVERSION_MENSUAL_OK (53 casos/236 aserciones, **idénticos**: el cambio del numerador no mueve nada) + **RLS 907/907** + advisors 0 ERROR + DEFINER 159→165 exacto. El gate RLS cazó EN VIVO la trampa NULL del `not in` heredado → allowlist con `coalesce`; ojo: **`crm.convertir_lead` (Avance) la arrastra en prod** (deniega igual por ámbito, pero con P0001) — migración aparte. `trg_equipo_validar_usuarios_jerarquia` se suspende durante seed+corrida y se REACTIVA. **El gate NO es re-ejecutable**: deja leads `% TRANSIENT` que el lector global sí ve. | Los cierres en COOPAC Qorilazo/Prodelco cuentan al vendedor en cuota y conversión SIN portal ni correo. Crea: `crm.cierres_externos` (deny-by-default absoluto, foto inmutable, un cierre por lead, **`numero_transaccion` NOT NULL con índice único GLOBAL** —no por cooperativa: la cooperativa la elige el mismo vendedor y bastaba declarar el voucher en las dos para cobrarlo doble—, `moneda` CHECK `='PEN'`, y `monto` con guarda `<> 'NaN'` porque Postgres considera NaN MAYOR que todo y envenenaba `sum()` de la cuota del equipo); `crm.conversion_reservas` + `crm.reservar_conversion_lead` + **`crm.marcar_efectos_conversion`** (la reserva DEJA DE CADUCAR cuando la edge sella que ya creó la cuenta de Auth: si caducara, una edge muerta a medias devolvía el lead al cierre en coop y quedaba un inversionista de cooperativa con portal); `crm.convertir_lead_externo`, `crm.corregir_cierre_externo`, **`crm.anular_cierre_externo`** (solo gerencia, motivo obligatorio, una sola dirección: deja de contar en cuota Y en conversión sin borrar la fila ni reabrir el lead); `crm.cierres_externos_fn` (filas + filas DEL MES para la revisión + totales + desglose; lector global SIN filas en NINGUNO de los dos bloques; el teléfono se recorta al ámbito porque el lead convertido sí se puede reasignar). **REEMPLAZA TRES cuerpos de producción, todos anclados por md5 en el preflight**: `private.leads_before_update` (P4 relajada a «convertido ⇒ perfil O cierre externo», md5 `c287f7f3…`), `crm.cumplimiento_metas_fn` (UNION ALL de externos valores-solo, md5 `b66732fe…`) y **`private.conversion_mensual_por_vendedor`** (md5 `8aa9663c…`, el núcleo aritmético ÚNICO de toda la conversión mensual: excluye del numerador los cierres anulados). Los DOS numeradores de conversión preguntan por `private.cierre_externo_anulado`, definición única: escrita dos veces a mano ya divergieron una vez. Oráculo `test-cierres-externos.sql` (28 casos finales: CEXT-00..18 + 99 y los del tercer ciclo) + bloque `testCierresExternos` en test-rls.mjs. DEFINER crm+private: 159 → **167**. |
| 20260813212332 | 20260813212332 | crm_cumplimiento_conversion_ponderada | ✅ **EN PROD 2026-08-13**, aplicada DIRECTO con `supabase/scripts/aplicar-cumplimiento-conversion-b-prod.sh` (OK explícito de Miguel; el merge de branches sigue roto). Fichero aplicado byte a byte el MISMO que auditó Codex (SHA-256 `7c5840e9…`). Verificación en vivo: fuente nueva declarada=1 · consume la definición única=1 · **fórmula vieja=0** · DEFINER sigue en **167** (no crea funciones) · registrada=1. Ancla nueva del cuerpo: `41936789…`. Advisors tras aplicar: **0 ERROR** (102 WARN / 12 INFO, la línea base; la única mención a la función es el WARN de siempre por ser SECURITY DEFINER ejecutable por `authenticated`, que es el diseño). Comprobado además que NO había riesgo de alertas injustas al aplicar con el front viejo delante: agosto tiene 16 metas con objetivo 15 % y hoy es día 13 (el front publicado avisa desde el 10), pero el divisor máximo real es **1** y el umbral de muestra son 10 → ningún aviso puede dispararse. ⚠️ Ojo al aplicarla: la ejecución la lanzó Miguel a mano (el guardia de seguridad de la sesión bloquea escrituras a producción desde el agente).</br>ESTADO ANTERIOR (se conserva por trazabilidad): ESCRITA Y VERIFICADA EN LOCAL. Es la **migración B** del plan de conversión mensual, la única de las cuatro que quedó fuera del lote del 2026-08-11 (entraron A, E, D y F). Verificación hecha SIN gastar branch, con la técnica de la 20260812000259: Postgres 16 local + stubs generados desde el catálogo de producción, y **ejecutando** la función (crear no basta: plpgsql solo valida sintaxis). El cuerpo se copió byte a byte del que dejó `20260812000259` en producción — comprobado `md5(prosrc)` fichero == producción == `d934bd98039ca9a0794138f6e7478e97`. Preflight con DOS anclas `pg_get_functiondef`: la propia función (`0cd746ef…`) y **`private.conversion_mensual_por_vendedor` (`65d3438a…`), de la que ahora depende la forma de la CTE**. Postflight ESTRUCTURAL a propósito (no llama a la función ni mira datos de negocio: un postflight que depende de datos reales vuelve frágil el replay). El payload real que produjo la función local se congeló como fixture en `app/src/lib/cumplimiento-post-migracion-b.test.ts` y se valida contra el `v.strictObject` DESPLEGADO: 6 casos, incluidos **conversión 132,5 % (>100)**, **`convertidos` (7) > `resueltos` (4)** y el payload VIEJO sin las claves nuevas (la vuelta atrás no exige redesplegar el front). Ejecutar destapó que el front exige las **6 dimensiones** de `detalles` (3 categorías × 2 monedas): con una sola, el parseo muere y los tres roles se quedan sin metas. ⚠️ El merge de branches sigue roto del lado de Supabase; el branch `cierres-externos-v3` está en el estado ANTERIOR a cooperativas (ancla `b66732fe…`) y vacío, así que no sirve de base sin re-aplicar cooperativas primero. **Vuelta atrás**: `supabase/scripts/rollback-cumplimiento-conversion-B.sql` (cuerpo verbatim de hoy). Vive FUERA de `migrations/` a propósito: con un timestamp posterior se aplicaría sola en cualquier replay y desharía la B. **Auditoría `auditor-rls` (2026-08-13): SIN BLOQUEANTES**, y refutó empíricamente el riesgo que más me preocupaba: levantó un PG17 y midió que `p_global=true,p_visibles={}` devuelve filas IDÉNTICAS a `p_global=false,p_visibles={A}` — el núcleo no tiene ni un agregado transversal (todas sus CTE agrupan por `analista_id` y devuelve como mucho UNA fila por analista), así que quien acota es la CTE `visibles`, que es la tabla conductora del join. Cinco correcciones aplicadas tras su informe: **(1) el fichero NO era una transacción** — sin `begin;`/`commit;` un `raise` del preflight aborta solo el bloque DO y el `create or replace` se aplicaba IGUAL; probado en local que ahora el cuerpo viejo sobrevive a un preflight fallido; **(2) el guard 2 del postflight era decorativo** (el literal `conversion_mensual_por_vendedor` ya vivía en dos comentarios del cuerpo viejo, así que pasaba sobre el cuerpo que decía detectar) → ahora ancla la LLAMADA `from private.conversion_mensual_por_vendedor(`, y se verificó que falla contra el cuerpo viejo; **(3) el comentario que justificaba `p_global => true` era FALSO** (decía que recortar dos veces dejaría fuera al analista que se fue; el auditor midió que da el mismo conjunto) → reescrito con la razón real: para el LECTOR GLOBAL `vendedor_ids_visibles` devuelve VACÍO y un `p_visibles` construido con ella le dejaría todo en blanco; **(4) CEXT-12 del oráculo se rompía** — asevera `resueltos de A = 4` (3 convertidos + 1 descarte) y bajo B pasa a ser el divisor de RECIBIDOS no referidos = **3** (el referido L1102 sale, justo lo que CEXT-11 ya exige a `conversion_mensual_fn`) → el aserto se bifurca por `fuentes_reales.conversion`, así que el oráculo queda verde ANTES y DESPUÉS, y post-B exige que los DOS payloads coincidan (71,67 %, numerador 2,150); **(5) `cumplimiento_metas_fn` tenía CERO casos en `test-rls.mjs`** pese a ser la función que esta migración reescribe → bloque `testCumplimientoMetas` nuevo (gerencia ve todo · sup1 no ve a vend3 de sup2 · vend1 solo a sí mismo · coordinador 200 con lista VACÍA, no 42501 · lector global igual que gerencia · vendInactive y clientBank 42501 · forma del payload post-B), con **guarda anti-vacuidad** explícita porque un snapshot vacío haría pasar todas las aserciones de ámbito sin probar nada. Anotados sin arreglar: el coste (con `p_global=true` cada llamada recorre el ledger del mes de toda la empresa — irrelevante hoy con 1-2 filas, revisar con la base fría C2) y que `pg_get_functiondef` depende de la versión mayor de Postgres, así que un salto de mayor haría abortar los preflights diciendo «cambió» cuando cambió el formateador. | La conversión de las METAS deja de tener fórmula propia y **consume `private.conversion_mensual_por_vendedor`**, la misma que pinta la pantalla. Antes la CTE `conversiones` calculaba convertidos ÷ RESUELTOS sin ponderar referidos ni arrastre, así que el mismo asesor tenía dos porcentajes distintos a 300 px: el titular y la barra de su propia meta. El front ya se unificó el 2026-08-13 (`fc261ee`, 20.º release) haciendo que la barra midiera el número servido; **esto borra la segunda definición de raíz**, que es lo único que impide que vuelvan a divergir, y de paso alinea las **alertas de gerencia**, que hasta ahora bebían de la fórmula vieja. Cambios de payload (contrato verificado contra `objetivos.ts`): `conversion_real` cambia de fórmula y **puede superar 100**; `resueltos` CONSERVA EL NOMBRE aunque ahora sea el divisor de RECIBIDOS (renombrarlo rompe el `strictObject`); `convertidos` sigue entero y **puede ser MAYOR que `resueltos`** (invariante roto a propósito); se AÑADEN `numerador`, `cierres_no_referidos`, `cierres_referidos` por vendedor y `ponderacion_referido` en el nivel superior — las cuatro `v.optional` desde el release del 11/08, así que **no hace falta un segundo despliegue de front**; y `fuentes_reales.conversion` pasa a `'leads_recibidos_ponderado'`, literal que el front acepta junto al viejo. ⚠️ Consecuencia de negocio para Miguel: el umbral de la alerta individual («casos resueltos mínimos») pasa a significar «RECIBIDOS mínimos» sin cambiar de nombre. |
| 20260813235119 | 20260813235119 | crm_anulacion_cierre_avance | ✅ **EN PROD 2026-08-14**, aplicada DIRECTO con `supabase/scripts/aplicar-anulacion-avance-prod.sh` (OK explícito de Miguel; el merge de branches sigue roto). SHA-256 del fichero aplicado: `a2ae6a4d…`. **Verificación en vivo tras aplicar**: tabla creada, las 4 funciones nuevas, la cadena de neutralización dentro de la cuota, DEFINER **167 → 169 exacto**, migración registrada y **advisors 0 ERROR** — la tabla nueva sale como `rls_enabled_no_policy` (INFO), que es precisamente el deny-by-default buscado, y la RPC como `authenticated_security_definer_function_executable` (WARN), el mismo patrón de las otras 99 RPC del CRM. Y **ejecutadas contra producción, no solo creadas** — plpgsql solo valida sintaxis al crear, así que el SQL nuevo no se había corrido ni una vez: `crm.cumplimiento_metas_fn('2026-08-01')` devuelve el período entero con las CTE nuevas dentro (16 vendedores, revisión 5, factor 0,150) y los tres helpers responden sobre leads reales. ⚠️ **EL PRIMER INTENTO ABORTÓ, y el guard era el equivocado, no la migración**: el preflight (3) —el que exige que el delegado tenga UN solo consumidor— contaba con `prosrc like '%cierre_externo_anulado%'`, y **en `LIKE` el guion bajo es COMODÍN de un carácter**, así que el patrón casaba también con la frase en castellano «cierre externo anulado» que `private.trg_cierres_externos_inmutables` lleva en su mensaje de error. Contaba 2 consumidores donde hay 1 y frenó una migración correcta. Corregido a `strpos(prosrc,'cierre_externo_anulado') > 0`, comparación literal e inmune a comodines; verificado aparte contra producción que el único que de verdad la **invoca** es `private.conversion_mensual_por_vendedor`. Lección: un guard que dice que no por una razón falsa entrena a saltárselo, que es peor que no tenerlo — y el patrón `like '%algo_con_guiones_bajos%'` sobre `prosrc` es una trampa que vuelve. ⚠️ **Hoy no hay nada que anular por esta vía**: el único lead en `etapa='convertido'` de producción cerró en COOPERATIVA (su dinero vive en `crm.cierres_externos`, no en `public.contratos`), y la RPC lo rechaza a propósito mandándolo a `crm.anular_cierre_externo`. O sea que la primera anulación de Avance real será también la primera prueba de esta cadena con datos vivos — por eso la RPC devuelve `contratos_afectados`. Verificada además con la técnica de la B: Postgres 16 local + stubs del catálogo de producción, **ejecutando** la RPC y la función. El invariante que exige la regla quedó medido de punta a punta: antes `capital=10.000 · contratos=1 · conversión=100 % · divisor=1`; después de anular `capital=0 · contratos=0 · conversión=0 % · divisor=1` — **las dos cifras bajan juntas y el divisor NO se mueve** (el lead se trabajó igual). Más 7 guardas MEDIDAS EN LOCAL: solo gerencia (42501), motivo obligatorio (22023), no se anula dos veces (P0409), lead no convertido, cierre de cooperativa redirigido a su propia RPC, append-only (no se edita ni se borra) y lead inexistente. ⚠️ **«Medido en local» NO es «cubierto por el gate»** y conviene no confundirlos: del gate cuelgan **CONV-24** (a/b/c) en `test-conversion-mensual.sql`, **M19** en `test-metas-versionadas.sql` y el bloque **H** en `test-rls.mjs`. Siguen SIN caso de gate: «lead no convertido» y «cierre de cooperativa redirigido» (los dos exigen un lead real del fixture; los otros cinco sí están cubiertos). 🔴 **EL HALLAZGO QUE JUSTIFICA EL DISEÑO**: el predicado excluye el CONTRATO ENTERO y no el enlace del lead. Se probó la versión ingenua (excluir dentro del lateral `enlaces`) contra el mismo mundo y el resultado fue que **anular REGALA el cierre**: el contrato pierde su vendedor explícito y cae al AUTOR por el `else meta_autor.vendedor_id`. Medido: Ana 10.000 → seguía en 10.000 (ella era la autora) y Beto pasaba de 0 a **7.000**. Con esa versión, anular no habría hecho nada — o peor, habría movido el mérito a otra persona. Cambio de guarda durante la construcción: la RPC preguntaba por un episodio de cierre en el LEDGER y pasó a preguntar por `etapa='convertido'`. Motivo: el ledger solo se escribe desde el movimiento del lead (`crm.ledger_writer` + `pg_trigger_depth() >= 2`), así que ningún oráculo puede fabricar un episodio; y además la cuota va por CONTRATO, no por episodio, de modo que un lead legado con contrato y sin episodio también debe poder corregirse. | **Gerencia puede anular un cierre de AVANCE.** Hasta hoy no existía ninguna forma: la práctica era borrar al cliente, y eso arregla solo la mitad — el capital sale de `public.contratos` y se iba con el contrato, pero la conversión sale del LEDGER, donde el episodio queda sellado como 'convertido' y es inmutable por diseño. El vendedor perdía el dinero y **conservaba el cierre**, con su porcentaje inflado para siempre. Regla de Miguel (2026-08-13): «si gerencia anula un cierre tiene que afectar en la conversión sí o sí, porque gerencia hará eso cuando haya errores de gestión o malas prácticas», con el alcance acotado por él mismo: lo que baja «no significa dinero real, solo baja para el vendedor». Por eso esto **no toca ni una fila de `public`**: el contrato, el cliente y la caja siguen intactos; lo único que cambia es a quién se le acredita el mérito. Crea `crm.cierres_avance_anulados` (deny-by-default absoluto, append-only por trigger, auditada, con `id` propio **porque `private.log_audit_crm` resuelve `fila_id` con `coalesce(id, perfil_id)` y sin él la anulación quedaría auditada sin fila identificable** — es el defecto (2) de cooperativas, no repetido) y `crm.anular_cierre_avance(uuid,text)`. **La pregunta «¿fue anulado?» se escribe UNA vez**: `private.cierre_anulado(uuid)` responde por los dos canales, y `private.cierre_externo_anulado` queda como DELEGADO de una línea — se conserva el nombre porque `private.conversion_mensual_por_vendedor` (11.761 caracteres) la invoca así, y renombrarla obligaría a reemplazar ese cuerpo entero, que es justo la deuda señalada en la última revisión. Con eso **la conversión aprende las anulaciones de Avance sin tocar el núcleo**. Único cuerpo reemplazado: `crm.cumplimiento_metas_fn` (copia byte a byte del post-B, `md5(prosrc)` fichero == producción == `0210e0daa1ee83896ec30d2948bb490f`) con un solo predicado añadido. Preflight con TRES anclas `pg_get_functiondef`: la propia función (`41936789…`), el delegado (`5f9dfd3d…`) y el núcleo (`65d3438a…`, porque si dejara de llamar al delegado la conversión no se enteraría de nada y este fichero mentiría en silencio). Postflight estructural. Pruebas: caso **M19** en `test-metas-versionadas.sql` (asevera el TOTAL de la empresa 964.000/5 a propósito: un aserto por vendedor pasaría igual aunque el cierre se le hubiera regalado a otro) y bloque **H** en `testCumplimientoMetas` de `test-rls.mjs` (vend1, sup1, coordinador, vendInactive y clientBank reciben 42501; gerencia pasa el gate de rol y muere en el lead inexistente, que es lo que distingue «no puedes» de «no existe»; y la tabla no se lee por la Data API). **Vuelta atrás**: `supabase/scripts/rollback-anulacion-avance.sql` — devuelve el cuerpo post-B y el delegado a mirar solo cooperativas. NO borra la tabla ni la RPC a propósito: si gerencia ya anuló algo, esa fila es la razón escrita que se le dio a una persona. **Auditoría `auditor-rls` (2026-08-13): SIN BLOQUEANTES**, con 6 correcciones aplicadas y REVERIFICADAS: **(1) 🔴 fuga real** — un contrato puede colgar de DOS leads, uno con vendedor (que lo acredita) y otro convertido SIN vendedor; anular el segundo le quitaba capital al primero, a quien nadie anuló. Medido en local: Ana perdía 3.000 sin el filtro y los conserva con él. Arreglo: `and l_anulado.vendedor_id is not null` (un lead sin vendedor no aporta mérito, así que tampoco puede quitarlo). **(2) el postflight del delegado era VACUO** — preguntaba si devolvía algo no nulo, y el cuerpo VIEJO también devuelve `false`: pasaba sobre el cuerpo que decía detectar, el mismo defecto ya corregido en la B. Ahora ancla la DELEGACIÓN (`position('private.cierre_anulado(' in ...)`). **(3) el preflight no comprobaba en la BASE** que el delegado tuviera un solo consumidor (leer ficheros no prueba que producción no tenga otro): añadido un conteo sobre `pg_proc` que exige exactamente 1. **(4)** la RPC devolvía un `ok` pelado que podía leerse como «ya bajó el dinero» cuando el lead no tiene contrato: ahora devuelve `contrato_id` y `afecta_cuota`. **(5)** el CHECK del motivo medía la longitud ANTES de recortar (divergía de cooperativas): ahora `length(btrim(motivo))`. **(6)** el comentario del orden de lock MENTÍA — decía replicar `anular_cierre_externo`, que en realidad bloquea la fila del cierre y no el lead; el orden replicado es el de `convertir_lead_externo`, que es el correcto y por una razón concreta (toma el lead ANTES de insertar el cierre, así que el `exists` no puede perderse un cierre naciendo en paralelo). ⚠️ **Deuda PREEXISTENTE que esta migración vuelve visible**: los tiles y rankings que cuentan `etapa='convertido'` en crudo seguirán pintando el lead anulado como convertido y con su monto. No lo introduce este fichero, pero con la anulación en uso se va a ver. ⚠️ **Retroactividad**: anular recalcula meses ya cerrados (cuota y conversión se recalculan en cada llamada) y es irreversible. Es lo pedido por Miguel, pero choca con el «congelado de meses liquidados» diferido — que es el punto 3 del orden acordado. DEFINER: **167 → 169** (`crm.anular_cierre_avance` y `private.trg_cierres_avance_anulados_append_only`; `private.cierre_anulado` es INVOKER a propósito). 🔴🔴 **REFUTACIÓN DE CODEX — el hallazgo más caro de la fase, y el que la salvó**: la primera versión del predicado buscaba el contrato por `crm.leads.contrato_id`, y **esa columna NO la rellena nadie**. Verificado contra producción: **371 contratos, CERO con lead enlazado; 0 leads con perfil enlazado**. `crm.convertir_lead` escribe `etapa`, `perfil_id` y `convertido_en` — nunca `contrato_id` — y el contrato se crea después sin enterarse del lead. Con aquel predicado la anulación habría bajado la conversión y **dejado el capital intacto**: exactamente la divergencia cuota↔conversión que esta migración existe para cerrar. Habríamos publicado el bug que veníamos a arreglar. ⚠️ **Y mi prueba local lo bendecía**, porque sembraba `contrato_id` a mano — un enlace que producción nunca crea. Es literalmente la trampa del `gate:realidad` documentada en `CLAUDE.md`: «los tests montan el mundo del FIXTURE y producción es otro mundo». Escribir el test en el estado que hay en producción no es una recomendación: es lo único que distingue un arreglo de una ilusión. **Arreglo**: el predicado correlaciona por el enlace que SÍ existe — `crm.leads.perfil_id = public.contratos.cliente_id`, con ventana `contrato.creado_en >= lead.convertido_en` para no tocar contratos anteriores del mismo cliente — y conserva `contrato_id` como camino (a) por si alguien lo rellena. Reverificado con la forma REAL (contrato_id NULL): capital 10.000 → 0 y conversión 100 % → 0 %, divisor intacto. 🔴 **SEGUNDA REFUTACIÓN (auditor RLS, sobre el predicado ya corregido)** — y la que dio con el diseño bueno: **la clave con la que se EXCLUÍA (el cliente) no era la clave con la que se ATRIBUYE (el autor del contrato)**. Nada comprobaba que la persona castigada fuese la del cierre anulado. Reproducción con flujos normales: Ana convierte al cliente P; meses después P **renueva con Beto**; gerencia anula el cierre de Ana → el contrato de Beto desaparecía y **Beto perdía capital en un mes cerrado sin haber hecho nada**. Peor que el residual anterior en tres ejes: no exige nada raro, no tiene techo temporal y el daño aterriza en el KPI de otra persona. **Rediseño aplicado** (cierra los DOS bloqueantes y el residual (i), sin el dilema que planteaba Codex): CTE `anulados` con `acreditado_a = coalesce(leads.vendedor_id, analista del LEDGER)` — el ledger es INMUTABLE, así que sacar al vendedor del lead ya no vuelve nada inerte —; y la neutralización se aplica **DESPUÉS de atribuir**, en `contratos_confirmados`, solo cuando el vendedor atribuido ES el acreditado del cierre anulado. Regla que esto hace explícita: **solo se le puede quitar el mérito a quien lo tiene**. Neutralizar (en vez de excluir en `contratos_base`) conserva además la garantía original de que el contrato desaparece y NO cae al autor. **Verificado en local con los tres escenarios**: (1) forma real de producción → Ana 10.000 → 0 y conversión 100 % → 0 % con divisor intacto; (2) **el caso que decide** → el mismo cliente renueva con Beto y Beto **conserva sus 8.000**; (3) respaldo del ledger → un lead sin vendedor vivo pero con cierre en el ledger sigue descontando a quien lo cerró (Beto 13.000 → 8.000, perdiendo solo lo suyo). También se corrigió `afecta_cuota`, que con la correlación nueva habría mentido **siempre**: lo calculaba desde `contrato_id` (vacío en producción) y decía «no baja» justo cuando bajaba. Ahora sale de `private.contratos_afectados_por_anulacion(uuid)` — **el mismo predicado que usa la cuota, escrito una vez** — y la RPC devuelve además la lista de contratos afectados, para que la primera anulación real sea verificable en vez de un acto de fe. Pruebas ampliadas: **M19b** siembra la forma REAL (contrato ligado solo por cliente, `contrato_id` NULL) con control positivo delante, y añade **el negativo decisivo**: la renovación de otro vendedor sobre el mismo cliente debe sobrevivir a la anulación. **Los dos puntos que quedaban abiertos, CERRADOS**: **(a) TECHO de la ventana** — el helper deja de reclamar en cuanto ese mismo cliente vuelve a cerrarse (`not exists` de un lead posterior del mismo `perfil_id` convertido antes de ese contrato). Sin él, un cierre anulado se quedaba con TODO el futuro del cliente para siempre, incluida la venta legítima que el mismo vendedor le hiciera un año después. **(b) SUELO** — se deja como está, con el razonamiento escrito: un contrato ANTERIOR a la conversión no lo produjo ese cierre, y `crm.convertir_lead` admite clientes que ya existían, así que su cartera previa es de otra historia comercial. No es un hueco: es la semántica correcta. **Y la regla se escribe UNA sola vez de verdad**: la cuota dejó de reimplementarla — CTE `neutralizados` que consulta el MISMO `private.contratos_afectados_por_anulacion` que usa la RPC. Escribirla dos veces es lo que costó dos rondas de revisión esta semana. **Verificación final con los cuatro límites en un solo escenario**: cliente P con contrato previo de Ana (4.000), cierre de Ana (10.000), recierre posterior de Ana (7.000) y renovación de Beto (6.000). Al anular el primer cierre de Ana: **21.000 → 11.000** — pierde SOLO los 10.000 de ese cierre, conserva el previo (suelo), conserva el recierre (techo) — y **Beto intacto en 6.000** (solo se le quita a quien lo tiene). `contratos_afectados` devuelve exactamente un contrato. Conversión de Ana 0 % con divisor intacto. Las 7 guardas, en verde. 🔴 **TERCERA LECTURA (auditor RLS)** — «en el SQL ya no queda ningún BLOQUEANTE», pero cazó uno del CICLO y dos ALTO, todos corregidos: **(1) 🔴 M19b no podía ejecutarse**: reutilizaba los ids de contrato `…109`/`…110` que el fixture base YA inserta → `23505 duplicate key` abortaba el fichero ANTES de un solo aserto. O sea que **el caso que prueba el rediseño entero no probaba nada**. Reasignados a `…111`/`…112`. Es la lección del `gate:realidad` en su versión más cruda: no es que bendijera un mundo falso, es que no llegaba a correr. **(2) 🔴 `acreditado_a` miraba primero `crm.leads.vendedor_id`, que es MUTABLE** (la policy `leads_update` deja a gerencia reasignar un lead aunque esté convertido) mientras la CONVERSIÓN descuenta al `analista_id` del LEDGER, que es inmutable. Bastaba una reasignación para que las dos mitades castigaran a personas distintas — y, si el nuevo vendedor le había vendido algo a ese cliente, para quitarle capital a él: el mismo bug entrando por otra puerta. **Invertido: el ledger manda y `vendedor_id` queda solo como respaldo del legado sin episodio.** Verificado: lead cerrado por Ana y reasignado a Beto → anular descuenta a ANA y Beto queda intacto. **(3) esa regla estaba escrita DOS veces** (helper + CTE) y si divergían el `exists` no casaba nunca y la neutralización quedaba **inerte en silencio** → extraída a `private.vendedor_acreditado_del_cierre(uuid)`. **(4) el postflight anclaba un literal que puede sobrevivir muerto** (una CTE sin referenciar ni se evalúa) → ahora ancla la CADENA: el `cross join lateral` al helper y el `from neutralizados n`. **(5) `anulados` recorría `crm.leads` ENTERA** llamando a la función por fila, en cada carga de la pantalla de Metas → ahora la conducen las dos tablas de anulación, que son diminutas. **(6) `afecta_cuota` podía prometer de más** (contratos de moneda o categoría que la cuota ni mira) → filtros añadidos. **(7)** comentarios de cabecera que describían el diseño anterior, corregidos: en este repo los comentarios guían el próximo cambio. Anotado sin arreglar (**el auditor lo clasifica como agujero que NO daña a terceros**): el helper compara por `c.creado_por` y la cuota puede atribuir por enlace explícito de lead; si un contrato enlazado lo creó otra persona, la conversión baja y la cuota no. Hoy es teórico (0 contratos enlazados en producción) y falla siempre hacia «la cuota no baja», nunca hacia castigar a un inocente. 🔴 **TERCERA LECTURA DE CODEX** — cuatro más, tres aceptados y uno discutido: **(a) la anulación no guardaba FOTO de a quién se le acreditó**, así que se RECALCULABA en cada consulta; para el legado sin episodio en el ledger eso depende de `crm.leads.vendedor_id`, y reasignar un lead ya anulado devolvía sus contratos al primero y podía borrarle los suyos al segundo. **Columna `acreditado_a` sellada al anular** — cooperativas ya fotografía su cierre; esto faltaba. Verificado: tras anular y reasignar a otro vendedor, nada se mueve. **(b) el techo usaba orden PARCIAL**: `now()` es constante dentro de una transacción, así que dos conversiones del mismo cliente pueden empatar al microsegundo y ninguna cerraba el techo de la otra → **orden total `(convertido_en, id)`**. **(c) `convertido_en` NULL** dejaba muerta la correlación por cliente y la anulación bajaba conversión sin tocar un sol, en silencio → la RPC ahora lo **rechaza con mensaje explícito**. **(d)** `afecta_cuota` podía prometer sobre un contrato que la cuota deja sin atribuir por tener leads de vendedores distintos → el helper **espeja esa misma regla de ambigüedad**. **DISCUTIDO (no aceptado como defecto)**: Codex marca como bloqueante que un cierre de fin de mes y su contrato del mes siguiente hagan bajar la conversión en un mes y la cuota en el otro. Eso NO lo introduce esta migración: los dos números ya viven en relojes distintos por diseño —la conversión fecha por el cierre del ledger y la cuota por `contrato.creado_en`— y la anulación quita cada uno del mes en el que estaba, que es lo correcto. Cada mes queda internamente coherente. Si se quisiera un solo reloj, es una decisión de negocio aparte y muy anterior a esto. ✅ **COBERTURA DE GATE COMPLETADA — caso `M19c`** en `test-metas-versionadas.sql`, que monta un solo mundo con los CINCO límites y los aserta por separado, cada uno nacido de un bloqueante real: **SUELO** (contrato anterior a la conversión sobrevive) · **TECHO** (si el cliente vuelve a cerrarse, el cierre viejo deja de reclamar) · **TERCERO** (la venta de otro vendedor al mismo cliente no se toca) · **FOTO** (reasignar un lead YA anulado no recalcula a quién se castigó) · **PAYLOAD** (`afecta_cuota` true y `contratos_afectados` con EXACTAMENTE el contrato que cae — si reclamara de más, el suelo, el techo o el de otro vendedor se habrían colado). Con **control positivo delante** (si el mundo no está montado, el caso grita en vez de pasar por vacuidad) y aserto de que A pierde 5.000 **y solo 5.000**. Más tres guardas por SQL: lead no convertido, anulación legítima del recierre y append-only. ⚠️ Antes de escribirlo se verificó que los ids nuevos (contratos 113-116, leads 211-212, cliente `ca`) estuvieran LIBRES — el descuido que abortó M19b la primera vez. Comprobado por script: cero PK duplicadas y cero `numero_contrato` repetidos en todo el fichero. |
| 20260814100746 | 20260814100746 | crm_cierre_estado_lectura | ✅ **EN PROD 2026-08-14**, aplicada DIRECTO con `supabase/scripts/aplicar-cierre-estado-prod.sh` (OK explícito de Miguel; el merge de branches sigue roto). SHA-256 `1346ed52…`. Verificación en vivo: función DEFINER creada, DEFINER total **169 → 170 exacto**, registrada, y —lo que más importa— **las tablas de anulación siguen cerradas**: cero policies y no legibles por `authenticated`. Esto abre una ventana, no una puerta. **Y EJECUTADA contra producción con las SEIS condiciones del contrato**, no solo creada: gerencia recibe la fila real (el único convertido de prod, canal `cooperativa`, sin anular) · el **dueño** del lead recibe 1 fila · un **vendedor ajeno recibe 0** (la frontera del predicado espejado, medida con el MISMO lead y dos llamadores) · lote vacío devuelve `[]` sin viajar · el tope de 200 frena con 22023 · sin sesión, 42501. ✅ **Y EL CANAL AVANCE, PROBADO TAMBIÉN** — que era el único hueco real: producción solo tiene un convertido y cerró en COOPERATIVA, así que todo lo anterior pasó por la otra rama y un fallo en el join contra `cierres_avance_anulados` habría quedado invisible (el defecto vacuo que ya mordió dos veces en esta familia). Técnica, reutilizable: un bloque `DO` que siembra la anulación, llama a la función y **termina SIEMPRE en `raise`** — al ser una sola sentencia, Postgres la deshace entera por construcción, no hay camino en el que quede algo escrito, y el resultado se lee del propio mensaje de error. Veredicto: gerencia recibe `canal='avance'` con fecha y **el motivo entero**, y un vendedor ajeno recibe **0 filas** (el motivo es lo sensible y tampoco se escapa). Comprobado después: 0 anulaciones, 0 leads de prueba, 0 actividades — producción exactamente como estaba. ⚠️ Dos candados del servidor que salieron a la luz de paso y conviene recordar: **un lead no puede NACER terminal** («Un lead debe nacer activo y en etapa operativa») y **la conversión solo se hace vía su operación** («La conversión a cliente solo se hace vía la operación de conversión») — por eso la prueba ataca la VENTANA y no fabrica un convertido a mano; forzarlo habría exigido `disable trigger` sobre `crm.leads`, que toma un lock exclusivo sobre una tabla viva. ⏳ Queda el gate de RLS (bloque 3bis) y M19c como REGRESIÓN, en el próximo ciclo de branch: no se pueden correr sobre producción porque el gate siembra y deja leads transitorios. **La ventana que le faltaba a la anulación.** La 20260813235119 le dio a gerencia la puerta, pero `crm.cierres_avance_anulados` es deny-by-default con cero policies y cero grants —y el gate lo comprueba a propósito (`test-rls.mjs`, «no se lee desde la Data API»)—, así que la anulación era **invisible para la aplicación**: gerencia anularía, recargaría y vería el lead exactamente igual que antes; el segundo intento moriría con «ese cierre ya estaba anulado». Una acción cuyo efecto no se ve es una acción que se repite. Crea `crm.cierres_estado_fn(uuid[])`, que devuelve una fila **por lead que tiene algo que decir** —cerró en cooperativa, o su cierre está anulado por cualquiera de los dos canales— con `canal`, `anulado_en` y `motivo`. El convertido de Avance sano NO viaja: es el caso por defecto del front, y así el payload no crece con la operación normal. **El `canal` no es adorno**: es lo único que impide ofrecerle a gerencia el botón de Avance sobre un cierre en COOPERATIVA, que `crm.anular_cierre_avance` rechaza a propósito — y hoy ese es literalmente el ÚNICO lead convertido que hay en producción, o sea que sin el canal el primer botón que gerencia vería sería el que no funciona. ⚠️ **Es `SECURITY DEFINER` y eso obliga a espejar el ámbito.** La regla de la casa para una RPC que devuelve filas de leads es INVOKER («el ALCANCE lo pone la RLS», `cartera_pagina_fn`, 20260810141953), pero aquí es imposible: las dos tablas de anulación no tienen ni una policy, así que un INVOKER no vería ni una fila y la función **mentiría devolviendo «no hay anulaciones»**. Mismo caso que `cierres_externos_fn`. El precio es un predicado copiado de `leads_select`, y un predicado copiado se desincroniza en silencio → el preflight **ancla el md5 del `using` de la policy** (`4fc91b80…`) y el gate compara **conjuntos**, no ejemplos. El gate restrictivo `crm_actor_activo_gate` no se copia: se **invoca** (`private.puede_acceder_crm()`), que es lo único que no puede divergir. Tope de 200 ids, alineado con `p_limite` de `cartera_pagina_fn`: esto sirve a una página en pantalla, no a un volcado. Postflight estructural: mira los dos canales, conserva el recorte de ámbito y **verifica que las tablas de anulación siguen sin policies y sin ser legibles por `authenticated`** — esta migración da una ventana, no una puerta. **Verificado EJECUTANDO contra producción antes de aplicar** (no solo creando: plpgsql valida sintaxis y nada más): el cuerpo completo corrió como bloque anónimo suplantando a gerencia y devolvió el estado real (el lead de coop, canal `cooperativa`, sin anular), y el recorte se midió con el MISMO lead pedido por su dueño (1 fila) y por un vendedor ajeno (0 filas). **Pruebas**: bloque **3bis** en `test-rls.mjs` (la frontera con el mismo lead y dos llamadores, el coordinador con ámbito ∅ que pasa el gate y recibe `[]`, cliente y revocado con 42501, el tope de 200, y un lead propio sin nada que decir preguntado **por su dueño** para que el vacío signifique «no hay nada» y no «no lo ves»); y la ampliación de **M19c** en `test-metas-versionadas.sql`, que es donde el caso Avance importa: allí sí existe un cierre de Avance anulado, y se asevera que la ventana lo muestra con canal `avance`, fecha y **el motivo entero**. Sin ese caso, `cierres_estado_fn` podría devolver vacío para TODO el canal Avance y el gate seguiría en verde — el cierre de cooperativa solo prueba el otro canal. |

⚠️ **Las cuatro son UNTRACKED y por eso se pueden reescribir en sitio** (la regla
de «nunca editar una migración ya commiteada» empieza a aplicar en el commit).
En cuanto se commiteen, cualquier corrección es una migración nueva.

⚠️ **Ninguna de las cuatro entra en el registro de excepciones a `public`**: no hay
un solo DDL sobre `public`. La A **inserta datos** en `public.audit_log` a través
del trigger de auditoría de la casa (`private.log_audit_crm`), que es el patrón
obligatorio de `LEEME.md` para toda tabla `crm.*`, y la D **lee** `public.perfiles`
por los helpers de siempre. Escribir una fila de auditoría no es alterar el
portal; crear, borrar o modificar un objeto sí lo sería.

**Orden de aplicación en el branch: por timestamp, A → D → E.** Es también el
orden lógico: D declara en su cabecera que va después de A (la métrica debe
existir antes que el sello que la protege), y E es independiente de las dos —
puede ir en cualquier posición mientras vaya en el mismo branch. Las tres en una
sola pasada de gate.

### 20260811154434 — la conversión mensual ponderada

**Qué cierra.** El negocio no tenía forma de contar la conversión de un mes: se
calculaba en el navegador, con reglas distintas según la pantalla. Esta
migración la pone en el servidor, entera y con una sola definición. Crea:

- `crm.conversion_pesos` — el **15 % versionado por mes** (`vigente_desde` =
  primer día del mes, `peso_referido numeric(4,3)`, `nota`). Con la constante en
  el código, cambiar el peso **recalcularía todo el histórico** y nadie podría
  reconstruir con qué regla se pagó marzo. RLS ON con **cero policies y cero
  grants** (deny-by-default absoluto para la Data API; precedente aceptado:
  `crm.cuentas_bancarias`, `crm.contrato_cuentas_pago`, `crm.lead_sla_*`), y
  trigger de auditoría `trg_audit_conversion_pesos`. Dispara el advisor INFO
  `rls_enabled_no_policy`, de la clase ya aceptada.
- `private.peso_referido_conversion(date)` y `private.etiqueta_mes_es(date)`.
- `private.conversion_mensual_por_vendedor(timestamptz, timestamptz, boolean,
  uuid[], numeric)` — el motor.
- `crm.conversion_mensual_fn(date)` — la RPC, `security definer`,
  `search_path = ''`, `grant execute … to authenticated`, con **gate explícito
  42501 antes de tocar ningún dato** (nunca RLS implícita).
- Cuatro índices: `lead_asignaciones_convertido_analista_idx`,
  `lead_asignaciones_convertido_fecha_idx`, `idx_leads_convertido_en`,
  `idx_leads_creado_por_referido`.

La regla, en una línea: **divisor** = leads NO referidos que el asesor RECIBIÓ en
el mes (entran los abiertos y los descartados; los referidos quedan fuera);
**numerador** = cierres del mes, no referidos ×1 + referidos ×0,15, atribuidos al
`analista_id` de la fila inmutable que cerró. Caso canónico de Ana: 90 no
referidos + 20 referidos, cierra 16 y 12 → **17,80 / 90 = 19,78 %**, de los que
los referidos aportan 2,00 puntos.

**La decisión de reloj.** Todo se fecha en **`America/Lima`**, y los dos extremos
del mes se construyen como `p_periodo::timestamp at time zone 'America/Lima'` —
nunca comparando fechas sueltas, que es como se cuelan los cierres de la
medianoche del día 1 en el mes de al lado. El **divisor** se fecha por
`asignado_en`; el **numerador**, por **`coalesce(resultado_en, finalizado_en)`**.
Ese `coalesce` es el cinturón del agujero 1: la migración E hace imposible que
`resultado_en` sea nulo en un cierre, pero la métrica no depende de ello para no
perder un cierre en silencio, que es la peor forma de fallar para un informe que
decide sueldos. En la misma línea, los cierres se cuentan con
**`count(distinct la.lead_id) filter (…)`**, no con `count(*)`: es el cinturón
del agujero 2 y además es lo que ya hacía el divisor, por el mismo motivo
(A→B→A dentro del mes le pesa **uno** a A: se cuenta el LEAD, no el episodio).
Dos detalles más del reloj: un **mes futuro** se rechaza con `22023` (el default
de copiar `cumplimiento_metas_fn` habría sido devolver un payload de ceros), y el
**suelo histórico** se CALCULA (`min(asignado_en) where not aproximado`, hoy
`2026-08-05 18:19:55+00` porque la limpieza del 5 de agosto se llevó las filas de
julio) — ningún test puede fijar una constante ahí.

**La decisión de roster.** El universo de la métrica es
**`private.roster_metas_vendedores()`**, la fuente única que nació en
`20260810163458`. No se define un roster propio: dos definiciones del mismo
conjunto no divergen el día que se escriben, divergen el día que los datos
estrenan un caso que ninguna contemplaba — y eso ya costó un ciclo. Hoy en
producción son **16 en el roster frente a 17 con rol efectivo**, así que hay
exactamente una persona que, al consultar su propia conversión, recibía una
pantalla en blanco sin explicación y un `medible = true` calculado sobre el
ledger de los demás. Ahora se le dice **por qué**, con el mismo vocabulario
cerrado de tres motivos que ya usa Configuración → Usuarios (`sin_supervisor`,
`supervisor_inactivo`, `supervisor_no_es_supervisor`). ⚠️ El front declara
`cobertura.motivo_no_medible` como `v.picklist`: **añadir un valor más adelante
rompe la pantalla**, así que el vocabulario es CERRADO
(`null · sin_ledger · anterior_al_ledger · mes_parcial` + los tres del roster).
Una sola excepción deliberada al recorte por ámbito: `cobertura.suelo_historico`
es `min(asignado_en)` de TODO el ledger y viaja también al vendedor — es una
propiedad del LEDGER, no de una persona, y recortarla haría que dos roles
dijeran cosas distintas del mismo mes. Es un timestamp de instalación, sin PII.

**El aviso del orden de despliegue: SERVIDOR PRIMERO, y sin prisa por el front.**
No cambia ni un byte del payload de ninguna función existente y **nadie la lee
todavía**, así que no hay regresión posible: puede vivir en producción semanas
sin que la pantalla cambie. Lo que **no** puede es adelantarse a su front la
**migración B** (unificar `cumplimiento_metas_fn`), que sí reescribe un payload
que la pantalla ya consume: B va **la última**, después del front. Regla de la
casa en [[crm-orden-deploy-front-primero]].

**Dos precisiones que la auditoría exigió dejar por escrito**, porque la cabecera
decía menos de lo que hacía:

- **No es «100 % aditiva» en sentido estricto.** Crea
  `trg_audit_conversion_pesos`, que **INSERTA en `public.audit_log`**. Cero DDL
  sobre `public` y patrón obligatorio de la casa, pero la frase original era
  imprecisa y una imprecisión en la cabecera es la que hace que la próxima
  auditoría desconfíe del resto.
- **Los cuatro índices se crean sin `CONCURRENTLY`, dentro de la transacción**, y
  eso es aceptable **hoy** por un dato concreto: producción tiene **1 lead y 1
  episodio**, así que el lock es instantáneo. Dejaría de serlo con
  `crm.lead_asignaciones` en el orden de 10⁵ filas: a partir de ahí hay que
  sacarlos de la transacción y crearlos `concurrently`.

**El estado real de la base, para que nadie confunda «funciona» con «dice algo»**:
producción tiene hoy 1 lead, 1 episodio abierto, 0 cierres y 0 referidos. El día
que se publique, esta métrica va a decir «mes parcial» y «sin actividad» para los
16 del roster, **y eso es correcto**. Los tests de pantalla van en el estado de
producción (vacío), no solo con el fixture lleno — regla del `gate:realidad`.

### 20260811190310 — los dos agujeros del ledger, cerrados en la raíz

**Qué cierra.** Dos filas que la métrica no sabría contar y que **hoy la base
admite**. Las dos se comprobaron con `INSERT` reales sobre una réplica de los
constraints en un PostgreSQL 16.14 efímero, no por lectura del SQL.

- **Agujero 1 — el cierre sin fecha.** `lead_asignaciones_cierre_consistente`
  exige, en la rama `motivo_cierre = 'convertido'`, que `resultado_en =
  finalizado_en`. Con `resultado_en` NULL esa comparación da **NULL**, la rama da
  NULL, el `OR` da NULL y **el CHECK PASA** — un CHECK solo rechaza en FALSE.
  Resultado: un cierre `convertido` con `resultado_en` nulo, **invisible** para el
  numerador: divisor 1, numerador 0, **0 % en vez de 100 %**. Y una **variante que
  casi se escapa**: `motivo_cierre = 'convertido'` con `resultado` **también**
  nulo entra igual, y a esa no la vería un índice que solo mirase `resultado`.
- **Agujero 2 — el cierre contado dos veces.** El EXCLUDE
  `lead_asignaciones_sin_solape` usa `tstzrange(asignado_en,
  coalesce(finalizado_en, 'infinity'), '[)')`: si `finalizado_en = asignado_en` el
  rango es **vacío**, y un rango vacío no se solapa con nada. Dos cierres
  `convertido` del mismo lead conviven y `count(*)` canta **200 % con divisor 1**.

**El hallazgo que decide el arreglo, y que descarta el arreglo obvio:** la
duración cero **no es necesaria** para el doble conteo. Dos episodios
`convertido` **adyacentes y no vacíos** —`[10:00, 11:00)` y `[11:00, 12:00)`—
también pasan el EXCLUDE. Endurecer `finalizado_en > asignado_en` **no cierra el
agujero**: solo tapa una de sus formas. Con los tres casos sembrados, el
`count(*)` de la migración A devolvió 1, 2 y 2 conversiones para 3 leads.

**El arreglo, en dos piezas:**

1. **Des-trivaluar el CHECK.** Se hace en migración nueva (`drop constraint` +
   `add constraint … not valid` + `validate constraint`), nunca editando la
   20260717212639. En las ramas `convertido` y `descartado` se escribe
   `resultado is not null and resultado = '…'` y `resultado_en is not null and
   resultado_en = finalizado_en`. La forma robusta es exigir la **no nulidad**
   con `is not null`, jamás con una igualdad. **Todas las demás ramas se
   reproducen byte a byte** desde el `pg_get_constraintdef` de producción.
2. **Un único parcial que diga «un lead se convierte una sola vez»:**

   ```sql
   create unique index lead_asignaciones_una_conversion_por_lead_idx
     on crm.lead_asignaciones (lead_id)
     where motivo_cierre = 'convertido' or resultado = 'convertido';
   ```

   El predicado mira **las dos columnas a propósito**: cubre las dos variantes
   NULL del agujero 1 y deja de depender del orden en que se apliquen las dos
   piezas. Con el CHECK endurecido los dos términos coinciden y dejar ambos no
   cuesta nada.

**Por qué un índice y no un trigger.** Hoy «un lead se convierte una sola vez» lo
sostiene **únicamente** `private.trg_leads_guard_tenencia` («Un lead convertido
no se puede reabrir», `20260803164348:562`), verificado contra el cuerpo **vivo**
de producción: existe, está habilitado (`tgenabled = 'O'`) y —a diferencia de
`leads_before_update`— **no tiene válvula `op_privilegiada`**, así que ni una RPC
privilegiada lo deshace. Pero es **código**: no sobrevive a un `disable trigger`
—patrón ya usado sobre esta misma tabla en `20260807203757:747-748`—, ni a
`session_replication_role`, ni a un backfill privilegiado. El índice escribe la
invariante en el **almacenamiento**, que es donde nadie la puede apagar.
Verificado además que **no existe salida de `convertido`** por ninguno de los
tres caminos de retroceso: `retroceso_por_anular_reunion` y el re-encolado exigen
`reunion_agendada` en su propio `WHERE`, y `deshacer_descarte` exige
`descartado`. La única salida de un estado terminal en todo el CRM es
descartado → nuevo.

**La decisión de reloj — la que prohíbe el arreglo fácil.**
`statement_timestamp()` es **constante dentro de una función plpgsql** (medido:
una función con `pg_sleep(0.2)` entre dos lecturas devuelve `t1 = t2`), y el
ledger sella apertura y cierre con **ese** reloj (`v_evento_en`,
`20260717212639:602` y `:636`; `creado_en` forzado en `:367`). Por tanto,
cualquier comando que mueva **dos veces** la tenencia del mismo lead abre y
cierra el episodio **en el mismo instante**: los episodios de duración cero son
alcanzables y algunos son **papeleo verdadero** (un traspaso o un parqueo
instantáneo ocurrió de verdad; un backfill que solo conoce un instante es
legítimo). Por eso `lead_asignaciones_intervalo_valido` se escribió con `>=` y no
con `>`, y por eso **NO se toca**: con `>` estricto, un reparto correcto abortaría
con `23514` desde el propio trigger del ledger. Tampoco se pasa el EXCLUDE de
`'[)'` a `'[]'`: haría chocar dos episodios legítimos consecutivos en su instante
de relevo. El rango vacío no era el problema de fondo; el problema de fondo era
que **nada decía que un lead se convierte una sola vez**.

**La decisión de roster: ninguna, y es deliberado.** La integridad del ledger no
se filtra por roster ni por `activo`. Un episodio de la persona que hoy está
fuera del roster (17 con rol efectivo, 16 en el roster) queda **igual de sujeto**
a la constraint aunque su conversión no se cuente en ninguna métrica. Es la misma
distinción que ya está escrita en [[crm-conversion-descartados-cuentan]]: una
cosa es qué se **ve**, otra qué se **cuenta**, y otra qué se **almacena**.

**Preflight y postflight.** Preflight que aborta si existe **una sola** fila que
violaría lo que se va a exigir, diciendo cuántas y con qué SQL encontrarlas.
Postflight que **ejercita** el comportamiento en subtransacciones que se
deshacen: debe **rechazar** el cierre `convertido` con `resultado_en` nulo, el
cierre con `motivo_cierre = 'convertido'` y `resultado` nulo, la segunda
conversión **adyacente** y la segunda conversión de **duración cero**; y debe
**aceptar** los descartes repetidos del mismo lead en ciclos distintos, el
descarte en el ciclo 1 con conversión en el ciclo 2, los episodios de duración
cero `transferido`/`parqueado`, y el episodio abierto conviviendo con el
histórico. Un postflight que solo mire `pg_constraint` no prueba que el agujero
esté cerrado: **solo una inserción rechazada lo prueba**.

**Producción, verificada por SELECT y no supuesta** (proyecto
`dctqcbznekcyxhjujuci`, solo lectura): `crm.lead_asignaciones` = 1 fila, 1
abierta, 0 con `resultado`, 0 cierres convertidos con `resultado_en` nulo, 0 con
`finalizado_en = asignado_en`, 0 leads con dos conversiones. `crm.leads` = 1
fila, 0 convertidos, 0 descartados, 0 con `ciclo_actual > 1`. **Los dos
endurecimientos entran con cero filas en conflicto.**

**El aviso del orden de despliegue.** Es **puro servidor, sin front**: no hay
payload que cambie ni pantalla que avisar. Va en el **mismo branch** que la A y
cuanto antes mejor, por una razón asimétrica: aplicarla **antes** de que la
métrica esté en pantalla no puede romper nada, mientras que aplicarla **después**
significa que cualquier fila mala colada entretanto haría fallar el
`validate constraint` en producción, con la migración a medio aplicar. El
`create unique index` va sin `CONCURRENTLY` por lo mismo que en la A: 1 fila.

⚠️ **Aviso para el futuro:** si una migración posterior choca con este índice
—típicamente un backfill que intente escribir dos cierres `convertido` del mismo
lead con `trg_lead_asignaciones_00_inmutables` apagado—, **la equivocada es la
migración**, no el índice. Ese es hoy el único camino alcanzable del agujero 2, y
es exactamente el que el índice existe para cerrar.

### 20260811190324 — el origen de un lead deja de moverse por UPDATE

**Qué cierra.** `crm.leads.origen` pasa a ser **inmutable**: un UPDATE que
intente cambiarlo **lanza excepción** con un mensaje útil. La métrica no lee esta
columna —lee el **snapshot** `crm.lead_asignaciones.origen`, inmutable por
trigger desde el día uno (T4)—, pero la palanca que quedaba abierta es la que va
del UPDATE al snapshot **futuro**: un lead todavía sin episodio (cola global,
bandeja del supervisor, base fría) cuyo origen se cambie antes de asignarlo entra
—o sale— del divisor con el valor nuevo; y un lead reasignado abre un episodio
nuevo que vuelve a fotografiar la columna viva, con lo que el mismo lead podría
contarse con **dos reglas distintas en el mismo mes**.

**Lo que esta versión TIRA, por decisión de Miguel de hoy.** La versión anterior
de este fichero traía la **ventana de corrección de gerencia de 24 h**, con su
propagación al ledger, su regla TODO-O-NADA y su `P0409`. Queda **descartada
entera**. Toda su complejidad —escribir en `crm.lead_asignaciones`, y por tanto
debilitar «un episodio cerrado es inmutable», que es la frase más fuerte del
ledger— nacía de resolver un problema que **no existe**: en todo
`public.audit_log` hay **CERO** cambios históricos de origen. Con la ventana se
van también todos los reparos del auditor sobre concurrencia, orden de triggers y
meses ya cerrados. **La corrección de gerencia queda APARCADA**, y el motivo
queda escrito aquí para que se entienda dentro de seis meses: no se quitó por
difícil, se quitó por **innecesaria**.

**La decisión de reloj: ninguna, y ésa es la decisión.** Sin ventana no hay
`creado_en + interval '24 hours'` que comparar, y con ella desaparece el borde
más feo que tenía la versión anterior: un lead creado el **31 de agosto a las
23:00** era corregible hasta el **1 de septiembre a las 23:00**, y esa corrección
movía el divisor de **agosto**, un mes ya cerrado. La inmutabilidad **no
caduca**, así que no hay reloj, no hay medianoche de fin de mes y no hay
`America/Lima` que acertar.

**La decisión de roster: no se toca, y el sello no distingue rol.** No hay
excepción para gerencia, ni para el coordinador, ni para `service_role`. La única
diferencia entre unos y otros es la **válvula**, y ése es el punto siguiente.

**La colocación, que es lo único delicado.** El sello va **POR DEBAJO del gate de
`crm.op_privilegiada`**, igual que las demás protecciones de la casa que
necesitan una válvula de escape. La versión anterior lo puso **por encima** y el
auditor lo marcó como grave: dejaba el dato **incorregible para siempre**, y el
único remedio habría sido un `disable trigger` en producción, que `CLAUDE.md`
prohíbe. Con el sello debajo del gate, una operación privilegiada y auditada
siempre puede corregir un origen el día que de verdad haga falta.

El cuerpo de `private.leads_before_update()` se saca **íntegro** con
`pg_get_functiondef` contra producción y se reproduce con **todas** sus
protecciones y **en el mismo orden** —incluidas «La conversión a cliente solo se
hace vía la operación de conversión» y la exigencia de `perfil_id` no nulo—:
perder una sola en la reescritura abre un agujero distinto del que se venía a
cerrar. La lista completa, protección por protección, va en la cabecera del
fichero.

**Y aquí está la diferencia con las otras dos: ésta TOCA UN CAMINO DE
ESCRITURA.** Es la única de las tres que puede romper algo en caliente, y por eso
se comprobó quién escribe `origen` **antes** de escribirla:

- El front actualiza leads con **cambios parciales** (`actualizarLead`,
  `app/src/data/crm-api.ts:1095`) y **hoy no ofrece editar el origen**.
- Los escritores de `origen` verificados son de **ALTA, no de UPDATE**: el edge
  `crm-importar-leads` lo manda en el `insert`
  (`supabase/functions/crm-importar-leads/index.ts:373`) y
  `crm.crear_lead_si_disponible` lo recibe como `p_origen`.
- Aun así, el sello se escribe con **`is distinct from`**: un UPDATE de payload
  completo que reenvíe el **mismo** valor **no lanza nada**. Ésa es la diferencia
  entre sellar una columna y romper a un importador, y el postflight lo ejercita
  como caso positivo (cambiar el origen **falla**; reenviar el mismo origen
  **pasa**; cambiar otra columna **pasa**; la operación privilegiada **sí** puede
  cambiarlo).

**El aviso del orden de despliegue.** No es el caso de «front primero» de
[[crm-orden-deploy-front-primero]] —no hay clave nueva en la respuesta que el
front deba tolerar—, sino su **espejo**: es un **endurecimiento del request**, o
sea una escritura que el servidor empieza a rechazar. La regla ahí es **el
escritor primero**: se verifica que ningún escritor manda `origen` en un UPDATE
con valor distinto (hecho, arriba), y **solo entonces** se aplica. Y va
**después de la A**: la métrica debe existir antes que el sello que la protege.

**El rastro de un intento denegado no está donde parece.** `trg_audit_leads` es
`AFTER` y la excepción **aborta la transacción**, así que la fila de auditoría se
va con ella: la excepción deja exactamente las **mismas cero líneas** en
`public.audit_log` que dejaría una restauración muda. El rastro real es un
**`raise warning` inmediatamente antes de cada `raise exception`**: un WARNING se
escribe en el log de Postgres en el momento en que se emite, **sobrevive al
rollback** y queda consultable por `get_logs`. La auditoría en tabla solo existe
para la corrección **autorizada**, que sí commitea.

**Por qué excepción y no restauración muda**, que es el patrón de la casa para
las columnas inmutables (`id`, `creado_por`, `creado_en`, `ciclo_actual`,
`sla_global_*`, `clasificacion_auto`, `descartado_*`, `tenencia_desde` — ninguno
de los cuales se toca aquí): por **honestidad**. `aplicar()` es optimista en el
store, así que con un 200 mudo gerencia vería el valor nuevo en pantalla y
cerraría la pestaña convencida de que el lead salió del divisor. Con la
excepción, el intento aborta y el error llega al cliente.

**Lo que esta migración NO consigue, sin adornos.** El origen **se elige en el
alta**. `crm.crear_lead_si_disponible` es ejecutable por `authenticated`, su gate
admite el rol `vendedor`, valida `p_origen` solo contra el dominio de 8 valores
del CHECK `leads_origen_check` y para un vendedor **autoasigna** el lead. Un
analista puede, por tanto, **dar de alta como `referido`** los leads que no
espera cerrar y sacarlos de su propio divisor desde el primer segundo. Sellar el
UPDATE impide **reescribir** el origen después; no impide **elegirlo mal al
nacer**. Cerrar esa puerta es otra migración, sobre otra función, y exige que
Miguel decida **qué rol puede declarar un referido**.

⚠️ **Sobre el nombre del fichero:** conserva `…_correccion_gerencia.sql` aunque la
corrección de gerencia ya no exista dentro, porque renombrarlo obliga a un
timestamp nuevo. Si al desplegar se le pone uno nuevo, **esta fila se renombra y
el fichero viejo se BORRA**: no pueden convivir dos ficheros que reescriben el
mismo trigger.

### Ciclo obligatorio de las CUATRO — EJECUTADO EN BRANCH el 2026-08-11 ✅

Branch `conversion-mensual-a-e-d-f` (`zmrzjsmhgmiwtxnnhkex`), con el orden
**corregido**: seed → aplicar (`20260811154434` → `20260811190310` →
`20260811190324` → `20260811210049`) → sondas → oráculo → RLS → advisors.

| Gate | Resultado |
|---|---|
| Aplicación por `psql` (sondas visibles) | 4/4 `exit=0`, **cero WARNING**: todas las sondas corrieron su rama real |
| Replay desde el registro (reset del branch) | 86 migraciones, las 4 nuevas incluidas — **ensayo exacto de lo que hará el merge** |
| Oráculo | **`CONVERSION_MENSUAL_OK` · 53 casos · 236 aserciones · rollback limpio** (×2: mundo pre-reset y mundo virgen) |
| `test-rls.mjs` | **✅ RLS OK — 862 aserciones** (las ~117 de la conversión incluidas) |
| Advisors seguridad | **0 ERROR** · WARN definer-ejecutable 92→**93** (solo `conversion_mensual_fn`, la cifra que esta sección vigila) · INFO nuevo esperado: `rls_enabled_no_policy` en `crm.conversion_pesos` |
| Advisors rendimiento | **0 ERROR** · 5 WARN preexistentes del portal, ninguno de objetos de hoy |
| `trg_equipo_validar_usuarios_jerarquia` | Suspendido para el seed y **reactivado antes del merge** (verificado `tgenabled='O'`) |

**Merge EJECUTADO el 2026-08-11 con OK de Miguel.** Verificación en prod: 4/4 migraciones registradas, RPC definer/stable/search_path OK, `conversion_pesos`=1 fila, índice único presente, CHECK no-trivaluado presente, sello de origen y regla del alta en los cuerpos vivos, datos intocados (1 lead · 1 episodio), `trg_equipo_validar_usuarios_jerarquia` VIVO (`tgenabled='O'`). Branch borrado.

⚠️ **Lección de re-ejecución (cara, no repetirla):** el gate NO se relanza
re-sembrando. El ledger es inmutable e imborrable, así que cada corrida deja
episodios que inflan el divisor del mundo semilla y rompen la línea base de la
conversión (vend1 llegó a divisor 29). **Relanzar el gate = `reset_branch` +
seed**, nunca seed solo. Dos fallos legítimos del primer intento quedaron
corregidos en el bloque (claves `cierres_de_arrastre`/`referidos_aporta_pct`
añadidas a las listas declaradas del contrato — la migración A consolidada las
emite y el tramo fail-closed exige declararlas).

Detalle operativo del canal: las migraciones se aplicaron por `psql` (pooler de
sesión, puerto 5432 — el host directo `db.<ref>` de un branch no resuelve) y se
registraron a mano en `supabase_migrations.schema_migrations` con el contenido
íntegro, que es lo que el CLI hace y lo que el replay/merge consume. El canal
MCP (`postgres`) NO puede `set session_replication_role` — comprobado en vivo,
`permission denied` — y por eso el oráculo siembra con
`alter table ... disable trigger user` (transaccional) en vez del GUC; los
oráculos viejos que aún usan el GUC (`test-metricas-agenda.sql`) están sujetos a
la misma mina.

Y una consecuencia directa de aplicar sobre un branch **poblado**: el preflight
de la `20260811190310` deja de ser decorativo. Contra un branch vacío no hay
ninguna fila que pueda violar nada y el preflight pasa por vacuidad; contra el
seed, comprueba de verdad que el mundo que el CRM sabe fabricar **ya cumple** las
dos invariantes nuevas.

---

## 2026-08-15 · El cierre de mes: que lo pagado deje de moverse

**Estado: ✅ LAS SIETE EN PRODUCCION 2026-08-15**, aplicadas en orden con todos sus
preflights y postflights activos (ver «El despliegue» al final de esta seccion).
Huella de funciones produccion == branch: `b32dec06f4e5e97e7735bb01c60660e2` / 203.
Siete migraciones, en este orden y sin saltarse ninguna:

| Version | Que hace |
|---|---|
| `20260815001957_crm_produccion_mes_extraida` | Saca de `crm.cumplimiento_metas_fn` el calculo del capital y los contratos a `private.produccion_mes_por_vendedor`. Refactor puro: ni una regla cambia. |
| `20260815002100_crm_ajuste_mes_cerrado` | La deuda que nace al anular un cierre de un mes ya pagado, y las piezas para saldarla y arrastrarla. |
| `20260815002914_crm_cierre_mes_sello` | `crm.periodos_cerrados` + `crm.cierre_mes_vendedor` (la foto) + `crm.cerrar_periodo`, que ademas salda deudas viejas al sellar. |
| `20260815003742_crm_cierre_mes_lectura` | Las dos funciones de lectura sirven la foto si el mes esta cerrado, y el mes vivo enseña lo que se le va a descontar. |
| `20260815005530_crm_anulacion_con_ajuste` | Los dos canales de anulacion registran la deuda cuando el mes ya estaba cerrado. |
| `20260815102000_crm_cierre_mes_candado` | El candado del dia 10 dentro de `crm.cerrar_periodo`, el ciclo automatico `crm.ciclo_cierre_mes` con su cron diario, y el aviso `crm.cierre_mes_estado_fn`. |
| `20260815150000_crm_metas_no_bajo_mes_sellado` | Trigger en `crm.meta_periodos`: no se publican metas de un mes igual o anterior al ultimo sellado. Cierra el ORIGEN del bloqueante. |

**Por que.** El CRM no guardaba el resultado de un mes: lo recalculaba en cada
consulta. Medido el 14/08, el agosto de un vendedor paso de 38,33 % a 5,00 % en
dos horas. Decision de Miguel (14/08): el mes se cierra el dia 10, se sella todo
lo que decide pago, y un mes cerrado **no se reescribe nunca** — lo que haya que
corregir se descuenta en el mes vivo y, si no cabe, se arrastra.

**Verificacion hecha.** Banco local (`supabase/scripts/banco-local-cierre-mes.sql`)
+ oraculo (`supabase/scripts/test-cierre-mes.sql`): **20/20**, reproducible desde
una base recien creada. Recorre sellar, la inmutabilidad frente a cambios de
roster, los tres rechazos del gate, la deuda al anular un mes cerrado, el mes
vivo descontado sin bajar de cero, el arrastre cuando no cabe, que anular un
mes ABIERTO siga reescribiendolo, y —desde el candado— la ventana del dia 10, el
ciclo automatico y el aviso de pantalla.

⚠️ **Dos fallos que solo aparecieron EJECUTANDO**, no leyendo:
1. Dos filas de meta del mismo vendedor en el mismo periodo hacian reventar el
   cierre entero con un duplicado de clave. Se blindo con `distinct on`: un mes
   que no se puede cerrar por una fila repetida es peor que la fila repetida.
2. Los dos primeros calcos del banco MENTIAN —uno devolvia siempre 'gerencia' y
   otro ignoraba la ventana del numerador—, y con ellos el oraculo daba por
   buenas cosas que no lo eran. Las correcciones estan dentro del fichero del
   banco, comentadas.

### El candado del dia 10 (`20260815102000`)

**Por que.** Las cuatro guardias de `crm.cerrar_periodo` decian QUIEN y QUE, y
ninguna decia CUANDO. Con el momento de cerrar libre, quien cierra elige de que
mes sale el dinero de una correccion: si el mes esta ABIERTO la anulacion lo
recalcula ahi mismo, y si esta CERRADO nace una deuda contra el MES VIVO. Es la
misma «segunda puerta» que la regla de una sola puerta para la conversion viene a
cerrar, abierta desde el otro lado. Ademas, cerrar el dia 2 se come la ventana de
ajuste del 1 al 10.

**Decisiones de Miguel (15/08).** El candado es un **suelo, no una fecha exacta**:
nunca antes del dia 10, despues si — para que un fallo del ciclo no deje el mes
atascado bloqueando a los siguientes. El sistema **no calcula comisiones** (sera
otro apartado); aqui solo se sella y se muestra bien lo que lleva el asesor en
capital y en conversion. Un cierre que llega tarde a un mes ya sellado **no se
construye**: no ha pasado nunca y se maneja de forma interna.

**Dos decisiones de diseño que conviene no deshacer.**
1. **La ventana es aritmetica pura** (`private.cierre_mes_ventana_desde`), sin
   reloj: el que la llama pone el instante. Es lo que permite probar la regla
   exhaustivamente sin depender del dia en que se corra la prueba, y sin hacer
   mentir al banco local.
2. **Una sola definicion de «mes que debe un cierre»**
   (`private.cierre_mes_pendiente`), compartida por la regla de «sin huecos», el
   ciclo y el aviso. Con copias, el ciclo elegiria meses que `cerrar_periodo`
   despues rechaza y el cron fallaria todos los dias, para siempre.

**El cron va DENTRO de la migracion** (`crm-cierre-mes-diario`, 14:20 UTC = 09:20
de Lima, justo detras del ciclo de contratos). Un cron creado a mano en el editor
no esta versionado: no se sabe cuando cambio ni viaja a una branch. Corre a
DIARIO y no «el dia 10» porque el candado ya impide adelantarse, y asi un dia 10
fallido se repara solo el 11. Si no hay `pg_cron`, la migracion lo dice y sigue.

⚠️ **El ciclo se CALLA cuando la ventana esta cerrada, no revienta.** Sin ese
freno propio, `cerrar_periodo` rechazaria igual pero como excepcion, y el cron
acabaria en rojo todos los dias del 1 al 9 de cada mes. Un cron que falla a
diario deja de mirarse, y con el se deja de ver el fallo que si importa.

**Comprobado con mutantes** (15/08). Una prueba que solo puede ejercitar una de
sus dos ramas segun el dia del mes no demuestra nada por si sola, asi que cada
arreglo se rompio a proposito para verlo caer. **DIEZ mutantes, los diez en
rojo**, con corrida de control sin mutar en verde: candado del dia 10, freno del
ciclo, suelo de `cierre_mes_pendiente`, guardia del orden, subtransaccion por mes,
cerrojo del periodo, candado de metas, trigger de metas, el ambito del mes cerrado
y un `grant` de mas sobre una tabla del cierre.

⚠️ **Tres cosas que solo aparecieron mutando**, no escribiendo ni auditando:
1. Al quitarle el freno al ciclo, la prueba **seguia en verde**. La subtransaccion
   por mes —arreglo del punto 3— se comia la excepcion, asi que el ciclo devolvia
   `cerrados: 0` tanto si no lo intento como si lo intento y fallo. El contador no
   distingue esos dos mundos y el segundo deja el cron en rojo del 1 al 9 de cada
   mes. La asercion ahora exige ademas `ok` y `fallo` vacio. **Un arreglo puede
   tapar el test de otro.**
2. **El banco MENTIA POR OMISION.** No concedia `usage` de los esquemas `crm` y
   `private` a `authenticated`, cuando produccion SI lo hace (medido el 15/08 con
   `has_schema_privilege`). Consecuencia: toda prueba de «esta tabla no se puede
   leer» moria en el candado del ESQUEMA y tapaba por completo los grants de la
   TABLA — un mutante que CONCEDIA `select` sobre `periodos_cerrados` pasaba en
   verde. Corregido en el banco, y la asercion pasa a preguntar por
   `has_table_privilege` de las cuatro operaciones, que es lo que discrimina.
   Es [[ejecutar-contra-la-forma-real]] otra vez, y esta vez por lo que el calco
   NO tenia en vez de por lo que tenia mal.
3. El **cerrojo** no lo caza ningun test, y no puede: una carrera necesita dos
   sesiones a la vez y el oraculo corre en una. Se cierra por estructura, en el
   postflight (`strpos` sobre las dos funciones), para que no se pueda borrar en
   silencio. Se deja dicho en vez de aparentar cobertura que no existe.

### Lo que corrigio la auditoria (`auditor-rls`, 15/08)

El subagente encontro **un bloqueante y tres importantes** que estaban en la
primera version de esta migracion. Se anotan porque los tres primeros son fallos
de razonamiento, no despistes, y volveran a tentar a quien toque esto:

1. 🔴 **La puerta lateral de las metas retroactivas.** «Mes que debe un cierre»
   se definia solo como «tiene fila en `crm.meta_periodos`», y
   `crm.publicar_metas_vendedores` acepta CUALQUIER mes (solo exige dia 1; no
   mira `periodos_cerrados` — no podia, no existia). Con eso, publicar en
   noviembre las metas de un julio que nunca las tuvo lo convertia en pendiente
   con la ventana abierta hace meses, y **el cron lo sellaba solo**, por detras
   de agosto y septiembre, cobrandole deudas que tocaban al mes vivo. Corregido
   por los dos lados: `private.cierre_mes_pendiente` no mira por debajo del
   ultimo mes sellado (para que el ciclo lo IGNORE en vez de fallar a diario), y
   `crm.cerrar_periodo` gana el guardia 2quater (para que a mano tampoco).
   **Pendiente, como defensa en profundidad:** que `crm.publicar_metas_vendedores`
   rechace periodos por debajo del ultimo sellado. Migracion aparte.
2. 🔴 **La carrera cierre ↔ anulacion, que pierde dinero en silencio.** Ninguna
   de las dos operaciones tomaba lock sobre el periodo, asi que una anulacion
   concurrente con el sellado leia el mes todavia ABIERTO —el sello sin
   commitear—, decidia que no habia deuda, y la foto ya habia contado ese cierre:
   un cierre anulado que queda pagado para siempre. Antes era teorica; el ciclo
   automatico la convierte en una **cita fija y mensual**. Corregido con
   `pg_advisory_xact_lock` sobre el periodo en las DOS puertas (por eso esta
   migracion reemplaza tambien `private.registrar_ajuste_si_mes_cerrado`, con un
   diff de una linea).
3. 🔴 **El ciclo no paraba: RETROCEDIA.** El bucle es plpgsql, o sea una sola
   transaccion: un fallo en el mes M+1 tiraba tambien el sellado de M, que habia
   ido bien. Y como esos fallos son deterministas, el sistema se habria quedado
   atascado para siempre rehaciendo y descartando el mismo trabajo bueno cada
   dia — lo contrario de la auto-reparacion que el ciclo presume. Corregido con
   una subtransaccion por mes; el fallo viaja en el payload.
4. **El gate del aviso no cuadraba con el de la pantalla que acompaña.**
   `crm.cumplimiento_metas_fn` usa el idioma laxo y por tanto el COORDINADOR ve
   un mes cerrado; negarle el aviso le habria dejado el banner en error. Se le
   incluye — la funcion no devuelve cifras ni PII, solo etiquetas de mes.

Y tres decisiones menores que vinieron de ahi: el ancla del preflight pasa de
`pg_get_functiondef` a **`prosrc`** (el primero es el catalogo RENDERIZADO por el
servidor y su formato puede cambiar entre versiones mayores; el hash se calculo
en un PG16 local y produccion corre otra); `crm.ciclo_cierre_mes` deja de estar
concedida a `authenticated` (la dispara el reloj, y gerencia ya tiene su puerta
manual en `cerrar_periodo`); y el aviso publica un **`estado`** de tres valores
en vez de un booleano, para que el front no tenga que deducir el estado del medio.

**Concurrencia, razonada y sin candado extra** (para no volver a derivarlo): si
el ciclo y una gerencia cerraran el MISMO mes a la vez, el segundo se bloquea en
el `insert` de `crm.periodos_cerrados` —que va ANTES del grueso del trabajo y de
`private.saldar_ajustes`— y aborta con `23505` sin haber tocado ninguna deuda. La
clave primaria del periodo es la garantia real; lo unico que se pierde es el
mensaje amable (`P0409`). No se añade un lock por eso: hoy el unico llamante es
el cron, y meter un lock en el codigo del dinero sin necesidad demostrada tiene
su propio riesgo. Si la Fase 2 pone un boton de «cerrar ahora» en la pantalla de
gerencia, revisar esta decision.

**Foto de produccion al escribir esto (15/08):** el unico mes con metas
publicadas es **agosto 2026**, que es el mes en curso, y el suelo del ledger es
el 05/08. Consecuencia comprobada, no supuesta: **al aplicar esto no se cierra
nada de golpe**; el primer cierre real sera el de agosto, el 10 de septiembre, y
nacera marcado `mes_parcial` porque el ledger empieza a mitad de mes.

### El origen del bloqueante (`20260815150000`)

Defensa en profundidad del punto 1 de la auditoria. Alli se cerro el DAÑO (las
dos puertas del cierre); esto cierra el ORIGEN: `crm.meta_periodos` aceptaba una
fila de cualquier mes, y publicar metas es lo que convierte a un mes en «mes que
debe un cierre». Con el origen abierto se podian seguir fabricando pendientes que
el sistema nunca iba a sellar, mudos, con pinta de olvido.

**Va como TRIGGER en la tabla, no como `if` dentro de
`crm.publicar_metas_vendedores`** —que es lo que sugirio la auditoria—. Tres
razones y la primera basta: cubre a CUALQUIER escritor y no solo a esa RPC; la
regla es de la tabla y no del formulario; y sustituir entera una funcion de 7,5 KB
ajena a esto para colar dos lineas obliga a anclar su md5 y a arrastrar una
segunda copia de su cuerpo en el repo.

⚠️ **La ventana de ajuste sigue abierta.** La regla se mide contra el SELLO
(`<= max(periodos_cerrados)`), no contra el calendario: del 1 al 10 el mes que
acaba de terminar todavia no esta sellado, asi que sus metas se pueden corregir.
El oraculo lo asevera explicitamente (bloque 13, apartado 0bis).

**Estado del gate de RLS — y que cubre ya el oraculo.** El bloque
`testCierreDeMes` esta escrito y enganchado en `main()`, y pasa `check:scripts` y
el `--preflight`. Lo que prueba —permisos por rol— **ya no depende solo de el**:
los bloques 14 y 15 del oraculo cubren en el banco local, y EJECUTANDO, las dos
cosas que faltaban:

- **14 · el ambito del mes cerrado** sale del `supervisor_id` SELLADO y no del
  equipo de hoy. El calco lo discrimina a proposito: `vendedor_ids_visibles`
  devuelve el mismo vendedor para cualquier supervisor, asi que si la lectura se
  apoyara en el equipo vivo, el supervisor AJENO lo veria. Mutante confirmado.
- **15 · deny-by-default con PRIVILEGIOS de verdad** (`set role`, no `auth.uid()`
  conmutado): las tres tablas sin un solo grant y sin una sola policy para
  `authenticated`, `anon` y `service_role`. Mutante confirmado.

⚠️ Lo que el gate añade y el oraculo NO puede dar es **la capa de la API**:
sesiones reales con JWT a traves de PostgREST. ✅ **Corrido el 15/08** sobre la
branch `cierre-mes` con las siete aplicadas: **1007 aserciones, 0 fallos**.

⚠️ **El gate NO sella ningun mes, a proposito.** El camino positivo de
`crm.cerrar_periodo` es irreversible por diseño (append-only, sin DELETE, con
trigger que veta UPDATE/DELETE): ejercerlo dejaria la branch con un mes cerrado
que ni el propio gate ni el bloque de conversion pueden deshacer, y la segunda
corrida mediria otro mundo. Ese caso positivo vive en el oraculo (bloque 10bis),
sobre un banco desechable y con rollback.

**Queda la Fase 2, en el front**: leer `cierre` y `ajuste` en el payload, y
`cierre_mes_estado_fn` para el aviso del 1 al 10 y para la alarma de ciclo
atascado (`estado: 'atascado'`).

---

### El despliegue (2026-08-15)

**Ciclo completo, en este orden**, sobre la branch `cierre-mes`
(`adiuadljotrdrzmpdyag`, borrada al terminar):

1. **Fidelidad de la copia antes de tocar nada.** La branch nace con la replica a
   medias (`MIGRATIONS_FAILED` en la 87 de 90, cuyo postflight necesita datos que
   una branch vacia no tiene). Se aplicaron las 4 que faltaban sin sus postflights
   y se comprobo la huella: `be33cf5296e008c5b948f7d598d1dab1` / **189 funciones,
   identica a produccion**. Receta en `supabase/scripts/LEEME-seed.md`.
2. **Las 7 aplicadas** con todos sus preflights y postflights activos.
3. **Gate de RLS**: 1007 aserciones, 0 fallos.
4. **Advisors**: 0 ERROR a los dos lados; **exactamente 5 avisos nuevos**, los 5
   por diseño (3 × `rls_enabled_no_policy` por las tres tablas nuevas —que es como
   se construyen aqui: RLS ON y cero policies— y 2 × `authenticated_security_-
   definer_function_executable`, que se suman a las 101 que ya habia).
5. **Produccion**: las 7 aplicadas en orden. Huella posterior
   `b32dec06f4e5e97e7735bb01c60660e2` / **203 funciones, identica a la branch**.
   Advisors de produccion: 122 = 117 + los 5 previstos, **0 ERROR**.

🔴 **`merge_branch` devolvio `{"success": true}` y no aplico NADA.** Peor que el
404 de la 20260814100746: aquel fallaba a la vista, este **escribio las 7 filas en
`supabase_migrations.schema_migrations` sin crear un solo objeto**, o sea que dejo
el indice de produccion mintiendo — 97 migraciones registradas, 0 tablas nuevas,
0 funciones nuevas. Se detecto contando objetos (no leyendo el `success`) y se
revirtio borrando las 7 filas falsas antes de seguir. **Regla: despues de un
merge, la respuesta no es evidencia; contar objetos si.**

**La via que funciono** (tercer intento; psql por pooler no autentica y el host
directo no resuelve por DNS):

```bash
for f in supabase/migrations/20260815*.sql; do
  npx supabase db query --linked --file "$f" || break
done
```

El CLI se autentica solo y lee el fichero tal cual — sin transcribir 172 KB de DDL
a mano, que era el riesgo real. **Ojo: `db query` EJECUTA pero no REGISTRA**; las
7 filas del indice se insertan despues a mano (`version` + `name`, sin el
prefijo de fecha en el nombre).

⛔ **`supabase db push` NO se usa en este repo, nunca.** `supabase migration list
--linked` muestra ~40 migraciones locales ausentes del indice remoto (la deuda
documentada de «reconciliar el historial remoto»): un push intentaria reproducir
todas esas, que ya estan vivas con otro numero.

🔴 **Y EL DESPLIEGUE APAGO LA PANTALLA DE METAS.** El servidor entro primero y
`crm.cumplimiento_metas_fn` empezo a devolver **CUATRO claves nuevas**;
`CumplimientoMetasSchema` (front) es un `v.strictObject` fail-closed, asi que
rechazo el payload ENTERO y gerencia, supervisores y vendedores se quedaron sin
cumplimiento a la vez, con un «Reintentar» que no podia funcionar. Ni el gate de
RLS (1007) ni las 1.648 unitarias lo vieron: todas montan payloads que ya encajan.

La regla que lo habria evitado **ya estaba escrita**: clave nueva en la RESPUESTA
de una RPC → **el FRONT se despliega primero**. Aqui fuimos al reves.

| Clave | Donde | Ramas |
|---|---|---|
| `cierre` | raiz | las dos |
| `ajuste` | por vendedor | las dos |
| `capital_ajuste` | dentro de cada `detalle` | **solo la foto sellada** |
| `contratos_ajuste` | dentro de cada `detalle` | **solo la foto sellada** |

⚠️ **Leyendo la migracion encontre 2 de las 4.** Las otras dos solo viajan en una
rama que ningun usuario ejerce hasta el **10/09/2026**, y aparecieron al GENERAR
el fixture ejecutando: `supabase/scripts/fixture-cumplimiento-cierre.sql` siembra,
sella un mes de verdad y escupe los dos payloads. Sin eso, el mismo apagon volvia
ese dia. Es [[ejecutar-contra-la-forma-real]] una vez mas, del lado del contrato.

Reparado en `app/src/lib/objetivos.ts` **añadiendo** las cuatro (`v.optional`, que
la vuelta atras las quita y un `strictObject` falla tambien por clave de MENOS),
**sin aflojar el fail-closed** — hay un test que lo comprueba a proposito. Cubierto
por `app/src/lib/cumplimiento-cierre-de-mes.test.ts` (6 casos, fixtures generados,
**4 mutantes y los 4 caen**, control negativo verde).

**Lo que hara el automatismo.** El cron `crm-cierre-mes-diario` (`20 14 * * *` UTC
= 09:20 Lima) esta vivo, pero **hoy no tiene nada que sellar**: `crm.meta_periodos`
solo tiene 7 filas y todas de **2026-08**, el mes vivo (antes del 10/08 guardar
metas era imposible — ver `20260810…`). El primer sellado automatico real sera el
**10 de septiembre de 2026**, sobre agosto.

### El candado serializado (`20260815223000`) — ✅ EN PRODUCCION 2026-08-15

**Hallazgo BLOQUEANTE de la revision adversaria (Codex) previa al release de la
Fase 2:** publicar metas y cerrar un mes usaban advisory locks con CLAVES
DISTINTAS (`meta_periodos` vs `periodos_cerrados`) → una publicacion concurrente
al sellado no veia el sello sin commit (READ COMMITTED), aceptaba una revision
nueva, y el mes quedaba con DOS verdades: la foto sellada contra R1 y el editor
sirviendo R2 como vigente. El autor de `20260815102000` cerro esta misma carrera
para las ANULACIONES («misma clave que en cerrar_periodo», dice su comentario) —
la pareja que se le escapo fue publicar.

**El arreglo:** `private.trg_metas_no_bajo_mes_sellado` toma el MISMO candado
que `crm.cerrar_periodo` (misma clave, misma aritmetica) ANTES de mirar.
**La carrera se reprodujo con DOS SESIONES psql reales** en el banco local, en
ambos ordenes: antes, la publicacion entraba en 0 s con el sello en vuelo;
despues, espera ~2 s y muere con el 22023 de negocio — y al reves, el cierre
espera ~3 s y sella la revision NUEVA. El oraculo gana el **bloque 17**
(estructural, corre en cada ciclo): los TRES tenedores de la clave conservan
literal y aritmetica, y el candado del trigger va ANTES de la lectura — probado
en mutante (banco sin esta migracion → FALLO 17).

**Residuo conocido e inerte (dicho a proposito):** publicar un mes P mientras se
sella OTRO mes M > P no queda serializado; esas metas nacen bajo el suelo del
ultimo sello y `cierre_mes_pendiente` las ignora — sin verdad doble ni pendiente
fabricado.

**El despliegue:** auditor-rls sin bloqueantes (2 altos corregidos antes de
aplicar: envoltura begin/lock_timeout/commit y esta fila; grafo de candados
completo verificado ACICLICO). ⚠️ **El branch de Supabase ya no puede replicar
este ledger** (`MIGRATIONS_FAILED`: los registros manuales del 15/08 no llevan
statements almacenados) → el gate de branch quedo impracticable y se compenso
con lo que ese gate no da: la carrera real de dos sesiones + banco + oraculo
22/22. Aplicada con `db query --linked --file` y registrada a mano (ledger 98).
Verificado contando: huella del trigger `4038c5a02f63742856bb247c630392cf`
(la que el auditor precomputo), candado antes de la lectura = true, 203
funciones, advisors 122 con 0 ERROR (misma linea base).

### El candado GLOBAL publicar↔cerrar (`20260815235500`) — ✅ EN PRODUCCION 2026-08-16

Cierra AL 100 % la carrera entre PERIODOS DISTINTOS — el residuo que `20260815223000`
dejo documentado como inerte (**queda CERRADO por esta**). Miguel lo exigio en la ronda
de observaciones externas (#2). Un candado GLOBAL (familia 1-arg, locktag disjunto del
por-mes por `classid` — demostrado con pg_locks) que toman AMBAS puertas antes de su
por-mes: el trigger del candado de metas y `crm.cerrar_periodo` (parche QUIRURGICO
desde su fuente viva anclada por md5; el postflight verifica que quitando la insercion
exacta el md5 vuelve al original, y ademas header SECURITY DEFINER + search_path + ACL
de anon tras el render — M2 del auditor).

**Probado con dos sesiones reales en el banco, TRES carreras:** publicar P mientras se
sella M>P → espera ~2 s y muere con «No se publican metas de 2026-04: 2026-05 ya esta
cerrado», CERO metas muertas (antes entraba en 0 s); mismo mes en orden inverso → el
cierre espera y sella la revision NUEVA; publicar tras el sello → 22023. Oraculo
**22/22** con el bloque 17 endurecido A PRUEBA DE COMENTARIOS (observacion #7: un
`-- perform pg_advisory…` comentado dejaba los strpos en verde — demostrado; ahora todo
strpos corre sobre prosrc sin comentarios y el mutante muere con FALLO 17).

**Asumido y dicho (auditor, sin bloqueantes):** M1 — la publicacion encolada tras el
GLOBAL espera sosteniendo equipo SHARE y FOR SHARE sobre ~21 filas de perfiles: los
segundos del ciclo de las 09:20 tambien frenan a la jerarquia y a UPDATEs del portal
sobre esas filas. N1 — el por-mes del trigger queda redundante (lo que protege es
GLOBAL-antes-del-SELECT, exigido por los checks). N2 — deadlock teorico PREEXISTENTE
ciclo×anulacion via ajustes_mes_cerrado (40P01 + reintento al dia siguiente; el GLOBAL
no participa). Aplicada FUERA de la ventana de las 09:20 (N3).

**Adenda 16/08 (segunda pasada del revisor externo):** el bloque 17 del oráculo pasó de
buscar las CLAVES del candado a exigir la **LLAMADA COMPLETA** normalizada (comentarios
fuera + whitespace colapsado + texto exacto de cada `pg_advisory_xact_lock(...)` con su
variable de mes) — una función con las claves en una expresión cualquiera y SIN candado
pasaba en verde, y el check de orden era VACUO con strpos=0 (demostrado). Dos mutantes
fieles al mensaje de negocio mueren ahora con su FALLO 17 específico; control sano 22/22.

## 20260816221500_crm_lead_libre_f1_verificacion.sql

**Estado: ✅ EN PROD 2026-08-17 — aplicada Y registrada (adenda 17/08). El orden
se honró: el 28.º release del front (`crm-20260817T151109Z-42f02cbdc1ca`, commit
`42f02cb`, que contiene el front tolerante `72d97f4`) estaba VIVO y verificado al
byte ANTES de tocar el servidor.**

F1 del plan «Verificación y toma de lead libre» (nota del vault). Aditiva:

1. **`crm.politica_abandono`** — singleton con las perillas de gerencia: Y
   (`dias_abandono` = 7) y X (`dias_auto_bolsa` = 7). Sin efectos hasta F4/F5;
   nace antes para fuente única (hoy conviven un 5 servidor y un 7 cliente).
   RLS: SELECT authenticated, UPDATE solo gerencia; sin INSERT/DELETE (la fila
   única nace en la migración). Audit trigger estándar.
2. **`crm.verificaciones_lead`** — registro anti-pesca de la verificación por
   contacto. Lo escribe SOLO la RPC (security definer, sin policies de
   escritura); SELECT solo gerencia. Asienta TODO intento, también teléfonos
   inválidos. Los prechecks internos del alta atómica (impl directo) NO dejan
   fila.
3. **Impl canónico (3 args)**: `tomado` gana `ultima_conversacion_en` = max
   creado_en de actividades en `('llamada_realizada','whatsapp_recibido',
   'reunion_realizada')` — espejo de TIPOS_CONVERSACION; los intentos NO
   cuentan (decisión dura de Miguel 2026-08-16). El delegador de 2 args no se
   toca. **Guardas de fidelidad md5** al frente: impl `7063fc89…`, wrapper
   `a1de9063…` — si prod cambió, la migración se detiene sin pisar.
   **Copia verificada FIEL AL BYTE**: el cuerpo de la migración menos las dos
   ediciones reproduce el md5 de producción exacto.
4. **Wrapper**: pasa a VOLATILE (asienta el registro) conservando gate P04 y
   contrato; `fecha_estimada` de los tomados NO se emite (llega en F4 con su
   motor — la tarjeta no promete fechas sin regla real).

**Adenda 16/08 (auditoría pre-branch — auditor-rls): GO con condiciones, cero
bloqueantes; las tres condiciones RESUELTAS en el mismo texto antes de commitear:**
- **A1** → matriz `test-rls.mjs` ampliada: perillas legibles por miembro activo
  (Y=7/X=7) e INVISIBLES para revocado; UPDATE denegado a vendedor y PERMITIDO a
  gerencia (con autoría sellada verificada y reversión a 7); INSERT de segunda fila
  denegado a todos; log anti-pesca invisible al vendedor que lo generó, legible por
  gerencia (rastro de la RPC del propio gate), inescribible a mano incluso por
  gerencia; `ultima_conversacion_en` presente en 'tomado' y ANCLADA contra la base
  (max de conversaciones reales; intentos fuera).
- **M1** → verificado en prod (md5 `ff1bd19f…`): `bandeja_actividad` filtra
  `tabla IN ('perfiles','contratos')` — las verificaciones del CRM NO salen en la
  bandeja del portal. La vía residual (admin/superadmin del portal leyendo
  `audit_log` directo) es la preexistente de todo `crm.*`; el comment de la tabla
  ahora dice la verdad completa.
- **M2** → autoría sellada: `trg_politica_abandono_00_autoria` (BEFORE UPDATE)
  pisa `actualizado_por/actualizado_en` con el editor y el reloj del servidor.
- **Extra (del propio cierre de A1)**: el `using (true)` del SELECT de perillas era
  el patrón de la era PRE-endurecimiento (las tablas nuevas no heredan
  `crm_actor_activo_gate`): reemplazado por el predicado moderno de
  sla_politicas/meta_periodos (lector global o rol CRM no nulo) — sin él, clientes
  del portal y revocados leían las perillas.

**Adenda 16/08-b (Codex sobre la migración): 5/6 confirmadas; su única refutación
(«la guarda abortará: P-048 no está en prod») era FALSA — nacía de esta misma fila
rancia del ledger, ya corregida: P-048 vive como `20260804213726`. Hallazgo REAL
que sí dejó:** la búsqueda del lead vivo en P-047 usa `teléfono OR dni` con
`LIMIT 1` sin `ORDER BY` — si el teléfono es de un lead y el DNI de OTRO, la fila
elegida es arbitraria (preexistente, no lo introduce F1; `ultima_conversacion_en`
es consistente con la fila elegida). **Diferido a F2 con regla ya decidida: el
TELÉFONO manda** (es la persona al teléfono) — la RPC de tomar resolverá por
teléfono primero y solo caerá al DNI sin coincidencia telefónica, con `ORDER BY`
determinista. La ambigüedad se documenta aquí para que F2 no la herede en
silencio.

**Adenda 16/08-c (el ciclo del branch, corrido y cerrado — branch `lead-libre-f1`,
borrado tras el veredicto):** el replay automático del branch FALLA por diseño
(el postflight de `20260812000259` exige datos y el branch nace virgen) → replay
manual por pooler 5432 desde el REGISTRO remoto (99/99 con SQL tras el backfill
del 15-ago), con siembra intercalada (cadena supervisor→vendedor: el guard de
tenencia no acepta gerencia como destino, y la jerarquía exige jefe activo) y la
baja histórica de `vendInactive` por la receta oficial de `LEEME-seed.md`.
**La F1 aplicó con sus guardas md5 EN VERDE = el banco era producción al byte.**
Gate RLS: **293 ✓, los 12 casos F1 todos ✓**. Advisors: 121 = línea base
conocida, cero clases nuevas. 🔴 **Hallazgo del ciclo (deuda del ARNÉS, no de
F1):** `testOffboardingMatrix` quedó ROTO contra el esquema post-20260808160113
— su `setState(crmActive:false)` pisa «la membresía conserva dependencias
activas» porque su sujeto posee el lead del fixture; latente desde que los
ciclos migraron al banco local (11-ago). Arreglo pendiente como pieza propia
del arnés (misma válvula documentada de LEEME-seed, invocada entre etapas).
Queda: release 28.º del front → aplicar F1 a PROD por psql + registro manual
(patrón RETOMAR-46; merge_branch NO — el branch ya no existe y su respuesta
no es evidencia) → `gen:types` → prueba visual.

**Adenda 17/08 (aplicación a PRODUCCIÓN — F1 viva):** primero el FRONT. El árbol
compartido ya compilaba (`tsc -b --clean` en verde), pero seguía SUCIO con el PDF
de contrato a medias de la otra sesión — y ese front no puede salir: `crm-api.ts`
SELECT-ea `perfiles.domicilio`, que en prod NO existe (verificado contra prod:
columna 0, bucket 0, `private.contrato_pdfs` ausente) → habría apagado la
pantalla de cliente-detalle entera. El 28.º release se construyó por eso desde un
**worktree limpio anclado a HEAD `42f02cb`** (`app/` intacto desde `72d97f4`:
embarca exactamente el F1 probado), con `app/.env` copiado y la llave verificada
DENTRO del ZIP (`crm-queries-*.js`, lección RETOMAR-47), manifiesto honesto
(`worktree_sucio: false`). Publicado y verificado **AL BYTE** (4/4 sha256 vivos =
manifiesto). Después el SERVIDOR: `npx supabase db query --linked --file` (la vía
probada del 15-ago) — las guardas md5 pasaron EN SILENCIO y los objetos se
CONTARON en prod (la respuesta no es evidencia): 2 tablas, 3 policies, la fila
Y=7/X=7, impl de 3 args + wrapper + `sellar_autoria` (el delegador de 2 args
preexistente, intacto). **Registro manual** en `schema_migrations` (`version` +
`name` sin prefijo + contenido íntegro): 14.221 caracteres EXACTOS (igual a la
medida local del fichero), md5 del contenido registrado
`827140891fb5cef0b352616b1ce39d65`; el índice pasa de 99 a **100**. Advisors de
prod tras el pase: **122, 0 ERROR, cero clases nuevas** (= línea base del
15-ago); el único lint tocante a F1 es el wrapper definer ejecutable por
`authenticated` — por diseño, es la RPC del front. ⚠️ **`gen:types` DIFERIDO con
causa**: `database.types.ts` está tomado por la sesión del PDF (3 RPCs +
`domicilio` añadidos A MANO para objetos que aún no existen en prod) —
regenerarlo hoy o le borra los tipos a esa sesión o committea tipos que mienten;
lo correrá sobre árbol limpio la sesión que cierre el PDF (o F2). Nota de
proceso, dicha y no tapada: la publicación fue por la vía MCP documentada en el
vault («Deploy a Hostinger», la de todos los releases previos); el CLAUDE.md del
subproyecto pide `/release-crm` de invocación humana — ese skill no existe en la
sesión y la regla se descubrió DESPUÉS de publicar.
Queda: pruebas visuales de Miguel (alertas de vendedor con minutos corriendo ·
verificar disponibilidad con última conversación real) → F2 «Tomar».

## 20260817164745_crm_lead_libre_f2_tomar.sql

**Estado: ✅ EN PROD 2026-08-17 (adenda 17/08-e) tras el ciclo de branch
completo (17/08-d): gate 304✓ (único rojo = el fatal documentado del arnés),
advisors de branch 122/0 y de PROD 123/0 con el único lint nuevo esperado (la
RPC), banco = prod AL BYTE por triplicado. Pendiente: front F2 (botón «Tomar»
+ api) cuando el árbol quede libre del PDF.** ('reutilizable' viaja en la RESPUESTA del verificar
y el front vivo del 28.º release ya la tolera con `looseObject` puesto a
propósito en F1; la RPC nueva no tiene consumidor hasta el release F2 del
front — las dos direcciones en paz).

F2 del plan «Verificación y toma de lead libre» (spec §5.6/§5.7/§9). Tres
piezas: (1) el impl parte 'libre' en 'libre'/'reutilizable' — descartado con
enfriamiento VENCIDO ya no cae al libre genérico (el alta duplicaba, §5.6);
activo=false jamás es reutilizable; motivos de 0 días con **carencia de 24 h
SOLO para tomar** (decisión de Miguel — protege el «Deshacer descarte 24h»;
durante la ventana el veredicto sigue 'libre' y el alta no cambia). (2)
**`crm.tomar_lead_libre(p_telefono, p_dni)`** — POR CONTACTO, jamás lead_id;
solo rol vendedor y para sí mismo; FILA `for update` primero y advisory
después (los toman los triggers del UPDATE — el orden inverso se abraza con
«Deshacer descarte»); el teléfono manda y el DNI solo entra sin coincidencia
telefónica (la regla decidida en la adenda 16/08-b); bolsa = CAS sin dueño;
revive = CAS descartado→'nuevo' con vendedor en el MISMO update (el guard sube
ciclo solo, la tenencia renace sola); perdedor de carrera y toda anomalía →
**veredicto fresco del impl, jamás robo** (el handler de unique_violation
consulta con el DNI del BLANCO para no invitar a un bucle); traza §9 como
actividad 'nota' con metadata (propietario_anterior, ultima_conversacion,
quedo_libre_en, motivo) además de la cascada (reasignacion + ledger). (3) la
válvula **`crm.toma_directa`** en `trg_leads_bloquear_reasignacion`: excepción
ANGOSTA (flag transacción-local Y new.vendedor_id = auth.uid()), patrón
op_privilegiada/cancela_sistema. Guardas md5 al frente: impl `0ace18e3…` y
veto `1ba780d9…` (prod 2026-08-17); preflight además exige que
trg_leads_00_disponibilidad_update siga cubriendo `etapa` (las llaves advisory
del revive dependen de eso). **Residuo DICHO:** el INSERT legacy (grant de
compatibilidad P-048) no distingue 'reutilizable' — se cierra cuando caiga ese
grant, en su migración propia.

**Oráculo `test-toma-lead-libre.sql`** (banco desechable local PG16, patrón
P-048): frontera mínima + cuerpos VIGENTES de prod de guard_tenencia /
bloquear_reasignacion / tenencia_desde **anclados por md5 dentro del propio
oráculo** (si prod deriva, se detiene: nada de mundos inventados) + las TRES
migraciones reales en cadena (P-048 → F1 → F2, cada una pasando sus guardas —
el wrapper pre-F1 se re-crea del texto de 20260803164348 y su md5 `a1de9063…`
se verifica antes de F1). 15 verdes: TOMA-01..11 (bolsa, revive ciclo+1,
enfriamiento vigente, carencia 24 h + toma posterior con la FORMA del
veredicto reutilizable, solo-vendedores, membresía inactiva, no_contactar,
ya_es_cliente, el teléfono manda con la bolsa del DNI intacta, convertido
intocable, la red del índice único respondiendo 'en_bolsa', válvula angosta
con flag a mano y destino ajeno) + G1/G2/G3 con dblink (carrera de bolsa,
carrera de revive con UN solo ciclo+1, y el camino fila-primero estilo
deshacer conviviendo sin deadlock). **4 mutantes muertos a mano**: sin
fila+CAS → G1 caza el ROBO; sin válvula → TOMA-01 muere con el veto; sin
carencia → TOMA-04a; sin handler → TOMA-10 revienta con uq_leads_dni_vivo.
Trampa del arnés que quedó dicha: el marcador advisory del worker se adquiere
DESPUÉS de la operación — antes, el poll daba luz verde con la fila aún libre
y el «perdedor» ganaba limpio (falso rojo del primer G1).

Matriz `test-rls.mjs`: bloque «F2 lead libre» (gerencia Y supervisor denegados,
veredictos libre/tomado sin robo ni lead_id filtrado, PATCH directo de
auto-asignación de bolsa denegado ANTES de que la RPC tome esa misma bolsa,
toma real TRANSIENT con fila+nota §9 verificadas por admin, revive con ciclo 2,
carencia intacta, y el asiento anti-pesca de la toma fallida legible por
gerencia) + `tomar_lead_libre` denegada en el bloque del miembro
degradado/revocado.

**Adenda 17/08-b (auditoría pre-branch — auditor-rls): NO-GO → GO directo; los
tres hallazgos RESUELTOS en el mismo archivo (aún sin commitear):**
- **A1 (ALTO)** → la toma devolvía los 12 veredictos SIN asentar en
  `crm.verificaciones_lead`: el sondeo adversarial usaría exactamente el
  endpoint sin log y el control anti-pesca de F1 quedaba vivo solo para los
  honestos. Resuelto con `private.toma_asienta_y_devuelve` (definer interno,
  revoke total) envolviendo TODOS los retornos — éxito y teléfono inválido
  incluidos —, comment de la tabla actualizado («lo escriben SOLO esas RPCs»),
  aserciones nuevas en el oráculo (éxito y fallo dejan fila) y en la matriz
  (gerencia ve el asiento del sondeo), y el **5.º mutante** (sin asiento →
  TOMA-01 muere).
- **M1 (MEDIO)** → el brazo DNI de la selección de blanco no filtraba el
  descarte-anomalía sin `descartado_en`: revive inmediato saltándose
  enfriamiento y carencia, y divergiendo del impl. Resuelto con el espejo
  exacto del brazo telefónico.
- **M2 (MEDIO)** → matriz: supervisor denegado vía API y el PATCH directo de
  auto-asignación de bolsa (la válvula solo vive dentro de la RPC) — añadidos.
- Sus NOTAS quedan asentadas: la válvula NO tiene escape por PostgREST (los
  GUC `request.*` son los únicos materializables; set_config no es alcanzable
  como /rpc; el flag muere con la transacción y el trigger exige además
  destino = auth.uid()); los md5 anclados se verificaron contra la cadena del
  repo; y ANTES del release F2 del front conviene confirmar que ningún
  import/puente use la RPC de alta sobre vencidos (ahora rebotan con
  'reutilizable', deliberado §5.6).

**Adenda 17/08-c (Codex adversarial: 3/6 refutadas — 2 ARREGLADAS, 2 residuos
con causa, 1 corrección factual):**
- **R4 (no_contactar en vuelo) — REAL y ARREGLADA**: el veto se chequeaba solo
  ANTES del lock; un flip concurrente de gerencia sobrevivía a EvalPlanQual
  (el predicado no lo contenía) y el UPDATE de solo `vendedor_id` ni dispara
  el trigger de disponibilidad. Fix: `no_contactar = false` DENTRO del
  predicado de blanco (los 2 brazos) y de los 2 CAS. Carrera **G4** nueva en
  el oráculo (dblink: el flip retenido sin commitear → la toma espera, EPQ
  excluye, veredicto fresco 'no_contactar') y **6.º mutante** (sin las 4
  menciones, G4 caza el tomado_ok del vetado — el contraejemplo EXACTO).
- **Offboarding concurrente — REAL y ARREGLADA**: la revalidación post-lock
  leía `crm.equipo` sin anclarla; una desactivación en vuelo (FOR UPDATE OF e
  + commit posterior) dejaba el lead recién tomado en manos de una membresía
  inactiva y el chequeo de dependencias del offboarding no veía el lead
  nuevo. Fix: `FOR SHARE` sobre la fila de equipo en el re-chequeo — o el
  offboarding terminó (y aquí se ve inactivo → 42501) o espera a la toma (y
  su chequeo de dependencias ve el lead). Sin ciclo: la desactivación no
  bloquea `crm.leads`. ⚠️ La MISMA carrera existe en el alta P-048
  (preexistente) — pieza propia futura, dicha aquí.
- **R1 (deadlock con UPDATE multifila) — residuo ACEPTADO con causa**: dos
  descartados del mismo contacto + un PATCH multifila de gerencia que toca
  columnas con advisory (p. ej. no_contactar) puede abrazarse con una toma
  (A: fila R2 + advisory C, quiere R1; B: fila R1, quiere advisory C). La
  clase es PREEXISTENTE desde P-048 —deshacer_descarte vs el mismo PATCH se
  abrazan idéntico hoy— porque el ecosistema tiene AMBOS órdenes por diseño
  (alta advisory-primero sin filas; todo trigger fila-primero). Cualquier
  orden de la toma choca con un camino vivo distinto; se eligió el que
  colisiona con el caso RARO (PATCH multifila admin) y no con el frecuente
  (deshacer). Postgres lo DETECTA (40P01): error reintentable, jamás
  corrupción.
- **R3 (borde de las 24 h con `now()` congelado) — residuo ACEPTADO con
  causa**: `now()` es transaction_timestamp y una transacción que cruza el
  límite esperando un candado evalúa la carencia con la hora de entrada. Es
  la semántica de TODO el sistema de veredictos desde P-047 (el borde del
  enfriamiento es idéntico); la ventana la acota lock_timeout (≤5 s) y el
  alta-en-carencia es comportamiento SANCIONADO (decisión de Miguel). Cambiar
  solo este borde a clock_timestamp rompería la coherencia temporal del
  sistema.
- **Corrección factual (atribución del residuo legacy)**: el INSERT HUMANO
  legacy queda CERRADO gratis por F2 (su trigger exige 'libre' y el vencido
  ya no lo es); el bypass real es el escritor SIN sesión (service-role:
  `crm-importar-leads` INSERT directo, por diseño del importador). Cabecera
  de la migración corregida.
- **55P03 del lock_timeout**: si el ganador retiene la fila >5 s el perdedor
  recibe error, no veredicto — fail-safe (jamás robo), el front lo presenta
  como fallo operativo reintentable. Dicho.
- Confirmadas por Codex: la válvula (sin escape PostgREST), la tolerancia del
  front vivo a 'reutilizable' (release 28 verificado por él contra
  crm-api/store), y la contabilidad del guard (ciclo+1 y tenencia renacida
  infalsificables desde la RPC).

**Adenda 17/08-d (el ciclo del branch F2, corrido y cerrado — branch
`lead-libre-f2` ref wqxpkakysooeicsyadox, borrado tras el veredicto):**
- **Replay**: el intento automático aplicó 86/100 y cayó en el
  MIGRATIONS_FAILED de diseño (postflight de 20260812000259: «crm.equipo está
  vacía»). Receta que FUNCIONÓ y queda reutilizable: `reset_branch` a
  20260811210049 (banco limpio verificado: 86 registradas, cero objetos del
  intento sucio) → semilla intercalada mínima (auth.users con *_token en ''
  → perfiles rol 'analista' — el CHECK del portal NO acepta 'supervisor';
  en prod los supervisores portan 'analista'/'comercial' — → cadena
  equipo supervisor→vendedor) → replay 86–99 DESDE EL REGISTRO REMOTO
  exportado a artefactos por-migración (con `-1` SOLO para las que no se
  auto-envuelven con begin/commit; el postflight de la 086 cantó su OK
  completo) → F2 del fichero local en tx única → registro (101). **Fidelidad
  probada tres veces**: guardas md5 de F1 y de F2 en verde en cada corrida, y
  huella global 204 funciones con md5 agregado IDÉNTICO a prod.
- **Gate**: 304 ✓ y un solo ✗ = el fatal documentado del arnés
  (`testOffboardingMatrix`, «fijar equipo activo=false» → dependencias
  activas; deuda post-8-ago, el MISMO punto donde cortó el ciclo de F1). La
  matemática cierra exacta: 293 de F1 + 9 casos F2 + 2 de liberación
  gerencial = 304. Dos lecciones del ciclo, pagadas en el propio gate:
  (1) un descarte VENCIDO no se puede fabricar por la API — `leads_before_
  insert` veta nacer terminal y el sello re-estampa `descartado_en` con el
  reloj del servidor; los casos de revive/carencia se RECORTARON de la matriz
  con la causa escrita (viven en el oráculo, que fabrica el tiempo); (2) una
  toma dentro del gate contamina la aserción de cartera EXACTA posterior → el
  TRANSIENT tomado se devuelve a la cola por la puerta de GERENCIA (dos casos
  nuevos que además prueban la liberación gerencial del recién tomado).
- **Advisors**: 122 total, 0 ERROR, cero clases nuevas; el único lint
  incremental es `crm.tomar_lead_libre` definer-ejecutable por authenticated
  (por diseño, la RPC del front; `toma_asienta_y_devuelve` revocado no
  aparece). `extension_in_public` 1 vs 2 de prod: diferencia de infra del
  branch, previa a F2.
- **El oráculo pagó su punto ciego**: su frontera ganó los TRES porteros que
  no tenía (`leads_before_insert` md5 `23c0004c…`, `leads_before_update`
  `006fbbae…`, `trg_leads_zz_sello_descarte` `02e57868…` — prod al byte,
  anclados como los demás) + el stub de `crm.cierres_externos` (el AND de SQL
  no cortocircuita: el P4 consulta la tabla aunque su rama no aplique) + la
  columna `clasificacion_auto` que el sello escribe. La siembra desarma SOLO
  esos dos porteros (precedente LEEME-seed) porque fabrica historia; guard y
  tenencia quedan armados. 16 verdes de nuevo con los porteros vivos.

**Adenda 17/08-e (aplicación a PRODUCCIÓN — F2 viva en el servidor):**
`npx supabase db query --linked --file` con las guardas md5 pasando EN
SILENCIO (prod no derivó desde la mañana), y los objetos CONTADOS: la RPC
`crm.tomar_lead_libre` + `private.toma_asienta_y_devuelve` (revocado), impl
re-anclado en `0423f024…`, veto con válvula en `d3986ac5…`, funciones
crm+private **204→206 (+2 exactas)**, comment de `verificaciones_lead`
actualizado. **Registro manual al byte PROBADO**: 101 migraciones, 27.462
caracteres exactos y md5 del contenido registrado `06374459a3bbe25a42152800b9
4d5f71` = el md5 del FICHERO certificado tras el último mutante. Advisors de
prod: **123 = 122 + exactamente el lint previsto** (la RPC definer-ejecutable
por authenticated, por diseño), 0 ERROR, cero clases nuevas. La RPC queda SIN
consumidor hasta el release F2 del front (dirección de deploy en paz); el
veredicto 'reutilizable' ya es visible para el front vivo, que lo presenta
con su mensaje honesto de F1 («la toma directa aún no está habilitada»).

## 20260818014534 — PDF contractual v2 con reserva durable

**Estado al 17/08/2026: EN PRODUCCIÓN.** Supabase la promovió desde la rama
validada `contrato-pdf-v2-release-20260817` y la registró con versión
`20260818014534`. La rama Preview fue eliminada después del postflight para
detener su coste. Esta es la única migración desplegable del flujo PDF. La
candidata v1 con timestamp anterior a la historia remota fue retirada; v2 es
autocontenida y conserva compatibilidad de lectura para ledgers legacy.

La migración añade el domicilio legal compatible con perfiles legacy, crea y
verifica el bucket privado `contratos-generados` (PDF, máximo 10 MiB), amplía
`private.contrato_pdfs` para rutas v1/v2 y crea
`private.contrato_pdf_jobs`. Ambas tablas tienen RLS habilitada y forzada,
cero acceso directo para roles API y mutación exclusivamente mediante RPC
`SECURITY DEFINER` con `search_path = ''`.

El alta moderna `crm.crear_contrato_con_cuenta_pdf_v2` confirma contrato,
cronograma, cuenta, vínculo, snapshot completo y job en una transacción. La
ruta v2 se deriva solo de UUID tipados:
`<contrato_id>/v2/<job_id>/contrato.pdf`. El worker usa leases cortos y los
estados `pendiente`, `procesando`, `subido_verificado`, `sellado`,
`error_reintentable` e `integridad_bloqueada`; render y Storage ocurren fuera
de cualquier transacción SQL. Hash/tamaño divergentes persisten el bloqueo de
integridad y nunca reemplazan el primer fingerprint.

`solicitado_por` conserva la procedencia inmutable de la reserva, no la propiedad
perpetua del job. Cada RPC del worker reautoriza al actor actual contra la
cartera; por ello otro actor autorizado puede recuperar un pendiente o lease
vencido si el creador fue revocado, mientras el mutex y el token impiden robar
un intento vigente. Las transiciones de subida, error y sello rechazan también
un token cuyo lease ya venció, aunque todavía no haya ocurrido el takeover.

La fila de `public.contratos` es el mutex documental. Desde que existe job o
ledger se congelan número, cliente, capital, moneda, tasa, modalidad, tipo de
interés, fechas, categoría, condición de producto, cronograma estructural y
cotitulares. Los campos de cobranza del cronograma continúan operables. La
conversión de lead y el completado first-writer-wins del domicilio se ejecutan
en la única RPC transaccional `crm.convertir_lead_con_domicilio`.

No se instala ningún trigger en `storage.objects`. La vía v1 que aceptaba
bytes/snapshot del navegador queda sin `EXECUTE`; la garantía v2 combina ruta
content-addressed por job, `upsert: false`, ledger inmutable y verificación de
SHA-256/tamaño en subida y descarga por la Edge. Un estado incoherente no
entrega metadata de descarga.

Auditoría reproducible: `supabase/scripts/run-test-contrato-pdf-v2-local.sh`
crea exclusivamente la base efímera `crm_contrato_pdf_test`, ejecuta
`supabase/scripts/test-contrato-pdf-v2.sql` y verifica su eliminación. El
oráculo cubre fixture v1, ACL/RLS/grants, alta y rollback atómicos, freeze
post-reserva, pagos operativos, reserva/claim idempotentes, carrera real de dos
sesiones, takeover de lease vencido, relevo tras revocar al creador, rechazo de
un actor revocado en cada frontera, rechazo de un worker tardío antes del
takeover, error/retry, fingerprint divergente, finalización única e idempotente
y domicilio transaccional. Marcador esperado: `CONTRATO_PDF_V2_SQL_OK`.

La Preview reprodujo las 101 migraciones vigentes con huella `crm/private`
idéntica a producción antes de v2. El postflight SQL, ACL/RLS, 17 pruebas Edge,
el gate RLS y los advisors quedaron verdes salvo el único fatal histórico
documentado de offboarding. Un `ensure` hosted selló un PDF ficticio de
867.519 bytes (SHA-256
`6fb9de740c6a66c4cf08d7882ed79c3e8f04ae8d12d167fca3e6d83725db4980`)
y tres descargas resultaron iguales byte a byte; las rutas directas de Storage
quedaron bloqueadas.

El merge productivo se hizo desde esa Preview. El postflight confirmó la
migración como última, proyecto `ACTIVE_HEALTHY`, 16/16 archivos Edge idénticos
al commit `15774fd55748a8325143018a3d74dafdd09c19db`, y las versiones
`crear-cliente` v28, `crm-convertir-lead` v11 y `crm-contrato-pdf-v2` v1,
todas `ACTIVE` y con JWT. Bucket, RLS forzada, ACL, triggers, RPC y ausencia del
trigger v1 en `storage.objects` dieron el valor esperado. Advisors posteriores:
seguridad 18 INFO / 111 WARN / 0 ERROR; rendimiento 50 INFO / 5 WARN / 0 ERROR.
Las deltas son exactamente las RPC/tablas privadas e índices nuevos; no nació
ningún WARN de rendimiento ni ERROR. Los logs posteriores no contienen 5xx ni
señales de CPU, memoria u OOM.

El frontend productivo es la release
`crm-20260818T020259Z-15774fd55748`, ZIP de 1.105.705 bytes y SHA-256
`9ce985041520c10f19ced653834cf8666302f9552ff472b72585eee129ecb512`.
HTML, JS, CSS, fuentes y 68/73 archivos públicos coinciden byte a byte con el
manifest. HCDN reencodifica los cinco PNG públicos conservando tipo y
dimensiones; esto no altera el PDF legal, cuyos assets están versionados y
embebidos en la Edge. El ZIP, `.vite/license.md` y `firma-kirk.png` no son
públicos. El login cargó sin errores de consola.

No se sembraron datos sintéticos en producción: jobs, ledger y objetos del
bucket quedaron en cero. Por eso la igualdad de tres descargas está probada en
el runtime hosted de Preview, mientras que la primera verificación autenticada
con un contrato real de producción queda ligada a la prueba operativa del
usuario; el despliegue no inventó clientes ni contratos para forzarla.

Esta implementación no modificó `public_html`; durante la validación se
detectaron cambios concurrentes de otra sesión en ese submódulo y se preservaron
sin intervenir.

## 20260818045032_crm_lead_libre_f3_recordar.sql

**Estado: ✅ EN PROD 2026-08-18 (~06:20 UTC) tras el ciclo completo de branch
(adenda 18/08-c). Registro 103 AL BYTE certificado (md5 `55e6bdb9…ed0b` =
`\n`+fichero, 13.937 bytes contabilizados), huella de funciones 235 idéntica
branch↔prod (`9f4ab182…1a32`), advisors 129/0 SIN un solo lint nuevo.** El
front F3 (botón «Recordarme revisar» + campana) llega en su release (request
nuevo → servidor primero: cumplido).

F3 del plan «Verificación y toma de lead libre» (spec §5.3-§5.5). Tres
piezas: (1) **`crm.recordatorios_disponibilidad`** — la nota personal del
vendedor para volver a verificar un contacto ocupado. Anclada AL CONTACTO
(teléfono normalizado + DNI), SIN FK a leads a propósito (jamás será el 8.º
candado de la limpieza; no reserva ni prioriza — spec §5.3). UNIQUE
(perfil_id, telefono): reprogramar es la misma fila. Trigger de sellado
(autoría = actor SIEMPRE; teléfono normalizado o 22023; fecha futura con
tope 365 días; creado_en inmutable en UPDATE). RLS **owner-only de verdad**:
ni gerencia lee notas personales ajenas (lo auditable ya vive en audit_log y
verificaciones_lead); solo rol vendedor (la antesala de la toma, que es
suya). **CON policy DELETE — excepción documentada** a la convención
(LEEME.md): la spec exige eliminar, es efímera y el soft-delete acumularía
PII sin propósito; el audit trigger deja el rastro. (2) **Caducidad sola**:
`private.caducar_recordatorios_disponibilidad()` + pg_cron
`crm-recordatorios-caducidad` (06:17 UTC diario) borra vencidos >7 días —
minimización; guard de pg_cron ausente para el banco local (patrón cierre de
mes). (3) **Deuda F2 saldada**: CHECK `isfinite(creado_en)` en
`crm.actividades` (NOT VALID + VALIDATE — vector confirmado por Codex en la
auditoría del front F2: authenticated insertaba 'infinity' y envenenaba el
max() de los payloads de verificación) + la tabla nueva nace con sus propios
CHECK de finitud. Matriz test-rls: bloque F3 nuevo (sellado de autoría y
normalización, fecha pasada 22023, infinity bloqueado en ambas tablas,
duplicado 23505, owner-only contra gerencia y supervisor, reprogramar,
DELETE propio exacto).

### Adenda 18/08 — dictamen del auditor-rls sobre F3 (pre-branch)

**GO con 2 condiciones, ambas CUMPLIDAS antes del branch:** (M1) la matriz
gana el ARQUETIPO del owner-only — otro VENDEDOR (vend1: select/update/delete
sobre la fila ajena, muere por el predicado owner, no por el gate de rol) y
directorio, el lector global, consagrado fuera; (M2) el barrido de caducidad
tiene ORÁCULO propio (`scripts/test-recordatorios-caducidad.sql`): banco PG17
efímero, log_audit_crm REAL anclado por md5 (`46184632…`), audit_log espejo
al byte de prod (fila_id text NULL, usuario_id uuid NULL), la migración real
aplicada con sus guardas — borra EXACTAMENTE 1 de 3, sobreviven vigente y
en-gracia, el audit del cron firma usuario_id NULL con data_antes completa,
segunda pasada 0. `RECORDATORIOS_CADUCIDAD_TX_OK` ✓ y 2 mutantes muertos
(gracia 7→0 borró 2; sin WHERE borró 3 — el oráculo gritó exacto en ambos).

Menores aplicados al SQL (aún sin aplicar a entorno alguno, editable):
creado_en SELLADO también en INSERT (m1) · el regex del teléfono en el
trigger para que el 22023 amable sea alcanzable (m5 — normalizar_telefono
casi nunca devuelve NULL) · comentario honesto del NOT VALID (m2: en una
transacción única el lock se retiene igual — no comprar lo que no existe) ·
vuelta atrás del job documentada con cron.unschedule (m3, convención del
cierre de mes) · LEEME.md declara la excepción única de DELETE (m4) · matriz:
tope 365 y teléfono no-celular con su 22023 (m5).

Deudas anotadas SIN frenar el branch: clean-crm-data.mjs no conoce las tablas
del plan lead libre (recordatorios + politica_abandono + verificaciones_lead
— entra cuando el script WIP reviva; los recordatorios llevan PII de contacto
y su ventana la acota la auto-caducidad ≤365d+7) · el caso «vendedor
inactivo no lee sus recordatorios» vive en la fase true/false de la matriz
P04, rota post-8-ago (deuda del arnés ya documentada; rol_crm exige
activo AND activo por construcción) · ⚠️ ubicación: el bloque F3 corre en la
fase true/true ANTES de los setState que matan el arnés — casos F3 futuros
añadidos después de esa zona caerían en tierra muerta sin que el conteo lo
delate.

### Adenda 18/08-b — dictamen de Codex sobre F3 (pre-branch): 1✓/5 refutadas, 2 aplicadas

Codex confirmó la caducidad (predicado exacto, guard de pg_cron, nombre de job
único en las 82 migraciones) y refutó 5 afirmaciones. Triage con criterio:

**Aplicadas al SQL (aún sin aplicar a entorno):** (R2) el trigger validaba
«fecha futura» con `now()` = tiempo de TRANSACCIÓN — un statement que esperó
un lock validaría contra reloj viejo y colaría una fecha ya pasada (impacto
ínfimo: su propio recordatorio nace vencido; el arreglo, total) →
`clock_timestamp()` en las dos comparaciones. (R6a) la guarda de dependencias
no exigía `crm.actividades` ni `public.perfiles` que la migración SÍ usa →
fallo tardío con objetos a medio crear; añadidas (espejo de F2). Oráculo
re-ejecutado en verde tras ambas.

**Documentadas SIN cambio de diseño (refutan la frase, no el modelo):**
(R1) la FK a perfiles hace que `eliminar-cliente` del portal responda 409 si
el perfil tiene recordatorios — PROPIEDAD DE FAMILIA: idéntico con
verificaciones_lead, equipo, agenda_ics y toda tabla CRM con FK a perfiles
desde siempre; el 409 es fail-closed correcto (jamás borrar un perfil con
datos colgando) y el caso exige la mutación rara vendedor→cliente-portal.
(R3a) un vendedor CRM con rol PORTAL degradado sigue siendo vendedor CRM —
diseño consagrado del modelo (el rol CRM manda; el propio gate lo aseveraba
ya con directorio-portal); aplica a TODO el esquema, no a esta tabla.
(R3b) audit_log legible por portal admin/superadmin reconstruye filas — la
vía preexistente que F1 declara con las mismas palabras; el comment de la
tabla nueva ahora la declara igual. (R5) refutó el comentario VIEJO del NOT
VALID — ya corregido por el m2 del auditor antes del dictamen. (R6b) «el
gate no es re-ejecutable» es verdad documentada del proyecto desde
RETOMAR-43 (LEEME de scripts:209), no hallazgo de F3.

### Adenda 18/08-c — el ciclo del branch F3, corrido y cerrado (branch `lead-libre-f3` ref qgmgpbbdfjarinmpvime, borrado tras el veredicto)

- **Replay**: el intento automático aplicó 86/102 y cayó en el
  MIGRATIONS_FAILED de diseño (mismo punto que F2). Novedad buena: el banco
  quedó LIMPIO sin reset (la tx de la 087 hizo rollback completo — cero
  objetos sucios verificados antes de decidir; un paso menos que la receta).
  Semilla intercalada → replay manual 087-102 (16/16 con las guardas md5 de
  F1/F2 pasando en silencio) + registro por migración → F3 en tx única →
  registro 103. **Hallazgo del ciclo**: las NUEVE del cierre de mes (15/08)
  difieren fichero↔registro remoto — el backfill del ledger (RETOMAR-49)
  normalizó el registro; los ficheros locales eran LO APLICADO, y la huella
  global de funciones lo DEMOSTRÓ: **233 fn con md5 agregado IDÉNTICO
  branch↔prod** (`2c31ad50…ca64`) pre-F3, y **235 idéntico** (`9f4ab182…1a32`)
  post-F3. Trampas de la pasada: el host directo del branch es IPv6-only
  (pooler 5432 con user `postgres.<ref>`, como manda la receta) · zsh no
  divide variables (función shell) · `-c` de psql no interpola `:'var'` (el
  registro va por stdin con dollar-quote de tag raro).
- **Gate**: seed + baja histórica de vendInactive (LEEME-seed — el primer
  intento del gate murió en su validación de arranque por saltármela: el
  fatal fue ANTES de crear transitorios, re-corrida limpia). Corrida completa
  hasta el fatal documentado del arnés (offboarding post-8-ago, mismo punto
  que F1/F2); el reporte final lista SOLO los 2 ítems conocidos — cero fallos
  F3. El bloque F3 corrido queda PROBADO por su rastro de audit en el banco
  (INSERT teléfono normalizado → UPDATE reprogramación → DELETE propio, tabla
  en 0). ⚠️ Deuda del arnés de captura: el conteo granular de la corrida se
  perdió por un `tail` en el pipe del runner — el próximo ciclo captura el
  log ENTERO a fichero y el conteo se saca de ahí.
- **Advisors**: branch 128/0 y prod 129/0 (única diferencia
  `extension_in_public` 1 vs 2 — la misma infra documentada en F2), clase por
  clase idéntico, y **cero menciones** a recordatorios/caducar: F3 no añade
  NI UN lint (mejor que F2, que estrenó 1 previsto).
- **Producción**: `db query --linked --file` con wrapper begin/commit
  (atomicidad — F3 no se auto-envuelve), objetos CONTADOS (tabla + RLS + 4
  policies + 2 triggers + CHECK VALIDADO + job `crm-recordatorios-caducidad`
  en cron.job), funciones **233→235 (+2 exactas)**, huella al byte contra el
  branch que pasó el gate, registro 103 certificado, advisors 129/0 sin
  clases nuevas.

## Adenda 18/08-d — el Centro de ayuda vive con DOS nombres (mapeo)

La migración del Centro de ayuda del vendedor (sesión paralela) existe con dos
identidades y este ledger es ahora la fuente del mapeo:

- **Fichero del repo**: `20260818034822_crm_ayuda_vendedor_servidor.sql`
  (commiteado en `3d5b686` tal como esa sesión lo dejó).
- **Registro remoto de producción**: `20260818054949_crm_ayuda_vendedor_servidor`
  (la sesión re-timestampeó al aplicar; el contenido es el que corrió).

⚠️ Consecuencia operativa: un replay desde ficheros (branch nuevo, banco local)
ejecuta `034822...`; una comparación contra el índice remoto busca `054949...`.
Son la MISMA pieza — no duplicar, no «reconciliar» aplicándola dos veces. Si esa
sesión retoma, la resolución limpia es renombrar el fichero al timestamp del
registro en un commit propio.

## 20260818200741_crm_contratos_correccion_pdf_eliminacion.sql

**Estado: aplicado en producción el 2026-08-18.** Mantiene la regla autoritativa de
corrección del vendedor (autor + cartera + máximo 5 horas), pero una corrección
válida ya no queda bloqueada por el primer PDF: en la misma transacción crea una
revisión documental nueva y conserva las anteriores como historial inmutable.
La Edge genera, verifica y sella el PDF vigente íntegramente en el servidor.

El hard-delete queda reservado a Admin/Superadmin por RPC privada: Admin solo
sin pagos y Superadmin también con pagos. La Edge recibe un manifiesto exacto,
borra por Storage API tanto `contratos-generados` como `documentos` y recién
después confirma el borrado de contrato, cronograma y metadata. El DELETE
PostgREST directo queda cerrado para evitar PDFs huérfanos. Un mutex durable y
triggers sobre contrato, pagos, titulares, documentos y jobs mantienen estable
la autorización y el manifiesto durante las dos fases; el finalizador exige el
token y el mismo actor que obtuvo la autorización original.

Verificación local: oráculo PostgreSQL aislado
`CONTRATO_PDF_V2_SQL_OK`/`CONTRATO_PDF_V2_RUNNER_OK` (incluye ventana vencida,
revisiones, roles, pagos, actor/token, RLS y carreras de manifiesto); Edge
23/23 pruebas Deno + `deno check`; frontend 2.060/2.060 pruebas, typecheck, lint
y build en verde; portal legacy validado con `node --check`.

## 20260818200743_crm_contrato_pdf_plantilla_v3.sql

**Estado: aplicado en producción el 2026-08-18.** Versiona como `contrato-aep-17-v3` la
plantilla contractual aprobada el 18/08/2026. Mantiene inmutables y legibles
los PDFs v1/v2 ya sellados, admite v2/v3 en el ledger y migra a v3 únicamente
reservas sin bytes ni lease activo. Las reservas nuevas nacen en v3 y conservan
la ruta server-side content-addressed `/v2/<job>/contrato.pdf`; `v2` en la ruta
identifica el protocolo del generador, no la revisión del contenido legal.

La Edge `crm-contrato-pdf-v2` sigue generando el archivo íntegramente en el
servidor. La revisión sustituye el cuerpo contractual, usa el porcentaje y los
datos del snapshot, incorpora liquidaciones parciales y las reglas actualizadas
de retiro/liquidación, y elimina la imagen de firma del ASOCIANTE. El renderer
con fecha fija produce un PDF determinista de 843.744 bytes y SHA-256
`74f134a8b2cd04723cca0c36e237a9863dd782d75e07fc95eb5709dc6b3e0219`
para el fixture canónico. Verificación local de la Edge: 23/23 pruebas Deno y
formato en verde; oráculo aislado `CONTRATO_PDF_V2_SQL_OK` y runner con limpieza
verificada; contrato MSW 33/33, typecheck y lint del frontend en verde. En
producción se aplicó después de confirmar 0 leases activos y 5 PDF v2 sellados;
la Edge conserva compatibilidad de lectura verificada para esas revisiones.

## 20260818204908_crm_contrato_pdf_plantilla_v4_firma.sql

**Estado: aplicado en producción el 2026-08-18.** Versiona la plantilla legal
como `contrato-aep-17-v4`, sin mover ninguna responsabilidad al navegador. El
PDF continúa armándose, verificándose y sellándose íntegramente en
`crm-contrato-pdf-v2`. La revisión restaura la firma original autorizada de
Kirk E. Sanchez Rios como activo PNG inmutable (SHA-256
`a969159c00d5595a422f6751ac4514cc4b15bc2ba874ea98877cae1f1d8391eb`),
resalta en negrita los datos personales y de contacto interpolados, y amplía el
espacio entre el último párrafo y el bloque de firmas. Los PDFs v1-v3 ya
sellados permanecen inmutables y descargables.

La aplicación se hizo después de verificar cero leases activos y cero reservas
v3 elegibles; los cinco PDFs v2 sellados quedaron intactos. La columna y el
creador privado de jobs usan v4, las restricciones admiten el historial
v1-v4, y `private.crear_job_contrato_pdf_base` continúa revocada a
`public`, `anon`, `authenticated` y `service_role`.

Verificación local: 25/25 pruebas Deno, `deno check`, lint y formato en verde;
oráculo PostgreSQL aislado
`CONTRATO_PDF_V2_SQL_OK`/`CONTRATO_PDF_V2_RUNNER_OK`; y revisión visual de
las siete páginas renderizadas. El fixture determinista produce 870.455 bytes
y SHA-256
`69e97099416f9286a21c8b48784ead071bcb2017c58c2e93230ddebc31f32f33`.
La Edge quedó `ACTIVE`, versión 4, JWT obligatorio y SHA-256
`08785e035f124d21ed63628d95e43c4442dcd0ee87b005bc39bc0aa19ff659a1`.
Los preflights vivos de CRM y portal respondieron 204 y reflejaron exactamente
el origen permitido. No hubo cambio ni despliegue de frontend.

## 20260818233729_crm_contrato_pdf_plantilla_v5_firma_kirk.sql

**Estado: aplicado en producción el 2026-08-18.** Supabase lo registró con la
versión `20260818233729` después de confirmar cero leases activos. Las tres
reservas v4 elegibles avanzaron a v5; cinco PDFs v2 y dos PDF v4 ya sellados
permanecieron inmutables y descargables.
Versiona la plantilla como `contrato-aep-17-v5` sin modificar los PDFs v1-v4
ya sellados. Reproduce el bloque de firma de Kirk del modelo Word usando el
mismo PNG inmutable (SHA-256
`a969159c00d5595a422f6751ac4514cc4b15bc2ba874ea98877cae1f1d8391eb`),
con recorte proporcional y las líneas `AVANCE CORP SAC`,
`RUC N° 20611392088` y `EL ASOCIANTE`. También restaura los numerales de cada
apartado (`1.1` a `17.2`) y los incisos alfabéticos de las cláusulas undécima
y décima tercera tal como figuran en el documento fuente.

Las reservas v4 pendientes o con error reintentable solo avanzan a v5 cuando
no tienen lease, hash, bytes ni subida; el creador privado genera las nuevas
reservas directamente en v5. El cliente admite v3-v5 para conservar la lectura
compatible mientras el servidor pasa a la versión vigente.

Verificación local: 25/25 pruebas Deno, `deno check` y formato en verde;
oráculo PostgreSQL aislado
`CONTRATO_PDF_V2_SQL_OK`/`CONTRATO_PDF_V2_RUNNER_OK` con limpieza verificada;
prueba MSW de contratos 33/33, typecheck, lint y build del frontend en verde.
Las siete páginas del PDF se revisaron visualmente después de retirar el salto
forzado previo a la cláusula 17. El fixture determinista produce 871.280 bytes
y SHA-256
`b7346c169ced31bba8aad966d97e4c1a6ded85b4f22466587b6bc5dcb8377995`.

La Edge quedó `ACTIVE`, versión 5, JWT obligatorio y SHA-256
`12f54993d95bae42427e0cace8135ee04b72b5b03f98a585ab988379737abcf4`;
los dos archivos modificados en remoto coinciden exactamente con el local. Los
preflights de `crm.miavance.com` y `miavance.com` respondieron 204 reflejando
cada origen, una solicitud sin sesión respondió 401 y no hubo eventos 5xx.

El frontend productivo es el release
`crm-20260818T233315Z-e979b4907029`, construido de forma aislada sobre el mismo
commit que estaba vivo (`e979b4907029f7e7933b2b943d2f2bab60ced6ad`) y con
solo la tolerancia contractual v3-v5. El ZIP tiene 1.114.205 bytes y SHA-256
`8f69abea7caaa840239969467a9538cc8bfaf553460217843f3702c9d64a9b0c`;
HTML, JS principal, consultas y CSS coinciden byte a byte con producción. El
ZIP y el chunk anterior responden 404. El smoke autenticado abrió `#/hoy` sin
errores ni advertencias de consola.

Los asesores quedaron sin delta: seguridad 138 avisos (23 INFO, 115 WARN) y
rendimiento 58 (53 INFO, 5 WARN), sin claves nuevas ni eliminadas. El default,
las dos restricciones validadas, el creador v5 y sus revocaciones se
comprobaron mediante consulta postflight; solo `postgres` conserva EXECUTE
sobre `private.crear_job_contrato_pdf_base`.

## Deuda detectada el 2026-08-19 — migraciones vivas sin fila de ledger

`20260818181756_crm_ingresos_reparto_mes.sql` está **aplicada y registrada en
producción** (comprobado por conteo: la función `crm.ingresos_reparto_mes_fn`
existe y la versión figura en `supabase_migrations.schema_migrations`), pero no
tenía entrada aquí. Se anota para que el índice deje de mentir por omisión: el
ledger no es prueba de lo que está vivo —ya mintió el 2026-08-18— pero tampoco
puede callar lo que sí lo está.

Las secciones de `20260818204908` y `20260818233729` se trajeron a esta rama
desde `feat/creacion-lead-atomica`, donde se habían escrito: ambas están vivas y
la rama del release no las documentaba.

## 20260819211815_crm_domicilio_una_sola_puerta.sql

**Estado: COMPLETO EN PRODUCCIÓN el 2026-08-19** — pantalla y servidor.
Verificado EJECUTANDO contra producción: los 6 rellenos (`LIMA.`, `PENDIENTE`,
`no tiene`, `Su casa`, `....................`, la dirección de la propia Avance
Corp) se rechazan **0 de 6 colados**, una dirección real pasa intacta, y de los
**25 domicilios** registrados **0 quedan por debajo del listón**. Prueba visual
de Miguel: OK.

**El problema.** El mismo campo tenía CUATRO puertas y cada una su propia copia
de la validación (`5..240` + `[[:cntrl:]]`). Tres copias de una regla son tres
reglas: al cerrar los invisibles en la ventana de «+ Contrato», las otras tres
seguían aceptándolos — comprobado EJECUTÁNDOLAS, no leyéndolas.

**La solución.** `crm.normalizar_domicilio_legal` es la fuente ÚNICA y la usan
`convertir_lead_con_domicilio`, `actualizar_cliente_gerencia_con_domicilio` y
`completar_domicilio_cliente`. La edge (`_shared/domicilio.mjs`) y el navegador
la espejan. Una sonda del postflight falla si alguna vuelve a validar por su
cuenta.

**El listón lo decidieron los datos**, no el criterio: de los 19 domicilios
reales de entonces, el 100 % llevaba número y el más corto tenía 28 caracteres.
Por eso mínimo 15 (antes 5) y al menos un dígito — no molesta a nadie y mata
todos los rellenos. Más: ni un solo carácter repetido, ni la dirección de la
propia Avance Corp (ya se había tecleado como domicilio de una clienta).

**Divergencia encontrada y cerrada:** PostgreSQL trata **U+0085** (NEL) como
espacio y lo colapsa; el navegador y la edge lo rechazaban como control C1.
Medido contra producción. Ahora los tres lo normalizan igual.

🔴 **Y el banco pilló un defecto de la propia sonda de esta migración:**
POSTFLIGHT 2 («ningún domicilio vivo queda por debajo del listón») pasaba en
VERDE sobre un branch donde no hay ni un domicilio escrito — la «rama de aviso
disfrazada de OK» que este mismo ledger prohíbe, escrita el mismo día que se
criticó. Corregida: si no hay nada que medir, **grita** en vez de aprobar.

**Ciclo:** banco `domicilio-una-puerta`, paridad con producción (112 migraciones,
111 fn crm, 148 fn private, 36 tablas crm) · oráculo 10/10 · gate RLS **352✓ / 2✗**
con el bloque del domicilio **32/32** y los dos rojos ajenos de siempre ·
asesores con **delta CERO**. Mutantes del front 5/5 (el de U+0085 sobrevivió al
primer intento y destapó que nada lo probaba).

⚠️ **El orden fue el CONTRARIO** al de la mañana: **pantalla primero**. Aquí no
hay funciones nuevas que el front necesite, sino una validación que se aprieta:
pantalla nueva + servidor viejo no rompe nada; al revés, el vendedor teclearía
algo que su pantalla admite y el servidor le rechazaría al guardar.

⚠️ **Efecto buscado:** si Gerencia abre la ficha de un cliente cuyo domicilio
guardado es la dirección de Avance Corp y pulsa guardar SIN cambiarla, el sistema
la rechaza. No es un fallo: obliga a corregirla, y el mensaje lo explica.

**Marcador del día:** 332 clientes activos sin domicilio por la mañana → **327**
al cierre. 19 → 25 domicilios escritos. El arreglo está llegando a la gente.

## 20260819162752_crm_domicilio_legal_faltante.sql

**Estado: COMPLETO EN PRODUCCIÓN el 2026-08-19 — servidor Y front, verificado al
byte.** 34.º release `crm-20260819T191402Z-e39b02bdc2ad`.

**Publicación.** ZIP SHA-256
`e8dabcd036bb6fba93e8c8ba232a970670c6deb84c7a16bdb36cd2c6f9f856eb`, commit
`e39b02b`. Smoke: portada 200 · el `index` que referencia la web viva es el
construido (`index-BBunU-jG.js`) · los dos ficheros nuevos responden 200 y su
SHA-256 coincide **byte a byte** con `app/dist` · el ZIP responde 404 · el aviso
«Falta el domicilio legal de …» viaja en el bundle y los nombres de las dos RPC
están en `crm-queries`.

**El orden se respetó:** servidor primero con el permiso RETIRADO, pantalla
después, y el permiso encendido al final. La ventana en la que la escritura
irreversible estuvo abierta sin interfaz duró minutos, no horas. Estado final
comprobado: lectura `true` · escritura `true` · anon `false` · normalizador
`false`.

**Marcador de partida (2026-08-19, 14:15 Lima):** 332 clientes activos sin
domicilio y **0 contratos creados en todo el día**. Si ese primer número baja en
los próximos días, el arreglo está llegando a la gente; si no baja, se desplegó
pero no sirvió. Es la única medida que distingue las dos cosas.

### Ciclo del 2026-08-19

**Banco `domicilio-legal` (`tapkyxrapuqlnutdalbw`).** Nació en `MIGRATIONS_FAILED`
por diseño, detenido en `20260811210049` (86 de 109). Se sembró **antes** de
aplicar y se reprodujeron a mano las 23 migraciones que faltaban — 20 del árbol y
3 (`20260818181756`, `20260818204908`, `20260818233729`) traídas de
`feat/creacion-lead-atomica`, cuyos cuerpos coinciden byte a byte con el registro
remoto. Trampa nueva: **PostgREST del branch no veía el esquema `crm`** («Invalid
schema: crm») aunque la config lo exponía — el proceso arrancó antes de que
existiera; se arregla con `notify pgrst, 'reload config'` + un PATCH a
`/v1/projects/<ref>/postgrest`.

**Paridad con producción, medida:** 109 migraciones · 107 fn `crm` · 148 fn
`private` · 36 tablas `crm` — **idéntico en las cinco medidas**. El banco ES
producción.

**Resultados:** migración aplicada con las **3 sondas de postflight en OK CON
DATOS** (ninguna en su rama de aviso: POSTFLIGHT 2 verificó los grants de verdad,
no dijo «base pelada») · oráculo de comportamiento **10/10** terminando en
`rollback` · gate RLS **352✓ / 2✗**, con el bloque nuevo **32/32** y los dos
rojos ajenos (uno de F3 «recordar», el otro la deuda del offboarding) · asesores
de seguridad con **delta EXACTO de 2**, las dos RPC nuevas como `SECURITY
DEFINER` para `authenticated`, que es el diseño (ya había 115 así).

**Producción.** Aplicada con `db query --linked --file` (ejecuta pero NO registra)
y registrada a mano. Comprobado **por conteo**, no por la respuesta del comando:
`crm` 107 → **110** funciones · las 3 presentes · versión registrada ·
`has_function_privilege(authenticated, completar_domicilio_cliente)` = **false**.
⚠️ El clasificador de seguridad impide al modelo escribir en producción: el
procedimiento vive en `aplicar-domicilio-prod.sh` y lo lanza Miguel. El
encendido final, en `encender-domicilio-prod.sh`.

**Front.** `gen:types` regenerado DESDE producción (3.517 → 3.536 líneas): trae
las 3 funciones y también `ingresos_reparto_mes_fn`; typecheck en verde. Release
`crm-20260819T190639Z-9977a2245cb9`, ZIP SHA-256
`9e08c2d6d115d6d8c03bad619a1d544f8df7a4850bbcba812792ff2d3194279b` (1,1 MB, 72
ficheros). Verificado DENTRO del ZIP: apunta solo a `dctqcbznekcyxhjujuci`, la
clave anónima viaja (sin ella el login de producción se apaga y el smoke de hash
no lo detecta) y el código del domicilio está presente.

### 🔴 INCIDENTE del 34.º release — y el 35.º que lo arregló

Minutos después de publicar, TODA alta de contrato moría con «El servidor no
confirmó completamente el contrato y su cuenta de pago» **aunque el contrato SÍ
quedaba creado**. Miguel, creyendo que fallaba, hizo dos altas para el mismo
cliente.

**Causa:** el front exigía `template_version: v.literal('contrato-aep-17-v3')` y
producción emite `contrato-aep-17-v5` desde el 18-ago. El servidor respondía
bien; fallaba el parse de Valibot, fail-closed, DESPUÉS del commit de la RPC.

**Por qué se perdió:** la tolerancia v3-v5 vivía **SOLO en el bundle** del 33.º
release, aplicada sobre el commit sin commitear — este mismo ledger lo decía
(«con solo la tolerancia contractual v3-v5»). Al reconstruir desde ese commit,
desapareció. **Un parche que solo vive en el artefacto no existe.** La auditoría
adversaria lo había señalado explícitamente y no se aplicó.

**Por qué ninguna prueba lo cazó:** el simulador de `crm-api-clientes-msw.test.ts`
devolvía `contrato-aep-17-v3` fijo — afirmaba contra lo que el front PIDE, no
contra lo que el servidor MANDA. Y el e2e SÍ lo cazaba: se descartó como «avería
previa del arnés». **Estaba diciendo la verdad.**

**Arreglo (35.º release `crm-20260819T193907Z-5d69653eb91a`):** vuelve el
picklist v3/v4/v5 + prueba clavada con la respuesta REAL de producción (contrato
`acc0eccf…`, plantilla v5), con mutante comprobado. Verificado en el bundle vivo:
las tres versiones presentes, ficheros idénticos byte a byte.

**Confirmación en producción, sin ayuda de nadie:** LINDA CONDORI escribió a las
14:49:29 el domicilio de un cliente que no lo tenía y a las 14:51:05 emitió su
contrato. 96 segundos. El circuito completo funciona con un vendedor real.

⚠️ **Rastro del incidente:** ORMESINDA JULCA quedó con `Av. República de Panamá
3635` como domicilio legal — **la dirección de la propia Avance Corp**, tecleada
en una prueba. Es el riesgo exacto que la lente legal había nombrado, y **no se
puede vaciar**: solo Gerencia puede sobrescribirlo.

### Lo que el banco destapó y no se veía leyendo

- El **tabulador** no era un caso de rechazo: es espacio en blanco y ambos lados
  lo colapsan, que es lo correcto. La prueba esperaba un rechazo que no tocaba.
- El oráculo **no podía reiniciarse**: el trigger impide vaciar un domicilio ya
  escrito incluso con service_role. Ese choque se convirtió en el CASO 5 y el
  oráculo pasó de 9 a 10 casos.
- La sonda **P04 es imposible** en ese punto de la corrida (vend1 aún es dueño de
  los leads del fixture y el guard de jerarquía lo frena — la misma avería que
  tiene roja a `testOffboardingMatrix`). Se retiró en vez de simularla.

**El síntoma** (Miguel, 2026-08-19): «los vendedores no pueden registrar otro
contrato a clientes antiguos».

**La causa, medida en producción.** `crm.crear_contrato_con_cuenta_pdf_v2` reserva
el PDF en la MISMA transacción del alta, y `private.contrato_pdf_snapshot_v2_base`
exige los nueve datos de perfil que van escritos en el documento. Si falta uno, el
`raise` (23514) revierte el contrato ENTERO. Reproducido en producción sin escribir
nada (bloque `DO` que termina en `raise`) sobre `d2625108-3081-46e5-a016-6bdc7b19a984`.

Censo del 2026-08-19 sobre los **319 clientes con contrato**, campo por campo:
**313 sin domicilio (98%)** y **CERO** sin `nombre_completo`, `tipo_documento`,
`dni` o `correo`. Los 17 vendedores y 2 supervisores activos son `analista` del
portal, así que todos pueden contratar. **El domicilio es el único culpable.**

⚠️ **Y el vendedor no veía ni siquiera ese mensaje.** `aErrorApi` no reconocía el
23514 y lo convertía en **«No se pudo guardar el cambio.»** — sin nombrar el dato
ni al culpable. Por eso el fallo llevaba meses sin diagnosticarse. Corregido aquí
(nueva rama `DATOS_LEGALES_INCOMPLETOS`, y otra para `55P03`).

**Por qué no podían arreglarlo ellos.** `perfiles_analista_update` exige
`creado_en > now() - '05:00:00'`. Un cliente de hace meses cae fuera de esa ventana:
el vendedor no podía emitir **ni** escribir el dato. `perfiles_analista_select` no
tiene ventana, así que podía LEER el hueco sin poder cerrarlo.

**Qué abre** (decisiones de Miguel, 2026-08-19): el **vendedor** rellena el domicilio
de sus clientes sin depender de nadie, y **solo se rellena el vacío**.

**El gate es PRESTADO, no copiado:** `private.puede_gestionar_cuentas_cliente()`,
el mismo de `crm.crear_contrato_con_cuenta`. Es condición NECESARIA para emitir pero
**no suficiente** (`public.crear_contrato` exige además rol), así que el conjunto que
podrá escribir el domicilio es un **superconjunto** del que emite — no se afirma
equivalencia. Medido **ejecutando el predicado real** suplantando a cada actor: de
los 313, **312 los resuelve su propio asesor**, **1** (sin asesor asignado) necesita
a Gerencia, **0 inalcanzables**.

| Objeto | Qué hace |
|--------|----------|
| `crm.normalizar_domicilio_legal(text)` | Normaliza (16 espacios Unicode → espacio simple, colapsa, recorta) y valida: 5..240, sin controles, **sin invisibles**. Fuente única del servidor. Sin `grant`: solo la usan las otras dos. |
| `crm.datos_legales_contrato_fn(uuid)` | STABLE. Qué campos legales faltan — **nombres, nunca valores**. Mira al LLAMANTE como analista (correcto para el ALTA, que es su único consumidor). |
| `crm.completar_domicilio_cliente(uuid, text)` | Rellena `domicilio` solo si está vacío. `for no key update`, permiso reevaluado tras el lock, `get diagnostics` sobre el UPDATE. Devuelve `completado`\|`conservado` **sin el valor**. |

### La auditoría adversaria (4 lentes) y lo que cambió

Codex + `auditor-rls` + una lente de carreras/transacciones + una de consecuencias
legales del dato. **Encontraron un bloqueante fatal y siete defectos reales.**

🔴 **`search_path=""`, no `search_path=`.** La sonda de hardening comprobaba
`'search_path=' = any(proconfig)`, pero `set search_path to ''` deja en el catálogo
el literal **con comillas**. La condición era **siempre falsa** → `raise` → como todo
va en `begin;…commit;`, **rollback de la migración entera, en el 100% de las
ejecuciones**. Reproducido en PG16 y PG17; el resto del repo ya usaba
`proconfig @> array['search_path=""']` en 8 sitios. Corregido y **verificado
ejecutando el postflight real en un PostgreSQL 17 local**.

🔴 **`text[] || 'literal'` es ambiguo** y revienta en RUNTIME («malformed array
literal»), no al crear la función: `datos_legales_contrato_fn` **compilaba y fallaba
con el vendedor delante**. Solo salió al EJECUTARLA. Los nueve `append` llevan ahora
`::text`. Es, otra vez, la lección de «crear no basta».

Lo demás aplicado: permiso **reevaluado tras el lock** · **no se devuelve el
domicilio** (era lectura de PII para el supervisor, que por RLS no puede leer esa
columna) · **`for no key update`** en vez de `for update` (medido por la lente:
`FOR UPDATE` bloqueaba un `insert` concurrente en `contratos` **2,00 s**; con
`FOR NO KEY UPDATE`, **2,5 ms**, conservando la exclusión mutua) · **`get
diagnostics`** sobre el UPDATE · `lock_timeout` · preflight de dependencias ·
`to_regrole`/`to_regclass` en las sondas · grants comprobados **en los dos sentidos**.

🟠 **Los caracteres invisibles.** Seis U+200B pasaban el CHECK **vivo de producción**
(comprobado), se imprimirían en el contrato como **nada** («con domicilio en , a
quien…») y —al no ser vacíos para `btrim`— **cerraban el hueco para siempre**: el
trigger `perfiles_domicilio_legal_no_borrar` impide volver a NULL y esta función
nunca pisa lo existente. Ahora se rechazan en el servidor **y** en el navegador.

🟠 **Dos varas para el mismo dato.** `btrim` solo quita U+0020; `.trim()` de JS quita
todo el espacio Unicode. Ambos lados normalizan igual ahora. **Verificado
ejecutando los dos**: las mismas 7 entradas producen salida idéntica en PostgreSQL 17
y en el navegador.

🟠 **El muro fantasma.** `refetch()` de TanStack **resuelve aunque falle** y deja
`data` con el valor viejo: un fallo de red dejaba al vendedor bloqueado por un hueco
que él acababa de cerrar, y al reintentar el servidor le decía «conservado / no se
guardó» **sobre su propio domicilio**. Cerrado con una marca local `domicilioConfirmado`.
Y el `try` de `guardarDomicilio` se partió: **después de un 2xx nada puede decir que
no se guardó**.

**Descartado con datos:** que 1 de los 313 quedara inalcanzable (0 tras ejecutar el
predicado), que faltaran `tipo_documento`/`nombre_completo` (0), que el botón
«+ Contrato» no apareciera para clientes antiguos (aparece: `mi-cartera.tsx:616`
pinta «+ Contrato» justo cuando ya hay contratos) y que hubiera **deadlock** con el
`for share` del alta (no hay ciclo: esta RPC toma un solo lock y termina).

**Pruebas.** Front: 2.082 en verde, **8 mutantes cazados 8/8** (dos sobrevivieron al
primer intento y destaparon código sin probar). Servidor: `scripts/test-domicilio-legal.sql`,
9 casos de comportamiento que **ejecutan** las RPC —el hueco que señalaron dos
auditorías: ninguna sonda las llamaba— dentro de una transacción que termina en
`rollback`.

**Decisión de diseño que conviene no perder:** un fallo de la consulta de pre-vuelo
**NO bloquea el alta**. Solo se frena cuando el servidor DIJO que falta algo; el
servidor sigue siendo la única puerta. Hay un test que lo fija.

### Arnés de la fase 1 (2026-08-19, tras el commit del arreglo)

- **`testDomicilioLegal` en `supabase/scripts/test-rls.mjs`**: 19 sondas + 16
  aserciones de contenido sobre 8 roles. Va **ANTES de `testOffboardingMatrix`**
  a propósito: ese bloque arrastra una avería conocida post-8-ago y puede
  llevarse por delante todo lo posterior (`testAnon` incluido), así que las
  sondas anon del domicilio viven dentro del bloque nuevo.
  Cubre: que el ámbito CRM basta (sin flip a `analista`, a diferencia de la
  sonda bancaria) · que el supervisor del árbol SÍ alcanza y el de otro árbol NO
  · coordinación, directorio y el propio cliente fuera · mismo mensaje para
  «ajeno» que para «inexistente» (sin oráculo de existencia) · los 6 candidatos
  basura, con la comprobación de que ningún rechazo dejó rastro · el normalizador
  fuera de la superficie pública · anon · y P04 (membresía CRM revocada), con
  restauración en `finally`.
  ⚠️ **Deja escrito** el domicilio de `clientBank` y no puede deshacerlo (el
  trigger prohíbe volver a NULL incluso con service_role). Coherente con que el
  gate ya no sea re-ejecutable sobre la misma base; dicho en voz alta en el
  bloque.
  ⚠️ Se aceptó `PGRST202` como rechazo del normalizador, que sería **tautológico**
  con la migración ausente: se ancla exigiendo que la lectura autorizada haya
  respondido antes.
- **`gate:realidad`**: supuesto nuevo `clientes_con_domicilio_legal`. Diverge
  mientras quede un solo cliente activo sin domicilio. Es la instrumentación
  permanente: ese número bajando es la única prueba de que el arreglo llega a la
  gente, no de que se desplegó. Medido el 2026-08-19: **332 de 339**.
- **`test:edge-preflight` pasó de 24 a 30 pruebas**: `_shared/domicilio.test.mjs`
  y `crm-convertir-lead/domicilio-atomico.test.mjs` **existían en el repo y no
  los ejecutaba nadie**. Enganchados y en verde.
- **Censo corregido**: el universo real es **332 clientes activos sin domicilio**,
  no 313. Los 19 de diferencia no tienen contrato todavía — son justo a los que
  se emitiría el PRIMERO y chocarían igual.

### Deuda abierta que esto NO resuelve (decisiones de negocio)

1. **Los contratos viejos sin PDF se pueden emitir con el domicilio de hoy**, fechados
   meses atrás. El domicilio es el de **notificaciones** (cláusula 14.ª), así que se
   fijaría retroactivamente. Los PDF **ya sellados no se tocan** (comprobado).
2. **`LIMA.`, `no tiene`, `PENDIENTE` pasan la validación.** Subir el listón (exigir
   estructura, lista negra de rellenos) es decisión de negocio.
3. **No se registra la PROCEDENCIA** del dato (el sistema ya tiene ese vocabulario en
   `consentimiento_fuente`). Queda quién lo escribió, no de dónde salió.
4. **`crm.leads.distrito` está al 98,5%** y podría pre-rellenar como *sugerencia*.
5. **`no_contactar` vive en `crm.leads`, no en `perfiles`**: para 336 de 338 clientes
   no existe lista «No Insista» antes de una campaña de 313 llamadas.
6. **El mismo muro sigue en tres puertas más**: `contrato-corregir`, «Ver PDF» de un
   contrato viejo, y el panel analista del portal.
7. `datos_legales_contrato_fn` mira al llamante: correcto para el alta, **no** para
   regenerar el PDF de un contrato creado por otra persona.

**Registro de excepciones a `public`:** sin DDL, pero **cambia quién escribe**
`public.perfiles.domicilio` saltándose la RLS del portal (antes solo Gerencia; ahora
toda la cartera CRM). Anotado porque ese registro es el índice donde se busca «quién
le escribe a mis tablas». Deuda adyacente detectada: `20260818014534` **sí** altera
`public.perfiles` (columna + constraint + trigger) y no tiene fila.

## Reporte y reparto de derivaciones de Supervisión (2026-08-20)

| Versión | Nombre | Qué hace | Estado |
|---------|--------|----------|--------|
| 20260820174320 | crm_reporte_derivaciones_equipo_supervisor | Añade dos índices, tres RPC gateadas y dos guardas privadas para que cada supervisor vea, por rango inclusivo en `America/Lima`, cuántos leads y cuánto capital derivó a cada asesor directo; prepare un borrador atómico de hasta 100 leads; y devuelva a su propia bandeja una derivación de hoy mientras el asesor no haya registrado ninguna actividad o tarea. El reporte no expone teléfono, correo, DNI ni notas. El ledger conserva cada apertura/cierre, pero un episodio devuelto como `parqueado` al supervisor de origen deja de pesar en `derivados`, capital y `repartido_hoy`: deshacer debe reducir la carga visible del asesor, no solo mover el lead. Las RPC son `SECURITY DEFINER`, `search_path=''`, revocadas a `PUBLIC`/`anon`/`service_role`, ejecutables por `authenticated` y con gate interno de supervisor activo/equipo directo. Guardado y devolución toman primero el advisory lock compartido de jerarquía y luego bloquean `lead → supervisor → asesor`, evitando deadlock con bajas/traslados. La guarda de `actividades`/`tareas` toma el mismo lock del lead, revalida dueño y sella `creado_en` con `clock_timestamp()` después del lock; la guarda de `leads` impide eludir la devolución con un `PATCH` directo. Oráculos: `supabase/scripts/test-reporte-derivaciones-equipo.sql` (atomicidad, aislamiento, PII, snapshot de capital, hora atrasada, bypass por `PATCH`, arrays no canónicos y contador/capital netos) y, al final de la branch, `test-reporte-derivaciones-concurrencia.mjs` (COMMIT intercalado, orden causal del sello y devolución bloqueada). Postflight, oráculo transaccional y sonda concurrente: ✅ PostgreSQL 17 local tras el ajuste causal. | ✅ Aplicada y registrada en producción el 2026-08-20 después de branch poblada, oráculo, gate RLS de 1.109 aserciones, advisors y sonda concurrente. Verificación directa: 116 migraciones, 3 RPC, 2 guardas, 3 triggers activos, 2 índices válidos, ACL y `search_path` correctos; frontend aislado publicado en Hostinger y verificado por HTTP 200 + SHA-256. La branch temporal fue eliminada. |

## 20260820190500_crm_documento_regimen_por_fecha_de_firma.sql

**Estado: pendiente de aplicar.** Fija el **régimen documental por FECHA DE FIRMA**:
un contrato firmado el **2026-08-19 o después** lleva el PDF que emite el sistema —y
ese PDF *es* el contrato—; uno firmado antes ya tiene el suyo en el formato anterior
y el sistema **no le emite ninguno**, aunque se cargue hoy. Regla de negocio de
Miguel del 2026-08-20.

**Qué estaba pasando (medido en producción, no supuesto).** De los 31 contratos
cargados desde el 18-ago, **26 se firmaron antes del 19** y a **21 de ellos ya se les
había emitido documento nuevo**; el más antiguo, del 17 de febrero. El mecanismo no
era el alta: era el botón **«Ver contrato PDF»** del detalle, que cuando no hay
documento no muestra —**fabrica**—, encadenando front → edge `ensure` →
`crm.contrato_pdf_reservar`. Cualquiera que abriese un contrato viejo acuñaba un
contrato en el formato nuevo, fechado meses atrás y con el domicilio de hoy, que es
el de notificaciones (cláusula 14.ª). Efecto colateral del mismo agujero: como el
documento exige los nueve datos legales, la **carga del histórico** —el 97 % del
trabajo real del equipo: 214 contratos en 30 días, solo 6 firmados del 19-ago en
adelante— chocaba contra un muro que ese contrato no necesita.

**Qué hace.** `private.contrato_documental_regimen(uuid)` como **fuente única** de la
frontera (misma forma que `crm.normalizar_domicilio_legal` en el bloque 1: una sola
puerta, un solo listón), consultada por las **cuatro** funciones que pueden acuñar o
mover un documento: `private.crear_job_contrato_pdf_base` (alta y botón),
`private.crear_revision_contrato_pdf_base` (corrección de contrato y de número),
`crm.contrato_pdf_reclamar` (entrega del turno a la Edge) y
`private.contrato_pdf_estado_base` (lo que ve la pantalla). Los ACL quedan idénticos
a los vivos (`postgres=X/postgres`, y `service_role` además en `reclamar`).

**Lo que NO toca, por decisión de Miguel:** los 21 documentos ya emitidos para
operaciones antiguas **se quedan como están**: sellados, íntegros y descargables. La
migración impide que nazcan más, no borra los que hay. Tampoco muta ni borra ninguna
fila: los dos trabajos huérfanos de producción (contratos `2026-01-000319` y
`2026-01-000602`, firmados en marzo y mayo, en `pendiente` desde el 19-ago con **cero
intentos**) quedan **inertes** —nadie puede reclamarlos— e **invisibles** —el estado
responde `sin_reserva`—, que es la verdad: ese contrato no lleva documento nuevo.

**Orden de despliegue — la Edge va PRIMERO.** `parseEstado` de `crm-contrato-pdf-v2`
exigía `reintentable === true` cuando el estado es `sin_reserva`; devolver `false`
sin actualizarla antes haría que la Edge descartase la respuesta entera (502) y
rompería el detalle de **todo** contrato antiguo. La Edge tolerante viaja en el mismo
commit y se despliega antes. El frontend puede ir después: no depende de claves
nuevas, solo deja de ofrecer un botón.

**Son DOS fechas, y la segunda no sobra.** `fecha_inicio` es el inicio del PLAZO, que
no siempre coincide con la firma: medido en producción, los contratos
`2026-01-000891` y `2026-01-000892` (REATEGUI PEREZ PEDRO IVAN, S/ 170.000 y
S/ 250.000) se **cargaron el 1 de julio** con `fecha_inicio` = **2027-07-01**. Con la
fecha de plazo sola caerían en el régimen nuevo y el sistema ofrecería emitir un
contrato del formato nuevo a dos operaciones firmadas en julio, cuando este documento
ni existía. El suelo `creado_en >= 2026-08-19` (en hora de Lima) lo impide sin
contradecir la regla: una operación registrada **antes** de la frontera no pudo
firmarse en ella o después. Con las dos fechas, producción clasifica **5 nuevos y 410
anteriores** sobre 415 contratos.

**Verificación local.** Oráculo aislado `CONTRATO_PDF_V2_SQL_OK` /
`CONTRATO_PDF_V2_RUNNER_OK` con seis escenarios nuevos que **ejecutan** la regla:
alta del 18-ago sin domicilio (nace el contrato, no nace trabajo), el mismo cliente
firmado el 19-ago (23514: sin domicilio no hay documento y por tanto no hay
contrato), reservar sobre un contrato antiguo (no acuña nada), el huérfano sembrado
tal como está en producción (inerte e invisible, sin perder la fila), el contrato con
el plazo empezando en 2027 pero registrado en julio (régimen anterior, no se le
ofrece nada) y el documento antiguo ya emitido (sigue `sellado` y descargable). **Dos mutantes:** neutralizar la
frontera pone el oráculo en rojo (salida 3, cero marcadores OK), y quitar el suelo de
`creado_en` lo pone rojo en el caso REATEGUI. Front: 2.108/2.108
unitarias, lint y typecheck en verde; Edge: 20/20 pruebas Deno.

**Deuda saldada en el camino.** Este branch **no contenía** los archivos de
`20260818204908` (plantilla v4) ni `20260818233729` (plantilla v5), ambos **vivos en
producción** y presentes solo en `feat/creacion-lead-atomica`: el repo no podía
reproducir producción para toda la cadena del PDF. Se incorporan aquí junto con el
oráculo y el runner que los acompañan. Sigue faltando en este branch
`20260818181756_crm_ingresos_reparto_mes.sql`, también vivo, que pertenece a otra
sesión. Además, el stub `public.contratos` del oráculo declaraba `fecha_inicio`
**opcional** cuando en producción es `NOT NULL`: era más débil que el mundo real y se
ha alineado.

**Registro de excepciones a `public`:** ninguna. No crea, altera ni borra objetos de
`public`; solo lee `public.contratos.fecha_inicio`.

## 20260821222348_portal_asiento_operaciones.sql

**Asiento «Operaciones» del Portal.** Gloria era la única cuenta `admin` del
Portal, y `admin` es un interruptor de todo o nada: las nueve pantallas del panel
pasan por el mismo portero (`verificarAdmin`) y, en la base, por la misma llave
(`public.es_admin`). Su asistente necesita cuatro de esas nueve —Clientes,
Contratos, Pagos y Documentos— y ninguna de las otras cinco.

**El diseño, en una frase: falla CERRADO.** `public.es_admin()` **no se toca**,
así que los ~20 objetos que hoy la usan —y todo objeto futuro que la use— siguen
significando exactamente «admin o superadmin» y niegan el asiento nuevo por
omisión. Lo que se abre se abre uno a uno, por una llave distinta:
`public.es_gestor_cartera()` = `es_admin() OR es_operaciones()`.

Se descartó el camino contrario (meter el rol dentro de `es_admin()` y luego
cerrar a mano lo que sobra) porque es fail-OPEN: el mutante **m2** lo demuestra
—contaminar `es_admin()` abre de golpe **siete** puertas que nadie pidió
(comunicados, borrado de documentos, borrado de cuotas, edición de analistas,
`audit_log`, Actividad y el cockpit del Directorio).

**Qué se abre.** Ocho políticas (`perfiles_select`, `perfiles_update`,
`contratos_select`, `cronograma_select`, `cronograma_admin_actualiza`,
`documentos_select`, `documentos_admin_inserta`, y en `storage` las dos del
bucket `documentos`) y siete funciones (`puede_ver_contrato`, `crear_contrato`,
`actualizar_contrato`, `actualizar_numero_contrato`, `cerrar_contrato`,
`private.puede_gestionar_cuentas_cliente` y `crm.cuentas_pago_contratos_fn`, que
el panel de Pagos consume). Los cuerpos de las siete son **idénticos a los vivos
en producción**: se descargaron, se cambió sólo la llave y se volvieron a
publicar.

**Tres puertas cerradas por decisión de Miguel** (no son omisiones). **Cerrar
ciclo**: `cerrar_contrato` ni aparece en esta migración. **Reasignar asesor**: la
RLS decide por FILA y esto es por COLUMNA, así que el corte vive en el trigger
`proteger_campos_inmutables` (bloque 5 bis) y **levanta una excepción** en vez de
restaurar en silencio —un guardado que dice «listo» sin reasignar es peor que un
error claro—, y solo salta si el asesor de verdad CAMBIA, para no romper el
guardado normal del formulario, que reenvía el mismo valor cada vez.
**Resetear contraseñas**: `resetear-password` sigue en `["admin","superadmin"]`.

**Qué NO se abre, a propósito.** `contratos` INSERT/UPDATE se quedan en
`es_admin()`: las tablas no hacen falta porque la escritura entra por RPC
`SECURITY DEFINER` (y sin `FORCE ROW LEVEL SECURITY`, el definidor —`postgres`—
las salta). Siguen cerradas las tres puertas de borrado, `admin_crea_perfiles`,
las dos de `novedades`, `audit_log_admin_select`, `bandeja_actividad`, las de
`comunicados` en storage e `importar-clientes`.

**Ensayo y mutantes.** `supabase/scripts/run-test-portal-asiento-operaciones.sh
--mutantes` (6 mutantes). El oráculo se aplica **contra el esquema y los datos REALES de
producción** dentro de una transacción que termina siempre en `rollback`: siembra
una identidad efímera, y en tres actos ejerce el asiento nuevo (todas las
aserciones EJECUTADAS, no leídas), comprueba que Gloria no pierde nada y que un
analista no gana nada. Cuatro mutantes lo ponen rojo: cerrar la subida de
documentos, contaminar `es_admin()`, abrir el borrado de documentos, dejar
`actualizar_numero_contrato` en `es_admin()`, **abrir `cerrar_contrato`** al
asiento nuevo y **quitar el corte del asesor** del trigger. **6/6 cazados.**

⚠️ **Trampa reencontrada** (ya documentada en `RETOMAR-53`): en el oráculo,
`text[] || 'literal'` **revienta en runtime** («malformed array literal»). El
oráculo estaba verde porque nunca llegaba a acumular un fallo; en cuanto tenía
algo que reportar, se caía. Se cerró con `array_append`. Sin esa corrección los
mutantes se ponían rojos, sí, pero por la razón equivocada y sin decir cuál.

⚠️ **Segunda trampa, en las Edge:** la `resetear-password` **viva** llevaba una
traducción del rechazo de contraseñas filtradas (HIBP) que **no estaba en el
repo** (`_supabase_functions/`). Editar la copia del repo y desplegar habría
borrado ese arreglo de producción. Se descargaron las tres funciones vivas, se
editaron ésas, y el repo se sincronizó con lo vivo + el cambio (deuda saldada de
paso). Es exactamente la lección de `parche-solo-en-el-artefacto-no-existe`.

**Registro de excepciones a `public`:** **SÍ**. Esta migración vive en el repo del
CRM porque es el único índice de migraciones del proyecto, pero su materia es el
Portal: altera el CHECK `perfiles_rol_check` (añade `'operaciones'`), crea
`public.es_operaciones()` y `public.es_gestor_cartera()`, y modifica las ocho
políticas y siete funciones listadas arriba.

## 20260821223019_crm_eliminar_recuperacion_credenciales.sql

**Credencial exclusiva del CRM = documento.** Retira la última superficie SQL
del flujo anterior de recuperación por correo:
`crm.preparar_recuperacion_usuario_fn(uuid, uuid)`. La Edge `crm-usuarios` v5
crea las identidades nuevas confirmadas con el documento normalizado como clave
exacta y sin iniciar ningún envío de Auth; la pantalla de usuarios ya no ofrece
acción ni modal de recuperación.

Las identidades Portal reutilizadas por el CRM conservan su contraseña. La
reconciliación productiva, protegida por marca de servidor, allowlist auditada y
conteo exacto, actualizó una sola identidad heredada exclusiva del CRM; cuatro
perfiles comerciales sin esa procedencia no se tocaron.

**Despliegue y verificación:** ✅ aplicada en producción el 2026-08-21; RPC
ausente, Edge v5 activa con `verify_jwt=true`, CORS del subdominio CRM en 204 y
POST sin JWT en 401. Build Hostinger `build-20260821T222650651Z`, con
`index.html` y módulo de usuarios idénticos byte por byte al artefacto aprobado.

**Registro de excepciones a `public`:** ninguna. No modifica `public`, el Portal
ni la configuración global de Supabase Auth.

## 20260821233241_crm_alta_vendedor_completa_gerencia.sql

**Causa corregida.** El alta anterior creaba Auth y `public.perfiles`, pero
dejaba al vendedor sin `crm.equipo`. Por eso Gerencia veía «Pendiente de rol»,
no podía seleccionar Supervisor y, después de autenticar correctamente,
`crm.mi_acceso_fn()` cerraba el acceso como `no_enrolado`.

**Nueva frontera atómica.** `crm.registrar_vendedor_usuario_fn(...)` permite a
Gerencia completar exclusivamente un Vendedor CRM con rol fijo `vendedor`,
Supervisor activo obligatorio y membresía activa en una sola transacción. No
acepta promociones ni un rol suministrado por el cliente; Superadmin conserva
el gobierno de los demás roles. Revalida autoridad después del candado global,
protege la idempotencia completa, exige coincidencia documental para candidatos
existentes y falla si perfil o Auth dejaron de estar vigentes.

**Frontera Portal.** Solo opera cuando coinciden el perfil `comercial` y la
marca servidor `app_metadata.origen_app = 'crm'`. Una identidad compartida con
el Portal devuelve `candidato_existente` sin cambios. No modifica código,
credenciales, rutas, funciones ni configuración Auth del Portal.

**Despliegue y verificación:** ✅ aplicada en producción el 2026-08-21. Edge
`crm-usuarios` v6 activa con `verify_jwt=true`; preflight CORS 204 y POST sin JWT
401. Frontend Hostinger `build-20260821T233409404Z`, con estado **Alta
pendiente**, selección de Supervisor, acción **Completar alta**, reintento del
catálogo y documento inmutable después de crear la identidad. Verificación:
2.129/2.129 pruebas web, 20/20 pruebas Edge del gate, lint, typecheck, build,
artefacto SHA-256 verificado y oráculo PostgreSQL
`USUARIOS_JERARQUIA_TX_OK` con el caso de candidato CRM existente.

**Registro de excepciones a `public`:** crea perfiles `comercial` únicamente
para identidades nuevas marcadas por el servidor como exclusivas del CRM, igual
que el flujo anterior. No altera objetos ni comportamiento del Portal.

## 20260824170630_crm_periodo_comercial_contratos.sql

**Regla comercial corregida.** El mes de un contrato ya no lo decide la fecha
en que la fila llegó al CRM. `public.contratos.fecha_cierre_comercial` es el
dato canónico para capital y cantidad de contratos; `creado_en` conserva la
verdad técnica del registro y `fecha_inicio` conserva el inicio del plazo. El
histórico se inicializó con la mejor evidencia disponible del sistema nuevo:
`least(fecha_inicio, día de registro en Lima)`, marcado siempre como
`migracion_inferida`. En producción 142 contratos cambiaron de mes con esta
regla y cero filas quedaron inconsistentes.

**Altas y correcciones.** Un alta no puede suministrar la fecha comercial: el
trigger la calcula como fecha de inicio cuando la carga llegó tarde o como día
de registro en los demás casos. Una modificación directa se rechaza. Solo
Gerencia puede corregirla mediante
`crm.corregir_fecha_cierre_comercial(uuid,date,text)`, con motivo obligatorio,
auditoría antes/después y rechazo de fechas futuras. Altas y correcciones toman
el mismo candado mensual de `crm.cerrar_periodo` y no pueden escribir un mes ya
sellado. La migración toma además el candado global antes del preflight para que
no pueda competir con un cierre en curso.

**Una sola lectura mensual.** `private.produccion_mes_por_vendedor`,
`crm.metricas_capital_mes_fn`, las ventanas de contratos de
`private.metricas_conversiones_implementacion` y `public.metricas_directorio`
consumen la nueva fecha. La cohorte de leads, la causalidad de anulaciones, los
cierres externos, el cronograma, el PDF y el ciclo contractual conservan sus
relojes anteriores. `crm.contratos_por_periodo_comercial_fn(date)` permite a
Gerencia/Directorio obtener lista y totales de cualquier mes incluso sin metas;
julio de 2026, que tiene cero `crm.meta_periodos`, devuelve correctamente 182
contratos por S/ 5,042,473.72 y US$ 390,400.

**Despliegue y verificación:** ✅ aplicada directamente en producción con OK
explícito de Miguel el 2026-08-24; versión local `20260824170630`, versión
registrada `20260824174020`. Antes de aplicar, la migración completa y el gate
se ejecutaron contra el esquema real dentro de una transacción revertida. Ya
desplegada, `test-periodo-comercial-contratos.sql` devolvió
`PERIODO_COMERCIAL_CONTRATOS_OK`: prueba límites entre meses, mes sin metas,
alta tardía, permisos, corrección auditada, fechas/motivos inválidos, escritura
directa prohibida, insert/corrección contra mes sellado y ejecuta los cuatro
consumidores recompilados. Advisors: cero `ERROR`; seguridad pasó de 157 a 159
avisos por las dos RPC `SECURITY DEFINER` expuestas a `authenticated`, ambas con
gate interno probado y `anon` revocado; rendimiento pasó de 49 a 48 avisos, sin
hallazgo propio. SHA-256 aplicado:
`9e4875d4ed12a67e2c4cce7b10be01bbf6a0a04cc04c5061cf0d9d1187b21a5c`.

Durante la ventana de despliegue el total vivo pasó de 439 a 438 por una
eliminación ordinaria, registrada por `audit_log` a las 17:38:28 UTC: un
contrato USD 20,000. La migración no contiene borrados y las cifras finales ya
reflejan esa operación concurrente. El gate histórico de metas no se contó como
prueba aprobada: se detuvo antes del código afectado porque su fixture espera un
roster distinto del roster productivo actual (19 esperados por el servidor, 20
enviados por el fixture).

## 20260824231133_crm_gestion_clientes_renovaciones_conversion.sql

**Mi cartera se vuelve operativa.** Crea el ledger inmutable
`crm.operaciones_cartera` para renovaciones y upgrades, acreditado al dueño de
cartera en el instante de la operación. Renovar exige que el contrato haya
llegado a su fecha fin, crea otro contrato dentro de la misma transacción,
enlaza y cierra el anterior, y traslada sus cuotas pendientes. El capital queda
separado en `capital_renovado` y `capital_adicional`; el adicional es una cifra
económica para pago distinto y nunca agrega otra conversión.

**Conversión sin inflar el divisor.** Cada cliente aporta como máximo una
conversión por mes aunque renueve varios contratos o combine renovación y
upgrade. Toda renovación es elegible; el upgrade solo lo es después del mes de
su primer contrato. La operación se suma exclusivamente al numerador de
`private.conversion_mensual_por_vendedor`; el divisor conserva como única fuente
los leads no referidos recibidos desde `crm.lead_asignaciones`.

**Postventa.** `crm.tareas` acepta como sujeto exactamente un `lead_id` o un
`perfil_id`. Las tareas de cliente heredan el asesor de su cartera y viajan con
ella al reasignarse. `crm.cerrar_tarea` registra el resultado en el nuevo
timeline `crm.actividades_cliente`, separado de etapas y SLA de leads, y puede
crear la siguiente acción conservando el mismo cliente.

**Histórico y seguridad.** Agosto de 2026 se reconstruyó sin inventar cifras:
48 operaciones (9 renovaciones y 39 upgrades), 29 clientes elegibles y 9
renovaciones históricas con desglose marcado como pendiente; su adicional
histórico permanece nulo/0. Ambos ledger tienen RLS, solo lectura directa para
`authenticated`, cero escritura directa y mutaciones encapsuladas en RPC con
gate interno.

**Despliegue y verificación:** ✅ aplicada y registrada en producción el
2026-08-24. La migración completa pasó dos ejecuciones transaccionales con
`ROLLBACK` antes de aplicarse. El gate
`test-gestion-clientes-renovaciones.sql` devolvió
`GESTION_CLIENTES_RENOVACIONES_OK`: comprueba cierre/enlace, suma económica por
moneda, upgrade por mes inicial, deduplicación cliente/mes, divisor inalterado,
ledger append-only y el flujo tarea → actividad de cliente → siguiente tarea sin
escribir en `crm.actividades`.

**Registro de excepciones a `public`:** reemplaza `public.crear_contrato` para
mantener la creación contractual como una sola transacción y añade el enlace de
renovación a `public.contratos`; no cambia Auth ni las superficies del Portal.

## 20260824233619_crm_cumplimiento_cartera_compatible.sql

**Compatibilidad de despliegue escalonado.** El bundle productivo validaba
`crm.cumplimiento_metas_fn` con un objeto estricto. Mantiene la conversión de
cartera dentro de los campos existentes (`convertidos`, numerador y porcentaje)
pero retira temporalmente la rama descriptiva adicional `cartera` de esa RPC.
El desglose completo sigue disponible desde `crm.operaciones_cartera` y
`crm.metricas_cartera_fn`; así el numerador nuevo llega sin romper la pantalla
vigente.

**Despliegue y verificación:** ✅ aplicada y registrada en producción el
2026-08-24 después de detectar la incompatibilidad durante la verificación del
contrato TypeScript. Su dry-run transaccional y el gate integral de gestión de
clientes pasaron completos.

**Registro de excepciones a `public`:** ninguna. Solo reemplaza una RPC del
esquema `crm`.

## 20260823204930_crm_alertas_reconocimientos.sql

**Estado: ✅ EN PRODUCCIÓN (2026-08-23, ~17:30 Lima).** Ciclo completo en el
branch `hoy-sin-ruido-f4` (ref `xoyeqftdfxmshjqswdey`, borrado tras el
veredicto): replay automático muerto en el MIGRATIONS_FAILED de diseño →
`reset_branch` a 20260811210049 → semilla intercalada (perfiles 'analista',
cadena sup→vend) → replay 087–123 DESDE EL REGISTRO remoto (37/37; los 3
asientos sin cuerpo salieron de los `.sql` locales del domicilio legal y del
régimen documental — que SÍ está vivo en prod, la nota del 20/08 quedó vieja)
→ **huella global 271 funciones md5 IDÉNTICA a prod** → F4 aplicada (+3
funciones exactas) → seed demo + bajas → gate **404✓ con el ÚNICO ✗ = el
fatal documentado del arnés** (offboarding post-8-ago; primera corrida cazó
además un bug de la PROPIA sonda de audit: `tabla` va calificada con esquema)
→ advisors del branch 156/0 ERROR (única diferencia con prod:
`extension_in_public`, infra de branch). Trampa nueva del ciclo: un branch
nace SIN `crm` en los esquemas expuestos de PostgREST — copiar la config API
de prod (Management API `PATCH /postgrest`) antes del seed. Aplicación a
prod por `merge_branch` con el cuerpo AL BYTE en el registro del branch
(md5 `6c1c10ab…` = fichero; sin eso el merge habría registrado sin ejecutar)
y verificada CONTANDO objetos: tabla + 3 triggers + 2 policies + 3 índices +
job de cron con EXECUTE, funciones **271→274 (+3 exactas)**, registro 124,
huella `399cd9ff…` = banco al byte. Advisors de prod post-merge: **157 =
línea base exacta, cero clases nuevas, 0 de F4**.

**F4.1 del plan «Hoy del supervisor, sin ruido»** (decisiones de Miguel
2026-08-23: reconocida = atenuada · posponer con fecha y tope 7 días ·
gerencia lee). Crea `crm.alertas_reconocimientos`, el libro INMUTABLE (solo
INSERT: sin policy ni grant de UPDATE/DELETE) donde el supervisor reconoce o
pospone las alertas agrupadas de su campana. Guarda la FOTO de miembros del
grupo — la base del «reaparece si empeora» que calcula el front — y la
severidad reconocida. Trigger sellador: autoría = actor, `alerta_id` atado al
uuid del actor (nadie reconoce alertas ajenas), posponer futuro con tope de
7 días a reloj de pared, miembros sin nulls ni ids venenosos, `creado_en`
del servidor. RLS: escribe solo el supervisor dueño; lee el dueño y gerencia
(trazabilidad); vendedor y directorio, nada. Caducidad pg_cron a 90 días
(la traza permanente queda en `public.audit_log` vía `private.log_audit_crm`).
Matriz `test-rls.mjs`: bloque «F4 sin ruido» con 28 casos (positivos y
denegados por rol —coordinador incluido—, predicado owner con OTRO supervisor,
inmutabilidad del propio dueño, re-sellado de creado_en, topes y venenos).
Auditoría `auditor-rls` aplicada ANTES del branch: 4 importantes (huecos de
matriz) + 6 menores (sello con clock_timestamp, guardia de inmutabilidad
BEFORE UPDATE/DELETE, rol también en el sellador, limitación de la foto
documentada en el COMMENT).

**Auditoría Codex (refutación) aplicada ANTES del branch:** 1 bloqueante —
la foto/severidad son falsificables por su dueño vía API — resuelto por
ESTRUCTURA: ningún reconocimiento vige más de 7 días (contrato de F4.2,
sellado por el creado_en del servidor; documentado en el COMMENT de la
tabla). Además: `array_ndims=1` (una foto 2D pasaba cardinality y unnest),
`secuencia` identity como ORDEN TOTAL del libro (creado_en empata al
microsegundo), `collate "C"` en los regex con rangos, vuelta atrás con
unschedule condicional, y la matriz endurecida (helper estricto con código
Y mensaje, positivo del 4.º tipo, sonda de audit_log, foto 2D, catálogos
de accion/severidad). Matriz F4: 36 casos. NO observables y DICHOS: la
caducidad de 90 días y la guardia de inmutabilidad ante el owner.

**Contratos que hereda F4.2 (front):** `AlertaCRM` debe exponer `miembros`
(hoy los grupos descartan los ids — hallazgo Codex #4) · un reconocimiento
vige ≤7 días por `creado_en` · «el último asiento manda» se lee por
`secuencia`, no por `creado_en`.

**Verificación post-merge obligatoria:** `cron.job` tiene UNA fila
`crm-alertas-reconocimientos-caducidad` y su `username` tiene EXECUTE sobre
`private.caducar_alertas_reconocimientos()` — el segfault por EXECUTE
ausente está documentado en esta misma imagen de Supabase
([[postgres-cae-por-permiso-de-funcion]]).

**Registro de excepciones a `public`:** solo la FK de lectura a
`public.perfiles` (patrón de la casa); ningún objeto del portal se altera.

## 20260824034730_crm_alertas_reconocimientos_vigentes.sql

**Qué hace:** F4.2 «Hoy del supervisor, sin ruido» — (1) vista
`crm.alertas_reconocimientos_vigentes` (`security_invoker = true`) que corta
la VIGENCIA del libro con el reloj de POSTGRES (≤7 días por `creado_en`;
posposiciones con `hasta > now()`): el front lee SOLO esta vista, cerrando el
bloqueante Codex F4.2 #2 (un dispositivo con el reloj atrasado podía alargar
un silencio — la clase de fallo de «una prueba de fechas en tu propia zona»);
(2) `UNIQUE (secuencia)` sobre `crm.alertas_reconocimientos` — «el último
asiento manda» se resuelve por secuencia y el UNIQUE cierra la vía anómala
(restauración/doble carga) de empates con ganador arbitrario (Codex #6).

**Estado:** ✅ **EN PRODUCCIÓN** (2026-08-24, madrugada). Ciclo completo del
banco `f42-vigentes` (ref `ggkpqmdvtybeinwulfvk`, borrado al cerrar): replay
38/38 desde el registro remoto verificado por md5 · gate 413 marcas con TODOS
los casos F4/F4.2 en verde (29 del libro + 14 nuevos de la vista, incluida la
prueba TEMPORAL: una posposición de 8 s nace visible y la vista la suelta con
el reloj del servidor mientras la tabla la conserva) · advisors del banco 0
sobre estos objetos · merge verificado CONTANDO objetos en prod: vista con
`reloptions = {security_invoker=true}` y viewdef exacto, constraint presente,
registro 125 (fila `20260824034730` con 7 statements, md5
`3fca26e8c4e4fd0fbe16fa47e7767936`), grants de la vista = SELECT a
authenticated y NADA a anon, funciones 274 SIN cambios y huella filtrada
`264|f583b7c5…` intacta, cron de caducidad 1 fila · advisors de prod
post-merge **157 = línea base exacta**, 0 sobre la vista.

⚠️ **Trampa nueva del merge (cazada en este ciclo):** el PRIMER merge falló
(main → MIGRATIONS_FAILED, prod intacto — verificado antes de reintentar)
porque la fila del registro llevaba el fichero entero como UN solo elemento
de `statements`; el ejecutor del merge corre elemento a elemento por
protocolo extendido y no acepta multi-statement. La fila debe ir con los
statements PARTIDOS (uno por sentencia, respetando `$$` y comillas; el
bloque comentado de vuelta atrás del final no va al registro). Con la fila
partida en 7, el segundo merge ejecutó y registró bien.

**Fallos del gate AJENOS a esta migración (dichos):** los 23 ✗ de la sección
domicilio legal — esperan funciones que en prod viven FUERA del registro (la
deriva de arriba), imposibles en un banco fiel al registro — y el fatal
documentado del arnés (offboarding post-8-ago).

**Auditoría (auditor-rls, 0 bloqueantes):** #2 aplicado — ⚠️ REGLA: todo
`CREATE OR REPLACE` de una vista invoker DEBE repetir `WITH (security_invoker
= true)`; en PG17 el replace SUSTITUYE las reloptions y sin el WITH la vista
se vuelve definer EN SILENCIO (quedó en el COMMENT de la vista). #3/#4/#5
aplicados a la matriz: denegados de directorio y anon sobre la vista, y DML
a través de la vista (auto-actualizable para Postgres) pinneado como
bloqueado. #6 dicho: el `ADD CONSTRAINT` no puede chocar con datos de prod —
la identity es `GENERATED ALWAYS`, PostgREST no puede mandar `secuencia` y
`OVERRIDING SYSTEM VALUE` no viaja por la API.

**NO observables y DICHOS:** el corte de 7 días de la vista (nadie fabrica un
`creado_en` viejo — lo sella el trigger de F4.1) y el empate de `secuencia`
(inalcanzable por la vía normal); ambos cerrados por estructura. La matriz sí
prueba el corte de `hasta` EN EL TIEMPO: una posposición de 8 segundos nace
visible en la vista, y pasada su fecha la vista la suelta mientras la tabla
la conserva — reloj del servidor, no del que consulta.

**⚠️ Deriva de prod FUERA del registro (hallazgo del ciclo):** al montar el
banco (replay 38/38 desde el registro remoto, registro 124), la huella global
dio 270 funciones en el banco contra 274 en prod. Diferencia identificada
función a función: 10 funciones del dominio **domicilio legal** y
**contrato-pdf** (4 que solo existen en prod: `completar_domicilio_cliente`,
`datos_legales_contrato_fn`, `normalizar_domicilio_legal`,
`contrato_documental_regimen`; 6 con hash distinto:
`actualizar_cliente_gerencia_con_domicilio`, `contrato_pdf_reclamar`,
`convertir_lead_con_domicilio`, `contrato_pdf_estado_base`,
`crear_job_contrato_pdf_base`, `crear_revision_contrato_pdf_base`) — trabajo
de las sesiones de domicilio legal / PDF aplicado a prod SIN fila en el
registro. **Excluyendo esas 10, banco y prod son idénticos al byte: 264|`f583b7c578a5bb3ebb0824d6be13f35d`
en ambos.** Esta migración no toca ese dominio; la deuda de registrar esas
funciones queda anotada y NO se «arregla» desde este ciclo (sería pisar
trabajo ajeno a ciegas — la lección de [[sesiones-paralelas-deploy]]).

**Verificación post-merge obligatoria:** contar objetos (vista + constraint),
`pg_class.reloptions` de la vista contiene `security_invoker=true`, registro
de prod 125 con md5 `281ac2ea…` en la fila nueva, funciones 274 SIN cambios
(esta migración no crea ni altera funciones) y huella filtrada
`264|f583b7c5…` intacta.

**Registro de excepciones a `public`:** ninguna — ningún statement toca
`public.*`.

## 20260825005519_crm_cerrar_reunion_cliente_clasificada.sql

**Estado: ✅ aplicada y registrada en producción el 2026-08-25.** Sustituye la
firma inicial de `crm.cerrar_tarea` por una compatible con los cinco argumentos
anteriores y
dos argumentos opcionales: `p_resultado_reunion` y
`p_motivo_no_realizada`. Así una reunión de cliente conserva su resultado y
una cancelación conserva su motivo real, sin perder el timeline postventa ni
la siguiente acción atómica.

La validación replica el contrato de `crm.cerrar_reunion`: una reunión
completada exige resultado; un no-show se sella como `cliente_no_asistio`; una
cancelación exige motivo y, para `otro`, detalle. Las tareas que no son reunión
rechazan esos campos. No crea tablas ni modifica datos históricos.

**Estado productivo comprobado el 2026-08-25 (solo lectura):** las tres versiones
`20260824231133`, `20260824233619` y `20260825005519` figuran en el historial
remoto. El esquema productivo expone únicamente la firma nueva de siete
argumentos, con cinco valores por defecto, `SECURITY DEFINER`,
`search_path = ''`, `PUBLIC` revocado y ejecución para `authenticated` y
`service_role`.

**Verificación previa sin tocar producción:** se extrajo únicamente el esquema
productivo (`auth`, `public`, `crm`, `private`) a una base local desechable, sin
datos ni PII. Sobre esa copia exacta la migración pasó; luego el gate integral,
con fixture sintético de 48 operaciones/29 clientes, devolvió
`GESTION_CLIENTES_RENOVACIONES_OK`. El gate incluye atomicidad, RLS/permisos,
PEN y USD separados, deduplicación cliente/mes, tarea → actividad → siguiente
tarea y reasignación de cartera sin perder pendientes ni reescribir historia.

**Reversión verificada:** `scripts/rollback-crm-cerrar-reunion-clasificada.sql`
restaura la firma de cinco argumentos, conserva los registros ya creados y
valida preflight, permisos y postflight. Se ejecutó correctamente sobre la copia
desechable y, a continuación, la migración se volvió a aplicar y el gate
integral volvió a pasar.

**Registro de excepciones a `public`:** ninguna. Solo reemplaza una RPC del
esquema `crm`.

---

## 20260826154500 · `crm_leads_telefono_alternativo_fijos_e_internacional`

✅ **EN PROD 2026-08-26.** Aplicada con `supabase db query --linked --file` y
registrada a mano (OK explícito de Miguel; `db push` sigue prohibido aquí).

Relaja el CHECK `leads_telefono_alternativo_formato`, que solo aceptaba celular
peruano, a **celular peruano · fijo peruano · E.164 de cualquier país**:

```
^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})$
```

⚠️ **El `(?!51)` no es adorno.** Sin él, el tramo internacional se traga
cualquier cosa que empiece por 51 con largo plausible: `+51123456789` entraría
como «internacional válido» y nadie podría llamarlo jamás. Todo lo que dice ser
peruano se juzga con la vara peruana o no entra. Postgres soporta lookahead en
su sintaxis ARE, y el postflight lo comprueba **ejecutándolo**.

⚠️ **El fijo peruano tiene OCHO dígitos nacionales**, se reparta como se reparta
entre zona y abonado: Lima es `1`+siete y las provincias `84`+seis. Escribirlo
como «siete para Lima, seis para provincias» deja fuera a medio país — error
real, cazado por una prueba antes de aplicar.

**Postflight sin tocar `crm.leads`.** Un CHECK se lee bien y rechaza mal, así que
se le meten filas — pero a una tabla TEMPORAL creada con `like crm.leads
including constraints including defaults`, que hereda el CHECK real del catálogo
y ningún trigger. Insertar en `crm.leads` habría disparado la auditoría, y
borrar después exige bajar los siete candados nombrados. 20 casos ejecutados.
Un guardia extra comprueba que la copia **heredó** el CHECK: sin él, si
`including constraints` fallara, todos los casos entrarían y el postflight
cantaría verde sin haber probado nada.

**Mutantes (4/4 muertos):** sin lookahead · fijo de 7 dígitos · tope de E.164
roto · la tabla de prueba sin heredar el CHECK.

**No toca `telefono`**, que no tiene CHECK en esta tabla: quién entra lo decide
la capa de aplicación y `private.trg_leads_normalizar_telefono` ya canoniza.

**Registro de excepciones a `public`:** ninguna.

---

## 20260826151907 · `crm_cartera_pagina_telefono_alternativo`

✅ **EN PROD 2026-08-26.** Misma vía y mismo OK.

`crm.cartera_pagina_fn` nunca devolvió `telefono_alternativo`, así que el
buscador de la cartera no podía encontrar un lead por su segundo número: el
vendedor que recibe una llamada del alternativo lo escribe y el CRM le responde
que ese lead no existe. Se añade al `returns table`, al `select` y al tramo de
dígitos del buscador.

Es `drop` + `create` y no `create or replace` porque Postgres no deja cambiar el
tipo de retorno; por eso el grant se vuelve a poner explícitamente. **Preflight
anclado al md5 del cuerpo vivo** (`e52ed18e…`): si alguien tocó la función por
otro lado, este `drop` se lo llevaría por delante en silencio.

**Mutantes (6/6 muertos):** columna declarada pero no seleccionada · buscador
ciego al 2.º número · colada como `SECURITY DEFINER` · abierta a `anon` · ámbito
anulado con `or true` · ventana de convertidos perdida.

⚠️ **Un mutante encontró un guardia flojo, no un fallo del código.** El
postflight comprobaba que apareciera la palabra `vendedor_ids_visibles`, que
sobrevive en la asignación de `v_visibles` aunque el `where` se sustituya por un
`true`. No era fuga —la función es INVOKER y manda `leads_select`—, pero el
guardia prometía más de lo que comprobaba: ahora ancla el predicado entero.

**Registro de excepciones a `public`:** ninguna.

---

## 20260826173523 · `crm_leads_telefono_alternativo_crudo`

✅ **EN PROD 2026-08-26.** Fase 4 de «Los dos números del lead».

Añade `crm.leads.telefono_alternativo_crudo`: el segundo número **tal como lo
escribió la persona**, cuando no se pudo entender como teléfono. Decisión de
Miguel: «que siempre todos los leads tengan ese número alternativo, así ese
número sea errado».

**El diagnóstico del origen (26/08) midió por qué esto vale poco y a la vez
importa:** de 14.310 filas, el **84,2 % repite el mismo número** en las dos
columnas, el 10,5 % trae un segundo celular distinto (que ya llegaba), y solo el
**2,1 % (299 filas)** trae algo escrito que no es un teléfono. Eso es lo que
rescata esta columna. Lo que de verdad quería Miguel —que todos tengan dos
números— **no es alcanzable**: en 12.043 filas no hay segundo número que dar.

**Dos CHECK.** Cordura (ni vacío ni solo espacios —«no hay dato» se escribe
NULL, y dos formas de decir lo mismo obligan a la ficha a comprobar las dos—,
máximo 40 caracteres) y **excluyencia** con `telefono_alternativo`: si el número
se pudo canonizar vive allí y este queda null. Sin esa regla la ficha tendría que
elegir cuál de los dos pinta.

**Postflight sobre tabla TEMPORAL** con `like … including constraints including
defaults` (misma técnica que 20260826154500: `crm.leads` tiene auditoría y
borrar exige bajar los siete candados). 9 combinaciones ejecutadas + un guardia
que verifica que la copia heredó **los dos** CHECK.

**Mutantes (4/4 muertos):** columnas dejan de ser excluyentes · se acepta cadena
vacía · se cae el tope de cordura · la copia no hereda los CHECK.

**Registro de excepciones a `public`:** ninguna.

---

## 20260826174500 · `crm_cartera_pagina_telefono_alternativo_crudo`

✅ **EN PROD 2026-08-26.**

`crm.cartera_pagina_fn` devuelve también `telefono_alternativo_crudo`. La ficha
del lead se sirve del **store** (`listarLeadsDelAmbito`, que consulta la tabla
directo), así que funcionaría igual sin esto — **y precisamente por eso se hace**:
dos caminos que producen un `Lead` con forma distinta es como se pierde un dato
sin que nadie lo vea, que es la lección entera de este ciclo.

El fichero se **genera a partir de 20260826151907** con dos líneas más, para que
el resto del cuerpo no pueda divergir. Preflight anclado al md5 vivo
(`6ce36d25…`, el que dejó la migración de la mañana). Postflight: además de todo
lo de la anterior, comprueba que el crudo se declara **y** se selecciona.

**Registro de excepciones a `public`:** ninguna.

---

## 20260826182000 · `crm_canonizar_contacto`

✅ **EN PROD 2026-08-28** (escrita el 26, aplicada el 28). Local antes de subir:
19 casos ejecutados, 6 mutantes muertos.

`private.canonizar_contacto(text)` → `(e164, clase, movil)`. Es el **sexto
espejo** de la regla del teléfono y el primero que vive en la base como función
con nombre propio, para que 20260826182500 la **llame** en vez de reescribir el
criterio dentro de una función de 200 líneas — que es como los espejos empiezan
a divergir.

⚠️ **NO sustituye a `private.normalizar_telefono`**, que sigue intacta y la
siguen usando el trigger de `crm.leads` y todo el CRM. Aquella responde «cómo se
guarda este número»; esta responde «es esto un teléfono, y de qué tipo». Tocar la
otra movería la huella con la que el CRM decide que dos leads son el mismo.

⚠️ **Un mutante enseñó que una prueba mía era vacua:** ensanchar E.164 a 6..20
no lo cazaba nadie, porque mi caso de «pasado del máximo» venía **sin `+`** y se
rechazaba antes, por «no hay país que suponer». Los límites de E.164 hay que
probarlos con `+`. Se añadieron las cuatro fronteras reales.

## 20260826182500 · `crm_crear_lead_telefono_alternativo`

✅ **EN PROD 2026-08-28** (escrita el 26, aplicada el 28). **Opción A**, elegida
por Miguel: el primer número IDENTIFICA al lead y sigue siendo celular peruano; el
segundo solo lo contacta y admite celular, fijo peruano o cualquier país.

Añade `p_telefono_alternativo` (al final, DEFAULT NULL) a
`crm.crear_lead_si_disponible`. Es `drop` + `create`: añadir un parámetro crea
una **sobrecarga**, no un reemplazo, y dos funciones con el mismo nombre harían
ambigua cada llamada — el postflight comprueba que quede **exactamente una**.

**El cuerpo se verificó por HUELLA, no por lectura.** Se reconstruyó, se le
quitaron las adiciones intencionadas y el `md5` resultante coincidió con el de
producción (`3c06a68d…`): prueba de que no se reescribió nada sin querer. El
laboratorio local instaló la función VIEJA con el prosrc vivo real y la huella
coincidió también, así que el ancla del preflight morderá de verdad.

**Ejecutada con 9 casos:** segundo celular · fijo · extranjero · repetido (no se
duplica) · sin segundo · ilegible (rechazado con 22023: lo que se teclea a mano
se corrige, no se guarda a medias) · principal fijo (rechazado — opción A) ·
idempotencia con mismo payload · **mismo id con el 2.º número distinto**, que
avisa en vez de confirmar en falso perdiendo el dato nuevo.

⚠️ **Asimetría consciente:** por la vía automática un lead SÍ puede entrar con un
fijo de identidad (allí la alternativa era perder el lead). Tecleando a mano se
exige celular. Un cliente de oficina que solo deje un fijo no se podrá registrar;
Miguel lo asumió. La opción B (alinear también el principal) queda descrita en el
vault para cuando haya un caso real que la justifique.

**Registro de excepciones a `public`:** ninguna en las dos.

## 20260826211500 · `crm_f0_anclar_metricas_conversiones`

✅ **APLICADA EN PROD** (2026-08-26 ~22:45 UTC, canal directo, orden «haz la
F0» de Miguel). Verificación en vivo: md5 intacto `906afdec…`, DEFINER `t`,
registrada en `schema_migrations`. Advisors tras aplicar: 0 ERROR (134 WARN
preexistentes). F0 del plan
[[Conversion unica en todo el CRM - plan de migraciones]] (D5 decidida por
Miguel; orden «haz la F0» del 26/08).

Ancla en el repo el texto VIVO de
`private.metricas_conversiones_implementacion(p_desde date, p_hasta date)`:
la `20260824170630` lo produjo con `replace()` dinámico sobre
`pg_get_functiondef` y el resultado no existía en ningún fichero (lección del
19/08: un parche que solo vive fuera del repo no existe). **Cero cambio
funcional**: preflight md5 `906afdec2bfbd1abcf3931093f09539f` → `CREATE OR
REPLACE` con el texto capturado byte a byte → postflight con el mismo md5.

Trazabilidad verificada dos veces (sesión y auditor, por hash): deshacer los
dos `replace()` del parche sobre este texto reproduce el ancla pre-parche
`561f3a43fd4895eac28f4dbbfb0b5095` — lo vivo = historia del repo + parche
conocido, sin deriva. Banco local (PG16, base desechable): siembra del vivo da
el MISMO md5 que prod; la migración aplica sin mover la huella; el mutante
(función distinta) aborta en preflight dejando todo intacto.

Auditor RLS: APROBADA. `CREATE OR REPLACE` preserva ACL y owner (la función
sigue revocada a `public,anon,authenticated,service_role` por
`20260807203757:1833`). ⚠️ Hacia adelante: NUNCA convertir este patrón en
`DROP`+`CREATE` — re-crearía la ACL con `EXECUTE` a `PUBLIC`. Deuda preexistente
dicha: `test-rls.mjs` sigue sin un caso para `crm.metricas_conversiones_fn`
(la admite la fila `20260810024404`). Excepciones a `public`: ninguna.

Codex (revisión adversarial, 5 ángulos): 2 refutaciones condicionales CERRADAS
antes de aplicar — (1) shadowing de `md5` por `search_path` → cualificado
`pg_catalog.md5(...)` en pre y postflight (banco re-ensayado verde); (2) posible
dependencia `DEPENDS ON EXTENSION` que `CREATE OR REPLACE` perdería → verificado
en prod `pg_depend`: solo dependencias `n` (esquema y lenguaje), cero `x`.
1 residual documentado: carrera TOCTOU de milisegundos entre preflight y CREATE
bajo READ COMMITTED (un DDL concurrente sobre ESTA función en esa ventana se
sobrescribiría sin alarma); la cubre la verificación en vivo post-aplicación del
guion. No refutado: visibilidad de catálogo en la misma transacción y atomicidad
del canal Management API (un solo mensaje Simple Query = transacción implícita).

Aplicación: `scripts/aplicar-f0-anclar-conversiones-prod.sh` (canal directo;
el merge de branches sigue roto). Vuelta atrás: no aplica — preflight/postflight
fallido = transacción revertida; éxito = objeto byte-idéntico al previo.

## 20260826233000 · `crm_f1_conversion_episodios`

✅ **APLICADA EN PROD** (2026-08-27 ~01:20 UTC; el clasificador de permisos
bloqueó el guion, se aplicó por el MCP oficial de Supabase con el MISMO
contenido — fidelidad probada: functiondefs vivos byte-idénticos a los del
fichero, y md5 del registro en `schema_migrations` = md5 del fichero local
`0f070a81…`). Candados de datos verdes (0 empates de `asignado_en`; PK y
NOT NULL de cartera). **PARIDAD EN PROD IDÉNTICA**: foto del núcleo (mes
actual f=0.15 y f=1.0, mes anterior) byte a byte igual antes y después.
Vigía v1: 4 funciones consume_nucleo, 4 motores conocidos en lista blanca
(F2), Distribución no menciona 'conversion' en su fuente → el detector por
CLAVES DE PAYLOAD queda para F2; resto = menciones en wrappers/triggers/
acciones, no motores. Advisors tras aplicar: 0 ERROR (134 WARN preexistentes).
F1 del plan
[[Conversion unica en todo el CRM - plan de migraciones]] (orden «desarrolla la
fase 1»; decisiones D1–D7 resueltas por Miguel el mismo día).

Nace **`private.conversion_episodios(p_ini, p_fin, p_periodo, p_global,
p_visibles, p_factor)`** — la tabla-base de la conversión: una fila por
episodio en tres piernas UNION ALL — `recibido` (divisor; origen/motivo del
PRIMER episodio en ventana, `aproximado` con bool_or), `cierre` (una fila por
asignación convertida; los ANULADOS viajan MARCADOS con aporte 0 — F2 los
contará sin recalcular; referidos ya ponderados con `p_factor`) y `operacion`
(cartera elegible, máx. 1 por cliente/mes, orden calculado ANTES del filtro de
visibles — semántica viva). `p_periodo` explícito desancla el mes del rango
(NULL = sin pierna de cartera): habilita los rangos libres de F2.
`security definer, search_path='', EXECUTE revocado a todos.

**`private.conversion_mensual_por_vendedor` redefinida como agrupación sobre
la base**, aritmética de agregación VERBATIM. Paridad probada dos veces:
- **Banco local** (`run-test-conversion-episodios-local.sh` + fixtures de
  `test-conversion-episodios.sql`): ancla md5 local↔prod del núcleo vivo
  (`49601295…`), 6 llamadas con paridad de conjunto (EXCEPT bidireccional) y
  de BYTES (md5 de filas ::text ordenadas), oráculo con números calculados a
  mano (V1–V5: multi-episodio, lead compartido, doble cierre del mismo lead,
  anulado, fallback `finalizado_en`, cubo «anteriores», solo-cartera, orden
  de cartera antes del filtro de visibles, bordes exactos de ventana), contrato
  propio de la base (p_periodo NULL, anulados marcados, ponderación) y
  **4 mutantes muertos** (sin distinct · sin filtro de anulados · sin tope
  1-por-cliente · origen del último episodio).
- **Producción**: el guion de aplicación toma FOTO del núcleo (mes actual y
  anterior, factor 0.15 y 1.0) antes y después — si difieren un byte, aborta
  y ordena el rollback.

Preflight: md5 del núcleo vivo y de `cierre_externo_anulado` + candado de
re-ejecución (si `conversion_episodios` ya existe, aborta). Postflight: el
núcleo consume la base y YA NO lee `crm.lead_asignaciones` ni
`crm.operaciones_cartera` directo; ACL de la base = solo owner (aclexplode vs
proowner); definer + `search_path=""` (comillas — lección RETOMAR-53).

Incluye el **vigía (a)** del plan en el guion de aplicación: toda función
`crm.*`/`private.*` con 'conversion' en el fuente debe consumir el núcleo o la
base (strpos, jamás LIKE); los 5 motores paralelos van en lista blanca
NOMINAL que F2 debe encoger. Consumidores NO tocados (heredan):
`conversion_mensual_sin_cartera_fn`, `conversion_mensual_fn`,
`cumplimiento_metas_fn`, cierre de mes, alertas. La anulación post-sello sigue
en la LECTURA (`ajuste_pendiente_por_vendedor`) — en el núcleo se descontaría
dos veces.

Deuda consciente dicha: `test-rls.mjs` no gana casos (función private sin
EXECUTE para roles de API); la global `metricas_conversiones_fn` sigue sin
caso (fila `20260810024404`). Excepciones a `public`: ninguna.

Auditor RLS: APROBADA (2 notas para F2: postflight del núcleo con identity
arguments si aparece sobrecarga · no relajar el NOT NULL de `origen` sin
revisar los `else 1` de la base). Codex (8 ángulos): 2 refutaciones REALES
cerradas antes de aplicar — (P1) empates exactos de `asignado_en` hacen
indeterminado el primer episodio TAMBIÉN en el vivo → candado de datos en el
guion (aborta si el ledger tiene empates); (P8) la base sumaba capitales
(aritmética que el vivo jamás ejecutó, overflow teórico) → `monto` NULL en F1,
y postflight nuevo: mismo owner en base y núcleo (dos DEFINER con owners
distintos correrían con identidades distintas). Condicionales verificadas:
desempate de cartera con orden total (PK de `operaciones_cartera`, verificado
en el guion) · peso del plan (RETURN QUERY materializa; datos de prod hoy
minúsculos, vigilancia en [[Plan de escalabilidad del CRM a data gigante|F4]]).
Banco re-ensayado verde tras las correcciones (paridad + oráculo + 4 mutantes).

Aplicación: `scripts/aplicar-f1-conversion-episodios-prod.sh`. Vuelta atrás:
`scripts/rollback-f1-conversion-episodios.sql` (núcleo vivo verbatim pre-F1 +
drop de la base + verificación md5).

## 20260827020000 · `crm_f2_1_conversiones_nucleo`

✅ **APLICADA EN PROD** (2026-08-27 ~03:00 UTC, canal MCP Supabase; registro
`schema_migrations` con md5 `67c07129…` = md5 del fichero local). Owners
verificados iguales ANTES de aplicar (`postgres`/`postgres`). Advisors tras
aplicar: **0 ERROR** (134 WARN preexistentes).

**EL CAMBIO REAL, medido en vivo (mes en curso, 545 leads):**

| | ANTES | DESPUÉS |
|---|---|---|
| `cohorte.contratos` | **0** (columna muerta) | **14** |
| `conversion_contratos_pct` | **0.0 %** | **2.6 %** |
| `cohorte.clientes` | 15 | 14 (uno tenía el cierre ANULADO) |
| bloque `nucleo` | no existía | **7.22 %** (38.75 / 537) |
| `cosecha` | no existía | 2.6 % (14 de 545) |

Sondas en vivo: `cuadra: true` con **paridad 0.000 sobre 16 filas** — el
bloque `nucleo` es EXACTAMENTE la cifra del héroe de HOY · `episodios_sin_
origen` 0 · `origen_ficha_distinto_del_ledger` **0** (la etiqueta D6 es segura
hoy) · `cierres_sin_ficha_convertida` 0 · `cartera_fuera_del_rango` 0 ·
`divisor_fuera_del_roster` 0 · `numerador_fuera_del_roster` **1.000** y
`cohorte_convertidos_sin_cierre_elegible` **1** (el cierre anulado): los dos
únicos desacuerdos, ahora visibles en vez de invisibles.

**F2.1** del plan
[[Conversion unica en todo el CRM - plan de migraciones]] — primer motor
paralelo que pasa a la tabla-base.

⚠️ **LOS NÚMEROS DE LA PANTALLA CAMBIAN EL DÍA DEL CORTE**, bajo los rótulos
viejos, hasta F3 (transición aceptada por Miguel, decisión D4). Estado VIVO
medido antes de aplicar (mes en curso, 545 leads): `contratos: 0` y
`conversion_contratos_pct: 0.0` — el 0 % estructural del hallazgo H3, en vivo.

`private.metricas_conversiones_implementacion(date,date)` deja de contar
`crm.leads.contrato_id` (columna que **nadie** rellena) y agrupa
`private.conversion_episodios`. Claves **solo añadidas** (el schema del front
de esta pantalla es `v.object`, verificado en el bundle VIVO `b3f6e98`:
9 `v.object`, 0 `strictObject` — al contrario que Distribución, 22
`strictObject`, de ahí el corte en dos tiempos de F2.3):
- `nucleo` — cifra principal (D2): flujo del rango por asignación, referidos
  ponderados y fuera del divisor, cartera solo si el rango es el mes entero o
  todo lo que va del mes en curso (`incluye_cartera` lo declara).
- `cosecha` — segunda lectura (D2): de los leads dados de alta en el rango,
  cuántos cerraron; **madura hasta hoy** (un lead de julio que cierra en
  agosto cuenta). Esa maduración es el sentido de la lectura, no un sesgo.
- `sondas` — `paridad_nucleo` (0 = el recomputo coincide con el núcleo),
  `divisor_fuera_del_roster`, `cohorte_convertidos_sin_cierre`,
  `cartera_fuera_del_rango`, `cierres_anulados`, `episodios_sin_origen`.
- por origen: `peso_en_nucleo` + `fuera_del_divisor_del_nucleo` (D6).
- por responsable: `nucleo_divisor` / `nucleo_numerador` /
  `nucleo_conversion_pct` — DENTRO del array `responsables`, así que los
  gobierna el mismo filtro del wrapper (`filtrar_desglose_sujetos_crm`).

**NO se toca** `produccion` ni los capitales: siguen midiendo CONTRATOS por
`fecha_cierre_comercial` (H14, universos distintos — se rotulan en F3).

Banco: `run-test-f2-conversiones-local.sh` + `test-f2-conversiones.sql` —
oráculo con números calculados a mano sobre **julio 2026** (mes ya pasado, para
que la maduración no dependa de la hora ni del huso del que ejecuta), contrato
de rango parcial y de rango libre, sondas, gate de rol en negativo, igualdad de
escala con el núcleo real, y **8 mutantes muertos** (numerador muerto ·
anulados que suman · referido a peso 1 · cosecha sin maduración · cartera del
mes entero en rango parcial · sonda mirando el conjunto equivocado · gate de
rol borrado · recomputo que pierde la cartera).

Auditor RLS: 2 objeciones ALTAS **cerradas antes de aplicar** — (A1) faltaba
comprobar que la pantalla y la tabla-base tienen el MISMO owner: son dos
DEFINER y la base solo la ejecuta su owner; sin ese candado la pantalla moriría
con permission denied y, en la imagen Supabase 17.6, un `select fn()` sin
EXECUTE tumba el backend ([[postgres-cae-por-permiso-de-funcion]]) → preflight
nuevo que aborta antes de tocar nada. (A2) la pierna de cartera filtra por MES,
no por la ventana: un rango 01→10 de julio sumaba las operaciones del 11 al 31
→ ahora solo se activa con el mes entero o el mes en curso completo, con caso
de prueba y mutante propios. MEDIAS cerradas: identity arguments en el
postflight, verificación de ACL, sondas de roster y de convertidos-sin-cierre,
y comentarios corregidos (el total del núcleo **no** es la suma de
`responsables`: incluye analistas fuera del roster, y el wrapper filtra).

Codex (8 ángulos, revisión adversarial): 6 defectos REALES cerrados antes de
aplicar — (1) la sonda de paridad solo comparaba divisor y cierres: **ignoraba
el numerador**, donde vive la cartera → ahora compara los cuatro términos;
(2) con ambas relaciones vacías `sum()` da NULL y el `coalesce` declaraba
«cuadra ✓» sin haber comparado nada → se añade `paridad_filas` y `cuadra` es
NULL si no hubo sustancia; (3) el % del núcleo se redondeaba a 1 decimal y el
núcleo real usa 2 (33.3 vs 33.33) → **dos decimales**, para que sea comparable
byte a byte con HOY; (4) `aclexplode(NULL)` devuelve cero filas, así que una
ACL por defecto (EXECUTE a PUBLIC) **pasaba** el postflight → el NULL se
rechaza aparte (verificado en prod: `{postgres=X/postgres}` en ambas
funciones); (5) las sondas prometían más de lo que medían → `numerador_fuera_
del_roster`, `cierres_sin_ficha_convertida` y el nombre honesto
`cohorte_convertidos_sin_cierre_elegible`; (6) **D6 se rotulaba sobre el origen
de la FICHA mientras el núcleo decide «referido» por el del LEDGER** → sonda
`origen_ficha_distinto_del_ledger` (mientras sea 0 la etiqueta es segura).

🔴 **La objeción más útil de Codex: las pruebas no mordían el gate de rol.**
`auth.uid()` estaba fijado a una gerencia válida en todo el banco, así que un
mutante que BORRARA la puerta de autorización habría sobrevivido a la suite
entera. Ahora `auth.uid()` es conmutable y hay casos negativos (vendedor,
anónimo, gerencia inactiva, periodo inválido) + el mutante M7 que los prueba.

Deuda consciente dicha (no se corrige aquí, se declara): el tope de rango
admite 366 días inclusivos (`p_hasta - p_desde > 365`) — comportamiento VIVO
copiado verbatim, no lo introduce F2.1. Y una operación de cartera con fecha
futura dentro del mes en curso entra en el núcleo del mes-hasta-hoy: **el héroe
de HOY la cuenta igual**, así que se conserva la paridad y se DECLARA con
`cartera_fuera_del_rango` en vez de divergir.

⚠️ **Deuda consciente dicha (M6 del auditor): `crm.metricas_conversiones_fn`
sigue con CERO casos en `test-rls.mjs`** (solo está cubierta `_equipo_fn`).
Faltan: permitido gerencia/lector global · denegado 42501 a vendedor,
supervisor, coordinador, analista · 22023 de periodo inválido llamado por
gerencia · que `responsables[]` no traiga a nadie que no sea vendedor · y
ausencia de EXECUTE comprobada con `has_function_privilege`, **nunca**
ejecutando la función (riesgo de A1). Preexistente (lo admite la fila
`20260810024404`), no lo introduce F2.1.

Excepciones a `public`: ninguna. Aplicación:
`scripts/aplicar-f2-1-conversiones-prod.sh` (imprime la foto antes y después:
aquí el cambio de cifras es el objetivo, no un fallo). Vuelta atrás:
`scripts/rollback-f2-1-conversiones.sql` (texto anclado en F0 verbatim; al
volver, la pantalla marca 0 % otra vez).

## 20260827033000 · `crm_f2_2_ranking_nucleo`

✅ **APLICADA EN PROD** (2026-08-27 ~04:00 UTC, canal MCP Supabase; registro
`schema_migrations` md5 `93ce1a5d…` = md5 del fichero). Advisors: **0 ERROR**
(134 WARN preexistentes).

**EL CAMBIO REAL, medido en vivo (mes en curso, 18 vendedores):**

| | ANTES | DESPUÉS |
|---|---|---|
| vendedores con clientes | **0 de 18** | **6 de 18** |
| total de clientes | **0** | **14** |
| primero del ranking | quien tenía más LEADS (42, con 0 cierres) | quien más CIERRA (5 cierres) |
| su conversión | 0.0 % | 13.2 % cosecha · **16.18 % núcleo** |

Sondas en vivo: `cuadra: true` con **paridad 0.000 sobre 16 filas** ·
`divisor_fuera_del_roster` 0 · `numerador_fuera_del_roster` 1.000 ·
`clientes_acreditados_a_otro_dueno` **0** (hoy las dos acreditaciones dicen lo
mismo) · `cierres_anulados` 1.

**F2.2** del plan
[[Conversion unica en todo el CRM - plan de migraciones]] — segundo motor
paralelo a la tabla-base.

⚠️ **LOS NÚMEROS DEL RANKING CAMBIAN EL DÍA DEL CORTE**, bajo los rótulos
viejos, hasta F3 (decisión D4). Estado previo: `clientes` contaba
`crm.leads.contrato_id`, columna que nadie rellena → **0 para TODOS**, y el
ranking se ordenaba por `leads`, es decir por nada que fuera resultado.

`crm.metricas_conversiones_equipo_fn` pasa a agrupar
`private.conversion_episodios` con el ámbito del que pregunta. Claves
**solo añadidas** (schema `v.object` verificado en el bundle VIVO `b3f6e98`):
por responsable `nucleo_divisor` / `nucleo_numerador` /
`nucleo_conversion_pct` (dos decimales, comparables byte a byte con HOY), más
los bloques `nucleo` y `sondas`.

🔑 **La objeción más valiosa del auditor (A2), corregida: la cosecha se mide
GLOBAL a propósito.** `cohorte` atribuye el lead a su **dueño actual**
(`crm.leads.vendedor_id`, MUTABLE) mientras el ledger lo atribuye a **quien lo
cerró** (`analista_id`, inmutable — el repo ya documenta ese choque en
`20260813235119`). Recortando la cosecha por ámbito, un lead cerrado por
alguien de otro subárbol contaba para gerencia y **no** para el supervisor del
dueño: dos `clientes`, dos `%` y dos órdenes de ranking del MISMO vendedor
según quién mirase, rompiendo el invariante de paridad de
`test-rls.mjs:5762`. Sin fuga: ese conjunto nunca sale al payload, solo sirve
de prueba de pertenencia sobre leads que `cohorte` ya recortó.

🔴 **BLOQUEANTE cerrado (B1): el gate `test-rls.mjs` habría fallado.** Su
aserto exigía que cada responsable trajera **exactamente 4 claves** («un campo
de más es superficie sin auditar»); F2.2 trae 7. Actualizado a la lista exacta
de 7 — no relajado a «contiene», que mataría la defensa — más un aserto nuevo
de la forma del bloque `sondas` y la paridad ampliada a las cifras del núcleo.

Otras objeciones cerradas: **A3** el postflight no anclaba el ÁMBITO, que es
lo único que corre en producción → cuenta las llamadas recortadas y rechaza
que la pierna de flujo se vuelva global; **M1** dos aristas DEFINER→DEFINER
nuevas (`peso_referido_conversion`, `conversion_mensual_por_vendedor`, ambas
revocadas a todos menos su owner) sin candado → preflight con
`has_function_privilege`, que **no ejecuta** la función (un `select fn()` sin
EXECUTE tumba el backend en esta imagen); **M2** el postflight solo prohibía
grantees de más, no comprobaba que `authenticated` CONSERVE EXECUTE (sin él,
PostgREST devuelve PGRST202 y la pantalla muere en silencio); **M3** la pierna
de paridad se calculaba para tirarla cuando el rango no es un mes → podada;
**N2/N3** asserts normalizados (minúsculas y espacios) y anclados con
paréntesis para que un comentario no cuente como uso.

Declarado, no silenciado (**M5**): un supervisor ve ahora, **en agregado**, la
producción de sus ex-miembros y sub-supervisores —
`private.vendedor_ids_visibles` conserva a los inactivos a propósito mientras
`roster` los excluye, y ese hueco es justo lo que publican
`divisor_fuera_del_roster` / `numerador_fuera_del_roster`. No es fuga (todo
dentro de su subárbol, y es su propia historia), pero es una clase de sujeto
que antes no aparecía.

Banco: `test-f2-ranking.sql` (comparte `fixture-f2-conversion.sql`) — ranking
global con números a mano, ámbito del supervisor recortado, **coherencia
dueño≠cerrador**, sondas del roster con un supervisor que tiene episodios
propios, gate en negativo y desglose solo-vendedores; **6 mutantes muertos**
(numerador muerto · gate borrado · desglose sin filtrar · núcleo global ·
cosecha recortada · sonda mirando el conjunto equivocado). Cuatro de ellos los
mata el **postflight dentro de la transacción**, no solo el oráculo.

Hallazgo de Codex convertido en SONDA (`clientes_acreditados_a_otro_dueno`):
en este payload conviven **dos acreditaciones legítimas del mismo hecho** —
`clientes` acredita al **dueño actual** del lead (reasignable por gerencia) y
las cifras `nucleo_*` acreditan a **quien lo cerró** (ledger, inmutable).
Coinciden salvo reasignación; la sonda cuenta los casos en que no. En prod
hoy vale 0. (Codex se colgó por red antes de emitir veredicto formal; su
objeción sustantiva quedó cerrada así, y la de coherencia, por A2.)

Excepciones a `public`: ninguna. Aplicación:
`scripts/aplicar-f2-2-ranking-prod.sh` (foto antes/después: aquí el cambio de
cifras es el objetivo). Vuelta atrás: `scripts/rollback-f2-2-ranking.sql`.

## 20260827050000 · `crm_f2_3a_distribucion_sin_anulados`

✅ **APLICADA EN PROD** (2026-08-27 ~05:30 UTC; registro md5 `a51a1643…` =
md5 del fichero). **F2.3a** del plan
[[Conversion unica en todo el CRM - plan de migraciones]] — tercer motor.

**EL CAMBIO, medido en vivo (mes en curso):** `resumen.convertidos_pen`
**11 → 10** (un cierre anulado deja de contar) · `descartados_pen` 80 y
`cohorte_episodios` 548 **intactos** · **FORMA DEL PAYLOAD IDÉNTICA**
(huella de claves `f99c4462…`, 1117 caracteres, byte a byte antes y después).

⛔ **Por qué esta migración no añade NI UNA clave:** el bundle VIVO (`b3f6e98`)
valida esta pantalla a **cierre hermético** — `v.strictObject` en todos los
niveles (`metricas-distribucion.ts`, 22 apariciones; las otras cinco pantallas
usan `v.object`). Con `strictObject` una clave NUEVA rompe la pantalla igual
que renombrar una, y el front está bloqueado hasta integrar ramas: no se
podría arreglar publicando. Por eso F2.3 va en dos tiempos; las claves nuevas
y las sondas esperan a **2.3b**.

Arregla **H17**: anular un cierre bajaba la conversión de Rendimiento y **no**
bajaba el «cierra el X %» del panel de abajo, en la misma pantalla y para el
mismo vendedor. Ahora los cierres los da la tabla-base, con la misma regla que
HOY/Ranking/Conversiones.

🔑 **El preflight se ganó el sueldo: abortó la primera aplicación.** Su primera
versión miraba el owner del wrapper público y falló con «no puede ejecutar la
tabla-base». Al mapear la cadena real de privilegios apareció el porqué:
`crm.metricas_distribucion_leads_v2_fn` (DEFINER, owner **`crm_metricas_bridge`**)
→ `private.metricas_distribucion_leads_autorizada` (DEFINER, owner
**`postgres`**) → `private.metricas_distribucion_leads_core` (**NO** definer).
Al no ser DEFINER, el motor corre con la identidad del DEFINER de arriba
(`postgres`), que sí puede. El candado ahora comprueba ESE eslabón y además
que `..._autorizada` siga siendo DEFINER — si dejara de serlo, cambiaría quién
ejecuta el motor. **El banco reproduce esa cadena de tres eslabones**, o el
candado no se probaría.

🔴 **El oráculo cazó un hueco REAL de mi migración**: además de las tres
agrupaciones (PEN total, PEN por rango, USD), el bloque `resumen` cuenta los
convertidos **por su cuenta** desde `cohorte`. Se me había escapado; el
postflight ahora exige **4** conteos filtrados, no 3. Y antes de eso el
oráculo pasaba **en vacío** (rutas equivocadas → comparaciones contra NULL,
que ni son verdad ni mentira): se añadió una guarda anti-vacuidad explícita.

Banco: `run-test-f2-distribucion-local.sh` + `fixture-f2-distribucion.sql` +
`test-f2-distribucion.sql` — ancla md5 del motor vivo, huella de forma de la
función VIEJA sobre los MISMOS datos, y **3 mutantes muertos** (vuelve a
contar anulados · solo una agrupación filtra · la pierna de cierres se corta
en el rango y pierde los que cierran después).

`ciclos_resueltos` NO cambia a propósito: el episodio **sí** se resolvió,
aunque el cierre se anulara después. Excepciones a `public`: ninguna.

## 20260827060000 · `crm_f2_5_reuniones_nucleo`

✅ **APLICADA EN PROD** (2026-08-27 ~06:00 UTC; registro md5 `3567a2dc…` =
md5 del fichero). **F2.5** del plan
[[Conversion unica en todo el CRM - plan de migraciones]] — cuarto motor.

`private.metricas_reuniones_implementacion`: «terminan en cliente» miraba la
FICHA del lead (`perfil_id` + `convertido_en`, que incluye los cierres
anulados) y «terminan en contrato» contaba `crm.leads.contrato_id`, la columna
que nadie rellena — valía **0 SIEMPRE**. Las dos pasan al LEDGER: un cierre
posterior a la reunión, sin anular, leído de `private.conversion_episodios`.
Arregla **H16**. Ninguna clave cambia (schema `v.object` en el bundle vivo).

⚠️ **HONESTIDAD SOBRE EL EFECTO MEDIDO: el número NO se movió en producción.**
Mes en curso: `clientes` 0 → 0 con 5 leads reunidos (ninguno de esos leads
cerró DESPUÉS de su reunión). Julio: **0 reuniones realizadas**, así que
tampoco hay con qué contrastar. El cambio es estructural y correcto — lo que
falta son datos que lo ejerciten, no la migración. Es exactamente el territorio
de `gate:realidad`: la prueba que vale es la del banco, no la foto de prod.

Banco (`run-test-f2-reuniones-local.sh` + `test-f2-reuniones.sql`): 5 reuniones
realizadas en julio → **2 terminan en cliente**, y las tres que quedan fuera
son las tres razones por las que puede quedar fuera — cierre ANULADO, lead que
no cierra, y un lead que **cerró ANTES de la reunión** (la reunión no lo trajo).
**4 mutantes muertos** (numerador muerto · anulados que cuentan · pierna de
cierres cortada en el rango · sin exigir que el cierre sea posterior).

🔴 **La misma trampa de F2.3a, otra vez: el oráculo pasaba EN VACÍO.** Las
aserciones apuntaban a `resumen.clientes`, pero el bloque real es
`conversion.clientes`; comparar contra NULL no es ni verdad ni mentira, así
que la prueba pasaba sin comprobar nada y un mutante sobrevivió. Se añadió
guarda anti-vacuidad explícita sobre las claves y sobre `leads_reunidos`.
**Lección para el resto de la fase: toda aserción sobre un payload necesita
una guarda que falle si la RUTA no existe.**

Excepciones a `public`: ninguna.

## 20260827070000 · `crm_f2_4_cartera_metrica_mes` + 20260827080000 · `crm_f2_4b_convertidos_sin_cartera`

✅ **AMBAS APLICADAS EN PROD** (2026-08-27 ~07:00 y ~08:00 UTC; registros md5
`f4b101f9…` y `d168d0db…` = md5 de sus ficheros). **F2.4** del plan — quinto y
último motor. Advisors: **0 ERROR**.

**Decisión D1 hecha código, en sus dos mitades:**
- la **MÉTRICA** de conversión pasa al **mes calendario del núcleo** en
  `crm.metricas_vendedores_fn`, `crm.resumen_cartera_fn` y
  `crm.series_comerciales_fn`;
- la **VISTA** sigue filtrando a **45 días** — es la regla de cartera que
  Miguel cerró el 08/08 («ya no son leads, desaparecen 45 días después de
  convertirse»), y D1 no la tocó. El payload lo declara con
  `ventana_metrica: 'mes_calendario'` junto al `ventana_convertidos_dias: 45`
  de siempre, para que F3 rotule sin adivinar. **Hay un mutante dedicado a cada
  mitad**: uno que devuelve la métrica a la cartera visible y otro que borra la
  ventana de la vista.

**EL CAMBIO, medido en vivo:**

| | ANTES | DESPUÉS |
|---|---|---|
| vendedores con convertidos | 6 | **14** |
| convertidos (equipo) | 15 | **14** cierres + 29 operaciones de cartera |
| tile «Convertidos» de cartera | 15 | **14** + 29 aparte |
| serie de cierres (6 meses) | **0 estructural** | **14** |
| leads vivos en cartera | 545 | **545** (la vista no se movió) |

🔴 **F2.4b existe porque F2.4 introdujo una incoherencia y la foto la destapó.**
Al pasar la métrica al núcleo, `convertidos` empezó a sumar **cierres de lead +
operaciones de cartera** (43), mientras la serie contaba solo cierres (14): dos
pantallas recién migradas discrepando entre sí — exactamente la enfermedad que
esta fase existe para eliminar. F2.4b deja `convertidos` = **cierres de lead**
en las tres, y las operaciones viajan en `operaciones_cartera`. El `%` NO
cambia: sigue siendo el del núcleo, que sí cuenta renovaciones en el numerador,
porque esa es la definición acordada. La migración 20260827070000 **no se
editó**: F2.4b es una migración nueva sobre el texto que quedó vivo.

Banco (`run-test-f2-cartera-local.sh` + `test-f2-cartera.sql`): oráculo con
números a mano (1 de 3 = 33.33 %), un lead convertido hace 100 días que debe
quedar **fuera de la vista y fuera del mes**, y **4 mutantes muertos**.

**VIGÍA FINAL, en producción: los 7 motores consumen `conversion_episodios`.**
No queda una sola pantalla contando cierres por su cuenta en el servidor.
Excepciones a `public`: ninguna.

## 20260827090000 · `crm_f2_3b_distribucion_v3`

**Estado: ✅ EN PROD (27/08, con OK de Miguel).** Aplicada vía MCP (preflight
y postflight verdes en la misma transacción, cadena real probada con gerencia
real, 18 analistas). Foto antes/después: **v1 y v2 byte-idénticas** (huellas
`6c2e80ee…`/`d9300951…` iguales antes y después). El mes real por la v3:
núcleo **38.75/537 = 7,22 %** — EXACTAMENTE el número de Conversiones/HOY/
Ranking, con `paridad_nucleo: 0` sobre 16 filas y `cuadra: true`; puntería
PEN 10/90 = 11,1 % y USD 4/10 = 40 %; `nucleo_sin_ficha: 1` — la sonda de la
objeción 9 del auditor ya caza en prod un caso real (un analista con historia
en el ledger fuera del roster). Advisors 0 ERROR (el WARN nuevo de la v3 es el
mismo informativo que llevan v1/v2). Registro en `schema_migrations` FIEL
(md5 registro = fichero `d246a471…`).

⚠️ Incidente de fidelidad, corregido en el mismo ciclo: la primera aplicación
pegó el SQL con comentarios internos recortados → los `prosrc` vivos no
coincidían con lo que produce el fichero. Se re-emitieron las 3 funciones con
el texto EXACTO (la puerta con danza INHERIT, dueño y ACL verificados
intactos tras el REPLACE) y los 4 md5 vivos = los del banco. Lección: lo que
se ejecuta debe ser el FICHERO, no una copia editada a mano. F2.3b del plan «Conversión única»: Distribución **sirve** sus
porcentajes en una RPC **v3 que el bundle vivo jamás llama**
(`crm.metricas_distribucion_leads_v3_fn`). El bundle `b3f6e98` valida la v2
con `strictObject` (una clave nueva la rompe), así que la forma nueva vive en
otra puerta: v1/v2 quedan **byte a byte** (postflight con `strpos` sobre texto
normalizado + paridad probada en banco: v3 sin sus claves nuevas ES v2).

Qué añade la v3: `conversion` por analista/rango/resumen (puntería
cerrados÷resueltos con 6 decimales — evita el doble redondeo del front — y
`pct` NULL cuando no hay resueltos), la cifra del **núcleo** (misma aritmética
que F2.1/F2.2), y `sondas` (paridad contra el núcleo real, anulados,
`nucleo_sin_ficha`, sin_analista) para que F3 oculte en vez de fabricar ceros.
Nuevos: `private.conversion_punteria`, `private.metricas_distribucion_leads_v3_core`
(ambos revocados de public/anon/authenticated/service_role — solo su dueño);
el despachador `..._autorizada` gana la rama `p_version=3` (gate y validación
intactos, verificado). La puerta: owner `crm_metricas_bridge`, DEFINER,
`search_path=''`, revoke total + grant solo `authenticated`, barrido
`aclexplode` con allowlist.

**Auditor RLS: 11 objeciones, todas cerradas antes de aplicar.** Las que
importan: (1) las funciones private nuevas nacían con EXECUTE a PUBLIC →
revoke + aserción de ACL; (2) cinco guardas comparaban `jsonb_typeof(...) <>`
— con la clave ausente pasan EN VACÍO → `is distinct from` en todas; (3) 🔴
**el `alter owner` desnudo habría reventado en prod**: `postgres` es admin del
puente pero `set_option=false` (verificado en `pg_auth_members`) y PG17 exige
poder `SET ROLE` — danza grant SET → alter → revoke SET; el banco corre como
superusuario y NO puede cazar esto; (4) `test-rls.mjs` gana 7 casos de la v3
(coordinador/vendedor/supervisor fuera; gerencia y directorio dentro con
sondas, sin SLA); (11) postflight 5.5 prueba la **cadena real** (puente →
rama 3 → puerta) con una gerencia real vía `request.jwt.claims`.

**Codex adversarial: 8 hallazgos; 4 nuevos, todos cerrados.** (d4) el
`alter owner` necesitaba ADEMÁS que el puente tuviera **CREATE sobre `crm`**
(revocado a propósito desde julio, verificado en prod) → danza completa
SET+CREATE, devuelta al terminar y aseverada en postflight; (e7/e8) el
rollback no podía borrar una función ajena y destruía estado si la migración
había abortado → guarda «nada que revertir» + danza INHERIT; (c3) un mutante
que pisara la v1 con una v2 pasaba el `strpos` y el oráculo → v1/v2 ahora se
distinguen por su clave propia (`sla_evaluables`/`sla_global_contactos`) y
mutante M7; (d5) la «paridad byte a byte» comparaba jsonb estructural (1≡1.0)
→ ahora compara el TEXTO serializado; (b6) el fixture no ejercitaba referidos
ni cartera (dos términos del numerador en cero) → referido 0.15 + operación
elegible, esperado 3.15/5=63.00 %, y mutantes M8/M9.

Banco (`run-test-f2-distribucion-v3-local.sh`): mundo anclado a prod por md5
(6 funciones), paridad por texto serializado, valores a mano (puntería
75 %/100 %, núcleo 3.15/5=63 %), gate en negativo Y positivo, rollback que
restaura el despachador al md5 exacto del vivo, **9/9 mutantes muertos** (3
por postflight, 6 por oráculo). El banco además cazó: el puente necesita
**USAGE del esquema** (no solo EXECUTE) — ahora candado del preflight,
verificado presente en prod.

Deuda dicha: la sonda de paridad ejecuta `conversion_episodios` 3 veces por
llamada (solo gerencia la paga) — medir antes de que F3 la llame en cada
render. Rollback: `rollback-f2-3b-distribucion-v3.sql`.
Excepciones a `public`: ninguna.

## 20260827154448 · `crm_f2_6_total_incluye_fuera_de_roster`

**Estado: ✅ EN PROD (27/08, con OK de Miguel).** Aplicada vía MCP: preflight
(`9a5025e4…`) y postflight (`c7a7a103…` + owner/secdef/search_path + cero
grants de API) verdes en la misma transacción. **Registro FIEL byte a byte:
md5 del registro en `schema_migrations` == md5 del fichero (`4d8da277…`,
24.122 bytes, 1 statement)** — el fichero se renombró de `…152918` a
`…154448` porque el MCP estampa su propio timestamp al registrar; contenido
intacto. Foto después por la cadena viva (gerencia real): **HOY
39,75/569 = 6,99 % == núcleo 39,75/569 = 6,99 %** (la igualdad D8 medida; el
7,22 % del hallazgo era la foto del 26/08 — la base se movió), 18 analistas
(17 roster + 1 ex-roster), `fuera_de_roster` sigue declarado
({analistas 1, divisor 0, cierres 0, numerador 1.0}), **responsables
byte-idénticos antes/después** (md5 `3c28b4cb…`, 17 filas). Control julio
(mes abierto histórico con fuera vacío): total en ceros, pct NULL, medible
false — semánticamente intacto (⚠️ el md5 del payload ENTERO nunca sirve de
control entre llamadas: lleva `generado_en`). Advisors: 0 ERROR, cero
menciones a la función. `test-rls.mjs` actualizado a D8 (total = filas +
fuera por CADA alcance + caso denegado sup2) pero NO corrido en este ciclo:
exige `SUPABASE_SERVICE_ROLE_KEY`, que no está a mano en esta sesión — queda
como gate del próximo ciclo que la tenga.

Decisión **D8 (Miguel, 27/08)**: la conversión de empresa mide lo
que PASÓ en el mes, no la nómina vigente. El `total` del mes ABIERTO de
`crm.conversion_mensual_fn` (vía `crm.conversion_mensual_sin_cartera_fn`, el
cuerpo grande que 20260824231133 renombró) pasa a SUMAR el agregado fuera de
roster que hasta hoy solo se declaraba en `cobertura.fuera_de_roster` — con
esto HOY vuelve a decir la misma cifra medida que el núcleo de F2
(`conversion_episodios`). Medido en prod antes de escribir: roster neto
38,75/569 = 6,81 % vs núcleo 39,75/569 = 6,99 % (1 analista fuera de roster
con 1 cierre y 0 leads — el mismo de `nucleo_sin_ficha: 1`).

Qué cambia (un VALOR, no la forma): `resumen` suma `filas` (roster, neto de
ajuste) + `fuera` (bruto — el ajuste de meses pagados se descuenta por fila
del roster y el ex-roster no tiene fila); `fuera` gana desgloses INTERNOS
(aproximado, no_referidos/referidos/arrastre, referidos_recibidos);
`motivos_totales` cubre también el divisor del ex-roster para que
`divisor_por_motivo` siga cuadrando con `total.divisor`. `cobertura.
fuera_de_roster` SIGUE declarándose con sus 4 claves de siempre; ni una fila
nueva en `responsables`, ningún uuid expuesto. Quien sale del roster a mitad
de mes cuenta ENTERO en el agregado (el roster es estado actual, no
histórico) — igual que hará su foto al sellarse, donde entra con nombre.
Meses SELLADOS: intactos (rama 3 sirve la foto de `periodos_cerrados`; no
pasa por este camino). Herederos: NADIE más llama la función —
`cerrar_periodo`, `cierre_mes_estado_fn`, `convertir_lead_externo` y
`cumplimiento_metas_sin_cartera_fn` solo la citan en comentarios (verificado
contra prosrc vivo). Privilegios idénticos (EXECUTE revocado a todos; la
única puerta sigue siendo el envoltorio).

Fidelidad: preflight aborta si el vivo no es `9a5025e4…` (== cuerpo de
20260815003742, verificado byte a byte contra prod el 27/08); postflight
exige `c7a7a103…` + owner postgres + secdef + search_path='' + cero grants de
API. Banco (`run-test-f2-6-total-fuera-roster-local.sh`, autocontenido con
stubs y núcleo como fixture): casos A–E — paridad byte a byte (::text) con
fuera vacío, el caso real de prod (+1 cierre), divisor/motivos/referidos,
roster vacío, divisor 0 → pct NULL — y **4/4 mutantes cazados** (numerador,
analistas, motivos, divisor). Rollback:
`rollback-f2-6-total-fuera-de-roster.sql` (restaura `9a5025e4…` con guarda).
Excepciones a `public`: ninguna.

## 20260824170349_crm_reconocimientos_ultimo_manda_vencido.sql

**Qué hace:** F4.4 «Hoy del supervisor, sin ruido» — re-crea la vista
`crm.alertas_reconocimientos_vigentes` (SIEMPRE con
`WITH (security_invoker = true)`, regla del auditor RLS #2) para que elija
PRIMERO el último asiento por alerta (`distinct on (alerta_id)` por
`secuencia desc`, dentro de la ventana de 7 días del candado) y evalúe la
vigencia DESPUÉS. Cierra el bloqueante Codex F4.4 B1: con la forma anterior,
al vencer una posposición la fila desaparecía de la vista y el asiento
ANTERIOR (aún dentro de sus 7 días) resucitaba como «último» — la campana
del supervisor volvía a atenuarse por un asiento superado y gerencia listaba
un compromiso que nadie sostiene. Ahora un posponer vencido, siendo el
último, bloquea a los anteriores: la alerta queda sin gobierno (cero filas)
y suena entera. Colateral bueno: la vista sirve a lo sumo UNA fila por
alerta. Gate nuevo en `test-rls.mjs`: «el posponer vencido BLOQUEA a los
asientos anteriores (nada resucita)» — ese caso FALLA contra la forma vieja.

**Estado: ✅ EN PRODUCCIÓN (2026-08-24, ~13:15 Lima).** md5 del fichero:
`31f358a01ce37e10285b37c7a8431e86`. Ciclo completo del banco
`f44-ultimo-manda` (ref `ertqnahqvqlazvxdgxro`, borrado al cerrar):
`reset_branch` a 20260811210049 (86 exactas, equipo vacío) → PATCH
/postgrest copiando la config API de prod → semilla intercalada → replay
**40/40 DESDE EL REGISTRO remoto** (los 3 asientos sin cuerpo salieron de los
`.sql` locales; 3 WARNINGs = postflights «sin datos» honestos del dominio
domicilio/régimen) → registro de las 40 al byte → **huella GLOBAL de
funciones IDÉNTICA a prod: 274 · md5 `556fe1ae563bfbad35a61b92aefc0481`**
(esta vez sin huella filtrada: los cuerpos locales cubren el drift) → F4.4
aplicada (registro 127 del banco, fila con 3 statements, md5 local
`585fb170…`) → `reloptions {security_invoker=true}` verificado → bajas de
semilla → seed demo + baja histórica → gate con los DOS oráculos nuevos EN
VERDE («el posponer vencido BLOQUEA a los asientos anteriores (nada
resucita)» + espejo de gerencia, hallazgo M1 del auditor; cierre en el único
✗ documentado del arnés; conteo completo no capturado — tail de 30) →
advisors del branch 156 = prod menos `extension_in_public_pg_net` (infra de
branch), cero clases nuevas → `merge_branch` verificado CONTANDO en prod:
fila `20260824170349` con 3 statements, viewdef con `DISTINCT ON`,
`security_invoker=true`, vigentes con una-fila-por-alerta, advisors sin
NINGUNA clase nueva propia. Auditor RLS previo: 0 bloqueantes/importantes —
verificó EMPÍRICAMENTE en un PG 17.10 local que los grants sobreviven al
replace, que el invoker se conserva, que el mutante sin `WITH` FUGA (sup2
vio filas ajenas), y que el oráculo discrimina forma vieja↔nueva.

⚠️ **Trampas nuevas del ciclo:**
- **El ejecutor del merge re-registra cada statement SIN su `;` terminal**:
  la fila en prod quedó con statements de [2134,608,1228] bytes vs
  [2135,609,1229] locales (exactamente el `;` final de cada uno) y md5
  `720e9b238dd40528a0be72bec5058edb`. Al verificar una fila mergeada,
  comparar contenido normalizado, no el md5 calculado sobre el fichero.
- **Una sesión paralela movió prod DURANTE el ciclo**: entre el volcado del
  registro y el merge aterrizaron `20260824154218_crm_leads_telefono_alternativo`
  y `20260824174020_crm_periodo_comercial_contratos` (+3 funciones y +2
  advisors `security_definer_executable` SUYOS: registro 126→128, funciones
  274→277, advisors 157→159). El merge no chocó (objetos disjuntos), pero
  toda aserción de conteo absoluto se re-mide al momento y se atribuyen los
  deltas antes de dar el veredicto.

**Registro de excepciones a `public`:** ninguna — ningún statement toca
`public.*`.

## 20260827193803 · `crm_f1_3_capital_por_leads_vivo`

✅ **APLICADA EN PROD** (2026-08-27 ~19:51 UTC, canal MCP Supabase; registro
`schema_migrations` versión `20260827195149` — el fichero local conserva su
`20260827193803`, equivalencia anotada aquí como manda el precedente del
banco). Preflight md5 `f38599fe…` (la de F2.1) OK · postflight md5
`47fb852c…` + candados (identity args, DEFINER/search_path, ACL owner-only,
caminos vivos presentes, enlace muerto ausente del CTE) OK. Advisors tras
aplicar: **0 ERROR** (135 WARN + 26 INFO preexistentes).

**Auditoría RLS previa (subagente auditor-rls): OBJECIONES — 3 MEDIO, ninguna
bloqueante, TODAS corregidas antes de aplicar**: (1) el reclamo «ya no se
consulta el enlace» se acotó al CTE `produccion` (sigue en `cohorte_base` y
`capital_responsables` → deuda F1.3b declarada); (2) pre/postflight ganaron el
patrón completo de F2.1 (identity args + prosecdef/search_path + ACL con la
trampa `aclexplode(null)`); (3) `metricas_conversiones_fn` estrenó casos en
`test-rls.mjs` (gerencia/directorio OK con forma exacta de `produccion` y
cero PII de cierres_externos en el payload; vendedores/supervisores/
coordinador/inactivo/banco 42501; gate antes que validación; 22023 con
período inválido) — **pendientes de ejecutar en el próximo ciclo de banco**
(el preflight local sigue sin `SUPABASE_SERVICE_ROLE_KEY`, deuda RETOMAR-57).

**EL CAMBIO REAL, medido en vivo como Carlos (gerencia), rango 01–27/08:**

| `produccion` | ANTES | DESPUÉS |
|---|---|---|
| `contratos` | **0** (enlace muerto) | **9** (6 portal + 3 coops) |
| `capital_pen` | **0** | **113.000** (58.000 portal + 55.000 coops) |
| `capital_usd` | **0** | **123.000** |
| `sin_rastro` | no existía | **1** («miguel alvarez» 19/08, prueba) |

Sondas intactas tras aplicar: `cuadra: true`, núcleo 6,80 %.
F1.3 del plan del «Hoy de gerencia» (27/08): el bloque `produccion` de
`private.metricas_conversiones_implementacion` medía el capital por leads vía
`crm.leads.contrato_id` — enlace JAMÁS poblado (auditoría en prod 27/08:
0 enlaces históricos; agosto: 111 contratos y S/ 3,7 M con el KPI en S/ 0).
Ahora mide por los caminos VIVOS: contratos del portal cuyo titular es un
perfil nacido de un lead (`leads.perfil_id = contratos.cliente_id`) + cierres
en cooperativas (`crm.cierres_externos` por lead, sin anulados), y declara
`produccion.sin_rastro` (convertidos del rango sin perfil ni cierre externo —
hoy 1: lead de prueba «miguel alvarez» 19/08).

**NO toca objetos de `public`** (solo LEE `public.contratos`, igual que la
versión anterior — sin OK adicional requerido). No cambia autorización,
policies ni grants; la columna `crm.leads.contrato_id` queda intacta.
Preflight: md5 vivo debe ser `f38599fe…` (la de F2.1). Postflight: md5
`47fb852c…` + `sin_rastro` presente + el enlace muerto ausente (por `strpos`,
no LIKE). Medido en prod antes de escribir (01–27/08): portal 6 contratos
S/ 58.000 + US$ 123.000 · externos 3 cierres S/ 55.000 · sin_rastro 1.

## 20260827220132 · `crm_f1_3b_capital_vivo_en_todas_las_patas`

✅ **APLICADA EN PROD** (2026-08-27 ~22:16 UTC, canal MCP; registro
`schema_migrations` versión `20260827221635` — fichero local `20260827220132`,
equivalencia anotada). Preflight md5 `47fb852c…` (F1.3) OK · postflight md5
`698f5999…` + candados completos (incl. ausencia TOTAL de `l.contrato_id`) OK.
Advisors tras aplicar: **0 ERROR** (fondo WARN/INFO preexistente). Auditoría
RLS previa (auditor-rls): **APROBADA** con 1 MEDIO no bloqueante que se
INCORPORÓ antes de aplicar — sonda nueva
`sondas.perfiles_con_leads_de_varios_vendedores` (un cliente que vuelve como
lead de OTRO vendedor duplicaría su capital en el desglose; hoy 0, el front
avisa si sube) + claim del ledger acotado a «foto del 27/08». Notas aceptadas:
pierna USD de coops = código muerto por CHECK moneda='PEN' (simetría a
propósito) · atribución portal por vendedor ACTUAL vs coops por FOTO al cierre
(definición elegida) · `select l.*` aún proyecta la columna (sin efecto,
cubierto por el pin de md5).

**EL CAMBIO REAL, medido en vivo como Carlos (01–27/08) tras aplicar:**
origenes[] con capital VIVO (oficina 77.000 + US$ 3.000 · referido 2.000 +
US$ 100.000 · otro 36.000 · formulario US$ 20.000 · landing US$ 10.000) ·
responsables[] con capital VIVO (VLADIMIR 107.000 + US$ 100.000 · LINDA
US$ 30.000 · NAYRA 6.000 · ADELAYDA US$ 3.000) · **las tres patas cuadran
EXACTO entre sí en la misma transacción** (vendedores PEN 113.000 =
produccion PEN · USD 133.000 = produccion USD) · sonda perfiles compartidos 0
· paridad `cuadra: true`. Matriz test-rls endurecida además con la forma
EXACTA de origenes[] (15 campos), responsables[] (12) y sondas (12, incl. la
nueva) — pendiente de ejecutar en banco.

(texto original de la entrada, escrito antes de aplicar:) F1.3b: mueren
las DOS últimas lecturas del enlace jamás poblado `crm.leads.contrato_id` —
`cohorte_base` (capital por lead HASTA HOY: portal vía perfil + coops
vigentes → `origenes[].capital_*` revive) y `capital_responsables` (capital
DEL RANGO por vendedor: contratos de perfiles de sus leads con `in` que
dedupe + coops del rango por `vendedor_id` → la ficha del vendedor deja el
S/ 0 eterno). El postflight ahora exige la ausencia TOTAL de `l.contrato_id`
en la función (lo que F1.3 no podía afirmar sin mentir). La columna queda
intacta. Medido contra la forma real antes de escribir: por origen oficina
S/ 77.000 + US$ 3.000 · referido US$ 100.000 · por vendedor VLADIMIR JURADO
S/ 107.000 + US$ 100.000, PEN cuadra exacto con produccion y cada contrato
atribuye a UN solo vendedor (sin doble conteo, verificado).

## 20260828003205 · `crm_filtro_origen_metricas_conversiones`

✅ **APLICADA EN PROD** (2026-08-28 ~00:52 UTC, canal MCP; pre/postflight OK
— md5 impl `b4875f18…`, wrapper `f6e43674…`; unicidad de sobrecarga, DEFINER/
search_path, ACL owner-only + candado service_role verificados). Advisors:
**0 ERROR** (fondo WARN/INFO preexistente). Medido en vivo como Carlos EN UNA
MISMA transacción: sin filtro 607 leads / `origen_filtrado` null · referido →
6 leads y 1 solo origen · oficina → 9 leads y capital S/ 77.000 · núcleo 599
SIN filtrar (deliberado). Filtro de
ORIGEN del lead (pedido de Miguel 27/08): `metricas_conversiones_fn` y su
implementación aprenden `p_origen text default null` — con filtro, TODO el
lote (cohorte/embudo/orígenes/categorías/responsables/tendencia) se recorta;
'sin_origen' selecciona los sin registrar; núcleo y paridad SIGUEN midiendo a
la empresa (deliberado, la pantalla ya no los pinta) y el payload declara
`origen_filtrado` SIEMPRE. **Cambio de firma, NO borrado**: los DROP de las
firmas de 2 args + CREATE de 3 con default van juntos porque dos sobrecargas
volverían ambigua la llamada PostgREST; toda llamada existente resuelve
idéntica. Autorización intacta; revoke cuádruple del histórico replicado.
Auditoría RLS: **APROBADA** con menores, TODAS incorporadas antes de aplicar
(candado service_role en postflight; matriz con denegado+p_origen,
'sin_origen' y origen inventado→lote vacío con forma estable; esta fila).

⚠️ **POR QUÉ SE APLICARON DOS DÍAS TARDE — y qué rompió mientras tanto.** El
front que las necesita se publicó el 28 en un release de OTRA sesión, sin estas
dos migraciones. Durante esas horas el bundle vivo mandaba `p_telefono_alternativo`
a una RPC que no lo tenía: **todo alta manual con segundo número fallaba y el lead
no se creaba** (con el campo vacío funcionaba, porque la clave no viajaba).

Es la regla de orden de despliegue del [[Deploy a Hostinger]] al revés: **clave
nueva en la PETICIÓN → servidor primero**. Al aplicarlas hubo que hacer
`notify pgrst, 'reload schema'`: sin eso PostgREST sigue sirviendo la firma vieja
y el arreglo no surte efecto aunque la función ya exista.

Cómo se comprueba que la API ve la firma nueva sin sesión: un POST anónimo al RPC
debe responder **42501** (muro de permisos, la firma resolvió) y no **PGRST202**
(no la encuentra en el caché de esquema).

## 20260828190000 / 190500 / 191000 · Fase 1 del PLAN MAESTRO P-055 — «proteger lo que ya tienes»

✅ **APLICADAS EN PRODUCCIÓN** (2026-08-29 ~01:40 UTC, autorizadas por Miguel:
«mergea por favor»). Registro de producción: **152 → 155 migraciones**.
Verificado por CONTEO y por COMPORTAMIENTO, no por lo que dijo el comando:
4 auditores nuevos · 16 guardianes · **0** tablas de `public` con permisos que la
RLS no gobierna · **0** RPC de administración abiertas a `anon`/PUBLIC y las 5
vivas para `authenticated` y `service_role` · `crear_contrato` **intacta**
(md5 `f50b62e1…`) · datos sin tocar (466 contratos, 9 co-titulares, 663 leads,
4252 cuotas). Sonda de comportamiento en producción, deshecha sola: el NaN
rebota · el aviso automático **no** ensucia la auditoría · borrar un co-titular
deja rastro con su `fila_id` y su documento · cambiar la gestión de un lead deja
rastro. Advisors de producción: **0 ERROR** (135 WARN + 26 INFO, fondo conocido).

🔴 **`merge_branch` VOLVIÓ A MENTIR — y ahora se sabe POR QUÉ.** Se llamó dos
veces: las dos devolvieron `{"success": true}` y producción **no cambió** (152
migraciones, cero auditores). La segunda dejó a `main` en `MIGRATIONS_FAILED`
**sin ejecutar una sola sentencia** (cero errores de Postgres en el log de esa
ventana). **La causa:** el registro del banco tenía las versiones **sin
`statements`** — se registran con `insert … (version)` a secas, igual que hacen
los `aplicar-*-prod.sh`, así que el merge no tenía SQL que llevarse. Cargar el
cuerpo en `statements` tampoco bastó: el merge siguió fallando en el orquestador.
**Vía que SÍ funcionó** (la de siempre en este proyecto):
`supabase db query --linked --file <migración>` una por una + registro de la
versión. ⚠️ Queda una secuela cosmética: **el branch `main` figura como
`MIGRATIONS_FAILED` en el panel** aunque la base está sana y completa.

**Qué hace cada una.**

| Versión | Qué | Por qué ahora |
|---|---|---|
| `190000` · `crm_f1_1_rastro_titulares_gestion_cuotas` | Auditor NUEVO en `public.contrato_titulares` y en `crm.actividades_cliente`; el de `crm.actividades` pasa de solo INSERT a INSERT/UPDATE/DELETE; y un auditor APARTE en `public.cronograma_pagos` solo para el alta y la baja. | `contrato_titulares` es el **único ROTO real** del inventario P-053: 0 filas de auditoría contra 1083 del contrato. Es el dato con más peso legal. |
| `190500` · `crm_f1_2_malla_anti_nan_montos` | 16 CHECK que rechazan NaN e infinitos en `cronograma_pagos` (2), `cierre_mes_vendedor` (7), `ajustes_mes_cerrado` (6) y `periodos_cerrados` (1). | Las tres tablas del cierre están **vacías hoy**: blindarlas es gratis. Después del primer cierre real, no. |
| `191000` · `crm_f1_3_puertas_baratas_anon` | REVOKE de las cuatro letras que RLS **no** gobierna (TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) a `anon` y `authenticated` en las 10 tablas de fábrica, `alter default privileges` para que no reincida, y cierre de las 5 RPC de administración. | Cuesta cinco minutos y no toca nada vivo. |

**🔻 LA CUARTA MIGRACIÓN SALIÓ DE LA FASE (Miguel, 28/08).** El cerrojo de la
numeración automática estaba escrito y verificado, pero Miguel decidió que **esa
numeración no se necesita todavía — más adelante sí**. Reemplazar una función
viva del portal para proteger una rama que hoy no usa nadie (466 contratos,
TODOS con número manual, cero autogenerados) es riesgo sin beneficio presente.
Además, Codex encontró que esa rama necesita **cuatro** arreglos, no uno: el
formato (`AC-2026-NNNN` cuando los 466 vivos son `2026-01-NNNNNN`), el cerrojo,
el año tomado de la zona de la sesión en vez de Lima, y la falta de validación
del número manual. Se deciden juntos el día que se encienda.
El archivo, con todo eso escrito, vive aparcado **fuera de `migrations/`** para
que ningún replay lo aplique por su cuenta:
`supabase/snippets/NO-APLICAR-numeracion-automatica-contratos.sql`.

**🔴 SEGUNDO FALLO PROPIO, CAZADO ANTES DE APLICAR — el `WHEN` que casi se
borra en silencio.** La primera versión hacía `DROP+CREATE` de
`trg_audit_cronograma_pago` para añadirle INSERT y DELETE. Ese trigger lleva una
cláusula **`WHEN`** puesta a propósito en la auditoría del portal del 2026-06-13:
audita solo los UPDATE que tocan el pago (`estado`, `monto_pagado`,
`fecha_pago_real`, `registrado_por`). Recrearlo la habría borrado sin decir nada,
y con ella la única defensa contra el ruido: el **cron diario de recordatorios**
escribe `notif_pago_enviada_en` y `recordatorio_3d_enviado_en` en muchas filas, y
cada sello habría dejado una fila de auditoría con el JSON entero. Corregido: el
trigger de UPDATE **no se toca** y el hueco probatorio —el borrado— se cierra con
`trg_audit_cronograma_pago_alta_baja`, un trigger aparte de INSERT/DELETE (donde
un `WHEN` sobre `old`/`new` ni siquiera sería válido). Sonda de regresión añadida:
sellar el recordatorio en todas las cuotas de un contrato produce **0** filas de
auditoría, un cambio de pago **sí** produce, y borrar una cuota **sí** produce.
**Regla que queda:** antes de recrear un trigger, leer `pg_get_triggerdef`
entero — `tgtype` no ve la cláusula `WHEN`.

**🔴 EL HALLAZGO QUE COSTÓ UNA SONDA — revocarle a `anon` no revocaba nada.**
La primera versión de `191000` hacía `revoke execute … from anon` y, medido
contra producción, **`anon` seguía pudiendo ejecutar las 5 RPC**. El permiso no
le venía de su nombre: el ACL de las cinco empieza por `{=X/postgres,…}`, que es
EXECUTE **para PUBLIC**. Quitárselo a un rol que lo hereda de PUBLIC no quita
nada. Corregido a `from public, anon` + `grant` explícito a `authenticated` y
`service_role`, y el postflight ya no usa `has_function_privilege` para esto
(dice «sí» también cuando el permiso es heredado): mira el ACL con `aclexplode`
y `grantee = 0`. **Regla que queda:** para comprobar que una puerta se cerró de
verdad, mirar el ACL, no la función de conveniencia.

**Cómo se verificaron sin gastar un branch ni escribir en producción.** Las
cuatro se aplicaron **contra producción dentro de bloques `DO` que siempre
terminan en `RAISE`**, así que todo se deshace (patrón ya usado en este
proyecto). Además de los preflight/postflight de cada archivo:

- **Sonda A + mutante:** borrar un co-titular real deja una fila de auditoría con
  su `documento`; **quitando el trigger, no la deja** — la sonda prueba lo que dice.
- **Sonda de regresión del `WHEN`:** sellar `recordatorio_3d_enviado_en` en todas
  las cuotas de un contrato → **0** filas de auditoría; un cambio de `monto_pagado`
  → **1**; borrar una cuota → **1**.
- **Sonda gestión:** modificar una fila de `crm.actividades` ya deja rastro (antes no).
- **Sonda B + mutante:** un `NaN` **rebota** en `cronograma_pagos`; **sin el CHECK, entra**.
- **Sonda C:** una cuota legítima (1234.56) entra y su alta queda registrada.
- **Postflight de la 2 sobre el predicado VIVO** (copiado del catálogo a una tabla
  temporal): NaN e infinito rebotan; `0`, `-3.5` y `17.25` pasan — el listón del
  cierre **no** impone rangos de negocio y por eso no puede romper el sellado del 10.
- **Sonda de permisos + mutante C:** cerrado TRUNCATE/REFERENCES/TRIGGER/MAINTAIN
  para `anon` y `authenticated` sin tocar SELECT/INSERT/UPDATE/DELETE; `service_role`
  intacto; y devolviendo PUBLIC la comprobación vuelve a fallar.
- **Sonda de la 4:** Postgres construyó el parche sobre su propia fuente viva y el
  cuerpo resultante coincide **byte a byte** (md5 `5db4ef8c…`) con el que instala el
  archivo. Compila, conserva SECURITY DEFINER, `search_path` y ACL, y el cerrojo
  resuelve la sobrecarga `(int,int)`.

**Decisión declarada — la convención de auditoría queda PARTIDA a propósito.**
`public` sigue con `public.log_audit_change` (columna `tabla` sin esquema) y `crm`
con `private.log_audit_crm` (con esquema). Unificarlas cambiaría el significado de
las ~23.000 filas ya escritas. El P-053 pedía decidirlo: decidido.

**Fuera de alcance, con motivo:** `crm.operaciones_cartera` (ledger append-only,
REFUTADO como roto), `crm.usuario_eventos` (su `id` es BIGINT y `log_audit_crm` lo
castea a uuid: colgárselo abortaría todo su DML), `public.audit_log` (recursión),
y las tablas sin valor probatorio. Van a la Fase 7.

**⚠️ Riesgo conocido y aceptado de `191000`:** en la imagen local de Postgres
17.6.1.105 llamar a una función sin EXECUTE **revienta el backend** en vez de dar
«permission denied». Cerrar estas 5 no crea esa exposición —ya hay ~300 funciones
en esquemas expuestos que `anon` no puede ejecutar—, pero queda dicho. Antes de
aplicar, confirmar que ninguna página pública del portal las llama: verificado por
lectura el 28/08, solo se invocan desde `/admin`, detrás del login.

**AUDITORÍA RLS (subagente `auditor-rls`, 28/08): 3 ALTO, 4 MEDIO, 6 notas — todas
resueltas o refutadas con evidencia antes de dar esto por terminado.**

| # | Hallazgo | Qué se hizo |
|---|---|---|
| **A1** | El `DROP+CREATE` borraba el `WHEN` del auditor de cuotas, y ni el preflight (`tgtype`) ni el postflight podían verlo | **Ya estaba corregido** cuando llegó la auditoría (trigger aparte de alta/baja). Se añadió además la comprobación de `tgattr` (`UPDATE OF cols`), que `tgtype` tampoco ve |
| **A2** | La bandeja de actividad del portal se contaminaría con las filas nuevas | **REFUTADO con evidencia:** `public.bandeja_actividad` filtra por lista blanca `al.tabla in ('perfiles','contratos')` (leído de producción). Su canal en vivo sí se suscribe a todo `audit_log`, pero con retardo de 500 ms y solo re-consulta esa RPC filtrada: una recarga más, la misma que ya provoca el alta del contrato. Declarado en la cabecera de F1.1 |
| **A3** | No había marcha atrás, y el `WHEN` del auditor de cuotas **no existía en ningún archivo del repo**: solo en la base | **Escrita:** `supabase/scripts/rollback-f1-p055.sql`, con el cuerpo vivo de `crear_contrato` (anclado por md5), las definiciones literales de los dos triggers y una comprobación final de que el servidor quedó como antes |
| **M1** | El postflight exigía conservar grants MUERTOS (escritura de `anon`, escritura de `authenticated` sobre `audit_log`) y así los cementaba | Postflight relajado: solo exige que no se pierda el SELECT que el portal usa ni el `service_role`. Declarado por qué esos grants no se tocan aquí (son Fase 5, tocan superficie viva) |
| **M2** | F1.2 no declaraba el residuo | Declarado: `crm.lead_asignaciones.monto_estimado` sigue aceptando NaN (`is null or >= 0`, listón de un solo lado) y va a la Fase 7. Anotado también que `crm.leads.monto_estimado` **sí** queda cubierto, por su tope superior |
| **M3** | Cero cobertura de lo nuevo en el gate | **Escrito** `supabase/scripts/test-f1-puertas.sql`: aceptación completa de las 4, con caso positivo, negativo y **dos mutantes**. Sigue el consejo del auditor de **no** llamar a las RPC como `anon` (eso revienta el backend en la imagen 17.6.1.105): la comprobación de permisos se hace por ACL con `aclexplode`, que es la misma verdad sin el riesgo. Falla en voz alta si el banco no tiene datos, en vez de pasar en verde |
| **M4** | La auditoría de `crm.actividades_cliente` mueve PII del CRM a un log gobernado por los roles del PORTAL | Declarado en la cabecera de F1.1 y aquí: un admin del portal que no sea gerencia del CRM pasa a poder leer el `detalle` de gestión y el documento de los co-titulares. Es el mismo trato que ya recibe `crm.leads`; la vista de `audit_log` recortada por ámbito queda para la Fase 7 |
| **N1** | Segundo bloque del preflight de F1.4 inalcanzable, con mensaje engañoso | Invertido el orden: primero «ya estaba puesta», después el md5 |
| **N2** | El postflight de F1.4 no comprobaba `search_path` ni ACL | Añadidos: `proconfig @> array['search_path=']`, sin PUBLIC, `anon` no y `authenticated` sí |
| **N3** | El cerrojo se sostiene hasta el commit | Sin ciclo de espera (mismo orden en todos los caminos, verificado). Declarado en la cabecera para el día que se encienda la numeración automática |
| **N4** | `alter default privileges` lo puede pisar la plataforma | Declarado; propuesto vigilarlo desde `gate-realidad.mjs` |
| **N5** | El preflight no veía una 11.ª tabla futura en `public` | Añadido: `public` tiene que tener exactamente 10 tablas |
| **N6** | El `revoke ... from public` afecta a roles que heredaban solo de PUBLIC | Declarado; verificado que los dos que importan (`authenticated`, `service_role`) tienen concesión propia |

**Corrida de aceptación final, con las 4 corregidas y aplicadas juntas contra
producción (todo deshecho):** 4 auditores + `WHEN` intacto · 16 guardianes · 0
tablas con permisos fuera de la RLS · 5 RPC cerradas a `anon`/PUBLIC y vivas para
`authenticated`/`service_role` · cerrojo puesto · NaN y 0 rechazados, cuota
válida con rastro de alta, borrado con rastro, **el sello del cron sin escribir ni
una fila** · co-titular borrado con su documento en el rastro · **los dos mutantes
confirman que las sondas prueban lo que dicen**.

**AUDITORÍA ADVERSARIAL DE CODEX (28/08): veredicto NO-GO — 4 P1 y 6 P2.
Corregido todo; dos hallazgos suyos quedaron refutados con evidencia.**

| # | Hallazgo de Codex | Resolución |
|---|---|---|
| **P1-1** | **El postflight de F1.4 abortaba el 100 % de las ejecuciones.** `SET search_path TO ''` se guarda en `proconfig` como `search_path=""` —con las comillas dentro—, y yo comprobaba `array['search_path=']`: falso siempre | **REAL, y era mío. Corregido.** Es la misma trampa que ya costó una sesión (`search_path=""` con comillas). Verificado contra producción (`proconfig = {"search_path=\"\""}`) y **con mutante**: la comprobación vieja falla, la nueva pasa. Nunca se había ejercitado porque ese bloque se añadió después de la última corrida |
| **P1-2** | La rama de autonumeración **es alcanzable hoy** y genera un formato que nadie usa | **Confirmado con datos y DECLARADO:** 0 de 466 contratos usan `AC-`; el formato vivo es `2026-01-NNNNNN`. También el año sale de la zona de la sesión, no de Lima, y un número manual `AC-…` no toma el cerrojo. **No se arregla aquí**: el candado es lo que pedía la Fase 1; el formato es una decisión de negocio de Miguel antes de encender la numeración automática |
| **P1-3** | La auditoría de `crm.actividades_cliente` mueve PII a un log con audiencia más amplia | **Acotado con números y declarado.** Los lectores de `audit_log` son `es_admin()` y superadmin: **3 personas** en producción (2 admins + 1 superadmin), no «cualquier admin». Y el precedente existe: `crm.leads` audita ahí con DNI y teléfono desde los cimientos. Se declara en la cabecera; la vista de `audit_log` recortada por ámbito queda en la Fase 7 |
| **P1-4** | El `REVOKE EXECUTE` crea **cinco rutas conocidas** hacia el crash ya reproducido (los nombres están en el JS publicado) | **Convertido en un gate obligatorio, no en un riesgo aceptado.** La cabecera de F1.3 exige comprobar en el BANCO —misma imagen que producción— que una llamada anónima real a `/rest/v1/rpc/dashboard_admin_metricas` responde **42501 y el banco sigue vivo**. Si se cae, **no se publica ese bloque** (las 5 se quedan como están, que no filtran nada) y se escala a Supabase. **No es una decisión de Miguel: es un paso del ciclo del banco**, y su resultado por defecto ya está decidido |
| **P2-5** | «El DELETE queda sin `fila_id` porque `log_audit_change` usa `NEW.id`» | **REFUTADO con evidencia.** La función viva usa `OLD.id` en la rama DELETE. Medido: el borrado de un co-titular deja `fila_id` con su id exacto. Añadido al script de aceptación para que no se pierda. La segunda mitad —que el sync produce DELETE+INSERT también para co-titulares que no cambiaron— **sí es cierta** y queda declarada |
| **P2-6** | El `DROP+CREATE` podía perder otros metadatos y toma ACCESS EXCLUSIVE | **Eliminado de raíz: la migración es ahora 100 % ADITIVA.** No se borra ni recrea ningún trigger; `crm.actividades` recibe `trg_audit_actividades_cambio_baja` (UPDATE/DELETE) y conserva su auditor de INSERT intacto. Además `set local lock_timeout = '5s'` |
| **P2-7** | `ADD CHECK` puede formar cola detrás de una transacción larga | `lock_timeout` de 5 s en F1.1 y F1.2: falla y se reintenta en vez de encolar al portal. No se usa `NOT VALID`+`VALIDATE` porque exigiría dos transacciones separadas para servir de algo, y validar 4252 filas es instantáneo |
| **P2-8** | `conname` no es único en toda la base | **Corregido:** preflight y postflight comprueban por par `(conrelid, conname)` y exigen `convalidated` |
| **P2-9** | El radio del `revoke ... from public` no estaba probado, ni la persistencia del default ACL | Afirmación suavizada (roles que heredaban solo de PUBLIC sí pierden) y **sonda nueva** de `pg_default_acl` en el postflight |
| **P2-10** | El md5 cubre el cuerpo, no los atributos | **Corregido:** el preflight exige además que las dos funciones de auditoría sean `SECURITY DEFINER` — una con el mismo texto y sin ese atributo abortaría todo el DML |

**Y lo que Codex confirmó que está bien:** ningún CHECK puede rechazar un valor
legítimo del cierre del 10/09 (negativos, cero y decimales pasan; los nullable
aceptan NULL; Postgres no convierte división por cero en NaN, lanza error, y
`cerrar_periodo` ni siquiera divide cuando el divisor es 0) · el `CASCADE` sí
dispara los triggers hijos · el advisory lock resuelve la sobrecarga `(int,int)`
y **no hay ciclo de deadlock** con el de `operaciones_cartera` · el
`alter default privileges for role postgres` es la forma correcta.

**Corrida de aceptación FINAL, con las 4 ya corregidas y aplicadas juntas contra
producción (todo deshecho):** 4 auditores nuevos + los 2 viejos intactos · 16
guardianes · `search_path` OK (el postflight que abortaba ahora pasa) · NaN
rechazado · el sello del cron sin escribir ni una fila · cuota, gestión y
co-titular con rastro (con `fila_id` y documento) · permisos exactos, presente y
futuro.

**ALCANCE FINAL: TRES migraciones.** La corrida de aceptación se repitió con ese
alcance y quedó en verde, comprobando además que `public.crear_contrato` sigue
**intacta y con su md5 original** — la Fase 1 no toca ninguna función.

### CICLO DEL BANCO — COMPLETO (2026-08-28, branch `f1-p055` / `dzfmczrdtxgfpkxswquq`)

| Paso | Resultado |
|---|---|
| Banco a paridad | **146 → 155 migraciones**; los 3 md5 de las funciones vivas (`log_audit_change`, `log_audit_crm`, `crear_contrato`) **coinciden al byte con producción** |
| Las 3 migraciones aplicadas | Los 3 postflights **en verde** |
| `test-f1-puertas.sql` | **En verde**: 8 comprobaciones + los 2 mutantes |
| **Gate de RLS** | **✅ 1185 aserciones, 0 rojos, `exit 0`** |
| Advisors (seguridad) | **0 ERROR.** 134 WARN + 26 INFO, todo fondo conocido: 131 `authenticated_security_definer_function_executable` (por diseño, revalidan el rol por dentro), 26 `rls_enabled_no_policy` (deny-by-default) y 2 `anon_security_definer_function_executable` (`es_gestor_cartera`, `es_operaciones` — preexistentes, van a la Fase 5) |
| Marcha atrás | **Probada en el banco**: `rollback-f1-p055.sql` deja el servidor como estaba y su propia comprobación lo confirma |

**🟢 EL RIESGO P1-4 DE CODEX, RESUELTO EMPÍRICAMENTE.** Se hicieron **20 llamadas
anónimas reales** por PostgREST a las 5 consultas ya cerradas, sobre la MISMA
imagen de Postgres que produccción. Las 20 respondieron **HTTP 401 con código
42501** (`permission denied for function …`) y **el banco siguió vivo** después.
El fallo de la imagen 17.6.1.105 **no se manifiesta por esta vía**: cerrar esas
cinco es seguro. La sospecha quedó medida en vez de aceptada.

**Tres hallazgos del ciclo que NO son de la Fase 1 y quedan anotados:**

1. **🔴 El seed determinista no puede correr contra un banco nuevo.**
   `private.definir_periodo_comercial_contrato()` es un trigger de
   `public.contratos` **SECURITY INVOKER** que lee `crm.periodos_cerrados`, tabla
   deny-by-default. Cualquier INSERT de contrato que NO pase por
   `public.crear_contrato` (que sí es DEFINER) muere con
   `permission denied for table periodos_cerrados`, y eso es justo lo que hace el
   seed. **Producción no está afectada**: se comprobó que `crear_contrato` es la
   ÚNICA función que inserta en `public.contratos`. **Demostrado que es
   preexistente**: con la Fase 1 revertida en el banco, el mismo INSERT falla
   igual. Andamio usado solo en el banco: `grant select on crm.periodos_cerrados
   to service_role`. Arreglo de verdad (Fase 5 o 7): que el trigger sea DEFINER, o
   que el seed cree los contratos por la RPC.
2. **🔴 `test-rls.mjs` tenía un fallo de JavaScript que abortaba el gate.** El
   bloque del filtro de origen (añadido el 28/08) llamaba a un ayudante `num()`
   declarado en OTRO ámbito: el gate moría con `num is not defined` tras 650
   comprobaciones verdes, sin llegar nunca a las de cierre de mes. **Corregido**
   en este ciclo (misma definición, en el ámbito que la usa).
3. **⚠️ El registro de migraciones de producción tiene 9 versiones sin cuerpo**
   (las que aplicaron los `aplicar-*-prod.sh`, que registran solo la versión).
   Para el banco hubo que rellenarlas desde los archivos locales. Sin eso, dos
   funciones vivas del CRM (`crm.datos_legales_contrato_fn` y
   `crm.completar_domicilio_cliente`) faltaban en el banco y el gate las reportaba
   como PGRST202. **Regla que queda:** al montar un banco, la fuente es el
   registro remoto **más** los archivos locales de las versiones sin `statements`.

**Banco `f1-p055`: borrado** al terminar (su trabajo estaba hecho).

**Lo que queda de la Fase 1:** nada. Fase cerrada.

---

## 20260829182800 · `crm_sancion_cooperativa_mes_sellado` *(renumerada desde 170000 el 29/08, antes de publicarse)*

**Estado: ESCRITA Y PROBADA CONTRA PRODUCCIÓN — SIN PUBLICAR.**

**Qué arregla.** Anular un cierre en cooperativa con el mes **ya sellado** le
devolvía la conversión al analista y le **regalaba el capital**. Con el mes
**abierto** sí se lo quitaba. Misma falta, misma sanción, dos resultados según el
día en que se anulara.

**Regla de negocio (Miguel, 2026-08-29):** *«una anulación no puede eliminar
capital; sí se lo puede quitar al analista, porque la anulación es para cuando
pasó algo en la gestión y hay alguna sanción»*. Este cambio **no toca el capital
de la empresa**: `crm.ajustes_mes_cerrado` solo lo leen
`registrar_ajuste_si_mes_cerrado`, `saldar_ajustes` y `ajuste_pendiente_por_vendedor`
— las tres son la hoja del analista. Verificado por catálogo antes de escribir.

**La causa.** `private.registrar_ajuste_si_mes_cerrado` calculaba el capital desde
`private.contratos_afectados_por_anulacion` → `public.contratos`, y **un cierre en
cooperativa no tiene contrato** (los 7 vivos dan 0 contratos afectados). En cambio
`private.produccion_mes_por_vendedor` **sí** lee `crm.cierres_externos` y respeta
`anulado_en`, que es por lo que el mes abierto sí lo descuenta.

**El arreglo.** Se copia la regla del mes abierto **tal cual**, sin inventar una
segunda: categoría `'nuevo'`, en su moneda, atribuido al `vendedor_id` del cierre y
solo si esa persona estaba en el cuadro de metas del mes. Las cuatro condiciones
del bloque `externos_confirmados` se reproducen una por una y el **preflight las
ancla**: si el mes abierto cambia de criterio, la migración aborta en vez de
fabricar una regla divergente en silencio.

**De propina:** los totales (`v_pen`/`v_usd`) y el desglose (`v_detalle`) salían de
**dos consultas separadas** sobre la misma fuente, sin nada que garantizara que
cuadraran — y `saldar_ajustes` descuenta casilla a casilla leyendo el desglose.
Ahora salen de una sola consulta: no pueden divergir.

**Anclas del preflight:** `md5(prosrc)` de `registrar_ajuste_si_mes_cerrado` =
`e07c89715b96ee2604ce435fea3e2c34`; las 4 condiciones vivas de la regla copiada;
las 4 casillas de `crm.ajustes_mes_cerrado`.
**Huella esperada tras publicar:** `d44dc889111ce00bdcff5e3496a49a9d`.

**Prueba contra producción (2026-08-29, todo deshecho).** La prueba se construye
**extrayendo el cuerpo del propio archivo de migración**, así que lo probado es
byte a byte lo que se publicaría. Con agosto sellado por un clon de
`crm.cerrar_periodo` al que solo se le movió el calendario:

| # | Comprobación | Resultado |
|---|---|---|
| 1 | Cooperativa de S/ 200 000 anulada tras el sello | deuda **PEN 200 000**, desglose `nuevo/PEN`, numerador 1 |
| 2 | El mes siguiente la absorbe | PEN 200 000, pendiente 0 |
| 3 | No se cobra dos veces | segundo intento absorbe 0 |
| 4 | Contrato normal (sin regresión) | USD 100 000, igual que antes |
| 5 | **Mutante** (versión vieja, otra cooperativa) | **PEN 0** → la prueba distingue, no es tautología |

**Ventana del defecto:** hoy no puede pasar (cero meses cerrados). Se abre el
**10/09**, cuando el ciclo automático selle agosto. Cooperativas vivas de agosto:
7 cierres, S/ 364 800.

**Correcciones de la auditoría RLS (29/08, antes de publicar):** hallazgo **A2** — la
deuda contaba también contratos DEMO (deuda fantasma: capital que nunca acreditó);
la rama de contratos lleva ahora `and not c.es_demo`, el preflight exige que
`es_demo` exista (por eso la renumeración: corre después de `20260829180000`) y el
postflight lo afirma.

**Pendiente:** veredicto de Codex y merge de Miguel.

---

## 20260829180000–183000 · FASE 3 del P-055 — «que cada venta tenga dueño»

**Estado: ESCRITAS Y PROBADAS CONTRA PRODUCCIÓN (cadena completa, todo deshecho) — SIN PUBLICAR. Auditorías en curso.**

Siete migraciones, en orden de publicación obligatorio:

| # | Versión | Qué hace |
|---|---|---|
| 1 | `180000` F3.1 | `public.contratos` gana `analista_cierre_id` (uuid, FK a perfiles, SIN on delete) y `es_demo` (boolean). Índices parciales. Solo estructura; el postflight ABORTA si algo quedó escrito. |
| 2 | `180500` F3.2 | Relleno del histórico, decisión por decisión: 2 demos (444444/888282, decisión 6) · 001163→Adelayda · 001325→Miguel (decisión 6, verificando el NOMBRE antes de escribir) · los 12 de gerencia se quedan VACÍOS (decisión 18) · el resto = quien lo registró si es del equipo comercial · `000180` (GLORIA, admin) declarado SIN REGLA y vacío. Postflight por FORMA (15 sin dueño exactos), no por conteo absoluto: la base está viva — mientras se escribía, Astrid registró el 001333. |
| 3 | `181000` F3.3 | `public.crear_contrato` acepta `analista_cierre_id`: parche por replace ANCLADO (md5 `f50b62e1…` + cada punto de inserción exactamente 1 vez; un acento — `inválida` — ya demostró por qué). Sin el campo: a nombre de quien registra si es del equipo; si no, nace sin dueño (transición). Valida contra `crm.equipo` sin exigir activo (decisión 15). |
| 4 | `181500` F3.4 | La reasignación: `crm.reasignaciones_analista` (append-only, RLS, motivo ≤300 obligatorio) + `public.reasignar_analista_contrato` (gate = gestor de cartera o gerencia, espejo de actualizar_contrato, con P04) + **trigger candado**: la columna SOLO se mueve por la puerta (válvula `crm.reasignando_analista`, mismo idioma que `crm.op_privilegiada`). Un demo no se atribuye. |
| 5 | `182000` F3.5 | Los demos dejan de contar: 7 funciones parcheadas vía `pg_get_functiondef` + replace del FROM (alias intacto), cada una anclada por md5 y con conteo de sitios esperado (1+1+1+1+1+1+7). `metricas_reuniones_implementacion` NO se toca: enlaza por `leads.contrato_id`, que está muerto (0/466). Las operativas (anulación, cerrar) tampoco: un demo se opera, no suma. |
| 6 | `182500` F3.6 | `crm.atribucion_contrato_fn`: quién es el analista, si es demo, y el historial de reasignaciones con nombres y motivo. La visibilidad NO se copia: pregunta a la vista viva `crm.contratos_cartera`. Se descartó ampliar esa vista: DROP+CREATE en cadena de 4 objetos vivos (la vista security_invoker + contratos_cartera_fn + cronograma_contrato_fn + titulares_contrato_fn) para 2 columnas de lectura. |
| 7 | `183000` F3.7 | ⛔ **NO PUBLICAR ANTES QUE EL FRONT.** La rama blanda de transición se vuelve dura: quien no es del equipo comercial y no elige, recibe «Elige el analista de la venta». |

**Prueba de la cadena completa contra producción (29/08, todo deshecho):** relleno 451+/15/2 · UPDATE directo rebota `P0409` · sin motivo rebota · demo no se atribuye · reasignación real con rastro y nombre · reasignar al mismo rebota · el rastro no se edita · audit_log vio el cambio · **mutante** (sin candado, el UPDATE pasa → la prueba distingue) · alta sin campo nace a nombre de quien registra · gerencia elige y va al elegido · un cliente como analista rebota · la atribución se lee (KELLY VEGA) · el demo se declara · métricas: bajan EXACTAMENTE PEN 100 000 + USD 100 000 y 2 contratos (lo que valen los demos).

**Front (commiteable junto):** `crm-api.ts` (input+payload+`reasignarAnalistaContrato`+`obtenerAtribucionContrato`), `crm-queries.ts` (hook), `database.types.ts` (columnas+2 RPC), `contrato-nuevo.tsx` (selector «Analista de la venta», arranca en quien registra), `mi-cartera.tsx` (3 llamadas + detalle), `lead-drawer.tsx` (arranca en el analista del lead), `contrato-detalle.tsx` (bloque de atribución + reasignar con motivo + historial), `roles.ts` (`puedeReasignarVenta`). Typecheck limpio; **2353/2353 pruebas** (3 mocks actualizados).

**Trampas nuevas de este ciclo:** el ancla de un parche falló por un ACENTO (`Moneda inválida`); las temp tables no son legibles bajo `set local role authenticated`; el catálogo de productos vivo es 100 % legacy (0 condiciones vigentes) — un alta de prueba NO debe fijar `crm.producto_condicion_id`, el candado fabrica el snapshot solo.

**Autorización para tocar `public` (regla de la casa, hallazgo A6):** OK explícito de
Miguel, 2026-08-29, chat: **«/goal — desarrola la fase 3 sin saltarte nada o iventar
reglas que yo no te he dicho»**, sobre el plan P-055 aprobado el 28/08 cuya decisión 2
(«el campo se crea y es obligatorio desde ya») vive en `public.contratos` por diseño.

**⚠️ ALCANCE DECLARADO (hallazgo A4 del auditor RLS):** en este tren, **ninguna métrica
lee todavía `analista_cierre_id`** — `produccion_mes_por_vendedor` sigue atribuyendo el
ranking por el analista del lead / `creado_por` + roster, como siempre. Esta fase crea
el DATO y su gobierno (puerta, motivo, rastro, candados); **cablear el ranking y el
capital al campo nuevo es la Fase 4** («una sola calculadora», §5 del plan: la fila-hecho
lleva «el analista que cerró»). Consecuencia honesta: hasta la Fase 4, reasignar mueve la
etiqueta y el expediente, no el mérito del podio. Se publica así A PROPÓSITO: cambiar la
atribución del núcleo vivo días antes del primer sello (10/09) es exactamente lo que la
Fase 2 prohíbe.

**Correcciones de la auditoría RLS (29/08, todas aplicadas antes de publicar):**
**B1** el respaldo del rollback iba a `public` (endpoint de la Data API con SELECT de
fábrica para anon) → va a `private`, con RLS y revoke · **A1** `es_demo` era el interruptor
más destructivo y el único sin puerta: candado propio (`trg_contratos_demo_solo_por_la_puerta`,
válvula aparte) + `public.marcar_contrato_demo` (solo gerencia, motivo obligatorio, el motivo
queda en `audit_log` como fila `demo_marca`) · **A2** (en la 182800) · **A3** el historial de
reasignaciones con motivos ya no se sirve al asesor del cliente: solo autoridad (con P04) o el
propio analista · **M1** el postflight de la 182000 era tautológico → invariante por conteo de
filtros + menciones totales · **M2** las 7 reescritas verifican `prosecdef`+`search_path`+dueño ·
**M3** anclaje por `regprocedure` con firma completa · **M4** el rastro audita vía
`log_audit_crm` · **M5** `service_role` sin permisos sobre el rastro · **M6** la policy de
lectura aplica P04 · **M7** el relleno abre su válvula y el comentario exige rollback entero ·
**M8** gerencia se excluye por MEMBRESÍA (la inactiva existe: la cuenta demo; 0 contratos, los
números no se mueven) · **N1** FKs del rastro a `crm.equipo` · **N2** revoke incluye `public` ·
**N4** invariante de la delegación comentada en la 182500.

**Veredicto de Codex (29/08, NO-GO) — TODO corregido y re-probado contra producción:**

| # | Hallazgo | Corrección |
|---|---|---|
| **P0-1** | La atribución era decorativa: el ranking y el sello seguían acreditando por `creado_por` | **`20260829182200`**: `produccion_mes_por_vendedor` atribuye por `analista_cierre_id` PRIMERO (validado contra el cuadro de metas del mes; fuera del cuadro ⇒ sin atribución, nunca cae a otro). Medido: Adelayda +17 000 (001163) → **PEN 383 600, la cifra exacta de la tabla del plan**; Miguel +10 000 (001325); los 12 de la decisión 18 siguen sin contarle a nadie |
| **P0-2** | Los demos seguían contando en el Directorio (AUM, crecimiento, top, ranking) y en pagos/admin | **`20260829182300`**: 9 funciones del portal parcheadas (13 sitios), con anclas por firma+huella+conteo. Y la vía de conversiones de cartera cerrada por la causa: un contrato CON operaciones no se puede marcar demo (la puerta correcta es la anulación de gerencia) |
| P1-1 | El relleno abría solo la válvula del candado de analista | Abre las dos |
| P1-2 | Un cliente cabía como analista por INSERT directo; coordinador/directorio podían recibir ventas | FK de `analista_cierre_id` → **`crm.equipo`** (la base lo rechaza sola); las dos puertas exigen rol `vendedor/supervisor/gerencia`; trigger nuevo: un contrato **no nace** marcado demo |
| P1-3 | Marcar demo podía partir un mes sellado en dos verdades | `marcar_contrato_demo` toma el cerrojo del período y **rechaza meses sellados** (mismo patrón que la fecha comercial) |
| P1-4 | La marcha atrás no era ejecutable de punta a punta | **Reescrita entera**: orden inverso real, todas las piezas, el cuerpo original de la sanción embebido y verificado por huella. **Probada contra producción: tren completo + rollback ⇒ las 3 huellas vuelven al original byte a byte, 0 columnas residuales** |
| P1-5 | Las 9 migraciones seguidas dejaban caído el alta administrativa | La obligatoriedad salió de `migrations/` → **`snippets/APLICAR-TRAS-EL-FRONT-…`** (mismo patrón que la numeración aparcada) |
| P2-1 | Anclas sensibles a comentarios | Residual aceptado: 3 cuerpos no versionados en el repo se validan solo por huella; anotado |
| P2-2 | El DROP del CHECK de audit_log sin validar | Preflight: nombre + forma + no-re-run antes del DROP |
| P2-3 | El relleno rompía un `db reset` limpio | Base sin contratos ⇒ relleno y postflight se OMITEN en voz alta |

**⚠️ SESIÓN PARALELA (29/08 por la tarde):** mientras se corregía, otra sesión publicó
`20260828205112` y `20260829175638` (gestión de cartera); la segunda **reemplazó
`crear_contrato`** (`f50b62e1…` → `2699cc72…`). Se verificaron las 18 huellas fijadas: solo
esa cambió, las 4 anclas del parche sobreviven en el cuerpo nuevo, y la `181000` y el
rollback quedaron **re-anclados** a la huella viva. La lección de [sesiones-paralelas-deploy]
aplicada en vivo: contrastar hash vivo ANTES de publicar.

**Estado final del tren (9 migraciones + 1 aparcada):** `180000 → 180500 → 181000 → 181500 →
182000 (6 fn CRM) → 182200 (núcleo) → 182300 (9 fn portal) → 182500 → 182800` y
`snippets/APLICAR-TRAS-EL-FRONT` para después del front.

**Validación final (29/08, todo deshecho):** corrida A (tren + 7/7 comportamiento) y
corrida B (tren + marcha atrás completa, huellas originales verificadas).

**✅ EN PRODUCCIÓN (2026-08-29, «mergea todo»).** Registro: 156 → **166** migraciones (las
10 registradas CON su cuerpo en `statements`, cerrando la deuda de las versiones mudas).
Orden ejecutado: 9 migraciones → verificación por conteo y sonda (Adelayda PEN 383 600 en
el ranking vivo; los dos candados rebotan P0409) → advisors **0 ERROR** → **integración de
la rama paralela del vivo** (`fb7e53d`, 12 commits; 2 conflictos triviales; 2439/2439
pruebas post-merge) → release `crm-20260829T182429Z-6088501b533d` desplegado a
crm.miavance.com y verificado (version.json nuevo, hashes byte a byte, asset 200, ZIP 404)
→ F3.7 movida de snippets a `20260829183000`, publicada y registrada: la obligatoriedad
está viva y la rama de transición, muerta.

**Decisión de Miguel (29/08): SOLO ACTIVOS en el alta.** El selector ofrece únicamente a
quien está trabajando y `crear_contrato` lo exige (`e.activo`); la venta vieja de alguien
que se fue entra por la reasignación de gerencia (que sí acepta inactivos, con motivo).

---

## 20260828210351 · `crm_gestion_cartera_autorizacion_integral`

🟡 **PREPARADA Y VERIFICADA EN UN CLON DESECHABLE · NO DESPLEGADA.** Al
cierre de esta entrada, producción continúa intacta sobre el release R5 y la
versión `20260828210351` no está registrada en su historial remoto. Esta fila
documenta un candidato; no autoriza ni afirma una aplicación productiva.

La migración corrige integralmente el límite de autorización de Gestión de
cartera sin cambiar su semántica comercial: Analista conserva únicamente su
cartera; Supervisor opera la cartera de su árbol; Gerencia conserva alcance
global; Directorio obtiene lectura comercial global, pero nunca banca ni
acciones de escritura. La pareja de roles Portal/CRM queda fail-closed:
`Directorio` solo puede corresponder a
`crm.equipo.rol_crm = 'directorio'`, y la
migración aborta si la reasignación de subordinados hacia la Gerencia real no
es unívoca.

Controles incorporados:

- ámbito de clientes centralizado en `private.cliente_ids_visibles_crm()`,
  incluida la recuperación de clientes aún no asignados por `creado_por`, solo
  dentro del árbol autorizado;
- detalle seguro mediante `crm.cliente_detalle_fn(uuid)`, sin lectura directa
  de `public.perfiles`, con cero filas fuera de ámbito y domicilio/banca
  redactados para Directorio;
- alta de tareas validada por el servidor con responsable canónico y sin
  depender de la RLS de `public.perfiles`;
- preflight de `tareas_insert` con las dos huellas históricas conocidas; un
  drift de autorización aborta antes de reemplazar la policy;
- invariantes Portal/CRM protegidas también ante escrituras posteriores;
- numeración automática de contratos serializada con advisory lock, manteniendo
  la restricción única como defensa final;
- funciones privilegiadas con `search_path = ''`, helpers privados sin acceso
  de API y RPC pública sin `EXECUTE` para `PUBLIC`/`anon`.

Evidencia ya obtenida sin tocar producción: preflight contra huellas de las
funciones vivas; convergencia explícita desde la forma versionada de 10 columnas
y la captura viva de 12 columnas de `crm.clientes_basicos_fn`; aplicación y
postflight de la migración exacta en una base temporal de esquema completo; gates
`GESTION_CARTERA_AUTORIZACION_TX_OK`, `CREAR_CONTRATO_CARTERA_OK`,
`GESTION_CLIENTES_RENOVACIONES_OK`, `TAREAS_TX_OK`, `CARTERA_KEYSET_TX_OK` y
`PERIODO_COMERCIAL_CONTRATOS_OK`, más `REPORTE_DERIVACIONES_TX_OK`; matriz Data API/RLS completa con
1.192/1.192 aserciones; dos altas automáticas concurrentes con números
consecutivos y espera de mutex observada, una carrera tarea/reasignación con
destino final canónico y una carrera causal de derivaciones. Los tres runners
rechazan URL con query/hash, exigen un nombre desechable `gcar_*`, neutralizan
variables libpq hostiles y solo terminan backends que coinciden por PID,
aplicación, base, usuario y tipo. Sus sondas son UUID propias, el cleanup es
exacto y fail-closed; la carrera de tareas exige además que
`pg_blocking_pids(S2)` contenga el PID exacto de S1. La corrida integrada con
falla inyectada conservó
idéntico un vector de 19 conteos globales y dejó cero sesiones rastreadas;
mutante de drift de `tareas_insert` rechazado por el preflight; `db lint` sin
errores en los esquemas propios; typecheck, build, 182/182 archivos con
2.439/2.439 unitarias y
Playwright completo con 110 aprobadas, 26 omitidas por diseño y 0 fallas. Dos
pases independientes cerraron los falsos verdes encontrados en los oráculos.
El escaneo formal `0e12f638-1ff3-4e08-a49d-5606320c3159` reportó un MEDIUM por
domicilio visible a Directorio; fue corregido y verificado como `fixed` sin
degradar la lectura legítima de Supervisor/Gerencia ni el ocultamiento a un
Analista ajeno.
La huella final de la migración es
`18df2b2a048b7404a857f743874294dddad589724ae55c9aa5c2e13e585a1af8`.
Los advisors productivos son una línea base de solo lectura: 0 errores y avisos
preexistentes; todavía no son evidencia postdeploy.

**Orden obligatorio de publicación: servidor primero.** Aplicar y leer de
vuelta esta única migración; recargar el esquema de PostgREST; confirmar que la
RPC nueva resuelve, sus ACL/RLS y postflight permanecen verdes, y repetir
advisors. Solo después puede publicarse el frontend que consume
`crm.cliente_detalle_fn`. El cierre requiere smokes autenticados separados de
Analista, Supervisor, Gerencia y Directorio, además de verificar que `anon`
sigue bloqueado.

**Pendiente únicamente para una eventual publicación autorizada:** dry-run
remoto, aplicación server-first, readback/postflight, advisors posteriores,
publicación del frontend y smoke autenticado productivo. Hasta completar esos
puntos no debe describirse el candidato como desplegado ni listo en producción.
---

## 20260829190500–192500 · FASE 4 del P-055 — «una sola calculadora de capital»

**Estado: ✅ EN PRODUCCIÓN (29/08 noche, orden de Miguel: «que ya nada quede a medias»).**
Registro: 166 → **171** (las 5 con `statements`). Los 4 oráculos embebidos pasaron EN el
momento de publicar (la paridad fue condición del commit, no una promesa). Sonda posterior:
núcleo+ventana vivos y cerrados a la API · pantalla de agosto = crudo al céntimo
(PEN 3 865 495) · 9 consumidores leyendo del núcleo. Advisors: **0 ERROR** (139 WARN
preexistentes; ninguno sobre los objetos nuevos). Auditor RLS: 15 hallazgos, TODOS
aplicados antes de publicar (huellas ancladas a los cuerpos vivos, foto de supervisor y
carne obligatoria en los oráculos, ventanas 1900/9999, postflight en 2 monedas + coops,
casos nuevos en el gate, OK de Miguel escrito en la 191500). **Codex F4 llegó (NO-GO: 4 P0 + 4 P1 + 2 P2) y su corrección YA ESTÁ EN
PRODUCCIÓN** — `20260829200000_crm_f4_e_correcciones_codex` (registro → **173**, junto a
`20260829195528_crm_ficha_360_scope_historial` de la sesión paralela, verificada sin cruce
con capital):

| Hallazgo | Qué era | Corrección |
|---|---|---|
| **P0-1** | El núcleo podía sumarse mezclando familias (contrato 100k + desglose 80k+20k = 200k) | Fila-hecho con **`medida`** (`stock`/`desglose`/`nula`) y **la ventana la EXIGE**: mezclar ya no es un descuido posible. Ningún consumidor actual mezclaba (todos filtran por tipo) |
| **P0-2** | Las cifras gerenciales/AUM **excluyen cooperativas** — igual que ayer | **NO es bug: es la omisión histórica que la paridad conservó a propósito.** Incluirlas cambia números de pantalla → **DECISIÓN DE MIGUEL** (abajo) |
| **P0-3** | 1900/9999 no era «todo el tiempo»; vencimientos tenía suelo 2020 | **±infinity** de verdad en todas; postflight prohíbe ventanas mágicas (exceptuando el suelo legítimo de fecha de nacimiento) |
| **P0-4** | El contrato temporal mezclaba día-local (contratos) e instante (coops) | **Escrito en el núcleo**: llamar con medianoches de Lima o ±infinity; para los llamadores reales es equivalente (Codex lo confirmó) |
| P1-6 | F4.c dejó caer 3 funciones de STABLE a VOLATILE en silencio | `ALTER FUNCTION … STABLE` ×3, con postflight |
| P2-9 | `en_roster` miraba cualquier revisión de metas | Solo la revisión **vigente** (la mayor) |
| P1-5 | Rendimiento del bloque por-lead (hipótesis de plan) | Se mide con EXPLAIN en banco tras el 10/09; panel de gerencia con cohortes chicas hoy |
| P1-7 | La ventana pierde los 13 sin dueño para no-globales | La ventana no tiene consumidores; su semántica de visibilidad se decide con el primero |
| P1-8 | `vendedores_fn` cambia por transitividad | La paridad de `cartera_por_vendedor` quedó fotografiada; el oráculo punta a punta llega con su migración post-10/09 |
| P2-10 | Hipótesis de solape contrato+coop del mismo lead | Consulta de comprobación anotada para el banco post-cierre |

**✅ DECISIÓN A DE MIGUEL (30/08): «las cooperativas cuentan en todo» — EN PRODUCCIÓN**
(`20260829201500` + etiqueta `20260829202000`; registro → **175**). Ruptura de paridad
DELIBERADA con oráculo de DELTA: cada cifra nueva = la vieja + las coops, AL CÉNTIMO.
Verificado en vivo: AUM PEN **17 947 313,12 → 18 212 113,12** (+264 800 exactos) · agosto
muestra **S/ 264 800** bajo su propia etiqueta `cooperativa` · el ranking del Directorio
acredita las coops a SU analista. Fuera, en voz alta: top de clientes (una coop no tiene
cliente de portal) y el resumen de cartera (gestión operativa de contratos) — si Miguel los
quiere, es otra decisión de pantalla.

**Decisión original (histórica):** tu decisión 4 dice «las cooperativas SON parte
del capital», y el cierre/conversiones ya las cuentan. Pero `metricas_capital_mes_fn`, el
AUM del Directorio y los resúmenes de cartera **nunca las contaron**, y la paridad byte a
byte lo conservó. ¿Deben esas pantallas empezar a incluirlas (los números SUBEN: hoy
S/ 264 800 vigentes), o el AUM/capital-del-mes es solo contratos Avance? Con la `medida` y
la pierna cooperativa ya en el núcleo, encenderlo es UNA línea por pantalla.

Orden de Miguel (29/08): *«yo quiero ver todo ya, no me interesa la fecha, lo que necesito es crear el sistema»* — la Fase 4 se construye y publica ya, con UNA línea de ingeniería: **el motor del sellado no se toca** con el primer sellado a 11 días (`produccion_mes_por_vendedor`, `cerrar_periodo`, `registrar_ajuste_si_mes_cerrado` migran justo después del 10/09).

| Versión | Qué hace |
|---|---|
| `190500` F4.0 | **El núcleo**: `private.capital_episodios(ini, fin, global, visibles)` — filas-hecho (pierna contrato ¬demo · pierna desglose renovado/adicional con el vendedor CONGELADO de la operación · pierna cooperativa con anuladas a 0). Columnas extra que la paridad exigió: `fecha_vencimiento`, `lead_id`. + `private.capital_autorizada` (la ventana). Ambas DEFINER, `search_path=''`, **sin grants a la API**. Postflight: AUM del núcleo = crudo al céntimo. |
| `191000` F4.a | `metricas_capital_mes_fn` + `metricas_vencimientos_fn` consumen el núcleo. **Oráculo embebido**: md5 del payload por gerencia Y por un vendedor real, antes/después, en la MISMA transacción — si difiere un byte, la migración aborta. |
| `192000` F4.b | `resumen_cartera_clientes_fn` + `contratos_por_periodo_comercial_fn` (hechos del núcleo, descriptivos por JOIN al contrato) + `metricas_cartera_por_vendedor` (el dinero del núcleo; los CONTEOS de operaciones siguen del registro). `metricas_cartera_fn` hereda por transitividad (consume a la tercera) y no se toca. |
| `191500` F4.c | Las 3 del Directorio. **Semántica conservada a propósito**: el ranking del Directorio agrupa por el ASESOR DEL CLIENTE con rol portal 'analista' — si debe pasar al analista que cierra, es decisión de pantalla de Miguel, no efecto colateral. La cobranza (cuotas) no es capital y sigue leyendo cronograma. |
| `192500` F4.d | Los 3 bloques de capital de `metricas_conversiones_implementacion` (por lead / totales / por analista) via **6 trasplantes anclados** (huella + cada ancla exactamente 1 vez). Oráculo con 3 variantes (ago-todos, ago-referido, jul-todos). |

**Fuera de este tren, con razón dicha:** las 3 del motor del sellado (arriba) · `metricas_vendedores_fn` (su dinero ya es DERIVADO de payloads del cierre: dominio del sellado) · `dashboard_admin_metricas` (INVOKER: no puede llamar al núcleo sin cambiarle la forma de seguridad — va con el cierre de fase) · `metricas_reuniones_implementacion` (su capital cuelga del enlace muerto `leads.contrato_id` y suma vacío; migrarlo CAMBIARÍA el payload).

**Front verificado (paso 4 del método):** ninguna pantalla recalcula capital de los payloads migrados; el pipeline es métrica aparte (decisión 16).

**Trampas nuevas del ciclo:** `returns setof <función>` no existe (TABLE explícita) · los `DEFAULT` de parámetros no se pueden quitar con `create or replace` (calzar firma) · las temp tables del dueño NO se leen NI escriben bajo `set role` (capturar en variables, escribir tras `reset`) · una `private.*` se fotografía como postgres CON claims (sin `set role`: no tiene EXECUTE para authenticated, y su gate lee `auth.uid()` igual).

**Pendiente:** veredictos auditor-rls + Codex → publicar → registrar con `statements` → sonda + advisors.


---

## 20260829210000–211000 · FASE 4 h/i — «terminemos la calculadora»: las 8 piezas finales

**Estado: ✅ EN PRODUCCIÓN (madrugada del 30/08). Registro → 177. LA FASE 4 ESTÁ COMPLETA.**

| # | Pieza | Cómo quedó |
|---|---|---|
| 1 | `produccion_mes_por_vendedor` → núcleo | Trasplante anclado de sus DOS fuentes crudas; TODA la lógica de atribución intacta. **El juez: ensayo del cierre completo con motor viejo y nuevo — foto sellada IDÉNTICA (`e59a303b…`, 18 personas)** |
| 2 | `cerrar_periodo` | Sin cambio de cuerpo: su capital ya es derivado del motor → alimentada por transitividad, y juzgada por el mismo ensayo |
| 3 | `registrar_ajuste_si_mes_cerrado` | Rama de contratos → núcleo. La rama de coop ANULADA queda cruda POR SEMÁNTICA (el núcleo carga el capital que existe; la deuda necesita el monto original de lo anulado) — escrito en la migración |
| 4 | `metricas_vendedores_fn` | Oráculo de punta a punta en F4.h: payload íntegro byte a byte |
| 5 | `dashboard_admin_metricas` | INVOKER→DEFINER con gate explícito `es_gestor_cartera()` (la misma autoridad que la RLS le daba de facto) + núcleo. Payload del admin byte a byte |
| 6 | `metricas_reuniones_implementacion` | El capital deja el enlace muerto y bebe del núcleo (regla del panel de Conversiones). El payload salvo capital: byte a byte. **El 0 de hoy es verdad del dato** (no existe aún ninguna cadena reunión→conversión, medido); el CABLE quedó probado con un lead real |
| 7 | **Trinquete = 0** | `scripts/trinquete-capital.sql` con tope CERO que no puede subir; verificado en vivo: 0 calculadoras crudas fuera del núcleo en crm+public+private |
| 8 | Deudas de Codex | Rendimiento MEDIDO en vivo: panel Conversiones 241–246 ms, vendedores 74 ms (hipótesis P1-5 refutada a escala actual; re-medir a 10k) · solape contrato+coop: **0 casos** (P2-10 refutada) |

**Trampa nueva:** `request.jwt.claims` puesto por un oráculo VIVE hasta el fin de la
transacción — un ensayo del cierre posterior en la misma tx sella como «manual»
(`automatico=false`). Limpiar con `set_config('request.jwt.claims','',true)` al salir.

---

## 20260829230000 · FASE 1.4 — «la regla que obliga a las que vengan»

**Estado: ✅ EN PRODUCCIÓN (29/08, junto con la F1.5). Registro → 178.**

**Por qué existe.** El arquitecto de servidor de Miguel señaló que la Fase 1 dejó
su propia meta a medias. Medido contra producción, de sus tres ejemplos **dos no
se sostienen** y el cuarto punto —el estructural— es correcto y es el que vale:

| Afirmación | Veredicto medido |
|---|---|
| «`crm.operaciones_cartera` puede cambiar sin dejar rastro» | **REFUTADA.** No puede cambiar en absoluto: `trg_operaciones_cartera_00_append_only` (BEFORE UPDATE OR DELETE) lanza excepción siempre, y por la API solo existe `SELECT:authenticated`. La única puerta es el arrastre al borrar un contrato, que además rebota si el mes está cerrado. **Hueco real, pequeño:** ese borrado no dejaba copia del contenido |
| «`usuario_eventos` y `novedades_leidas` nacieron después del 28» | **FALSA.** 07/08 (`20260807203740`) y 21/08 (`20260821222348`) |
| «`agenda_ics` y `suscripciones_push` sin auditoría» | **CIERTA** (él mismo dice que pesan poco) |
| «F1 arregló las tablas que existían, no instaló la regla para las que vengan» | **CIERTA, y es el hallazgo bueno.** Los 6 event triggers vivos son de Supabase; ninguno nuestro |

Dato que le da la razón por otro lado: la única tabla nacida después del 28
(`crm.reasignaciones_analista`, F3.4) nació **con** rastro — pero por memoria del
que la escribió, no porque el servidor lo exija.

**Lo que instala, en tres filos:**

| Filo | Pieza | Qué hace |
|---|---|---|
| 1 | `private.tablas_sin_rastro()` | La regla DENTRO del servidor: tablas de crm/public sin auditor y sin exención. Debe dar CERO. Cubre `relkind in ('r','p')` (particionadas incluidas; hijas fuera: heredan el trigger del padre) |
| 1 | `private.auditoria_exenciones` | La lista blanca deja de vivir en la memoria de nadie. CHECK de razón ≥ 40 caracteres: sin razón de verdad, no entra. Dos filas: `crm.usuario_eventos` (es la bitácora, y su id BIGINT rompería `log_audit_crm`) y `public.novedades_leidas` (marca de «leído») |
| 2 | `private.vigia_auditoria()` + cron `crm-auditoria-vigia` (06:29 UTC) | Mira el ESTADO a diario y abre/cierra alertas en `private.auditoria_alertas`. **Sustituye al event trigger que NO se puede crear:** `postgres` no es superusuario en este proyecto (solo bypassrls; los 6 event triggers vivos son de `supabase_admin`) |
| 3 | `scripts/trinquete-auditoria.sql` + `npm run gate:auditoria` | No deja publicar con la regla rota **y** compara la lista blanca VIVA con la escrita en el repo: una exención metida a mano en la base también pone el gate en rojo |

**Los tres huecos cerrados:** `crm.operaciones_cartera` (con `log_audit_crm`: es
dinero, se quiere ver entero) · `crm.agenda_ics` y `public.suscripciones_push`
con un auditor nuevo.

**🔴 Por qué esas dos no usan el auditor normal:** `public.audit_log` lo lee
CUALQUIER `es_admin()` (política `audit_log_admin_select`) y lo expone
`bandeja_actividad`. El token ICS hoy solo lo ve su dueño por RLS y las claves
push nunca salen del portal: copiarlos en claro AMPLIARÍA el círculo que ve un
secreto. `private.log_audit_sin_secretos` guarda `***:` + 8 de md5 — se ve QUE el
secreto cambió, nunca CUÁL es. Verificado en lectura: oculta el valor, respeta lo
no secreto y deja los NULL como NULL.

**Dos defensas que no estaban en el plan y salieron de medir:**
- El `UPDATE` de `suscripciones_push` se acota a las columnas con significado:
  `actualizado_en` se toca en cada visita y habría enterrado la auditoría en ruido.
- `audit_log.usuario_id` es FK a `perfiles`: un actor de Auth todavía sin perfil
  habría hecho fallar el INSERT **y con él la operación de negocio**. El auditor
  guarda sin actor antes que tumbar lo que audita.

**El mutante** (`scripts/trinquete-auditoria-mutante.sql`, `npm run gate:auditoria:mutante`)
rompe la regla de tres formas y exige que cada filo la cace: tabla nueva sin
rastro (la regla), su alerta (el vigía) y una exención colada a mano (el espejo
del repo). Todo dentro de un bloque que se deshace solo.

**Gate probado en ROJO antes de aplicar:** con la base tal cual, cazó exactamente
`crm.agenda_ics, crm.operaciones_cartera, public.suscripciones_push`.

**Trampa nueva:** con `search_path=''`, `coalesce` y `current_user` NO llevan
prefijo `pg_catalog` — no son funciones de catálogo sino construcciones del
parser, y `pg_catalog.coalesce(...)` aborta la migración entera.

**Probada ENTERA antes de tocar producción, en un espejo local desechable**
(misma imagen 17.6.1.105, stubs en `scripts/espejo-f1-4-stubs.sql`):

| Prueba | Resultado |
|---|---|
| La migración aplica | ✅ postflight en verde |
| El postflight sirve | ✅ **cazó un fallo del propio espejo** (`public.perfiles` sin auditor) antes de dar verde |
| Trinquete | ✅ 0 tablas sin rastro · lista blanca alineada |
| Mutante (3 filos) | ✅ cazado: la regla lo vio, el vigía lo anotó, el espejo delató la exención colada |
| Secretos de punta a punta (`scripts/prueba-secretos-f1-4.sql`) | ✅ **0 fugas**: alta+rotación+baja del token ICS y alta+cambio+baja de un dispositivo dejan 6 movimientos auditados con el valor sustituido por `***:` + 8 de md5. El toque de `actualizado_en` NO cuenta (6, no 7). El dinero de cartera sí deja rastro |
| Marcha atrás (`scripts/rollback-f1-4-p055.sql`) | ✅ deja el servidor como estaba **y conserva las 7 filas de auditoría ya escritas** (un rastro no se borra) |
| Reaplicación tras la marcha atrás | ✅ idempotente |

**Trampa nueva (la cazó la marcha atrás):** dentro de un agregado,
`string_agg(x, ', ' order by 1)` ordena por la CONSTANTE 1, no por la columna —
la lista sale desordenada y una comparación exacta falla sin motivo real. Hay que
nombrar la expresión: `order by n.nspname || '.' || c.relname`.

---

## 20260829233000 · FASE 1.5 — enmienda de la F1.4 tras la auditoría

**Estado: ✅ EN PRODUCCIÓN (29/08). Registro → 179.**

La F1.4 se auditó **antes** de aplicarse y volvió con tres bloqueantes. Como no
se edita una migración ya versionada, la corrección viaja en su propia migración
y las dos se publican juntas y en orden.

| # | Lo que la auditoría rompió | Cómo queda |
|---|---|---|
| 1 | 🔴 **La regla solo preguntaba «¿hay algún trigger?»**, no «¿audita de verdad?». Medido: **9 tablas** que el gate habría dado por buenas tienen la auditoría a medias — metas y políticas de SLA sin UPDATE ni DELETE; los ledgers de asignación de leads sin DELETE | La regla exige trigger **activo**, **por fila**, auditor **por OID** (una función señuelo con el mismo nombre pasaba) y **los tres verbos**. La migración completa las nueve añadiendo solo el verbo que falta, sin tocar ningún trigger vivo |
| 2 | 🔴 **El ruido que la F1.4 decía evitar no se evitaba.** El portal guarda la suscripción con un `upsert` que lista TODAS las columnas en el SET, y lo hace en CADA carga del panel: un `UPDATE OF` dispara por estar la columna en el SET, cambie o no. Con 216 dispositivos activos eran cientos de filas idénticas al día | Dos triggers: alta/baja sin condición, y cambios con un `WHEN` que compara valores de verdad. El postflight exige el WHEN **y** que no mencione la columna de reloj |
| 3 | 🔴 **La lista de secretos era global y fija** → fail-open el día que alguien colgara el auditor de otra tabla | Las columnas van como **argumentos del trigger**; sin argumentos, el auditor se niega a correr. El postflight lo verifica |
| 4 | La defensa anti-FK estaba solo en el auditor nuevo, y la tabla del **dinero** cuelga del de siempre | El mismo rescate en `log_audit_crm`, **anclando su md5 vivo** (`461846328…`) antes de tocarlo. Cambia también su `search_path` a `''` (postura del resto del servidor): declarado, y el rollback restaura la definición original al byte |
| 5 | `public.audit_log` estaba excluida **dentro** de la función: una segunda lista blanca que nadie vigilaba | Pasa a ser exención declarada con su razón. `public.schema_migrations` se cae: no existe en `public` |
| 6 | El interruptor que apaga una auditoría no dejaba rastro | La tabla de exenciones **se audita a sí misma**, y un **sello** de la lista permite al vigía abrir alerta si alguien la toca fuera del repo |
| 7 | Un `id` no-uuid abortaba la operación auditada | El cast va protegido en los dos auditores |

**🔴 LA TRAMPA MÁS CARA, y la que invalidaba el gate entero:** el canal
`supabase db query` **NO transporta los `raise notice`** (medido: un bloque que
solo hace notice devuelve `{"rows": []}` y código 0). El gate buscaba
«MUTANTE CAZADO» en un aviso → **nunca habría podido ponerse verde**, y el verde
del trinquete era «ausencia de error», no una afirmación. Ahora **el veredicto
viaja como FILA** (`TRINQUETE_AUDITORIA_OK`, `F1_5_APLICADA`,
`MARCHA_ATRAS_F1_4_F1_5_OK`) y el mutante **termina en `raise exception`**, que
además arregla el segundo bloqueante: así su DDL de prueba **se deshace entero**
en vez de quedar confirmado en producción (con su recarga del esquema de
PostgREST en cada corrida).

**El mutante ahora tiene CUATRO filos** (antes tres): tabla sin rastro · **tabla
con rastro a medias** (el fallo real que la auditoría encontró) · el vigía · y
una exención colada a mano contra el sello.

**Ciclo completo probado en el espejo local**, con el auditor real de producción
replicado al byte (md5 `461846328…`, incluido su `search_path 'public','crm'`):

| Paso | Resultado |
|---|---|
| F1.4 → F1.5 | ✅ ambas aplican; el ancla de md5 se prueba de verdad |
| Trinquete | ✅ `TRINQUETE_AUDITORIA_OK` · 0 sin rastro · 3 exenciones |
| Mutante | ✅ `MUTANTE_CAZADO` por los cuatro filos, sin dejar nada escrito |
| Secretos | ✅ 6 movimientos auditados, **0 fugas**, el toque de reloj no cuenta |
| Puertas (`scripts/prueba-permisos-f1-5.sql`) | ✅ ni anon, ni authenticated, ni service_role, ni **PUBLIC** alcanzan la maquinaria nueva; las 3 tablas con RLS y sin políticas |
| Marcha atrás | ✅ vuelve a la foto original, restaura el auditor a su md5 y **conserva las 7 filas de rastro ya escritas** |

**Corrección al ledger de la F1.4:** la frase «gate probado en ROJO… cazó
exactamente las 3 tablas» era cierta de una versión anterior del trinquete (que
llevaba la consulta en línea); con el trinquete actual, sin la regla aplicada, lo
que devuelve es «la regla no está en el servidor». Y el mutante de aquella
versión **confirmaba** en vez de deshacerse.

### Verificación en producción (29/08, tras publicar F1.4 + F1.5)

| Comprobación | Resultado |
|---|---|
| Registro | **179** versiones, las dos nuevas **con cuerpo** |
| La regla | **0 tablas sin rastro completo** en crm+public |
| Lista blanca | 3 exenciones (`crm.usuario_eventos`, `public.audit_log`, `public.novedades_leidas`), **sello cuadra**, 0 alertas abiertas |
| Coberturas completadas | **las 9 exactas** (`trg_audit_*_completa` en metas ×3, políticas SLA ×2, ledgers de leads ×4) |
| Tablas auditadas | 42 → **45** |
| Vigía | `crm-auditoria-vigia` activo, 06:29 UTC |
| Gate + mutante contra producción | ✅ verde: «0 tablas sin rastro completo · 3 exenciones» y «mutante cazado por los cuatro filos» |
| Advisors de seguridad | **0 ERROR** (169 avisos, ninguno nuevo salvo los 3 INFO `rls_enabled_no_policy` de las tablas nuevas — que es justo el deny-by-default buscado) |
| **Humo del flujo VIVO del portal** (`scripts/humo-portal-auditoria-f1-5.sql`, en transacción deshecha) | ✅ el alta deja rastro · **el guardado repetido de cada carga del panel NO ensucia** (la corrección del `WHEN` funciona con el `upsert` real) · un cambio de verdad sí queda · **0 fugas** de la clave push |

---

## 20260829235000 · FASE 1.6 — la regla a prueba de señuelos (auditoría adversarial de Codex)

**Estado: ✅ EN PRODUCCIÓN (29/08). Registro → 180.**

Codex atacó la F1.4 y devolvió **NO-GO con 9 hallazgos**. Dos avisos sobre su
veredicto: auditó la versión **anterior a la enmienda F1.5**, y **no pudo leer
producción** (su CLI se quedó sin token: `LegacyPlatformAuthRequiredError`), así
que sus afirmaciones son sobre el código, no medidas. Al medirlas, dos de sus
correcciones había que cambiarlas.

| Su hallazgo | Veredicto | Qué se hizo |
|---|---|---|
| #1 F1.4 y los gates no forman unidad desplegable | **Ya resuelto** | Se publicaron juntas y el gate quedó verde contra producción. Su «squash» no aplica: este repo no edita migraciones publicadas |
| #2 La regla acepta triggers decorativos, en modo réplica o señuelos | ✅ **CIERTO, arreglado** | Se exige `tgenabled in ('O','A')`, AFTER, `FOR EACH ROW`, sin `UPDATE OF` parcial, auditor **por OID** y **SECURITY DEFINER con search_path fijo** |
| #3 Universo con huecos (particiones hoja, UNLOGGED, foráneas, materializadas) | ✅ **CIERTO, arreglado** | `relkind in ('r','p','f','m')` y `relpersistence in ('p','u')`, hijas incluidas. Preventivo: hoy no existe ninguna (48 tablas, todas normales) |
| #4 El mutante no prueba el gate, prueba sus piezas | ✅ **CIERTO, y era grave** | El gate entero vive en `private.assert_auditoria()`; cada filo del mutante **ejecuta esa misma función** y exige que reviente con P0001 |
| #5 El upsert del portal ensucia la auditoría | **Ya resuelto en F1.5** y MEDIDO contra el flujo vivo | Se mantiene, pero el filtro se muda DENTRO del auditor para poder exigir triggers sin `WHEN` |
| #6 El cron no se verifica de verdad | ✅ **CIERTO, arreglado** | Se comprueba nombre, usuario, base, horario y comando exactos, sin duplicados de otro usuario — en la migración **y** en el gate |
| #7 El enmascarado es un oráculo | ✅ **CIERTO, arreglado** | `***` plano, sin huella derivada. Y se enmascaran también `user_agent` y `dispositivo`: la huella del aparato de un cliente no tiene por qué verla cualquier admin |
| #8 Las razones de la lista blanca no se gobiernan | ✅ **CIERTO, arreglado** | `on conflict do update` de la razón, y la huella del sello incluye el **texto** de cada razón |
| #9 Falta prueba de comportamiento | **Parcial** | Hecha en F1.5 contra producción en transacción deshecha; queda la matriz por roles, que se cubre en el espejo |

**⚖️ DOS CORRECCIONES SUYAS QUE LA MEDICIÓN OBLIGÓ A CAMBIAR:**

1. Pedía exigir `proconfig @> ['search_path=""']`. **Medido: `public.log_audit_change`
   vive con `search_path = 'public, pg_temp'`** desde siempre — aplicar su regla
   habría marcado como rota media base sin ganar seguridad. Se exige search_path
   **fijo**, no vacío.
2. Pedía **prohibir el `WHEN`** en los triggers de auditoría. **Medido:
   `public.cronograma_pagos` lo usa desde antes de esta fase, a propósito.**
   Prohibirlo habría marcado como rota una tabla que audita bien. Solución
   intermedia: se permite, pero **declarado** en `private.auditoria_condicionada`
   con su razón — un compromiso que nadie escribió no vale.

**El mutante pasa de 4 filos a CINCO**, y cada uno ejecuta el gate real:
tabla sin rastro · rastro a medias · **trigger anulado con `WHEN (false)`** (su
señuelo) · exención colada a mano · **vigía apagado**.

**Probado en el espejo** (con `public.cronograma_pagos` y su `WHEN` replicados):
las tres migraciones aplican en cadena, trinquete verde (0 sin rastro · 3
exenciones · 1 condicionada), `MUTANTE_CAZADO` por los cinco filos sin dejar
nada, y la marcha atrás —ya ampliada a F1.6— devuelve el servidor a su foto
original. De paso, la regla nueva **cazó un auditor no-DEFINER en el propio
espejo** antes de dar verde.

### Verificación en producción de la F1.6

| Comprobación | Resultado |
|---|---|
| Registro | **180**, con cuerpo |
| La regla, ya endurecida | **0 tablas sin rastro** · 3 exenciones · **1 condicionada** (`public.cronograma_pagos`) · sello cuadra · 0 alertas |
| Trigger de push | uno solo, `AFTER INSERT OR DELETE OR UPDATE`, sin `WHEN` ni `UPDATE OF`, enmascarando 5 columnas (incluidas `user_agent` y `dispositivo`) |
| Enmascarado | `***` plano: se acabó la huella derivada |
| **El vigía sobrevivió al mutante** | 1 job, activo, 06:29, comando y dueño correctos — el quinto filo lo apaga y la transacción deshecha lo devuelve |
| Basura del mutante | **ninguna** tabla `zzz*` en `crm` |
| Gate + mutante contra producción | ✅ «0 tablas sin rastro completo · 3 exenciones» y «mutante cazado por los cinco filos» |
| Advisors | **0 ERROR** (170 avisos; los 4 INFO `rls_enabled_no_policy` de las tablas de `private` son el deny-by-default buscado) |
| Humo del flujo vivo del portal | ✅ repetido con el trigger unificado: el guardado repetido no ensucia (ahora por el filtro DENTRO del auditor), el cambio real sí queda, 0 fugas |

---

## P-055 · FASE 5.a — UNA SOLA PREGUNTA: «¿es analista VIGENTE?» (2026-08-30)

**Estado: escrita, ensayada tres veces contra producción y DESHECHA. Sin publicar** (registro sigue en **180**).
Dos auditorías completas (auditor RLS + Codex) y **dos NO-GO atendidos enteros**.

**Autorización de Miguel (chat del 2026-08-30):** «*esa parte se puede adelantar sola, es lo único con efecto
sobre datos reales hoy*» · «*pásalo por Codex y el auditor antes de publicar*» · «*dale, hazlo así, y audita
que quede bien*» (sobre la forma de una sola pregunta + trinquete + las siete puertas).
**Alcance sobre `public` con ese OK:** 3 tablas (`contratos`, `cronograma_pagos`, `perfiles`) y 2 funciones
(`puede_ver_contrato`, `productos_inversion_seleccion_fn`), más un `grant` sobre una función de `private`.

| Archivo | Qué hace |
|---|---|
| `migrations/20260830090000_crm_f5_a_una_sola_pregunta_analista.sql` | `private.es_analista_vigente()` + **7 puertas** preguntando eso; candado de borrado en `crm.equipo`; trinquete con exenciones selladas por huella; vigía diario |
| `scripts/rollback-f5a-p055.sql` | Marcha atrás en **dos bloques**: el operativo y, comentado, el histórico exacto que revoca el permiso y reabre el fallo de la F3 |
| `scripts/test-f5a-una-sola-pregunta.sh` + `test-f5a-antes.sql` + `test-f5a-despues.sql` | Aceptación que ejecuta **la migración real** dentro de una transacción que siempre se deshace |
| `scripts/trinquete-analista-vigencia.sql` + `…-mutante.sql` + `gate-analista-vigencia.mjs` | El gate y sus **7 filos**; `npm run gate:vigencia [-- --mutante]` |
| `scripts/registrar-f5a-version.sql` | Registro de la versión **con `statements`** |

### Las siete puertas

`contratos_analista_select` · `cronograma_analista_select` · `perfiles_analista_select` ·
`perfiles_analista_update` · `crm.cliente_detalle_fn` (ficha 360: DNI, correo, teléfono, domicilio y banca
PEN/USD) · `public.puede_ver_contrato` (co-titulares y `contrato_tiene_pagos`) ·
`public.productos_inversion_seleccion_fn` (dos ramas).

### Medido contra producción el 2026-08-30 (todo deshecho)

| | contratos/cuotas/fichas | co-titulares | ficha 360 | productos | ¿ve el contrato? | ¿tiene pagos? | edición |
|---|---|---|---|---|---|---|---|
| Revocada, **antes** | 3 / 39 / 3 | 1 | 1 | 0 filas | **sí** | **sí** | — |
| Revocada, **después** | **0 / 0 / 0** | **0** | **0** | **42501** | **no** | **no** | **0 filas** |
| Analista viva, antes y después | 58 / 549 / 45 (idéntico) | igual | 1 → 1 | 0 → 0 | — | — | **1 fila** |
| `anon`, antes y después | 0 → 0 **sin error** | | | | | | |

**Mutantes de comportamiento:** `m2` (deshacer las dos políticas de lectura) devuelve 3 · `m4` (deshacer la de
edición) devuelve 1 · `m5`/`m6`/`m7` (puerta nueva sin declarar, subir el tope, borrar del equipo) revientan.
**Mutante del trinquete: los SIETE filos ponen rojo el gate** — puerta nueva, **comentario señuelo**, **puerta
mixta**, **vista**, política, **el rol comprobado a mano** y **exención caducada**.
**Corrida B:** tren + marcha atrás → las 4 políticas y las 3 funciones vuelven a su **huella original**, 0
funciones nuevas, vigía retirado y las 9 exenciones conservadas.
**Trinquete de partida:** 9 puertas declaradas y selladas, tope 9, **0 sin declarar**.

### Lo que las dos auditorías cambiaron del diseño

1. **El trinquete medía TEXTO y ahora mide LLAMADAS.** Con `strpos` bastaba un comentario
   (`-- ya migrado a es_analista_vigente`) para desaparecer del radar, y una puerta **mixta** tampoco salía.
   Ahora se quitan comentarios antes de mirar y el ancla es `\mes_analista\s*\(` (inicio de palabra +
   paréntesis). Eso además elimina **tres falsos positivos** que casaban por el nombre de la tabla
   `crm.reasignaciones_analista` y por un comentario: el tope real no era 10, es **9**.
2. **Se vigila también el rol comprobado a mano** (`rol = 'analista'`), que era la forma obvia de esquivar la
   función, y se miran **procedimientos, vistas y todos los esquemas**, no solo funciones de tres.
3. **Cada exención va sellada con la huella de su cuerpo**: si la función cambia, su razón caduca y el gate se
   pone rojo. Y se identifican por `regprocedure`, no por nombre: una sobrecarga nueva no hereda la exención.
4. **Orden de la transacción**: primero todo lo que no bloquea tablas de negocio; los 4 `alter policy` y el
   trigger, al final. `lock_timeout` limita lo que se **espera**, no lo que se **retiene**.
5. **El ensayo ya no apaga ningún trigger de producción** (apagarlo tomaba ACCESS EXCLUSIVE sobre `perfiles`
   durante todo el ensayo y habría congelado el portal): da de alta dos fichas nuevas y un co-titular temporal.
6. Preflight con el **comando exacto** de cada política, `polpermissive` y roles; postflight que exige que la
   pregunta **cruda haya desaparecido**; ACL por `aclexplode(coalesce(proacl, acldefault(...)))`.
7. **RLS en las dos tablas nuevas** y `revoke all from public` en las funciones nuevas.
8. **El vigía existe de verdad**: `crm-vigencia-analista-vigia` a las 06:39, además del gate del repo.

### Trampas nuevas pagadas aquí

1. 🔴 **`perfiles.creado_en` es INMUTABLE** — `trg_proteger_perfiles` hace `NEW.creado_en := OLD.creado_en` en
   silencio. Rejuvenecer una ficha para probar la ventana de 5 h **no ocurre**, y el caso positivo medía 0 filas
   por un defecto del oráculo, no del arreglo.
2. 🔴 **El `search_path` vacío lleva comillas** (`search_path=""`): comprobar `array['search_path=']` falla
   siempre. Tercera vez que este proyecto tropieza con lo mismo.
3. 🔴 **`regprocedure::text` imprime el esquema o no según el `search_path`**: dentro de una función con
   `search_path=''` sale cualquificado, y las identidades declaradas tienen que coincidir letra por letra.
4. 🔴 **Una función SQL valida su cuerpo al crearse**: el helper tiene que existir ANTES de los reemplazos.
5. 🔴 **El censo no puede resolver por `regprocedure` una función que aún no existe** — las piezas del propio
   trinquete se excluyen por nombre dentro de `private`.

### Lo que NO toca, y no es olvido

- `public.es_analista()` sigue igual · las políticas de `es_admin()`/`es_gestor_cartera()` van en el paso 2 de
  la Fase 5 (los 2 admin del Portal no tienen fila en `crm.equipo`) · `proteger_campos_inmutables` queda
  **declarado**: ahí la pregunta sirve para PROHIBIR y añadirle la vigencia relajaría el candado.

### La decisión de Miguel sobre el candado (2026-08-30): **«vamos con la 1, mantén el candado»**

`crm.equipo` queda con candado `BEFORE DELETE` fail-closed, y la baja deliberada sale por una **puerta
declarada**: `crm.purgar_membresia_crm(perfil_id, motivo)` — **solo `service_role`** (revocada a `anon` y a
`authenticated`, comprobado en el postflight), **motivo escrito de 20 caracteres mínimo** y **lápida** en
`private.membresias_purgadas`. La válvula (`crm.purgando_membresia`) se cierra sola dentro de la propia
función: medido, un `delete` suelto inmediatamente después sigue rebotando.

🔴 **Dicho en voz alta:** purgar **sí** devuelve los accesos del Portal a quien estaba revocado. Lo que el
candado impide es el borrado **accidental y silencioso** —la cascada del panel, el script de limpieza, un
`delete` suelto—, que era el camino real. Y hay una segunda red no buscada: purgar a alguien **con historia**
es imposible de todos modos, porque las claves foráneas de los ledgers que le nombran lo rechazan (23503,
medido).

**Dos consumidores adaptados:** `scripts/test-rls.mjs` (las dos retiradas de la membresía fabricada, la de la
prueba y la del `finally`) y `scripts/clean-crm-data.mjs` (purga fila a fila con su motivo). Ambos pasan
`node --check`.

**Y el panel:** el borrado duro de un colaborador con ficha en `crm.equipo` deja de funcionar. La baja es
desactivar, que es la norma que ya estaba escrita.

### Declarado y no cerrado aquí

- **La sesión no se cierra con las puertas:** las 4 personas revocadas siguen con `perfiles.activo = true` y
  `auth.users.banned_until` NULL. Una de las tres cuentas llamadas «DEMO» **inició sesión el 28/08**.
- **Ventana del PDF firmado:** una URL emitida ANTES de la revocación sigue siendo válida 300 s.

---

## P-055 · FASE 6.a — EL NÚCLEO DE CITAS y EL CENSO SELLADO (2026-08-30)

**Estado: ✅ EN PRODUCCIÓN 2026-08-30 (registro 182).** Dos auditorías (auditor RLS + Codex), **dos NO-GO
atendidos enteros** (1 P0 + 9 P1 + 11 P2). Gate y **mutante 10/10 contra producción**; advisors 0 ERROR;
vigía `crm-analitica-lc-vigia` activo 06:49 con su tabla de alertas propia.

**Objetivo de Miguel (fijado por `/goal`):** que cada pregunta sobre leads y citas tenga UNA sola
respuesta en todo el sistema. Contrato con las **5 decisiones firmadas** en el vault.

**Lo que la medición cambió del plan (verificado en vivo):**
- El núcleo de LEADS **ya existía** (`private.conversion_episodios`, de la «conversión única») y las
  pantallas de métricas beben de él directa o **transitivamente**: el SELLO vía
  `conversion_mensual_por_vendedor` → núcleo; `metricas_vendedores_fn` lee `crm.conversion_mensual_fn`.
- La **ventana de 45 días es de la VISTA** (qué convertidos siguen visibles), no de la métrica: la métrica
  ya es mensual y rotulada. La decisión 5 queda cumplida EN LA MÉTRICA; la vista no se toca.
- Para CITAS no había núcleo: la definición canónica vivía incrustada en la pantalla de reuniones.

| Archivo | Qué hace |
|---|---|
| `migrations/20260830120000_crm_f6_a_nucleo_de_citas_y_censo.sql` | `private.citas_episodios` + la pantalla de reuniones bebiendo de él (4 anclas) + censo por LLAMADA + **30 exenciones selladas por huella** + tope solo-baja + vigía 06:49 |
| `scripts/rollback-f6a-p055.sql` | Marcha atrás: reemplazo INVERSO anclado (whitespace exacto) + retirada del trinquete; las tablas de exenciones/tope se conservan |
| `scripts/trinquete-analitica-lc.sql` + `…-mutante.sql` + `gate-analitica-lc.mjs` | `npm run gate:analitica [-- --mutante]`, **7 filos** |
| `scripts/registrar-f6a-version.sql` | Registro de la versión con `statements` |

**Ensayos (30/08, todo deshecho):** paridad del núcleo 11/11 campos · **consumidor 1 con payload
ENTERO idéntico byte a byte (6 011 bytes)** · tren completo: 30 declarados, tope 30, 0 sin declarar ·
corrida B: la pantalla vuelve a su **huella md5 original exacta** · mutante **7/7 filos**.

**Lo que las auditorías cambiaron (NO-GO → arreglado):**
1. 🔴 **P0: el vigía escribía en una tabla que NO EXISTE** (`crm.audit_log`) — y el de la **F5.a tenía el
   defecto idéntico VIVO en producción**. Ahora los dos escriben en `private.vigia_alertas` (RLS on) y el
   **camino de alerta se probó de verdad** en el ensayo (rojo forzado → la alerta aparece → restaurado).
2. **Dos pantallas vivas bajo el mismo rótulo «citas»** (Codex): inteligencia comercial cuenta **leads con
   cita** (83/7) y reuniones cuenta **citas** (40/6). Son preguntas distintas: quedaron **declaradas con la
   verdad** y el rótulo se corrige en la **F6.b del front**.
3. **Dos razones eran FALSAS** y se reescribieron con la verdad: `series_comerciales_fn` guarda una **segunda
   fórmula de conversión** (cohorte sin peso de referido: 2,8 % vs 7,0 %) y `registrar_ajuste_si_mes_cerrado`
   **recalcula el numerador localmente** y replica la rama de coops a mano — ambas ahora **deuda declarada del
   Bloque B**, visibles para siempre en la exención.
4. Detector endurecido: minúsculas, `crm.\s*leads` (comentario borrado deja hueco), `sum(1)`, `prosqlbody`
   vía coalesce, **todos los esquemas de usuario** (fail-closed), exclusión de los núcleos **por OID**
   (`::oid`, no `::text` — un oid numérico jamás igualaba un nombre), SQL dinámico que nombre tareas.
5. **Sello de la lista de exenciones** (F1.6): md5 del agregado, verificado en cada assert + candado
   anti-DELETE. Assert con anti-vacuidad, ACL exacta del núcleo (solo postgres), candados del tope vigilados,
   y **cada consumidor de `citas_episodios` debe estar declarado** (el núcleo sirve filas de toda la empresa).
6. Mutante de **7 → 10 filos** (pantalla que deja de beber DE VERDAD, núcleos renombrados, candado apagado),
   con aislamiento entre filos y mensajes esperados. Rollback que **conserva los candados** y no suelta el
   núcleo si alguien más lo llama. Registrar **fail-closed** (no re-escribe la historia).
7. `test-rls.mjs`: bloque `testCitasNucleo` nuevo (gerencia/lector 200 con forma y anti-vacuidad; comercial,
   supervisor y coordinador 42501; `private.citas_episodios` inalcanzable por PostgREST). Corre en el próximo
   ciclo de banco.

**🔴 Trampas nuevas pagadas:** un reemplazo anclado que borra una cláusula debe llevarse TAMBIÉN el salto y la
sangría previos (línea huérfana = la marcha atrás no vuelve al byte) · el registrador con cuerpo embebido
necesita **etiqueta propia** en su `do` (el cuerpo lleva `$$` y un `do $$` normal se corta en el primero) ·
`oid::text` es un número: comparar contra `regprocedure::text` no iguala jamás.

**⏳ Para la F6.b (front) y la firma de Miguel:** rotular las dos preguntas de «citas» con su apellido
(por vencimiento vs leads con cita), renombrar `conversion_pct` de series a `conversion_cohorte` (o
convertirla), y **la relectura de la decisión 5** (los 45 días eran de la vista; la métrica ya era mensual)
necesita su firma — el ejecutor no cierra decisiones por reinterpretación.

---

## P-055 · FASE 6.c — LAS DOS DEUDAS DECLARADAS, CERRADAS (2026-08-30)

**Estado: escrita y ensayada contra producción (todo deshecho), en auditoría.**

Orden de Miguel: «cerremos las 2 deudas declaradas».

| Deuda | Cierre |
|---|---|
| `series_comerciales_fn.conversion_pct` era una segunda fórmula sin apellido | La clave pasa a **`conversion_cohorte_pct`** (espejo deliberado del front, sin consumidores de la RPC) y el payload gana **`conversion_mensual_pct`**: pedida **A LA CAPA PUBLICADA** (`conversion_mensual_fn` por mes — P0 de Codex: recalcular del núcleo ignoraba la foto del mes sellado, los ajustes pendientes y los dos decimales). Coordinador recibe NULL, no error. `version` 2 |
| `registrar_ajuste_si_mes_cerrado` recalculaba el referido a mano | **EL EPISODIO MANDA** (P1 de Codex): el cierre puede caer a caballo del mes — se localiza el episodio canónico del lead sin depender de `convertido_en`, y de él salen el PERIODO real (re-tomando el cerrojo), el referido y el peso. **0 episodios ⇒ la sanción de conversión vale CERO** (nunca 1 en silencio) + alerta `f6c_ajuste_sin_episodio`; >1 ⇒ excepción de integridad. La rama de coops queda **por semántica de la F4**; su deriva la vigila el trinquete |

**Ensayos (30/08, deshechos):** cohorte agosto **2,8 idéntica** · mensual **VERBATIM de la oficial** (null, null, **7,02** — dos decimales) · referido por episodio canónico en TODOS los convertidos: **0 discrepancias** (y mes del episodio = mes de `convertido_en` hoy) · corrida B v5: las dos huellas crudas **de vuelta al byte** con rollback de LITERALES DE MÁQUINA y trinquete OK 30/30 · smoke ejecutado como gerencia dentro del postflight.

**Dos NO-GO atendidos enteros** (auditor RLS: 4 P1 + P2 de la alerta · Codex: P0 de la «oficial que no era oficial» + P1 del cierre a caballo del mes). 🔴 Trampa nueva: extraer anclas de un archivo con `find(desde=...)` tras un `raise` rebana el ancla EQUIVOCADA — los literales del rollback se generan por máquina desde la propia migración.

Archivos: `migrations/20260830140000_crm_f6_c_deudas_declaradas.sql` · `scripts/rollback-f6c-p055.sql` · bloque de series v2 en `test-rls.mjs` (paridad serie-vs-oficial incluida).

**P2 aceptados con nombre:** para meses SELLADOS la serie mensual recalcula del ledger (hoy converge; si tras el 10/09 Miguel quiere espejo del sellado, es decisión suya) · `EXPLAIN` con p_meses=24 en el próximo banco.

---

## P-055 · FASE 5.b — UNA PREGUNTA POR CAPACIDAD y LOS PARES DECLARADOS (2026-08-30)

**Estado: ✅ EN PRODUCCIÓN (registro 184).** Dos auditorías (auditor RLS + Codex), **dos NO-GO atendidos**.

**4 decisiones de Miguel (firmadas):** D1 registrar/editar ventas = `private.puede_registrar_ventas()`
(admin O miembro comercial vigente del CRM) · D2 catálogo = `private.puede_ver_catalogo_productos()`
(admin O miembro CRM O lector) · D3 cerrar_contrato añade `es_gerencia_crm_activa()` · D4 `private.pares_autoridad`
(9 pares, NULL = sin ficha; GABRIEL/GLORIA declarados) con candados en las dos mitades y válvula `crm.cambiando_par`.

**Lo que cambió por las auditorías:**
- 🔴 **El candado exime `auth.uid() IS NULL`** (service_role, seed, consola postgres) — como
  `proteger_campos_inmutables`: el guardián vive donde hay una PERSONA (el panel, RPC DEFINER con
  auth.uid). Esto arregla el seed del banco, la sonda P04 de `test-rls` y el guion Carlos-Valles de una vez.
- El candado del equipo vigila `rol_crm` **y `perfil_id`** (re-apuntar la ficha).
- Higiene del trinquete F5.a: las 3 gemelas del Portal dejan de nombrar `es_analista` → fuera del censo;
  **tope 9→6**. El rollback las re-declara con la normalización EXACTA del censo (sin `lower`) y **repone
  el tope a 9** saltando el guard solo-baja.
- Candado anti-DELETE/TRUNCATE en `pares_autoridad` (DELETE por fila, TRUNCATE por sentencia — no se pueden
  juntar en un `for each row`).
- Bloque `testCapacidadUnificada` en `test-rls.mjs`.

**Ensayado (deshecho):** GLORIA con las 2 puertas · ALAN simétrico · ROSA catálogo-sí/ventas-no ·
cerrar vendedor-no/gerencia-sí · candado vía panel (auth.uid presente) rebota, consola exenta · corrida B v4:
10 huellas al byte, 9 pares, vigencia 9/9 y analítica 30/30 tras revertir. Advisors 0 ERROR; ambos gates verdes.

**🔴 D1 QUEDA A MEDIAS — F5.c (decisión de Miguel, Opción B «cualquier cliente»):** la pantalla REAL de
contratos usa `crear/actualizar_contrato_con_cuenta_pdf_v2/v3` → núcleo del dinero gateado por **P04**
(`puede_gestionar_cuentas_cliente`, con scope de cartera), no por las 7 gemelas que unificó la F5.b. Para que
la pregunta sea UNA sola de verdad, la F5.c lleva `puede_registrar_ventas()` a los 4 núcleos del dinero
(`crm.crear/actualizar_contrato_con_cuenta`, `public.crear/actualizar_contrato`) **quitando el scope de
cartera** (Opción B firmada: cualquier analista, cualquier cliente; la venta cuenta a quien la cierra por el
campo `analista_cierre` de la F3). ALAN queda como analista normal SIN código especial (la puerta mira la
membresía del CRM). Va con auditoría propia por ser el camino del dinero.

## P-055 · FASE 5.c — LA REGLA DE VENTAS, EN EL NÚCLEO DEL DINERO (2026-08-30)

**Estado: ✅ EN PRODUCCIÓN (2026-08-30, registro 185).**
Migración `20260830190000_crm_f5_c_ventas_al_nucleo_del_dinero.sql`. Es el CAMINO DEL DINERO
(creación/edición de contratos) → auditoría propia (auditor RLS + Codex).

**Qué hace (Opción B firmada por Miguel):** los 4 núcleos del dinero —`public.crear_contrato`,
`public.actualizar_contrato`, `crm.crear_contrato_con_cuenta`, `crm.actualizar_contrato_con_cuenta`— dejan de
gatear la AUTORIDAD por P04 (`puede_gestionar_cuentas_cliente`, scope de cartera por cliente) y pasan a
`private.puede_registrar_ventas()`. Se **suelta el scope de cartera**: cualquier analista puede registrar/editar
a nombre de cualquier cliente; la venta cuenta a quien la cierra (`analista_cierre`, F3). **P04 sigue viva** para
banca / PDF / domicilio.

**La pregunta, ampliada:** `puede_registrar_ventas()` = `auth.uid presente AND not membresia_crm_revocada()
AND (es_admin() OR private.es_analista_vigente() OR puede_gestionar_contratos_crm())`. Se pregunta
`es_analista_VIGENTE` (no `es_analista` a secas) para NO nacer como puerta sin vigencia en el censo de la F5.a
— semántica idéntica porque el `not revocada` de arriba ya cubre las tres ramas. Operaciones-a-secas queda
fuera (0 usuarios). ALAN = analista normal, sin código especial.

**OK EXPLÍCITO de tocar `public`:** la F5.c modifica `public.crear_contrato` y `public.actualizar_contrato`
(igual que la F5.b tocó `public`), autorizado por Miguel como parte de la Opción B.

**Lo que cambió por las auditorías (dos NO-GO atendidos):**
- 🔴 **P0-1 (trinquete de vigencia F5.a):** cambiar el cuerpo de los núcleos cambia su huella → el guardián de
  la F5.a se pondría rojo y el commit seguía verde (lección F1.6). Arreglo: la migración **re-fija las huellas**
  de `crear_contrato`/`actualizar_contrato` en `analista_vigencia_exenciones` (siguen nombrando `es_analista`
  en su DECLARE muerto) y **corre `assert_analista_vigencia()` + `assert_analitica_leads_citas()` en su propio
  postflight**. El rollback revierte esas huellas y vuelve a correr el guardián.
- 🔴 **P0-2 (test-rls):** la Opción B invierte aserciones vivas (un analista sin ficha creando para cliente
  ajeno pasaba a estar permitido). Reescritas a semántica B + bloque nuevo F5.c.
- 🟠 **P1-1 (cliente activo):** P04 exigía `cli.activo=true`; el for-share del alta solo miraba el rol. Se
  **endurece a `and p.activo`** para que un cliente dado de baja no reciba contratos nuevos (en la EDICIÓN no
  se exige activo: corregir el histórico de un cliente de baja es coherente). Default firmable por Miguel.

**Ensayado contra prod (transacción deshecha, nada tocó producción) — códigos MEDIDOS:**
guardián vigencia 6/6 y analítica 30/30 verdes tras aplicar · analista para cliente ajeno **pasa autoridad**
(muere en términos, `23514`) igual que para su propio cliente · un cliente / anon / cliente **inactivo** →
`42501` denegados. Rollback restaura las 4 huellas al byte y repone el guardián.

**Verificado OK por el auditor:** la pregunta ampliada no abre a ningún rol indebido (operaciones sigue
denegado, anon/service_role/cliente/coordinador/directorio/lector denegados); la atribución queda en quien
cierra (no hereda al asesor del cliente); ventana de 5 h y "solo lo que tú creaste" intactas; P04 viva para
banca/PDF/domicilio; rollback byte-exact e idempotente.

**PUBLICADA (2026-08-30, vía `db query --linked --file`, lanzada por Miguel con `!` por el clasificador):**
la migración aplicó limpia (su preflight por huella, postflight y los DOS trinquetes corrieron dentro de la
misma transacción) y `registrar-f5c-version.sql` dejó el registro en **185** (`20260830190000`). Verificado
por CONTEO tras aplicar: 4/4 núcleos unificados a `puede_registrar_ventas` (0 menciones a
`puede_gestionar_cuentas_cliente`), pregunta ampliada con `es_analista_vigente` + no-revocado, candado
`rol='cliente' and p.activo` en pie, 2 huellas re-fijadas en `analista_vigencia_exenciones`.

**Batería post-publish:** `gate:vigencia` 6/6 ✅ · `gate:analitica` 30/30 ✅ · advisors **0 ERROR** (140 WARN,
los de siempre) ✅ · **ítem REVISAR wrapper 5028 CERRADO con código medido**: sonda en prod (DO que termina
en raise, nada escrito) — un analista vigente editando un contrato AJENO por
`crm.actualizar_contrato_con_cuenta` pasa la autoridad nueva y muere en `[42501] «Solo puedes corregir
contratos que tú creaste»` → la aserción `expectExplicitAuthorizationDenied` de test-rls sigue verde, la
hipótesis del agente era correcta. ⚠️ La suite `test:rls` COMPLETA no corre contra prod (0 cuentas
`*.crm@demo.avancecorp.pe` en producción; los fixtures viven en un banco): queda para el **próximo ciclo de
banco**, junto al gate pendiente de F4.

---

## P-055 · FASE 5.d — CERRAR LA PUERTA GEMELA MUERTA (2026-08-30)

**Estado: ✅ EN PRODUCCIÓN (2026-08-30 noche, registro 186).** Publicada por Miguel con `!` (su OK explícito
de `public`). Verificado por CONTEO tras aplicar: **7/7 con el ACL literal `{postgres=X/postgres}`**, las 2
de selección vivas para authenticated, registro **186** (`20260830210000`). Batería: `gate:vigencia` 6/6 ·
`gate:analitica` 30/30 · advisors **0 ERROR** (133 WARN — 7 menos que antes de cerrar). Con esto la
**Fase 5 queda ENTERA**: 5.a (181) + 5.b (184) + 5.c (185) + 5.d (186) y el paso 3 medido cerrado.
Migración `20260830210000_crm_f5_d_cerrar_gemelas_catalogo_versionado.sql`. Residual del **paso 2** de la
Fase 5 («la puerta gemela que sobre se retira por el camino seguro: cerrar → observar → borrar»). Aquí SOLO
se CIERRA (revoke); el DROP va a la F7 con OK de Miguel por pieza.

**Lo medido (30/08, contra producción y contra TODAS las superficies del repo):** las **7 funciones CRUD del
catálogo de productos versionados** (que Miguel decidió eliminar en la F0) son **rama muerta total** —
`public.crear_contrato_producto` + `actualizar_contrato_producto` + `actualizar_contrato_con_cuenta_producto`
y `crm.crear_contrato_producto` + `crear_contrato_con_cuenta_producto` + `actualizar_contrato_producto` +
`actualizar_contrato_con_cuenta_producto`: **0 llamadas** en portal (`public_html`), CRM (`app/src`), edges
propias y compartidas (`_supabase_functions`), Apps Script (`.gs`), cron de pg y servidor (lo único que las
nombra es `crm.cerrar_altas_legacy_productos`, y solo como comprobación de EXISTENCIA por `to_regprocedure`
— un REVOKE no la rompe; un DROP sí, por eso el drop espera). Las **2 de SELECCIÓN quedan VIVAS y no se
tocan**: `public.productos_inversion_seleccion_fn(uuid)` (la usa el portal) y
`crm.productos_inversion_seleccion_fn()` (la usa el CRM); ambas preguntan ya `puede_ver_catalogo_productos`
(D2 de la F5.b).

**Qué hace:** `REVOKE EXECUTE ... FROM authenticated, anon, public` sobre las 7 (postgres conserva).
Preflight: huella md5 de las 7 + ACL exactamente `{authenticated,postgres}` + selección viva + censo de
llamadores = 1 (solo la comprobación de existencia). Postflight en la MISMA transacción: juez = **ACL crudo
por `aclexplode` con `grantee=0`** (la memoria dice que `has_function_privilege` MIENTE si PUBLIC tiene el
permiso; queda de segundo testigo), las 7 con EXECUTE solo de `postgres`, selección intacta,
`to_regprocedure` de las comprobadas not null, y los DOS guardianes (`assert_analista_vigencia` +
`assert_analitica_leads_citas`) corren dentro (higiene F1.6).

**⚠️ Cuidado heredado que MOLDEÓ el ensayo:** NO se llama a una función revocada dentro del ensayo
(`select fn()` sin EXECUTE segfaulteó el backend en la imagen 17.6.1.105) — la prueba es de ACL, no de
conducta; la conducta 42501 vía PostgREST la probará `test-rls` en el próximo ciclo de banco.

**Ensayo contra prod (transacción deshecha):** `CIERRE: 7/7 cerradas, 2 vivas intactas, guardianes verdes ·
ROLLBACK: 7/7 ACL al byte, guardianes verdes`. El ensayo cazó un error real del guion (con `DISTINCT`,
`string_agg ... order by 1` es ilegal 42P10 → subconsulta) antes de que llegara a producción. **Ensayo v2**
(tras las auditorías) re-corrido EN VERDE con los literales de ACL en ambas direcciones.

**Dos auditorías, ambas atendidas ENTERAS:**
- **Auditor RLS → GO condicionado** (condición 1 = el OK de `public`, lo da el `!` de Miguel). Aplicado: P1
  (el D1 del banco reintroducía el patrón del segfault de imagen → **canaria**: la primera llamada a una
  gemela cerrada va sola y, si la respuesta llega SIN código —backend caído—, el bloque aborta nombrando la
  causa real en vez de cascada espuria; la vía PostgREST se midió segura en F1: 20× 401/42501) · P2 censo
  por OID · P2 superficies `pg_policy`/`pg_attrdef`/`pg_constraint`/`cron.job` re-medidas en el preflight
  (sonda contra prod: 0) · P2 registrador con candado «existe SIN cuerpo = excepción» · P2 consts muertas
  del D1 borradas.
- **Codex → NO-GO (2 P1 + 3 P2), refutación parcial, todo corregido:** P1 el registrador podía ceder ante
  un INSERT concurrente bajo Read Committed (`on conflict do nothing` sin relectura) → **relectura
  fail-closed tras el insert**: la fila final debe tener ESTE nombre y ESTE cuerpo o aborta (el cuerpo va
  embebido 3 veces: comparar + insertar + releer) · P1 el rollback probaba grantees, no el ACL entero →
  postflight compara el **literal completo `proacl::text`** contra el original medido
  (`{postgres=X/postgres,authenticated=X/postgres}`; el post-revoke exige `{postgres=X/postgres}`) · P2
  cobertura de conducta 2/7 → **7/7**: el D1 prueba las SIETE firmas por PostgREST en sus dos superficies ·
  P2 identidad del censo atada por OID (no por cuenta) · P2 «rama muerta TOTAL» matizada: los **e2e** montan
  las gemelas en su backend SIMULADO (`app/e2e/_helpers.ts`, no tocan prod) y el **oráculo local**
  `test-productos-inversion.sql` (corre en `gate-config-operativa.mjs` sobre un Postgres local que reproduce
  las migraciones PRE-F5.d) las llama como authenticated — ninguno pisa producción, pero cuando la **F7
  quiera el DROP**, ese oráculo y esos mocks deben retirarse CON las funciones. Codex también confirmó:
  PostgREST devuelve **42501** (no PGRST202) para una función viva sin EXECUTE — la expectativa del D1 es
  correcta.

**`test-rls.mjs`:** el bloque D1 de `testCapacidadUnificada` probaba autoridad por la gemela
`crm.crear_contrato_producto` (vend1/sup1 «pasan el gate») — invertido a la semántica F5.d: la gemela está
**cerrada para TODOS** (42501 para gerencia/vend1/sup1/coordinador/directorio/vendInactive); la semántica de
autoridad de ventas vive en `testVentasNucleoF5c` sobre el núcleo real.

**⚠️ OK de `public` PENDIENTE:** la F5.d revoca sobre 3 funciones de `public` — igual que F5.b/F5.c
necesita el OK explícito de Miguel (el acto de publicar con `!` lo es).

**Paso 3 de la Fase 5 (el par de cada persona): MEDIDO CERRADO** — las 7 combinaciones Portal↔CRM reales de
las 24 personas activas están TODAS declaradas en `private.pares_autoridad` (GABRIEL y GLORIA con su par
`admin+∅` deliberado); no existe gerencia CRM que no sea admin del Portal; quedan 2 pares declarados sin
persona viva (`directorio+directorio`, `comercial+supervisor`) que son combinaciones permitidas, no un hueco.

Archivos: `migrations/20260830210000_crm_f5_d_cerrar_gemelas_catalogo_versionado.sql` ·
`scripts/rollback-f5d-p055.sql` · `scripts/registrar-f5d-version.sql` (generado a máquina, cuerpo embebido
fail-closed) · bloque D1 reescrito en `scripts/test-rls.mjs`.

---

## P-055 · ATR-1 — EL UPGRADE CUENTA A QUIEN LO HACE (2026-08-30)

**Estado: ✅ EN PRODUCCIÓN (2026-08-30 noche, registro 187).** Publicada por Miguel con `!` la misma
noche (dentro del margen; el preflight re-midió agosto en el instante y pasó con delta VACÍO).
Verificado por conteo: huellas nuevas exactas en los dos núcleos (CE `71213ac0…`, MC `f968879a…`),
resolutor con ACL `{postgres=X/postgres}`, registro **187** (`20260830223000`). Batería:
`gate:vigencia` 6/6 · `gate:analitica` 30/30 · advisors **0 ERROR** (133 WARN, sin cambio).
**Desde esta noche, el primer upgrade que registre un no-dueño contará a quien lo haga** — y el
sellado del 10/09 capturará la política nueva.
Migración `20260830223000_crm_atr_1_upgrade_cuenta_a_quien_lo_hace.sql`. Primera fase del plan de
**atribución por cadena de upgrade** (decisión de Miguel 30/08 + sus 4 respuestas; contrato técnico
en el vault: «Contrato de la atribucion por cadena de upgrade (2026-08-30)»).

**La regla:** upgrade → cuenta al analista del selector (`analista_cierre_id`), no al dueño del
cliente; la renovación de ese upgrade → al mismo analista (adopción por LÍNEA — la cadena sigue al
CONTRATO y relee el analista VIVO de la cabeza); `asesor_perfil_id` jamás cambia; el Directorio del
Portal SE QUEDA con la regla vieja (dos podios, a propósito).

**Dónde vive:** en la LECTURA. Pieza nueva `private.analista_atribuido_cadena(uuid)` (CTE recursiva
sobre `operaciones_cartera.contrato_origen_id`; cabeza upgrade → su `analista_cierre_id` vivo; si no
→ NULL y regla vieja por `coalesce`; sin conteos → fuera del censo F6.a). La preguntan:
`private.conversion_episodios` (pierna 'operacion': columna + filtro de visibles — **firma idéntica**,
su exclusión del censo F6.a es por firma) y `private.metricas_cartera_por_vendedor` (bloque
economía: select + group by). El ledger `operaciones_cartera` NO cambia ni una fila: `vendedor_id`
pasa a significar «quién ERA el dueño» (HECHO); «a quién cuenta» es POLÍTICA del resolutor.

**Medido el 30/08 contra prod:** 46 upgrades en agosto, **TODOS con analista = dueño (delta VACÍO)**
→ la re-atribución de agosto mueve CERO filas HOY y el oráculo exige **paridad byte a byte**; la
lista delta se re-mide en el preflight por si nace un upgrade de un no-dueño antes del publish.
0 renovaciones de cadena (aborta si no), 0 upgrades sin analista (aborta si no), 19 de los 46 no
elegibles a conversión (regla del primer mes, intacta).

**Oráculo (misma transacción):** episodios antes/después por cada mes NO sellado — mismo número de
filas; las que difieren, EXACTAMENTE las del delta (dueño→analista, resto de columnas al byte);
economía de RENOVACIONES intacta SIEMPRE (contadores + 4 columnas de capital); total de upgrades de
la EMPRESA idéntico; con delta vacío, paridad EXACTA también en cartera; el resolutor probado contra
datos reales (todo upgrade → su analista; todo contrato 'nuevo' → NULL). **Pines de lo intocado**
(md5 en pre y postflight): `produccion_mes_por_vendedor` · `capital_episodios` ·
`registrar_ajuste_si_mes_cerrado` · `directorio_ranking_analistas` · `cerrar_periodo` ·
`cumplimiento_metas_sin_cartera_fn` — el capital de upgrades YA iba al analista (F3.5b): esta fase
mueve SOLO conversión y economía de cartera; el capital por cadena es la **ATR-2 (11–12/09, tras el
sello)**.

**Postflight:** huellas nuevas exactas (CE `71213ac0…`, MC `f968879a…`) · firma de
`conversion_episodios` pinneada · ni un `count(` nuevo en los cuerpos (números pinneados) · ACL
literal `{postgres=X/postgres}` en las 3 privates · los DOS guardianes dentro.

**Ensayos (30/08, deshechos): `ATR1-ENSAYO-VERDE-v3`** (migración entera + oráculos) y
**`ATR1-CICLO-VERDE-v3`** (migración + marcha atrás en UNA transacción: huellas originales al byte,
resolutor fuera, guardianes verdes dos veces).

**Auditoría Codex → NO-GO (3 P1 + 2 P2), atendidos ENTEROS:** P1-1 (el resolutor asumía invariantes
que el esquema no garantiza: la puerta de edición PUEDE corregir `categoria`, y dos filas cruzadas
A↔B satisfacen los UNIQUE) → resolutor v2: **la adopción más RECIENTE manda** (`nivel asc`: primer
ancestro upgrade — corregir la categoría corrige la adopción, declarado en el contrato) + anti-ciclo
por lista de visitados + invariante nueva en el preflight (`tipo = categoria`, 0 divergencias
medidas; también 0 ciclos y 0 cadenas hoy) · P1-2 (la pantalla de Conversiones en BRUTO relee
atribución viva para meses sellados) → **declarado en el contrato: lente ≠ foto** — la FOTO
(`cierre_mes_vendedor`) manda para pagos y jamás cambia; la lente en bruto es decisión previa de
Miguel · P1-3 (el rollback pisaba hotfixes posteriores) → preflight del rollback: los cuerpos vivos
deben ser EXACTAMENTE los de ATR-1 o aborta («regenerar, no pisar») · P2-1 (oráculo) → 3c compara
TODAS las columnas restantes null-safe + 3e-bis (reparto de upgrades por analista cuadra con el
delta persona a persona) + 3e-tris (nadie entra/sale de la foto fuera del delta) · P2-2 (conducta
solo-ACL en test-rls) → ya declarado: fixtures de upgrade en el próximo ciclo de banco.

**Auditoría del auditor RLS → NO-GO por el MISMO P1 que Codex** (`desc`→`asc`: con upgrades
encadenados atribuía al más ANTIGUO, contradiciendo la regla 3 y el propio oráculo 3g — reproducido
por él en un Postgres 17 local) — **ya corregido en la ronda Codex** (resolutor v2, `nivel asc` =
la adopción más reciente). Sus P2, aplicados: P2-3 la cabecera prometía el pin de
`public.crear_contrato` y no existía → **7.º pin** añadido (md5 `4c25cee5…`, pre y post) · P2-4
candado temporal: si agosto YA está sellado y contiene upgrades de no-dueños, el preflight ABORTA
(«el publish llegó tarde») en vez de fingir · P2-5a el rollback comprueba que NADIE nombra al
resolutor antes del drop (strpos, no LIKE) · P2-5b **la marcha atrás NO borra la fila
`20260830223000` del registro** — si se revierte en prod, retirar esa fila a mano es paso documentado
· P2-1 el comentario «ciclos imposibles» ya se había reescrito (anti-ciclo por visitados en v2).
Verificado en verde por él: byte-exactitud 2+2 parches, registrador triple fail-closed, seguridad
del resolutor (INVOKER dentro de DEFINER = postgres, sin FORCE RLS en esas tablas, sin PII), censo
F6.a intacto (exclusión por OID sobrevive al CREATE OR REPLACE), dedupe correcta, consumidores con
el fallback pactado.

**Caso (e) para el banco** (del auditor): el mutante del filtro — sin el parche de visibles, el
dueño seguiría viendo la operación que ya no le cuenta.

**`test-rls.mjs`:** bloque `testAtribucionCadena` (resolutor inalcanzable por PostgREST). ⏳ Los
casos de CONDUCTA (upgrade de vend2 sobre cliente de vend1 → métricas a vend2; dueño no lo ve como
suyo; Directorio sin cambio) necesitan un fixture de upgrade en `seed-demo` → **próximo ciclo de
banco**, con la suite entera.

**⏰ Ventana de publicación: 31/08–05/09** (nunca la mañana de un cierre; el 10/09 sella agosto).

Archivos: `migrations/20260830223000_crm_atr_1_upgrade_cuenta_a_quien_lo_hace.sql` ·
`scripts/rollback-atr1-p055.sql` · `scripts/registrar-atr1-version.sql` (triple embebido fail-closed)
· bloque nuevo en `scripts/test-rls.mjs`.

---

## P-055 · ATR-2 — LA RENOVACIÓN DEL UPGRADE HEREDA A SU ANALISTA (2026-08-31)

**Estado: 🟡 PREPARADA — DOS auditorías atendidas ENTERAS; ensayo v2 (cadena sintética + 2 mutantes + SEGUNDO PASE del oráculo con delta real) EN VERDE, deshecho.
⏰ PUBLICAR 11–12/09, CON AGOSTO YA SELLADO (candado en el propio preflight).** Migración
`20260830233000_crm_atr_2_capital_por_cadena_de_upgrade.sql`. Segunda fase del tren de atribución
(ATR-1 = registro 187).

**Qué hace:** el núcleo de capital (`private.capital_episodios`) pregunta la MISMA política que
ATR-1 en sus piernas **contrato** y **desglose** — analista, `en_roster` y filtro de visibles pasan
JUNTOS (regla de los 3 puntos) a `coalesce(resolutor(...), regla vieja)`; la pierna cooperativa
intacta. Por transitividad heredan SIN tocar cuerpo: `produccion_mes_por_vendedor` → metas → el
SELLO, `metricas_capital/vencimientos`, bloque dinero de cartera. **Efecto en números de HOY: CERO**
(el propio upgrade ya iba a su analista; solo se movería una renovación-de-cadena, y hay 0 — el
preflight re-mide y el oráculo exige que SOLO se mueva lo que haya).

**Pines:** el núcleo viejo (`872f5ad4…`→ nuevo `90f1d8c2…`) + el resolutor de ATR-1 (`e39016e2…`,
DEBE existir) + 8 intocadas (CE/MC de ATR-1, producción, registrar_ajuste, directorio, cerrar_periodo,
cumplimiento, crear_contrato). **Oráculo:** foto entera del núcleo (rango total) antes/después —
paridad exacta con deltas vacíos; con delta, emparejamiento viejo→nuevo columna a columna (en_roster
re-verificado contra el cuadro de metas del NUEVO analista), totales de dinero por tipo/medida/moneda
al céntimo, y producción de meses abiertos sin moverse fuera del delta.

**Ensayo `ATR2-CICLO-VERDE` (30/08 noche, TODO deshecho):** migración + **cadena sintética fabricada
contra prod** (upgrade de X sobre cliente de Y → renovación → renovación²; más una rota estilo
backfill): adopción en 1 y 2 saltos en capital Y desglose · la rota cae a regla vieja · **reasignar
la CABEZA (válvula F3.4) mueve la cadena entera; un eslabón, no** · **2 mutantes CAZADOS** (resolutor
anulado; recursión cortada) · el resolutor restaurado vuelve a resolver · marcha atrás al byte con
guardianes verdes. Ensayo guardado en `scripts/ensayo-atr2-cadena-sintetica.sql` (re-corrible antes
del publish). 🔴 Tres candados del catálogo aprendidos fabricando: un snapshot histórico NO se
reutiliza · las condiciones solo cambian en borrador · la fecha de cierre comercial LA PONE el
servidor (fabricar = `producto_condicion_id` NULL + `fecha_cierre_comercial` NULL y los triggers
hacen el resto).

**Auditoría Codex → NO-GO (1 P0 + 4 P1), atendidos:** P0-1 el registrador podía registrar un esquema
NO migrado → ahora exige la huella ATR-2 VIVA antes de insertar («un ledger jamás declara aplicada
una migración que no lo está») · P1-2 el emparejamiento de desglose comparaba menos columnas que el
de contrato → igualado (12 columnas null-safe) · P1-4 el anti-pisado del rollback solo miraba prosrc
(un ALTER de atributos sobrevivía) → pinnea también definer/volatility/search_path en pre y post ·
P2-1 la cabecera dice la verdad (6 parches + 1 comentario) · **P1-1 → DECISIÓN DE MIGUEL (31/08):
las dos lentes SE ALINEAN** — `metricas_capital_mes_fn` y `metricas_vencimientos_fn` pasarán a
enseñar por el analista resuelto de la cadena, **en ATR-3** (con oráculo de paridad propio). El
Directorio del Portal queda como la única lente por cartera, a propósito.

**Auditoría del auditor RLS → GO (1 P1 + 5 P2), atendidos:** P1-1 los caminos del oráculo con delta
no vacío jamás habían corrido con filas → **SEGUNDO PASE del oráculo en el ensayo**: se repone el
núcleo viejo, se fotografía el mundo sintético, se re-aplica ATR-2 y el MISMO código empareja las
cadenas fabricadas (delta ≥2) sin abort espurio · P2-1 candado de calendario para publish TEMPRANO
en el preflight (espejo del de ATR-1: agosto abierto + delta de agosto → aborta) · P2-3 guardia de
conteos con el patrón del censo (case-insensitive + `sum(1)`) · NOTA-2 dos pines gratis añadidos
(`capital_autorizada` `dc499b1f…`, `metricas_conversiones_implementacion` `46421295…`) · P2-2
**deuda de rendimiento ANOTADA**: el resolutor corre ~2 veces por fila en lecturas globales — a 10k
contratos re-medir `capital_episodios` con EXPLAIN ANALYZE (va junto a la re-medición F4) · P2-4
**si se revierte en prod, retirar A MANO la fila `20260830233000` del registro** (el rollback repone
la función, no borra el registro) · P2-5 deudas de oráculo documentadas (EXCEPT sin ALL colapsa
duplicados exactos — inalcanzable hoy porque el parche mueve por contrato entero).

Archivos: `migrations/20260830233000_crm_atr_2_capital_por_cadena_de_upgrade.sql` ·
`scripts/rollback-atr2-p055.sql` (preflight anti-pisado + literal original) ·
`scripts/registrar-atr2-version.sql` (triple embebido fail-closed) ·
`scripts/ensayo-atr2-cadena-sintetica.sql`.

---

## P-055 · ATR-3a — LAS LENTES Y LA FICHA DICEN QUIÉN SE LLEVA LA PRODUCCIÓN (2026-08-31)

**Estado: ✅ EN PRODUCCIÓN (2026-08-31, registro 188).** Publicada por Miguel con `!`; el oráculo
bajo claims corrió dentro de la transacción. Verificado por conteo: las TRES huellas nuevas exactas
(`b21f9a7a…`/`54a9bf11…`/`1eccb3a1…`), registro **188** (`20260831010000`). Batería: gates 6/6 y
30/30 · advisors **0 ERROR**. El front (ATR-3b) sale con `/release-crm`. Migración `20260831010000_crm_atr_3a_lentes_y_ficha_al_analista.sql`.
Decisión de Miguel (31/08): las dos gráficas se ALINEAN + SIN funciones nuevas.

**Tres cambios:** `metricas_capital_mes_fn` y `metricas_vencimientos_fn` — el corte de visibilidad
no-global pasa de cartera (`cli.asesor_perfil_id`) al **analista del episodio** (con ATR-2 será el de
la cadena); el join muerto a perfiles se retira; cooperativas intactas. `atribucion_contrato_fn` gana
la clave **`atribucion_efectiva`** `{cadena, adoptada, analista_id, analista_nombre}` preguntando al
resolutor; el resto del payload AL BYTE. **Efecto visible hoy: CERO** (solo gerencia/global mira esas
gráficas y el corte no le aplica). Sin analista (15 históricos) → fuera de la vista no-global
(invariante F3.5b); gerencia lo ve todo.

**Oráculo bajo CLAIMS reales (dentro de la migración):** gerencia (global) byte a byte en ambas
lentes · supervisor: la foto nueva = agregación PREDICHA a mano desde el núcleo (subárbol replicado
con la MISMA CTE de `vendedor_ids_visibles` — que se niega sin claims por defensa en profundidad — y
las cooperativas con su regla intacta) y todo mes movido queda explicado · fichas: payload viejo al
byte + clave nueva contra la verdad pre-calculada como postgres. **Pines:** las 3 tocadas + resolutor
+ `capital_episodios` con **pin BIVALENTE** (P0 de ordenación, confirmado por ambas auditorías: en
prod ATR-3a corre ANTES que ATR-2, pero en el replay del banco el orden es por timestamp y ATR-2 va
primero — se acepta cualquiera de las dos huellas y el postflight exige la MISMA capturada; sin
renumerar nada) + producción + `cerrar_periodo` +
**`directorio_ranking_analistas` (la ÚNICA lente por cartera que queda, pinneada)** + `crear_contrato`.

**Ensayos:** `ATR3A-ENSAYO-VERDE` y `ATR3A-CICLO-VERDE` (marcha atrás con anti-pisado de cuerpo Y
atributos, ACL literal por función, guardianes). 🔴 Aprendido: `vendedor_ids_visibles` devuelve VACÍO
sin claims (defensa en profundidad) — toda foto/predicción de lentes se captura bajo claims o se
replica el subárbol a mano; las temporales que se releen bajo claims llevan GRANT explícito.
Registrador con candado «mundo vivo YA migrado». Si se revierte en prod: retirar a mano la fila
`20260831010000` del registro.

**Dos auditorías, atendidas:** Codex NO-GO (2 P1 + 3 P2) → oráculo del supervisor BIDIRECCIONAL en
las DOS lentes (vencimientos incluida, contra su propia predicción con estado+ventana replicados) ·
registrador exige las TRES huellas vivas · ficha verifica también `analista_nombre` y EXACTAMENTE 4
claves · el «15 sin analista» del comentario pasó a MEDIDO Y VERIFICADO en preflight (13 sin demos)
· rollback pinnea owner/lang/strict/parallel/leakproof/cost. Auditor RLS GO-condicionado → su P0 de
ordenación quedó cerrado por el pin bivalente (verificó ambos sentidos con md5 del árbol entero) y
sus P2 de oráculo cayeron con los mismos arreglos; COMMENT de la ficha actualizado. **⏳ Deuda con
nombre para el próximo ciclo de banco (P1-1 del auditor):** casos del gate de las lentes — permitido
(analista ve el agregado de un episodio SUYO de cliente ajeno), denegado (el dueño de cartera deja
de verlo; sin-analista invisible para no-global), y la verdad de `atribucion_efectiva` con cadenas
reales — necesitan el fixture de upgrade de seed-demo, el MISMO que ya esperan ATR-1/ATR-2. El
bloque runnable (formas + clave en contrato normal + no-miembro vacío) va en `testLentesAtribucion`.
Si se revierte en prod: retirar a mano la fila `20260831010000` del registro.

Archivos: `migrations/20260831010000_crm_atr_3a_lentes_y_ficha_al_analista.sql` ·
`scripts/rollback-atr3a-p055.sql` · `scripts/registrar-atr3a-version.sql`.

---

## P-055 · F7.0 — EL GATE QUE VIGILA LAS PUERTAS CERRADAS (2026-08-31)

**Estado: ✅ EN PRODUCCIÓN (2026-08-31, registro 189).** Publicada por Miguel con `!`. Verificado:
7 piezas vigiladas, veredicto OK, vigía 06:59 activo. Batería: **`gate:f7` verde con su mutante de
DOS filos cazados y limpieza verificada** (🔴 trampa pagada en vivo: `db query` devuelve solo el
ÚLTIMO resultado de un archivo multi-sentencia — el mutante se partió en 3 archivos, un SELECT
final cada uno) · gates 6/6 y 30/30 · advisors 0 ERROR. Desde mañana, el rondín de las 06:59 pasa
lista a las 7 gemelas; demolibles desde el 13/09. Migración
`20260831020000_crm_f7_0_el_gate_que_vigila_las_puertas.sql`. Primera ola de la Fase 7 «ordenar la
casa» (plan por olas aprobado por Miguel el 31/08: ventana de observación **14 días**, alcance
servidor+registro+repo, catálogo entero con pantallas).

**Qué instala (nada se cierra ni se derriba aquí):**
- **`private.f7_piezas_en_observacion`** — la lista que el vigía lee, el CANDADO temporal del DROP
  (`drop_no_antes_de` vive en el servidor) y el registro histórico. Trinquete propio (fechas solo
  crecen, huella/cierre inmutables, ni DELETE ni TRUNCATE; ⚠️ limitación declarada, como F6.a: el
  assert no vigila esos triggers). RLS ON, 0 policies, 0 grants. **Seed: las 7 gemelas de F5.d**
  (cerradas 30/08 → demolibles 13/09; fechas LITERALES para el replay del banco; llamador permitido:
  `cerrar_altas_legacy_productos`, que solo comprueba existencia).
- **`private.assert_f7_piezas_cerradas()`** — por pieza: existe · huella intacta · ACL = literal
  esperado · 0 llamadores nuevos (censo por OID normalizado sin comentarios, excluyendo el conjunto
  vigilado + permitidos resueltos) · 4 superficies en 0 (policies/defaults/CHECKs/cron). Las
  `demolida` NO renacen; tabla vacía = rojo (fail-closed).
- **Vigía `crm-f7-piezas-vigia` a las 06:59** (completa la serie 06:29/39/49), molde F6.a (jamás
  revienta el cron; escribe en `vigia_alertas` fase `f7_piezas_cerradas`), programado con
  verificación exacta estilo F1.6.
- **`npm run gate:f7`** (`gate-f7-observacion.mjs` + trinquete de FILA-veredicto): 0 alertas
  abiertas en `vigia_alertas` **de TODAS las fases** (⭐ cierra la deuda medida: esa tabla no la
  leía NADIE) + vigía exacto + assert OK. `-- --mutante`: alerta sintética en transacción deshecha
  que DEBE cazarse y no quedar escrita.

**La observación, honesta (medida):** un intento rechazado (42501) NO es detectable desde dentro —
el chequeo de EXECUTE corre antes del cuerpo y no hay event triggers (postgres no es superusuario).
Este vigía vigila la SUPERFICIE (nadie re-cableó la pieza); los intentos reales se revisan en los
logs del panel a D+7 y D+14, con fecha y responsable.

**Ensayo `F70-CICLO-VERDE` (31/08, deshecho):** aplicar → marcha atrás (la TABLA y sus filas se
conservan, doctrina F6.a) → **RE-aplicar** (creación condicional + seed idempotente `on conflict do
nothing`) → marcha atrás final. Guardianes verdes en cada tramo.

**Séquito:** sonda nueva en `test-rls.mjs` (`testF7Observacion`: la tabla es inalcanzable por la
API) · `package.json` gana `gate:f7`. Censo F1.4 NO aplica (solo `crm`+`public`; la tabla es
`private`, como `vigia_alertas`); censo F6.a NO aplica (el assert no nombra leads/citas).

**Auditoría del auditor RLS → GO (2 P1 + 5 P2), atendidos:** P1 el censo era EVADIBLE con
MAYÚSCULAS o comillas (lo probó contra el motor: `~` es case-sensitive y la comilla rompía el
patrón) → normalización `lower(replace(…,'"',''))` en el censo y las 4 superficies · P1 el
trinquete congelaba 2 de 11 columnas → congela la declaración ENTERA (huella, ACL esperada, patrón,
permitidos, ok_miguel, ola, firma) y toda transición exige rastro en nota · P2 la demolida
prematura ahora delata · P2 el CHECK codifica los 14 días (`cerrada_en + 14`) · P2 sonda con
códigos esperados · P2 `%s`→`%` · P2 revoke + postflight de las funciones de trigger. Verificó
contra prod: 0 alertas abiertas (el gate no nace en rojo, y el preflight lo exige), huellas 7/7,
ACL 7/7, censo 0, 06:59 libre, triple embebido 3/3 al byte.

**Auditoría Codex → NO-GO (4 P0 + 4 P1 + 2 P2), atendidos ENTEROS:** P0-1 el censo omitía VISTAS
(`pg_get_viewdef` de v/m) y funciones SQL-standard (`prosqlbody`) → ambos censados · P0-2 `liberada`
era una ESCOTILLA (update de consola + grant = assert verde) → **máquina de estados cerrada**: solo
observación→demolida y observación→cerrada_permanente por UPDATE; liberar o salir de
demolida/permanente EXIGE migración con el candado bajado · P0-3 la ventana se reseteaba vía NULL →
una fila sin ventana no re-adquiere fecha por UPDATE · P0-4 la herencia de roles no toca `proacl`
→ cierre transversal: authenticated/anon NO alcanzan a postgres por la cadena de `pg_auth_members`
(CTE recursiva) · P1-1 la RE-aplicación revalida la tabla superviviente (seed íntegro + el CHECK
de 14 días vivo) · P1-2 **el veredicto es ahora una FUNCIÓN** (`private.veredicto_f7`): el
trinquete Y el mutante ejercitan EL MISMO código; mutante con DOS filos (alerta sintética + cron
desprogramado, ambos deshechos y con limpieza verificada) · P1-3 el cron pinnea `username` y la
última corrida no-fallida · P1-4 `firma` congelada · P2-1 el falso-rojo por homónimas queda
declarado (fail-noisy; salida = `llamadores_permitidos`) · P2-2 la sonda de test-rls se RETIRÓ
(probaba la config global de PostgREST, no esta migración — deuda honesta: la garantía vive en el
postflight y el vigía). 🔴 Trampa nueva: la variable `r` de un loop plpgsql PISA el alias SQL `r`
dentro de un EXISTS — alias distintos o revienta con «record has no field».

Archivos: `migrations/20260831020000_crm_f7_0_el_gate_que_vigila_las_puertas.sql` ·
`scripts/rollback-f7-0-p055.sql` (conserva la tabla) · `scripts/registrar-f7-0-version.sql`
(candado mundo-vivo: el assert vivo debe dar OK antes de registrar) ·
`scripts/trinquete-f7-observacion{,-mutante}.sql` · `scripts/gate-f7-observacion.mjs`.

---

## P-055 · F7.1 — CERRAR LO QUE QUEDÓ SUELTO (2026-08-31)

**Estado: ✅ EN PRODUCCIÓN — publicada por Miguel el 31/08 a las 00:0x Lima (registro 191).
Verificado post-publish: 191 versiones, las 7 puertas cerradas AL LITERAL, libro con 14 piezas
(«OK: 14 vigiladas — 10 observación, 4 permanentes»), vigilante ampliado sellado (2e28ebb4…),
gates vigencia+analítica+f7 verdes + mutante de 2 filos cazado, advisors 0 ERROR. La suite
test:rls completa queda para el ciclo de banco (prod tiene 0 demos a propósito — deuda declarada).** Migración
`20260831060000_crm_f7_1_cerrar_lo_que_quedo_suelto.sql` — **v3: reemplaza a la `20260831050000`
(v2), que reemplazó a la `20260831040000` (v1); NINGUNA publicada jamás** (regla del repo: las
migraciones commiteadas no se editan; cada reemplazada se retiró del árbol en su commit y ninguna
llegó a prod ni al registro). Ola 1 de la Fase 7: **7 cierres, 0 derribos**, todos al libro de la
Ola 0.

**LA ENMIENDA (veredicto Codex 30/08, verificado contra prod antes de aplicar):**

1. **La danza del rol puente SOBRABA.** postgres HEREDA del dueño `crm_metricas_bridge`
   (membresía con USAGE): el revoke/grant directo se ejecuta COMO el dueño — **medido ida y
   vuelta contra prod el 30/08**, el ACL va y vuelve al byte con el bridge como grantor. Fuera el
   `grant … with set true` → `set local role` → `reset` (menos maquinaria tocando prod); el
   preflight ahora pinnea la HERENCIA (`pg_has_role USAGE`) porque sin ella el revoke sí sería un
   no-op silencioso — y el postflight compara el ACL LITERAL, que cazaría cualquier no-op.
2. **La adopción de `metricas_altas_analista_fn` SOBRABA.** Su partida de nacimiento SÍ está en el
   registro de prod: versión `20260716203331` (`crm_metricas_gerencia_fn`), CON cuerpo — lo
   incompleto es el ARCHIVO local (el repo tiene 167 de las 189 versiones de prod). No se adopta
   nada: se cierra tal cual con su huella pinneada.
3. **El vigilante de la Ola 0 se AMPLÍA aquí:** su cierre transversal de herencia solo vigilaba
   `authenticated`/`anon`; ahora vigila TAMBIÉN que `service_role` no alcance a `postgres` por
   membresía (esta ola le quita a service_role dos EXECUTE directos; sin la ampliación, un GRANT
   futuro de membresía se los devolvería todos SIN tocar proacl y el vigía seguiría verde).
   Preflight pinnea la huella Ola 0 (`e6f0070260e1fff2757201df8134167b`); postflight verifica la
   mención por `strpos` (jamás LIKE: el guion bajo es comodín).
4. **El rollback ya NO borra filas del libro** (contradecía la doctrina de la propia tabla: «jamás
   DELETE; la salida es estado=liberada»): marca las 7 filas de la ola como `liberada` con rastro
   en nota (candado bajado NOMBRADO) y RESTAURA el vigilante de la Ola 0 al byte. La migración, a
   su vez, RE-DECLARA filas `liberada` de su propia ola al re-aplicarse (ciclo ida-vuelta honesto).
5. **Honestidad temporal del registrador en hora de LIMA** (`now() at time zone 'America/Lima'`),
   no UTC — la ventana real de registro es 31/08–02/09 del reloj comercial.

**TABLA DE OK DE MIGUEL (su `!` al publicar es la firma):**

| Pieza | Acción | Consecuencia |
|---|---|---|
| `metricas_distribucion_leads_fn` (v1) | REVOKE → observación (demolible 14/09) | Puerta supersedida por v3; su core private sigue vivo |
| `metricas_distribucion_leads_v2_fn` | REVOKE → observación (14/09) | Muere también en el registro el «v2 aún llamada» de RETOMAR-57 |
| `metricas_cartera_fn` | REVOKE **permanente** (incl. service_role) | Órgano interno de conversion_mensual_fn — JAMÁS se derriba |
| `crear_contrato_con_cuenta` | REVOKE **permanente** | Órgano interno del alta pdf_v2 |
| `actualizar_contrato_con_cuenta` | REVOKE **permanente** | Órgano interno de la corrección pdf_v3 |
| `public.actualizar_numero_contrato` ⚠️`public` | REVOKE **permanente** (incl. service_role) | Órgano interno de numero_pdf_v3; el `!` es el OK explícito de tocar public |
| `metricas_altas_analista_fn` | REVOKE → observación (14/09) | Partida de nacimiento verificada en el registro (20260716203331); se cierra tal cual |
| `assert_f7_piezas_cerradas` | AMPLIAR (cierre transversal + service_role) | El vigía diario caza también la puerta trasera de membresía hacia service_role |
| Front | Retirar 2 wrappers + 2 hooks muertos + sus tests | Cero pantallas los usaban |

**Las versiones MUDAS del registro son 12, no 9** (medido; lista completa en el preflight de la
futura Ola R — `metricas_altas_analista_fn` NO es una de ellas).

**Oráculo (read-only, bajo claims de gerencia, dentro de la migración):** `conversion_mensual_fn`
byte-igual tras cerrar su órgano interno (prueba VIVA de que la delegación DEFINER sobrevive) ·
distribución v3 byte-igual · los cuerpos de las 7 sin moverse (esta ola solo toca ACLs) · el censo
fino de llamadores/superficies lo corre el **vigilante recién AMPLIADO** sobre las 7 filas recién
sembradas (14 en el libro) + veredicto + guardianes.

**test-rls (la deuda declarada de la v1 quedó SALDADA — Codex la refutó como insuficiente):** las
sondas de negocio de las puertas internas se RE-APUNTAN a las puertas VIVAS del PDF (mismos
argumentos, delegan en las mismas validaciones): cuenta-obsoleta/UUID-forjado/atomicidad → pdf_v2
con sus expectativas ORIGINALES restauradas (P0001/22023/23505+regex de mensaje) · scope y P04 y
número-vacío → pdf_v3 · `expectHidden` de altas → denegación explícita · bloque `testF7Ola1`
ampliado: canaria + 6 puertas crm × 2 roles + **sonda directa de `public.actualizar_numero_contrato`**
(los argumentos sí se conocen: son los de las sondas P04) + **revocación efectiva bajo
`service_role`** (cliente admin → 42501 en cartera y numero).

**Ensayo y ciclo RE-MEDIDOS sobre la v2, VERDES (30/08 noche, deshechos):** `F71-ENSAYO-VERDE` +
`F71-CICLO-VERDE` — el ciclo aplica→libera→re-declara→libera y prueba viva la ruta nueva del
rollback; el registrador falla-cerrado verificado contra prod («el mundo vivo NO esta migrado»).
Si se revierte en prod: `scripts/rollback-f7-1-p055.sql` + retirar a mano la fila `20260831050000`
del registro.

**Auditoría 1/2 (auditor-rls, 30/08 noche): GO — 0 P0, 2 P1 operativos, 6 P2.** Refutó en verde
los 10 puntos delicados (vigilante restaurado BYTE-IDÉNTICO a la Ola 0, huella ampliada
`3376972d9e9d45a75de7508dc02dc045`; 3 embebidos del registrador idénticos entre sí y al archivo;
ningún objeto persistente de prod-visible llama a las 7; argumentos de todas las sondas correctos;
ninguna sonda residual incompatible). Atendido: P1-1 ya estaba hecho (ensayo/ciclo v2 verdes —
esta sección lo decía mal), P2-6 comentario de test-rls corregido. **Declarado sin cambio:** P2-1
la re-declaración tras rollback NO reinicia la ventana de 14d (mitigado: demoler exige migración
propia + OK de Miguel; la nota deja rastro) · P2-2 el oráculo corre en READ COMMITTED — un dato
que se mueva en prod entre foto y comparación aborta con falso rojo (fail-safe: rollback limpio,
re-intentar; publicar en hora valle) · P2-3 la rama service_role del cierre transversal queda SIN
mutante hasta el ciclo de banco (en prod no se puede `grant postgres to service_role` ni en
ensayo; el mutante va al banco: grant + assert esperando el raise, deshecho) · P2-4/P2-5 notas
cosméticas.

**⚠️ OPERATIVO (P1-2): la ventana del registrador es [31/08 – 02/09] en hora de LIMA** (el seed
declara `cerrada_en = 2026-08-31`; el candado es `between cerrada_en and cerrada_en + 2` — no
admite publicar ANTES del 31/08 00:00 Lima). Publicar la migración y el registrador JUNTOS a
partir de esa hora; si se publica la migración antes, el registrador aborta y prod queda migrado
sin fila (el escenario «el ledger mintió»).

Archivos: `migrations/20260831060000_crm_f7_1_cerrar_lo_que_quedo_suelto.sql` ·
`scripts/rollback-f7-1-p055.sql` · `scripts/registrar-f7-1-version.sql` (candado de honestidad
temporal en hora de Lima: ventana [31/08 – 02/09]; ver el bloque OPERATIVO arriba).


## P-055 · EL BANCO: 4.º INTENTO — EL PROTOCOLO FUNCIONÓ Y EL DIAGNÓSTICO CAMBIA (01/09)

**El banco NO está roto: llegó a la migración que muere POR DISEÑO.** El protocolo que dejó
escrito el intento del 31/08 (medir la salud de storage ANTES de culpar al replay) hizo su
trabajo a la primera:

| Medición | Intentos 1-3 (31/08) | Intento 4 (`banco-f7`, 01/09) |
|---|---|---|
| storage / realtime | **nunca levantaron** (`TenantNotFound`) | ✅ **ambos levantaron** |
| esquemas `crm` y `private` | no nacieron | ✅ existen (24 tablas, 174 funciones) |
| versiones replayadas | **0** | ✅ **86** |
| Veredicto | plataforma | **nuestro registro, y es lo esperado** |

⇒ Los tres fallos del 31/08 **sí eran de Supabase**; este es otra cosa. El replay se detuvo en
**`20260812000259_crm_cierres_externos`**, que es exactamente la que
[[banco-branch-replay-manual]] documenta desde el 16/08: *«su postflight exige un perfil real
activo en `crm.equipo` — en branch el seed corre antes — y el branch nace virgen»*. **Todo branch
nuevo muere ahí por diseño**, y la receta manual (replay desde el REGISTRO remoto por el pooler,
con siembra intercalada) es la vía conocida.

🔴 **Y el CLI también tenía su trampa, ya documentada:** el host directo
`db.<ref>.supabase.co` NO resuelve (ECONNREFUSED); hay que ir por el **pooler en modo SESIÓN**
(`aws-0-us-east-2.pooler.supabase.com:5432`, usuario `postgres.<branch_ref>`). El
`POSTGRES_URL` que devuelve `branches get` viene en 6543 (modo transacción) y hay que cambiarlo
a 5432.

**Estado:** `banco-f7` (`cwkiejoaqadcnaieghnf`) vivo, con 86 de 196 versiones. Para completarlo
falta la siembra intercalada + el replay manual de las 110 restantes desde el registro remoto —
trabajo del próximo ciclo, ya sin misterio de plataforma.

## P-055 · F7.2 — ✅ EN PRODUCCIÓN EL 01/09: EL INTERRUPTOR LEGACY, CERRADO CON LLAVE

**Estado: ✅ PUBLICADA por Miguel con `!` el 2026-09-01 (`20260901200000`).** Batería verde:
interruptor con ACL `{postgres=X/postgres}` · su acta en el libro (observación, cerrada 01/09,
**demolible el 15/09**) · **15 piezas vigiladas** (11 en observación + 4 permanentes) · los 4
gates del repo verdes · advisors 0 en las clases de ERROR · vigía 0 · **negocio intacto** (496
contratos, 572 condiciones — el equipo siguió cerrando ventas mientras se publicaba).
⚠️ El registro llegó a **196 versiones**: dos son de otra sesión que publicó en paralelo.

**Qué se cerró y por qué — medido el 01/09.** `crm.cerrar_altas_legacy_productos(bigint)` es el
interruptor que apagaría el «modo compatibilidad» del catálogo. Estado real medido: el único
producto es `HISTORICO-SIN-CATALOGO` (archivado, legacy), **las 568 condiciones son TODAS legacy
y cero normales**, y los contratos cuelgan de ahí ⇒ **si alguien lograra ejecutarlo, el equipo
dejaría de poder crear contratos**. Hoy es inejecutable (su propio cuerpo exige una condición
no-legacy publicada y no hay ninguna), nunca se usó, y ninguna pantalla lo dispara: el envoltorio
`cerrarCompatibilidadLegacyProductos` existe en el front pero **ningún componente lo importa**.
🔑 Y además **desbloquea la Ola 2**: nombraba tres de las siete gemelas por `to_regprocedure`.

**⚠️ NO se tocó el catálogo de condiciones** (tablas, datos, FK, columna, trigger de snapshot):
eso es infraestructura VIVA del cierre de ventas — 18 personas la mueven a diario — y Miguel
decidió el 01/09 que **no se toca**. Ver «El catálogo de productos NO es un catálogo».

**Paquete:** migración · `scripts/registrar-f7-2-version.sql` (relectura fail-closed) ·
`scripts/rollback-f7-2-p055.sql` (reabre el interruptor y retira el acta bajando el candado
NOMBRADO `trg_f7_obs_01_no_borrar`) · `scripts/ensayo-f7-2-ciclo.sql` → **F7.2-CICLO-VERDE**
contra prod, deshecho. 🔴 Si se revierte: retirar A MANO la fila `20260901200000`.

## P-055 · F7 · LAS DEMOLICIONES — v2 TRAS EL NO-GO DE CODEX (13 y 14/09)

**Estado: 🟡 v2 ESCRITA Y ENSAYADA ENTERA contra producción; falta la evidencia D+7/D+14 y el `!`
de Miguel en su fecha.** La v1 se declaró aquí «lista para correr» el 01/09 y **una segunda
auditoría de Codex la devolvió NO-GO con 12 puntos**; esta sección la corrige. Ver abajo «lo que
la v1 daba por bueno y no lo era».

**✏️ LAS v1 SE RETIRAN DEL ÁRBOL.** `20260913120000` y `20260914120000` (commit 9695d67) **nunca
se aplicaron en ningún sitio** — el registro remoto va por 196 y estaban fechadas el 13 y el
14/09. Como las migraciones commiteadas **no se editan** (regla del CRM, con guardián que la hace
cumplir), se retiran del árbol y entran en su lugar las v2. **No podían quedarse**: un replay de
banco aplica por orden de versión y habría demolido con los preflights débiles. Copia de las v1
en la sesión; ninguna versión del registro las nombra.

- **Ola 2 (13/09)** `20260913130000_crm_f7_ola2_demoler_las_siete_gemelas_v2` — demuele las 7
  gemelas. Preflight: ventana **por FIRMA exacta** (no por conteo de la ola) · **vigía VIVO**
  (cron activo, comando exacto, última corrida reciente y `succeeded`) + cero alertas ·
  `assert_f7_piezas_cerradas()` **antes** del DROP · huella del **cuerpo Y de
  `pg_get_functiondef` entera** + dueño + comentario · **ACL efectivo** (`acldefault` para el
  caso `proacl IS NULL`) + `has_function_privilege` a los tres roles de la API · **censo de nueve
  superficies** (`pg_depend`, `prosrc`, `prosqlbody`, vistas, policies, defaults, constraints,
  índices de expresión, `cron.job`) en **todos** los esquemas · acta por firma con `ROW_COUNT` ·
  postflight por firma exacta, con las puertas VIVAS `crear_contrato_con_cuenta_pdf_v2` y
  `actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)` y el trigger de snapshot.
  Registrador: `scripts/registrar-f7-ola2-version.sql`.
  Marcha atrás: `scripts/rollback-f7-ola2-gemelas.sql`.
- **Ola 2b (14/09)** `20260914130000_crm_f7_ola2b_demoler_el_tablero_de_altas_v2` — demuele
  **solo** `metricas_altas_analista_fn`, con las mismas defensas.
  Registrador: `scripts/registrar-f7-ola2b-version.sql`.
  Marcha atrás: `scripts/rollback-f7-ola2b-tableros.sql`.

**🤖 Los registradores y el ensayo se GENERAN, no se copian.**
`scripts/generar-registrador-f7.mjs` y `scripts/generar-ensayo-f7-olas.mjs` leen los archivos
reales. Es la lección de ATR-4 (registrador con una migración vieja incrustada dentro) convertida
en herramienta, y **`npm run gate:f7` corre el `--verificar` de los dos ANTES de tocar el
servidor**: si alguien edita una migración de demolición y no regenera, el gate se pone rojo.
Probado con mutante: toqué una migración → rojo; la restauré → verde. El generador del ensayo
además exige que los registradores estén al día antes de embeberlos.

### Segunda vuelta de la auditoría (el mismo 01/09): cinco arreglos más

Codex re-auditó la v2 con el encargo de refutar la propia corrección. Nueve de sus doce puntos
quedaron CERRADOS y tres siguen abiertos **a propósito** (evidencia D+7/D+14, paquete del 15/09 y
ruta del bridge). Los cinco huecos nuevos, ya cerrados:

1. **El generador solo protegía el delimitador INTERIOR.** El exterior (`$reg_*$`) envuelve el
   cuerpo embebido: una migración que lo contuviera habría cerrado el literal antes de tiempo y
   producido SQL corrupto. Ahora **los dos se calculan** buscando uno libre (determinista, así que
   `--verificar` no se pone rojo por regenerar). Probado: con `$reg_ola2b$` dentro de la migración,
   el generador pasa solo a `$reg_ola2b_1$`.
2. **`--verificar` era una promesa en un comentario**: decía que lo corría `gate:config`, donde no
   estaba cableado. Ahora lo corre `gate:f7`, de verdad.
3. **El ensayo no tenía `--verificar`** y podía quedarse viejo acreditando un paquete que ya no
   existe. Ya lo tiene, y valida los registradores antes de embeberlos.
4. **El mutante de la Ola 2 no identificaba unívocamente la guarda temporal**: su mensaje
   («no estan listas») sale de una guarda COMPUESTA. Ahora exige además que el detalle **nombre la
   fecha futura** que puso el viaje en el tiempo, que solo puede salir de la rama de la ventana.
5. **El rollback de la Ola 2 validaba el libro por conteo**, no por conjunto exacto de firmas —
   justo en una marcha atrás de emergencia, el peor momento para enterarse. Ya exige las siete.

**🧪 `F7-OLAS-2y2b-ENSAYO-VERDE` (01/09, `scripts/ensayo-f7-olas-2-y-2b.sql`)** contra producción,
deshecho entero: mutante de ventana **cazado en las dos olas por el preflight REAL** (con el CHECK
`f7_obs_ventana` PUESTO todo el rato), migraciones y registradores aplicados (el registro habría
quedado en **198** versiones), las marchas atrás recrearon las **8** con definición **y comentario**
al byte, libro con 15 piezas y guardianes en verde.

### Lo que la v1 daba por bueno y no lo era (auditoría de Codex, 01/09)

Codex confirmó primero lo importante: **demoler no rompe nada vivo**. Censo exhaustivo con
lecturas — cero dependencias en `pg_depend`, cero referencias en cuerpos, vistas, policies,
defaults, índices y `cron.job`, cero en las **16 edge functions desplegadas**, cero en los dos
`.gs`, cero en los **68 archivos del portal vivo** y los **49 del CRM vivo**. El NO-GO era del
**paquete**, no de la decisión:

1. **Los dos registradores NO EXISTÍAN** — y esta misma sección declaraba el paquete «listo».
2. **La marcha atrás de la Ola 2b perdía el COMENTARIO** de `metricas_altas_analista_fn`, y el
   ensayo salía verde igual porque solo comparaba `md5(prosrc)`. Prueba concreta de que una
   huella de cuerpo **no acredita** una recreación fiel. Los dos rollbacks fijan ahora definición
   completa + comentario + dueño + ACL efectivo.
3. **Cinco falsos verdes en los preflights**: libro validado por conteo y no por conjunto exacto ·
   stop-the-line ciego al vigía (un cron apagado también devuelve cero alertas) · huella solo del
   cuerpo · `aclexplode(NULL)` no devuelve filas mientras el ACL por defecto **sí** concede EXECUTE
   a PUBLIC · censo demasiado estrecho.
4. **El ensayo no ejercitaba el preflight real** (repetía su consulta) y **desmontaba el CHECK** de
   14 días para viajar en el tiempo: la migración nunca se probaba con su guarda instalada.
5. **`test-rls` exigía 42501 exacto**: tras el DROP, PostgREST responde `PGRST202` y la suite se
   ponía roja. Ahora las siete gemelas y el tablero aceptan **42501 (cerrada) o PGRST202
   (demolida)** — y **solo ellas**: en una puerta viva un PGRST202 seguiría siendo rojo, porque
   significaría que alguien se llevó por delante algo que debía seguir en pie.

**📌 Donde Codex se pasó de frenada — y él mismo lo refutó en la segunda vuelta.** Dijo que tras el
DROP `gate:config` quedaría rojo por `test-productos-inversion.sql`. **No es así**: ese oráculo es
autocontenido — el gate le crea un clon de `template0` y el propio archivo hace `\ir` de las dos
migraciones del catálogo, o sea que **se recrea las gemelas antes de probarlas**. Su mundo no
depende de producción. Llegué a meterle guardas de existencia por esa premisa falsa; **se
revirtieron enteras**, porque nunca se ejecutarían y, si lo hicieran, saltaban también pruebas de
superficies VIVAS y la preparación (`CAT-001`) que bloques posteriores consumen. Una guarda
inerte-pero-mal es peor que ninguna guarda.

**⏳ Lo que todavía falta antes del `!` (no es código):** la **evidencia D+7 (06/09) y D+14
(13/09)** por firma —rebotes `42501`/`PGRST202` en los registros, con **intervalo y cobertura
declarados**—. La ausencia de logs no se convierte en «cero uso probado»: se reporta como «sin
evidencia de uso en la ventana X, con cobertura Y».

**🔜 El paquete del 15/09 queda APLAZADO, no olvidado:** demoler
`crm.cerrar_altas_legacy_productos(bigint)` (cerrada el 01/09, ventana hasta el 15/09) necesita su
propia captura, migración, registrador y ensayo. Se escribe cuando se escriba, con el mismo patrón.

**🔴 CUATRO TRAMPAS QUE EL ENSAYO CAZÓ (ninguna era visible leyendo el código):**
1. **Recrear una función en `public` la REABRE**: los default privileges de Supabase le devuelven
   EXECUTE a anon/authenticated/service_role y `revoke ... from public` (el ROL) NO los quita. Lo
   cazó el propio vigilante F7 a mitad del ensayo. Los rollbacks revocan a los tres explícitamente.
2. El trigger `solo_crece` **exige rastro escrito en `nota`** al cambiar de estado — y
   `nota || texto` es NULL si `nota` es NULL (va con `coalesce`).
3. Volver de `demolida` a `observacion` **exige bajar el candado NOMBRADO** (doctrina
   limpieza-leads), nunca un `disable trigger user` a ciegas.
4. **🔴 DEUDA DECLARADA — dos tableros salen del plan:** `metricas_distribucion_leads_fn` y su
   `v2` pertenecen al rol `crm_metricas_bridge`, y por el canal de publicación **no se puede
   asumir ese rol tal y como está hoy** (`42501 permission denied to set role`): ni `alter owner`
   ni `set role`. Su marcha atrás las recrearía con dueño `postgres` y el vigilante las vería
   REABIERTAS. **No se derriba lo que no se sabe reconstruir**: quedan cerradas y vigiladas.
   ⚠️ **Corrección de la 2.ª auditoría:** decir «hace falta superusuario» es **demasiado fuerte**.
   Codex midió que existe una vía transaccional plausible — conceder temporalmente `SET OPTION` a
   la membresía de `postgres` usando el `ADMIN OPTION` que YA existe, más `CREATE` en `crm` al
   bridge, restaurando ambos exactamente. **No está ensayada y no entra aquí**: va en su propio
   paquete, con ensayo adversarial y fotos exactas de `pg_auth_members` y `nspacl`.

**Los 14 días NO se tocaron.** El ensayo viaja en el tiempo solo dentro de su transacción
abortada, y su ACTO 2 es el **mutante del candado**: comprueba que hoy las 7 gemelas están dentro
de su ventana, o sea que el trinquete de verdad frena. En producción el CHECK sigue intacto.

## P-055 · ATR-4 — ✅ EN PRODUCCIÓN EL 01/09 (REGISTRO 193): LA SANCIÓN DE ANULAR ES SOLO DE CONVERSIÓN

**Estado: ✅ PUBLICADA por Miguel con `!` el 2026-09-01, ONCE días antes de su calendario
(«12/09+»).** Batería post-publish EN VERDE: **registro 193** con cuerpo, **0 actas mudas**, y el
cuerpo registrado es **byte a byte el archivo** (md5 `b46efb62dce76bc3793f64cb2e85da82` — el
arreglo ① de la 2.ª vuelta pagó aquí) · **las 8 funciones con su huella nueva** y el núcleo con
sus atributos y ACL `{postgres=X/postgres}` intactos · **los 4 guardianes y los 4 gates del repo
en verde** (6 puertas · 30 contadores · 14 piezas F7 · 0 tablas sin rastro) · `vigia_alertas` 0 ·
advisors por SQL: **0 en todas las clases de ERROR** · la demo qorilazo sigue fuera del dinero ·
mundo intacto: 0 anulaciones reales, 0 deudas.
**Con ATR-4 dentro ANTES del primer sello, la pregunta transitoria del contrato («las deudas de
capital ya registradas, ¿se saldan o se condonan?») MUERE SIN NACER: nunca existirá una deuda
con la regla vieja.** ✅ **Y el FRONT publicado el mismo día** (Miguel invocó `/release-crm`): release
`crm-20260901T173750Z-3d89d2787123` (commit `3d89d27`), gates 2433/2433, manifiesto
`ARTEFACTO_OK`, smoke 200 y **bundle vivo `index-Bogte3tJ.js` idéntico al local por SHA-256**,
con los textos nuevos medidos DENTRO del bundle de producción. Rollback inmediato:
`crm-20260901T170814Z-cf3812973845.zip`. 🔴 Trampa repetida (RETOMAR-55): `release:crm` aborta
por archivos untracked — los 5 eran guiones SQL de otra sesión, ninguno toca `app/`, así que se
usó `--allow-dirty` explícito y el manifiesto quedó anclado al commit correcto.

**Estado previo (el paquete que autorizó publicar):** Migración `20260901180000_crm_atr_4_sancion_de_anular_solo_conversion.sql` ·
`scripts/ensayo-atr4-conducta-sintetica.sql` (**ATR4-ENSAYO-CONDUCTA-VERDE** contra prod,
deshecho) · `scripts/rollback-atr4-p055.sql` (**ATR4-CICLO-VERDE-v2**: ida→vuelta al byte→re-ida)
· `scripts/registrar-atr4-version.sql`. Front actualizado (textos de anular + tests, 2433/2433).

**La regla (Miguel, 31/08): «solo la conversión, siempre».** Anular baja la conversión del
analista con mes abierto o sellado por igual; el capital NO se toca jamás — ni la producción del
analista ni el AUM de la empresa. **CINCO bisturís, todo en la LECTURA:**
1. `produccion_mes_por_vendedor` — fuera las CTE `anulados`/`neutralizados`; la pierna coop
   filtra por **MEDIDA del núcleo** (`medida='stock'`), no por el flag.
2. `registrar_ajuste_si_mes_cerrado` — la deuda de mes sellado carga SOLO numerador
   (capital 0/0, detalle `[]`); numerador 0 ⇒ NULL POR DISEÑO (la alerta del vigía queda).
3. `capital_episodios` — la coop anulada REAL vuelve a `medida='stock'` con su monto; conserva
   `estado='anulado'` y el flag. ÚNICA excepción DECLARADA por id sellado: la demo qorilazo
   (S/100k, lead REAL — el filtro de demos no la caza, medido).
4. `contratos_afectados_por_anulacion` — SOLO informativa; compara por la ATRIBUCIÓN EFECTIVA
   (`coalesce(analista_atribuido_cadena, analista_cierre_id)`), no por `creado_por`.
5. **LAS LENTES DEL DINERO** (la refutación tumbó el «sin tocar lentes» del contrato del vault):
   `metricas_vencimientos_fn`, `directorio_ranking_analistas` y `metricas_directorio` cortaban
   la pierna coop por `estado='vigente'` — habrían borrado a la anulada aunque el núcleo la
   conservara; `cierres_externos_fn` llevaba contabilidad paralela (`anulado_en is null`). Las
   cuatro pasan a la MEDIDA (o a la exclusión declarada de la demo, en la paralela).

**Re-sellos:** 4 exenciones del censo F6.a (las 3 del contrato + `cierres_externos_fn`, que el
trinquete cazó en vivo) + sello agregado + **el censo de VIGENCIA** (F5.a): el ranking del
Directorio es puerta exenta allí — su fórmula es md5 SIN lower (distinta de la del F6.a; ambas
medidas contra los assert vivos, que las cazaron una a una hasta quedar exactas).

**Preflight:** pines de las 12 funciones (las 8 que se tocan con cuerpo viejo exacto + 4 del
mundo alrededor) + **candado del mundo**: 0 anulaciones de Avance, 0 deudas, exactamente 1 coop
anulada = la demo por id y motivo. Si nace una anulación REAL antes de publicar, ABORTA y se
decide con Miguel. **Postflight:** las 8 cambiaron de verdad · anti-conteos · atributos y ACL ·
**tres paridades al byte** (capital global, conversión global, producción de agosto: con el
mundo de hoy, ANTES = DESPUÉS) · la demo sigue sin ser dinero · los 2 guardianes en OK.

**El ensayo de conducta (los 4 escenarios del contrato + el sello):** coop y avance anulados con
mes ABIERTO → producción idéntica al byte, AUM intacto, **las 4 lentes fotografiadas BAJO CLAIMS
no se mueven**, y la conversión baja EXACTO el episodio; con mes SELLADO (sellado dentro del
ensayo por el camino del cron) → la deuda nace solo-conversión (numerador EXACTO al episodio,
capital 0/0) y la foto sellada no se toca. **Orden inverso v3:** el sello con ATR-4 dentro es
IDÉNTICO al sello con las reglas vivas **medido en la MISMA transacción** (línea base LOCAL — la
constante de las 00:32 caducó a mediodía porque el negocio REGISTRÓ 3 contratos de agosto
mientras se ensayaba: el discriminador separó DATO de LÓGICA e hizo su trabajo).

**Refutación (4 lentes en paralelo + verificadores): NO-GO del dinero ATENDIDO ENTERO.** Los 8
confirmados, cerrados: las 3 lentes vivas + la contabilidad paralela (→ bisturí 5) · el
registrador NO PARSEABA (dollar-quote anónimo cortado por el `do $$` del cuerpo embebido → tag
`$reg_atr4$`, y el cuerpo guardado ahora es BYTE-EXACTO al archivo) · el rollback re-sellaba con
razones INVENTADAS (→ las vivas leídas de prod, en dollar-quote) y le faltaba candado de mundo
(→ solo corre con 0 anulaciones reales; después de la primera, se corrige HACIA DELANTE) · los
textos del front prometían descuento de cuota (→ «baja la conversión; el capital no se toca», con
sus tests) · faltaba esta entrada del ledger.

**🔎 SEGUNDA VUELTA DE CODEX (01/09 tarde): NO-GO ATENDIDO ENTERO.** Sus 7 arreglos: ① el
registrador embebía una migración VIEJA (se editó después de generarlo) → re-embebido del archivo
FINAL, literal verificado byte-idéntico (md5 `b46efb62dce76bc3793f64cb2e85da82`, 55 113 bytes) ·
② `afecta_cuota` de la RPC `anular_cierre_avance` queda como DEUDA DECLARADA (el front ya no lo
lee; renombrar el payload exige migrar la RPC pública + api + mocks — va con la limpieza
semántica de F8, no se apila aquí) · ③ el modo DEMO del front excluía anulados del total →
alineado a la regla (suman; test espera 14 000) · ④ los actos B/D asertan también
`pendiente_numerador/pen/usd/detalle` exactos · ⑤ rótulos del rollback a «8 cuerpos» · ⑥ esta
actualización · ⑦ los SELECTs que su sandbox no pudo correr, corridos contra el catálogo VIVO:
**0 consumidores de dinero adicionales** con `cierres_externos+anulado` o `'vigente'`+dinero
(los 2 hallazgos usan «anulado» para CONVERSIÓN o para bloquear ediciones — correctos bajo la
regla; la prosa vieja de `corregir_cierre_externo` va a la limpieza de F8), 0 vistas. Ensayo
re-corrido tras todo: **ATR4-ENSAYO-CONDUCTA-VERDE** · front **2433/2433**.

**⚠️ Operativo del publish:** mismo patrón de la noche — `db query --linked --file` migración →
`registrar-atr4-version.sql` → gates → advisors. El ensayo retiene el candado global de cierre:
no publicar metas ni anular en ese minuto. 🔴 Si se revierte: `rollback-atr4-p055.sql` (solo con
0 anulaciones reales) y retirar A MANO la fila `20260901180000`. **Deudas al banco:** mutante de
los bisturís (romper uno y ver el acto exacto que lo caza) · absorción de una deuda
numerador-pura por `saldar_ajustes` en el sello del mes siguiente (imposible con un solo sello).

## P-055 · ATR-2 — ✅ EN PRODUCCIÓN EL 01/09 (REGISTRO 192), NUEVE DÍAS ANTES DEL CALENDARIO

**Estado: ✅ PUBLICADA por Miguel con `!` el 2026-09-01, con agosto ABIERTO y ningún mes sellado.**
Batería post-publish EN VERDE:
- **Registro 192**, ATR-2 registrada CON cuerpo, **0 actas mudas** (la Ola R sigue en pie).
- **Núcleo `capital_episodios`**: huella `90f1d8c2342becb94cc3d3e023227078` (la que exigía el
  registrador), **6 llamadas al resolutor de cadena**, definer + stable + `search_path` vacío,
  ACL `{postgres=X/postgres}`.
- **Las otras 11 funciones ancladas: 11/11 con su huella original** — el mundo alrededor intacto.
- **Delta real: 0** contratos cuya atribución resuelta difiera de la vieja ⇒ efecto en números de
  hoy CERO, como prometía el contrato.
- **Los 4 guardianes en OK**: vigencia (6 puertas), analítica (30 contadores), F7 (14 piezas
  vigiladas), auditoría (0 tablas sin rastro, 3 exenciones). **Los 4 gates del repo en verde**
  (`gate:vigencia`, `gate:analitica`, `gate:f7`, `gate:auditoria`). `vigia_alertas`: 0 filas.
- **Advisors**: el MCP de Supabase estaba desconectado, así que se midieron **por SQL las clases
  que producen ERROR** — vistas definer expuestas 0 · tablas expuestas sin RLS 0 · policies con
  RLS apagada 0 · funciones del área sin `search_path` 0 · índices inválidos 0 · triggers
  deshabilitados 0. Queda pendiente el pase del MCP cuando reconecte, por completitud.

**🔎 AUDITORÍA DE CODEX SOBRE LA PUBLICACIÓN (01/09, 23 min): GO-CONDICIONADO — y sus condiciones
quedaron CERRADAS o DECLARADAS el mismo día.** Su sandbox no tenía token, así que sus consultas
pendientes las corrió esta sesión contra prod:
- ✅ **El cuerpo REGISTRADO es byte a byte el archivo del repo** (md5 `ac63b470c366fc573e0e2491982ed8fd`,
  22 829 bytes, 1 statement) — Codex además verificó que las 3 copias dentro del registrador son
  idénticas al archivo.
- ✅ **Delta re-medido en LAS DOS piernas: contrato 0 y DESGLOSE 0** (el desglose no se había medido
  post-publish; también vacío). Re-medir otra vez el 09/09 con el ensayo de la víspera.
- ✅ **0 residuos de los ensayos** (0 clones, 0 tablas `_atr2%`/`_sello%`, 0 contratos marcador,
  0 sellos).
- ✅ Advisors por MCP (los corrió Codex): seguridad 0 ERROR (39 INFO/126 WARN de las clases de
  siempre) · rendimiento 0 ERROR. Coincide con la medición por SQL de esta sesión.
- 🔴 **Fe de erratas (ángulo 9 de Codex, CONFIRMADO en vivo):** la cabecera de ATR-2 — que quedó
  registrada dentro de `statements` — afirma que `metricas_capital_mes_fn` y
  `metricas_vencimientos_fn` «recortan por cartera»; **eso quedó OBSOLETO antes de publicarla**:
  la ATR-3a (registro 188, 31/08) ya las alineó por `e.analista_id`, y así están vivas (medido:
  cortan por analista, no por `asesor_perfil_id`; el Directorio conserva ambos criterios a
  propósito). El cuerpo registrado NO se maquilla (regla de la Ola R: historia primero); esta nota
  es la corrección.
- 🟡 **Lo que los gates verdes NO prueban (ángulo 6, tiene razón):** los 4 gates/guardianes miden
  sus dominios (vigencia/analítica/F7/auditoría), no la CONDUCTA de ATR-2 — de los 4, solo el de
  analítica menciona `capital_episodios` (por sus exenciones) y ninguno vigila la cadena. La
  conducta con una cadena REAL y `p_global=false` es la **deuda ya declarada del ciclo de banco**
  (fixture de upgrade), bloqueado por el aprovisionamiento de Supabase; se salda allí.
- 🟡 Protocolo (ángulo 7): `test:rls` no corre contra prod (0 cuentas demo — deuda declarada del
  banco) y los advisors corrieron DESPUÉS del publish, no antes; queda dicho.

**Estado previo (el triple ensayo que autorizó publicar hoy):** producción intacta tras los tres,
191 versiones, 0 meses sellados, núcleo con su huella vieja `872f5ad4…`, 0 clones residuales.

**🔑 EL CANDADO NO ES UNA FECHA — es CONDICIONAL, y hoy NO salta.** El preflight (línea 99) dice:
aborta si `agosto NO sellado` **Y** `hay renovaciones-de-cadena con mes agosto en el delta`. Con el
**delta en 0** (medido hoy: 0 contratos divergentes) la segunda condición es falsa y **el preflight
pasa con agosto abierto**. El «11–12/09» de la cabecera es **disciplina declarada**, no un bloqueo
técnico — y esta sesión midió que esa disciplina no tiene coste.

**Los 12 pines del preflight: 12/12 INTACTOS** tras las Olas R y 1 (registros 190 y 191, publicadas
DESPUÉS de preparar ATR-2). Ninguna de las 12 funciones ancladas se movió.

**TRES ENSAYOS, TODOS CONTRA PRODUCCIÓN Y DESHECHOS:**
1. **`ATR2-CICLO-VERDE-v2`** — el ensayo con cadena sintética que ya existía
   (`scripts/ensayo-atr2-cadena-sintetica.sql`: migración entera + siembra de una cadena real +
   oráculos + marcha atrás al byte). Re-corrido hoy: **sigue verde con las Olas R/1 dentro**.
2. **`ENSAYO-COMBINADO-SELLO+ATR2-VERDE`** (nuevo,
   `scripts/ensayo-atr2-sobre-agosto-sellado.sql`) — **el 10/09 y el 11/09 en la MISMA
   transacción**: sellar agosto por el camino del cron → aplicar ATR-2 entera con agosto ya
   sellado → comprobar que **la foto sellada no se movió ni un byte** (huella por elemento de las
   18 filas + la cabecera del sello). Es el orden previsto por el calendario, y funciona.
3. **`ENSAYO-ORDEN-INVERSO-VERDE`** (nuevo, `scripts/ensayo-atr2-antes-del-sello.sql`) — **la
   prueba decisiva**: aplicar ATR-2 PRIMERO y sellar agosto DESPUÉS, con el sello leyendo ya el
   núcleo parcheado, y comparar contra la **línea base del ensayo de la F2**
   (`656c6b6e00f2d2a6867eb184b9f5c02b`). **Resultado: la foto sellada es IDÉNTICA.** ⇒ Publicar
   ATR-2 antes del 10/09 **no cambia el sello**. Queda demostrado, no argumentado.
   (El guion está escrito fail-closed: si la huella hubiera diferido, aborta con `ATENCION:
   publicar ATR-2 hoy CAMBIA el sello del 10/09`.)

**Por qué el efecto es cero, en una línea:** con delta vacío el resolutor de cadena devuelve el
propio `analista_cierre_id` del contrato (no-op), así que el núcleo parcheado calcula lo mismo que
el viejo. Solo una RENOVACIÓN DE CADENA DE UPGRADE se movería, y hoy no existe ninguna.

**Vía de publicación (sin cambios):** `db query --linked --file` la migración →
`scripts/registrar-atr2-version.sql` (exige la huella VIVA `90f1d8c2…` antes de registrar) →
gates → advisors. Será el registro **192**. 🔴 Si se revierte: retirar A MANO la fila
`20260830233000` del registro.

**Lo que sigue valiendo del calendario:** si entre hoy y el sello NACIERA una renovación de cadena
de upgrade con mes agosto, el candado del preflight **sí** saltaría y habría que decidir con
Miguel. El guion del orden inverso se puede re-correr en cualquier momento para re-comprobarlo.

## P-055 · FASE 2 — ENSAYO DEFINITIVO DEL PRIMER SELLO (2026-09-01)

**Estado: ✅ ENSAYADO CONTRA PRODUCCION Y DESHECHO ENTERO. Produccion verificada intacta despues
(0 meses sellados, 0 filas de foto, 0 clones residuales, `cerrar_periodo` y `ciclo_cierre_mes`
con la misma huella que antes: `cefe29a1…` / `aa816313…`).** No es una migracion.
Guiones versionados: `scripts/ensayo-cierre-agosto-definitivo.sql` (v2) y su comparador
`scripts/verificar-sello-contra-control.sql`. **El ensayo del 29/08 nunca se commiteo y se
perdio; este si queda.**

**Por que se hizo hoy:** el 29/08 se ensayo con agosto ABIERTO. Desde el 01/09 el mes ya termino,
asi que el candado «el mes tiene que haber terminado» **lo pasa agosto por si mismo** y solo hay
que neutralizar UNO de los dos (la ventana de ajuste) — ensayo mas fiel que el anterior.

**RESULTADO (todo por el camino REAL, el ciclo automatico del cron):**
`ok=true` · **18 personas** · `cerrados=1` · **52,7 ms** · sello `automatico=true`,
`cerrado_por=null`, `meta_revision=14`, `ponderacion_referido=0.150`,
cobertura `medible=false / motivo=mes_parcial / suelo 2026-08-17` (agosto sella parcial: ya
decidido, no es pregunta). La llamada DIRECTA da la **huella identica** (el ciclo no altera lo
que sella). Rebotes: segundo cierre → `P0409 «Ese mes ya estaba cerrado»`; sellar julio por
detras → `22023` **del candado 2quater** (comprobado por MENSAJE, no solo por sqlstate: cuatro
candados comparten ese codigo).

**LINEA BASE (no «foto del 10/09» — ver abajo):** foto `656c6b6e00f2d2a6867eb184b9f5c02b`;
entradas conversion `b0151ec6…`, produccion `0a74291d…`, metas `278a52ed…`, metas_detalle
`b31a363a…`, nombres `d0e143e3…`, deudas `18f854b2…`, referidos de agosto 7.

**🔴 LA REFUTACION QUE CAMBIO EL ENCUADRE (4 lentes en paralelo; la v1 afirmaba lo contrario y
era FALSO): AGOSTO NO ESTA CONGELADO EL 01/09.** La ventana del 1 al 10 existe justamente porque
el mes admite correcciones. Cuatro caminos vivos medidos por los que la foto puede moverse antes
del sello: (1) **anulaciones** — `conversion_episodios` evalua `cierre_externo_anulado(lead_id)`
EN VIVO, con 25 asignaciones convertidas de agosto expuestas; (2) **republicacion de metas** —
agosto ya va por la **revision 14** y `cerrar_periodo` toma `order by revision desc limit 1`;
(3) **operaciones de cartera** — la pierna filtra por la COLUMNA `periodo`, no por fechas: en
septiembre se puede registrar una operacion con periodo de agosto (aporta 1.0 frente a 0.15 de
un referido); (4) **atribucion** — `analista_atribuido_cadena(...)` es politica de lectura VIVA.
⇒ **Una huella distinta el 10/09 es lo NORMAL.** Por eso el comparador separa
`DIFIERE-POR-DATO` (legitimo) de `DIFIERE-SIN-DATO` (rojo de verdad), con una huella por cada
entrada. **Recomendado: repetir el ensayo la VISPERA (09/09)** — ese si es control proximo.

**Otras 11 correcciones de la refutacion, aplicadas en la v2:** rastro consciente declarado (el
payload NO lleva nombres — `log_min_error_statement=error`, asi que el mensaje del raise queda en
los Postgres Logs y eso no lo borra el rollback) · asercion dura tras el acto A (el ciclo se
TRAGA cualquier error de `cerrar_periodo` y devuelve `{ok:false,cerrados:0}` sin excepcion: sin
la asercion se habria podido publicar un `md5('vacio')` como control) · precondicion de clones
residuales · `revoke execute … from public` en los dos clones (nacen SECURITY DEFINER) ·
`TimeZone`/`DateStyle` clavados y hashes de metas sin columnas de tiempo (si no, la huella
dependia de la sesion) · acto E ampliado a metas_detalle + nombres + deudas por FILA + referidos ·
forma del ciclo verificada (secdef+proconfig), no asumida · candado del mes MEDIDO en vez de
literal `true` · acto D por mensaje · titular fuera del json (jsonb ordena claves por longitud:
si el canal truncara, se perdia la huella) · acto B renombrado — **no** es «el camino de
gerencia»: sin uid recorre igual la rama automatica, y la rama con uid no se puede probar en prod
(inyectar claims contamina la transaccion entera, trampa ya documentada) → va a banco.

**⚠️ Operativo:** mientras corre retiene el candado global de cierre
(`pg_advisory_xact_lock` sobre `crm.periodos_cerrados`): no publicar metas ni anular contratos en
ese minuto, y no correrlo cerca de las 09:20 de Lima.

## P-055 · OLA R — LAS DOCE ACTAS MUDAS DEL REGISTRO (2026-08-30/31)

**Estado: ✅ EN PRODUCCIÓN — publicada por Miguel el 30/08 noche (registro 190). Verificado
post-publish: 190 versiones, 0 mudas, las 12 reparadas EXACTAS por huella-por-elemento, 0 sin
nombre, fila propia con cuerpo y nombre; gates vigencia+analítica+f7 verdes. Pendiente declarado:
la sonda del runner del banco (P1-1) antes del replay completo.** Migración
`20260831055000_crm_ola_r_las_doce_actas_mudas.sql` (055000 < 060000 a propósito: orden de
publicación = orden de replay).

**Qué repara:** las 12 versiones del registro con `statements` NULL (20260819162752, 20260819211815,
20260820190500, 20260826151907, 20260826154500, 20260826173523, 20260826174500, 20260826182000,
20260826182500, 20260828190000, 20260828190500, 20260828191000) ganan su cuerpo exacto — **136
sentencias** (17/13/17/10/9/11/10/7/10/7/19/6) divididas con separador que respeta
dollar-quoting/comillas/comentarios (verificado ADEMÁS por un separador independiente de Codex:
mismos conteos). Las 9 sin nombre ganan además su `name` con la convención del CLI (mejora
deliberada; el rollback lo revierte).

**La FIDELIDAD es contra el catálogo VIVO, no contra git (Codex refutó la narrativa de fechas y
se corrigió):** 39 objetos persistentes comparados contra prod — 15 cuerpos de función por md5 +
firma/retorno/volatilidad/definer/config/owner/ACL, 4 triggers por DEFINICIÓN COMPLETA
(pg_get_triggerdef: tgtype 29/29/25/13, sin WHEN, como los archivos), 19 constraints VALIDADAS por
constraintdef, la columna cruda con tipo/nullabilidad/comment, y los efectos ACL de la 191000
(10 tablas sin letras caras para anon/auth; 5 funciones anon=0/auth=5). **2 reemplazos INTERNOS
reconciliados** (normalizar_domicilio_legal 162752→211815; cartera_pagina_fn 151907→174500 — el
vivo coincide con la posterior). Sobre git, la verdad exacta: 182000/182500 se commitearon el
26/08 y el ledger las da por aplicadas el 28/08; el instante real de aplicación NO es recuperable
(`track_commit_timestamp=off`); 211815 fue editada 10m41s tras su primer commit y el delta es SOLO
su sonda DO (cero DDL — se registra el texto final del repo con esta nota).

**Contrato PRE/POST (refutación 4b de Codex atendida):** el preflight acepta DOS estados globales
y ninguno más — PRE (189 versiones, 12 mudas, las 12 exactas) → repara; POST (0 mudas y las 12 con
el cuerpo objetivo EXACTO; la fila propia puede no existir aún) → no-op total. **Un híbrido (p. ej.
11 mudas) ABORTA a propósito.**

**v3 — la SEGUNDA refutación de Codex (NO-GO sobre archivos), atendida entera:** ① la identidad
del cuerpo es **POR ELEMENTO** — `md5(string_agg(md5(elemento) order by ordinality))` + conteo +
cero NULL/vacíos — porque el md5 del texto UNIDO no ve fronteras desplazadas (Codex lo demostró
contra prod con dos arrays distintos de igual join); rige en preflight POST, relectura, rollback y
registrador · ② tags con **versión completa** `$olar_<version>_<i>$` (los sufijos de 6 dígitos
colisionaban entre 0820190500 y 0828190500 — benigno para PG, falso para el verificador) · ③ la
foto del diff-cero compara **CONTENIDO, no conteos**: policies con qual/withcheck, triggers por
triggerdef, checks por definición, cron por comando, comments con classoid, default-ACL con
namespace, columnas con identidad/generación/collation/ACL/stats · ④ el rollback **BLOQUEA las 12
filas (FOR UPDATE)** antes de chequear — el TOCTOU entre chequear y anular quedó cerrado · ⑤ el
registrador verifica cuerpo **y nombre** de la fila propia ANTES del insert · ⑥ **el registrador
de la F7.1 quedó ENCADENADO**: aborta si la Ola R no está registrada o quedan mudas — el orden de
la noche ya no depende del operador. Medido: `OLAR-V3-ENSAYO-VERDE` + `OLAR-V4-CICLO-VERDE`
(reparar → no-op POST → rollback endurecido → mundo original → re-reparar) + ambos registradores
falla-cerrado en cadena.

**Diff-cero ampliado (refutación 4c atendida):** la foto antes/después cubre funciones con huella
completa, rels, policies, triggers, checks, crons, **pg_description (comments), pg_default_acl y
metadatos de columnas (pg_attribute+defaults)**, y conteos comerciales. NULL-guard por versión +
relectura md5 + cero sentencias vacías + suma 136 congelada.

**Medido contra prod (todo deshecho): `OLAR-V2-ENSAYO-VERDE` · `OLAR-V2-CICLO-VERDE`**
(reparar → RE-aplicar no-op por el camino POST → deshacer con el rollback → mundo original EXACTO
con los 9 names a NULL → re-reparar). Registrador propio verificado falla-cerrado (jamás la muda
13). Rollback `scripts/rollback-ola-r-p055.sql` con anti-pisado por md5+conteo, name-guard por valor exacto y assert_f7 en su postflight (P2-1/P2-2 del auditor atendidos).

**Replay en banco (condición 4 de Miguel): POST-PUBLISH inmediato y declarado.** Un banco creado
HOY muere por la enfermedad que esto cura (las 12 mudas). Tras publicar: crear branch y replay-ar
la historia completa; **2 versiones con hambre de datos declarada** que pueden exigir la receta
manual: `20260819211815` (su sonda exige domicilios existentes, líneas 263–289) y
`20260820190500` (exige contratos previos, línea 544). Cualquier fallo del replay se documenta
aquí por nombre — el cuerpo registrado NO se maquilla (historia primero). **⚠️ P1-1 del auditor
(30/08), declarado:** el camino POST exige md5+conteo EXACTOS, y si el runner del CLI del banco
divide con OTRA convención (RETOMAR-54: «merge re-registra statements sin `;`» — los nuestros SÍ
llevan su `;`), la 055000 abortará en el replay — **fail-closed, jamás corrupción**. Sonda barata
ANTES del replay completo: dejar que el runner registre UNA versión (la 191000, 6 sentencias) y
comparar su huella POR ELEMENTO contra `3390c367bf9b573b525c508ad21bd576`; si difiere (p. ej. el
runner divide sin `;` — RETOMAR-54), reconciliar documentado.

**🔬 SONDA DEL RUNNER — INTENTO 31/08 (~15:00–16:15 UTC): 3 de 3 bancos muertos ANTES de
nuestras migraciones; el diagnóstico pasó por refutación de Codex y quedó AJUSTADO (v2).**
Prod verificada sana antes de tocar nada (191 versiones · 0 mudas · la 191000 clava
`3390c367…` con 6 elementos — ojo: la fórmula lleva separador `'|'`, `md5(string_agg(md5(s),'|'
order by ord))`; sin el `'|'` sale `e6768388…` y es un falso rojo). Los tres bancos
(`sonda-runner`/`-2`/`-3`):
- `sonda-runner`: 37 min clavado en CREATING_PROJECT sin que el runner conectara jamás; el
  `reset_branch` lo marcó MIGRATIONS_FAILED sin dejar UNA conexión en postgres_logs.
- `sonda-runner-2` y `-3` (mismo patrón): el runner SÍ corre y muere en
  `relation "storage.buckets" does not exist`; en toda la ventana los servicios del branch
  nunca inicializaron (`TenantNotFound` ×62 en realtime_logs, health 400 en storage_logs,
  `storage.buckets` ausente ~30 min). Registro del banco creado con **0 versiones**;
  `crm`/`private` nunca nacen. status.supabase.com sin incidente de branching.
**Lo MEDIDO que reencuadra la P1-1:** la primera versión del registro es
`20260708000000_baseline_squash_portal` con **UN solo elemento** en `statements` — un dump
entero (contiene `-- Name: crear_contrato(jsonb, jsonb)` y referencias a `storage.buckets`).
Lo que los logs del banco 2 muestran ejecutándose con cabecera pg_dump es EXACTAMENTE contenido
de esa baseline, no un «dump de plataforma» (la lectura inicial de esta sesión decía eso y SE
RETRACTA). El fallo cae DENTRO de la baseline, en su dependencia de `storage.buckets`.
**Refutación de Codex (2 pases, 31/08) — lo que TUMBÓ del diagnóstico inicial:** ① la
causalidad «storage roto → runner muere» NO está probada, solo hay simultaneidad — podría ser
orden normal de arranque donde el restore corre antes del bootstrap de storage (P0); ② «el
runner divide la baseline con su propia convención» NO está demostrado — ver un CREATE FUNCTION
suelto es compatible con que el emisor ya lo entregue por tramos (P1); ③ «nada cambió salvo la
Ola R» es falso — entre el banco sano del 16/08 y hoy entraron ~90 archivos de migración (P1);
lo que SÍ se sostiene: el fallo ocurre ANTES de alcanzar cualquiera de las 12 versiones de la
Ola R, así que la Ola R no es la causa del stack observado; y la baseline n=1 ya pasó limpia en
bancos reales (16/08), no es defecto intrínseco (P2).
**Protocolo del PRÓXIMO intento (diseño de Codex, mejor que repetir a ciegas):** capturar
timestamps de (a) primer SQL del restore, (b) primer error `storage.buckets`, (c) primera salud
válida de storage y realtime — si storage inicializa ANTES del replay y el replay muere igual,
el sospechoso pasa a ser el registro; si storage nunca inicializa, plataforma. (El control
«padre pre-Ola R» que Codex propone no es viable: el padre es prod y ya está reparada.)
Los 3 branches borrados (facturación cerrada). Si el patrón reincide con storage sano, ticket a
Supabase con los refs `ltyihtgfzllskhbgrycy`/`qwzasniwivfahqajnoxq`/`mqyfkiwjfjjdalqiqbbu` y
las horas de este bloque.
**P2-3 (para la próxima ola que copie el patrón de foto):** añadir `classoid` y `nspname` a las
claves de orden de comments_h/columnas_h — hoy cero empates medidos y el fallo sería solo falso
ROJO.

**Repo (la otra mitad de la ola):** 8 `aplicar-*.sh` + 2 fixtures huérfanos (medidos: los otros 3
tienen consumidores y SE QUEDAN) + `.tmp-verificar-atribucion-capital.mjs` → `scripts/archivo/`;
retirado el directorio vacío `functions/crm-contrato-pdf`. Cero referencias rotas; `gate:vigencia`
y `gate:f7` verdes tras el movimiento.

**Publicación (Miguel, con `!`, EN ESTE ORDEN):**
1. `npx supabase db query --linked --file supabase/migrations/20260831055000_crm_ola_r_las_doce_actas_mudas.sql`
2. `npx supabase db query --linked --file supabase/scripts/registrar-ola-r-version.sql`
Después la F7.1 (060000 + su registrador). Si se revierte: rollback + retirar a mano la fila
20260831055000.

## CONTRATO PDF · PLANTILLA v6 — DATOS ECONÓMICOS RESALTADOS (2026-09-01)

**Pedido de Miguel:** capital aportado (3.1), porcentaje de participación (3.4) y plazo (5.1)
en **negrita + MAYÚSCULAS** (negro, como los datos del inversionista), y el **domicilio del
inversionista en MAYÚSCULAS**. Aprobado sobre muestra renderizada con el renderer real.

**Migración:** `20260901115030_crm_contrato_pdf_plantilla_v6_datos_resaltados.sql` — espejo del
salto v4→v5 (20260818233729): default y CHECK de `private.contrato_pdf_jobs` a v6, CHECK de
`private.contrato_pdfs` acepta v6, re-estampa las reservas v5 sin bytes ni lease (14 en prod al
censar) y `private.crear_job_contrato_pdf_base` estampa `contrato-aep-17-v6` (cuerpo = el VIVO
de prod con la frontera documental, solo cambia el literal).

**Edge (mismo paquete, árbol `supabase/functions/crm-contrato-pdf-v2`):** constante v6;
`versionJobLegible` acepta ahora v2 **y v5** además de la vigente (los 69 sellados v5 + 3 v2
siguen legibles); template con las negritas/mayúsculas. 27/27 tests Deno, golden v6
`1b2e3d26e556…` (871.757 bytes). Función viva contrastada contra HEAD antes de tocar: 8/8
byte a byte (lección de la v8).

**Front:** `crm-api.ts` picklist de `template_version` acepta v6 (creación de contrato valida
la RESPUESTA → front primero, lección del 33.º release).

**Publicación (Miguel, con `!`, EN ESTE ORDEN):**
1. Front: `/release-crm` (tolerante a v5 y v6; sin esto, tras la migración toda creación
   moriría con «El servidor no confirmó completamente el contrato»).
2. Edge: `npx supabase functions deploy crm-contrato-pdf-v2` (v10; lee v5 sellados, aún no
   renderiza pendientes v5 → 409 reintentable, ventana de segundos).
3. BD: `npx supabase db query --linked --file supabase/migrations/20260901115030_crm_contrato_pdf_plantilla_v6_datos_resaltados.sql`
   (re-estampa pendientes y estampa v6 en adelante; cierra la ventana).
Rollback: redeploy del commit v9 + `create or replace` con literal v5 + re-estampar pendientes
v6→v5 (los CHECK ampliados pueden quedarse: son aditivos).

**✅ PUBLICADO 2026-09-01 (~17:15 UTC), en el orden previsto:** front release
`crm-20260901T170814Z-cf3812973845` (index-CALV-OvO.js verificado en disco del servidor,
caché purgada) → edge **v11** (contrastada byte a byte contra el árbol tras el deploy, 8/8)
→ migración por `db query --linked --file` (Miguel con `!`). Verificado contra prod después:
default v6, ambos CHECK con v6, `crear_job` estampa v6, 14 pendientes re-estampados (0 en v5),
sellados intactos (69 v5 + 3 v2, ledger 72).

## CONTRATO PDF · PLANTILLA v7 — PLAZO AJUSTADO A FIN DE MES (2026-09-01)

**Estado: ✅ frontend, Edge y migración EN PRODUCCIÓN; generación de las siete revisiones
pendiente de una sesión humana autorizada.** Migración local
`20260901184132_crm_contrato_pdf_plantilla_v7_plazo_fin_mes.sql`, registrada por Supabase como
`20260901191947`.

**Causa corregida:** la plantilla restaba un mes cuando el día de vencimiento era menor que el
día de inicio. Esa regla interpretaba `2026-08-31`→`2027-02-28` como 5 meses, aunque el formulario
había sumado correctamente 6 meses y ajustado el aniversario al último día de febrero. La v7
compara contra el aniversario ajustado al último día del mes de destino: 28/02 completa el plazo;
27/02 sigue siendo un mes incompleto. La misma corrección quedó en la Edge y en la copia local del
frontend.

**Frontera de datos:** los PDFs sellados permanecen inmutables. La migración amplía ambos CHECK,
fija default/creación/revisión en `contrato-aep-17-v7`, re-estampa únicamente reservas v5/v6 sin
bytes ni lease y crea revisión 2 pendiente para los 7 contratos sellados afectados:
`2026-01-001324`, `001332`, `001337`, `001342`, `001343`, `001344` y `001348`. Cada revisión nueva
copia el snapshot exacto de su v5; no vuelve a fotografiar datos actuales ni sobrescribe Storage.
El bloque falla cerrado si producción no presenta exactamente las siete revisiones 1 esperadas;
en un banco vacío es no-op.

**Estado productivo previo medido:** 3 sellados v2, 69 sellados v5, 2 sellados v6 y 14 pendientes
v6. Los siete afectados son v5/revisión 1. La migración v6 está viva en default, CHECK y funciones,
pero `20260901115030` no aparece en el registro remoto; por eso la v7 es autosuficiente y no depende
de que el runner aplique esa fila omitida.

**Pruebas:** 29/29 Deno (incluye 31/08→28/02, 31/08→29/02 bisiesto, día incompleto,
año bisiesto y lectura histórica v6),
44/44 Vitest focalizadas, typecheck del frontend y ensayo transaccional en PostgreSQL 16 con siete
fixtures + una reserva v6: `CONTRATO_PDF_V7_MIGRATION_OK`. Golden v7
`88665f229db4…` (871.757 bytes).

**Orden de publicación previsto:** front tolerante a v7 → Edge v7 (sigue leyendo sellados
v2/v5/v6) → migración v7 → generación/verificación de las siete revisiones nuevas. La ventana entre
Edge y BD solo afecta temporalmente a reservas v6 pendientes; la migración las convierte a v7.

**Publicación 2026-09-01:** frontend aislado sobre el commit vivo `3d89d2787123`, con solo
`crm-api.ts`, `contrato-pdf.ts` y su test modificados (los cambios paralelos del worktree principal
quedaron fuera). Release `crm-20260901T191336Z-3d89d2787123`, build
`build-20260901T191336554Z`, ZIP SHA-256 `ea1be181b247…`; versión estable en tres lecturas, JS y
CSS principales idénticos local↔producción, ZIP 404 en ambos dominios. Edge
`crm-contrato-pdf-v2` v12 activa, `verify_jwt=true`, fuente remota con v7 y
`diaAniversarioAjustado`; smoke sin JWT 401. Migración aplicada tras preflight 7/7: default v7,
trigger de inmutabilidad activo, 14 reservas v6→v7, 7 revisiones 2 v7 pendientes, revisiones 1 v5
preservadas y advisors sin ERROR. No se acuñaron los siete bytes todavía: Browser no expuso una
sesión y se rechazó usar impersonación o llaves administrativas como usuario.

## CRM · LANDING/FORMULARIO EN ALTA MANUAL, FUERA DEL DIVISOR (2026-09-01)

**Estado: implementado y validado localmente; no publicado en producción.** Migración
`20260901185600_habilitar_landing_formulario_alta_manual.sql`.

**Regla confirmada por Miguel:** `landing` y `formulario` vuelven a estar disponibles en el
formulario manual. Ese lead cuenta en cartera, trazabilidad, cierres, numerador y cualquier otra
métrica aplicable; la única excepción es el divisor mensual del analista. El mismo origen llegado
por el puente automático conserva el divisor normal. Como consecuencia válida, un analista puede
superar 100 % de conversión.

**Implementación sin funciones nuevas:** se añadió el sello inmutable
`crm.leads.alta_manual boolean not null default false`. La RPC existente
`crm.crear_lead_si_disponible` lo fija en `true`; el importador automático omite la columna y toma
`false`. El sello no se deduce de `creado_por`, cuya FK es `ON DELETE SET NULL`. La función
existente `private.conversion_episodios` solo cambia la pierna `recibido`: manual +
landing/formulario produce `aporte_divisor=0`. La pierna `cierre` queda intacta y conserva
`aporte_numerador=1`. No cambió ninguna firma ni apareció una sobrecarga.

**Front y pruebas:** el selector ofrece LANDING/FORMULARIO a vendedor, supervisor y gerencia;
Referido sigue reservado al vendedor. Vitest focalizado 69/69 y typecheck verdes. En PostgreSQL
del stack Docker se aplicó la migración sobre una base desechable y se ejercitaron cuatro leads:
LANDING/FORMULARIO manuales dieron divisor total 0, un cierre manual dio numerador 1, y los dos
controles automáticos dieron divisor total 2 (`MIGRATION_OK`). La base y los archivos temporales se
eliminaron al terminar; el Supabase local principal no se modificó.

**Orden de publicación previsto:** migración de BD primero (compatible con el front anterior) y
después el frontend. Hasta publicar ambos, la funcionalidad no está completa para usuarios.
---

## 20260829183627 · `crm_ficha_360_scope_historial`

🟢 **DESPLEGADA Y VERIFICADA EN PRODUCCIÓN EL 2026-08-29.** Reintegra la Ficha
360 como panel lateral de Mi cartera sobre el núcleo ya desplegado, sin portar
en bloque la rama preview. El registro remoto es
`20260829195528_crm_ficha_360_scope_historial`.

La migración es forward-only y expone `crm.cliente_ficha_fn(uuid)` con la
proyección mínima de identidad y contacto, scopeada por
`private.cliente_ids_visibles_crm()`; alinea el historial y las operaciones con
la asignación actual del cliente y registra las reasignaciones como actividad.
No redefine contratos, tareas, numeración, PDF ni writers de cartera.

La única intervención sobre `public` es un trigger `AFTER UPDATE OF
asesor_perfil_id` en `public.perfiles`; no cambia columnas, constraints,
policies ni privilegios de `public`. Su oráculo versionado se ejecuta mediante
`npm run test:ficha-360:db` y el preflight de solo lectura mediante
`npm run test:ficha-360:db:preflight`.

El frontend completo se publicó primero como
`crm-20260829T195236Z-7cfc31bb8ea8` y luego con las mejoras UX como
`crm-20260829T220216Z-e8ac4262b75d` (`build-20260829T220216363Z`). El detalle
operativo está en [[Deploy Ficha 360 2026-08-29]] y
[[Mejoras UX Ficha 360 2026-08-29]].

---

## P-055 · EL LECTOR GLOBAL NO VE LO BORRADO (2026-09-01/02)

🟢 **EN PRODUCCIÓN el 2026-09-02, registros 197 y 198.** Publicada por Miguel con
su `!` por pieza, en el orden migración → registrador ×2. Registro del servidor:
198 versiones, **cero actas mudas**, 902 leads vivos intactos.

Son DOS migraciones y no una, porque el auditor RLS refutó que la primera
bastara (ver más abajo): `20260902040000_crm_lector_global_no_ve_borrados.sql`
(las 3 policies) y `20260902050000_crm_lector_global_definers.sql` (las 2
SECURITY DEFINER). Marchas atrás: `scripts/rollback-lector-global-borrados.sql`
y `scripts/rollback-lector-global-definers.sql` — **en orden inverso**, las
DEFINER primero, o quedarían más estrictas que la RLS.

**El hallazgo** lo destapó la primera corrida ejecutable de `test:rls` (banco a
paridad total, 01/09): `leads_select` exige `activo = true` a analistas,
supervisores y gerencia, pero la rama `es_lector_global()` va FUERA de ese
candado — con 7 leads vivos, gerencia veía 7 y el Directorio veía 55, los
soft-borrados incluidos, con su PII (DNI, nacimiento, género). La MISMA forma
está copiada en `tareas_select` (qual idéntica al byte) y en
`actividades_select` (el predicado de leads dentro del EXISTS). Decisión de
Miguel el 01/09: «arregla las dos» → el lector global ve TODO lo vivo y NADA de
lo borrado, igual que gerencia.

**Qué hace:** mete la rama del lector dentro del candado `activo = true` en las
TRES políticas, conservando letra a letra las ramas de analista/bandeja/gerencia
(initplans incluidos). `equipo_select` se deja a propósito: ver miembros dados
de baja es la semántica del P04 (revocado ≠ ajeno).

**Defensas:** preflight fija por md5 las tres cláusulas vivas
(`4fc91b80…` ×2, `40b0cd19…`) y aborta si el mundo se movió; postflight de
CONDUCTA en la misma transacción — con los claims de un directorio real: ve
exactamente los vivos y CERO borrados en leads, tareas y actividades. Ensayo en
el banco: `POSTFLIGHT OK: lector global ve 7 vivos de 88 totales y 0 borrados`;
la marcha atrás restaura las tres cláusulas **al byte** (md5 original
verificado en su propio postflight).

### 🔴 No bastaba con la RLS: dos puertas DEFINER

El auditor RLS dio GO **con tres hallazgos altos**, y el primero invalidaba el
alcance: dos funciones `SECURITY DEFINER` llevan el MISMO espejo copiado y la
RLS no las alcanza, así que la regla habría quedado incumplida por dos puertas:

| Función | Qué servía a un lector global |
|---|---|
| `crm.actividades_del_ambito_fn()` | timeline de 365 días (hasta 10 000 filas), con el `detalle` de las conversaciones de leads borrados |
| `crm.cierres_estado_fn(uuid[])` | canal, `anulado_en` y motivo de sus cierres |

Medido en el banco **con la forma vieja**: `timeline = 195 filas` de leads
borrados y `cierres = 4`. Con la enmienda: **0 por las tres puertas** y las 26
actividades vivas intactas, con el ciclo aplicar → marcha atrás → re-aplicar
en verde. Es el caso de libro de la «desincronización silenciosa del predicado
copiado» contra la que avisa la propia suite.

### Tres errores propios que cazaron los guardias

1. **El postflight de la primera migración era TAUTOLÓGICO**: contaba las
   actividades de leads borrados con un `join crm.leads` bajo `authenticated`,
   donde la policy recién corregida ya los ocultaba → 0 siempre, aunque
   `actividades_select` hubiera quedado rota. La sonda buena (segunda
   migración) calcula los ids como `postgres` y pregunta SOLO a
   `crm.actividades`.
2. **`cierres_estado_fn` se reescribió de memoria y habría quedado ROTA**:
   perdía el gate `puede_acceder_crm()`, el `order by` del `jsonb_agg`, el
   mensaje exacto del tope de 200 y hasta la FORMA del payload
   (`canal`/`anulado_en`/`motivo`). Lo destapó la marcha atrás al no cuadrar la
   huella. 🔑 **Una función viva no se reteclea: se copia del volcado y se toca
   lo justo** (31 líneas, verificado con diff).
3. **La marcha atrás tampoco era fiel al byte**, por lo mismo. Reconstruida del
   volcado; su postflight vuelve a dar `d1423797…` exacto.

### ⚠️ Lo que esta publicación NO probó

En producción **no hay ni un perfil `directorio` ni un solo lead borrado**
(medido: 0 y 0; roles activos = admin, analista, cliente, comercial,
superadmin). Los postflights de conducta cayeron por tanto en su rama de aviso
y solo dejaron las anclas estructurales. **La garantía real es la equivalencia
byte a byte con el banco**, donde la conducta sí se midió:

| Pieza | Huella (banco == producción) |
|---|---|
| `leads_select` / `tareas_select` | `073deaeb…` |
| `actividades_select` | `e80e3af9…` |
| `actividades_del_ambito_fn` | `c2f9a322…` |
| `cierres_estado_fn` | `bcaf7f54…` |

🔑 Se cerró la puerta **antes de que llegara el visitante**: el rol Directorio
está previsto y los leads se borran por limpieza. **Cuando exista el primer
Directorio real, repetir la sonda de conducta contra producción.**

### En el mismo acto (suite y front)

- El bloque «fuera de roster» dejó de asumir mes virgen. Codex refutó la
  primera versión: medía el ledger crudo, y el servidor NO define así «analista
  del mes» — lo define con `private.conversion_mensual_por_vendedor`, cuya base
  mete cierres y operaciones por FULL OUTER JOIN. Ahora se pregunta a **la misma
  función** (y la columna era `analista_id`, no `vendedor_id`).
- El **candidato del tercer estado pasa a ser REUTILIZABLE**: ya no se exige
  virginidad (solo divisor y cierres en cero) y las aserciones son DELTAS. Cada
  corrida quemaba un analista virgen y el pool se agotó (medido: 0 de 6); esto
  lo cierra sin tocar el ledger INSERT-only ni inflar el roster.
- **El front seguía en la conducta vieja** (`store.tsx` daba los borrados al
  Directorio) **y su test LA EXIGÍA**. Espejo alineado y test invertido.
  ⏳ El código está commiteado pero **NO publicado**: hasta el próximo
  `/release-crm`, la pantalla del Directorio pide algo que el servidor ya no da.
- **Matriz permanente**: bloque `testLectorGlobalNoVeBorrados` con las tres
  puertas más la excepción deliberada del P04, para que nadie «arregle por
  simetría» lo que es semántica.

**Veredicto de la suite:** `✅ RLS OK — 1291 aserciones; gate aprobado`, cero
rojos — la primera corrida completamente verde de su historia. Front: 184
archivos, 2488 tests.

---

## 20260902070052 · `crm_ranking_poblacion_mes_calendario`

🟢 **DESPLEGADA, REGISTRADA Y VERIFICADA EN PRODUCCIÓN EL 2026-09-02.** Corrige
los rankings de Gerencia y Supervisión con una sola semántica mensual: la fecha
final elige el mes calendario; un histórico usa del día 1 al último día y el
mes vigente, del día 1 hasta hoy en Lima.

No crea funciones comerciales independientes. Reemplaza únicamente los
núcleos existentes `crm.conversion_mensual_fn(date)` y
`crm.metricas_conversiones_equipo_fn(date,date)`. Para un histórico abierto
ambos toman la última revisión publicada de `meta_periodos/metas_vendedor`; si
el mes ya cerró, toman la identidad y el alcance sellados por
`private.cierre_mes_visible`; el mes vigente mantiene el roster vivo.
`crm.cumplimiento_metas_fn(date)` no cambió porque ya era la autoridad mensual
de metas y capital.

**Registro y estructura productiva:** ledger remoto
`20260902070052_crm_ranking_poblacion_mes_calendario`, un cuerpo con MD5
`edb08d2a2dcbdb41caaf1f8699b4d5d1`. Huellas posteriores: conversión
`016f19d203bb552696d5270ee8c4884e`, métricas de equipo
`0631448b64810fc4d0a5dc936016debf`; cumplimiento conservó
`b76cc20b5b88604308a9974fc1948a7a`. Owner `postgres`, volatilidad `STABLE`,
`SECURITY DEFINER`, `search_path=''`, ACL esperadas y ninguna ejecución para
`anon/public`. Supabase Advisors: cero errores.

**Oráculo con identidad autenticada:** las tres fuentes devolvieron poblaciones
idénticas. Gerencia: agosto 16/16/16 y setiembre 17/17/17; un Supervisor real:
agosto 8/8/8 y setiembre 10/10/10. El caso de agosto confirma la foto: 16
miembros frente a 17 del roster actual.

**Edge complementaria:** la función existente `crm-tipo-cambio` pasó de v7 a
v8, sin cambiar `verify_jwt=true`. Acepta un `fecha_corte`, toma las últimas
siete fechas publicadas por BCRP hasta ese corte y lo devuelve explícitamente.
El corte 2026-08-31 produjo 3,3491 (21–31/08); futuro 400 y sin JWT 401.

**Gate:** 2.524/2.524 unitarias; E2E completo 113 aprobadas, 26 omitidas, cero
fallidas; focal Gerencia/Supervisión 9/9; Edge 30/30 Node y 5/5 Deno, más
formato, lint y typecheck. Tres auditorías independientes cerraron sin
bloqueadores. `CRM app quality` terminó verde (`33644821968`). El primer
preflight RLS sí destapó una diferencia del runner: Deno 2, con `package.json`,
usaba `nodeModulesDir=manual` y no instalaba `npm:openai`, dependencia
transitiva solo de `edge-runtime.d.ts`; las 30 pruebas Node habían pasado y no
se abrió ninguna conexión remota. `eca2dcb85cef` añadió auto-instalación con
lock congelado y registró el lock completo. El comando pasó desde checkout y
caché vacíos, y el CI `33646311542` cerró verde.

**Rollback probado/preservado:** `/private/tmp/rollback-ranking-20260902070052.sql`
(SHA-256 `a863055cb91da437787cc072b2157e4c6892664d1b65797a7d9ac4edbac86a8e`),
volcado previo `/private/tmp/crm-before-ranking-20260902.sql` (SHA-256
`8d5a51f9338bdb5491788b56482f4d24d4b5a833531b142ba13f200049ee96e8`) y
fuente Edge v7 en
`/private/tmp/crm-tipo-cambio-v7.RYpJr3/supabase/functions/crm-tipo-cambio/index.ts`
(SHA-256 `ae395cbc1a09d081382c72d7143988e548616d4228c6157815eaf33ea544a8b1`).

## 20260902190000 · `crm_mi_cartera_por_mes_de_cierre`

**Estado: APLICADA EN PRODUCCIÓN el 2026-09-02** (`supabase db query --linked
--file`, autorizada por Miguel). Front construido y con preflight pasado; su
subida la lanza Miguel con `/release-crm`.

**Qué.** `crm.contratos_cartera` gana una columna de lectura,
`fecha_cierre_comercial`, para que «Mi cartera» pueda partir sus bloques por el
mes en que el analista VENDIÓ en vez del mes en que TECLEÓ.

**Por qué.** La pantalla agrupaba por `creado_en` desde el 14/08, cuando la
cuota también medía por `creado_en`. El P-055 movió la cuota a
`fecha_cierre_comercial` y la pantalla se quedó atrás. El 02/09/2026, nueve
cierres de agosto registrados el 01/09 (S/ 517.500 + US$ 37.000, de MERLYS
GARCIA, FIORELLA RUIZ y KELLY VEGA) aparecen bajo «Septiembre 2026» mientras la
cuota los cuenta en agosto. El caso que lo destapó: contrato `2026-01-001348`,
cerrado el 31/08 y tecleado el 01/09 a las 11:00 de Lima. En toda la base son
164 de 499 contratos los que caen en un mes distinto según qué fecha se mire, y
la deriva va SIEMPRE en la misma dirección: se registra después de vender.

**Sin DROP de nada vivo.** La migración 20260829182500 había descartado ampliar
esta vista porque `contratos_cartera_fn` es `security definer` con
`returns table(...)` y añadirle una columna exige DROP + CREATE. Sigue siendo
verdad, y por eso NO se toca: se ENVUELVE en `crm.contratos_cartera_v2_fn()`,
que pregunta a la función viva (donde vive la regla de quién ve qué contrato) y
le pega la fecha con un join 1:1 por PK. La vista se rehace con
`create or replace view`, que SÍ admite añadir una columna al final conservando
OID, grants y `security_invoker`.

Las otras dos premisas de aquella nota ya no se sostenían, y se comprobó contra
producción antes de escribir esto: `cronograma_contrato_fn` y
`titulares_contrato_fn` llaman a la FUNCIÓN, no a la vista; solo
`atribucion_contrato_fn` nombra la vista, desde el cuerpo y sin dependencia
registrada (`pg_depend` sobre la vista devuelve vacío).

**Lo que NO toca:** la cuota, los rankings, `capital_episodios` ni la
posibilidad de retro-datar un cierre. Esa puerta se deja ABIERTA a propósito
(Miguel, 02/09): quedan clientes antiguos sin registrar. El alta sigue
calculando `least(fecha_inicio, día de registro)` y el mes sellado sigue siendo
corregible solo por Gerencia.

**La trampa del front (la cazó Codex refutando).** `fecha_cierre_comercial` es
un DATE. Pasada por el conversor de instantes a Lima, `'2026-08-01'` se leería
como medianoche UTC = **31 de julio**: 49 contratos reales cerrados en día 1 se
habrían ido al mes anterior. Por eso `cartera-meses.ts` estrena `mesDeCierre()`,
que RECORTA la cadena y no convierte nada, con su test de regresión.

**La señal que no se pierde.** El mes de registro es la única fecha que nadie
puede mover, así que no se tira: `registradosEnOtroMes` cuenta cuántos cierres
del bloque se teclearon fuera de su mes y la cabecera lo declara, igual que ya
avisaba de los registrados por otra persona.

**Gate del front (verde, 02/09):** `npm run check` completo — 2.529/2.529
unitarias, lint, typecheck, coverage, build, bundle y duplicación.

**Verificado tras aplicar (no dado por bueno, contado):** la vista quedó con 25
columnas y la 25ª es `fecha_cierre_comercial`; las 24 originales no se movieron;
`authenticated` y `service_role` conservan su SELECT; `security_invoker=true`
sigue puesto; PUBLIC no puede ejecutar la envoltura (ACL crudo, `grantee = 0`);
`search_path` guardado como `search_path=""`; y `crm.contratos_cartera_fn()`
sigue viva e intacta.

**Advisors:** cero de nivel ERROR. El único aviso nuevo es
`authenticated_security_definer_function_executable` sobre la envoltura — el
MISMO que ya llevaba `contratos_cartera_fn` y por el mismo motivo: el gate vive
dentro de la función, que por eso es DEFINER.

**Artefacto:** `crm-20260902T170713Z-e9d9a283175b` (SHA-256
`23c6c8fef2cd50a687003620eec001e6cbdb706236c21eea59851effe3aa24e7`), construido
desde un worktree aislado en `e9d9a28` porque el taller tenía cambios sin
confirmar de otra sesión (los del puente de leads). Preflight:
`live=build-20260902T145407204Z/5b1c808f9138 → candidate=e9d9a283175b`, OK.

**Rollback preservado:** `rollback-mi-cartera-20260902190000.sql` (SHA-256
`2969778bbe462b205da1c3bdf4d2d4b89f123f2f1a8f6a57c00b79a5527df39c`). ⚠️ Si el
front ya está publicado pidiendo la columna, revertir el servidor deja la
cartera en blanco: primero el front.

**Front PUBLICADO el 2026-09-02** por Miguel con `/release-crm` desde la carpeta
del subproyecto (el skill no figura desde la raíz). Se le pasó el ZIP ya
construido y verificado en vez de dejarle rehacerlo: el taller estaba sucio por
OTRA sesión en curso (20 archivos de conversión/ranking a medio editar) y un ZIP
nuevo habría metido ese trabajo ajeno en la foto.

**Verificado contra lo VIVO, no contra el artefacto** (la lección de
«un parche que solo vive en el artefacto no existe»): los **51 archivos servidos
por crm.miavance.com son byte a byte idénticos** al manifiesto —
`identicos=51 distintos=0 inaccesibles=0` contrastando SHA-256 fichero a fichero.
`version.json` vivo: `build-20260902T170712941Z`.

**Pendiente:** gate `test-rls.mjs` y E2E, que no se corrieron porque el árbol
compartido no está limpio; correrlos cuando la otra sesión asiente lo suyo.

## 20260902200000 · `crm_g0_reloj_hoy_es_lima`

**Estado: ESCRITA, EN REFUTACIÓN POR CODEX.** Autorizada por Miguel el 02/09
(«ok sigamos hazlo»), incluido el OK para tocar `public.dashboard_admin_metricas`.

**Qué.** En cuatro funciones de lectura, «hoy» deja de ser la fecha del servidor
(UTC) y pasa a ser la fecha civil de Lima: `current_date` →
`(now() at time zone 'America/Lima')::date`. Ocho sustituciones en total
(capital 2, pagos 1, vencimientos 3, dashboard del Portal 2). **Nada más
cambia**: los cuerpos se generaron desde `pg_get_functiondef` de las funciones
vivas y se aplican con `create or replace`, que conserva OID, grants y
dependencias. El `search_path` no vacío de `metricas_pagos_mes_fn` se conserva
tal cual — es otra decisión y otra migración.

**Por qué.** Lima va 5 h por detrás de UTC: de 19:00 a 23:59 el servidor ya
está en «mañana». El oráculo R3 del G0 (02/09, READ ONLY, un año día a día con
`cd = D` y `cd = D+1`, fidelidad 0 contra el núcleo) midió la consecuencia:
Vencimientos falla a DIARIO (282 de 365 días con `p_dias = 90`: lo que vence hoy
desaparece de «por vencer» a las 19:00 y lo de D+p_dias entra un día antes);
Capital mensual pierde el mes más antiguo de su ventana de 12 cinco horas antes
el último día de cada mes (primer fallo visible: 31/12/2026); el tablero del
Portal marca «vencido» desde las 19:00 lo que vence hoy. Medido para ESTA noche
(02/09): nada vence hoy, pero 3 contratos entrarían un día antes en la ventana
de 90 días y 1 en la de 365.

**Guardas.** Preflight: `md5(prosrc)` de cada función debe ser el que se leyó al
generar la migración — si alguien la cambió entre medias, aborta en vez de
pisarla. Postflight: sin `current_date`, con la fecha de Lima, DEFINER, PUBLIC
fuera, `search_path` y ACL idénticos a los previos.

**Prueba de no-regresión.** Foto «antes» de las cuatro salidas a las **12:50 de
Lima** (claims de Gerencia, READ ONLY, md5 del jsonb ordenado): a esa hora
fecha-servidor = fecha-Lima, así que la foto «después» tiene que ser IDÉNTICA.
`capital_12 643e0b0a…` (40 filas) · `venc_365 67049435…` (23 filas) ·
`venc_90 71e0ba17…` · `pagos_12 c95221c8…` (157 filas) · `dashboard 09daf7a0…`.

**Rollback preservado:** `rollback-g0-reloj-20260902200000.sql` con los cuatro
cuerpos vivos tal cual estaban (SHA-256 `48e6a687…93ae4`).

**Enmienda (mismo día):** el primer intento de aplicar abortó en su propio
postflight — escribí los booleanos de la huella de metadata como `true/false` y
Postgres los imprime `t/f`; todo lo demás coincidía byte a byte. Como el archivo
ya estaba confirmado y el hook del CRM no deja editar migraciones versionadas,
la corrección vive en **`20260902201000_crm_g0_reloj_hoy_es_lima_v2.sql`**, con
los CUATRO cuerpos idénticos (verificado por `diff`) y solo la huella cambiada.
`20260902200000` queda en el repo **sin aplicar y sin poder aplicarse nunca**:
su preflight exige el md5 viejo (que dejará de existir) y su postflight una
huella imposible. Lección: el guard hizo exactamente su trabajo — abortó la
transacción entera y no dejó nada a medias.

**Codex refutó la migración antes de aplicarla** (sesión `01a0633f…`, ~25 min,
solo lectura contra producción): A1 equivalencia y planes/índices CONFIRMADA
(`Function Scan` ya era el plan por ser DEFINER con `SET search_path`; los tres
índices de fecha se conservan); A2 sintaxis y precedencia de las 8 sustituciones
CONFIRMADA (sin doble conversión); A3 `create or replace` conserva OID/ACL/deps
CONFIRMADA (0 dependientes, 1 sobrecarga por nombre); A4 alcance del G0
CONFIRMADA (quedan 10 usos de `current_date` AJENOS al núcleo: pagos del Portal,
productos, F7 — no son de esta migración). **A5 REFUTADA**: el postflight de
substrings no acreditaba una recreación fiel → ahora exige md5 posterior EXACTO
por `regprocedure` + huella completa de metadata (owner, lenguaje, volatilidad,
paralelismo, strict, leakproof, coste, filas, resultado, `search_path`, ACL con
grantor, comentario, dependientes) + cuenta = 4 + sin sobrecargas. **A6
REFUTADA**: dos fotos en transacciones distintas no prueban paridad → la paridad
va DENTRO de una sola transacción `REPEATABLE READ` con los mismos claims, foto
antes → reemplazo → foto después, y aborta si difieren o si es hora de borde.
Añadido además `pg_advisory_xact_lock` de exclusión entre despliegues.

**APLICADA EN PRODUCCIÓN el 2026-09-02 a las 15:00 de Lima** (la lanzó Miguel
con `db query --linked --file` sobre el envoltorio; el clasificador de permisos
bloqueó al modelo, y bien). Resultado: **`PARIDAD_OK`** — dentro de UNA
transacción `REPEATABLE READ` con claims de Gerencia, las cinco huellas antes y
después del reemplazo fueron idénticas (`venc_90 71e0ba17…` coincide además con
la foto de las 12:50; las otras cuatro cambiaron respecto a esa foto porque la
base siguió recibiendo contratos entre medias — exactamente el motivo por el que
Codex tumbó la comparación entre transacciones).

**Contado después, en lectura aparte:** md5 de `prosrc` EXACTOS
(`a25667f6…`, `88c79901…`, `dbafa025…`, `df2c28bc…` — los mismos que Codex y yo
calculamos por separado), cero `current_date`, la fecha de Lima 2/1/3/2 veces,
OIDs intactos (20368/20369/20371/18403), `search_path` sin cambios (pagos sigue
con el suyo), comentarios conservados.

**Pendiente del G0:** recapturar las huellas y repetir el oráculo como **R4**
para firmar; la próxima verificación real es esta noche de 19:00 a 23:59 Lima
(Vencimientos ya no debe mover nada) y el 23/09 (150 000 PEN que vencen ese día
tienen que seguir en «por vencer» hasta medianoche de Lima).

## 20260902202247 · `crm_ranking_foto_mensual_coherente`

**Estado: APLICADA EN PRODUCCIÓN el 2026-09-02.**

**Qué.** Unifica la población mensual de Conversión, Cumplimiento/Capital y
Cosecha sin crear calculadoras nuevas. Reemplaza en sitio seis núcleos
existentes: `private.produccion_mes_por_vendedor`, `crm.cerrar_periodo`,
`crm.conversion_mensual_sin_cartera_fn`, `crm.conversion_mensual_fn`,
`crm.cumplimiento_metas_fn` y `crm.metricas_conversiones_equipo_fn`. La foto
existente `crm.cierre_mes_vendedor` gana `cartera jsonb NOT NULL`; no aparece
ninguna tabla, función ni RPC paralela.

**Regla comercial.** Un mes calendario histórico abierto usa la última
revisión publicada de metas como roster. Al cerrar, la foto suma también a
quien produjo o tuvo cartera aunque no tuviera meta: conserva vendedor y
supervisor, pone sus objetivos en cero y no pierde su producción real. Una vez
cerrado, Conversión y Cumplimiento leen la cartera congelada, no el presente.
Las fórmulas y porcentajes no cambian.

La producción atribuida explícitamente a un supervisor, Gerencia, coordinación,
directorio o una identidad ya fuera del equipo tampoco se borra ni se disfraza
de analista: queda nominada en `periodos_cerrados.cobertura.fuera_ranking` y
sale solo para Gerencia en `cumplimiento_metas_fn.fuera_ranking`. Suma a los
totales empresariales de capital, cartera y conversión, pero no materializa una
fila en `vendedores`/`responsables`, no aumenta el contador de analistas y no
recibe puesto. El frontend la muestra bajo «Producción fuera del ranking».

**Contrato de coherencia.** Las tres respuestas mensuales publican el mismo
`revision` y `cierre`; los rangos libres de Cosecha declaran ambos como `null`.
Esto permite que Gerencia y Supervisión bloqueen una mezcla de fotos distintas
en vez de enseñar rankings contradictorios.

**Guardas.** Preflight exige cero meses cerrados y las seis huellas exactas de
producción. El cierre conserva el candado global, el candado por período,
`private.saldar_ajustes` y añade un lock compartido del roster durante la foto.
Postflight comprueba owner, lenguaje, volatilidad, DEFINER, `search_path`, ACL,
columnas no nulas y el censo analítico sellado. La transacción entera revierte
si una sola condición no coincide.

**Orden de publicación.** `fuera_ranking` es opcional en el contrato del
frontend para aceptar tanto el servidor anterior como el nuevo. Por eso el
bundle compatible se publica primero y la migración después; el orden inverso
haría que el `strictObject` del bundle vivo rechazara la clave nueva.

**Refutación y pruebas.** La revisión independiente encontró tres huecos antes
del deploy: población histórica duplicada fuera del núcleo base, bajas
históricas descartadas al final y ausencia del candado global en el preflight.
Los tres quedaron corregidos. La migración se aplicó desde cero sobre un dump
combinado fresco de `public,crm,private`; el censo terminó en
`30/30, 0 sin declarar`. El oráculo conjunto ejecutó altas, bajas,
transferencias, ámbitos de Gerencia/Supervisor, foto abierta/cerrada, aislamiento
de cartera y un cierre real con S/ 43 210 de producción sin meta: objetivo cero,
supervisor preservado, seis dimensiones y cartera completa. Añade inversiones
de supervisor en mes abierto y cerrado, prueba que quedan nominadas fuera del
ranking, que solo Gerencia las ve, que el total empresa las conserva y que el
contador/las filas rankeables no cambian. Resultado:
`TEST-RANKING-POBLACION-MENSUAL: TODO VERDE`.

**Verificación viva.** Septiembre respondió revisión 1 y 17 filas rankeables;
agosto respondió revisión 14, 16 filas rankeables y tres identidades nominadas
fuera del ranking (dos supervisores y un vendedor sin meta). Ninguna identidad
externa recibió puesto. Capital externo conservado: S/ 65 000, USD 12 640 y tres
operaciones de cartera. El frontend compatible quedó publicado antes del
servidor y la historia oficial de migraciones quedó registrada.

## 20260902224847 · `crm_conversion_total_analistas_solo_ranking`

**Estado: APLICADA EN PRODUCCIÓN el 2026-09-02.**

**Qué.** Corrige una única expresión dentro del núcleo existente
`crm.conversion_mensual_sin_cartera_fn(date)`. En el mes abierto,
`total.analistas` sumaba también las identidades agregadas en
`cobertura.fuera_de_roster`, aunque esas personas no existían en
`responsables`. El contador ahora es exactamente el número de filas que pueden
competir. No se crea ninguna función, tabla ni RPC.

**Qué no cambia.** Divisor, numerador, cierres, porcentaje y cartera continúan
sumando toda la actividad empresarial, incluida la atribuida a supervisores u
otras identidades externas. La corrección solo evita que dichas identidades
inflen el número de analistas o se interpreten como participantes del ranking.

**Guardas y prueba.** Preflight exige la huella productiva exacta del núcleo y
que la expresión antigua aparezca una sola vez. Postflight fija la nueva
huella, firma, owner, volatilidad, `SECURITY DEFINER`, `search_path`, ACL y
resella el censo analítico. El oráculo incorpora un supervisor con episodio real
fuera del roster: antes del parche reproduce `2 analistas / 1 responsable` y
falla; después devuelve `1 / 1`, conserva el divisor externo y termina
`TEST-RANKING-POBLACION-MENSUAL: TODO VERDE`.

**Verificación viva.** Agosto pasó de `18 analistas / 16 responsables` a
`16 / 16`; divisor `823`, numerador `55,9` y conversión `6,79 %` quedaron
idénticos. Sus dos supervisores externos siguen declarados en cobertura y las
tres identidades de producción externa permanecen fuera de las posiciones, con
S/ 65 000, USD 12 640 y tres operaciones conservadas. Septiembre quedó en
`17 / 17`, divisor `182`, numerador `9` y `4,95 %`. La huella productiva final
es `a64a30be3182589c02553759728276f2`, el censo terminó `30/30` y la historia
oficial registró nueve bloques bajo el nombre correcto.

**Registro en `schema_migrations` (03/09, madrugada):** las dos migraciones
aplicadas hoy con `db query` (`20260902190000` y `20260902201000_v2`) quedaron
registradas por Miguel con el `INSERT` que preparó la sesión f3 y esta sesión
cotejó byte a byte contra los archivos confirmados. Verificado en lectura por f3:
total **203**, ambas con 1 statement, **`20260902200000` ausente** (como debe),
huella del registro `c6dad2fd…`.

## 20260903160000 · `crm_f1_identidad_empresas_inversiones`

**Estado: ESCRITA y ENSAYADA EN BANCO (rama `feat/multiempresa-f1-expand`), REVISADA (auditor-rls + Codex) — GATE G1 EN VERDE. SIN APLICAR A PRODUCCIÓN (falta el `!` de Miguel).** Autorizada por Miguel el 03/09 («desarrolla la fase 1»). NO se aplica a producción sin ensayo en banco (G1: reconstruíble) y su `!`.

**Qué.** F1 del plan multiempresa: crea el esqueleto relacional de «una persona, varias inversiones, varias empresas», TODO aditivo, nullable y APAGADO (flags off). 10 tablas nuevas en `crm` (empresas, inversionistas, inversionista_identificadores, inversionista_leads, inversionista_responsables, inversionista_fusiones, inversiones, inversion_titulares, multiempresa_idempotencia, multiempresa_flags), columnas nullable `inversionista_id` en `crm.leads` y `crm.cierres_externos`, y la primitiva `private.inversionista_resolver(tipo,documento)` sin EXECUTE a la API. No toca `public.*` (salvo FKs de lectura a perfiles), no crea Auth/Portal, no toca `private.capital_episodios`.

**Por qué.** Hoy la persona se escribe por cuatro caminos que no se conocen entre sí y un lead solo admite una inversión externa (`UNIQUE(lead_id)`). F1 pone el ancla de identidad y el registro relacional para que F2 (backfill) y F3 (puertas canónicas) enganchen sin duplicar.

**Guardas.** Preflight: exige dependencias y aborta si `crm.inversionistas` ya existe. RLS activa en las 10 tablas; CERO grants a la Data API (anon/authenticated/service_role); acceso por RPC definer en fases siguientes. Auditoría en las 10; la tabla de identificadores usa el auditor ENMASCARADO (`private.log_audit_sin_secretos`) para que el documento nunca viaje en claro a `public.audit_log`, el resto usa `private.log_audit_crm`. Índices en FKs y columnas de RLS; únicos parciales que arbitran la carrera del resolver (identificador vigente), un lead por persona, un responsable abierto, una fuente por inversión. Postflight cuenta lo que quedó (10 tablas, RLS, 0 grants, resolver privado, 3 empresas, flags apagadas, enlaces vacíos, núcleo intacto por md5).

**Gate G1 — ENSAYADO EN BANCO el 03/09/2026 (VERDE).** Branch de Supabase efímero (creado, ensayado y borrado; ~centavos). El auto-replay se detuvo en 86/203 por el preflight anclado a producción de `20260812000259` (el `MIGRATIONS_FAILED` conocido), así que se trajeron las dependencias REALES de F1 al branch (tabla `crm.cierres_externos` con su forma real, los auditores reales `enmascarar_claves`/`log_audit_sin_secretos`, y un stub de `capital_episodios` solo para la comprobación de existencia — F1 no usa el núcleo). Resultados:
- **Reconstruíble:** F1 aplica limpio y su postflight pasa; se aplicó DOS veces (tras la reversa) sin residuo.
- **Reversible:** `rollback-f1-multiempresa.sql` retira las 10 tablas, la función y los enlaces sin tocar nada vivo; su guarda aborta correctamente cuando hay datos (probado con los datos del test de concurrencia).
- **Seguro:** el oráculo de gate dio TODO VERDE (Data API cerrada en las 10 tablas + resolver sin EXECUTE, resolver idempotente, índice único arbitra, documentos distintos no colapsan, **el documento NO aparece en `audit_log`** —enmascarado—, núcleo presente).
- **Concurrencia REAL:** 12 llamadas simultáneas del mismo documento produjeron **una sola identidad** (1 inversionista, 1 identificador vigente).
Un replay de paridad total (las 203) por el arnés `scripts/banco/` sigue disponible, pero F1 no depende de las migraciones intermedias más allá de esas dependencias.

**Siguiente:** aplicar a producción es un paso aparte (gate G3 del plan: recenso, backup, reversa y autorización expresa `!` de Miguel), NO cubierto por este ensayo.

**Revisión.** auditor-rls: bloqueante B1 (PII del documento a `audit_log`) + 6 recomendados, aplicados. Codex: NO-GO con 8 bloqueantes y 3 menores, TODOS aplicados: resolver solo resuelve/crea con documento VERIFICADO y de identidad no fusionada; validación por tipo alineada con `cierres_externos` (DNI 8 / CE 9-12 / PASAPORTE 6-12); `crm.leads.inversionista_id` protegido por trigger ante escritura de la Data API; coherencia fuente↔empresa y titular principal por trigger; fusiones con `UNIQUE(fusionado_id)`, destino activo (sin ciclos) y append-only; reversa con `LOCK TABLE` (anti-carrera) y guarda que aborta si hay datos; el notice ya no afirma "forzada". Oráculo de gate y arnés de concurrencia ajustados a documento verificado.

**Reversa:** `scripts/rollback-f1-multiempresa.sql`.
