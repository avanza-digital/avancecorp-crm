import { describe, expect, it } from 'vitest'
import { rotuloTipoCambio, tcAplicable, totalEnSoles } from './capital-unificado'

describe('tcAplicable — un TC inválido no llega a multiplicar dinero', () => {
  it('acepta un TC real', () => {
    expect(tcAplicable(3.3947)).toBe(3.3947)
  })

  it.each([
    ['null', null],
    ['undefined', undefined],
    ['cero', 0],
    ['negativo', -3.39],
    ['NaN', Number.NaN],
    ['Infinity', Number.POSITIVE_INFINITY],
  ])('descarta %s', (_caso, valor) => {
    expect(tcAplicable(valor as number | null | undefined)).toBeNull()
  })
})

describe('totalEnSoles — la única conversión sancionada', () => {
  it('convierte el USD al TC y lo suma al PEN', () => {
    const r = totalEnSoles(100_000, 20_000, 3.3947)

    expect(r.total).toBeCloseTo(167_894, 0)
    expect(r.estado).toBe('convertido')
    expect(r.tc).toBe(3.3947)
  })

  it('SIN TC degrada a solo-PEN: el USD queda fuera, nunca se inventa una tasa', () => {
    const r = totalEnSoles(100_000, 20_000, null)

    expect(r.total).toBe(100_000)
    expect(r.estado).toBe('solo_pen')
    expect(r.tc).toBeNull()
    // El USD sigue disponible para rotularse aparte, no se pierde.
    expect(r.usd).toBe(20_000)
  })

  it('el total NUNCA es la suma cruda de las dos monedas', () => {
    const r = totalEnSoles(100_000, 20_000, 3.3947)

    expect(r.total).not.toBe(120_000)
  })

  it('sin dólares el total es exactamente el PEN', () => {
    expect(totalEnSoles(113_000, 0, 3.3947).total).toBe(113_000)
  })

  it('cartera 100% en dólares: el total NO es cero (el defecto que cierra la decisión #10)', () => {
    const r = totalEnSoles(0, 20_000, 3.3947)

    expect(r.total).toBeCloseTo(67_894, 0)
    expect(r.total).not.toBe(0)
  })

  it.each([
    ['falta el PEN', null, 5_000],
    ['falta el USD', 5_000, null],
    ['faltan ambos', null, null],
  ])('%s ⇒ total null, jamás 0 (un cero se leería como un hecho)', (_caso, pen, usd) => {
    const r = totalEnSoles(pen, usd, 3.3947)

    expect(r.total).toBeNull()
    expect(r.estado).toBe('indisponible')
  })

  it('el TC que devuelve es el APLICADO: un TC inválido sale como null aunque se pasara un número', () => {
    const r = totalEnSoles(100_000, 20_000, -1)

    expect(r.tc).toBeNull()
    expect(r.estado).toBe('solo_pen')
    expect(r.total).toBe(100_000)
  })
})

describe('rotuloTipoCambio', () => {
  it('anuncia la tasa con 4 decimales y su fuente', () => {
    expect(rotuloTipoCambio(3.3947, 'SBS · prom. 6d')).toBe('TC S/ 3.3947 (SBS · prom. 6d)')
  })
})
