// Arnés FOCALIZADO de equipo.tsx: solo el cableado «el fallo de la conversión
// MENSUAL es un error real del ranking» (exigencia pre-release, 2026-08-15).
// El panel completo ya tiene su suite; aquí se prueba que ESTA pantalla le
// pasa el error de SU pestaña — antes un error global degradaba o bloqueaba
// también las lecturas sanas.
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { CUMPLIMIENTO_METAS_DEMO } from '@/lib/demo'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import type { ConversionMensual } from '@/lib/conversion-mensual'
import type { MetricasConversionesEquipo } from '@/lib/metricas-conversiones-equipo'
import { objetivosCero, type CumplimientoMetasJerarquico } from '@/lib/objetivos'
import type { Miembro, Yo } from '@/lib/tipos'

let YO: Yo | null = null
let MENSUAL_FALLA = false
let CONVERSION_MENSUAL_DATA: ConversionMensual | undefined
let COSECHA_DATA: MetricasConversionesEquipo | undefined
let COSECHA_PENDING = false
let COSECHA_FETCHING = false
let CONVERSION_OPERATIVA: number | null | undefined
let CONVERSION_EQUIPO_OPERATIVA: number | null | undefined
let CONVERSION_DISPONIBLE = true
let CONVERSION_EQUIPO_DISPONIBLE = true
let AVISO_CONVERSION: string | null = null
let CUMPLIMIENTO_STORE: CumplimientoMetasJerarquico | null = null
const CONSULTAS_RANKING = vi.hoisted(() => ({
  cierre: vi.fn(),
  conversion: vi.fn(),
  cosecha: vi.fn(),
  cumplimiento: vi.fn(),
  tipoCambio: vi.fn(),
}))
const ESTADO_CUMPLIMIENTO = vi.hoisted(() => ({
  data: undefined as CumplimientoMetasJerarquico | undefined,
  isError: false,
  isPending: false,
  isFetching: false,
  refetch: vi.fn(),
}))
const REFETCH_CONVERSION_MENSUAL = vi.hoisted(() => vi.fn())
const REFETCH_COSECHA = vi.hoisted(() => vi.fn())

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
    cumplimientoMetas: CUMPLIMIENTO_STORE,
    recargar: vi.fn(),
    reasignar: vi.fn(),
    agenda: [],
    tareasDe: () => [],
  }),
  usePanelesActions: () => ({ abrirLead: () => {}, abrirNuevoLead: () => {} }),
}))
vi.mock('@/data/crm-queries', async (importActual) => ({
  ...(await importActual<typeof import('@/data/crm-queries')>()),
  useCierreMesEstado: (habilitada: boolean) => {
    CONSULTAS_RANKING.cierre(habilitada)
    return { data: undefined, isError: false }
  },
  useConversionMensual: (...argumentos: [boolean, string, 'equipo', string | undefined]) => {
    CONSULTAS_RANKING.conversion(...argumentos)
    return {
      data: CONVERSION_MENSUAL_DATA,
      error: MENSUAL_FALLA ? new Error('500 simulado') : null,
      isError: MENSUAL_FALLA,
      isPending: false,
      isFetching: false,
      refetch: REFETCH_CONVERSION_MENSUAL,
    }
  },
  useMetricasConversionesEquipo: (
    ...argumentos: [boolean, string, string, 'equipo', string | undefined]
  ) => {
    CONSULTAS_RANKING.cosecha(...argumentos)
    return {
      data: COSECHA_DATA,
      error: null,
      isError: false,
      isPending: COSECHA_PENDING,
      isFetching: COSECHA_FETCHING,
      refetch: REFETCH_COSECHA,
    }
  },
  useCumplimientoMetas: (...argumentos: [boolean, string, string | null | undefined]) => {
    CONSULTAS_RANKING.cumplimiento(...argumentos)
    return ESTADO_CUMPLIMIENTO
  },
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
  useTipoCambio: (...argumentos: [boolean?, string?]) => {
    CONSULTAS_RANKING.tipoCambio(...argumentos)
    return { tc: null, recargar: vi.fn() }
  },
}))
vi.mock('@/components/common/animated-value', () => ({
  AnimatedValue: ({ value }: { value: string }) => <>{value}</>,
}))
// El panel imprime el error propio de conversión: es exactamente lo que este
// arnés afirma, sin mezclarlo con capital o cosecha.
vi.mock('./hoy/ranking-vendedores', () => ({
  RankingVendedoresPanel: ({
    conversionError,
    capitalError,
    metaMensual,
    metasVendedores,
    cumplimientoVendedores,
    fotoMensualCargando,
    cosechaCargando,
    fotoMensualError,
    onReintentarFotoMensual,
    usarIdentidadSnapshot,
    estadoFotoMensual,
  }: {
    conversionError: string | null
    capitalError: string | null
    metaMensual: { etiqueta: string, comparable: boolean }
    metasVendedores: Record<string, unknown>
    cumplimientoVendedores: Record<string, unknown>
    fotoMensualCargando?: boolean
    cosechaCargando?: boolean
    fotoMensualError?: string | null
    onReintentarFotoMensual?: () => void
    usarIdentidadSnapshot?: boolean
    estadoFotoMensual?: 'sellada' | 'abierta'
  }) => (
    <div>
      <h1>Ranking de mi equipo{fotoMensualError || conversionError || capitalError ? ` · ERROR: ${fotoMensualError ?? conversionError ?? capitalError}` : ''}</h1>
      <output aria-label="Meta del ranking de equipo">{metaMensual.etiqueta}|{String(metaMensual.comparable)}</output>
      <output aria-label="Metas históricas de equipo">{Object.keys(metasVendedores).sort().join(',')}</output>
      <output aria-label="Cumplimiento histórico de equipo">{Object.keys(cumplimientoVendedores).sort().join(',')}</output>
      <output aria-label="Carga mensual de equipo">{String(fotoMensualCargando ?? false)}</output>
      <output aria-label="Carga de cosecha de equipo">{String(cosechaCargando ?? false)}</output>
      <output aria-label="Identidad mensual de equipo">{String(usarIdentidadSnapshot ?? false)}</output>
      <output aria-label="Estado de foto mensual de equipo">{estadoFotoMensual ?? 'vigente'}</output>
      {fotoMensualError && <button type="button" onClick={onReintentarFotoMensual}>Reintentar foto mensual</button>}
    </div>
  ),
}))

const { Equipo } = await import('./equipo')

// Provider mínimo: el mock parcial de crm-queries deja vivos otros hooks de la
// pantalla; aquí degradan a error sin red y este arnés no los mira.
function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <PeriodoGerenciaProvider>
        <Equipo />
      </PeriodoGerenciaProvider>
    </QueryClientProvider>,
  )
}

function fotoMensual(periodo: string, vendedorId: string): CumplimientoMetasJerarquico {
  const fila = Object.values(CUMPLIMIENTO_METAS_DEMO.porVendedor)[0]!
  return {
    ...CUMPLIMIENTO_METAS_DEMO,
    periodo,
    porVendedor: {
      [vendedorId]: { ...fila, vendedorId },
    },
  }
}

function cosechaMensual(
  desde: string,
  hasta: string,
  over: Partial<MetricasConversionesEquipo> = {},
): MetricasConversionesEquipo {
  return {
    version: 1,
    generado_en: `${hasta}T15:00:00Z`,
    alcance: 'equipo',
    periodo: { desde, hasta },
    responsables: [],
    ...over,
  }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-09-02T15:00:00Z'))
  MENSUAL_FALLA = false
  CONVERSION_MENSUAL_DATA = undefined
  COSECHA_DATA = undefined
  COSECHA_PENDING = false
  COSECHA_FETCHING = false
  CONVERSION_OPERATIVA = undefined
  CONVERSION_EQUIPO_OPERATIVA = undefined
  CONVERSION_DISPONIBLE = true
  CONVERSION_EQUIPO_DISPONIBLE = true
  AVISO_CONVERSION = null
  CUMPLIMIENTO_STORE = null
  YO = {
    id: 's-1',
    nombre_completo: 'SUPERVISOR UNO',
    rol: 'supervisor',
    demo: false,
    puede_contratar: false,
  }
  ESTADO_CUMPLIMIENTO.data = undefined
  ESTADO_CUMPLIMIENTO.isError = false
  ESTADO_CUMPLIMIENTO.isPending = false
  ESTADO_CUMPLIMIENTO.isFetching = false
  ESTADO_CUMPLIMIENTO.refetch.mockReset()
  REFETCH_CONVERSION_MENSUAL.mockReset()
  REFETCH_COSECHA.mockReset()
  vi.clearAllMocks()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Equipo — el ranking y la conversión mensual', () => {
  it('mantiene activo el observador de cierre sin mostrar el banner de Gerencia', () => {
    CONVERSION_EQUIPO_OPERATIVA = 12
    montar()

    expect(CONSULTAS_RANKING.cierre).toHaveBeenLastCalledWith(true)
  })

  it('permite al supervisor elegir agosto y alinea los tres núcleos mensuales', () => {
    ESTADO_CUMPLIMIENTO.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-09-01',
    }
    CONVERSION_MENSUAL_DATA = {
      ...conversionMensualDemo(Date.parse('2026-09-02T15:00:00Z'), {
        alcance: 'equipo',
        actorId: 's-1',
      }),
      revision: 1,
      cierre: { cerrado: false },
    }
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02', {
      revision: 1,
      cierre: { cerrado: false },
    })
    montar()

    const selector = screen.getByLabelText('Mes del ranking')
    expect(selector).toHaveValue('2026-09')
    expect(selector).toHaveAttribute('max', '2026-09')

    ESTADO_CUMPLIMIENTO.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-08-01',
      cierre: { cerrado: false },
    }
    CONVERSION_MENSUAL_DATA = {
      ...conversionMensualDemo(Date.parse('2026-08-15T15:00:00Z'), {
        alcance: 'equipo',
        actorId: 's-1',
      }),
      revision: 1,
      cierre: { cerrado: false },
    }
    COSECHA_DATA = cosechaMensual('2026-08-01', '2026-08-31', {
      revision: 1,
      cierre: { cerrado: false },
    })
    fireEvent.change(selector, { target: { value: '2026-08' } })

    expect(CONSULTAS_RANKING.conversion).toHaveBeenLastCalledWith(true, '2026-08-01', 'equipo', 's-1')
    expect(CONSULTAS_RANKING.cosecha).toHaveBeenLastCalledWith(
      true, '2026-08-01', '2026-08-31', 'equipo', 's-1',
    )
    expect(CONSULTAS_RANKING.cumplimiento).toHaveBeenLastCalledWith(true, '2026-08-01', 's-1')
    expect(CONSULTAS_RANKING.tipoCambio).toHaveBeenLastCalledWith(true, '2026-08-31')
    expect(screen.getByLabelText('Meta del ranking de equipo')).toHaveTextContent('agosto 2026|true')
    expect(screen.getByLabelText('Metas históricas de equipo')).toHaveTextContent('d-v1,d-v2,d-v3')
    expect(screen.getByLabelText('Cumplimiento histórico de equipo')).toHaveTextContent('d-v1,d-v2,d-v3')
    expect(screen.getByLabelText('Carga mensual de equipo')).toHaveTextContent('false')
    expect(screen.getByLabelText('Identidad mensual de equipo')).toHaveTextContent('true')
    expect(screen.getByLabelText('Estado de foto mensual de equipo')).toHaveTextContent('abierta')
    expect(screen.queryByText(/ERROR:/)).not.toBeInTheDocument()
  })

  it('tolera el backend anterior solo mientras conversión y Cosecha omiten juntos los tokens', () => {
    CONVERSION_MENSUAL_DATA = conversionMensualDemo(
      Date.parse('2026-09-02T15:00:00Z'),
      { alcance: 'equipo', actorId: 's-1' },
    )
    ESTADO_CUMPLIMIENTO.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-09-01',
    }
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02')

    montar()

    expect(screen.queryByText(/ERROR:/)).not.toBeInTheDocument()
  })

  it('falla cerrado si el rollout publica tokens solo en uno de los dos productores nuevos', () => {
    CONVERSION_MENSUAL_DATA = conversionMensualDemo(
      Date.parse('2026-09-02T15:00:00Z'),
      { alcance: 'equipo', actorId: 's-1' },
    )
    ESTADO_CUMPLIMIENTO.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-09-01',
    }
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02', {
      revision: 1,
      cierre: { cerrado: false },
    })

    montar()

    expect(screen.getByRole('heading', { name: /Ranking de mi equipo · ERROR/ }))
      .toHaveTextContent('mismo mes, revisión o estado de cierre')
  })

  it('avanza el corte vigente al cruzar la medianoche de Lima', () => {
    vi.setSystemTime(new Date('2026-09-03T04:59:59Z'))
    montar()

    expect(CONSULTAS_RANKING.conversion).toHaveBeenLastCalledWith(true, '2026-09-01', 'equipo', 's-1')
    expect(CONSULTAS_RANKING.cosecha).toHaveBeenLastCalledWith(
      true, '2026-09-01', '2026-09-02', 'equipo', 's-1',
    )

    act(() => { vi.advanceTimersByTime(1_000) })

    expect(CONSULTAS_RANKING.cosecha).toHaveBeenLastCalledWith(
      true, '2026-09-01', '2026-09-03', 'equipo', 's-1',
    )
  })

  it('al cruzar de mes pide la foto nueva y nunca reutiliza el cumplimiento anterior del store', () => {
    vi.setSystemTime(new Date('2026-09-01T04:59:59Z'))
    CUMPLIMIENTO_STORE = fotoMensual('2026-08-01', 'store-agosto')
    ESTADO_CUMPLIMIENTO.data = fotoMensual('2026-08-01', 'foto-agosto')
    montar()

    expect(CONSULTAS_RANKING.cumplimiento).toHaveBeenLastCalledWith(true, '2026-08-01', 's-1')
    expect(screen.getByLabelText('Metas históricas de equipo')).toHaveTextContent('foto-agosto')
    expect(screen.getByLabelText('Metas históricas de equipo')).not.toHaveTextContent('store-agosto')
    expect(screen.getByLabelText('Identidad mensual de equipo')).toHaveTextContent('false')

    ESTADO_CUMPLIMIENTO.data = fotoMensual('2026-09-01', 'foto-setiembre')
    act(() => { vi.advanceTimersByTime(1_000) })

    expect(CONSULTAS_RANKING.cumplimiento).toHaveBeenLastCalledWith(true, '2026-09-01', 's-1')
    expect(screen.getByLabelText('Meta del ranking de equipo')).toHaveTextContent('setiembre 2026|true')
    expect(screen.getByLabelText('Metas históricas de equipo')).toHaveTextContent('foto-setiembre')
    expect(screen.getByLabelText('Metas históricas de equipo')).not.toHaveTextContent('store-agosto')
    expect(screen.getByLabelText('Identidad mensual de equipo')).toHaveTextContent('false')
    expect(CONSULTAS_RANKING.tipoCambio.mock.calls).toContainEqual([])
  })

  it('rechaza un mes futuro aunque el input se manipule fuera del navegador', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Mes del ranking'), { target: { value: '2026-10' } })

    expect(screen.getByLabelText('Mes del ranking')).toHaveValue('2026-09')
    expect(CONSULTAS_RANKING.conversion).toHaveBeenLastCalledWith(true, '2026-09-01', 'equipo', 's-1')
    expect(CONSULTAS_RANKING.cosecha).toHaveBeenLastCalledWith(
      true, '2026-09-01', '2026-09-02', 'equipo', 's-1',
    )
  })

  it('en demo fija el ranking al mes vigente y no fabrica un histórico', () => {
    YO = { ...YO!, demo: true }
    montar()

    const selector = screen.getByLabelText('Mes del ranking')
    expect(selector).toBeDisabled()
    expect(selector).toHaveValue('2026-09')
    expect(screen.getByText('Demo · mes vigente')).toBeInTheDocument()
    expect(screen.getByLabelText('Meta del ranking de equipo')).toHaveTextContent('setiembre 2026|true')
    expect(CONSULTAS_RANKING.conversion).toHaveBeenLastCalledWith(false, '2026-09-01', 'equipo', 's-1')
    expect(CONSULTAS_RANKING.cosecha).toHaveBeenLastCalledWith(
      false, '2026-09-01', '2026-09-02', 'equipo', 's-1',
    )
    expect(CONSULTAS_RANKING.cumplimiento).toHaveBeenLastCalledWith(false, '2026-09-01', 's-1')
    expect(CONSULTAS_RANKING.tipoCambio).toHaveBeenLastCalledWith(false, '2026-09-02')
    expect(screen.getByLabelText('Identidad mensual de equipo')).toHaveTextContent('false')

    fireEvent.change(selector, { target: { value: '2026-08' } })
    expect(selector).toHaveValue('2026-09')
  })

  it('no presenta ceros mientras carga el mes histórico', () => {
    ESTADO_CUMPLIMIENTO.isPending = true
    montar()

    fireEvent.change(screen.getByLabelText('Mes del ranking'), { target: { value: '2026-08' } })

    expect(screen.getByLabelText('Carga mensual de equipo')).toHaveTextContent('true')
    expect(screen.getByLabelText('Metas históricas de equipo')).toBeEmptyDOMElement()
    expect(screen.getByLabelText('Cumplimiento histórico de equipo')).toBeEmptyDOMElement()
  })

  it('conserva la cosecha visible mientras la refresca en segundo plano', () => {
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02')
    COSECHA_FETCHING = true
    montar()

    expect(screen.getByLabelText('Carga de cosecha de equipo')).toHaveTextContent('false')
  })

  it('oculta la cosecha cacheada mientras refresca un mes histórico', () => {
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02')
    COSECHA_FETCHING = true
    montar()

    fireEvent.change(screen.getByLabelText('Mes del ranking'), { target: { value: '2026-08' } })

    expect(screen.getByLabelText('Carga de cosecha de equipo')).toHaveTextContent('true')
  })

  it('si falla la foto mensual entrega un error global, también en el mes vigente', () => {
    ESTADO_CUMPLIMIENTO.isError = true
    montar()

    expect(screen.getByText(/ERROR: No se pudieron cargar la identidad, las metas y el capital del mes elegido\./)).toBeInTheDocument()
    expect(screen.getByLabelText('Meta del ranking de equipo')).toHaveTextContent('setiembre 2026|false')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar foto mensual' }))
    expect(REFETCH_CONVERSION_MENSUAL).toHaveBeenCalledTimes(1)
    expect(ESTADO_CUMPLIMIENTO.refetch).toHaveBeenCalledTimes(1)
    expect(REFETCH_COSECHA).toHaveBeenCalledTimes(1)
  })

  it('bloquea revisiones mezcladas y reintenta conversión, cumplimiento y Cosecha', () => {
    CONVERSION_MENSUAL_DATA = {
      ...conversionMensualDemo(Date.parse('2026-09-02T15:00:00Z'), {
        alcance: 'equipo',
        actorId: 's-1',
      }),
      revision: 7,
      cierre: { cerrado: false },
    }
    ESTADO_CUMPLIMIENTO.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-09-01',
      revision: 8,
      cierre: { cerrado: false },
    }
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02', {
      revision: 7,
      cierre: { cerrado: false },
    })
    montar()

    expect(screen.getByRole('heading', { name: /Ranking de mi equipo · ERROR/ }))
      .toHaveTextContent('mismo mes, revisión o estado de cierre')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar foto mensual' }))
    expect(REFETCH_CONVERSION_MENSUAL).toHaveBeenCalledTimes(1)
    expect(ESTADO_CUMPLIMIENTO.refetch).toHaveBeenCalledTimes(1)
    expect(REFETCH_COSECHA).toHaveBeenCalledTimes(1)
  })

  it('bloquea una Cosecha con otro estado de cierre aunque mes y revisión coincidan', () => {
    CONVERSION_MENSUAL_DATA = {
      ...conversionMensualDemo(Date.parse('2026-09-02T15:00:00Z'), {
        alcance: 'equipo',
        actorId: 's-1',
      }),
      revision: 7,
      cierre: { cerrado: false },
    }
    ESTADO_CUMPLIMIENTO.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-09-01',
      revision: 7,
      cierre: { cerrado: false },
    }
    COSECHA_DATA = cosechaMensual('2026-09-01', '2026-09-02', {
      revision: 7,
      cierre: { cerrado: true },
    })
    montar()

    expect(screen.getByRole('heading', { name: /Ranking de mi equipo · ERROR/ }))
      .toHaveTextContent('mismo mes, revisión o estado de cierre')
  })

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
      name: 'Analistas del equipo de SUPERVISORA UNO',
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
