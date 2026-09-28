import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { CitaAgendada, PedidoCitas, PaginaCitas } from '@/lib/gestion-diaria-citas'
import type { Yo } from '@/lib/tipos'
import { CrmApiError } from './crm-api'

const dobles = vi.hoisted(() => ({ listar: vi.fn(), yo: null as Yo | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ tareas: [], equipo: [], ambito: { leads: [] } }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-24T17:00:00Z') }))
vi.mock('./gestion-diaria-citas-api', () => ({ listarCitasGestion: dobles.listar }))
const { useCitasGestion, claveCitas } = await import('./gestion-diaria-citas-queries')

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

// Páginas reales de 25 (el límite del hook), en orden (creado_en, id).
const cita = (n: number): CitaAgendada => ({ id: id(100 + n), vendedor_id: id(2), vendedor_nombre: 'ANALISTA', lead_id: null, lead_nombre: null,
  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', creado_en: new Date(Date.parse('2026-09-24T06:00:00Z') + n * 60_000).toISOString() })
const rango = (desde: number, hasta: number) => Array.from({ length: hasta - desde + 1 }, (_, i) => cita(desde + i))
const pagina = (p: PedidoCitas, items: CitaAgendada[], total: number, hayMas: boolean): PaginaCitas => ({ ...vacia(p), items, resumen: { total }, hay_mas: hayMas,
  siguiente_cursor: hayMas ? { despues_de: items.at(-1)!.creado_en, despues_id: items.at(-1)!.id } : null })

describe('G4b: la lista cambia entre páginas (Codex P1)', () => {
  it('crece entre páginas: se descarta, se pide desde cero, se dice y nunca se anuncia un total que no es la lista', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    let primeras = 0
    dobles.listar.mockImplementation(async (p: PedidoCitas) => {
      if (p.cursor) return pagina(p, rango(26, 27), 27, false) // entró una cita nueva: la 2.ª página dice 27
      primeras += 1
      return primeras === 1 ? pagina(p, rango(1, 25), 26, true) : pagina(p, rango(1, 25), 27, true)
    })
    const vistas: [number, number | null][] = []
    const { result } = renderHook(() => { const r = useCitasGestion('2026-09-24', 'operacion', null, true); vistas.push([r.items.length, r.total]); return r }, { wrapper: envolver })
    await waitFor(() => expect(result.current.total).toBe(26))
    expect(result.current.cambio).toBe(false)
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.total).toBe(27))
    expect(result.current.items).toHaveLength(25)
    expect(result.current.cambio).toBe(true)
    expect(dobles.listar).toHaveBeenCalledTimes(3)
    expect(dobles.listar).toHaveBeenLastCalledWith(expect.objectContaining({ cursor: null }), expect.any(AbortSignal))
    // Ninguna vista mostró más filas que su total (antes: «26» anunciadas y 27 filas).
    expect(vistas.filter(([filas, total]) => total !== null && filas > total)).toEqual([])
  })
  it('se reduce entre páginas: igual, desde cero y con el aviso', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    let primeras = 0
    dobles.listar.mockImplementation(async (p: PedidoCitas) => {
      if (p.cursor) return pagina(p, [cita(26)], 26, false) // se retiró una cita: la 2.ª página dice 26
      primeras += 1
      return primeras === 1 ? pagina(p, rango(1, 25), 27, true) : pagina(p, rango(1, 25), 26, true)
    })
    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
    await waitFor(() => expect(result.current.total).toBe(27))
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.total).toBe(26))
    expect(result.current.items).toHaveLength(25)
    expect(result.current.cambio).toBe(true)
    // «Actualizar» empieza otra foto y el aviso ya no aplica.
    await act(async () => { await result.current.recargar() })
    await waitFor(() => expect(result.current.cambio).toBe(false))
  })
  it('una secuencia coherente no avisa ni recarga', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    dobles.listar.mockImplementation(async (p: PedidoCitas) => p.cursor ? pagina(p, rango(26, 27), 27, false) : pagina(p, rango(1, 25), 27, true))
    const { result } = renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
    await waitFor(() => expect(result.current.total).toBe(27))
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.items).toHaveLength(27))
    expect(result.current.cambio).toBe(false)
    expect(result.current.hayMas).toBe(false)
    expect(dobles.listar).toHaveBeenCalledTimes(2)
  })
  it('un 42501 DESPUÉS de una página válida retira las filas, limpia la caché y no vuelve a consultar solo', async () => {
    dobles.yo = { id: id(1), rol: 'gerencia', demo: false } as Yo
    dobles.listar.mockImplementation(async (p: PedidoCitas) => {
      if (p.cursor) throw new CrmApiError('revocado', '42501')
      return pagina(p, rango(1, 25), 30, true)
    })
    const { result, rerender } = renderHook(() => useCitasGestion('2026-09-24', 'operacion', null, true), { wrapper: envolver })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.sinPermiso).toBe(true))
    expect(result.current.items).toEqual([])
    expect(result.current.total).toBeNull()
    expect(cliente.getQueryData([...claveCitas(id(1), 'gerencia', false, '2026-09-24', 'operacion', null), 0])).toEqual({ pages: [], pageParams: [] })
    const n = dobles.listar.mock.calls.length
    rerender()
    await act(async () => { await new Promise((listo) => setTimeout(listo, 20)) })
    expect(dobles.listar).toHaveBeenCalledTimes(n)
    await act(async () => { await result.current.cargarMas() })
    expect(dobles.listar).toHaveBeenCalledTimes(n)
  })
})
