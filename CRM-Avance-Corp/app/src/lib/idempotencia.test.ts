import { afterEach, describe, expect, it, vi } from 'vitest'
import { RE_CLAVE_IDEMPOTENCIA, nuevaClaveIdempotencia } from './idempotencia'

describe('nuevaClaveIdempotencia', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('devuelve un uuid canónico distinto en cada llamada', () => {
    const a = nuevaClaveIdempotencia()
    const b = nuevaClaveIdempotencia()
    expect(a).toMatch(RE_CLAVE_IDEMPOTENCIA)
    expect(b).toMatch(RE_CLAVE_IDEMPOTENCIA)
    expect(a).not.toBe(b)
  })

  it('sin randomUUID cae al respaldo con getRandomValues y sigue siendo un uuid v4 canónico', () => {
    const real = globalThis.crypto
    vi.stubGlobal('crypto', { getRandomValues: real.getRandomValues.bind(real) })
    const clave = nuevaClaveIdempotencia()
    expect(clave).toMatch(RE_CLAVE_IDEMPOTENCIA)
    expect(clave[14]).toBe('4')
    expect('89ab').toContain(clave[19])
  })

  it('sin criptografía disponible falla ruidoso en vez de inventar una clave débil', () => {
    vi.stubGlobal('crypto', {})
    expect(() => nuevaClaveIdempotencia()).toThrow(/clave de idempotencia/)
  })
})
