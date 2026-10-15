import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import {
  prepararFilaSegura, estadoClienteCorrecto, cerrarVuelta, codigosFase7, operacionesFase7, verificarFase7,
  cargarDefinicionOperativaF7, definirBancoF7, nodoLatido, TABLA_LATIDO, LATIDO, VERSION_FASE6,
} from './formulario3.fase7.mjs'
import { cargarDefinicionOperativa, seleccionarPendientes } from './formulario3.fase6.mjs'
import { cargarDefinicion, WORKFLOW_ID } from './formulario3.workflow.mjs'
import { COLUMNAS, prepararFila } from './formulario3.mjs'
import { clasificarRespuestaPuerta } from '../../supabase/functions/crm-importar-leads/resultado-importacion.ts'

const RUTA_CLASIFICADOR = new URL('../../supabase/functions/crm-importar-leads/resultado-importacion.ts', import.meta.url)
const fila = (n, extra = {}) => ({
  row_number: n, [COLUMNAS.fecha]: '2026-10-15T10:00:00-05:00', [COLUMNAS.nombre]: 'PERSONA SINTÉTICA ' + n,
  [COLUMNAS.telefono]: '99900' + String(n).padStart(4, '0'), [COLUMNAS.alternativo]: '', [COLUMNAS.moneda]: 'soles',
  [COLUMNAS.capital]: 'de_50,000_a_100,000', [COLUMNAS.ciudad]: 'Lima', [COLUMNAS.intencion]: 'invertir',
  [COLUMNAS.informacion]: 'tasa', [COLUMNAS.asesor]: 'plazo', ...extra,
})
// Ejecuta el código de un nodo Code como lo hace n8n (runOnceForAllItems).
const ejecutarNodo = (codigo, items, control = { simular_registro: false }) =>
  new Function('$input', '$', codigo)({ all: () => items.map(json => ({ json })) }, () => ({ first: () => ({ json: control }) }))
const nodo = (w, nombre) => w.nodes.find(n => n.name === nombre)
// Aplica las operaciones del MCP sobre una copia, con conexiones en el formato de n8n.
function aplicar(w, ops) {
  const copia = structuredClone(w)
  for (const op of ops) {
    if (op.type === 'updateNodeParameters') Object.assign(nodo(copia, op.nodeName).parameters, op.parameters)
    else if (op.type === 'addNode') copia.nodes.push(structuredClone(op.node))
    else if (op.type === 'setNodeSettings') Object.assign(nodo(copia, op.nodeName), op.settings)
    else if (op.type === 'addConnection') {
      const salidas = (copia.connections[op.source] ??= { main: [] }).main
      while (salidas.length <= op.sourceIndex) salidas.push([])
      salidas[op.sourceIndex].push({ node: op.target, type: 'main', index: op.targetIndex })
    } else if (op.type === 'updateNodeGroup') copia.nodeGroups = copia.nodeGroups.map(g => g.name === op.groupName ? { ...g, nodeNames: op.nodeNames } : g)
    else throw new Error('Operación no prevista: ' + op.type)
  }
  return copia
}
// Fase 6 tal como la devuelve el MCP: conexiones en diccionario y despublicada.
function fase6Viva() {
  const w = cargarDefinicionOperativa()
  const dicc = {}
  for (const c of w.connections) {
    const salidas = (dicc[c.source] ??= { main: [] }).main
    while (salidas.length <= c.sourceIndex) salidas.push([])
    salidas[c.sourceIndex].push({ node: c.target, type: 'main', index: c.targetIndex })
  }
  return { ...w, connections: dicc, active: false, activeVersionId: null, versionId: VERSION_FASE6 }
}

test('la definición de fase 7 reproduce fase 6 más el latido sin tocar los cánones', () => {
  const canon = JSON.stringify(cargarDefinicion()), f6 = JSON.stringify(cargarDefinicionOperativa())
  const w = cargarDefinicionOperativaF7()
  assert.equal(w.nodes.length, 23)
  assert.equal(w.connections.length, 27)
  assert.ok(verificarFase7(w))
  assert.equal(nodo(w, LATIDO).parameters.dataTableId.value, TABLA_LATIDO)
  assert.equal(JSON.stringify(cargarDefinicion()), canon)
  assert.equal(JSON.stringify(cargarDefinicionOperativa()), f6)
})

test('una celda de tipo inesperado deja solo esa fila para revisar', () => {
  const buena = fila(2), rara = fila(3, { [COLUMNAS.ciudad]: true })
  assert.deepEqual(prepararFilaSegura(buena), prepararFila(buena))
  const revisar = prepararFilaSegura(rara)
  assert.equal(revisar.mapeo_correcto, false)
  assert.deepEqual(revisar.errores, ['Celda con un dato inesperado en «ciudad»'])
  assert.equal(revisar.huella_material, prepararFilaSegura(structuredClone(rara)).huella_material)
  assert.notEqual(revisar.huella_material, prepararFilaSegura(fila(3, { [COLUMNAS.ciudad]: false })).huella_material)
  assert.ok(!JSON.stringify(revisar.payload).includes('PERSONA'))
  // La selección del lote la acepta y sigue sin enviar al CRM (va a revisión).
  assert.equal(seleccionarPendientes([{ json: { ...revisar, huella: 'b'.repeat(64) } }], 0)[0].json.mapeo_correcto, false)
  for (const n of [undefined, 1, 'x']) assert.throws(() => prepararFilaSegura({ ...rara, row_number: n }), /número de fila/)
})

test('el nodo Preparar leads sigue con las demás filas y frena solo si cambia la cabecera', () => {
  const { preparar7 } = codigosFase7()
  const salida = ejecutarNodo(preparar7, [fila(2), fila(3, { [COLUMNAS.nombre]: true }), fila(4)])
  assert.deepEqual(salida.map(i => [i.json.fila, i.json.mapeo_correcto]), [[2, true], [3, false], [4, true]])
  assert.deepEqual(salida.map(i => i.pairedItem.item), [0, 1, 2])
  const sinColumna = fila(2); delete sinColumna[COLUMNAS.ciudad]
  assert.throws(() => ejecutarNodo(preparar7, [sinColumna]), /Faltan columnas/)
})

test('cerrarVuelta reúne revisiones y pendientes en un solo mensaje sin datos de contacto', () => {
  const lote = [
    { fila: 2, resultado: 'importado', estado: 'IMPORTADO ✓' },
    { fila: 3, resultado: 'rechazado', estado: 'RECHAZADO: dato privado' },
    { fila: 5, resultado: 'ya_cliente', estado: 'YA ES CLIENTE (asesor: Nombre Privado): NO se pudo anotar (nadie a cargo de este cliente)' },
    { fila: 6, resultado: 'pendiente', estado: 'PENDIENTE' },
  ]
  assert.throws(() => cerrarVuelta(lote, false), e =>
    e.message === 'Revisar filas de la hoja: 3 (rechazada), 5 (cliente sin registrar). Pendientes para reintentar: 6.' &&
    !/privado/i.test(e.message))
  assert.throws(() => cerrarVuelta([lote[3]], false), e => e.message === 'Pendientes para reintentar: 6.')
  assert.throws(() => cerrarVuelta([lote[1]], false), e => e.message === 'Revisar filas de la hoja: 3 (rechazada).')
  const ok = cerrarVuelta([lote[0], { fila: 7, resultado: 'ya_cliente', estado: 'YA ES CLIENTE: reingreso registrado en su ficha' }, { fila: 8, resultado: 'aplazado' }], false)
  assert.deepEqual(ok.resultados, { importado: 1, ya_cliente: 1, aplazado: 1 })
  assert.throws(() => cerrarVuelta([{ fila: 9, resultado: 'aplazado' }], false), /Sin avance/)
  assert.throws(() => cerrarVuelta([{ fila: 9, resultado: 'otro' }], false), /Falta el recibo/)
  const { resumen7 } = codigosFase7()
  assert.throws(() => ejecutarNodo(resumen7, lote), /^Error: Revisar filas de la hoja: 3 \(rechazada\)/)
  assert.equal(ejecutarNodo(resumen7, [lote[0]])[0].json.resultados.importado, 1)
})

test('«ya es cliente» solo es correcto cuando el CRM dejó el seguimiento anotado', () => {
  const casos = []
  for (const asesor of [undefined, 'Ana Pérez']) {
    const v = asesor ? { asesor } : {}
    const r = extra => clasificarRespuestaPuerta({ resultado: 'ya_cliente', veredicto: v, ...extra }).estado
    casos.push(
      [r({ reingreso: { ok: true } }), true],
      [r({ reingreso: { ok: true, repetido: true } }), true],
      [r({ reingreso: { ok: false, error: 'P0001: algo' } }), false],
      [r({ solicitud: { ok: true, repetido: true } }), true],
      [r({ solicitud: { ok: true } }), true],
      [r({ solicitud: { ok: true, sin_tarea: true } }), false],
      [r({ solicitud: { ok: false, vetado: true } }), true],
      [r({ solicitud: { ok: false, sin_ficha: true } }), false],
      [r({ solicitud: { ok: false, error: 'x' } }), false],
      [r({}), false],
    )
  }
  for (const [estado, esperado] of casos) assert.equal(estadoClienteCorrecto(estado), esperado, estado)
  for (const raro of [null, '', 'YA ES CLIENTE: algo nuevo', 'IMPORTADO ✓', 'YA ES CLIENTE: reingreso registrado en su ficha extra']) assert.equal(estadoClienteCorrecto(raro), false)
  // Contraejemplo de Codex: el texto de un error no puede pasar por el nombre del asesor.
  const absorbido = clasificarRespuestaPuerta({ resultado: 'ya_cliente', veredicto: { asesor: 'Ana' }, reingreso: { ok: false, error: 'x): no se registra seguimiento («No insistir»' } }).estado
  assert.match(absorbido, /NO se pudo anotar/)
  assert.equal(estadoClienteCorrecto(absorbido), false)
  assert.equal(estadoClienteCorrecto('YA ES CLIENTE (asesor: Ana): x (asesor: B): reingreso registrado en su ficha'), false)
})

test('los textos aceptados existen en el clasificador del CRM', () => {
  const fuente = readFileSync(RUTA_CLASIFICADOR, 'utf8')
  for (const t of ['reingreso ya anotado en su ficha', 'reingreso registrado en su ficha', 'solicitud ya anotada en su ficha',
    'solicitud anotada y tarea para su analista', 'no se registra seguimiento («No insistir»)', 'YA ES CLIENTE', '(asesor: ']) assert.ok(fuente.includes(t), t)
})

test('la transición solo parte de la fase 6 exacta y despublicada', () => {
  const viva = fase6Viva()
  const ops = operacionesFase7(viva)
  assert.deepEqual(ops.map(o => o.type), ['updateNodeParameters', 'updateNodeParameters', 'addNode', 'setNodeSettings', 'addConnection', 'updateNodeGroup'])
  const nueva = aplicar(viva, ops)
  assert.ok(verificarFase7(nueva))
  const esperado = cargarDefinicionOperativaF7()
  for (const n of esperado.nodes) assert.deepEqual(nodo(nueva, n.name).parameters, n.parameters, n.name)
  assert.deepEqual(nueva.nodes.map(n => n.credentials), [...viva.nodes.map(n => n.credentials), undefined])
  assert.deepEqual(nueva.settings, viva.settings)
  for (const cambiar of [
    w => { w.active = true },
    w => { w.activeVersionId = 'publicada' },
    w => { w.versionId = 'otra-version' },
    w => { delete w.versionId },
    w => { nodo(w, 'Preparar leads').parameters.jsCode += '\n//' },
    w => { nodo(w, 'Leer leads filtrados').credentials.googleSheetsOAuth2Api.id = 'otra' },
    w => { w.settings.errorWorkflow = 'otro' },
  ]) { const w = structuredClone(viva); cambiar(w); assert.throws(() => operacionesFase7(w)) }
  assert.throws(() => operacionesFase7(nueva), /ya está aplicada|publicar|Código/)
  assert.throws(() => operacionesFase7(viva, '1foRUzITWOnUJsNf/'), /tabla del latido/)
})

test('el gate posterior rechaza un latido mal colocado o código sin aplicar', () => {
  const base = aplicar(fase6Viva(), operacionesFase7(fase6Viva()))
  for (const cambiar of [
    w => { nodo(w, LATIDO).position = [1420, 600] },
    w => { nodo(w, LATIDO).disabled = true },
    w => { nodo(w, LATIDO).executeOnce = false },
    w => { nodo(w, LATIDO).parameters.dataTableId.value = '1foRUzITWOnUJsNf' },
    w => { w.connections['Leer leads filtrados'].main[0].push({ node: LATIDO, type: 'main', index: 0 }) },
    w => {
      w.connections['Identificar fila'].main[0] = w.connections['Identificar fila'].main[0].filter(d => d.node !== LATIDO)
      w.connections['Leer leads filtrados'].main[0].push({ node: LATIDO, type: 'main', index: 0 })
    },
    w => { w.connections[LATIDO] = { main: [[{ node: 'Enviar al CRM', type: 'main', index: 0 }]] } },
    w => { nodo(w, 'Resumen de importación').parameters.jsCode = codigosFase7().resumen6 },
    w => { w.nodes = w.nodes.filter(n => n.name !== LATIDO) },
    w => { w.settings.saveDataSuccessExecution = 'all' },
  ]) { const w = structuredClone(base); cambiar(w); assert.throws(() => verificarFase7(w)) }
  // Los valores por defecto que n8n omite al guardar no cuentan como cambio.
  const guardado = structuredClone(base)
  const p = nodo(guardado, LATIDO).parameters
  delete p.resource; delete p.options; delete p.filters.conditions[0].condition
  assert.ok(verificarFase7(guardado))
  for (const cambiar of [w => { nodo(w, LATIDO).retryOnFail = true }, w => { nodo(w, LATIDO).alwaysOutputData = true }]) {
    const w = structuredClone(base); cambiar(w); assert.throws(() => verificarFase7(w))
  }
  // Publicado: la versión activa debe ser la inspeccionada.
  const publicado = { ...structuredClone(base), active: true, versionId: 'v7', activeVersionId: 'v7' }
  assert.ok(verificarFase7(publicado, TABLA_LATIDO, { publicado: true }))
  for (const p2 of [{ activeVersionId: VERSION_FASE6 }, { active: false }, { versionId: undefined, activeVersionId: undefined }]) {
    assert.throws(() => verificarFase7({ ...publicado, ...p2 }, TABLA_LATIDO, { publicado: true }), /publicada/)
  }
})

test('el banco parte de fase 7, no usa credenciales y aísla sus tablas', () => {
  const fuente = readFileSync(new URL('./formulario3.mjs', import.meta.url), 'utf8')
  const banco = definirBancoF7(fuente, { tablaRecibos: 'PruebaRecibos0001', tablaLatido: 'PruebaLatido00001', filas: [fila(2)] })
  assert.equal(banco.nodes.length, 23)
  assert.ok(banco.nodes.every(n => !n.credentials))
  assert.equal(nodo(banco, LATIDO).parameters.dataTableId.value, 'PruebaLatido00001')
  for (const n of ['Omitir filas confirmadas', 'Registrar resultado']) assert.equal(nodo(banco, n).parameters.dataTableId.value, 'PruebaRecibos0001')
  assert.equal(nodo(banco, 'Preparar leads').parameters.jsCode, codigosFase7().preparar7)
  assert.equal(nodo(banco, 'Importar en CRM').type, 'n8n-nodes-base.code')
  assert.match(nodo(banco, 'Control del envío').parameters.jsonOutput, /enviar_crm:true,simular_registro:false/)
  for (const tablas of [{ tablaRecibos: '1foRUzITWOnUJsNf', tablaLatido: 'x' }, { tablaRecibos: 'a', tablaLatido: TABLA_LATIDO }, { tablaRecibos: 'a', tablaLatido: 'a' },
    { tablaRecibos: TABLA_LATIDO, tablaLatido: 'PruebaLatido00001' }, { tablaRecibos: 'a', tablaLatido: '1foRUzITWOnUJsNf' }, { tablaRecibos: 'TcpMCmhVw3oT9GjD', tablaLatido: 'b' }]) {
    assert.throws(() => definirBancoF7(fuente, { ...tablas, filas: [fila(2)] }))
  }
  assert.equal(nodoLatido('X').executeOnce, true)
  assert.equal(WORKFLOW_ID, 'BjI5m1PKVWhO0NDb')
})
