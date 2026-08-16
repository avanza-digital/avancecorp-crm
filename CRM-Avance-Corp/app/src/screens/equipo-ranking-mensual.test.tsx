// Arnés FOCALIZADO de equipo.tsx: solo el cableado «el fallo de la conversión
// MENSUAL es un error real del ranking» (exigencia pre-release, 2026-08-15).
// El panel completo ya tiene su suite; aquí se prueba que ESTA pantalla le
// pasa el error — antes iba error={null} fijo y el fallo degradaba mudo.
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { objetivosCero } from '@/lib/objetivos'
import type { Yo } from '@/lib/tipos'

let YO: Yo | null = null
let MENSUAL_FALLA = false

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: [], vendedores: [], esGlobal: false },
    actividadesDelAmbito: [],
    actividades: [],
    tareas: [],
    equipo: [],
    objetivos: objetivosCero(),
    objetivosError: false,
    cumplimientoMetas: null,
    recargar: vi.fn(),
    reasignar: vi.fn(),
    agenda: [],
    tareasDe: () => [],
  }),
  usePanelesActions: () => ({ abrirLead: () => {}, abrirNuevoLead: () => {} }),
}))
vi.mock('@/data/crm-queries', async (importActual) => ({
  ...(await importActual<typeof import('@/data/crm-queries')>()),
  useConversionMensual: () => ({
    data: undefined,
    error: MENSUAL_FALLA ? new Error('500 simulado') : null,
    isError: MENSUAL_FALLA,
    isPending: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
}))
// Lo que el foco de este arnés no mira, en su versión más barata.
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({ indice: new Map(), cargando: false, error: null, recargar: vi.fn() }),
}))
vi.mock('@/data/use-cola-accion-operativa', () => ({
  useColaAccionOperativa: () => ({ cola: null, cargando: false, error: null, recargar: vi.fn() }),
}))
vi.mock('@/data/use-resumen-cartera-operativo', () => ({
  useResumenCarteraOperativo: () => ({ resumen: null, cargando: false, error: null, recargar: vi.fn() }),
}))
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/tipo-cambio')>(),
  useTipoCambio: () => ({ tc: null, recargar: vi.fn() }),
}))
vi.mock('@/components/common/animated-value', () => ({
  AnimatedValue: ({ value }: { value: string }) => <>{value}</>,
}))
// El panel imprime su prop error: es EXACTAMENTE lo que este arnés afirma.
vi.mock('./hoy/ranking-vendedores', () => ({
  RankingVendedoresPanel: ({ error }: { error: string | null }) => (
    <h1>Ranking de mi equipo{error ? ` · ERROR: ${error}` : ''}</h1>
  ),
}))

const { Equipo } = await import('./equipo')

// Provider mínimo: el mock parcial de crm-queries deja vivos otros hooks de la
// pantalla; aquí degradan a error sin red y este arnés no los mira.
function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={qc}><Equipo /></QueryClientProvider>)
}

beforeEach(() => {
  MENSUAL_FALLA = false
  YO = {
    id: 's-1',
    nombre_completo: 'SUPERVISOR UNO',
    rol: 'supervisor',
    demo: false,
    puede_contratar: false,
  }
})

describe('Equipo — el ranking y la conversión mensual', () => {
  it('si la MENSUAL falla, el ranking lo recibe como error (no degrada mudo)', () => {
    MENSUAL_FALLA = true
    montar()

    expect(
      screen.getByText(/ERROR: No se pudo calcular la conversión mensual del equipo\./),
    ).toBeInTheDocument()
  })

  it('con la mensual sana no se inventa ningún error', () => {
    montar()
    expect(screen.queryByText(/ERROR:/)).not.toBeInTheDocument()
  })
})
