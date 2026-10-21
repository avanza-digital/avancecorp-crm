ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión LEVEL 2 — n8n «Avance Corp — Formulario 3 → CRM», fase 8: la fila a medio escribir no se rechaza en su primera vuelta (21/10/2026)

Eres el revisor secundario (solo análisis, sin herramientas, sin base ni red). Todo lo que necesitas está transcrito abajo.
Tu trabajo es REFUTAR: busca cómo esto falla en producción (una fila con lead real que se quede sin importar, una fila vacía que
deje de avisar para siempre, un gate que deje pasar un flujo distinto del revisado, código que no corra en el sandbox de n8n).
Sin hallazgo sin evidencia (cita archivo y línea o fragmento). Distingue hipótesis de hechos. Responde en español con:
VERDICT (APPROVE / APPROVE_WITH_NOTES / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 (cada uno con evidencia y propuesta),
RIESGOS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Contexto: cómo funciona el flujo hoy (fase 7, publicada el 15/10 como versión b6c88f1b)
- Cada 5 minutos: «Control del envío» (Set) fija `{enviar_crm:true, simular_registro:false, inicio_ms:$now.toMillis()}` →
  «Leer leads filtrados» (Google Sheets, rango A1:J de la hoja FORMULARIO 3; columnas: Fecha, 5 preguntas, n.º celular, nombre
  completo, número de teléfono, ciudad) → «Preparar leads» (Code, código de abajo) → «Identificar fila» (SHA-256 de
  `huella_material`, que incluye los DATOS de la fila) → «Omitir filas confirmadas» (Data Table, `rowNotExists` por huella) →
  «Seleccionar lote rotativo» → bucle de una en una: «Datos válidos» (`mapeo_correcto`) → «Importar en CRM» (edge
  `crm-importar-leads`) o «Marcar para revisión» (recibo `rechazado`) → «Registrar resultado» (upsert del recibo por huella) →
  … → «Resumen de importación», que lanza `Revisar filas de la hoja: N (rechazada)…` si hubo rechazos; ese error dispara el
  flujo de avisos (correo). Solo se guardan las ejecuciones con error.
- Consecuencia del diseño: un recibo `rechazado` queda ligado a la huella del CONTENIDO leído. Si la fila cambia, su huella
  cambia y se procesa como fila nueva.

## Hechos (ejecución 1883, 21/10/2026, hora UTC; Lima = UTC−5)
- 13:30:11 arranca la vuelta. La hoja devuelve 280 filas (2–281). Las filas 277–281 llegan así, textualmente:
  `{"row_number":277,"Fecha":"2026-10-21T07:27:54-05:00"}` … `{"row_number":281,"Fecha":"2026-10-21T01:22:37-05:00"}`
  (ninguna otra columna con valor; la hoja termina en la columna J, no hay datos más a la derecha).
- 13:30:29–30: recibos `rechazado` para 277–281 con estado «RECHAZADO: Falta el nombre completo; Faltan ambos teléfonos;
  Capital no reconocido: conserva el rango para revisar; Moneda no reconocida: debe indicar soles o dólares». Las filas 261–276,
  completas, se importaron en la misma vuelta (15 `importado`, 1 `duplicado`). «Resumen de importación» lanza el error → correo.
- 13:32:45: última modificación de la hoja (metadatos de Drive).
- 13:35:18–20 (vuelta siguiente, exitosa, no guardada): recibos `importado` para 277–281 con OTRAS huellas («IMPORTADO ✓ (2.º
  número repetía al principal → no se guardó)»). Hasta las 17:40 UTC el latido sigue y no hay más errores.
- Conclusión: la hoja se escribe por tandas (las fechas de 261–276 van de las 09:51 a las 23:39 del 20/10 y todas se
  escribieron el 21/10 hacia las 08:30 Lima; dentro de cada tanda las fechas van en orden descendente). La vuelta 1883 leyó la
  tanda a medias: cinco filas con solo la fecha. Nada se perdió; el aviso fue una falsa alarma y quedaron cinco recibos
  `rechazado` sin lead detrás (inofensivos: ninguna huella volverá a coincidir).
- Aparte y fuera de este encargo: el 20/10 a las 21:10, 21:15 y 21:20 UTC hubo tres errores `connect ETIMEDOUT` de la API de
  Google Sheets en «Leer leads filtrados» (sin `retryOnFail`). No se toca en esta fase.

## Decisión y cambio (fase 8)
Una fila cuyo único contenido es la fecha, legible y a menos de 48 h de la hora de la vuelta (`inicio_ms` de «Control del
envío»), se considera «en escritura»: se omite en esa vuelta SIN recibo (como ya se omite la fila totalmente vacía) y se juzga en
la siguiente, cuando la tanda haya terminado. Si pasado el margen sigue con solo la fecha, se rechaza y avisa como hasta ahora.
Cualquier otro dato en la fila, una celda de tipo raro, una fecha ilegible (también el número de serie de Sheets) o la fecha vacía
la sacan de esa regla y la juzga `prepararFilaSegura` (fase 7). La identidad inválida (`row_number`) sigue siendo fatal.
Margen de 48 h: la tanda trae leads de hasta ~23 h antes (la fila 276, lead de las 09:51 del 20/10, se escribió a las 08:30 del 21/10).
Solo cambia el código del nodo «Preparar leads»; la transición y el gate siguen el patrón de la fase 7.

## Código nuevo: `CRM-Avance-Corp/scripts/n8n/formulario3.fase8.mjs`
```js
import { COLUMNAS, texto } from './formulario3.mjs'
import { WORKFLOW_ID } from './formulario3.workflow.mjs'
import { prepararFilaSegura, codigosFase7, verificarFase7, cargarDefinicionOperativaF7, TABLA_LATIDO } from './formulario3.fase7.mjs'

// Fase 8: una fila que solo trae la fecha se está escribiendo todavía.
// La vuelta 1883 (21/10/2026, 08:30 Lima) leyó cinco filas así (277–281), las
// rechazó por falta de nombre, teléfonos, capital y moneda, y avisó por correo.
// A las 08:32 la hoja ya las tenía completas y en la vuelta de las 08:35 las
// cinco entraron al CRM con otra huella. Los cinco recibos «rechazado» no tienen
// ningún lead detrás. Aquí la fila a medio escribir se omite en esa vuelta, sin
// recibo, y se juzga en la siguiente; si sigue igual pasado el margen, se
// rechaza como hasta ahora, para que una fila vacía de verdad siga avisando.
// Las funciones se copian como texto al nodo Code: solo usan nombres que el nodo
// ya define (COLUMNAS, texto, prepararFilaSegura) y la constante que se inyecta.

// Versión publicada de fase 7 (verificada el 15/10); la transición solo parte de ella.
export const VERSION_FASE7 = 'b6c88f1b-2ef2-4500-a168-c1a0f1b884d0'
// Dos días. La hoja se escribe por tandas con leads de hasta ~23 h antes (la fila
// 276, lead de las 09:51 del 20/10, se escribió a las 08:30 del 21/10).
export const MARGEN_ESCRITURA_MS = 48 * 60 * 60 * 1000

// Solo la fecha tiene contenido, es legible y cae dentro del margen alrededor de
// la hora de la vuelta. Una celda rara, una fecha ilegible (también el número de
// serie de Sheets) o cualquier otro dato la sacan de aquí: la juzga prepararFilaSegura.
export function filaEnEscritura(registro, ahoraMs) {
  if (!Number.isFinite(ahoraMs)) throw new Error('Falta la hora de la vuelta')
  let fecha = ''
  try {
    for (const [clave, columna] of Object.entries(COLUMNAS)) {
      const valor = texto(registro[columna])
      if (clave === 'fecha') fecha = valor
      else if (valor !== '') return false
    }
  } catch { return false }
  if (!fecha) return false
  const momento = Date.parse(fecha)
  return Number.isFinite(momento) && Math.abs(ahoraMs - momento) <= MARGEN_ESCRITURA_MS
}

// La identidad inválida sigue siendo fatal, también para una fila a medio escribir.
export function prepararFilaVuelta(registro, ahoraMs) {
  const fila = Number(registro?.row_number)
  if (!Number.isInteger(fila) || fila < 2) throw new Error('La lectura no incluye un número de fila válido')
  return filaEnEscritura(registro, ahoraMs) ? null : prepararFilaSegura(registro)
}

const SUFIJO_PREPARAR7 = "\nconst entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\nreturn entradas.map((item,index)=>({json:prepararFilaSegura(item.json),pairedItem:{item:index}})).filter(item=>item.json!==null);"
// La hora de la vuelta es la de «Control del envío», la misma que ordena el lote.
const SUFIJO_PREPARAR8 = "\nconst entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\nconst ahora=$(\"Control del envío\").first().json.inicio_ms;\nreturn entradas.map((item,index)=>({json:prepararFilaVuelta(item.json,ahora),pairedItem:{item:index}})).filter(item=>item.json!==null);"

export function codigosFase8() {
  const { preparar7 } = codigosFase7()
  if (!preparar7.endsWith(SUFIJO_PREPARAR7)) throw new Error('Cambió el código de fase 7')
  return {
    preparar7,
    preparar8: preparar7.slice(0, -SUFIJO_PREPARAR7.length) + '\nconst MARGEN_ESCRITURA_MS = ' + MARGEN_ESCRITURA_MS + '\n' +
      filaEnEscritura.toString() + '\n' + prepararFilaVuelta.toString() + SUFIJO_PREPARAR8,
  }
}

// Transición desde la fase 7 exacta y despublicada. Devuelve operaciones de
// update_workflow; solo cambia el código de «Preparar leads».
export function operacionesFase8(actual) {
  if (actual.id !== WORKFLOW_ID || actual.active || actual.activeVersionId) throw new Error('Preparar sin publicar y sin ejecuciones concurrentes')
  if (actual.versionId !== VERSION_FASE7) throw new Error('El borrador no es la versión de fase 7 verificada')
  const { preparar8 } = codigosFase8()
  if (actual.nodes.find(n => n.name === 'Preparar leads')?.parameters?.jsCode === preparar8) throw new Error('La fase 8 ya está aplicada')
  verificarFase7({ ...actual, active: false, activeVersionId: null })
  return [{ type: 'updateNodeParameters', nodeName: 'Preparar leads', parameters: { jsCode: preparar8 } }]
}

// Gate posterior a la escritura: el código de fase 8 aplicado y, con él devuelto
// a fase 7, todo lo demás tal como lo revisó verificarFase7. Con { publicado: true }
// exige además que la versión activa sea la inspeccionada.
export function verificarFase8(actual, tabla = TABLA_LATIDO, { publicado = false } = {}) {
  if (publicado && (actual.active !== true || !actual.versionId || actual.activeVersionId !== actual.versionId)) throw new Error('La versión publicada no es la inspeccionada')
  const { preparar7, preparar8 } = codigosFase8()
  const copia = JSON.parse(JSON.stringify(actual))
  const preparar = copia.nodes.find(n => n.name === 'Preparar leads')
  if (preparar?.parameters?.jsCode !== preparar8) throw new Error('Código de fase 8 no aplicado')
  preparar.parameters.jsCode = preparar7
  verificarFase7(copia, tabla)
  return true
}

// Fuente reproducible del flujo operativo de fase 8 (borrador local).
export function cargarDefinicionOperativaF8(tabla = TABLA_LATIDO) {
  const w = cargarDefinicionOperativaF7(tabla)
  w.nodes.find(n => n.name === 'Preparar leads').parameters.jsCode = codigosFase8().preparar8
  verificarFase8(w, tabla)
  return w
}
```

## Lo que quedará en el nodo «Preparar leads» después del preludio compartido (texto generado por `codigosFase8().preparar8`; el preludio es el de la fase 7, byte a byte, hasta `prepararFilaSegura` inclusive)
```js

const MARGEN_ESCRITURA_MS = 172800000
function filaEnEscritura(registro, ahoraMs) {
  if (!Number.isFinite(ahoraMs)) throw new Error('Falta la hora de la vuelta')
  let fecha = ''
  try {
    for (const [clave, columna] of Object.entries(COLUMNAS)) {
      const valor = texto(registro[columna])
      if (clave === 'fecha') fecha = valor
      else if (valor !== '') return false
    }
  } catch { return false }
  if (!fecha) return false
  const momento = Date.parse(fecha)
  return Number.isFinite(momento) && Math.abs(ahoraMs - momento) <= MARGEN_ESCRITURA_MS
}
function prepararFilaVuelta(registro, ahoraMs) {
  const fila = Number(registro?.row_number)
  if (!Number.isInteger(fila) || fila < 2) throw new Error('La lectura no incluye un número de fila válido')
  return filaEnEscritura(registro, ahoraMs) ? null : prepararFilaSegura(registro)
}
const entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));
const ahora=$("Control del envío").first().json.inicio_ms;
return entradas.map((item,index)=>({json:prepararFilaVuelta(item.json,ahora),pairedItem:{item:index}})).filter(item=>item.json!==null);
```

## Pruebas: `CRM-Avance-Corp/scripts/n8n/formulario3.fase8.test.mjs`
```js
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
// Tal como la devolvió la hoja en la vuelta 1883: todas las columnas, solo la fecha con contenido.
const soloFecha = (n, fecha) => ({ row_number: n, ...Object.fromEntries(Object.values(COLUMNAS).map(c => [c, ''])), [COLUMNAS.fecha]: fecha })
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
  const vacia = soloFecha(277, '')
  assert.equal(filaEnEscritura(vacia, AHORA), false)
  assert.equal(prepararFilaVuelta(vacia, AHORA), null)
  assert.equal(prepararFila(vacia), null)
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
  const tarde = ejecutarNodo(preparar8, [soloFecha(3, iso(-HORA))], { simular_registro: false, inicio_ms: AHORA + MARGEN_ESCRITURA_MS + HORA })
  assert.deepEqual(tarde.map(i => [i.json.fila, i.json.mapeo_correcto]), [[3, false]])
  // La fase 7 la rechazaba en la primera vuelta: eso es lo que cambia.
  assert.deepEqual(ejecutarNodo(preparar7, [soloFecha(3, iso(-HORA))]).map(i => [i.json.fila, i.json.mapeo_correcto]), [[3, false]])
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
```

## Fragmentos de referencia (código vigente, sin cambios)
`formulario3.mjs` (preludio copiado a todos los nodos Code):
```js
export function texto(valor) {
  if (valor == null) return ''
  if (typeof valor === 'string') return valor.trim()
  if (typeof valor === 'number' && Number.isFinite(valor)) return String(valor)
  throw new Error('La celda contiene un tipo de dato inesperado')
}
export function validarColumnas(registros) {
  const claves = new Set(registros.flatMap((registro) => Object.keys(registro)))
  if (!Object.values(COLUMNAS).some((columna) => claves.has(columna))) {
    if (registros.every((registro) => Object.entries(registro).every(([clave, valor]) => clave === 'row_number' || valor == null || valor === ''))) return
  }
  const faltantes = Object.values(COLUMNAS).filter((columna) => !claves.has(columna))
  if (faltantes.length) throw new Error('Cambió la estructura de Google Sheets. Faltan columnas: ' + faltantes.join(' | '))
}

export function prepararFila(registro) {
  const fila = Number(registro.row_number)
  if (!Number.isInteger(fila) || fila < 2) throw new Error('La lectura no incluye un número de fila válido')
  const datos = {}
  for (const [clave, columna] of Object.entries(COLUMNAS)) datos[clave] = texto(registro[columna])
  if (Object.values(datos).every((valor) => valor === '')) return null
```
`formulario3.fase7.mjs` (lo que la fase 8 reutiliza):
```js
// Solo recupera el tipo de celda inesperado; la identidad inválida sigue siendo
// fatal. La fila queda para revisión con la forma que exige la selección del lote.
export function prepararFilaSegura(registro) {
  const fila = Number(registro?.row_number)
  if (!Number.isInteger(fila) || fila < 2) throw new Error('La lectura no incluye un número de fila válido')
  const raras = Object.values(COLUMNAS).filter((columna) => {
    try { texto(registro[columna]); return false } catch { return true }
  })
  if (!raras.length) return prepararFila(registro)
  const datos = {}
  for (const [clave, columna] of Object.entries(COLUMNAS)) {
    if (!raras.includes(columna)) { datos[clave] = texto(registro[columna]); continue }
    let valor
    try { valor = JSON.stringify(registro[columna]) } catch { valor = undefined }
    datos[clave] = { tipo: typeof registro[columna], valor: valor ?? String(registro[columna]) }
  }
  return {
    fila,
    campania: CAMPAÑA,
    mapeo_correcto: false,
    errores: raras.map((columna) => 'Celda con un dato inesperado en «' + columna + '»'),
    avisos: [],
    huella_material: JSON.stringify({ documento: DOCUMENTO, pestana: 'gid=0', datos }),
    payload: { filas: [{ fila, canal: 'FORMULARIO', campania_origen: CAMPAÑA }] },
  }
}
const SUFIJO_PREPARAR = "\nconst entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\nreturn entradas.map((item,index)=>({json:prepararFila(item.json),pairedItem:{item:index}})).filter(item=>item.json!==null);"
const SUFIJO_RESUMEN = exigirRevisionRechazos.toString() + '\nconst filas=$input.all().map(item=>item.json);\nreturn [{json:exigirRevisionRechazos(resumirImportacion(filas,$("Control del envío").first().json.simular_registro),filas)}];'

export function codigosFase7() {
  const f6 = cargarDefinicionOperativa()
  const preparar6 = f6.nodes.find(n => n.name === 'Preparar leads').parameters.jsCode
  const resumen6 = f6.nodes.find(n => n.name === 'Resumen de importación').parameters.jsCode
  if (!preparar6.endsWith(SUFIJO_PREPARAR) || !resumen6.endsWith(SUFIJO_RESUMEN)) throw new Error('Cambió el código de fase 6')
  return {
    preparar6, resumen6,
    preparar7: preparar6.slice(0, -SUFIJO_PREPARAR.length) + '\n' + prepararFilaSegura.toString() +
      "\nconst entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\nreturn entradas.map((item,index)=>({json:prepararFilaSegura(item.json),pairedItem:{item:index}})).filter(item=>item.json!==null);",
    resumen7: resumen6.slice(0, -SUFIJO_RESUMEN.length) + estadoClienteCorrecto.toString() + '\n' + cerrarVuelta.toString() +
      '\nreturn [{json:cerrarVuelta($input.all().map(item=>item.json),$("Control del envío").first().json.simular_registro)}];',
  }
}
// Vista «fase 6» de un flujo con fase 7 aplicada: sin latido y con el código
// anterior. Si algo más cambió, verificarFase6 lo rechaza.
function comoFase6(actual) {
  const { preparar6, resumen6, preparar7, resumen7 } = codigosFase7()
  const copia = JSON.parse(JSON.stringify(actual))
  const latidos = copia.nodes.filter(n => n.name === LATIDO)
  if (latidos.length !== 1) throw new Error('Falta el latido o está repetido')
  const esperado = nodoLatido(latidos[0].parameters?.dataTableId?.value)
  const real = { ...latidos[0] }
  for (const k of ['id', 'notes', 'notesInFlow', 'color']) delete real[k]
  // n8n omite al guardar los valores por defecto del nodo de tablas.
  const comparar = n => {
    const p = JSON.parse(JSON.stringify(n.parameters ?? {}))
    p.resource ??= 'row'
    p.options ??= {}
    for (const c of p.filters?.conditions ?? []) c.condition ??= 'eq'
    return canonico({ type: n.type, typeVersion: n.typeVersion, executeOnce: n.executeOnce ?? false, disabled: n.disabled ?? false, onError: n.onError ?? 'stopWorkflow',
      retryOnFail: n.retryOnFail ?? false, maxTries: n.maxTries ?? null, waitBetweenTries: n.waitBetweenTries ?? null, continueOnFail: n.continueOnFail ?? false,
      alwaysOutputData: n.alwaysOutputData ?? false, credenciales: n['credentials'] ?? null, parameters: p })
  }
  if (comparar(real) !== comparar(esperado)) throw new Error('El latido no coincide con el revisado')
  if (!(latidos[0].position?.[1] < copia.nodes.find(n => n.name === 'Enviar al CRM').position[1])) throw new Error('El latido debe ir encima de la importación')
  copia.nodes = copia.nodes.filter(n => n.name !== LATIDO)
  const aristas = aLista(copia.connections)
  const delLatido = aristas.filter(a => a.source === LATIDO || a.target === LATIDO)
  if (delLatido.length !== 1 || delLatido[0].source !== 'Identificar fila' || delLatido[0].sourceIndex !== 0 ||
      (delLatido[0].targetIndex ?? 0) !== 0 || (delLatido[0].tipo ?? 'main') !== 'main') throw new Error('El latido debe colgar solo de Identificar fila')
  copia.connections = aristas.filter(a => a.target !== LATIDO)
  const nodo = nombre => copia.nodes.find(n => n.name === nombre)
  if (nodo('Preparar leads').parameters.jsCode !== preparar7 || nodo('Resumen de importación').parameters.jsCode !== resumen7) throw new Error('Código de fase 7 no aplicado')
  nodo('Preparar leads').parameters.jsCode = preparar6
  nodo('Resumen de importación').parameters.jsCode = resumen6
  return copia
}
// Gate posterior a la escritura. Con { publicado: true } exige además que la
// versión activa sea la misma que se inspecciona (no un borrador sobre fase 6).
export function verificarFase7(actual, tabla = TABLA_LATIDO, { publicado = false } = {}) {
  if (publicado && (actual.active !== true || !actual.versionId || actual.activeVersionId !== actual.versionId)) throw new Error('La versión publicada no es la inspeccionada')
  const vista = comoFase6(actual)
  if (vista.nodes.length !== 22) throw new Error('Los nodos cambiaron desde la revisión')
  if (actual.nodes.find(n => n.name === LATIDO).parameters.dataTableId.value !== tabla) throw new Error('Tabla del latido distinta')
  comprobarRecorrido(vista)
  verificarFase6({ ...vista, active: false, activeVersionId: null }, { enviar: true, programar: true })
  return true
}

// Fuente reproducible del flujo operativo de fase 7 (borrador local).
export function cargarDefinicionOperativaF7(tabla = TABLA_LATIDO) {
  const w = cargarDefinicionOperativa()
  const { preparar7, resumen7 } = codigosFase7()
  w.nodes.find(n => n.name === 'Preparar leads').parameters.jsCode = preparar7
  w.nodes.find(n => n.name === 'Resumen de importación').parameters.jsCode = resumen7
  w.nodes.push(nodoLatido(tabla))
  w.connections = [...aLista(w.connections), { source: 'Identificar fila', target: LATIDO, sourceIndex: 0, targetIndex: 0 }]
  w.nodeGroups = w.nodeGroups.map(g => g.name === 'Lectura y preparación' ? { ...g, nodeNames: g.nodeNames.filter(n => n !== 'Identificar fila') } : g)
  verificarFase7(w, tabla)
  return w
}
```
`formulario3.fase5.mjs` `comprobarRecorrido` exige, entre otras cosas, que el `jsCode` de «Preparar leads» sea el canónico de fases 1–5;
por eso `verificarFase7` devuelve el código a fase 6 (`comoFase6`) antes de llamarlo, y `verificarFase8` lo devuelve a fase 7 antes de
llamar a `verificarFase7`. `verificarFase6` compara parámetros y ajustes del flujo (`saveDataSuccessExecution:'none'`, `errorWorkflow`, etc.).

## Verificación hecha
- `node --test 'scripts/n8n/*.test.mjs'` → 63/63 PASS (57 de fases 1–7 + 6 nuevos), en un worktree limpio de `avancecorp/main` (8406775f).
- 12 mutantes sobre las defensas nuevas, todos MUERTOS: margen exclusivo; sin valor absoluto (fecha futura); otro dato no descalifica;
  celda rara se omite; identidad inválida no fatal; sin exigir versión de fase 7; gate publicado sin exigir versión activa; gate sin exigir
  código de fase 8; sin exigir hora de la vuelta; hora del reloj en vez del control; sin aviso de «ya aplicada»; margen distinto al documentado.
- NOT RUN: banco en n8n (la fase 7 lo usó para probar nodos nuevos; aquí solo cambia código JS que las pruebas ejecutan como lo hace
  n8n, `runOnceForAllItems`, con `$input` y `$("Control del envío")` simulados).

## Publicación prevista (NO hecha; la autoriza Miguel)
1. Comprobar que no haya vuelta en curso; despublicar `BjI5m1PKVWhO0NDb`.
2. `get_workflow_details` → `operacionesFase8(actual)` (exige `versionId` b6c88f1b, despublicado, código de fase 7 exacto) → `update_workflow`
   con esa única operación → `verificarFase8(borrador)`.
3. Publicar; `verificarFase8(publicado, TABLA_LATIDO, { publicado: true })`.
4. Primera vuelta real: latido, 0 errores, recibos intactos. Volver atrás: `restore_workflow_version` a b6c88f1b, publicar, `verificarFase7(..., { publicado: true })`.

## Preguntas concretas a refutar
1. ¿Hay alguna forma de que una fila con un lead real quede sin importar o sin avisar PARA SIEMPRE con esta regla? (Mi hipótesis: no; o se
   completa y entra con su huella nueva, o pasa el margen y se rechaza con aviso.)
2. Una fila que de verdad llegue vacía (solo fecha) tarda hasta 48 h en avisar. ¿Es un riesgo que merezca otro diseño (p. ej. estado
   «incompleto» con primera vista en la tabla de recibos) o basta documentarlo?
3. `$("Control del envío").first().json.inicio_ms` dentro de «Preparar leads»: ¿algún caso (disparo manual «Revisar hoja», reintentos,
   `executionOrder v1`) en que no esté disponible o sea otro valor?
4. `Date.parse('2026-10-21T07:27:54-05:00')` en el sandbox de n8n (task runner, Node): ¿algún riesgo de formato o de zona?
5. ¿La transición (`operacionesFase8`) o el gate (`verificarFase8`) dejan pasar un flujo distinto del revisado? ¿Falta alguna mutación?
6. ¿Algo en el código copiado como texto al nodo usa un nombre que el nodo no define? (El nodo define el preludio de `formulario3.mjs`
   —COLUMNAS, texto, validarColumnas, prepararFila, …— más `prepararFilaSegura`, y la fase 8 inyecta `MARGEN_ESCRITURA_MS`.)
