import { cargarDefinicion, WORKFLOW_ID, TABLA_PRODUCCION, AJUSTES } from './formulario3.workflow.mjs'
import { comprobarRecorrido, operacionesFase5 } from './formulario3.fase5.mjs'

// El filtro de recibos precede a este nodo. Una huella repetida en la misma
// lectura se envía una sola vez; pairedItem conserva el vínculo con su fila.
export function seleccionarPendientes(items, inicioMs) {
  if (!Array.isArray(items) || !Number.isFinite(inicioMs) || inicioMs < 0) throw new Error('Lote inválido')
  const vistas = new Set()
  const unicas = []
  for (const [index, item] of items.entries()) {
    const fila = item.json
    if (!/^[0-9a-f]{64}$/.test(fila?.huella) || !Number.isInteger(fila.fila) || fila.fila < 2 ||
        fila.campania !== 'Formulario 3' || fila.payload?.filas?.length !== 1 ||
        fila.payload.filas[0].fila !== fila.fila ||
        fila.payload.filas[0].campania_origen !== 'Formulario 3' ||
        fila.payload.filas[0].canal !== 'FORMULARIO') throw new Error('Identidad o campaña inválida antes del envío')
    if (!vistas.has(fila.huella)) {
      vistas.add(fila.huella)
      unicas.push({ ...item, pairedItem: { item: index } })
    }
  }
  if (!unicas.length) return []
  const offset = Math.floor(inicioMs / 300000) % unicas.length
  return [...unicas.slice(offset), ...unicas.slice(0, offset)].slice(0, 25)
}

export function exigirRevisionRechazos(resumen, filas) {
  const rechazadas = filas.filter(fila => fila.resultado === 'rechazado').map(fila => fila.fila)
  if (rechazadas.length) throw new Error('Filas rechazadas para revisar: ' + rechazadas.join(', ') + '. Sus resultados definitivos se conservaron.')
  return resumen
}

const canonico = valor => JSON.stringify(valor, (_, v) => v && typeof v === 'object' && !Array.isArray(v)
  ? Object.fromEntries(Object.entries(v).sort(([a],[b]) => a.localeCompare(b))) : v)
const jsonIgual = (a,b) => canonico(a) === canonico(b)

// Defaults que n8n 2.43.5 omite al serializar. Solo se normalizan equivalencias
// conocidas; cualquier parámetro operativo adicional sigue causando rechazo.
function nodoComparable(nodo) {
  const n = JSON.parse(JSON.stringify(nodo))
  for (const k of ['id','position','output','notes','notesInFlow','color']) delete n[k]
  for (const k of ['disabled','retryOnFail','alwaysOutputData','executeOnce']) n[k] ??= false
  n.onError ??= 'stopWorkflow'
  if (n.credentials) n.credentials = Object.fromEntries(Object.entries(n.credentials).map(([k,v])=>[k,{id:v.id}]))
  const p = n.parameters
  if (n.type === 'n8n-nodes-base.code') { p.mode ??= 'runOnceForAllItems'; p.language ??= 'javaScript' }
  if (n.type === 'n8n-nodes-base.googleSheets') { p.resource ??= 'sheet'; p.operation ??= 'read'; p.authentication ??= 'oAuth2' }
  if (n.type === 'n8n-nodes-base.crypto') { p.action ??= 'hash'; p.type ??= 'SHA256'; p.encoding ??= 'hex' }
  if (n.type === 'n8n-nodes-base.dataTable') { p.resource ??= 'row'; for (const c of p.filters?.conditions ?? []) c.condition ??= 'eq' }
  if (n.type === 'n8n-nodes-base.splitInBatches') p.batchSize ??= 1
  if (n.type === 'n8n-nodes-base.httpRequest') p.contentType ??= 'json'
  if (n.type === 'n8n-nodes-base.scheduleTrigger') for (const i of p.rule?.interval ?? []) if (i.field === 'minutes') i.minutesInterval ??= 5
  if (['n8n-nodes-base.set','n8n-nodes-base.if'].includes(n.type)) p.options ??= {}
  if (n.type === 'n8n-nodes-base.if') {
    if (![2,3].includes(p.conditions?.options?.version)) throw new Error('Versión de condición no revisada')
    p.conditions.options.version = 3
    for (const c of p.conditions.conditions) delete c.id
  }
  return n
}

export function operacionesFase6(actual, { enviar = false, programar = false, guardarExitos = false } = {}) {
  if (actual.id !== WORKFLOW_ID || actual.active || actual.activeVersionId) throw new Error('Preparar sin publicar y sin ejecuciones concurrentes')
  if ([enviar, programar, guardarExitos].some(x => typeof x !== 'boolean') || (programar && !enviar)) throw new Error('Modo inválido')
  const canon = cargarDefinicion()
  const esperados = new Map(canon.nodes.map(n => [n.name,n]))
  const copia = JSON.parse(JSON.stringify(actual))
  // La transición admite exclusivamente el cierre conocido de fase 5 o el
  // propio código de fase 6; no disfraza cambios ajenos al restaurar el parser.
  const f5 = operacionesFase5({ ...canon, id: WORKFLOW_ID, active:false, activeVersionId:null }, { fila:2 })
  const codigoSeleccion = seleccionarPendientes.toString() + '\nreturn seleccionarPendientes($input.all(),$("Control del envío").first().json.inicio_ms);'
  const resumenBase = esperados.get('Resumen de importación').parameters.jsCode
  const sufijo = 'return [{json:resumirImportacion($input.all().map(item=>item.json),$("Control del envío").first().json.simular_registro)}];'
  if (!resumenBase.endsWith(sufijo)) throw new Error('Cambió el resumen canónico')
  const codigoResumen = resumenBase.slice(0,-sufijo.length) + exigirRevisionRechazos.toString() +
    '\nconst filas=$input.all().map(item=>item.json);\nreturn [{json:exigirRevisionRechazos(resumirImportacion(filas,$("Control del envío").first().json.simular_registro),filas)}];'
  for (const n of copia.nodes) {
    const e = esperados.get(n.name)
    if (!e) throw new Error('Nodo no revisado')
    if (n.parameters.jsCode) {
      const permitidos = [e.parameters.jsCode]
      const guardadoF5 = f5.find(op => op.nodeName === n.name)?.parameters?.jsCode
      if (guardadoF5) permitidos.push(guardadoF5)
      if (n.name === 'Seleccionar lote rotativo') permitidos.push(codigoSeleccion)
      if (n.name === 'Resumen de importación') permitidos.push(codigoResumen)
      if (!permitidos.includes(n.parameters.jsCode)) throw new Error('Código no revisado: ' + n.name)
      n.parameters.jsCode = e.parameters.jsCode
    }
    if (n.name === 'Control del envío') n.parameters.jsonOutput = e.parameters.jsonOutput
    if (['Cada 5 minutos','Importar en CRM'].includes(n.name)) n.disabled = e.disabled ?? false
    if (!jsonIgual(nodoComparable(n),nodoComparable(e))) throw new Error('Configuración de nodo no revisada: ' + n.name)
  }
  comprobarRecorrido(copia)
  const nodo = nombre => actual.nodes.find(n => n.name === nombre)
  for (const nombre of ['Registrar resultado','Omitir filas confirmadas']) {
    if (nodo(nombre).parameters.dataTableId.value !== TABLA_PRODUCCION) throw new Error('Tabla de recibos distinta')
  }
  const http = nodo('Importar en CRM'), eHttp = esperados.get('Importar en CRM')
  if (!jsonIgual({ ...http.parameters, contentType:http.parameters.contentType ?? 'json' },eHttp.parameters) ||
      http.credentials?.httpTemplatedCustomAuth?.id !== 'YNRHr2PjhfLXnKff' ||
      http.onError !== 'continueErrorOutput' || http.retryOnFail !== true || http.maxTries !== 3 ||
      http.waitBetweenTries !== 1000) throw new Error('Importador no coincide con el revisado')
  const intervalos = nodo('Cada 5 minutos').parameters.rule?.interval
  if (!Array.isArray(intervalos) || intervalos.length !== 1 || intervalos[0].field !== 'minutes' ||
      (intervalos[0].minutesInterval ?? 5) !== 5) throw new Error('Intervalo distinto de cinco minutos')
  if (nodo('Leer leads filtrados').credentials?.googleSheetsOAuth2Api?.id !== 'vPzsYCzKnotpycYi' ||
      actual.settings.executionTimeout !== 180 || actual.settings.errorWorkflow !== '4jfthNhVJLiZUeIo') throw new Error('Credencial o control operativo distinto')
  return [
    { type:'setNodeDisabled',nodeName:'Cada 5 minutos',disabled:!programar },
    { type:'updateNodeParameters',nodeName:'Control del envío',parameters:{jsonOutput:'={{ JSON.stringify({enviar_crm:'+enviar+',simular_registro:'+!enviar+',inicio_ms:$now.toMillis()}) }}'} },
    { type:'updateNodeParameters',nodeName:'Preparar leads',parameters:{jsCode:esperados.get('Preparar leads').parameters.jsCode} },
    { type:'updateNodeParameters',nodeName:'Seleccionar lote rotativo',parameters:{jsCode:codigoSeleccion} },
    { type:'updateNodeParameters',nodeName:'Resumen de importación',parameters:{jsCode:codigoResumen} },
    { type:'setNodeDisabled',nodeName:'Importar en CRM',disabled:!enviar },
    { type:'setWorkflowSettings',settings:{...AJUSTES,saveDataSuccessExecution:guardarExitos?'all':'none'} },
  ]
}

// Gate posterior a la escritura. También permite verificar la versión activa
// sin mutarla: exige el código y todos los controles exactos del modo esperado.
export function verificarFase6(actual, modo) {
  const ops = operacionesFase6({...actual,active:false,activeVersionId:null},modo)
  for (const op of ops) {
    if (op.type === 'setWorkflowSettings') {
      for (const [k,v] of Object.entries(op.settings)) if (!jsonIgual(actual.settings[k],v)) throw new Error('Ajuste no aplicado: ' + k)
      continue
    }
    const n = actual.nodes.find(n=>n.name===op.nodeName)
    if ('disabled' in op && (n.disabled ?? false) !== op.disabled) throw new Error('Estado no aplicado: ' + n.name)
    for (const [k,v] of Object.entries(op.parameters ?? {})) if (!jsonIgual(n.parameters[k],v)) throw new Error('Parámetro no aplicado: ' + n.name)
  }
  return true
}

export function restaurarRetencion(actual, versionId) {
  if (!actual.active || !versionId || actual.versionId !== versionId || actual.activeVersionId !== versionId) throw new Error('La versión activa no es la verificada')
  verificarFase6(actual,{enviar:true,programar:true,guardarExitos:true})
  return [{type:'setWorkflowSettings',settings:{...AJUSTES,saveDataSuccessExecution:'none'}}]
}

// Fuente reproducible del flujo operativo. cargarDefinicion() permanece como
// base histórica de fases 1–5; futuros cambios operativos parten de esta función.
// Construye un borrador local: no publica ni llama a servicios.
export function cargarDefinicionOperativa() {
  const w = JSON.parse(JSON.stringify({...cargarDefinicion(),id:WORKFLOW_ID,active:false,activeVersionId:null}))
  for (const op of operacionesFase6(w,{enviar:true,programar:true})) {
    if (op.type === 'setWorkflowSettings') { w.settings = {...op.settings}; continue }
    const n = w.nodes.find(n=>n.name===op.nodeName)
    if (op.parameters) Object.assign(n.parameters,op.parameters)
    if ('disabled' in op) n.disabled=op.disabled
  }
  verificarFase6(w,{enviar:true,programar:true})
  return w
}

export function conciliarFotografia(filas, recibos) {
  if (filas.some(f=>!Number.isInteger(f.fila)||f.fila<2||!/^[0-9a-f]{64}$/.test(f.huella))) throw new Error('Identidad de fila inválida')
  const porHuella = new Map()
  for (const r of recibos) {
    if (!/^[0-9a-f]{64}$/.test(r.huella) || porHuella.has(r.huella) ||
        !['importado','duplicado','ya_cliente','rechazado'].includes(r.resultado) || r.campania !== 'Formulario 3') throw new Error('Recibo inválido o repetido')
    porHuella.set(r.huella,r)
  }
  const porFila = filas.map(f => ({ fila:f.fila, resultado:porHuella.get(f.huella)?.resultado ?? 'pendiente' }))
  const conteos = {}
  for (const r of porFila) conteos[r.resultado] = (conteos[r.resultado] ?? 0) + 1
  const huellas = new Set(filas.map(f=>f.huella))
  return { filas:porFila.length,huellas_unicas:huellas.size,conteos,por_fila:porFila,
    recibos_sin_fila:recibos.filter(r=>!huellas.has(r.huella)).map(r=>({fila:r.fila,resultado:r.resultado})) }
}
