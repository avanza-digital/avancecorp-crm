// El hook operativo: en demo responde con el espejo del ÁMBITO sin tocar la
// red; en sesión real, ante un error devuelve null (fail-closed, también si
// TanStack conserva una foto vieja) y las páginas con cursor no laten solas.
import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Actividad, Lead, Miembro, Tarea, Yo } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({
  yo: { id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: true } as Yo,
  listar: vi.fn(),
  obtenerDia: vi.fn(),
  tareas: [] as Tarea[],
  ambito: { leads: [] as Lead[], vendedores: [] as Miembro[], esGlobal: false },
  actividadesDelAmbito: [] as Actividad[],
  actividades: [] as Actividad[],
  equipo: [] as Miembro[],
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true, actividadesDelAmbito: dobles.actividadesDelAmbito, actividades: dobles.actividades, ambito: dobles.ambito, equipo: dobles.equipo, tareas: dobles.tareas }),
}))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-19T18:00:00Z') }))
vi.mock('./gestion-diaria-api', () => ({ listarRegistroActividad: dobles.listar, obtenerDiaAnalista: dobles.obtenerDia }))
const { useRegistroActividadOperativo, useDiaAnalista } = await import('./gestion-diaria-queries')

const FILTROS = { dia: '2026-09-19', analistaIds: null, pestana: 'todo' as const, etapa: null }
function envoltorio() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
}

beforeEach(() => {
  vi.clearAllMocks()
  dobles.yo = { id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: true } as Yo
  dobles.equipo = [{ perfil_id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true }]
  dobles.ambito = { leads: [{ id: 'l1', nombre_completo: 'LEAD UNO', etapa: 'nuevo', activo: true } as Lead], vendedores: dobles.equipo, esGlobal: false }
  dobles.actividadesDelAmbito = [{ id: 'x1', lead_id: 'l1', tipo: 'llamada_realizada', detalle: 'hoy', autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-19T15:00:00.000Z' }]
  // Una gestión GLOBAL sobre un lead ajeno: el espejo NO debe verla.
  dobles.tareas = []
  dobles.actividades = [...dobles.actividadesDelAmbito, { id: 'x9', lead_id: 'l-ajeno', tipo: 'llamada_realizada', detalle: 'ajena', autor_nombre: 'OTRO', creado_en: '2026-09-19T16:00:00.000Z' }]
})

describe('useRegistroActividadOperativo', () => {
  it('en demo devuelve el espejo del ámbito sin llamar a la red', () => {
    const { result } = renderHook(() => useRegistroActividadOperativo(FILTROS, null, 25), { wrapper: envoltorio() })
    expect(dobles.listar).not.toHaveBeenCalled()
    expect(result.current.cargando).toBe(false)
    expect(result.current.pagina?.items.map((i) => i.id)).toEqual(['x1'])
    expect(result.current.pagina?.items[0]?.creado_por).toBe('d-v1')
  })

  it('en sesión real un error deja pagina en null aunque llegue tarde', async () => {
    dobles.yo = { ...dobles.yo, demo: false }
    dobles.listar.mockRejectedValue(new Error('caído'))
    const { result } = renderHook(() => useRegistroActividadOperativo(FILTROS, null, 25), { wrapper: envoltorio() })
    expect(result.current.cargando).toBe(true)
    await waitFor(() => expect(result.current.error).toBeTruthy())
    expect(result.current.pagina).toBeNull()
    expect(result.current.cargando).toBe(false)
  })

  it('en sesión real entrega la página validada por la API', async () => {
    dobles.yo = { ...dobles.yo, demo: false }
    const pagina = { version: 1, generado_en: '2026-09-19T18:00:00Z', desde: '2026-09-19', hasta: '2026-09-19', zona: 'America/Lima', limite: 26, items: [] }
    dobles.listar.mockResolvedValue(pagina)
    const { result } = renderHook(() => useRegistroActividadOperativo(FILTROS, { antes_de: '2026-09-19T15:00:00Z', antes_id: 'a1' }, 25), { wrapper: envoltorio() })
    await waitFor(() => expect(result.current.pagina).toEqual(pagina))
    expect(dobles.listar).toHaveBeenCalledWith(FILTROS, { antes_de: '2026-09-19T15:00:00Z', antes_id: 'a1' }, 25, expect.anything())
  })
})

describe('useDiaAnalista', () => {
  it('en demo arma el día del ámbito sin tocar la red', () => {
    const { result } = renderHook(() => useDiaAnalista(null, null), { wrapper: envoltorio() })
    expect(dobles.obtenerDia).not.toHaveBeenCalled()
    expect(result.current.dia?.analista_id).toBe('d-v1')
    expect(result.current.dia?.marcador.llamadas).toBe(1)
    expect(result.current.cargando).toBe(false)
  })

  it('en sesión real un error deja el día en null (fail-closed)', async () => {
    dobles.yo = { ...dobles.yo, demo: false }
    dobles.obtenerDia.mockRejectedValue(new Error('caído'))
    const { result } = renderHook(() => useDiaAnalista(null, null), { wrapper: envoltorio() })
    await waitFor(() => expect(result.current.error).toBeTruthy())
    expect(result.current.dia).toBeNull()
  })

  it('en sesión real entrega lo que valida la API y le pasa el día y el analista pedidos', async () => {
    dobles.yo = { ...dobles.yo, demo: false }
    const dia = { version: 1, analista_id: 'otro', dia: '2026-09-18' }
    dobles.obtenerDia.mockResolvedValue(dia)
    const { result } = renderHook(() => useDiaAnalista('2026-09-18', 'otro'), { wrapper: envoltorio() })
    await waitFor(() => expect(result.current.dia).toEqual(dia))
    expect(dobles.obtenerDia).toHaveBeenCalledWith('2026-09-18', 'otro', expect.anything())
  })
})
