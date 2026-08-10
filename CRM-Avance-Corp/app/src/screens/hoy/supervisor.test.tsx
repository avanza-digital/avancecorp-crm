// Tests de integración de la tarjeta mensual de monto y conversión del equipo.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante y
// sin fijarlo estos tests pasarían o fallarían según el día en que se ejecuten.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { CUMPLIMIENTO_METAS_DEMO, METAS_DEMO } from '@/lib/demo'
import {
  objetivosCero,
  type CumplimientoMetasJerarquico,
  type ObjetivosPorRol,
} from '@/lib/objetivos'
import type { Actividad, Lead, Miembro, Yo } from '@/lib/tipos'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const MIERCOLES_10AM = new Date('2026-07-15T15:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let VENDEDORES: Miembro[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero()
let OBJETIVOS_ERROR = false
let CUMPLIMIENTO: CumplimientoMetasJerarquico | null = null
let CUMPLIMIENTO_ERROR = false
const recargar = vi.fn()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: VENDEDORES, esGlobal: false },
    actividades: [] as Actividad[],
    tareas: [],
    objetivos: OBJETIVOS,
    objetivosError: OBJETIVOS_ERROR,
    cumplimientoMetas: CUMPLIMIENTO,
    cumplimientoMetasError: CUMPLIMIENTO_ERROR,
    recargar,
    equipo: VENDEDORES,
    reasignar: () => ({ ok: true }),
  }),
  usePanelesActions: () => ({ abrirLead: () => {} }),
}))
// El panel de agenda del equipo vive de una RPC (TanStack) que no es lo que se
// prueba aquí: se apaga junto con su consulta para no montar un QueryClient.
vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => null }))
vi.mock('@/data/crm-queries', () => ({
  useMetricasAgenda: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
}))
// crm-api arrastra el cliente de Supabase al importarse; solo se usa su
// formateador de errores.
vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({ indice: new Map(), cargando: false, error: null, recargar: vi.fn() }),
}))

// F1b: los hooks operativos se sustituyen por los ESPEJOS puros sobre los
// mismos datos del mock — la pantalla se prueba con números derivados de
// verdad, sin red ni QueryClientProvider (el shape es el del RPC, validado en
// los tests de lib/).
vi.mock('@/data/use-resumen-cartera-operativo', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useResumenCarteraOperativo: (leads: Lead[], actividades: Actividad[]) => ({
      resumen: resumenCarteraDesdeAmbito(leads, actividades ?? [], Date.now()),
      cargando: false,
      error: null,
      recargar: vi.fn(),
    }),
  }
})
vi.mock('@/data/use-cola-accion-operativa', async () => {
  const { colaAccionDesdeAmbito } = await import('@/lib/cola-accion')
  return {
    useColaAccionOperativa: (
      leads: Lead[],
      actividades: Actividad[],
      tareas: never[],
      indice?: ReadonlyMap<string, never>,
    ) => ({
      cola: colaAccionDesdeAmbito(leads, actividades ?? [], tareas ?? [], Date.now(), indice),
      cargando: false,
      error: null,
      recargar: vi.fn(),
    }),
  }
})
vi.mock('@/data/use-metricas-vendedores-operativas', async () => {
  const { metricasVendedoresDesdeAmbito } = await import('@/lib/metricas-vendedores')
  return {
    useMetricasVendedoresOperativas: (
      roster: Miembro[],
      equipo: Miembro[],
      leads: Lead[],
      actividades: Actividad[],
    ) => ({
      metricas: metricasVendedoresDesdeAmbito(roster ?? [], equipo ?? [], leads ?? [], actividades ?? [], Date.now()),
      cargando: false,
      error: null,
      recargar: vi.fn(),
    }),
  }
})

const { HoySupervisor } = await import('./supervisor')

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
    objetivos?: Partial<ObjetivosPorRol['supervisor']>
    objetivosError?: boolean
    cumplimiento?: CumplimientoMetasJerarquico | null
    cumplimientoError?: boolean
  } = {},
): void {
  vi.setSystemTime(MIERCOLES_10AM)
  YO = {
    id: 's-1',
    nombre_completo: 'SUPERVISOR UNO',
    rol: 'supervisor',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  VENDEDORES = []
  OBJETIVOS_ERROR = over.objetivosError ?? false
  CUMPLIMIENTO_ERROR = over.cumplimientoError ?? false
  OBJETIVOS = { ...METAS_DEMO, supervisor: { ...METAS_DEMO.supervisor, ...over.objetivos } }
  CUMPLIMIENTO = over.cumplimiento === undefined ? null : over.cumplimiento
  render(<HoySupervisor />)
}

function cumplimientoSupervisor(
  conversionReal: number | null,
  resueltos: number,
): CumplimientoMetasJerarquico {
  const base = CUMPLIMIENTO_METAS_DEMO.supervisor
  if (!base) throw new Error('fixture demo sin supervisor')
  return {
    ...CUMPLIMIENTO_METAS_DEMO,
    supervisor: {
      ...base,
      conversionReal,
      convertidos: conversionReal == null ? 0 : Math.round((conversionReal * resueltos) / 100),
      resueltos,
    },
  }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.clearAllMocks()
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  OBJETIVOS_ERROR = false
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Hoy · supervisor — meta del equipo', () => {
  it('la conversión del equipo proviene del cumplimiento confirmado y no del pipeline local', () => {
    montar({
      leads: [
        lead({ id: 'l-c', etapa: 'convertido' }),
        lead({ id: 'l-d', etapa: 'descartado' }),
        lead({ id: 'l-abierto', etapa: 'propuesta_enviada' }),
      ],
      objetivos: { conversionObjetivo: 50 },
      cumplimiento: cumplimientoSupervisor(50, 2),
    })

    expect(screen.getByText('50% de 50%')).toBeInTheDocument()
  })

  it('un mes sin nada resuelto es SIN DATO, no un 0 % en rojo crítico', () => {
    montar({
      leads: [lead({ id: 'l-abierto', etapa: 'propuesta_enviada' })],
      objetivos: { conversionObjetivo: 40 },
      cumplimiento: cumplimientoSupervisor(null, 0),
    })

    expect(screen.getByText('Todavía no se resolvió ningún lead este mes')).toBeInTheDocument()
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.queryByText('0% de 40%')).not.toBeInTheDocument()
  })

  it('no inventa una meta inicial de 15 % cuando no hay meta publicada', () => {
    montar({
      objetivos: { conversionObjetivo: 0 },
      cumplimiento: cumplimientoSupervisor(50, 2),
    })

    expect(screen.getByText('Sin meta fijada para este mes')).toBeInTheDocument()
    expect(screen.queryByText('50% de 15%')).not.toBeInTheDocument()
    expect(screen.queryByText('0% de 0%')).not.toBeInTheDocument()
  })

  it('sin ninguna meta publicada mantiene PEN, USD y conversión neutrales', () => {
    montar({
      objetivos: objetivosCero('2026-07-01').supervisor,
      cumplimiento: cumplimientoSupervisor(100, 1),
    })

    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(3)
    expect(screen.queryByText('100% de 15%')).not.toBeInTheDocument()
  })

  it('si la lectura de metas falla no reemplaza el error por 15 %', () => {
    montar({
      objetivos: objetivosCero('2026-07-01').supervisor,
      objetivosError: true,
    })

    expect(screen.getAllByText('Meta mensual no disponible')).toHaveLength(3)
    expect(screen.queryByText(/de 15%/)).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(recargar).toHaveBeenCalled()
  })

  it('si falla el cumplimiento conserva el pipeline únicamente como pronóstico', () => {
    montar({
      leads: [lead({ monto_estimado: 900_000, etapa: 'propuesta_enviada' })],
      cumplimiento: null,
      cumplimientoError: true,
    })

    expect(screen.getByText('Pronóstico de capital abierto')).toBeInTheDocument()
    expect(screen.getAllByText('Cumplimiento confirmado no disponible')).toHaveLength(3)
    expect(screen.getByText(/no cuenta como cumplimiento/)).toBeInTheDocument()
  })
})

describe('Hoy · supervisor — ranking de mi equipo (decisión #10)', () => {
  it('monta el ranking acotado a SU equipo, no el general de la empresa', () => {
    montar()

    expect(screen.getByText('Ranking de mi equipo')).toBeInTheDocument()
    expect(screen.getByText('Mi equipo')).toBeInTheDocument()
    // El título de gerencia no debe filtrarse a esta pantalla.
    expect(screen.queryByText('Ranking general de vendedores')).not.toBeInTheDocument()
  })

  it('NO ofrece la pestaña «Conversión general»: su RPC deniega al supervisor', () => {
    // Ofrecer un tab que siempre falla sería mentirle. Se abrirá cuando exista la
    // RPC scopeada al subárbol (hoy `metricas_conversiones_fn` responde 42501, y
    // relajarla sería una fuga: sus vistas base no tienen predicado jerárquico).
    montar()

    expect(screen.queryByRole('tab', { name: /Conversión general/i })).not.toBeInTheDocument()
    expect(screen.getByRole('tab', { name: /Capital total/i })).toBeInTheDocument()
  })

  it('abre directamente en la pestaña de capital, la única que puede servir', () => {
    montar()

    expect(screen.getByRole('tab', { name: /Capital total/i })).toHaveAttribute('aria-selected', 'true')
  })
})
