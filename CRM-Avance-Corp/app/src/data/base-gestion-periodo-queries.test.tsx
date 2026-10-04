// Las lecturas de la vista del supervisor (F4) son de un DÍA de Lima (Codex F4 r1): la base del equipo, el panel
// (intentos de hoy, reactivaciones del mes) y el detalle de una cifra. Al cruzar la medianoche —o el mes, para las
// reactivaciones— con la pestaña abierta y SIN cambiar el foco, se vuelven a pedir, y mientras llega la nueva no se
// presenta la foto anterior como vigente. El interruptor «Ver no contactar» sí conserva la lista del MISMO día.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

const llamadas = vi.hoisted(() => ({ base: [] as unknown[], resumen: 0, detalle: [] as unknown[] }))
vi.mock('./crm-api', async (original) => ({
  ...(await original<typeof import('./crm-api')>()),
  leerBaseGestion: vi.fn(async (_v: unknown, opciones: { incluirVetados?: boolean }) => {
    llamadas.base.push(opciones.incluirVetados)
    return { filas: [], conVetados: true }
  }),
  baseGestionResumen: vi.fn(async () => { llamadas.resumen += 1; return [] }),
  baseGestionResumenDetalle: vi.fn(async (vendedorId: string, cifra: string) => { llamadas.detalle.push([vendedorId, cifra, Date.now()]); return [] }),
}))

const { useBaseGestionEquipo, useBaseGestionResumen, useBaseGestionResumenDetalle } = await import('./crm-queries')

function envoltorio() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
}
/** Pasa un minuto: el reloj vivo (`useAhora`) hace su tic y la pantalla se entera de la hora nueva. */
const pasaUnMinuto = () => act(() => { vi.advanceTimersByTime(60_000) })

beforeEach(() => {
  llamadas.base = []
  llamadas.resumen = 0
  llamadas.detalle = []
  // Solo el reloj de pared y el intervalo del reloj vivo: TanStack sigue con sus temporizadores reales y `vi.waitFor`
  // (temporizadores propios de Vitest) avanza el reloj falso de a pocos milisegundos en cada comprobación.
  vi.useFakeTimers({ toFake: ['Date', 'setInterval', 'clearInterval'] })
  vi.setSystemTime(Date.parse('2026-10-04T04:59:30Z')) // sábado 3, 23:59:30 en Lima
})
afterEach(() => vi.useRealTimers())

describe('medianoche en Lima, sin cambiar el foco', () => {
  it('la base del equipo se vuelve a pedir y la de ayer NO se muestra mientras llega', async () => {
    const { result } = renderHook(() => useBaseGestionEquipo(true, false), { wrapper: envoltorio() })
    await vi.waitFor(() => expect(result.current.data).toBeDefined())
    expect(llamadas.base).toHaveLength(1)
    pasaUnMinuto() // 00:00:30 del domingo 4
    expect(result.current.data).toBeUndefined()
    expect(result.current.isPending).toBe(true)
    await vi.waitFor(() => expect(result.current.data).toBeDefined())
    expect(llamadas.base).toHaveLength(2)
  })

  it('el interruptor «Ver no contactar» conserva la lista del MISMO día mientras llega la otra', async () => {
    const { result, rerender } = renderHook(({ vetados }) => useBaseGestionEquipo(true, vetados), { wrapper: envoltorio(), initialProps: { vetados: false } })
    await vi.waitFor(() => expect(result.current.data).toBeDefined())
    rerender({ vetados: true })
    expect(result.current.isPlaceholderData).toBe(true)
    expect(result.current.data).toBeDefined()
    await vi.waitFor(() => expect(result.current.isPlaceholderData).toBe(false))
    expect(llamadas.base).toEqual([false, true])
  })

  it('el panel por analista se vuelve a pedir', async () => {
    const { result } = renderHook(() => useBaseGestionResumen(true), { wrapper: envoltorio() })
    await vi.waitFor(() => expect(result.current.data).toBeDefined())
    pasaUnMinuto()
    expect(result.current.data).toBeUndefined()
    await vi.waitFor(() => expect(llamadas.resumen).toBe(2))
  })

  it('el detalle de «Intentos de hoy» se vuelve a pedir; el de «Reactivaciones del mes» no (sigue siendo el mismo mes)', async () => {
    const intentos = renderHook(() => useBaseGestionResumenDetalle(true, 'v1', 'intentos_hoy'), { wrapper: envoltorio() })
    const reactivaciones = renderHook(() => useBaseGestionResumenDetalle(true, 'v1', 'reactivaciones_mes'), { wrapper: envoltorio() })
    await vi.waitFor(() => expect(intentos.result.current.data).toBeDefined())
    await vi.waitFor(() => expect(reactivaciones.result.current.data).toBeDefined())
    expect(llamadas.detalle).toHaveLength(2)
    pasaUnMinuto()
    expect(intentos.result.current.data).toBeUndefined()
    expect(reactivaciones.result.current.data).toBeDefined()
    await vi.waitFor(() => expect(llamadas.detalle).toHaveLength(3))
    expect(llamadas.detalle.at(-1)).toEqual(['v1', 'intentos_hoy', expect.any(Number)])
  })
})

describe('cambio de mes en Lima', () => {
  it('«Reactivaciones del mes» se vuelve a pedir al empezar el mes nuevo', async () => {
    vi.setSystemTime(Date.parse('2026-11-01T04:59:30Z')) // sábado 31 de octubre, 23:59:30 en Lima
    const { result } = renderHook(() => useBaseGestionResumenDetalle(true, 'v1', 'reactivaciones_mes'), { wrapper: envoltorio() })
    await vi.waitFor(() => expect(result.current.data).toBeDefined())
    pasaUnMinuto() // 1 de noviembre
    expect(result.current.data).toBeUndefined()
    await vi.waitFor(() => expect(llamadas.detalle).toHaveLength(2))
  })
})
