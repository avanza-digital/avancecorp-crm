import test from 'node:test'
import assert from 'node:assert/strict'
import { seleccionarFilaUnica, validarEnvioUnico, operacionesFase5 } from './formulario3.fase5.mjs'
import { cargarDefinicion, WORKFLOW_ID } from './formulario3.workflow.mjs'
import { COLUMNAS } from './formulario3.mjs'

const huella = 'a'.repeat(64)
const control = { fila_objetivo: 8, huella_objetivo: huella, limite_filas: 1 }
const elegida = () => ({ json: { fila: 8, huella, mapeo_correcto: true,
  payload: { filas: [{ fila: 8, campania_origen: 'Formulario 3', canal: 'FORMULARIO' }] } } })

test('selecciona la fila explícita y conserva su enlace aunque no sea la primera', () => {
  const items = Array.from({ length: 127 }, (_, i) => ({ json: { row_number: i + 2 } }))
  const salida = seleccionarFilaUnica(items, 8)
  assert.equal(salida.length, 1)
  assert.equal(salida[0].json.row_number, 8)
  assert.deepEqual(salida[0].pairedItem, { item: 6 })
  assert.equal(items[6].pairedItem, undefined)
})
test('no sustituye una fila ausente por la siguiente ni acepta dos con el mismo número', () => {
  assert.throws(() => seleccionarFilaUnica([{ json: { row_number: 9 } }], 8))
  assert.throws(() => seleccionarFilaUnica([{ json: { row_number: 8 } }, { json: { row_number: 8 } }], 8))
  for (const fila of [null, 0, 1, 2.5, '8']) assert.throws(() => seleccionarFilaUnica([], fila))
})
test('el envío exige una única fila con la identidad y contrato revisados', () => {
  assert.equal(validarEnvioUnico([elegida()], control).length, 1)
  assert.throws(() => validarEnvioUnico([], control))
  assert.throws(() => validarEnvioUnico([elegida(), elegida()], control))
  for (const alteracion of [{ limite_filas: 25 }, { huella_objetivo: null }, { huella_objetivo: 'b'.repeat(64) }, { fila_objetivo: 9 }]) {
    assert.throws(() => validarEnvioUnico([elegida()], { ...control, ...alteracion }))
  }
  for (const alteracion of [{ fila: 9 }, { huella: 'b'.repeat(64) }, { mapeo_correcto: false }, { payload: { filas: [] } }]) {
    assert.throws(() => validarEnvioUnico([{ json: { ...elegida().json, ...alteracion } }], control))
  }
  for (const alteracion of [{ fila: 9 }, { campania_origen: 'Otra' }, { canal: 'LANDING' }]) {
    const item = elegida(); Object.assign(item.json.payload.filas[0], alteracion)
    assert.throws(() => validarEnvioUnico([item], control))
  }
})

test('las operaciones conservan credenciales y recibos y el código generado limita la preparación', () => {
  const base = { ...cargarDefinicion(), id: WORKFLOW_ID, active: false, activeVersionId: null }
  const original = JSON.stringify(base)
  const ops = operacionesFase5(base, { fila: 8 })
  assert.equal(JSON.stringify(base), original)
  assert.ok(ops.find(o => o.nodeName === 'Importar en CRM' && o.disabled === true))
  assert.ok(ops.find(o => o.nodeName === 'Cada 5 minutos' && o.disabled === true))
  assert.match(ops.find(o => o.nodeName === 'Control del envío').parameters.jsonOutput, /"simular_registro":true/)
  assert.ok(ops.every(o => !['setNodeCredential', 'addConnection', 'removeConnection'].includes(o.type)))
  const registro = { row_number: 8, ...Object.fromEntries(Object.values(COLUMNAS).map(c => [c, ''])) }
  Object.assign(registro, { [COLUMNAS.nombre]: 'PERSONA SINTÉTICA', [COLUMNAS.telefono]: '999000111', [COLUMNAS.capital]: '5000', [COLUMNAS.moneda]: 'soles' })
  const ejecutar = new Function('$input', '$', ops.find(o => o.nodeName === 'Preparar leads').parameters.jsCode)
  const salida = ejecutar({ all: () => [{ json: { ...registro, row_number: 7 } }, { json: registro }, { json: { ...registro, row_number: 9 } }] }, () => ({ first: () => ({ json: control }) }))
  assert.equal(salida.length, 1)
  assert.equal(salida[0].json.fila, 8)
  assert.equal(salida[0].json.mapeo_correcto, true)
  assert.deepEqual(salida[0].pairedItem, { item: 1 })
  assert.throws(() => operacionesFase5(base, { fila: 8, enviar: true }))
  assert.throws(() => operacionesFase5({ ...base, active: true }, { fila: 8 }))
  const envio = operacionesFase5(base, { fila: 8, huella, enviar: true })
  assert.match(envio.find(o => o.nodeName === 'Control del envío').parameters.jsonOutput, /"simular_registro":false/)
  const validar = new Function('$input', '$', envio.find(o => o.nodeName === 'Seleccionar lote rotativo').parameters.jsCode)
  assert.equal(validar({ all: () => [elegida()] }, () => ({ first: () => ({ json: control }) })).length, 1)
  assert.throws(() => validar({ all: () => [elegida(), elegida()] }, () => ({ first: () => ({ json: control }) })))
})

test('rechaza un recorrido con atajos, otro origen o protecciones de recibos alteradas', () => {
  const nuevo = () => ({ ...cargarDefinicion(), id: WORKFLOW_ID, active: false, activeVersionId: null })
  let base = nuevo()
  base.connections = [...base.connections, { source: 'Identificar fila', target: 'Importar en CRM', sourceIndex: 0, targetIndex: 0 }]
  assert.throws(() => operacionesFase5(base, { fila: 8 }), /recorrido/)
  for (const [nombre, cambiar] of [
    ['Leer leads filtrados', p => { p.documentId.value = 'otra' }],
    ['Omitir filas confirmadas', p => { p.operation = 'get' }],
    ['Registrar resultado', p => { p.filters.conditions = [] }],
    ['Enviar al CRM', p => { p.conditions.conditions[0].leftValue = 'true' }],
    ['Identificar fila', p => { p.type = 'MD5' }],
  ]) {
    base = nuevo(); cambiar(base.nodes.find(n => n.name === nombre).parameters)
    assert.throws(() => operacionesFase5(base, { fila: 8 }))
  }
})
