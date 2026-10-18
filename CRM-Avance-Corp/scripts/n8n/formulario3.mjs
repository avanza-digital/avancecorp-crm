export const CAMPAÑA = 'Formulario 3'
export const DOCUMENTO = '1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI'
export const COLUMNAS = {
  fecha: 'Fecha',
  intencion: '¿qué deseas hacer con qorilazo?',
  informacion: '¿qué información te gustaría evaluar antes de realizar un depósito a plazo fijo?',
  moneda: '¿en qué moneda te interesa ahorrar?',
  capital: '¿qué monto aproximado deseas evaluar para tu depósito?',
  asesor: '¿qué te gustaría reforzar con el asesor antes de realizar tu deposito a plazo fijjo?',
  telefono: 'n.º celular',
  nombre: 'nombre completo',
  alternativo: 'número de teléfono',
  ciudad: 'ciudad',
}

export function texto(valor) {
  if (valor == null) return ''
  if (typeof valor === 'string') return valor.trim()
  if (typeof valor === 'number' && Number.isFinite(valor)) return String(valor)
  throw new Error('La celda contiene un tipo de dato inesperado')
}

export function normalizarRespuesta(valor) {
  return texto(valor).normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/_/g, ' ').replace(/[^a-zA-Z0-9,.$/+\-\s]/g, '')
    .replace(/\s+/g, ' ').trim().toLowerCase()
}

export function capitalEstimado(valor) {
  const numero = '(?:\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.\\d{1,2})?'
  const limpio = normalizarRespuesta(valor).replace(/^(?:s\/\.?|us\$|\$)\s*/, '').replace(/(mas)\.$/, '$1')
  const rango = new RegExp('^de\\s+(' + numero + ')\\s+(?:a|hasta)\\s+(' + numero + ')$').exec(limpio)
  const abierto = new RegExp('^(?:(?:mas de|desde|mayor a)\\s+)?(' + numero + ')(?:\\s+(?:a mas|o mas)|\\s*\\+)?$').exec(limpio)
  const match = rango || abierto
  if (!match) throw new Error('Capital no reconocido: conserva el rango para revisar')
  const piso = Number(match[1].replace(/,/g, ''))
  const techo = rango ? Number(rango[2].replace(/,/g, '')) : piso
  if (!Number.isFinite(piso) || piso <= 0 || piso > 9_999_999_999.99 || techo < piso || techo > 9_999_999_999.99) {
    throw new Error('Capital fuera del rango permitido')
  }
  return String(piso)
}

export function monedaDeRespuesta(valor) {
  const limpio = normalizarRespuesta(valor)
  const soles = /\b(?:sol|soles|pen)\b/.test(limpio)
  const dolares = /\b(?:dolar|dolares|usd)\b|us\$/.test(limpio)
  if (!soles && !dolares) throw new Error('Moneda no reconocida: debe indicar soles o dólares')
  return { moneda: soles ? 'PEN' : 'USD', ambigua: soles && dolares }
}

export function validarColumnas(registros) {
  const claves = new Set(registros.flatMap((registro) => Object.keys(registro)))
  if (!Object.values(COLUMNAS).some((columna) => claves.has(columna))) {
    if (registros.every((registro) => Object.entries(registro).every(([clave, valor]) => clave === 'row_number' || valor == null || valor === ''))) return
  }
  const faltantes = Object.values(COLUMNAS).filter((columna) => !claves.has(columna))
  if (faltantes.length) throw new Error('Cambió la estructura de Google Sheets. Faltan columnas: ' + faltantes.join(' | '))
}

export function prepararFila(registro) {
  const fila = Number(registro.row_number)
  if (!Number.isInteger(fila) || fila < 2) throw new Error('La lectura no incluye un número de fila válido')
  const datos = {}
  for (const [clave, columna] of Object.entries(COLUMNAS)) datos[clave] = texto(registro[columna])
  if (Object.values(datos).every((valor) => valor === '')) return null
  const errores = []
  if (!datos.nombre) errores.push('Falta el nombre completo')
  if (datos.nombre.length > 160) errores.push('El nombre supera 160 caracteres')
  if (!datos.telefono && !datos.alternativo) errores.push('Faltan ambos teléfonos')
  let capital = null
  let moneda = null
  let monedaAmbigua = false
  try { capital = capitalEstimado(datos.capital) } catch (error) { errores.push(error.message) }
  try {
    const resultado = monedaDeRespuesta(datos.moneda)
    moneda = resultado.moneda
    monedaAmbigua = resultado.ambigua
  } catch (error) { errores.push(error.message) }
  const partes = [
    'Campaña: ' + CAMPAÑA,
    'Fecha original: ' + datos.fecha,
    'Capital declarado: ' + datos.capital,
    'Moneda declarada: ' + datos.moneda,
    datos.intencion ? 'Intención: ' + datos.intencion : '',
    datos.informacion ? 'Información solicitada: ' + datos.informacion : '',
    datos.asesor ? 'Consulta para el asesor: ' + datos.asesor : '',
    monedaAmbigua ? 'Indicó soles y dólares; se usa PEN según la regla del puente' : '',
  ].filter(Boolean)
  const prefijo = normalizarRespuesta(datos.capital)
  const monedaCapital = /^us\$/.test(prefijo) ? 'USD' : /^s\//.test(prefijo) ? 'PEN' : null
  const conflictoMoneda = monedaCapital && moneda && monedaCapital !== moneda
  if (conflictoMoneda) partes.splice(4, 0, 'Aviso: el símbolo del capital indica ' + monedaCapital + '; se conserva la moneda declarada ' + moneda)
  const notaCompleta = partes.join('\n')
  const nota = notaCompleta.slice(0, 2000).toWellFormed()
  const avisos = []
  if (conflictoMoneda) avisos.push('El símbolo del capital y la moneda declarada no coinciden')
  if (nota.length < notaCompleta.length) avisos.push('La nota se limita a 2000 caracteres; el original permanece en Google Sheets')
  const importacion = {
    fila,
    nombre: datos.nombre,
    telefono: datos.telefono,
    telefono_alternativo: datos.alternativo,
    capital,
    moneda,
    canal: 'FORMULARIO',
    campania_origen: CAMPAÑA,
    distrito: datos.ciudad,
    interes: 'Nuevo',
    nota,
    autorizo: 'SI',
    fuente_consentimiento: 'Formulario 3 de Facebook',
  }
  return {
    fila,
    campania: CAMPAÑA,
    mapeo_correcto: errores.length === 0,
    errores,
    avisos,
    huella_material: JSON.stringify({ documento: DOCUMENTO, pestana: 'gid=0', datos }),
    payload: { filas: [importacion] },
  }
}

export function resumirPreparacion(filas) {
  const monedas = {}
  for (const fila of filas) {
    const moneda = fila.payload.filas[0].moneda
    if (moneda) monedas[moneda] = (monedas[moneda] || 0) + 1
  }
  return {
    campania: CAMPAÑA,
    modo: 'Vista previa: no se envían datos al CRM',
    total_filas: filas.length,
    preparadas: filas.filter((fila) => fila.mapeo_correcto).length,
    para_revisar: filas.filter((fila) => !fila.mapeo_correcto).map((fila) => ({ fila: fila.fila, motivos: fila.errores })),
    monedas,
    envios_crm: 0,
  }
}

export function reciboDeRechazo(fila) {
  return {
    huella: fila.huella,
    campania: CAMPAÑA,
    fila: fila.fila,
    resultado: 'rechazado',
    estado: 'RECHAZADO: ' + fila.errores.join('; '),
  }
}

export function conciliarRespuesta(respuesta, original) {
  if (!respuesta || !Array.isArray(respuesta.resultados) || respuesta.resultados.length !== 1) {
    throw new Error('Respuesta del CRM incompleta: la fila sigue pendiente')
  }
  const resultado = respuesta.resultados[0]
  if (resultado.fila !== original.fila) throw new Error('El CRM respondió para otra fila: no se confirma la importación')
  if (resultado.resultado === 'error_temporal') throw new Error('Error temporal del CRM: la fila sigue pendiente para reintentar')
  if (!['importado', 'duplicado', 'ya_cliente', 'rechazado'].includes(resultado.resultado) || typeof resultado.estado !== 'string' || !resultado.estado.trim()) {
    throw new Error('Resultado del CRM no reconocido: la fila sigue pendiente')
  }
  if (typeof original.huella !== 'string' || !/^[0-9a-f]{64}$/.test(original.huella)) throw new Error('Falta la huella SHA-256 de la fila')
  return {
    huella: original.huella,
    campania: CAMPAÑA,
    fila: original.fila,
    resultado: resultado.resultado,
    estado: resultado.estado,
  }
}

export function pendienteDeFila(original) {
  if (!original || !Number.isInteger(original.fila) || !/^[0-9a-f]{64}$/.test(original.huella)) throw new Error('Falta la identidad de la fila pendiente')
  return { huella: original.huella, campania: CAMPAÑA, fila: original.fila, resultado: 'pendiente', estado: 'PENDIENTE: el CRM no confirmó un resultado definitivo' }
}

export function resumirImportacion(filas, simulacion) {
  const resultados = {}
  for (const fila of filas) {
    if (!['importado', 'duplicado', 'ya_cliente', 'rechazado', 'pendiente', 'aplazado'].includes(fila.resultado)) throw new Error('Falta el recibo de una fila')
    resultados[fila.resultado] = (resultados[fila.resultado] || 0) + 1
  }
  const pendientes = filas.filter((fila) => fila.resultado === 'pendiente').map((fila) => fila.fila)
  if (pendientes.length) throw new Error('Filas pendientes para reintentar: ' + pendientes.join(', ') + '. Resultados: ' + JSON.stringify(resultados))
  const definitivos = filas.filter((fila) => ['importado', 'duplicado', 'ya_cliente', 'rechazado'].includes(fila.resultado)).length
  if (resultados.aplazado && definitivos === 0) throw new Error('Sin avance: todas las filas se aplazaron por falta de tiempo')
  return { campania: CAMPAÑA, filas_procesadas: filas.length, resultados, simulacion }
}

// Rota un puesto por intervalo del cron. Incluso dos filas lentas no pueden
// quedarse permanentemente al principio. No muta los items ni conserva estado.
export function seleccionarLote(items, inicioMs, max = 25) {
  if (!Array.isArray(items)) throw new Error('El lote debe ser una lista')
  if (!items.length) return []
  if (!Number.isFinite(inicioMs) || inicioMs < 0 || !Number.isInteger(max) || max < 1) throw new Error('Configuración de lote inválida')
  const offset = Math.floor(inicioMs / 300000) % items.length
  return [...items.slice(offset), ...items.slice(0, offset)].slice(0, max)
}
