// Estas pruebas ejercitan la vista legada; la cola activa se verifica en sla-operacion.test.tsx.
vi.mock('@/data/sla-operacion-queries', () => ({ useModoSla: () => ({ legado: true, activo: false, error: null }) }))
// Tests de integración de la pantalla "Hoy · Analista" — los cinco arreglos de
// la auditoría 2026-07-25, cada uno con su regresión:
//   1. la agenda héroe listaba TODA la agenda futura mientras su badge contaba
//      solo hoy (los números no cuadraban con las filas);
//   2. esa agenda venía CONGELADA del store (`Date.now()` dentro de un memo sin
//      dependencia temporal) y las vencidas nunca aparecían durante la jornada;
//   3. una meta que gerencia no fijó (objetivo 0) se pintaba en rojo crítico;
//   5. las filas "Sin próxima acción" no traían el botón Agendar;
//   6. la misma tarea vencida se listaba y contaba en la agenda Y en la cola.
//
// …y los tres que dejó vivos ESE arreglo (segunda ronda):
//   7. el anti-duplicado escondía de la cola TODAS las vencidas, pero la agenda
//      solo lista 3 y colapsa el resto en "+N más": las de más allá del corte
//      desaparecían de la pantalla, y encima la cola se declaraba "al día";
//   8. el viernes de higiene duplicaba cada vencida (franja ámbar + fila de
//      higiene) porque la exclusión que recibía `colaHigiene` era solo la cola
//      visible, que los viernes son únicamente los `sin_responder`;
//   9. la conversión sin nada resuelto en el mes (día 1) se pintaba en rojo
//      crítico: 0 % sobre un denominador que no existe.
//
// El reloj se fija con timers falsos: la pantalla entera (día operable, viernes
// de higiene, mes vigente) se deriva del instante, y sin fijarlo estos tests
// pasarían o fallarían según la hora en que se ejecuten.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { CUMPLIMIENTO_METAS_DEMO, METAS_DEMO } from '@/lib/demo'
import { objetivosCero, type CumplimientoMetasJerarquico, type ObjetivosPorRol } from '@/lib/objetivos'
import { money } from '@/lib/format'
import type { Actividad, Lead, Tarea, Yo } from '@/lib/tipos'
import type { ConversionMensual } from '@/lib/conversion-mensual'

// El arnés monta SIN QueryClientProvider a propósito (sin red): el hook de la
// conversión mensual se sustituye aquí y cada test decide qué payload «llegó».
// En demo la pantalla ni lo consulta (deriva de demo-conversion-mensual).
let CONVERSION_MENSUAL: ConversionMensual | null = null
let CONVERSION_MENSUAL_ERROR = false
let CONVERSION_MENSUAL_PENDING = false
const REFETCH_MENSUAL = vi.fn()
vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  return {
    ...actual,
    // Rentabilidad R3: sin solicitudes ni decisiones en estos escenarios (tienen sus propios tests).
    useSolicitudesTasa: () => ({ data: [], isPending: false, isError: false, refetch: () => {} }),
    // Fase 4d: la cartera propia viene del servidor; aquí, la misma foto del fixture.
    useLeadsPropios: () => ({ data: LEADS, isPending: false, isFetching: false, error: null, refetch: () => {} }),
    useResolverSolicitudTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    useResponderTopeTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    useResolucionTasa: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
    useSolicitarTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
    useConversionMensual: () => ({
      data: CONVERSION_MENSUAL ?? undefined,
      isError: CONVERSION_MENSUAL_ERROR,
      isPending: CONVERSION_MENSUAL_PENDING,
      isFetching: CONVERSION_MENSUAL_PENDING,
      refetch: REFETCH_MENSUAL,
    }),
  }
})

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5) — día normal, sin higiene.
const MIERCOLES_10AM = new Date('2026-07-15T15:00:00Z')
// Viernes 2026-07-17, 14:00 en Lima — el modo "viernes de higiene" (≥ 13:00).
const VIERNES_2PM = new Date('2026-07-17T19:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let TAREAS: Tarea[] = []
let ACTIVIDADES: Actividad[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero()
let OBJETIVOS_ERROR = false
let CUMPLIMIENTO: CumplimientoMetasJerarquico | null = null
let CUMPLIMIENTO_ERROR = false
const crearTarea = vi.fn()
const asegurarLead = vi.fn<(id: string) => Promise<boolean>>()
const recargar = vi.fn()
const abrirLead = vi.fn()
let COLA_CARGANDO = false
let COLA_ERROR = false

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead,
    ambito: { leads: LEADS, vendedores: [], esGlobal: false },
    actividades: ACTIVIDADES,
    tareas: TAREAS,
    objetivos: OBJETIVOS,
    objetivosError: OBJETIVOS_ERROR,
    cumplimientoMetas: CUMPLIMIENTO,
    cumplimientoMetasError: CUMPLIMIENTO_ERROR,
    recargar,
    // La agenda del STORE va SIEMPRE vacía a propósito: la pantalla debe
    // derivar la suya de `tareas` con el reloj vivo. Si alguien vuelve a
    // consumir este array, la agenda héroe se queda muda en todos los tests.
    agenda: [],
    reprogramarTarea: () => ({ ok: true }),
    crearTarea,
    tareasDe: (id: string) => TAREAS.filter((t) => t.lead_id === id && t.estado === 'pendiente' && t.activo),
  }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead: () => {} }),
}))
// El tipo de cambio viene de una edge; aquí se fija para que el CONSOLIDADO sea
// determinista. `TC = null` prueba el caso honesto: sin tasa, el total no puede
// incluir los dólares y la pantalla tiene que decirlo.
let TC: { promedio: number; fuente: string } | null | undefined = {
  promedio: 3.5,
  fuente: 'BCRP · prom. 7d',
}
const RECARGAR_TIPO_CAMBIO = vi.fn()
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
  useTipoCambio: () => ({ tc: TC, recargar: RECARGAR_TIPO_CAMBIO }),
}))
// El contador animado cuenta 0→N por requestAnimationFrame: con timers falsos
// el texto quedaría a medio camino y las aserciones serían una lotería.
vi.mock('@/components/common/animated-value', () => ({
  AnimatedValue: ({ value }: { value: string }) => <>{value}</>,
}))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({
    indice: new Map(),
    cargando: false,
    error: null,
    recargar: vi.fn(),
  }),
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
      cola:
        COLA_CARGANDO || COLA_ERROR
          ? null
          : colaAccionDesdeAmbito(leads, actividades ?? [], tareas ?? [], Date.now(), indice),
      cargando: COLA_CARGANDO,
      error: COLA_ERROR ? new Error('cola no disponible') : null,
      recargar: vi.fn(),
    }),
  }
})

const { HoyVendedor } = await import('./vendedor')

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

function tarea(over: Partial<Tarea> = {}): Tarea {
  return {
    id: 't-1',
    lead_id: 'l-1',
    tipo: 'llamada',
    titulo: 'Llamar a Ana',
    vence_en: '2026-07-15T16:00:00Z',
    estado: 'pendiente',
    reprogramaciones: 0,
    activo: true,
    creado_en: '2026-07-10T15:00:00Z',
    ...over,
  }
}

/** Actividad de contacto real: saca al lead del bucket speed-to-lead. */
function contacto(leadId: string, creadoEn: string): Actividad {
  return {
    id: `a-${leadId}-${creadoEn}`,
    lead_id: leadId,
    tipo: 'llamada_realizada',
    detalle: null,
    autor_nombre: 'ANALISTA UNO',
    creado_en: creadoEn,
  }
}

// CINCO vencidas del mismo analista (2026-07-08 … 12) — dos más de las que la
// franja ámbar de la agenda alcanza a listar. Cada lead con contacto real hace
// días para que ninguno caiga en speed-to-lead (la excepción que nunca se
// esconde) y todos con tarea pendiente (así no salen como "sin próxima acción").
const VENCIDOS = [
  { id: 'l-1', vence: '2026-07-08T20:00:00Z' },
  { id: 'l-2', vence: '2026-07-09T20:00:00Z' },
  { id: 'l-3', vence: '2026-07-10T20:00:00Z' },
  { id: 'l-4', vence: '2026-07-11T20:00:00Z' },
  { id: 'l-5', vence: '2026-07-12T20:00:00Z' },
]
const LEADS_VENCIDOS = VENCIDOS.map((v, i) => lead({ id: v.id, nombre_completo: `LEAD ${i + 1}` }))
const ACTS_VENCIDOS = VENCIDOS.map((v) => contacto(v.id, '2026-07-05T15:00:00Z'))
const TAREAS_VENCIDAS = VENCIDOS.map((v, i) =>
  tarea({
    id: `t-${i + 1}`,
    lead_id: v.id,
    titulo: `Tarea ${i + 1}`,
    vence_en: v.vence,
  }),
)

function montar(
  over: {
    ahora?: Date
    leads?: Lead[]
    tareas?: Tarea[]
    actividades?: Actividad[]
    objetivos?: Partial<ObjetivosPorRol['vendedor']>
    periodoObjetivos?: string
    /** El store no pudo LEER las metas: sus ceros no son un dato. */
    objetivosError?: boolean
    cumplimiento?: CumplimientoMetasJerarquico | null
    cumplimientoError?: boolean
  } = {},
): void {
  vi.setSystemTime(over.ahora ?? MIERCOLES_10AM)
  YO = {
    id: 'v-1',
    nombre_completo: 'ANALISTA UNO',
    rol: 'vendedor',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  TAREAS = over.tareas ?? []
  ACTIVIDADES = over.actividades ?? []
  OBJETIVOS_ERROR = over.objetivosError ?? false
  CUMPLIMIENTO_ERROR = over.cumplimientoError ?? false
  OBJETIVOS = {
    ...METAS_DEMO,
    periodo: over.periodoObjetivos ?? '2026-07-01',
    vendedor: { ...METAS_DEMO.vendedor, ...over.objetivos },
  }
  CUMPLIMIENTO = over.cumplimiento == null
    ? (over.cumplimiento ?? null)
    : { ...over.cumplimiento, periodo: OBJETIVOS.periodo }
  render(<HoyVendedor />)
}

/**
 * `metas` describe si la revisión publicada TRAE metas o viene en cero. Es un
 * parámetro y no un detalle del fixture porque desde 2026-08-10 el avance se
 * mide contra la foto del snapshot: «no hay meta» ya no se simula poniendo
 * `objetivos` a cero mientras el cumplimiento sigue trayendo las suyas — eso
 * describía un mundo que producción no puede generar.
 */
function cumplimientoVendedor(
  conversionReal: number | null,
  resueltos: number,
  metas: 'con-metas' | 'sin-metas' = 'con-metas',
  metaConversion?: number,
): CumplimientoMetasJerarquico {
  const base = CUMPLIMIENTO_METAS_DEMO.vendedor
  if (!base) throw new Error('fixture demo sin analista')
  return {
    ...CUMPLIMIENTO_METAS_DEMO,
    vendedor: {
      ...base,
      ...(metas === 'sin-metas'
        ? {
            conversionObjetivo: 0,
            detalles: base.detalles.map((d) => ({
              ...d,
              capitalObjetivo: 0,
              contratosObjetivo: 0,
            })),
          }
        : {}),
      ...(metaConversion == null ? {} : { conversionObjetivo: metaConversion }),
      conversionReal,
      convertidos: conversionReal == null ? 0 : Math.round((conversionReal * resueltos) / 100),
      resueltos,
    },
  }
}

/**
 * Payload mínimo de `crm.conversion_mensual_fn` con la fila del propio analista
 * (alcance 'propio'). Es la fuente NUEVA del tile «Conversión del mes» — el
 * cumplimiento ya no manda ahí (decisión E1: rótulo nuevo sobre número nuevo,
 * sin esperar a la migración B).
 */
function conversionMensualPropia(
  conversionPct: number | null,
  divisor: number,
  extras: Partial<ConversionMensual['responsables'][number]> = {},
): ConversionMensual {
  const cierres = extras.cierres_no_referidos ?? (conversionPct == null ? 0 : 1)
  const carteraResponsable: ConversionMensual['responsables'][number]['cartera'] = {
    conversiones_clientes: 0,
    conversiones_renovacion: 0,
    conversiones_upgrade: 0,
    capital_renovado_pen: 0,
    capital_renovado_usd: 0,
    capital_adicional_pen: 0,
    capital_adicional_usd: 0,
    renovaciones_sin_desglose: 0,
  }
  const carteraTotal: ConversionMensual['cartera'] = {
    ...carteraResponsable,
    operaciones_renovacion: 0,
    operaciones_upgrade: 0,
  }
  const fila: ConversionMensual['responsables'][number] = {
    vendedor_id: 'v-1',
    supervisor_id: null,
    divisor,
    cierres_no_referidos: cierres,
    cierres_referidos: 0,
    cierres_de_arrastre: 0,
    numerador: cierres,
    conversion_pct: conversionPct,
    estado: divisor > 0 ? 'medible' : cierres > 0 ? 'solo_arrastre' : 'sin_actividad',
    procedencia: [],
    referidos: {
      recibidos: 0,
      cerrados: 0,
      dados_de_alta: 0,
      aporta_pct: null,
    },
    ...extras,
    // La ausencia ya no significa cero: cada fixture declara su versión del
    // contrato y solo sobrescribe cartera cuando la prueba realmente la usa.
    cartera: extras.cartera ?? carteraResponsable,
  }
  return {
    version: 1,
    generado_en: '2026-07-15T15:00:00Z',
    alcance: 'propio',
    periodo: {
      mes: '2026-07',
      mes_nombre: 'julio',
      anio: 2026,
      zona: 'America/Lima',
      desde: '2026-07-01T05:00:00Z',
      hasta: '2026-08-01T05:00:00Z',
    },
    ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
    fuentes: {
      divisor: 'crm.lead_asignaciones.asignado_en',
      numerador: 'crm.lead_asignaciones.resultado_en',
      referido: 'crm.lead_asignaciones.origen',
    },
    cobertura: {
      medible: true,
      suelo_historico: null,
      motivo_no_medible: null,
      divisor_aproximado: 0,
      divisor_por_motivo: divisor > 0 ? { ingreso: divisor } : {},
      cierres_sin_episodio: 0,
      fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
    },
    cartera: carteraTotal,
    total: {
      analistas: 1,
      divisor,
      cierres_no_referidos: fila.cierres_no_referidos,
      cierres_referidos: fila.cierres_referidos,
      cierres_de_arrastre: fila.cierres_de_arrastre,
      referidos_recibidos: fila.referidos.recibidos,
      numerador: fila.numerador,
      conversion_pct: conversionPct,
      referidos_aporta_pct: null,
      cartera: carteraTotal,
    },
    responsables: [fila],
  }
}

/** Meta del analista con importes exactos por moneda (todo en la categoría
 *  'nuevo'; el panel agrega por moneda, así que la categoría da igual). */
function metaPenUsd(pen: number, usd: number): ObjetivosPorRol['vendedor'] {
  const base = objetivosCero('2026-07-01').vendedor
  return {
    ...base,
    detalles: base.detalles.map((d) =>
      d.categoria === 'nuevo' ? { ...d, capitalObjetivo: d.moneda === 'PEN' ? pen : usd } : d,
    ),
  }
}

/**
 * Cumplimiento con capital CERRADO exacto por moneda, y con la META DENTRO.
 *
 * La meta viaja aquí y no solo en `objetivos` porque desde 2026-08-10 el avance
 * se mide contra la FOTO del snapshot (`metaVigente`): meta y producción del
 * mismo origen. Un fixture que declarase una meta en `objetivos` y otra distinta
 * en el cumplimiento describiría un mundo que producción no puede generar.
 */
function cumplimientoPenUsd(
  pen: number,
  usd: number,
  metaPen = 150_000,
  metaUsd = 20_000,
): CumplimientoMetasJerarquico {
  const base = cumplimientoVendedor(50, 2)
  const vendedor = base.vendedor
  if (!vendedor) throw new Error('fixture demo sin analista')
  return {
    ...base,
    vendedor: {
      ...vendedor,
      detalles: vendedor.detalles.map((d) => ({
        ...d,
        capitalObjetivo: d.categoria === 'nuevo' ? (d.moneda === 'PEN' ? metaPen : metaUsd) : 0,
        capitalReal: d.categoria === 'nuevo' ? (d.moneda === 'PEN' ? pen : usd) : 0,
      })),
    },
  }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.clearAllMocks()
  recargar.mockResolvedValue(true)
  crearTarea.mockReturnValue({ ok: true, id: 't-nueva' })
  asegurarLead.mockResolvedValue(true)
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  OBJETIVOS_ERROR = false
  // ESTADO DE PRODUCCIÓN por defecto: la RPC de conversión no respondió nada.
  // Cada test que quiera un mes medible siembra su propio payload.
  CONVERSION_MENSUAL = null
  CONVERSION_MENSUAL_ERROR = false
  CONVERSION_MENSUAL_PENDING = false
  COLA_CARGANDO = false
  COLA_ERROR = false
  TC = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
})

afterEach(() => {
  vi.useRealTimers()
})

it('recarga una sola vez si la foto del store quedó en el mes anterior', () => {
  montar({ periodoObjetivos: '2026-06-01' })

  expect(recargar).toHaveBeenCalledTimes(1)
})

it('no reutiliza la meta del mes anterior y deja reintentar un rollover fallido', async () => {
  recargar.mockResolvedValue(false)
  CONVERSION_MENSUAL = conversionMensualPropia(50, 2)
  montar({
    periodoObjetivos: '2026-06-01',
    objetivos: { conversionObjetivo: 99 },
  })

  await act(async () => {})

  expect(screen.queryByText('meta 99%')).not.toBeInTheDocument()
  expect(screen.getByText('No pudimos cargar toda la información mensual.')).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
  await act(async () => {})
  expect(recargar).toHaveBeenCalledTimes(2)
})

describe('Hoy · analista — contrato perceptual de Ahora', () => {
  it('muestra como máximo tres decisiones, una por lead, y abre la ficha desde la prioridad', () => {
    montar({
      leads: Array.from({ length: 4 }, (_, i) =>
        lead({
          id: `l-${i + 1}`,
          nombre_completo: `LEAD PRIORIDAD ${i + 1}`,
          etapa: 'nuevo',
          creado_en: `2026-07-15T14:0${i}:00Z`,
        }),
      ),
    })

    const ahora = screen.getByRole('region', {
      name: 'Tu siguiente movimiento',
    })
    expect(within(ahora).getAllByText(/^Prioridad 0[1-3]$/)).toHaveLength(3)
    expect(within(ahora).getByText('3 de 4 señales priorizadas')).toBeInTheDocument()

    const primera = within(ahora).getByText('LEAD PRIORIDAD 1').closest('article')
    expect(primera).not.toBeNull()
    fireEvent.click(
      within(primera as HTMLElement).getByRole('button', {
        name: /ver ficha/i,
      }),
    )
    expect(abrirLead).toHaveBeenCalledWith('l-1')
  })

  it('muestra skeleton y no declara la cartera al día mientras la cola está cargando', () => {
    COLA_CARGANDO = true
    montar({ leads: [lead({ etapa: 'nuevo' })] })

    expect(screen.getByRole('status', { name: 'Cargando próximas acciones' })).toBeInTheDocument()
    expect(screen.queryByText('No tienes una intervención pendiente')).not.toBeInTheDocument()
    expect(screen.queryByText('Al día ✦ sin pendientes')).not.toBeInTheDocument()
  })

  it('explica el dato parcial y conserva la agenda cuando falla la cola', () => {
    COLA_ERROR = true
    montar({ tareas: [tarea({ titulo: 'Seguimiento conservado' })] })

    expect(screen.getByText('Seguimiento conservado')).toBeInTheDocument()
    expect(screen.getByText(/Mostramos lo que sí llegó de tu agenda/)).toBeInTheDocument()
    expect(screen.queryByText('Tu agenda y tu cartera están al día')).not.toBeInTheDocument()
  })

  it('mantiene el cumplimiento mensual colapsado hasta que el analista lo pide', () => {
    montar()

    const resumen = screen.getByText('Tu cumplimiento del mes').closest('summary')
    const detalle = resumen?.closest('details')
    expect(detalle).not.toBeNull()
    expect(detalle).not.toHaveAttribute('open')

    fireEvent.click(resumen as HTMLElement)
    expect(detalle).toHaveAttribute('open')
  })
})

describe('Hoy · analista — agenda héroe', () => {
  it('lista solo el día operable: las citas de días futuros no se pintan (el badge cuadra con las filas)', () => {
    montar({
      leads: [lead({ id: 'l-1' }), lead({ id: 'l-2', nombre_completo: 'BRUNO DÍAZ' })],
      tareas: [
        tarea({
          id: 't-hoy',
          lead_id: 'l-1',
          titulo: 'Llamar a Ana',
          vence_en: '2026-07-15T20:00:00Z',
        }),
        tarea({
          id: 't-lejos',
          lead_id: 'l-2',
          titulo: 'Llamar a Bruno',
          vence_en: '2026-07-22T20:00:00Z',
        }),
      ],
    })

    expect(screen.getByText('Llamar a Ana')).toBeInTheDocument()
    expect(screen.queryByText('Llamar a Bruno')).not.toBeInTheDocument()
    // La señal operable sube a «Ahora» con su fecha y hora; la futura no
    // compite por atención ni infla el conteo.
    expect(screen.getByText('Hoy · 15:00')).toBeInTheDocument()
    expect(screen.getByText('1 de 1 señal priorizadas')).toBeInTheDocument()
  })

  it('un día sin nada operable se lee VACÍO aunque haya agenda futura', () => {
    montar({
      tareas: [
        tarea({
          id: 't-lejos',
          titulo: 'Llamar a Ana',
          vence_en: '2026-07-30T20:00:00Z',
        }),
      ],
    })

    expect(screen.getByText('Sin citas para hoy')).toBeInTheDocument()
    expect(screen.queryByText('Llamar a Ana')).not.toBeInTheDocument()
  })

  it('sigue al reloj vivo: la cita de hoy pasa a VENCIDA sola, sin recargar', () => {
    montar({
      tareas: [
        tarea({
          id: 't-hoy',
          titulo: 'Llamar a Ana',
          vence_en: '2026-07-15T15:00:30Z',
        }),
      ],
    })

    expect(screen.queryByText('Vencida')).not.toBeInTheDocument()

    // Un tick del reloj vivo (useAhora: 60 s) y la tarea ya venció.
    act(() => {
      vi.advanceTimersByTime(60_000)
    })

    expect(screen.getByText('Vencida')).toBeInTheDocument()
    expect(screen.getByText('Llamar a Ana')).toBeInTheDocument()
  })

  it('la tarea vencida NO se repite en la cola de al lado (una sola vez, un solo conteo)', () => {
    montar({
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      // Contacto real hace 10 días: sin él el lead caería en speed-to-lead,
      // que es la excepción que SÍ se queda en la cola.
      actividades: [contacto('l-1', '2026-07-05T15:00:00Z')],
      tareas: [
        tarea({
          id: 't-muerta',
          titulo: 'Llamar a Ana',
          vence_en: '2026-07-13T20:00:00Z',
        }),
      ],
    })

    expect(screen.getByText('Vencida')).toBeInTheDocument()
    // «Ahora» reúne contexto y acción, pero cada lead y tarea aparecen una
    // sola vez en toda la pantalla.
    expect(screen.getAllByText('ANA TORRES')).toHaveLength(1)
    expect(screen.getAllByText('Llamar a Ana')).toHaveLength(1)
    // La superficie inferior no puede cantar «al día» mientras arriba queda
    // una intervención abierta.
    expect(screen.queryByText('Al día ✦ sin pendientes')).not.toBeInTheDocument()
    expect(screen.getByText('Sin trabajo adicional')).toBeInTheDocument()
    expect(screen.getByText('Tus intervenciones están arriba. Aquí no queda trabajo adicional.')).toBeInTheDocument()
  })

  it('el speed-to-lead SÍ se queda en la cola aunque tenga una vencida (nunca se entierra)', () => {
    montar({
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES', etapa: 'nuevo' })],
      tareas: [
        tarea({
          id: 't-muerta',
          titulo: 'Llamar a Ana',
          vence_en: '2026-07-13T20:00:00Z',
        }),
      ],
    })

    expect(screen.getAllByText('ANA TORRES')).toHaveLength(1)
    expect(screen.getAllByText('Sin responder')).toHaveLength(1)
  })

  it('reparte las vencidas entre Ahora y Agenda sin perderlas ni repetirlas', () => {
    montar({
      leads: LEADS_VENCIDOS,
      actividades: ACTS_VENCIDOS,
      tareas: TAREAS_VENCIDAS,
    })

    expect(screen.getByText('3 de 5 señales priorizadas')).toBeInTheDocument()
    for (const titulo of ['Tarea 1', 'Tarea 2', 'Tarea 3', 'Tarea 4', 'Tarea 5']) {
      expect(screen.getAllByText(titulo)).toHaveLength(1)
    }
    // El remanente cabe en «Tu agenda de hoy»; la cola cede para no
    // presentar dos mandatos sobre el mismo lead.
    expect(screen.queryByText(/\+2 más vencidas/)).not.toBeInTheDocument()
    expect(screen.getByText('Lo pendiente está en tu agenda')).toBeInTheDocument()
  })

  // El pie "+N más vencidas" prometía SIEMPRE "las tienes en la cola de al
  // lado", y para las vencidas de HOY era falso: la agenda marca vencida por
  // HORA (lib/agenda-derivada) y el plan del lead muere por DÍA
  // (lib/plan-lead), así que una tarea que venció esta mañana deja al lead con
  // plan VIGENTE, `colaDe` lo salta y su fila no existe. Los dos criterios se
  // quedan como están —cada uno contesta bien una pregunta distinta— y lo que
  // se corrige es la frase, que ahora cuenta lo que hay abajo de verdad.
  it('las vencidas de HOY no se prometen en la cola: ahí NO están (su plan sigue vivo)', () => {
    montar({
      leads: LEADS_VENCIDOS,
      actividades: ACTS_VENCIDOS,
      // Las 5 vencieron HOY por la mañana (08:00–08:40 Lima), antes de las 10:00.
      tareas: VENCIDOS.map((v, i) =>
        tarea({
          id: `t-${i + 1}`,
          lead_id: v.id,
          titulo: `Tarea ${i + 1}`,
          vence_en: `2026-07-15T13:${String(i * 10).padStart(2, '0')}:00Z`,
        }),
      ),
    })

    for (const titulo of ['Tarea 1', 'Tarea 2', 'Tarea 3', 'Tarea 4', 'Tarea 5']) {
      expect(screen.getAllByText(titulo)).toHaveLength(1)
    }
    // La cola está vacía y remite al remanente visible de la agenda: no
    // promete una ubicación donde el trabajo no existe.
    expect(screen.getByText('Lo pendiente está en tu agenda')).toBeInTheDocument()
    expect(screen.queryByText(/cola de al lado/)).not.toBeInTheDocument()
  })

  it('una cita futura no duplica ni oculta el excedente operable', () => {
    montar({
      leads: LEADS_VENCIDOS,
      actividades: ACTS_VENCIDOS,
      // LEAD 5 tiene además una cita futura: conserva plan VIVO, así que la
      // cola lo salta y su vencida solo se puede trabajar desde Agenda.
      tareas: [
        ...TAREAS_VENCIDAS,
        tarea({
          id: 't-futura',
          lead_id: 'l-5',
          titulo: 'Reunión con LEAD 5',
          vence_en: '2026-07-22T20:00:00Z',
        }),
      ],
    })

    for (const titulo of ['Tarea 1', 'Tarea 2', 'Tarea 3', 'Tarea 4', 'Tarea 5']) {
      expect(screen.getAllByText(titulo)).toHaveLength(1)
    }
    expect(screen.queryByText('Cita con LEAD 5')).not.toBeInTheDocument()
    expect(screen.queryByText(/cola de al lado/)).not.toBeInTheDocument()
  })
})

// El analista abre esta pantalla cada mañana y su chip de capital fijaba PEN a
// mano: una cartera íntegramente en dólares se anunciaba como "S/ 0.00" con el
// capital real en la letra chica, contradiciendo a Cartera y a Pipeline sobre
// el mismo lead. El criterio vive ahora en lib/inteligencia (capitalPrincipal).
describe('Hoy · analista — capital en proceso', () => {
  it('una cartera 100 % en dólares se anuncia en dólares, no como "S/ 0.00"', () => {
    montar({
      leads: [lead({ id: 'l-usd', moneda: 'USD', monto_estimado: 40_000 })],
      actividades: [contacto('l-usd', '2026-07-14T15:00:00Z')],
    })

    expect(screen.getByText(money(40_000, 'USD'))).toBeInTheDocument()
    expect(screen.getByText('Pipeline activo (USD)')).toBeInTheDocument()
    expect(screen.queryByText(/Pipeline activo \(PEN\)/)).not.toBeInTheDocument()
  })

  it('con las dos monedas manda el PEN y el USD se dice aparte — JAMÁS sumados', () => {
    montar({
      leads: [
        lead({ id: 'l-pen', moneda: 'PEN', monto_estimado: 120_000 }),
        lead({
          id: 'l-usd',
          nombre_completo: 'BRUNO DÍAZ',
          moneda: 'USD',
          monto_estimado: 40_000,
        }),
      ],
      actividades: [contacto('l-pen', '2026-07-14T15:00:00Z'), contacto('l-usd', '2026-07-14T15:00:00Z')],
    })

    expect(screen.getByText(money(120_000))).toBeInTheDocument()
    expect(screen.getByText('Pipeline activo (PEN) · +US$ 40k aparte')).toBeInTheDocument()
    // Los 160 000 mixtos no existen en ninguna parte de la pantalla.
    expect(screen.queryByText(money(160_000))).not.toBeInTheDocument()
  })
})

describe('Hoy · analista — meta del mes', () => {
  it('distingue la consulta mensual de un mes realmente sin datos', () => {
    CONVERSION_MENSUAL_PENDING = true
    montar({ cumplimiento: cumplimientoVendedor(25, 1, 'con-metas', 50) })

    expect(screen.getByText('Consultando la conversión del mes…')).toBeInTheDocument()
    expect(screen.getByText('Tu cumplimiento del mes').closest('summary')).toHaveTextContent('Conversión consultando…')
    expect(screen.queryByText('Sin datos de asignación para este mes')).not.toBeInTheDocument()
  })

  it('la conversión proviene de la RPC MENSUAL (la definición), no del cumplimiento ni del pipeline', () => {
    // El cumplimiento dice 80 % (fórmula vieja, viva hasta la migración B) y la
    // RPC mensual dice 50 %: el tile pinta la MENSUAL. Rótulo nuevo sobre
    // número nuevo — jamás rótulo nuevo sobre número viejo (E1, plan §4bis).
    CONVERSION_MENSUAL = conversionMensualPropia(50, 10, {
      cierres_no_referidos: 5,
      numerador: 5,
    })
    montar({
      leads: [
        lead({ id: 'l-c', etapa: 'convertido' }),
        lead({ id: 'l-d', etapa: 'descartado' }),
        lead({ id: 'l-abierto', etapa: 'propuesta_enviada' }),
      ],
      objetivos: { conversionObjetivo: 50 },
      // La meta viaja en el snapshot, que es contra lo que se mide.
      cumplimiento: cumplimientoVendedor(80, 2, 'con-metas', 50),
    })

    expect(screen.getByText('Conversión del mes')).toBeInTheDocument()
    expect(screen.getByText('50.00%')).toBeInTheDocument()
    expect(screen.getByText('100% del objetivo')).toBeInTheDocument()
    // El divisor SIEMPRE al lado del %: se lo llena el reparto, no el analista.
    expect(screen.getByText(/Recibidos 10/)).toBeInTheDocument()
  })

  it('el descuento por anulaciones de un mes cerrado se dice al lado, con su porqué', () => {
    // El servidor ya sirve el numerador NETO (2 cierres − 1 anulado = 1): sin
    // el chip, su conversión «baja sola» — la llamada a soporte que el
    // servidor comenta. El detalle (mes, motivo, cuánto) viaja en el title.
    CONVERSION_MENSUAL = conversionMensualPropia(25, 4, {
      cierres_no_referidos: 2,
      numerador: 1,
      ajuste: {
        pendiente: 1,
        origenes: [{ periodo: '2026-06', motivo: 'Pago no confirmado', numerador: 1 }],
      },
    })
    montar({
      objetivos: { conversionObjetivo: 50 },
      cumplimiento: cumplimientoVendedor(25, 1, 'con-metas', 50),
    })

    // «arrastra», no «−N»: lo afirmable con lo que viaja es la DEUDA — el
    // descuento efectivo del mes es min(deuda, bruto) y el bruto no viaja.
    const chip = screen.getByText('arrastra 1 conversión de anulaciones · junio 2026')
    expect(chip).toHaveAttribute('title', 'junio 2026: Pago no confirmado (−1)')
  })

  it('sin arrastre no hay chip: −0 no existe', () => {
    CONVERSION_MENSUAL = conversionMensualPropia(50, 4, {
      cierres_no_referidos: 2,
      numerador: 2,
      ajuste: { pendiente: 0, origenes: [] },
    })
    montar({
      objetivos: { conversionObjetivo: 50 },
      cumplimiento: cumplimientoVendedor(50, 2, 'con-metas', 50),
    })

    expect(screen.queryByText(/de anulaciones|descontad/)).not.toBeInTheDocument()
  })

  it('la conversión mensual caída SE PUEDE reintentar (y reintenta LA query, no solo el store)', () => {
    CONVERSION_MENSUAL_ERROR = true
    REFETCH_MENSUAL.mockClear()
    montar({
      objetivos: { conversionObjetivo: 50 },
      cumplimiento: cumplimientoVendedor(25, 1, 'con-metas', 50),
    })

    expect(screen.getByText('Conversión del mes no disponible')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(REFETCH_MENSUAL).toHaveBeenCalledOnce()
  })

  // Decisión de Miguel (2026-08-14): un mes INCOMPLETO se ve. El caso real fue
  // agosto —3 recibidos, 1 cierre, 38,33 %— y la pantalla decía «Sin datos de
  // asignación para este mes», que era sencillamente falso: el ledger nace el
  // día 5 y al mes le faltan días, pero los datos existen.
  it('un mes incompleto SE VE, y al analista no se le cuenta por qué', () => {
    const base = conversionMensualPropia(38.33, 3, {
      cierres_no_referidos: 1,
      numerador: 1,
    })
    CONVERSION_MENSUAL = {
      ...base,
      cobertura: {
        ...base.cobertura,
        medible: false,
        motivo_no_medible: 'mes_parcial',
        suelo_historico: '2026-07-05T18:19:55Z',
      },
    }
    montar({ objetivos: { conversionObjetivo: 15 } })

    // Ve su número y su divisor…
    expect(screen.getByText('38.33%')).toBeInTheDocument()
    expect(screen.getByText(/Recibidos 3/)).toBeInTheDocument()
    // …y NO la frase que negaba los datos.
    expect(screen.queryByText(/Sin datos de asignación/i)).not.toBeInTheDocument()
    // El matiz de «provisional» es para supervisor y gerencia, no para él.
    expect(screen.queryByText(/Provisional/i)).not.toBeInTheDocument()
  })

  it('sin leads RECIBIDOS en el mes la conversión es SIN DATO, no un 0 % en rojo', () => {
    // Divisor 0 con actividad ninguna: el estado sin_actividad de la RPC.
    CONVERSION_MENSUAL = conversionMensualPropia(null, 0, {
      estado: 'sin_actividad',
      cierres_no_referidos: 0,
      numerador: 0,
    })
    montar({
      // Cartera viva, nada cerrado todavía: el día 1 de cada mes, para todos.
      leads: [lead({ id: 'l-1', etapa: 'contactado' })],
      objetivos: { conversionObjetivo: 40 },
      cumplimiento: cumplimientoVendedor(null, 0),
    })

    expect(screen.getByText('Sin leads recibidos este mes')).toBeInTheDocument()
    // Un porcentaje sin denominador no se escribe como 0 %, ni se compara con
    // la cuota: ni valor, ni barra, ni "% del objetivo" para esta fila.
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.queryByText('0%')).not.toBeInTheDocument()
    expect(screen.queryByText('meta 40%')).not.toBeInTheDocument()
  })

  it('no inventa una meta inicial de 15 % cuando no existe una revisión publicada', () => {
    CONVERSION_MENSUAL = conversionMensualPropia(50, 4, {
      cierres_no_referidos: 2,
      numerador: 2,
    })
    montar({
      objetivos: { conversionObjetivo: 0 },
      cumplimiento: cumplimientoVendedor(50, 2, 'sin-metas'),
    })

    // Las dos dimensiones quedan sin meta: la revisión publicada vino en cero.
    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(2)
    expect(screen.queryByText('meta 15%')).not.toBeInTheDocument()
    expect(screen.queryByText('meta 0%')).not.toBeInTheDocument()
  })

  it('sin ninguna meta publicada mantiene neutrales las dimensiones que se pintan', () => {
    CONVERSION_MENSUAL = conversionMensualPropia(100, 1, {
      cierres_no_referidos: 1,
      numerador: 1,
    })
    montar({
      objetivos: objetivosCero('2026-07-01').vendedor,
      cumplimiento: cumplimientoVendedor(100, 1, 'sin-metas'),
    })

    // Las DOS dimensiones del analista —capital consolidado y conversión— sin
    // juicio: una meta que nadie fijó no es un incumplimiento.
    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(2)
    expect(screen.queryByText('meta 15%')).not.toBeInTheDocument()
    // El capital cerrado en dólares del fixture SIGUE viéndose en el desglose:
    // sin meta no hay barra que pintar, pero el trabajo hecho no se esconde.
    expect(screen.getByText(/US\$/)).toBeInTheDocument()
  })

  it('si la LECTURA de metas falló no dice "por definir": lo confiesa y ofrece reintentar', () => {
    montar({
      objetivos: objetivosCero('2026-07-01').vendedor,
      objetivosError: true,
    })

    // Los mismos ceros, dos causas opuestas: afirmar que nadie fijó la meta
    // cuando lo que se cayó fue la red hace que el analista deje de buscarla.
    expect(screen.queryByText(/Meta mensual por definir/)).not.toBeInTheDocument()
    expect(screen.getByText('No pudimos cargar toda la información mensual.')).toBeInTheDocument()
    expect(screen.queryByText('meta 15%')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(recargar).toHaveBeenCalled()
  })

  // ── CAPITAL CONSOLIDADO (Miguel, 2026-08-10) ────────────────────────────────
  // «que vea cuánto ha metido en soles y en dólares, pero también, y como más
  // importante, el consolidado de las dos». El panel pasa a UNA cifra —el total
  // en soles al TC real— con el desglose por moneda debajo.
  it('un cierre en DÓLARES sube el avance: entra al total convertido al TC', () => {
    // 120k PEN + 20k USD a 3,5 → S/ 190k de capital; meta 150k PEN + 20k USD → S/ 220k.
    montar({
      objetivos: metaPenUsd(150_000, 20_000),
      cumplimiento: cumplimientoPenUsd(120_000, 20_000),
    })

    expect(screen.getByText('Capital confirmado')).toBeInTheDocument()
    expect(screen.getByText('S/ 190k')).toBeInTheDocument()
    expect(screen.getByText('meta S/ 220k')).toBeInTheDocument()
    // 190/220 = 86 % — el texto vive dentro de «86% del objetivo».
    expect(screen.getByText(/86%/)).toBeInTheDocument()
  })

  it('el desglose dice cuánto entró en cada moneda y a qué tasa se unificó', () => {
    montar({
      objetivos: metaPenUsd(150_000, 20_000),
      cumplimiento: cumplimientoPenUsd(120_000, 20_000),
    })

    const desglose = screen.getByText((_, el) => (el?.textContent ?? '').startsWith('S/ 120k + US$ 20k'), {
      selector: 'p',
    })
    // La tasa que se ROTULA es la que de verdad entró en el número.
    expect(desglose.textContent).toContain('TC S/ 3.5')
    expect(desglose.textContent).toContain('BCRP · prom. 7d')
  })

  it('sin dólares no se pinta desglose: repetiría el total', () => {
    montar({
      objetivos: metaPenUsd(150_000, 0),
      cumplimiento: cumplimientoPenUsd(120_000, 0, 150_000, 0),
    })

    expect(screen.getByText('S/ 120k')).toBeInTheDocument()
    expect(screen.queryByText(/US\$/)).not.toBeInTheDocument()
  })

  it('SIN tipo de cambio el total NO incluye los dólares, y lo dice', () => {
    TC = null
    montar({
      objetivos: metaPenUsd(150_000, 20_000),
      cumplimiento: cumplimientoPenUsd(120_000, 20_000),
    })

    // El total cae a los soles solos (120k) — jamás se inventa una tasa…
    expect(screen.getByText('S/ 120k')).toBeInTheDocument()
    // …y el analista tiene que enterarse de que le falta media moneda en el avance.
    expect(screen.getByText(/sin tipo de cambio: el total NO incluye los dólares/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(RECARGAR_TIPO_CAMBIO).toHaveBeenCalledTimes(1)
  })

  it('mientras consulta el tipo de cambio no publica un subtotal ni afirma un fallo', () => {
    TC = undefined
    montar({
      objetivos: metaPenUsd(150_000, 20_000),
      cumplimiento: cumplimientoPenUsd(120_000, 20_000),
    })

    expect(screen.getByText('Tu cumplimiento del mes').closest('summary')).toHaveTextContent('Capital consultando…')
    expect(screen.getByText('Consultando el tipo de cambio para consolidar los dólares…')).toBeInTheDocument()
    expect(screen.queryByText(/sin tipo de cambio: el total NO incluye los dólares/)).not.toBeInTheDocument()
  })

  it('refresca el promedio móvil del tipo de cambio al comenzar otro día en Lima', () => {
    montar({ cumplimiento: cumplimientoPenUsd(120_000, 20_000) })

    act(() => {
      vi.setSystemTime(new Date('2026-07-16T15:00:00Z'))
      window.dispatchEvent(new Event('focus'))
    })

    expect(RECARGAR_TIPO_CAMBIO).toHaveBeenCalledTimes(1)
  })

  // ⚠️ ESTE es el test que faltaba, y el que habría evitado un redespliegue: el
  // ESTADO REAL DE PRODUCCIÓN — gerencia no ha publicado ninguna revisión de
  // metas (`crm.meta_periodos` con 0 filas), así que el store degrada a
  // `objetivosCero` y el cumplimiento llega nulo. Una versión anterior decidía
  // qué pintar con un fail-safe de «no se sabe», y como ese es el estado de
  // TODOS los días, el arreglo no arreglaba nada. Ver `npm run gate:realidad`.
  it('ESTADO DE PRODUCCIÓN (sin metas publicadas): capital neutral y conversión sin fila propia', () => {
    // La base real HOY: la RPC responde (medible) pero el analista no tiene fila
    // — responsables vacío. El tile no inventa un 0 %: dice «sin leads
    // recibidos», que es la verdad.
    CONVERSION_MENSUAL = {
      ...conversionMensualPropia(null, 0, {
        estado: 'sin_actividad',
        cierres_no_referidos: 0,
        numerador: 0,
      }),
      responsables: [],
    }
    montar({
      objetivos: objetivosCero('2026-07-01').vendedor,
      cumplimiento: null,
    })

    expect(screen.getByText('Capital confirmado')).toBeInTheDocument()
    expect(screen.getByText('Conversión del mes')).toBeInTheDocument()
    // Capital sin meta publicada = neutral; conversión sin fila = sin dato.
    expect(screen.getAllByText('Sin meta fijada para este mes')).toHaveLength(1)
    expect(screen.getByText('Sin leads recibidos este mes')).toBeInTheDocument()
    expect(screen.queryByText('0%')).not.toBeInTheDocument()
    // Y ninguna columna suelta por moneda: eso era el ruido que se quitó.
    expect(screen.queryByText('Capital confirmado PEN')).not.toBeInTheDocument()
    expect(screen.queryByText('Capital confirmado USD')).not.toBeInTheDocument()
  })
  it('si falla el cumplimiento no usa el pronóstico abierto como sustituto', () => {
    montar({
      leads: [lead({ monto_estimado: 900_000, etapa: 'propuesta_enviada' })],
      cumplimiento: null,
      cumplimientoError: true,
    })

    expect(screen.getByText('S/ 900,000')).toBeInTheDocument()
    // Solo el CAPITAL depende del cumplimiento; la conversión del mes es fuente
    // independiente (RPC propia) y aquí, sin payload, dice su propio vacío.
    expect(screen.getAllByText('Cumplimiento confirmado no disponible')).toHaveLength(1)
    expect(screen.getByText('Sin datos de asignación para este mes')).toBeInTheDocument()
    expect(screen.getByText('Capital abierto')).toBeInTheDocument()
  })
})

describe('Hoy · analista — gestiones de clientes', () => {
  it('muestra en una franja postventa la reunión agendada desde Mi cartera', () => {
    montar({
      tareas: [
        tarea({
          id: 'tc-1',
          lead_id: null,
          perfil_id: 'cliente-1',
          vendedor_id: 'v-1',
          tipo: 'reunion',
          titulo: 'Reunión con Rosa',
        }),
      ],
    })

    expect(screen.getByText('Clientes por gestionar hoy')).toBeInTheDocument()
    expect(screen.getByText('Cita con Rosa')).toBeInTheDocument()
    expect(screen.getByText('Cliente')).toBeInTheDocument()
    expect(abrirLead).not.toHaveBeenCalled()
  })
})

describe('Hoy · analista — viernes de higiene', () => {
  it('las filas "Sin próxima acción" traen el botón Agendar', async () => {
    montar({
      ahora: VIERNES_2PM,
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      actividades: [contacto('l-1', '2026-07-17T18:00:00Z')],
      tareas: [],
    })

    expect(screen.getByText('Pendientes: viernes de higiene')).toBeInTheDocument()
    expect(screen.getByText('Sin urgencias inmediatas')).toBeInTheDocument()
    expect(screen.getByText(/Tienes 1 acción de preparación en “Pendientes”/)).toBeInTheDocument()
    expect(screen.getByText('Sin próxima acción')).toBeInTheDocument()

    const boton = screen.getByRole('button', {
      name: 'Agendar el siguiente paso con ANA TORRES',
    })
    fireEvent.click(boton)
    // Fase 4e: antes de agendar, el store asegura conocer el lead (asíncrono): se vacían las microtareas.
    await act(async () => { await Promise.resolve() })
    expect(crearTarea).toHaveBeenCalledWith(expect.objectContaining({ lead_id: 'l-1', tipo: 'llamada' }))
  })

  it('doble clic en Agendar crea UNA sola tarea (el await de red no abre la puerta al segundo)', async () => {
    montar({
      ahora: VIERNES_2PM,
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      actividades: [contacto('l-1', '2026-07-17T18:00:00Z')],
      tareas: [],
    })

    const boton = screen.getByRole('button', {
      name: 'Agendar el siguiente paso con ANA TORRES',
    })
    fireEvent.click(boton)
    fireEvent.click(boton)
    await act(async () => { await Promise.resolve() })
    expect(crearTarea).toHaveBeenCalledTimes(1)
  })

  it('tras un fallo de red, Agendar vuelve a quedar disponible (la guarda se libera)', async () => {
    asegurarLead.mockRejectedValueOnce(new Error('sin red'))
    montar({
      ahora: VIERNES_2PM,
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      actividades: [contacto('l-1', '2026-07-17T18:00:00Z')],
      tareas: [],
    })

    const boton = screen.getByRole('button', {
      name: 'Agendar el siguiente paso con ANA TORRES',
    })
    fireEvent.click(boton)
    await act(async () => { await Promise.resolve() })
    expect(crearTarea).not.toHaveBeenCalled()
    expect(boton).not.toBeDisabled()

    fireEvent.click(boton)
    await act(async () => { await Promise.resolve() })
    expect(crearTarea).toHaveBeenCalledTimes(1)
  })

  it('la vencida que la agenda YA lista no se repite como fila de higiene', () => {
    montar({
      ahora: VIERNES_2PM,
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      actividades: [contacto('l-1', '2026-07-10T15:00:00Z')],
      tareas: [
        tarea({
          id: 't-muerta',
          titulo: 'Llamar a Ana',
          vence_en: '2026-07-16T20:00:00Z',
        }),
      ],
    })

    expect(screen.getByText('Pendientes: viernes de higiene')).toBeInTheDocument()
    // UNA sola vez en toda la pantalla: la pinta la agenda (manda la agenda) y
    // la higiene cede. Antes salía en las dos, con su mismo botón de cerrar.
    expect(screen.getAllByText('Llamar a Ana')).toHaveLength(1)
    // El motivo es exclusivo de la fila de higiene (la de agenda pinta la hora).
    expect(screen.queryByText(/ciérrala o reprográmala/)).not.toBeInTheDocument()
    // Y el badge de la cola no la vuelve a contar.
    expect(screen.queryByText('1 pendiente')).not.toBeInTheDocument()
    expect(screen.getByText('Sin trabajo adicional')).toBeInTheDocument()
  })

  it('las vencidas que no caben en la agenda SÍ bajan a la higiene (ninguna se pierde)', () => {
    montar({
      ahora: VIERNES_2PM,
      leads: LEADS_VENCIDOS,
      actividades: ACTS_VENCIDOS,
      tareas: TAREAS_VENCIDAS,
    })

    // 3 arriba en «Ahora» + 2 en la agenda siguiente = las 5, cada una en
    // UN solo sitio. Higiene cede porque Agenda ya ofrece la acción directa.
    for (const titulo of ['Tarea 1', 'Tarea 2', 'Tarea 3', 'Tarea 4', 'Tarea 5']) {
      expect(screen.getAllByText(titulo)).toHaveLength(1)
    }
    expect(screen.queryByText(/ciérrala o reprográmala/)).not.toBeInTheDocument()
    expect(screen.queryByText('2 pendientes')).not.toBeInTheDocument()
    expect(screen.getByText('Lo pendiente está en tu agenda')).toBeInTheDocument()
  })
})

describe('Hoy · analista — tile «Convertidos» (F3.1, H9/D1)', () => {
  it('el rótulo dice la ventana OPERATIVA leída del payload, no un 45 afirmado por su cuenta', () => {
    // Este número es la VISTA de cartera (ganados aún visibles), no la
    // conversión del mes: el sub lo dice y toma la ventana del payload
    // certificado (`ventana_convertidos_dias`), la misma que declara el RPC.
    montar({ leads: [lead({ id: 'l-c', etapa: 'convertido' })] })

    expect(screen.getByText('Convertidos')).toBeInTheDocument()
    expect(
      screen.getByText('Ganados aún en tu cartera · ventana de 45 días'),
    ).toBeInTheDocument()
    expect(screen.queryByText(/clientes ganados/)).not.toBeInTheDocument()
  })
})
