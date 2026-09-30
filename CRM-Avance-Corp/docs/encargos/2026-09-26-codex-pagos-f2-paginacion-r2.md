ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia,
RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo (2.ª ronda, solo los dos hallazgos): Portal · Pagos F2 paginación

En la 1.ª ronda diste BLOCK por: P1 «total_count no viaja cuando la página queda vacía → el
recorte nunca ocurre y se pinta tabla vacía»; P2 «recargar() sin protección contra recargas
solapadas». Se aceptaron ambos. Juzga SOLO si las correcciones cierran esos dos hallazgos sin
abrir otros. Contexto completo (RPC, núcleo, flujo) en la ronda anterior; aquí va lo que cambió.

## Corrección P1 — núcleo `pagos-tabla-core.js` (fragmento nuevo)

```js
 * `total_count` viene repetido en cada fila. SIN filas el total es DESCONOCIDO, no 0:
 * `count(*) OVER()` no tiene dónde viajar cuando el OFFSET deja la página vacía
 * (hallazgo P1 de Codex, 26/09). Devuelve null en ese caso para que quien llama
 * sondee la primera página antes de dar la lista por vacía.
 */
export function totalDeRespuesta(filas) {
  if (!Array.isArray(filas) || filas.length === 0) return null
  return numero(filas[0].total_count)
}

/** Página pedida más allá del final: sin filas y no era la primera. */
export function paginaFueraDeRango(filas, pagina) {
  return Array.isArray(filas) && filas.length === 0 && Number.isInteger(pagina) && pagina > 0
}

/** Última página válida (base 0) para un total; 0 si no hay nada. */
export function ultimaPagina(total, porPagina = PAGE_SIZE_TABLA) {
  const n = Number.isFinite(total) && total > 0 ? total : 0
  const tam = Number.isInteger(porPagina) && porPagina > 0 ? porPagina : PAGE_SIZE_TABLA
  return Math.max(0, Math.ceil(n / tam) - 1)
}
```

## Corrección P1 — `recargarTabla()` y carga (fragmentos vigentes de pagos.js)

```js
async function cargarPaginaContratos({ tab, busqueda, moneda, pagina, porPagina = PAGE_SIZE_TABLA }, signal) {
  const params = parametrosTabla({ tab, busqueda, moneda, pagina, porPagina })
  let consulta = supabase.rpc('pagos_admin_resumen_contratos', params)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw error
  const filas = Array.isArray(data) ? data : []
  // total === null cuando la página vino vacía: la RPC no puede decir el total sin filas.
  return { contratos: filas.map(mapearFilaResumen), total: totalDeRespuesta(filas) }
}
async function cargarContadoresTabla() {
  const [cobrar, pagados] = await Promise.all(['cobrar', 'pagados'].map(async (tab) => {
    const { total } = await cargarPaginaContratos({ tab, busqueda: '', moneda: '', pagina: 0, porPagina: 1 })
    return total ?? 0   // primera página vacía = de verdad no hay contratos en esa pestaña
  }))
  return { cobrar, pagados }
}
async function recargarTabla() {
  if (TAB_ACTIVO === 'agenda') return
  if (TABLA_ABORT) TABLA_ABORT.abort()
  const ctrl = new AbortController()
  TABLA_ABORT = ctrl
  const tbody = document.getElementById('tablaContratos')
  if (tbody && CONTRATOS_PAGINA.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" class="table-empty">Cargando…</td></tr>`
  }
  try {
    const filtros = { tab: TAB_ACTIVO, busqueda: FILTRO_TEXTO, moneda: FILTRO_MONEDA }
    let res = await cargarPaginaContratos({ ...filtros, pagina: TABLA_PAGINA }, ctrl.signal)
    if (paginaFueraDeRango(res.contratos, TABLA_PAGINA)) {
      // La página quedó más allá del final (p. ej. se pagó el último contrato de la última
      // página). Sin filas la RPC no puede decir el total, así que se sondea la primera
      // página con 1 fila y se salta a la última página válida (hallazgo P1 de Codex).
      const sonda = await cargarPaginaContratos({ ...filtros, pagina: 0, porPagina: 1 }, ctrl.signal)
      const total = sonda.total ?? 0
      TABLA_PAGINA = ultimaPagina(total, PAGE_SIZE_TABLA)
      res = total > 0
        ? await cargarPaginaContratos({ ...filtros, pagina: TABLA_PAGINA }, ctrl.signal)
        : { contratos: [], total: 0 }
    }
    if (ctrl.signal.aborted) return
    TABLA_TOTAL = res.total ?? 0
    CONTRATOS_PAGINA = await asociarCuentasPagina(res.contratos)
    if (ctrl.signal.aborted) return
    renderTabla()
  } catch (err) {
    if (ctrl.signal.aborted || err?.name === 'AbortError') return   // otra carga la reemplazó
    console.error('[pagos] no se pudo cargar la tabla por contrato:', err)
    CONTRATOS_PAGINA = []
    TABLA_TOTAL = 0
    renderTabla()
    mostrarError('No se pudo cargar la tabla por contrato. Revisa tu conexión e intenta de nuevo.')
  } finally {
    if (TABLA_ABORT === ctrl) TABLA_ABORT = null
  }
}
```

## Corrección P2 — `recargar()` con generación (fragmento vigente)

```js
let RECARGA_GEN = 0   // dos recargas solapadas (dos pagos seguidos): solo la más nueva escribe estado

async function recargar() {
  const gen = ++RECARGA_GEN
  const vigente = () => gen === RECARGA_GEN
  // Invalida primero los datos anteriores: si falla la RPC contractual no debe
  // quedar habilitada una exportación con cuentas de una carga previa.
  CUENTAS_PAGO_LISTAS = false
  AGENDA_CACHE = []
  CONTADORES_TABS = { cobrar: null, pagados: null }
  try {
    // La tabla por contrato se carga aparte y por páginas (recargarTabla); aquí van
    // las métricas, la agenda completa (≤ 7 días) y los totales de las pestañas.
    const [metricas, agenda, contadores] = await Promise.all([
      cargarMetricas(),
      cargarAgenda(),
      cargarContadoresTabla().catch((error) => {
        console.error('[pagos] no se pudieron contar los contratos por pestaña:', error)
        return { cobrar: null, pagados: null }
      }),
    ])
    if (!vigente()) return   // una recarga más nueva ya está en marcha: no pisar con datos viejos
    AGENDA_CACHE = agenda
    CONTADORES_TABS = contadores
    let cuentasError = null
    try {
      const filas = await consultarCuentasContractuales([...new Set(agenda.map(c => c.contrato_id).filter(Boolean))])
      if (!vigente()) return
      AGENDA_CACHE = asociarCuentasPagoPantalla(agenda, [], filas).agenda
      CUENTAS_PAGO_LISTAS = true
    } catch (error) {
      if (!vigente()) return
      cuentasError = error
    }
    renderMetricas(metricas)
    actualizarContadoresTabs()
    renderAgenda()
    await recargarTabla()   // conserva la página actual (p. ej. tras pagar desde la página 3)
    if (cuentasError) {
      console.error('[pagos] no se pudieron resolver las cuentas contractuales:', cuentasError)
      mostrarError('Los pagos se cargaron, pero no se verificaron sus cuentas de depósito. El registro y la exportación quedaron bloqueados hasta recargar.')
    }
  } catch (err) {
    if (!vigente()) return
    console.error(err)
    actualizarContadoresTabs()
    renderAgenda()
    renderTabla()
    mostrarError('No se pudieron cargar los pagos ni sus cuentas de depósito. El registro y la exportación quedaron bloqueados.')
  }
}
```

## Pruebas añadidas (pasan; 134/134 en total)

```js
test('el total sale de la primera fila; sin filas es DESCONOCIDO (null), no 0', () => {
  assert.equal(totalDeRespuesta([filaRpc, filaRpc]), 651)
  assert.equal(totalDeRespuesta([]), null)
  assert.equal(totalDeRespuesta(undefined), null)
})

test('una página vacía que no es la primera está fuera de rango', () => {
  assert.equal(paginaFueraDeRango([], 2), true)
  assert.equal(paginaFueraDeRango([], 0), false)
  assert.equal(paginaFueraDeRango([filaRpc], 2), false)
})

test('última página válida para un total', () => {
  assert.equal(ultimaPagina(101, 50), 2)
  assert.equal(ultimaPagina(100, 50), 1)
  assert.equal(ultimaPagina(0, 50), 0)
  assert.equal(ultimaPagina(1, 50), 0)
})

test('escenario Codex P1: 101 contratos, página 3 (índice 2); se paga uno y quedan 100 → se muestra 51–100 de 100', () => {
  // La página 3 vuelve vacía y sin total: fuera de rango → se sondea la primera página (total 100)
  assert.equal(paginaFueraDeRango([], 2), true)
  const totalSondeado = 100
  const pagina = ultimaPagina(totalSondeado, 50)
  assert.equal(pagina, 1)
  const plan = planPagina({ total: totalSondeado, porPagina: 50, pagina })
  assert.equal(etiquetaPagina(plan), '51–100 de 100 · Página 2 de 2')
  assert.equal(plan.haySiguiente, false)
  assert.equal(plan.hayAnterior, true)
})
```

## Preguntas

1. P1: con 101 contratos en «Por pagar», página índice 2, se paga el único contrato de esa
   página → la RPC devuelve [] → ¿el flujo termina mostrando 51–100 de 100 (página 2 de 2)?
   ¿Y si el total baja a 0 (última cuota de todo)? ¿Y si la sonda se aborta a mitad?
2. P2: ¿la generación cubre todos los `await` de `recargar()`? ¿Queda algún camino que escriba
   estado viejo o deje `CUENTAS_PAGO_LISTAS=false` para siempre? Nota: `recargarTabla()` tiene su
   propio AbortController y lo llama la recarga vigente.
3. `cargarContadoresTabla` usa `total ?? 0` para la primera página: ¿correcto?
