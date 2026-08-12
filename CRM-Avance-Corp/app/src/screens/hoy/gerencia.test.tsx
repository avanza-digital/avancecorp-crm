// Tests de integración de la pantalla "Hoy · gerencia" y sus metas mensuales.
// Monto y conversión son las dos únicas metas visibles.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { useState, type ReactNode } from 'react'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { CUMPLIMIENTO_METAS_DEMO, METAS_DEMO } from '@/lib/demo'
import {
  objetivosCero,
  type CumplimientoMetasJerarquico,
  type ObjetivoComercial,
  type ObjetivosPorRol,
} from '@/lib/objetivos'
import type { Lead, Yo } from '@/lib/tipos'
import type { SeccionGerencia } from './gerencia'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const MIERCOLES_10AM = new Date('2026-07-15T15:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero()
let OBJETIVOS_ERROR = false
let CUMPLIMIENTO: CumplimientoMetasJerarquico | null = null
let CUMPLIMIENTO_ERROR = false
const RECARGAR = vi.fn(async () => true)
const CONSULTAS = vi.hoisted(() => ({
  conversiones: vi.fn(),
  reuniones: vi.fn(),
  distribucion: vi.fn(),
}))
const ESTADO_CONVERSIONES = vi.hoisted(() => ({
  data: undefined as unknown,
  error: null as unknown,
  isPending: false,
  isFetching: false,
  refetch: vi.fn(),
}))

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: [], esGlobal: true },
    equipo: [],
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
vi.mock('./inteligencia-comercial', () => ({ InteligenciaComercialPanel: () => null }))
vi.mock('./ranking-vendedores', () => ({ RankingVendedoresPanel: () => <h1>Ranking de vendedores</h1> }))
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
  useTipoCambio: () => ({ tc: TIPO_CAMBIO.tc, recargar: () => {} }),
}))
vi.mock('./reuniones-gerencia', () => ({ ReunionesGerenciaPanel: () => null }))
vi.mock('./resumen-gerencia', () => ({ ResumenGerenciaPanel: () => <h1>Resumen comercial</h1> }))
vi.mock('./equipo-gerencia', () => ({ EquipoGerenciaPanel: () => null }))
vi.mock('./graficas-gerencia', () => ({ GraficasGerencia: () => null }))
vi.mock('./metas-editor', () => ({ MetasEditor: () => <div>Editor de metas</div> }))
vi.mock('@/components/gerencia/motion', () => ({
  GerenciaMotion: ({ children }: { children: ReactNode }) => <>{children}</>,
}))
// La conversión mensual (la definición), controlable por test.
let CONVERSION_MENSUAL: import('@/lib/conversion-mensual').ConversionMensual | null = null
vi.mock('@/data/crm-queries', () => ({
  useConversionMensual: () => ({
    data: CONVERSION_MENSUAL ?? undefined,
    isError: false,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
  useMetricasDistribucionLeads: (...argumentos: [boolean, string, string]) => {
    CONSULTAS.distribucion(...argumentos)
    return { data: undefined, error: null, isPending: false, isFetching: false, refetch: () => {} }
  },
  useMetricasConversiones: (...argumentos: [boolean, string, string]) => {
    CONSULTAS.conversiones(...argumentos)
    return ESTADO_CONVERSIONES
  },
  useMetricasReuniones: (...argumentos: [boolean, string, string]) => {
    CONSULTAS.reuniones(...argumentos)
    return { data: undefined, error: null, isPending: false, isFetching: false, refetch: () => {} }
  },
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
    objetivosError?: boolean
    cumplimiento?: CumplimientoMetasJerarquico | null
    cumplimientoError?: boolean
  } = {},
  seccion: SeccionGerencia = 'completo',
  ahora: Date = MIERCOLES_10AM,
): ReturnType<typeof render> {
  vi.setSystemTime(ahora)
  YO = {
    id: 'g-1',
    nombre_completo: 'GERENCIA UNO',
    rol: 'gerencia',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  OBJETIVOS_ERROR = over.objetivosError ?? false
  CUMPLIMIENTO_ERROR = over.cumplimientoError ?? false
  OBJETIVOS = { ...METAS_DEMO, gerencia: over.objetivos ?? METAS_DEMO.gerencia }
  CUMPLIMIENTO = over.cumplimiento === undefined ? null : over.cumplimiento
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
  OBJETIVOS_ERROR = false
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  ESTADO_CONVERSIONES.data = undefined
  ESTADO_CONVERSIONES.error = null
  ESTADO_CONVERSIONES.isPending = false
  ESTADO_CONVERSIONES.isFetching = false
  ESTADO_CONVERSIONES.refetch.mockReset()
})

afterEach(() => {
  vi.useRealTimers()
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

  // Las metas se pactan por MES, así que esta sección mide siempre el mes en
  // curso y el selector de rango de arriba no la toca. Antes se desactivaba la
  // comparación al cambiar el rango, pero el importe que quedaba en pantalla
  // seguía siendo el del mes: una cifra mensual rotulada «rango aplicado».
  it('mide siempre el mes en curso y lo dice cuando el rango es otro', () => {
    montar({}, 'metas')

    const metaVigente = within(tarjetaMeta())
    expect(metaVigente.getByText('Meta mensual · julio 2026')).toBeInTheDocument()
    expect(metaVigente.queryByText('0%')).not.toBeInTheDocument()
    expect(metaVigente.getByText('Cumplimiento confirmado no disponible')).toBeInTheDocument()
    expect(metaVigente.getByText('Todavía no hay leads recibidos este mes')).toBeInTheDocument()
    // Sin rango raro no hay por qué advertir nada.
    expect(metaVigente.queryByText(/no del rango que elegiste/)).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-06-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-06-30' } })
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))

    const metaHistorica = within(tarjetaMeta())
    expect(metaHistorica.getByText(/Estas cifras son del mes en curso \(julio 2026\)/))
      .toBeInTheDocument()
    expect(metaHistorica.queryByText('0%')).not.toBeInTheDocument()
  })

  it('si falla la lectura de metas no muestra ceros como objetivos ni permite editar encima', () => {
    montar({
      objetivos: objetivosCero('2026-07-01').gerencia,
      objetivosError: true,
    }, 'metas')

    const meta = within(tarjetaMeta())
    expect(meta.queryByText('meta por definir')).not.toBeInTheDocument()
    expect(meta.queryByText('Editor de metas')).not.toBeInTheDocument()
    expect(meta.queryAllByRole('progressbar')).toHaveLength(0)
    expect(meta.getByText('No pudimos cargar las metas mensuales')).toBeInTheDocument()
    expect(meta.getAllByText('meta no disponible')).toHaveLength(2)

    fireEvent.click(meta.getByRole('button', { name: 'Reintentar' }))
    expect(RECARGAR).toHaveBeenCalledTimes(1)
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
    montar({ cumplimiento: null, cumplimientoError: true }, 'metas')

    meta = within(tarjetaMeta())
    expect(meta.getByRole('alert')).toHaveTextContent('No se pudo calcular el cumplimiento confirmado')
    expect(meta.getByText('Cumplimiento confirmado no disponible')).toBeInTheDocument()
    expect(meta.queryByText('S/ 0')).not.toBeInTheDocument()
    fireEvent.click(meta.getByRole('button', { name: 'Reintentar cumplimiento' }))
    expect(RECARGAR).toHaveBeenCalledTimes(1)
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
  it('abre en el mes calendario vigente de Lima y lo propaga a todas las métricas', () => {
    montar()

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-07-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-07-15')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
    expect(CONSULTAS.reuniones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
    expect(CONSULTAS.distribucion).toHaveBeenLastCalledWith(false, '2026-07-01', '2026-07-15')
  })

  it('respeta Lima cuando UTC ya pasó al mes siguiente', () => {
    // 1 de agosto en UTC, pero todavía 31 de julio a las 21:30 en Lima.
    montar({}, 'completo', new Date('2026-08-01T02:30:00Z'))

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-07-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-07-31')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-31')
  })

  it('cambia de mes exactamente a medianoche de Lima', () => {
    montar({}, 'completo', new Date('2026-08-01T05:00:00Z'))

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-08-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-08-01')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-08-01', '2026-08-01')
  })

  it('recalcula todas las consultas al aplicar otro rango', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-06-01' } })
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-06-30' } })

    // Editar solo cambia el borrador; ningún panel consulta el rango nuevo
    // hasta que Gerencia confirma con Aplicar.
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
    expect(CONSULTAS.reuniones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar' }))

    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-06-01', '2026-06-30')
    expect(CONSULTAS.reuniones).toHaveBeenLastCalledWith(true, '2026-06-01', '2026-06-30')
    expect(CONSULTAS.distribucion).toHaveBeenLastCalledWith(false, '2026-06-01', '2026-06-30')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
  })

  it('bloquea fechas futuras antes de consultar los RPC', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-07-16' } })

    expect(screen.getByRole('alert')).toHaveTextContent('La fecha hasta no puede ser posterior a hoy en Lima.')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
  })

  it('bloquea rangos que superan el límite aceptado por los RPC', () => {
    montar()

    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2025-07-14' } })

    expect(screen.getByRole('alert')).toHaveTextContent('El rango no puede superar 365 días de diferencia.')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-07-01', '2026-07-15')
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

    expect(screen.getByLabelText('Desde')).toHaveValue('2026-06-01')
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-06-30')
    expect(CONSULTAS.conversiones).toHaveBeenLastCalledWith(true, '2026-06-01', '2026-06-30')
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled()
  })
})
