import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { cargarDefinicion, definirBanco, codigoSDK, TABLA_PRODUCCION, CONEXIONES, UMBRAL_MS } from './formulario3.workflow.mjs'

const fuente = readFileSync(new URL('./formulario3.mjs', import.meta.url), 'utf8')
const base = cargarDefinicion()
const nodo = nombre => base.nodes.find(n => n.name === nombre)

test('el borrador reproduce la hoja y credenciales verificadas, con el envío cerrado', () => {
  assert.equal(nodo('Leer leads filtrados').parameters.documentId.value, '1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI')
  assert.equal(nodo('Leer leads filtrados').credentials.googleSheetsOAuth2Api.id, 'vPzsYCzKnotpycYi')
  assert.match(nodo('Control del envío').parameters.jsonOutput, /enviar_crm:false/)
  assert.equal(nodo('Importar en CRM').disabled, true)
  assert.equal(nodo('Importar en CRM').credentials.httpTemplatedCustomAuth.id, 'YNRHr2PjhfLXnKff')
  assert.equal(nodo('Importar en CRM').parameters.authentication, 'genericCredentialType')
  assert.equal(base.settings.errorWorkflow, '4jfthNhVJLiZUeIo')
})

test('los recibos de lectura y escritura usan la misma tabla y la simulación conserva su control', () => {
  const tablas = base.nodes.filter(n => n.parameters.dataTableId)
  assert.equal(tablas.length, 2)
  assert.ok(tablas.every(n => n.parameters.dataTableId.value === TABLA_PRODUCCION))
  assert.equal(nodo('Registrar resultado').parameters.options.dryRun, '={{ $("Control del envío").first().json.simular_registro }}')
  assert.equal(nodo('Conservar recibo').executeOnce, true)
})

test('los errores vuelven al bucle sin entrar al registro definitivo', () => {
  for (const nombre of ['Importar en CRM', 'Confirmar respuesta del CRM']) {
    assert.equal(nodo(nombre).onError, 'continueErrorOutput')
    assert.ok(CONEXIONES.some(e => e.source === nombre && e.sourceIndex === 1 && e.target === 'Mantener pendiente'))
  }
  assert.deepEqual(CONEXIONES.filter(e => e.source === 'Mantener pendiente').map(e => e.target), ['Procesar de una en una'])
  assert.match(nodo('Confirmar respuesta del CRM').parameters.jsCode, /\.itemMatching\(0\)/)
  assert.match(nodo('Mantener pendiente').parameters.jsCode, /\.itemMatching\(0\)/)
})

test('el lote y margen de tiempo dejan espacio para los tres intentos HTTP', () => {
  assert.match(nodo('Seleccionar lote rotativo').parameters.jsCode, /return seleccionarLote\(/)
  const http = nodo('Importar en CRM')
  const peorIntento = http.parameters.options.timeout * http.maxTries + http.waitBetweenTries * (http.maxTries - 1)
  assert.ok(base.settings.executionTimeout * 1000 - UMBRAL_MS > peorIntento)
  assert.ok(nodo('Tiempo disponible').parameters.conditions.conditions[0].leftValue.includes('< ' + UMBRAL_MS))
  assert.equal(base.settings.saveDataSuccessExecution, 'none')
})

test('el banco exige tabla aislada y sustituye todas las lecturas y llamadas externas', () => {
  const filas = nodo('Leer leads filtrados').output
  assert.throws(() => definirBanco(fuente, { tablaId: TABLA_PRODUCCION, filas }), /aislada/)
  assert.throws(() => definirBanco(fuente, { filas }), /aislada/)
  const banco = definirBanco(fuente, { tablaId: 'tabla-sintetica', filas })
  assert.ok(banco.every(n => !n.credentials))
  assert.ok(banco.every(n => !['n8n-nodes-base.httpRequest', 'n8n-nodes-base.googleSheets'].includes(n.type)))
  assert.ok(banco.filter(n => n.parameters.dataTableId).every(n => n.parameters.dataTableId.value === 'tabla-sintetica'))
  assert.match(banco.find(n => n.name === 'Control del envío').parameters.jsonOutput, /simular_registro:true/)
  assert.equal(nodo('Importar en CRM').type, 'n8n-nodes-base.httpRequest')
})

test('el SDK deriva conexiones y grupos por nombre, incluso si se reordenan nodos', () => {
  const inversos = [...base.nodes].reverse()
  const sdk = codigoSDK(inversos)
  const inicio = inversos.findIndex(n => n.name === 'Revisar hoja')
  const control = inversos.findIndex(n => n.name === 'Control del envío')
  assert.ok(sdk.includes('.add(n' + inicio + '.output(0).to(n' + control + '))'))
  const bucle = inversos.findIndex(n => n.name === 'Procesar de una en una')
  const siguiente = inversos.findIndex(n => n.name === 'Tiempo disponible')
  assert.ok(sdk.includes('.add(n' + bucle + '.onEachBatch(n' + siguiente + '))'))
  assert.throws(() => codigoSDK(base.nodes.slice(1)), /Nodo desconocido/)
  assert.equal((sdk.match(/\.add\(/g) ?? []).length, CONEXIONES.length)
  assert.equal((sdk.match(/nextBatch\(/g) ?? []).length, 3)
  for (const arista of CONEXIONES.filter(e => e.loop)) {
    const origen = inversos.findIndex(n => n.name === arista.source)
    assert.ok(sdk.includes('.add(n' + origen + '.output(0).to(nextBatch(n' + bucle + ')))'))
  }
})
