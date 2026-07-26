// Tests de integración de la pantalla "Hoy · vendedor" — los cinco arreglos de
// la auditoría 2026-07-25, cada uno con su regresión:
//   1. la agenda héroe listaba TODA la agenda futura mientras su badge contaba
//      solo hoy (los números no cuadraban con las filas);
//   2. esa agenda venía CONGELADA del store (`Date.now()` dentro de un memo sin
//      dependencia temporal) y las vencidas nunca aparecían durante la jornada;
//   3. "Ventas cerradas" comparaba el HISTÓRICO de vida contra la cuota MENSUAL;
//   4. una meta que gerencia no fijó (objetivo 0) se pintaba en rojo crítico;
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
import { objetivosCero, type ObjetivosPorRol } from '@/lib/objetivos'
import { money } from '@/lib/format'
import type { Actividad, Lead, Tarea, Yo } from '@/lib/tipos'

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
// El contador animado cuenta 0→N por requestAnimationFrame: con timers falsos
// el texto quedaría a medio camino y las aserciones serían una lotería.
vi.mock('@/components/common/animated-value', () => ({
  AnimatedValue: ({ value }: { value: string }) => <>{value}</>,
}))

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
  OBJETIVOS = objetivosCero()
  OBJETIVOS.vendedor = { capitalObjetivo: 100_000, ventasObjetivo: 3, conversionObjetivo: 40, ...over.objetivos }
  render(<HoyVendedor />)
}

beforeEach(() => {
  vi.useFakeTimers()
  crearTarea.mockReturnValue({ ok: true, id: 't-nueva' })
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
  it('"Ventas cerradas" cuenta el MES vigente, no la vida entera', () => {
    montar({
      leads: [
        lead({ id: 'l-viejo', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' }),
        lead({ id: 'l-viejo2', etapa: 'convertido', actualizado_en: '2026-06-20T15:00:00Z' }),
        lead({ id: 'l-mes', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
      ],
      objetivos: { ventasObjetivo: 3 },
    })

    // 1 de 3 este mes = 33 %, no 100 % por tres conversiones de vida.
    expect(screen.getByText('33% del objetivo')).toBeInTheDocument()
    expect(screen.getByText('meta 3')).toBeInTheDocument()
    // El KPI de arriba sigue siendo el histórico y la fila lo dice en voz alta.
    expect(screen.getByText('Histórico · clientes ganados')).toBeInTheDocument()
    expect(
      screen.getByText('Cerradas este mes · 3 en total desde que llevas cartera.'),
    ).toBeInTheDocument()
  })

  it('la conversión es la del mes: convertidos sobre lo RESUELTO en el mes', () => {
    montar({
      leads: [
        lead({ id: 'l-c', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
        lead({ id: 'l-d', etapa: 'descartado', actualizado_en: '2026-07-10T15:00:00Z' }),
        // Resuelto el mes pasado: fuera del cálculo.
        lead({ id: 'l-viejo', etapa: 'descartado', actualizado_en: '2026-06-10T15:00:00Z' }),
      ],
      objetivos: { conversionObjetivo: 50 },
    })

    expect(screen.getByText('50%')).toBeInTheDocument() // 1 de 2 resueltos
    expect(screen.getByText('100% del objetivo')).toBeInTheDocument()
  })

  it('sin nada resuelto en el mes la conversión es SIN DATO, no un 0 % en rojo', () => {
    montar({
      // Cartera viva, nada cerrado todavía: el día 1 de cada mes, para todos.
      leads: [lead({ id: 'l-1', etapa: 'contactado' })],
      objetivos: { conversionObjetivo: 40 },
    })

    expect(
      screen.getByText('Sin leads resueltos este mes todavía — el % sale con el primer cierre'),
    ).toBeInTheDocument()
    // Un porcentaje sin denominador no se escribe como 0 %, ni se compara con
    // la cuota: ni valor, ni barra, ni "% del objetivo" para esta fila.
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.queryByText('0%')).not.toBeInTheDocument()
    expect(screen.queryByText('meta 40%')).not.toBeInTheDocument()
    // La fila de ventas SÍ conserva su semáforo: 0 de 3 sí es incumplimiento.
    expect(screen.getByText('meta 3')).toBeInTheDocument()
  })

  it('una meta que gerencia dejó en blanco NO se pinta como incumplida', () => {
    montar({ objetivos: { conversionObjetivo: 0 } })

    expect(screen.getByText('Sin meta fijada para este mes')).toBeInTheDocument()
    // Antes: "0 % del objetivo · meta 0 %" en rojo crítico sobre una cuota
    // que nadie fijó.
    expect(screen.queryByText('meta 0%')).not.toBeInTheDocument()
    // Las otras dos filas conservan su barra y su semáforo.
    expect(screen.getByText('meta 3')).toBeInTheDocument()
  })

  it('sin ninguna meta fijada cae al bloque "por definir" con el conteo del mes', () => {
    montar({
      leads: [
        lead({ id: 'l-mes', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
        lead({ id: 'l-viejo', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' }),
      ],
      objetivos: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
    })

    expect(screen.getByText(/Meta mensual por definir/)).toBeInTheDocument()
    expect(screen.getByText('Ventas cerradas este mes')).toBeInTheDocument()
  })

  it('si la LECTURA de metas falló no dice "por definir": lo confiesa y ofrece reintentar', () => {
    montar({
      objetivos: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
      objetivosError: true,
    })

    // Los mismos ceros, dos causas opuestas: afirmar que nadie fijó la meta
    // cuando lo que se cayó fue la red hace que el asesor deje de buscarla.
    expect(screen.queryByText(/Meta mensual por definir/)).not.toBeInTheDocument()
    expect(screen.getByText(/No pudimos cargar tu meta del mes/)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(recargar).toHaveBeenCalled()
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
