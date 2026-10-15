// Paridad comercial real: Auth, importador, RPC y Storage de la rama autorizada.
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { writeFileSync } from 'node:fs'
import { importar, sesion, usuarios, ref } from './auth-http.mjs'

assert.equal(ref, 'bxkborlvpmuwttzjrjqn')
const evidencia = { rama: ref, casos: [], conversiones: [], objetos: [] }
const guardar = () => writeFileSync(new URL('./conversion-real.json', import.meta.url), JSON.stringify(evidencia, null, 2) + '\n')
const pasa = (nombre, datos = {}) => { evidencia.casos.push({ nombre, estado: 'PASS', ...datos }); console.log('PASS: ' + nombre); guardar() }
const exigir = (r, nombre) => { assert.equal(r.error, null, nombre + ': ' + r.error?.message); return r.data }
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUN0AAAAASUVORK5CYII=', 'base64')
const fecha = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
const vence = String(Number(fecha.slice(0, 4)) + 1) + fecha.slice(4)

try {
  const { cliente } = await sesion('vendedor')
  const crm = cliente.schema('crm')
  for (const [i, campania] of [null, 'Formulario 3'].entries()) {
    const numero = 31 + i
    const fila = { fila: numero, nombre: 'PRUEBA F3 Conversión ' + (campania ?? 'Legacy'), telefono: '9843000' + numero,
      capital: '5000', moneda: 'PEN', canal: 'FORMULARIO', autorizo: 'SI', fuente_consentimiento: 'Ensayo aislado F3',
      vendedor_correo: usuarios.vendedor.email, ...(campania ? { campania_origen: campania } : {}) }
    const alta = await importar([fila])
    // Conservar el alta incluso si falla un paso posterior. La evidencia del
    // ensayo del 14/10 no incluía este campo; no se rellena retroactivamente.
    evidencia.altas ??= []
    evidencia.altas.push({ campania, status: alta.status, resultados: alta.body?.resultados })
    guardar()
    assert.equal(alta.status, 200); assert.ok(['importado', 'duplicado'].includes(alta.body.resultados[0].resultado))
    const lead = exigir(await crm.from('leads').select('id,campania_origen,origen,vendedor_id').eq('telefono', '+51' + fila.telefono).single(), 'Leer alta')
    assert.equal(lead.campania_origen, campania)
    const dni = '494300' + numero
    const persona = exigir(await crm.rpc('preparar_persona_lead_inversion_fn', { p_lead: lead.id, p_tipo_documento: 'DNI', p_documento: dni, p_nombre: fila.nombre }), 'Preparar persona')
    pasa('Alta y reconocimiento real: ' + (campania ?? 'Legacy'), { lead_id: lead.id, inversionista_id: persona.inversionista_id })
    const reingreso = await importar([{ ...fila, dni }])
    assert.equal(reingreso.status, 200); assert.equal(reingreso.body.resultados[0].resultado, 'ya_cliente')
    const repetido = await importar([{ ...fila, dni, fila: numero + 100 }])
    assert.equal(repetido.status, 200); assert.equal(repetido.body.resultados[0].resultado, 'ya_cliente')
    const notas = exigir(await crm.from('actividades').select('id,detalle,metadata').eq('lead_id', lead.id).contains('metadata', { evento: 'reingreso' }), 'Reingresos')
    assert.equal(notas.length, 1)
    if (campania) { assert.equal(notas[0].metadata.datos.campania_origen, campania); assert.match(notas[0].detalle, /Formulario 3/) }
    pasa('Reingreso HTTP conserva una sola nota: ' + (campania ?? 'Legacy'), { resultados: [reingreso.body.resultados, repetido.body.resultados], notas })
    const clave = randomUUID()
    const ruta = persona.inversionista_id + '/' + clave + '/comprobante.png'
    const datos = { inversionista_id: persona.inversionista_id, lead_id: lead.id, empresa: 'qorilazo', moneda: 'PEN', monto: 5000,
      fecha_comercial: fecha, vence_en: vence, plazo_meses: 12, tasa_anual: 18, numero_transaccion: 'F3-' + clave, referencia: 'CERTIFICADO FICTICIO F3', evidencia: { ruta } }
    const preparada = exigir(await crm.rpc('preparar_inversion_fn', { p_clave: clave, p_datos: datos }), 'Preparar inversión')
    assert.equal(preparada.solicitud_id, clave)
    exigir(await cliente.storage.from('f4-comprobantes').upload(ruta, png, { contentType: 'image/png' }), 'Subir comprobante ficticio')
    evidencia.objetos.push(ruta); guardar()
    const confirmada = exigir(await crm.rpc('confirmar_inversion_revisada_fn', { p_solicitud: clave, p_revision_datos_esperada: 0 }), 'Confirmar inversión')
    const otra = exigir(await crm.rpc('confirmar_inversion_revisada_fn', { p_solicitud: clave, p_revision_datos_esperada: 0 }), 'Reintentar confirmación')
    assert.equal(otra.inversion_id, confirmada.inversion_id)
    const final = exigir(await crm.from('leads').select('id,etapa,campania_origen,origen,vendedor_id').eq('id', lead.id).single(), 'Leer cierre')
    assert.equal(final.etapa, 'convertido'); assert.equal(final.campania_origen, campania); assert.equal(final.origen, 'formulario'); assert.equal(final.vendedor_id, usuarios.vendedor.id)
    evidencia.conversiones.push({ campania, lead: final, solicitud_id: clave, resultado: confirmada })
    pasa('Conversión y reintento único por la puerta actual: ' + (campania ?? 'Legacy'))
  }
} catch (e) { evidencia.error = e.name + ': ' + e.message; guardar(); console.error(evidencia.error); process.exitCode = 1 }
