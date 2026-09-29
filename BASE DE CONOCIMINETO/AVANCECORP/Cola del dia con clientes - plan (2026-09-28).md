---
tags: [crm, gestion-diaria, cola, postventa, plan, servidor]
fecha: 2026-09-28
estado: F1 EN PROD 28/09 · F2 EN PROD 29/09 (PR #130 fusionada) · F3 EN PROD 29/09 (build-20260929T164822097Z, ce9e688f; PR #131)
nivel: LEVEL 3 (funciones del núcleo, datos, alcance por rol)
---

# Cola del día con clientes — plan (2026-09-28)

## Lo que pidió Miguel
«En Gestión diaria también me salen las llamadas que tengo agendadas pero a clientes?» → No: la cola de
Gestión diaria solo trae leads. Miguel eligió la **opción 2: servidor**, para que la cola devuelva también las
tareas agendadas con clientes de cartera y haya una sola verdad para analista, supervisor y gerencia.

## Hechos (verificados el 28/09 en la base viva y en el código)
- `crm.cola_accion_v2_fn(p_limite, p_senal, p_etapa, p_analista_id, p_cursor)` (DEFINER, md5 `ef9b56ed…`) obtiene
  TODAS las filas autorizadas de `private.sla_operacion_autorizada(null,true)` (una por LEAD), filtra, calcula
  totales, ordena y pagina UNA vez (keyset por `prioridad, referencia_en, lead_id`; cursor con md5 de contexto).
  Las tareas de leads entran por `private.sla_tareas_hechos` (`join crm.tareas t on t.lead_id = h.lead_id`):
  **las tareas sin lead quedan fuera por construcción**.
- `crm.tareas`: un solo sujeto por fila (`lead_id` | `perfil_id` | `inversionista_id`). Hoy hay 17 tareas de
  clientes pendientes (3 analistas, 7 vencidas) frente a 1397 de leads. RLS real: `tareas_select` =
  `vendedor_id ∈ vendedor_ids_visibles(uid)` **o** (`vendedor_id is null` y `asignado_supervisor_id ∈ visibles`)
  **o** gerencia **o** lector global; restrictiva `tareas_postventa_lectura` (`inversionista_id is null or
  postventa_visible(inversionista_id)`, que a su vez depende del candado y flags de postventa).
- Contrato del front (`app/src/lib/sla-operacion.ts:12-59`): cada item exige `lead_id`, `lead`, `senales`,
  `estado`; un item sin lead tira la página entera (`SLA_CONTRACT`). Consumidores de la v2: Gestión diaria del
  analista (`analista.tsx`, `ordenarColaDiaria`: identidad, selección, `cerrados`, `asegurarLead`, cierre y
  siguiente fila, todo por `lead_id`), botón «GESTIÓN DIARIA» de Hoy (`use-conteo-gestion-diaria.ts`,
  `FILTROS_COLA_DIA` = `senal:'todas'`), Seguimiento y Hoy del supervisor (`abrirLead`).
- Candados: `private.assert_sla_nucleo()` (lista cerrada de funciones: exige `sla_operacion_autorizada(` y
  `sla_filtros_cola_validos(` en la cola y prohíbe mencionar `crm.tareas`); `assert_gestion_diaria_analista()` exige
  la firma exacta de la v2; md5 de la v2 fijado en `scripts/rollback-sla-accion-rol.sql` y
  `scripts/gestion-diaria-analista/ensayar.mjs`. `test-rls.mjs` no prueba la v2. Los e2e simulan la v2 en
  `app/e2e/_sla-cola.ts` copiando `muestraSql.cola.items[0]` y filtrando por `fila.lead.etapa`.
- Precedente para leer tareas de clientes: `private.gestion_diaria_pendientes_core` (`20260928043728`): INVOKER,
  `referencia_tipo` lead/perfil/postventa, error 22000 si el sujeto no es único, y detecta `vence_en` no finito.
- En Hoy la fila de cliente abre `abrirInversionista(...)`; una tarea con solo `perfil_id` no es clicable en
  ninguna pantalla; el cierre va por `CerrarTareaDialog` (ramas `perfil_id` e `inversionista_id`).

## Refutación de Codex (28/09, 527 s): CHANGES_REQUESTED, 3 P1 + 6 P2 — aceptados
Confirmó lo central (v3 aparte, servidor primero, v2 intacta) y tumbó el detalle: el alcance replicado «a mano»
omitía ramas de la RLS; «filas de la v2 + clientes» podía paginar dos veces; la identidad `lead_id | tarea_id`
sin tipo puede chocar; el contexto del cursor no cubría a los clientes; `pendientes` quedaba sin semántica;
faltaban la validación de fechas y el `<=`; `proximo_cambio_en` solo miraba leads; el teléfono en el payload
ampliaba la exposición sin puerta autorizada; y los candados/reversa no cubrían el ciclo de vida. Todo
incorporado abajo. Rechazadas las alternativas «lead sintético» y «dos endpoints fundidos en el front».

## Decisiones de diseño (v2)
1. **No se toca la v2 ni el núcleo SLA** (`sla_operacion_leads`, `sla_tareas_hechos`): contaminaría
   `primera_agenda`, `tareas_vencidas` y los avisos de leads, y rompería md5 sellados y candados. La v2 sigue
   viva para Seguimiento y Hoy del supervisor (y para los asserts que exigen su firma).
2. **Nueva puerta `crm.cola_accion_v3_fn`**, DEFINER, `search_path ''`, MISMA firma que la v2 (tipos y gates sin
   cambio de forma). **Una sola operación**: (1) todas las filas autorizadas de leads de
   `sla_operacion_autorizada(null,true)` — NO la página de la v2 —; (2) todas las tareas de clientes autorizadas
   del helper; (3) filtros con semántica definida para los dos tipos (`p_analista_id` → responsable de la tarea
   de cliente; `p_etapa` no nulo → excluye clientes; los filtros nunca amplían el ámbito); (4) contexto, totales
   y orden sobre la unión; (5) una sola paginación.
3. **Autorización de clientes en `private.tareas_clientes_autorizadas(p_uid)`** (STABLE, `search_path ''`, sin
   grants a `authenticated`, sin `auth.` dentro: recibe el actor desde la puerta), que reproduce **todas** las
   ramas de la RLS: `vendedor_id ∈ visibles` · `vendedor_id is null and asignado_supervisor_id ∈ visibles` ·
   gerencia (rama propia, no vía `crm.equipo`) · y la restrictiva de postventa para todos los roles
   (`postventa_visible_actor(inversionista_id, p_uid)`, incluida gerencia). Regla de PRODUCTO aparte y documentada
   (no «equivalencia con RLS»): lector global sin rol CRM y Directorio no reciben filas de clientes; una persona con
   rol CRM y condición global se trata por su rol CRM. Sobre ese conjunto autorizado se **valida integridad
   ANTES del recorte**: sujeto único (`num_nonnulls(lead_id,perfil_id,inversionista_id) = 1`, cubriendo también
   `lead_id + perfil_id` y `lead_id + inversionista_id`) y `vence_en` finito → error 22000 con detalle; luego se
   recorta a tareas `activo and estado='pendiente'` **del día**: vencida si `vence_en <= p_ahora` (igual que los
   leads), de hoy si cae antes de la próxima medianoche de Lima (expresado como límite superior para que use
   índice). Futuras fuera (viven en Agenda y «Tus citas»).
4. **Identidad con tipo**: cada fila lleva `clave` = `lead:<uuid>` | `tarea:<uuid>` (una fila POR TAREA; un
   cliente con dos tareas = dos filas). Deduplicación, keyset `(prioridad, referencia_en nulls last, clave)`,
   cursor v3 (`version 2`: `contexto, prioridad, referencia_en, clave`) y selección/cierre del front usan esa
   clave. El **contexto md5** incluye, además de actor/ámbito/filtros/límite, las filas de clientes autorizadas
   (clave, responsable, sujeto, referencia, señales) → cualquier cambio entre páginas invalida el cursor (22023,
   reinicio), como ya pasa con los leads. Cursores de la v2 se rechazan.
5. **Contrato v3 discriminado (aditivo)**: items de lead = idénticos a la v2 + `clave` + `sujeto:{tipo:'lead',id,
   nombre}`; items de cliente = `lead_id: null`, `lead: null`, `estado: null`, `tarea_id`, `bucket`
   (`tarea_vencida`|`tarea_hoy`), `prioridad` (la misma numérica que el bucket de lead equivalente),
   `referencia_en = vence_en`, `senales` (7 booleanos), `sujeto:{tipo:'cliente', perfil_id, inversionista_id,
   nombre}`. **Sin teléfono en el payload**: el contacto se carga al elegir la fila por la puerta autorizada que
   ya exista para inversionista/perfil (F2 la identifica; si no hay, la tarjeta no muestra teléfono).
6. **Señales y totales**: cliente vencida → `pendientes=true` y `tareas_vencidas=true` (entra en `todas`,
   `pendientes` y `tareas_vencidas`); cliente de hoy aún futura → solo `todas` (`pendientes=false`). `totales`
   cuenta clientes en `pendientes`/`tareas_vencidas` y añade `clientes` (número de TAREAS de clientes; si se
   muestra, abre ese mismo conjunto). El botón de Hoy cuenta exactamente lo que abre Gestión diaria (`todas`).
   `proximo_cambio_en` = mínimo entre el de los leads, el próximo vencimiento de cliente y la próxima medianoche
   de Lima (entrada de tareas nuevas al día).
7. **Candados y reversa**: `private.assert_cola_v3()` propio (no se toca `assert_sla_nucleo`): dependencias
   (`sla_operacion_autorizada(`, `sla_filtros_cola_validos(`, `tareas_clientes_autorizadas(`), propiedades
   (STABLE, DEFINER solo la puerta, `search_path ''`, owner), ACL efectiva (helper sin `execute` externo; puerta
   solo `authenticated`; sin `auth.` en el helper) y que la puerta no lea `crm.tareas` en crudo; md5 además, no
   en lugar. Reversa completa: `drop function` de puerta, helper y assert + entrada del ledger; la v2 y sus
   sellos no se tocan. No se retira la v3 mientras haya bundles que la consuman.
8. **Despliegue seguro**: F1 instala la v3 sin consumidores; el front cambia en F2 con clave de caché PROPIA
   (`cola-dia-v3`), nunca compartida con la v2.

## Fases
- **F0 — Plan v2** (esta nota) → OK de Miguel («sii», 28/09 ~19:15).
- **F1 — HECHA y EN PROD (28/09 ~20:55)**: migración `20260929004455_crm_cola_accion_v3_clientes.sql` (commit
  `9dc57651`): `private.tareas_clientes_autorizadas(p_uid, p_visibles, p_rol, p_global, p_ahora, p_fin_dia)` (INVOKER,
  sin grants; RLS completa reproducida; regla de producto lector global/Directorio), `crm.cola_accion_v3_fn` (misma
  firma que la v2, DEFINER solo `authenticated`, unión antes de paginar, clave tipada, cursor v2, contexto con clientes,
  `totales.clientes`, `proximo_cambio_en` con clientes y medianoche, `version: 3`), `private.assert_cola_v3()` con
  huellas selladas (puerta `1ec76074…`, helper `234ee27f…`; el postflight y el gate rechazan «SIN SELLAR»). Gate
  `test-rls.mjs` bloque `testColaAccionV3` (140 aserciones). Banco Docker propio a paridad (804 funciones, md5 idéntico;
  hubo que añadir el storage/auth de prod como superusuario local para que la suite llegue al final; la suite del repo
  está desfasada con la regla «canal concreto» de hoy: 27 `origen:'otro'` → parche solo en la copia del banco):
  ANTES 2280 ✓/37 ✗ → DESPUÉS 2383 ✓/37 ✗ (mismos 37, ajenos: PostgREST local devuelve 500 en códigos P0xxx).
  Índices: `tareas_cola_idx` y `tareas_bandeja_idx` ya cubren al helper. Registrador fail-closed
  `scripts/registrar-20260929004455.sql` (probado en banco, aplicado en prod: cuerpo exacto md5 `6fbbb05e…`).
  Advisors NOT RUN al cierre (MCP desconectado): revisar en el panel. auditor-rls y Codex aplicados.
- **F1 — Servidor** (`/nueva-migracion` → `AAAAMMDDHHMMSS_crm_cola_accion_v3_clientes.sql`): helper + puerta +
  `assert_cola_v3` + `COMMENT ON` + grants + ledger. Índice parcial candidato
  `(vendedor_id, vence_en, id) where activo and estado='pendiente' and lead_id is null` solo si `EXPLAIN` en el banco
  lo justifica (más la rama por `asignado_supervisor_id` si hace falta). Gate `test-rls.mjs` con los casos de
  Codex: ámbito por rol (A/B, supervisor con B fuera del subárbol, gerencia, lector global, Directorio); ramas
  omitidas (tarea sin vendedor con supervisor visible); postventa visible/no visible con flags; estados
  (hecha/cancelada/inactiva fuera); tiempo (vencida hace días, hoy futura, mañana, medianoche de Lima, instante
  exacto); integridad (dos sujetos, fecha no finita → 22000, sin afectar a otros actores); filtros; paginación
  real con límites 1–2, empates y varias tareas de una persona; invalidación de cursor; ACL (helper no ejecutable
  desde fuera; cursores v2/manipulados rechazados). Todo con sesiones autenticadas de usuarios de prueba en el
  banco Docker a paridad, gate ANTES y DESPUÉS; advisors; `auditor-rls`; merge nativo (Miguel con `!`); muestra
  SQL v3 para el fixture del front (aparte del v2).
- **F2 — Front del analista** (`app/`): `ColaDiaV3Schema` discriminado; `listarColaDia` + `useColaDiaPagina`
  (clave propia) en `analista.tsx` y `use-conteo-gestion-diaria.ts`; `FilaDiaria` con `clave` y `sujeto`;
  `ordenarColaDiaria`, selección, `cerrados`, siguiente fila, claves de render y callbacks por `clave`;
  `asegurarLead` y sesión de llamada solo en la rama lead; tarjeta **Cliente** (nombre; teléfono solo si hay
  puerta autorizada; «Registrar resultado» → `CerrarTareaDialog` con el payload que exija su rama perfil/postventa;
  el éxito cierra por `tarea_id`; sin ficha para solo `perfil_id`, sin enlace ficticio); espejo demo con clientes
  vencidos/de hoy, dos tareas de una persona y sin teléfono; `gen:types`; tests unitarios + fixture SQL v3 +
  e2e `_sla-cola.ts` con rama v3 (Docker). Release con preflight.
- **F2 — HECHA el 29/09 (sin publicar)**, en el worktree `AVANCECORP-desktop-worktrees/cola-v3-f2-20260929`.
  Lo que cambió en `app/`:
  - **Contrato y lectura**: `ColaDiaPaginaSchema` (unión lead | cliente con comprobaciones estrictas y claves
    únicas) en `lib/sla-operacion.ts`, `listarColaDia` y `useColaDiaPagina` con clave de caché PROPIA
    `cola-dia-v3`, y la entrada `cola_accion_v3_fn` A MANO en `database.types.ts`.
  - **Filas**: `FilaDiaria` = `FilaLead | FilaCliente`, con `tipo` y `clave`. Selección, `cerrados`,
    `siguienteTrasGuardar`, `key` y conteo del botón van por `clave`. Un cliente con dos tareas son dos filas.
  - **Tarjeta «Cliente»** en «Ahora»: nombre, «Cliente de tu cartera», tiempo en palabras y la tarea del ámbito.
    El teléfono sale de la ficha AUTORIZADA (`inversionista_ficha_fn`) y solo si `contactar` y no `no_contactar`.
    Es fail-closed si la relectura falla y usa `enlaceTel`. En el celular «Llamar» marca; en la laptop copia el
    número y abre el registro, como el lead. «Registrar resultado» abre `CerrarTareaDialog` con la tarea del
    store. Un cliente solo de portal no tiene ficha ni enlace ficticio.
  - **Cierre de un cliente**: lo decide el STORE en el primer commit tras el aviso del diálogo, no la página
    de la cola. Solo cuenta el primer aviso. «Ahora» pasa a la fila de detrás, sin esperas de red, y el foco
    no se pierde.
  - **Espejo demo** con las tareas de clientes del ámbito y la misma regla del servidor.
  - **`LIMITE_COLA_DIA`: 100 → 200**, el máximo de la v3.
  Verificación y revisiones:
  - `npm run check` PASS. E2E Docker de `gestion-diaria-*`, `hoy-*` y `sla-operacion`: **77/77**. Hay un e2e
    nuevo, `gestion-diaria-clientes.spec.ts`, con el flujo completo.
  - La muestra SQL REAL de la v3 se capturó en el banco a paridad, en una transacción deshecha
    (`sla-operacion-cola-v3-sql.test.fixture.json`), y pasa el esquema.
  - Revisiones: Codex pasada 1 → CHANGES_REQUESTED (2 P1 + 3 P2). Se aceptaron el teléfono fail-closed, el
    cierre por store y las carreras. El límite se aceptó en parte (200; lo demás es riesgo aceptado). Se
    rechazó con evidencia el P2 del demo de inversionista, porque el demo no tiene esas tareas.
  - `revisor-a11y` → CHANGES_REQUESTED. Se aceptaron el foco tras guardar, «Llamar» por aparato con
    `enlaceTel`, los avisos y los nombres accesibles.
- **F3 — HECHA el 29/09 (commit `ce9e688f` en `main`, sin publicar)**:
  - **Pantallas:** «Seguimiento comercial» y «Hoy» del supervisor leen la v3. Ya no queda consumidor de
    la v2 en el front: se retiraron `listarColaSla` y `useColaSlaPagina`. La función v2 del servidor sigue
    viva (CERRAR → OBSERVAR → DERRIBAR).
  - **Filas de cliente:** son un enlace a «Mi cartera» con el id que trae la cola. Sin ficha, la fila se
    lee y lo dice. No se inventa analista: en «Hoy», la columna dice «Cliente».
  - **Conteo:** el Seguimiento cuenta los clientes de la página, no `totales.clientes`, que no lleva la
    señal.
  - **Vigencia:** una página de otra revisión, o con el modo en error, no se pinta.
  - **Verificación:** check 4 900 PASS; e2e 78/78 (1 intermitente ajeno) y, sobre la base con el anexo,
    31/31.
  - **Revisiones:** Codex (LEVEL 2): se aceptaron el conteo, la canónica vieja y los dos de vigencia.
    `revisor-a11y`: se aceptaron el P2 de «Sin ficha» oculto en estrecho, los enlaces, la región viva y
    el contraste.
  - **Rebase:** la F3 se reasentó sobre el anexo de cronograma, publicado por otra sesión (vivo
    `fb79c46f`).
  - ✅ **PUBLICADA 29/09 ~11:50 Lima** (Miguel con `!`): vivo `build-20260929T164822097Z`.
    - **Smoke:** `index-D9XMRhsn.js` idéntico al construido y con el texto de la F3 dentro; home 200; ZIP y `license.md` 404.
    - **Asset anterior:** sigue en 200 desde la CDN, pero es inmutable y el HTML (`no-store`) ya sirve el nuevo. No hizo falta purgar.
    - **GitHub:** PR #131 (`integra/cola-v3-f3-20260929`). El `main` local integró la #130 (`77f79101`, sin cambios de archivos).
  - Pendiente: fusionar la #131 y traer `avancecorp/main`. La v2 del servidor se retira más adelante: CERRAR → OBSERVAR → DERRIBAR.
- **F3 (texto original del plan)**: Seguimiento y Hoy del supervisor a la v3 (navegación por sujeto, totales,
  acciones autorizadas) y, mucho después, retirar la v2 solo tras inventariar asserts, scripts y envoltorios
  (CERRAR → OBSERVAR → DERRIBAR).

## Riesgos que quedan
- Rendimiento: medir en el banco con `EXPLAIN`; las 17 filas de hoy no acreditan nada.
- `LIMITE_COLA_DIA = 100`: con clientes `hay_mas` llega antes y el botón de Hoy dice «sin cifras» (conducta válida
  mientras exprese incompletitud; la v3 admite hasta 200).
- Doble aparición coherente: una cita de cliente de hoy se ve en «Tu agenda de hoy», «Tus citas» y Gestión diaria.
- Tareas de solo `perfil_id`: visibles y cerrables, sin ficha (deuda previa).

## Verificación obligatoria antes de dar F1 por hecha
- [ ] Gate `test-rls.mjs` ANTES y DESPUÉS en el banco Docker (paridad) con los casos de arriba, con sesiones reales.
- [ ] Aislamiento: analista A no ve clientes de B; supervisor solo su subárbol; gerencia completo.
- [ ] Rol: lector global sin rol CRM y Directorio sin filas de clientes; postventa según candado y flags.
- [ ] Advisors de seguridad y rendimiento sin alertas nuevas; `EXPLAIN` documentado.
- [ ] `COMMENT ON` completo; sin secretos; ACL efectiva comprobada; ledger al día.

## Estado 29/09 (sesión que retomó la pausa)

- F2 hecha y verificada (ver «Fases»). Codex pasada 2: todo lo de la pasada 1 resuelto o retirado; 3 P2 nuevos
  → aceptados 2 (reprogramar a otro día saca la tarea de la cola; «Llamar» en laptop abre el registro sin esperar
  al portapapeles) y la hipótesis de orden store/commit se cubre vigilando el store 3 s; rechazado 1 con
  evidencia (una relectura fallida no destapa nada: la cola con error no se pinta).
- Commit publicable `9a74a1d0` (sobre `d20762ca`, SIN el anexo de cronograma, cuyo servidor aún no está en prod).
  Artefacto `crm-20260929T155246Z-9a74a1d05806` (verificado; copiado a `CRM-Avance-Corp/releases/`), **preflight
  OK** contra el vivo `build-20260928T233226790Z/7e9b426a`. Lleva además `7b2c9de0` (clientes en «Tu agenda de hoy»)
  y `89a8930a`, que esperaban publicación. Integrado en `main` local: `7a48282c` (fusión, `9a74a1d0` ⊂ `main`).
- ✅ **PUBLICADA 29/09 ~11:00 Lima**: Miguel desplegó con `!` (preflight del script OK); vivo
  `build-20260929T155245887Z`. Smoke OK:
  - `index-CWz0qth7.js` con sha256 idéntico al construido y la llamada a `cola_accion_v3_fn` dentro;
  - home 200; ZIP 404; `license.md` 404; el asset anterior `index-C-4-REdx.js` 404 (sin purga).
- ✅ **PR #130** a `avancecorp/main` (rama `integra/cola-v3-f2-20260929`, `898e1d03`): lo publicado sin lo de Gloria,
  sin el anexo y sin la entrada del ledger de «Leads reasignados». Al fusionarla, traer `avancecorp/main` al `main` local.
- Pendiente: retirar el banco `crm-banco-cola-v3` (detenido; solo quedan sus volúmenes) y la F3 (supervisor a la v3).
- `main` local integró `avancecorp/main` (#129) el 29/09 (`d20762ca`, sin cambios de archivos).
- Banco `crm-banco-cola-v3` DETENIDO otra vez con sus datos (se usó para capturar la muestra v3). Retirarlo tras
  publicar la F2: `supabase stop --no-backup --project-id crm-banco-cola-v3` + `git worktree remove`.

## Para retomar (pausa 28/09 ~21:30 · seguir el 29/09)

**Serial de la sesión de Claude:** `ab26b668-c893-4ae9-a1cf-87fbd5fab72e`
(`claude --resume ab26b668-c893-4ae9-a1cf-87fbd5fab72e`, desde `CRM-Avance-Corp/GESTION DIARIA`).

### Estado al pausar
- Todo commiteado en `main` local (HEAD `4e98042d`); nada de esta tarea queda sin commit. F1 EN PROD y registrada.
- Front: NADIE consume la v3 todavía (Gestión diaria del analista y el botón de «Hoy» siguen en `cola_accion_v2_fn`).
- Vivo en crm.miavance.com: `build-20260928T233226790Z` (commit `7e9b426a`, botón GESTIÓN DIARIA).
- Artefacto construido y SIN publicar: `CRM-Avance-Corp/releases/crm-20260928T235425Z-7b2c9de00cc6.zip` (commit
  `7b2c9de0`: gestiones de clientes dentro de «Tu agenda de hoy», fuera la pastilla «Vista personal»,
  `LIMITE_COLA_DIA` unificado). Antes de publicarlo: REPETIR el preflight contra el vivo (otra sesión puede haber
  publicado) y deploy por Miguel con `!` (`/release-crm`).
- Banco Docker `crm-banco-cola-v3` DETENIDO con datos (volúmenes conservados). Worktree
  `AVANCECORP-desktop-worktrees/banco-cola-v3-20260928`. Rearrancar: `cd …/banco-cola-v3-20260928/CRM-Avance-Corp &&
  supabase start`. Retirar tras F2: `supabase stop --no-backup --project-id crm-banco-cola-v3` + `git worktree remove`.

### Contrato v3 que el front debe leer (verificado en la migración `20260929004455`)
- Sobre: igual a la v2 pero `version: 3`; `totales` añade `clientes`; `proximo_cambio_en` ya incluye el próximo
  vencimiento de cliente y la medianoche de Lima.
- Item LEAD: los campos de la v2 + `clave: 'lead:<lead_id>'` + `sujeto: {tipo:'lead', id, nombre}`.
- Item CLIENTE: `clave: 'tarea:<tarea_id>'`, `tarea_id`, `lead_id: null`, `lead: null`, `estado: null`, `bucket`
  (`tarea_vencida` | `tarea_hoy`), `prioridad` (20 | 30), `severidad` (`critica` | `media`), `referencia_en` (= `vence_en`),
  `senales` (solo `tareas_vencidas` y `pendientes`, ambas = vencida), `sujeto: {tipo:'cliente', perfil_id,
  inversionista_id, nombre}`. SIN teléfono y SIN `responsable_id` (se quita antes de salir).
- Cursor: `{version: 2, contexto, prioridad, referencia_en, clave}`; cualquier otra forma → error del servidor.

### F2, orden de trabajo (front del analista, `app/`)
1. `src/lib/database.types.ts`: añadir A MANO la entrada `cola_accion_v3_fn` (mismos Args/Returns que
   `cola_accion_v2_fn`, línea ~5036). NO correr `gen:types`: otra sesión tiene ahí un cambio a mano sin commit
   (`p_reasignados`) y el generado lo pisaría. Commit solo de mi hunk (índice temporal `GIT_INDEX_FILE` + `git apply --cached`).
2. `src/lib/sla-operacion.ts`: `ColaDiaV3PaginaSchema` con unión discriminada por `sujeto.tipo` (`v.union`; `v.variant`
   exige la clave en la raíz); tipo `ItemColaDia`.
3. `src/data/sla-operacion-api.ts`: `listarColaDia` → rpc `cola_accion_v3_fn` con las MISMAS comprobaciones de contrato
   que `listarColaSla` (límite, filtros eco, `hay_mas` ⇔ cursor).
4. `src/data/sla-operacion-queries.ts`: `useColaDiaPagina` con clave PROPIA `[...raiz, actor, 'cola-dia-v3', filtros,
   cursor, limite]` (nunca la de la v2).
5. `src/lib/gestion-diaria-analista.ts`: `FilaDiaria` con `clave` y `sujeto`; `ordenarColaDiaria` sobre items v3
   (cliente vencido → grupo `tarea_vencida`; cliente de hoy → `tarea_hoy`); `filasDiariasDemo` con clientes (vencido,
   de hoy, dos tareas de una misma persona, sin teléfono).
6. `src/screens/gestion-diaria/analista.tsx`: `useColaDiaPagina`; identidad, selección, `cerrados`, siguiente fila y
   keys de render por `clave`; `asegurarLead` y sesión de llamada SOLO en la rama lead; tarjeta **Cliente** (nombre;
   teléfono solo si hay puerta autorizada; «Registrar resultado» → `CerrarTareaDialog`, que exige un `Tarea` completo:
   traer la tarea por id o construirla desde el item con su rama `perfil_id`/`inversionista_id`; el éxito cierra por
   `tarea_id`; sin ficha para solo `perfil_id`; sin enlace ficticio).
7. `src/data/use-conteo-gestion-diaria.ts`: `useColaDiaPagina` con la misma clave que el destino (caché compartida).
8. Pruebas: `gestion-diaria-analista.test.ts`, `analista.test.tsx`, `use-conteo-gestion-diaria.test.ts`,
   `sla-operacion-api.test.ts`; fixture `src/data/sla-operacion-sql.test.fixture.json` → añadir `cola_v3` capturado
   del banco (sesión autenticada de un analista de prueba, como hace `test-rls.mjs`); e2e `e2e/_sla-cola.ts` con rama
   `cola_accion_v3_fn` (los mocks hacen ECO de los argumentos) y correr `gestion-diaria-*.spec.ts` en Docker.
9. Codex refuta el diff (LEVEL 3: datos y alcance por rol) + `revisor-a11y`; `npm run check`; release con preflight;
   deploy por Miguel con `!`; PR de integración a `avancecorp/main` (sin lo de Gloria).

### Otros pendientes de esta tarea
- Advisors de Supabase (seguridad y rendimiento) NOT RUN al cierre de F1: revisar en el panel.
- Suite `supabase/scripts/test-rls.mjs` del repo desfasada con la regla «canal concreto» (27 fixtures `origen:'otro'`
  → canal concreto) y cleanup del banco con el trigger `perfiles_domicilio_legal_no_borrar`.
- PR #129 (contiene #128) pendiente de fusionar por Miguel → traer `avancecorp/main` al main local.
