import { describe, expect, it } from 'vitest'
import { fmtFecha, iniciales, money, moneyK, primerNombre } from './format'

describe('formato monetario', () => {
  it('formatea PEN y USD sin mezclar símbolos', () => {
    expect(money(1_234.5)).toBe('S/ 1,234.5')
    expect(money(1_234.5, 'USD')).toBe('US$ 1,234.5')
    expect(money(-12.25)).toBe('S/ -12.25')
  })

  it('trata valores ausentes y no finitos como cero seguro', () => {
    expect(money(null)).toBe('S/ 0')
    expect(money(undefined, 'USD')).toBe('US$ 0')
    expect(money(Number.NaN)).toBe('S/ 0')
    expect(money(Number.POSITIVE_INFINITY)).toBe('S/ 0')
    expect(moneyK(Number.NEGATIVE_INFINITY, 'USD')).toBe('US$ 0')
  })

  it('abrevia miles conservando signo y una precisión útil', () => {
    expect(moneyK(1_000)).toBe('S/ 1k')
    expect(moneyK(1_250, 'USD')).toBe('US$ 1.3k')
    expect(moneyK(-1_500)).toBe('S/ -1.5k')
    expect(moneyK(999)).toBe('S/ 999')
  })
})

describe('formato de nombres y fechas', () => {
  it('genera iniciales estables y nunca vacías', () => {
    expect(iniciales('  María   López Castro ')).toBe('ML')
    expect(iniciales('ana')).toBe('A')
    expect(iniciales('')).toBe('·')
    expect(iniciales(null)).toBe('·')
  })

  it('normaliza solo el primer nombre para saludos', () => {
    expect(primerNombre('  JOSÉ   PÉREZ ')).toBe('José')
    expect(primerNombre('maría')).toBe('María')
    expect(primerNombre(undefined)).toBe('')
  })

  it('rechaza fechas vacías o inválidas y localiza fechas válidas', () => {
    expect(fmtFecha(null)).toBe('—')
    expect(fmtFecha('fecha-invalida')).toBe('—')
    expect(fmtFecha('2026-07-10T12:00:00.000Z')).toMatch(/10.*jul.*2026/i)
  })
})
