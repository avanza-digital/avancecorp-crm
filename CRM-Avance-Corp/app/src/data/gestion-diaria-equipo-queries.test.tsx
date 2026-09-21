import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { diaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import type { Miembro, Yo } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({ obtener: vi.fn(), yo: null as Yo | null, equipo: [] as Miembro[] }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ equipo: dobles.equipo, ambito: { leads: [] }, actividadesDelAmbito: [], tareas: [] }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-21T15:00:00Z') }))
vi.mock('./gestion-diaria-api', () => ({ obtenerDiaEquipo: dobles.obtener }))
const { useDiaEquipo, claveDiaEquipo } = await import('./gestion-diaria-equipo-queries')
let cliente: QueryClient
function envolver({ children }: { children: ReactNode }) { return <QueryClientProvider client={cliente}>{children}</QueryClientProvider> }
beforeEach(() => {
  vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  dobles.yo = { id: 's1', rol: 'supervisor', demo: false, nombre_completo: 'SUP' } as Yo
  dobles.equipo = []
  dobles.obtener.mockResolvedValue(diaEquipoPrueba())
})
describe('Consulta operativa completa y fail-closed', () => {
  it('con store vacío usa el servidor, no inventa un roster vacío', async () => {
    const { result } = renderHook(() => useDiaEquipo('2026-09-21'), { wrapper: envolver })
    expect(result.current.cargando).toBe(true)
    await waitFor(() => expect(result.current.dia?.equipo).toHaveLength(1))
  })
  it('un refetch fallido oculta datos aunque TanStack los conserve', async () => {
    const { result } = renderHook(() => useDiaEquipo('2026-09-21'), { wrapper: envolver })
    await waitFor(() => expect(result.current.dia).not.toBeNull())
    dobles.obtener.mockRejectedValue(new Error('revocado'))
    await act(async () => { await result.current.recargar() })
    await waitFor(() => expect(result.current.error).not.toBeNull())
    expect(result.current.dia).toBeNull()
    expect(cliente.getQueryData(claveDiaEquipo('s1', 'supervisor', '2026-09-21'))).toBeTruthy()
  })
  it('separa actor, rol y jornada en caché y deja de mostrar al perder el rol', async () => {
    const { result, rerender } = renderHook(() => useDiaEquipo('2026-09-21'), { wrapper: envolver })
    await waitFor(() => expect(result.current.dia).not.toBeNull())
    dobles.yo = { ...dobles.yo!, rol: 'vendedor' }
    rerender()
    expect(result.current.dia).toBeNull()
    expect(claveDiaEquipo('s1', 'supervisor', '2026-09-21')).not.toEqual(claveDiaEquipo('s2', 'supervisor', '2026-09-21'))
    expect(claveDiaEquipo('s1', 'supervisor', '2026-09-21')).not.toEqual(claveDiaEquipo('s1', 'supervisor', '2026-09-22'))
  })
  it('la demo incluye al analista sin cartera y no llama al backend ni al actualizar', async () => {
    dobles.yo = { ...dobles.yo!, demo: true }
    dobles.equipo = [{ perfil_id: 'a1', nombre_completo: 'SIN CARTERA', rol_crm: 'vendedor', supervisor_id: 's1', activo: true }]
    const { result } = renderHook(() => useDiaEquipo('2026-09-21'), { wrapper: envolver })
    expect(result.current.dia?.equipo[0]?.gestiones_hoy).toBe(0)
    await act(async () => { await result.current.recargar() })
    expect(dobles.obtener).not.toHaveBeenCalled()
  })
  it('sin sesión no consulta ni ofrece datos de otra identidad, tampoco al actualizar', async () => {
    dobles.yo = null
    const { result } = renderHook(() => useDiaEquipo('2026-09-21'), { wrapper: envolver })
    expect(result.current.dia).toBeNull()
    await act(async () => { await result.current.recargar() })
    expect(dobles.obtener).not.toHaveBeenCalled()
  })
})
