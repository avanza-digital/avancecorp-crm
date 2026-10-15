import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { WORKFLOW_ID, TABLA_PRODUCCION, CONEXIONES, cargarDefinicion } from './formulario3.workflow.mjs'

export function comprobarRecorrido(base) {
  const aristas = Array.isArray(base.connections) ? base.connections : Object.entries(base.connections).flatMap(([source, tipos]) =>
    Object.entries(tipos).flatMap(([tipo, salidas]) => salidas.flatMap((destinos, sourceIndex) =>
      destinos.map(d => ({ source, target: d.node, sourceIndex, targetIndex: d.index, tipo })))))
  const firma = lista => lista.map(a => JSON.stringify([a.source, a.tipo ?? 'main', a.sourceIndex, a.target, a.targetIndex])).sort().join('\n')
  if (firma(aristas) !== firma(CONEXIONES)) throw new Error('El recorrido cambió desde la revisión')
  const esperado = cargarDefinicion().nodes
  if (base.nodes.length !== esperado.length || new Set(base.nodes.map(n => n.name)).size !== esperado.length ||
      base.nodes.some(n => !esperado.some(e => e.name === n.name && e.type === n.type && e.typeVersion === n.typeVersion))) {
    throw new Error('Los nodos cambiaron desde la revisión')
  }
  const p = nombre => base.nodes.find(n => n.name === nombre).parameters
  const hoja = p('Leer leads filtrados')
  if (hoja.documentId?.value !== '1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI' || hoja.sheetName?.value !== 'gid=0' ||
      hoja.options?.dataLocationOnSheet?.values?.range !== 'A1:J') throw new Error('La hoja de origen cambió')
  const cripto = p('Identificar fila')
  if ((cripto.action ?? 'hash') !== 'hash' || (cripto.type ?? 'SHA256') !== 'SHA256' || (cripto.encoding ?? 'hex') !== 'hex' ||
      cripto.value !== '={{ $json.huella_material }}' || cripto.dataPropertyName !== 'huella') throw new Error('La identidad de la fila cambió')
  for (const [nombre, expresion] of [['Enviar al CRM', '={{ $("Control del envío").first().json.enviar_crm }}'], ['Datos válidos', '={{ $json.mapeo_correcto }}']]) {
    const c = p(nombre).conditions
    if (c?.conditions?.length !== 1 || c.combinator !== 'and' || c.options?.typeValidation !== 'strict' ||
        c.conditions[0].leftValue !== expresion || c.conditions[0].rightValue !== true ||
        c.conditions[0].operator?.type !== 'boolean' || c.conditions[0].operator?.operation !== 'equals') throw new Error('La puerta de envío cambió')
  }
  for (const [nombre, operacion] of [['Omitir filas confirmadas', 'rowNotExists'], ['Registrar resultado', 'upsert']]) {
    const tabla = p(nombre), filtro = tabla.filters?.conditions
    if (tabla.operation !== operacion || tabla.matchType !== 'allConditions' || filtro?.length !== 1 ||
        filtro[0].keyName !== 'huella' || filtro[0].keyValue !== '={{ $json.huella }}' || (filtro[0].condition ?? 'eq') !== 'eq') throw new Error('La deduplicación cambió')
  }
  if (p('Registrar resultado').options?.dryRun !== '={{ $("Control del envío").first().json.simular_registro }}') throw new Error('La simulación cambió')
  for (const nombre of ['Preparar leads', 'Confirmar respuesta del CRM', 'Mantener pendiente']) {
    if (p(nombre).jsCode !== esperado.find(n => n.name === nombre).parameters.jsCode) throw new Error('El código revisado cambió: ' + nombre)
  }
}

export function seleccionarFilaUnica(items, fila) {
  if (!Number.isInteger(fila) || fila < 2) throw new Error('Fila de prueba inválida')
  const elegidas = items.map((item, index) => ({ ...item, pairedItem: { item: index } }))
    .filter(item => Number(item.json.row_number) === fila)
  if (elegidas.length !== 1) throw new Error('La fila de prueba debe existir exactamente una vez')
  return elegidas
}

export function validarEnvioUnico(items, control) {
  if (control.limite_filas !== 1 || items.length !== 1) throw new Error('La fase 5 admite una sola fila')
  if (!Number.isInteger(control.fila_objetivo) || control.fila_objetivo < 2 ||
      typeof control.huella_objetivo !== 'string' || !/^[0-9a-f]{64}$/.test(control.huella_objetivo)) {
    throw new Error('Falta la identidad verificada de la fila')
  }
  const fila = items[0].json
  if (fila.fila !== control.fila_objetivo || fila.huella !== control.huella_objetivo) {
    throw new Error('La fila cambió desde la revisión: no se envía')
  }
  if (fila.mapeo_correcto !== true || fila.payload?.filas?.length !== 1 ||
      fila.payload.filas[0].fila !== control.fila_objetivo ||
      fila.payload.filas[0].campania_origen !== 'Formulario 3' ||
      fila.payload.filas[0].canal !== 'FORMULARIO') {
    throw new Error('La fila no cumple el contrato de Formulario 3')
  }
  return [{ ...items[0], pairedItem: { item: 0 } }]
}

export function operacionesFase5(base, { fila, huella = null, enviar = false }) {
  if (base.id !== WORKFLOW_ID || base.active || base.activeVersionId) throw new Error('El flujo debe estar sin publicar')
  comprobarRecorrido(base)
  if (!Number.isInteger(fila) || fila < 2 || typeof enviar !== 'boolean') throw new Error('Configuración de prueba inválida')
  if (enviar && (typeof huella !== 'string' || !/^[0-9a-f]{64}$/.test(huella))) throw new Error('No se permite enviar sin huella verificada')
  const porNombre = nombre => {
    const nodo = base.nodes.find(n => n.name === nombre)
    if (!nodo) throw new Error('Falta el nodo ' + nombre)
    return nodo
  }
  for (const nombre of ['Registrar resultado', 'Omitir filas confirmadas']) {
    if (porNombre(nombre).parameters.dataTableId.value !== TABLA_PRODUCCION) throw new Error('No se debe sustituir la tabla de recibos')
  }
  const importador = porNombre('Importar en CRM')
  if (importador.parameters.url !== 'https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-importar-leads' ||
      importador.credentials?.httpTemplatedCustomAuth?.id !== 'YNRHr2PjhfLXnKff') {
    throw new Error('El destino o la credencial del importador cambiaron')
  }
  const preparacion = porNombre('Preparar leads').parameters.jsCode
  const fin = 'const entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\nreturn entradas.map((item,index)=>({json:prepararFila(item.json),pairedItem:{item:index}})).filter(item=>item.json!==null);'
  if (!preparacion.endsWith(fin)) throw new Error('El código de preparación no coincide con el revisado')
  const codigo = preparacion.slice(0, -fin.length) + seleccionarFilaUnica.toString() + '\n' +
    'const entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\n' +
    'const elegidas=seleccionarFilaUnica(entradas,$("Control del envío").first().json.fila_objetivo);\n' +
    'return elegidas.map(item=>{ const fila=prepararFila(item.json); if(!fila)throw new Error("La fila elegida está vacía"); return {json:fila,pairedItem:item.pairedItem}; });'
  const control = { enviar_crm: enviar, simular_registro: !enviar, fila_objetivo: fila, huella_objetivo: huella, limite_filas: 1 }
  return [
    { type: 'setNodeDisabled', nodeName: 'Cada 5 minutos', disabled: true },
    { type: 'updateNodeParameters', nodeName: 'Control del envío', parameters: { jsonOutput: '={{ JSON.stringify({...'+JSON.stringify(control)+',inicio_ms:$now.toMillis()}) }}' } },
    { type: 'updateNodeParameters', nodeName: 'Preparar leads', parameters: { jsCode: codigo } },
    { type: 'updateNodeParameters', nodeName: 'Seleccionar lote rotativo', parameters: { jsCode: validarEnvioUnico.toString()+'\nreturn validarEnvioUnico($input.all(),$("Control del envío").first().json);' } },
    { type: 'setNodeDisabled', nodeName: 'Importar en CRM', disabled: !enviar },
  ]
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const base = JSON.parse(readFileSync(process.argv[2], 'utf8'))
  const fila = Number(process.argv[3])
  const huella = process.argv[4] || null
  console.log(JSON.stringify(operacionesFase5(base, { fila, huella, enviar: process.argv[5] === 'enviar' }), null, 2))
}
