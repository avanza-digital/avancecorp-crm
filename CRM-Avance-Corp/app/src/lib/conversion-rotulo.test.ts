import { describe, expect, it } from 'vitest'
import { esLaCifraOficial, rotuloDeLaCifra } from './conversion-rotulo'

describe('el rótulo de la cifra de conversión', () => {
  it('no rotula un servidor previo: undefined no es «no se sabe»', () => {
    expect(rotuloDeLaCifra({})).toBeNull()
    expect(rotuloDeLaCifra(null)).toBeNull()
    expect(rotuloDeLaCifra(undefined)).toBeNull()
  })

  it('calla cuando la cifra es la oficial de un mes abierto: no hay noticia', () => {
    expect(rotuloDeLaCifra({
      es_mes_calendario: true, fuente: 'mensual', sellado: false, ajuste_aplicado: true,
    })).toBeNull()
  })

  it('avisa cuando el mes está cerrado, porque la cifra ya no se mueve', () => {
    expect(rotuloDeLaCifra({
      es_mes_calendario: true, fuente: 'mensual', sellado: true, ajuste_aplicado: true,
    })).toBe('Cifra oficial del mes cerrado: ya no cambia aunque cambien los datos.')
  })

  it('SIEMPRE avisa de un recálculo en vivo sobre un rango que no es un mes', () => {
    expect(rotuloDeLaCifra({
      es_mes_calendario: false, fuente: 'rango_vivo', sellado: null, ajuste_aplicado: false,
    })).toBe('Calculado sobre el rango elegido; no es la cifra oficial de ningún mes.')
  })

  it('distingue el caso raro: es un mes completo y aun así no se delegó', () => {
    // Pasa cuando falta identidad para preguntarle a la oficial. El usuario
    // tiene que poder ver que la cifra pudo ser la oficial y no lo es.
    expect(rotuloDeLaCifra({
      es_mes_calendario: true, fuente: 'rango_vivo', sellado: null, ajuste_aplicado: false,
    })).toBe('Calculado ahora, no pedido a la cifra oficial del mes.')
  })

  it('con filtro de origen manda el filtro, aunque el bloque venga de la oficial', () => {
    // La regla de Miguel exige «sin filtro de fuente» para delegar: el desglose
    // por origen se calcula en vivo SIEMPRE.
    expect(rotuloDeLaCifra(
      { es_mes_calendario: true, fuente: 'mensual', sellado: true, ajuste_aplicado: true },
      true,
    )).toBe('Calculado sobre el origen elegido; no es la cifra oficial del mes.')
  })

  it('sin declaración no rotula ni con filtro: no se fabrica un aviso', () => {
    expect(rotuloDeLaCifra({}, true)).toBeNull()
  })

  it('esLaCifraOficial solo es cierto cuando se delegó', () => {
    expect(esLaCifraOficial({ fuente: 'mensual' })).toBe(true)
    expect(esLaCifraOficial({ fuente: 'rango_vivo' })).toBe(false)
    expect(esLaCifraOficial({})).toBe(false)
    expect(esLaCifraOficial(null)).toBe(false)
  })
})
