import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider, focusManager, onlineManager } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { idPendiente, paginaPendientes, pedidoPendientes, tareaPendiente } from '@/lib/gestion-diaria-pendientes.fixture'
import type { PedidoPendientes } from '@/lib/gestion-diaria-pendientes'
import type { Yo } from '@/lib/tipos'
import { CrmApiError } from './crm-api'

const dobles = vi.hoisted(() => ({ listar: vi.fn(), yo: null as Yo | null, vendedores: [] as { perfil_id: string; activo: boolean }[] }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ tareas: [], equipo: [], ambito: { leads: [], vendedores: dobles.vendedores } }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-23T17:00:00Z') }))
vi.mock('./gestion-diaria-pendientes-api', () => ({ listarPendientesSupervisor: dobles.listar }))
const { usePendientesSupervisor, clavePendientes } = await import('./gestion-diaria-pendientes-queries')
let cliente: QueryClient
const envolver = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
beforeEach(() => {
  vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } }); dobles.vendedores = []
  dobles.yo = { id: pedidoPendientes.supervisor, rol: 'supervisor', demo: false } as Yo
  dobles.listar.mockImplementation(async (p: PedidoPendientes) => {
    const inicio = p.cursor ? Number(p.cursor.despues_id.slice(-12)) + 1 : 10
    const items = Array.from({ length: 25 }, (_, i) => tareaPendiente(inicio + i))
    return paginaPendientes(items, { solo_vencidas: p.soloVencidas, resumen: { tareas_pendientes: 100, tareas_vencidas: 100 }, hay_mas: true,
      siguiente_cursor: { despues_de: items[24]!.vence_en, despues_id: items[24]!.id } })
  })
})
afterEach(() => { cliente.clear(); focusManager.setFocused(undefined); onlineManager.setOnline(true); vi.useRealTimers() })
describe('Memoria y refresco paginados del supervisor', () => {
  it('no consulta hasta hacerse visible y reanuda una sola página', async () => {
    const { result, rerender } = renderHook(({ visible }) => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, visible), { wrapper: envolver, initialProps: { visible: false } })
    expect(dobles.listar).not.toHaveBeenCalled()
    rerender({ visible: true }); await waitFor(() => expect(result.current.items).toHaveLength(25))
    rerender({ visible: false }); const n = dobles.listar.mock.calls.length
    await act(async () => { focusManager.setFocused(false); focusManager.setFocused(true); onlineManager.setOnline(false); onlineManager.setOnline(true) })
    expect(dobles.listar).toHaveBeenCalledTimes(n)
    rerender({ visible: true }); await waitFor(() => expect(dobles.listar.mock.calls.length).toBeGreaterThan(n))
  })
  it('dos páginas congelan todas las consultas al volver, enfocar y reconectar; refrescar empieza desde cero', async () => {
    const { result, rerender } = renderHook(({ visible }) => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, visible), { wrapper: envolver, initialProps: { visible: true } })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    await act(async () => { await result.current.cargarMas() }); await waitFor(() => expect(result.current.items).toHaveLength(50))
    expect(result.current.congelada).toBe(true)
    const n = dobles.listar.mock.calls.length
    rerender({ visible: false }); rerender({ visible: true })
    await act(async () => { focusManager.setFocused(false); focusManager.setFocused(true); onlineManager.setOnline(false); onlineManager.setOnline(true) })
    vi.useFakeTimers(); await act(async () => { await vi.advanceTimersByTimeAsync(120001) }); vi.useRealTimers()
    expect(dobles.listar).toHaveBeenCalledTimes(n)
    await act(async () => { await result.current.recargar() })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    expect(dobles.listar).toHaveBeenLastCalledWith(expect.objectContaining({ cursor: null }), expect.any(AbortSignal))
    expect(result.current.congelada).toBe(false)
  })
  it('un error de red cargando más conserva páginas identificadas como anteriores', async () => {
    const { result } = renderHook(() => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, true), { wrapper: envolver })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    dobles.listar.mockRejectedValue(new Error('sin red'))
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.error).not.toBeNull())
    expect(result.current.items).toHaveLength(25); expect(result.current.hayMas).toBe(false)
  })
  it('42501 retira las filas y purga también la memoria; volver no las recupera', async () => {
    const { result, rerender } = renderHook(({ visible }) => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, visible), { wrapper: envolver, initialProps: { visible: true } })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    dobles.listar.mockRejectedValue(new CrmApiError('revocado', '42501'))
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.sinPermiso).toBe(true))
    expect(result.current.items).toEqual([])
    expect(cliente.getQueryData([...clavePendientes(pedidoPendientes.supervisor, 'supervisor', false, '2026-09-23', pedidoPendientes.analista, false), 0])).toEqual({ pages: [], pageParams: [] })
    const n = dobles.listar.mock.calls.length
    rerender({ visible: false }); rerender({ visible: true })
    expect(result.current.items).toEqual([]); expect(dobles.listar).toHaveBeenCalledTimes(n)
  })
  it('una revocación purga también otro filtro y cambiar de filtro no recupera filas', async () => {
    const { result, rerender } = renderHook(({ filtro }) => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, filtro, true), { wrapper: envolver, initialProps: { filtro: false } })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    const otraClave=[...clavePendientes(pedidoPendientes.supervisor, 'supervisor', false, '2026-09-23', pedidoPendientes.analista, true),0]
    cliente.setQueryData(otraClave,{pages:[paginaPendientes()],pageParams:[null]})
    dobles.listar.mockRejectedValue(new CrmApiError('revocado','42501'))
    await act(async () => { await result.current.cargarMas() })
    await waitFor(() => expect(result.current.sinPermiso).toBe(true))
    expect(cliente.getQueryData(otraClave)).toEqual({pages:[],pageParams:[]})
    const n=dobles.listar.mock.calls.length
    rerender({filtro:true}); expect(result.current.sinPermiso).toBe(true); expect(result.current.items).toEqual([])
    expect(dobles.listar).toHaveBeenCalledTimes(n)
  })
  it('el fallo de la tercera página conserva las dos anteriores congeladas', async () => {
    const {result}=renderHook(()=>usePendientesSupervisor('2026-09-23',pedidoPendientes.analista,false,true),{wrapper:envolver})
    await waitFor(()=>expect(result.current.items).toHaveLength(25))
    await act(async()=>{await result.current.cargarMas()});await waitFor(()=>expect(result.current.items).toHaveLength(50))
    dobles.listar.mockRejectedValue(new Error('sin red'))
    await act(async()=>{await result.current.cargarMas()})
    await waitFor(()=>expect(result.current.error).not.toBeNull())
    expect(result.current.items).toHaveLength(50);expect(result.current.congelada).toBe(true);expect(result.current.hayMas).toBe(false)
  })
  it('una respuesta tardía del analista anterior no cruza al siguiente', async () => {
    let resolver!: (v: unknown)=>void
    dobles.listar.mockImplementationOnce(()=>new Promise(r=>{resolver=r})).mockImplementation(()=>new Promise(()=>{}))
    const {result,rerender}=renderHook(({analista})=>usePendientesSupervisor('2026-09-23',analista,false,true),{wrapper:envolver,initialProps:{analista:pedidoPendientes.analista}})
    rerender({analista:idPendiente(8)})
    await act(async()=>{resolver(paginaPendientes())})
    expect(result.current.items).toEqual([]);expect(result.current.cargando).toBe(true)
  })
  it.each(['actor', 'rol', 'demo', 'dia', 'analista', 'filtro', 'apertura'])('separa el cambio de %s y rechaza respuestas tardías', async cambio => {
    const inicial = { dia: '2026-09-23', analista: pedidoPendientes.analista, filtro: false, apertura: 0 }
    const { result, rerender } = renderHook(p => usePendientesSupervisor(p.dia, p.analista, p.filtro, true, p.apertura), { wrapper: envolver, initialProps: inicial })
    await waitFor(() => expect(result.current.items).toHaveLength(25))
    const p = { ...inicial }
    if (cambio === 'actor') dobles.yo = { ...dobles.yo!, id: idPendiente(9) }
    if (cambio === 'rol') dobles.yo = { ...dobles.yo!, rol: 'vendedor' }
    if (cambio === 'demo') dobles.yo = { ...dobles.yo!, demo: true }
    if (cambio === 'dia') p.dia = '2026-09-24'
    if (cambio === 'analista') p.analista = idPendiente(8)
    if (cambio === 'filtro') p.filtro = true
    if (cambio === 'apertura') p.apertura++
    dobles.listar.mockImplementation(() => new Promise(() => {}))
    rerender(p)
    expect(result.current.items).toEqual([])
  })
})

describe('G4a: quién consulta pendientes', () => {
  it('gerencia consulta con su propio id como «supervisor» del pedido: el servidor autoriza toda la operación', async () => {
    const gerente = idPendiente(90)
    dobles.yo = { id: gerente, rol: 'gerencia', demo: false } as Yo
    const { result } = renderHook(() => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, true), { wrapper: envolver })
    await waitFor(() => expect(dobles.listar).toHaveBeenCalled())
    expect(dobles.listar).toHaveBeenCalledWith(expect.objectContaining({ supervisor: gerente, analista: pedidoPendientes.analista }), expect.any(AbortSignal))
    expect(result.current.sinPermiso).toBe(false)
  })
  it.each(['vendedor', 'coordinador', 'directorio'] as const)('%s no consulta pendientes', async (rol) => {
    dobles.yo = { id: idPendiente(91), rol, demo: false } as Yo
    const { result } = renderHook(() => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, true), { wrapper: envolver })
    await act(async () => { await Promise.resolve() })
    expect(dobles.listar).not.toHaveBeenCalled()
    expect(result.current.items).toEqual([])
  })
})

describe('G4a en modo demo: gerencia, el mismo ámbito que el servidor', () => {
  it('lee a cualquier analista activo de la operación y a nadie más', async () => {
    const gerente = idPendiente(92)
    dobles.yo = { id: gerente, rol: 'gerencia', demo: true } as Yo
    dobles.vendedores = [{ perfil_id: pedidoPendientes.analista, activo: true }, { perfil_id: idPendiente(93), activo: false }]
    const { result } = renderHook(() => usePendientesSupervisor('2026-09-23', pedidoPendientes.analista, false, true), { wrapper: envolver })
    await waitFor(() => expect(result.current.cargando).toBe(false))
    expect(result.current.sinPermiso).toBe(false)
    expect(result.current.error).toBeNull()
    expect(result.current.pagina?.supervisor_id).toBe(gerente)
    expect(dobles.listar).not.toHaveBeenCalled()
    const inactivo = renderHook(() => usePendientesSupervisor('2026-09-23', idPendiente(93), false, true), { wrapper: envolver })
    await waitFor(() => expect(inactivo.result.current.sinPermiso).toBe(true))
  })
})
