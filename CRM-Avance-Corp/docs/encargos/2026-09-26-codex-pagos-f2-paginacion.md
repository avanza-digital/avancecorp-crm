ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Portal admin · Pagos F2 — la tabla por contrato pasa a paginación server-side (LEVEL 2)

Tu trabajo es REFUTAR: busca fallos reales en el cambio (carreras, estados incoherentes,
regresiones de flujo, escapes, permisos), no confirmarlo. Sin hallazgo sin evidencia.

## Contexto

Portal `miavance.com`, pantalla `admin/pagos.html` + `js/admin/pagos.js` (vanilla ES modules,
Supabase JS v2). Roles que la usan: admin/superadmin y el asiento `operaciones` (`verificarGestorCartera`).
Producción: 656 contratos, 5.747 cuotas, 4.852 por pagar.

Antes: la pantalla llamaba a `admin_pagos_resumen()` (jsonb con TODOS los contratos, ~2,8 s),
guardaba todo en `CONTRATOS_CACHE`, filtraba/ordenaba en memoria y pintaba 1.300 filas.
Ahora: pide una página de 50 a la RPC `pagos_admin_resumen_contratos` (que YA existía en la base,
security invoker, EXECUTE a authenticated) y solo guarda la página actual (`CONTRATOS_PAGINA`).
La agenda (cuotas ≤ 7 días) sigue viniendo completa y se recorre por páginas en pantalla
(`agenda-paginas-core.js`, ya publicado). Exportar/importar Excel leen `AGENDA_CACHE`, no la tabla.

Requisitos que Miguel (dueño) fijó: paginación «← Anterior · 1–50 de N · Siguiente →» (nunca «Ver más»);
buscar y moneda se resuelven en la base; pagar/anular desde la página 3 te devuelve a la página 3;
el cronograma de cada contrato se sigue abriendo al hacer clic; sin migraciones ni cambios de permisos.

## Definición de la RPC (transcrita de producción, sin cambios)

```sql
CREATE OR REPLACE FUNCTION public.pagos_admin_resumen_contratos(p_tab text DEFAULT 'cobrar', p_busqueda text DEFAULT '', p_moneda text DEFAULT '', p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS TABLE(contrato_id uuid, cliente_nombre text, numero_contrato text, moneda text, capital numeric, estado_contrato text, total_cuotas bigint, pagadas bigint, vencidas bigint, pendientes bigint, adeudado numeric, pagado_total numeric, proxima_cuota_id uuid, proxima_numero integer, proxima_monto numeric, proxima_fecha date, proxima_tipo text, proxima_estado_real text, completo boolean, total_count bigint)
 LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  WITH cuotas_con_estado AS (
    SELECT cp.id, cp.contrato_id, cp.numero_cuota, cp.fecha_programada, cp.monto_programado, cp.estado, cp.tipo, cp.monto_pagado,
      CASE WHEN cp.estado = 'pagado' THEN 'pagado' WHEN cp.estado = 'trasladado' THEN 'trasladado'
           WHEN cp.fecha_programada < CURRENT_DATE THEN 'vencido' ELSE 'pendiente' END AS estado_real
    FROM cronograma_pagos cp),
  metricas_contrato AS (SELECT contrato_id, count(*) AS total_cuotas,
      count(*) FILTER (WHERE estado_real = 'pagado') AS pagadas, count(*) FILTER (WHERE estado_real = 'vencido') AS vencidas,
      count(*) FILTER (WHERE estado_real = 'pendiente') AS pendientes,
      COALESCE(sum(monto_programado) FILTER (WHERE estado_real = 'vencido'), 0) AS adeudado,
      COALESCE(sum(monto_pagado) FILTER (WHERE estado_real = 'pagado'), 0) AS pagado_total
    FROM cuotas_con_estado GROUP BY contrato_id),
  proximas AS (SELECT DISTINCT ON (contrato_id) contrato_id, id AS proxima_cuota_id, numero_cuota AS proxima_numero,
      monto_programado AS proxima_monto, fecha_programada AS proxima_fecha, tipo AS proxima_tipo, estado_real AS proxima_estado_real
    FROM cuotas_con_estado WHERE estado_real NOT IN ('pagado','trasladado')
    ORDER BY contrato_id, CASE estado_real WHEN 'vencido' THEN 0 ELSE 1 END, fecha_programada ASC),
  contratos_full AS (SELECT c.id AS contrato_id, COALESCE(p.nombre_completo, '—') AS cliente_nombre, c.numero_contrato,
      c.moneda::text AS moneda, c.capital, c.estado::text AS estado_contrato,
      COALESCE(m.total_cuotas,0) AS total_cuotas, COALESCE(m.pagadas,0) AS pagadas, COALESCE(m.vencidas,0) AS vencidas,
      COALESCE(m.pendientes,0) AS pendientes, COALESCE(m.adeudado,0) AS adeudado, COALESCE(m.pagado_total,0) AS pagado_total,
      pr.proxima_cuota_id, pr.proxima_numero, pr.proxima_monto, pr.proxima_fecha, pr.proxima_tipo, pr.proxima_estado_real,
      (COALESCE(m.pendientes,0) + COALESCE(m.vencidas,0) = 0) AS completo
    FROM (SELECT * FROM contratos WHERE NOT es_demo) c
    LEFT JOIN perfiles p ON p.id = c.cliente_id
    LEFT JOIN metricas_contrato m ON m.contrato_id = c.id
    LEFT JOIN proximas pr ON pr.contrato_id = c.id),
  filtrados AS (SELECT * FROM contratos_full
    WHERE (p_tab = 'todos' OR (p_tab = 'cobrar' AND completo = false) OR (p_tab = 'pagados' AND completo = true))
      AND (NULLIF(p_moneda, '') IS NULL OR moneda = p_moneda)
      AND (NULLIF(p_busqueda, '') IS NULL OR cliente_nombre ILIKE '%' || p_busqueda || '%' OR numero_contrato ILIKE '%' || p_busqueda || '%')),
  con_count AS (SELECT *, count(*) OVER() AS tc FROM filtrados)
  SELECT contrato_id, cliente_nombre, numero_contrato, moneda, capital, estado_contrato, total_cuotas, pagadas, vencidas, pendientes,
    adeudado, pagado_total, proxima_cuota_id, proxima_numero, proxima_monto, proxima_fecha, proxima_tipo, proxima_estado_real, completo, tc AS total_count
  FROM con_count
  ORDER BY CASE WHEN proxima_estado_real = 'vencido' THEN 0 WHEN proxima_estado_real = 'pendiente' AND proxima_fecha <= CURRENT_DATE + 7 THEN 1
                WHEN proxima_estado_real = 'pendiente' THEN 2 ELSE 3 END, proxima_fecha ASC NULLS LAST, numero_contrato ASC
  OFFSET p_offset LIMIT p_limit;
$function$
```

Medido en producción: cobrar 651 · pagados 4 · todos 655 · búsqueda 'quispe' 26 · USD 96 · offset 650/50 devuelve 5 filas.

## Núcleo puro nuevo: `js/admin/pagos-tabla-core.js` (completo)

```js
/**
 * PAGOS · tabla por contrato paginada (núcleo puro, sin DOM ni red)
 *
 * La pantalla pedía TODOS los contratos de golpe (`admin_pagos_resumen`, ~3 s y
 * 1.300 filas escondidas) y filtraba en memoria. Ahora pide una página a la RPC
 * `pagos_admin_resumen_contratos(p_tab, p_busqueda, p_moneda, p_offset, p_limit)`,
 * que filtra, ordena por urgencia y devuelve `total_count` en cada fila.
 *
 * Aquí viven las tres traducciones que conviene probar sin navegador:
 *  - los filtros de pantalla → parámetros de la RPC (con la búsqueda escapada),
 *  - una fila de la RPC → la forma que ya usan las funciones de pintado,
 *  - el total de la respuesta.
 */

export const PAGE_SIZE_TABLA = 50
export const TABS_TABLA = Object.freeze(['cobrar', 'pagados', 'todos'])

/**
 * La RPC concatena la búsqueda dentro de un ILIKE '%…%' sin cláusula ESCAPE, así
 * que `%`, `_` y `\` del usuario actuarían como comodines. Se escapan para que
 * «2026-01_000029» busque el guion bajo literal y no «cualquier carácter».
 */
export function escaparBusqueda(texto) {
  return String(texto ?? '').trim().replace(/[\\%_]/g, '\\$&')
}

export function parametrosTabla({ tab, busqueda, moneda, pagina, porPagina = PAGE_SIZE_TABLA }) {
  const p_tab = TABS_TABLA.includes(tab) ? tab : 'cobrar'
  const p_moneda = moneda === 'PEN' || moneda === 'USD' ? moneda : ''
  const limite = Number.isInteger(porPagina) && porPagina > 0 ? porPagina : PAGE_SIZE_TABLA
  const p = Number.isInteger(pagina) && pagina > 0 ? pagina : 0
  return {
    p_tab,
    p_busqueda: escaparBusqueda(busqueda),
    p_moneda,
    p_offset: p * limite,
    p_limit: limite,
  }
}

function numero(v) {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

/**
 * Fila de `pagos_admin_resumen_contratos` → forma que ya consumen renderFilaContrato,
 * renderCronogramaContenido y el modal de pago (la de `admin_pagos_resumen`).
 * `proxima.estado` se deja en 'pendiente': la pantalla decide «atrasada» por fecha
 * (decorarEstado), igual que antes; la RPC ya excluye pagadas y trasladadas.
 */
export function mapearFilaResumen(fila) {
  if (!fila || typeof fila !== 'object') throw new TypeError('La fila del resumen debe ser un objeto.')
  if (!fila.contrato_id) throw new Error('Fila del resumen sin contrato_id.')
  const proxima = fila.proxima_cuota_id
    ? {
        id: fila.proxima_cuota_id,
        numero_cuota: fila.proxima_numero,
        fecha_programada: fila.proxima_fecha,
        monto_programado: numero(fila.proxima_monto),
        estado: 'pendiente',
        tipo: fila.proxima_tipo ?? null,
        fecha_pago_real: null,
      }
    : null
  return {
    id: fila.contrato_id,
    numero_contrato: fila.numero_contrato ?? '',
    cliente: fila.cliente_nombre ?? '—',
    moneda: fila.moneda === 'USD' ? 'USD' : 'PEN',
    capital: numero(fila.capital),
    estado_contrato: fila.estado_contrato ?? null,
    totalCuotas: numero(fila.total_cuotas),
    pagadas: numero(fila.pagadas),
    vencidas: numero(fila.vencidas),
    pendientes: numero(fila.pendientes),
    adeudado: numero(fila.adeudado),
    pagadoTotal: numero(fila.pagado_total),
    completo: fila.completo === true,
    proxima,
  }
}

/** `total_count` viene repetido en cada fila; sin filas, el total es 0. */
export function totalDeRespuesta(filas) {
  if (!Array.isArray(filas) || filas.length === 0) return 0
  return numero(filas[0].total_count)
}
```

## Pruebas del núcleo: `tests/pagos-tabla-core.test.mjs` (pasan, 130/130 en total)

```js
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = await readFile(new URL('../js/admin/pagos-tabla-core.js', import.meta.url), 'utf8')
const { PAGE_SIZE_TABLA, escaparBusqueda, parametrosTabla, mapearFilaResumen, totalDeRespuesta } =
  await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('la búsqueda se escapa para el ILIKE de la RPC (guion bajo, porcentaje, barra)', () => {
  assert.equal(escaparBusqueda('  quispe '), 'quispe')
  assert.equal(escaparBusqueda('2026-01_000029'), '2026-01\\_000029')
  assert.equal(escaparBusqueda('100%'), '100\\%')
  assert.equal(escaparBusqueda('a\\b'), 'a\\\\b')
  assert.equal(escaparBusqueda(undefined), '')
})

test('los filtros de pantalla se traducen a los parámetros de la RPC', () => {
  assert.deepEqual(parametrosTabla({ tab: 'todos', busqueda: ' Quispe', moneda: 'USD', pagina: 2 }), {
    p_tab: 'todos', p_busqueda: 'Quispe', p_moneda: 'USD', p_offset: 100, p_limit: 50,
  })
  assert.equal(PAGE_SIZE_TABLA, 50)
})

test('una pestaña o moneda desconocida cae en «cobrar» y «todas las monedas»', () => {
  const p = parametrosTabla({ tab: 'agenda', busqueda: '', moneda: 'EUR', pagina: -1 })
  assert.equal(p.p_tab, 'cobrar')
  assert.equal(p.p_moneda, '')
  assert.equal(p.p_offset, 0)
})

const filaRpc = {
  contrato_id: 'c-1', cliente_nombre: 'QUISPE FLORES GERMAN', numero_contrato: '2026-01-001292',
  moneda: 'USD', capital: '5000.00', estado_contrato: 'activo',
  total_cuotas: 13, pagadas: 1, vencidas: 1, pendientes: 11, adeudado: '250.00', pagado_total: '250.00',
  proxima_cuota_id: 'q-2', proxima_numero: 2, proxima_monto: '250.00', proxima_fecha: '2026-09-24',
  proxima_tipo: null, proxima_estado_real: 'vencido', completo: false, total_count: 651,
}

test('una fila de la RPC toma la forma que ya usan las funciones de pintado', () => {
  const c = mapearFilaResumen(filaRpc)
  assert.equal(c.id, 'c-1')
  assert.equal(c.cliente, 'QUISPE FLORES GERMAN')
  assert.equal(c.moneda, 'USD')
  assert.equal(c.capital, 5000)
  assert.equal(c.totalCuotas, 13)
  assert.equal(c.adeudado, 250)
  assert.equal(c.pagadoTotal, 250)
  assert.equal(c.completo, false)
  assert.deepEqual(c.proxima, {
    id: 'q-2', numero_cuota: 2, fecha_programada: '2026-09-24', monto_programado: 250,
    estado: 'pendiente', tipo: null, fecha_pago_real: null,
  })
})

test('un contrato cumplido llega sin próxima cuota', () => {
  const c = mapearFilaResumen({ ...filaRpc, proxima_cuota_id: null, proxima_numero: null, completo: true, vencidas: 0, pendientes: 0 })
  assert.equal(c.proxima, null)
  assert.equal(c.completo, true)
})

test('una fila sin contrato_id se rechaza', () => {
  assert.throws(() => mapearFilaResumen({ ...filaRpc, contrato_id: null }), /contrato_id/)
  assert.throws(() => mapearFilaResumen(null), TypeError)
})

test('el total sale de la primera fila y es 0 sin filas', () => {
  assert.equal(totalDeRespuesta([filaRpc, filaRpc]), 651)
  assert.equal(totalDeRespuesta([]), 0)
  assert.equal(totalDeRespuesta(undefined), 0)
})
```

## Núcleo de páginas ya publicado (reutilizado): `js/admin/agenda-paginas-core.js`

```js
/**
 * AGENDA DE PAGOS · paginación por tramo (núcleo puro, sin DOM)
 *
 * «Pagar hoy» y «Esta semana» pueden traer decenas o cientos de cuotas y hacían
 * la agenda interminable (Miguel, 2026-09-26). Cada tramo se recorre por páginas
 * con «← Anterior · 1–10 de 42 · Siguiente →»; «En mora» no se pagina: es la
 * alarma del día y se ve completa.
 *
 * Solo decide QUÉ filas se pintan: la exportación a Excel sigue leyendo la lista
 * completa, no la página a la vista.
 */

export const POR_PAGINA_POR_TRAMO = Object.freeze({
  mora: Infinity,
  hoy: 10,
  semana: 10,
})

/**
 * @param {{ total: number, porPagina: number, pagina: number }} p  pagina en base 0
 * @returns {{ pagina: number, totalPaginas: number, desde: number, hasta: number,
 *             total: number, hayAnterior: boolean, haySiguiente: boolean }}
 */
export function planPagina({ total, porPagina, pagina }) {
  const n = Number.isInteger(total) && total > 0 ? total : 0
  const tam = Number.isFinite(porPagina) && porPagina >= 1 ? Math.floor(porPagina) : Infinity
  const totalPaginas = tam === Infinity ? 1 : Math.max(1, Math.ceil(n / tam))
  const pedida = Number.isInteger(pagina) ? pagina : 0
  const p = Math.min(Math.max(0, pedida), totalPaginas - 1)   // se recorta si la lista encogió
  const desde = tam === Infinity ? 0 : p * tam
  const hasta = tam === Infinity ? n : Math.min(n, desde + tam)
  return {
    pagina: p,
    totalPaginas,
    desde,
    hasta,
    total: n,
    hayAnterior: p > 0,
    haySiguiente: p < totalPaginas - 1,
  }
}

export function etiquetaPagina({ desde, hasta, total, pagina, totalPaginas }) {
  if (total === 0) return 'Sin cuotas'
  return `${desde + 1}–${hasta} de ${total} · Página ${pagina + 1} de ${totalPaginas}`
}
```

## Diff de `js/admin/pagos.js` (contra lo publicado hoy, commit 97895bb)

```diff
diff --git a/js/admin/pagos.js b/js/admin/pagos.js
index 6a338bf..dd6cf41 100644
--- a/js/admin/pagos.js
+++ b/js/admin/pagos.js
@@ -8,9 +8,12 @@
  *  - Sort: contratos con cuotas más vencidas arriba; dentro del cronograma, las
  *    cuotas siguen el mismo orden de prioridad.
  *
- * Arquitectura (post-refactor):
- *  - El resumen por contrato lo computa la RPC `admin_pagos_resumen()` server-side.
+ * Arquitectura (F2, 2026-09-26):
+ *  - La tabla por contrato se pide POR PÁGINAS (50) a la RPC
+ *    `pagos_admin_resumen_contratos(p_tab, p_busqueda, p_moneda, p_offset, p_limit)`:
+ *    filtra, ordena por urgencia y devuelve `total_count`. Ya no se descarga todo.
  *  - Las métricas globales (cards arriba) las computa `admin_pagos_metricas()`.
+ *  - La agenda (≤ 7 días) sigue viniendo completa y se recorre por páginas en pantalla.
  *  - El cronograma completo se carga lazy sólo cuando el user expande una fila,
  *    y se cachea por contrato_id para no re-pedir.
  */
@@ -28,10 +31,18 @@ import {
   cuentaParaCuota,
 } from './cuentas-pago-core.js?v=2'
 import { POR_PAGINA_POR_TRAMO, planPagina, etiquetaPagina } from './agenda-paginas-core.js?v=1'
+import {
+  PAGE_SIZE_TABLA, parametrosTabla, mapearFilaResumen, totalDeRespuesta,
+} from './pagos-tabla-core.js?v=1'
 
 const MS_DIA = 86400000
 
-let CONTRATOS_CACHE   = []          // array de contratos (shape de admin_pagos_resumen)
+let CONTRATOS_PAGINA  = []          // SOLO la página actual de la tabla por contrato (máx. PAGE_SIZE_TABLA)
+let TABLA_PAGINA      = 0           // página actual de la tabla (base 0); se conserva al pagar/anular
+let TABLA_TOTAL       = 0           // total de contratos que cumplen pestaña + filtros (total_count de la RPC)
+let TABLA_ABORT       = null        // AbortController de la carga en vuelo (buscador con debounce)
+let TABLA_TIMER       = null        // debounce del buscador para la tabla
+let CONTADORES_TABS   = { cobrar: null, pagados: null }   // totales globales de las pestañas (null = cargando)
 let CRONOGRAMA_CACHE  = new Map()   // contrato_id → cuotas[] (lazy load por contrato)
 let AGENDA_CACHE      = []          // cuotas planas con datos cliente para la vista Agenda
 let AGENDA_PAGINA     = {}          // tramo → página actual (base 0); vuelve a la primera al cambiar filtros
@@ -79,10 +90,29 @@ async function notificarPagos(cuotaIds) {
    CARGA
    ============================================ */
 
-async function cargarResumen() {
-  const { data, error } = await supabase.rpc('admin_pagos_resumen')
+/**
+ * Una página de la tabla por contrato. La RPC aplica pestaña, búsqueda y moneda y
+ * ordena por urgencia (atrasadas más viejas primero); `total_count` viene en cada fila.
+ * `signal` cancela la petición si el usuario sigue tecleando o cambia de pestaña.
+ */
+async function cargarPaginaContratos({ tab, busqueda, moneda, pagina }, signal) {
+  const params = parametrosTabla({ tab, busqueda, moneda, pagina, porPagina: PAGE_SIZE_TABLA })
+  let consulta = supabase.rpc('pagos_admin_resumen_contratos', params)
+  if (signal) consulta = consulta.abortSignal(signal)
+  const { data, error } = await consulta
   if (error) throw error
-  return Array.isArray(data) ? data : []
+  const filas = Array.isArray(data) ? data : []
+  return { contratos: filas.map(mapearFilaResumen), total: totalDeRespuesta(filas) }
+}
+
+/** Totales globales de las pestañas (sin filtros), pidiendo una sola fila por pestaña. */
+async function cargarContadoresTabla() {
+  const [cobrar, pagados] = await Promise.all(['cobrar', 'pagados'].map(async (tab) => {
+    const { data, error } = await supabase.rpc('pagos_admin_resumen_contratos', parametrosTabla({ tab, busqueda: '', moneda: '', pagina: 0, porPagina: 1 }))
+    if (error) throw error
+    return totalDeRespuesta(Array.isArray(data) ? data : [])
+  }))
+  return { cobrar, pagados }
 }
 
 async function cargarMetricas() {
@@ -159,16 +189,6 @@ async function consultarCuentasContractuales(contratoIds) {
   return data || []
 }
 
-/**
- * Verifica también los contratos del cronograma completo, no solo los de la
- * agenda urgente. Una respuesta parcial deja esas filas sin cuenta de pago.
- */
-async function asociarCuentasPantalla(agenda, contratos) {
-  const ids = [...new Set([...agenda.map(c => c.contrato_id), ...contratos.map(c => c.id)].filter(Boolean))]
-  const filas = await consultarCuentasContractuales(ids)
-  return asociarCuentasPagoPantalla(agenda, contratos, filas)
-}
-
 async function verificarCuentasParaCuotas(cuotas) {
   const ids = [...new Set(cuotas.map(c => c.contrato_id).filter(Boolean))]
   const filas = await consultarCuentasContractuales(ids)
@@ -252,60 +272,100 @@ function chipUrgencia(p) {
 }
 
 /* ============================================
-   PRIORIDAD POR CONTRATO (sort de la tabla principal)
+   TABLA POR CONTRATO: carga paginada
    ============================================ */
 
 /**
- * Sort contratos: vencidas más viejas primero, luego por vencer, luego al día, luego cumplidos.
- * La RPC ya entrega `proxima` precalculada; aquí sólo decidimos el orden visible.
+ * Pide la página actual a la RPC (pestaña + búsqueda + moneda) y la pinta. Cancela
+ * la carga anterior si sigue en vuelo. Si la página pedida ya no existe (la lista
+ * encogió, p. ej. al pagar la última cuota del último contrato de la página), cae
+ * a la última página disponible.
  */
-function prioridadContrato(c) {
-  if (c.proxima) {
-    return prioridadCuota(c.proxima)
+async function recargarTabla() {
+  if (TAB_ACTIVO === 'agenda') return
+  if (TABLA_ABORT) TABLA_ABORT.abort()
+  const ctrl = new AbortController()
+  TABLA_ABORT = ctrl
+  const tbody = document.getElementById('tablaContratos')
+  if (tbody && CONTRATOS_PAGINA.length === 0) {
+    tbody.innerHTML = `<tr><td colspan="7" class="table-empty">Cargando…</td></tr>`
+  }
+  try {
+    const filtros = { tab: TAB_ACTIVO, busqueda: FILTRO_TEXTO, moneda: FILTRO_MONEDA }
+    let res = await cargarPaginaContratos({ ...filtros, pagina: TABLA_PAGINA }, ctrl.signal)
+    if (res.contratos.length === 0 && res.total > 0 && TABLA_PAGINA > 0) {
+      TABLA_PAGINA = Math.max(0, Math.ceil(res.total / PAGE_SIZE_TABLA) - 1)
+      res = await cargarPaginaContratos({ ...filtros, pagina: TABLA_PAGINA }, ctrl.signal)
+    }
+    if (ctrl.signal.aborted) return
+    TABLA_TOTAL = res.total
+    CONTRATOS_PAGINA = await asociarCuentasPagina(res.contratos)
+    if (ctrl.signal.aborted) return
+    renderTabla()
+  } catch (err) {
+    if (ctrl.signal.aborted || err?.name === 'AbortError') return   // otra carga la reemplazó
+    console.error('[pagos] no se pudo cargar la tabla por contrato:', err)
+    CONTRATOS_PAGINA = []
+    TABLA_TOTAL = 0
+    renderTabla()
+    mostrarError('No se pudo cargar la tabla por contrato. Revisa tu conexión e intenta de nuevo.')
+  } finally {
+    if (TABLA_ABORT === ctrl) TABLA_ABORT = null
   }
-  // contrato cumplido (sin pendientes ni vencidas) → al final
-  return [4, 0]
 }
 
-/* ============================================
-   FILTROS Y TABS
-   ============================================ */
-
-function pasaTabContrato(c) {
-  if (TAB_ACTIVO === 'cobrar')  return !c.completo
-  if (TAB_ACTIVO === 'pagados') return c.completo
-  return true // 'todos'
+/**
+ * Cuentas de pago de los contratos de la página. Si la consulta falla, la página
+ * se pinta igual pero con el registro de pagos bloqueado en esas filas (no se
+ * confía en cuentas de una carga anterior).
+ */
+async function asociarCuentasPagina(contratos) {
+  if (contratos.length === 0) return contratos
+  try {
+    const filas = await consultarCuentasContractuales([...new Set(contratos.map(c => c.id))])
+    return asociarCuentasPagoPantalla([], contratos, filas).contratos
+  } catch (error) {
+    console.error('[pagos] no se pudieron resolver las cuentas de la página:', error)
+    mostrarError('Se cargó la tabla, pero no se verificaron las cuentas de depósito de esta página. Recarga para poder registrar pagos aquí.')
+    return contratos.map(c => ({ ...c, cuenta_pago_contrato: null, cuentas_sin_verificar: true }))
+  }
 }
 
-function aplicarFiltrosContratos() {
-  const tx = FILTRO_TEXTO.toLowerCase().trim()
-  const filtrados = CONTRATOS_CACHE.filter(c => {
-    if (!pasaTabContrato(c)) return false
-    if (FILTRO_MONEDA && c.moneda !== FILTRO_MONEDA) return false
-    if (!tx) return true
-    return c.cliente.toLowerCase().includes(tx)
-        || c.numero_contrato.toLowerCase().includes(tx)
-  })
-  filtrados.sort((a, b) => {
-    const [ba, sa] = prioridadContrato(a)
-    const [bb, sb] = prioridadContrato(b)
-    if (ba !== bb) return ba - bb
-    return sa - sb
-  })
-  return filtrados
+function programarRecargaTabla() {
+  clearTimeout(TABLA_TIMER)
+  TABLA_TIMER = setTimeout(() => { recargarTabla() }, 300)
 }
 
 function actualizarContadoresTabs() {
-  let cobrar = 0, pagados = 0
-  for (const c of CONTRATOS_CACHE) {
-    if (c.completo) pagados++
-    else cobrar++
-  }
-  // Contador de agenda = todo lo cargado (la query ya filtra a ≤ 7 días)
+  // Contador de agenda = todo lo cargado (la query ya filtra a ≤ 7 días). Los de
+  // las pestañas de contratos son totales globales (sin filtros) que trae la RPC.
+  const { cobrar, pagados } = CONTADORES_TABS
   setText('cnt-agenda',  AGENDA_CACHE.length)
-  setText('cnt-cobrar',  cobrar)
-  setText('cnt-pagados', pagados)
-  setText('cnt-todos',   CONTRATOS_CACHE.length)
+  setText('cnt-cobrar',  cobrar ?? '…')
+  setText('cnt-pagados', pagados ?? '…')
+  setText('cnt-todos',   cobrar == null || pagados == null ? '…' : cobrar + pagados)
+}
+
+function renderPaginacionTabla() {
+  const cont = document.getElementById('paginacionContratos')
+  if (!cont) return
+  const plan = planPagina({ total: TABLA_TOTAL, porPagina: PAGE_SIZE_TABLA, pagina: TABLA_PAGINA })
+  if (plan.total === 0) { cont.innerHTML = ''; return }
+  cont.innerHTML = `
+    <button type="button" class="btn btn-secondary btn-sm" data-action="pagina-tabla" data-delta="-1" ${plan.hayAnterior ? '' : 'disabled'}>← Anterior</button>
+    <span class="agenda-bucket-pie-info">Contratos ${etiquetaPagina(plan)}</span>
+    <button type="button" class="btn btn-secondary btn-sm" data-action="pagina-tabla" data-delta="1" ${plan.haySiguiente ? '' : 'disabled'}>Siguiente →</button>
+  `
+  cont.querySelectorAll('[data-action="pagina-tabla"]').forEach(btn => {
+    btn.addEventListener('click', (e) => {
+      TABLA_PAGINA = Math.max(0, TABLA_PAGINA + Number(e.currentTarget.dataset.delta))
+      EXPANDIDO = null
+      recargarTabla()
+      // La página nueva se lee desde arriba: si la cabecera de la tabla quedó fuera, volver a ella.
+      const vista = document.getElementById('vistaContratos')
+      if (vista && vista.getBoundingClientRect().top < 0) vista.scrollIntoView({ block: 'start' })
+    })
+  })
 }
 
 /* ============================================
@@ -425,6 +485,7 @@ function onPaginaTramoAgenda(e) {
 
 function cuentaDisponible(cuota) {
   if (!CUENTAS_PAGO_LISTAS) return false
+  if (cuota?.cuentas_sin_verificar) return false   // la consulta de cuentas de ESTA página falló
   try {
     return cuentaPagoCompleta(cuentaParaCuota(cuota))
   } catch {
@@ -432,8 +493,8 @@ function cuentaDisponible(cuota) {
   }
 }
 
-function avisoCuentaPago() {
-  return CUENTAS_PAGO_LISTAS
+function avisoCuentaPago(cuota) {
+  return CUENTAS_PAGO_LISTAS && !cuota?.cuentas_sin_verificar
     ? 'Sin cuenta de pago — requiere conciliación'
     : 'No se pudo verificar la cuenta de pago — recarga la página'
 }
@@ -459,7 +520,7 @@ function renderFilaAgenda(a) {
         <div class="agenda-row-urgencia">${chipUrgencia({ estado: 'pendiente', fecha_programada: a.fecha_programada })}</div>
         <div class="agenda-row-monto tabular">${formatearMoneda(a.monto_programado, a.moneda)}</div>
         <div class="agenda-row-accion">
-          ${pagable ? '' : `<span class="aviso-cuenta">${avisoCuentaPago()}</span>`}
+          ${pagable ? '' : `<span class="aviso-cuenta">${avisoCuentaPago(a)}</span>`}
           <button class="btn btn-primary btn-sm" data-action="pagar-agenda" data-cuota-id="${a.cuota_id}" ${pagable ? '' : 'disabled'}>
             Marcar pagado
           </button>
@@ -988,13 +1049,17 @@ function renderTabla() {
   if (!tbody) return
 
   actualizarContadoresTabs()
-  const filtrados = aplicarFiltrosContratos()
+  renderPaginacionTabla()
+  const filtrados = CONTRATOS_PAGINA   // la RPC ya filtró y ordenó por urgencia
 
   if (filtrados.length === 0) {
+    const hayFiltros = FILTRO_TEXTO.trim() !== '' || FILTRO_MONEDA !== ''
     tbody.innerHTML = `<tr><td colspan="7" class="table-empty">
-      ${CONTRATOS_CACHE.length === 0
-        ? 'Aún no hay cuotas registradas. Crea un contrato para generar el cronograma.'
-        : 'Ningún contrato coincide con los filtros.'}
+      ${hayFiltros
+        ? 'Ningún contrato coincide con los filtros.'
+        : TAB_ACTIVO === 'pagados'
+          ? 'Todavía no hay contratos con todas sus cuotas pagadas.'
+          : 'Aún no hay cuotas registradas. Crea un contrato para generar el cronograma.'}
     </td></tr>`
     return
   }
@@ -1095,7 +1160,7 @@ async function toggleExpand(id) {
 
 function pintarCronogramaExpandido(contratoId) {
   const contenedor = document.getElementById(`cronograma-${contratoId}`)
-  const contrato = CONTRATOS_CACHE.find(c => c.id === contratoId)
+  const contrato = CONTRATOS_PAGINA.find(c => c.id === contratoId)
   if (!contenedor || !contrato) return
   contenedor.innerHTML = renderCronogramaContenido(contrato)
   contenedor.querySelectorAll('[data-action]').forEach(btn => {
@@ -1106,7 +1171,7 @@ function pintarCronogramaExpandido(contratoId) {
 function renderFilaContrato(c, idx = 0) {
   const expanded = EXPANDIDO === c.id
   const avisoPago = !cuentaDisponible(c)
-    ? `<div class="aviso-cuenta">${avisoCuentaPago()}</div>`
+    ? `<div class="aviso-cuenta">${avisoCuentaPago(c)}</div>`
     : ''
   const proximaHTML = c.proxima
     ? `<div class="proxima-cuota">
@@ -1236,7 +1301,7 @@ function renderCronogramaContenido(c) {
       <div class="cron-titulo">Cronograma del contrato <span class="font-mono">${escapeHtml(c.numero_contrato)}</span></div>
       <div class="cron-pills">${pills.join('')}</div>
     </div>
-    ${pagable ? '' : `<div class="alert alert-warning">${avisoCuentaPago()}</div>`}
+    ${pagable ? '' : `<div class="alert alert-warning">${avisoCuentaPago(c)}</div>`}
     <div class="table-container cron-tabla-wrap">
       <table class="table-dense">
         <thead>
@@ -1262,7 +1327,7 @@ function onAccionCuota(e) {
   const contratoId = e.currentTarget.dataset.contrato
   const cuotas = CRONOGRAMA_CACHE.get(contratoId) || []
   const cuota = cuotas.find(p => p.id === id)
-  const contrato = CONTRATOS_CACHE.find(c => c.id === contratoId)
+  const contrato = CONTRATOS_PAGINA.find(c => c.id === contratoId)
   if (!cuota || !contrato) return
   if (action === 'pagar')    abrirModalPago(cuota, contrato)
   if (action === 'revertir') revertirPago(cuota, contrato)
@@ -1274,7 +1339,7 @@ function onAccionCuota(e) {
 
 function abrirModalPago(cuota, contrato) {
   if (!cuentaDisponible(contrato)) {
-    mostrarError(avisoCuentaPago())
+    mostrarError(avisoCuentaPago(contrato))
     return
   }
   // Guard: una cuota trasladada no se registra como pagada (su capital se roleó al
@@ -1355,7 +1420,7 @@ async function confirmarPago(e) {
   const contratoId = MODAL_CONTRATO_ID
   const cuotas = CRONOGRAMA_CACHE.get(contratoId) || []
   const cuota = cuotas.find(p => p.id === id)
-  const contrato = CONTRATOS_CACHE.find(c => c.id === contratoId)
+  const contrato = CONTRATOS_PAGINA.find(c => c.id === contratoId)
   // Fuente primaria: el programado guardado al abrir el modal (sirve desde la Agenda);
   // fallback al cache por si el modal se abrió de otra forma.
   const programado = MODAL_PROGRAMADO > 0 ? MODAL_PROGRAMADO : Number(cuota?.monto_programado || 0)
@@ -1547,21 +1612,24 @@ async function recargar() {
   // Invalida primero los datos anteriores: si falla la RPC contractual no debe
   // quedar habilitada una exportación con cuentas de una carga previa.
   CUENTAS_PAGO_LISTAS = false
-  CONTRATOS_CACHE = []
   AGENDA_CACHE = []
+  CONTADORES_TABS = { cobrar: null, pagados: null }
   try {
-    const [metricas, contratos, agenda] = await Promise.all([
+    // La tabla por contrato se carga aparte y por páginas (recargarTabla); aquí van
+    // las métricas, la agenda completa (≤ 7 días) y los totales de las pestañas.
+    const [metricas, agenda, contadores] = await Promise.all([
       cargarMetricas(),
-      cargarResumen(),
-      cargarAgenda()
+      cargarAgenda(),
+      cargarContadoresTabla().catch((error) => {
+        console.error('[pagos] no se pudieron contar los contratos por pestaña:', error)
+        return { cobrar: null, pagados: null }
+      }),
     ])
-    CONTRATOS_CACHE = contratos
     AGENDA_CACHE = agenda
+    CONTADORES_TABS = contadores
     let cuentasError = null
     try {
-      const asociadas = await asociarCuentasPantalla(agenda, contratos)
-      CONTRATOS_CACHE = asociadas.contratos
-      AGENDA_CACHE = asociadas.agenda
+      AGENDA_CACHE = asociarCuentasPagoPantalla(agenda, [], await consultarCuentasContractuales([...new Set(agenda.map(c => c.contrato_id).filter(Boolean))])).agenda
       CUENTAS_PAGO_LISTAS = true
     } catch (error) {
       cuentasError = error
@@ -1569,7 +1637,7 @@ async function recargar() {
     renderMetricas(metricas)
     actualizarContadoresTabs()
     renderAgenda()
-    renderTabla()
+    await recargarTabla()   // conserva la página actual (p. ej. tras pagar desde la página 3)
     if (cuentasError) {
       console.error('[pagos] no se pudieron resolver las cuentas contractuales:', cuentasError)
       mostrarError('Los pagos se cargaron, pero no se verificaron sus cuentas de depósito. El registro y la exportación quedaron bloqueados hasta recargar.')
@@ -1590,18 +1658,23 @@ async function recargar() {
   await setupAdminShell({ welcomeFirstName: false, perfil: ok })
   await recargar()
 
-  // Búsqueda y filtro de moneda: re-render ambas vistas (la activa será la visible)
+  // Búsqueda y moneda: la agenda se filtra en memoria al instante; la tabla por
+  // contrato vuelve a pedir su primera página a la base (con debounce al teclear).
   document.getElementById('search')?.addEventListener('input', (e) => {
     FILTRO_TEXTO = e.target.value
     AGENDA_PAGINA = {}   // otro filtro = otra lista: volver a la primera página de cada tramo
+    TABLA_PAGINA = 0
+    EXPANDIDO = null
     renderAgenda()
-    renderTabla()
+    if (TAB_ACTIVO !== 'agenda') programarRecargaTabla()
   })
   document.getElementById('filterMoneda')?.addEventListener('change', (e) => {
     FILTRO_MONEDA = e.target.value
     AGENDA_PAGINA = {}
+    TABLA_PAGINA = 0
+    EXPANDIDO = null
     renderAgenda()
-    renderTabla()
+    if (TAB_ACTIVO !== 'agenda') recargarTabla()
   })
 
   // Tabs: Agenda / Por pagar / Cumplidos / Todos
@@ -1611,9 +1684,12 @@ async function recargar() {
       tab.classList.add('active')
       TAB_ACTIVO = tab.dataset.tab
       EXPANDIDO  = null // colapsar al cambiar de tab
+      TABLA_PAGINA = 0  // otra pestaña = otra lista: empezar por la primera página
+      CONTRATOS_PAGINA = []
+      clearTimeout(TABLA_TIMER)   // una búsqueda a medio teclear no debe pisar la carga de la pestaña
       actualizarVistaActiva()
       if (TAB_ACTIVO === 'agenda') renderAgenda()
-      else renderTabla()
+      else recargarTabla()
     })
   })
 
```

## Diff de `admin/pagos.html` y `css/admin.css`

```diff
diff --git a/admin/pagos.html b/admin/pagos.html
index 7bf130b..295e20a 100644
--- a/admin/pagos.html
+++ b/admin/pagos.html
@@ -32,7 +32,7 @@
   <link rel="stylesheet" href="/css/main.css?v=13">
   <link rel="preload" href="/css/animations.css?v=5" as="style" onload="this.onload=null;this.rel='stylesheet'">
   <link rel="preload" href="/css/dashboard.css?v=13" as="style" onload="this.onload=null;this.rel='stylesheet'">
-  <link rel="preload" href="/css/admin.css?v=21" as="style" onload="this.onload=null;this.rel='stylesheet'">
+  <link rel="preload" href="/css/admin.css?v=22" as="style" onload="this.onload=null;this.rel='stylesheet'">
   <link rel="stylesheet" href="/css/mobile.css?v=9">
   <style id="critical-mobile-fallback">
     @media (max-width: 768px) {
@@ -42,7 +42,7 @@
   <noscript>
     <link rel="stylesheet" href="/css/animations.css?v=5">
     <link rel="stylesheet" href="/css/dashboard.css?v=13">
-    <link rel="stylesheet" href="/css/admin.css?v=21">
+    <link rel="stylesheet" href="/css/admin.css?v=22">
   </noscript>
 </head>
 <body>
@@ -218,6 +218,8 @@
               </tbody>
             </table>
           </div>
+          <!-- Paginación de la tabla (50 contratos por página): la pinta el JS -->
+          <div id="paginacionContratos" class="paginacion-pie"></div>
         </div>
       </section>
 
@@ -325,7 +327,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/pagos.js?v=40"></script>
+  <script type="module" src="/js/admin/pagos.js?v=41"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/css/admin.css b/css/admin.css
index c17958d..d92fa08 100644
--- a/css/admin.css
+++ b/css/admin.css
@@ -1044,8 +1044,12 @@
 
 .agenda-row:hover { background: #f9f6ec; }
 
-/* Pie del tramo paginado: «← Anterior · 1–10 de 42 · Página 1 de 5 · Siguiente →». */
-.agenda-bucket-pie {
+/* Pie paginado («← Anterior · 1–10 de 42 · Página 1 de 5 · Siguiente →»): en cada
+   tramo de la agenda y bajo la tabla por contrato (.paginacion-pie). */
+.paginacion-pie:empty { display: none; }
+.paginacion-pie { margin-top: 10px; border-radius: 10px; border: 1px dashed #e3dcc6; }
+.agenda-bucket-pie,
+.paginacion-pie {
   display: flex;
   align-items: center;
   justify-content: center;
```

## Funciones de pagos.js que NO cambian pero interactúan (transcritas)

```js
function onPagarDesdeAgenda(e) {
  const cuotaId = e.currentTarget.dataset.cuotaId
  const a = AGENDA_CACHE.find(x => x.cuota_id === cuotaId)
  if (!a) return
  // Adaptamos al shape esperado por abrirModalPago: { cuota, contrato }
  const cuota = {
    id: a.cuota_id,
    numero_cuota: a.numero_cuota,
    tipo: a.tipo,
    monto_programado: a.monto_programado,
    fecha_programada: a.fecha_programada,
    estado: a.estado,
  }
  const contrato = {
    id: a.contrato_id,
    numero_contrato: a.numero_contrato,
    moneda: a.moneda,
    cliente: a.cliente,
    cuenta_pago_contrato: a.cuenta_pago_contrato,
  }
  abrirModalPago(cuota, contrato)
}
async function toggleExpand(id) {
  const newId = (EXPANDIDO === id) ? null : id

  // Cerrar el actualmente abierto
  if (EXPANDIDO) {
    const cur = document.querySelector(`.row-contrato[data-id="${EXPANDIDO}"]`)
    if (cur) {
      cur.classList.remove('is-expanded')
      cur.setAttribute('aria-expanded', 'false')
    }
    const curDet = document.querySelector(`.row-detalle[data-parent="${EXPANDIDO}"]`)
    if (curDet) {
      curDet.classList.remove('is-open')
      curDet.classList.add('is-collapsed')
      curDet.setAttribute('aria-hidden', 'true')
    }
  }

  EXPANDIDO = newId
  if (!EXPANDIDO) return

  const next = document.querySelector(`.row-contrato[data-id="${EXPANDIDO}"]`)
  if (next) {
    next.classList.add('is-expanded')
    next.setAttribute('aria-expanded', 'true')
  }
  const nextDet = document.querySelector(`.row-detalle[data-parent="${EXPANDIDO}"]`)
  if (nextDet) {
    nextDet.classList.remove('is-collapsed')
    nextDet.classList.add('is-open')
    nextDet.setAttribute('aria-hidden', 'false')
  }

  // Lazy load del cronograma. Spinner mientras llega.
  const objetivo = EXPANDIDO
  if (!CRONOGRAMA_CACHE.has(objetivo)) {
    try {
      await cargarCronogramaContrato(objetivo)
    } catch (err) {
      console.error(err)
      const cont = document.getElementById(`cronograma-${objetivo}`)
      if (cont) {
        cont.innerHTML = `<p class="text-danger" style="padding: 16px;">No se pudo cargar el cronograma: ${escapeHtml(err.message || 'error')}</p>`
      }
      return
    }
    // Si el user cerró/abrió otro mientras cargaba, no pintamos sobre algo distinto
    if (EXPANDIDO !== objetivo) return
  }
  pintarCronogramaExpandido(objetivo)
}
function abrirModalPago(cuota, contrato) {
  if (!cuentaDisponible(contrato)) {
    mostrarError(avisoCuentaPago(contrato))
    return
  }
  // Guard: una cuota trasladada no se registra como pagada (su capital se roleó al
  // contrato de renovación). La UI ya no ofrece el botón; esto es defensa extra —
  // y el UPDATE de confirmarPago igual exige .eq('estado','pendiente').
  if (cuota.estado === 'trasladado') {
    mostrarError('Esta cuota fue trasladada al contrato de renovación: no se registra como pagada.')
    return
  }
  MODAL_CONTRATO_ID = contrato.id
  const moneda = contrato.moneda || 'PEN'
  // Guardamos el programado/moneda de ESTA cuota: el aviso de pago parcial debe
  // funcionar también desde la Agenda, donde CRONOGRAMA_CACHE puede estar vacío.
  MODAL_PROGRAMADO = Number(cuota.monto_programado || 0)
  MODAL_MONEDA = moneda
  const esRetorno = cuota.tipo === 'retorno'
  const concepto = esRetorno
    ? '<strong style="color: var(--gold);">RETORNO DEL CAPITAL</strong>'
    : cuota.tipo === 'devolucion'
      ? '<strong style="color: var(--gold);">PAGO DE INTERESES</strong>'
      : `Cuota #${cuota.numero_cuota}`
  document.getElementById('p_id').value = cuota.id
  // Hoy en local (no UTC) para que el input date no salga corrido en clientes UTC-5
  const hoyLocal = new Date()
  const yyyy = hoyLocal.getFullYear()
  const mm = String(hoyLocal.getMonth() + 1).padStart(2, '0')
  const dd = String(hoyLocal.getDate()).padStart(2, '0')
  document.getElementById('p_fecha').value = `${yyyy}-${mm}-${dd}`
  document.getElementById('p_monto').value = Number(cuota.monto_programado).toFixed(2)
  document.getElementById('p_resumen').innerHTML = `
    <strong>${escapeHtml(contrato.cliente || '—')}</strong><br>
    Contrato <span class="font-mono">${escapeHtml(contrato.numero_contrato || '—')}</span> ·
    ${concepto} ·
    A pagar el ${formatearFecha(cuota.fecha_programada)}<br>
    Monto a pagar: <strong>${formatearMoneda(cuota.monto_programado, moneda)}</strong>
  `
  document.getElementById('modalPagoError').classList.add('hidden')
  document.getElementById('modalPago').classList.remove('hidden')
}
async function confirmarPago(e) {
  e.preventDefault()
  const errEl = document.getElementById('modalPagoError')
  errEl.classList.add('hidden')

  const id = document.getElementById('p_id').value
  const fecha = document.getElementById('p_fecha').value
  // Redondeamos a 2 decimales: el dinero no debe guardarse con sub-céntimos.
  const monto = Math.round(parseFloat(document.getElementById('p_monto').value) * 100) / 100

  if (!fecha || !monto || monto <= 0) {
    errEl.textContent = 'Completa fecha y monto válidos.'
    errEl.classList.remove('hidden')
    return
  }

  // Rango razonable de la fecha de pago: ni anterior al 2000 ni futura (misma regla
  // que el import de Excel; una fecha absurda distorsiona la reportería/caja).
  const [fy, fm, fd] = String(fecha).split('-').map(Number)
  const dPago = new Date(fy, (fm || 1) - 1, fd || 1)
  const finHoy = new Date(); finHoy.setHours(23, 59, 59, 999)
  if (isNaN(dPago.getTime()) || fy < 2000 || dPago > finHoy) {
    errEl.textContent = 'La fecha del pago no puede ser futura ni anterior al año 2000.'
    errEl.classList.remove('hidden')
    return
  }

  // Advertencia de pago parcial: si el admin marca como `pagado` una cuota con
  // monto menor al programado, la cuota queda cerrada sin trazar el diferencial.
  // Pedir confirmación explícita (no hay esquema para parciales todavía).
  const contratoId = MODAL_CONTRATO_ID
  const cuotas = CRONOGRAMA_CACHE.get(contratoId) || []
  const cuota = cuotas.find(p => p.id === id)
  const contrato = CONTRATOS_PAGINA.find(c => c.id === contratoId)
  // Fuente primaria: el programado guardado al abrir el modal (sirve desde la Agenda);
  // fallback al cache por si el modal se abrió de otra forma.
  const programado = MODAL_PROGRAMADO > 0 ? MODAL_PROGRAMADO : Number(cuota?.monto_programado || 0)
  const moneda = MODAL_MONEDA || contrato?.moneda || 'PEN'
  const epsilon = 0.01
  if (programado > 0 && (programado - monto) > epsilon) {
    const diff = (programado - monto).toFixed(2)
    const ok = confirm(
      `⚠️ Pago parcial: vas a marcar ${moneda} ${monto.toFixed(2)} de los ${moneda} ${programado.toFixed(2)} programados.\n\n` +
      `Diferencia: ${moneda} ${diff}\n\n` +
      `Si confirmas, la cuota queda como pagada y el faltante no se registra en ningún lado.\n\n` +
      `¿Continuar de todos modos?`
    )
    if (!ok) return
  }
  // Sobrepago: el monto manual es MAYOR al programado (típico: un dígito de más).
  // El import de Excel ya rechaza esto; aquí pedimos confirmación explícita en vez
  // de guardarlo en silencio, para no inflar la caja/reportería por un tipeo.
  if (programado > 0 && (monto - programado) > epsilon) {
    const extra = (monto - programado).toFixed(2)
    const ok = confirm(
      `⚠️ Sobrepago: vas a marcar ${moneda} ${monto.toFixed(2)}, MÁS que los ${moneda} ${programado.toFixed(2)} programados.\n\n` +
      `Diferencia de más: ${moneda} ${extra}\n\n` +
      `Revisa que el monto sea correcto antes de continuar.\n\n` +
      `¿Continuar de todos modos?`
    )
    if (!ok) return
  }

  const btn = document.getElementById('btnConfirmarPago')
  btn.disabled = true
  btn.textContent = 'Guardando…'

  try {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) {
      errEl.textContent = 'Tu sesión expiró. Vuelve a iniciar sesión.'
      errEl.classList.remove('hidden')
      return
    }
    await verificarCuentasParaCuotas([{ contrato_id: contratoId, moneda }])
    const { data: filasPagadas, error } = await supabase
      .from('cronograma_pagos')
      .update({
        estado: 'pagado',
        fecha_pago_real: fecha,
        monto_pagado: monto,
        registrado_por: session.user.id
      })
      .eq('id', id)
      .eq('estado', 'pendiente')   // anti-carrera: no pisar una cuota ya pagada en otra pestaña/admin
      .select('id')

    if (error) {
      errEl.textContent = error.message
      errEl.classList.remove('hidden')
      return
    }
    // 0 filas afectadas = la cuota ya estaba pagada (la marcó otra pestaña u otro admin
    // entre que abrimos el modal y confirmamos). Avisamos en vez de pisar el dato.
    if (!filasPagadas || filasPagadas.length === 0) {
      errEl.textContent = 'Esta cuota ya estaba registrada como pagada (quizá desde otra pestaña). Refresca la página para ver el estado actual.'
      errEl.classList.remove('hidden')
      return
    }

    // Invalidar el cache del cronograma del contrato afectado para que se relea al reabrir
    if (contratoId) CRONOGRAMA_CACHE.delete(contratoId)

    // Avisar al cliente (novedad + push + correo). En segundo plano: no demora el toast.
    notificarPagos([id])

    // Guardar datos del pago para el botón WhatsApp del toast de éxito.
    // El teléfono lo traemos de la agenda (donde sí joineamos perfiles.telefono),
    // o lo dejamos null y el botón no se muestra.
    const cuotaAgenda = AGENDA_CACHE.find(a => a.cuota_id === id)
    ULTIMO_PAGO = {
      telefono: cuotaAgenda?.telefono || null,
      nombre: contrato?.cliente || cuotaAgenda?.cliente || '',
      numero_contrato: contrato?.numero_contrato || cuotaAgenda?.numero_contrato || '',
      numero_cuota: cuota?.numero_cuota || cuotaAgenda?.numero_cuota,
      es_retorno: cuota?.tipo === 'retorno' || cuotaAgenda?.tipo === 'retorno',
      es_devolucion: cuota?.tipo === 'devolucion' || cuotaAgenda?.tipo === 'devolucion',
      monto: monto,
      moneda: moneda,
      fecha: fecha,
    }

    cerrarModalPago()
    mostrarExitoConWhatsApp()
    await recargar()
  } catch (err) {
    // Sin catch, un fallo real (getSession/red) restauraba el botón pero no
    // avisaba: el admin podía creer que registró el pago. Mostramos el error.
    console.error('[pagos] confirmarPago falló:', err)
    errEl.textContent = err.message === 'Sin cuenta de pago — requiere conciliación.'
      ? err.message : 'No se pudo registrar el pago. Verifica la cuenta contractual y tu conexión antes de reintentar.'
    errEl.classList.remove('hidden')
  } finally {
    btn.disabled = false
    btn.textContent = 'Marcar como pagado'
  }
}
async function revertirPago(cuota, contrato) {
  if (!confirm(`¿Anular el pago de la cuota #${cuota.numero_cuota}? Volverá a estado pendiente.`)) return

  try {
    const { data: filasAnuladas, error } = await supabase
      .from('cronograma_pagos')
      .update({
        estado: 'pendiente',
        fecha_pago_real: null,
        monto_pagado: null,
        registrado_por: null,
        // Limpiar el sello: si esta cuota se vuelve a pagar, se notifica de nuevo.
        notif_pago_enviada_en: null
      })
      .eq('id', cuota.id)
      .eq('estado', 'pagado')   // anti-carrera: no pisar una cuota que ya cambió en otra pestaña/admin
      .select('id')

    if (error) {
      mostrarError(`No se pudo anular: ${error.message}`)
      return
    }
    if (!filasAnuladas || filasAnuladas.length === 0) {
      mostrarError('No se anuló: la cuota ya no estaba en estado "pagado" (pudo cambiar en otra pestaña).')
      if (contrato?.id) CRONOGRAMA_CACHE.delete(contrato.id)
      await recargar()
      return
    }

    if (contrato?.id) CRONOGRAMA_CACHE.delete(contrato.id)
    mostrarExito('Pago anulado correctamente.')
    await recargar()
  } catch (err) {
    // onAccionCuota llama a revertirPago sin await/catch: sin este try, una caída
    // de red dejaba una promesa rechazada sin manejar y al admin sin aviso.
    console.error('[pagos] revertirPago falló:', err)
    mostrarError('No se pudo anular el pago. Revisa tu conexión e intenta de nuevo.')
  }
}
```

## Preguntas concretas a refutar

1. Carreras: teclear rápido + cambiar de pestaña + pagar; ¿puede pintarse una página de otra
   pestaña/filtro, o quedar `CONTRATOS_PAGINA` desalineado con `TABLA_TOTAL`/`TABLA_PAGINA`?
   ¿El AbortController y los `if (ctrl.signal.aborted) return` cubren todos los caminos?
2. `recargar()` tras pagar/anular: ¿se conserva la página 3? ¿Qué pasa si la página quedó vacía
   (se recorta a la última) o si `EXPANDIDO` apunta a un contrato que ya no está en la página?
3. Escape de la búsqueda para el ILIKE sin ESCAPE (`\`, `%`, `_`): ¿correcto para PostgreSQL?
   ¿Algún carácter que rompa la consulta o permita inyección vía RPC (los parámetros van por
   PostgREST como JSON, no concatenados en cliente)?
4. Cuentas de pago: antes, un fallo de la RPC de cuentas bloqueaba pagar y exportar globalmente
   (`CUENTAS_PAGO_LISTAS`). Ahora la agenda conserva ese candado y la página marca sus filas con
   `cuentas_sin_verificar`. ¿Queda algún camino donde se pueda registrar un pago sin cuenta verificada?
   (Nota: `confirmarPago` vuelve a verificar en servidor con `verificarCuentasParaCuotas` antes del UPDATE.)
5. Contadores de pestañas: 2 llamadas extra con `p_limit=1`; si fallan quedan en «…». ¿Aceptable?
6. Cualquier regresión respecto a la versión anterior (expandir cronograma, revertir, import Excel).
