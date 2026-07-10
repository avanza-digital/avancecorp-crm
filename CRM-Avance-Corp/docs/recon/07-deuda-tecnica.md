# Auditoría de deuda técnica y anti-patrones — CRM VITANOVA (crm-vitanova-vite)

Base auditada: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova-vite/src` (solo lectura). Total: 19,514 líneas TS/TSX. Premisa de evaluación: destino en React Native (Expo), ~5,000 clientes, red móvil, jerarquía de 4 niveles, soft-delete `activo=false`.

---

## 1. El monolito `src/lib/store.ts` (2,385 líneas)

**Estructura:** un solo módulo con estado global mutable + pub/sub casero + ~60 métodos exportados en un objeto `store` (src/lib/store.ts:2341-2383). Contiene a la vez: auth, 7 loaders, mutaciones de pipeline/citas/cotizaciones/inbox, realtime, adaptadores UI, `dashboardData` (338 líneas), inteligencia comercial (2 motores), motor de reportes, y TODO el CRUD de configuración (líneas/SLA/plantillas/cadencias/usuarios/metas). El cache es un singleton `S` (src/lib/store.ts:125-135) y el snapshot para React se rebuilde en cada `notifyAll` (src/lib/store.ts:163-190, `useSyncExternalStore`).

**¿Carga todo el dataset al boot? SÍ.** `boot()` (src/lib/store.ts:266-282) ejecuta en cascada: usuarios → líneas+usuarios → prospectos+plantillas → conversaciones → notifs+config. Las cargas clave NO tienen límite ni proyección:

- src/lib/store.ts:302-306:
  ```ts
  async function loadProspectos(): Promise<void> {
    const r = await sb.from('prospectos').select('*').order('score_actual', { ascending: false })
  ```
- src/lib/store.ts:314-320: `sb.from('conversaciones').select('*, prospectos(...)')` — también sin límite.
- Solo `notificaciones` tiene `.limit(50)` (src/lib/store.ts:322). No existe NINGÚN `.range(` en todo `src` (grep verificado); los únicos `.limit(` son 50/5000/10000/500 (store.ts:322,1916,1919,1921).

**¿Escala a 5,000 clientes y móvil? NO, por cinco razones verificadas:**
1. **Truncamiento silencioso:** con el `max-rows` por defecto de PostgREST/Supabase (1000 filas), `select('*')` sin `.range()` devolvería solo 1000 prospectos sin error alguno: KPIs, kanban y reportes mentirían en silencio. Si se sube el cap, el boot descarga 5,000 filas × todas las columnas por red móvil.
2. **Full re-fetch tras cada mutación:** `await loadProspectos(); notifyAll()` se repite en 10 sitios tras cada escritura — moverEtapa (389), crearProspecto (404), importarProspectos (423), anonimizarProspecto (433), reasignar (462), rebalancearSupervisor (471), guardarCotizacion (523), enviarBorrador (530), simularEntrante (726), registrarContacto (789). Cada drag del kanban = re-descarga de la tabla entera.
3. **Realtime tabla-completa:** `suscribirRealtime` (src/lib/store.ts:794-820) crea un canal con binds SIN filtro sobre `conversaciones`, `actividades`, `citas` y `cotizaciones` (solo `notificaciones` filtra por `usuario_id`). Cualquier cambio de cualquier usuario dispara `loadConversaciones()` completo o `notifyAll()` en todos los clientes conectados (tormenta N clientes × M eventos).
4. **Re-render global:** cada `notifyAll` cambia la referencia del snapshot → todos los componentes con `useStore()` re-renderizan. En RN (bridge + gama media) esto es jank garantizado.
5. **Dashboard recomputa + 4 queries por cada cambio:** dashboard.tsx:301-311 tiene `useEffect(... [snap.booted, snap.prospectos, snap.lineas, snap.usuarios, snap.plantillas, snap.configClinica, rol, colaTick])` que llama `store.dashboardData(rol)` — y esa función hace 4 queries de red (metas, cotizaciones aceptadas, citas seguimiento, citas hoy: store.ts:1053, 1207, 1302, 1362) más agregación O(n×k) sobre todos los prospectos. Cada evento realtime que toque el cache re-ejecuta todo.

**Qué habría que cambiar para RN:** TanStack React Query con queries paginadas por pantalla (`.range()` + `count`), invalidación selectiva por query-key en lugar de `loadProspectos()` global, mutaciones optimistas inmutables (cache de RQ), agregados/KPIs vía RPC o vistas SQL (no en el cliente), realtime selectivo (canal filtrado por cartera/usuario o polling + invalidate), FlatList virtualizada, y storage adapter para sesión (ver §6).

---

## 2. Verificación de las lecciones de la auditoría previa

| Lección | Estado actual | Evidencia |
|---|---|---|
| Métricas mensuales vs acumulado | **CORREGIDO en su mayoría** — el código tiene fixes documentados C3/C4/C6/C8 | store.ts:1063-1067 (etapa máxima), 1086-1087 (C3), 1194-1212 (C4: ingreso del mes desde cotizaciones aceptadas; C6: `cerrado_en` estable). El sparkline de KPIs sigue siendo acumulado 7 semanas por diseño y etiquetado (`serie()` store.ts:1024-1041, `out[i] += out[i-1]`; dashboard.tsx:119 lo titula "acumulado") |
| `humanizarDuracion` clampa negativos | **PERSISTE el footgun** — `const m = Math.max(0, min)` (src/lib/format.ts:96). Mitigado a mano solo en `adaptSla` (store.ts:842-847: "no mostrar 'Vence en 1 min' (humanizarDuracion clampa el negativo)"). Cualquier llamador nuevo vuelve a caer | format.ts:94-104 |
| delete+insert no atómico (PostgREST) | **PERSISTE** en `guardarPasos` (store.ts:2109-2134): `delete` luego `insert`, con mitigación de respaldo best-effort ("como delete+insert NO es atómico, si el insert falla restauramos", store.ts:2119-2120) y `catch { /* sin recuperación posible */ }` (2131). Si el cliente muere entre delete e insert, la cadencia queda sin pasos. Debe ser RPC transaccional | store.ts:2121-2133 |
| Botones muertos | No se detectan handlers vacíos por grep (`onClick={() => {}}`, `href="#"`: 0 resultados). Los previos parecen corregidos; el diff sin commitear de pipeline.tsx además elimina bloques UI enteros | — |
| localStorage/NaN | **CORREGIDO**: `readLS/writeLS` con try/catch (src/lib/theme.tsx:13-15); `money/moneyK` con guard `isFinite` (format.ts:13,20) |
| Coherencia filtro-por-asesor | **CORREGIDO/ELIMINADO**: pipeline y prospectos filtran por id (`p.asesor === asesorFiltro`, pipeline.tsx:118, prospectos.tsx:74); el diff sin commitear ELIMINA los 4 KPIs del tablero donde vivía la incoherencia |
| Realtime de hilos | **FUNCIONA pero frágil**: el hilo activo se recarga vía cadena bind tabla-completa `conversaciones` → `loadConversaciones()` entero → cambia `ultimo_mensaje_en` → `useEffect([active, activeUltimo])` refetch (inbox.tsx:135-153). El bind de `actividades` INSERT solo hace `notifyAll()` si coincide `activeConvId` (store.ts:801-804) pero eso solo re-renderiza, no refetchea — el refetch real depende del trigger de BD que actualice `conversaciones` |
| Gating UI↔RLS | **PRESENTE y bien planteado**: `roles.ts` declara "NO es seguridad (eso vive en RLS) — es la UX" (src/lib/roles.ts:2); matriz CAPS por rol (roles.ts:19-32) + route-guard en App.tsx:66-69 |

---

## 3. Nuevos anti-patrones encontrados

### 3.1 Mutación in-place + memoización por referencia → el update optimista está muerto
`moverEtapa` muta el objeto del cache en sitio: `p.etapa = to; p.fecha_cambio_etapa = ...; notifyAll()` (store.ts:376-379). Pero `buildSnapshot()` reutiliza LA MISMA referencia de array: `prospectos: S.prospectos` (store.ts:170). Los consumidores memoizan por referencia: pipeline.tsx:111-114 `useMemo(... [snap.prospectos])` (ídem prospectos.tsx:86, inbox.tsx:102, leads-nuevos.tsx:41, reportes.tsx:160, cotizaciones.tsx:60, ficha-provider.tsx:222, cotizador-provider.tsx:122,256). Resultado: la "actualización optimista" NO se refleja en el kanban (el memo no recomputa); la tarjeta solo se mueve cuando `loadProspectos()` devuelve un array nuevo tras el roundtrip. El mismo defecto afecta el rollback (store.ts:384) y `registrarContacto` (776), `marcarLeido` (701). Anti-patrón de libro: estado mutable compartido + igualdad referencial.

### 3.2 Soft-delete filtrado inconsistente
`Prospecto.eliminado` existe (src/lib/types.ts:103) pero `loadProspectos()` no lo filtra en la query. Solo 3 consumidores lo filtran: `bucketsAccionables` (store.ts:981), leads-nuevos.tsx:37, sidebar.tsx:37 e import-prospectos.ts:73. NO lo filtran: `dashboardData` (KPIs, funnel, ranking, resultadosSemana), `inteligenciaComercial(+Plus)`, pipeline, prospectos, reportes → los eliminados cuentan en métricas y aparecen en listas. Lección crítica para Avance Corp (donde `activo=false` es regla dura): el filtro de soft-delete debe vivir en la QUERY (política RLS o `.eq('activo', true)` centralizado), jamás repartido por consumidor.

### 3.3 Cómputo muerto + HTML en la capa de datos
`dashboardData` calcula `funnel`, `hot`, `ia`, `heroPct`, `heroAside`, `sub` (store.ts:1104-1162, 1369-1379) y **ningún componente los consume** (grep de `data.ia|data.hot|data.funnel|heroAside|heroPct`: 0 resultados en pantallas). Se recalculan en cada refresh del dashboard. Peor: `porqueDe()` y `sub` generan strings HTML (`<em class="em">`, `<b>`) desde el store (store.ts:1134-1141, 1162) con escape manual (1159-1160) — presentación y markup en la capa de datos; en RN ni siquiera existe innerHTML.

### 3.4 Presentación incrustada en constantes del data layer
Colores hex, emojis y labels viven en el store: `ETAPAS`/`TERMINALES` con color (store.ts:39-49), `ACT` con emoji-iconos (66-78), `PALETTE` + `PALETTE_DASH` divergentes (80-82, comentario admite "distinta de la del store"), `FUNNEL_DEF` (954-960), `scoreColor` verde `#18a06b` (format.ts:86) y verdes en ETAPAS/ACT (`#22c55e`, `#16a34a`, `#18a06b`). Para Avance esto choca de frente con la restricción "SIN verde / navy #111e3d / #2563eb": los tokens de color deben vivir en un theme, no en el dominio.

### 3.5 Reportes calculados en el cliente con truncamiento silencioso
`reportesCtx().fetchDataset` baja hasta 5,000 cotizaciones + 10,000 actividades + 500 metas al navegador (store.ts:1916-1922) y `construirReportes` (src/lib/reportes.ts, 524 líneas) agrega todo en JS. Los `.limit()` truncan sin avisar al usuario (un `.then(ok, () => [])` además convierte errores en dataset vacío → reportes en cero sin error visible). `serieIngresos6m` baja TODAS las cotizaciones aceptadas de la historia para quedarse con 6 meses (store.ts:1770). Con el volumen de Avance (5,000 clientes × contratos × cuotas) esto debe ser RPC/vista SQL server-side.

### 3.6 Sin paginación ni virtualización en ninguna lista
prospectos.tsx renderiza `items.map((p) => ...)` completo (línea ~193 del archivo; grep confirmó ausencia de `slice`/`Pagination`/virtualización). Inbox igual. 5,000 filas = DOM/árbol RN inmanejable. En RN: FlatList + `.range()` server-side + búsqueda server-side (la búsqueda actual es `indexOf` en memoria sobre todo el cache, prospectos.tsx:79, inbox.tsx:120-125).

### 3.7 Errores silenciados y observabilidad no cableada
30 `catch {` vacíos en src (11 en store.ts). `dashboardData` degrada a `return null` con solo `console.warn` (store.ts:1380-1383) → dashboard en blanco sin telemetría. Lo irónico: existe `logError` (src/lib/log-error.ts) — pieza EXCELENTE: scrub de PII/tokens/DNI (regex línea 10), de-dup con TTL 30s (21-30), fire-and-forget a tabla `app_errores` con RLS — pero solo se usa en los ErrorBoundary de App.tsx:80 y los handlers globales de main.tsx:15-16. La capa de datos, donde ocurren los fallos reales, nunca lo llama.

### 3.8 Config y textos hardcodeados
- src/lib/config.ts: `MARCA: 'Clínica Álvarez'`, `SEDE: 'Surco'`, `CLINICA_NOMBRE`, `WHATSAPP_LIVE: false` literales en código (solo URL/key salen de env).
- App.tsx:35: `reportes: { t: 'Reportes', s: 'Junio 2026 · Clínica Álvarez' }` — subtítulo con MES HARDCODEADO, ya desactualizado (hoy 2026-07-09).
- Defaults de negocio dispersos: cupos "3 sup / 6 asesores" (store.ts:2164-2165), SLA 5 min (341), meta conversión 45 (1158).

### 3.9 Navegación por estado local, sin router
`useState('dash')` + cadena de ternarios (App.tsx:59, 86-96). Sin URL, deep-links ni back. En RN esto se reemplaza por react-navigation de todos modos, pero NO copiar el patrón "view string + ternarios".

### 3.10 Cliente Supabase con storage por defecto (incompatible RN)
src/lib/supabase.ts:7 `createClient(URL, KEY)` sin opciones — persiste sesión en `localStorage`, que NO existe en React Native. En Expo hace falta `auth: { storage: AsyncStorage/SecureStore, detectSessionInUrl: false, autoRefreshToken: true }`.

### 3.11 Import masivo con reintento fila-a-fila
`importarProspectos` inserta lotes de 500 y, si un lote falla, reintenta FILA POR FILA (hasta 500 requests secuenciales, store.ts:417-421). En red móvil es inviable; debe ser RPC server-side con reporte de duplicados.

### 3.12 Jerarquía de solo 3 niveles y validación de negocio solo en cliente
`export type Rol = 'gerente' | 'supervisor' | 'asesor'` (types.ts:7) — Avance necesita 4 (vendedor → supervisor → gerencia → directorio/auditoría) y un modo lectura-total-sin-escritura (directorio) que no existe. `validTransition` (store.ts:357-364) valida transiciones de etapa SOLO en el cliente; para contratos de inversión la máquina de estados debe replicarse en el servidor (trigger/RPC).

---

## 4. Tests existentes

- **Unit (Vitest): 121 líneas en 3 archivos, solo helpers puros.** `src/lib/format.test.ts` (55 líneas: money, moneyK, telE164, humanizarDuracion, iniciales), `src/lib/reportes.test.ts` (39: presets de rango, etiquetaPeriodo, type-guard de error), `src/lib/leads-reparto.test.ts` (27: orden de reparto, no-mutación). 
- **E2E (Playwright): 39 líneas, 5 smoke tests** de navegación por rol (gerente ve Config, asesor NO, supervisor sin Config; gerente entra a Reportes, asesor abre Tablero) — e2e/*.spec.ts.
- **Cero tests** para store.ts (2,385 líneas de lógica de negocio), dashboardData, inteligencia comercial, adaptadores, RLS. El patrón sí rescatable: extraer lógica a módulos puros testeables (leads-reparto.ts es el mejor ejemplo: helper puro + test de no-mutación).
- Punto a favor verificado: **cero `any`** en src (grep `: any|as any|any[]|<any>`: 0 resultados); types.ts usa `unknown` (11 veces) y tipos estrictos. types.ts es un monolito de 1,078 líneas pero limpio.

## 5. Estado del git (repo VITANOVA)

Rama `main`, **13 commits adelante de `origin/main` sin push**, y 4 archivos modificados sin commit (`git diff --stat`: 73 inserciones, 128 borrados):

1. **src/lib/types.ts** (+2): añade `cohorte: number[]` a `ResultadoSemanaSerie` con doc "# que INGRESARON y CERRARON en la MISMA semana (cohorte same-week), por semana".
2. **src/lib/store.ts** (1 línea): `construirSerie` ahora expone `cohorte` en el objeto retornado (`key, label, montos, cerradas, recibidos, cohorte,` — store.ts:1268).
3. **src/components/bi/resultados-semana.tsx** (±103): rediseño del card "Resultados por semana": reemplaza el `ComposedChart` (barras de monto S/ + línea de conversión %, doble eje Y) por un `BarChart` de dos barras por semana ("Ingresados" = recibidos por `creado_en` vs "Convertidos" = cohorte same-week), añade leyenda propia, mueve la conversión % al tooltip, y cambia el resumen principal de "Monto cerrado del mes" a "Ingresaron este mes" (el monto pasa a subtexto).
4. **src/screens/pipeline.tsx** (−73 netas): ELIMINA del tablero las 4 tarjetas KPI (`SummaryCard`: Valor total / Estimado / Conversión / Precio prom.), la barra "Distribución del valor por etapa" (`SegmentBar`) y el contador "N prospectos en el tablero"; deja solo el kanban + filtro por asesor. Comentario nuevo: "Solo el tablero: sin tarjetas de resumen ni barra de distribución".

Trabajo en curso coherente (mover métricas del tablero al dashboard/BI), pero es deuda de higiene: cambios de tipo + store + 2 vistas sin commit, y 13 commits sin respaldar en remoto.

## 6. Veredicto sobre el esqueleto para React Native

**El patrón `store` singleton + boot-carga-todo NO sobrevive** el traslado a RN con 5,000 clientes (razones en §1). Lo que SÍ transfiere del esqueleto: la separación roles-como-UX/RLS-como-seguridad (roles.ts), la convención `ActionResult {ok, error}`, helpers puros testeados, `logError` con scrub de PII (adaptado), ErrorBoundary por pantalla (adaptado a RN), la disciplina de comentarios que documentan POR QUÉ (C3/C4/C6/C8), y la Edge Function para crear usuarios con cuotas server-side. Lo que hay que construir distinto desde el día 1: React Query + paginación server-side, agregados por RPC/vistas SQL, realtime selectivo o polling, FlatList, storage adapter de sesión, filtro central de soft-delete, tema sin verde con tokens fuera del dominio, y 4º nivel de rol (directorio, lectura total).
