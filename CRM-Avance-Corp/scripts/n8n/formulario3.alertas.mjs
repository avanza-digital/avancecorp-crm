// Avisos sin datos de leads ni mensajes crudos del servidor.
import { pathToFileURL } from 'node:url'
import { codigoSDK, WORKFLOW_ID, NOMBRE } from './formulario3.workflow.mjs'

export const WORKFLOW_AVISOS = '4jfthNhVJLiZUeIo'
export const TABLA_AVISOS = 'TcpMCmhVw3oT9GjD'
export const DESTINATARIO = 'miguel@miavance.com'
export const NOMBRE_AVISOS = 'Avance Corp — Avisos de Formulario 3'

export function prepararAlerta(evento, ahoraMs) {
  if (evento?.workflow?.id !== 'BjI5m1PKVWhO0NDb') return null
  if (!Number.isFinite(ahoraMs) || ahoraMs < 0) throw new Error('Falta la hora del aviso')
  const prueba = evento.prueba === true
  const id = String(evento.execution?.id ?? '')
  const ejecucion = /^\d+$/.test(id) ? id : 'consultar historial'
  const url = 'https://n8n-t27j.srv1906432.hstgr.cloud/workflow/BjI5m1PKVWhO0NDb'
  return {
    clave: 'BjI5m1PKVWhO0NDb|' + (prueba ? 'prueba|' : 'error|') + Math.floor(ahoraMs / 3600000),
    workflow: 'BjI5m1PKVWhO0NDb',
    asunto: (prueba ? '[PRUEBA] ' : '') + 'Avance Corp — Revisar importación Formulario 3',
    mensaje: prueba
      ? 'Este es un aviso de prueba de Formulario 3. El canal de correo funciona.\n\nFlujo: ' + url
      : 'La importación de Formulario 3 terminó con un error.\nEjecución: ' + ejecucion + '\n\nRevisa la ejecución en n8n para identificar los pendientes y corregir el problema:\n' + url + '\n\nSe envía como máximo un aviso por hora mientras persistan los errores.',
  }
}

export function definirAvisos() {
  const codigo = prepararAlerta.toString() + '\nreturn $input.all().map((item,i)=>({json:prepararAlerta(item.json,Date.now()),pairedItem:{item:i}})).filter(item=>item.json!==null);'
  const sample = prepararAlerta({ workflow: { id: WORKFLOW_ID }, execution: { id: '24' } }, 1792010000000)
  return [
    { name: 'Error de importación', type: 'n8n-nodes-base.errorTrigger', typeVersion: 1, parameters: {}, position: [0,0], output: [{workflow:{id:WORKFLOW_ID,name:NOMBRE},execution:{id:'24',error:{message:'Error de prueba'}}}] },
    { name: 'Probar aviso por correo', type: 'n8n-nodes-base.manualTrigger', typeVersion: 1, parameters: {}, position: [0,300], output: [{}] },
    { name: 'Preparar prueba de aviso', type: 'n8n-nodes-base.set', typeVersion: 3.5, parameters: { mode:'raw',jsonOutput:JSON.stringify({prueba:true,workflow:{id:WORKFLOW_ID},execution:{id:'0'}}) }, position: [280,300],output:[{prueba:true,workflow:{id:WORKFLOW_ID},execution:{id:'0'}}] },
    { name: 'Preparar aviso', type: 'n8n-nodes-base.code', typeVersion: 2, parameters: {mode:'runOnceForAllItems',language:'javaScript',jsCode:codigo}, position:[580,100],output:[sample] },
    { name: 'Limitar avisos a uno por hora', type:'n8n-nodes-base.dataTable',typeVersion:1.1,parameters:{resource:'row',operation:'rowNotExists',dataTableId:{__rl:true,mode:'list',value:TABLA_AVISOS,cachedResultName:'Formulario 3 — avisos enviados'},matchType:'allConditions',filters:{conditions:[{keyName:'clave',condition:'eq',keyValue:'={{ $json.clave }}'}]}},position:[860,100],output:[sample] },
    { name:'Enviar aviso a Miguel',type:'n8n-nodes-base.gmail',typeVersion:2.2,parameters:{resource:'message',operation:'send',authentication:'oAuth2',sendTo:DESTINATARIO,subject:'={{ $json.asunto }}',emailType:'text',message:'={{ $json.mensaje }}',options:{appendAttribution:false,senderName:'Avance Corp — Automatizaciones'}},credentials:{gmailOAuth2:{id:'FNfEzbpTEsdutlzd',name:'Gmail account'}},position:[1140,100],output:[{id:'mensaje-de-prueba',threadId:'hilo-de-prueba',labelIds:['SENT']}] },
    { name:'Registrar aviso enviado',type:'n8n-nodes-base.dataTable',typeVersion:1.1,parameters:{resource:'row',operation:'upsert',dataTableId:{__rl:true,mode:'list',value:TABLA_AVISOS,cachedResultName:'Formulario 3 — avisos enviados'},matchType:'allConditions',filters:{conditions:[{keyName:'clave',condition:'eq',keyValue:'={{ $("Preparar aviso").first().json.clave }}'}]},columns:{mappingMode:'defineBelow',value:{clave:'={{ $("Preparar aviso").first().json.clave }}',workflow:'={{ $("Preparar aviso").first().json.workflow }}',enviado_en:'={{ $now.toISO() }}'}},options:{dryRun:false}},position:[1420,100],output:[{id:1,clave:sample.clave,workflow:WORKFLOW_ID}] },
  ]
}

export const CONEXIONES_AVISOS = [
  { source:'Error de importación',target:'Preparar aviso',sourceIndex:0,targetIndex:0 },
  { source:'Probar aviso por correo',target:'Preparar prueba de aviso',sourceIndex:0,targetIndex:0 },
  { source:'Preparar prueba de aviso',target:'Preparar aviso',sourceIndex:0,targetIndex:0 },
  { source:'Preparar aviso',target:'Limitar avisos a uno por hora',sourceIndex:0,targetIndex:0 },
  { source:'Limitar avisos a uno por hora',target:'Enviar aviso a Miguel',sourceIndex:0,targetIndex:0 },
  { source:'Enviar aviso a Miguel',target:'Registrar aviso enviado',sourceIndex:0,targetIndex:0 },
]
export const GRUPOS_AVISOS = [{name:'Aviso por correo',description:'Prepara el aviso, limita repeticiones a una por hora y registra el envío confirmado.',nodeNames:['Preparar aviso','Limitar avisos a uno por hora','Enviar aviso a Miguel','Registrar aviso enviado']}]

export function cargarAvisos() {
  const nodes=definirAvisos()
  return { workflowId:WORKFLOW_AVISOS,name:NOMBRE_AVISOS,nodes,connections:CONEXIONES_AVISOS,nodeGroups:GRUPOS_AVISOS,settings:{executionOrder:'v1',timezone:'America/Lima',executionTimeout:120,saveDataSuccessExecution:'none',saveDataErrorExecution:'all',saveManualExecutions:true},code:codigoSDK(nodes,WORKFLOW_AVISOS,NOMBRE_AVISOS,CONEXIONES_AVISOS,GRUPOS_AVISOS) }
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) process.stdout.write(JSON.stringify(cargarAvisos()))
