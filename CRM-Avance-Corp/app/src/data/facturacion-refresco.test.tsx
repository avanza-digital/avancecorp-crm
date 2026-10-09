import { act, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider, focusManager } from '@tanstack/react-query'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import type { ReactNode } from 'react'

const listar = vi.hoisted(() => vi.fn(async (_mes: string) => []))
vi.mock('./crm-api', async (original) => ({ ...(await original<typeof import('./crm-api')>()), listarFacturacionDiaria: listar }))
const { useFacturacionDeMeses } = await import('./crm-queries')
let cliente: QueryClient
beforeEach(() => {
  listar.mockClear()
  vi.useFakeTimers({ toFake: ['Date', 'setInterval', 'clearInterval'] })
  vi.setSystemTime(new Date('2026-10-09T15:00:00Z'))
  focusManager.setFocused(true)
  cliente = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: Infinity } } })
})
afterEach(() => { cliente.clear(); focusManager.setFocused(undefined); vi.useRealTimers() })
function wrapper({ children }: { children: ReactNode }) { return <QueryClientProvider client={cliente}>{children}</QueryClientProvider> }
const pedidos = (mes: string) => listar.mock.calls.filter(([m]) => m === mes).length

it('9: un mes cerrado no se repide a los 5 minutos, sí a los 30 y al volver a la pestaña aunque la caché esté fresca', async () => {
  const { result } = renderHook(() => useFacturacionDeMeses(true, ['2026-09-01', '2026-10-01']), { wrapper })
  await vi.waitFor(() => expect(result.current.every((c) => c.isSuccess)).toBe(true))
  await act(async () => { vi.advanceTimersByTime(5 * 60_000) })
  await vi.waitFor(() => expect(pedidos('2026-10-01')).toBe(2))
  expect(pedidos('2026-09-01')).toBe(1)
  await act(async () => { vi.advanceTimersByTime(25 * 60_000) })
  await vi.waitFor(() => expect(pedidos('2026-09-01')).toBe(2))
  await act(async () => { focusManager.setFocused(false); focusManager.setFocused(true) })
  await vi.waitFor(() => expect(pedidos('2026-09-01')).toBe(3))
})

it('9: al cruzar el mes en Lima, el que acaba de cerrar pasa al intervalo de 30 minutos', async () => {
  vi.setSystemTime(new Date('2026-11-01T04:59:30Z'))
  renderHook(() => useFacturacionDeMeses(true, ['2026-10-01']), { wrapper })
  await vi.waitFor(() => expect(listar).toHaveBeenCalledTimes(1))
  await act(async () => { vi.advanceTimersByTime(60_000) })
  await act(async () => { vi.advanceTimersByTime(5 * 60_000) })
  expect(pedidos('2026-10-01')).toBe(1)
})
