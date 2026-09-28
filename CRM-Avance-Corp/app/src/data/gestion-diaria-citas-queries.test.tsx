import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { PedidoCitas, PaginaCitas } from '@/lib/gestion-diaria-citas'
import type { Yo } from '@/lib/tipos'
import { CrmApiError } from './crm-api'

const dobles = vi.hoisted(() => ({ listar: vi.fn(), yo: null as Yo | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ tareas: [], equipo: [], ambito: { leads: [] } }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-24T17:00:00Z') }))
vi.mock('./gestion-diaria-citas-api', () => ({ listarCitasGestion: dobles.listar }))
const { useCitasGestion } = await import('./gestion-diaria-citas-queries')

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const vacia = (p: PedidoCitas): PaginaCitas => ({ version: 1, zona: 'America/Lima', dia: p.dia, ambito: p.ambito, id: p.id,
  generado_en: '2026-09-24T17:00:00.000Z', limite: p.limite, resumen: { total: 0 }, items: [], hay_mas: false, siguiente_cursor: null })
let cliente: QueryClient
const envolver = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
beforeEach(() => {
  vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  dobles.listar.mockImplementation(async (p: PedidoCitas) => vacia(p))
})

describe('G4b: quién pide la lista de citas', () => {
  it('gerencia pide cualquier ámbito y el pedido lleva el día, el ámbito y el id', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'equipo', id(2), true), { wrapper: envolver })
    await waitFor(() => expect(result.current.total).toBe(0))
    expect(dobles.listar).toHaveBeenCalledWith(expect.objectContaining({ dia: '2026-09-24', ambito: 'equipo', id: id(2), cursor: null }), expect.any(AbortSignal))
  })
  it('supervisión sólo pide el ámbito «analista»', async () => {
    dobles.yo = { id: id(3), rol: 'supervisor', demo: false } as Yo
    const analista = renderHook(() => useCitasGestion('2026-09-24', 'analista', id(4), true), { wrapper: envolver })
    await waitFor(() => expect(dobles.listar).toHaveBeenCalledTimes(1))
    renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
    await act(async () => { await Promise.resolve() })
    expect(dobles.listar).toHaveBeenCalledTimes(1)
    expect(analista.result.current.sinPermiso).toBe(false)
  })
  it.each(['vendedor', 'coordinador', 'directorio'] as const)('%s no pide la lista', async (rol) => {
    dobles.yo = { id: id(5), rol, demo: false } as Yo
    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'analista', id(4), true), { wrapper: envolver })
    await act(async () => { await Promise.resolve() })
    expect(dobles.listar).not.toHaveBeenCalled()
    expect(result.current.items).toEqual([])
  })
  it('no consulta hasta hacerse visible', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    const { rerender } = renderHook(({ visible }) => useCitasGestion('2026-09-24', 'operacion', null, visible), { wrapper: envolver, initialProps: { visible: false } })
    await act(async () => { await Promise.resolve() })
    expect(dobles.listar).not.toHaveBeenCalled()
    rerender({ visible: true })
    await waitFor(() => expect(dobles.listar).toHaveBeenCalledTimes(1))
  })
  it('un 42501 retira las filas y no vuelve a consultar solo', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    dobles.listar.mockRejectedValue(new CrmApiError('revocado', '42501'))
    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
    await waitFor(() => expect(result.current.sinPermiso).toBe(true))
    expect(result.current.items).toEqual([])
    expect(dobles.listar).toHaveBeenCalledTimes(1)
  })
})
