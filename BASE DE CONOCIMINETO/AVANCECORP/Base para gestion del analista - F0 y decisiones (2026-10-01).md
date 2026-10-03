---
tags: [crm, base-para-gestion, rescate, analista, f0, decision, figma]
fecha: 2026-10-01
estado: F0 ☑ · D1–D13 ☑ · B1–B3b EN PRODUCCIÓN (02/10 20:15, registradas, huellas = rama) · tipos regenerados · sigue el frontend F1–F4
---

# Base para gestión del analista — F0 y decisiones (01/10/2026)

Encargo «P-0XX: Base de gestión para analistas con seguimiento y reactivación de leads» (Miguel, 01/10 noche).
Objetivo: que el analista tenga su propia «Base para gestión» con los leads descartados de los que es dueño,
registre intentos, agende rellamadas y reactive al pipeline. El F0 se hizo solo leyendo código y vault:
**ningún archivo de producto ni objeto de base de datos se modificó.** El diseño va a Figma por el conector
«claude.ai Figma» (regla del 01/10: Figma SIEMPRE por MCP, nunca manejando la pantalla). Enlace del archivo:
https://www.figma.com/board/zbgq3gjYGsaaMCo6e140bU (tablero FigJam, creado 02/10 por el conector).

Relacionado: [[Centro de rescate de descartes 2026-08-20]] · [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] ·
[[Gestion Diaria - resultado separado del descarte (2026-09-21)]] · [[Auditoria del historial de leads - analista y supervisor (2026-09-20)]] ·
[[Fundamentos UX del CRM]] · [[Acceso y roles del CRM]] · [[Inicio]]

## F0 — Lo que ya existe (evidencia en `CRM-Avance-Corp/app` y `supabase/migrations`)

1. **La «base para gestión» del supervisor es el Centro de rescate.** Pantalla `screens/rescate-descartados.tsx`
   (rutas `#/rescate` y `#/rescate-carpeta`, menú «Base para gestión» en `sidebar.tsx:60`). La ven supervisor y
   **también Gerencia** (capacidad `repartirLeads`, `lib/roles.ts`; RPC con gate `supervisor|gerencia`). RPC:
   `crm.rescate_descartes_meses`, `crm.rescate_descartes_mes(p_mes)`, `crm.rescatar_descartes(episodios, destinos, evitar_origen)`
   (vigente en `20260906140000`). Tabla de carpeta: Seleccionar · Lead · Descartó · Origen · Capital · Fecha · Estado · Detalle.
2. **Qué entra en la base:** episodios de `crm.lead_asignaciones` con `resultado='descartado'`. «Pendiente» = el lead sigue
   `activo`, `etapa='descartado'`, `descartado_en = resultado_en` y motivo ≠ `datos_invalidos`. **No existe «perdido».**
   La etapa es un CHECK de texto: `nuevo, contactado, reunion_agendada, propuesta_enviada, convertido, descartado`.
3. **Dueño del lead:** `crm.leads.vendedor_id` (→ `crm.equipo`). Si es null, está en bandeja de `asignado_supervisor_id`
   (exclusividad por CHECK). En el ledger es `lead_asignaciones.analista_id`. El descartado conserva su `vendedor_id`.
4. **Actividades:** `crm.actividades(id, lead_id, tipo, detalle, metadata, creado_por, creado_en)`, log inmutable.
   **El resultado de llamada ya existe** en `metadata` (`evento='resultado_llamada'`, `resultado`, `submotivo`, `intento_n`…),
   con 7 resultados cerrados por CHECK: `no_contesto, volver_a_llamar, agendo_reunion, no_interesado, numero_errado,
   no_es_la_persona, pide_otro_producto`; solo lo escribe el núcleo (`trg_00_actividades_resultado_solo_nucleo`).
   Puerta vigente `crm.registrar_llamada_v4` (descartar y «no insista» se deciden aparte). Catálogo front `lib/resultado-llamada.ts`.
5. **Campos:** `motivo_descarte` (CHECK `sin_interes, sin_fondos, competencia, no_responde, datos_invalidos, pide_credito, otro`),
   `origen` (CHECK `referido, landing, formulario, oficina, otro, web, campania, whatsapp`), `descartado_en/descartado_por`
   (sellados por trigger, NULL al reabrir), `no_contactar` + `consentimiento_*`. **No existe** etapa máxima alcanzada,
   `proxima_llamada`, `agendado_en` ni `etapa_cambiada_en`: la próxima llamada vive en `crm.tareas` (tipo `llamada`, `vence_en`, `pendiente`).
6. **Reasignación:** no hay `crm.reasignar_lead`; la individual es `update crm.leads set vendedor_id` bajo RLS + triggers
   (`trg_leads_bloquear_reasignacion` impide que el analista lo cambie). Lotes: `derivar_leads_equipo_fn` (supervisor),
   `repartir_lead` (coordinador), `rescatar_descartes`. El ledger (`trg_leads_asignaciones`) cierra y abre episodios y
   `trg_leads_reasignacion` inserta la actividad `reasignacion`. **Reabrir:** `crm.reabrir_lead_fn` (vendedor en su ámbito,
   supervisor, gerencia) → `nuevo`, ciclo nuevo, SLA reiniciado.
7. **RLS:** restrictiva `crm_actor_activo_gate` en todo. `leads_select/insert/update` por visibilidad
   (`private.vendedor_ids_visibles`); `actividades_select` sigue al lead, `actividades_insert` exige `creado_por=uid` y dueño o
   supervisor visible; **`lead_asignaciones` sin grants: solo por RPC `security definer`**.
8. **Triggers al cambiar etapa:** `00_guard_tenencia` (un descartado solo reabre en `nuevo`; sube `ciclo_actual`),
   `01_sla_global` (reinicia al cambiar ciclo), `cambio_etapa` (actividad), `zz_sello_descarte`, `zz_reapertura_solo_rpc`,
   AFTER `02_sla_versionado` (cierra/abre `lead_sla_etapas`), `asignaciones`, `zz_sync_tareas`. En actividades:
   `trg_zz_actividades_avance_etapa` (llamada realizada → `contactado` automático).
9. **Roles:** `crm.equipo.rol_crm in (vendedor, supervisor, gerencia, coordinador, directorio)`; «analista» = `vendedor`.
   Rol resuelto en servidor por `private.rol_crm(uuid)`; en el front `crm.mi_acceso_fn()`. Equipo del supervisor =
   subárbol por `supervisor_id`.
10. **Stack:** Vite 8 + React 19 + TS (SPA con router por hash), no Next.js. Checks: `npm run lint` (oxlint),
    `typecheck` (`tsc -b`), `test:run` (vitest), `build`, `check` (todo), raíz `test:rls`. E2E solo con Docker local.

## Supuestos del encargo que son FALSOS o distintos

| Encargo | CRM real | Consecuencia |
|---|---|---|
| Reactivar a **Contactado** | `reabrir_lead_fn` y `rescatar_descartes` reabren a **`nuevo`**; el guard prohíbe otra etapa | Decisión D1 |
| Mismo dueño al reactivar | El rescate del supervisor **evita** al asesor que descartó; `reabrir_lead_fn` sí conserva al dueño | Coexisten dos caminos; D2 |
| Enum nuevo `resultado_llamada` (4 valores) | Ya hay 7 resultados cerrados y puerta v4 | No crear enum; D3 |
| `proxima_llamada_en` en actividades | La agenda es `crm.tareas` (v4 ya crea la tarea en «volver a llamar») | Reutilizar tareas; D7 |
| 3 intentos → 30 días de enfriamiento | Para leads activos el umbral es el 6.º intento → «perdido» | Constante propia de la base; D4 |
| Supervisor quita `no_contactar` | Hoy **solo Gerencia** (`crm.levantar_no_contactar`, Ley 29571) | D5 |
| Etapa máxima alcanzada | No existe | Calcular desde `cambio_etapa` o columna nueva; D6 |
| Vista «solo supervisor» | Gerencia también la ve | El dispatcher por rol debe cubrir 3 roles |
| Frontend «portal Next.js» | CRM Vite + React | — |
| Campo `asesor_id`/`analista_id` en leads | Es `vendedor_id` | — |
| `crm.reasignar_lead`, `crm.rol_actual()` | No existen | — |

## Decisiones que necesita Miguel antes de B1 (D1–D8)

- **D1 · Etapa al reactivar.** (a) Reabrir a `nuevo` con la puerta existente y que la primera llamada realizada lo lleve a
  `contactado` (trigger de avance ya existente); (b) RPC nueva que reabra a `nuevo` y en la misma transacción pase a
  `contactado`, tocando el guard. **Recomendación: (b) solo si el negocio exige ver «Contactado» de inmediato; si no, (a).**
- **D2 · Dueño.** Analista reactiva **sus** leads conservando dueño (como `reabrir_lead_fn`); el supervisor sigue repartiendo
  con «evitar al que descartó». **Recomendación: mantener ambos.**
- **D3 · Resultado «interesado».** No existe. (a) «Reactivar» es acción explícita y «agendó cita» reactiva sola;
  (b) añadir 8.º resultado `interesado` al CHECK, trigger y catálogo. **Recomendación: (a).**
- **D4 · Umbrales.** 3 intentos sin `agendo_reunion`/reactivación → enfriamiento 30 días, como constantes en un solo sitio
  (función `private.base_gestion_constantes()` o cabecera de la RPC). Intentos se cuentan por ciclo (desde el `descartado_en` vigente).
- **D5 · Quitar «no contactar».** Mantener solo Gerencia (legal) y que el supervisor lo vea y lo pida; o abrirlo al supervisor.
  **Recomendación: mantener Gerencia.**
- **D6 · Etapa máxima.** Calcularla en la RPC desde `crm.actividades` (`cambio_etapa`) y la etapa al descartar, sin columna.
  Columna con trigger solo si la lectura resulta lenta.
- **D7 · Rellamada.** Reutilizar `crm.tareas` (tipo `llamada`): «Llamar hoy» = tareas pendientes de leads de la base con
  `vence_en` ≤ hoy Lima. Verificar qué hace `trg_leads_zz_sync_tareas` con las pendientes al reasignar.
- **D8 · Enfriamiento.** (a) columna `enfriado_hasta` + trigger (como pide el encargo); (b) calcularlo en la RPC a partir del
  3.º intento. **Recomendación: (b)** — sin trigger ni columna; mismo resultado, menos piezas.

Verificado tras el F0: `trg_zz_actividades_avance_etapa` solo actúa con `etapa = 'nuevo'` (`20260725060657`), así que registrar un
intento sobre un lead `descartado` **no** lo mueve de etapa. Y `trg_leads_zz_sync_tareas` hace que las tareas pendientes
**sigan la tenencia del lead** (una rellamada agendada pasa al nuevo dueño al reasignar; solo se cancelan al re-encolar a NULL).
Queda por verificar en B3 si `crm.registrar_llamada_v4` acepta leads en `descartado` o si el intento de la base necesita su
propia puerta (`crm.registrar_intento_base`) que escriba `metadata.evento='intento_base'`.

## Plan ajustado (resumen; detalle en el archivo de Figma)

- **B1:** `origen` gana `reactivacion_base`; `reactivado_en` en `crm.leads`; sin enum ni columnas de resultado (se reutiliza
  metadata); índices `(vendedor_id, etapa) where etapa='descartado'` y `tareas(vence_en) where estado='pendiente'`.
- **B2:** RLS no cambia para el analista (ya ve y escribe sus leads y actividades); el acceso a la base va por RPC
  `security definer` con gate por rol y ámbito; `no_contactar` sigue bloqueado al analista.
- **B3:** `crm.obtener_base_gestion()` (por rol), `crm.registrar_intento_base`, `crm.reactivar_lead_base` (compone sobre
  `reabrir_lead_fn`), reuso de `marcar_no_contactar`/`levantar_no_contactar`. Fechas con `at time zone 'America/Lima'`.
- **B4:** sin trigger de enfriamiento si D8=(b); el SLA ya se reinicia al reabrir (`01_sla_global`, `02_sla_versionado`).
- **F1–F4:** `#/rescate` despacha por rol (como `gestion-diaria`): analista → lista plana con «Llamar hoy», filtros y
  contador de intentos; supervisor/gerencia → mosaico actual + columnas Intentos · Último resultado · Gestiona y el
  indicador de reactivaciones por analista. Ficha: historial completo con buscador, formulario de intento con los 7 resultados,
  «Reactivar» con confirmación, «No contactar» con motivo.

## Segunda pasada sobre el encargo (01/10, más tarde) — dos choques nuevos que el F0 no tenía

- **`origen` es inmutable.** `private.leads_before_update()` rechaza con `P0409` cualquier cambio de `crm.leads.origen`
  salvo con `crm.op_privilegiada=on` (`20260811190324_crm_origen_inmutable.sql:448`, postflight en :585). El encargo
  pide `origen = reactivacion_base` al reactivar: **no se puede hacer como está escrito.** → **D9:** marcar la reactivación
  con `reactivado_en` + la actividad `cambio_etapa` (metadata `via='base_gestion'`), o con una columna aparte
  (`origen_reactivacion`), sin tocar `origen`. Recomendación: la actividad + `reactivado_en`; `origen` sigue siendo el canal
  de llegada, que es lo que mide el Ranking.
- **La puerta de llamada vigente rechaza al descartado.** `private.llamada_registrar` hace
  `if v_etapa_antes in ('convertido','descartado') then raise 'El lead esta cerrado'`
  (`20260921153654_crm_resultado_llamada_seguimiento.sql:186`) y además «Un lead descartado no recibe tarea siguiente» (:109).
  Resuelve la duda que dejó el F0: **los intentos de la base necesitan su propia puerta** (`crm.registrar_intento_base`) con
  su propio núcleo o una variante del actual que admita `descartado` y cree la tarea de rellamada. → **D10:** núcleo nuevo
  (`private.intento_base_registrar`) que reutilice el CHECK de 7 resultados y el trigger «solo núcleo», o abrir una excepción
  en `llamada_registrar`. Recomendación: núcleo nuevo; el actual está sellado por huella
  (`assert_gestion_diaria_resultado`) y tocarlo obliga a re-sellar Gestión Diaria.
- Confirmado también: el guard de tenencia dice literalmente «Un lead descartado solo se puede reabrir en etapa nuevo»
  (`20260929201813_crm_reasignacion_conversion_consistente.sql:567`), así que D1 sigue abierta tal cual.

## Tablero del plan en FigJam (02/10/2026)

**Tablero editable:** https://www.figma.com/board/zbgq3gjYGsaaMCo6e140bU — mismo formato que
[[Portal Pagos - plan de mejora en Figma (2026-09-26)]]: título, línea «actualizado», leyenda ☐/◉/☑/✖ y cuatro columnas
(Diagnóstico · Decisiones D1–D10 · Fases · Reglas).

**Política:** actualizar ESTE tablero al cerrar cada fase verificada (☐→◉→☑ en el título de la fase, la letra elegida y la
fecha en cada decisión, y la línea «Actualizado»). No recrearlo. No marcar ☑ sin evidencia.

Nodos (para actualizar sin buscar):
- Título `1:2` · subtítulo `1:3` · **actualizado `1:4`** · leyenda `1:5`
- Secciones: diagnóstico `1:6` · decisiones `1:7` · fases `1:8` · reglas `1:9`
- Diagnóstico: «lo que existe» `2:3`–`2:12` · «choques» `2:14`–`2:22`
- Decisiones: D1 `2:25`/`2:26` · D2 `2:27`/`2:28` · D3 `2:29`/`2:30` · D4 `2:31`/`2:32` · D5 `2:33`/`2:34` · D6 `2:35`/`2:36` ·
  D7 `2:37`/`2:38` · D8 `2:39`/`2:40` · D9 `2:41`/`2:42` · D10 `2:43`/`2:44` (título/cuerpo)
- Fases (título/cuerpo): F0 `2:47`/`2:48` · B1 `2:49`/`2:50` · B2 `2:51`/`2:52` · B3 `2:53`/`2:54` · B4 `2:55`/`2:56` ·
  F1 `2:57`/`2:58` · F2 `2:59`/`2:60` · F3 `2:61`/`2:62` · F4 `2:63`/`2:64` · QA `2:65`/`2:66`
- Reglas: alcance `2:68` · casos límite `2:70` · seguridad `2:72` · protocolo `2:74` · fuentes `2:76`

## Decisiones de Miguel (02/10/2026) — cierran D1–D10

| # | Decisión | Consecuencia técnica |
|---|---|---|
| D1 | **(b) Directo a `contactado`** en la misma operación | La RPC de reactivación reabre a `nuevo` (puerta `reabrir_lead_fn`, respeta el guard) y en la MISMA transacción avanza a `contactado`. Evaluar en B3 si basta con dos UPDATE encadenados sin tocar `trg_leads_00_guard_tenencia`; el SLA versiona `nuevo`→`contactado` como un avance normal. |
| D2 | **(a) Mismo analista**; el supervisor sigue repartiendo desde el rescate | Dos caminos coexisten. `rescatar_descartes` no cambia. |
| D3 | **(a) Botón «Reactivar» explícito**; «agendó cita» reactiva sola | No se toca el CHECK de 7 resultados ni el catálogo del front. |
| D4 | **3 intentos sin cita ni reactivación → 30 días**, por ciclo | Constantes en `private.base_gestion_constantes()`. Intentos desde el `descartado_en` vigente. |
| D5 | **(b) El supervisor también puede quitar «no contactar»** (su equipo, con motivo) | Cambia la política vigente (hoy solo Gerencia, Ley 29571): ampliar el gate de `crm.levantar_no_contactar` a supervisor dentro de `vendedor_ids_visibles`, con bitácora de quién y por qué. LEVEL 3. |
| D6 | **(a) Etapa máxima deducida del historial** en la RPC | Desde `crm.actividades` (`cambio_etapa`) + etapa al descartar. Sin columna. |
| D7 | **(a) Rellamada en `crm.tareas`** | «Llamar hoy» = pendientes de la base con `vence_en` ≤ hoy Lima. |
| D8 | **(a) Columna `enfriado_hasta` + trigger** | Trigger AFTER INSERT en `crm.actividades` para `metadata.evento = 'intento_base'`: al 3.º intento del ciclo sin cita/reactivación, `enfriado_hasta = hoy Lima + 30`. Respetar prefijos. Gerencia podrá editarla a mano. |
| D9 | **(a) `reactivado_en` + línea en el historial** | `origen` no se toca. Actividad `cambio_etapa` con `metadata.via = 'base_gestion'`. |
| D10 | **(a) Puerta y núcleo propios** | `crm.registrar_intento_base` → `private.intento_base_registrar`; reutiliza el CHECK de 7 resultados y el trigger «solo núcleo»; no se re-sella Gestión Diaria. |

Miguel pidió además (02/10): **trabajar con agentes** porque el módulo es largo. Los agentes de investigación son de solo lectura;
sigue habiendo un único escritor (esta sesión como PRIMARY).

## Evidencia reunida por agentes para B1–B3 (02/10/2026, solo lectura)

- **Flujo de migración:** rama de Supabase → aplicar → `supabase/scripts/test-rls.mjs` → advisors → merge nativo
  (`CRM-Avance-Corp/CLAUDE.md:47-54`, skill `nueva-migracion`). La rama se maneja con el conector «claude.ai Supabase»
  (permisos en `.claude/settings.json`); si no está cargado, `/mcp`. Cada migración lleva su banco Docker propio en
  `supabase/scripts/<tema>/` (`banco.mjs` o `ensayar.mjs`) y su reversa `reversa-*.sql`. `crm.leads` tiene **grants por columna**.
- **Sellos por huella:** `private.assert_gestion_diaria_resultado()` (`20260921153654:409`) fija el md5 de `llamada_registrar`,
  `reabrir_lead_fn`, `marcar_no_contactar`, `trg_leads_cambio_etapa`, `trg_leads_zz_sello_descarte`, `trg_leads_sync_tareas`,
  `trg_actividades_resultado_solo_nucleo`, `actividades_de_lead_core`, el CHECK `actividades_resultado_llamada_forma` y el
  trigger `trg_00_actividades_resultado_solo_nucleo`. **Llamarlos está bien; reemplazar su cuerpo obliga a re-sellar.**
  NO sellados: `private.trg_leads_guard_tenencia` (anclas puntuales) y `crm.levantar_no_contactar` → D5 se puede ampliar
  con `create or replace` normal (+ anclas nuevas).
- **D1 (b) es viable sin tocar el guard:** tras el UPDATE `descartado → nuevo` (por `reabrir_lead_fn`, GUC
  `crm.reapertura_identidad`), un segundo UPDATE `nuevo → contactado` en la MISMA transacción pasa el guard (ya `old.etapa = nuevo`,
  `20260803164348:559-569`) y `zz_reapertura_solo_rpc`; el SLA cierra el episodio `nuevo` como `cambio_etapa` y abre `contactado`
  en el mismo ciclo (`20260807203757:963-1026`); el reloj global solo se reinicia con el cambio de ciclo (`01_sla_global`).
- **Reabrir:** `crm.reabrir_lead_fn(uuid)` (`20260906150000:87`): gate vendedor/supervisor/gerencia, ámbito `vendedor_ids_visibles`,
  exige `etapa = descartado` (P0409), veto `persona_vetada` (P0429), sin idempotencia (el replay falla P0409). Devuelve
  `{ok, lead_id, etapa, inversionista_id, enlazado, reabierto_por, reabierto_en}`.
- **No contactar:** `marcar_no_contactar(uuid, motivo)` (vendedor/supervisor/gerencia) y `levantar_no_contactar(uuid, motivo)`
  (solo gerencia, `20260906160000:292`) escriben `leads.no_contactar` bajo `crm.op_privilegiada` y el **motivo va en la actividad**
  `nota` con `metadata {evento: no_contactar, accion: marcar|levantar, motivo}`. `crm.inversionistas` sí tiene `no_contactar_en/por`.
  → No hacen falta `no_contactar_por/motivo` en leads.
- **Idempotencia del CRM:** `crm.sla_operacion_recibos (actor_id, operacion_id)` vía `private.sla_ejecutar_comando`
  (`crm.registrar_actividad_v2` / `cerrar_tarea_v2`); la actividad lleva `id = operacion_id`. El núcleo de llamada escribe el
  resultado con `set_config('crm.op_resultado_llamada','on',true)`; `intento_n` cuenta `llamada_*` desde `private.inicio_ciclo_lead`.
  Para la base: contar desde `descartado_en` (D4).
- **Etapa máxima (D6):** `trg_leads_cambio_etapa` deja `cambio_etapa` con `metadata {etapa_anterior, etapa_nueva, automatico}`;
  acotar por ciclo con `inicio_ciclo_lead` o `lead_asignaciones.ciclo_n`.
- **Visibilidad:** `vendedor_ids_visibles`: vendedor → él; supervisor → subárbol; gerencia → todos; coordinador → vacío.
  `mi_acceso_fn()` da `rol_crm` al front.
- **Ya existe y se reutiliza:** `lead_asignaciones.motivo_apertura = 'reactivado'`; `crm.enfriamiento_politica` (otro concepto:
  días por motivo para reingresar una persona; no se toca); índices `idx_leads_vendedor`, `idx_leads_descarte`,
  `tareas_pendientes_keyset_idx`, `tareas_cola_idx` (ninguno nuevo en B1 salvo que el EXPLAIN lo pida).

## B1 · Esquema — HECHO en local y ensayado (02/10/2026); falta la rama de Supabase y el merge

- **Migración:** `supabase/migrations/20261002054402_crm_base_gestion_esquema.sql`. `crm.leads.reactivado_en`
  (timestamptz) y `enfriado_hasta` (date), NULL, GRANT SELECT por columna; **sello** `trg_leads_zz_sello_base_gestion`
  (BEFORE INSERT OR UPDATE OF ambas): solo escribe quien lleve el GUC de transacción `crm.op_base_gestion = 'on'` o una
  sesión sin usuario. Hace falta porque `crm.leads` da a `authenticated` privilegios de TABLA (`rw`): un grant por
  columna no protege. CHECK `actividades_intento_base_forma` (evento `intento_base`, los 7 resultados, `intento_n`/
  `ciclo_n` ≥ 1, `tarea_id` en `volver_a_llamar`). `private.base_gestion_constantes()` = (3, 30). **Sin índices nuevos.**
- **Banco:** `supabase/scripts/base-gestion/` (`banco.mjs crear|aplicar|test|reversa-y-reaplicar`, `test.sql`,
  `reversa-esquema.sql`, README). Base Docker `base_gestion_20261002` desde `conversion_tipos_v3_20260927`, con el ACL de
  tabla de prod repuesto (`authenticated=rw`, `service_role=arwd`). Tiene 6 leads y 0 descartados: el EXPLAIN de ahí
  no vale como evidencia de índices; se repite en la rama.
- **auditor-rls:** CAMBIOS REQUERIDOS, todos aceptados y aplicados. El P1 era real: `information_schema.column_privileges`
  expande el grant de tabla a cada columna y el postflight habría abortado en producción; ahora se mira
  `pg_attribute.attacl`. P2: trampa NULL del CHECK cerrada con `coalesce`. P2: `test-rls.mjs` gana `testBaseGestionB1`.
- **Verificación:** aplicar + postflight (5 negativos) PASS · `test` 12/12 · `reversa-y-reaplicar` PASS · `typecheck` PASS
  (tipos a mano en `database.types.ts`) · `check:scripts` PASS · `test:rls:preflight` PASS con el entorno ficticio de CI
  (el hook del proyecto no deja pasar valores inline: se leyeron del propio YAML del workflow).
- **Para B3 (acoplamiento):** el núcleo del intento debe encender DOS GUC: `crm.op_base_gestion` (sello de leads) y
  `crm.op_resultado_llamada` (claves `resultado`/`intento_n` reservadas por `trg_00_actividades_resultado_solo_nucleo`),
  restaurando el valor previo. `reabrir_lead_fn` no tiene idempotencia: la reactivación añade la suya (recibos).
- **Manual (Miguel):** conectar «claude.ai Supabase» con `/mcp` (o lanzar con `!`) para: rama → aplicar → `test-rls.mjs`
  con `CRM_RLS_EXIGE_BASE_GESTION=1` → advisors → merge. Nada se ha commiteado todavía.

## B2 · Permisos — HECHO en local y ensayado (02/10/2026); PAUSADO esperando auditor-rls, Codex y D7-bis

- **Sin migración de RLS:** las políticas vigentes ya limitan al analista a sus leads, actividades y tareas
  (`vendedor_ids_visibles` = solo él). Demostrado en el banco con `b2-rls.sql` (20/20) bajo rol `authenticated` e
  impersonación (ambas formas del claim). Banco con la ACL de producción copiada del stack local (`paridad-acl`).
- **Migración `20261002061500_crm_base_gestion_no_contactar_supervisor.sql` (D5):** `levantar_no_contactar` para Gerencia o
  Supervisión en su ámbito; regla «todos los leads de la persona en su equipo» (si no, 42501 «pídelo a Gerencia»); historial
  con rol. Reversa byte a byte. 7 casos nuevos en `test-rls.mjs`.
- **D7-bis (nuevo, pendiente de Miguel):** `trg_tareas_before_insert` dice «El lead está cerrado: no admite tareas nuevas» y
  `trg_leads_zz_sync_tareas` cancela las pendientes al descartar: la rellamada de la base NO puede vivir en `crm.tareas`.
  Recomendación: columna sellada `crm.leads.proxima_llamada_en` (+ fecha en la metadata del intento; el CHECK pasa a exigirla
  en `volver_a_llamar`), sin tocar el núcleo SLA ni la cola diaria.
- **Pendiente:** leer el informe del auditor-rls de B2 y el de Codex (B1+B2, encargo versionado en
  `CRM-Avance-Corp/docs/encargos/2026-10-02-codex-base-gestion-b1-b2.md`), aplicar hallazgos, rama → test-rls → advisors → merge.

## Revisiones de B2 aplicadas y rama de Supabase (02/10/2026, noche)

- **Codex (BLOCK → corregido):** P1 real de semántica NULL en la revalidación bajo candado: un lead parqueado (sin
  vendedor) en la bandeja de otro supervisor daba NULL y `not NULL` lo dejaba pasar. Ahora `(…) is not true` en las dos
  comprobaciones. Huella nueva `05df49be…` (md5 de `prosrc` calculado en local con el método verificado contra la viva
  `3840a73f…`, y confirmado en el banco). **auditor-rls:** `activo` en el espejo de la policy; reversa con guarda de prosrc +
  contrato/ACL; fixtures con persona real y pruebas estrictas (25/25, el script falla si hay FAIL). Informes en
  `BASE PARA GESTION/revisiones/`.
- **Por qué el caso de dos equipos vive solo en el banco:** por la API no se puede crear un lead nuevo con el documento de una
  persona reconocida (puertas b1/D-13); los fixtures lo hacen bajo `crm.op_privilegiada`.
- **Rama de Supabase por CLI:** `supabase branches create base-gestion-20261002 --project-ref dctqcbznekcyxhjujuci --region
  us-east-2 --size micro` → ref `dmhewdxipdspvojaudvu`, `ACTIVE_HEALTHY` pero `MIGRATIONS_FAILED` (el replay automático del
  historial se detiene en una base vacía, como `banco-f7` el 01/09; la de 25/09 sí llegó a FUNCTIONS_DEPLOYED). La CLI de
  Supabase está autenticada y enlazada aunque el conector MCP no aparezca en la sesión; `branches list|get|create|delete`
  funcionan; no hay `merge` por CLI (la aplicación en producción sigue siendo de Miguel con `!`).

## Decisiones D7-bis, D11 y D12 (02/10/2026, noche) y migración B1b

| # | Decisión | Consecuencia |
|---|---|---|
| D7-bis | **Agenda propia de la base** («Sí, así»): la rellamada vive en `crm.leads.proxima_llamada_en` (sellada), no en `crm.tareas`. Pantallas: bloque «Llamar hoy» (vencidas + hoy), contador en el menú «Base para gestión», línea «Base: N rellamadas para hoy» en «Hoy» (solo lectura). | Migración B1b `20261002224851`: columna + sello de 3 columnas + CHECK (fecha ISO en `volver_a_llamar`) + constantes (3, 30, 10) + índice parcial. Nada entra en la cola diaria ni en el SLA. |
| D11 | La rellamada se agenda **como máximo 10 días adelante**. | `dias_max_rellamada = 10` en `private.base_gestion_constantes()`; la puerta del intento rechaza fechas más lejanas (B3). |
| D12 | **Gana la rellamada:** el lead descansa (30 días) solo cuando el 3.º intento termina sin cita y sin rellamada. | El trigger de enfriamiento (B4) no actúa si el intento trae `proxima_llamada_en`; la rellamada se consume con el siguiente intento. |

Reglas de la rellamada acordadas: una nueva «volver a llamar» sustituye la fecha; el siguiente intento la consume;
reactivar o vetar la limpia; el supervisor la ve como columna «Próxima llamada». Ensayo en banco de B1b: aplicar +
postflight, `test`, `reversa-y-reaplicar-b1b` PASS; `test-b2` 25/25 sigue verde; typecheck PASS. Rama de Supabase con
datos: `base-gestion-datos-20261002` (ref `dpjojnpfcwkeikyagtxj`, `--with-data`, decisión de Miguel) para `test-rls`,
advisors y EXPLAIN reales; la rama vacía `base-gestion-20261002` se borró (replay 86/400).

## B3 · Puertas y núcleos — HECHO en local y ensayado (02/10/2026, noche)

- **Migración `20261002231436_crm_base_gestion_puertas.sql`.** Cuatro puertas `crm.*` DEFINER (EXECUTE solo authenticated):
  `obtener_base_gestion(p_vendedor_id)` (lectura por rol con ámbito explícito, espejo de `leads_select`; excluye veto y descanso;
  intentos del ciclo desde `descartado_en`, último resultado, próxima rellamada, **etapa máxima alcanzada desde la última
  reapertura del historial** —acotar con `inicio_ciclo_lead` fallaba en transacciones multi-sentencia porque `now()` del log y
  `statement_timestamp()` del ledger difieren—, días desde el descarte, quién gestiona; orden rellamada vencida/hoy → etapa
  máxima → menos días; sin fecha o sin etapa al final), `registrar_intento_base`, `reactivar_lead_base` y
  `base_gestion_resumen` (Supervisión/Gerencia, cifras de F4). Núcleos `private.base_gestion_intento_core` (7 resultados,
  rellamada futura ≤ 10 días, veto P0429, descanso 22023, actividad `intento_base` con `id = operación` bajo los dos GUC,
  fija/limpia `proxima_llamada_en`, `agendo_reunion` reactiva en la misma transacción, idempotencia por `metadata.respuesta`)
  y `base_gestion_reactivar_core` (llama a `reabrir_lead_fn` sellada → `nuevo`; avanza a `contactado` en la misma transacción;
  sella `reactivado_en`; limpia rellamada y descanso; actividad `reactivacion_base`). Ayudantes `base_gestion_rol`,
  `base_gestion_lead_visible` (`is true` ante NULL), `base_gestion_etapa_rango`.
- **Banco:** `b3-puertas.sql` **40/40** bajo rol: analista propio/ajeno, veto, 10 días, idempotencia y doble clic, 23505 con
  otro contenido, rellamada consumida por el siguiente intento, orden, reactivación (contactado, ciclo 2, SLA global reiniciado
  y episodio abierto en contactado), agendó cita reactiva, reactivado y descartado otra vez con contador 0, Supervisión por
  equipo y filtro por analista, Gerencia todo, resumen. `reversa-y-reaplicar-b3` PASS. `test-rls.mjs`: bloque
  `testBaseGestionB3` por la API (roles 42501, validaciones sin escribir, camino bueno con lead transitorio, soft-delete).
- **Pendiente:** auditor-rls B3; Codex B3+B4; rama con datos (URL de Miguel) → aplicar B1/B1b/B2/B3 → `test-rls` → advisors.
- **Sigue B4:** trigger AFTER INSERT en `actividades` (evento `intento_base`): al `max_intentos`-ésimo intento del ciclo sin
  cita ni rellamada (D12), `enfriado_hasta = hoy Lima + dias_enfriamiento` bajo el GUC del sello. El SLA al reactivar ya está
  verificado en B3 (reloj global y episodio).

## B4 · Trigger de enfriamiento — HECHO en local y ensayado (02/10/2026, noche)

- **Migración `20261002233851_crm_base_gestion_enfriamiento.sql`:** `trg_zz_actividades_enfriamiento_base` (AFTER INSERT, WHEN
  `evento = intento_base`). Regla: sin rellamada ni cita, al llegar a 3 intentos en el ciclo → `enfriado_hasta = hoy Lima + 30`
  bajo el sello. Con rellamada o cita no enfría (D12/D3). Tras el descanso, un intento más sin rellamada vuelve a enfriar
  (el cupo del ciclo ya está agotado); reactivar limpia el descanso y reinicia el SLA (cambio de ciclo).
- **Banco:** 15/15 con fechas simuladas; `b3-puertas.sql` ajustado (con B4, el 3.º intento de LA la pone a descansar): 44/44.
- **Auditoría B3 aplicada antes:** sello de actividades (`intento_base`/`reactivacion_base`/`respuesta`/`via` solo por el núcleo),
  candados persona → lead al reactivar, replay tras el candado y por actor, resumen atribuido al dueño del lead.
- **Pendiente:** auditor-rls B4 → Codex B3+B4 (LEVEL 3) → rama con datos (URL de Miguel) → `test-rls.mjs` → advisors → merge.

## D13 y B4b (02/10/2026, noche) · auditoría de B4 aplicada

- **D13 (Miguel):** tras cada descanso de 30 días el analista vuelve a tener **3 intentos nuevos** (antes, con el cupo del
  ciclo agotado, un solo intento sin rellamada volvía a enfriar). Migración B4b `20261002235342`: ayudante
  `private.base_gestion_intentos_desde` (el descarte o el inicio Lima del día en que venció el último descanso) y
  `create or replace` de `obtener_base_gestion`, `base_gestion_intento_core` y del trigger de enfriamiento. El historial
  completo sigue en la ficha; lo que se reinicia es el contador. Banco 17/17 (incluida la simulación de 30 días con los
  intentos antiguos retrasados 40 días).
- **auditor-rls B4 aplicado:** el trigger solo actúa bajo `crm.op_base_gestion` (un backfill sin usuario no enfría), DEFINER
  redactado, ensayo del postflight sobre el descartado más antiguo, aviso de descansos vigentes en la reversa; `test-rls.mjs`
  con D12 por la API y el contrato del trigger.

## Codex B3+B4 (BLOCK) → B3b (03/10/2026, madrugada)

Seis P2, cinco aceptados y uno parcial, en la migración de enmienda `20261003001014_crm_base_gestion_idempotencia_y_orden.sql`
(las commiteadas no se editan): el replay de un intento se resuelve antes de las validaciones temporales (un reintento de
rellamada ya vencida sigue devolviendo su respuesta); la identidad de la operación incluye fecha de rellamada y nota (otra
fecha u otra nota → 23505); la reactivación hija de «agendó cita» usa un uuid nuevo y se verifica; el orden de la base sigue
el contrato (rellamada hoy → etapa máxima → días; la hora solo desempata); el último resultado desempata por `intento_n`; el
descarte del ciclo anterior que comparta instante con la reapertura no cuenta para la etapa máxima. Banco 48/48 y 17/17.
Riesgo operativo que queda: el postflight de B4 ensaya sobre un lead real con candado breve → aplicar B4 en producción fuera
de horario. Informe en `BASE PARA GESTION/revisiones/2026-10-02-codex-b3-b4.md`.

## Traspaso a otra sesión (03/10/2026)

Miguel pasa el módulo a una sesión con la contraseña de BD. Todo está commiteado en `main` local (sin push). Punto de
entrada para la sesión siguiente: `BASE PARA GESTION/ESTADO.md` → «Cómo continuar» (pasos 0–9 con comandos), más
`FRONTEND.md` para F1–F4. Rama de Supabase con datos: `base-gestion-datos-20261002` (ref `dpjojnpfcwkeikyagtxj`), viva y sin
migraciones aplicadas. Nada en producción.

## Rama y gate de RLS (02/10/2026, noche) — listas para el merge

- **Sin contraseña de BD.** El MCP de Supabase no estaba conectado. Todo fue por la Management API: la CLI con
  `--linked --project-ref <rama> --workdir <carpeta aparte>` (`db query`, `db advisors`, `db dump`). La carpeta compartida
  sigue enlazada a producción. Es la misma vía del merge: el CRM no necesita la contraseña para una rama con datos.
- **Rama:** las 7 aplicadas; antes había 0 intentos previos (eso acredita el punto (a) de Codex r2). Con datos reales:
  2806 leads, 1078 descartados vivos y 26 analistas. El EXPLAIN usa índices (1,7 ms; «llamar hoy» 0,05 ms), así que
  **la B5 de índice no hace falta**. Puertas: analista 73 ms, gerencia 78 ms con 1069 filas (en F4, filtrar o paginar),
  supervisores hasta 137 ms. Advisors: solo 4 WARN nuevas, las del patrón DEFINER de las puertas; 0 ERROR.
- **Gate en Docker propio a paridad total.** Las huellas del banco son idénticas a las de la rama. Tras aplicar las
  reversas, son idénticas a PRODUCCIÓN: eso acredita las 7 reversas. A/B: 77 rojos antes y 68 después; los 68 son de fondo
  y salen igual en las dos corridas. Base para gestión 74/74.
- El gate cazó 2 expectativas viejas del test: con B3, el sello «solo núcleo» corta antes. Corregidas en `72189f04`.
- **Registradores** de las 7 versionados y probados (idempotentes). Evidencia completa en
  `BASE PARA GESTION/revisiones/2026-10-02-rama-y-gate.md`.
- 🔑 **Un banco Docker a paridad se acredita en los dos sentidos:** con las migraciones debe dar las huellas de la rama, y
  sin ellas las de producción. Las ACL se igualan objeto por objeto, incluido el orden de los aclitem y los privilegios por
  defecto. El stack local trae `public` más permisivo.
- 🔴 La reversa de B1b no corre si ya hay intentos con fecha: el CHECK de B1 los rechaza. Con el módulo en uso, revertir
  exige tratar antes esas actividades.
- **Sigue:** merge de Miguel con `!`, fuera del horario de gestión (`BASE PARA GESTION/ESTADO.md`, paso 1). Después:
  gen:types, push, borrar la rama, y luego F1–F4.

## EN PRODUCCIÓN (02/10/2026, 20:15 Lima)

- Miguel aplicó con `!` las 7, cada una con su registrador, en orden: 7/7 `OK`.
- Comprobado después, en solo lectura: las 7 en true y 7 registradas con el md5 de su archivo; 0 intentos, reactivados,
  enfriados o rellamadas (los postflights deshicieron sus ensayos); **huellas de producción = rama** (cuerpos, ACL,
  políticas, relaciones, triggers); advisors iguales a la rama.
- Tipos regenerados desde producción (`9c1d7296`, typecheck PASS). También trajeron tipos de otros módulos ya publicados
  que `main` no tenía.
- Rama de Supabase borrada.
- 🔴 `main` local y `avancecorp/main` DIVERGEN (285 commits solo en local, 28 solo en GitHub). No se hizo push: la
  integración va por una PR sin lo de Gloria y la decide Miguel.
- **Sigue:** frontend F1 → F4 (`BASE PARA GESTION/FRONTEND.md`).

## F1 · Vista del analista — HECHA en la rama (02/10/2026, noche)

- Rama `crm/base-gestion-front`, worktree `AVANCECORP-desktop-worktrees/base-gestion-front-20261002`. **Nace del VIVO
  `44985828`**, no de `main`: el tronco está partido (el vivo tiene 52 commits que `main` no tiene) y la publicación debe
  contener el vivo. Commits: `c11a8840` tipos de producción · `7231672e` F1 · `becbd7ea` accesibilidad.
- `#/rescate` despacha por rol: el analista ve SU base (sin `repartirLeads`); Supervisión y Gerencia, el Centro de rescate
  intacto. Resumen (en base · llamar hoy · agendadas), tabla en escritorio y tarjetas en el celular, orden del servidor.
- 🔑 **«Llamar» depende del APARATO** (convención de la casa, `usePuedeMarcar`): `tel:` en el celular, copiar el número en la
  laptop; siempre por `enlaceTel()` (fuente única: un número que no sirve no se ofrece).
- 🔑 Un refresco fallido con datos ya cargados NO desmonta la lista: aviso en línea (el refetch salta al volver del marcador).
- Verificado: `npm run check` PASS (5619 pruebas), `revisor-a11y` (2 P2 + 3 P3 aplicados), capturas demo 1440/390/320 px.
- **Sigue:** F2, la ficha (historial completo + buscador, registrar intento, reactivar, «no contactar»).

## Cierre del 02/10 (noche): forma de la lista, el MES del lead y la regla del seguimiento activo

- **Miguel vio F1 y le gustó.** Dos correcciones de forma, ya aplicadas en `8570cdfb`: las cifras de arriba PEQUEÑAS (pastillas)
  y la lista como **hoja de Excel** (cuadrícula, un dato por celda, número de fila, columnas # y Lead fijas, fila «hoy» con
  formato condicional; el teléfono es el botón de llamar). En el celular siguen las tarjetas.
- **«MUY IMPORTANTE saber qué mes estoy gestionando»**: el analista se organiza por el mes en que le llegó el lead («mis leads
  de enero, marzo, agosto»). Mes = `coalesce(tenencia_desde, creado_en)` en Lima (el criterio de recepción de la casa:
  `private.cartera_recepciones_fn`). La RPC no lo devuelve hoy → **B5** añade `recibido_en` a `crm.obtener_base_gestion`
  (drop + create por el `returns table`). El dominio del front ya lo calcula (`lib/base-gestion.ts`: `mesesDeLaBase`,
  `filasDelMes`, `etiquetaMesLead`, reutilizando `cartera-meses`); falta la columna y el selector en la pantalla.
- **Regla nueva (B6, pendiente de 2 respuestas):** al supervisor se le ocultan los descartados con **seguimiento activo**
  (intento con nota del analista en los últimos 7 días) para que no reasigne un lead que se está trabajando; además
  `rescatar_descartes` debe rechazarlo en el servidor. Preguntas abiertas: ¿la rellamada agendada vigente también cuenta?
  (recomendado: sí) · ¿ocultar o mostrar en gris «En gestión por X hasta Y»?
- **Estado al cierre:** nada publicado; rama `crm/base-gestion-front` en `8570cdfb` (verde); `main` local con la
  documentación. Servidor Vite y Docker del gate apagados.

## 03/10/2026: columna «Mes», B5 y B6 escritas, y el pedido de «Bases cargadas»

- **F1 terminada en la rama** (`c9e772fd`): columna «Mes» tras el lead y selector «Mes: Todos (N) · Agosto 2026 (n)…»; el
  número de fila, las pastillas y el título de la tabla cuentan lo filtrado. 🔑 Sin `recibido_en` (producción antes de B5)
  no se pinta ni columna ni selector: nunca una columna llena de rayas. `revisor-a11y` APPROVE (5 P3 aplicados: separador
  oculto en la pastilla, `label htmlFor`, selector alto en el celular, el mes vaciado se olvida, título con el mes).
- **B6 decidida por Miguel (03/10):** seguimiento activo = intento de la base del ciclo vigente hace ≤ 7 días **o**
  rellamada agendada vigente; el supervisor lo ve **en gris** «En gestión por X hasta el día Y», sin casilla, y
  `crm.rescatar_descartes` rechaza el lote entero (P0409).
- **Paquete de servidor (03/10), en este orden:** `20261003162300` B3c · `20261003162400` B5 · `20261003162500` B6. Cuerpos
  tomados del texto VIVO (md5 de `prosrc` igual en producción y en el banco), sustituciones exactas, preflight y postflight
  por md5 y ACL exacta. 🔑 `estado` del Centro de rescate NO cambia: el bundle viejo valida con lista cerrada y un valor
  nuevo le haría desaparecer la fila; con `puede_rescatar = false` la pinta «Solo historial». Pantalla del supervisor `5475be81`.
- 🔴 **Lección del censo analítico:** B3/B4 llegaron a producción el 02/10 y desde las 06:49 del 03/10 hay una alerta diaria:
  4 funciones del módulo nombran `crm.leads`/«reunion» y usan `count(` sin declarar. Ningún banco de solo esquema lo ve
  (exenciones vacías). **B3c** las saca del alcance: «intentos del ciclo» en UNA función que solo lee actividades
  (`private.base_gestion_intentos_ciclo`, antes eran tres copias) y el resumen cuenta la lista de `obtener_base_gestion`.
  Antes de aplicar cualquier cosa que nombre leads y cuente: mirar el censo en producción.
- 🔑 **Una regla «aunque lo intenten por otra vía» va en el LEAD, no en una puerta.** El auditor-rls y el banco mostraron
  que la ficha (PATCH de `vendedor_id`) y «tomar lead libre» movían un descartado en gestión. B6 es un trigger BEFORE UPDATE
  en `crm.leads` (descartado + cambia `vendedor_id`) que cubre las tres vías; y así `rescatar_descartes`, declarada con su
  huella en el censo, no se toca. Una baja (dueño inactivo) libera; devolverlo a su MISMO analista no es reasignar.
- Banco: B2 25/25 · B3 48/48 · B4 17/17 · B6 29/29; mutantes → FALLAN; reversas B6 → B5 → B3c → huellas de producción.
  Revisión del auditor en `BASE PARA GESTION/revisiones/2026-10-03-auditor-rls-b5-b6.md`.
- 🔴 En el Docker local, llamar a una función sin EXECUTE tumba Postgres (ya conocido del 20/08): se cayó una vez con la
  prueba de la ayudante privada. Ese caso se prueba con `has_function_privilege`, nunca llamándola.
- **Pedido nuevo — «Bases cargadas»** (detalle y plan en `BASE PARA GESTION/BASES-CARGADAS.md`): el supervisor carga bases
  antiguas y las reparte «40 a uno, 30 a otro» o una por una, y ve si se trabajan. Decisiones de Miguel: **E1** las dos
  entradas (archivo Excel/CSV con contactos nuevos **y** lotes de leads viejos del CRM); **E2** duplicado (mismo teléfono
  o DNI) se salta y se informa; **E3** el analista la trabaja dentro de su Base para gestión, con las mismas reglas;
  **E4** supervisor a su equipo, gerencia a todos. Fases B7–B10 + F5–F6, después de F2–F4.
- **FigJam** (`zbgq3gjYGsaaMCo6e140bU`), nodos nuevos: fases B3c `39:32`/`39:33` · B5 `27:2`/`27:3` · B6 `27:4`/`27:5` (las tres ☑ en producción 03/10); sección nueva «5 · Bases cargadas» `28:2` (decisiones E1 `28:11` … E4 `28:17`,
  flujo `29:3`→`29:23`, fases B7 `31:32` … F6 `31:42`, bocetos «Repartir» `32:35` y «Seguimiento» `33:33`); fases B5
  `27:2` y B6 `27:4` entre F1 y F2.
- **Listo para el `!` (03/10, tarde):** Codex r1 BLOCK (las suites aceptaban NULL como PASS; el detail del candado llevaba el
  lead_id) → arreglado → r2 PASS. Rama con datos (borrada): censo 42 → 38, advisors iguales, mismos resultados que los cuerpos
  vivos con los datos reales. Gate de RLS en Docker: ningún rojo nuevo, bloque nuevo 17/17. Evidencia en
  `BASE PARA GESTION/revisiones/2026-10-03-rama-b3c-b5-b6.md`. Orden de aplicación: B3c → B5 → B6, cada una con su registrador.
- **EN PRODUCCIÓN el 03/10 (~14:30 Lima):** Miguel aplicó con `!` B3c → B5 → B6, cada una seguida de su registrador.
  Comprobado en solo lectura tras cada paso (huellas del gate, ACL, trigger habilitado, registro con el md5 del archivo).
  El censo analítico quedó en rojo SOLO por `private.gestion_diaria_cola_hechos` (de otra sesión): la alerta f6a sigue hasta
  que esa sesión la arregle. Tipos regenerados (`390e21bc` en la rama del front, `083b0c57` en `main`). Falta publicar el front.
- **Front PUBLICADO el 03/10 (17:10 Lima)** con `/release-crm`: `build-20261003T221026768Z`, commit `c489d487` (el vivo de otra
  sesión `8db0d4f1` + F1 con «Mes» + gris del supervisor + tipos). Hubo que rearmar la rama: a las 14:26 otra sesión publicó
  `8db0d4f1` y nuestra rama nacía de `44985828`; el preflight lo habría rechazado (y habría borrado su filtro). Preflight OK,
  smoke con `index-*.js` idéntico. E2E: 2 rojos que también fallan en `8db0d4f1` (previos). PR #177 para el tronco de GitHub.
  🔑 El `.env` de un worktree lo copia Miguel con `!` (el hook bloquea tocarlo) y iCloud deja copias « 2» al cambiar de
  commit: apartarlas antes de construir.

## F2 · Ficha del lead de la base — HECHA en la rama (03/10/2026, tarde), sin publicar

- Rama `crm/base-gestion-f2` (`0f33bb0f` + `3e248407`), nacida del vivo `c489d487`. Hoja lateral ANCHA en dos columnas
  (regla «horizontal»): izquierda, registrar el intento (7 resultados con atajos 1–7, nota, fecha y hora para «volver a
  llamar» ≤ 10 días, aviso antes del 3.er intento); derecha, historial COMPLETO de corrido con buscador sin tildes;
  arriba, Reactivar y «No contactar» con motivo. Se abre tocando el nombre en la hoja («Ver ficha» en el celular).
- 🔑 Idempotencia en pantalla: un `p_operacion_id` por contenido (firma de resultado + nota + fecha): el doble clic o el
  reintento tras un corte reusan el id (replay); si cambia lo que se manda, id nuevo (si no, la puerta da 23505).
- 🔑 Cuando una acción saca la fila de la lista con la ficha abierta, el foco caía en `<body>`: `Sheet` ganó
  `focoRespaldo` (vecino → hoja/lista → resumen) y `focoInicial` (primer resultado). Probado en E2E.
- 🔑 El historial con `min-h-0` medía 0 px en el celular (grilla de una columna): el recorte va solo en `lg:`.
- «Quitar No contactar» va en F4: la base no lista vetados.
- revisor-a11y: CHANGES_REQUESTED → APPROVE. Pruebas y E2E Docker en verde; `npm run check` PASS (5667).

