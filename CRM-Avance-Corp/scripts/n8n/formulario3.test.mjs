import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { CAMPAÑA, COLUMNAS, capitalEstimado, monedaDeRespuesta, prepararFila, resumirPreparacion, conciliarRespuesta, validarColumnas, pendienteDeFila, resumirImportacion, seleccionarLote } from './formulario3.mjs'

function registro(cambios = {}) {
  return {
    row_number: 2,
    [COLUMNAS.fecha]: '2026-10-07T22:33:22-05:00',
    [COLUMNAS.intencion]: 'ahorrar',
    [COLUMNAS.informacion]: 'las_tasas',
    [COLUMNAS.moneda]: '🇵🇪_soles',
    [COLUMNAS.capital]: 'de_50,000_a_100,000',
    [COLUMNAS.asesor]: 'requisitos',
    [COLUMNAS.telefono]: 999000111,
    [COLUMNAS.nombre]: 'PERSONA DE PRUEBA',
    [COLUMNAS.alternativo]: 'p:+51999000112',
    [COLUMNAS.ciudad]: 'Lima',
    ...cambios,
  }
}

test('el rango de capital conserva el piso decidido para el puente y no fabrica un promedio', () => {
  assert.equal(capitalEstimado('de_50,000_a_100,000'), '50000')
  assert.equal(capitalEstimado('de_5,000_a_20,000'), '5000')
  assert.equal(capitalEstimado('más_de_100,000'), '100000')
  assert.equal(capitalEstimado('50,000_a_más'), '50000')
  assert.equal(capitalEstimado('100,000_o_más.'), '100000')
  assert.equal(capitalEstimado(50000.50), '50000.5')
})

test('un capital ambiguo, invertido, ausente o fuera de límite necesita revisión', () => {
  for (const valor of ['', '12,50', '50.000,00', '5000.999', 'de_20,000_a_5,000', '0', '-5000', '10,000,000,000']) {
    assert.throws(() => capitalEstimado(valor), undefined, String(valor))
  }
})

test('monedas con emojis, subrayados y tildes se reconocen; se conserva la regla de moneda mixta', () => {
  assert.deepEqual(monedaDeRespuesta('🇵🇪_soles'), { moneda: 'PEN', ambigua: false })
  assert.deepEqual(monedaDeRespuesta('🇺🇸_dólares'), { moneda: 'USD', ambigua: false })
  assert.deepEqual(monedaDeRespuesta('Soles/Dólares'), { moneda: 'PEN', ambigua: true })
  assert.throws(() => monedaDeRespuesta('euros'))
})

test('la importación conserva los dos candidatos a teléfono, la fecha, las respuestas y la campaña', () => {
  const fila = prepararFila(registro())
  const carga = fila.payload.filas[0]
  assert.equal(fila.mapeo_correcto, true)
  assert.equal(carga.telefono, '999000111')
  assert.equal(carga.telefono_alternativo, 'p:+51999000112')
  assert.equal(carga.canal, 'FORMULARIO')
  assert.equal(carga.campania_origen, CAMPAÑA)
  assert.equal(carga.capital, '50000')
  assert.equal(carga.moneda, 'PEN')
  assert.equal(carga.autorizo, 'SI')
  assert.match(carga.nota, /Campaña: Formulario 3/)
  assert.match(carga.nota, /2026-10-07T22:33:22-05:00/)
  assert.match(carga.nota, /de_50,000_a_100,000/)
  assert.match(carga.nota, /las_tasas/)
  assert.equal(carga.vendedor_correo, undefined)
})

test('un primer teléfono vacío no elimina una fila que conserva el segundo', () => {
  const fila = prepararFila(registro({ [COLUMNAS.telefono]: '' }))
  assert.equal(fila.mapeo_correcto, true)
  assert.equal(fila.payload.filas[0].telefono_alternativo, 'p:+51999000112')
})

test('una fila incompleta se expone en el resumen y no se anuncia como preparada', () => {
  const mala = prepararFila(registro({ [COLUMNAS.nombre]: '', [COLUMNAS.capital]: 'no_se' }))
  const resumen = resumirPreparacion([prepararFila(registro()), mala])
  assert.equal(resumen.total_filas, 2)
  assert.equal(resumen.preparadas, 1)
  assert.equal(resumen.para_revisar.length, 1)
  assert.equal(resumen.envios_crm, 0)
})

test('una fila enteramente vacía de la hoja se omite, sin ocultar una fila parcialmente rellenada', () => {
  assert.equal(prepararFila({ row_number: 110 }), null)
  const parcial = prepararFila({ row_number: 111, [COLUMNAS.nombre]: 'PERSONA DE PRUEBA' })
  assert.equal(parcial.mapeo_correcto, false)
  assert.ok(parcial.errores.includes('Faltan ambos teléfonos'))
})

test('mover una fila no cambia su huella; corregir datos sí permite un nuevo intento', () => {
  const primera = prepararFila(registro())
  const movida = prepararFila(registro({ row_number: 25 }))
  const corregida = prepararFila(registro({ [COLUMNAS.capital]: 'de_20,000_a_50,000' }))
  assert.equal(primera.huella_material, movida.huella_material)
  assert.notEqual(primera.huella_material, corregida.huella_material)
  assert.equal(primera.payload.filas[0].nota, movida.payload.filas[0].nota)
})

test('solo una respuesta completa, definitiva y de la misma fila produce un recibo', () => {
  const original = prepararFila(registro())
  original.huella = createHash('sha256').update(original.huella_material).digest('hex')
  for (const resultado of ['importado', 'duplicado', 'ya_cliente', 'rechazado']) {
    const recibo = conciliarRespuesta({ resultados: [{ fila: 2, resultado, estado: resultado.toUpperCase() }] }, original)
    assert.equal(recibo.resultado, resultado)
    assert.equal(recibo.huella, original.huella)
  }
  for (const respuesta of [
    {},
    { resultados: [] },
    { resultados: [{ fila: 3, resultado: 'importado', estado: 'IMPORTADO' }] },
    { resultados: [{ fila: 2, resultado: 'error_temporal', estado: 'ERROR temporal' }] },
    { resultados: [{ fila: 2, resultado: 'desconocido', estado: 'X' }] },
    { resultados: [{ fila: 2, resultado: 'importado', estado: '' }] },
  ]) assert.throws(() => conciliarRespuesta(respuesta, original))
})

test('la etiqueta permanece al limitar la nota; tipos inesperados no se convierten en datos comerciales', () => {
  const fila = prepararFila(registro({ [COLUMNAS.asesor]: 'a'.repeat(5000) }))
  assert.equal(fila.payload.filas[0].nota.length, 2000)
  assert.match(fila.payload.filas[0].nota, /^Campaña: Formulario 3/)
  assert.equal(fila.avisos.length, 1)
  assert.throws(() => prepararFila(registro({ [COLUMNAS.nombre]: { nombre: 'X' } })))
  assert.throws(() => prepararFila(registro({ row_number: undefined })))
})

test('un encabezado opcional renombrado detiene la lectura antes de reenviar el histórico', () => {
  const fila = registro()
  delete fila[COLUMNAS.asesor]
  fila['Consulta asesor'] = 'requisitos'
  assert.throws(() => validarColumnas([fila]), /Cambió la estructura/)
  assert.doesNotThrow(() => validarColumnas([{ row_number: 2 }, registro({ row_number: 3 })]))
  assert.doesNotThrow(() => validarColumnas([]))
})

test('el recorte de nota no deja un surrogate suelto y advierte sobre divisas contradictorias', () => {
  const fila = prepararFila(registro({ [COLUMNAS.capital]: 'US$ 50,000', [COLUMNAS.asesor]: '😀'.repeat(2000) }))
  assert.equal(fila.payload.filas[0].nota.isWellFormed(), true)
  assert.ok(fila.payload.filas[0].nota.length <= 2000)
  assert.match(fila.payload.filas[0].nota, /símbolo del capital indica USD/)
  assert.ok(fila.avisos.some((aviso) => /no coinciden/.test(aviso)))
})

test('una fila pendiente no se presenta como importada y deja la ejecución en error después del resumen', () => {
  const original = prepararFila(registro())
  original.huella = createHash('sha256').update(original.huella_material).digest('hex')
  const pendiente = pendienteDeFila(original)
  assert.equal(pendiente.resultado, 'pendiente')
  assert.throws(() => resumirImportacion([pendiente, { fila: 3, resultado: 'importado' }], false), /pendientes.*2.*importado/)
  assert.throws(() => resumirImportacion([{ fila: 4, resultado: 'aplazado' }], false), /Sin avance/)
  assert.equal(resumirImportacion([{ fila: 4, resultado: 'aplazado' }, { fila: 5, resultado: 'importado' }], false).resultados.aplazado, 1)
  assert.throws(() => pendienteDeFila({ fila: 2, huella: '' }))
})

test('cada pendiente llega al primer puesto en un ciclo completo, aunque los anteriores fallen', () => {
  for (const n of [1, 2, 5, 25, 30, 127]) {
    const items = Array.from({ length: n }, (_, i) => ({ fila: i }))
    const primeros = new Set()
    for (let turno = 0; turno < n; turno++) {
      const lote = seleccionarLote(items, (1000 + turno) * 300000)
      assert.equal(lote.length, Math.min(25, n))
      primeros.add(lote[0].fila)
      assert.equal(new Set(lote).size, lote.length)
    }
    assert.equal(primeros.size, n)
    assert.equal(items[0].fila, 0)
    assert.ok(primeros.has(n - 1), 'Las primeras filas lentas no bloquean la última')
  }
})

test('el lote vacío no inventa una fila y los parámetros inválidos fallan', () => {
  assert.deepEqual(seleccionarLote([], 0), [])
  assert.throws(() => seleccionarLote([{}], NaN))
  assert.throws(() => seleccionarLote([{}], 0, 0))
})
