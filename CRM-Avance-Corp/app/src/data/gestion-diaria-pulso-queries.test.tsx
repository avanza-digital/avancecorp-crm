import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'
import type { Yo } from '@/lib/tipos'
import fixture from '@/lib/gestion-diaria-f5.test.fixture.json'
const d = vi.hoisted(() => ({ pulso: vi.fn(), habitos: vi.fn(), equipo: vi.fn(), yo: null as Yo | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: d.yo }) }))
vi.mock('./gestion-diaria-pulso-api', () => ({ obtenerPulsoGerencia: d.pulso, obtenerHabitosGerencia: d.habitos }))
vi.mock('./gestion-diaria-api', () => ({ obtenerDiaEquipo: d.equipo }))
const { usePulsoGerencia, useHabitosGerencia, useDetallePulso, clavePulso } = await import('./gestion-diaria-pulso-queries')
let cliente: QueryClient
function envolver({ children }: { children: ReactNode }) { return <QueryClientProvider client={cliente}>{children}</QueryClientProvider> }
beforeEach(() => {
  vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  d.yo = { id: 'gerencia-1', rol: 'gerencia', demo: false } as Yo
  d.pulso.mockResolvedValue(fixture.pulso); d.habitos.mockResolvedValue(fixture.habitos); d.equipo.mockResolvedValue(fixture.equipo)
})
afterEach(() => cliente.clear())
describe('F5: caché por identidad y período, cancelación y permisos', () => {
  it('una respuesta tardía del día anterior no sustituye al elegido', async () => {
    let resolver!: (r: unknown) => void
    d.pulso.mockImplementation((dia: string) => dia === '2026-09-22' ? new Promise((r) => { resolver = r }) : Promise.resolve({ ...fixture.pulso, dia }))
    const { result, rerender } = renderHook(({ dia }) => usePulsoGerencia(dia), { wrapper: envolver, initialProps: { dia: '2026-09-22' } })
    rerender({ dia: '2026-09-23' })
    await waitFor(() => expect(result.current.datos?.dia).toBe('2026-09-23'))
    await act(async () => resolver({ ...fixture.pulso, dia: '2026-09-22' }))
    expect(result.current.datos?.dia).toBe('2026-09-23')
    expect(d.pulso.mock.calls[0]![1]).toBeInstanceOf(AbortSignal)
  })
  it('oculta la foto tras un fallo de refresco aunque siga en caché', async () => {
    const { result } = renderHook(() => usePulsoGerencia('2026-09-23'), { wrapper: envolver })
    await waitFor(() => expect(result.current.datos).not.toBeNull())
    d.pulso.mockRejectedValue(new Error('revocada'))
    await act(async () => { await result.current.recargar() })
    await waitFor(() => expect(result.current.error).not.toBeNull())
    expect(result.current.datos).toBeNull()
    expect(cliente.getQueryData(clavePulso('gerencia-1', 'gerencia', 'pulso', '2026-09-23'))).toBeTruthy()
  })
  it('al cambiar actor o rol no muestra el ámbito anterior', async () => {
    const { result, rerender } = renderHook(() => usePulsoGerencia('2026-09-23'), { wrapper: envolver })
    await waitFor(() => expect(result.current.datos).not.toBeNull())
    d.pulso.mockImplementation(() => new Promise(() => {})); d.yo = { ...d.yo!, id: 'gerencia-2' }
    rerender(); expect(result.current.datos).toBeNull()
    d.yo = { ...d.yo!, rol: 'supervisor' }; rerender()
    expect(result.current.datos).toBeNull()
    const n = d.pulso.mock.calls.length
    await act(async () => { await result.current.recargar() })
    expect(d.pulso).toHaveBeenCalledTimes(n)
  })
  it.each(['demo', 'sin sesion'] as const)('%s no pide las RPC productivas ni al actualizar', async (caso) => {
    d.yo = caso === 'demo' ? { ...d.yo!, demo: true } : null
    const { result } = renderHook(() => ({ p: usePulsoGerencia('2026-09-23'), h: useHabitosGerencia('2026-09-23', 7, true), e: useDetallePulso('2026-09-23', true) }), { wrapper: envolver })
    await act(async () => { await result.current.p.recargar(); await result.current.h.recargar(); await result.current.e.recargar() })
    expect(d.pulso).not.toHaveBeenCalled(); expect(d.habitos).not.toHaveBeenCalled(); expect(d.equipo).not.toHaveBeenCalled()
  })
  it('carga hábitos y detalle sólo al abrirlos; una ventana nueva no conserva la anterior', async () => {
    const { result, rerender } = renderHook(({ abierta, dias }: { abierta: boolean; dias: 7 | 14 }) => ({ h: useHabitosGerencia('2026-09-23', dias, abierta), e: useDetallePulso('2026-09-23', abierta) }), { wrapper: envolver, initialProps: { abierta: false, dias: 7 } })
    expect(d.habitos).not.toHaveBeenCalled(); expect(d.equipo).not.toHaveBeenCalled()
    rerender({ abierta: true, dias: 7 })
    await waitFor(() => expect(result.current.h.datos).not.toBeNull())
    expect(d.equipo).toHaveBeenCalledWith('2026-09-23', null, expect.any(AbortSignal))
    d.habitos.mockImplementation(() => new Promise(() => {})); rerender({ abierta: true, dias: 14 })
    expect(result.current.h.datos).toBeNull()
  })
})
