import { describe, expect, it } from 'vitest'
import { parseMonto } from './numero'

describe('parseMonto — montos escritos a mano', () => {
  it('acepta enteros y decimales con punto o coma', () => {
    expect(parseMonto('125000')).toBe(125000)
    expect(parseMonto('125000.50')).toBe(125000.5)
    expect(parseMonto('125000,50')).toBe(125000.5)
    expect(parseMonto('1,5')).toBe(1.5)
    expect(parseMonto(' 100 ')).toBe(100)
  })

  // EL bug que motivó este módulo: la coma de miles convertía 125,000 en 125.
  it('rechaza separadores de miles en vez de convertirlos en decimales', () => {
    expect(parseMonto('125,000')).toBeNull() // 3 decimales = miles, no decimal
    expect(parseMonto('1,000,000')).toBeNull()
    expect(parseMonto('1.000.000')).toBeNull()
    expect(parseMonto('125 000')).toBeNull()
  })

  it('rechaza basura', () => {
    expect(parseMonto('')).toBeNull()
    expect(parseMonto('abc')).toBeNull()
    expect(parseMonto('12a')).toBeNull()
    expect(parseMonto('-100')).toBeNull()
    expect(parseMonto('100.123')).toBeNull() // más de 2 decimales
  })
})
