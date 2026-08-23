// Tests de integración de HOY del supervisor: reparto compacto y tarjeta
// mensual de monto/conversión del equipo.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante y
// sin fijarlo estos tests pasarían o fallarían según el día en que se ejecuten.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
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
// `undefined`: espejo derivado normal; número: el RPC manda ese total; `null`:
// el resumen no está disponible. Permite comprobar que HOY no reemplaza la
// autoridad del servidor con el número de filas que tenga cargadas en cliente.
let TOTAL_PARKEADOS_RPC: number | null | undefined
const recargar = vi.fn()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))

// El TC real llamaría a la edge. Mutable a propósito: sin mock, `tc` arrancaba
// en `undefined` («consultando») y el panel degradaba en TODOS los tests, que
// es como este fichero llegó a no ejercitar nunca el consolidado.
const TIPO_CAMBIO: { tc: { promedio: number, fuente: string } | null | undefined } = {
  tc: { promedio: 3.5, fuente: 'BCRP · prom. 7d' },
}
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
  useTipoCambio: () => ({ tc: TIPO_CAMBIO.tc, recargar: () => {} }),
}))
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
  }),
  usePanelesActions: () => ({ abrirLead: () => {} }),
}))
// El panel de agenda del equipo vive de una RPC (TanStack) que no es lo que se
// prueba aquí: se apaga junto con su consulta para no montar un QueryClient.
vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => null }))
// La conversión mensual del equipo, controlable por test (sin QueryClient).
let CONVERSION_MENSUAL: import('@/lib/conversion-mensual').ConversionMensual | null = null
let CONVERSION_MENSUAL_ERROR = false
vi.mock('@/data/crm-queries', () => ({
  useMetricasAgenda: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
  useConversionMensual: () => ({
    data: CONVERSION_MENSUAL ?? undefined,
    isError: CONVERSION_MENSUAL_ERROR,
  }),
  // Sin cierres en coops: el bloque «Por empresa» se oculta y no toca la suite.
  useCierresExternos: () => ({
    data: undefined,
    isError: false,
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
    useResumenCarteraOperativo: (leads: Lead[], actividades: Actividad[]) => {
      const resumenDerivado = resumenCarteraDesdeAmbito(leads, actividades ?? [], Date.now())
      const resumen = TOTAL_PARKEADOS_RPC === null
        ? null
        : TOTAL_PARKEADOS_RPC === undefined
          ? resumenDerivado
          : {
              ...resumenDerivado,
              totales: { ...resumenDerivado.totales, parkeados: TOTAL_PARKEADOS_RPC },
            }
      return {
        resumen,
        cargando: false,
        error: null,
        recargar: vi.fn(),
      }
    },
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

/**
 * `metas` describe si la revisión publicada TRAE metas o viene en cero, porque
 * desde 2026-08-10 el avance se mide contra la FOTO del snapshot
 * (`metaVigente`): «no hay meta» ya no se simula poniendo `objetivos` a cero
 * mientras el cumplimiento sigue trayendo las suyas.
 */
/** Payload de alcance 'equipo' cuyo TOTAL trae el % y el divisor dados. */
function conversionMensualEquipo(pct: number | null, divisor: number): import('@/lib/conversion-mensual').ConversionMensual {
  return {
    version: 1,
    generado_en: '2026-07-15T15:00:00Z',
    alcance: 'equipo',
    periodo: { mes: '2026-07', mes_nombre: 'julio', anio: 2026, zona: 'America/Lima', desde: '2026-07-01T05:00:00Z', hasta: '2026-08-01T05:00:00Z' },
    ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
    fuentes: { divisor: 'crm.lead_asignaciones.asignado_en', numerador: 'crm.lead_asignaciones.resultado_en', referido: 'crm.lead_asignaciones.origen' },
    cobertura: { medible: true, suelo_historico: null, motivo_no_medible: null, divisor_aproximado: 0, divisor_por_motivo: divisor > 0 ? { ingreso: divisor } : {}, cierres_sin_episodio: 0, fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 } },
    total: { analistas: divisor > 0 ? 1 : 0, divisor, cierres_no_referidos: 0, cierres_referidos: 0, cierres_de_arrastre: 0, referidos_recibidos: 0, numerador: pct == null ? 0 : (pct * divisor) / 100, conversion_pct: pct, referidos_aporta_pct: null },
    responsables: [],
  }
}

function cumplimientoSupervisor(
  conversionReal: number | null,
  resueltos: number,
  metas: 'con-metas' | 'sin-metas' = 'con-metas',
  metaConversion?: number,
): CumplimientoMetasJerarquico {
  const base = CUMPLIMIENTO_METAS_DEMO.supervisor
  if (!base) throw new Error('fixture demo sin supervisor')
  return {
    ...CUMPLIMIENTO_METAS_DEMO,
    supervisor: {
      ...base,
      ...(metas === 'sin-metas'
        ? {
            conversionObjetivo: 0,
            detalles: base.detalles.map((d) => ({ ...d, capitalObjetivo: 0, contratosObjetivo: 0 })),
          }
        : {}),
      ...(metaConversion == null ? {} : { conversionObjetivo: metaConversion }),
      conversionReal,
      convertidos: conversionReal == null ? 0 : Math.round((conversionReal * resueltos) / 100),
      resueltos,
    },
  }
}

beforeEach(() => {
  CONVERSION_MENSUAL = null
  CONVERSION_MENSUAL_ERROR = false
  TIPO_CAMBIO.tc = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
  vi.useFakeTimers()
  vi.clearAllMocks()
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  OBJETIVOS_ERROR = false
  TOTAL_PARKEADOS_RPC = undefined
})

afterEach(() => {
  vi.useRealTimers()
})

// 2026-08-23 «una cosa se avisa en un solo lugar»: la tarjeta «Leads sin
// movimiento» desaparece y pasa a ser una pestaña de la cola. Con el reloj del
// fixture (mié 15-jul 10:00) un lead «contactado» del 1-jul lleva 14 días sin
// actividad (seguimiento de severidad baja + estancado) y un «nuevo» del 13-jul
// es «sin responder» de severidad media.
describe('Hoy · supervisor — cola con pestañas', () => {
  const viejo = lead({ id: 'viejo', nombre_completo: 'VIEJO SIN MOVER', creado_en: '2026-07-01T15:00:00Z' })
  const nuevo = lead({ id: 'nuevo', nombre_completo: 'NUEVO SIN RESPONDER', etapa: 'nuevo', creado_en: '2026-07-13T15:00:00Z' })

  it('una sola tarjeta: pestañas con conteo, aterriza en Urgente y ya no existe «Leads sin movimiento»', () => {
    montar({ leads: [viejo, nuevo] })
    expect(screen.queryByRole('heading', { name: 'Leads sin movimiento' })).not.toBeInTheDocument()
    const tabs = screen.getByRole('tablist', { name: 'Filtrar la cola' })
    expect(within(tabs).getByRole('tab', { name: 'Urgente: 1' })).toHaveAttribute('aria-selected', 'true')
    expect(within(tabs).getByRole('tab', { name: 'Sin movimiento: 1' })).toHaveAttribute('aria-selected', 'false')
    expect(within(tabs).getByRole('tab', { name: 'Todo: 2' })).toHaveAttribute('aria-selected', 'false')
    const panel = screen.getByRole('tabpanel')
    expect(panel).toHaveAttribute('aria-labelledby', 'tab-cola-urgente')
    expect(within(panel).getByRole('button', { name: 'Abrir ficha de NUEVO SIN RESPONDER' })).toBeInTheDocument()
    expect(within(panel).queryByRole('button', { name: 'Abrir ficha de VIEJO SIN MOVER' })).not.toBeInTheDocument()
  })

  it('«Sin movimiento» lista los estancados del RPC con su espera, en el mismo lugar', () => {
    montar({ leads: [viejo, nuevo] })
    fireEvent.click(screen.getByRole('tab', { name: 'Sin movimiento: 1' }))
    const panel = screen.getByRole('tabpanel')
    expect(panel).toHaveAttribute('aria-labelledby', 'tab-cola-sin_movimiento')
    expect(within(panel).getByRole('button', { name: 'Abrir ficha de VIEJO SIN MOVER' }))
      .toHaveTextContent('Sin actividad hace 14 días')
    expect(within(panel).queryByText('NUEVO SIN RESPONDER')).not.toBeInTheDocument()
  })

  it('«Todo» muestra la cola completa y el lead viejo sale una sola vez', () => {
    montar({ leads: [viejo, nuevo] })
    fireEvent.click(screen.getByRole('tab', { name: 'Todo: 2' }))
    const panel = screen.getByRole('tabpanel')
    expect(within(panel).getAllByRole('button', { name: /^Abrir ficha de/ })).toHaveLength(2)
  })

  it('las flechas recorren las pestañas y mueven el foco (tabindex itinerante)', () => {
    montar({ leads: [viejo, nuevo] })
    const urgente = screen.getByRole('tab', { name: 'Urgente: 1' })
    expect(urgente).toHaveAttribute('tabindex', '0')
    urgente.focus()
    fireEvent.keyDown(urgente, { key: 'ArrowRight' })
    const sinMovimiento = screen.getByRole('tab', { name: 'Sin movimiento: 1' })
    expect(sinMovimiento).toHaveAttribute('aria-selected', 'true')
    expect(sinMovimiento).toHaveAttribute('tabindex', '0')
    expect(urgente).toHaveAttribute('tabindex', '-1')
    expect(document.activeElement).toBe(sinMovimiento)
    fireEvent.keyDown(sinMovimiento, { key: 'ArrowLeft' })
    expect(screen.getByRole('tab', { name: 'Urgente: 1' })).toHaveAttribute('aria-selected', 'true')
  })

  it('aterriza en la primera pestaña con filas: sin urgentes cae en «Sin movimiento»', () => {
    montar({ leads: [viejo] })
    expect(screen.getByRole('tab', { name: 'Urgente: 0' })).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByRole('tab', { name: 'Sin movimiento: 1' })).toHaveAttribute('aria-selected', 'true')
  })

  it('ESTADO DE PRODUCCIÓN (sin leads): tres ceros, aterriza en «Todo» y el vacío es honesto', () => {
    montar({ leads: [] })
    expect(screen.getByRole('tab', { name: 'Todo: 0' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByText('Sin pendientes — el equipo está al día con todos sus leads abiertos.')).toBeInTheDocument()
    // Panel vacío ENFOCABLE (WAI-ARIA): sin interactivos dentro, Tab lo saltaría.
    expect(screen.getByRole('tabpanel')).toHaveAttribute('tabindex', '0')
    fireEvent.click(screen.getByRole('tab', { name: 'Urgente: 0' }))
    expect(screen.getByText('Nada urgente — ninguna fila crítica ni media en la cola.')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Sin movimiento: 0' }))
    expect(screen.getByText('Ningún lead del equipo lleva 5 días o más sin actividad.')).toBeInTheDocument()
    expect(screen.getByRole('tabpanel')).toHaveAttribute('tabindex', '0')
  })

  it('«Urgente» cuenta el TOTAL por severidad del RPC, no las filas recortadas a 100', () => {
    // 120 nuevos sin responder: el espejo (como el RPC) recorta items a 100,
    // pero porSev trae el universo completo. Antes la pestaña decía 100
    // mientras «Todo» decía 120 (hallazgo de Codex).
    montar({
      leads: Array.from({ length: 120 }, (_, i) => lead({
        id: `nuevo-${String(i).padStart(3, '0')}`,
        nombre_completo: `NUEVO ${i}`,
        etapa: 'nuevo',
        creado_en: '2026-07-13T15:00:00Z',
      })),
    })
    expect(screen.getByRole('tab', { name: 'Urgente: 120' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('tab', { name: 'Todo: 120' })).toBeInTheDocument()
    // El expansor tampoco miente: muestra 100 filas de un total de 120.
    expect(screen.getByRole('button', { name: /Ver los 100 más urgentes de 120/ })).toBeInTheDocument()
  })
})

describe('Hoy · supervisor — reparto compacto', () => {
  it('con pendientes concentra el reparto en un KPI enlazado y retira la bandeja duplicada', () => {
    montar({
      leads: [
        lead({
          id: 'l-parkeado-antiguo',
          nombre_completo: 'LEAD ANTIGUO',
          vendedor_id: null,
          creado_en: '2026-07-15T13:00:00Z',
        }),
        lead({
          id: 'l-parkeado-reciente',
          nombre_completo: 'LEAD RECIENTE',
          vendedor_id: null,
          creado_en: '2026-07-15T14:30:00Z',
        }),
      ],
    })

    const acceso = screen.getByRole('link', { name: 'Repartir 2 leads pendientes' })
    expect(acceso).toHaveAttribute('href', '#/derivaciones')
    expect(within(acceso).getByText('Por repartir')).toBeInTheDocument()
    expect(within(acceso).getByText('2')).toBeInTheDocument()
    expect(within(acceso).getByText('Más rezagado: hace 2 h · Repartir →')).toBeInTheDocument()
    expect(within(acceso).getByTestId('reparto-pendiente-acento')).toBeInTheDocument()

    acceso.focus()
    expect(acceso).toHaveFocus()
    expect(screen.queryByRole('heading', { name: 'Por repartir — tu bandeja' })).not.toBeInTheDocument()
    expect(screen.queryByRole('combobox', { name: /Vendedor para/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Asignar/i })).not.toBeInTheDocument()
  })

  it('sin pendientes conserva el acceso compacto, neutral y sin afirmar una alerta', () => {
    montar({ leads: [lead()] })

    const acceso = screen.getByRole('link', { name: 'Ver derivaciones; bandeja sin pendientes' })
    expect(acceso).toHaveAttribute('href', '#/derivaciones')
    expect(within(acceso).getByText('Por repartir')).toBeInTheDocument()
    expect(within(acceso).getByText('0')).toBeInTheDocument()
    expect(within(acceso).getByText('Bandeja al día · Ver historial →')).toBeInTheDocument()
    expect(within(acceso).queryByTestId('reparto-pendiente-acento')).not.toBeInTheDocument()
  })

  it('usa el conteo del servidor aunque el cliente solo tenga parte del detalle', () => {
    TOTAL_PARKEADOS_RPC = 7
    montar({
      leads: [
        lead({
          vendedor_id: null,
          creado_en: '2026-07-15T13:00:00Z',
        }),
      ],
    })

    const acceso = screen.getByRole('link', { name: 'Repartir 7 leads pendientes' })
    expect(within(acceso).getByText('7')).toBeInTheDocument()
    expect(within(acceso).getByText('Más rezagado: hace 2 h · Repartir →')).toBeInTheDocument()
  })

  it('sin resumen mantiene el destino y evita inventar un conteo o una alerta', () => {
    TOTAL_PARKEADOS_RPC = null
    montar({
      leads: [lead({ vendedor_id: null })],
    })

    const acceso = screen.getByRole('link', {
      name: 'Ver derivaciones; total por repartir no disponible',
    })
    expect(acceso).toHaveAttribute('href', '#/derivaciones')
    expect(within(acceso).getByText('—')).toBeInTheDocument()
    expect(within(acceso).getByText('Sin dato por ahora · Ver derivaciones →')).toBeInTheDocument()
    expect(within(acceso).queryByTestId('reparto-pendiente-acento')).not.toBeInTheDocument()
  })
})

describe('Hoy · supervisor — meta del equipo', () => {
  it('la conversión del equipo proviene de la RPC MENSUAL, no del cumplimiento ni del pipeline', () => {
    // El cumplimiento dice 80 % (fórmula vieja); la RPC mensual, 50 % con 10
    // recibidos. El tile pinta la mensual: número nuevo bajo rótulo nuevo (E1).
    CONVERSION_MENSUAL = conversionMensualEquipo(50, 10)
    montar({
      leads: [
        lead({ id: 'l-c', etapa: 'convertido' }),
        lead({ id: 'l-d', etapa: 'descartado' }),
        lead({ id: 'l-abierto', etapa: 'propuesta_enviada' }),
      ],
      objetivos: { conversionObjetivo: 50 },
      // La meta viaja en el snapshot, que es contra lo que se mide.
      cumplimiento: cumplimientoSupervisor(80, 2, 'con-metas', 50),
    })

    expect(screen.getByText('50% de 50% · 10 recibidos')).toBeInTheDocument()
  })

  it('un mes sin leads RECIBIDOS es SIN DATO, no un 0 % en rojo crítico', () => {
    CONVERSION_MENSUAL = conversionMensualEquipo(null, 0)
    montar({
      leads: [lead({ id: 'l-abierto', etapa: 'propuesta_enviada' })],
      objetivos: { conversionObjetivo: 40 },
      cumplimiento: cumplimientoSupervisor(null, 0, 'con-metas', 40),
    })

    expect(screen.getByText('Sin leads recibidos este mes')).toBeInTheDocument()
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.queryByText('0% de 40%')).not.toBeInTheDocument()
  })

  it('no inventa una meta inicial de 15 % cuando no hay meta publicada', () => {
    CONVERSION_MENSUAL = conversionMensualEquipo(50, 4)
    montar({
      objetivos: { conversionObjetivo: 0 },
      cumplimiento: cumplimientoSupervisor(50, 2, 'sin-metas'),
    })

    // Las dos dimensiones: la revisión publicada vino en cero.
    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(2)
    expect(screen.queryByText('50% de 15%')).not.toBeInTheDocument()
    expect(screen.queryByText('0% de 0%')).not.toBeInTheDocument()
  })

  // Dos filas desde 2026-08-10: capital CONSOLIDADO y conversión. La fila de
  // dólares desapareció porque su meta era imposible de fijar —el editor
  // escribe todo en soles— y vivía en «Sin meta fijada» para siempre mientras
  // el capital real en USD no movía ninguna barra.
  it('sin ninguna meta publicada mantiene capital y conversión neutrales', () => {
    CONVERSION_MENSUAL = conversionMensualEquipo(100, 1)
    montar({
      objetivos: objetivosCero('2026-07-01').supervisor,
      cumplimiento: cumplimientoSupervisor(100, 1, 'sin-metas'),
    })

    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(2)
    expect(screen.queryByText('100% de 15%')).not.toBeInTheDocument()
    expect(screen.queryByText('Capital confirmado USD')).not.toBeInTheDocument()
  })

  it('si la lectura de metas falla no reemplaza el error por 15 %', () => {
    CONVERSION_MENSUAL = conversionMensualEquipo(30, 10)
    montar({
      objetivos: objetivosCero('2026-07-01').supervisor,
      objetivosError: true,
    })

    expect(screen.getAllByText('Meta mensual no disponible')).toHaveLength(2)
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
    // Solo el CAPITAL cuelga del cumplimiento; la conversión del mes viene de
    // su propia RPC y aquí, sin payload, declara su propio vacío.
    expect(screen.getAllByText('Cumplimiento confirmado no disponible')).toHaveLength(1)
    expect(screen.getByText('Sin datos de asignación para este mes')).toBeInTheDocument()
    expect(screen.getByText(/no cuenta como cumplimiento/)).toBeInTheDocument()
  })

  // El capital en dólares del equipo ENTRA al cumplimiento, convertido a tasa
  // real y con la tasa dicha. Antes vivía en su propia fila, sin meta posible,
  // sin mover ninguna barra: trabajo hecho que no contaba para nada.
  it('consolida los dólares del equipo al total y dice a qué tasa', () => {
    montar({ cumplimiento: cumplimientoSupervisor(40, 10) })

    expect(screen.getByText('Capital confirmado')).toBeInTheDocument()
    // Dos sitios rotulan la tasa: el cumplimiento del mes y «Tu equipo hoy»,
    // que también convierte USD→PEN y era el único punto del CRM que no decía
    // a qué tasa lo hacía.
    expect(screen.getAllByText(/TC S\/ 3\.5/).length).toBeGreaterThanOrEqual(2)
    expect(screen.getAllByText(/BCRP/).length).toBeGreaterThanOrEqual(2)
    // Y la nota del desglose enseña las dos monedas por separado.
    expect(screen.getByText(/S\/ .* \+ US\$/)).toBeInTheDocument()
  })

  // Sin tipo de cambio NO se inventa la conversión: el total se queda en soles
  // y se dice que los dólares no están dentro.
  it('sin tipo de cambio avisa en vez de consolidar a ciegas', () => {
    TIPO_CAMBIO.tc = null
    montar({ cumplimiento: cumplimientoSupervisor(40, 10) })

    expect(screen.getByText(/sin tipo de cambio: el total NO incluye los dólares/))
      .toBeInTheDocument()
  })

  // ESTADO DE PRODUCCIÓN (2026-08-10): ninguna revisión de metas publicada, así
  // que el cumplimiento llega NULO sin que haya fallado nada. Ni un solo test
  // cubría este caso, que es el que un supervisor real ve hoy.
  it('sin metas publicadas ni error no pinta ceros ni barras rojas', () => {
    CONVERSION_MENSUAL = conversionMensualEquipo(25, 8)
    montar({
      objetivos: objetivosCero('2026-07-01').supervisor,
      cumplimiento: null,
      cumplimientoError: false,
    })

    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(2)
    expect(screen.queryByText('0%')).not.toBeInTheDocument()
    expect(screen.queryByRole('progressbar')).not.toBeInTheDocument()
  })
})
