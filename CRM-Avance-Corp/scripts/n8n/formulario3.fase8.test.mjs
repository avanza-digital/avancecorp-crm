import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import {
  filaEnEscritura, prepararFilaVuelta, codigosFase8, operacionesFase8, verificarFase8, cargarDefinicionOperativaF8,
  VERSION_FASE7, MARGEN_ESCRITURA_MS,
} from './formulario3.fase8.mjs'
import { prepararFilaSegura, codigosFase7, cargarDefinicionOperativaF7, verificarFase7, LATIDO } from './formulario3.fase7.mjs'
import { cargarDefinicionOperativa } from './formulario3.fase6.mjs'
import { cargarDefinicion, WORKFLOW_ID } from './formulario3.workflow.mjs'
import { COLUMNAS, prepararFila } from './formulario3.mjs'

// La vuelta 1883: 21/10/2026 13:30:11 UTC (08:30 Lima).
const AHORA = Date.parse('2026-10-21T13:30:11Z')
const HORA = 60 * 60 * 1000
const iso = desfaseMs => new Date(AHORA + desfaseMs).toISOString()
const fila = (n, extra = {}) => ({
  row_number: n, [COLUMNAS.fecha]: '2026-10-21T07:00:00-05:00', [COLUMNAS.nombre]: 'PERSONA SINTÉTICA ' + n,
  [COLUMNAS.telefono]: '99900' + String(n).padStart(4, '0'), [COLUMNAS.alternativo]: '', [COLUMNAS.moneda]: 'soles',
  [COLUMNAS.capital]: 'de_50,000_a_100,000', [COLUMNAS.ciudad]: 'Lima', [COLUMNAS.intencion]: 'invertir',
  [COLUMNAS.informacion]: 'tasa', [COLUMNAS.asesor]: 'plazo', ...extra,
})
// Tal como la devolvió la hoja en la vuelta 1883: n8n omite las celdas vacías, así que la fila llega solo con row_number y Fecha.
const soloFecha = (n, fecha) => ({ row_number: n, [COLUMNAS.fecha]: fecha })
// La misma fila con todas las columnas presentes y vacías (la otra forma posible de la lectura).
const soloFechaExplicita = (n, fecha) => ({ row_number: n, ...Object.fromEntries(Object.values(COLUMNAS).map(c => [c, ''])), [COLUMNAS.fecha]: fecha })
const RECHAZO_VACIA = ['Falta el nombre completo', 'Faltan ambos teléfonos', 'Capital no reconocido: conserva el rango para revisar', 'Moneda no reconocida: debe indicar soles o dólares']
// Ejecuta el código de un nodo Code como lo hace n8n (runOnceForAllItems).
const ejecutarNodo = (codigo, items, control = { simular_registro: false, inicio_ms: AHORA }) =>
  new Function('$input', '$', codigo)({ all: () => items.map(json => ({ json })) }, () => ({ first: () => ({ json: control }) }))
const nodo = (w, nombre) => w.nodes.find(n => n.name === nombre)
function aplicar(w, ops) {
  const copia = structuredClone(w)
  for (const op of ops) {
    if (op.type === 'updateNodeParameters') Object.assign(nodo(copia, op.nodeName).parameters, op.parameters)
    else throw new Error('Operación no prevista: ' + op.type)
  }
  return copia
}
// Fase 7 tal como la devuelve el MCP: conexiones en diccionario y despublicada.
function fase7Viva() {
  const w = cargarDefinicionOperativaF7()
  const dicc = {}
  for (const c of w.connections) {
    const salidas = (dicc[c.source] ??= { main: [] }).main
    while (salidas.length <= c.sourceIndex) salidas.push([])
    salidas[c.sourceIndex].push({ node: c.target, type: 'main', index: c.targetIndex })
  }
  return { ...w, connections: dicc, active: false, activeVersionId: null, versionId: VERSION_FASE7 }
}

test('la definición de fase 8 es la de fase 7 con solo el código de Preparar leads cambiado y sin tocar los cánones', () => {
  const canon = JSON.stringify(cargarDefinicion()), f6 = JSON.stringify(cargarDefinicionOperativa()), f7 = JSON.stringify(cargarDefinicionOperativaF7())
  const w = cargarDefinicionOperativaF8()
  assert.equal(w.nodes.length, 23)
  assert.equal(w.connections.length, 27)
  assert.ok(verificarFase8(w))
  for (const n of cargarDefinicionOperativaF7().nodes) {
    if (n.name === 'Preparar leads') assert.notEqual(nodo(w, n.name).parameters.jsCode, n.parameters.jsCode)
    else assert.deepEqual(nodo(w, n.name).parameters, n.parameters, n.name)
  }
  assert.throws(() => verificarFase7(w), /Código de fase 7/)
  assert.equal(JSON.stringify(cargarDefinicion()), canon)
  assert.equal(JSON.stringify(cargarDefinicionOperativa()), f6)
  assert.equal(JSON.stringify(cargarDefinicionOperativaF7()), f7)
})

test('una fila con solo la fecha reciente se omite esta vuelta; vieja, ilegible o con algún dato más se rechaza', () => {
  const reciente = soloFecha(277, '2026-10-21T07:27:54-05:00')
  assert.equal(filaEnEscritura(reciente, AHORA), true)
  assert.equal(prepararFilaVuelta(reciente, AHORA), null)
  assert.equal(filaEnEscritura(soloFechaExplicita(277, '2026-10-21T07:27:54-05:00'), AHORA), true)
  assert.equal(prepararFilaVuelta(soloFechaExplicita(277, '2026-10-21T07:27:54-05:00'), AHORA), null)
  // Dentro del margen por ambos lados, inclusive; fuera de él, se rechaza como hasta ahora.
  for (const [desfase, esperado] of [[-MARGEN_ESCRITURA_MS, true], [-MARGEN_ESCRITURA_MS - 1000, false], [HORA, true], [MARGEN_ESCRITURA_MS + 1000, false]]) {
    assert.equal(filaEnEscritura(soloFecha(277, iso(desfase)), AHORA), esperado, String(desfase))
  }
  const vieja = soloFecha(277, iso(-MARGEN_ESCRITURA_MS - HORA))
  assert.deepEqual(prepararFilaVuelta(vieja, AHORA), prepararFilaSegura(vieja))
  assert.deepEqual(prepararFilaVuelta(vieja, AHORA).errores, RECHAZO_VACIA)
  // Fecha ilegible o número de serie de Sheets: no se adivina, se rechaza.
  for (const fecha of ['ayer', '46216.5', '21/10/2026']) assert.deepEqual(prepararFilaVuelta(soloFecha(277, fecha), AHORA).errores, RECHAZO_VACIA, fecha)
  // Una fila sin nada sigue sin salir, como siempre.
  for (const vacia of [soloFecha(277, ''), soloFechaExplicita(277, ''), { row_number: 277 }]) {
    assert.equal(filaEnEscritura(vacia, AHORA), false)
    assert.equal(prepararFilaVuelta(vacia, AHORA), null)
    assert.equal(prepararFila(vacia), null)
  }
  // Con cualquier otro dato ya no está «en escritura»: la juzga la regla de siempre.
  const conNombre = { ...reciente, [COLUMNAS.nombre]: 'PERSONA SINTÉTICA' }
  assert.equal(filaEnEscritura(conNombre, AHORA), false)
  assert.deepEqual(prepararFilaVuelta(conNombre, AHORA).errores, RECHAZO_VACIA.slice(1))
  const completa = fila(2)
  assert.equal(filaEnEscritura(completa, AHORA), false)
  assert.deepEqual(prepararFilaVuelta(completa, AHORA), prepararFila(completa))
  // Una celda rara con solo la fecha va a revisión por la celda, no se omite.
  const rara = { ...reciente, [COLUMNAS.ciudad]: true }
  assert.equal(filaEnEscritura(rara, AHORA), false)
  assert.deepEqual(prepararFilaVuelta(rara, AHORA).errores, ['Celda con un dato inesperado en «ciudad»'])
  for (const ahora of [undefined, NaN, '1']) assert.throws(() => filaEnEscritura(reciente, ahora), /hora de la vuelta/)
  for (const n of [undefined, 1, 'x']) assert.throws(() => prepararFilaVuelta({ ...reciente, row_number: n }, AHORA), /número de fila/)
})

test('el nodo Preparar leads omite la fila a medio escribir, conserva pairedItem y toma la hora de la vuelta del control', () => {
  const { preparar7, preparar8 } = codigosFase8()
  assert.ok(preparar8.startsWith(preparar7.slice(0, preparar7.indexOf('\nconst entradas='))))
  assert.ok(preparar8.includes(prepararFilaSegura.toString()))
  assert.ok(preparar8.includes('\nconst MARGEN_ESCRITURA_MS = ' + MARGEN_ESCRITURA_MS + '\n'))
  assert.ok(preparar8.includes('$("Control del envío").first().json.inicio_ms'))
  const lectura = [fila(2), soloFecha(3, iso(-HORA)), fila(4), soloFecha(5, iso(-MARGEN_ESCRITURA_MS - HORA))]
  const salida = ejecutarNodo(preparar8, lectura)
  assert.deepEqual(salida.map(i => [i.json.fila, i.json.mapeo_correcto]), [[2, true], [4, true], [5, false]])
  assert.deepEqual(salida.map(i => i.pairedItem.item), [0, 2, 3])
  // La misma fila, leída dos días después sin completarse, se rechaza y avisa.
  const tarde = ejecutarNodo(preparar8, [fila(2), soloFecha(3, iso(-HORA))], { simular_registro: false, inicio_ms: AHORA + MARGEN_ESCRITURA_MS + HORA })
  assert.deepEqual(tarde.map(i => [i.json.fila, i.json.mapeo_correcto]), [[2, true], [3, false]])
  // La fase 7 la rechazaba en la primera vuelta: eso es lo que cambia.
  assert.deepEqual(ejecutarNodo(preparar7, [fila(2), soloFecha(3, iso(-HORA))]).map(i => [i.json.fila, i.json.mapeo_correcto]), [[2, true], [3, false]])
  // Codex (P2): si la lectura entera son filas a medio escribir, sin las demás claves, no es un cambio de
  // cabecera: se omiten todas. La fase 7 ahí frenaba la vuelta con «Faltan columnas».
  const soloEnEscritura = [soloFecha(277, iso(-HORA)), soloFecha(278, iso(-2 * HORA))]
  assert.deepEqual(ejecutarNodo(preparar8, soloEnEscritura), [])
  assert.throws(() => ejecutarNodo(preparar7, soloEnEscritura), /Faltan columnas/)
  // Pasado el margen la fila ya no está en escritura y la protección de cabecera es la de la fase 7.
  assert.throws(() => ejecutarNodo(preparar8, [soloFecha(277, iso(-MARGEN_ESCRITURA_MS - HORA))]), /Faltan columnas/)
  assert.throws(() => ejecutarNodo(preparar8, [soloFecha(3, iso(-HORA))], { simular_registro: false }), /hora de la vuelta/)
  const sinColumna = fila(2); delete sinColumna[COLUMNAS.ciudad]
  assert.throws(() => ejecutarNodo(preparar8, [sinColumna]), /Faltan columnas/)
})

test('la transición solo parte de la fase 7 exacta y despublicada', () => {
  const viva = fase7Viva()
  const ops = operacionesFase8(viva)
  assert.deepEqual(ops.map(o => [o.type, o.nodeName]), [['updateNodeParameters', 'Preparar leads']])
  const nueva = aplicar(viva, ops)
  assert.ok(verificarFase8(nueva))
  const esperado = cargarDefinicionOperativaF8()
  for (const n of esperado.nodes) assert.deepEqual(nodo(nueva, n.name).parameters, n.parameters, n.name)
  assert.deepEqual(nueva.nodes.map(n => n.credentials), viva.nodes.map(n => n.credentials))
  assert.deepEqual(nueva.settings, viva.settings)
  for (const cambiar of [
    w => { w.active = true },
    w => { w.activeVersionId = 'publicada' },
    w => { w.versionId = 'otra-version' },
    w => { delete w.versionId },
    w => { nodo(w, 'Preparar leads').parameters.jsCode += '\n//' },
    w => { nodo(w, 'Resumen de importación').parameters.jsCode = codigosFase7().resumen6 },
    w => { nodo(w, LATIDO).disabled = true },
    w => { nodo(w, 'Leer leads filtrados').credentials.googleSheetsOAuth2Api.id = 'otra' },
    w => { w.settings.errorWorkflow = 'otro' },
  ]) { const w = structuredClone(viva); cambiar(w); assert.throws(() => operacionesFase8(w)) }
  assert.throws(() => operacionesFase8(nueva), /ya está aplicada/)
})

test('el gate posterior rechaza código sin aplicar o alterado y exige la versión publicada', () => {
  const base = aplicar(fase7Viva(), operacionesFase8(fase7Viva()))
  assert.throws(() => verificarFase8({ ...structuredClone(base), nodes: base.nodes.map(n => n.name === 'Preparar leads' ? { ...n, parameters: { jsCode: codigosFase8().preparar7 } } : n) }), /fase 8 no aplicado/)
  for (const cambiar of [
    w => { nodo(w, 'Preparar leads').parameters.jsCode += '\n//' },
    w => { nodo(w, 'Resumen de importación').parameters.jsCode = codigosFase7().resumen6 },
    w => { nodo(w, LATIDO).disabled = true },
    w => { w.nodes = w.nodes.filter(n => n.name !== LATIDO) },
    w => { w.settings.saveDataSuccessExecution = 'all' },
    w => { nodo(w, 'Leer leads filtrados').parameters.options.dataLocationOnSheet.values.range = 'A1:K' },
  ]) { const w = structuredClone(base); cambiar(w); assert.throws(() => verificarFase8(w)) }
  const publicado = { ...structuredClone(base), active: true, versionId: 'v8', activeVersionId: 'v8' }
  assert.ok(verificarFase8(publicado, undefined, { publicado: true }))
  for (const p2 of [{ activeVersionId: VERSION_FASE7 }, { active: false }, { versionId: undefined, activeVersionId: undefined }]) {
    assert.throws(() => verificarFase8({ ...publicado, ...p2 }, undefined, { publicado: true }), /publicada/)
  }
})

test('las constantes de la fase 8 coinciden con lo publicado y documentado', () => {
  assert.equal(MARGEN_ESCRITURA_MS, 48 * 60 * 60 * 1000)
  assert.match(VERSION_FASE7, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
  assert.ok(readFileSync(new URL('../../docs/N8N-FORMULARIO3-FASE7.md', import.meta.url), 'utf8').includes(VERSION_FASE7.slice(0, 8)))
  assert.equal(WORKFLOW_ID, 'BjI5m1PKVWhO0NDb')
})
