import { definirAvisos, CONEXIONES_AVISOS, GRUPOS_AVISOS } from './formulario3.alertas.mjs'
import { codigoSDK } from './formulario3.workflow.mjs'

// Copia del mecanismo real: Error Trigger, límite horario, Gmail y recibo.
// Únicamente cambian los identificadores aislados y la etiqueta de prueba.
export function definicion() {
  const nodes=JSON.parse(JSON.stringify(definirAvisos())
    .replaceAll('BjI5m1PKVWhO0NDb','OKrtxmixSxpfhVxE')
    .replaceAll('TcpMCmhVw3oT9GjD','AzKAJhB5uALZDNuL'))
    .filter(n=>!['Probar aviso por correo','Preparar prueba de aviso'].includes(n.name))
  const preparar=nodes.find(n=>n.name==='Preparar aviso')
  preparar.parameters.jsCode=preparar.parameters.jsCode
    .replace("asunto: (prueba ? '[PRUEBA] ' : '') +", "asunto: '[PRUEBA F3] ' +")
    .replace('La importación de Formulario 3 terminó con un error.', 'PRUEBA AISLADA: se provocó un fallo controlado en la importación de Formulario 3.')
  const names=new Set(nodes.map(n=>n.name))
  const connections=CONEXIONES_AVISOS.filter(c=>names.has(c.source)&&names.has(c.target))
  const name='PRUEBA F3 — avisos automáticos aislados'
  return {name,nodes,connections,code:codigoSDK(nodes,'prueba-f3-avisos',name,connections,GRUPOS_AVISOS)}
}
process.stdout.write(JSON.stringify(definicion()))
