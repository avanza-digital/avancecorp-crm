import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { msRestantes, textoVentana, useVentana, VENTANA_MS, ventanaVigente } from './ventana'

const CREADO = '2026-07-16T10:00:00.000Z'
const T0 = new Date(CREADO).getTime()

beforeEach(() => {
  vi.useFakeTimers()
})
afterEach(() => {
  vi.useRealTimers()
})

describe('msRestantes / ventanaVigente', () => {
  it('cuenta desde creado_en: a la hora 1 quedan 4 horas', () => {
    vi.setSystemTime(T0 + 1 * 60 * 60 * 1000)
    expect(msRestantes(CREADO)).toBe(4 * 60 * 60 * 1000)
    expect(ventanaVigente(CREADO)).toBe(true)
  })

  it('a las 5 h EXACTAS ya está vencida (el servidor manda; sin regalos de borde)', () => {
    vi.setSystemTime(T0 + VENTANA_MS)
    expect(msRestantes(CREADO)).toBe(0)
    expect(ventanaVigente(CREADO)).toBe(false)
  })

  it('una fecha ilegible cuenta como vencida (fail-closed)', () => {
    vi.setSystemTime(T0)
    expect(ventanaVigente('no-es-fecha')).toBe(false)
    expect(textoVentana('no-es-fecha')).toBe('Bloqueado')
  })
})

describe('textoVentana', () => {
  it("formatea 'Quedan H h MM m' con minutos a dos dígitos", () => {
    vi.setSystemTime(T0 + 1 * 60 * 60 * 1000 + 18 * 60 * 1000) // pasó 1 h 18 m
    expect(textoVentana(CREADO)).toBe('Quedan 3 h 42 m')

    vi.setSystemTime(T0 + 4 * 60 * 60 * 1000 + 55 * 60 * 1000) // quedan 5 min
    expect(textoVentana(CREADO)).toBe('Quedan 0 h 05 m')
  })

  it("vencida → 'Bloqueado'", () => {
    vi.setSystemTime(T0 + VENTANA_MS + 1)
    expect(textoVentana(CREADO)).toBe('Bloqueado')
  })
})

describe('useVentana', () => {
  it('re-renderiza cada 15 s y el texto avanza solo', () => {
    vi.setSystemTime(T0 + 4 * 60 * 60 * 1000 + 44 * 60 * 1000 + 50_000) // quedan 15 m 10 s
    const { result } = renderHook(() => useVentana(CREADO))
    expect(result.current.texto).toBe('Quedan 0 h 15 m')
    expect(result.current.vigente).toBe(true)

    act(() => {
      vi.advanceTimersByTime(15_000)
    })
    expect(result.current.texto).toBe('Quedan 0 h 14 m')
  })

  it('cruza a Bloqueado en el tick que vence y deja de refrescar', () => {
    vi.setSystemTime(T0 + VENTANA_MS - 10_000) // quedan 10 s
    const { result } = renderHook(() => useVentana(CREADO))
    expect(result.current.vigente).toBe(true)

    act(() => {
      vi.advanceTimersByTime(15_000)
    })
    expect(result.current.vigente).toBe(false)
    expect(result.current.texto).toBe('Bloqueado')
    // Sin timers pendientes: el intervalo se cortó solo tras vencer.
    expect(vi.getTimerCount()).toBe(0)
  })

  it('sin creado_en (fila aún no cargada) queda Bloqueado y no arma timer', () => {
    vi.setSystemTime(T0)
    const { result } = renderHook(() => useVentana(null))
    expect(result.current).toEqual({ ms: 0, vigente: false, texto: 'Bloqueado' })
    expect(vi.getTimerCount()).toBe(0)
  })
})
