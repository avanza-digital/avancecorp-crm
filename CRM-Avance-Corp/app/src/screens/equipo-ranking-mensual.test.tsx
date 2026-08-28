// Arnés FOCALIZADO de equipo.tsx: solo el cableado «el fallo de la conversión
// MENSUAL es un error real del ranking» (exigencia pre-release, 2026-08-15).
// El panel completo ya tiene su suite; aquí se prueba que ESTA pantalla le
// pasa el error — antes iba error={null} fijo y el fallo degradaba mudo.
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { objetivosCero } from '@/lib/objetivos'
import type { Miembro, Yo } from '@/lib/tipos'

let YO: Yo | null = null
let MENSUAL_FALLA = false
let CONVERSION_OPERATIVA: number | null | undefined
let CONVERSION_EQUIPO_OPERATIVA: number | null | undefined
let CONVERSION_DISPONIBLE = true
let CONVERSION_EQUIPO_DISPONIBLE = true
let AVISO_CONVERSION: string | null = null

const VENDEDOR: Miembro = {
  perfil_id: 'v-1',
  nombre_completo: 'ANA TORRES',
  rol_crm: 'vendedor',
  supervisor_id: 's-1',
  activo: true,
}

const SUPERVISORA: Miembro = {
  perfil_id: 's-1',
  nombre_completo: 'SUPERVISORA UNO',
  rol_crm: 'supervisor',
  supervisor_id: null,
  activo: true,
}

function totalConversion(disponible: boolean, conversion: number | null) {
  return {
    cierresConversion: disponible ? 0 : null,
    conversion,
    conversionDisponible: disponible,
    operacionesCartera: disponible ? 4 : null,
    divisorConversion: disponible ? conversion == null ? 0 : 8 : null,
    numeradorConversion: disponible ? conversion == null ? 4 : 11.0104 : null,
  }
}

const TOTAL_INDISPONIBLE = totalConversion(false, null)

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: {
      leads: [],
      vendedores: CONVERSION_OPERATIVA === undefined && CONVERSION_EQUIPO_OPERATIVA === undefined ? [] : [VENDEDOR],
      esGlobal: CONVERSION_EQUIPO_OPERATIVA !== undefined,
    },
    actividadesDelAmbito: [],
    actividades: [],
    tareas: [],
    equipo: CONVERSION_EQUIPO_OPERATIVA !== undefined
      ? [SUPERVISORA, VENDEDOR]
      : CONVERSION_OPERATIVA === undefined ? [] : [VENDEDOR],
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
vi.mock('@/data/use-metricas-vendedores-operativas', () => ({
  useMetricasVendedoresOperativas: () => ({
    metricas: CONVERSION_EQUIPO_OPERATIVA !== undefined
      ? {
        filas: [{
          m: VENDEDOR,
          activos: 0,
          capitalPEN: 0,
          capitalUSD: 0,
          convertidos: 0,
          cierresConversion: CONVERSION_EQUIPO_DISPONIBLE ? 0 : null,
          conversion: CONVERSION_EQUIPO_OPERATIVA,
          conversionDisponible: CONVERSION_EQUIPO_DISPONIBLE,
          operacionesCartera: CONVERSION_EQUIPO_DISPONIBLE ? 4 : null,
          divisorConversion: CONVERSION_EQUIPO_DISPONIBLE
            ? CONVERSION_EQUIPO_OPERATIVA == null ? 0 : 8
            : null,
          numeradorConversion: CONVERSION_EQUIPO_DISPONIBLE
            ? CONVERSION_EQUIPO_OPERATIVA == null ? 4 : 11.0104
            : null,
          sinTocar: 0,
          diasSinActividadMax: 0,
        }],
        equipos: [{
          supervisor: SUPERVISORA,
          vendedores: 1,
          activos: 0,
          capitalPEN: 0,
          capitalUSD: 0,
          convertidos: 0,
          cierresConversion: CONVERSION_EQUIPO_DISPONIBLE ? 0 : null,
          conversion: CONVERSION_EQUIPO_OPERATIVA,
          conversionDisponible: CONVERSION_EQUIPO_DISPONIBLE,
          operacionesCartera: CONVERSION_EQUIPO_DISPONIBLE ? 4 : null,
          divisorConversion: CONVERSION_EQUIPO_DISPONIBLE
            ? CONVERSION_EQUIPO_OPERATIVA == null ? 0 : 8
            : null,
          numeradorConversion: CONVERSION_EQUIPO_DISPONIBLE
            ? CONVERSION_EQUIPO_OPERATIVA == null ? 4 : 11.0104
            : null,
          parkeados: 0,
        }],
        totalConversion: totalConversion(
          CONVERSION_EQUIPO_DISPONIBLE,
          CONVERSION_EQUIPO_OPERATIVA,
        ),
        generadoEn: '2026-08-27T12:00:00Z',
        avisoConversion: AVISO_CONVERSION,
        mesMetrica: '2026-08-01',
      }
      : CONVERSION_OPERATIVA === undefined
      ? {
        filas: [],
        equipos: [],
        totalConversion: TOTAL_INDISPONIBLE,
        generadoEn: '2026-08-27T12:00:00Z',
        avisoConversion: AVISO_CONVERSION,
        mesMetrica: '2026-08-01',
      }
      : {
        filas: [{
          m: VENDEDOR,
          activos: 0,
          capitalPEN: 0,
          capitalUSD: 0,
          convertidos: 0,
          cierresConversion: CONVERSION_DISPONIBLE ? 0 : null,
          conversion: CONVERSION_OPERATIVA,
          conversionDisponible: CONVERSION_DISPONIBLE,
          operacionesCartera: CONVERSION_DISPONIBLE ? 4 : null,
          divisorConversion: CONVERSION_DISPONIBLE
            ? CONVERSION_OPERATIVA == null ? 0 : 8
            : null,
          numeradorConversion: CONVERSION_DISPONIBLE
            ? CONVERSION_OPERATIVA == null ? 4 : 11.0104
            : null,
          sinTocar: 0,
          diasSinActividadMax: 0,
        }],
        equipos: [],
        totalConversion: totalConversion(CONVERSION_DISPONIBLE, CONVERSION_OPERATIVA),
        generadoEn: '2026-08-27T12:00:00Z',
        avisoConversion: AVISO_CONVERSION,
        mesMetrica: '2026-08-01',
      },
    cargando: false,
    error: null,
    recargar: vi.fn(),
  }),
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
  CONVERSION_OPERATIVA = undefined
  CONVERSION_EQUIPO_OPERATIVA = undefined
  CONVERSION_DISPONIBLE = true
  CONVERSION_EQUIPO_DISPONIBLE = true
  AVISO_CONVERSION = null
  YO = {
    id: 's-1',
    nombre_completo: 'SUPERVISOR UNO',
    rol: 'supervisor',
    demo: false,
    puede_contratar: false,
  }
})

describe('Equipo — el ranking y la conversión mensual', () => {
  it('mantiene el reparto fuera de Gestión de equipo', () => {
    montar()

    expect(
      screen.queryByRole('heading', { name: 'Por repartir' }),
    ).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Asignar' })).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Cola del equipo' })).toBeInTheDocument()
  })

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

  it('pinta el porcentaje exacto >100 y explica cartera sin una barra capada a 100', () => {
    CONVERSION_OPERATIVA = 137.63
    const { container } = montar()

    expect(screen.getByText(/137\.63% · 4 de cartera/)).toBeInTheDocument()
    expect(screen.queryByText('138%')).not.toBeInTheDocument()
    expect(screen.getByText(/0 cierres \+ 4 de cartera · agosto de 2026/)).toBeInTheDocument()
    // Gestión ya no representa una conversión sin techo con Progress (0–100).
    expect(container.querySelector('[style*="width: 100%"]')).toBeNull()
  })

  it('con porcentaje NULL mantiene la ausencia aunque existan operaciones de cartera', () => {
    CONVERSION_OPERATIVA = null
    montar()

    expect(screen.queryByText('0%')).not.toBeInTheDocument()
    expect(screen.getByText(/0 cierres \+ 4 de cartera · agosto de 2026/)).toBeInTheDocument()
    expect(screen.getByText('Sin divisor mensual')).toBeInTheDocument()
    expect(screen.getAllByText(/4 de cartera/).length).toBeGreaterThan(0)
  })

  it('una fila mensual ausente dice dato no disponible y no inventa divisor, cartera ni causa', () => {
    CONVERSION_OPERATIVA = null
    CONVERSION_DISPONIBLE = false
    montar()

    expect(screen.getByText('Dato no disponible')).toBeInTheDocument()
    expect(screen.getByText(/Cierres no disponibles/)).toBeInTheDocument()
    expect(screen.queryByText('Sin divisor mensual')).not.toBeInTheDocument()
    expect(screen.queryByText(/de cartera/)).not.toBeInTheDocument()
    expect(screen.queryByText('0%')).not.toBeInTheDocument()
  })

  it('la comparativa de equipos conserva >100, decimales y operaciones de cartera', () => {
    CONVERSION_EQUIPO_OPERATIVA = 137.63
    YO = { ...YO!, rol: 'gerencia' }
    const { container } = montar()

    const tabla = screen.getByRole('table', { name: 'Comparativa de supervisores' })
    const fila = within(tabla).getByRole('row', { name: /SUPERVISORA UNO/ })
    expect(fila).toHaveTextContent('137.63% · 4 de cartera')
    expect(fila).not.toHaveTextContent('138%')
    expect(container.querySelector('[style*="width: 100%"]')).toBeNull()
  })

  it('la comparativa de equipos conserva NULL aunque haya cartera', () => {
    CONVERSION_EQUIPO_OPERATIVA = null
    YO = { ...YO!, rol: 'gerencia' }
    montar()

    const tabla = screen.getByRole('table', { name: 'Comparativa de supervisores' })
    const fila = within(tabla).getByRole('row', { name: /SUPERVISORA UNO/ })
    expect(within(fila).getByTitle('Sin divisor mensual')).toHaveTextContent('—')
    expect(fila).toHaveTextContent('4 de cartera')
    expect(fila).not.toHaveTextContent('0%')
  })

  it('un bundle indisponible no se colapsa al vacío «todo en cero»', () => {
    CONVERSION_EQUIPO_OPERATIVA = null
    CONVERSION_EQUIPO_DISPONIBLE = false
    YO = { ...YO!, rol: 'gerencia' }
    montar()

    expect(screen.queryByText('Este equipo aún no tiene leads asignados')).not.toBeInTheDocument()
    const detalle = screen.getByRole('table', {
      name: 'Vendedores del equipo de SUPERVISORA UNO',
    })
    expect(screen.getByText(/Cierres no disponibles/)).toBeInTheDocument()
    expect(detalle).toHaveTextContent('Dato no disponible')
  })

  it('expone el aviso global de cobertura sin convertirlo en un reintento falso', () => {
    CONVERSION_EQUIPO_OPERATIVA = null
    CONVERSION_EQUIPO_DISPONIBLE = false
    AVISO_CONVERSION = 'Cifras en revisión: 1 cierre no tiene episodio verificable.'
    YO = { ...YO!, rol: 'gerencia' }
    montar()

    expect(screen.getByText(AVISO_CONVERSION).closest('[role="status"]')).not.toBeNull()
    expect(screen.queryByRole('button', { name: /Reintentar.*conversión/i })).not.toBeInTheDocument()
  })
})
