// Tests de integración de HOY del supervisor: reparto compacto y tarjeta
// mensual de monto/conversión del equipo.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante y
// sin fijarlo estos tests pasarían o fallarían según el día en que se ejecuten.
import { StrictMode } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { CUMPLIMIENTO_METAS_DEMO, METAS_DEMO } from '@/lib/demo'
import { ContextoSplashVisible } from '@/lib/splash-visible'
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
const RECARGAR_TIPO_CAMBIO = vi.fn()
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
  useTipoCambio: () => ({ tc: TIPO_CAMBIO.tc, recargar: RECARGAR_TIPO_CAMBIO }),
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
let CONVERSION_MENSUAL_PENDING = false
const REFETCH_CONVERSION_MENSUAL = vi.fn()
let METRICAS_AGENDA: import('@/lib/metricas-agenda').MetricasAgenda | undefined
vi.mock('@/data/crm-queries', () => ({
  useMetricasAgenda: () => ({
    data: METRICAS_AGENDA,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
  useConversionMensual: () => ({
    data: CONVERSION_MENSUAL ?? undefined,
    isError: CONVERSION_MENSUAL_ERROR,
    isPending: CONVERSION_MENSUAL_PENDING,
    isFetching: CONVERSION_MENSUAL_PENDING,
    refetch: REFETCH_CONVERSION_MENSUAL,
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
// Knobs de la consulta real que el espejo no tiene: un refetch EN VUELO
// (F4.3 espera al payload fresco) y la cola CAÍDA (fail-closed → null).
let COLA_EN_VUELO = false
let COLA_CAIDA = false
vi.mock('@/data/use-cola-accion-operativa', async () => {
  const { colaAccionDesdeAmbito } = await import('@/lib/cola-accion')
  return {
    useColaAccionOperativa: (
      leads: Lead[],
      actividades: Actividad[],
      tareas: never[],
      indice?: ReadonlyMap<string, never>,
    ) => ({
      cola: COLA_CAIDA
        ? null
        : colaAccionDesdeAmbito(leads, actividades ?? [], tareas ?? [], Date.now(), indice),
      cargando: false,
      enVuelo: COLA_EN_VUELO,
      error: COLA_CAIDA ? new Error('cola caída') : null,
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
    vendedores?: Miembro[]
    objetivos?: Partial<ObjetivosPorRol['supervisor']>
    periodoObjetivos?: string
    objetivosError?: boolean
    cumplimiento?: CumplimientoMetasJerarquico | null
    cumplimientoError?: boolean
    /** F4.3: arrancar con el refetch de la cola EN VUELO. */
    colaEnVuelo?: boolean
    /** F4.3: montar detrás del splash (provider explícito). */
    splashVisible?: boolean
    /** F4.3: montar bajo StrictMode (doble efecto de desarrollo). */
    estricto?: boolean
  } = {},
): ReturnType<typeof render> {
  vi.setSystemTime(MIERCOLES_10AM)
  YO = {
    id: 's-1',
    nombre_completo: 'SUPERVISOR UNO',
    rol: 'supervisor',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  VENDEDORES = over.vendedores ?? []
  OBJETIVOS_ERROR = over.objetivosError ?? false
  CUMPLIMIENTO_ERROR = over.cumplimientoError ?? false
  OBJETIVOS = {
    ...METAS_DEMO,
    periodo: over.periodoObjetivos ?? '2026-07-01',
    supervisor: { ...METAS_DEMO.supervisor, ...over.objetivos },
  }
  CUMPLIMIENTO = over.cumplimiento == null
    ? (over.cumplimiento ?? null)
    : { ...over.cumplimiento, periodo: OBJETIVOS.periodo }
  COLA_EN_VUELO = over.colaEnVuelo ?? false
  COLA_CAIDA = false
  const pantalla = over.splashVisible == null
    ? <HoySupervisor />
    : (
        <ContextoSplashVisible.Provider value={over.splashVisible}>
          <HoySupervisor />
        </ContextoSplashVisible.Provider>
      )
  return render(over.estricto === true ? <StrictMode>{pantalla}</StrictMode> : pantalla)
}

/**
 * `metas` describe si la revisión publicada TRAE metas o viene en cero, porque
 * desde 2026-08-10 el avance se mide contra la FOTO del snapshot
 * (`metaVigente`): «no hay meta» ya no se simula poniendo `objetivos` a cero
 * mientras el cumplimiento sigue trayendo las suyas.
 */
/** Payload de alcance 'equipo' cuyo TOTAL trae el % y el divisor dados. */
function conversionMensualEquipo(pct: number | null, divisor: number): import('@/lib/conversion-mensual').ConversionMensual {
  const cartera = {
    conversiones_clientes: 0,
    conversiones_renovacion: 0,
    conversiones_upgrade: 0,
    capital_renovado_pen: 0,
    capital_renovado_usd: 0,
    capital_adicional_pen: 0,
    capital_adicional_usd: 0,
    renovaciones_sin_desglose: 0,
    operaciones_renovacion: 0,
    operaciones_upgrade: 0,
  }
  return {
    version: 1,
    generado_en: '2026-07-15T15:00:00Z',
    alcance: 'equipo',
    periodo: { mes: '2026-07', mes_nombre: 'julio', anio: 2026, zona: 'America/Lima', desde: '2026-07-01T05:00:00Z', hasta: '2026-08-01T05:00:00Z' },
    ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
    fuentes: { divisor: 'crm.lead_asignaciones.asignado_en', numerador: 'crm.lead_asignaciones.resultado_en', referido: 'crm.lead_asignaciones.origen' },
    cobertura: { medible: true, suelo_historico: null, motivo_no_medible: null, divisor_aproximado: 0, divisor_por_motivo: divisor > 0 ? { ingreso: divisor } : {}, cierres_sin_episodio: 0, fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 } },
    cartera,
    total: { analistas: divisor > 0 ? 1 : 0, divisor, cierres_no_referidos: 0, cierres_referidos: 0, cierres_de_arrastre: 0, referidos_recibidos: 0, numerador: pct == null ? 0 : (pct * divisor) / 100, conversion_pct: pct, referidos_aporta_pct: null, cartera },
    responsables: [],
  }
}

// Los dos primeros argumentos quedaron vestigiales con F3.3 («Conversión
// única»): CumplimientoAgregado ya no lleva conversionReal/convertidos/
// resueltos — la conversión pintada sale del mock del servidor
// (CONVERSION_MENSUAL). Se conservan los parámetros para no reescribir a
// los seis llamadores del release.
function cumplimientoSupervisor(
  _conversionReal: number | null,
  _resueltos: number,
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
    },
  }
}

beforeEach(() => {
  METRICAS_AGENDA = undefined
  CONVERSION_MENSUAL = null
  CONVERSION_MENSUAL_ERROR = false
  CONVERSION_MENSUAL_PENDING = false
  TIPO_CAMBIO.tc = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
  vi.useFakeTimers()
  vi.clearAllMocks()
  recargar.mockResolvedValue(true)
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  OBJETIVOS_ERROR = false
  TOTAL_PARKEADOS_RPC = undefined
})

afterEach(() => {
  vi.useRealTimers()
})

it('recarga una sola vez si la foto del store quedó en el mes anterior', () => {
  montar({ periodoObjetivos: '2026-06-01', estricto: true })

  expect(recargar).toHaveBeenCalledTimes(1)
})

it('nunca rotula la foto anterior como vigente y deja reintentar si el rollover falla', async () => {
  recargar.mockResolvedValue(false)
  CONVERSION_MENSUAL = conversionMensualEquipo(50, 2)
  montar({
    periodoObjetivos: '2026-06-01',
    objetivos: { conversionObjetivo: 99 },
  })

  await act(async () => {})

  expect(screen.queryByText(/de 99%/)).not.toBeInTheDocument()
  expect(screen.getAllByText('Meta mensual no disponible')).toHaveLength(2)
  fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
  await act(async () => {})
  expect(recargar).toHaveBeenCalledTimes(2)
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
    expect(within(panel).getByRole('button', { name: 'Abrir ficha de VIEJO SIN MOVER (sin asignar), sin actividad hace 14 días' }))
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

// F2 (2026-08-23) — presupuesto de color: la severidad se dice UNA vez (tira
// de 3 px), el bucket va en texto plano, el monto y el capital dejan el azul,
// el rezago del analista va en texto y solo el no-show repetido conserva un
// chip rojo, y el punto de semáforo solo aparece cuando hay señal.
// F3 (2026-08-23) — «Hoy, tres cosas»: la franja navy con las intervenciones
// del día (máx. 3, rojo primero), alimentada por las mismas fuentes de la
// pantalla. Con ella, el KPI «Nuevos sin responder» pierde su último rojo.
describe('Hoy · supervisor — «Hoy, tres cosas» (F3)', () => {
  const viejo = lead({ id: 'viejo', nombre_completo: 'VIEJO SIN MOVER', creado_en: '2026-07-01T15:00:00Z' })
  const nuevoLead = lead({ id: 'nuevo', nombre_completo: 'NUEVO SIN RESPONDER', etapa: 'nuevo', creado_en: '2026-07-13T15:00:00Z' })

  it('la franja muestra las cosas del día con su acción, rojo primero', () => {
    montar({ leads: [viejo, nuevoLead] })
    const franja = screen.getByRole('region', { name: 'Hoy, tres cosas' })
    const chips = within(franja).getAllByRole('button')
    // nuevo → «1 nuevo sin responder» (rojo, pestaña Urgente); viejo → sin movimiento.
    // Sin fotografía SLA el nuevo es severidad media → «esta semana» (F3 #1).
    expect(chips[0]).toHaveAccessibleName('esta semana: 1 nuevo sin responder — Ver')
    expect(within(franja).getByLabelText(/esta semana: 1 sin movimiento · el peor lleva 14 días — Ver/)).toBeInTheDocument()
  })

  it('«Ver» selecciona la pestaña Urgente y le lleva el foco', () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'setInterval', 'Date', 'requestAnimationFrame'] })
    montar({ leads: [viejo, nuevoLead] })
    // Aterrizó en Urgente; salto primero a otra pestaña para probar el regreso.
    fireEvent.click(screen.getByRole('tab', { name: 'Todo: 2' }))
    fireEvent.click(screen.getByRole('button', { name: 'esta semana: 1 nuevo sin responder — Ver' }))
    vi.advanceTimersByTime(50)
    const urgente = screen.getByRole('tab', { name: 'Urgente: 1' })
    expect(urgente).toHaveAttribute('aria-selected', 'true')
    expect(document.activeElement).toBe(urgente)
  })

  it('las cosas con destino de vista son enlaces reales', () => {
    METRICAS_AGENDA = { 
      version: 1,
      generado_en: '2026-07-15T15:00:00Z',
      periodo: { desde: '2026-07-09', hasta: '2026-07-15', dias: 7, zona: 'America/Lima' },
      vendedores: [{
        vendedor_id: 'v-1', nombre: 'CARLA DÍAZ', rol: 'vendedor', activo: true,
        toques: 5, toques_por_dia: 0.7, reuniones_realizadas: 0, completadas: 0,
        no_asistio: 2, canceladas: 0, pct_completadas: null, tareas_creadas: 0,
        reuniones_agendadas: 0, reprogramaciones: 0, pendientes: 0, vencidas: 0,
        leads_sin_accion: 0,
      }],
    } as import('@/lib/metricas-agenda').MetricasAgenda
    montar({ leads: [] })
    expect(screen.getByRole('link', { name: 'urgente hoy: CARLA DÍAZ: 2 citas sin asistir — Ver equipo' }))
      .toHaveAttribute('href', '#/equipo')
  })

  it('ESTADO DE PRODUCCIÓN (sin nada que hacer): la franja NO se pinta', () => {
    montar({ leads: [] })
    expect(screen.queryByRole('region', { name: 'Hoy, tres cosas' })).not.toBeInTheDocument()
  })

  it('con la franja viva, el KPI «Nuevos sin responder» ya no grita: icono neutro y sub sin «urge»', () => {
    montar({ leads: [nuevoLead] })
    expect(screen.getByText('Sin primer contacto')).toBeInTheDocument()
    expect(screen.queryByText(/urge/)).not.toBeInTheDocument()
    // El tile del icono queda en el gris neutro AUNQUE haya sin responder —
    // mata el mutante «volver rojo el KPI» que sobrevivía (Codex F3 #5).
    const chip = screen.getByText('Nuevos sin responder').parentElement
      ?.parentElement?.querySelector('.ac-chip') as HTMLElement
    expect(chip.style.getPropertyValue('--c')).toBe('#8b95a7')
  })
})

describe('Hoy · supervisor — jerarquía visual (F2)', () => {
  const viejo = lead({ id: 'viejo', nombre_completo: 'VIEJO SIN MOVER', creado_en: '2026-07-01T15:00:00Z' })
  const nuevoLead = lead({ id: 'nuevo', nombre_completo: 'NUEVO SIN RESPONDER', etapa: 'nuevo', creado_en: '2026-07-13T15:00:00Z' })

  const miembro = (over: Partial<Miembro> = {}): Miembro => ({
    perfil_id: 'v-1',
    nombre_completo: 'CARLA DÍAZ',
    rol_crm: 'vendedor',
    supervisor_id: 's-1',
    activo: true,
    ...over,
  })

  const metricaAgenda = (
    over: Partial<import('@/lib/metricas-agenda').MetricaAgendaVendedor> = {},
  ): import('@/lib/metricas-agenda').MetricasAgenda => ({
    version: 1,
    generado_en: '2026-07-15T15:00:00Z',
    periodo: { desde: '2026-07-09', hasta: '2026-07-15', dias: 7, zona: 'America/Lima' },
    vendedores: [{
      vendedor_id: 'v-1',
      nombre: 'CARLA DÍAZ',
      rol: 'vendedor',
      activo: true,
      toques: 5,
      toques_por_dia: 0.7,
      reuniones_realizadas: 1,
      completadas: 2,
      no_asistio: 0,
      canceladas: 0,
      pct_completadas: 100,
      tareas_creadas: 2,
      reuniones_agendadas: 1,
      reprogramaciones: 0,
      pendientes: 1,
      vencidas: 0,
      leads_sin_accion: 0,
      ...over,
    }],
  } as import('@/lib/metricas-agenda').MetricasAgenda)

  it('la fila de la cola lleva la severidad en la tira y el bucket en texto, sin badge ni monto azul', () => {
    montar({ leads: [nuevoLead] })
    const fila = screen.getByRole('button', { name: 'Abrir ficha de NUEVO SIN RESPONDER' })
    expect(fila).toHaveAttribute('data-sev', 'media')
    // La tira EXISTE (clase de ancho) y lleva el color de la severidad.
    expect(fila.className).toContain('border-l-[3px]')
    expect(fila).toHaveStyle({ borderLeftColor: '#d97706' })
    // El bucket dejó el badge: va en texto plano, delante del motivo.
    expect(within(fila).getByText('Sin responder · Entró hace 2 días · primer contacto pendiente')).toBeInTheDocument()
    // «sin asignar» también es texto, no badge ámbar (ac-chip = Badge soft).
    expect(within(fila).getByText('sin asignar').className).not.toContain('ac-chip')
    // El monto perdió el azul.
    const monto = within(fila).getByText('S/ 10k')
    expect(monto.className).toContain('text-muted-foreground')
    expect(monto.className).not.toContain('text-primary')
  })

  it('una fila de severidad baja no gasta color: tira transparente', () => {
    montar({ leads: [viejo] })
    fireEvent.click(screen.getByRole('tab', { name: 'Todo: 1' }))
    const fila = screen.getByRole('button', { name: 'Abrir ficha de VIEJO SIN MOVER' })
    expect(fila).toHaveAttribute('data-sev', 'baja')
    // Estilo inline directo: jsdom normaliza «transparent» y toHaveStyle no compara.
    expect(fila.style.borderLeftColor).toBe('transparent')
  })

  it('el rezago del analista va en texto pegado a la persona; solo el no-show repetido es chip', () => {
    METRICAS_AGENDA = metricaAgenda({ no_asistio: 2, vencidas: 3, leads_sin_accion: 1 })
    montar({ leads: [viejo], vendedores: [miembro()] })
    const fila = screen.getByText('CARLA DÍAZ').closest('div[class*="px-5"]') as HTMLElement
    expect(fila).toHaveTextContent('Última actividad hace 14 días · 3 vencidas · 1 sin acción')
    expect(within(fila).getByText('2 no asistió')).toBeInTheDocument()
  })

  it('un solo no-show NO es chip rojo: el rojo se reserva al patrón repetido', () => {
    METRICAS_AGENDA = metricaAgenda({ no_asistio: 1, vencidas: 1, leads_sin_accion: 0 })
    montar({ leads: [viejo], vendedores: [miembro()] })
    expect(screen.queryByText('1 no asistió')).not.toBeInTheDocument()
    expect(screen.getByText(/· 1 vencida/)).toBeInTheDocument()
  })

  it('actividad fresca PERO rezago de agenda: punto ámbar (el rezago también es señal)', () => {
    // Hallazgo de Codex sobre F2: quien tocó ayer pero arrastra vencidas
    // quedaba sin ninguna marca visual. El punto se enciende en ámbar.
    METRICAS_AGENDA = metricaAgenda({ no_asistio: 0, vencidas: 10, leads_sin_accion: 1 })
    montar({
      leads: [lead({ id: 'fresco', creado_en: '2026-07-14T15:00:00Z' })],
      vendedores: [miembro()],
    })
    expect(screen.getByTestId('equipo-semaforo')).toHaveStyle({ background: '#d97706' })
  })

  it('con actividad reciente y sin rezago el punto desaparece (azul «al día» ya no se pinta)', () => {
    montar({
      leads: [lead({ id: 'fresco', creado_en: '2026-07-14T15:00:00Z' })],
      vendedores: [miembro()],
    })
    expect(screen.queryByTestId('equipo-semaforo')).not.toBeInTheDocument()
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

    acceso.focus()
    expect(acceso).toHaveFocus()
    expect(screen.queryByRole('heading', { name: 'Por repartir — tu bandeja' })).not.toBeInTheDocument()
    expect(screen.queryByRole('combobox', { name: /Analista para/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Asignar/i })).not.toBeInTheDocument()
  })

  it('sin pendientes conserva el acceso compacto, neutral y sin afirmar una alerta', () => {
    montar({ leads: [lead()] })

    const acceso = screen.getByRole('link', { name: 'Ver derivaciones; bandeja sin pendientes' })
    expect(acceso).toHaveAttribute('href', '#/derivaciones')
    expect(within(acceso).getByText('Por repartir')).toBeInTheDocument()
    expect(within(acceso).getByText('0')).toBeInTheDocument()
    expect(within(acceso).getByText('Bandeja al día · Ver historial →')).toBeInTheDocument()
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
  })
})

describe('Hoy · supervisor — meta del equipo', () => {
  it('distingue la consulta mensual de un mes realmente sin datos', () => {
    CONVERSION_MENSUAL_PENDING = true
    montar({ cumplimiento: cumplimientoSupervisor(40, 10) })

    expect(screen.getByText('Calculando…')).toBeInTheDocument()
    expect(screen.getByText('Consultando la conversión del mes…')).toBeInTheDocument()
    expect(screen.queryByText('Sin datos de asignación para este mes')).not.toBeInTheDocument()
  })

  it('permite reintentar la conversión mensual sin recargar el store sano', () => {
    CONVERSION_MENSUAL_ERROR = true
    montar({ cumplimiento: cumplimientoSupervisor(40, 10) })

    expect(screen.getByText('Conversión del mes no disponible')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(REFETCH_CONVERSION_MENSUAL).toHaveBeenCalledTimes(1)
    expect(recargar).not.toHaveBeenCalled()
  })

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

    expect(screen.getByText('50.00% de 50% · 10 recibidos')).toBeInTheDocument()
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
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(RECARGAR_TIPO_CAMBIO).toHaveBeenCalledTimes(1)
  })

  it('mientras consulta el tipo de cambio no afirma que falló ni publica el subtotal', () => {
    TIPO_CAMBIO.tc = undefined
    montar({ cumplimiento: cumplimientoSupervisor(40, 10) })

    expect(screen.getByText('Calculando…')).toBeInTheDocument()
    expect(screen.getByText('Consultando el tipo de cambio para consolidar los dólares…')).toBeInTheDocument()
    expect(screen.queryByText(/sin tipo de cambio: el total NO incluye los dólares/)).not.toBeInTheDocument()
  })

  it('refresca el promedio móvil del tipo de cambio al comenzar otro día en Lima', () => {
    montar({ cumplimiento: cumplimientoSupervisor(40, 10) })

    act(() => {
      vi.setSystemTime(new Date('2026-07-16T15:00:00Z'))
      window.dispatchEvent(new Event('focus'))
    })

    expect(RECARGAR_TIPO_CAMBIO).toHaveBeenCalledTimes(1)
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

// ── F4.3: qué EMPEORÓ en «Sin movimiento» desde la última visita ─────────────
// La foto vive en localStorage POR supervisor; aquí se instala un almacén de
// mentira sobre el global para que el test no dependa del entorno.
describe('Hoy · supervisor — novedades de la visita (F4.3)', () => {
  const viejo = lead({ id: 'viejo', nombre_completo: 'VIEJO SIN MOVER', creado_en: '2026-07-01T15:00:00Z' })
  // 6 días sin actividad: estancado en ÁMBAR (5–6).
  const recienEstancado = lead({ id: 'recien', nombre_completo: 'RECIEN ESTANCADO', creado_en: '2026-07-09T15:00:00Z' })
  const sinResponder = lead({ id: 'nuevo', nombre_completo: 'NUEVO SIN RESPONDER', etapa: 'nuevo', creado_en: '2026-07-13T15:00:00Z' })
  const CLAVE = 'crm:sin-movimiento:visita:s-1'

  function instalarAlmacen(inicial: Record<string, string> = {}) {
    const datos = new Map(Object.entries(inicial))
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      value: {
        getItem: (k: string) => datos.get(k) ?? null,
        setItem: (k: string, v: string) => { datos.set(k, v) },
      },
    })
    return datos
  }

  it('la PRIMERA visita no marca nada y deja la foto anotada (ids y días, sin nombres)', () => {
    const datos = instalarAlmacen()
    montar({ leads: [viejo] })

    // Sin urgentes aterriza directo en «Sin movimiento»: eso ES una visita.
    expect(screen.getByRole('tab', { name: 'Sin movimiento: 1' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.queryByText(/Desde tu última visita/)).not.toBeInTheDocument()
    expect(screen.queryByText('Nuevo aquí')).not.toBeInTheDocument()

    const foto = JSON.parse(datos.get(CLAVE) ?? 'null') as { dias: Record<string, number> }
    expect(foto.dias).toEqual({ viejo: 14 })
    expect(datos.get(CLAVE)).not.toContain('VIEJO SIN MOVER')
  })

  it('la SEGUNDA visita marca al que ENTRÓ (chip violeta) y al que CRUZÓ a crítico (texto)', () => {
    // Foto anterior: al viejo se le vio en ÁMBAR (6 días); hoy lleva 14.
    instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6 } }),
    })
    montar({ leads: [viejo, recienEstancado] })

    const panel = screen.getByRole('tabpanel')
    expect(within(panel).getByText('Desde tu última visita: 1 nuevo · 1 cruzó a crítico')).toBeInTheDocument()
    // El que entró: chip CATEGÓRICO (violeta) + aria que lo dicta.
    const filaNueva = within(panel).getByRole('button', {
      name: 'Abrir ficha de RECIEN ESTANCADO (sin asignar), sin actividad hace 6 días, nuevo aquí desde tu última visita',
    })
    expect(within(filaNueva).getByText('Nuevo aquí')).toBeInTheDocument()
    // El que cruzó: SIN chip nuevo (la tira roja ya lo grita) — lo dice el texto.
    const filaCruzada = within(panel).getByRole('button', {
      name: 'Abrir ficha de VIEJO SIN MOVER (sin asignar), sin actividad hace 14 días, crítico desde tu última visita',
    })
    expect(filaCruzada).toHaveTextContent('· crítico desde tu última visita')
    expect(within(filaCruzada).queryByText('Nuevo aquí')).not.toBeInTheDocument()
  })

  it('la foto se CONGELA al abrir: reabrir la pestaña en la misma sesión limpia las marcas', () => {
    instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6 } }),
    })
    montar({ leads: [viejo, sinResponder] })

    // Aterriza en Urgente (hay un nuevo sin responder); visita Sin movimiento…
    fireEvent.click(screen.getByRole('tab', { name: 'Sin movimiento: 1' }))
    expect(screen.getByText(/cruzó a crítico/)).toBeInTheDocument()
    // …sale y vuelve: la visita anterior ya es ESTA, sin novedades.
    fireEvent.click(screen.getByRole('tab', { name: 'Todo: 2' }))
    fireEvent.click(screen.getByRole('tab', { name: 'Sin movimiento: 1' }))
    expect(screen.queryByText(/Desde tu última visita/)).not.toBeInTheDocument()
  })

  it('con el storage ROTO la pestaña se pinta completa y sin marcas (jamás revienta)', () => {
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      value: {
        getItem: () => { throw new Error('bloqueado') },
        setItem: () => { throw new Error('bloqueado') },
      },
    })
    montar({ leads: [viejo] })

    expect(screen.getByRole('button', { name: 'Abrir ficha de VIEJO SIN MOVER (sin asignar), sin actividad hace 14 días' })).toBeInTheDocument()
    expect(screen.queryByText(/Desde tu última visita/)).not.toBeInTheDocument()
  })

  it('una foto corrupta se ignora: sin marcas y la visita la REPARA', () => {
    const datos = instalarAlmacen({ [CLAVE]: '{roto' })
    montar({ leads: [viejo] })

    expect(screen.queryByText(/Desde tu última visita/)).not.toBeInTheDocument()
    expect((JSON.parse(datos.get(CLAVE) ?? 'null') as { dias: Record<string, number> }).dias)
      .toEqual({ viejo: 14 })
  })

  it('las marcas se CONGELAN durante la visita: lo que cruza o entra con la cola viva no gana marca', () => {
    // Visto en ámbar a 30 min de cumplir 7 días: cruzará DURANTE la visita.
    const casiCritico = lead({ id: 'casi', nombre_completo: 'CASI CRITICO', creado_en: '2026-07-08T15:30:00Z' })
    const datos = instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6, casi: 6 } }),
    })
    const leads = [viejo, casiCritico]
    montar({ leads })

    // Al abrir: solo el viejo cruzó (6 → 14); el casi-crítico sigue en 6.
    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
    const vistoEn = (JSON.parse(datos.get(CLAVE)!) as { vistoEn: string }).vistoEn

    // La cola sigue VIVA debajo: una hora después el casi-crítico ya está en
    // 7 días y un lead nuevo ENTRÓ a la lista…
    leads.push(lead({ id: 'durante', nombre_completo: 'ENTRO DURANTE', creado_en: '2026-07-09T15:00:00Z' }))
    act(() => { vi.advanceTimersByTime(3_600_000) })

    // …la severidad de la fila sí vive (ya dice 7 días), pero NADIE gana una
    // marca de novedad bajo el cursor: ni sufijo en el aria del que cruzó…
    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Abrir ficha de CASI CRITICO (sin asignar), sin actividad hace 7 días' }))
      .toBeInTheDocument()
    // …ni chip para el que entró…
    const filaDurante = screen.getByRole('button', { name: 'Abrir ficha de ENTRO DURANTE (sin asignar), sin actividad hace 6 días' })
    expect(within(filaDurante).queryByText('Nuevo aquí')).not.toBeInTheDocument()
    // …ni re-anotación: la foto guardada es la del instante de apertura.
    const foto = JSON.parse(datos.get(CLAVE)!) as { vistoEn: string; dias: Record<string, number> }
    expect(foto.vistoEn).toBe(vistoEn)
    expect(foto.dias['durante']).toBeUndefined()
  })

  it('bajo StrictMode (efectos dobles de desarrollo) las novedades NO desaparecen', () => {
    instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6 } }),
    })
    montar({ leads: [viejo], estricto: true })

    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
  })

  it('con el refetch EN VUELO la anotación espera al payload fresco', () => {
    const datos = instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6 } }),
    })
    montar({ leads: [viejo], colaEnVuelo: true })

    // La lista se ve, pero ni marcas ni anotación con una cola posiblemente vieja.
    expect(screen.getByRole('button', { name: 'Abrir ficha de VIEJO SIN MOVER (sin asignar), sin actividad hace 14 días' }))
      .toBeInTheDocument()
    expect(screen.queryByText(/Desde tu última visita/)).not.toBeInTheDocument()
    expect((JSON.parse(datos.get(CLAVE)!) as { dias: Record<string, number> }).dias).toEqual({ viejo: 6 })

    // Aterriza el payload fresco → visita anotada y marcas contra la foto anterior.
    COLA_EN_VUELO = false
    act(() => { vi.advanceTimersByTime(60_000) })
    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
    // `dias` viaja fraccional (el minuto avanzado se nota): basta con que la
    // foto haya pasado de los 6 vistos a los ~14 reales.
    expect((JSON.parse(datos.get(CLAVE)!) as { dias: Record<string, number> }).dias['viejo'])
      .toBeCloseTo(14, 1)
  })

  it('un refetch caído que quita y devuelve la cola NO fabrica otra visita ni borra las marcas', () => {
    const datos = instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6 } }),
    })
    montar({ leads: [viejo] })
    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
    const vistoEn = (JSON.parse(datos.get(CLAVE)!) as { vistoEn: string }).vistoEn

    // Se cae el refetch: fail-closed deja la cola en null y el panel se va…
    COLA_CAIDA = true
    act(() => { vi.advanceTimersByTime(60_000) })
    expect(screen.getByText('La cola del equipo no está disponible en este momento.')).toBeInTheDocument()

    // …y al recuperarse sigue la MISMA visita: marcas intactas, sin re-anotar.
    COLA_CAIDA = false
    act(() => { vi.advanceTimersByTime(60_000) })
    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
    expect((JSON.parse(datos.get(CLAVE)!) as { vistoEn: string }).vistoEn).toBe(vistoEn)
  })

  it('detrás del splash NO hay visita: se anota recién al quedar visible', () => {
    const datos = instalarAlmacen({
      [CLAVE]: JSON.stringify({ vistoEn: '2026-07-14T15:00:00.000Z', dias: { viejo: 6 } }),
    })
    const { rerender } = montar({ leads: [viejo], splashVisible: true })

    expect(screen.queryByText(/Desde tu última visita/)).not.toBeInTheDocument()
    expect((JSON.parse(datos.get(CLAVE)!) as { dias: Record<string, number> }).dias).toEqual({ viejo: 6 })

    // El splash termina: recién ahí cuenta la visita (nadie vio nada antes).
    rerender(
      <ContextoSplashVisible.Provider value={false}>
        <HoySupervisor />
      </ContextoSplashVisible.Provider>,
    )
    expect(screen.getByText('Desde tu última visita: 1 cruzó a crítico')).toBeInTheDocument()
    expect((JSON.parse(datos.get(CLAVE)!) as { dias: Record<string, number> }).dias).toEqual({ viejo: 14 })
  })
})
