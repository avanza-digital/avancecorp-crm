---
tags: [crm, escalabilidad, arquitectura, plan]
actualizado: 2026-08-08
estado: en-ejecucion (F0 ✅ · sigue F1)
---

# Plan de escalabilidad del CRM a data gigante

Relacionado con [[Inicio]], [[Limpieza controlada del dataset CRM]] y
[[Distribución de leads y base fría (plan revisado)]].

**Objetivo declarado por Miguel (2026-08-08):** que el CRM soporte "data
gigante". Rango de diseño: **100.000 a 1.000.000 de leads**, actividades ~10×.

**Procedencia:** borrador redactado sobre 6 mapas de reconocimiento del código
real (store, 29 pantallas, 11 RPC, capa API, demo/E2E, actividades) y depurado
con 30 hallazgos de crítica adversarial (4 bloqueantes) en tres lentes:
RLS/seguridad, front/demo/tests y secuenciación de despliegue. Todos los
hallazgos están incorporados abajo, en su fase.

## 📊 Estado de avance (al 2026-08-08, noche)

| Fase | Estado | Detalle |
|---|---|---|
| **F0 Cimientos** | ✅ **EN PROD** | 4 migraciones mergeadas (gate 521/521, advisors limpios, branch borrado) |
| **F1 Métricas al servidor** | ⬜ SIGUE | La fase que mata el techo de 2000; arranca con «retomemos F1 de escalabilidad» |
| **F2 Keyset** | ⬜ pendiente | Requiere F1 |
| **F3 Desmontar el store** | ⬜ pendiente | Requiere F1+F2 |
| **F4 Histórico vs vivo** | ⬜ pendiente | **Bloqueada por el DSN de Sentry** (Miguel) |
| **F5 Tableros** | ⏸️ diferida | Se abre por umbral medido, no por calendario |
| **Infra transversal** | 🟡 parcial | Alarma de topes instrumentada; pool de Auth y vigilancia mensual pendientes |

**F0 entregó** (2026-08-08): los 6 índices de lectura (`170231`), la función de
actividades versionada as-built (`170243`) y techada con ventana 365 d + LIMIT
10000 + índice (`170301`), la alarma de topes en las 5 lecturas del front (6
tests MSW; muda hasta que Miguel dé el DSN), y la decisión de convertidos
CERRADA: **45 días** (implementación en F1).

**F0 entregó además, sin estar planificado** — la corrida fue el primer gate
completo desde el 03-08 y destapó deuda de 3 ciclos ya en prod:
- Migración extra `crm_restaurar_prevalencia_p04_banca` (`173903`): corrige una
  regresión REAL del catálogo (miembro CRM revocado recuperaba banca por su rol
  de portal).
- Gate reconciliado con los diseños nuevos: 521 aserciones verdes (creación
  atómica, guards de agenda, matriz bancaria, canal legacy, ventana de
  actividades).
- 4 hallazgos documentados en [[Conflicto re-encolado vs destino efectivo (2026-08-08)]]
  y el ledger: re-encolado bloqueado con tareas pendientes (¿feature o bug?),
  Pagos exige membresía CRM (afecta solo `gloria@` y `AdminCorp@`), seed/gate
  sin vía sancionada para estados históricos, y la rama admin de
  `public.actualizar_contrato` sin guard (espera OK de Miguel).

**Desviación del plan original en F0:** de los 4 índices de FK del advisor
sobrevivió solo 1 (`enfriamiento_politica`) — los otros 3 eran de
`objetivos_vendedores`, archivada ese mismo día por la migración de metas
versionadas de otra sesión; el modelo nuevo nació indexado.

## Principio rector

> **El navegador NUNCA recibe filas para contarlas; la base de datos devuelve
> resultados agregados.**

Complementos innegociables: PEN y USD jamás se suman (toda métrica de dinero va
por moneda); todo cambio de esquema pasa por el ciclo branch → aplicar → gate
`test-rls.mjs` → advisors → merge, con ledger y `gen:types`.

**Regla de exclusión (para no sobre-ingeniar):** los agregados sobre conjuntos
acotados por el **roster** (decenas de filas: equipo, metas, config) se quedan
en el cliente. Solo migra al servidor lo que escala con leads/actividades.

## Estado de partida (hechos verificados)

- El store (`app/src/lib/store.tsx`, 2015 líneas) carga TODO el ámbito en un
  `Promise.all` de 6 llamadas y resincroniza COMPLETO tras cada mutación. Las
  pantallas operativas calculan sus métricas recorriendo arrays; solo los
  paneles de gerencia nuevos ya consumen RPC agregadas.
- Topes mudos: `MAX_LEADS_AMBITO=2000`, `MAX_TAREAS_AMBITO=2000`,
  `MAX_CLIENTES_CARTERA/MAX_CONTRATOS_CARTERA=2000`. Al pasarse, recorte
  silencioso de los leads menos tocados — golpea a gerencia primero.
- `actividades_del_ambito_fn` no tiene límite NI está versionada en el repo
  (drift: vive solo en prod, `MIGRACIONES.md:313-320`).
- `convertir_lead` no saca al convertido del ámbito: cada venta consume cupo
  para siempre.
- Existe patrón canónico de RPC consolidado (migraciones 20260803164348,
  20260807203740, 20260807203757): `security definer` + `stable` +
  `set search_path = ''`, guardia explícita primero (nunca RLS implícita),
  `revoke all` + `grant execute to authenticated`, visibilidad por
  `private.rol_crm` / `vendedor_ids_visibles` / `es_lector_global`, agregados
  en `jsonb` con `version:1`.
- Existe dormida `listarLeads` paginada (`crm-api.ts:310`) con tests MSW.
- ~~Migración de índices escrita y pendiente de aplicar~~ → ✅ EN PROD
  2026-08-08 junto con toda F0 (ver Estado de avance arriba).

---

## F0 — Cimientos ✅ COMPLETADA (en prod 2026-08-08; detalle en Estado de avance)

**Objetivo:** acotar toda lectura no acotada, instrumentar los topes, y cerrar
la decisión de los convertidos.

1. **Aplicar la migración de índices** `20260808155128` por el ciclo completo
   (recordar: `merge_branch` es asíncrono ~90 s). No editarla; si algo falla,
   migración nueva.
2. **Versionar as-built `crm.actividades_del_ambito_fn`**: migración con la
   definición EXACTA de prod (extraída con `pg_get_functiondef` en el branch,
   revisada por `auditor-rls`). Prerequisito duro del paso 3: prohibido
   modificar una función no versionada.
3. **LIMIT 10000 + ventana 365 días** en `actividades_del_ambito_fn` (segunda
   migración, `create or replace`, guardia y scoping intactos). Es tope de
   seguridad, hoy invisible (el CRM arrancó 2026-07); la ventana operativa de
   90 días es F4, cuando existan las compensaciones. Caso test-rls: actividad
   fuera de ventana no viaja.
4. **Alarma de topes**: helper `avisarTopeAlcanzado(nombre, tope)` en
   `crm-api.ts` → `registrarError('crm_api.tope_alcanzado', …)` (canal sin PII)
   cuando `filas.length === MAX`. Instrumentar las 4 lecturas con tope + el
   LIMIT nuevo de actividades. Test MSW por tope. El helper es desplegable sin
   DSN de Sentry: **el DSN NO bloquea F0** — queda como pendiente paralelo y
   pasa a ser **bloqueante del arranque de F4** (sus umbrales viven de esa
   telemetría).
5. **Decisión de convertidos — ✅ CERRADA por Miguel el 2026-08-08, se
   implementa en F1.** Su formulación: «ya no son leads, así que desaparecen
   cuando se convierten en clientes, después de **45 días**». Salen del ámbito
   operativo **por filtro de etapa con ventana**
   (`etapa <> 'convertido' OR convertido_en ≥ hoy − 45d`), `activo` queda
   intacto. 45 días sigue cubriendo `cierres-del-mes` (opera sobre
   `convertido_en` del mes en curso, máx. 31 días). NO usar `activo=false`: contaminaría la semántica de soft-delete
   (directorio ve soft-borrados) y el dedup del servidor debe seguir viendo al
   convertido para bloquear duplicados de clientes reales. La implementación va
   en F1 porque aplicar el filtro antes degradaría dos derivados sin reemplazo:
   las series de 6 meses (sub-contarían meses 4–6) y el aviso de duplicado en
   cliente. Miguel valida el default con captura de cartera.
6. `npm run gen:types` tras las migraciones.

**Gates:** `npm run check` · gate test-rls con el caso nuevo · advisors ·
`test:e2e` (demo no llama RPC: debe pasar sin tocar) · ledger.

**No se hace en F0:** subir `MAX_LEADS_AMBITO` (la solución es F1–F3, no un
tope más grande); tocar el store; ventana de 90 días.

---

## F1 — Métricas al servidor (6–8 sesiones; partible en F1a/F1b)

**Objetivo:** cada agregado que escala con leads/actividades llega calculado
por RPC SQL. **Requisito DURO de F2** (los totales de la UI dejan de depender
de contar filas).

### Inventario a migrar (11 métricas, todas con archivo:línea en el borrador)

Capital por moneda; conteos por etapa/embudo/donut; cola de acción (buckets);
sinTocar/estancados; métricas por vendedor; comparativa de equipos + parkeados;
conversión global/por origen + descartes por motivo; series comerciales 6 meses;
stats de tareas; resumen mi-cartera; resumen de reparto.

### RPC nuevas (7, en 2 migraciones)

**Tanda 1:** `resumen_cartera_fn()`, `cola_accion_fn(p_limite)`,
`metricas_vendedores_fn()`, `series_comerciales_fn(p_meses)`.
**Tanda 2:** `resumen_tareas_fn()`, `resumen_cartera_clientes_fn()`,
`resumen_reparto_fn()`.

Reglas grabadas por la crítica (no negociables al implementar):

- **Predicado canónico COMPLETO, incluida la rama de parkeados** (hallazgo
  mayor): `(vendedor_id in visibles) OR (vendedor_id IS NULL AND (rol =
  'gerencia' OR puede_operar_reparto_crm() OR es_lector_global()))` — copiado
  de `estado_sla_leads_fn` (20260807203757:1328). Sin esa rama, gerencia vería
  0 parkeados; y "arreglarlo" quitando el filtro abriría los leads sin dueño a
  cualquier rol.
- **Las 3 RPC de la tanda 2 llevan su WHERE explícito** (hallazgo BLOQUEANTE):
  `resumen_tareas_fn` scoped a visibles; `resumen_cartera_clientes_fn` con el
  MISMO predicado que `clientes_basicos_fn` (el bucket «sin asesor» solo se
  llena para gerencia/lector global); `resumen_reparto_fn` con gate
  `puede_operar_reparto_crm()`. Una definer que agrega todo sin re-implementar
  el scope es una fuga aunque devuelva números.
- `resumen_cartera_clientes_fn` **100 % canónica**: `search_path = ''` y
  tablas base calificadas — NO apilarse sobre `clientes_basicos_fn` (heredaría
  su excepción legacy de search_path).
- `cola_accion_fn` **devuelve también `ultimo_contacto_en`** (resuelto por
  lateral sobre `idx_actividades_lead`): es el dato del semáforo del kanban y
  decidirlo aquí es lo que deja a F3 sin migraciones (hallazgo BLOQUEANTE).
- Las señales que consume `alertas-provider` (`derivarAlertasVendedor/
  Supervisor` reciben hoy ámbito+actividades+tareas completos) se cubren
  extendiendo `cola_accion_fn`/`resumen_tareas_fn` con los campos que
  necesitan — si no alcanza, `alertas_operativas_fn` propia.
- **Contrato de denegación fijado POR RPC antes de codificar tests**: tabla
  explícita de qué devuelve el coordinador en cada una (agregado vacío o
  `42501`).
- Filtro de convertidos (decisión F0) aplicado en el MISMO corte
  (`VENTANA_CONVERTIDOS_DIAS = 45`) en SQL y en `listarLeadsDelAmbito`, junto
  con el debounce de `verificarDisponibilidadLead` en lead-nuevo.

### Front y demo (hallazgos bloqueantes incorporados)

- Hooks en `crm-queries.ts` (`useResumenCartera`, `useColaAccion`, …) con
  sufijo `fuente` demo/real, mappers Valibot fail-closed sobre los payloads
  jsonb.
- **Espejos demo leen el estado demo VIVO** (el `datos` del store /
  sessionStorage), NO la semilla estática — si no, crear un lead en demo no
  movería los tiles (BLOQUEANTE). Las series demo son la excepción: fixture
  RPC-shaped estático derivado de `SPARKS_DEMO` (computarlas desde 20 leads
  daría ceros), con serie separada por moneda — ningún punto suma PEN+USD.
- **Puente de coherencia transitorio** (BLOQUEANTE): mientras las mutaciones
  sigan pasando por el store (hasta F3), `persistir`/`resincronizarReal`
  invalidan por prefijo las claves nuevas de métricas tras cada mutación. Se
  retira en F3.
- `useSeriesComerciales` lo consumen las PANTALLAS, nunca el StoreProvider
  (cada refetch dentro del provider regeneraría el memo gigante).
- **`montarBackendReal` gana los handlers de las 7 RPC en el MISMO PR de cada
  pantalla migrada** (BLOQUEANTE: si no, los E2E de sesión real cuelgan), con
  el precedente de `metricasConversionesReal` (`_helpers.ts:648-814`).
- Estados de carga/error por hook definidos con el precedente de degradación
  (`objetivosError`: la pantalla vive con aviso, sin bloquear) + caso E2E de
  RPC caída → pantalla degradada visible.
- Cambio de pantallas en **2–3 tandas de release** (cartera/pipeline primero;
  hoy/* + equipo + directorio después), observando latencia real de cada RPC
  entre tandas — nada de big-bang de 8 pantallas.
- `acciones-demo.spec.ts` gana un assert de tile/cola tras crear lead.

### Matriz test-rls

Por RPC: casos permitido Y denegado por rol (vend1 solo lo suyo; sup1 subárbol;
gerencia todo; directorio lector; coordinador según tabla; `vendInactive` →
`42501`); vend1 NO ve parkeados ni personas ajenas; «sin_asesor»=0 para
vendedor; validación `p_limite` (`22023`); **sonda `anon`** y **verificación de
ACL** de cada función nueva (exactamente `{authenticated}`) — el revoke a
service_role es lo que un copy-paste incompleto rompe en silencio.

---

## F2 — Cursor keyset en listas (3–4 sesiones)

**Objetivo:** toda lista que escala con leads pagina por keyset en servidor;
muere `count: 'exact'`; la UI pasa a «cargar más».

**Decisión de diseño (absorbe un hallazgo mayor de inyección):** las listas
keyset van por **RPC `returns table` con parámetros tipados**
(`p_limite int default 50, p_antes_de timestamptz default null, p_antes_id
uuid default null`), no por `.or()` de PostgREST interpolando strings del
cliente. El cursor tipado lo valida Postgres — desaparece la superficie de
inyección de operadores y el saneo frágil (la allowlist de
`normalizarBusquedaPostgrest` mutila timestamps ISO; verificado). La
`listarLeads` dormida y sus tests MSW sirven de referencia de filtros, y el
camino final es RPC.

1. **`crm.cartera_pagina_fn`**: keyset `(actualizado_en desc, id asc)` servido
   por el índice de F0; filtros etapa/vendedor/texto (trigram vía
   `ilike '%'||p_texto||'%'`); **incluye `ultimo_contacto_en`** por lateral
   (semáforo del kanban). Dedup por `id` al concatenar páginas en
   `useInfiniteQuery` (un lead editado durante el scroll puede migrar de
   página; aceptado — no se congela snapshot).
2. **Cartera** → `useLeadsInfinitos` + «Cargar más»; tiles ya de F1.
3. **Mi-cartera**: keyset `(nombre asc, id asc)` **con su índice `(nombre,
   id)` en la misma migración** (hallazgo: sin él, cada página re-ordena la
   tabla). **Búsqueda y filtros (estado, sin_asesor, por_vencer) pasan como
   parámetros del servidor** — con keyset, filtrar en cliente sobre lo cargado
   miente (vacíos falsos, contadores parciales). Chips desde
   `resumen_cartera_clientes_fn`. El filtrado local queda solo para demo.
4. **`crm.leads_descartados` keyset** (hallazgo mayor de firma): **DROP
   explícito de la firma vieja + CREATE con TODOS los parámetros con default**
   (así el front viejo llamando con `{}` sigue vivo en la ventana
   servidor→front) + bloque completo revoke/grant (una función nueva sin
   revoke hereda EXECUTE de PUBLIC) — también sobre la `private.*_implementacion`
   si cambia. Sondas: llamada SIN argumentos + firma vieja responde `PGRST202`.
   Mismo tratamiento para `leads_por_repartir(p_limite)`.
5. **`crm.actividades_de_lead_fn`** (timeline por lead, base de F4): keyset
   `(creado_en desc, id asc)` sobre `idx_actividades_lead`; **contrato de
   denegación fijado: `42501` si el lead no es visible** (mismo predicado que
   las RPC de leads, incluida la rama sin-vendedor), aseverado con
   `expectExplicitAuthorizationDenied` — el timeline es PII conversacional y
   «vacío» sería indistinguible de un bug. Consumida por el drawer con
   `useInfiniteQuery`.
6. E2E: `montarBackendReal` responde páginas según el cursor.

**No se hace:** `config-usuarios` (roster, ya pagina); eliminar el boot
completo (F3); paginar el pipeline por columna (F3).

---

## F3 — Desmontar el store (6–8 sesiones; 100 % front, sin migraciones)

**Objetivo:** el store deja de ser fuente-de-verdad; cada pantalla consume su
caché por consulta (estrategia estranguladora), preservando demo y
write-gating. Gracias a la decisión de `ultimo_contacto_en` en F1/F2, esta
fase queda **realmente** sin migraciones.

1. Dominio de leads en TanStack (`crm-leads-queries.ts`): se levanta la
   prohibición deliberada de claves de leads (`crm-queries.ts:20-22`). Hooks
   demo-aware (fixtures vía `import()` dinámico).
2. Mutaciones a `useMutation`: `onMutate` optimista, `onError` rollback,
   `onSettled` invalidación por prefijo (muere `resincronizarReal`). La doble
   defensa de write-gating (`puedeEscribir` + guard demo) se conserva.
   **En el mismo PR se reescribe `acciones-real.spec.ts`** contra los handlers
   nuevos aunque siga bajo skip de `FUNCIONES_LEADS_APROBADAS` — si no,
   resucitaría contra un contrato muerto.
3. Mapa de invalidaciones por mutación (tabla completa en el borrador;
   se documenta como comentario-contrato en el código).
4. Estrangulamiento por riesgo ascendente, **lista completa** (la crítica
   encontró 3 consumidores omitidos): cartera → pipeline (kanban a
   `useLeadsInfinitos` por etapa; semáforo de `ultimo_contacto_en` servido) →
   agenda → hoy/vendedor → hoy/supervisor → equipo → hoy/directorio →
   **alertas-provider** (señales servidas de F1; espejo demo conserva
   `derivarAlertas*` sobre fixtures) → **App.tsx** (deep-links `#lead=<id>`
   validan con `useLead(id)`, no contra `ambito.leads` en memoria) →
   **hoy/gerencia.tsx** (identidades desde el roster, no del ámbito) → topbar
   (búsqueda global a RPC con debounce ≥300 ms sobre trigram) → drawers y
   modales.
5. Dedup en real vía `verificarDisponibilidadLead` (debounce ya de F1); en
   demo se conserva el índice local sobre fixtures.
6. `ambito` se extrae a `lib/demo-ambito.ts` como función pura SOLO demo (los
   E2E demo dependen de ese recorte exacto).
7. StoreProvider reducido a paneles + flags demo + write-gating. **Antes de
   borrar `epocaRef`** (hallazgo anti-fuga PII): endurecer el logout con
   `await queryClient.cancelQueries()` + `clear()` (hoy `clear()` no cancela
   fetches en vuelo) e incluir `perfil_id` en las claves; test de hooks que
   simula respuesta en vuelo tras logout y asevera que no repuebla caché.
   Splash: enumerar explícitamente las queries del boot mínimo con retry/
   timeout propio.
8. Tests de store migrados a tests de hooks sin bajar umbrales de cobertura.

**Gates:** `npm run check` + E2E completos tras CADA pantalla, no al final.
`equipo.spec.ts` (el más acoplado al ámbito) migra junto con su pantalla en el
mismo PR.

---

## F4 — Histórico vs vivo (2 sesiones; DSN de Sentry bloquea el arranque)

**Orden invertido por la crítica** (regla del propio proyecto: quitar filas de
una RESPUESTA exige front tolerante PRIMERO):

1. **Primero el front**: `antiguedad-etapa.ts:53` deja de buscar `cambio_etapa`
   en el timeline y consume `etapa_iniciada_en` de `estado_sla_leads_fn` (ya
   viaja; 20260807203757:1386). Puede adelantarse a F3 — no depende de nada
   de F4.
2. **Gate previo a tocar la RPC**: barrido CODEgraph de consumidores de
   `actividades_del_ambito_fn`. Si F3 la dejó huérfana, la migración correcta
   es de **deprecación** (revoke + comment), no la ventana de 90 días.
3. Si sigue viva: ventana 365 → 90 días. Degradaciones fail-safe verificadas:
   leads fríos caen al fallback `creado_en` (mismo bucket crítico); el veto
   «No responde» se vuelve MÁS estricto.
4. Higiene de tareas: aviso operativo cuando las vencidas acumuladas superen
   el 50 % del tope (una cartera abandonada puede llenar el LIMIT solo con
   vencidas).
5. **Partición de `crm.actividades` por RANGE(`creado_en`) — DIFERIDA.**
   Umbral: **> 5 M filas O p95 de `actividades_de_lead_fn` > 300 ms sostenido
   una semana**. Preparación documentada, no ejecutada: tabla append-only real
   (compatible); única traba, la FK `crm.tareas.resultado_actividad_id`
   (20260718180001:66) → columna sin FK + trigger de validación; PK compuesta
   `(id, creado_en)`.

---

## F5 — Tableros precalculados (DIFERIDA; 2–3 sesiones al activarse)

**Umbral:** p95 de `resumen_cartera_fn` o `metricas_vendedores_fn` > 500 ms
sostenido una semana, O ámbito de gerencia > 300.000 leads.

- Tabla `crm.resumen_cartera_diario` (RLS ON al crear, deny-by-default, sin
  DELETE, sin grants directos — se lee solo vía RPC) + refresco
  `private.refrescar_resumen_cartera()` con EXECUTE revocado.
- pg_cron cada 5 min (revisar jobs existentes: proyecto compartido con el
  portal).
- Lectura híbrida en las RPC de F1: resumen fresco < 10 min → servirlo; si no,
  calcular en vivo. **La rama híbrida re-aplica el MISMO predicado de scoping
  sobre la tabla resumen** (hallazgo mayor: se refresca con datos GLOBALES sin
  contexto de usuario; servirla sin filtrar filtraría los agregados de toda la
  empresa a cualquier vendedor). Caso test-rls: resumen sembrado para vend2 →
  vend1 no recibe sus filas.

---

## Infra transversal (1–2 sesiones repartidas; arranca con F0)

1. Pool de Auth/PostgREST a porcentaje (hoy Auth fijo en 10 conexiones);
   cambios de pooler/instancia en ventana coordinada con el portal (comparten
   `dctqcbznekcyxhjujuci`).
2. Umbral de subida de instancia: leads > 250 k O CPU p95 semanal > 70 % O
   cache hit < 99 % sostenido. Miguel aprueba el gasto.
3. Vigilancia mensual: `pg_stat_statements` top por tiempo total (RPC de F1 y
   keyset de F2 primero); conexiones vs pool (> 70 % = alarma); tamaño de
   `crm.actividades` (alimenta el umbral de F4); índices sin uso (no podar sin
   tráfico real); duración del boot y de cada RPC en Sentry.

---

## Decisiones abiertas

| # | Decisión | Default recomendado | Quién/cuándo |
|---|---|---|---|
| 1 | Convertidos en el ámbito | ✅ CERRADA (Miguel, 2026-08-08): ventana de **45 días**; `activo` intacto | Se implementa en F1 |
| 2 | Ventana de actividades | 365 d + LIMIT 10000 (F0); 90 d o deprecación (F4) | Confirmar en F4 con telemetría |
| 3 | Forma del keyset | RPC `returns table` con cursor tipado (no `.or()` de PostgREST) | Cerrada salvo objeción |
| 4 | DSN de Sentry | Pendiente paralelo; **bloqueante del arranque de F4** | Miguel |
| 5 | Umbral partición actividades | > 5 M filas O p95 timeline > 300 ms/semana | Chequeo mensual |
| 6 | Umbral activación F5 | p95 resumen > 500 ms/semana O gerencia > 300 k leads | Chequeo mensual |
| 7 | Umbral subida de instancia | leads > 250 k O CPU p95 > 70 % O cache hit < 99 % | Miguel aprueba gasto |
| 8 | Refresco tableros F5 | pg_cron 5 min | Se ratifica al activar F5 |
| 9 | Cambios de firma en RPC públicas | SIEMPRE drop explícito + defaults en todos los params + revoke/grant completo | Cerrada — regla permanente |

## Orden global y estimación

| Orden | Fase | Sesiones (≈ media jornada) |
|---|---|---|
| 1 | ✅ F0 Cimientos | HECHA (2026-08-08; tomó ~1 sesión larga, incluida la reconciliación no planificada del gate) |
| 2 | F1 Métricas al servidor | 6–8 (partible F1a/F1b) |
| 3 | F2 Keyset | 3–4 |
| 4 | F3 Desmontar el store | 6–8 |
| 5 | F4 Histórico vs vivo | 2 |
| — | F5 Tableros | 0 (diferida; 2–3 al activarse) |
| ∥ | Infra | 1–2 repartidas |

**Total al objetivo operativo (F0–F4): 20–26 sesiones.** El sistema queda apto
para 100 k–1 M de leads al cierre de F3; F4 consolida el costo de actividades;
F5 y la partición son válvulas ya diseñadas que se abren por umbral, no por
calendario.
