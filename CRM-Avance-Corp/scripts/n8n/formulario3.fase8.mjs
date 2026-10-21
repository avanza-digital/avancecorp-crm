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
// n8n omite las celdas vacías: una fila a medio escribir llega solo con row_number
// y Fecha. La cabecera se valida sobre las filas que no están en escritura; si la
// lectura entera está a medio escribir no es un cambio de cabecera (Codex, P2).
const SUFIJO_PREPARAR8 = "\nconst entradas=$input.all();\nconst ahora=$(\"Control del envío\").first().json.inicio_ms;\nvalidarColumnas(entradas.filter(item=>!filaEnEscritura(item.json,ahora)).map(item=>item.json));\nreturn entradas.map((item,index)=>({json:prepararFilaVuelta(item.json,ahora),pairedItem:{item:index}})).filter(item=>item.json!==null);"

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
