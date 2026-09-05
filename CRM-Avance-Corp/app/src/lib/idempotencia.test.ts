import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  RE_CLAVE_IDEMPOTENCIA,
  claveIdempotenciaPendiente,
  liberarClaveIdempotencia,
  nuevaClaveIdempotencia,
} from './idempotencia'

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

describe('la clave pendiente por ámbito (sobrevive al componente, a la recarga y a otra pestaña)', () => {
  beforeEach(() => {
    localStorage.clear()
    liberarClaveIdempotencia('alta_contrato:cli-1')
    liberarClaveIdempotencia('alta_contrato:cli-2')
  })
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('la misma clave mientras el intento no se confirma; otra tras liberarla', () => {
    const a = claveIdempotenciaPendiente('alta_contrato:cli-1')
    expect(a).toMatch(RE_CLAVE_IDEMPOTENCIA)
    expect(claveIdempotenciaPendiente('alta_contrato:cli-1')).toBe(a)
    expect(localStorage.getItem('crm.idempotencia.alta_contrato:cli-1')).toBe(a)
    liberarClaveIdempotencia('alta_contrato:cli-1')
    expect(localStorage.getItem('crm.idempotencia.alta_contrato:cli-1')).toBeNull()
    expect(claveIdempotenciaPendiente('alta_contrato:cli-1')).not.toBe(a)
  })

  it('cada ámbito (cliente) tiene su propia clave', () => {
    expect(claveIdempotenciaPendiente('alta_contrato:cli-1')).not.toBe(claveIdempotenciaPendiente('alta_contrato:cli-2'))
  })

  it('lo que otra pestaña dejó guardado se reutiliza (simulado escribiendo el almacenamiento)', () => {
    localStorage.setItem('crm.idempotencia.alta_contrato:cli-1', 'f6a1c2d4-3b5e-4f70-8a91-b2c3d4e5f607')
    expect(claveIdempotenciaPendiente('alta_contrato:cli-1')).toBe('f6a1c2d4-3b5e-4f70-8a91-b2c3d4e5f607')
  })

  it('un valor corrupto en el almacenamiento se ignora y se sustituye por una clave válida', () => {
    localStorage.setItem('crm.idempotencia.alta_contrato:cli-1', 'basura')
    const clave = claveIdempotenciaPendiente('alta_contrato:cli-1')
    expect(clave).toMatch(RE_CLAVE_IDEMPOTENCIA)
    expect(localStorage.getItem('crm.idempotencia.alta_contrato:cli-1')).toBe(clave)
  })

  it('sin localStorage (bloqueado) sigue protegiendo dentro del proceso', () => {
    vi.stubGlobal('localStorage', {
      getItem: () => { throw new Error('bloqueado') },
      setItem: () => { throw new Error('bloqueado') },
      removeItem: () => { throw new Error('bloqueado') },
    })
    const a = claveIdempotenciaPendiente('alta_contrato:cli-1')
    expect(a).toMatch(RE_CLAVE_IDEMPOTENCIA)
    expect(claveIdempotenciaPendiente('alta_contrato:cli-1')).toBe(a)
    liberarClaveIdempotencia('alta_contrato:cli-1')
    expect(claveIdempotenciaPendiente('alta_contrato:cli-1')).not.toBe(a)
  })
})
