// Tests de integración de la pantalla "Hoy · vendedor" — los cinco arreglos de
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
import { act, fireEvent, render, screen } from '@testing-library/react'
import { CUMPLIMIENTO_METAS_DEMO, METAS_DEMO } from '@/lib/demo'
import {
  objetivosCero,
  type CumplimientoMetasJerarquico,
  type ObjetivosPorRol,
} from '@/lib/objetivos'
import { money } from '@/lib/format'
import type { Actividad, Lead, Tarea, Yo } from '@/lib/tipos'
import type { ConversionMensual } from '@/lib/conversion-mensual'

// El arnés monta SIN QueryClientProvider a propósito (sin red): el hook de la
// conversión mensual se sustituye aquí y cada test decide qué payload «llegó».
// En demo la pantalla ni lo consulta (deriva de demo-conversion-mensual).
let CONVERSION_MENSUAL: ConversionMensual | null = null
let CONVERSION_MENSUAL_ERROR = false
const REFETCH_MENSUAL = vi.fn()
vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  return {
    ...actual,
    useConversionMensual: () => ({
      data: CONVERSION_MENSUAL ?? undefined,
      isError: CONVERSION_MENSUAL_ERROR,
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
const recargar = vi.fn()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
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
    tareasDe: (id: string) =>
      TAREAS.filter((t) => t.lead_id === id && t.estado === 'pendiente' && t.activo),
  }),
  usePanelesActions: () => ({ abrirLead: () => {}, abrirNuevoLead: () => {} }),
}))
// El tipo de cambio viene de una edge; aquí se fija para que el CONSOLIDADO sea
// determinista. `TC = null` prueba el caso honesto: sin tasa, el total no puede
// incluir los dólares y la pantalla tiene que decirlo.
let TC: { promedio: number; fuente: string } | null = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/tipo-cambio')>(),
  useTipoCambio: () => ({ tc: TC, recargar: vi.fn() }),
}))
// El contador animado cuenta 0→N por requestAnimationFrame: con timers falsos
// el texto quedaría a medio camino y las aserciones serían una lotería.
vi.mock('@/components/common/animated-value', () => ({
  AnimatedValue: ({ value }: { value: string }) => <>{value}</>,
}))
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
    autor_nombre: 'VENDEDOR UNO',
    creado_en: creadoEn,
  }
}

// CINCO vencidas del mismo asesor (2026-07-08 … 12) — dos más de las que la
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
  tarea({ id: `t-${i + 1}`, lead_id: v.id, titulo: `Tarea ${i + 1}`, vence_en: v.vence }),
)

function montar(
  over: {
    ahora?: Date
    leads?: Lead[]
    tareas?: Tarea[]
    actividades?: Actividad[]
    objetivos?: Partial<ObjetivosPorRol['vendedor']>
    /** El store no pudo LEER las metas: sus ceros no son un dato. */
    objetivosError?: boolean
    cumplimiento?: CumplimientoMetasJerarquico | null
    cumplimientoError?: boolean
  } = {},
): void {
  vi.setSystemTime(over.ahora ?? MIERCOLES_10AM)
  YO = {
    id: 'v-1',
    nombre_completo: 'VENDEDOR UNO',
    rol: 'vendedor',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  TAREAS = over.tareas ?? []
  ACTIVIDADES = over.actividades ?? []
  OBJETIVOS_ERROR = over.objetivosError ?? false
  CUMPLIMIENTO_ERROR = over.cumplimientoError ?? false
  OBJETIVOS = { ...METAS_DEMO, vendedor: { ...METAS_DEMO.vendedor, ...over.objetivos } }
  CUMPLIMIENTO = over.cumplimiento === undefined ? null : over.cumplimiento
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
  if (!base) throw new Error('fixture demo sin vendedor')
  return {
    ...CUMPLIMIENTO_METAS_DEMO,
    vendedor: {
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

/**
 * Payload mínimo de `crm.conversion_mensual_fn` con la fila del propio asesor
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
  const fila: ConversionMensual['responsables'][number] = {
    vendedor_id: '00000000-0000-4000-8000-000000000001',
    supervisor_id: null,
    divisor,
    cierres_no_referidos: cierres,
    cierres_referidos: 0,
    cierres_de_arrastre: 0,
    numerador: cierres,
    conversion_pct: conversionPct,
    estado: divisor > 0 ? 'medible' : cierres > 0 ? 'solo_arrastre' : 'sin_actividad',
    procedencia: [],
    referidos: { recibidos: 0, cerrados: 0, dados_de_alta: 0, aporta_pct: null },
    ...extras,
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
    },
    responsables: [fila],
  }
}

/** Meta del asesor con importes exactos por moneda (todo en la categoría
 *  'nuevo'; el panel agrega por moneda, así que la categoría da igual). */
function metaPenUsd(pen: number, usd: number): ObjetivosPorRol['vendedor'] {
  const base = objetivosCero('2026-07-01').vendedor
  return {
    ...base,
    detalles: base.detalles.map((d) => (
      d.categoria === 'nuevo'
        ? { ...d, capitalObjetivo: d.moneda === 'PEN' ? pen : usd }
        : d
    )),
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
  if (!vendedor) throw new Error('fixture demo sin vendedor')
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
  crearTarea.mockReturnValue({ ok: true, id: 't-nueva' })
  CUMPLIMIENTO = null
  CUMPLIMIENTO_ERROR = false
  OBJETIVOS_ERROR = false
  // ESTADO DE PRODUCCIÓN por defecto: la RPC de conversión no respondió nada.
  // Cada test que quiera un mes medible siembra su propio payload.
  CONVERSION_MENSUAL = null
  CONVERSION_MENSUAL_ERROR = false
  TC = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Hoy · vendedor — agenda héroe', () => {
  it('lista solo el día operable: las citas de días futuros no se pintan (el badge cuadra con las filas)', () => {
    montar({
      leads: [lead({ id: 'l-1' }), lead({ id: 'l-2', nombre_completo: 'BRUNO DÍAZ' })],
      tareas: [
        tarea({ id: 't-hoy', lead_id: 'l-1', titulo: 'Llamar a Ana', vence_en: '2026-07-15T20:00:00Z' }),
        tarea({ id: 't-lejos', lead_id: 'l-2', titulo: 'Llamar a Bruno', vence_en: '2026-07-22T20:00:00Z' }),
      ],
    })

    expect(screen.getByText('Llamar a Ana')).toBeInTheDocument()
    expect(screen.queryByText('Llamar a Bruno')).not.toBeInTheDocument()
    // El badge decía "1 hoy" mientras abajo se pintaban las dos filas.
    expect(screen.getByText('1 hoy')).toBeInTheDocument()
  })

  it('un día sin nada operable se lee VACÍO aunque haya agenda futura', () => {
    montar({
      tareas: [tarea({ id: 't-lejos', titulo: 'Llamar a Ana', vence_en: '2026-07-30T20:00:00Z' })],
    })

    expect(screen.getByText('Sin citas para hoy')).toBeInTheDocument()
    expect(screen.queryByText('Llamar a Ana')).not.toBeInTheDocument()
  })

  it('sigue al reloj vivo: la cita de hoy pasa a VENCIDA sola, sin recargar', () => {
    montar({
      tareas: [tarea({ id: 't-hoy', titulo: 'Llamar a Ana', vence_en: '2026-07-15T15:00:30Z' })],
    })

    expect(screen.queryByText('1 vencida')).not.toBeInTheDocument()

    // Un tick del reloj vivo (useAhora: 60 s) y la tarea ya venció.
    act(() => {
      vi.advanceTimersByTime(60_000)
    })

    expect(screen.getByText('1 vencida')).toBeInTheDocument()
    expect(screen.getByText('0 hoy · 1 vencida')).toBeInTheDocument()
  })

  it('la tarea vencida NO se repite en la cola de al lado (una sola vez, un solo conteo)', () => {
    montar({
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      // Contacto real hace 10 días: sin él el lead caería en speed-to-lead,
      // que es la excepción que SÍ se queda en la cola.
      actividades: [contacto('l-1', '2026-07-05T15:00:00Z')],
      tareas: [tarea({ id: 't-muerta', titulo: 'Llamar a Ana', vence_en: '2026-07-13T20:00:00Z' })],
    })

    expect(screen.getByText('1 vencida')).toBeInTheDocument()
    // La fila de la cola pinta el NOMBRE del lead; la de la agenda, el título
    // de la tarea. Antes salían las dos por el mismo vencimiento.
    expect(screen.queryByText('ANA TORRES')).not.toBeInTheDocument()
    // Y la cola vacía NO puede cantar "al día" con una vencida al lado: remite
    // a la agenda, que es donde está el trabajo (y su botón de cerrar).
    expect(screen.queryByText('Al día ✦ sin pendientes')).not.toBeInTheDocument()
    expect(screen.getByText('Lo pendiente está en tu agenda')).toBeInTheDocument()
    expect(screen.getByText(/Tienes 1 seguimiento vencido/)).toBeInTheDocument()
  })

  it('el speed-to-lead SÍ se queda en la cola aunque tenga una vencida (nunca se entierra)', () => {
    montar({
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES', etapa: 'nuevo' })],
      tareas: [tarea({ id: 't-muerta', titulo: 'Llamar a Ana', vence_en: '2026-07-13T20:00:00Z' })],
    })

    expect(screen.getByText('ANA TORRES')).toBeInTheDocument()
    expect(screen.getByText('Sin responder')).toBeInTheDocument()
  })

  it('las vencidas que la agenda NO alcanza a listar siguen trabajándose desde la cola', () => {
    montar({ leads: LEADS_VENCIDOS, actividades: ACTS_VENCIDOS, tareas: TAREAS_VENCIDAS })

    // La franja ámbar cuenta las 5 pero solo pinta las 3 más viejas.
    expect(screen.getByText('5 vencidas')).toBeInTheDocument()
    expect(screen.getByText('Tarea 1')).toBeInTheDocument()
    expect(screen.getByText('Tarea 3')).toBeInTheDocument()
    expect(screen.queryByText('Tarea 4')).not.toBeInTheDocument()
    expect(screen.getByText(/\+2 más vencidas/)).toBeInTheDocument()
    // Las 2 que no caben NO se evaporan: la cola las califica con su motivo.
    // Antes el anti-duplicado las escondía a ellas también.
    expect(screen.queryByText('LEAD 1')).not.toBeInTheDocument()
    expect(screen.getByText('LEAD 4')).toBeInTheDocument()
    expect(screen.getByText('LEAD 5')).toBeInTheDocument()
    expect(screen.getByText('2 pendientes')).toBeInTheDocument()
    // …y el pie puede prometer la cola porque AHÍ están las dos.
    expect(
      screen.getByText('+2 más vencidas — las tienes en la cola de al lado y en Agenda.'),
    ).toBeInTheDocument()
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

    expect(screen.getByText('5 vencidas')).toBeInTheDocument()
    // La cola está vacía y remite a la agenda: mandarle el excedente sería
    // mandarlo a un sitio donde no hay nada.
    expect(screen.getByText('Lo pendiente está en tu agenda')).toBeInTheDocument()
    expect(screen.getByText('+2 más vencidas — ábrelas desde Agenda.')).toBeInTheDocument()
    expect(screen.queryByText(/cola de al lado/)).not.toBeInTheDocument()
  })

  it('cuando solo PARTE del excedente baja a la cola, el pie dice cuántas', () => {
    montar({
      leads: LEADS_VENCIDOS,
      actividades: ACTS_VENCIDOS,
      // LEAD 5 tiene además una cita futura: conserva plan VIVO, así que la
      // cola lo salta y su vencida solo se puede trabajar desde Agenda.
      tareas: [
        ...TAREAS_VENCIDAS,
        tarea({ id: 't-futura', lead_id: 'l-5', titulo: 'Reunión con LEAD 5', vence_en: '2026-07-22T20:00:00Z' }),
      ],
    })

    expect(screen.getByText('LEAD 4')).toBeInTheDocument()
    expect(screen.queryByText('LEAD 5')).not.toBeInTheDocument()
    expect(
      screen.getByText('+2 más vencidas — 1 en la cola de al lado; todas en Agenda.'),
    ).toBeInTheDocument()
  })
})

// El asesor abre esta pantalla cada mañana y su chip de capital fijaba PEN a
// mano: una cartera íntegramente en dólares se anunciaba como "S/ 0.00" con el
// capital real en la letra chica, contradiciendo a Cartera y a Pipeline sobre
// el mismo lead. El criterio vive ahora en lib/inteligencia (capitalPrincipal).
describe('Hoy · vendedor — capital en proceso', () => {
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
        lead({ id: 'l-usd', nombre_completo: 'BRUNO DÍAZ', moneda: 'USD', monto_estimado: 40_000 }),
      ],
      actividades: [contacto('l-pen', '2026-07-14T15:00:00Z'), contacto('l-usd', '2026-07-14T15:00:00Z')],
    })

    expect(screen.getByText(money(120_000))).toBeInTheDocument()
    expect(screen.getByText('Pipeline activo (PEN) · +US$ 40k aparte')).toBeInTheDocument()
    // Los 160 000 mixtos no existen en ninguna parte de la pantalla.
    expect(screen.queryByText(money(160_000))).not.toBeInTheDocument()
  })
})

describe('Hoy · vendedor — meta del mes', () => {
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
    expect(screen.getByText('50%')).toBeInTheDocument()
    expect(screen.getByText('100% del objetivo')).toBeInTheDocument()
    // El divisor SIEMPRE al lado del %: se lo llena el reparto, no el asesor.
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
  it('un mes incompleto SE VE, y al vendedor no se le cuenta por qué', () => {
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
    expect(screen.getByText('38.3%')).toBeInTheDocument()
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
    CONVERSION_MENSUAL = conversionMensualPropia(50, 4, { cierres_no_referidos: 2, numerador: 2 })
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
    CONVERSION_MENSUAL = conversionMensualPropia(100, 1, { cierres_no_referidos: 1, numerador: 1 })
    montar({
      objetivos: objetivosCero('2026-07-01').vendedor,
      cumplimiento: cumplimientoVendedor(100, 1, 'sin-metas'),
    })

    // Las DOS dimensiones del asesor —capital consolidado y conversión— sin
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
    // cuando lo que se cayó fue la red hace que el asesor deje de buscarla.
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

    const desglose = screen.getByText(
      (_, el) => (el?.textContent ?? '').startsWith('S/ 120k + US$ 20k'),
      { selector: 'p' },
    )
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
    // …y el asesor tiene que enterarse de que le falta media moneda en el avance.
    expect(screen.getByText(/sin tipo de cambio: el total NO incluye los dólares/))
      .toBeInTheDocument()
  })

  // ⚠️ ESTE es el test que faltaba, y el que habría evitado un redespliegue: el
  // ESTADO REAL DE PRODUCCIÓN — gerencia no ha publicado ninguna revisión de
  // metas (`crm.meta_periodos` con 0 filas), así que el store degrada a
  // `objetivosCero` y el cumplimiento llega nulo. Una versión anterior decidía
  // qué pintar con un fail-safe de «no se sabe», y como ese es el estado de
  // TODOS los días, el arreglo no arreglaba nada. Ver `npm run gate:realidad`.
  it('ESTADO DE PRODUCCIÓN (sin metas publicadas): capital neutral y conversión sin fila propia', () => {
    // La base real HOY: la RPC responde (medible) pero el asesor no tiene fila
    // — responsables vacío. El tile no inventa un 0 %: dice «sin leads
    // recibidos», que es la verdad.
    CONVERSION_MENSUAL = {
      ...conversionMensualPropia(null, 0, { estado: 'sin_actividad', cierres_no_referidos: 0, numerador: 0 }),
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
    expect(screen.getByText('Pronóstico de capital abierto')).toBeInTheDocument()
  })
})

describe('Hoy · vendedor — viernes de higiene', () => {
  it('las filas "Sin próxima acción" traen el botón Agendar', () => {
    montar({
      ahora: VIERNES_2PM,
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      actividades: [contacto('l-1', '2026-07-17T18:00:00Z')],
      tareas: [],
    })

    expect(screen.getByText('Viernes de higiene')).toBeInTheDocument()
    expect(screen.getByText('Sin próxima acción')).toBeInTheDocument()

    const boton = screen.getByRole('button', { name: 'Agendar el siguiente paso con ANA TORRES' })
    fireEvent.click(boton)
    expect(crearTarea).toHaveBeenCalledWith(expect.objectContaining({ lead_id: 'l-1', tipo: 'llamada' }))
  })

  it('la vencida que la agenda YA lista no se repite como fila de higiene', () => {
    montar({
      ahora: VIERNES_2PM,
      leads: [lead({ id: 'l-1', nombre_completo: 'ANA TORRES' })],
      actividades: [contacto('l-1', '2026-07-10T15:00:00Z')],
      tareas: [tarea({ id: 't-muerta', titulo: 'Llamar a Ana', vence_en: '2026-07-16T20:00:00Z' })],
    })

    expect(screen.getByText('Viernes de higiene')).toBeInTheDocument()
    // UNA sola vez en toda la pantalla: la pinta la agenda (manda la agenda) y
    // la higiene cede. Antes salía en las dos, con su mismo botón de cerrar.
    expect(screen.getAllByText('Llamar a Ana')).toHaveLength(1)
    // El motivo es exclusivo de la fila de higiene (la de agenda pinta la hora).
    expect(screen.queryByText(/ciérrala o reprográmala/)).not.toBeInTheDocument()
    // Y el badge de la cola no la vuelve a contar.
    expect(screen.queryByText('1 pendiente')).not.toBeInTheDocument()
    expect(screen.getByText('Lo pendiente está en tu agenda')).toBeInTheDocument()
  })

  it('las vencidas que no caben en la agenda SÍ bajan a la higiene (ninguna se pierde)', () => {
    montar({
      ahora: VIERNES_2PM,
      leads: LEADS_VENCIDOS,
      actividades: ACTS_VENCIDOS,
      tareas: TAREAS_VENCIDAS,
    })

    // 3 arriba (agenda) + 2 abajo (higiene) = las 5, cada una en UN solo sitio.
    for (const titulo of ['Tarea 1', 'Tarea 2', 'Tarea 3', 'Tarea 4', 'Tarea 5']) {
      expect(screen.getAllByText(titulo)).toHaveLength(1)
    }
    expect(screen.getAllByText(/ciérrala o reprográmala/)).toHaveLength(2)
    expect(screen.getByText('2 pendientes')).toBeInTheDocument()
  })
})
