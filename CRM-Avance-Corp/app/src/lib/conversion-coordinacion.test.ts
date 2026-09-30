// El candado de paridad del navegador: no recalcula nada, pero se niega a
// pintar un payload cuyas sumas no cierran (formulario + landing = divisor;
// analistas + sin analista = empresa; cierres directos + referidos×peso +
// upgrade + renovación×peso = numerador bruto; neto = bruto − ajuste). Es la
// parte del cinturón que hace que «alguien volvió a calcular fuera del núcleo»
// se vea en pantalla como un error, no como un número inventado.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ConversionCoordinacionSchema,
  camposInvalidos,
  conversionCoordinacionConsistente,
  diasInclusivos,
  fechasDeConsulta,
  finDeMes,
  mesActualLima,
  motivoConsultaInvalida,
  periodoDesdeMes,
  sumaDePartes,
  type ConversionCoordinacion,
} from './conversion-coordinacion'

const ASTRID = '2ec5954f-0490-44f2-87cd-af6210f3426f'
const MERLYS = '75c0933c-9cce-4e5f-ae0e-2b4bfd557a37'

/** Setiembre 2026 real: Astrid 5 + 2 + 1 × 0,15 + 4 upgrade = 11,15; Merlys 6 + 1 + 2 upgrade = 9. */
export function payloadValido(): ConversionCoordinacion {
  return {
    version: 1,
    generado_en: '2026-09-30T18:00:00.000Z',
    alcance: 'global',
    periodo: { modo: 'mes', mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-30', dias: 30, cruza_meses_sellados: false },
    sellado: false,
    peso_referido: 0.15,
    peso_renovacion: 0.15,
    fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead', modo: 'mensual' },
    empresa: {
      divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79,
      numerador_bruto: 20.15, ajuste_pendiente: 0, desglose_disponible: true,
      cierres: { formulario: 11, landing: 3, referido: 1, referido_aporte: 0.15, oficina: 1, otros: 0 },
      cartera: { upgrade: 6, renovacion: 0, renovacion_aporte: 0 },
    },
    sin_analista: { divisor: 2, numerador: 0 },
    analistas: [
      {
        analista_id: ASTRID, nombre: 'ASTRID CENTENARO', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA',
        en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7,
        numerador_bruto: 11.15, ajuste_pendiente: 0, desglose_disponible: true,
        cierres: { formulario: 5, landing: 2, referido: 1, referido_aporte: 0.15, oficina: 1, otros: 0 },
        cartera: { upgrade: 4, renovacion: 0, renovacion_aporte: 0 },
      },
      {
        analista_id: MERLYS, nombre: 'MERLYS GARCIA', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA',
        en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23,
        numerador_bruto: 9, ajuste_pendiente: 0, desglose_disponible: true,
        cierres: { formulario: 6, landing: 1, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
        cartera: { upgrade: 2, renovacion: 0, renovacion_aporte: 0 },
      },
    ],
  }
}

/** Foto sellada: mismos totales, sin desglose de llegadas, bruto y ajuste en null. */
export function payloadSellado(conDesglose = true): ConversionCoordinacion {
  const datos = payloadValido()
  const sellar = <T extends { cierres: unknown; cartera: unknown }>(fila: T) => ({
    ...fila,
    divisor_formulario: null,
    divisor_landing: null,
    numerador_bruto: null,
    ajuste_pendiente: null,
    desglose_disponible: conDesglose,
    cierres: conDesglose ? fila.cierres : null,
    cartera: conDesglose ? fila.cartera : null,
  })
  return {
    ...datos,
    sellado: true,
    fuente: { ...datos.fuente, modo: 'foto' },
    empresa: sellar(datos.empresa) as ConversionCoordinacion['empresa'],
    analistas: datos.analistas.map((a) => sellar(a) as ConversionCoordinacion['analistas'][number]),
  }
}

describe('conversionCoordinacionConsistente', () => {
  it('acepta el payload del núcleo (Astrid 65 + 50 = 115 y 5 + 2 + 0,15 + 4 = 11,15; empresa = analistas + sin analista)', () => {
    expect(conversionCoordinacionConsistente(payloadValido(), '2026-09-01', '2026-09-30')).toBe(true)
  })

  it('rechaza un período distinto del pedido', () => {
    expect(conversionCoordinacionConsistente(payloadValido(), '2026-08-01', '2026-08-31')).toBe(false)
  })

  it('rechaza a un analista cuyo formulario + landing no suman su divisor (el 62 del reporte de entregas)', () => {
    const datos = payloadValido()
    datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: 62 }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('rechaza un numerador bruto que no es la suma de sus partes (un upgrade de más)', () => {
    const datos = payloadValido()
    datos.analistas[0] = { ...datos.analistas[0]!, cartera: { upgrade: 5, renovacion: 0, renovacion_aporte: 0 } }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('rechaza un neto que no es el bruto con el ajuste; acepta el ajuste bien aplicado con suelo en cero', () => {
    const datos = payloadValido()
    datos.analistas[1] = { ...datos.analistas[1]!, ajuste_pendiente: 1 } // neto sigue en 9 pero debería ser 8
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)

    const ajustado = payloadValido()
    ajustado.analistas[1] = { ...ajustado.analistas[1]!, ajuste_pendiente: 1, numerador: 8 }
    ajustado.empresa = { ...ajustado.empresa, ajuste_pendiente: 1, numerador: 19.15 }
    expect(conversionCoordinacionConsistente(ajustado, '2026-09-01', '2026-09-30')).toBe(true)

    // El suelo en cero es POR PERSONA: la empresa suma netos (11,15 + 0 = 11,15), no max(bruto − ajuste, 0).
    const conSuelo = payloadValido()
    conSuelo.analistas[1] = { ...conSuelo.analistas[1]!, ajuste_pendiente: 12, numerador: 0 }
    conSuelo.empresa = { ...conSuelo.empresa, ajuste_pendiente: 12, numerador: 11.15 }
    expect(conversionCoordinacionConsistente(conSuelo, '2026-09-01', '2026-09-30')).toBe(true)
    const sueloAlAgregado = payloadValido()
    sueloAlAgregado.analistas[1] = { ...sueloAlAgregado.analistas[1]!, ajuste_pendiente: 12, numerador: 0 }
    sueloAlAgregado.empresa = { ...sueloAlAgregado.empresa, ajuste_pendiente: 12, numerador: 8.15 }
    expect(conversionCoordinacionConsistente(sueloAlAgregado, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('tolera los decimales de los pesos (19 referidos × 0,15 = 2,85) sin falso rojo', () => {
    const datos = payloadValido()
    datos.analistas[0] = {
      ...datos.analistas[0]!,
      cierres: { formulario: 65, landing: 25, referido: 19, referido_aporte: 2.85, oficina: 11, otros: 0 },
      cartera: { upgrade: 24, renovacion: 3, renovacion_aporte: 0.45 },
      numerador_bruto: 117.3, numerador: 117.3,
    }
    datos.empresa = { ...datos.empresa, cierres: { formulario: 71, landing: 26, referido: 19, referido_aporte: 2.85, oficina: 11, otros: 0 }, cartera: { upgrade: 26, renovacion: 3, renovacion_aporte: 0.45 }, numerador_bruto: 126.3, numerador: 126.3 }
    expect(sumaDePartes(datos.analistas[0].cierres!, datos.analistas[0].cartera!)).toBeCloseTo(117.3, 6)
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(true)
  })

  it('rechaza una empresa que no suma analistas + sin analista', () => {
    const datos = payloadValido()
    datos.empresa = { ...datos.empresa, divisor: 204, divisor_formulario: 125 }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('rechaza analistas repetidos', () => {
    const datos = payloadValido()
    datos.analistas.push({ ...datos.analistas[1]! })
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('en un mes sellado exige llegadas por origen, bruto y ajuste en null; el desglose puede venir o no', () => {
    expect(conversionCoordinacionConsistente(payloadSellado(true), '2026-09-01', '2026-09-30')).toBe(true)
    expect(conversionCoordinacionConsistente(payloadSellado(false), '2026-09-01', '2026-09-30')).toBe(true)

    const mezclado = payloadValido()
    mezclado.sellado = true
    expect(conversionCoordinacionConsistente(mezclado, '2026-09-01', '2026-09-30')).toBe(false)

    const sinDesgloseConCifras = payloadSellado(false)
    sinDesgloseConCifras.analistas[0] = { ...sinDesgloseConCifras.analistas[0]!, cierres: payloadValido().analistas[0]!.cierres }
    expect(conversionCoordinacionConsistente(sinDesgloseConCifras, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('en un mes abierto no admite desglose ausente ni llegadas por origen en null', () => {
    const sinLlegadas = payloadValido()
    sinLlegadas.analistas[0] = { ...sinLlegadas.analistas[0]!, divisor_formulario: null }
    expect(conversionCoordinacionConsistente(sinLlegadas, '2026-09-01', '2026-09-30')).toBe(false)

    const sinDesglose = payloadValido()
    sinDesglose.analistas[0] = { ...sinDesglose.analistas[0]!, desglose_disponible: false, cierres: null, cartera: null }
    expect(conversionCoordinacionConsistente(sinDesglose, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('tolera sin_analista nulo y analistas con divisor 0 (sin dividir por cero)', () => {
    const datos = payloadValido()
    datos.sin_analista = null
    datos.empresa = {
      divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0,
      numerador_bruto: 0, ajuste_pendiente: 0, desglose_disponible: true,
      cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
      cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
    }
    datos.analistas = [{
      ...datos.analistas[0]!, divisor: 0, divisor_formulario: 0, divisor_landing: 0, numerador: 0, conversion_pct: null,
      numerador_bruto: 0, cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
      cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
    }]
    expect(conversionCoordinacionConsistente(datos, '2026-09-01', '2026-09-30')).toBe(true)
  })
})

describe('ConversionCoordinacionSchema', () => {
  it('acepta numéricos como texto (PostgREST) y rechaza claves de contrato ausentes', () => {
    const crudo = JSON.parse(JSON.stringify(payloadValido())) as Record<string, unknown>
    const primero = (crudo.analistas as Record<string, unknown>[])[0]!
    primero.numerador = '11.15'
    ;(primero.cierres as Record<string, unknown>).referido_aporte = '0.15'
    expect(v.safeParse(ConversionCoordinacionSchema, crudo).success).toBe(true)

    const { empresa: _fuera, ...roto } = crudo
    expect(v.safeParse(ConversionCoordinacionSchema, roto).success).toBe(false)
    expect(v.safeParse(ConversionCoordinacionSchema, { ...crudo, version: 2 }).success).toBe(false)
    expect(v.safeParse(ConversionCoordinacionSchema, { ...crudo, alcance: 'equipo' }).success).toBe(false)
    const { peso_renovacion: _sinPeso, ...sinPeso } = crudo
    expect(v.safeParse(ConversionCoordinacionSchema, sinPeso).success).toBe(false)
  })
})

describe('mesActualLima / periodoDesdeMes', () => {
  it('el mes vigente sale de la hora de Lima, no de UTC (23:30 del 30/09 en Lima sigue siendo setiembre)', () => {
    expect(mesActualLima(new Date('2026-10-01T04:30:00Z'))).toBe('2026-09')
    expect(mesActualLima(new Date('2026-10-01T05:00:00Z'))).toBe('2026-10')
  })

  it('convierte el mes al primer día y rechaza meses inválidos', () => {
    expect(periodoDesdeMes('2026-09')).toBe('2026-09-01')
    expect(periodoDesdeMes('2026-13')).toBeNull()
    expect(periodoDesdeMes('')).toBeNull()
    expect(periodoDesdeMes('2026-09-15')).toBeNull()
  })
})

/** Rango libre del 1 al 15 de setiembre: mismo mundo, sin nombre de mes, sin ajuste, nunca sellado. */
export function payloadRango(): ConversionCoordinacion {
  const datos = payloadValido()
  return {
    ...datos,
    periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: 15, cruza_meses_sellados: false },
    fuente: { ...datos.fuente, modo: 'rango_vivo' },
  }
}

describe('modo rango (v2)', () => {
  it('acepta un rango cuyo período eco-a desde/hasta y los días inclusivos', () => {
    expect(conversionCoordinacionConsistente(payloadRango(), '2026-09-01', '2026-09-15')).toBe(true)
  })

  it('rechaza un rango que no coincide con lo pedido o con los días mal contados', () => {
    expect(conversionCoordinacionConsistente(payloadRango(), '2026-09-01', '2026-09-16')).toBe(false)
    const dias = payloadRango()
    dias.periodo = { ...dias.periodo, dias: 14 }
    expect(conversionCoordinacionConsistente(dias, '2026-09-01', '2026-09-15')).toBe(false)
  })

  it('un rango libre no puede venir sellado, con nombre de mes ni con ajuste', () => {
    const sellado = payloadRango()
    sellado.sellado = true
    expect(conversionCoordinacionConsistente(sellado, '2026-09-01', '2026-09-15')).toBe(false)
    const conMes = payloadRango()
    conMes.periodo = { ...conMes.periodo, mes: '2026-09' }
    expect(conversionCoordinacionConsistente(conMes, '2026-09-01', '2026-09-15')).toBe(false)
    const conAjuste = payloadRango()
    conAjuste.analistas[1] = { ...conAjuste.analistas[1]!, ajuste_pendiente: 1, numerador: 8 }
    conAjuste.empresa = { ...conAjuste.empresa, ajuste_pendiente: 1, numerador: 19.15 }
    expect(conversionCoordinacionConsistente(conAjuste, '2026-09-01', '2026-09-15')).toBe(false)
  })

  it('un mes exacto exige modo mes con nombre; el modo mes sin nombre se rechaza', () => {
    const sinNombre = payloadValido()
    sinNombre.periodo = { ...sinNombre.periodo, mes_nombre: null }
    expect(conversionCoordinacionConsistente(sinNombre, '2026-09-01', '2026-09-30')).toBe(false)
  })

  it('helpers de fechas: fin de mes, días inclusivos y fechas de la consulta', () => {
    expect(finDeMes('2026-09')).toBe('2026-09-30')
    expect(finDeMes('2026-02')).toBe('2026-02-28')
    expect(finDeMes('2028-02')).toBe('2028-02-29')
    expect(finDeMes('2026-13')).toBeNull()
    expect(diasInclusivos('2026-09-01', '2026-09-01')).toBe(1)
    expect(diasInclusivos('2026-09-01', '2026-09-30')).toBe(30)
    expect(fechasDeConsulta({ modo: 'mes', mes: '2026-09' })).toEqual({ desde: '2026-09-01', hasta: '2026-09-30' })
    expect(fechasDeConsulta({ modo: 'mes', mes: 'x' })).toBeNull()
    expect(fechasDeConsulta({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })).toEqual({ desde: '2026-09-01', hasta: '2026-09-15' })
  })

  it('motivoConsultaInvalida: mes futuro, fechas cruzadas, futuro y más de 366 días', () => {
    const hoy = '2026-09-30'
    expect(motivoConsultaInvalida({ modo: 'mes', mes: '2026-09' }, hoy)).toBeNull()
    expect(motivoConsultaInvalida({ modo: 'mes', mes: '2026-10' }, hoy)).toMatch(/no puede ser futuro/)
    expect(motivoConsultaInvalida({ modo: 'mes', mes: '' }, hoy)).toMatch(/mes válido/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' }, hoy)).toBeNull()
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-16', hasta: '2026-09-15' }, hoy)).toMatch(/inicial no puede ser posterior/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2026-09-01', hasta: '2026-10-01' }, hoy)).toMatch(/fechas futuras/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '2025-09-01', hasta: '2026-09-30' }, hoy)).toMatch(/366 días/)
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '', hasta: '2026-09-15' }, hoy)).toMatch(/dos fechas/)
    // Un año tecleado a medias (0202-…) queda por debajo del mínimo y no dispara consulta.
    expect(motivoConsultaInvalida({ modo: 'rango', desde: '0202-09-01', hasta: '2026-09-15' }, hoy)).toMatch(/empieza como pronto/)
  })

  it('camposInvalidos marca solo el campo que está mal', () => {
    const hoy = '2026-09-30'
    expect(camposInvalidos({ modo: 'rango', desde: '', hasta: '2026-09-15' }, hoy)).toEqual({ desde: true, hasta: false })
    expect(camposInvalidos({ modo: 'rango', desde: '2026-09-01', hasta: '2026-10-01' }, hoy)).toEqual({ desde: false, hasta: true })
    expect(camposInvalidos({ modo: 'rango', desde: '2026-09-16', hasta: '2026-09-15' }, hoy)).toEqual({ desde: true, hasta: true })
    expect(camposInvalidos({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' }, hoy)).toEqual({ desde: false, hasta: false })
    expect(camposInvalidos({ modo: 'mes', mes: '2026-13' }, hoy)).toEqual({ desde: false, hasta: false })
  })

  it('un rango que declara cruzar meses sellados es válido; un mes no puede declararlo; el modo de la fuente debe casar', () => {
    const cruza = payloadRango()
    cruza.periodo = { ...cruza.periodo, cruza_meses_sellados: true }
    expect(conversionCoordinacionConsistente(cruza, '2026-09-01', '2026-09-15')).toBe(true)
    const mesCruza = payloadValido()
    mesCruza.periodo = { ...mesCruza.periodo, cruza_meses_sellados: true }
    expect(conversionCoordinacionConsistente(mesCruza, '2026-09-01', '2026-09-30')).toBe(false)
    const fuenteMal = payloadRango()
    fuenteMal.fuente = { ...fuenteMal.fuente, modo: 'mensual' }
    expect(conversionCoordinacionConsistente(fuenteMal, '2026-09-01', '2026-09-15')).toBe(false)
    const fotoAbierta = payloadValido()
    fotoAbierta.fuente = { ...fotoAbierta.fuente, modo: 'foto' }
    expect(conversionCoordinacionConsistente(fotoAbierta, '2026-09-01', '2026-09-30')).toBe(false)
  })
})
