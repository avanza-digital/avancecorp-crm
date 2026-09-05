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

// ─────────────────────────────────────────────────────────────────────────────
// Dos pestañas del MISMO ámbito comparten el almacenamiento pero NO la memoria de
// proceso. La regresión que motiva estas pruebas (Codex, revisión adversaria del
// 05/09/2026): si la pestaña que confirma libera el almacenamiento, la otra, al
// reintentar, no debe nacer con una clave nueva —eso reabre el duplicado del 05/09
// entre pestañas—. Se modelan dos instancias reales del módulo con vi.resetModules.
// ─────────────────────────────────────────────────────────────────────────────
describe('dos pestañas del mismo ámbito (almacenamiento compartido, memoria separada)', () => {
  const CLAVE = 'crm.idempotencia.alta_contrato:cli-tabs'
  beforeEach(() => {
    localStorage.clear()
  })
  afterEach(() => {
    vi.resetModules()
    localStorage.clear()
  })

  it('la pestaña que reintenta conserva SU clave aunque la otra libere el almacenamiento', async () => {
    vi.resetModules()
    const A = await import('./idempotencia')
    vi.resetModules()
    const B = await import('./idempotencia')
    const ambito = 'alta_contrato:cli-tabs'
    const claveA = A.claveIdempotenciaPendiente(ambito) // A acuña K y la guarda en el almacenamiento
    const claveB = B.claveIdempotenciaPendiente(ambito) // B lee K y la respalda en SU memoria de proceso
    expect(claveB).toBe(claveA)
    A.liberarClaveIdempotencia(ambito, claveA) // A confirma su alta y libera el almacenamiento compartido
    expect(localStorage.getItem(CLAVE)).toBeNull()
    // B reintenta (su respuesta se perdió): sin el respaldo en memoria nacería K2 y
    // un cambio de número crearía un segundo contrato. Con el respaldo, sigue siendo K.
    expect(B.claveIdempotenciaPendiente(ambito)).toBe(claveA)
  })
})

// El compare-and-clear evita que la respuesta TARDÍA de un intento borre la clave de
// un intento POSTERIOR ya en curso.
describe('liberar por clave (compare-and-clear)', () => {
  const CLAVE = 'crm.idempotencia.alta_contrato:cli-tardio'
  beforeEach(() => {
    localStorage.clear()
    liberarClaveIdempotencia('alta_contrato:cli-tardio')
  })

  it('la respuesta tardía de un intento no borra la clave de un intento posterior', () => {
    const ambito = 'alta_contrato:cli-tardio'
    const claveVieja = claveIdempotenciaPendiente(ambito) // intento 1 → K
    liberarClaveIdempotencia(ambito, claveVieja) // intento 1 se resuelve y libera
    const claveNueva = claveIdempotenciaPendiente(ambito) // intento 2 → K2, guardada
    expect(claveNueva).not.toBe(claveVieja)
    liberarClaveIdempotencia(ambito, claveVieja) // respuesta TARDÍA del intento 1: la vigente es K2 ≠ K
    expect(localStorage.getItem(CLAVE)).toBe(claveNueva) // no se borró
    expect(claveIdempotenciaPendiente(ambito)).toBe(claveNueva) // K2 sigue vigente
  })

  it('liberar SIN clave sigue limpiando de forma incondicional (comportamiento anterior)', () => {
    const ambito = 'alta_contrato:cli-tardio'
    const clave = claveIdempotenciaPendiente(ambito)
    expect(localStorage.getItem(CLAVE)).toBe(clave)
    liberarClaveIdempotencia(ambito)
    expect(localStorage.getItem(CLAVE)).toBeNull()
  })
})
