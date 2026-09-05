// Tests de integración de la pantalla "Hoy · gerencia" y sus metas mensuales.
// Monto y conversión son las dos únicas metas visibles.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { useState, type ReactNode } from 'react'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { CUMPLIMIENTO_METAS_DEMO, METAS_DEMO } from '@/lib/demo'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import type { MetricasConversionesEquipo } from '@/lib/metricas-conversiones-equipo'
import {
  objetivosCero,
  type CumplimientoMetasJerarquico,
  type ObjetivoComercial,
  type ObjetivosPorRol,
} from '@/lib/objetivos'
import type { Lead, Miembro, Yo } from '@/lib/tipos'
import type { AsientoReconocimiento } from '@/lib/reconocimientos-alertas'
import type { SeccionGerencia } from './gerencia'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const MIERCOLES_10AM = new Date('2026-07-15T15:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let EQUIPO: Miembro[] = []
let ASIENTOS_TRAZA: AsientoReconocimiento[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero()
let OBJETIVOS_ERROR = false
let CUMPLIMIENTO: CumplimientoMetasJerarquico | null = null
let CUMPLIMIENTO_ERROR = false
const RECARGAR = vi.fn(async () => true)
const RECARGAR_TC = vi.fn()
const CONSULTAS = vi.hoisted(() => ({
  conversiones: vi.fn(),
  conversionMensual: vi.fn(),
  cumplimiento: vi.fn(),
  cosecha: vi.fn(),
  reuniones: vi.fn(),
  distribucion: vi.fn(),
  tipoCambio: vi.fn(),
}))
const ESTADO_CONVERSIONES = vi.hoisted(() => ({
  data: undefined as unknown,
  error: null as unknown,
  isPending: false,
  isFetching: false,
  refetch: vi.fn(),
}))
const ESTADO_CUMPLIMIENTO_RANKING = vi.hoisted(() => ({
  data: undefined as CumplimientoMetasJerarquico | undefined,
  error: null as unknown,
  isError: false,
  isPending: false,
  isFetching: false,
  refetch: vi.fn(),
}))
const ESTADO_COSECHA_RANKING = vi.hoisted(() => ({
  data: undefined as MetricasConversionesEquipo | undefined,
  error: null as unknown,
  isError: false,
  isPending: false,
  isFetching: false,
  refetch: vi.fn(),
}))
const REFETCH_CONVERSION_MENSUAL = vi.hoisted(() => vi.fn())

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: {
      leads: LEADS,
      vendedores: EQUIPO.filter((miembro) => miembro.rol_crm === 'vendedor'),
      esGlobal: true,
    },
    equipo: EQUIPO,
    objetivos: OBJETIVOS,
    objetivosError: OBJETIVOS_ERROR,
    cumplimientoMetas: CUMPLIMIENTO,
    cumplimientoMetasError: CUMPLIMIENTO_ERROR,
    recargar: RECARGAR,
  }),
}))
// Paneles que viven de RPCs (TanStack) o de Recharts: fuera, no son lo que se
// prueba aquí y montarlos exigiría un QueryClient y el bundle de gráficas.
vi.mock('./distribucion-leads-gerencia', () => ({ DistribucionLeadsGerencia: () => null }))
vi.mock('./inteligencia-comercial', () => ({
  InteligenciaComercialPanel: ({
    conversionMensual,
    equipo,
    equipoMensual,
    mensualError,
    rangoError,
    mensualCargando,
    rangoCargando,
    metaMensual,
    metaConversion,
    modoDemo,
    puedeAlternarEjemplo,
    onAlternarEjemplo,
    onReintentarMensual,
    onReintentarRango,
  }: {
    conversionMensual: { periodo?: { mes?: string } } | null | undefined
    equipo: Array<{ vendedorId?: string | null }>
    equipoMensual?: Array<{ vendedorId?: string | null }>
    mensualError: string | null
    rangoError: string | null
    mensualCargando: boolean
    rangoCargando: boolean
    metaMensual: { etiqueta: string; errorCarga?: boolean }
    metaConversion: number
    modoDemo: boolean
    puedeAlternarEjemplo: boolean
    onAlternarEjemplo: () => void
    onReintentarMensual: () => void
    onReintentarRango: () => void
  }) => (
    <div>
      <h1>Inteligencia comercial</h1>
      <output aria-label="Error mensual de Conversiones">{mensualError ? `ERROR: ${mensualError}` : ''}</output>
      <output aria-label="Error de rango en Conversiones">{rangoError ? `ERROR: ${rangoError}` : ''}</output>
      <output aria-label="Carga mensual de Conversiones">{String(mensualCargando)}</output>
      <output aria-label="Dato mensual de Conversiones">{conversionMensual === undefined ? 'esperando' : 'recibido'}</output>
      <output aria-label="Período mensual de Conversiones">{conversionMensual?.periodo?.mes ?? ''}</output>
      <output aria-label="Población de rango en Conversiones">{equipo.map((fila) => fila.vendedorId).join(',')}</output>
      <output aria-label="Población mensual en Conversiones">{(equipoMensual ?? equipo).map((fila) => fila.vendedorId).join(',')}</output>
      <output aria-label="Carga de rango en Conversiones">{String(rangoCargando)}</output>
      <output aria-label="Meta mensual de Conversiones">{metaMensual.etiqueta}|{metaMensual.errorCarga ? 'error' : 'ok'}|{metaConversion}</output>
      <output aria-label="Modo de Conversiones">{modoDemo ? 'ejemplo' : 'real'}</output>
      {puedeAlternarEjemplo && <button type="button" onClick={onAlternarEjemplo}>Ver ejemplo</button>}
      {mensualError && <button type="button" onClick={onReintentarMensual}>Reintentar mensual</button>}
      {rangoError && <button type="button" onClick={onReintentarRango}>Reintentar rango</button>}
    </div>
  ),
}))
vi.mock('./ranking-vendedores', () => ({
  RankingVendedoresPanel: ({
    conversionError,
    capitalError,
    cosechaError,
    metaMensual,
    metasVendedores,
    cumplimientoVendedores,
    fotoMensualCargando,
    fotoMensualError,
    onReintentarFotoMensual,
    usarIdentidadSnapshot,
    estadoFotoMensual,
    etiquetaAlcance,
  }: {
    conversionError: string | null
    capitalError: string | null
    cosechaError: string | null
    metaMensual: { etiqueta: string, comparable: boolean }
    metasVendedores: Record<string, unknown>
    cumplimientoVendedores: Record<string, unknown>
    fotoMensualCargando?: boolean
    fotoMensualError?: string | null
    onReintentarFotoMensual?: () => void
    usarIdentidadSnapshot?: boolean
    estadoFotoMensual?: 'sellada' | 'abierta'
    etiquetaAlcance?: string
  }) => (
    <div>
      <h1>Ranking de analistas{fotoMensualError || conversionError || capitalError || cosechaError ? ` · ERROR: ${fotoMensualError ?? conversionError ?? capitalError ?? cosechaError}` : ''}</h1>
      <output aria-label="Meta del ranking">{metaMensual.etiqueta}|{String(metaMensual.comparable)}</output>
      <output aria-label="Metas del ranking">{Object.keys(metasVendedores).sort().join(',')}</output>
      <output aria-label="Cumplimiento del ranking">{Object.keys(cumplimientoVendedores).sort().join(',')}</output>
      <output aria-label="Carga de foto mensual">{String(fotoMensualCargando ?? false)}</output>
      <output aria-label="Identidad mensual">{String(usarIdentidadSnapshot ?? false)}</output>
      <output aria-label="Estado de foto mensual">{estadoFotoMensual ?? 'vigente'}</output>
      <output aria-label="Alcance del ranking">{etiquetaAlcance ?? 'Equipo completo'}</output>
      {fotoMensualError && <button type="button" onClick={onReintentarFotoMensual}>Reintentar foto mensual</button>}
    </div>
  ),
}))
// El TC real invocaría la edge crm-tipo-cambio desde el hook; en tests queda
// hermético en null (la pantalla solo lo reenvía al panel, que aquí está
// mockeado). importOriginal conserva usdAPen/promedioSemanal: la lib pura
// conversion-vendedores los importa de este módulo (hallazgo de la verificación).
// Mutable a propósito: con `tc: null` fijo, `totalEnSoles` degradaba a
// «solo_pen» y el consolidado —el cambio central de esta pantalla— no se
// ejecutaba NUNCA en su rama normal. El fixture da S/ 650,000 sin TC y
// S/ 961,500 con TC 3.5: 311.500 soles que ningún test habría echado en falta.
const TIPO_CAMBIO: { tc: { promedio: number, fuente: string } | null | undefined } = {
  tc: { promedio: 3.5, fuente: 'BCRP · prom. 7d' },
}
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
  useTipoCambio: (...argumentos: [boolean?, string?]) => {
    CONSULTAS.tipoCambio(...argumentos)
    return { tc: TIPO_CAMBIO.tc, recargar: RECARGAR_TC }
  },
}))
vi.mock('./reuniones-gerencia', () => ({ ReunionesGerenciaPanel: () => null }))
vi.mock('./resumen-gerencia', () => ({
  ResumenGerenciaPanel: ({ error, mensualCargando, onReintentar }: { error: string | null; mensualCargando?: boolean; onReintentar: () => void }) => (
    <div>
      <h1>Resumen comercial{error ? ` · ERROR: ${error}` : ''}</h1>
      <output aria-label="Carga mensual del Resumen">{String(mensualCargando ?? false)}</output>
      <button type="button" onClick={onReintentar}>Reintentar fuentes del Resumen</button>
    </div>
  ),
}))
vi.mock('./equipo-gerencia', () => ({ EquipoGerenciaPanel: () => null }))
vi.mock('./graficas-gerencia', () => ({ GraficasGerencia: () => null }))
vi.mock('./metas-editor', () => ({ MetasEditor: () => <div>Editor de metas</div> }))
vi.mock('@/components/gerencia/motion', () => ({
  GerenciaMotion: ({ children }: { children: ReactNode }) => <>{children}</>,
}))
// La conversión mensual (la definición), controlable por test.
let CONVERSION_MENSUAL: import('@/lib/conversion-mensual').ConversionMensual | null = null
let CONVERSION_MENSUAL_FALLA = false
let CONVERSION_MENSUAL_FETCHING = false
vi.mock('@/data/crm-queries', () => ({
  // El aviso del ciclo no se prueba aquí (tiene su propio test): sin datos,
  // el banner simplemente no existe.
  useCierreMesEstado: () => ({ data: undefined, isError: false }),
  // La traza de compromisos (F4.4) tiene su test propio; aquí un knob mínimo
  // para el ORÁCULO del cableado (que el panel está en el Resumen y recibe
  // el roster de verdad).
  useReconocimientosAlertas: () => ({
    data: ASIENTOS_TRAZA,
    error: null,
    isPending: false,
    refetch: vi.fn(),
  }),
  // La V3 vive en crm-queries desde la mudanza de F3 (capa de datos): mismo
  // doble — la pantalla solo necesita el contrato del hook, no la red.
  useMetricasDistribucionLeadsV3: (...argumentos: [boolean, string, string]) => {
    CONSULTAS.distribucion(...argumentos)
    return { data: undefined, error: null, isPending: false, isFetching: false, refetch: () => {} }
  },
  // Cosecha del ranking (F2.2/D2): mismo doble sin red; sus casos de pintura
  // viven en ranking-vendedores.test.tsx.
  useMetricasConversionesEquipo: (...argumentos: [boolean, string, string, 'global', string?]) => {
    CONSULTAS.cosecha(...argumentos)
    return ESTADO_COSECHA_RANKING
  },
  useConversionMensual: (...argumentos: [boolean, string, 'global', string?]) => {
    CONSULTAS.conversionMensual(...argumentos)
    return {
    data: CONVERSION_MENSUAL_FALLA ? undefined : (CONVERSION_MENSUAL ?? undefined),
    error: CONVERSION_MENSUAL_FALLA ? new Error('500 simulado') : null,
    isError: CONVERSION_MENSUAL_FALLA,
    isPending: false,
    isFetching: CONVERSION_MENSUAL_FETCHING,
    refetch: REFETCH_CONVERSION_MENSUAL,
    }
  },
  useCumplimientoMetas: (...argumentos: [boolean, string, string | null | undefined]) => {
    CONSULTAS.cumplimiento(...argumentos)
    return ESTADO_CUMPLIMIENTO_RANKING
  },
  useMetricasDistribucionLeads: (...argumentos: [boolean, string, string]) => {
    CONSULTAS.distribucion(...argumentos)
    return { data: undefined, error: null, isPending: false, isFetching: false, refetch: () => {} }
  },
  useMetricasConversiones: (...argumentos: [boolean, string, string, string | null]) => {
    CONSULTAS.conversiones(...argumentos)
    return ESTADO_CONVERSIONES
  },
  useMetricasReuniones: (...argumentos: [boolean, string, string]) => {
    CONSULTAS.reuniones(...argumentos)
    return { data: undefined, error: null, isPending: false, isFetching: false, refetch: () => {} }
  },
  // Altas nuevas por analista (F7, sustituto del reporte viejo): tiene su
  // propio test; aquí un vacío honesto para que el panel monte sin red.
  useAltasNuevasPorAnalista: () => ({ data: [], isPending: false, isError: false, refetch: () => {} }),
  useActualizarCapacidadLeadsObjetivo: () => ({ mutateAsync: async () => {} }),
  // Sin cierres en coops: el bloque «Por empresa» se oculta y no toca la suite.
  useCierresExternos: () => ({
    data: undefined,
    isError: false,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
}))
// crm-api arrastra el cliente de Supabase al importarse.
vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))

const { HoyGerencia } = await import('./gerencia')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'l-1',
    nombre_completo: 'ANA TORRES',
    telefono: '+51987654321',
    etapa: 'contactado',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-07-01T15:00:00Z',
    activo: true,
    ...over,
  }
}

function montar(
  over: {
    leads?: Lead[]
    objetivos?: ObjetivoComercial
    periodoObjetivos?: string
    objetivosError?: boolean
    cumplimiento?: CumplimientoMetasJerarquico | null
    cumplimientoError?: boolean
    demo?: boolean
  } = {},
  seccion: SeccionGerencia = 'completo',
  ahora: Date = MIERCOLES_10AM,
): ReturnType<typeof render> {
  vi.setSystemTime(ahora)
  YO = {
    id: 'g-1',
    nombre_completo: 'GERENCIA UNO',
    rol: 'gerencia',
    demo: over.demo ?? false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  OBJETIVOS_ERROR = over.objetivosError ?? false
  CUMPLIMIENTO_ERROR = over.cumplimientoError ?? false
  OBJETIVOS = {
    ...METAS_DEMO,
    periodo: over.periodoObjetivos ?? '2026-07-01',
    gerencia: over.objetivos ?? METAS_DEMO.gerencia,
  }
  CUMPLIMIENTO = over.cumplimiento == null
    ? (over.cumplimiento ?? null)
    : { ...over.cumplimiento, periodo: OBJETIVOS.periodo }
  if (over.cumplimiento !== undefined
    && ESTADO_CUMPLIMIENTO_RANKING.data === undefined
    && !ESTADO_CUMPLIMIENTO_RANKING.isPending
    && !ESTADO_CUMPLIMIENTO_RANKING.isError) {
    ESTADO_CUMPLIMIENTO_RANKING.data = over.cumplimiento ?? undefined
  }
  return render(<PeriodoGerenciaProvider><HoyGerencia seccion={seccion} /></PeriodoGerenciaProvider>)
}

/** La tarjeta del marcador mensual (hay muchos números sueltos en la pantalla). */
function tarjetaMeta(): HTMLElement {
  const titulo = screen.getByRole('heading', { name: 'Metas mensuales' })
  const tarjeta = titulo.closest('[data-slot="card"]')
  if (!(tarjeta instanceof HTMLElement)) throw new Error('no se encontró la tarjeta de meta')
  return tarjeta
}

beforeEach(() => {
  TIPO_CAMBIO.tc = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
  vi.useFakeTimers()
  vi.clearAllMocks()
  RECARGAR.mockResolvedValue(true)
  OBJETIVOS_ERROR = false
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  CONVERSION_MENSUAL = null
  CONVERSION_MENSUAL_FALLA = false
  CONVERSION_MENSUAL_FETCHING = false
  EQUIPO = []
  ASIENTOS_TRAZA = []
  ESTADO_CONVERSIONES.data = undefined
  ESTADO_CONVERSIONES.error = null
  ESTADO_CONVERSIONES.isPending = false
  ESTADO_CONVERSIONES.isFetching = false
  ESTADO_CONVERSIONES.refetch.mockReset()
  ESTADO_CUMPLIMIENTO_RANKING.data = undefined
  ESTADO_CUMPLIMIENTO_RANKING.error = null
  ESTADO_CUMPLIMIENTO_RANKING.isError = false
  ESTADO_CUMPLIMIENTO_RANKING.isPending = false
  ESTADO_CUMPLIMIENTO_RANKING.isFetching = false
  ESTADO_CUMPLIMIENTO_RANKING.refetch.mockReset()
  ESTADO_COSECHA_RANKING.data = undefined
  ESTADO_COSECHA_RANKING.error = null
  ESTADO_COSECHA_RANKING.isError = false
  ESTADO_COSECHA_RANKING.isPending = false
  ESTADO_COSECHA_RANKING.isFetching = false
  ESTADO_COSECHA_RANKING.refetch.mockReset()
  REFETCH_CONVERSION_MENSUAL.mockReset()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Hoy · gerencia — compromisos de supervisores (F4.4)', () => {
  const asientoTraza: AsientoReconocimiento = {
    id: '00000000-0000-4000-8000-0000000000f4',
    alerta_id: 'grupo:por_repartir:s-77',
    accion: 'reconocer',
    miembros: ['l1', 'l2'],
    severidad: 'critica',
    hasta: null,
    creado_en: '2026-07-15T13:00:00Z',
    secuencia: 1,
  }

  it('el Resumen monta la tarjeta y le llega el ROSTER (el nombre del supervisor se ve)', () => {
    EQUIPO = [{
      perfil_id: 's-77',
      nombre_completo: 'SUPERVISOR SETENTA',
      rol_crm: 'supervisor',
      supervisor_id: null,
      activo: true,
    } as unknown as Miembro]
    ASIENTOS_TRAZA = [asientoTraza]
    montar({}, 'completo')

    expect(screen.getByRole('heading', { name: 'Compromisos de supervisores' })).toBeInTheDocument()
    expect(screen.getByRole('listitem')).toHaveTextContent('SUPERVISOR SETENTA reconoció «Leads esperando reparto» (2 leads)')
  })

  it('fuera del Resumen la tarjeta NO se monta', () => {
    ASIENTOS_TRAZA = [asientoTraza]
    montar({}, 'conversiones')
    expect(screen.queryByRole('heading', { name: 'Compromisos de supervisores' })).not.toBeInTheDocument()
  })
})

describe('Hoy · gerencia — ranking por mes calendario', () => {
  const SETIEMBRE_2 = new Date('2026-09-02T15:00:00Z')

  it('al elegir agosto alinea conversión, cosecha, meta y capital con todo agosto', () => {
    ESTADO_CUMPLIMIENTO_RANKING.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-08-01',
      cierre: { cerrado: true, cerrado_en: '2026-09-10T14:20:00Z', automatico: true },
    }
    montar({}, 'ranking-vendedores', SETIEMBRE_2)

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-08' } })

    expect(CONSULTAS.conversionMensual).toHaveBeenLastCalledWith(true, '2026-08-01', 'global', 'g-1')
    expect(CONSULTAS.cosecha).toHaveBeenLastCalledWith(true, '2026-08-01', '2026-08-31', 'global', 'g-1')
    expect(CONSULTAS.cumplimiento).toHaveBeenLastCalledWith(true, '2026-08-01', 'g-1')
    expect(CONSULTAS.tipoCambio).toHaveBeenLastCalledWith(true, '2026-08-31')
    expect(screen.getByLabelText('Meta del ranking')).toHaveTextContent('agosto 2026|true')
    expect(screen.getByLabelText('Metas del ranking')).toHaveTextContent('d-v1,d-v2,d-v3')
    expect(screen.getByLabelText('Cumplimiento del ranking')).toHaveTextContent('d-v1,d-v2,d-v3')
    expect(screen.getByLabelText('Carga de foto mensual')).toHaveTextContent('false')
    expect(screen.getByLabelText('Identidad mensual')).toHaveTextContent('true')
    expect(screen.getByLabelText('Estado de foto mensual')).toHaveTextContent('sellada')
  })

  it('mantiene las tres lecturas en carga mientras llega la foto histórica', () => {
    ESTADO_CUMPLIMIENTO_RANKING.isPending = true
    montar({}, 'ranking-vendedores', SETIEMBRE_2)

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-08' } })

    expect(screen.getByLabelText('Carga de foto mensual')).toHaveTextContent('true')
    expect(screen.getByLabelText('Metas del ranking')).toBeEmptyDOMElement()
    expect(screen.getByLabelText('Cumplimiento del ranking')).toBeEmptyDOMElement()
  })

  it('rechaza meses futuros o inválidos aunque el input se manipule fuera del navegador', () => {
    montar({}, 'ranking-vendedores', SETIEMBRE_2)

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-10' } })
    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-13' } })

    expect(screen.getByLabelText('Mes calendario')).toHaveValue('2026-09')
    expect(CONSULTAS.conversionMensual).toHaveBeenLastCalledWith(true, '2026-09-01', 'global', 'g-1')
    expect(CONSULTAS.cosecha).toHaveBeenLastCalledWith(true, '2026-09-01', '2026-09-02', 'global', 'g-1')
  })

  it('en demo mantiene el ranking en el mes vigente aunque el filtro global apunte a agosto', () => {
    montar({ demo: true }, 'ranking-vendedores', SETIEMBRE_2)

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-08' } })

    expect(CONSULTAS.conversionMensual).toHaveBeenLastCalledWith(false, '2026-09-01', 'global', 'g-1')
    expect(CONSULTAS.cosecha).toHaveBeenLastCalledWith(false, '2026-09-01', '2026-09-02', 'global', 'g-1')
    expect(CONSULTAS.cumplimiento).toHaveBeenLastCalledWith(false, '2026-09-01', 'g-1')
    expect(CONSULTAS.tipoCambio).toHaveBeenLastCalledWith(true, undefined)
    expect(screen.getByLabelText('Meta del ranking')).toHaveTextContent('setiembre 2026|true')
    expect(screen.getByLabelText('Alcance del ranking')).toHaveTextContent('Demo · mes vigente')
    expect(screen.getByLabelText('Identidad mensual')).toHaveTextContent('false')
  })

  it('consulta también la foto del mes vigente y no reutiliza el store del mes anterior', () => {
    const fila = Object.values(CUMPLIMIENTO_METAS_DEMO.porVendedor)[0]!
    const foto = (periodo: string, vendedorId: string): CumplimientoMetasJerarquico => ({
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo,
      porVendedor: {
        [vendedorId]: { ...fila, vendedorId },
      },
    })
    ESTADO_CUMPLIMIENTO_RANKING.data = foto('2026-08-01', 'foto-agosto')
    montar(
      { cumplimiento: foto('2026-08-01', 'store-agosto') },
      'ranking-vendedores',
      new Date('2026-09-01T04:59:59Z'),
    )

    expect(CONSULTAS.cumplimiento).toHaveBeenLastCalledWith(true, '2026-08-01', 'g-1')
    expect(screen.getByLabelText('Metas del ranking')).toHaveTextContent('foto-agosto')
    expect(screen.getByLabelText('Metas del ranking')).not.toHaveTextContent('store-agosto')
    expect(screen.getByLabelText('Identidad mensual')).toHaveTextContent('false')

    ESTADO_CUMPLIMIENTO_RANKING.data = foto('2026-09-01', 'foto-setiembre')
    act(() => { vi.advanceTimersByTime(1_000) })

    expect(CONSULTAS.cumplimiento).toHaveBeenLastCalledWith(true, '2026-09-01', 'g-1')
    expect(screen.getByLabelText('Meta del ranking')).toHaveTextContent('setiembre 2026|true')
    expect(screen.getByLabelText('Metas del ranking')).toHaveTextContent('foto-setiembre')
    expect(screen.getByLabelText('Metas del ranking')).not.toHaveTextContent('store-agosto')
    expect(screen.getByLabelText('Identidad mensual')).toHaveTextContent('false')
  })

  it('si falla la foto mensual, el ranking recibe un error global fail-closed', () => {
    ESTADO_CUMPLIMIENTO_RANKING.isError = true
    ESTADO_CUMPLIMIENTO_RANKING.error = new Error('periodo cruzado')
    montar({}, 'ranking-vendedores', SETIEMBRE_2)

    expect(screen.getByText(/ERROR: No se pudieron cargar la identidad, las metas y el capital del mes elegido\./)).toBeInTheDocument()
    expect(screen.getByLabelText('Meta del ranking')).toHaveTextContent('setiembre 2026|false')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar foto mensual' }))
    expect(REFETCH_CONVERSION_MENSUAL).toHaveBeenCalledTimes(1)
    expect(ESTADO_CUMPLIMIENTO_RANKING.refetch).toHaveBeenCalledTimes(1)
    expect(ESTADO_COSECHA_RANKING.refetch).toHaveBeenCalledTimes(1)
  })
})

describe('Hoy · gerencia — meta del mes', () => {
  it('una meta que gerencia todavía no fijó NO se pinta como incumplida', () => {
    montar({ objetivos: objetivosCero('2026-07-01').gerencia }, 'metas')

    const meta = within(tarjetaMeta())
    // Dos tarjetas desde 2026-08-10: capital consolidado y conversión de
    // empresa. Antes eran tres —PEN, USD y conversión— y dos de ellas no
    // podían tener meta porque el editor no permitía fijarlas.
    expect(meta.getAllByText('Meta del mes todavía sin fijar')).toHaveLength(2)
    // Antes: dos barras en ROJO CRÍTICO con "0%" sobre cuotas que nadie fijó.
    expect(meta.queryByText('0%')).not.toBeInTheDocument()
    expect(meta.getAllByText('meta por definir')).toHaveLength(2)
  })

  it('cambia meta, capital y conversión juntos por mes calendario', () => {
    montar({}, 'metas')

    const metaVigente = within(tarjetaMeta())
    expect(metaVigente.getByText('Meta mensual · julio 2026')).toBeInTheDocument()
    expect(metaVigente.queryByText('0%')).not.toBeInTheDocument()
    expect(metaVigente.getAllByText('Meta del mes todavía sin fijar')).toHaveLength(2)
    // Sin rango raro no hay por qué advertir nada.
    expect(metaVigente.queryByText(/no del rango que elegiste/)).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-06' } })

    const metaHistorica = within(tarjetaMeta())
    expect(metaHistorica.getByText('Meta mensual · junio 2026')).toBeInTheDocument()
    expect(metaHistorica.getByText(/Vista histórica de junio 2026/)).toBeInTheDocument()
    expect(metaHistorica.queryByText('0%')).not.toBeInTheDocument()
  })

  it('si falla la lectura de metas no muestra ceros como objetivos ni permite editar encima', () => {
    ESTADO_CUMPLIMIENTO_RANKING.isError = true
    ESTADO_CUMPLIMIENTO_RANKING.error = new Error('foto mensual caída')
    montar({
      objetivos: objetivosCero('2026-07-01').gerencia,
      objetivosError: true,
    }, 'metas')

    const meta = within(tarjetaMeta())
    expect(meta.queryByText('meta por definir')).not.toBeInTheDocument()
    expect(meta.queryByText('Editor de metas')).not.toBeInTheDocument()
    expect(meta.queryAllByRole('progressbar')).toHaveLength(0)
    expect(meta.getByText(/No se pudieron cargar la identidad, las metas y el capital/)).toBeInTheDocument()
    expect(meta.getAllByText('meta no disponible')).toHaveLength(2)

    fireEvent.click(meta.getByRole('button', { name: 'Reintentar cumplimiento' }))
    expect(ESTADO_CUMPLIMIENTO_RANKING.refetch).toHaveBeenCalledTimes(1)
  })

  it('bloquea el editor con una foto del mes anterior y permite reintentar el rollover', async () => {
    RECARGAR.mockResolvedValue(false)
    montar({ periodoObjetivos: '2026-06-01' }, 'metas')

    await act(async () => {})

    const meta = within(tarjetaMeta())
    expect(meta.queryByText('Editor de metas')).not.toBeInTheDocument()
    expect(meta.getByText('No pudimos cargar las metas del mes vigente')).toBeInTheDocument()
    fireEvent.click(meta.getByRole('button', { name: 'Reintentar' }))
    await act(async () => {})
    expect(RECARGAR).toHaveBeenCalledTimes(2)
  })

  it('el cumplimiento no depende de la consulta de pipeline y nunca se reemplaza con producción', () => {
    ESTADO_CONVERSIONES.isPending = true
    const carga = montar({ cumplimiento: CUMPLIMIENTO_METAS_DEMO }, 'metas')

    let meta = within(tarjetaMeta())
    expect(meta.queryByLabelText('Cargando avance de metas')).not.toBeInTheDocument()
    // El total CONSOLIDADO, no el PEN puro: 650.000 en soles + los dólares del
    // fixture convertidos a TC 3.5. Con el mock viejo (tc fijo a null) esta
    // aserción pasaba con S/ 650,000 aunque el consolidado estuviera roto.
    expect(meta.getByText('S/ 961,500')).toBeInTheDocument()
    carga.unmount()

    ESTADO_CONVERSIONES.isPending = false
    ESTADO_CONVERSIONES.error = new Error('sin conexión')
    ESTADO_CUMPLIMIENTO_RANKING.data = undefined
    ESTADO_CUMPLIMIENTO_RANKING.isError = true
    ESTADO_CUMPLIMIENTO_RANKING.error = new Error('foto mensual caída')
    montar({ cumplimiento: null, cumplimientoError: true }, 'metas')

    meta = within(tarjetaMeta())
    expect(meta.getByRole('alert')).toHaveTextContent('No se pudieron cargar la identidad, las metas y el capital')
    expect(meta.queryByText('S/ 0')).not.toBeInTheDocument()
    fireEvent.click(meta.getByRole('button', { name: 'Reintentar cumplimiento' }))
    expect(ESTADO_CUMPLIMIENTO_RANKING.refetch).toHaveBeenCalledTimes(1)
  })

  // Pedido de Miguel (2026-08-10): «me gustaría ver cuánto vamos en soles y
  // dólares y luego un total en soles». Antes eran dos tarjetas separadas y la
  // de dólares no podía tener meta, así que vivía vacía.
  it('enseña soles, dólares y el total consolidado en una sola lectura', () => {
    montar({ cumplimiento: CUMPLIMIENTO_METAS_DEMO }, 'metas')

    const meta = within(tarjetaMeta())
    expect(meta.getByText('Capital confirmado del mes')).toBeInTheDocument()
    // Las dos monedas, juntas y con la tasa APLICADA rotulada.
    expect(meta.getByText(/S\/ .* \+ US\$/)).toBeInTheDocument()
    expect(meta.getByText(/TC S\/ 3\.5/)).toBeInTheDocument()
    expect(meta.getByText(/BCRP/)).toBeInTheDocument()
    // Y la conversión es la de la EMPRESA; el detalle vive en Conversiones.
    expect(meta.getByText('Conversión de la empresa')).toBeInTheDocument()
    expect(meta.getByText('El detalle por analista está en Conversiones.')).toBeInTheDocument()
  })

  // El dinero en dólares no se convierte a una tasa inventada: se dice que el
  // total no los incluye y se ofrece un camino de vuelta.
  it('sin tipo de cambio avisa, no consolida a ciegas, y deja reintentar', () => {
    TIPO_CAMBIO.tc = null
    montar({ cumplimiento: CUMPLIMIENTO_METAS_DEMO }, 'metas')

    const meta = within(tarjetaMeta())
    expect(meta.getByText(/sin tipo de cambio: el total NO incluye los dólares/))
      .toBeInTheDocument()
    expect(meta.getByRole('button', { name: /Reintentar tipo de cambio/ })).toBeInTheDocument()
  })

  // Mientras la consulta del TC está en vuelo no se puede afirmar el total ni
  // el porcentaje: antes se aplanaba con «caído» y el % salía inflado porque
  // ignoraba los dólares de los dos lados.
  it('no afirma el cumplimiento mientras el tipo de cambio está en vuelo', () => {
    TIPO_CAMBIO.tc = undefined
    montar({ cumplimiento: CUMPLIMIENTO_METAS_DEMO }, 'metas')

    const meta = within(tarjetaMeta())
    expect(meta.getByText(/Consultando el tipo de cambio/)).toBeInTheDocument()
    expect(meta.queryAllByRole('progressbar')).toHaveLength(0)
  })

  it('presenta inteligencia comercial sin herramientas operativas', () => {
    montar()

    expect(screen.getByRole('heading', { name: 'Resumen comercial' })).toBeInTheDocument()
    expect(screen.queryByText('Por repartir')).not.toBeInTheDocument()
  })

})

describe('Hoy · gerencia — período del tablero', () => {
  it('no promete que el origen filtre las citas globales del resumen', () => {
    montar({}, 'resumen')

    expect(screen.getByText(/Conversión y citas: 01 jul\. 2026 al 15 jul\. 2026/))
      .toBeInTheDocument()
    expect(screen.getByText(/El origen recorta Cosecha y embudo; la conversión canónica sigue mostrando todos los orígenes/))
      .toBeInTheDocument()
    expect(screen.queryByText(/el rango y origen recortan Cosecha, citas y embudo/))
      .not.toBeInTheDocument()
  })

  it('el reintento del Resumen recupera también el tipo de cambio', () => {
    montar({}, 'resumen')

    fireEvent.click(screen.getByRole('button', { name: 'Reintentar fuentes del Resumen' }))

    expect(RECARGAR_TC).toHaveBeenCalledTimes(1)
  })

  it('abre en el mes calendario vigente de Lima y lo propaga a todas las métricas', () => {
    montar()

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-07-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-07-15')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15', null)
    expect(CONSULTAS.reuniones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
    expect(CONSULTAS.distribucion).toHaveBeenLastCalledWith(false, '2026-07-01', '2026-07-15')
  })

  it('respeta Lima cuando UTC ya pasó al mes siguiente', () => {
    // 1 de agosto en UTC, pero todavía 31 de julio a las 21:30 en Lima.
    montar({}, 'completo', new Date('2026-08-01T02:30:00Z'))

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-07-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-07-31')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-31', null)
  })

  it('cambia de mes exactamente a medianoche de Lima', () => {
    montar({}, 'completo', new Date('2026-08-01T05:00:00Z'))

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-08-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-08-01')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-08-01', '2026-08-01', null)
  })

  it('mantiene el TC del cierre elegido al cruzar medianoche con un mes histórico', () => {
    montar({}, 'metas', new Date('2026-09-03T04:59:59Z'))

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-08' } })
    expect(CONSULTAS.tipoCambio).toHaveBeenLastCalledWith(true, '2026-08-31')
    expect(RECARGAR_TC).not.toHaveBeenCalled()

    act(() => { vi.advanceTimersByTime(1_000) })

    expect(RECARGAR_TC).not.toHaveBeenCalled()
    expect(CONSULTAS.tipoCambio).toHaveBeenLastCalledWith(true, '2026-08-31')
  })

  it('recalcula todas las consultas al aplicar otro rango', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-06-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-06-30' } })

    // Editar solo cambia el borrador; ningún panel consulta el rango nuevo
    // hasta que Gerencia confirma con Aplicar.
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15', null)
    expect(CONSULTAS.reuniones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))

    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-06-01', '2026-06-30', null)
    expect(CONSULTAS.reuniones).toHaveBeenLastCalledWith(true, '2026-06-01', '2026-06-30')
    expect(CONSULTAS.distribucion).toHaveBeenLastCalledWith(false, '2026-06-01', '2026-06-30')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
  })

  it('bloquea fechas futuras antes de consultar los RPC', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-07-16' } })

    expect(screen.getByRole('alert')).toHaveTextContent('La fecha hasta no puede ser posterior a hoy en Lima.')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15', null)
  })

  it('bloquea rangos que superan el límite aceptado por los RPC', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2025-07-14' } })

    expect(screen.getByRole('alert')).toHaveTextContent('El rango no puede superar 365 días de diferencia.')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15', null)
  })

  it('conserva el rango aplicado entre vistas y descarta el borrador sin aplicar', () => {
    vi.setSystemTime(MIERCOLES_10AM)
    YO = {
      id: 'g-1',
      nombre_completo: 'GERENCIA UNO',
      rol: 'gerencia',
      demo: false,
      puede_contratar: true,
    }
    LEADS = [lead()]
    OBJETIVOS = objetivosCero()

    function NavegacionGerenciaPrueba(): ReactNode {
      const [seccion, setSeccion] = useState<SeccionGerencia>('completo')
      return (
        <>
          <button type="button" onClick={() => setSeccion('ranking-vendedores')}>Ir a ranking</button>
          <HoyGerencia key={seccion} seccion={seccion} />
        </>
      )
    }

    render(<PeriodoGerenciaProvider><NavegacionGerenciaPrueba /></PeriodoGerenciaProvider>)
    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-06-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-06-30' } })
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-05-01' } })
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeEnabled()
    fireEvent.click(screen.getByRole('button', { name: 'Ir a ranking' }))

    expect(screen.getByLabelText('Mes calendario')).toHaveValue('2026-06')
    expect(screen.queryByLabelText('Origen del lead')).not.toBeInTheDocument()
    // El ranking ya no enciende metricas_conversiones_fn: sus pestañas leen
    // mensual, cumplimiento/capital y cosecha, cada una por separado.
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(false, '2026-06-01', '2026-06-30', null)
    expect(screen.queryByRole('button', { name: 'Aplicar' })).not.toBeInTheDocument()
  })
})

describe('Hoy · gerencia — el ranking y la conversión mensual', () => {
  it('si la MENSUAL falla, el ranking lo dice como error con su Reintentar (no degrada mudo)', () => {
    // Exigencia pre-release de Miguel (2026-08-15): antes, el fallo dejaba el
    // panel en «indisponible» sin decir por qué ni ofrecer reintento.
    CONVERSION_MENSUAL_FALLA = true
    montar({}, 'ranking-vendedores')

    expect(screen.getByText(/ERROR: No se pudo calcular la conversión mensual\./)).toBeInTheDocument()
  })

  it('con la mensual sana no se inventa ningún error', () => {
    montar({}, 'ranking-vendedores')
    expect(screen.queryByText(/ERROR:/)).not.toBeInTheDocument()
  })

  it('un fallo de metricas_conversiones_fn no bloquea el ranking porque ya no es una fuente suya', () => {
    ESTADO_CONVERSIONES.error = new Error('consulta lateral caída')
    montar({}, 'ranking-vendedores')

    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(false, expect.any(String), expect.any(String), null)
    expect(screen.queryByText(/ERROR:/)).not.toBeInTheDocument()
  })

  it('el RESUMEN también recibe el fallo de la MENSUAL (la tercera pantalla del hueco)', () => {
    CONVERSION_MENSUAL_FALLA = true
    montar({}, 'resumen')

    expect(screen.getByText(/ERROR: .*No se pudo calcular la conversión mensual\./)).toBeInTheDocument()
  })

  it('el Resumen mantiene neutral la foto mensual mientras espera capital y meta', () => {
    ESTADO_CUMPLIMIENTO_RANKING.isPending = true
    montar({}, 'resumen')

    expect(screen.getByLabelText('Carga mensual del Resumen')).toHaveTextContent('true')
  })

  it('Inteligencia Comercial también recibe el fallo de la MENSUAL (no lo oculta)', () => {
    // Observación #3 de la revisión externa: su héroe y su ficha beben de la
    // mensual, pero el error que recibía era solo el del payload de rango.
    CONVERSION_MENSUAL_FALLA = true
    montar({}, 'conversiones')

    expect(screen.getByLabelText('Error mensual de Conversiones')).toHaveTextContent(
      'ERROR: No se pudo calcular la conversión mensual.',
    )
    expect(screen.getByLabelText('Error de rango en Conversiones')).toBeEmptyDOMElement()
  })

  it('Inteligencia Comercial entrega el fallo de Cosecha solo al estado del rango', () => {
    ESTADO_CONVERSIONES.error = new Error('consulta lateral caída')
    montar({}, 'conversiones')

    expect(screen.getByLabelText('Error mensual de Conversiones')).toBeEmptyDOMElement()
    expect(screen.getByLabelText('Error de rango en Conversiones')).toHaveTextContent(
      'ERROR: No se pudieron cargar las conversiones.',
    )
    expect(screen.getByLabelText('Carga mensual de Conversiones')).toHaveTextContent('false')
  })

  it('mantiene la lectura mensual en carga hasta recibir también capital y meta', () => {
    ESTADO_CUMPLIMIENTO_RANKING.isPending = true
    montar({}, 'conversiones')

    expect(screen.getByLabelText('Carga mensual de Conversiones')).toHaveTextContent('true')
    expect(screen.getByLabelText('Dato mensual de Conversiones')).toHaveTextContent('esperando')
    expect(screen.getByLabelText('Carga de rango en Conversiones')).toHaveTextContent('false')
  })

  it('durante el refetch de un mes histórico no mezcla las fotos cacheadas', () => {
    CONVERSION_MENSUAL = {
      ...conversionMensualDemo(Date.now(), { alcance: 'global' }),
      cierre: { cerrado: false },
    }
    CONVERSION_MENSUAL_FETCHING = true
    ESTADO_CUMPLIMIENTO_RANKING.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-06-01',
      cierre: { cerrado: false },
    }
    ESTADO_CUMPLIMIENTO_RANKING.isFetching = true
    montar({}, 'conversiones')

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-06-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-06-30' } })
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))

    expect(screen.getByLabelText('Carga mensual de Conversiones')).toHaveTextContent('true')
    expect(screen.getByLabelText('Dato mensual de Conversiones')).toHaveTextContent('esperando')
  })

  it('detecta una conversión abierta mezclada con cumplimiento ya sellado', () => {
    CONVERSION_MENSUAL = {
      ...conversionMensualDemo(Date.parse('2026-06-15T15:00:00Z'), { alcance: 'global' }),
      cierre: { cerrado: false },
    }
    ESTADO_CUMPLIMIENTO_RANKING.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-06-01',
      cierre: { cerrado: true },
    }
    montar({}, 'ranking-vendedores')

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-06' } })

    expect(screen.getByRole('heading', { name: /Ranking de analistas · ERROR/ }))
      .toHaveTextContent('mismo mes, revisión o estado de cierre')
  })

  it('bloquea la terna cuando una revisión difiere y reintenta los tres núcleos', () => {
    CONVERSION_MENSUAL = {
      ...conversionMensualDemo(Date.parse('2026-06-15T15:00:00Z'), { alcance: 'global' }),
      revision: 7,
      cierre: { cerrado: false },
    }
    ESTADO_CUMPLIMIENTO_RANKING.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-06-01',
      revision: 8,
      cierre: { cerrado: false },
    }
    ESTADO_COSECHA_RANKING.data = {
      version: 1,
      revision: 7,
      cierre: { cerrado: false },
      generado_en: '2026-06-30T15:00:00Z',
      alcance: 'global',
      periodo: { desde: '2026-06-01', hasta: '2026-06-30' },
      responsables: [],
    }
    montar({}, 'ranking-vendedores')

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-06' } })

    expect(screen.getByRole('heading', { name: /Ranking de analistas · ERROR/ }))
      .toHaveTextContent('mismo mes, revisión o estado de cierre')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar foto mensual' }))
    expect(REFETCH_CONVERSION_MENSUAL).toHaveBeenCalledTimes(1)
    expect(ESTADO_CUMPLIMIENTO_RANKING.refetch).toHaveBeenCalledTimes(1)
    expect(ESTADO_COSECHA_RANKING.refetch).toHaveBeenCalledTimes(1)
  })

  it('bloquea una Cosecha que llega con otro mes aunque coincidan revisión y cierre', () => {
    CONVERSION_MENSUAL = {
      ...conversionMensualDemo(Date.parse('2026-06-15T15:00:00Z'), { alcance: 'global' }),
      revision: 7,
      cierre: { cerrado: false },
    }
    ESTADO_CUMPLIMIENTO_RANKING.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-06-01',
      revision: 7,
      cierre: { cerrado: false },
    }
    ESTADO_COSECHA_RANKING.data = {
      version: 1,
      revision: 7,
      cierre: { cerrado: false },
      generado_en: '2026-06-30T15:00:00Z',
      alcance: 'global',
      periodo: { desde: '2026-05-01', hasta: '2026-05-31' },
      responsables: [],
    }
    montar({}, 'ranking-vendedores')

    fireEvent.change(screen.getByLabelText('Mes calendario'), { target: { value: '2026-06' } })

    expect(screen.getByRole('heading', { name: /Ranking de analistas · ERROR/ }))
      .toHaveTextContent('mismo mes, revisión o estado de cierre')
  })

  it('al ver el ejemplo no arrastra el error ni la meta fallida de la foto real', () => {
    ESTADO_CUMPLIMIENTO_RANKING.isError = true
    ESTADO_CUMPLIMIENTO_RANKING.error = new Error('foto mensual caída')
    montar({}, 'conversiones', new Date('2026-09-02T15:00:00Z'))

    const origen = screen.getByLabelText('Origen del lead')
    fireEvent.change(origen, { target: { value: 'referido' } })
    expect(origen).toHaveValue('referido')
    expect(screen.getByLabelText('Error mensual de Conversiones')).not.toBeEmptyDOMElement()
    fireEvent.click(screen.getByRole('button', { name: 'Ver ejemplo' }))

    expect(screen.getByLabelText('Modo de Conversiones')).toHaveTextContent('ejemplo')
    expect(screen.getByLabelText('Error mensual de Conversiones')).toBeEmptyDOMElement()
    expect(screen.getByLabelText('Meta mensual de Conversiones')).toHaveTextContent('setiembre 2026|ok|')
    expect(screen.getByLabelText('Meta mensual de Conversiones')).not.toHaveTextContent('|0')
    expect(origen).toBeDisabled()
    expect(origen).toHaveValue('')
    expect(screen.getByText(/Los datos de ejemplo no se filtran por origen/)).toBeInTheDocument()
  })

  it('el ejemplo mensual respeta el mes elegido y no lo rotula con datos del mes vigente', () => {
    montar({}, 'conversiones', new Date('2026-09-02T15:00:00Z'))

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-08-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-08-31' } })
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))
    fireEvent.click(screen.getByRole('button', { name: 'Ver ejemplo' }))

    expect(screen.getByLabelText('Período mensual de Conversiones')).toHaveTextContent('2026-08')
    expect(screen.getByLabelText('Meta mensual de Conversiones')).toHaveTextContent('agosto 2026')
  })

  it('no mezcla el roster vigente del rango con la identidad de un mes histórico', () => {
    const vendedorHistorico = Object.keys(CUMPLIMIENTO_METAS_DEMO.porVendedor)[0]!
    ESTADO_CUMPLIMIENTO_RANKING.data = {
      ...CUMPLIMIENTO_METAS_DEMO,
      periodo: '2026-06-01',
    }
    EQUIPO = [{
      perfil_id: 'vendedor-vigente',
      nombre_completo: 'VENDEDOR VIGENTE',
      rol_crm: 'vendedor',
      supervisor_id: 'supervisor-vigente',
      activo: true,
    } as Miembro]
    montar({}, 'conversiones')

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-06-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-06-30' } })
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))

    expect(screen.getByLabelText('Población de rango en Conversiones')).toHaveTextContent('vendedor-vigente')
    expect(screen.getByLabelText('Población mensual en Conversiones')).toHaveTextContent(vendedorHistorico)
    expect(screen.getByLabelText('Población mensual en Conversiones')).not.toHaveTextContent('vendedor-vigente')
  })

  it('Inteligencia Comercial entrega la carga de Cosecha sin marcar la mensual como pendiente', () => {
    ESTADO_CONVERSIONES.isPending = true
    montar({}, 'conversiones')

    expect(screen.getByLabelText('Carga mensual de Conversiones')).toHaveTextContent('false')
    expect(screen.getByLabelText('Carga de rango en Conversiones')).toHaveTextContent('true')
  })
})
