// Resumen diario de Formulario 3: cuenta lo ocurrido desde las 19:00 del día
// anterior y dice cuándo leyó n8n la hoja por última vez. Sin datos de leads:
// solo totales y números de fila.
import { pathToFileURL } from 'node:url'
import { codigoSDK, TABLA_PRODUCCION, WORKFLOW_ID } from './formulario3.workflow.mjs'
import { DESTINATARIO } from './formulario3.alertas.mjs'
import { estadoClienteCorrecto, TABLA_LATIDO } from './formulario3.fase7.mjs'

export const WORKFLOW_RESUMEN = 'Chn5g93IgxNlkF3K'
export const NOMBRE_RESUMEN = 'Avance Corp — Resumen diario de Formulario 3'

// 19:00 en Lima (UTC-5, sin horario de verano) es exactamente 00:00 UTC. El
// intervalo real es [19:00 de ayer, 19:00 de hoy): sin huecos ni solapes entre
// correos. En prueba termina en el momento de la ejecución.
export function prepararResumen(recibos, latidos, ahoraMs, prueba) {
  if (!Number.isFinite(ahoraMs) || ahoraMs < 0) throw new Error('Falta la hora del resumen')
  const DIA = 86400000, LIMA = 5 * 3600000, MARGEN = 20 * 60000
  const fin = prueba === true ? ahoraMs : Math.floor(ahoraMs / DIA) * DIA
  const inicio = fin - DIA
  const fecha = (ms) => {
    const d = new Date(ms - LIMA)
    const dos = (n) => String(n).padStart(2, '0')
    return dos(d.getUTCDate()) + '/' + dos(d.getUTCMonth() + 1) + ' ' + dos(d.getUTCHours()) + ':' + dos(d.getUTCMinutes())
  }
  const cuenta = { importado: 0, duplicado: 0, ya_cliente: 0 }
  const revisar = []
  for (const recibo of recibos) {
    // La lectura vacía llega como un ítem sin columnas (alwaysOutputData).
    if (!recibo || typeof recibo.huella !== 'string') continue
    const ms = Date.parse(recibo.createdAt ?? recibo.procesado_en)
    if (!Number.isFinite(ms)) throw new Error('Recibo sin fecha')
    if (ms < inicio || ms >= fin) continue
    if (recibo.resultado === 'rechazado') revisar.push({ fila: recibo.fila, motivo: 'rechazada' })
    else if (recibo.resultado === 'ya_cliente' && !estadoClienteCorrecto(recibo.estado)) revisar.push({ fila: recibo.fila, motivo: 'cliente sin registrar' })
    else if (Object.hasOwn(cuenta, recibo.resultado)) cuenta[recibo.resultado]++
    else throw new Error('Recibo con resultado desconocido')
  }
  revisar.sort((a, b) => a.fila - b.fila)
  const latido = latidos.find((l) => l && l.clave === 'principal')
  const leidoMs = Date.parse(latido?.leido_en)
  const sinLectura = !Number.isFinite(leidoMs) || ahoraMs - leidoMs > MARGEN
  const filasLeidas = Number.isInteger(Number(latido?.filas_leidas)) ? Number(latido.filas_leidas) : null
  const ultima = Number.isFinite(leidoMs) ? fecha(leidoMs) + (filasLeidas === null ? '' : ' (' + filasLeidas + ' filas)') : 'sin registro'
  const url = 'https://n8n-t27j.srv1906432.hstgr.cloud/workflow/BjI5m1PKVWhO0NDb'
  const asunto = (prueba === true ? '[PRUEBA] ' : '') + (sinLectura
    ? '⚠️ Formulario 3: sin lectura de la hoja desde ' + (Number.isFinite(leidoMs) ? fecha(leidoMs) : 'hace tiempo')
    : 'Formulario 3 — ' + cuenta.importado + ' nuevos' + (revisar.length ? ' · ' + revisar.length + ' para revisar' : ''))
  const lineas = [
    'Formulario 3, del ' + fecha(inicio) + ' al ' + fecha(fin) + ' (hora de Lima).',
    '',
    'Nuevos en el CRM: ' + cuenta.importado,
    'Ya existían en el CRM: ' + cuenta.duplicado,
    'Clientes que volvieron: ' + cuenta.ya_cliente,
    'Filas para revisar en la hoja: ' + (revisar.length ? revisar.map((r) => r.fila + ' (' + r.motivo + ')').join(', ') : 'ninguna'),
    '',
    'Última lectura de la hoja: ' + ultima,
  ]
  // El latido se escribe cuando la hoja se lee con al menos una fila: una hoja
  // vacía también deja de latir, y eso merece revisión.
  if (sinLectura) lineas.push('⚠️ Hace más de 20 minutos que n8n no lee filas de la hoja: el flujo está detenido o la hoja quedó vacía. Revisa: ' + url)
  lineas.push('', 'Flujo: ' + url, 'Si un día no llega este correo, algo falla (n8n, Gmail o este resumen): revisa n8n.')
  return { asunto, mensaje: lineas.join('\n'), revisar: revisar.length, sin_lectura: sinLectura }
}

export function definirResumen(tablaRecibos = TABLA_PRODUCCION, tablaLatido = TABLA_LATIDO) {
  const codigo = estadoClienteCorrecto.toString() + '\n' + prepararResumen.toString() +
    "\nreturn [{json:prepararResumen($('Leer recibos').all().map(i=>i.json),$('Leer latido').all().map(i=>i.json),Date.now(),!$('Cada día 7 p. m.').isExecuted)}];"
  const tabla = (value, cachedResultName) => ({ __rl: true, mode: 'list', value, cachedResultName })
  const muestra = { asunto: 'Formulario 3 — 0 nuevos', mensaje: 'Resumen', revisar: 0, sin_lectura: false }
  return [
    { name: 'Cada día 7 p. m.', type: 'n8n-nodes-base.scheduleTrigger', typeVersion: 1.2, parameters: { rule: { interval: [{ field: 'cronExpression', expression: '0 19 * * *' }] } }, position: [0, 0], output: [{}] },
    { name: 'Probar resumen', type: 'n8n-nodes-base.manualTrigger', typeVersion: 1, parameters: {}, position: [0, 240], output: [{}] },
    { name: 'Leer recibos', type: 'n8n-nodes-base.dataTable', typeVersion: 1.1, alwaysOutputData: true, parameters: { resource: 'row', operation: 'get', dataTableId: tabla(tablaRecibos, 'Formulario 3 — importaciones'), returnAll: true }, position: [280, 120], output: [{ huella: 'a'.repeat(64), fila: 2, resultado: 'importado', estado: 'IMPORTADO ✓', createdAt: '2026-10-15T12:00:00.000Z' }] },
    { name: 'Leer latido', type: 'n8n-nodes-base.dataTable', typeVersion: 1.1, alwaysOutputData: true, executeOnce: true, parameters: { resource: 'row', operation: 'get', dataTableId: tabla(tablaLatido, 'Formulario 3 — latido'), matchType: 'allConditions', filters: { conditions: [{ keyName: 'clave', condition: 'eq', keyValue: 'principal' }] }, returnAll: true }, position: [560, 120], output: [{ clave: 'principal', leido_en: '2026-10-15T18:55:00.000-05:00', filas_leidas: 160 }] },
    { name: 'Preparar resumen', type: 'n8n-nodes-base.code', typeVersion: 2, parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: codigo }, position: [840, 120], output: [muestra] },
    { name: 'Enviar resumen a Miguel', type: 'n8n-nodes-base.gmail', typeVersion: 2.2, parameters: { resource: 'message', operation: 'send', authentication: 'oAuth2', sendTo: DESTINATARIO, subject: '={{ $json.asunto }}', emailType: 'text', message: '={{ $json.mensaje }}', options: { appendAttribution: false, senderName: 'Avance Corp — Automatizaciones' } }, credentials: { gmailOAuth2: { id: 'FNfEzbpTEsdutlzd', name: 'Gmail account' } }, position: [1120, 120], output: [{ id: 'mensaje', labelIds: ['SENT'] }] },
  ]
}

export const CONEXIONES_RESUMEN = [
  { source: 'Cada día 7 p. m.', target: 'Leer recibos', sourceIndex: 0, targetIndex: 0 },
  { source: 'Probar resumen', target: 'Leer recibos', sourceIndex: 0, targetIndex: 0 },
  { source: 'Leer recibos', target: 'Leer latido', sourceIndex: 0, targetIndex: 0 },
  { source: 'Leer latido', target: 'Preparar resumen', sourceIndex: 0, targetIndex: 0 },
  { source: 'Preparar resumen', target: 'Enviar resumen a Miguel', sourceIndex: 0, targetIndex: 0 },
]
export const GRUPOS_RESUMEN = [{ name: 'Resumen diario', description: 'Cuenta los recibos del día y la última lectura de la hoja; envía solo totales y números de fila.', nodeNames: ['Leer recibos', 'Leer latido', 'Preparar resumen', 'Enviar resumen a Miguel'] }]
export const AJUSTES_RESUMEN = { executionOrder: 'v1', timezone: 'America/Lima', executionTimeout: 120, saveDataSuccessExecution: 'none', saveDataErrorExecution: 'all', saveManualExecutions: true, errorWorkflow: '4jfthNhVJLiZUeIo' }

export function cargarResumen(tablaRecibos, tablaLatido) {
  const nodes = definirResumen(tablaRecibos, tablaLatido)
  return { workflowId: WORKFLOW_RESUMEN, name: NOMBRE_RESUMEN, nodes, connections: CONEXIONES_RESUMEN, nodeGroups: GRUPOS_RESUMEN, settings: AJUSTES_RESUMEN, code: codigoSDK(nodes, WORKFLOW_RESUMEN, NOMBRE_RESUMEN, CONEXIONES_RESUMEN, GRUPOS_RESUMEN), importador: WORKFLOW_ID }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.stdout.write(JSON.stringify(cargarResumen()))
