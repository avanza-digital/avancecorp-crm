import { COLUMNAS, CAMPAÑA, DOCUMENTO, texto, prepararFila, resumirImportacion } from './formulario3.mjs'
import { WORKFLOW_ID, GRUPOS, definirBanco } from './formulario3.workflow.mjs'
import { cargarDefinicionOperativa, verificarFase6, exigirRevisionRechazos } from './formulario3.fase6.mjs'
import { comprobarRecorrido } from './formulario3.fase5.mjs'

// Fase 7: una celda rara ya no frena la vuelta, los clientes que no se pudieron
// anotar avisan y un latido deja constancia de cada lectura completa de la hoja.
// Las funciones se copian como texto a los nodos Code: solo usan nombres que
// formulario3.mjs ya define dentro del nodo.

export const TABLA_LATIDO = 'CJpN45ukEXmZInuG'
export const LATIDO = 'Registrar latido'
// Versión publicada de fase 6 verificada el 15/10; la transición solo parte de ella.
export const VERSION_FASE6 = 'e2f62a7e-7675-414d-a7b0-b617e2528c72'

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

// Estados de «ya es cliente» que dejaron el seguimiento anotado en el CRM
// (clasificarRespuestaPuerta). Cualquier otro texto se trata como pendiente de
// revisión: un estado nuevo avisa en lugar de pasar en silencio. El nombre del
// asesor no admite paréntesis ni dos puntos: así no puede absorber el texto de
// un error y hacerlo pasar por éxito.
export function estadoClienteCorrecto(estado) {
  return typeof estado === 'string' &&
    /^YA ES CLIENTE(?: \(asesor: [^():\n]+\))?: (?:reingreso ya anotado en su ficha|reingreso registrado en su ficha|solicitud ya anotada en su ficha|solicitud anotada y tarea para su analista|no se registra seguimiento \(«No insistir»\))$/.test(estado)
}

// Cierra la vuelta con un solo error que reúne las filas para revisar y las
// pendientes; sin incidencias delega en resumirImportacion (también «sin avance»).
export function cerrarVuelta(filas, simulacion) {
  const conocidos = ['importado', 'duplicado', 'ya_cliente', 'rechazado', 'pendiente', 'aplazado']
  const revisar = []
  const pendientes = []
  for (const fila of filas) {
    if (!conocidos.includes(fila.resultado)) throw new Error('Falta el recibo de una fila')
    if (fila.resultado === 'rechazado') revisar.push(fila.fila + ' (rechazada)')
    else if (fila.resultado === 'ya_cliente' && !estadoClienteCorrecto(fila.estado)) revisar.push(fila.fila + ' (cliente sin registrar)')
    else if (fila.resultado === 'pendiente') pendientes.push(fila.fila)
  }
  const partes = []
  if (revisar.length) partes.push('Revisar filas de la hoja: ' + revisar.join(', ') + '.')
  if (pendientes.length) partes.push('Pendientes para reintentar: ' + pendientes.join(', ') + '.')
  if (partes.length) throw new Error(partes.join(' '))
  return resumirImportacion(filas, simulacion)
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

// Se ejecuta una vez por vuelta, solo si la hoja se leyó y se preparó. Arriba en
// el lienzo para que el orden v1 lo ejecute antes que la importación.
export function nodoLatido(tabla = TABLA_LATIDO) {
  return {
    name: LATIDO,
    type: 'n8n-nodes-base.dataTable',
    typeVersion: 1.1,
    position: [1420, -120],
    executeOnce: true,
    output: [{ id: 1, clave: 'principal', filas_leidas: 152 }],
    parameters: {
      resource: 'row',
      operation: 'upsert',
      dataTableId: { __rl: true, mode: 'list', value: tabla, cachedResultName: 'Formulario 3 — latido' },
      matchType: 'allConditions',
      filters: { conditions: [{ keyName: 'clave', condition: 'eq', keyValue: 'principal' }] },
      columns: { mappingMode: 'defineBelow', value: { clave: 'principal', leido_en: '={{ $now.toISO() }}', filas_leidas: '={{ $("Identificar fila").all().length }}' } },
      options: {},
    },
  }
}

const aLista = conexiones => Array.isArray(conexiones) ? conexiones.map(c => ({ ...c }))
  : Object.entries(conexiones).flatMap(([source, tipos]) => Object.entries(tipos).flatMap(([tipo, salidas]) =>
    salidas.flatMap((destinos, sourceIndex) => (destinos ?? []).map(d => ({ source, target: d.node, sourceIndex, targetIndex: d.index, tipo })))))

const canonico = valor => JSON.stringify(valor, (_, v) => v && typeof v === 'object' && !Array.isArray(v)
  ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b))) : v)

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

// Transición desde la fase 6 exacta y despublicada. Devuelve operaciones de
// update_workflow; no toca credenciales, intervalo, retención ni recibos.
export function operacionesFase7(actual, tabla = TABLA_LATIDO) {
  if (actual.id !== WORKFLOW_ID || actual.active || actual.activeVersionId) throw new Error('Preparar sin publicar y sin ejecuciones concurrentes')
  if (actual.versionId !== VERSION_FASE6) throw new Error('El borrador no es la versión de fase 6 verificada')
  if (!/^[A-Za-z0-9]{16}$/.test(tabla)) throw new Error('Falta la tabla del latido')
  if (actual.nodes.some(n => n.name === LATIDO)) throw new Error('La fase 7 ya está aplicada')
  verificarFase6({ ...actual, active: false, activeVersionId: null }, { enviar: true, programar: true })
  const { preparar7, resumen7 } = codigosFase7()
  const latido = nodoLatido(tabla)
  return [
    { type: 'updateNodeParameters', nodeName: 'Preparar leads', parameters: { jsCode: preparar7 } },
    { type: 'updateNodeParameters', nodeName: 'Resumen de importación', parameters: { jsCode: resumen7 } },
    { type: 'addNode', node: { name: latido.name, type: latido.type, typeVersion: latido.typeVersion, position: latido.position, parameters: latido.parameters } },
    { type: 'setNodeSettings', nodeName: LATIDO, settings: { executeOnce: true } },
    { type: 'addConnection', source: 'Identificar fila', target: LATIDO, sourceIndex: 0, targetIndex: 0 },
    // n8n exige una sola salida por grupo: Identificar fila sale a la importación y
    // al latido, así que queda fuera del grupo (si no, n8n borraría el grupo entero).
    { type: 'updateNodeGroup', groupName: 'Lectura y preparación', nodeNames: GRUPOS[0].nodeNames.filter(n => n !== 'Identificar fila') },
  ]
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

// Banco cerrado: parte de la definición operativa de fase 7 y sustituye la hoja,
// el CRM y las tablas por piezas aisladas. Nunca usa credenciales.
export function definirBancoF7(codigoFuente, { tablaRecibos, tablaLatido, filas, respuestaCodigo }) {
  const productivas = ['1foRUzITWOnUJsNf', TABLA_LATIDO, 'TcpMCmhVw3oT9GjD']
  if (!tablaRecibos || !tablaLatido || tablaRecibos === tablaLatido ||
      [tablaRecibos, tablaLatido].some(t => productivas.includes(t))) throw new Error('El banco requiere tablas aisladas de producción')
  const base = definirBanco(codigoFuente, { tablaId: tablaRecibos, filas, respuestaCodigo, simularRegistro: false })
  const operativa = cargarDefinicionOperativaF7()
  const nodos = operativa.nodes.map(n => {
    const sustituto = base.find(b => b.name === n.name)
    if (n.name === LATIDO) return nodoLatido(tablaLatido)
    if (['Leer leads filtrados', 'Importar en CRM', 'Control del envío', 'Omitir filas confirmadas', 'Registrar resultado'].includes(n.name)) return sustituto
    const copia = JSON.parse(JSON.stringify(n))
    delete copia.credentials
    return copia
  })
  return { nodes: nodos, connections: operativa.connections, nodeGroups: operativa.nodeGroups }
}
