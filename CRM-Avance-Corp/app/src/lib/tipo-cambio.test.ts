// Tests de las funciones puras de tipo de cambio (el hook useTipoCambio se cubre
// en el flujo de la pantalla). promedioSemanal + usdAPen.
import { describe, expect, it } from 'vitest'
import { promedioSemanal, usdAPen } from './tipo-cambio'

describe('promedioSemanal', () => {
  it('promedia una serie de cotizaciones', () => {
    expect(promedioSemanal([3.7, 3.8])).toBeCloseTo(3.75, 5)
  })

  it('ignora ceros, negativos y NaN', () => {
    expect(promedioSemanal([3.75, 0, -1, Number.NaN, 3.85])).toBeCloseTo(3.8, 5)
  })

  it('serie vacía o toda inválida → 0 (sin dividir por cero)', () => {
    expect(promedioSemanal([])).toBe(0)
    expect(promedioSemanal([0, -2, Number.NaN])).toBe(0)
  })
})

describe('usdAPen', () => {
  it('convierte USD a PEN al tipo de cambio dado', () => {
    expect(usdAPen(100, 3.75)).toBe(375)
  })

  it('sin tipo de cambio (0 o negativo) devuelve 0 — no inventa soles', () => {
    expect(usdAPen(100, 0)).toBe(0)
    expect(usdAPen(100, -1)).toBe(0)
  })

  it('monto 0 → 0', () => {
    expect(usdAPen(0, 3.75)).toBe(0)
  })
})
