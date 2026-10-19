import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { recorridoFixture, recorridoId as id, recorridosFixture } from '@/test/fixtures/recorrido'
import type { Recorridos } from '@/lib/recorrido-lead'

let yo: { id: string; rol: string; demo: boolean } | null = null
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo }) }))
const api = vi.hoisted(() => ({ obtenerRecorridos: vi.fn() }))
vi.mock('./recorrido-api', () => api)
import { recorridoKeys, useRecorridoLeads } from './recorrido-queries'

function proveedor() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
  return { cliente, wrapper }
}
beforeEach(() => {
  yo = { id: 'analista', rol: 'vendedor', demo: false }
  api.obtenerRecorridos.mockReset().mockResolvedValue(recorridosFixture([recorridoFixture()]))
})

describe('caché del recorrido', () => {
  it('comparte por lote normalizado; invalidar leads refresca sin usar una foto anterior como permiso', async () => {
    const { cliente, wrapper } = proveedor()
    const { result, rerender } = renderHook(({ ids }) => useRecorridoLeads(ids), { wrapper, initialProps: { ids: [id(1), id(1)] } })
    await waitFor(() => expect(result.current.estado).toBe('listo'))
    rerender({ ids: [id(1)] })
    expect(api.obtenerRecorridos).toHaveBeenCalledTimes(1)
    let resolver!: (dato: Recorridos) => void
    api.obtenerRecorridos.mockImplementationOnce(() => new Promise<Recorridos>((r) => { resolver = r }))
    await act(async () => { void cliente.invalidateQueries({ queryKey: ['crm', 'leads'] }) })
    await waitFor(() => expect(result.current.estado).toBe('cargando'))
    expect(result.current.porLead.size).toBe(0)
    await act(async () => resolver(recorridosFixture([recorridoFixture(id(1), { ciclo_n: 2 })])))
    await waitFor(() => expect(result.current.porLead.get(id(1))?.ciclo_n).toBe(2))
    expect(recorridoKeys.raiz().slice(0, 2)).toEqual(['crm', 'leads'])
  })
  it('un fallo al refrescar oculta el dato anterior y ofrece estado desconocido', async () => {
    const { cliente, wrapper } = proveedor()
    const { result } = renderHook(() => useRecorridoLeads([id(1)]), { wrapper })
    await waitFor(() => expect(result.current.estado).toBe('listo'))
    api.obtenerRecorridos.mockRejectedValueOnce(new Error('red caída'))
    await act(async () => { await cliente.invalidateQueries({ queryKey: recorridoKeys.raiz() }) })
    await waitFor(() => expect(result.current.estado).toBe('error'))
    expect(result.current.porLead.size).toBe(0)
  })
  it('una respuesta tardía del actor anterior no aparece en la sesión nueva', async () => {
    let resolver!: (dato: Recorridos) => void
    api.obtenerRecorridos.mockImplementationOnce(() => new Promise<Recorridos>((r) => { resolver = r }))
    const { wrapper } = proveedor()
    const { result, rerender } = renderHook(() => useRecorridoLeads([id(1)]), { wrapper })
    yo = { id: 'supervisor', rol: 'supervisor', demo: false }
    api.obtenerRecorridos.mockResolvedValueOnce(recorridosFixture([]))
    rerender()
    await waitFor(() => expect(result.current.estado).toBe('listo'))
    await act(async () => resolver(recorridosFixture([recorridoFixture()])))
    expect(result.current.porLead.size).toBe(0)
  })
  it('el cambio de rol también consulta y no reutiliza la visibilidad anterior', async () => {
    const { wrapper } = proveedor()
    const { result, rerender } = renderHook(() => useRecorridoLeads([id(1)]), { wrapper })
    await waitFor(() => expect(result.current.estado).toBe('listo'))
    yo = { id: 'analista', rol: 'directorio', demo: false }
    api.obtenerRecorridos.mockResolvedValueOnce(recorridosFixture([]))
    rerender()
    await waitFor(() => expect(api.obtenerRecorridos).toHaveBeenCalledTimes(2))
    expect(result.current.porLead.size).toBe(0)
  })
  it.each(['sin sesión', 'demo', 'apagado', 'sin backend'])('queda inactivo: %s', async (caso) => {
    if (caso === 'sin sesión') yo = null
    if (caso === 'demo') yo = { id: 'demo', rol: 'vendedor', demo: true }
    api.obtenerRecorridos.mockResolvedValue(caso === 'apagado' ? recorridosFixture([], { modo: 'apagado' }) : null)
    const { wrapper } = proveedor()
    const { result } = renderHook(() => useRecorridoLeads([id(1)]), { wrapper })
    await waitFor(() => expect(result.current.estado).toBe('inactivo'))
    expect(result.current.porLead.size).toBe(0)
    if (caso === 'sin sesión' || caso === 'demo') expect(api.obtenerRecorridos).not.toHaveBeenCalled()
  })
})
