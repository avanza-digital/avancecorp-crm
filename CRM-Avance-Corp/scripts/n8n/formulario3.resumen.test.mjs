import test from 'node:test'
import assert from 'node:assert/strict'
import { prepararResumen, cargarResumen, WORKFLOW_RESUMEN } from './formulario3.resumen.mjs'
import { DESTINATARIO } from './formulario3.alertas.mjs'
import { TABLA_LATIDO } from './formulario3.fase7.mjs'

// 16/10/2026 00:00 UTC = 15/10/2026 19:00 en Lima.
const CORTE = Date.UTC(2026, 9, 16)
const recibo = (fila, resultado, ms, estado = 'X') => ({ huella: fila.toString(16).padStart(64, '0'), fila, resultado, estado, createdAt: new Date(ms).toISOString() })
const latido = ms => [{ clave: 'principal', leido_en: new Date(ms).toISOString(), filas_leidas: 160 }]

test('cuenta lo ocurrido entre las 19:00 de ayer y las 19:00 de hoy, sin huecos', () => {
  const recibos = [
    recibo(2, 'importado', CORTE - 86400000 - 1),     // cae en el correo anterior
    recibo(3, 'importado', CORTE - 86400000),         // 19:00 de ayer: entra
    recibo(4, 'duplicado', CORTE - 60000),
    recibo(5, 'ya_cliente', CORTE - 120000, 'YA ES CLIENTE (asesor: Ana): reingreso registrado en su ficha'),
    recibo(6, 'importado', CORTE),                    // 19:00 de hoy: va al correo siguiente
  ]
  const r = prepararResumen(recibos, latido(CORTE - 60000), CORTE + 5000, false)
  assert.match(r.mensaje, /Nuevos en el CRM: 1\n/)
  assert.match(r.mensaje, /Ya existían en el CRM: 1\n/)
  assert.match(r.mensaje, /Clientes que volvieron: 1\n/)
  assert.match(r.mensaje, /del 14\/10 19:00 al 15\/10 19:00/)
  assert.equal(r.asunto, 'Formulario 3 — 1 nuevos')
  assert.equal(r.sin_lectura, false)
  assert.match(r.mensaje, /Última lectura de la hoja: 15\/10 18:59 \(160 filas\)/)
  // El correo siguiente recoge exactamente la fila 6.
  assert.match(prepararResumen(recibos, latido(CORTE + 86400000 - 60000), CORTE + 86400000 + 3000, false).mensaje, /Nuevos en el CRM: 1\n/)
})

test('lista las filas para revisar en orden y sin datos privados', () => {
  const recibos = [
    recibo(9, 'rechazado', CORTE - 1000, 'RECHAZADO: Persona Privada'),
    recibo(7, 'ya_cliente', CORTE - 2000, 'YA ES CLIENTE (asesor: Asesora Privada): NO se pudo anotar (nadie a cargo de este cliente)'),
  ]
  const r = prepararResumen(recibos, latido(CORTE - 1000), CORTE + 1000, false)
  assert.match(r.mensaje, /Filas para revisar en la hoja: 7 \(cliente sin registrar\), 9 \(rechazada\)/)
  assert.equal(r.asunto, 'Formulario 3 — 0 nuevos · 2 para revisar')
  assert.ok(!/Privad/.test(r.asunto + r.mensaje))
})

test('sin recibos ni latido avisa con ⚠️ en lugar de fallar', () => {
  const r = prepararResumen([{}], [{}], CORTE + 1000, false)
  assert.equal(r.sin_lectura, true)
  assert.match(r.asunto, /^⚠️ Formulario 3: sin lectura de la hoja desde hace tiempo$/)
  assert.match(r.mensaje, /el flujo está detenido o la hoja quedó vacía/)
  assert.match(r.mensaje, /Nuevos en el CRM: 0\n/)
  assert.match(r.mensaje, /Filas para revisar en la hoja: ninguna/)
  assert.match(r.mensaje, /Última lectura de la hoja: sin registro/)
  const viejo = prepararResumen([], latido(CORTE - 21 * 60000), CORTE, false)
  assert.equal(viejo.sin_lectura, true)
  assert.match(viejo.asunto, /desde 15\/10 18:39/)
  assert.equal(prepararResumen([], latido(CORTE - 19 * 60000), CORTE, false).sin_lectura, false)
})

test('cuenta más de 100 recibos y falla ante un recibo imposible', () => {
  const muchos = Array.from({ length: 250 }, (_, i) => recibo(i + 2, 'importado', CORTE - 1000 - i))
  assert.match(prepararResumen(muchos, latido(CORTE), CORTE + 1, false).mensaje, /Nuevos en el CRM: 250\n/)
  assert.throws(() => prepararResumen([{ huella: 'a'.repeat(64), resultado: 'importado' }], latido(CORTE), CORTE, false), /sin fecha/)
  assert.throws(() => prepararResumen([recibo(2, 'otro', CORTE - 1)], latido(CORTE), CORTE, false), /desconocido/)
  assert.throws(() => prepararResumen([], [], Number.NaN, false), /hora/)
})

test('la prueba se marca y termina en el momento de la ejecución', () => {
  const ahora = CORTE + 3 * 3600000
  const r = prepararResumen([recibo(2, 'importado', ahora - 1000)], latido(ahora - 1000), ahora, true)
  assert.match(r.asunto, /^\[PRUEBA\] Formulario 3 — 1 nuevos$/)
  assert.match(r.mensaje, /al 15\/10 22:00/)
})

test('el flujo lee las dos tablas, ejecuta su código y escribe solo a Miguel', () => {
  const d = cargarResumen()
  assert.equal(d.workflowId, WORKFLOW_RESUMEN)
  const n = nombre => d.nodes.find(x => x.name === nombre)
  assert.deepEqual(n('Cada día 7 p. m.').parameters.rule.interval, [{ field: 'cronExpression', expression: '0 19 * * *' }])
  assert.equal(n('Leer recibos').parameters.dataTableId.value, '1foRUzITWOnUJsNf')
  assert.equal(n('Leer recibos').parameters.returnAll, true)
  assert.equal(n('Leer recibos').alwaysOutputData, true)
  assert.equal(n('Leer latido').parameters.dataTableId.value, TABLA_LATIDO)
  assert.equal(n('Enviar resumen a Miguel').parameters.sendTo, DESTINATARIO)
  assert.equal(n('Enviar resumen a Miguel').credentials.gmailOAuth2.id, 'FNfEzbpTEsdutlzd')
  assert.equal(d.settings.errorWorkflow, '4jfthNhVJLiZUeIo')
  assert.equal(d.settings.timezone, 'America/Lima')
  assert.deepEqual(d.connections.map(c => c.target), ['Leer recibos', 'Leer recibos', 'Leer latido', 'Preparar resumen', 'Enviar resumen a Miguel'])
  const codigo = n('Preparar resumen').parameters.jsCode
  const tabla = { 'Leer recibos': [{ json: {} }], 'Leer latido': [{ json: latido(Date.now())[0] }] }
  const entorno = programado => nombre => ({ all: () => tabla[nombre], isExecuted: nombre === 'Cada día 7 p. m.' && programado })
  const salida = new Function('$', codigo)(entorno(true))
  assert.equal(salida[0].json.sin_lectura, false)
  assert.doesNotMatch(salida[0].json.asunto, /PRUEBA/)
  const prueba = new Function('$', codigo)(entorno(false))
  assert.match(prueba[0].json.asunto, /^\[PRUEBA\]/)
})
