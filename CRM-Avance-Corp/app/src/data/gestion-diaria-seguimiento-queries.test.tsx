import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Yo } from '@/lib/tipos'
import { idH4, jornadaH4 } from '@/lib/gestion-diaria-h4.fixture'
import { CrmApiError } from './crm-api'

const dobles = vi.hoisted(() => ({ obtener: vi.fn(), reconocer: vi.fn(), yo: null as Yo | null,
  ahora: Date.parse('2026-09-24T12:00:00-05:00') }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => dobles.ahora }))
vi.mock('@/lib/config', async (importOriginal) => ({ ...await importOriginal<typeof import('@/lib/config')>(), funcionesLeadsVisibles: () => true }))
vi.mock('./gestion-diaria-seguimiento-api', () => ({ obtenerAvisosCortes: dobles.obtener, reconocerCorte: dobles.reconocer }))
const { useAvisosCortes, seguimientoKeys } = await import('./gestion-diaria-seguimiento-queries')
let cliente: QueryClient
function envolver({ children }: { children: ReactNode }) { return <QueryClientProvider client={cliente}>{children}</QueryClientProvider> }
beforeEach(() => {
  vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  dobles.yo = { id: idH4(1), rol: 'supervisor', demo: false, nombre_completo: 'SUP' } as Yo
  dobles.ahora = Date.parse('2026-09-24T12:00:00-05:00')
  dobles.obtener.mockResolvedValue(jornadaH4().avisos); dobles.reconocer.mockResolvedValue(jornadaH4().avisos)
})
afterEach(() => cliente.clear())
describe('H4: lectura compartida y acciones confirmadas', () => {
  it('dos observadores comparten una sola lectura y la escritura espera el refresco del servidor', async () => {
    const { result } = renderHook(() => [useAvisosCortes(), useAvisosCortes()] as const, { wrapper: envolver })
    await waitFor(() => expect(result.current[0].datos).not.toBeNull())
    expect(dobles.obtener).toHaveBeenCalledOnce()
    let resolver!: (data: ReturnType<typeof jornadaH4>['avisos']) => void
    dobles.obtener.mockImplementationOnce(() => new Promise((r) => { resolver = r }))
    let accion!: Promise<unknown>
    act(() => { accion = result.current[0].accion.mutateAsync({ alertaId: jornadaH4().avisos.alertas[0]!.id, accion: 'posponer', solicitudId: idH4(9) }) })
    await waitFor(() => expect(dobles.obtener).toHaveBeenCalledTimes(2))
    expect(result.current[0].accion.isPending).toBe(true)
    const confirmado = jornadaH4().avisos; confirmado.alertas[0]!.estado = 'pospuesto'; confirmado.alertas[0]!.puede_posponer = false
    confirmado.alertas[0]!.pospuesto_hasta = '2026-09-24T13:00:00-05:00'
    await act(async () => { resolver(confirmado); await accion })
    await waitFor(() => expect(result.current[1].datos?.alertas[0]?.estado).toBe('pospuesto'))
    expect(dobles.reconocer).toHaveBeenCalledWith(idH4(1), confirmado.alertas[0]!.id, 'posponer', idH4(9))
  })
  it('error temporal o revocación retira la foto; recupera sólo tras respuesta confirmada', async () => {
    const { result } = renderHook(() => useAvisosCortes(), { wrapper: envolver })
    await waitFor(() => expect(result.current.datos).not.toBeNull())
    dobles.obtener.mockRejectedValue(new CrmApiError('revocado', '42501'))
    await act(async () => { await result.current.consulta.refetch() })
    await waitFor(() => expect(result.current.datos).toBeNull())
    expect(cliente.getQueryData(seguimientoKeys.avisos(idH4(1), '2026-09-24'))).toBeTruthy()
    dobles.obtener.mockResolvedValue({ ...jornadaH4().avisos, alertas: [] })
    await act(async () => { await result.current.consulta.refetch() })
    await waitFor(() => expect(result.current.datos?.alertas).toEqual([]))
  })
  it('cambio de día limpia avisos anteriores y rechaza una respuesta de otra jornada', async () => {
    const { result, rerender } = renderHook(() => useAvisosCortes(), { wrapper: envolver })
    await waitFor(() => expect(result.current.datos).not.toBeNull())
    dobles.ahora += 86400000; rerender()
    expect(result.current.datos).toBeNull()
    await waitFor(() => expect(result.current.consulta.error).toMatchObject({ code: 'GESTION_DIARIA_JORNADA' }))
    dobles.obtener.mockResolvedValue(jornadaH4('2026-09-25').avisos)
    await act(async () => { await result.current.consulta.refetch() })
    await waitFor(() => expect(result.current.datos?.dia).toBe('2026-09-25'))
  })
  it('cambio de actor descarta la respuesta tardía del anterior', async () => {
    let resolver!: (data: ReturnType<typeof jornadaH4>['avisos']) => void
    dobles.obtener.mockImplementationOnce(() => new Promise((r) => { resolver = r }))
    const { result, rerender } = renderHook(() => useAvisosCortes(), { wrapper: envolver })
    dobles.yo = { ...dobles.yo!, id: idH4(99) }
    dobles.obtener.mockResolvedValue(jornadaH4('2026-09-24', idH4(99)).avisos); rerender()
    await waitFor(() => expect(result.current.datos?.supervisor_id).toBe(idH4(99)))
    await act(async () => { resolver(jornadaH4().avisos) })
    expect(result.current.datos?.supervisor_id).toBe(idH4(99))
  })
  it.each(['vendedor', 'gerencia', 'demo', 'sin sesión'])('%s no puede consultar ni reconocer cortes', async (caso) => {
    if (caso === 'sin sesión') dobles.yo = null
    else if (caso === 'demo') dobles.yo!.demo = true
    else dobles.yo!.rol = caso as Yo['rol']
    const { result } = renderHook(() => useAvisosCortes(), { wrapper: envolver })
    expect(result.current.datos).toBeNull(); expect(dobles.obtener).not.toHaveBeenCalled()
    await act(async () => { await expect(result.current.accion.mutateAsync({ alertaId: 'x', accion: 'reconocer', solicitudId: idH4(9) })).rejects.toMatchObject({ code: 'SIN_PERMISO' }) })
    expect(dobles.reconocer).not.toHaveBeenCalled()
  })
})
