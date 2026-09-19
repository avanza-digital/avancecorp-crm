import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Actividad } from '@/lib/tipos'
import * as crmApi from './crm-api'
import { useActividadesDeLead } from './use-actividades-de-lead'

vi.mock('./crm-api', async (importActual) => {
  const actual = await importActual<typeof import('./crm-api')>()
  return { ...actual, listarActividadesDeLead: vi.fn() }
})
const listar = vi.mocked(crmApi.listarActividadesDeLead)

const LEAD = 'lead-1'
const srv = (id: string, creado_en: string, tipo: Actividad['tipo'] = 'nota'): Actividad => ({
  id, lead_id: LEAD, tipo, detalle: null, autor_nombre: 'ANALISTA', creado_en,
})
const SENALES = { tieneReunionRealizada: false, tieneContacto: true, ultimaConversacionEn: null }

function sesion(demo: boolean): AuthContextValue {
  return {
    fase: 'listo',
    yo: { id: 'vendedor-1', nombre_completo: 'ANALISTA PRUEBA', rol: 'vendedor', demo, puede_contratar: true },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

function montar(locales: Actividad[], demo = false) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const api = { actividadesDe: (id: string) => (id === LEAD ? locales : []) } as unknown as StoreDataApi
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={sesion(demo)}>
        <StoreDataContext.Provider value={api}>{children}</StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>
  )
  return renderHook(() => useActividadesDeLead(LEAD), { wrapper })
}

beforeEach(() => vi.clearAllMocks())

describe('useActividadesDeLead — historial por lead (sesión real)', () => {
  it('pide la primera página al servidor y la sirve ordenada con sus señales', async () => {
    listar.mockResolvedValueOnce({
      items: [srv('s-vieja', '2026-09-10T10:00:00+00:00'), srv('s-nueva', '2026-09-19T10:00:00+00:00')],
      cursor: null,
      senales: SENALES,
    })

    const { result } = montar([])
    expect(result.current.cargando).toBe(true)
    await waitFor(() => expect(result.current.cargando).toBe(false))

    expect(listar).toHaveBeenCalledWith(LEAD, null, expect.anything())
    expect(result.current.items.map((a) => a.id)).toEqual(['s-nueva', 's-vieja'])
    expect(result.current.hayMas).toBe(false)
    expect(result.current.senales).toEqual(SENALES)
    expect(result.current.error).toBeNull()
  })

  it('la fila optimista se pinta hasta que llega una lectura POSTERIOR a su creación', async () => {
    const futura = { ...srv('local-futura', '2026-09-19T12:00:00.000Z', 'llamada_realizada'), local: true as const, local_ts: Date.now() + 60_000 }
    const vieja = { ...srv('local-vieja', '2026-09-19T11:00:00.000Z', 'llamada_realizada'), local: true as const, local_ts: 1 }
    listar.mockResolvedValueOnce({ items: [srv('s-1', '2026-09-19T11:00:00.000Z', 'llamada_realizada')], cursor: null, senales: SENALES })

    const { result } = montar([futura, vieja])
    // Antes de leer nada del servidor, las dos locales se ven.
    expect(result.current.items.map((a) => a.id)).toEqual(['local-futura', 'local-vieja'])
    await waitFor(() => expect(result.current.cargando).toBe(false))

    // La lectura es posterior a `local-vieja` (la sustituye) y anterior a `local-futura` (sigue viva).
    expect(result.current.items.map((a) => a.id)).toEqual(['local-futura', 's-1'])
    // Las señales unen lo servido con lo local vivo: la llamada local cuenta como conversación.
    expect(result.current.senales.ultimaConversacionEn).toBe('2026-09-19T12:00:00.000Z')
  })

  it('con fallo del servidor no cae a la lista global: expone el error, hayMas=false y solo las locales', async () => {
    const local = { ...srv('local-1', '2026-09-19T12:00:00.000Z'), local: true as const, local_ts: Date.now() }
    listar.mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo cargar el historial del lead.', 'PGRST000'))

    const { result } = montar([local])
    await waitFor(() => expect(result.current.error).not.toBeNull())

    expect(result.current.items.map((a) => a.id)).toEqual(['local-1'])
    expect(result.current.hayMas).toBe(false)
    expect(result.current.cargando).toBe(false)
  })

  it('«cargar más» pide la siguiente página con el cursor que devolvió el servidor', async () => {
    listar
      .mockResolvedValueOnce({ items: [srv('p1', '2026-09-19T10:00:00+00:00')], cursor: { creadoEn: '2026-09-19T10:00:00+00:00', id: 'p1' }, senales: SENALES })
      .mockResolvedValueOnce({ items: [srv('p2', '2026-09-18T10:00:00+00:00')], cursor: null, senales: SENALES })

    const { result } = montar([])
    await waitFor(() => expect(result.current.hayMas).toBe(true))

    act(() => result.current.cargarMas())
    await waitFor(() => expect(result.current.items).toHaveLength(2))

    expect(listar).toHaveBeenLastCalledWith(LEAD, { creadoEn: '2026-09-19T10:00:00+00:00', id: 'p1' }, expect.anything())
    expect(result.current.items.map((a) => a.id)).toEqual(['p1', 'p2'])
    expect(result.current.hayMas).toBe(false)
  })
})

describe('useActividadesDeLead — demo (fail-closed: ni un request)', () => {
  it('sirve el historial del store tal cual y deriva las señales de él', () => {
    const acts = [srv('d-2', '2026-09-19T10:00:00Z', 'reunion_realizada'), srv('d-1', '2026-09-18T10:00:00Z')]

    const { result } = montar(acts, true)

    expect(listar).not.toHaveBeenCalled()
    expect(result.current.items).toBe(acts)
    expect(result.current.cargando).toBe(false)
    expect(result.current.hayMas).toBe(false)
    expect(result.current.senales).toEqual({
      tieneReunionRealizada: true,
      tieneContacto: true,
      ultimaConversacionEn: '2026-09-19T10:00:00Z',
    })
  })
})
