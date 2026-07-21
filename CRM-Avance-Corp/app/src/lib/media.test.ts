// Tests del hook reactivo de media query. Cubre los 3 caminos: sin matchMedia
// (jsdom por defecto → desktop), coincidencia inmediata, y re-render al cruzar
// el umbral (evento 'change'). Restaura el global tras cada test.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { useEsMovil, useMediaQuery } from './media'

/** MediaQueryList falso y controlable: se puede cambiar `matches` y disparar el
 *  evento 'change' hacia los listeners registrados. */
function mediaQueryFalsa(inicial: boolean) {
  let matches = inicial
  const listeners = new Set<() => void>()
  const mql = {
    get matches() {
      return matches
    },
    media: '',
    onchange: null,
    addEventListener: (_: string, cb: () => void) => listeners.add(cb),
    removeEventListener: (_: string, cb: () => void) => listeners.delete(cb),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }
  const cambiarA = (v: boolean) => {
    matches = v
    for (const cb of listeners) cb()
  }
  return { mql, cambiarA }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useMediaQuery / useEsMovil', () => {
  it('sin matchMedia (jsdom) reporta false → desktop', () => {
    const { result } = renderHook(() => useEsMovil())
    expect(result.current).toBe(false)
  })

  it('reporta true cuando la consulta coincide desde el inicio', () => {
    vi.stubGlobal('matchMedia', () => mediaQueryFalsa(true).mql)
    const { result } = renderHook(() => useMediaQuery('(max-width: 767px)'))
    expect(result.current).toBe(true)
  })

  it('re-renderiza al cruzar el umbral (evento change)', () => {
    const { mql, cambiarA } = mediaQueryFalsa(false)
    vi.stubGlobal('matchMedia', () => mql)
    const { result } = renderHook(() => useEsMovil())
    expect(result.current).toBe(false)
    act(() => cambiarA(true))
    expect(result.current).toBe(true)
  })

  it('libera el listener al desmontar', () => {
    const add = vi.fn()
    const remove = vi.fn()
    vi.stubGlobal('matchMedia', () => ({
      matches: false,
      media: '',
      onchange: null,
      addEventListener: add,
      removeEventListener: remove,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }))
    const { unmount } = renderHook(() => useEsMovil())
    expect(add).toHaveBeenCalledTimes(1)
    unmount()
    expect(remove).toHaveBeenCalledTimes(1)
  })

  it('al cambiar la consulta, desuscribe la anterior y suscribe la nueva', () => {
    // Un MediaQueryList distinto por consulta, cada uno con sus contadores.
    const porConsulta = new Map<string, { add: ReturnType<typeof vi.fn>; remove: ReturnType<typeof vi.fn> }>()
    vi.stubGlobal('matchMedia', (consulta: string) => {
      const espias = porConsulta.get(consulta) ?? { add: vi.fn(), remove: vi.fn() }
      porConsulta.set(consulta, espias)
      return {
        matches: false,
        media: consulta,
        onchange: null,
        addEventListener: espias.add,
        removeEventListener: espias.remove,
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(),
      }
    })
    const { rerender } = renderHook(({ q }) => useMediaQuery(q), { initialProps: { q: '(max-width: 767px)' } })
    rerender({ q: '(min-width: 1024px)' })
    // La consulta vieja quedó desuscrita; la nueva, suscrita.
    expect(porConsulta.get('(max-width: 767px)')?.remove).toHaveBeenCalledTimes(1)
    expect(porConsulta.get('(min-width: 1024px)')?.add).toHaveBeenCalledTimes(1)
  })
})
