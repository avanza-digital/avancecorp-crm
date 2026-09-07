import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { focusManager, onlineManager, QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useEstadosSlaV2 } from './sla-operacion-queries'
const api = vi.hoisted(() => ({ estado: vi.fn() }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'analista', demo: false } }) }))
vi.mock('./sla-operacion-api', () => ({ obtenerEstadosSlaV2: api.estado }))
let cliente: QueryClient
const datos = { version: 2, modo: 'activo', control_revision: 1, modelo_avisos: 3,
  calculado_en: '2026-09-07T15:00:00Z', proximo_cambio_en: '2026-09-07T15:00:03Z', filas: [] }
function montar() {
  return renderHook(() => useEstadosSlaV2(['lead']), {
    wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>,
  })
}
async function pasar(ms: number) { await act(async () => { await vi.advanceTimersByTimeAsync(ms) }) }
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(new Date('2020-01-01Z'))
  focusManager.setFocused(true); onlineManager.setOnline(true)
  cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  api.estado.mockReset().mockResolvedValue(datos)
})
afterEach(() => { cliente.clear(); focusManager.setFocused(undefined); onlineManager.setOnline(true); vi.useRealTimers() })
describe('actualización del SLA con el QueryClient real', () => {
  it('usa la próxima frontera del servidor y conserva la protección de cancelación', async () => {
    const { result } = montar(); await pasar(1)
    expect(result.current.isSuccess).toBe(true)
    expect(api.estado.mock.calls[0]?.[1]).toBeInstanceOf(AbortSignal)
    await pasar(2_998); expect(api.estado).toHaveBeenCalledTimes(1)
    await pasar(2); expect(api.estado).toHaveBeenCalledTimes(2)
  })
  it('revalida al recuperar foco o conexión después del vencimiento', async () => {
    montar(); await pasar(1)
    act(() => focusManager.setFocused(false))
    await pasar(4_000); expect(api.estado).toHaveBeenCalledTimes(1)
    act(() => focusManager.setFocused(true)); await pasar(1)
    expect(api.estado).toHaveBeenCalledTimes(2)
    act(() => onlineManager.setOnline(false))
    await pasar(4_000); expect(api.estado).toHaveBeenCalledTimes(2)
    act(() => onlineManager.setOnline(true)); await pasar(1)
    expect(api.estado).toHaveBeenCalledTimes(3)
  })
  it('un fallo conserva los datos como no confirmados y evita consultar cada segundo', async () => {
    const { result } = montar(); await pasar(1)
    api.estado.mockRejectedValue(new Error('Sin conexión'))
    await pasar(3_001)
    expect(result.current.isError).toBe(true)
    expect(result.current.data).toEqual(datos)
    expect(api.estado).toHaveBeenCalledTimes(2)
    await pasar(5_000)
    expect(api.estado).toHaveBeenCalledTimes(2)
  })
})
