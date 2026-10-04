// Lógica pura de «Bases cargadas» (F5): reconocer columnas, validar cada fila COMO EL SERVIDOR (B8,
// bases_carga_cargar_lote_core: el primer motivo gana), partir en lotes, el informe sin datos ajenos y el reparto.
import { describe, expect, it } from 'vitest'
import {
  MAPEO_VACIO,
  MAX_FILAS_BASE,
  MAX_REPARTO_CONTACTOS,
  analistasDelReparto,
  errorTopeBloque,
  etiquetaMotivoReparto,
  resumenOmitidos,
  cantidadDesdeTexto,
  contarVeredictos,
  detectarColumnas,
  enGestionHasta,
  errorNombreBase,
  esCelularPeruano,
  estadoContador,
  etiquetaAvance,
  etiquetaMotivoExcluido,
  etiquetaMotivoFila,
  etiquetaVeredictoFila,
  excluidosPorMotivo,
  filaEnvio,
  informeCsv,
  nombreDesdeArchivo,
  normalizarCapital,
  normalizarMoneda,
  normalizarTelefonoBase,
  partirEnLotes,
  prepararFilas,
  repartirEnPartesIguales,
  repartoEnBloque,
  repartoIndividual,
  resultadosLocales,
  supervisoresActivos,
  textoCelda,
  totalAsignado,
  type Celda,
  type TablaArchivo,
} from './bases-cargadas'
import type { Miembro } from './tipos'

const tabla = (encabezados: string[], filas: Celda[][]): TablaArchivo => ({ encabezados, filas: filas.map((celdas, i) => ({ numero: i + 2, celdas })) })

describe('reconocer las columnas por su encabezado', () => {
  it('sin tildes ni mayúsculas, exacto primero y después por prefijo; una columna alimenta un solo campo', () => {
    expect(detectarColumnas(['Nombres y Apellidos', 'Celular', 'N° DNI', 'Distrito', 'Observaciones', 'Monto (S/)', 'Moneda'])).toEqual({
      nombre: 0, apellidos: null, telefono: 1, dni: null, distrito: 3, comentario: 4, capital: 5, moneda: 6,
    })
    expect(detectarColumnas(['DNI del cliente', 'Teléfono 1', 'Teléfono 2', 'NOMBRES', 'APELLIDOS'])).toMatchObject({ dni: 0, telefono: 1, nombre: 3, apellidos: 4 })
    expect(detectarColumnas(['', 'x', 'y'])).toEqual(MAPEO_VACIO)
  })
})

describe('teléfono, capital y moneda como el servidor', () => {
  it('teléfono: espejo de private.normalizar_telefono + ^\\+519\\d{8}$', () => {
    expect(normalizarTelefonoBase('987 654 321')).toBe('+51987654321')
    expect(normalizarTelefonoBase('+51 987-654-321')).toBe('+51987654321')
    expect(normalizarTelefonoBase('51987654321')).toBe('+51987654321')
    expect(normalizarTelefonoBase('0051987654321')).toBe('+0051987654321')
    expect(normalizarTelefonoBase('abc')).toBeNull()
    expect(esCelularPeruano('+51987654321')).toBe(true)
    expect(esCelularPeruano('+5114457890')).toBe(false) // un fijo no es celular
    expect(esCelularPeruano(normalizarTelefonoBase('0051987654321'))).toBe(false)
    expect(esCelularPeruano(null)).toBe(false)
  })

  it('capital: miles y decimales como los escribe la gente; > 0 y hasta 2 decimales (el formato que acepta el servidor)', () => {
    expect(normalizarCapital('S/ 30,000')).toBe('30000')
    expect(normalizarCapital('30 000.50')).toBe('30000.50')
    expect(normalizarCapital('1.500,75')).toBe('1500.75')
    expect(normalizarCapital('1,500,000')).toBe('1500000')
    expect(normalizarCapital('1.500')).toBe('1500')
    expect(normalizarCapital('30000.5')).toBe('30000.5')
    expect(normalizarCapital('US$ 0012')).toBe('12')
    expect(normalizarCapital('0')).toBeNull()
    expect(normalizarCapital('-500')).toBeNull()
    expect(normalizarCapital('mucho')).toBeNull()
    expect(normalizarCapital('12345678901')).toBeNull() // más de 10 dígitos enteros
  })

  it('moneda: soles o dólares en sus formas; vacío = PEN en el servidor; otra cosa, inválida', () => {
    expect(normalizarMoneda('S/.')).toBe('PEN')
    expect(normalizarMoneda('Soles')).toBe('PEN')
    expect(normalizarMoneda('US$')).toBe('USD')
    expect(normalizarMoneda('dólares')).toBe('USD')
    expect(normalizarMoneda('')).toBeNull()
    expect(normalizarMoneda('EUR')).toBe('invalida')
  })

  it('las celdas de Excel: números sin «.0» ni notación científica; el DNI numérico recupera sus ceros', () => {
    expect(textoCelda(987654321, 'telefono')).toBe('987654321')
    expect(textoCelda(4587123, 'dni')).toBe('04587123')
    expect(textoCelda(4587123, 'capital')).toBe('4587123')
    expect(textoCelda(30000.5, 'capital')).toBe('30000.5')
    expect(textoCelda(null, 'nombre')).toBe('')
    expect(textoCelda('  ROSA  ', 'nombre')).toBe('ROSA')
    expect(textoCelda(true, 'comentario')).toBe('VERDADERO')
    expect(textoCelda(new Date('2026-01-15T00:00:00Z'), 'comentario')).toBe('2026-01-15')
  })
})

describe('preparar el archivo (vista previa)', () => {
  const mapeo = detectarColumnas(['Nombre', 'Teléfono', 'DNI', 'Distrito', 'Comentario', 'Capital', 'Moneda'])

  it('el primer motivo gana, en el orden del servidor; las filas vacías no cuentan', () => {
    const p = prepararFilas(tabla(['Nombre', 'Teléfono', 'DNI', 'Distrito', 'Comentario', 'Capital', 'Moneda'], [
      ['ROSA QUISPE', '987654321', '45871236', 'Surco', 'Feria', '30,000', 'S/'],
      ['', '987654322', '', '', '', '', ''],
      ['X'.repeat(201), '987654323', '', '', '', '', ''],
      ['LUIS', '12345', '1234', '', '', '', ''],
      ['ANA', '987654324', '1234', '', '', '-5', ''],
      ['BETO', '987654325', '', '', '', '-5', ''],
      ['CARLA', '987654326', '', '', '', '100', 'EUR'],
      ['DIEGO', '987654327', '', 'D'.repeat(121), '', '', ''],
      ['ELSA', '987654328', '', '', 'C'.repeat(1001), '', ''],
      [null, null, null, null, null, null, null],
    ]), mapeo)
    expect(p.filas.map((f) => [f.fila, f.error])).toEqual([
      [2, null], [3, 'nombre_vacio'], [4, 'nombre_largo'], [5, 'telefono_invalido'], [6, 'dni_invalido'],
      [7, 'capital_invalido'], [8, 'moneda_invalida'], [9, 'distrito_largo'], [10, 'comentario_largo'],
    ])
    expect(p.invalidas).toBe(8)
    expect(p.validas).toHaveLength(1)
    expect(filaEnvio(p.validas[0]!)).toEqual({ fila: 2, nombre: 'ROSA QUISPE', telefono: '+51987654321', dni: '45871236', distrito: 'Surco', comentario: 'Feria', capital: '30000', moneda: 'PEN' })
  })

  it('repetidas en el archivo (mismo celular o mismo DNI): la primera aparición gana; las inválidas no ocupan el lugar', () => {
    const p = prepararFilas(tabla(['Nombre', 'Teléfono', 'DNI'], [
      ['ROSA', '987654321', '45871236'],
      ['ROSA BIS', '+51 987 654 321', ''],
      ['OTRA', '987000111', '45.871.236'],
      ['MALA', '987', '11111111'],
      ['BUENA', '987000222', '11111111'],
    ]), detectarColumnas(['Nombre', 'Teléfono', 'DNI']))
    expect(p.filas.map((f) => f.error)).toEqual([null, 'en_archivo', 'en_archivo', 'telefono_invalido', null])
    expect([p.invalidas, p.repetidas, p.validas.length]).toEqual([1, 2, 2])
    expect(resultadosLocales(p)).toEqual([
      { fila: 3, veredicto: 'repetida', motivo: 'en_archivo' },
      { fila: 4, veredicto: 'repetida', motivo: 'en_archivo' },
      { fila: 5, veredicto: 'invalida', motivo: 'telefono_invalido' },
    ])
  })

  it('nombre y apellidos en dos columnas se juntan; sin capital no viaja ni el capital ni la moneda', () => {
    const p = prepararFilas(tabla(['Nombres', 'Apellidos', 'Celular', 'Moneda'], [['ROSA', 'QUISPE  ROJAS', 987654321, 'USD']]), detectarColumnas(['Nombres', 'Apellidos', 'Celular', 'Moneda']))
    expect(filaEnvio(p.validas[0]!)).toEqual({ fila: 2, nombre: 'ROSA QUISPE ROJAS', telefono: '+51987654321' })
  })

  it(`${MAX_FILAS_BASE} filas: se preparan todas y se parten en 50 lotes de 100 (el tope del servidor)`, () => {
    const filas: Celda[][] = Array.from({ length: MAX_FILAS_BASE }, (_, i) => [`CONTACTO ${i}`, `9${String(10_000_000 + i).padStart(8, '0')}`])
    const p = prepararFilas(tabla(['Nombre', 'Celular'], filas), detectarColumnas(['Nombre', 'Celular']))
    expect(p.validas).toHaveLength(MAX_FILAS_BASE)
    const lotes = partirEnLotes(p.validas.map(filaEnvio))
    expect(lotes).toHaveLength(50)
    expect(lotes.every((l) => l.length === 100)).toBe(true)
    expect(lotes[49]?.at(-1)?.fila).toBe(MAX_FILAS_BASE + 1)
    expect(partirEnLotes([1, 2, 3], 2)).toEqual([[1, 2], [3]])
  })
})

describe('nombre de la base', () => {
  it('1 a 80 caracteres; sugerencia desde el archivo', () => {
    expect(errorNombreBase('  ')).toMatch(/Escribe el nombre/)
    expect(errorNombreBase('x'.repeat(81))).toMatch(/hasta 80/)
    expect(errorNombreBase('Feria 2025')).toBeNull()
    expect(nombreDesdeArchivo('Feria_2025.XLSX')).toBe('Feria 2025')
  })
})

describe('el informe', () => {
  const resultados = [
    { fila: 5, veredicto: 'ya_existia', motivo: 'con_dueno' },
    { fila: 2, veredicto: 'cargada', motivo: null },
    { fila: 3, veredicto: 'ya_existia', motivo: null },
    { fila: 4, veredicto: 'no_contactar', motivo: 'no_insistir' },
    { fila: 6, veredicto: 'invalida', motivo: 'telefono_invalido' },
    { fila: 7, veredicto: 'repetida', motivo: 'en_base' },
    { fila: 8, veredicto: 'sin_enviar', motivo: null },
  ]
  it('cuenta por veredicto y redacta cada motivo (sin motivo, sin delatar a otro equipo)', () => {
    expect(contarVeredictos(resultados)).toEqual({ cargada: 1, ya_existia: 2, no_contactar: 1, invalida: 1, repetida: 1 })
    expect(etiquetaMotivoFila('ya_existia', 'con_dueno')).toBe('Ya es lead de un analista')
    expect(etiquetaMotivoFila('ya_existia', null)).toBe('Ya existe en el CRM')
    expect(etiquetaMotivoFila('repetida', 'en_base')).toBe('Ya está en esta base')
    expect(etiquetaMotivoFila('otro', 'motivo_nuevo')).toBe('motivo_nuevo')
    expect(etiquetaVeredictoFila('ya_existia')).toBe('Ya existía')
    expect(etiquetaVeredictoFila('sin_enviar')).toBe('Sin enviar')
    expect(etiquetaVeredictoFila('nuevo_veredicto')).toBe('nuevo_veredicto')
  })

  it('el CSV: fila, resultado y motivo, ordenado por fila, con BOM y sin ids ni nombres de leads ajenos', () => {
    const csv = informeCsv([...resultados, { fila: 9, veredicto: 'ya_existia', motivo: 'cliente', lead_id: 'secreto-1' } as never])
    const lineas = csv.replace('﻿', '').split('\r\n')
    expect(lineas[0]).toBe('"Fila del archivo","Resultado","Motivo"')
    expect(lineas[1]).toBe('"2","Cargada","Entró a la base sin repartir"')
    expect(lineas[4]).toBe('"5","Ya existía","Ya es lead de un analista"')
    expect(lineas.map((l) => l.split(',')[0])).toEqual(['"Fila del archivo"', '"2"', '"3"', '"4"', '"5"', '"6"', '"7"', '"8"', '"9"'])
    expect(csv).not.toContain('secreto-1')
    expect(csv.startsWith('﻿')).toBe(true)
  })
})

describe('armar desde el CRM', () => {
  const AHORA = Date.parse('2026-10-04T15:00:00Z')
  it('seguimiento activo (B6): un intento de los últimos 7 días o una rellamada agendada', () => {
    expect(enGestionHasta({ ultimo_intento_en: '2026-10-01T15:00:00Z', proxima_llamada_en: null }, AHORA)).toBe(Date.parse('2026-10-08T15:00:00Z'))
    expect(enGestionHasta({ ultimo_intento_en: '2026-09-20T15:00:00Z', proxima_llamada_en: null }, AHORA)).toBeNull()
    expect(enGestionHasta({ ultimo_intento_en: null, proxima_llamada_en: '2026-10-06T15:00:00Z' }, AHORA)).toBe(Date.parse('2026-10-06T15:00:00Z'))
    expect(enGestionHasta({ ultimo_intento_en: null, proxima_llamada_en: null }, AHORA)).toBeNull()
  })
  it('excluidos por motivo, del más numeroso al menos; los motivos se leen', () => {
    expect(excluidosPorMotivo({ en_gestion: [1, 4], ocupado: [2], no_contactar: [] })).toEqual([{ motivo: 'en_gestion', n: 2 }, { motivo: 'ocupado', n: 1 }])
    expect(etiquetaMotivoExcluido('ocupado')).toMatch(/reintenta/)
    expect(etiquetaMotivoExcluido('raro')).toBe('raro')
  })
})

describe('repartir por cantidades', () => {
  it('casilla: solo dígitos; el contador «70 de 85 por repartir» y si se pasa', () => {
    expect(cantidadDesdeTexto('4a0')).toBe(40)
    expect(cantidadDesdeTexto('')).toBe(0)
    expect(totalAsignado({ a: 40, b: 30 })).toBe(70)
    expect(estadoContador(70, 85)).toEqual({ texto: '70 de 85 por repartir', excede: false, sobreTope: false, listo: true })
    expect(estadoContador(90, 85)).toMatchObject({ excede: true, listo: false })
    expect(estadoContador(0, 85)).toMatchObject({ listo: false })
    // B9: hasta 500 por operación aunque haya más disponibles.
    expect(estadoContador(501, 5000)).toMatchObject({ excede: false, sobreTope: true, listo: false })
  })

  it('topes de B9 (500 contactos, 100 analistas por operación) y los motivos del reparto en palabras', () => {
    expect(MAX_REPARTO_CONTACTOS).toBe(500)
    expect(errorTopeBloque({ a: 300, b: 201 }, 5000)).toMatch(/hasta 500 contactos por vez \(pides 501\)/)
    expect(errorTopeBloque({ a: 90 }, 85)).toMatch(/Te pasas por 5/)
    expect(errorTopeBloque(Object.fromEntries(Array.from({ length: 101 }, (_, i) => [`a${i}`, 1])), 5000)).toMatch(/100 analistas/)
    expect(errorTopeBloque({ a: 40, b: 30 }, 85)).toBeNull()
    expect(etiquetaMotivoReparto('en_gestion')).toBe('En gestión: tiene seguimiento activo')
    expect(etiquetaMotivoReparto('ya_asignado')).toBe('Ya era de ese analista')
    expect(etiquetaMotivoReparto('motivo_nuevo')).toBe('motivo_nuevo')
    expect(resumenOmitidos([{ motivo: 'ocupado', cantidad: 1 }, { motivo: 'en_gestion', cantidad: 3 }, { motivo: 'ocupado', cantidad: 1 }]))
      .toEqual({ total: 5, detalle: '3 · en gestión: tiene seguimiento activo; 2 · otra operación lo tenía tomado: reintenta en un momento' })
    expect(resumenOmitidos([])).toEqual({ total: 0, detalle: '' })
  })

  it('«En partes iguales»: entre los que tienen cantidad (o todos); el resto de a uno a los primeros', () => {
    expect(repartirEnPartesIguales(['a', 'b', 'c'], 85)).toEqual({ a: 29, b: 28, c: 28 })
    expect(repartirEnPartesIguales(['a', 'b', 'c'], 85, { a: 10, c: 1 })).toEqual({ a: 43, b: 0, c: 42 })
    expect(repartirEnPartesIguales(['a', 'b'], 0)).toEqual({ a: 0, b: 0 })
    expect(repartirEnPartesIguales([], 10)).toEqual({})
  })

  it('lo que viaja: el bloque solo con quienes tienen cantidad; el individual, un par por lead', () => {
    expect(repartoEnBloque(['a', 'b', 'c'], { a: 40, b: 0, c: 30 })).toEqual({ modo: 'bloque', asignaciones: [{ analista_id: 'a', cantidad: 40 }, { analista_id: 'c', cantidad: 30 }] })
    expect(repartoIndividual(['l1', 'l2'], 'a')).toEqual({ modo: 'individual', asignaciones: [{ lead_id: 'l1', analista_id: 'a' }, { lead_id: 'l2', analista_id: 'a' }] })
  })

  it('a quién: analistas activos; Supervisión los suyos; Gerencia todos con el equipo del dueño primero', () => {
    const m = (perfil_id: string, rol_crm: Miembro['rol_crm'], supervisor_id: string | null, activo = true): Miembro => ({ perfil_id, nombre_completo: perfil_id.toUpperCase(), rol_crm, supervisor_id, activo })
    const equipo = [m('zoe', 'vendedor', 's1'), m('ana', 'vendedor', 's2'), m('beto', 'vendedor', 's1'), m('ido', 'vendedor', 's1', false), m('s1', 'supervisor', null), m('s2', 'supervisor', null)]
    expect(analistasDelReparto(equipo, { id: 's1', rol: 'supervisor' }, 's1').map((x) => x.perfil_id)).toEqual(['beto', 'zoe'])
    expect(analistasDelReparto(equipo, { id: 'g', rol: 'gerencia' }, 's2').map((x) => x.perfil_id)).toEqual(['ana', 'beto', 'zoe'])
    expect(analistasDelReparto(equipo, { id: 'g', rol: 'gerencia' }, 's1').map((x) => x.perfil_id)).toEqual(['beto', 'zoe', 'ana'])
    expect(supervisoresActivos(equipo).map((x) => x.perfil_id)).toEqual(['s1', 's2'])
  })

  it('avance: «45 %» (trabajados ÷ repartidos); sin repartidos, raya', () => {
    expect(etiquetaAvance(0.454)).toBe('45 %')
    expect(etiquetaAvance(null)).toBe('—')
    expect(etiquetaAvance(1.2)).toBe('100 %')
  })
})
