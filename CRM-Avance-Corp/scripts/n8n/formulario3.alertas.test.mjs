import { test } from 'node:test'
import assert from 'node:assert/strict'
import { prepararAlerta, cargarAvisos, TABLA_AVISOS, DESTINATARIO } from './formulario3.alertas.mjs'
const evento={workflow:{id:'BjI5m1PKVWhO0NDb'},execution:{id:'25',error:{message:'SECRETO-no-se-debe-enviar'},data:{telefono:'999000111'}}}

test('el aviso usa el destinatario autorizado y excluye mensajes crudos, secretos y datos personales',()=>{
  const aviso=prepararAlerta(evento,3600000)
  assert.equal(DESTINATARIO,'miguel@miavance.com')
  assert.ok(!JSON.stringify(aviso).includes('SECRETO'))
  assert.ok(!JSON.stringify(aviso).includes('999000111'))
  assert.match(aviso.mensaje,/Ejecución: 25/)
  assert.equal(prepararAlerta({workflow:{id:'otro-flujo'}},3600000),null)
})

test('la clave agrupa errores de la misma hora y separa las pruebas del aviso real',()=>{
  const a=prepararAlerta(evento,3600000)
  assert.equal(a.clave,prepararAlerta({...evento,execution:{id:'26'}},7199999).clave)
  assert.notEqual(a.clave,prepararAlerta(evento,7200000).clave)
  assert.notEqual(a.clave,prepararAlerta({...evento,prueba:true},3600000).clave)
  assert.match(prepararAlerta({...evento,prueba:true},3600000).asunto,/^\[PRUEBA\]/)
})

test('el recibo del aviso se escribe después de Gmail y ambas tablas apuntan al registro de avisos',()=>{
  const d=cargarAvisos()
  assert.ok(d.nodes.filter(n=>n.parameters.dataTableId).every(n=>n.parameters.dataTableId.value===TABLA_AVISOS))
  assert.equal(d.nodes.find(n=>n.name==='Enviar aviso a Miguel').parameters.sendTo,DESTINATARIO)
  assert.deepEqual(d.connections.filter(e=>e.target==='Registrar aviso enviado').map(e=>e.source),['Enviar aviso a Miguel'])
  assert.equal(d.nodes.find(n=>n.name==='Enviar aviso a Miguel').onError,undefined)
})

test('datos inesperados del error no fabrican enlaces ni contenido en el correo',()=>{
  const a=prepararAlerta({...evento,execution:{id:'https://malicioso.example',url:'https://malicioso.example'}},3600000)
  assert.ok(!a.mensaje.includes('malicioso'))
  assert.throws(()=>prepararAlerta(evento,NaN))
})

test('fase 7: el correo copia solo la lista de filas y reconoce el resumen diario', () => {
  const aviso = (id, message) => prepararAlerta({ workflow: { id }, execution: { id: '30', error: { message } } }, 3600000)
  const lista = 'Revisar filas de la hoja: 153 (rechazada), 160 (cliente sin registrar). Pendientes para reintentar: 161.'
  assert.match(aviso('BjI5m1PKVWhO0NDb', lista).mensaje, /terminó con un error\.\nRevisar filas de la hoja: 153 \(rechazada\), 160 \(cliente sin registrar\)\. Pendientes para reintentar: 161\.\nEjecución: 30/)
  assert.match(aviso('BjI5m1PKVWhO0NDb', lista + ' [line 245]').mensaje, /Pendientes para reintentar: 161\.\nEjecución/)
  assert.match(aviso('BjI5m1PKVWhO0NDb', 'Pendientes para reintentar: 4, 5.').mensaje, /Pendientes para reintentar: 4, 5\.\n/)
  for (const otro of ['Revisar filas de la hoja: 153 (Persona Privada).', 'SECRETO 999000111', lista + ' extra', '']) {
    assert.match(aviso('BjI5m1PKVWhO0NDb', otro).mensaje, /terminó con un error\.\nEjecución: 30/)
  }
  const resumen = aviso('Chn5g93IgxNlkF3K', 'Recibo sin fecha')
  assert.match(resumen.asunto, /resumen diario/)
  assert.match(resumen.mensaje, /workflow\/Chn5g93IgxNlkF3K/)
  assert.ok(!resumen.mensaje.includes('Recibo sin fecha'))
  assert.notEqual(resumen.clave, aviso('BjI5m1PKVWhO0NDb', '').clave)
  assert.equal(aviso('toString', ''), null)
  assert.equal(aviso('__proto__', ''), null)
})
