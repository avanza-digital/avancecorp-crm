// Ensayo real en recursos temporales. Sin claves ni sustitución del importador.
// Los IDs de este archivo son HISTÓRICOS: rama, hoja y tablas retiradas;
// workflows archivados. El modo preparado reproduce la configuración auditada,
// no proporciona un entorno vivo. Un nuevo ensayo requiere recursos nuevos.
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { definirNodos, codigoSDK, CONEXIONES, GRUPOS, AJUSTES } from './formulario3.workflow.mjs'

export const REF = 'bxkborlvpmuwttzjrjqn'
export const HOJA = '1QsB_sUVjPJIH4yVSHW7F7isCdGpWogTxfeXs3SNVpfU'
export const GID = '490643893'
export const TABLA = '0AGwleVZe229mdVe'
export const CREDENCIAL = 'CRM — prueba temporal fase 3'
export const ENSAYO_VERIFICADO = Object.freeze({
  credencialId: 'Ag61FRD4BJjGI4hZ',
  credencialNombre: 'Simplified Custom Auth account 2',
  errorWorkflow: 'K5zUJos1RrK1tMv4',
  cron: '0 0 1 1 *',
})
export const ENCABEZADOS = ['Fecha','nombre completo','n.º celular','número de teléfono','¿en qué moneda te interesa ahorrar?','¿qué monto aproximado deseas evaluar para tu depósito?','ciudad','¿qué deseas hacer con qorilazo?','¿qué información te gustaría evaluar antes de realizar un depósito a plazo fijo?','¿qué te gustaría reforzar con el asesor antes de realizar tu deposito a plazo fijjo?']
export const FILAS = [
  ['14/10/2026','PRUEBA F3 HTTP Uno','984300001','','soles','de_50,000_a_100,000','Prueba','Invertir','Tasa','Sin contacto: datos ficticios'],
  ['14/10/2026','PRUEBA F3 HTTP Dos','984300002','','dólares','de_50,000_a_100,000','Prueba','Invertir','Plazo','Sin contacto: datos ficticios'],
]

// El modo preparado reproduce la configuración probada. Antes de publicarlo,
// el flujo de avisos debe existir y estar publicado. No activa ningún flujo.
export function definicion({ preparado = false } = {}) {
  const fuente = readFileSync(new URL('./formulario3.mjs', import.meta.url),'utf8')
    .replace('1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI', HOJA)
    .replace("pestana: 'gid=0'", "pestana: 'gid=" + GID + "'")
  const nodos=definirNodos(fuente)
  for(const n of nodos) {
    if(n.parameters.dataTableId) n.parameters.dataTableId={__rl:true,mode:'id',value:TABLA}
    if(n.name==='Leer leads filtrados') {
      n.parameters.documentId={__rl:true,mode:'id',value:HOJA}
      n.parameters.sheetName={__rl:true,mode:'id',value:GID}
    }
    if(n.name==='Control del envío') n.parameters.jsonOutput='={{ JSON.stringify({enviar_crm:true,simular_registro:false,inicio_ms:$now.toMillis()}) }}'
    if(n.name==='Importar en CRM') {
      n.parameters.url='https://'+REF+'.supabase.co/functions/v1/crm-importar-leads'
      n.credentials={httpTemplatedCustomAuth:{name:CREDENCIAL}}
      n.disabled=true // Activar solo después de asignar la credencial TEMPORAL.
      if(preparado) {
        n.credentials={httpTemplatedCustomAuth:{id:ENSAYO_VERIFICADO.credencialId,name:ENSAYO_VERIFICADO.credencialNombre}}
        n.disabled=false
      }
    }
    if(preparado && n.name==='Cada 5 minutos') n.parameters.rule={interval:[{field:'cronExpression',expression:ENSAYO_VERIFICADO.cron}]}
  }
  const {errorWorkflow,...settings}=AJUSTES
  return {nodes:nodos,connections:CONEXIONES,settings:{...settings,saveDataSuccessExecution:'all',...(preparado?{errorWorkflow:ENSAYO_VERIFICADO.errorWorkflow}:{})},code:codigoSDK(nodos,'formulario3-fase3-20261014','PRUEBA F3 — Sheets → CRM aislado',CONEXIONES,GRUPOS)}
}

export function escritura(filas=FILAS) {
  if(filas.length>38) throw new Error('La hoja de ensayo admite hasta 38 filas')
  return {
    method:'PUT',url:'https://sheets.googleapis.com/v4/spreadsheets/'+HOJA+'/values/Hoja%201!A1:J40?valueInputOption=RAW',
    authentication:'predefinedCredentialType',nodeCredentialType:'googleSheetsOAuth2Api',
    sendBody:true,specifyBody:'json',jsonBody:JSON.stringify({range:'Hoja 1!A1:J40',majorDimension:'ROWS',values:[ENCABEZADOS,...filas,...Array.from({length:39-filas.length},()=>Array(10).fill(''))]}),
    options:{timeout:20000,response:{response:{responseFormat:'json'}}},
  }
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  process.stdout.write(JSON.stringify(process.argv[2]==='escritura'?escritura():definicion({preparado:process.argv[2]==='preparado'})))
}
