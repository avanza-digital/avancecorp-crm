// El candado de paridad del navegador: no recalcula nada, pero se niega a
// pintar un payload cuyas sumas no cierran (formulario + landing = divisor;
// analistas + sin analista = empresa). Es la parte del cinturón que hace que
// «alguien volvió a calcular el divisor fuera del núcleo» se vea en pantalla
// como un error, no como un número inventado.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ConversionCoordinacionSchema,
  conversionCoordinacionConsistente,
  mesActualLima,
  periodoDesdeMes,
  type ConversionCoordinacion,
} from './conversion-coordinacion'

const ASTRID = '2ec5954f-0490-44f2-87cd-af6210f3426f'
const MERLYS = '75c0933c-9cce-4e5f-ae0e-2b4bfd557a37'

export function payloadValido(): ConversionCoordinacion {
  return {
    version: 1,
    generado_en: '2026-09-30T18:00:00.000Z',
    alcance: 'global',
    periodo: { mes: '2026-09', mes_nombre: 'setiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-10-01' },
    sellado: false,
    peso_referido: 0.5,
    fuente: { divisor: 'private.conversion_neta_por_vendedor', origen: 'private.conversion_episodios', regla: 'una llegada por lead' },
    empresa: { divisor: 205, numerador: 20.15, conversion_pct: 9.83, divisor_formulario: 126, divisor_landing: 79 },
    sin_analista: { divisor: 2, numerador: 0 },
    analistas: [
      { analista_id: ASTRID, nombre: 'ASTRID CENTENARO', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA', en_nucleo: true, divisor: 115, divisor_formulario: 65, divisor_landing: 50, numerador: 11.15, conversion_pct: 9.7 },
      { analista_id: MERLYS, nombre: 'MERLYS GARCIA', supervisor_id: '0eeb8c64-25e4-418b-b5d5-e07b06758b5e', supervisor_nombre: 'SUPERVISORA', en_nucleo: true, divisor: 88, divisor_formulario: 60, divisor_landing: 28, numerador: 9, conversion_pct: 10.23 },
    ],
  }
}

describe('conversionCoordinacionConsistente', () => {
  it('acepta el payload del núcleo (Astrid 65 + 50 = 115; empresa = analistas + sin analista)', () => {
    expect(conversionCoordinacionConsistente(payloadValido(), '2026-09-01')).toBe(true)
  })

  it('rechaza un período distinto del pedido', () => {
    expect(conversionCoordinacionConsistente(payloadValido(), '2026-08-01')).toBe(false)
  })

  it('rechaza a un analista cuyo formulario + landing no suman su divisor (el 62 del reporte de entregas)', () => {
    const datos = payloadValido()
    datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: 62 }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01')).toBe(false)
  })

  it('rechaza una empresa que no suma analistas + sin analista', () => {
    const datos = payloadValido()
    datos.empresa = { ...datos.empresa, divisor: 204, divisor_formulario: 125 }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01')).toBe(false)
  })

  it('rechaza analistas repetidos', () => {
    const datos = payloadValido()
    datos.analistas.push({ ...datos.analistas[1]! })
    expect(conversionCoordinacionConsistente(datos, '2026-09-01')).toBe(false)
  })

  it('en un mes sellado exige el desglose por origen en null (la foto no lo guarda)', () => {
    const sellado = payloadValido()
    sellado.sellado = true
    sellado.empresa = { ...sellado.empresa, divisor_formulario: null, divisor_landing: null }
    sellado.analistas = sellado.analistas.map((a) => ({ ...a, divisor_formulario: null, divisor_landing: null }))
    expect(conversionCoordinacionConsistente(sellado, '2026-09-01')).toBe(true)

    const mezclado = payloadValido()
    mezclado.sellado = true
    expect(conversionCoordinacionConsistente(mezclado, '2026-09-01')).toBe(false)
  })

  it('en un mes abierto no admite el desglose en null', () => {
    const datos = payloadValido()
    datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: null }
    expect(conversionCoordinacionConsistente(datos, '2026-09-01')).toBe(false)
  })

  it('tolera sin_analista nulo y analistas con divisor 0 (sin dividir por cero)', () => {
    const datos = payloadValido()
    datos.sin_analista = null
    datos.empresa = { divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0 }
    datos.analistas = [{ ...datos.analistas[0]!, divisor: 0, divisor_formulario: 0, divisor_landing: 0, numerador: 0, conversion_pct: null }]
    expect(conversionCoordinacionConsistente(datos, '2026-09-01')).toBe(true)
  })
})

describe('ConversionCoordinacionSchema', () => {
  it('acepta numéricos como texto (PostgREST) y rechaza claves de contrato ausentes', () => {
    const crudo = JSON.parse(JSON.stringify(payloadValido())) as Record<string, unknown>
    ;(crudo.analistas as Record<string, unknown>[])[0]!.numerador = '11.15'
    expect(v.safeParse(ConversionCoordinacionSchema, crudo).success).toBe(true)

    const { empresa: _fuera, ...roto } = crudo
    expect(v.safeParse(ConversionCoordinacionSchema, roto).success).toBe(false)
    expect(v.safeParse(ConversionCoordinacionSchema, { ...crudo, version: 2 }).success).toBe(false)
    expect(v.safeParse(ConversionCoordinacionSchema, { ...crudo, alcance: 'equipo' }).success).toBe(false)
  })
})

describe('mesActualLima / periodoDesdeMes', () => {
  it('el mes vigente sale de la hora de Lima, no de UTC (23:30 del 30/09 en Lima sigue siendo setiembre)', () => {
    // 2026-10-01T04:30Z = 2026-09-30 23:30 en Lima.
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
