// El diferido de la búsqueda de la cartera (F2). Sin él, cada tecla dispara una
// consulta al servidor; con él mal hecho, la última pulsación se pierde.
import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useValorDiferido } from './use-valor-diferido'

beforeEach(() => { vi.useFakeTimers() })
afterEach(() => { vi.useRealTimers() })

describe('useValorDiferido', () => {
  it('devuelve el valor inicial sin esperar', () => {
    const { result } = renderHook(() => useValorDiferido('rosa'))
    expect(result.current).toBe('rosa')
  })

  it('no adopta el valor nuevo hasta que pasa la pausa', () => {
    const { rerender, result } = renderHook(({ v }: { v: string }) => useValorDiferido(v, 300), {
      initialProps: { v: '' },
    })

    rerender({ v: 'r' })
    expect(result.current).toBe('')

    act(() => { vi.advanceTimersByTime(299) })
    expect(result.current).toBe('')

    act(() => { vi.advanceTimersByTime(1) })
    expect(result.current).toBe('r')
  })

  it('teclear seguido solo deja pasar la ÚLTIMA pulsación', () => {
    const { rerender, result } = renderHook(({ v }: { v: string }) => useValorDiferido(v, 300), {
      initialProps: { v: '' },
    })

    for (const v of ['m', 'ma', 'mar', 'mari', 'maria']) {
      rerender({ v })
      act(() => { vi.advanceTimersByTime(100) })
    }
    // 500 ms de tecleo, pero nunca 300 seguidos sin cambio: aún no viaja nada.
    expect(result.current).toBe('')

    act(() => { vi.advanceTimersByTime(300) })
    expect(result.current).toBe('maria')
  })

  it('volver al valor ya asentado no deja un cambio pendiente', () => {
    const { rerender, result } = renderHook(({ v }: { v: string }) => useValorDiferido(v, 300), {
      initialProps: { v: 'ana' },
    })

    rerender({ v: 'anaa' })
    rerender({ v: 'ana' })
    act(() => { vi.advanceTimersByTime(300) })

    expect(result.current).toBe('ana')
  })
})
