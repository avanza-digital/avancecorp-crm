ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: REFUTAR el plan de la pantalla «Hoy» del SUPERVISOR (puesto de mando en una pantalla) — LEVEL 2

Todavía NO hay código: se revisa el PLAN antes de que el dueño (Miguel, no desarrollador) lo
apruebe. Tu trabajo es encontrar lo que el plan rompe, olvida o subestima: funciones que hoy ve el
supervisor y se perderían, supuestos sobre datos que en producción no se cumplen, conteos que no
cuadran entre bloques, filtros que enseñan otra cosa que la que se promete, estados de carga / error /
vacío mal resueltos, regresiones de accesibilidad (tablist, filas desplegables, panel superpuesto,
foco), pruebas faltantes y riesgos de publicación. Si el plan es correcto en un punto, no lo menciones.

## Contexto

CRM interno (React 19 + Vite + Tailwind 4 + TanStack Query + Supabase) de una empresa de inversiones
en Lima. Roles: vendedor (analista), supervisor, gerencia. La pantalla «Hoy» del supervisor es su
arranque del día. Un diseñador entregó un paquete («handoff 2a», transcrito abajo): README + prototipo
HTML + un borrador `supervisor-mando.tsx` escrito contra el código actual. La idea: una sola pantalla
horizontal 1440×900 en tres bandas — (1) «Decide primero»: 3 tarjetas de decisión + desplegable
«Esta semana»; (2) «Cola urgente» (3/5) + «Equipo hoy» (2/5), donde tocar una decisión o un analista
FILTRA la cola; (3) franja «Consulta» con cifras en línea y un panel superpuesto «Detalle» con los KPI,
el cumplimiento del mes y la agenda del equipo.

## HECHO DE PRODUCCIÓN que el paquete no tuvo en cuenta (verificado hoy 27/09/2026, lectura SQL)

```
select modo, revision, primera_activacion_en from crm.sla_operacion_control;
→ modo = 'activo', revision = 1, primera_activacion_en = 2026-09-07 04:03:49+00
```

El borrador construye la banda 1 y la cola de la banda 2 sobre `useColaAccionOperativa` (RPC
`cola_accion_fn`), que la pantalla solo habilita con `modoSla.legado` (supervisor.tsx: `useColaAccionOperativa(..., modoSla.legado)`,
y la franja actual se pinta solo con `{modoSla.legado && <TresCosas …/>}`). En producción `legado`
es false → `cola = null` y `error = null`. Consecuencias si se implementa tal cual:
- banda 1: los candidatos `sin_responder` y `sin_movimiento` no existen; si tampoco hay agenda ni
  reparto, el borrador muestra «Cargando las decisiones del día…» para siempre (supervisor-mando.tsx:448);
- banda 2: dentro de `SlaOperacionBoundary` el modo activo pinta hoy SOLO la tarjeta «Seguimiento del
  equipo» con un enlace a `#/seguimiento`: la cola del diseño no existiría en producción.
`legado` solo es true en demo (`yo.demo`) o si gerencia apaga el seguimiento nuevo.

Además verificado en el cuerpo VIVO de `crm.cola_accion_v2_fn` (md5(prosrc) = 0a3ea253eef1be087d9121afc04499e5,
misma lógica que la migración 20260907212612 transcrita abajo): filtra por `p_analista_id` ANTES de
calcular `totales`, así que con filtro por analista los totales por señal son exactos para ese analista.

## Decisiones del dueño (NO son hallazgos)
1. El supervisor se hace ANTES que el analista (cambio de orden del 27/09).
2. Diseño en horizontal, en una pantalla; colores del CRM (navy #111e3d, azul #2563eb), sin verde;
   escala tipográfica del diseño (etiquetas 11 px versalitas, cuerpo 12–14 px, títulos 15–32 px).
3. Nada de siglas ni jerga en pantalla («SLA», «pipeline», «suma÷suma…»).
4. Se publica solo con su orden explícita (`/release-crm`); la pantalla vieja queda como respaldo.

## EL PLAN (técnico)

Sin cambios de base de datos, RPC, permisos ni grants. Solo pantalla + funciones puras en `lib/`.
Archivo nuevo `app/src/screens/hoy/supervisor-mando.tsx` (parte del borrador). `supervisor.tsx`
NO se borra (rollback de una línea en `screens/hoy.tsx`).

### Fuentes de datos por modo (regla central del plan)
| Pieza | Modo ACTIVO (producción) | Modo LEGADO (demo / seguimiento apagado) |
|---|---|---|
| Cola de la banda 2 | `useColaSlaPagina({senal, etapa:null, analista_id}, cursor, 7, true)` → `crm.cola_accion_v2_fn` | `useColaAccionOperativa` (como el borrador) |
| Conteos de pestañas | `pagina.totales` del servidor (respetan el filtro por analista) | `cola.porSev` / `total` del RPC (como hoy) |
| Filtro por analista | EN EL SERVIDOR (`analista_id`) | en cliente sobre `cola.items` + rótulo «de las N cargadas» si items < total |
| «Nuevos sin responder» (banda 1) | `totales.primera_atencion` de la consulta sin filtro; rojo si el primer ítem de una consulta `senal='primera_atencion', limite=1` tiene `severidad='critica'`, si no ámbar | `cola.porBucket.sin_responder` (como hoy) |
| «Sin movimiento» (banda 1 y pestaña) | NO existe (no hay fuente); sin dato no hay tarjeta ni pestaña | como hoy (`cola.estancados`) |
| No asistió / sin próxima acción | `useMetricasAgenda` (igual en ambos modos) | igual |
| Por repartir | `resumen_cartera_fn` (igual en ambos modos) | igual |

Pestañas en modo activo: «Para atender ahora» (`senal='pendientes'`, conteo `totales.pendientes`) ·
«Tareas vencidas» (`tareas_vencidas`) · «Todas» (`senal='todas'`, conteo `total_items` de esa
consulta — hipótesis: se pide con `limite=1` para tener el número sin traer filas). Patrón tablist WAI-ARIA existente (flechas/Home/End, conteo en el nombre accesible).

Mientras el modo no se conoce (`!legado && !activo && !error`) o falla: la banda 1 NO se pinta y la
banda 2 muestra el estado de `SlaOperacionBoundary` («Consultando el seguimiento comercial…» /
«No se pudo cargar el seguimiento» + Reintentar). Nunca «Cargando…» eterno.

### Etapa S1 — Esqueleto + banda 2 (cola + equipo)
- `supervisor-mando.tsx` con las tres bandas; `hoy.tsx` apunta a `HoySupervisorMando` en local
  (no se publica hasta S4).
- Cola: fila del diseño (tira de severidad 3 px con `SEV_COLOR`, analista primero salvo con filtro,
  nombre 14 px, 2.ª línea `ACCIONES_SLA[bucket]` · tiempo desde `referencia_en`, `AccionesContacto`
  compacto, chevron, `aria-label` «Abrir ficha de …», `abrirLead`). Monto: se toma del lead del store
  si está cargado; si no, NO se pinta (el store es caché parcial: desconocido ≠ 0). 7 filas + «Ver
  todo en Seguimiento →» (`#/seguimiento`); en modo legado, el «Ver los N» actual.
- Chips por analista: salen del roster del equipo (no de las filas cargadas) → «Todos» + un chip por
  analista SIN número; al elegir uno, el título pasa a «Cola de Karen · N» con N = `totales` del
  servidor filtrado. (Evita el «Urgente 17 / Todos · 12» del prototipo.)
- Equipo hoy: como el borrador (punto solo con señal, umbrales `<2 d` azul · `2–5` ámbar · `>5` rojo,
  no-show ≥2 rojo, sin acción ≥3/≥5), CONSERVANDO «N de cartera» de la fila actual; SIN «N en cola»
  en modo activo (daría N consultas); fila seleccionada = filtro + despliegue con chips de señal y
  «N toques · N % cierres». La segunda línea y los chips no repiten la misma frase.
- Enlace de la cabecera: «Mi equipo hoy →» a `#/gestion-diaria` (vista del supervisor que ya existe
  con la actividad del día por analista) en vez de `#/equipo`.

### Etapa S2 — Banda 1 «Decide primero»
- `lib/tres-cosas.ts`: (a) separar `candidatosDeHoy` (sin recorte) y `tresCosasDeHoy` = slice(0,3)
  — parche del handoff, comportamiento idéntico; (b) añadir `vendedorId?: string` a `CosaDeHoy`
  cuando la cosa es de UN analista (no_asistio / sin_accion) → se retira el puente «buscar el nombre
  en el texto»; (c) entrada nueva opcional `seguimiento: { primeraAtencion: number; hayCritica: boolean } | null`
  que en modo activo alimenta `sin_responder` (misma regla de severidad: rojo solo si hay crítico).
  Los tests existentes de `tres-cosas.test.ts` deben seguir verdes sin tocarse, salvo los `toEqual`
  que cambien por `vendedorId` (se ajustan explícitamente).
- Tarjeta: cifra 32 px + rótulo «Hoy»/«Esta semana» + título + botón navy con la acción + chevron.
  Clic en tarjeta = desplegar una línea de contexto y FILTRAR la banda 2 a LO QUE LA TARJETA DICE:
  - sin_responder → modo activo: `senal='primera_atencion'`; legado: pestaña Urgente + bucket.
  - no_asistio → NO filtra la cola (la cola no contiene citas no asistidas); despliega y su botón
    lleva a la agenda del analista / Equipo (el borrador filtraba la cola de Milagros y enseñaba
    otros leads: corregido).
  - sin_accion → filtro por analista (`vendedorId`).
  - por_repartir → solo despliega; botón «Repartir» a `#/derivaciones` con el `aria-label` que ya
    existe en el KPI actual.
- «Esta semana · N» (`<details>` nativo): los candidatos ámbar que no entraron en las tres.
- Sin cosas: con datos cargados, «Nada que decidir ahora mismo»; sin datos, no se pinta la banda.

### Etapa S3 — Banda 3 «Consulta» + panel «Detalle»
- Barra: Pronóstico (PEN, USD aparte) · leads activos · % capital confirmado · conversión del mes |
  toques 7 d · % completadas · no asistió (rojo ≥2). Mismo dato que las KpiCard/`filasMeta`; sin dato «—».
  Textos SIN «pipeline», SIN «suma÷suma del servidor», SIN «solo producción».
- «Detalle» abre un panel superpuesto (no empuja; Esc y «Cerrar» cierran; foco al abrir en el título
  del panel y al cerrar vuelve al botón). Dentro, con los componentes de hoy: 4 KpiCard ·
  «Cumplimiento del mes» con la nota del capital en USD y el botón «Reintentar» (objetivos /
  cumplimiento / conversión / TC) · `AgendaEquipoPanel` · `DesglosePorEmpresa` («Por empresa») ·
  `TasasAutorizadasAnalistaPanel` (por defecto se conserva aquí; Miguel decide si se quita) · pie
  «Ves solo a tu equipo…».
- `AvisoDegradacion` debajo de la banda 1, como hoy.

### Etapa S4 — Cierre
- `supervisor-mando.test.tsx`: casos de `supervisor.test.tsx` que apliquen + ESTADO DE PRODUCCIÓN
  (seguimiento ACTIVO, sin metas publicadas, cola legada deshabilitada) + modo desconocido/caído +
  filtro por analista con totales del servidor + tarjeta no_asistio que NO filtra + tablist con flechas.
  Mocks de `cola_accion_v2_fn` con la FORMA real del contrato (valibot `ColaSlaPaginaSchema`).
- E2E en local con Docker (teclado: tarjetas, chips, filas del equipo, Detalle con Esc).
- `revisor-a11y`, review de código de Codex, `npm run check`, `npm run gate:realidad`,
  `npm run test:e2e:docker`.
- Miguel lo mira en local; publicación solo con `/release-crm`. Rollback: `hoy.tsx` vuelve a `<HoySupervisor />`.

### Qué NO cambia
Base de datos, RPC, permisos; la pantalla del analista; «Gestión diaria → Mi equipo hoy» del
supervisor; la vista Seguimiento; la campana; las reglas de color (`lib/semaforo.ts`) y de «sin dato → —».

### Diferidos
Nombres en Title Case (formateador aparte); «N en cola» por analista en modo activo (necesitaría un
conteo por analista en el servidor); rediseño VitaNova de «Mi equipo hoy».

### Preguntas concretas para ti
1. ¿Es correcto mostrar la cola del seguimiento nuevo en «Hoy» (vista previa de 7 + enlace), o choca
   con la regla «una cosa se avisa en un solo lugar» dado que ya existen la vista Seguimiento y la
   campana (`useResumenAvisosSla`)? ¿Y la tarjeta «nuevos sin responder» junto a la campana?
2. ¿La equivalencia `sin_responder` ↔ `primera_atencion` es fiel? (en el modelo nuevo
   `primera_atencion` respeta compromisos: migración 20260907194756).
3. ¿Qué rompe mantener DOS fuentes (activo / legado) en un mismo componente? ¿Sería mejor
   `legado ? <HoySupervisor/> : <HoySupervisorMando/>`, sabiendo que el demo es siempre legado?
4. Coste: la pantalla haría 2–3 llamadas a `cola_accion_v2_fn` (página, primera_atencion limite 1,
   Todas limite 1) y cada una recalcula `private.sla_operacion_autorizada` entera. ¿Riesgo real?
5. ¿Qué se pierde de `supervisor.tsx` que el plan no nombra?

---
# EVIDENCIA TRANSCRITA (con números de línea)

## `design_handoff_hoy_supervisor/README.md (handoff del diseñador)`
```
     1	# Handoff · Hoy del supervisor en una pantalla (propuesta 2a)
     2	
     3	Paquete para quien mantiene `CRM-Avance-Corp/app`. Objetivo: implementar la pantalla **Hoy** del rol supervisor como puesto de mando en una sola pantalla (1440×900, orientación horizontal), **sin tocar la lógica de negocio ni los RPC**.
     4	
     5	## Qué hay en esta carpeta
     6	
     7	- `Hoy Supervisor - una pantalla.dc.html` + `support.js` + `brand/` — la **referencia de diseño en HTML** (prototipo navegable: ábrelo en el navegador). No es código para copiar: la tarea es recrearlo en la app real (React 19 + TS + Tailwind v4) con los componentes y hooks que ya existen.
     8	- `supervisor-mando.tsx` — **implementación propuesta**, escrita contra los componentes, hooks y helpers actuales del repo. Va como archivo NUEVO en `app/src/screens/hoy/`. Léela como borrador fuerte: compila contra las firmas leídas el 2026-09-27 en `main`; revisa imports y tipos con `npm run check` antes de dar por bueno.
     9	- Fidelidad: **alta**. Colores, tipografía y espaciados son los del sistema del CRM (`index.css`); no hay tokens nuevos.
    10	
    11	## Regla de oro: qué NO cambia
    12	
    13	Todo lo siguiente se reutiliza tal cual desde `screens/hoy/supervisor.tsx`. Si algo de esto se toca, se rompe una decisión ya tomada:
    14	
    15	- Hooks y fuentes: `useResumenCarteraOperativo`, `useColaAccionOperativa`, `useMetricasVendedoresOperativas`, `useMetricasAgenda` / `metricasAgendaDemo`, `useConversionMensual` / `conversionMensualDemo`, `useTipoCambio`, `useEstadoSlaOperativo`, `useModoSla`, `useAhora`, y toda la derivación mensual (`metaVigente`, `totalEnSoles`, `lecturaCobertura`, `filasMeta`).
    16	- `tresCosasDeHoy` decide QUÉ tres cosas salen y en qué orden (rojo primero, peso fijo, máximo tres, sin dato no hay tarjeta). La pantalla solo las pinta más grandes.
    17	- Presupuesto de color (`lib/semaforo.ts`): rojo = hoy con acción al lado, ámbar = esta semana, azul = acción, violeta categórico, neutro sin señal, sin verde. El color nunca va solo (siempre texto + forma).
    18	- Conteos del RPC, no del store: pestaña Urgente = `porSev.critica + porSev.media`; Todo = `total`; estancados al tope → `50+`.
    19	- «Una cosa se avisa en un solo lugar»: Sin movimiento sigue siendo pestaña de la cola.
    20	- Sin dato → «—». Ninguna afirmación positiva sin payload.
    21	- Pronóstico (`capitalPrincipal`: PEN, USD aparte) y cumplimiento (`totalEnSoles` con TC) siguen siendo dos cifras distintas.
    22	- Umbrales del semáforo por analista: `<2 d` azul · `2–5` ámbar · `>5` rojo; no-show ≥2 rojo; sin acción ≥3 (≥5 crítico). Punto solo cuando hay señal.
    23	- Patrón tablist WAI-ARIA con el conteo en el nombre accesible; `aria-label` de cada fila dicta lo visible; objetivos ≥36 px; foco visible (`focus-visible:ring-[3px] focus-visible:ring-ring/40`).
    24	- `SlaOperacionBoundary`: en modo SLA no legado la cola se sustituye por la tarjeta «Seguimiento del equipo», igual que hoy.
    25	
    26	## Cómo se conecta (sin romper nada)
    27	
    28	1. Copiar `supervisor-mando.tsx` a `app/src/screens/hoy/supervisor-mando.tsx`. **No borrar** `supervisor.tsx`: queda como rollback y sus tests siguen verdes.
    29	2. Aplicar el parche pequeño en `lib/tres-cosas.ts` (abajo): exporta los candidatos completos para poder pintar «Esta semana» sin duplicar la regla. Los tests existentes no cambian.
    30	3. En `app/src/screens/hoy.tsx`, un solo cambio:
    31	   ```tsx
    32	   import { HoySupervisorMando } from './hoy/supervisor-mando'
    33	   // …
    34	   case 'supervisor':
    35	     return <><ConfiguracionRespuestasTasa soloActivacion /><HoySupervisorMando /></>
    36	   ```
    37	   Rollback = volver a `<HoySupervisor />`.
    38	4. Añadir `supervisor-mando.test.tsx` copiando los casos de `supervisor.test.tsx` que sigan aplicando (degradación con «—», conteos de pestañas, tablist con flechas, semáforo del equipo) y el caso canónico **«ESTADO DE PRODUCCIÓN (sin metas publicadas)»**. Correr `npm run check` y `npm run gate:realidad` antes de dar por bueno el arreglo (regla de `CLAUDE.md`).
    39	5. `revisor-a11y` antes del merge: hay controles nuevos (chips por analista, filas desplegables del equipo, franja Consulta).
    40	
    41	### Parche en `lib/tres-cosas.ts` (6 líneas)
    42	
    43	```ts
    44	/** Todos los candidatos del día, ya ordenados (rojo primero, peso fijo), SIN recortar. */
    45	export function candidatosDeHoy(input: TresCosasInput): CosaDeHoy[] {
    46	  // …cuerpo actual de tresCosasDeHoy hasta el sort, sin el .slice(0, TOPE)
    47	}
    48	export function tresCosasDeHoy(input: TresCosasInput): CosaDeHoy[] {
    49	  return candidatosDeHoy(input).slice(0, TOPE)
    50	}
    51	```
    52	Es decir: renombrar la función actual a `candidatosDeHoy`, quitarle el `.slice(0, TOPE)` final, y dejar `tresCosasDeHoy` como envoltura que recorta. Comportamiento idéntico para todos los llamadores.
    53	
    54	## La pantalla
    55	
    56	Un solo `div` de contenido, `max-w-[1376px]`, tres bandas horizontales. Con el menú lateral en riel (64 px, ya existe en `sidebar.tsx`) todo cabe en 1440×900; con el menú fijado abierto (240 px) también cabe, con columnas más estrechas. El `<main>` sigue siendo el que hace scroll si la ventana es más baja.
    57	
    58	### Banda 1 · «Decide primero»
    59	
    60	- Fila de cabecera: `h2` «Decide primero» (18 px / 800 / navy) y, a la derecha, el desplegable **«Esta semana · N»** (chip blanco con punto ámbar de 8 px; `<details>` nativo, la lista aparece en un popover absoluto de 320 px). N = candidatos ámbar que no entraron en las tres cosas. Si no hay, el chip no se pinta.
    61	- Tres tarjetas en `grid-cols-3`, `gap-3.5`, cada una `Card` con borde izquierdo de 4 px en el color de su severidad (`SEMAFORO.critico` / `SEMAFORO.atencion`):
    62	  - Cifra grande: primer número del texto de la cosa (32 px / 800 / navy, tabular). Si el texto no empieza por número, no se pinta la cifra.
    63	  - Rótulo de severidad (11 px / 700 / mayúsculas / tracking .08em): «Hoy» en `--destructive-text`, «Esta semana» en `--warning-text`.
    64	  - Título: el resto del texto (15 px / 700, truncado).
    65	  - Botón de acción navy (`Button` default, 34 px de alto) con la `accion` de la cosa y flecha. Navega igual que la franja actual (`destino`).
    66	  - Chevron a la derecha: girado 90° cerrado, −90° y azul abierto.
    67	- Clic en la tarjeta = **desplegar** (una línea de contexto calculada con datos ya cargados) **y filtrar** la banda 2:
    68	  - `sin_responder` → pestaña Urgente + filtro de bucket `sin_responder`.
    69	  - `sin_movimiento` → pestaña Sin movimiento.
    70	  - `no_asistio` / `sin_accion` → filtro por analista (el dueño se resuelve por el prefijo `«Nombre: »` del texto; ver nota técnica).
    71	  - `por_repartir` → solo despliega; la acción lleva a Derivar leads.
    72	- Segundo clic cierra y quita el filtro. Cambiar de pestaña a mano también quita el filtro de bucket.
    73	- Sin cosas: si `cola == null` se pinta «Cargando las decisiones del día…»; si la cola llegó y está vacía, «Nada que decidir ahora mismo».
    74	
    75	### Banda 2 · Cola + Equipo (`grid-cols-5`, cola `col-span-3`, equipo `col-span-2`)
    76	
    77	**Cola urgente** (`Card`, `SectionHead` con `ListChecks`):
    78	- Título dinámico: «Cola urgente» / «Nuevos sin responder» / «Cola de Karen» según filtro. Sub en gris: «· N urgentes» (del RPC) o «· N leads».
    79	- Tablist actual sin cambios (Urgente N · Sin movimiento N · Todo N), incluidas flechas/Home/End y el conteo en `aria-label`.
    80	- Fila de **chips por analista** bajo el título: «Todos · N» y un chip por analista con leads en las filas cargadas (`primerNombre` + conteo). Activo = navy con texto blanco; inactivo = borde `border`, texto `muted-foreground-strong`. Alto 28 px, radio completo. Si `cola.items.length < cola.total`, el rótulo dice «de las N cargadas» para no prometer conteos que el RPC recortó.
    81	- Filas (7 visibles, luego «Ver los N» con el patrón actual de expandir): tira de 3 px a la izquierda con `SEV_COLOR[sev]` (transparente en baja); **el analista va primero** (avatar 26 px + nombre corto, ancho fijo 118 px) salvo cuando hay filtro por analista; nombre del lead 14 px / 600 truncado; segunda línea `BUCKET_LABEL · motivo` 12.5 px gris; monto 13 px / 600 tabular a la derecha; `AccionesContacto compacto`; chevron. Misma `aria-label` «Abrir ficha de …» y misma apertura con `abrirLead`.
    82	- Pestaña Sin movimiento: bloque de estancados actual sin cambios (novedades desde la última visita incluidas).
    83	
    84	**Equipo hoy** (`Card`, `SectionHead` con `UsersRound`; sub «· N en rojo · N en ámbar»; enlace «Gestión de equipo →» a `hashDe('equipo')`):
    85	- Una fila por analista de `rank`: punto de 8 px solo cuando hay señal (mismo cálculo que hoy), `Avatar` 30 px, nombre 13.5 px / 700, segunda línea con la señal en palabras (`Última actividad hace N d · N vencidas · N sin acción` o `Sin leads abiertos`), a la derecha capital unificado 13.5 px / 800 + `DesgloseMonedas compacto`, y debajo «N en cola» (conteo de filas cargadas de la cola para ese analista).
    86	- Clic en la fila = seleccionar (fondo `accent/8` con borde `accent/28`, radio 10 px) → filtra la cola. Al seleccionar, la fila **se despliega**: chips de señal (rojo/ámbar según umbral; `Badge solid` rojo «N no asistió» cuando ≥2) y, al final, «N toques · N % cierres» de la agenda de 7 días. Sin señal: chip neutro «Al día».
    87	- Rótulo del TC («Capital en proceso · TC …») pasa a la franja Consulta.
    88	
    89	### Banda 3 · Franja «Consulta» (pie, 48 px)
    90	
    91	- Barra blanca con: «CONSULTA» (10.5 px / 700 / mayúsculas), cifras en línea (12.5 px, número en 800 navy): pronóstico de capital, leads activos, % capital confirmado, conversión del mes, separador, toques 7 d, % completadas, no asistió (rojo si ≥2). Cada cifra sale del mismo dato que hoy pinta la KpiCard o `filasMeta`; sin dato, «—».
    92	- Botón «Detalle» (borde, texto azul, 32 px). Abre un **panel superpuesto** anclado sobre la barra (`absolute`, `bottom-14`, `z-20`, sombra `--shadow-pop`) que no empuja nada. Dentro, con los componentes de siempre:
    93	  1. Las 4 `KpiCard` actuales (mismos labels, subs y reglas de «—»).
    94	  2. Tarjeta «Cumplimiento del mes» con las dos filas de `filasMeta` y `Progress` con `colorMeta`.
    95	  3. `AgendaEquipoPanel` tal cual.
    96	- «Cerrar» vuelve a la barra. Esc también cierra.
    97	
    98	### Lo que se retira de la primera vista
    99	
   100	- `TasasAutorizadasAnalistaPanel`: fuera de esta pantalla por indicación del negocio (el supervisor no acepta tasas). Si el supervisor también opera cartera propia y necesita ver sus solicitudes, cabe dentro del panel «Detalle»; decidirlo con Miguel antes de borrar la importación.
   101	- `AvisoDegradacion` se mantiene, debajo de la banda 1.
   102	
   103	## Interacción y estado
   104	
   105	Estado local del componente (además del que ya existe: `pestanaElegida`, `colaExpandida`, visita F4.3):
   106	- `decisionAbierta: CosaDeHoy['id'] | null`
   107	- `bucketFiltro: 'sin_responder' | null`
   108	- `analistaFiltro: string | null` (perfil_id)
   109	- `consultaAbierta: boolean`
   110	
   111	Transiciones: clic en tarjeta de decisión → abre/cierra + fija filtros según su `id`; clic en chip o fila de equipo → `analistaFiltro` (toggle) y limpia `bucketFiltro` y `decisionAbierta`; cambiar de pestaña → limpia `bucketFiltro`; «Todos» limpia ambos. Todo es filtro en cliente sobre las filas ya cargadas; **el RPC no cambia**. Transiciones CSS de la casa (`transition-colors`, `ac-rise`, `ac-pop`), sin animaciones nuevas; respetar `prefers-reduced-motion` (ya global).
   112	
   113	## Notas técnicas y riesgos
   114	
   115	- **Dueño de una cosa por texto**: `CosaDeHoy` no trae `vendedorId`; la pantalla lo resuelve buscando el analista cuyo `nombre` es prefijo `«Nombre: »` del texto. Es un puente. Lo limpio es añadir `vendedorId?: string` a `CosaDeHoy` en `lib/tres-cosas.ts`; ojo con los `toEqual` de `tres-cosas.test.ts` al hacerlo.
   116	- **Conteos por analista** salen de `cola.items` (recortados por `p_limite = 100`). Si `items.length < total`, decirlo. Alternativa a futuro: `p_vendedor` en `cola_accion_fn`.
   117	- **Title Case de nombres**: los nombres llegan en mayúsculas del servidor. El prototipo los muestra en Title Case; si se quiere en producción, es un formateador (no `text-transform`: «DE LA CRUZ» y los compuestos lo rompen). Fuera del alcance de este paquete.
   118	- **Tests**: los de `supervisor.test.tsx` no cubren el archivo nuevo. Sin `supervisor-mando.test.tsx` el gate de cobertura de `src` cae.
   119	- Menú en riel: no forzarlo desde la pantalla; es preferencia del usuario (`ac-crm-sidebar-colapsado`).
   120	
   121	## Tokens usados (todos existentes en `index.css`)
   122	
   123	Colores: `--primary #111e3d`, `--accent #2563eb`, `--foreground #16233f`, `--muted-foreground #64748b`, `--muted-foreground-strong #475569`, `--border #e4e9f2`, `--muted #eef2f8`, `--background #f6f8fc`, `--destructive #dc2626` / `--destructive-text #991b1b`, `--warning #d97706` / `--warning-text #92400e`, neutro `#8b95a7`. Tipografía: Plus Jakarta Sans; 32/18/15/14/13.5/12.5/11 px. Radios: 12 px tarjetas, 8 px botones, 999 chips. Sombras: `--shadow-card`, `--shadow-pop`.
   124	
   125	## Assets
   126	
   127	Solo la marca existente (`/brand/avance-icon.png`). Iconos lucide ya en el proyecto: `ListChecks`, `UsersRound`, `ChevronRight`, `Wallet`, `Users`, `AlertTriangle`, `Inbox`, `Target`.
```

## `design_handoff_hoy_supervisor/supervisor-mando.tsx (borrador del diseñador)`
```
     1	// Hoy · SUPERVISOR — puesto de mando en UNA pantalla (propuesta 2a, 2026-09-27).
     2	//
     3	// Misma lógica y mismas fuentes que ./supervisor.tsx: los hooks, los agregados
     4	// del RPC y las reglas de la casa (tres cosas, presupuesto de color, «—» sin
     5	// dato, tablist WAI-ARIA) se copian sin cambios. Lo que cambia es el ORDEN y el
     6	// PLIEGUE:
     7	//   1 · Decide primero — las tres cosas como tarjetas grandes con acción; un
     8	//       clic despliega el contexto y FILTRA la cola de abajo.
     9	//   2 · Cola urgente (analista primero, chips por analista) + Equipo hoy (fila
    10	//       desplegable con sus señales y su agenda).
    11	//   3 · Consulta plegada al pie — KPIs, cumplimiento del mes y agenda del
    12	//       equipo, montados con los MISMOS componentes de siempre.
    13	// Convive con HoySupervisor: hoy.tsx decide cuál se pinta (rollback = 1 línea).
    14	// Todo filtro es en cliente sobre las filas ya cargadas; el RPC no cambia.
    15	import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
    16	import { AlertTriangle, ChevronRight, Inbox, ListChecks, Target, Users, UsersRound, Wallet } from 'lucide-react'
    17	import { SlaOperacionBoundary } from '@/components/app/sla-operacion'
    18	import { useModoSla } from '@/data/sla-operacion-queries'
    19	import { Card, CardContent } from '@/components/ui/card'
    20	import { Avatar } from '@/components/ui/avatar'
    21	import { Badge } from '@/components/ui/badge'
    22	import { Button } from '@/components/ui/button'
    23	import { Progress } from '@/components/ui/progress'
    24	import { KpiCard } from '@/components/common/kpi-card'
    25	import { SectionHead } from '@/components/common/section-head'
    26	import { AccionesContacto } from '@/components/app/contacto'
    27	import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
    28	import { DesgloseMonedas } from '@/components/common/desglose-monedas'
    29	import { AgendaEquipoPanel } from './agenda-equipo'
    30	import {
    31	  BUCKET_LABEL, DIA_MS, capitalPrincipal, colorMeta, diasSinActividad, haceCortoTexto, haceTexto,
    32	  indexarUltimaActividad, pctMeta,
    33	} from '@/lib/inteligencia'
    34	import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
    35	import { derivarNovedades, fotoDeVisita, guardarFotoVisita, leerFotoVisita, resumenNovedades, type NovedadesVisita } from '@/lib/visita-sin-movimiento'
    36	import { useSplashVisible } from '@/lib/splash-visible'
    37	import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
    38	import { fechaLima } from '@/lib/agenda-derivada'
    39	import { capitalObjetivo, metaVigente, capitalReal, metaConversionAplicable, objetivosCero, periodoLima } from '@/lib/objetivos'
    40	import { useConversionMensual, useMetricasAgenda } from '@/data/crm-queries'
    41	import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
    42	import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
    43	import { useAhora } from '@/lib/ahora'
    44	import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
    45	import { resumenAgenda } from '@/lib/agenda-equipo-vista'
    46	import { useAuth } from '@/lib/auth-context'
    47	import { useCRMData, usePanelesActions } from '@/lib/store-context'
    48	import { mensajeDeError } from '@/data/crm-api'
    49	import { money, moneyK, numero, porcentajeConversionCanonica, primerNombre } from '@/lib/format'
    50	import { cn } from '@/lib/utils'
    51	import { hashDe } from '@/lib/router'
    52	// `candidatosDeHoy` es el parche de 6 líneas descrito en el README: la misma
    53	// función de siempre SIN el recorte a tres, para poder pintar «Esta semana».
    54	import { candidatosDeHoy, tresCosasDeHoy, type CosaDeHoy } from '@/lib/tres-cosas'
    55	import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
    56	import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
    57	import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
    58	import { textoConversionOperativa } from '@/lib/metricas-vendedores'
    59	import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
    60	import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
    61	import { useTipoCambio } from '@/lib/tipo-cambio'
    62	
    63	const COLA_VISIBLES = 7
    64	type PestanaCola = 'urgente' | 'sin_movimiento' | 'todo'
    65	const PESTANAS_COLA: ReadonlyArray<{ id: PestanaCola; label: string }> = [
    66	  { id: 'urgente', label: 'Urgente' },
    67	  { id: 'sin_movimiento', label: 'Sin movimiento' },
    68	  { id: 'todo', label: 'Todo' },
    69	]
    70	const SIN_META = 'Sin meta fijada para este mes'
    71	// La severidad TAMBIÉN en texto (el color nunca va solo).
    72	const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = { critica: 'Hoy', atencion: 'Esta semana' }
    73	
    74	/** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
    75	function semaforoDias(d: number): string {
    76	  if (d > 5) return SEMAFORO.critico
    77	  if (d >= 2) return SEMAFORO.atencion
    78	  return SEMAFORO.ok
    79	}
    80	
    81	/** «5 nuevos sin responder» → { cifra: '5', resto: 'nuevos sin responder' }. Sin número al inicio, sin cifra. */
    82	function cifraDe(texto: string): { cifra: string | null; resto: string } {
    83	  const m = /^(\d+\+?)\s+(.*)$/.exec(texto)
    84	  return m ? { cifra: m[1] ?? null, resto: m[2] ?? texto } : { cifra: null, resto: texto }
    85	}
    86	
    87	/** Botón de acción de una cosa: enlace a vista o salto de pestaña (mismo destino que la franja actual). */
    88	function AccionDecision({ cosa, onIrAPestana }: { cosa: CosaDeHoy; onIrAPestana: (p: PestanaCola) => void }): JSX.Element {
    89	  const clase = 'inline-flex h-[34px] shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
    90	  const label = `${SEV_TEXTO[cosa.severidad]}: ${cosa.texto} — ${cosa.accion}`
    91	  return cosa.destino.tipo === 'vista' ? (
    92	    <a href={hashDe(cosa.destino.vista)} aria-label={label} className={clase} onClick={(e) => e.stopPropagation()}>
    93	      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
    94	    </a>
    95	  ) : (
    96	    <button
    97	      type="button"
    98	      aria-label={label}
    99	      className={clase}
   100	      onClick={(e) => { e.stopPropagation(); onIrAPestana(cosa.destino.tipo === 'pestana' ? cosa.destino.pestana : 'todo') }}
   101	    >
   102	      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
   103	    </button>
   104	  )
   105	}
   106	
   107	export function HoySupervisorMando(): JSX.Element {
   108	  const modoSla = useModoSla()
   109	  const { ambito, actividades, tareas, objetivos, objetivosError, cumplimientoMetas, cumplimientoMetasError, recargar, equipo } = useCRMData()
   110	  const { abrirLead } = usePanelesActions()
   111	  const { yo } = useAuth()
   112	  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
   113	  const ahora = useAhora()
   114	  const periodoVigente = periodoLima(ahora)
   115	
   116	  // ── Foto mensual vigente (copiado de supervisor.tsx) ──
   117	  const periodoStoreIntentado = useRef<string | null>(null)
   118	  const [recargaPeriodoFallida, setRecargaPeriodoFallida] = useState(false)
   119	  const fotoMensualStoreVigente = yo?.demo === true || (
   120	    objetivos.periodo === periodoVigente && (cumplimientoMetas == null || cumplimientoMetas.periodo === periodoVigente)
   121	  )
   122	  useEffect(() => {
   123	    if (yo?.demo || fotoMensualStoreVigente || periodoStoreIntentado.current === periodoVigente) return
   124	    periodoStoreIntentado.current = periodoVigente
   125	    setRecargaPeriodoFallida(false)
   126	    void recargar().then((ok) => { if (!ok) setRecargaPeriodoFallida(true) })
   127	  }, [fotoMensualStoreVigente, periodoVigente, recargar, yo?.demo])
   128	
   129	  // ── Agregados del servidor (o espejo demo) ──
   130	  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
   131	  const resumen = resumenOp.resumen
   132	  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
   133	  const cola = colaOp.cola
   134	  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividades)
   135	  const rank = vendedoresOp.metricas?.filas ?? null
   136	  const { tc, recargar: recargarTipoCambio } = useTipoCambio()
   137	  const diaTipoCambio = fechaLima(ahora)
   138	  const diaTipoCambioAnterior = useRef(diaTipoCambio)
   139	  useEffect(() => {
   140	    if (diaTipoCambioAnterior.current === diaTipoCambio) return
   141	    diaTipoCambioAnterior.current = diaTipoCambio
   142	    recargarTipoCambio()
   143	  }, [diaTipoCambio, recargarTipoCambio])
   144	  const capitalPronostico = resumen ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd) : null
   145	
   146	  // ── Bandeja de reparto (copiado) ──
   147	  const bandejaReparto = useMemo(() => {
   148	    const parkeados = ambito.leads.filter((l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null)
   149	    return { parkeados, indice: indexarUltimaActividad(actividades) }
   150	  }, [ambito, actividades])
   151	  const esperaMasLargaReparto = useMemo(() => {
   152	    if (!yo?.demo || bandejaReparto.parkeados.length === 0) return null
   153	    let maxima = 0
   154	    for (const lead of bandejaReparto.parkeados) maxima = Math.max(maxima, diasSinActividad(lead, actividades, ahora, bandejaReparto.indice))
   155	    return maxima
   156	  }, [actividades, ahora, bandejaReparto, yo?.demo])
   157	  const totalPorRepartir = resumen?.totales.parkeados ?? null
   158	  const hayPorRepartir = (totalPorRepartir ?? 0) > 0
   159	  const detalleReparto = totalPorRepartir == null
   160	    ? 'Sin dato por ahora · Ver derivaciones →'
   161	    : hayPorRepartir
   162	      ? esperaMasLargaReparto == null ? 'Pendientes en tu bandeja · Repartir →' : `Más rezagado: ${haceCortoTexto(esperaMasLargaReparto)} · Repartir →`
   163	      : 'Bandeja al día · Ver historial →'
   164	
   165	  const nombrePorId = useMemo(() => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])), [equipo])
   166	
   167	  // ── Pestañas y conteos (copiado; los conteos salen del resumen COMPLETO del RPC) ──
   168	  const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)
   169	  const [colaExpandida, setColaExpandida] = useState(false)
   170	  const urgentes = useMemo(() => (cola?.items ?? []).filter((i) => i.sev !== 'baja'), [cola])
   171	  const urgenteTotal = (cola?.porSev.critica ?? 0) + (cola?.porSev.media ?? 0)
   172	  const conteoPestana: Record<PestanaCola, string> = {
   173	    urgente: String(urgenteTotal),
   174	    sin_movimiento: cola && cola.estancados.length >= TOPE_ESTANCADOS ? `${TOPE_ESTANCADOS}+` : String(cola?.estancados.length ?? 0),
   175	    todo: String(cola?.total ?? 0),
   176	  }
   177	  const primeraConFilas: PestanaCola = urgentes.length > 0 ? 'urgente' : (cola?.estancados.length ?? 0) > 0 ? 'sin_movimiento' : 'todo'
   178	  const pestana = pestanaElegida ?? primeraConFilas
   179	
   180	  // ── NUEVO: filtros en cliente sobre las filas cargadas ──
   181	  const [bucketFiltro, setBucketFiltro] = useState<'sin_responder' | null>(null)
   182	  const [analistaFiltro, setAnalistaFiltro] = useState<string | null>(null)
   183	  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
   184	  const [consultaAbierta, setConsultaAbierta] = useState(false)
   185	
   186	  const elegirPestana = (siguiente: PestanaCola) => {
   187	    if (pestana === 'sin_movimiento' && siguiente !== 'sin_movimiento') {
   188	      visitaAnotadaRef.current = null
   189	      setVisitaCongelada(null)
   190	    }
   191	    setBucketFiltro(null)
   192	    setPestanaElegida(siguiente)
   193	  }
   194	  useEffect(() => { setColaExpandida(false) }, [pestana, analistaFiltro, bucketFiltro])
   195	  const elegirAnalista = (id: string | null) => {
   196	    setAnalistaFiltro((actual) => (actual === id ? null : id))
   197	    setBucketFiltro(null)
   198	    setDecisionAbierta(null)
   199	  }
   200	
   201	  // ── F4.3 novedades de «Sin movimiento» (copiado) ──
   202	  const splashVisible = useSplashVisible()
   203	  const [visitaCongelada, setVisitaCongelada] = useState<{ novedades: NovedadesVisita | null; recortada: boolean } | null>(null)
   204	  const visitaAnotadaRef = useRef<string | null>(null)
   205	  useEffect(() => {
   206	    if (pestana !== 'sin_movimiento' || yo?.id == null || cola == null) return
   207	    if (colaOp.enVuelo || splashVisible) return
   208	    if (visitaAnotadaRef.current === yo.id) return
   209	    visitaAnotadaRef.current = yo.id
   210	    const fotoAnterior = leerFotoVisita(yo.id)
   211	    guardarFotoVisita(yo.id, fotoDeVisita(cola.estancados, Date.now()))
   212	    setVisitaCongelada({ novedades: derivarNovedades(cola.estancados, fotoAnterior), recortada: cola.estancados.length >= TOPE_ESTANCADOS })
   213	  }, [pestana, cola, colaOp.enVuelo, splashVisible, yo?.id])
   214	  const novedadesVisita = visitaCongelada?.novedades ?? null
   215	  const resumenVisita = resumenNovedades(novedadesVisita, visitaCongelada?.recortada === true ? TOPE_ESTANCADOS : undefined)
   216	
   217	  const filasBase = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
   218	  const filasCola = filasBase.filter((i) =>
   219	    (bucketFiltro == null || i.bucket === bucketFiltro) && (analistaFiltro == null || i.lead.vendedor_id === analistaFiltro))
   220	  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal
   221	  const hayFiltro = bucketFiltro != null || analistaFiltro != null
   222	  const filasRecortadas = cola != null && cola.items.length < cola.total
   223	  // Conteo por analista sobre las filas CARGADAS (p_limite recorta a 100).
   224	  const enColaPorAnalista = useMemo(() => {
   225	    const m = new Map<string, number>()
   226	    for (const i of cola?.items ?? []) if (i.lead.vendedor_id) m.set(i.lead.vendedor_id, (m.get(i.lead.vendedor_id) ?? 0) + 1)
   227	    return m
   228	  }, [cola])
   229	
   230	  const errorIndicadores = !yo?.demo && Boolean(resumenOp.error || (modoSla.legado && colaOp.error) || vendedoresOp.error)
   231	  const reintentarIndicadores = () => {
   232	    if (resumenOp.error) void resumenOp.recargar()
   233	    if (colaOp.error) void colaOp.recargar()
   234	    if (vendedoresOp.error) void vendedoresOp.recargar()
   235	  }
   236	
   237	  // ── Cumplimiento del mes (copiado íntegro) ──
   238	  const fotoMensualStoreCargando = !yo?.demo && !fotoMensualStoreVigente && !recargaPeriodoFallida
   239	  const objetivosMensualesError = fotoMensualStoreVigente ? objetivosError : recargaPeriodoFallida
   240	  const cumplimientoMensualError = fotoMensualStoreVigente ? cumplimientoMetasError : recargaPeriodoFallida
   241	  const objetivosMensuales = fotoMensualStoreVigente ? objetivos : objetivosCero(periodoVigente)
   242	  const cumplimientoMensual = fotoMensualStoreVigente ? cumplimientoMetas : null
   243	  const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
   244	  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
   245	  const cumplimiento = cumplimientoMensual?.supervisor ?? null
   246	  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
   247	  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
   248	  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
   249	  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
   250	  const esDemoConversion = yo?.demo === true
   251	  const qConversionMensual = useConversionMensual(!esDemoConversion, periodoVigente, 'equipo', yo?.id)
   252	  const conversionMensualCargando = !esDemoConversion && qConversionMensual.isPending && qConversionMensual.data === undefined
   253	  const conversionMensual = esDemoConversion
   254	    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
   255	    : conversionMensualCargando ? undefined : (qConversionMensual.data ?? null)
   256	  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
   257	  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
   258	  const totalConversion = totalConversionPublicable(conversionMensual)
   259	  const conversionConfirmada = totalConversion?.conversion_pct ?? null
   260	  const recibidosEquipo = totalConversion?.divisor ?? null
   261	  const capitalConfirmado = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tc?.promedio)
   262	  const metaCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
   263	  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
   264	  const tcEnVuelo = tc === undefined && hayDolares
   265	  const ajusteCierre = cumplimiento?.ajuste
   266	  const notaAjusteCierre = ajusteCierre != null && (ajusteCierre.aplicadoPen > 0 || ajusteCierre.aplicadoUsd > 0 || ajusteCierre.contratosAplicados > 0)
   267	    ? ['Neto tras ajuste de cierre',
   268	        ajusteCierre.aplicadoPen > 0 ? `−${money(ajusteCierre.aplicadoPen, 'PEN')}` : null,
   269	        ajusteCierre.aplicadoUsd > 0 ? `−${money(ajusteCierre.aplicadoUsd, 'USD')}` : null,
   270	        ajusteCierre.contratosAplicados > 0 ? `−${numero(ajusteCierre.contratosAplicados)} ${ajusteCierre.contratosAplicados === 1 ? 'contrato' : 'contratos'}` : null,
   271	      ].filter(Boolean).join(' · ')
   272	    : null
   273	  const notaCapitalMonedas = !tcEnVuelo && (capitalConfirmadoUsd ?? 0) > 0
   274	    ? `${moneyK(capitalConfirmadoPen ?? 0, 'PEN')} + ${moneyK(capitalConfirmadoUsd ?? 0, 'USD')}`
   275	      + (capitalConfirmado.tc == null ? ' · sin tipo de cambio: el total NO incluye los dólares' : ` · ${rotuloTipoCambio(capitalConfirmado.tc, tc?.fuente ?? 'TC del día')}`)
   276	    : null
   277	  const pctCapital = tcEnVuelo ? 0 : pctMeta(capitalConfirmado.total ?? 0, metaCapital.total ?? 0)
   278	  const pctConversion = pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0)
   279	  const filasMeta: Array<{ label: string; txt: string; pct: number; sinDato: string | null; nota?: string | null }> = [
   280	    {
   281	      label: 'Capital confirmado',
   282	      txt: tcEnVuelo ? 'Calculando…'
   283	        : (metaCapital.total ?? 0) > 0 && capitalConfirmado.total != null
   284	          ? `${moneyK(capitalConfirmado.total, 'PEN')} de ${moneyK(metaCapital.total ?? 0, 'PEN')}`
   285	          : capitalConfirmado.total == null ? '—' : moneyK(capitalConfirmado.total, 'PEN'),
   286	      pct: pctCapital,
   287	      nota: [notaCapitalMonedas, notaAjusteCierre].filter(Boolean).join(' · ') || null,
   288	      sinDato: fotoMensualStoreCargando ? 'Actualizando la meta y el cumplimiento de este mes…'
   289	        : objetivosMensualesError ? 'Meta mensual no disponible'
   290	        : tcEnVuelo ? 'Consultando el tipo de cambio para consolidar los dólares…'
   291	        : (metaCapital.total ?? 0) <= 0 ? SIN_META
   292	        : cumplimientoMensualError || capitalConfirmado.total == null ? 'Cumplimiento confirmado no disponible' : null,
   293	    },
   294	    {
   295	      label: 'Conversión del mes',
   296	      txt: conversionMensualCargando ? 'Calculando…'
   297	        : conversionConfirmada == null ? '—'
   298	        : metaConversion != null
   299	          ? `${porcentajeConversionCanonica(conversionConfirmada)} de ${metaConversion}% · ${numero(recibidosEquipo)} recibidos`
   300	          : `${porcentajeConversionCanonica(conversionConfirmada)} · ${numero(recibidosEquipo)} recibidos`,
   301	      nota: lecturaConversion.aviso,
   302	      pct: pctConversion,
   303	      sinDato: conversionMensualCargando ? 'Consultando la conversión del mes…'
   304	        : conversionMensualError ? 'Conversión del mes no disponible'
   305	        : !lecturaConversion.mostrar ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
   306	        : conversionConfirmada == null ? 'Sin leads recibidos este mes'
   307	        : fotoMensualStoreCargando ? 'Actualizando la meta de este mes…'
   308	        : objetivosMensualesError ? 'Meta mensual no disponible'
   309	        : metaConversion == null ? SIN_META : null,
   310	    },
   311	  ]
   312	
   313	  // ── Agenda del equipo (copiado) ──
   314	  const sesionReal = Boolean(yo && !yo.demo)
   315	  const hastaMA = fechaLima(ahora)
   316	  const desdeMA = fechaLima(ahora - 6 * DIA_MS)
   317	  const consultaAgenda = useMetricasAgenda(sesionReal, desdeMA, hastaMA)
   318	  const datosAgenda = sesionReal ? consultaAgenda.data : metricasAgendaDemo(desdeMA, hastaMA)
   319	  const errorAgenda = sesionReal && consultaAgenda.error
   320	    ? mensajeDeError(consultaAgenda.error, 'No pudimos consultar la agenda del equipo. Revisa tu conexión e inténtalo otra vez.')
   321	    : null
   322	  const cargandoAgenda = sesionReal && (consultaAgenda.isPending || consultaAgenda.isFetching)
   323	  const vendedoresAgenda = datosAgenda?.vendedores ?? []
   324	  const rezagosAgenda = useMemo(() => new Map(vendedoresAgenda.map((v) => [v.vendedor_id, v] as const)), [vendedoresAgenda])
   325	  const resumenAg = datosAgenda ? resumenAgenda(vendedoresAgenda) : null
   326	
   327	  // ── Tres cosas + «Esta semana» (misma función; los candidatos sobrantes van al desplegable) ──
   328	  const entradaCosas = { cola, totalPorRepartir, esperaMasLargaReparto, vendedoresAgenda }
   329	  const cosas = useMemo(() => tresCosasDeHoy(entradaCosas), [cola, totalPorRepartir, esperaMasLargaReparto, vendedoresAgenda])
   330	  const estaSemana = useMemo(() => {
   331	    const ids = new Set(cosas.map((c) => c.id))
   332	    return candidatosDeHoy(entradaCosas).filter((c) => !ids.has(c.id))
   333	  }, [cosas, cola, totalPorRepartir, esperaMasLargaReparto, vendedoresAgenda])
   334	
   335	  // Puente: CosaDeHoy no trae vendedorId; el texto de las cosas de analista
   336	  // empieza por «Nombre: ». Lo limpio es añadir vendedorId al tipo (ver README).
   337	  const duenoDe = (cosa: CosaDeHoy): string | null =>
   338	    vendedoresAgenda.find((v) => cosa.texto.startsWith(`${v.nombre}:`))?.vendedor_id ?? null
   339	
   340	  const irAPestanaCola = (destino: PestanaCola) => {
   341	    elegirPestana(destino)
   342	    requestAnimationFrame(() => { document.getElementById(`tab-cola-${destino}`)?.focus() })
   343	  }
   344	  const alternarDecision = (cosa: CosaDeHoy) => {
   345	    const abrir = decisionAbierta !== cosa.id
   346	    setDecisionAbierta(abrir ? cosa.id : null)
   347	    if (!abrir) { setBucketFiltro(null); setAnalistaFiltro(null); return }
   348	    switch (cosa.id) {
   349	      case 'sin_responder': setAnalistaFiltro(null); setPestanaElegida('urgente'); setBucketFiltro('sin_responder'); break
   350	      case 'sin_movimiento': setAnalistaFiltro(null); setBucketFiltro(null); setPestanaElegida('sin_movimiento'); break
   351	      case 'no_asistio':
   352	      case 'sin_accion': setBucketFiltro(null); setPestanaElegida('todo'); setAnalistaFiltro(duenoDe(cosa)); break
   353	      default: setBucketFiltro(null); setAnalistaFiltro(null)
   354	    }
   355	  }
   356	  /** Una línea de contexto con datos YA cargados; sin dato, nada (no se inventa). */
   357	  const contextoDe = (cosa: CosaDeHoy): string | null => {
   358	    switch (cosa.id) {
   359	      case 'sin_responder': {
   360	        const n = cola?.porBucket.sin_responder ?? 0
   361	        const items = (cola?.items ?? []).filter((i) => i.bucket === 'sin_responder')
   362	        const maxDias = items.reduce((m, i) => Math.max(m, diasSinActividad(i.lead, actividades, ahora, bandejaReparto.indice)), 0)
   363	        return items.length ? `${n} sin primer contacto · el más antiguo ${haceTexto(maxDias)}` : null
   364	      }
   365	      case 'por_repartir': return detalleReparto
   366	      case 'sin_movimiento': { const peor = cola?.estancados[0]; return peor ? `El peor lleva ${haceTexto(peor.dias).replace('hace ', '')} · ${conteoPestana.sin_movimiento} en total` : null }
   367	      case 'no_asistio':
   368	      case 'sin_accion': {
   369	        const v = rezagosAgenda.get(duenoDe(cosa) ?? '')
   370	        return v ? `${v.vencidas} vencidas · ${v.leads_sin_accion} sin próxima acción · ${v.no_asistio} no asistió` : null
   371	      }
   372	      default: return null
   373	    }
   374	  }
   375	
   376	  const analistaSel = analistaFiltro != null ? rank?.find((r) => r.m.perfil_id === analistaFiltro) ?? null : null
   377	  const tituloCola = bucketFiltro === 'sin_responder' ? 'Nuevos sin responder' : analistaSel ? `Cola de ${primerNombre(analistaSel.m.nombre_completo)}` : 'Cola urgente'
   378	  const subCola = cola == null ? '' : hayFiltro ? `· ${numero(filasCola.length)} ${filasCola.length === 1 ? 'lead' : 'leads'}${filasRecortadas ? ' · de las cargadas' : ''}` : `· ${numero(urgenteTotal)} urgentes`
   379	  const enRojo = (rank ?? []).filter((r) => r.activos > 0 && semaforoDias(r.diasSinActividadMax) === SEMAFORO.critico).length
   380	  const enAmbar = (rank ?? []).filter((r) => {
   381	    const rez = rezagosAgenda.get(r.m.perfil_id)
   382	    return r.activos > 0 && (semaforoDias(r.diasSinActividadMax) === SEMAFORO.atencion || (rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)))
   383	  }).length
   384	
   385	  const filaCola = (i: (typeof filasCola)[number]) => {
   386	    const abrir = () => abrirLead(i.lead.id)
   387	    return (
   388	      <div
   389	        key={i.lead.id}
   390	        role="button"
   391	        tabIndex={0}
   392	        data-sev={i.sev}
   393	        onClick={abrir}
   394	        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); abrir() } }}
   395	        aria-label={`Abrir ficha de ${i.lead.nombre_completo}${i.lead.vendedor_nombre ? ` (${i.lead.vendedor_nombre})` : ''}`}
   396	        className="flex w-full cursor-pointer items-center gap-3.5 border-l-[3px] border-t border-t-border/60 py-2 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   397	        style={{ borderLeftColor: i.sev === 'baja' ? 'transparent' : SEV_COLOR[i.sev] }}
   398	      >
   399	        {/* El analista PRIMERO: es la unidad de gestión del supervisor. Con filtro por analista sobra. */}
   400	        {analistaFiltro == null && (
   401	          <span className="flex w-[118px] shrink-0 items-center gap-2">
   402	            <Avatar nombre={i.lead.vendedor_nombre} className="size-[26px] text-[10px]" />
   403	            <span className="truncate text-xs font-semibold text-muted-foreground-strong">
   404	              {i.lead.vendedor_nombre ? primerNombre(i.lead.vendedor_nombre) : 'sin asignar'}
   405	            </span>
   406	          </span>
   407	        )}
   408	        <div className="min-w-0 flex-1 leading-tight">
   409	          <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
   410	          <p className="truncate text-xs text-muted-foreground">{BUCKET_LABEL[i.bucket]} · {i.motivo}</p>
   411	        </div>
   412	        {i.lead.monto_estimado != null && (
   413	          <span className="w-[60px] shrink-0 text-right text-[13px] font-semibold tabular-nums">{moneyK(i.lead.monto_estimado, i.lead.moneda)}</span>
   414	        )}
   415	        <AccionesContacto lead={i.lead} compacto />
   416	        <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   417	      </div>
   418	    )
   419	  }
   420	
   421	  return (
   422	    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
   423	      {/* ── 1 · Decide primero ── */}
   424	      <div className="flex items-center justify-between gap-4">
   425	        <h2 className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
   426	        {estaSemana.length > 0 && (
   427	          <details className="group relative">
   428	            <summary className="inline-flex h-8 cursor-pointer list-none items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 [&::-webkit-details-marker]:hidden">
   429	              <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
   430	              Esta semana · {estaSemana.length}
   431	              <ChevronRight className="size-3.5 rotate-90 transition-transform group-open:-rotate-90" aria-hidden />
   432	            </summary>
   433	            <ul className="ac-pop absolute right-0 top-10 z-20 min-w-[320px] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]">
   434	              {estaSemana.map((c) => (
   435	                <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
   436	                  <span className="size-2 shrink-0 rounded-full" style={{ background: c.severidad === 'critica' ? SEMAFORO.critico : SEMAFORO.atencion }} aria-hidden />
   437	                  <span className="min-w-0 flex-1 truncate">{c.texto}</span>
   438	                  <AccionDecision cosa={c} onIrAPestana={irAPestanaCola} />
   439	                </li>
   440	              ))}
   441	            </ul>
   442	          </details>
   443	        )}
   444	      </div>
   445	
   446	      {cosas.length === 0 ? (
   447	        <Card><CardContent className="py-4 text-sm text-muted-foreground">
   448	          {cola == null ? (colaOp.error ? 'Las decisiones del día no están disponibles en este momento.' : 'Cargando las decisiones del día…') : 'Nada que decidir ahora mismo.'}
   449	        </CardContent></Card>
   450	      ) : (
   451	        <div className="grid gap-3.5 sm:grid-cols-3">
   452	          {cosas.map((cosa) => {
   453	            const abierta = decisionAbierta === cosa.id
   454	            const color = cosa.severidad === 'critica' ? SEMAFORO.critico : SEMAFORO.atencion
   455	            const { cifra, resto } = cifraDe(cosa.texto)
   456	            const contexto = abierta ? contextoDe(cosa) : null
   457	            return (
   458	              <Card key={cosa.id} className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')} style={{ borderLeftColor: color }}>
   459	                <div
   460	                  role="button"
   461	                  tabIndex={0}
   462	                  aria-expanded={abierta}
   463	                  aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}${abierta ? ' — filtrando la cola' : ''}`}
   464	                  onClick={() => alternarDecision(cosa)}
   465	                  onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); alternarDecision(cosa) } }}
   466	                  className="flex cursor-pointer items-center gap-3.5 px-4 py-3 text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   467	                >
   468	                  {cifra && <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>}
   469	                  <span className="min-w-0 flex-1 leading-tight">
   470	                    <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: cosa.severidad === 'critica' ? 'var(--destructive-text)' : 'var(--warning-text)' }}>
   471	                      {SEV_TEXTO[cosa.severidad]}
   472	                    </span>
   473	                    <span className="block truncate text-[15px] font-bold">{resto}</span>
   474	                  </span>
   475	                  <AccionDecision cosa={cosa} onIrAPestana={irAPestanaCola} />
   476	                  <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   477	                </div>
   478	                {abierta && contexto && (
   479	                  <p className="border-t border-border/60 px-4 py-2.5 pl-[70px] text-xs text-muted-foreground-strong">{contexto}</p>
   480	                )}
   481	              </Card>
   482	            )
   483	          })}
   484	        </div>
   485	      )}
   486	
   487	      <AvisoDegradacion activo={errorIndicadores} queReintenta="de los indicadores del equipo" onReintentar={reintentarIndicadores}>
   488	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   489	      </AvisoDegradacion>
   490	
   491	      {/* ── 2 · Cola + Equipo ── */}
   492	      <div className="grid gap-4 lg:grid-cols-5">
   493	        <div className="min-w-0 lg:col-span-3">
   494	          <SlaOperacionBoundary legado={(
   495	            <Card className="flex flex-col overflow-hidden">
   496	              <SectionHead
   497	                icon={ListChecks}
   498	                title={tituloCola}
   499	                right={cola ? (
   500	                  <div role="tablist" aria-label="Filtrar la cola" className="inline-flex rounded-lg bg-muted/60 p-0.5">
   501	                    {PESTANAS_COLA.map((p, indice) => (
   502	                      <button
   503	                        key={p.id}
   504	                        id={`tab-cola-${p.id}`}
   505	                        type="button"
   506	                        role="tab"
   507	                        aria-selected={pestana === p.id}
   508	                        aria-controls="panel-cola"
   509	                        aria-label={`${p.label}: ${conteoPestana[p.id]}`}
   510	                        tabIndex={pestana === p.id ? 0 : -1}
   511	                        onClick={() => elegirPestana(p.id)}
   512	                        onKeyDown={(e) => {
   513	                          const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS_COLA.length
   514	                            : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS_COLA.length) % PESTANAS_COLA.length
   515	                            : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS_COLA.length - 1 : null
   516	                          if (destino == null) return
   517	                          e.preventDefault()
   518	                          const siguiente = PESTANAS_COLA[destino]
   519	                          if (!siguiente) return
   520	                          elegirPestana(siguiente.id)
   521	                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
   522	                        }}
   523	                        className={cn(
   524	                          'min-h-7 cursor-pointer rounded-md px-3 py-1.5 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   525	                          pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
   526	                        )}
   527	                      >
   528	                        {p.label} <span aria-hidden>{conteoPestana[p.id]}</span>
   529	                      </button>
   530	                    ))}
   531	                  </div>
   532	                ) : <span className="text-xs text-muted-foreground">—</span>}
   533	              />
   534	              {subCola && <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground">{subCola}</p>}
   535	
   536	              {/* Chips por analista: filtro en cliente sobre las filas cargadas. */}
   537	              {cola != null && pestana !== 'sin_movimiento' && (
   538	                <div className="flex flex-wrap items-center gap-1.5 px-5 pb-2.5" role="group" aria-label="Filtrar por analista">
   539	                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">Analista</span>
   540	                  <button
   541	                    type="button"
   542	                    aria-pressed={!hayFiltro}
   543	                    onClick={() => { setAnalistaFiltro(null); setBucketFiltro(null); setDecisionAbierta(null) }}
   544	                    className={cn('min-h-7 cursor-pointer rounded-full px-2.5 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   545	                      !hayFiltro ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground')}
   546	                  >
   547	                    Todos · {numero(cola.items.length)}{filasRecortadas ? ` de ${numero(cola.total)}` : ''}
   548	                  </button>
   549	                  {(rank ?? []).filter((r) => (enColaPorAnalista.get(r.m.perfil_id) ?? 0) > 0).map((r) => {
   550	                    const activo = analistaFiltro === r.m.perfil_id
   551	                    return (
   552	                      <button
   553	                        key={r.m.perfil_id}
   554	                        type="button"
   555	                        aria-pressed={activo}
   556	                        aria-label={`${r.m.nombre_completo}: ${enColaPorAnalista.get(r.m.perfil_id)} en cola`}
   557	                        onClick={() => elegirAnalista(r.m.perfil_id)}
   558	                        className={cn('min-h-7 cursor-pointer rounded-full px-2.5 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   559	                          activo ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground')}
   560	                      >
   561	                        {primerNombre(r.m.nombre_completo)} · {enColaPorAnalista.get(r.m.perfil_id)}
   562	                      </button>
   563	                    )
   564	                  })}
   565	                </div>
   566	              )}
   567	
   568	              {cola == null ? (
   569	                <CardContent className="pb-5 pt-0"><p className="text-sm text-muted-foreground">{colaOp.error ? 'La cola del equipo no está disponible en este momento.' : 'Cargando la cola del equipo…'}</p></CardContent>
   570	              ) : pestana === 'sin_movimiento' ? (
   571	                <div id="panel-cola" role="tabpanel" aria-labelledby="tab-cola-sin_movimiento" tabIndex={cola.estancados.length === 0 ? 0 : undefined}>
   572	                  {cola.estancados.length === 0 ? (
   573	                    <CardContent className="pb-5 pt-0"><p className="text-sm text-muted-foreground">Ningún lead del equipo lleva 5 días o más sin actividad.</p></CardContent>
   574	                  ) : (
   575	                    <>
   576	                      {resumenVisita != null && <p className="border-t border-border/60 px-5 py-2 text-[11px] font-semibold text-muted-foreground-strong">{resumenVisita}</p>}
   577	                      <div className="divide-y divide-border/60 border-t border-border/60">
   578	                        {cola.estancados.map((a) => {
   579	                          const esNuevo = novedadesVisita?.nuevos.has(a.leadId) === true
   580	                          const cruzoACritico = novedadesVisita?.agravados.has(a.leadId) === true
   581	                          const vendedor = (a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'
   582	                          return (
   583	                            <button
   584	                              key={a.leadId}
   585	                              type="button"
   586	                              onClick={() => abrirLead(a.leadId)}
   587	                              aria-label={`Abrir ficha de ${a.nombre} (${vendedor}), sin actividad ${haceTexto(a.dias)}${esNuevo ? ', nuevo aquí desde tu última visita' : cruzoACritico ? ', crítico desde tu última visita' : ''}`}
   588	                              className="flex w-full cursor-pointer items-center gap-2.5 border-l-[3px] py-2.5 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   589	                              style={{ borderLeftColor: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
   590	                            >
   591	                              <div className="min-w-0 flex-1 leading-tight">
   592	                                <p className="truncate text-sm font-semibold">{a.nombre} <span className="text-xs font-medium text-muted-foreground">({vendedor})</span></p>
   593	                                <p className="text-[11px] font-medium text-muted-foreground">
   594	                                  Sin actividad {haceTexto(a.dias)}
   595	                                  {cruzoACritico && <span className="text-muted-foreground-strong"> · crítico desde tu última visita</span>}
   596	                                </p>
   597	                              </div>
   598	                              {esNuevo && <Badge color={SEMAFORO.violeta} variant="outline" className="shrink-0 whitespace-nowrap">Nuevo aquí</Badge>}
   599	                              <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   600	                            </button>
   601	                          )
   602	                        })}
   603	                      </div>
   604	                    </>
   605	                  )}
   606	                </div>
   607	              ) : filasCola.length === 0 ? (
   608	                <CardContent id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} tabIndex={0} className="pb-5 pt-0">
   609	                  <p className="text-sm text-muted-foreground">
   610	                    {hayFiltro ? 'Sin filas con este filtro entre las cargadas.' : pestana === 'urgente' ? 'Nada urgente — ninguna fila crítica ni media en la cola.' : 'Sin pendientes — el equipo está al día con todos sus leads abiertos.'}
   611	                  </p>
   612	                </CardContent>
   613	              ) : (
   614	                <div id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`}>
   615	                  {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map(filaCola)}
   616	                  {filasCola.length > COLA_VISIBLES && (
   617	                    <button
   618	                      type="button"
   619	                      onClick={() => setColaExpandida((e) => !e)}
   620	                      aria-expanded={colaExpandida}
   621	                      className="flex w-full cursor-pointer items-center justify-center gap-1 border-t border-border/60 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   622	                    >
   623	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', colaExpandida && 'rotate-90')} aria-hidden />
   624	                      {colaExpandida ? `Mostrar solo los ${COLA_VISIBLES} más urgentes`
   625	                        : !hayFiltro && totalPestanaActiva > filasCola.length ? `Ver los ${filasCola.length} más urgentes de ${totalPestanaActiva}`
   626	                        : `Ver los ${filasCola.length}`}
   627	                    </button>
   628	                  )}
   629	                </div>
   630	              )}
   631	            </Card>
   632	          )}>
   633	            <Card>
   634	              <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
   635	                <div className="space-y-1">
   636	                  <h2 className="text-sm font-bold">Seguimiento del equipo</h2>
   637	                  <p className="text-xs text-muted-foreground">Prioriza las gestiones y revisa los plazos de cada analista.</p>
   638	                </div>
   639	                <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   640	                  Abrir seguimiento <ChevronRight className="size-4" aria-hidden />
   641	                </a>
   642	              </CardContent>
   643	            </Card>
   644	          </SlaOperacionBoundary>
   645	        </div>
   646	
   647	        {/* ── Equipo hoy: una fila por analista; clic = filtrar la cola y desplegar sus señales ── */}
   648	        <Card className="min-w-0 overflow-hidden lg:col-span-2">
   649	          <SectionHead
   650	            icon={UsersRound}
   651	            title="Equipo hoy"
   652	            right={<a href={hashDe('equipo')} className="text-xs font-bold text-accent hover:underline">Gestión de equipo →</a>}
   653	          />
   654	          {rank != null && rank.length > 0 && (
   655	            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground">· {enRojo} en rojo · {enAmbar} en ámbar</p>
   656	          )}
   657	          {rank == null ? (
   658	            <CardContent className="pb-5 pt-0"><p className="text-sm text-muted-foreground">{vendedoresOp.error ? 'El resumen por analista no está disponible en este momento.' : 'Cargando el resumen por analista…'}</p></CardContent>
   659	          ) : rank.length === 0 ? (
   660	            <CardContent className="pb-5 pt-0"><p className="text-sm text-muted-foreground">Sin analistas a cargo.</p></CardContent>
   661	          ) : (
   662	            <div className="divide-y divide-border/60 border-t border-border/60">
   663	              {rank.map((r) => {
   664	                const c = semaforoDias(r.diasSinActividadMax)
   665	                const rez = rezagosAgenda.get(r.m.perfil_id)
   666	                const conRezagoAgenda = rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)
   667	                const haySenal = r.activos === 0 || c !== SEMAFORO.ok || conRezagoAgenda
   668	                const colorPunto = r.activos === 0 ? SEMAFORO.neutro : c !== SEMAFORO.ok ? c : SEMAFORO.atencion
   669	                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   670	                const seleccionado = analistaFiltro === r.m.perfil_id
   671	                const enCola = enColaPorAnalista.get(r.m.perfil_id) ?? 0
   672	                const estado = r.activos === 0 ? 'Sin leads abiertos'
   673	                  : `Última actividad ${haceTexto(r.diasSinActividadMax)}${rez != null && rez.vencidas > 0 ? ` · ${rez.vencidas} ${rez.vencidas === 1 ? 'vencida' : 'vencidas'}` : ''}${rez != null && rez.leads_sin_accion > 0 ? ` · ${rez.leads_sin_accion} sin acción` : ''}`
   674	                // Chips de señal para la fila desplegada (color + texto, umbrales de la casa).
   675	                const senales: Array<{ texto: string; color: string }> = []
   676	                if (r.activos > 0) {
   677	                  if (rez != null && rez.no_asistio >= 2) senales.push({ texto: `${rez.no_asistio} citas sin asistir`, color: SEMAFORO.critico })
   678	                  if (rez != null && rez.leads_sin_accion >= 3) senales.push({ texto: `${rez.leads_sin_accion} leads sin próxima acción`, color: rez.leads_sin_accion >= 5 ? SEMAFORO.critico : SEMAFORO.atencion })
   679	                  if (r.diasSinActividadMax >= 2) senales.push({ texto: `${r.diasSinActividadMax} días sin actividad`, color: c })
   680	                  if (rez != null && rez.vencidas > 0) senales.push({ texto: `${rez.vencidas} ${rez.vencidas === 1 ? 'tarea vencida' : 'tareas vencidas'}`, color: SEMAFORO.atencion })
   681	                  if (r.sinTocar > 0) senales.push({ texto: `${r.sinTocar} sin tocar`, color: SEMAFORO.atencion })
   682	                }
   683	                return (
   684	                  <div
   685	                    key={r.m.perfil_id}
   686	                    role="button"
   687	                    tabIndex={0}
   688	                    aria-pressed={seleccionado}
   689	                    aria-label={`${r.m.nombre_completo}: ${estado}${seleccionado ? ' — filtrando la cola' : ''}`}
   690	                    onClick={() => elegirAnalista(r.m.perfil_id)}
   691	                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); elegirAnalista(r.m.perfil_id) } }}
   692	                    className={cn('relative cursor-pointer px-5 py-2 transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40', seleccionado && 'bg-accent/[0.08]')}
   693	                  >
   694	                    <div className="flex items-center gap-2.5">
   695	                      {haySenal ? <span data-testid="equipo-semaforo" className="size-2 shrink-0 rounded-full" style={{ background: colorPunto }} aria-hidden /> : <span className="size-2 shrink-0" aria-hidden />}
   696	                      <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" />
   697	                      <div className="min-w-0 flex-1 leading-tight">
   698	                        <p className="truncate text-[13.5px] font-bold">{r.m.nombre_completo}</p>
   699	                        <p className="truncate text-[11.5px] tabular-nums text-muted-foreground">
   700	                          {estado} · {r.activos} activos · {r.conversion == null
   701	                            ? (r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible')
   702	                            : `${textoConversionOperativa(r.conversion)} conversión`}
   703	                        </p>
   704	                      </div>
   705	                      <div className="shrink-0 text-right leading-tight">
   706	                        <p className="text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</p>
   707	                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
   708	                        <p className="text-[10.5px] tabular-nums text-muted-foreground">{enCola} en cola</p>
   709	                      </div>
   710	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', seleccionado ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   711	                    </div>
   712	                    {seleccionado && (
   713	                      <div className="mt-2 flex flex-wrap items-center gap-1.5 pl-[50px]">
   714	                        {senales.length === 0 ? (
   715	                          <Badge color={SEMAFORO.neutro}>{r.activos === 0 ? 'Sin cartera asignada' : 'Al día'}</Badge>
   716	                        ) : senales.map((s) => (
   717	                          <Badge key={s.texto} color={s.color} variant={s.color === SEMAFORO.critico ? 'solid' : 'soft'}>{s.texto}</Badge>
   718	                        ))}
   719	                        {rez != null && (
   720	                          <span className="ml-auto text-[11.5px] tabular-nums text-muted-foreground">
   721	                            {rez.toques > 0 ? `${rez.toques} toques${rez.pct_completadas != null ? ` · ${Math.round(rez.pct_completadas)} % cierres` : ''}` : 'sin actividad en 7 d'}
   722	                          </span>
   723	                        )}
   724	                      </div>
   725	                    )}
   726	                  </div>
   727	                )
   728	              })}
   729	            </div>
   730	          )}
   731	        </Card>
   732	      </div>
   733	
   734	      {/* ── 3 · Consulta plegada: la barra siempre, el panel encima cuando se pide ── */}
   735	      <div className="relative">
   736	        {consultaAbierta && (
   737	          <div
   738	            role="region"
   739	            aria-label="Detalle de consulta"
   740	            onKeyDown={(e) => { if (e.key === 'Escape') setConsultaAbierta(false) }}
   741	            className="ac-pop ac-scroll absolute inset-x-0 bottom-14 z-20 max-h-[70vh] space-y-4 overflow-auto rounded-xl border border-border bg-card p-4 shadow-[var(--shadow-pop)]"
   742	          >
   743	            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   744	              <KpiCard label="Pronóstico de capital abierto" value={capitalPronostico ? capitalPronostico.valor : '—'} icon={Wallet} color={SEMAFORO.neutro}
   745	                sub={capitalPronostico?.otra ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte` : capitalPronostico?.soloDolares ? 'Pipeline (USD)'
   746	                  : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0 ? 'Sin montos estimados — complétalos en cada ficha' : 'Pipeline (PEN) · abiertos con analista'} />
   747	              <KpiCard label="Leads activos del equipo" value={resumen ? String(resumen.totales.asignados) : '—'} icon={Users} color={SEMAFORO.neutro}
   748	                sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`} delay={60} />
   749	              <KpiCard label="Nuevos sin responder" value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'} icon={AlertTriangle} color={SEMAFORO.neutro}
   750	                sub={cola == null ? 'Sin dato por ahora' : (cola.porBucket.sin_responder ?? 0) > 0 ? 'Sin primer contacto' : 'Todos los nuevos fueron contactados'} delay={120} />
   751	              <a href={hashDe('derivaciones')} className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background">
   752	                <KpiCard label="Por repartir" value={totalPorRepartir == null ? '—' : String(totalPorRepartir)} icon={Inbox} color={SEMAFORO.neutro} sub={detalleReparto} delay={180} />
   753	              </a>
   754	            </div>
   755	            <div className="grid gap-4 lg:grid-cols-5">
   756	              <Card className="lg:col-span-2">
   757	                <SectionHead icon={Target} title="Cumplimiento del mes" right={tc ? <span className="text-xs text-muted-foreground">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined} />
   758	                <CardContent className="space-y-3 pb-5 pt-0">
   759	                  {filasMeta.map((f) => (
   760	                    <div key={f.label}>
   761	                      <div className="mb-1 flex items-center justify-between gap-2">
   762	                        <span className="text-xs font-semibold">{f.label}</span>
   763	                        <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   764	                      </div>
   765	                      {f.nota && <p className="mb-1 text-[10.5px] tabular-nums text-muted-foreground">{f.nota}</p>}
   766	                      {f.sinDato ? <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p> : <Progress value={f.pct} color={colorMeta(f.pct)} />}
   767	                    </div>
   768	                  ))}
   769	                </CardContent>
   770	              </Card>
   771	              <div className="lg:col-span-3">
   772	                <AgendaEquipoPanel datos={datosAgenda} cargando={cargandoAgenda} error={errorAgenda} modoDemo={yo?.demo === true} onReintentar={() => { if (sesionReal) void consultaAgenda.refetch() }} equipo={equipo} />
   773	              </div>
   774	            </div>
   775	          </div>
   776	        )}
   777	        <div className="flex h-12 items-center gap-5 rounded-xl border border-border bg-card px-5 text-xs tabular-nums text-muted-foreground-strong">
   778	          <span className="text-[10.5px] font-bold uppercase tracking-[0.1em] text-muted-foreground">Consulta</span>
   779	          <span><strong className="font-extrabold text-primary">{capitalPronostico ? capitalPronostico.valor : '—'}</strong> pipeline</span>
   780	          <span><strong className="font-extrabold text-primary">{resumen ? numero(resumen.totales.asignados) : '—'}</strong> activos</span>
   781	          <span><strong className="font-extrabold text-primary">{filasMeta[0]?.sinDato ? '—' : `${Math.round(pctCapital)} %`}</strong> meta</span>
   782	          <span><strong className="font-extrabold text-primary">{conversionConfirmada == null ? '—' : porcentajeConversionCanonica(conversionConfirmada)}</strong> conversión</span>
   783	          <span className="h-[18px] w-px bg-border" aria-hidden />
   784	          <span><strong className="font-extrabold text-primary">{resumenAg ? numero(resumenAg.toques) : '—'}</strong> toques</span>
   785	          <span><strong className="font-extrabold text-primary">{resumenAg?.pctCompletadas != null ? `${resumenAg.pctCompletadas} %` : '—'}</strong> completadas</span>
   786	          <span><strong className="font-extrabold" style={{ color: resumenAg && resumenAg.noAsistio >= 2 ? SEMAFORO.critico : 'var(--primary)' }}>{resumenAg ? numero(resumenAg.noAsistio) : '—'}</strong> no asistió</span>
   787	          <Button type="button" variant="outline" size="sm" className="ml-auto h-8 text-accent" aria-expanded={consultaAbierta} onClick={() => setConsultaAbierta((v) => !v)}>
   788	            {consultaAbierta ? 'Cerrar' : 'Detalle'}
   789	          </Button>
   790	        </div>
   791	      </div>
   792	    </div>
   793	  )
   794	}
```

## `app/src/screens/hoy/supervisor.tsx (pantalla ACTUAL en producción)`
```
     1	import { SlaOperacionBoundary } from '@/components/app/sla-operacion'
     2	import { useModoSla } from '@/data/sla-operacion-queries'
     3	// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
     4	// ya trae: sus leads + los de sus analistas + parkeados de SU bandeja.
     5	// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
     6	// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
     7	import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
     8	import {
     9	  AlertTriangle,
    10	  ChevronRight,
    11	  Inbox,
    12	  ListChecks,
    13	  Target,
    14	  Users,
    15	  UsersRound,
    16	  Wallet,
    17	} from 'lucide-react'
    18	import { Card, CardContent } from '@/components/ui/card'
    19	import { Avatar } from '@/components/ui/avatar'
    20	import { Badge } from '@/components/ui/badge'
    21	import { Button } from '@/components/ui/button'
    22	import { Progress } from '@/components/ui/progress'
    23	import { KpiCard } from '@/components/common/kpi-card'
    24	import { SectionHead } from '@/components/common/section-head'
    25	import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
    26	import { AccionesContacto } from '@/components/app/contacto'
    27	import { AgendaEquipoPanel } from './agenda-equipo'
    28	import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
    29	import { TresCosas } from './tres-cosas'
    30	import {
    31	  BUCKET_LABEL,
    32	  DIA_MS,
    33	  capitalPrincipal,
    34	  colorMeta,
    35	  diasSinActividad,
    36	  haceCortoTexto,
    37	  haceTexto,
    38	  indexarUltimaActividad,
    39	  pctMeta,
    40	} from '@/lib/inteligencia'
    41	import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
    42	import {
    43	  derivarNovedades,
    44	  fotoDeVisita,
    45	  guardarFotoVisita,
    46	  leerFotoVisita,
    47	  resumenNovedades,
    48	  type NovedadesVisita,
    49	} from '@/lib/visita-sin-movimiento'
    50	import { useSplashVisible } from '@/lib/splash-visible'
    51	import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
    52	import { fechaLima } from '@/lib/agenda-derivada'
    53	import {
    54	  capitalObjetivo,
    55	  metaVigente,
    56	  capitalReal,
    57	  metaConversionAplicable,
    58	  objetivosCero,
    59	  periodoLima,
    60	} from '@/lib/objetivos'
    61	import { useConversionMensual } from '@/data/crm-queries'
    62	import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
    63	import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
    64	import { useAhora } from '@/lib/ahora'
    65	import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
    66	import { useAuth } from '@/lib/auth-context'
    67	import { useCRMData, usePanelesActions } from '@/lib/store-context'
    68	import { mensajeDeError } from '@/data/crm-api'
    69	import { useMetricasAgenda } from '@/data/crm-queries'
    70	import { money, moneyK, numero, porcentajeConversionCanonica } from '@/lib/format'
    71	import { cn } from '@/lib/utils'
    72	import { hashDe } from '@/lib/router'
    73	import { tresCosasDeHoy } from '@/lib/tres-cosas'
    74	import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
    75	import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
    76	import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
    77	import { textoConversionOperativa } from '@/lib/metricas-vendedores'
    78	import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
    79	import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
    80	import { DesgloseMonedas } from '@/components/common/desglose-monedas'
    81	import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
    82	import { useTipoCambio } from '@/lib/tipo-cambio'
    83	
    84	// Tope de la cola del equipo: los primeros son la plata (colaDe ya ordena por
    85	// severidad); el resto vive tras "Ver los N pendientes" para que la Agenda del
    86	// equipo (montada debajo) no quede varios pantallazos abajo.
    87	const COLA_VISIBLES = 8
    88	
    89	// Pestañas de la cola (2026-08-23, «una cosa se avisa en un solo lugar»):
    90	// «Leads sin movimiento» era una tercera tarjeta sobre los MISMOS leads
    91	// abiertos que la cola, así que un lead con 6 días salía dos veces en el mismo
    92	// pantallazo. Ahora es una pestaña de la misma tarjeta: mismo conteo, mismo
    93	// tope del RPC, un solo lugar. Urgente = severidad crítica y media.
    94	type PestanaCola = 'urgente' | 'sin_movimiento' | 'todo'
    95	const PESTANAS_COLA: ReadonlyArray<{ id: PestanaCola; label: string }> = [
    96	  { id: 'urgente', label: 'Urgente' },
    97	  { id: 'sin_movimiento', label: 'Sin movimiento' },
    98	  { id: 'todo', label: 'Todo' },
    99	]
   100	
   101	// Texto neutro de una meta que gerencia todavía no fijó para el mes.
   102	const SIN_META = 'Sin meta fijada para este mes'
   103	
   104	/** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
   105	function semaforoDias(d: number): string {
   106	  if (d > 5) return SEMAFORO.critico
   107	  if (d >= 2) return SEMAFORO.atencion
   108	  return SEMAFORO.ok
   109	}
   110	
   111	export function HoySupervisor(): JSX.Element {
   112	  const modoSla = useModoSla()
   113	  const {
   114	    ambito,
   115	    actividades,
   116	    tareas,
   117	    objetivos,
   118	    objetivosError,
   119	    cumplimientoMetas,
   120	    cumplimientoMetasError,
   121	    recargar,
   122	    equipo,
   123	  } = useCRMData()
   124	  const { abrirLead } = usePanelesActions()
   125	  const { yo } = useAuth()
   126	  // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola — en sesión real
   127	  // esos vencimientos ya llegan resueltos dentro de cola_accion_fn, así que el
   128	  // RPC de estado SLA ni se pide (habilitado = demo).
   129	  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
   130	  // Reloj vivo: tick por minuto y al volver a la pestaña — la bandeja y los
   131	  // "hace N" se refrescan solos al pasar el tiempo.
   132	  const ahora = useAhora()
   133	  const periodoVigente = periodoLima(ahora)
   134	  const periodoStoreIntentado = useRef<string | null>(null)
   135	  const [recargaPeriodoFallida, setRecargaPeriodoFallida] = useState(false)
   136	  const fotoMensualStoreVigente = yo?.demo === true || (
   137	    objetivos.periodo === periodoVigente
   138	    && (cumplimientoMetas == null || cumplimientoMetas.periodo === periodoVigente)
   139	  )
   140	  useEffect(() => {
   141	    if (yo?.demo || fotoMensualStoreVigente
   142	      || periodoStoreIntentado.current === periodoVigente) return
   143	    periodoStoreIntentado.current = periodoVigente
   144	    setRecargaPeriodoFallida(false)
   145	    void recargar().then((ok) => {
   146	      if (!ok) setRecargaPeriodoFallida(true)
   147	    })
   148	  }, [fotoMensualStoreVigente, periodoVigente, recargar, yo?.demo])
   149	  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
   150	  const [colaExpandida, setColaExpandida] = useState(false)
   151	  // Pestaña elegida a mano; `null` = automática (la primera con filas), así
   152	  // un supervisor que entra por la mañana aterriza donde hay trabajo.
   153	  const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)
   154	
   155	  // ── F1b: los agregados llegan del servidor (o del espejo demo vivo) ──
   156	  // resumen_cartera_fn → tiles de capital/activos/parkeados; cola_accion_fn →
   157	  // cola + estancados + tile "sin responder"; metricas_vendedores_fn → ranking.
   158	  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
   159	  const resumen = resumenOp.resumen
   160	  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
   161	  const cola = colaOp.cola
   162	  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividades)
   163	  const rank = vendedoresOp.metricas?.filas ?? null
   164	  // TC izado UNA vez por pantalla: el hook no pasa por TanStack (sin cache ni
   165	  // dedupe), así que uno por fila multiplicaría las llamadas a la edge.
   166	  const { tc, recargar: recargarTipoCambio } = useTipoCambio()
   167	  const diaTipoCambio = fechaLima(ahora)
   168	  const diaTipoCambioAnterior = useRef(diaTipoCambio)
   169	  useEffect(() => {
   170	    if (diaTipoCambioAnterior.current === diaTipoCambio) return
   171	    diaTipoCambioAnterior.current = diaTipoCambio
   172	    recargarTipoCambio()
   173	  }, [diaTipoCambio, recargarTipoCambio])
   174	  // Pronóstico: `capitalPrincipal` (criterio compartido con Cartera/Pipeline),
   175	  // NUNCA un total mixto. Antes se fijaba PEN a mano y un equipo que vende en
   176	  // dólares se titulaba «S/ 0».
   177	  const capitalPronostico = resumen
   178	    ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd)
   179	    : null
   180	  // HOY solo resume la bandeja; la operación completa vive en Derivar leads.
   181	  // Conservamos el índice local para resumir la espera observable del caso más
   182	  // rezagado sin añadir otra consulta; si no hubo actividad, parte del ingreso.
   183	  // Fase 3 «sin topes»: en sesión real el arranque ya no baja el registro de
   184	  // actividades, y sin él la «espera» de un parkeado caería a `creado_en`
   185	  // (un lead de 30 días parkeado hace una hora diría «30 días»; su
   186	  // `tenencia_desde` se anula al quedar sin analista). Antes que exagerar, en
   187	  // sesión real se omite la antigüedad: el conteo del RPC sigue siendo la
   188	  // verdad y el CTA lo dice sin cifra. En demo sigue el timeline del fixture.
   189	  const bandejaReparto = useMemo(() => {
   190	    const parkeados = ambito.leads.filter(
   191	      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null,
   192	    )
   193	    const indice = indexarUltimaActividad(actividades)
   194	    return { parkeados, indice }
   195	  }, [ambito, actividades])
   196	
   197	  const esperaMasLargaReparto = useMemo(() => {
   198	    if (!yo?.demo) return null
   199	    if (bandejaReparto.parkeados.length === 0) return null
   200	    let maxima = 0
   201	    for (const lead of bandejaReparto.parkeados) {
   202	      maxima = Math.max(
   203	        maxima,
   204	        diasSinActividad(lead, actividades, ahora, bandejaReparto.indice),
   205	      )
   206	    }
   207	    return maxima
   208	  }, [actividades, ahora, bandejaReparto, yo?.demo])
   209	
   210	  // El conteo del RPC sigue siendo la autoridad. Si el detalle local aún no
   211	  // está disponible, el CTA conserva la verdad y omite la antigüedad.
   212	  const totalPorRepartir = resumen?.totales.parkeados ?? null
   213	  const hayPorRepartir = (totalPorRepartir ?? 0) > 0
   214	  const detalleReparto = totalPorRepartir == null
   215	    ? 'Sin dato por ahora · Ver derivaciones →'
   216	    : hayPorRepartir
   217	      ? esperaMasLargaReparto == null
   218	        ? 'Pendientes en tu bandeja · Repartir →'
   219	        : `Más rezagado: ${haceCortoTexto(esperaMasLargaReparto)} · Repartir →`
   220	      : 'Bandeja al día · Ver historial →'
   221	  const etiquetaAccesoReparto = totalPorRepartir == null
   222	    ? 'Ver derivaciones; total por repartir no disponible'
   223	    : hayPorRepartir
   224	      ? `Repartir ${totalPorRepartir} ${totalPorRepartir === 1 ? 'lead pendiente' : 'leads pendientes'}`
   225	      : 'Ver derivaciones; bandeja sin pendientes'
   226	
   227	  // Nombres para los estancados del payload (el servidor no manda nombres de
   228	  // personas): join con el roster completo, una sola vez por render.
   229	  const nombrePorId = useMemo(
   230	    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
   231	    [equipo],
   232	  )
   233	
   234	  // Filas y conteos por pestaña. «Todo» cuenta el universo del RPC (`total`),
   235	  // no las filas recortadas por p_limite; «Urgente» solo puede contar lo que
   236	  // llegó. Con estancados al tope, el conteo dice «50+» y no miente.
   237	  const urgentes = useMemo(
   238	    () => (cola?.items ?? []).filter((i) => i.sev !== 'baja'),
   239	    [cola],
   240	  )
   241	  // El conteo de «Urgente» sale de porSev (el resumen COMPLETO del RPC), no de
   242	  // las filas: p_limite recorta items a 100 y con 120 urgentes la pestaña
   243	  // habría dicho 100 mientras «Todo» decía 120 (hallazgo de Codex).
   244	  const urgenteTotal = (cola?.porSev.critica ?? 0) + (cola?.porSev.media ?? 0)
   245	  const conteoPestana: Record<PestanaCola, string> = {
   246	    urgente: String(urgenteTotal),
   247	    sin_movimiento: cola && cola.estancados.length >= TOPE_ESTANCADOS
   248	      ? `${TOPE_ESTANCADOS}+`
   249	      : String(cola?.estancados.length ?? 0),
   250	    todo: String(cola?.total ?? 0),
   251	  }
   252	  const primeraConFilas: PestanaCola = urgentes.length > 0
   253	    ? 'urgente'
   254	    : (cola?.estancados.length ?? 0) > 0
   255	      ? 'sin_movimiento'
   256	      : 'todo'
   257	  const pestana = pestanaElegida ?? primeraConFilas
   258	  const elegirPestana = (siguiente: PestanaCola) => {
   259	    // F4.3: la visita la cierra el USUARIO al irse de la pestaña. Un vaivén
   260	    // automático de `primeraConFilas` (refetch caído que salta a «Todo» y
   261	    // vuelve al recuperarse) no borra las marcas ni fabrica otra visita.
   262	    if (pestana === 'sin_movimiento' && siguiente !== 'sin_movimiento') {
   263	      visitaAnotadaRef.current = null
   264	      setVisitaCongelada(null)
   265	    }
   266	    setPestanaElegida(siguiente)
   267	  }
   268	  // El colapso se reinicia con CUALQUIER cambio de pestaña — también el
   269	  // automático: la cola se refresca cada minuto y sin esto una pestaña recién
   270	  // aparecida heredaba la expansión de la anterior (hasta 100 filas de golpe).
   271	  useEffect(() => {
   272	    setColaExpandida(false)
   273	  }, [pestana])
   274	  // F4.3: qué EMPEORÓ en «Sin movimiento» desde la última visita. TODO se
   275	  // CONGELA en el instante de anotar: la foto anterior Y las marcas derivadas
   276	  // — una marca que aparece «bajo el cursor» porque la cola se refrescó
   277	  // debajo sería ruido, no memoria (la severidad de la tira sí sigue viva).
   278	  // La visita queda anotada en localStorage en ese mismo instante — anotar
   279	  // «al salir» exigiría un unload handler, y perder una anotación solo marca
   280	  // DE MÁS la próxima vez, la dirección segura. La anotación ESPERA a que el
   281	  // payload esté fresco (enVuelo: persistir una cola vieja podría CALLAR una
   282	  // novedad futura) y a que el workspace sea visible (splash: una «visita»
   283	  // que nadie vio también calla). El ref la hace idempotente (StrictMode
   284	  // ejecuta el efecto dos veces) y fiel a la identidad: si `yo` cambiara en
   285	  // caliente se anota de nuevo para el id nuevo.
   286	  const splashVisible = useSplashVisible()
   287	  const [visitaCongelada, setVisitaCongelada] = useState<{
   288	    novedades: NovedadesVisita | null
   289	    recortada: boolean
   290	  } | null>(null)
   291	  const visitaAnotadaRef = useRef<string | null>(null)
   292	  useEffect(() => {
   293	    if (pestana !== 'sin_movimiento' || yo?.id == null || cola == null) return
   294	    if (colaOp.enVuelo || splashVisible) return
   295	    if (visitaAnotadaRef.current === yo.id) return
   296	    visitaAnotadaRef.current = yo.id
   297	    const fotoAnterior = leerFotoVisita(yo.id)
   298	    guardarFotoVisita(yo.id, fotoDeVisita(cola.estancados, Date.now()))
   299	    setVisitaCongelada({
   300	      novedades: derivarNovedades(cola.estancados, fotoAnterior),
   301	      recortada: cola.estancados.length >= TOPE_ESTANCADOS,
   302	    })
   303	  }, [pestana, cola, colaOp.enVuelo, splashVisible, yo?.id])
   304	  const novedadesVisita = visitaCongelada?.novedades ?? null
   305	  const resumenVisita = resumenNovedades(
   306	    novedadesVisita,
   307	    visitaCongelada?.recortada === true ? TOPE_ESTANCADOS : undefined,
   308	  )
   309	  const filasCola = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
   310	  // Total real de la pestaña activa, para que el botón de expandir no prometa
   311	  // menos de lo que existe cuando el RPC recortó las filas.
   312	  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal
   313	
   314	  const errorIndicadores = !yo?.demo
   315	    && Boolean(resumenOp.error || (modoSla.legado && colaOp.error) || vendedoresOp.error)
   316	  const reintentarIndicadores = () => {
   317	    if (resumenOp.error) void resumenOp.recargar()
   318	    if (colaOp.error) void colaOp.recargar()
   319	    if (vendedoresOp.error) void vendedoresOp.recargar()
   320	  }
   321	
   322	  // La meta sale del snapshot cuando lo hay: si un analista se fue o cambió
   323	  // de equipo, su meta y su producción viajan juntas (ver `metaVigente`).
   324	  const fotoMensualStoreCargando = !yo?.demo
   325	    && !fotoMensualStoreVigente
   326	    && !recargaPeriodoFallida
   327	  const objetivosMensualesError = fotoMensualStoreVigente
   328	    ? objetivosError
   329	    : recargaPeriodoFallida
   330	  const cumplimientoMensualError = fotoMensualStoreVigente
   331	    ? cumplimientoMetasError
   332	    : recargaPeriodoFallida
   333	  const objetivosMensuales = fotoMensualStoreVigente
   334	    ? objetivos
   335	    : objetivosCero(periodoVigente)
   336	  const cumplimientoMensual = fotoMensualStoreVigente ? cumplimientoMetas : null
   337	  const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
   338	  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
   339	  const cumplimiento = cumplimientoMensual?.supervisor ?? null
   340	  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
   341	  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
   342	  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
   343	  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
   344	
   345	  // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
   346	  // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
   347	  // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
   348	  // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
   349	  const esDemoConversion = yo?.demo === true
   350	  const qConversionMensual = useConversionMensual(
   351	    !esDemoConversion,
   352	    periodoVigente,
   353	    'equipo',
   354	    yo?.id,
   355	  )
   356	  const conversionMensualCargando = !esDemoConversion
   357	    && qConversionMensual.isPending
   358	    && qConversionMensual.data === undefined
   359	  const conversionMensual = esDemoConversion
   360	    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
   361	    : conversionMensualCargando
   362	      ? undefined
   363	      : (qConversionMensual.data ?? null)
   364	  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
   365	  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
   366	  // 2026-08-14). La regla vive en `lecturaCobertura`, compartida con las otras
   367	  // tres pantallas que pintan esta misma cifra.
   368	  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
   369	  const totalConversion = totalConversionPublicable(conversionMensual)
   370	  const conversionConfirmada = totalConversion?.conversion_pct ?? null
   371	  const recibidosEquipo = totalConversion?.divisor ?? null
   372	  // ── Cumplimiento del mes ──────────────────────────────────────────────────
   373	  // PEN y USD ya NO van por separado: la meta se pacta en soles (el editor
   374	  // escribe todo en `nuevo/PEN`), así que la fila de dólares vivía en «Sin meta
   375	  // fijada» para siempre mientras el capital real en USD no movía ninguna
   376	  // barra. Se consolida con el MISMO tipo de cambio en numerador y denominador
   377	  // —comparar a tasas distintas es comparar peras con manzanas— igual que en el
   378	  // panel del analista y en el de gerencia.
   379	  const capitalConfirmado = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tc?.promedio)
   380	  const metaCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
   381	  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
   382	  const tcEnVuelo = tc === undefined && hayDolares
   383	  const tcCaido = tc === null && hayDolares
   384	  const ajusteCierre = cumplimiento?.ajuste
   385	  const notaAjusteCierre = ajusteCierre != null && (
   386	    ajusteCierre.aplicadoPen > 0
   387	    || ajusteCierre.aplicadoUsd > 0
   388	    || ajusteCierre.contratosAplicados > 0
   389	  )
   390	    ? [
   391	        'Neto tras ajuste de cierre',
   392	        ajusteCierre.aplicadoPen > 0 ? `−${money(ajusteCierre.aplicadoPen, 'PEN')}` : null,
   393	        ajusteCierre.aplicadoUsd > 0 ? `−${money(ajusteCierre.aplicadoUsd, 'USD')}` : null,
   394	        ajusteCierre.contratosAplicados > 0
   395	          ? `−${numero(ajusteCierre.contratosAplicados)} ${ajusteCierre.contratosAplicados === 1 ? 'contrato' : 'contratos'}`
   396	          : null,
   397	      ].filter(Boolean).join(' · ')
   398	    : null
   399	  const notaCapitalMonedas = !tcEnVuelo && (capitalConfirmadoUsd ?? 0) > 0
   400	    ? `${moneyK(capitalConfirmadoPen ?? 0, 'PEN')} + ${moneyK(capitalConfirmadoUsd ?? 0, 'USD')}`
   401	      + (capitalConfirmado.tc == null
   402	        ? ' · sin tipo de cambio: el total NO incluye los dólares'
   403	        : ` · ${rotuloTipoCambio(capitalConfirmado.tc, tc?.fuente ?? 'TC del día')}`)
   404	    : null
   405	  const filasMeta: Array<{
   406	    label: string
   407	    txt: string
   408	    pct: number
   409	    sinDato: string | null
   410	    nota?: string | null
   411	  }> = [
   412	    {
   413	      label: 'Capital confirmado',
   414	      txt:
   415	        tcEnVuelo
   416	          ? 'Calculando…'
   417	          : (metaCapital.total ?? 0) > 0 && capitalConfirmado.total != null
   418	          ? `${moneyK(capitalConfirmado.total, 'PEN')} de ${moneyK(metaCapital.total ?? 0, 'PEN')}`
   419	          : capitalConfirmado.total == null ? '—' : moneyK(capitalConfirmado.total, 'PEN'),
   420	      pct: tcEnVuelo ? 0 : pctMeta(capitalConfirmado.total ?? 0, metaCapital.total ?? 0),
   421	      // El desglose solo aporta cuando hay dólares; si no, repetiría el total.
   422	      nota: [notaCapitalMonedas, notaAjusteCierre].filter(Boolean).join(' · ') || null,
   423	      sinDato: fotoMensualStoreCargando
   424	        ? 'Actualizando la meta y el cumplimiento de este mes…'
   425	        : objetivosMensualesError
   426	        ? 'Meta mensual no disponible'
   427	        : tcEnVuelo
   428	          ? 'Consultando el tipo de cambio para consolidar los dólares…'
   429	          : (metaCapital.total ?? 0) <= 0
   430	            ? SIN_META
   431	            : cumplimientoMensualError || capitalConfirmado.total == null
   432	              ? 'Cumplimiento confirmado no disponible'
   433	              : null,
   434	    },
   435	    {
   436	      label: 'Conversión del mes',
   437	      txt:
   438	        conversionMensualCargando
   439	          ? 'Calculando…'
   440	          : conversionConfirmada == null
   441	          ? '—'
   442	          : metaConversion != null
   443	            ? `${porcentajeConversionCanonica(conversionConfirmada)} de ${metaConversion}% · ${numero(recibidosEquipo)} recibidos`
   444	            : `${porcentajeConversionCanonica(conversionConfirmada)} · ${numero(recibidosEquipo)} recibidos`,
   445	      // El porqué de que la cifra no sea definitiva viaja PEGADO a ella. Antes
   446	      // esto la sustituía, y un mes con recibidos y cierres decía «sin datos».
   447	      nota: lecturaConversion.aviso,
   448	      pct: pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0),
   449	      sinDato: conversionMensualCargando
   450	        ? 'Consultando la conversión del mes…'
   451	        : conversionMensualError
   452	          ? 'Conversión del mes no disponible'
   453	          : !lecturaConversion.mostrar
   454	          ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
   455	          : conversionConfirmada == null
   456	            ? 'Sin leads recibidos este mes'
   457	            : fotoMensualStoreCargando
   458	              ? 'Actualizando la meta de este mes…'
   459	              : objetivosMensualesError
   460	              ? 'Meta mensual no disponible'
   461	              : metaConversion == null
   462	                ? SIN_META
   463	                : null,
   464	    },
   465	  ]
   466	
   467	  // ── Fase F — Agenda del equipo (RPC crm.metricas_agenda_fn) ──
   468	  // Periodo fijo: últimos 7 días con el reloj vivo (se corre solo al pasar la
   469	  // medianoche de Lima). En demo se alimenta del fixture sin tocar la red.
   470	  const sesionReal = Boolean(yo && !yo.demo)
   471	  const hastaMA = fechaLima(ahora)
   472	  const desdeMA = fechaLima(ahora - 6 * DIA_MS)
   473	  const consultaAgenda = useMetricasAgenda(sesionReal, desdeMA, hastaMA)
   474	  // En sesión real con data aún undefined y sin error, viaja undefined a
   475	  // propósito: el panel muestra su estado de carga.
   476	  const datosAgenda = sesionReal ? consultaAgenda.data : metricasAgendaDemo(desdeMA, hastaMA)
   477	  const errorAgenda =
   478	    sesionReal && consultaAgenda.error
   479	      ? mensajeDeError(
   480	          consultaAgenda.error,
   481	          'No pudimos consultar la agenda del equipo. Revisa tu conexión e inténtalo otra vez.',
   482	        )
   483	      : null
   484	  const cargandoAgenda =
   485	    sesionReal && (consultaAgenda.isPending || consultaAgenda.isFetching)
   486	  // Rezagos de agenda por miembro (vendedor_id → métrica) para que la señal de
   487	  // vencidas / sin acción / no-shows viva DENTRO de la fila de "Tu equipo hoy":
   488	  // la persona se juzga en un solo lugar, sin cruzar a la tabla de la izquierda.
   489	  const rezagosAgenda = useMemo(
   490	    () => new Map((datosAgenda?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   491	    [datosAgenda],
   492	  )
   493	
   494	  // ── F3: «Hoy, tres cosas» — el sistema prioriza el día (ley de Tesler). ──
   495	  // Mismas fuentes que ya están en pantalla; sin dato no hay tarjeta.
   496	  const cosas = useMemo(
   497	    () => tresCosasDeHoy({
   498	      cola,
   499	      totalPorRepartir,
   500	      esperaMasLargaReparto,
   501	      vendedoresAgenda: datosAgenda?.vendedores ?? [],
   502	    }),
   503	    [cola, totalPorRepartir, esperaMasLargaReparto, datosAgenda],
   504	  )
   505	  // «Ver →» de la franja: selecciona la pestaña y le LLEVA el foco (el
   506	  // focus() también hace scroll hasta la tarjeta de la cola).
   507	  const irAPestanaCola = (destino: PestanaCola) => {
   508	    elegirPestana(destino)
   509	    requestAnimationFrame(() => {
   510	      document.getElementById(`tab-cola-${destino}`)?.focus()
   511	    })
   512	  }
   513	
   514	  return (
   515	    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
   516	      {/* ── F3: la franja manda — máximo tres intervenciones, luego consulta ── */}
   517	      {modoSla.legado && <TresCosas cosas={cosas} onIrAPestana={irAPestanaCola} />}
   518	
   519	      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
   520	      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   521	        {/* F2 (figura-fondo): los KPIs son CONSULTA, no alarma — iconos en
   522	            neutro. Desde F3 TODOS: la urgencia de «Nuevos sin responder»
   523	            vive en la franja, que es su reemplazo. */}
   524	        <KpiCard
   525	          label="Pronóstico de capital abierto"
   526	          // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
   527	          // cumplimiento, y no se convierte a una tasa que aquí no se rotula.
   528	          // Fijar PEN a mano titulaba «S/ 0» a un equipo que vende en dólares.
   529	          value={capitalPronostico ? capitalPronostico.valor : '—'}
   530	          icon={Wallet}
   531	          color={SEMAFORO.neutro}
   532	          sub={
   533	            capitalPronostico?.otra
   534	              ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte`
   535	              : capitalPronostico?.soloDolares
   536	                ? 'Pipeline (USD)'
   537	                : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0
   538	                  ? 'Sin montos estimados — complétalos en cada ficha'
   539	                  : 'Pipeline (PEN) · abiertos con analista'
   540	          }
   541	          delay={0}
   542	        />
   543	        <KpiCard
   544	          label="Leads activos del equipo"
   545	          value={resumen ? String(resumen.totales.asignados) : '—'}
   546	          icon={Users}
   547	          color={SEMAFORO.neutro}
   548	          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   549	          delay={60}
   550	        />
   551	        {/* Sin payload, los subs NO afirman estados positivos («todos
   552	            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
   553	        <KpiCard
   554	          label="Nuevos sin responder"
   555	          value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
   556	          icon={AlertTriangle}
   557	          color={SEMAFORO.neutro}
   558	          sub={
   559	            cola == null
   560	              ? 'Sin dato por ahora'
   561	              : (cola.porBucket.sin_responder ?? 0) > 0
   562	                ? 'Sin primer contacto'
   563	                : 'Todos los nuevos fueron contactados'
   564	          }
   565	          delay={120}
   566	        />
   567	        <a
   568	          href={hashDe('derivaciones')}
   569	          aria-label={etiquetaAccesoReparto}
   570	          className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   571	        >
   572	          {/* F2: fuera el acento ámbar — la urgencia del reparto vive en la
   573	              campana (grupo) y desde F3 en la franja; el KPI es el conteo. */}
   574	          <KpiCard
   575	            label="Por repartir"
   576	            value={totalPorRepartir == null ? '—' : String(totalPorRepartir)}
   577	            icon={Inbox}
   578	            color={SEMAFORO.neutro}
   579	            sub={detalleReparto}
   580	            delay={180}
   581	          />
   582	        </a>
   583	      </div>
   584	
   585	      <AvisoDegradacion
   586	        activo={errorIndicadores}
   587	        queReintenta="de los indicadores del equipo"
   588	        onReintentar={reintentarIndicadores}
   589	      >
   590	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   591	      </AvisoDegradacion>
   592	
   593	      <div className="grid gap-4 lg:grid-cols-5">
   594	        <div className="space-y-4 lg:col-span-3">
   595	          {/* ── Cola del equipo (con dueño de cada item) ── */}
   596	          <SlaOperacionBoundary legado={(
   597	          <Card className="overflow-hidden">
   598	            <SectionHead
   599	              icon={ListChecks}
   600	              title="Cola del equipo"
   601	              right={
   602	                cola ? (
   603	                  // Patrón tablist de la casa (ranking-vendedores): aria-selected
   604	                  // + aria-controls, tabindex itinerante y flechas. Sin el
   605	                  // conteo en el nombre accesible el lector de pantalla no
   606	                  // sabría cuál pestaña tiene trabajo.
   607	                  <div role="tablist" aria-label="Filtrar la cola" className="inline-flex rounded-lg bg-muted/60 p-0.5">
   608	                    {PESTANAS_COLA.map((p, indice) => (
   609	                      <button
   610	                        key={p.id}
   611	                        id={`tab-cola-${p.id}`}
   612	                        type="button"
   613	                        role="tab"
   614	                        aria-selected={pestana === p.id}
   615	                        aria-controls="panel-cola"
   616	                        aria-label={`${p.label}: ${conteoPestana[p.id]}`}
   617	                        tabIndex={pestana === p.id ? 0 : -1}
   618	                        onClick={() => elegirPestana(p.id)}
   619	                        onKeyDown={(e) => {
   620	                          // Flechas con vuelta + Home/End (patrón APG completo).
   621	                          const destino = e.key === 'ArrowRight'
   622	                            ? (indice + 1) % PESTANAS_COLA.length
   623	                            : e.key === 'ArrowLeft'
   624	                              ? (indice - 1 + PESTANAS_COLA.length) % PESTANAS_COLA.length
   625	                              : e.key === 'Home'
   626	                                ? 0
   627	                                : e.key === 'End'
   628	                                  ? PESTANAS_COLA.length - 1
   629	                                  : null
   630	                          if (destino == null) return
   631	                          e.preventDefault()
   632	                          const siguiente = PESTANAS_COLA[destino]
   633	                          if (!siguiente) return
   634	                          elegirPestana(siguiente.id)
   635	                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
   636	                        }}
   637	                        className={cn(
   638	                          // Fitts: min-h para un objetivo táctil cómodo.
   639	                          'min-h-7 cursor-pointer rounded-md px-3 py-1.5 text-[11px] font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   640	                          pestana === p.id
   641	                            ? 'bg-card text-foreground shadow-sm'
   642	                            // Gris FUERTE: 11px sobre bg-muted no llega a 4.5:1
   643	                            // con el muted normal (revisor a11y, M1).
   644	                            : 'text-muted-foreground-strong hover:text-foreground',
   645	                        )}
   646	                      >
   647	                        {p.label} <span aria-hidden>{conteoPestana[p.id]}</span>
   648	                      </button>
   649	                    ))}
   650	                  </div>
   651	                ) : (
   652	                  <span className="text-xs text-muted-foreground">—</span>
   653	                )
   654	              }
   655	            />
   656	            {cola == null ? (
   657	              <CardContent className="pb-5 pt-0">
   658	                <p className="text-sm text-muted-foreground">
   659	                  {colaOp.error
   660	                    ? 'La cola del equipo no está disponible en este momento.'
   661	                    : 'Cargando la cola del equipo…'}
   662	                </p>
   663	              </CardContent>
   664	            ) : pestana === 'sin_movimiento' ? (
   665	              // ── Sin movimiento (≥5 días) — bloque estancados del RPC. El tope
   666	              //    de 50 es señal, no listado: con 50 justos la pestaña dice 50+.
   667	              //    tabIndex 0 SOLO en el panel vacío (patrón WAI-ARIA: el panel
   668	              //    sin interactivos debe ser enfocable para que Tab no lo salte). ──
   669	              <div
   670	                id="panel-cola"
   671	                role="tabpanel"
   672	                aria-labelledby="tab-cola-sin_movimiento"
   673	                tabIndex={cola.estancados.length === 0 ? 0 : undefined}
   674	              >
   675	                {cola.estancados.length === 0 ? (
   676	                  <CardContent className="pb-5 pt-0">
   677	                    <p className="text-sm text-muted-foreground">
   678	                      Ningún lead del equipo lleva 5 días o más sin actividad.
   679	                    </p>
   680	                  </CardContent>
   681	                ) : (
   682	                  <>
   683	                    {/* F4.3: el resumen de novedades va ANTES de la lista —
   684	                        es la razón para escanearla. Solo existe si hay algo
   685	                        que decir (el silencio también es información). */}
   686	                    {resumenVisita != null && (
   687	                      <p className="border-t border-border/60 px-5 py-2 text-[11px] font-semibold text-muted-foreground-strong">
   688	                        {resumenVisita}
   689	                      </p>
   690	                    )}
   691	                    <div className="divide-y divide-border/60 border-t border-border/60">
   692	                      {cola.estancados.map((a) => {
   693	                        // F2: la gravedad va UNA vez, en la tira (rojo desde 7
   694	                        // días, ámbar 5–6); el texto queda en gris de contexto.
   695	                        // F4.3: la novedad es CATEGÓRICA, no de severidad —
   696	                        // chip violeta para el que entró; el que cruzó a
   697	                        // crítico ya tiene la tira roja y lo dice el texto.
   698	                        const esNuevo = novedadesVisita?.nuevos.has(a.leadId) === true
   699	                        const cruzoACritico = novedadesVisita?.agravados.has(a.leadId) === true
   700	                        const vendedor = (a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'
   701	                        return (
   702	                          <button
   703	                            key={a.leadId}
   704	                            type="button"
   705	                            onClick={() => abrirLead(a.leadId)}
   706	                            // El label DICTA todo lo visible: el aria-label
   707	                            // pisa el contenido para un SR, así que lleva al
   708	                            // analista (a11y M1: de quién es el lead es parte
   709	                            // de la decisión), los días (la criticidad no
   710	                            // puede vivir solo en la tira de color) y el
   711	                            // literal del chip («nuevo aquí») para que el
   712	                            // dictado por voz también lo alcance (2.5.3).
   713	                            aria-label={`Abrir ficha de ${a.nombre} (${vendedor}), sin actividad ${haceTexto(a.dias)}${
   714	                              esNuevo
   715	                                ? ', nuevo aquí desde tu última visita'
   716	                                : cruzoACritico ? ', crítico desde tu última visita' : ''
   717	                            }`}
   718	                            className="flex w-full cursor-pointer items-center gap-2.5 border-l-[3px] py-2.5 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   719	                            style={{ borderLeftColor: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
   720	                          >
   721	                            <div className="min-w-0 flex-1 leading-tight">
   722	                              <p className="truncate text-sm font-semibold">
   723	                                {a.nombre}{' '}
   724	                                <span className="text-xs font-medium text-muted-foreground">
   725	                                  ({vendedor})
   726	                                </span>
   727	                              </p>
   728	                              <p className="text-[11px] font-medium text-muted-foreground">
   729	                                Sin actividad {haceTexto(a.dias)}
   730	                                {/* Gris FUERTE (a11y F4.3 #2): es la única
   731	                                    señal textual del cruce y el gris débil a
   732	                                    11px roza el 4.5:1 en hover. */}
   733	                                {cruzoACritico && (
   734	                                  <span className="text-muted-foreground-strong"> · crítico desde tu última visita</span>
   735	                                )}
   736	                              </p>
   737	                            </div>
   738	                            {esNuevo && (
   739	                              <Badge color={SEMAFORO.violeta} variant="outline" className="shrink-0 whitespace-nowrap">
   740	                                Nuevo aquí
   741	                              </Badge>
   742	                            )}
   743	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   744	                          </button>
   745	                        )
   746	                      })}
   747	                    </div>
   748	                  </>
   749	                )}
   750	              </div>
   751	            ) : filasCola.length === 0 ? (
   752	              <CardContent id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} tabIndex={0} className="pb-5 pt-0">
   753	                <p className="text-sm text-muted-foreground">
   754	                  {pestana === 'urgente'
   755	                    ? 'Nada urgente — ninguna fila crítica ni media en la cola.'
   756	                    : 'Sin pendientes — el equipo está al día con todos sus leads abiertos.'}
   757	                </p>
   758	              </CardContent>
   759	            ) : (
   760	              <div id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} className="divide-y divide-border/60 border-t border-border/60">
   761	                {/* Fila = div role="button" (no <button>: contiene los links de
   762	                    AccionesContacto y un botón no puede anidar interactivos).
   763	                    F2 (pregnancia): la severidad se dice UNA vez — la tira de
   764	                    3 px. Fuera el punto, el badge de etapa y el azul del monto;
   765	                    la etapa va en texto plano delante del motivo. El pl de
   766	                    17 px compensa los 3 px de la tira: el contenido queda a
   767	                    20 px, alineado con la cabecera (Codex F2). */}
   768	                {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map((i) => {
   769	                  const abrir = () => abrirLead(i.lead.id)
   770	                  return (
   771	                    <div
   772	                      key={i.lead.id}
   773	                      role="button"
   774	                      tabIndex={0}
   775	                      data-sev={i.sev}
   776	                      onClick={abrir}
   777	                      onKeyDown={(e) => {
   778	                        if (e.key === 'Enter' || e.key === ' ') {
   779	                          e.preventDefault()
   780	                          abrir()
   781	                        }
   782	                      }}
   783	                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
   784	                      className="flex w-full cursor-pointer items-center gap-3 border-l-[3px] py-3 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   785	                      style={{ borderLeftColor: i.sev === 'baja' ? 'transparent' : SEV_COLOR[i.sev] }}
   786	                    >
   787	                      <div className="min-w-0 flex-1 leading-tight">
   788	                        <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
   789	                        <p className="truncate text-xs text-muted-foreground">
   790	                          {BUCKET_LABEL[i.bucket]} · {i.motivo}
   791	                        </p>
   792	                      </div>
   793	                      {i.lead.monto_estimado != null && (
   794	                        <span className="hidden shrink-0 text-xs font-semibold tabular-nums text-muted-foreground sm:inline">
   795	                          {moneyK(i.lead.monto_estimado, i.lead.moneda)}
   796	                        </span>
   797	                      )}
   798	                      {i.lead.vendedor_nombre ? (
   799	                        <span className="flex shrink-0 items-center gap-1.5">
   800	                          <Avatar nombre={i.lead.vendedor_nombre} className="size-6 text-[9px]" />
   801	                          <span className="hidden max-w-[110px] truncate text-xs text-muted-foreground md:inline">
   802	                            {i.lead.vendedor_nombre}
   803	                          </span>
   804	                        </span>
   805	                      ) : (
   806	                        <span className="shrink-0 text-xs font-medium text-muted-foreground">sin asignar</span>
   807	                      )}
   808	                      <AccionesContacto lead={i.lead} compacto />
   809	                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   810	                    </div>
   811	                  )
   812	                })}
   813	                {filasCola.length > COLA_VISIBLES && (
   814	                  <button
   815	                    type="button"
   816	                    onClick={() => setColaExpandida((e) => !e)}
   817	                    aria-expanded={colaExpandida}
   818	                    className="flex w-full cursor-pointer items-center justify-center gap-1 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   819	                  >
   820	                    <ChevronRight
   821	                      className={cn('size-3.5 shrink-0 transition-transform', colaExpandida && 'rotate-90')}
   822	                      aria-hidden
   823	                    />
   824	                    {colaExpandida
   825	                      ? `Mostrar solo los ${COLA_VISIBLES} más urgentes`
   826	                      // Con más pendientes que el p_limite del RPC, el botón no
   827	                      // puede prometer el total de la pestaña: dice lo que muestra.
   828	                      : totalPestanaActiva > filasCola.length
   829	                        ? `Ver los ${filasCola.length} más urgentes de ${totalPestanaActiva}`
   830	                        : `Ver los ${filasCola.length} pendientes`}
   831	                  </button>
   832	                )}
   833	              </div>
   834	            )}
   835	          </Card>
   836	          )}>
   837	            <Card>
   838	              <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
   839	                <div className="space-y-1">
   840	                  <h2 className="text-sm font-bold">Seguimiento del equipo</h2>
   841	                  <p className="text-xs text-muted-foreground">Prioriza las gestiones y revisa los plazos de cada analista.</p>
   842	                </div>
   843	                <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   844	                  Abrir seguimiento <ChevronRight className="size-4" aria-hidden />
   845	                </a>
   846	              </CardContent>
   847	            </Card>
   848	          </SlaOperacionBoundary>
   849	
   850	          {/* Rentabilidad R3: tus solicitudes de tasa en curso (solo si hay). */}
   851	          <TasasAutorizadasAnalistaPanel />
   852	
   853	          {/* ── Agenda del equipo (Fase F — quién registra, cierra y arrastra) ── */}
   854	          <AgendaEquipoPanel
   855	            datos={datosAgenda}
   856	            cargando={cargandoAgenda}
   857	            error={errorAgenda}
   858	            modoDemo={yo?.demo === true}
   859	            onReintentar={() => {
   860	              if (sesionReal) void consultaAgenda.refetch()
   861	            }}
   862	            equipo={equipo}
   863	          />
   864	        </div>
   865	        <div className="space-y-4 lg:col-span-2">
   866	          {/* ── Tu equipo hoy (semáforo por analista) ── */}
   867	          <Card className="overflow-hidden">
   868	            <SectionHead
   869	              icon={UsersRound}
   870	              title="Tu equipo hoy"
   871	              right={tc ? (
   872	                <span className="text-xs text-muted-foreground">
   873	                  Capital en proceso · {rotuloTipoCambio(tc.promedio, tc.fuente)}
   874	                </span>
   875	              ) : undefined}
   876	            />
   877	            {rank == null ? (
   878	              <CardContent className="pb-5 pt-0">
   879	                <p className="text-sm text-muted-foreground">
   880	                  {vendedoresOp.error
   881	                    ? 'El resumen por analista no está disponible en este momento.'
   882	                    : 'Cargando el resumen por analista…'}
   883	                </p>
   884	              </CardContent>
   885	            ) : rank.length === 0 ? (
   886	              <CardContent className="pb-5 pt-0">
   887	                <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   888	              </CardContent>
   889	            ) : (
   890	              <div className="divide-y divide-border/60 border-t border-border/60">
   891	                {rank.map((r) => {
   892	                  const c = semaforoDias(r.diasSinActividadMax)
   893	                  // Rezago de agenda del miembro (mismos umbrales del panel
   894	                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
   895	                  const rez = rezagosAgenda.get(r.m.perfil_id)
   896	                  // El rezago de agenda TAMBIÉN es señal: sin esto, quien tocó
   897	                  // ayer pero arrastra 10 vencidas quedaba sin ninguna marca
   898	                  // visual (hallazgo IMPORTANTE de Codex sobre F2).
   899	                  const conRezagoAgenda = rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)
   900	                  const colorPunto = r.activos === 0
   901	                    ? SEMAFORO.neutro
   902	                    : c !== SEMAFORO.ok
   903	                      ? c
   904	                      : SEMAFORO.atencion
   905	                  const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   906	                  return (
   907	                    <div key={r.m.perfil_id} className="px-5 py-3">
   908	                      <div className="flex items-center gap-2.5">
   909	                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
   910	                        <div className="min-w-0 flex-1 leading-tight">
   911	                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
   912	                          <p className="text-[11px] tabular-nums text-muted-foreground">
   913	                            {r.activos} activos · {r.conversion == null
   914	                              ? r.conversionDisponible && r.divisorConversion === 0
   915	                                ? 'sin divisor mensual'
   916	                                : 'dato de conversión no disponible'
   917	                              : `${textoConversionOperativa(r.conversion)} conversión`}
   918	                            {r.operacionesCartera != null && r.operacionesCartera > 0
   919	                              ? ` · ${numero(r.operacionesCartera)} de cartera`
   920	                              : ''}
   921	                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
   922	                          </p>
   923	                        </div>
   924	                        {/* Decisión #10: el total unificado es el número grande y el
   925	                            desglose por moneda va debajo. Sin TC degrada al PEN de
   926	                            siempre — el USD no entra al total sin una tasa real. */}
   927	                        <div className="shrink-0 text-right leading-tight">
   928	                          <p className="text-sm font-extrabold tabular-nums text-foreground">
   929	                            {cap.total != null ? moneyK(cap.total) : '—'}
   930	                          </p>
   931	                          <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
   932	                        </div>
   933	                      </div>
   934	                      <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 gap-y-1 pl-[46px]">
   935	                        {/* F2: el punto solo cuando HAY señal (ámbar 2–5 d,
   936	                            rojo >5 d, neutro sin cartera). Pintar «al día» de
   937	                            azul en cada fila gastaba el color en nada. Sin
   938	                            leads abiertos no hay «al día» que celebrar:
   939	                            `semaforoDias(0)` devolvía azul y un analista sin
   940	                            cartera se pintaba como el que va al corriente. */}
   941	                        {(r.activos === 0 || c !== SEMAFORO.ok || conRezagoAgenda) && (
   942	                          <span
   943	                            data-testid="equipo-semaforo"
   944	                            className="size-2 shrink-0 rounded-full"
   945	                            style={{ background: colorPunto }}
   946	                            aria-hidden
   947	                          />
   948	                        )}
   949	                        <span className="text-[11px] text-muted-foreground">
   950	                          {r.activos === 0
   951	                            ? 'Sin leads abiertos'
   952	                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
   953	                          {/* El rezago va en TEXTO pegado a la persona (aquí se
   954	                              juzga, decisión 1 del 2026-08-23); el único chip
   955	                              es el no-show repetido — uno de los dos rojos del
   956	                              presupuesto de color. */}
   957	                          {rez != null && rez.vencidas > 0
   958	                            && ` · ${rez.vencidas} ${rez.vencidas === 1 ? 'vencida' : 'vencidas'}`}
   959	                          {rez != null && rez.leads_sin_accion > 0
   960	                            && ` · ${rez.leads_sin_accion} sin acción`}
   961	                        </span>
   962	                        {rez != null && rez.no_asistio >= 2 && (
   963	                          <span className="ml-auto">
   964	                            {/* solid: el soft (rojo sobre tinte) da 4.01:1 a 11px
   965	                                y no llega a AA (revisor a11y, M2). */}
   966	                            <Badge color={SEMAFORO.critico} variant="solid">{rez.no_asistio} no asistió</Badge>
   967	                          </span>
   968	                        )}
   969	                      </div>
   970	                    </div>
   971	                  )
   972	                })}
   973	              </div>
   974	            )}
   975	          </Card>
   976	
   977	          {/* ── Cumplimiento confirmado del equipo ── */}
   978	          <Card>
   979	            <SectionHead
   980	              icon={Target}
   981	              title="Cumplimiento del equipo"
   982	              right={<span className="text-xs text-muted-foreground">contratos confirmados · este mes</span>}
   983	            />
   984	            <CardContent className="space-y-4 pb-5 pt-0">
   985	              {filasMeta.map((f) => (
   986	                <div key={f.label}>
   987	                  <div className="mb-1.5 flex items-baseline justify-between gap-2">
   988	                    <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   989	                    <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   990	                  </div>
   991	                  {f.nota && (
   992	                    <p className="mb-1 text-[10.5px] tabular-nums text-muted-foreground">{f.nota}</p>
   993	                  )}
   994	                  {f.sinDato ? (
   995	                    <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
   996	                  ) : (
   997	                    <Progress value={f.pct} color={colorMeta(f.pct)} />
   998	                  )}
   999	                </div>
  1000	              ))}
  1001	              <p className="text-[10.5px] text-muted-foreground">
  1002	                El capital en dólares entra al total convertido a tipo de cambio real. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
  1003	              </p>
  1004	              {(objetivosMensualesError || cumplimientoMensualError || conversionMensualError || tcCaido) && (
  1005	                <Button
  1006	                  variant="ghost"
  1007	                  size="sm"
  1008	                  onClick={() => {
  1009	                    if (objetivosMensualesError || cumplimientoMensualError) {
  1010	                      setRecargaPeriodoFallida(false)
  1011	                      void recargar().then((ok) => {
  1012	                        if (!ok && !fotoMensualStoreVigente) setRecargaPeriodoFallida(true)
  1013	                      })
  1014	                    }
  1015	                    if (conversionMensualError) void qConversionMensual.refetch()
  1016	                    if (tcCaido) recargarTipoCambio()
  1017	                  }}
  1018	                >
  1019	                  Reintentar
  1020	                </Button>
  1021	              )}
  1022	            </CardContent>
  1023	          </Card>
  1024	
  1025	          {/* ── Por empresa: de dónde vino cada sol (Avance vs. COOPAC). Se
  1026	               oculta solo si el mes no tiene cierres en cooperativas. ── */}
  1027	          <DesglosePorEmpresa
  1028	            demo={yo?.demo === true}
  1029	            porVendedor={cumplimientoMensual?.porVendedor ?? null}
  1030	          />
  1031	        </div>
  1032	      </div>
  1033	
  1034	      <p className="text-[11px] text-muted-foreground">
  1035	        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
  1036	      </p>
  1037	    </div>
  1038	  )
  1039	}
```

## `app/src/screens/hoy.tsx`
```
     1	// Pantalla Hoy (F1c) — wrapper que enruta por rol: cada rango ve SU propio
     2	// universo e inteligencia (screens/hoy/*). El ámbito de datos lo recorta el
     3	// store (useCRMData().ambito); aquí solo se decide QUÉ panel renderizar.
     4	import type { JSX } from 'react'
     5	import { useAuth } from '@/lib/auth-context'
     6	import { HoyVendedor } from './hoy/vendedor'
     7	import { HoySupervisor } from './hoy/supervisor'
     8	import { HoyGerencia } from './hoy/gerencia'
     9	import { HoyDirectorio } from './hoy/directorio'
    10	import { ConfiguracionRespuestasTasa } from '@/components/app/respuestas-tasa'
    11	
    12	export function Hoy(): JSX.Element {
    13	  const { yo } = useAuth()
    14	  switch (yo?.rol) {
    15	    case 'supervisor':
    16	      return <><ConfiguracionRespuestasTasa soloActivacion /><HoySupervisor /></>
    17	    case 'gerencia':
    18	      return <HoyGerencia seccion="resumen" />
    19	    case 'directorio':
    20	      return <HoyDirectorio />
    21	    case 'vendedor':
    22	    default:
    23	      // Rol desconocido degrada al panel de analista: su ámbito es el más
    24	      // restrictivo (solo leads propios — para una sesión rara, ninguno).
    25	      return <><ConfiguracionRespuestasTasa soloActivacion /><HoyVendedor /></>
    26	  }
    27	}
```

## `app/src/lib/tres-cosas.ts`
```
     1	// lib/tres-cosas.ts — la franja «Hoy, tres cosas» del supervisor (F3,
     2	// 2026-08-23). Ley de Tesler aplicada: el SISTEMA absorbe la priorización del
     3	// día — qué mirar primero — en vez de dejar que el supervisor escanee cinco
     4	// tarjetas. Máximo TRES intervenciones (Hick/Miller), cada una con su acción.
     5	//
     6	// Reglas de la casa que esta función custodia:
     7	// · Sin dato NO hay tarjeta: un candidato solo existe si su fuente llegó
     8	//   (nada de «—» en la franja; la degradación se avisa en AvisoDegradacion).
     9	// · Presupuesto de color: rojo = interviene HOY (nuevos sin responder,
    10	//   no-show repetido); ámbar = esta semana. El rojo va siempre primero.
    11	// · Espejo de la campana (lib/alertas.ts): mismas DECISIONES y mismos
    12	//   umbrales (no_asistio ≥ 2 · sin acción ≥ 3, crítica ≥ 5). Los CONTEOS
    13	//   pueden diferir a propósito: la campana deduplica lead a lead y trabaja
    14	//   sobre ambito.leads (tope 2000); la franja lee los agregados del RPC
    15	//   (universo completo, foto actual). Misma decisión, lentes distintas —
    16	//   auditado y aceptado (Codex F3 #2).
    17	// · Degradación honesta: con cola null (cargando o error) el candidato NO
    18	//   existe y no se inventa urgencia desde el store local; el fallo se avisa
    19	//   en AvisoDegradacion, que es el canal de errores de la pantalla (F3 #4).
    20	import type { MetricaAgendaVendedor } from './metricas-agenda'
    21	import { haceTexto } from './inteligencia'
    22	import { TOPE_ESTANCADOS, type ColaAccionOperativa } from './cola-accion'
    23	
    24	/** Pestaña de la cola a la que salta una cosa (espejo del tablist de HOY). */
    25	export type PestanaColaDestino = 'urgente' | 'sin_movimiento' | 'todo'
    26	
    27	export type DestinoCosa =
    28	  | { tipo: 'pestana'; pestana: PestanaColaDestino }
    29	  | { tipo: 'vista'; vista: 'derivaciones' | 'equipo' }
    30	
    31	export interface CosaDeHoy {
    32	  id: 'sin_responder' | 'no_asistio' | 'por_repartir' | 'sin_accion' | 'sin_movimiento'
    33	  severidad: 'critica' | 'atencion'
    34	  texto: string
    35	  /** Etiqueta del enlace/botón — siempre hay UNA acción al lado del rojo. */
    36	  accion: string
    37	  destino: DestinoCosa
    38	}
    39	
    40	export interface TresCosasInput {
    41	  /** Cola operativa (null = sin dato: ese candidato no existe). */
    42	  cola: ColaAccionOperativa | null
    43	  /** Total autorizado por resumen_cartera_fn (null = sin dato). */
    44	  totalPorRepartir: number | null
    45	  /** Espera observable del parkeado más rezagado, en días (null = sin detalle). */
    46	  esperaMasLargaReparto: number | null
    47	  /** Métricas de agenda por analista (vacío = sin dato o sin rezago). */
    48	  vendedoresAgenda: readonly MetricaAgendaVendedor[]
    49	}
    50	
    51	/** Peso del candidato dentro de su severidad (menor = primero). */
    52	const PESO: Record<CosaDeHoy['id'], number> = {
    53	  sin_responder: 0,
    54	  no_asistio: 1,
    55	  por_repartir: 2,
    56	  sin_accion: 3,
    57	  sin_movimiento: 4,
    58	}
    59	
    60	const TOPE = 3
    61	
    62	/**
    63	 * Deriva las (a lo sumo) tres intervenciones del día del supervisor.
    64	 * Devuelve [] cuando no hay nada que hacer O nada que decir con datos: la
    65	 * franja entera no se pinta — el silencio también es información.
    66	 */
    67	export function tresCosasDeHoy({
    68	  cola,
    69	  totalPorRepartir,
    70	  esperaMasLargaReparto,
    71	  vendedoresAgenda,
    72	}: TresCosasInput): CosaDeHoy[] {
    73	  const cosas: CosaDeHoy[] = []
    74	
    75	  // 1 · Nuevos sin responder — la interrupción del día (un lead nuevo se
    76	  //     enfría por horas). Autoridad del CONTEO: el resumen por bucket del
    77	  //     RPC. La SEVERIDAD sale de los items: un nuevo de dos horas es media
    78	  //     para el RPC y pintarlo rojo desalinearía franja, cola y campana
    79	  //     (Codex F3 #1) — rojo solo cuando algún sin_responder ya es crítico.
    80	  const sinResponder = cola?.porBucket.sin_responder ?? 0
    81	  if (cola != null && sinResponder > 0) {
    82	    const hayCritico = cola.items.some(
    83	      (i) => i.bucket === 'sin_responder' && i.sev === 'critica',
    84	    )
    85	    cosas.push({
    86	      id: 'sin_responder',
    87	      severidad: hayCritico ? 'critica' : 'atencion',
    88	      texto: `${sinResponder} ${sinResponder === 1 ? 'nuevo sin responder' : 'nuevos sin responder'}`,
    89	      accion: 'Ver',
    90	      destino: { tipo: 'pestana', pestana: 'urgente' },
    91	    })
    92	  }
    93	
    94	  // 2 · No-show repetido — el otro rojo del presupuesto (≥2, umbral de la
    95	  //     campana y de «Tu equipo hoy»). Con varios analistas se agrupa.
    96	  // Solo ANALISTAS activos: el RPC también trae la fila del propio
    97	  // supervisor, y sin este filtro su agenda ocupaba un cupo disfrazada de
    98	  // problema de analista (Codex F3 #3) — mismo corte que la campana.
    99	  const vendedores = vendedoresAgenda.filter((v) => v.rol === 'vendedor' && v.activo)
   100	  const conNoShow = vendedores
   101	    .filter((v) => v.no_asistio >= 2)
   102	    .sort((a, b) => b.no_asistio - a.no_asistio || a.vendedor_id.localeCompare(b.vendedor_id))
   103	  const peorNoShow = conNoShow[0]
   104	  if (peorNoShow != null) {
   105	    cosas.push({
   106	      id: 'no_asistio',
   107	      severidad: 'critica',
   108	      texto: conNoShow.length === 1
   109	        ? `${peorNoShow.nombre}: ${peorNoShow.no_asistio} citas sin asistir`
   110	        : `${conNoShow.length} analistas con citas sin asistir`,
   111	      accion: 'Ver equipo',
   112	      destino: { tipo: 'vista', vista: 'equipo' },
   113	    })
   114	  }
   115	
   116	  // 3 · Por repartir — el conteo es SIEMPRE el del servidor; el rezago solo
   117	  //     acompaña si el detalle local llegó (misma regla del KPI compacto).
   118	  if (totalPorRepartir != null && totalPorRepartir > 0) {
   119	    cosas.push({
   120	      id: 'por_repartir',
   121	      severidad: 'atencion',
   122	      texto: `${totalPorRepartir} por repartir`
   123	        + (esperaMasLargaReparto != null ? ` · el más rezagado ${haceTexto(esperaMasLargaReparto)}` : ''),
   124	      accion: 'Repartir',
   125	      destino: { tipo: 'vista', vista: 'derivaciones' },
   126	    })
   127	  }
   128	
   129	  // 4 · Analista con más leads sin próxima acción (≥3, umbral de la campana).
   130	  const conSinAccion = vendedores
   131	    .filter((v) => v.leads_sin_accion >= 3)
   132	    .sort((a, b) => b.leads_sin_accion - a.leads_sin_accion || a.vendedor_id.localeCompare(b.vendedor_id))
   133	  const peorSinAccion = conSinAccion[0]
   134	  if (peorSinAccion != null) {
   135	    cosas.push({
   136	      id: 'sin_accion',
   137	      // Desde 5 es crítico — el MISMO umbral que la campana (Codex F3 #1).
   138	      severidad: peorSinAccion.leads_sin_accion >= 5 ? 'critica' : 'atencion',
   139	      texto: conSinAccion.length === 1
   140	        ? `${peorSinAccion.nombre}: ${peorSinAccion.leads_sin_accion} leads sin próxima acción`
   141	        : `${conSinAccion.length} analistas con leads sin próxima acción`,
   142	      accion: 'Ver equipo',
   143	      destino: { tipo: 'vista', vista: 'equipo' },
   144	    })
   145	  }
   146	
   147	  // 5 · Sin movimiento — el peor caso del bloque estancados del RPC (≥5 días).
   148	  const peorEstancado = cola?.estancados[0]
   149	  if (cola != null && peorEstancado != null) {
   150	    // Al tope del RPC el conteo dice «50+», igual que la pestaña: con 50
   151	    // justos afirmar «50» sería mentir por omisión (Codex F3 #6).
   152	    const conteoEstancados = cola.estancados.length >= TOPE_ESTANCADOS
   153	      ? `${TOPE_ESTANCADOS}+`
   154	      : String(cola.estancados.length)
   155	    cosas.push({
   156	      id: 'sin_movimiento',
   157	      severidad: 'atencion',
   158	      texto: `${conteoEstancados} sin movimiento · el peor lleva ${haceTexto(peorEstancado.dias).replace('hace ', '')}`,
   159	      accion: 'Ver',
   160	      destino: { tipo: 'pestana', pestana: 'sin_movimiento' },
   161	    })
   162	  }
   163	
   164	  // Rojo primero, luego el peso fijo: el orden es una decisión, no un azar.
   165	  return cosas
   166	    .sort((a, b) => (
   167	      (a.severidad === b.severidad ? 0 : a.severidad === 'critica' ? -1 : 1)
   168	      || PESO[a.id] - PESO[b.id]
   169	    ))
   170	    .slice(0, TOPE)
   171	}
```

## `app/src/lib/sla-operacion.ts (contratos del seguimiento nuevo)`
```
     1	import * as v from 'valibot'
     2	import type { Rol } from './roles'
     3	
     4	const fecha = v.nullable(v.string())
     5	const indicador = v.nullable(v.boolean())
     6	const numero = v.nullable(v.number())
     7	const tarea = v.nullable(v.object({ id: v.string(), tipo: v.string(), vence_en: v.string(), reprogramaciones: v.number() }))
     8	export const TipoAvisoSlaSchema = v.picklist(['primera_atencion', 'tarea_vencida', 'seguimiento', 'revision_comercial', 'datos_incompletos', 'por_repartir'])
     9	export const AvisoSlaSchema = v.object({ id: v.string(), bucket: TipoAvisoSlaSchema, severidad: v.picklist(['critica', 'media']),
    10	  referencia_en: fecha, tarea_id: v.nullable(v.string()) })
    11	export type AvisoSla = v.InferOutput<typeof AvisoSlaSchema>
    12	export const EstadoSlaV2Schema = v.pipe(v.object({
    13	  lead_id: v.string(), evaluacion: v.picklist(['completa', 'parcial', 'no_aplica']), motivos_datos: v.array(v.string()),
    14	  avisos: v.array(AvisoSlaSchema),
    15	  avisos_mostrados: v.optional(v.array(AvisoSlaSchema)),
    16	  operacion: v.optional(v.object({ modelo: v.literal(3), aviso_principal: v.nullable(AvisoSlaSchema),
    17	    proxima_accion: v.nullable(v.object({ id: v.string(), tipo: v.string(), titulo: v.string(), vence_en: v.string() })),
    18	    proximo_cambio_en: fecha })),
    19	  seguimiento: v.object({ referencia_en: fecha, ultima_gestion_en: fecha, limite_en: fecha, vencido: indicador, accion_pendiente: indicador }),
    20	  compromiso: v.object({ tarea, validez: v.string(), hasta_en: fecha, cobertura_activa: indicador }),
    21	  etapa: v.object({ limite_original_en: fecha, limite_prorrogado_en: fecha, limite_operativo_en: fecha, techo_en: fecha,
    22	    prorrogas_usadas: numero, prorrogas_restantes: numero, revision_requerida: indicador, motivos_revision: v.array(v.string()) }),
    23	}), v.check((estado) => !estado.operacion || (estado.avisos_mostrados !== undefined
    24	  && estado.avisos_mostrados.every((aviso) => estado.avisos.some((causa) => causa.id === aviso.id)))))
    25	export type EstadoSlaV2 = v.InferOutput<typeof EstadoSlaV2Schema>
    26	export const ModoSlaSchema = v.picklist(['legado', 'observacion', 'activo'])
    27	const sobre = { modelo_avisos: v.optional(v.literal(3)), proximo_cambio_en: v.optional(fecha), version: v.literal(2), modo: ModoSlaSchema, control_revision: v.number(), calculado_en: v.string() }
    28	export const EstadosSlaV2Schema = v.object({ ...sobre, filas: v.array(EstadoSlaV2Schema) })
    29	const conteo = v.pipe(v.number(), v.integer(), v.minValue(0))
    30	export const ResumenAvisosSlaSchema = v.pipe(v.object({ ...sobre,
    31	  total_oportunidades: conteo, total_avisos: conteo, criticas: conteo,
    32	  grupos: v.pipe(v.array(v.object({ bucket: TipoAvisoSlaSchema, total: v.pipe(conteo, v.minValue(1)) })), v.maxLength(6)),
    33	}), v.check((r) => r.total_oportunidades <= r.total_avisos && r.criticas <= r.total_avisos
    34	  && r.grupos.reduce((total, g) => total + g.total, 0) === r.total_avisos
    35	  && new Set(r.grupos.map((g) => g.bucket)).size === r.grupos.length
    36	  && (r.total_oportunidades > 0 || r.total_avisos === 0)))
    37	export type ResumenAvisosSla = v.InferOutput<typeof ResumenAvisosSlaSchema>
    38	export const SENALES_SLA = [
    39	  ['pendientes', 'Para atender ahora'], ['todas', 'Todas las acciones'], ['primera_atencion', 'Primera atención'], ['tareas_vencidas', 'Tareas vencidas'],
    40	  ['seguimientos_pendientes', 'Seguimiento pendiente'], ['revisiones', 'Revisión comercial'],
    41	  ['datos_incompletos', 'Datos incompletos'], ['por_repartir', 'Por repartir'],
    42	] as const
    43	export type SenalSla = typeof SENALES_SLA[number][0]
    44	export type FiltrosSla = { senal: SenalSla; etapa: string | null; analista_id: string | null }
    45	export type CursorSla = Record<string, unknown>
    46	const senales = v.object({ pendientes: v.boolean(), primera_atencion: v.boolean(), tareas_vencidas: v.boolean(), seguimientos_pendientes: v.boolean(),
    47	  revisiones: v.boolean(), datos_incompletos: v.boolean(), por_repartir: v.boolean() })
    48	const cursor = v.nullable(v.record(v.string(), v.unknown()))
    49	export const ColaSlaPaginaSchema = v.object({ ...sobre,
    50	  filtros: v.object({ senal: v.string(), etapa: v.nullable(v.string()), analista_id: v.nullable(v.string()) }),
    51	  limite: v.number(), total_items: v.number(), hay_mas: v.boolean(), cursor_siguiente: cursor,
    52	  rango: v.object({ desde: v.number(), hasta: v.number() }),
    53	  totales: v.object({ pendientes: v.number(), primera_atencion: v.number(), tareas_vencidas: v.number(), seguimientos_pendientes: v.number(), revisiones: v.number(), datos_incompletos: v.number(), por_repartir: v.number() }),
    54	  items: v.array(v.object({ lead_id: v.string(), bucket: v.string(), severidad: v.picklist(['critica', 'media', 'baja']),
    55	    prioridad: v.number(), referencia_en: fecha, tarea_id: v.nullable(v.string()),
    56	    lead: v.object({ id: v.string(), nombre_completo: v.string(), etapa: v.string(), analista_id: v.nullable(v.string()), analista_nombre: v.nullable(v.string()) }),
    57	    senales, estado: EstadoSlaV2Schema,
    58	  })),
    59	})
    60	export type ColaSlaPagina = v.InferOutput<typeof ColaSlaPaginaSchema>
    61	export const ACCIONES_SLA: Record<string, string> = {
    62	  primera_atencion: 'Contactar al cliente', tarea_vencida: 'Revisar actividad pendiente', tarea_hoy: 'Actividad de hoy',
    63	  seguimiento: 'Retomar el contacto', revision_comercial: 'Definir el siguiente paso', datos_incompletos: 'Revisar datos',
    64	  proxima_tarea: 'Próxima tarea', por_repartir: 'Asignar analista',
    65	}
    66	/**
    67	 * La gestión manual desde la ficha pertenece al analista asignado. Supervisión
    68	 * y Gerencia revisan el seguimiento, pero no deben registrar una actividad como
    69	 * si la hubieran realizado ellas. Es una regla de interfaz, no autorización.
    70	 */
    71	export function puedeRegistrarGestionSla(rol: Rol | null | undefined): boolean {
    72	  return rol === 'vendedor'
    73	}
    74	
    75	// Solo presentación: el servidor decide qué avisos corresponden al actor y cuándo.
    76	// `boton: null` hace inseparables el texto de revisión de supervisión y la
    77	// ausencia de una acción que fingiría una gestión del analista.
    78	export function textoAvisoSla(aviso: AvisoSla, supervision: boolean, modelo?: number) {
    79	  if (modelo === 3 && aviso.bucket === 'primera_atencion') return {
    80	    titulo: supervision ? 'Revisa la primera gestión con el analista' : 'Realiza el primer intento y registra el resultado', boton: supervision ? null : 'Registrar gestión',
    81	  }
    82	  if (modelo === 3 && aviso.bucket === 'seguimiento') return {
    83	    titulo: supervision ? 'Revisa el seguimiento con el analista' : 'Retoma el seguimiento', boton: supervision ? null : 'Registrar gestión',
    84	  }
    85	  switch (aviso.bucket) {
    86	    case 'tarea_vencida': return { titulo: 'Revisa la actividad pendiente', boton: 'Revisar actividad' }
    87	    case 'primera_atencion': return { titulo: supervision ? 'Revisa el contacto inicial con el cliente' : 'Contacta al cliente y registra el resultado', boton: supervision ? null : 'Registrar gestión' }
    88	    case 'seguimiento': return { titulo: supervision ? 'Revisa el seguimiento con el analista' : 'Retoma el contacto y registra el resultado', boton: supervision ? null : 'Registrar gestión' }
    89	    case 'revision_comercial': return { titulo: 'Revisa el caso y define el siguiente paso', boton: 'Revisar caso' }
    90	    case 'por_repartir': return { titulo: 'Asigna un analista a esta oportunidad', boton: 'Ver asignación' }
```

## `app/src/data/sla-operacion-queries.ts`
```
     1	import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
     2	import { useAuth } from '@/lib/auth-context'
     3	import { crmQueryKeys } from './crm-queries'
     4	import { cambiarModoSla, publicarReglasSlaAprobadas, obtenerConfiguracionSlaV2, listarColaSla, obtenerEstadosSlaV2, obtenerResumenAvisosSla } from './sla-operacion-api'
     5	import { CrmApiError } from './crm-api'
     6	import type { CursorSla, FiltrosSla } from '@/lib/sla-operacion'
     7	import { intervaloReconsultaSla } from './sla-operacion-reloj'
     8	
     9	// Ambas lecturas heredan la invalidación existente de cada gestión, tarea y cambio de ámbito.
    10	export const slaOperacionKeys = {
    11	  raiz: () => [...crmQueryKeys.metricasAmbito(), 'sla-v2'] as const,
    12	  estado: (actor: string | null, ids: string[]) => [...slaOperacionKeys.raiz(), actor, 'estado', ids] as const,
    13	  cola: (actor: string | null, filtros: FiltrosSla, cursor: CursorSla | null, limite: number) => [...slaOperacionKeys.raiz(), actor, 'cola', filtros, cursor, limite] as const,
    14	  avisos: (actor: string | null) => [...slaOperacionKeys.raiz(), actor, 'avisos'] as const,
    15	}
    16	export function useResumenAvisosSla(habilitada: boolean) {
    17	  const { yo } = useAuth()
    18	  return useQuery({ queryKey: slaOperacionKeys.avisos(yo?.id ?? null),
    19	    queryFn: ({ signal }) => obtenerResumenAvisosSla(signal), enabled: Boolean(habilitada && yo && !yo.demo),
    20	    refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
    21	}
    22	export function useEstadosSlaV2(ids: string[]) {
    23	  const { yo } = useAuth()
    24	  return useQuery({ queryKey: slaOperacionKeys.estado(yo?.id ?? null, ids),
    25	    queryFn: ({ signal }) => obtenerEstadosSlaV2(ids, signal), enabled: Boolean(yo && !yo.demo), refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
    26	}
    27	export function useModoSla() {
    28	  const { yo } = useAuth()
    29	  const consulta = useEstadosSlaV2([])
    30	  return { ...consulta, legado: Boolean(yo?.demo || (!consulta.error && consulta.data && consulta.data.modo !== 'activo')),
    31	    activo: Boolean(!yo?.demo && !consulta.error && consulta.data?.modo === 'activo') }
    32	}
    33	export function useColaSlaPagina(filtros: FiltrosSla, cursor: CursorSla | null, limite: number, habilitada: boolean) {
    34	  const { yo } = useAuth()
    35	  return useQuery({ queryKey: slaOperacionKeys.cola(yo?.id ?? null, filtros, cursor, limite),
    36	    queryFn: ({ signal }) => listarColaSla(filtros, cursor, limite, signal), enabled: Boolean(habilitada && yo && !yo.demo),
    37	    refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
    38	  })
    39	}
    40	
```

## `app/src/components/app/sla-operacion.tsx (boundary y cola del Seguimiento)`
```
     1	import { Fragment, useEffect, useId, useRef, useState, type ReactNode } from 'react'
     2	import { GuardadosSlaPendientes } from './guardados-sla-pendientes'
     3	import { useQueryClient } from '@tanstack/react-query'
     4	import { ChevronLeft, ChevronRight, RefreshCw, ArrowUpRight, ListFilter, X } from 'lucide-react'
     5	import './sla-operacion.css'
     6	import { CrmApiError } from '@/data/crm-api'
     7	import { Button } from '@/components/ui/button'
     8	import { Select } from '@/components/ui/select'
     9	import { useAuth } from '@/lib/auth-context'
    10	import { useCRMData, usePanelesActions } from '@/lib/store-context'
    11	import { ETAPA_INFO, ETAPAS } from '@/lib/tipos'
    12	import { slaOperacionKeys, useColaSlaPagina, useEstadosSlaV2, useModoSla } from '@/data/sla-operacion-queries'
    13	import { ACCIONES_SLA, MOTIVOS_REVISION_SLA, SENALES_SLA, fechaSla, puedeRegistrarGestionSla, textoAvisoSla, type AvisoSla, type CursorSla, type EstadoSlaV2, type FiltrosSla, type SenalSla } from '@/lib/sla-operacion'
    14	
    15	export function SlaOperacionBoundary({ children, legado }: { children: ReactNode; legado?: ReactNode }) {
    16	  const modo = useModoSla()
    17	  const { yo } = useAuth()
    18	  if (modo.legado) return legado ?? null
    19	  if (modo.error) return <FalloSla onReintentar={() => void modo.refetch()} />
    20	  if (!modo.activo) return <p role="status" className="rounded-xl border p-4 text-sm">Consultando el seguimiento comercial…</p>
    21	  return <Fragment key={`${yo?.id}|${yo?.rol}|${modo.data?.control_revision}`}>{children}</Fragment>
    22	}
    23	function FalloSla({ onReintentar }: { onReintentar: () => void }) {
    24	  return <div role="alert" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 p-4">
    25	    <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
    26	    <Button variant="outline" size="sm" onClick={onReintentar}><RefreshCw aria-hidden /> Reintentar</Button>
    27	  </div>
    28	}
    29	export function ColaSlaPanel() {
    30	  const { yo } = useAuth()
    31	  const { equipo } = useCRMData()
    32	  const { abrirLead } = usePanelesActions()
    33	  const [filtros, setFiltros] = useState<FiltrosSla>({ senal: 'pendientes', etapa: null, analista_id: null })
    34	  const [limite, setLimite] = useState(10)
    35	  const [abriendo, setAbriendo] = useState<string | null>(null)
    36	  const [errorApertura, setErrorApertura] = useState(false)
    37	  const [cursores, setCursores] = useState<(CursorSla | null)[]>([null])
    38	  const cursor = cursores[cursores.length - 1] ?? null
    39	  const consulta = useColaSlaPagina(filtros, cursor, limite, true)
    40	  const pagina = consulta.error ? undefined : consulta.data
    41	  const encabezado = useRef<HTMLHeadingElement>(null)
    42	  const queryClient = useQueryClient()
    43	  const prefijo = JSON.stringify(slaOperacionKeys.raiz()).slice(0, -1)
    44	  // Cada gestión confirmada invalida esta raíz: el orden anterior ya no sirve.
    45	  useEffect(() => queryClient.getQueryCache().subscribe((evento) => {
    46	    if (evento.type === 'updated' && evento.action.type === 'invalidate'
    47	      && JSON.stringify(evento.query.queryKey).startsWith(prefijo)) setCursores([null])
    48	  }), [prefijo, queryClient])
    49	  // Una frontera temporal o un cambio de cartera invalida la posición anterior.
    50	  useEffect(() => {
    51	    if (cursor && consulta.error instanceof CrmApiError && consulta.error.code === '22023') setCursores([null])
    52	  }, [cursor, consulta.error])
    53	  const esSupervisor = yo?.rol === 'supervisor' || yo?.rol === 'gerencia' || yo?.rol === 'directorio'
    54	  const id = useId()
    55	  function filtrar(cambio: Partial<FiltrosSla>) { setFiltros((actual) => ({ ...actual, ...cambio })); setCursores([null]) }
    56	  function navegar(siguiente: boolean) {
    57	    if (consulta.isFetching) return
    58	    if (siguiente && pagina?.cursor_siguiente) setCursores((actual) => [...actual, pagina.cursor_siguiente])
    59	    else if (!siguiente) setCursores((actual) => actual.length > 1 ? actual.slice(0, -1) : actual)
    60	    encabezado.current?.focus()
    61	  }
    62	  const reiniciar = () => { setCursores([null]); if (cursor === null) void consulta.refetch() }
    63	  async function abrirFicha(id: string) {
    64	    if (abriendo) return
    65	    setAbriendo(id)
    66	    setErrorApertura(false)
    67	    try {
    68	      if (await abrirLead(id) === false) setErrorApertura(true)
    69	    } catch {
    70	      setErrorApertura(true)
    71	    } finally {
    72	      setAbriendo(null)
    73	    }
    74	  }
    75	  const senales = SENALES_SLA.filter(([key]) => esSupervisor || (key !== 'por_repartir' && key !== 'revisiones'))
    76	    .map(([key, label]) => [key, pagina?.modelo_avisos === 3 && key === 'primera_atencion' ? 'Primera gestión pendiente' : label] as const)
    77	  const hayFiltros = filtros.senal !== 'pendientes' || filtros.etapa !== null || filtros.analista_id !== null
    78	  const limpiar = () => { setFiltros({ senal: 'pendientes', etapa: null, analista_id: null }); setCursores([null]); setErrorApertura(false) }
    79	  return <section className="sla-bandeja" aria-label="Seguimiento comercial">
    80	    <header className="sla-cabecera">
    81	      <div>
    82	        <h2 ref={encabezado} tabIndex={-1} className="sla-titulo">Seguimiento comercial</h2>
    83	        <p>{yo?.rol === 'gerencia' ? 'Las oportunidades de todo el equipo que necesitan atención.' : esSupervisor ? 'Los pendientes de tu equipo y los casos que necesitan tu decisión.' : 'Tus oportunidades pendientes, ordenadas para la próxima gestión.'}</p>
    84	      </div>
    85	      <Button variant="outline" size="sm" disabled={consulta.isFetching} onClick={reiniciar}><RefreshCw aria-hidden className={consulta.isFetching ? 'motion-safe:animate-spin' : ''} /> Actualizar</Button>
    86	    </header>
    87	
    88	    <div className="sla-prioridades" role="group" aria-label="Prioridades de seguimiento">
    89	      {senales.filter(([key]) => key !== 'todas' && key !== 'pendientes').map(([key, label]) => <button key={key} type="button"
    90	        aria-label={`${label} ${pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : 'sin confirmar'}`}
    91	        aria-pressed={filtros.senal === key} onClick={() => filtrar({ senal: key })}>
    92	        <span>{label}</span><strong>{pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : '—'}</strong>
    93	      </button>)}
    94	    </div>
    95	
    96	    <div className="sla-herramientas">
    97	      <div className="sla-todas"><button type="button" aria-pressed={filtros.senal === 'pendientes'} onClick={() => filtrar({ senal: 'pendientes' })}>Para atender ahora</button><button type="button" aria-pressed={filtros.senal === 'todas'} onClick={() => filtrar({ senal: 'todas' })}><ListFilter aria-hidden /> Todas las acciones</button></div>
    98	      <label htmlFor={`${id}-senal`} className="sla-mostrar">Mostrar
    99	        <Select id={`${id}-senal`} value={filtros.senal} onChange={(e) => filtrar({ senal: e.target.value as SenalSla })}>
   100	          {senales.map(([key, label]) => <option key={key} value={key}>{label}{key !== 'todas' && pagina ? ` (${pagina.totales[key]})` : ''}</option>)}
   101	        </Select>
   102	      </label>
   103	      <label htmlFor={`${id}-etapa`}>Etapa
   104	        <Select id={`${id}-etapa`} value={filtros.etapa ?? ''} onChange={(e) => filtrar({ etapa: e.target.value || null })}>
   105	          <option value="">Todas las etapas</option>{ETAPAS.map((etapa) => <option key={etapa.k} value={etapa.k}>{etapa.label}</option>)}
   106	        </Select>
   107	      </label>
   108	      {esSupervisor && <label htmlFor={`${id}-analista`}>Analista
   109	        <Select id={`${id}-analista`} value={filtros.analista_id ?? ''} onChange={(e) => filtrar({ analista_id: e.target.value || null })}>
   110	          <option value="">Todos los analistas</option>{equipo.filter((miembro) => miembro.activo && miembro.rol_crm === 'vendedor').map((miembro) => <option key={miembro.perfil_id} value={miembro.perfil_id}>{miembro.nombre_completo}</option>)}
   111	        </Select>
   112	      </label>}
   113	      {hayFiltros && <Button variant="ghost" size="sm" onClick={limpiar}><X aria-hidden /> Limpiar filtros</Button>}
   114	    </div>
   115	
   116	    {abriendo && <p role="status" className="sla-aviso">Abriendo ficha…</p>}
   117	    {errorApertura && <p role="alert" className="sla-aviso text-destructive">No se pudo abrir la ficha. Actualiza la lista o vuelve a intentarlo.</p>}
   118	    {consulta.error ? <div className="sla-estado"><FalloSla onReintentar={reiniciar} />{cursores.length > 1 && <Button variant="outline" size="sm" onClick={() => setCursores([null])}>Volver a la primera página</Button>}</div>
   119	      : !pagina ? <p role="status" className="sla-estado">Cargando oportunidades…</p>
   120	      : pagina.modo !== 'activo' ? <p role="status" className="sla-estado">Las reglas operativas están desactivadas. Actualiza la pantalla para ver el modo vigente.</p>
```

## `app/src/data/use-cola-accion-operativa.ts`
```
     1	import { useMemo } from 'react'
     2	import { useAhora } from '@/lib/ahora'
     3	import { useAuth } from '@/lib/auth-context'
     4	import {
     5	  LIMITE_COLA_ACCION,
     6	  colaAccionDesdeAmbito,
     7	  mapearColaAccion,
     8	  type ColaAccionOperativa,
     9	} from '@/lib/cola-accion'
    10	import type { EstadoSlaLead } from '@/lib/sla-versionado'
    11	import type { Actividad, Lead, Tarea } from '@/lib/tipos'
    12	import { useColaAccion } from './crm-queries'
    13	
    14	export interface ColaAccionOperativaHook {
    15	  /** Cola operativa (RPC en real, espejo vivo en demo); null mientras carga o si el RPC cayó. */
    16	  cola: ColaAccionOperativa | null
    17	  cargando: boolean
    18	  /** true mientras un fetch del RPC está EN VUELO (primera carga o refetch):
    19	   *  `cola` puede ser todavía la foto anterior, y quien PERSISTA algo derivado
    20	   *  de ella (la visita de F4.3) debe esperar al payload fresco. En demo el
    21	   *  espejo es síncrono: siempre false. */
    22	  enVuelo: boolean
    23	  error: unknown
    24	  recargar: () => Promise<void>
    25	}
    26	
    27	/**
    28	 * Une crm.cola_accion_fn con su espejo demo (F1b). En sesión real el servidor
    29	 * decide buckets/severidad/orden y este hook solo re-une cada item con el Lead
    30	 * COMPLETO del ámbito en memoria (hover, drawer y cronómetros conservan toda
    31	 * la ficha hasta F3) y redacta los motivos. En demo, colaDe sobre el estado
    32	 * VIVO — mover un lead recoloca su fila al instante.
    33	 *
    34	 * `indiceSla` solo alimenta el espejo demo: en real esos vencimientos ya
    35	 * vienen resueltos dentro del payload (la pantalla puede dejar de pedir el
    36	 * RPC de estado SLA si no lo usa para nada más).
    37	 */
    38	export function useColaAccionOperativa(
    39	  leads: readonly Lead[],
    40	  actividades: readonly Actividad[],
    41	  tareas: readonly Tarea[],
    42	  indiceSla?: ReadonlyMap<string, EstadoSlaLead>,
    43	  habilitado = true,
    44	  limite: number = LIMITE_COLA_ACCION,
    45	): ColaAccionOperativaHook {
    46	  const { yo } = useAuth()
    47	  const sesionReal = Boolean(habilitado && yo && !yo.demo)
    48	  const consulta = useColaAccion(sesionReal, limite)
    49	  const porId = useMemo(() => new Map(leads.map((l) => [l.id, l])), [leads])
    50	  // Reloj vivo (tick por minuto): el espejo demo debe recolocar buckets al
    51	  // pasar el tiempo, como hacía colaDe en las pantallas antes de F1b.
    52	  const ahora = useAhora()
    53	  const cola = useMemo(
    54	    () => {
    55	      if (!habilitado || !yo) return null
    56	      if (yo.demo) {
    57	        return colaAccionDesdeAmbito(leads, actividades, tareas, ahora, indiceSla, limite)
    58	      }
    59	      // Fail-closed TAMBIÉN en refetch: TanStack conserva `data` cuando un
    60	      // refetch falla, y servir esa foto vieja mientras el banner promete
    61	      // «—» sería mentir dos veces (hallazgo ALTA de la revisión Codex).
    62	      if (consulta.error) return null
    63	      if (!consulta.data) return null
    64	      // La foto envejece contra el reloj LOCAL: dataUpdatedAt es el instante
    65	      // (de este navegador) en que llegó el payload, así el desfase con el
    66	      // reloj del servidor no infla los números. El clamp cubre el tick de
    67	      // useAhora que aún no corrió tras un refetch recién aterrizado.
    68	      const derivaDias = Math.max(0, (ahora - consulta.dataUpdatedAt) / 86_400_000)
    69	      return mapearColaAccion(consulta.data, (id) => porId.get(id), derivaDias)
    70	    },
    71	    [actividades, ahora, consulta.data, consulta.dataUpdatedAt, consulta.error, habilitado, indiceSla, leads, limite, porId, tareas, yo],
    72	  )
    73	
    74	  return {
    75	    cola,
    76	    cargando: sesionReal && consulta.isPending,
    77	    enVuelo: sesionReal && consulta.isFetching,
    78	    error: sesionReal ? consulta.error : null,
    79	    recargar: async () => { await consulta.refetch() },
    80	  }
    81	}
```

## `app/src/lib/alertas-provider.tsx (campana; usa useResumenAvisosSla)`
```
     1	import {
     2	  useCallback,
     3	  useMemo,
     4	  useState,
     5	  type JSX,
     6	  type ReactNode,
     7	} from 'react'
     8	import { useQueryClient } from '@tanstack/react-query'
     9	import {
    10	  CrmApiError,
    11	  mensajeDeError,
    12	  reconocerAlertaSupervisor,
    13	} from '@/data/crm-api'
    14	import {
    15	  crmQueryKeys,
    16	  useMetricasConversiones,
    17	  useReconocimientosAlertas,
    18	  useRecordatoriosDisponibilidad,
    19	} from '@/data/crm-queries'
    20	import { derivarAlertasRecordatorios } from '@/lib/recordatorios-disponibilidad'
    21	import {
    22	  aplicarReconocimientos,
    23	  type AccionReconocimiento,
    24	  type AsientoReconocimiento,
    25	} from '@/lib/reconocimientos-alertas'
    26	import { fechaLima } from '@/lib/agenda-derivada'
    27	import {
    28	  derivarAlertasSupervisor,
    29	  derivarAlertasVendedor,
    30	  type AlertaCRM,
    31	} from '@/lib/alertas'
    32	import {
    33	  derivarAlertasGerencia,
    34	  LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL,
    35	  MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR,
    36	  periodoAnteriorComparable,
    37	  type AlertaGerencia,
    38	} from '@/lib/alertas-gerencia'
    39	import { AlertasCRMContext, type EstadoAlertasCRM } from '@/lib/alertas-context'
    40	import { useAuth } from '@/lib/auth-context'
    41	import { funcionesLeadsVisibles } from '@/lib/config'
    42	import {
    43	  cumplimientoMetasConversionEquipoDemo,
    44	  metasConversionEquipoDemo,
    45	  metricasConversionesDemo,
    46	} from '@/lib/demo-inteligencia-comercial'
    47	import { useAhora } from '@/lib/ahora'
    48	import { useCRMData } from '@/lib/store-context'
    49	import { administraSoloRolesCrm, type Rol } from '@/lib/roles'
    50	import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
    51	import { useResumenAvisosSla } from '@/data/sla-operacion-queries'
    52	import { alertaResumenSla } from '@/lib/sla-avisos-presentacion'
    53	import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
    54	import { tituloCorte, horaCorte } from '@/lib/gestion-diaria-avisos'
    55	import { alertaDiariaAAlertaCRM } from '@/lib/gestion-diaria-alertas'
    56	
    57	function adaptarAlertaGerencial(alerta: AlertaGerencia, periodo: { desde: string; hasta: string }): AlertaCRM {
    58	  if (alerta.tipo === 'bajo_meta_conversion') {
    59	    // H10/H21 (F3): el aviso dice su VENTANA (mes en curso — la misma cifra
    60	    // ponderada que pinta el ranking al que manda) y su UMBRAL de muestra;
    61	    // un corte que no se dice hace parecer arbitraria la alerta que aparece
    62	    // y sospechosa la que no.
    63	    const muestra = alerta.muestra == null
    64	      ? ''
    65	      : ` · base de conversión: ${alerta.muestra} (se avisa desde ${MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR})`
    66	    return {
    67	      id: alerta.id,
    68	      tipo: alerta.tipo,
    69	      severidad: alerta.severidad,
    70	      alcance: 'empresa',
    71	      titulo: 'Conversión bajo meta',
    72	      detalle: `${alerta.responsable}: ${alerta.actual ?? alerta.valor}% frente a ${alerta.objetivo ?? '—'}% · brecha ${alerta.brechaPp ?? '—'} pp · mes en curso${muestra}`,
    73	      responsableId: alerta.responsableId,
    74	      responsable: alerta.responsable,
    75	      valor: alerta.valor,
    76	      destino: {
    77	        vista: 'ranking-vendedores',
    78	        etiqueta: 'Ver ranking',
    79	        periodo,
    80	      },
    81	    }
    82	  }
    83	
    84	  // H11: desde F3 esta cifra es la del NÚCLEO (la misma que HOY/Ranking y que
    85	  // su vecina individual), comparada contra el mismo corte del mes anterior.
    86	  const muestra = alerta.muestra == null
    87	    ? ''
    88	    : ` · base de conversión: ${alerta.muestra} (se compara desde ${LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL})`
    89	  return {
    90	    id: alerta.id,
    91	    tipo: alerta.tipo,
    92	    severidad: alerta.severidad,
    93	    alcance: 'empresa',
    94	    titulo: 'Cayó la conversión general',
    95	    detalle: `${alerta.actual ?? alerta.valor}% frente a ${alerta.objetivo ?? '—'}% del mismo corte del mes anterior · caída ${alerta.brechaPp ?? '—'} pp · cifra del núcleo${muestra}`,
    96	    responsableId: null,
    97	    responsable: 'Equipo comercial',
    98	    valor: alerta.valor,
    99	    destino: {
   100	      vista: 'conversiones',
   101	      etiqueta: 'Ver conversión',
   102	      periodo,
   103	    },
   104	  }
   105	}
   106	
   107	function esRolOperativo(rol: Rol | null): rol is 'vendedor' | 'supervisor' {
   108	  return rol === 'vendedor' || rol === 'supervisor'
   109	}
   110	
   111	export function AlertasCRMProvider({ children }: { children: ReactNode }): JSX.Element {
   112	  const { yo } = useAuth()
   113	  const cortes = useGestionDiariaAvisos()
   114	  const diarias = cortes?.datos?.diarias
   115	  const {
   116	    ambito,
   117	    actividadesDelAmbito,
   118	    tareas,
   119	    objetivos,
   120	    objetivosError,
   121	    cumplimientoMetas,
   122	    cumplimientoMetasError,
   123	    recargar,
   124	  } = useCRMData()
   125	  const ahora = useAhora()
   126	  const [actualizandoOperativo, setActualizandoOperativo] = useState(false)
   127	  const rol = yo?.rol ?? null
   128	  const soloRoles = administraSoloRolesCrm(yo)
   129	  const sesionAvisosReal = Boolean(yo && !yo.demo && !soloRoles
   130	    && (rol === 'vendedor' || rol === 'supervisor' || rol === 'gerencia' || rol === 'directorio')
   131	    && funcionesLeadsVisibles(yo.demo, rol))
   132	  const consultarResumen = sesionAvisosReal && !(rol === 'supervisor' && diarias)
   133	  const resumenSla = useResumenAvisosSla(consultarResumen)
   134	  // Un fallo o modo sin confirmar no reactiva los cálculos anteriores.
   135	  const legado = Boolean(yo?.demo || (diarias ? diarias.modo_sla !== 'activo'
   136	    : !resumenSla.error && resumenSla.data && resumenSla.data.modo !== 'activo'))
   137	  const estadoSla = useEstadoSlaOperativo(
   138	    ambito.leads,
   139	    actividadesDelAmbito,
   140	    !soloRoles && esRolOperativo(rol) && legado,
   141	  )
   142	  const diaLima = fechaLima(ahora)
   143	  const periodoActual = useMemo(
   144	    () => ({ desde: `${diaLima.slice(0, 7)}-01`, hasta: diaLima }),
   145	    [diaLima],
   146	  )
   147	  const periodoAnterior = useMemo(() => periodoAnteriorComparable(diaLima), [diaLima])
   148	  const sesionGerenciaReal = Boolean(yo && !yo.demo && rol === 'gerencia')
   149	  // F3 «Recordar»: SOLO el analista real tiene recordatorios (la RLS es
   150	  // owner-only y el rol es la antesala de la toma). En demo no existen. Y solo
   151	  // con las funciones de leads VISIBLES (Codex F3-R2, espejo de vistas.ts): la
   152	  // campana vive tras ese gate — consultar con el gate cerrado sería trabajo
   153	  // invisible y una insignia que el analista no puede ni abrir.
   154	  const sesionVendedorReal = Boolean(
   155	    yo && !yo.demo && rol === 'vendedor' && !soloRoles
   156	    && funcionesLeadsVisibles(yo.demo, rol),
   157	  )
   158	  const recordatorios = useRecordatoriosDisponibilidad(sesionVendedorReal)
   159	  // F4 «sin ruido»: el libro de reconocimientos es del SUPERVISOR real, y
   160	  // solo con la campana pintada (el mismo gate de leads que usa vistas.ts
   161	  // para #/alertas): consultar el libro con la campana apagada sería trabajo
   162	  // invisible — la misma regla que los recordatorios del analista.
   163	  const sesionSupervisorReal = Boolean(
   164	    yo && !yo.demo && rol === 'supervisor' && !soloRoles
   165	    && funcionesLeadsVisibles(yo.demo, rol),
   166	  )
   167	  const usaLibro = legado || Boolean(diarias)
   168	  const reconocimientos = useReconocimientosAlertas(sesionSupervisorReal && usaLibro)
   169	  // Espejo LOCAL para la demo: mismo contrato y misma lógica pura, sin
   170	  // servidor — el supervisor de demo prueba el circuito completo y su libro
   171	  // muere con la sesión.
   172	  const [asientosDemo, setAsientosDemo] = useState<AsientoReconocimiento[]>([])
   173	  const queryClient = useQueryClient()
   174	
   175	  // Solo Gerencia consulta conversiones globales. Analista y supervisor derivan
   176	  // sus pendientes de los datos ya recortados por RLS que carga el store.
   177	  const conversionAnterior = useMetricasConversiones(
   178	    sesionGerenciaReal,
   179	    periodoAnterior.desde,
   180	    periodoAnterior.hasta,
   181	  )
   182	  const conversionActual = useMetricasConversiones(
   183	    sesionGerenciaReal,
   184	    periodoActual.desde,
   185	    periodoActual.hasta,
   186	  )
   187	
   188	  const metasGerencia = useMemo(
   189	    () => yo?.demo ? metasConversionEquipoDemo() : (objetivos.porVendedor ?? {}),
   190	    [objetivos.porVendedor, yo?.demo],
   191	  )
   192	  const cumplimientoGerencia = useMemo(
   193	    () => yo?.demo
   194	      ? cumplimientoMetasConversionEquipoDemo().porVendedor
   195	      : (cumplimientoMetas?.porVendedor ?? {}),
   196	    [cumplimientoMetas?.porVendedor, yo?.demo],
   197	  )
   198	  const conversionGerencia = useMemo(
   199	    () => yo?.demo
   200	      ? metricasConversionesDemo(periodoActual.desde, periodoActual.hasta)
   201	      : conversionActual.data,
   202	    [conversionActual.data, periodoActual.desde, periodoActual.hasta, yo?.demo],
   203	  )
   204	
   205	  const alertas = useMemo<AlertaCRM[]>(() => {
   206	    if (!yo || soloRoles) return []
   207	    const operativas = sesionAvisosReal && !resumenSla.error && resumenSla.data?.modo === 'activo'
   208	      ? alertaResumenSla(resumenSla.data, yo.id, rol) : []
   209	    if (rol === 'vendedor') {
   210	      return [
   211	        // F3: los recordatorios VENCIDOS primero — son acción inmediata y
   212	        // barata («verifica si ya está libre»); los vigentes no suenan.
   213	        ...derivarAlertasRecordatorios(recordatorios.data ?? [], ahora),
   214	        // Fase 3 «sin topes»: el arranque real ya no baja el registro de
   215	        // actividades, así que las alertas LEGADO (derivadas de él) solo se
   216	        // pueden calcular en demo. En sesión real con el modo SLA apagado no
   217	        // se inventan alertas «sin contacto» sobre una lista vacía: se callan.
   218	        ...(legado && yo.demo ? derivarAlertasVendedor({
   219	          vendedorId: yo.id,
   220	          leads: ambito.leads,
   221	          actividades: actividadesDelAmbito,
   222	          tareas,
   223	          ahora,
   224	          estadosSla: estadoSla.indice,
   225	        }) : operativas),
   226	      ]
   227	    }
   228	    if (rol === 'supervisor') {
   229	      if (diarias) return diarias.alertas.map((a) => alertaDiariaAAlertaCRM(a, yo.id, cortes?.datos?.contexto))
   230	      return legado && yo.demo ? derivarAlertasSupervisor({
   231	        supervisorId: yo.id,
   232	        leads: ambito.leads,
   233	        actividades: actividadesDelAmbito,
   234	        tareas,
   235	        vendedores: ambito.vendedores,
   236	        ahora,
   237	        estadosSla: estadoSla.indice,
   238	      }) : operativas
   239	    }
   240	    if (rol !== 'gerencia') return operativas
   241	
   242	    return [...operativas, ...derivarAlertasGerencia({
   243	      conversiones: conversionGerencia,
   244	      conversionesAnteriores: yo.demo ? undefined : conversionAnterior.data,
   245	      metasVendedores: metasGerencia,
   246	      cumplimientosVendedores: cumplimientoGerencia,
   247	      objetivosError,
   248	      cumplimientoError: cumplimientoMetasError,
   249	      diaDelMes: Number(diaLima.slice(8, 10)),
   250	      // Los días del mes salen de la fecha de LIMA, no del reloj de la máquina:
   251	      // el día 0 del mes siguiente es el último del actual, y en UTC eso puede
   252	      // caer en otro mes. Febrero corre el último corte a su día 28 o 29.
   253	      diasDelMes: new Date(
   254	        Number(diaLima.slice(0, 4)),
   255	        Number(diaLima.slice(5, 7)),
   256	        0,
   257	      ).getDate(),
   258	    }).map((alerta) => adaptarAlertaGerencial(alerta, periodoActual))]
   259	  }, [
   260	    legado,
   261	    resumenSla.data,
   262	    resumenSla.error,
   263	    sesionAvisosReal,
   264	    diarias,
   265	    cortes?.datos?.contexto,
   266	    actividadesDelAmbito,
   267	    ambito.leads,
   268	    ambito.vendedores,
   269	    ahora,
   270	    conversionAnterior.data,
   271	    conversionGerencia,
   272	    diaLima,
   273	    estadoSla.indice,
   274	    cumplimientoGerencia,
   275	    cumplimientoMetasError,
   276	    metasGerencia,
   277	    objetivosError,
   278	    periodoActual,
   279	    recordatorios.data,
   280	    rol,
   281	    tareas,
   282	    yo,
   283	    soloRoles,
   284	  ])
   285	
   286	  // F4 (Codex #5): con el ámbito EN el tope local, la foto de miembros puede
   287	  // estar incompleta — una foto trunca que el servidor acepta callaría al
   288	  // lead 2001. Sin foto confiable, reconocer se desactiva Y el libro se
   289	  // ignora: la comparación de «empeoró» tampoco es de fiar.
   290	  // Fase 4e «sin topes»: ya no hay foto de leads del ámbito; las derivaciones
   291	  // legado por actividad solo viven en demo (Fase 3), así que la «foto» es de
   292	  // fiar salvo en sesión real con el modo SLA apagado (donde no se calcula).
   293	  const fotoConfiable = Boolean(diarias) || !legado || Boolean(yo?.demo)
   294	
   295	  // F4: el libro atenúa (reconocer) u oculta (posponer) las alertas AGRUPADAS
   296	  // del supervisor. Con el libro caído se aplica []: TODO suena — un fallo de
   297	  // lectura jamás se convierte en silencio (y el error se dice abajo).
   298	  // `error` manda sobre `data` (bloqueante Codex #1): TanStack CONSERVA los
   299	  // datos del último fetch bueno cuando un refetch falla, y aplicar esos
   300	  // asientos viejos con el libro caído sería exactamente el silencio indebido.
   301	  const { visibles, pendientes, pospuestas } = useMemo(() => {
   302	    if (!yo || rol !== 'supervisor' || !usaLibro) {
   303	      return { visibles: alertas, pendientes: alertas.length, pospuestas: 0 }
   304	    }
   305	    if (!fotoConfiable) {
   306	      return {
   307	        visibles: alertas.map(({ miembros: _foto, ...resto }) => resto),
   308	        pendientes: alertas.length,
   309	        pospuestas: 0,
   310	      }
   311	    }
   312	    const asientos = yo.demo
   313	      ? asientosDemo
   314	      : (reconocimientos.error ? [] : (reconocimientos.data ?? []))
   315	    return aplicarReconocimientos(alertas, asientos, ahora)
   316	  }, [ahora, alertas, asientosDemo, fotoConfiable, usaLibro, reconocimientos.data, reconocimientos.error, rol, yo])
   317	
   318	  // Asienta en el libro y refresca la query; el toast y el foco son de la
   319	  // pantalla. En demo escribe el espejo local con secuencia monotónica —
   320	  // el MISMO contrato que la identity del servidor.
   321	  const reconocer = useCallback(async (
   322	    alerta: AlertaCRM,
   323	    accion: AccionReconocimiento,
   324	    hasta: string | null,
   325	  ): Promise<void> => {
   326	    if (!yo || rol !== 'supervisor' || alerta.miembros == null) return
   327	    const miembros = [...alerta.miembros]
   328	    if (yo.demo) {
   329	      setAsientosDemo((previos) => [...previos, {
   330	        id: crypto.randomUUID(),
   331	        alerta_id: alerta.id,
   332	        accion,
   333	        miembros,
   334	        severidad: alerta.severidad,
   335	        hasta,
   336	        creado_en: new Date().toISOString(),
   337	        secuencia: (previos[previos.length - 1]?.secuencia ?? 0) + 1,
   338	      }])
   339	      return
   340	    }
   341	    await reconocerAlertaSupervisor(yo.id, alerta.id, accion, miembros, alerta.severidad, hasta)
   342	    // throwOnError (Codex #4): sin él, un refetch caído se ABSORBE, la
   343	    // promesa resuelve y la pantalla cantaría éxito con la fila vieja en
   344	    // pantalla. El asiento SÍ quedó: el mensaje lo distingue del fallo real.
   345	    try {
   346	      await queryClient.invalidateQueries(
   347	        { queryKey: crmQueryKeys.reconocimientosAlertas() },
   348	        { throwOnError: true },
   349	      )
   350	    } catch {
   351	      throw new CrmApiError(
   352	        'Quedó asentado, pero la lista no se pudo refrescar: usa Actualizar.',
   353	        'RECONOCIMIENTOS_REFRESCO',
   354	      )
   355	    }
   356	  }, [queryClient, rol, yo])
   357	
   358	  const errores = useMemo(() => {
   359	    if (yo?.demo || soloRoles) return []
   360	    const mensajes = [
   361	      // Fase 3 «sin topes»: sin el registro de actividades del ámbito (ya no se
   362	      // descarga), las alertas LEGADO por actividad no pueden calcularse en
   363	      // sesión real; con el modo SLA apagado la campana se calla y lo DICE.
   364	      // (La demo ya salió arriba; un rol no nulo implica sesión.)
   365	      legado && (rol === 'vendedor' || rol === 'supervisor')
   366	        ? 'Las alertas por actividad de leads necesitan el modo SLA activo: el CRM ya no descarga el registro de actividades del ámbito.'
   367	        : null,
   368	      rol === 'gerencia' && conversionActual.error
   369	        ? mensajeDeError(conversionActual.error, 'No se pudo calcular la conversión actual.')
   370	        : null,
   371	      rol === 'gerencia' && conversionAnterior.error
   372	        ? mensajeDeError(conversionAnterior.error, 'No se pudo comparar con el mes anterior.')
   373	        : null,
   374	      rol === 'gerencia' && objetivosError
   375	        ? 'No se pudieron cargar las metas individuales.'
   376	        : null,
   377	      rol === 'gerencia' && cumplimientoMetasError
   378	        ? 'No se pudo calcular el cumplimiento confirmado.'
   379	        : null,
   380	      consultarResumen && resumenSla.error
   381	        ? 'No se pudieron confirmar los avisos de seguimiento. Pulsa Actualizar.'
   382	        : null,
   383	      legado && esRolOperativo(rol) && estadoSla.error
   384	        ? mensajeDeError(
   385	            estadoSla.error,
   386	            'No se pudo verificar el reloj SLA; se ocultaron las escalaciones temporales.',
   387	          )
   388	        : null,
   389	      // F3.1: un fallo al listar recordatorios NO puede ser mudo — la campana
   390	      // omitiría los «Revisar contacto» y el analista leería «sin pendientes»
   391	      // como verdad (hallazgo convergente de la auditoría del 18/08).
   392	      sesionVendedorReal && recordatorios.error
   393	        ? mensajeDeError(
   394	            recordatorios.error,
   395	            'No se pudieron cargar tus recordatorios de contacto.',
   396	          )
   397	        : null,
   398	      // F4: un libro ilegible tampoco es mudo — sin él las alertas suenan
   399	      // COMPLETAS (reconocimientos incluidos) y el supervisor debe saber por
   400	      // qué su campana volvió a llenarse.
   401	      sesionSupervisorReal && usaLibro && reconocimientos.error
   402	        ? mensajeDeError(
   403	            reconocimientos.error,
   404	            'No se pudieron leer tus reconocimientos; las alertas se muestran completas.',
   405	          )
   406	        : null,
   407	      // F4 (Codex #5): la foto trunca se DICE, no se disimula quitando botones.
   408	      rol === 'supervisor' && !soloRoles && !fotoConfiable
   409	        ? 'Reconocer y Posponer quedan desactivados sin el modo SLA activo: el CRM ya no descarga la foto de leads del ámbito.'
   410	        : null,
   411	    ]
   412	    return mensajes.filter((mensaje): mensaje is string => Boolean(mensaje))
   413	  }, [
   414	    legado,
   415	    usaLibro,
   416	    consultarResumen,
   417	    resumenSla.error,
   418	    conversionActual.error,
   419	    conversionAnterior.error,
   420	    objetivosError,
   421	    cumplimientoMetasError,
   422	    estadoSla.error,
   423	    fotoConfiable,
   424	    reconocimientos.error,
   425	    recordatorios.error,
   426	    rol,
   427	    sesionSupervisorReal,
   428	    sesionVendedorReal,
   429	    soloRoles,
   430	    yo?.demo,
   431	  ])
   432	
   433	  const cargandoGerencia = sesionGerenciaReal && (
   434	    conversionActual.isPending
   435	    || conversionActual.isFetching
   436	    || conversionAnterior.isPending
   437	    || conversionAnterior.isFetching
   438	  )
   439	
   440	  const reintentar = useCallback(() => {
   441	    if (soloRoles) return
   442	    cortes?.recargar()
   443	    if (consultarResumen) void resumenSla.refetch()
   444	    // La fuente diaria ya incluye los pendientes completos. Actualizar esta
   445	    // superficie solo necesita cortes y libro, no descargar el store del CRM.
   446	    if (sesionSupervisorReal && diarias) {
   447	      void reconocimientos.refetch()
   448	      return
   449	    }
   450	    if (rol === 'gerencia' && !yo?.demo) {
   451	      void conversionActual.refetch()
   452	      void conversionAnterior.refetch()
   453	      // H10 (F3): «Actualizar» converge TODO lo que alimenta la campana de
   454	      // gerencia — también metas y cumplimiento (la alerta individual), no
   455	      // solo cuando fallaron. Sin esto, la individual vivía congelada desde
   456	      // el arranque salvo error.
   457	      void recargar()
   458	      return
   459	    }
   460	    if (esRolOperativo(rol) && !yo?.demo) {
   461	      setActualizandoOperativo(true)
   462	      void Promise.all([
   463	        recargar(),
   464	        estadoSla.error ? estadoSla.recargar() : Promise.resolve(),
   465	        // F3.1: Reintentar también reintenta los recordatorios caídos.
   466	        sesionVendedorReal && recordatorios.error
   467	          ? recordatorios.refetch()
   468	          : Promise.resolve(),
   469	        // F4 (Codex #3): Actualizar refresca el libro SIEMPRE (no solo caído)
   470	        // — es la vía manual de converger con lo asentado en otra pestaña.
   471	        sesionSupervisorReal && usaLibro
   472	          ? reconocimientos.refetch()
   473	          : Promise.resolve(),
   474	      ]).finally(() => setActualizandoOperativo(false))
   475	    }
   476	  }, [
   477	    cortes,
   478	    usaLibro,
   479	    diarias,
   480	    consultarResumen,
   481	    resumenSla,
   482	    conversionActual,
   483	    conversionAnterior,
   484	    recargar,
   485	    reconocimientos,
   486	    recordatorios,
   487	    rol,
   488	    sesionSupervisorReal,
   489	    sesionVendedorReal,
   490	    soloRoles,
   491	    estadoSla,
   492	    yo?.demo,
   493	  ])
   494	
   495	  const cargando = cargandoGerencia
   496	    || actualizandoOperativo
   497	    || (consultarResumen && (resumenSla.isPending || resumenSla.isFetching))
   498	    || (legado && !soloRoles && esRolOperativo(rol) && estadoSla.cargando)
   499	    // isPending sería true PERPETUO con la query deshabilitada — el AND con
   500	    // sesionVendedorReal (la misma condición de enabled) lo impide.
   501	    || (sesionVendedorReal && (recordatorios.isPending || recordatorios.isFetching))
   502	    || (sesionSupervisorReal && usaLibro && (reconocimientos.isPending || reconocimientos.isFetching))
   503	  const alertasCortes = useMemo<AlertaCRM[]>(() => (cortes?.datos?.alertas ?? []).map((aviso) => ({
   504	    id: aviso.id, tipo: aviso.tipo, corte: aviso, severidad: 'atencion', alcance: 'equipo',
   505	    titulo: tituloCorte(aviso),
   506	    detalle: `${horaCorte(aviso.corte_en)} Lima · ${aviso.miembros.map((m) => `${m.nombre}: ${m.llamadas} de ${m.objetivo} llamadas`).join('; ')}`,
   507	    responsableId: yo?.id ?? null, responsable: 'Mi equipo', valor: aviso.miembros.length,
   508	    destino: { vista: 'gestion-diaria', etiqueta: 'Revisar equipo' },
   509	  })), [cortes?.datos, yo?.id])
   510	  const valor = useMemo<EstadoAlertasCRM>(() => ({
   511	    alertas: [...alertasCortes, ...visibles],
   512	    pendientes: pendientes + alertasCortes.filter((a) => a.corte?.estado === 'pendiente').length,
   513	    pospuestas,
   514	    rol,
   515	    cargando: cargando || Boolean(cortes?.cargando),
   516	    errores: cortes?.error ? [...errores, 'No se pudieron confirmar los avisos de Gestión Diaria. Pulsa Actualizar.'] : errores,
   517	    generadoEn: diarias ? cortes!.datos!.generado_en : sesionAvisosReal && !legado ? (resumenSla.data?.calculado_en ?? null) : rol === 'gerencia'
   518	      ? (conversionGerencia?.generado_en ?? null)
   519	      : new Date(ahora).toISOString(),
   520	    reintentar,
   521	    reconocer,
   522	  }), [
   523	    alertasCortes,
   524	    diarias,
   525	    cortes,
   526	    legado,
   527	    resumenSla.data?.calculado_en,
   528	    sesionAvisosReal,
   529	    visibles,
   530	    pendientes,
   531	    pospuestas,
   532	    ahora,
   533	    cargando,
   534	    conversionGerencia?.generado_en,
   535	    errores,
   536	    reconocer,
   537	    reintentar,
   538	    rol,
   539	  ])
   540	
   541	  return <AlertasCRMContext.Provider value={valor}>{children}</AlertasCRMContext.Provider>
   542	}
```

## `supabase/migrations/20260907212612_crm_sla_avisos_por_accion_y_rol.sql — crm.cola_accion_v2_fn (lógica = viva)`
```
   373	CREATE OR REPLACE FUNCTION crm.cola_accion_v2_fn(p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb)
   374	 RETURNS jsonb
   375	 LANGUAGE plpgsql
   376	 STABLE SECURITY DEFINER
   377	 SET search_path TO ''
   378	AS $function$
   379	declare
   380	  v_datos jsonb;v_totales jsonb;v_total integer;v_items jsonb;v_filtradas jsonb;
   381	  v_filtros jsonb;v_contexto text;v_prioridad integer;v_referencia timestamptz;v_lead uuid;
   382	  v_restantes integer;v_anteriores integer;v_siguiente jsonb;v_ultima jsonb;
   383	begin
   384	  if p_limite is null or p_limite not between 1 and 200
   385	    or private.sla_filtros_cola_validos(p_senal,p_etapa) is not true then
   386	    raise exception 'Filtros SLA invalidos o limite fuera de 1 a 200' using errcode='22023';
   387	  end if;
   388	  -- La ventana resuelve autoridad, hechos y reloj. Los filtros solo reducen
   389	  -- las filas recibidas; un cursor es posicion de lectura, nunca autoridad.
   390	  v_datos:=private.sla_operacion_autorizada(null,true);
   391	  v_filtros:=jsonb_build_object('senal',p_senal,'etapa',p_etapa,'analista_id',p_analista_id);
   392	  v_contexto:=md5(jsonb_build_object('version',2,'modelo_avisos',v_datos->'modelo_avisos','ambito',v_datos->'contexto_ambito',
   393	    'filtros',v_filtros,'limite',p_limite,'modo',v_datos->'modo',
   394	    'orden',(select md5(coalesce(jsonb_agg(jsonb_build_array(f.value#>>'{lead,id}',
   395	      f.value->'accion',f.value->'accion_pendiente',f.value->'senales')
   396	      order by f.value#>>'{lead,id}'),'[]'::jsonb)::text)
   397	      from jsonb_array_elements(v_datos->'filas') f),
   398	    'revision',v_datos->'control_revision','politica',v_datos->'politica_operativa_id')::text);
   399	  if p_cursor is not null then
   400	    if jsonb_typeof(p_cursor)<>'object' then
   401	      raise exception 'Cursor SLA invalido' using errcode='22023';
   402	    end if;
   403	    if (select count(*) from jsonb_object_keys(p_cursor))<>5
   404	      or not p_cursor ?& array['version','contexto','prioridad','referencia_en','lead_id']
   405	      or p_cursor->'version'<>'1'::jsonb
   406	      or jsonb_typeof(p_cursor->'contexto')<>'string'
   407	      or jsonb_typeof(p_cursor->'prioridad')<>'number'
   408	      or jsonb_typeof(p_cursor->'referencia_en') not in ('string','null')
   409	      or jsonb_typeof(p_cursor->'lead_id')<>'string' then
   410	      raise exception 'Cursor SLA invalido' using errcode='22023';
   411	    end if;
   412	    if p_cursor->>'contexto' is distinct from v_contexto then
   413	      raise exception 'Cursor incompatible; reinicia la paginacion' using errcode='22023';
   414	    end if;
   415	    begin
   416	      v_prioridad:=(p_cursor->>'prioridad')::integer;
   417	      v_referencia:=(p_cursor->>'referencia_en')::timestamptz;
   418	      v_lead:=(p_cursor->>'lead_id')::uuid;
   419	      if (p_cursor->>'prioridad') !~ '^[0-9]+$'
   420	        or v_prioridad not in (0,10,20,30,40,50,60,70)
   421	        or v_lead is null or (v_referencia is not null and not isfinite(v_referencia)) then
   422	        raise exception 'Cursor SLA invalido' using errcode='22023';
   423	      end if;
   424	    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then
   425	      raise exception 'Cursor SLA invalido' using errcode='22023';
   426	    end;
   427	  end if;
   428	  select coalesce(jsonb_agg(f.value),'[]'::jsonb) into v_filtradas
   429	  from jsonb_array_elements(v_datos->'filas') f
   430	  where (p_etapa is null or f.value#>>'{lead,etapa}'=p_etapa)
   431	    and (p_analista_id is null or f.value#>>'{lead,analista_id}'=p_analista_id::text);
   432	  select jsonb_build_object(
   433	    'pendientes',count(*) filter (where (f.value#>>'{senales,pendientes}')::boolean),
   434	    'primera_atencion',count(*) filter (where (f.value#>>'{senales,primera_atencion}')::boolean),
   435	    'tareas_vencidas',count(*) filter (where (f.value#>>'{senales,tareas_vencidas}')::boolean),
   436	    'seguimientos_pendientes',count(*) filter (where (f.value#>>'{senales,seguimientos_pendientes}')::boolean),
   437	    'revisiones',count(*) filter (where (f.value#>>'{senales,revisiones}')::boolean),
   438	    'datos_incompletos',count(*) filter (where (f.value#>>'{senales,datos_incompletos}')::boolean),
   439	    'por_repartir',count(*) filter (where (f.value#>>'{senales,por_repartir}')::boolean))
   440	  into v_totales from jsonb_array_elements(v_filtradas) f;
   441	  with candidatos as (
   442	    select f.value,
   443	      case when p_senal='pendientes' then f.value->'accion_pendiente'
   444	        when p_senal='todas' then f.value->'accion'
   445	        else coalesce((select a.value from jsonb_array_elements(f.value#>'{estado,avisos}') a
   446	          where a.value->>'bucket'=case p_senal
   447	            when 'tareas_vencidas' then 'tarea_vencida' when 'seguimientos_pendientes' then 'seguimiento'
   448	            when 'revisiones' then 'revision_comercial' else p_senal end limit 1),
   449	          nullif(f.value->'accion','null'::jsonb),f.value->'accion_revision') end as accion
   450	    from jsonb_array_elements(v_filtradas) f
   451	    where (p_senal='todas' and f.value->'accion'<>'null'::jsonb)
   452	      or (p_senal<>'todas' and (f.value->'senales'->>p_senal)::boolean is true)
   453	  )
   454	  select coalesce(jsonb_agg(c.accion||jsonb_build_object(
   455	    'estado',c.value->'estado','lead',c.value->'lead','senales',c.value->'senales')),'[]'::jsonb)
   456	    into v_filtradas from candidatos c;
   457	  v_total:=jsonb_array_length(v_filtradas);
   458	  with ordenadas as (
   459	    select f.value,(f.value->>'prioridad')::integer as prioridad,
   460	      (f.value->>'referencia_en')::timestamptz as referencia,(f.value->>'lead_id')::uuid as lead_id
   461	    from jsonb_array_elements(v_filtradas) f
   462	  ), posteriores as (
   463	    select o.* from ordenadas o where p_cursor is null or
   464	      (o.prioridad,coalesce(o.referencia,'infinity'::timestamptz),o.lead_id)>
   465	      (v_prioridad,coalesce(v_referencia,'infinity'::timestamptz),v_lead)
   466	  ), pagina as (
   467	    select p.* from posteriores p order by p.prioridad,p.referencia nulls last,p.lead_id limit p_limite
   468	  )
   469	  select (select count(*) from posteriores),
   470	    coalesce((select jsonb_agg(p.value order by p.prioridad,p.referencia nulls last,p.lead_id) from pagina p),'[]'::jsonb)
   471	    into v_restantes,v_items;
   472	  v_anteriores:=v_total-v_restantes;
   473	  if v_restantes>p_limite then
   474	    v_ultima:=v_items->(jsonb_array_length(v_items)-1);
   475	    v_siguiente:=jsonb_build_object('version',1,'contexto',v_contexto,'prioridad',v_ultima->'prioridad',
   476	      'referencia_en',v_ultima->'referencia_en','lead_id',v_ultima->'lead_id');
   477	  end if;
   478	  return jsonb_build_object('version',2,'modelo_avisos',v_datos->'modelo_avisos',
   479	    'proximo_cambio_en',v_datos->'proximo_cambio_en','modo',v_datos->'modo','control_revision',v_datos->'control_revision',
   480	    'calculado_en',v_datos->'calculado_en','politica_operativa_id',v_datos->'politica_operativa_id',
   481	    'politica_operativa_version',v_datos->'politica_operativa_version',
   482	    'total_items',v_total,'hay_mas',v_restantes>p_limite,'totales',v_totales,'items',v_items,
   483	    'filtros',v_filtros,'limite',p_limite,'cursor_siguiente',v_siguiente,
   484	    'rango',jsonb_build_object('desde',case when jsonb_array_length(v_items)=0 then 0 else v_anteriores+1 end,
   485	      'hasta',case when jsonb_array_length(v_items)=0 then 0 else v_anteriores+jsonb_array_length(v_items) end));
   486	end;
   487	$function$
   488	;
   489	
   490	select private.assert_sla_nucleo();
```

---
## PROTOCOLO DEL PROYECTO (.ai/REVIEW_PROTOCOL.md, íntegro)
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.

## PROTOCOLO GLOBAL (~/.config/ai-collaboration/REVIEW_PROTOCOL.md, íntegro)
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
