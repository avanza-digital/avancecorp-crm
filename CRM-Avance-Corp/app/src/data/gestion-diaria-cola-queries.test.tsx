import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import type { PedidoColaTrabajo, ColaTrabajo } from '@/lib/gestion-diaria-cola'
import muestra from './gestion-diaria-cola-sql.fixture.json'
const dobles = vi.hoisted(() => ({ yo: { id: 'a1', rol: 'vendedor', demo: false }, obtener: vi.fn() }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('./gestion-diaria-cola-api', () => ({ obtenerColaTrabajo: dobles.obtener }))
import { useColaTrabajo } from './gestion-diaria-cola-queries'
const p: PedidoColaTrabajo = { filtro: 'todo', pagina: 0, limite: 8, elegido: null }
function wrapper() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>
}
beforeEach(() => { dobles.obtener.mockReset(); dobles.yo = { id: 'a1', rol: 'vendedor', demo: false } })
describe('foto de la cola por ámbito y navegación', () => {
  it('cancela un filtro obsoleto y su respuesta tardía no pisa el nuevo', async () => {
    let resolver!: (data: ColaTrabajo) => void
    let senal: AbortSignal | undefined
    dobles.obtener.mockImplementationOnce((_p, _actor, _dia, signal) => {
      senal = signal; return new Promise<ColaTrabajo>((r) => { resolver = r })
    }).mockResolvedValue({ ...muestra, filtro: 'tarea_vencida' })
    const { result, rerender } = renderHook(({ pedido }) => useColaTrabajo(pedido, '2026-09-30'), {
      wrapper: wrapper(), initialProps: { pedido: p },
    })
    await waitFor(() => expect(dobles.obtener).toHaveBeenCalledTimes(1))
    rerender({ pedido: { ...p, filtro: 'tarea_vencida' } })
    await waitFor(() => expect(result.current.data?.filtro).toBe('tarea_vencida'))
    expect(senal?.aborted).toBe(true)
    await act(async () => { resolver(muestra as ColaTrabajo) })
    expect(result.current.data?.filtro).toBe('tarea_vencida')
  })
  it('un refetch fallido retira la foto y otro actor o día no reutiliza la anterior', async () => {
    dobles.obtener.mockResolvedValue(muestra)
    const { result, rerender } = renderHook(({ dia }) => useColaTrabajo(p, dia), {
      wrapper: wrapper(), initialProps: { dia: '2026-09-30' },
    })
    await waitFor(() => expect(result.current.data).toBeDefined())
    dobles.obtener.mockRejectedValue(new Error('corte'))
    await act(async () => { await result.current.refetch() })
    await waitFor(() => expect(result.current.data).toBeUndefined())
    dobles.yo = { ...dobles.yo, id: 'otro' }
    rerender({ dia: '2026-10-01' })
    expect(result.current.data).toBeUndefined()
    await waitFor(() => expect(dobles.obtener).toHaveBeenLastCalledWith(p, 'otro', '2026-10-01', expect.any(AbortSignal)))
  })
  it('demo no consulta la RPC', () => {
    dobles.yo.demo = true
    renderHook(() => useColaTrabajo(p, '2026-09-30'), { wrapper: wrapper() })
    expect(dobles.obtener).not.toHaveBeenCalled()
  })
  it('una lectura iniciada antes del guardado no se usa tras confirmarlo, aunque coincida el elegido', async () => {
    let resolverVieja!: (data: ColaTrabajo) => void
    let resolverNueva!: (data: ColaTrabajo) => void
    const seleccionado = { ...p, elegido: muestra.elegido }
    const despues = { ...muestra, generado_en: '2026-09-30T19:00:00Z' } as ColaTrabajo
    dobles.obtener.mockResolvedValueOnce(muestra)
      .mockImplementationOnce(() => new Promise<ColaTrabajo>((r) => { resolverVieja = r }))
      .mockImplementationOnce(() => new Promise<ColaTrabajo>((r) => { resolverNueva = r }))
    const { result, rerender } = renderHook(({ revision }) => useColaTrabajo(seleccionado, '2026-09-30', revision), {
      wrapper: wrapper(), initialProps: { revision: 0 },
    })
    await waitFor(() => expect(result.current.data).toBeDefined())
    act(() => { void result.current.refetch() })
    await waitFor(() => expect(dobles.obtener).toHaveBeenCalledTimes(2))
    rerender({ revision: 1 })
    // Ni caché ni placeholder de la lectura anterior al guardado.
    expect(result.current.data).toBeUndefined()
    await waitFor(() => expect(dobles.obtener).toHaveBeenCalledTimes(3))
    await act(async () => { resolverVieja(muestra as ColaTrabajo) })
    expect(result.current.data).toBeUndefined()
    await act(async () => { resolverNueva(despues) })
    await waitFor(() => expect(result.current.data?.generado_en).toBe(despues.generado_en))

    // Una gestión posterior o su deshacer son datos nuevos válidos: no hay
    // una máscara local que espere para siempre el id de la primera actividad.
    const deshecha = { ...despues, items: despues.items.map((f) => ({ ...f, ultima_gestion: null, estado_trabajo: 'pendiente' })) }
    dobles.obtener.mockResolvedValue(deshecha)
    await act(async () => { await result.current.refetch() })
    await waitFor(() => expect(result.current.data?.items.every((f) => f.ultima_gestion === null)).toBe(true))
  })
})
