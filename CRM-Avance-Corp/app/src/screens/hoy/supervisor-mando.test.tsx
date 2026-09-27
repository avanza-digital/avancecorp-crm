// Hoy · supervisor — puesto de mando (27/09/2026). Se prueba en el MUNDO DE
// PRODUCCIÓN: seguimiento ACTIVO (la cola legada no se consulta), sin metas
// publicadas y con la agenda que llegue o no llegue. La derivación compartida
// (./datos-supervisor.ts) corre de verdad sobre los mismos mocks que usa
// supervisor.test.tsx; lo que se sustituye es la red.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { objetivosCero, type CumplimientoMetasJerarquico, type ObjetivosPorRol } from '@/lib/objetivos'
import type { Actividad, Lead, Miembro, Yo } from '@/lib/tipos'
import type { ColaSlaPagina, FiltrosSla } from '@/lib/sla-operacion'
import type { MetricaAgendaVendedor, MetricasAgenda } from '@/lib/metricas-agenda'

// Sábado 2026-09-26, 10:00 en Lima (UTC-5).
const AHORA = new Date('2026-09-26T15:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let VENDEDORES: Miembro[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero('2026-09-01')
let CUMPLIMIENTO: CumplimientoMetasJerarquico | null = null
const recargar = vi.fn()
const abrirLead = vi.fn<(id: string) => Promise<boolean>>()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
  useTipoCambio: () => ({ tc: { promedio: 3.5, fuente: 'BCRP · prom. 7d' }, recargar: vi.fn() }),
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    conocerLeads: () => {}, asegurarLead: async () => true,
    ambito: { leads: LEADS, vendedores: VENDEDORES, esGlobal: false },
    actividades: [] as Actividad[],
    tareas: [],
    objetivos: OBJETIVOS,
    objetivosError: false,
    cumplimientoMetas: CUMPLIMIENTO,
    cumplimientoMetasError: false,
    recargar,
    equipo: VENDEDORES,
  }),
  usePanelesActions: () => ({ abrirLead }),
}))
vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => <section aria-label="Agenda del equipo" /> }))
// La pantalla clásica tiene su propia suite: aquí solo importa CUÁNDO se elige.
vi.mock('./supervisor', () => ({ HoySupervisor: () => <p>Pantalla clásica del supervisor</p> }))

let METRICAS_AGENDA: MetricasAgenda | undefined
let AGENDA_ERROR: Error | null = null
const REFETCH_AGENDA = vi.fn()
vi.mock('@/data/crm-queries', () => ({
  useSolicitudesTasa: () => ({ data: [], isPending: false, isError: false, refetch: () => {} }),
  useResolverSolicitudTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useResponderTopeTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useResolucionTasa: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
  useSolicitarTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
  useMetricasAgenda: () => ({ data: METRICAS_AGENDA, error: AGENDA_ERROR, isPending: false, isFetching: false, refetch: REFETCH_AGENDA }),
  useConversionMensual: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: vi.fn() }),
  useCierresExternos: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: () => {} }),
}))
vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))
vi.mock('@/data/use-resumen-cartera-operativo', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useResumenCarteraOperativo: (leads: Lead[], actividades: Actividad[]) => ({
      resumen: resumenCarteraDesdeAmbito(leads, actividades ?? [], Date.now()),
      cargando: false, error: null, recargar: vi.fn(),
    }),
  }
})
vi.mock('@/data/use-metricas-vendedores-operativas', async () => {
  const { metricasVendedoresDesdeAmbito } = await import('@/lib/metricas-vendedores')
  return {
    useMetricasVendedoresOperativas: (roster: Miembro[], equipo: Miembro[], leads: Lead[], actividades: Actividad[]) => ({
      metricas: metricasVendedoresDesdeAmbito(roster ?? [], equipo ?? [], leads ?? [], actividades ?? [], Date.now()),
      cargando: false, error: null, recargar: vi.fn(),
    }),
  }
})

// ── Seguimiento activo: modo + cola del servidor, controlables por prueba ──
const MODO = { legado: false, activo: true, error: null as Error | null, data: { control_revision: 1 } as { control_revision: number } | undefined }
const REFETCH_MODO = vi.fn()
type RespuestaCola = { data: ColaSlaPagina | undefined; error: Error | null; isFetching: boolean }
let RESPONDER: (filtros: FiltrosSla) => RespuestaCola = () => ({ data: undefined, error: null, isFetching: false })
const REFETCH_COLA = vi.fn()
const pedidosCola: Array<{ filtros: FiltrosSla; limite: number; habilitada: boolean }> = []
vi.mock('@/data/sla-operacion-queries', () => ({
  useModoSla: () => ({ ...MODO, refetch: REFETCH_MODO }),
  useColaSlaPagina: (filtros: FiltrosSla, _cursor: unknown, limite: number, habilitada: boolean) => {
    pedidosCola.push({ filtros, limite, habilitada })
    return { ...RESPONDER(filtros), refetch: REFETCH_COLA }
  },
}))

const { HoySupervisorMando } = await import('./supervisor-mando')

const KAREN = 'aaaaaaaa-0000-4000-8000-000000000001'
const JORGE = 'aaaaaaaa-0000-4000-8000-000000000002'

function miembro(id: string, nombre: string, over: Partial<Miembro> = {}): Miembro {
  return { perfil_id: id, nombre_completo: nombre, rol_crm: 'vendedor', supervisor_id: 's-1', activo: true, ...over }
}

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'l-1', nombre_completo: 'ROSA CHÁVEZ', telefono: '+51987654321', etapa: 'contactado', origen: 'referido',
    monto_estimado: 20_000, moneda: 'PEN', vendedor_id: KAREN, creado_en: '2026-09-20T15:00:00Z', activo: true, ...over,
  }
}

type ItemCola = ColaSlaPagina['items'][number]
function item(over: { lead_id: string; nombre: string; analistaId: string | null; analista: string | null; bucket?: string; severidad?: ItemCola['severidad']; referencia_en?: string | null }): ItemCola {
  return {
    lead_id: over.lead_id,
    bucket: over.bucket ?? 'primera_atencion',
    severidad: over.severidad ?? 'critica',
    prioridad: 10,
    referencia_en: over.referencia_en === undefined ? '2026-09-24T15:00:00Z' : over.referencia_en,
    tarea_id: null,
    lead: { id: over.lead_id, nombre_completo: over.nombre, etapa: 'nuevo', analista_id: over.analistaId, analista_nombre: over.analista },
    senales: { pendientes: true, primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
  } as unknown as ItemCola
}

const TOTALES_CERO = { pendientes: 0, primera_atencion: 0, tareas_vencidas: 0, seguimientos_pendientes: 0, revisiones: 0, datos_incompletos: 0, por_repartir: 0 }
function pagina(items: ItemCola[], over: Partial<Omit<ColaSlaPagina, 'totales'>> & { totales?: Partial<ColaSlaPagina['totales']> } = {}): ColaSlaPagina {
  const { totales, ...resto } = over
  return {
    version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-26T15:00:00Z', modelo_avisos: 3,
    filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7,
    total_items: items.length, hay_mas: false, cursor_siguiente: null, rango: { desde: 1, hasta: items.length },
    totales: { ...TOTALES_CERO, ...totales },
    items,
    ...resto,
  } as ColaSlaPagina
}

function agenda(vendedores: Array<Partial<MetricaAgendaVendedor> & { vendedor_id: string; nombre: string }>): MetricasAgenda {
  return {
    version: 1, generado_en: '2026-09-26T15:00:00Z',
    periodo: { desde: '2026-09-20', hasta: '2026-09-26', dias: 7, zona: 'America/Lima' },
    vendedores: vendedores.map((v) => ({
      rol: 'vendedor', activo: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0, completadas: 0, no_asistio: 0,
      canceladas: 0, pct_completadas: null, tareas_creadas: 0, reuniones_agendadas: 0, reprogramaciones: 0, pendientes: 0,
      vencidas: 0, leads_sin_accion: 0, ...v,
    })),
  } as MetricasAgenda
}

function montar(): ReturnType<typeof render> {
  vi.setSystemTime(AHORA)
  YO = { id: 's-1', nombre_completo: 'SUPERVISOR UNO', rol: 'supervisor', demo: false, puede_contratar: true }
  return render(<HoySupervisorMando />)
}

const colaTodo = () => [
  item({ lead_id: 'l-1', nombre: 'ROSA CHÁVEZ', analistaId: KAREN, analista: 'KAREN ZAPATA' }),
  item({ lead_id: 'l-2', nombre: 'VÍCTOR PALOMINO', analistaId: JORGE, analista: 'JORGE HUAMÁN', bucket: 'tarea_vencida', severidad: 'critica', referencia_en: '2026-09-26T12:00:00Z' }),
  item({ lead_id: 'l-3', nombre: 'MARTHA SOTO', analistaId: KAREN, analista: 'KAREN ZAPATA', bucket: 'seguimiento', severidad: 'media', referencia_en: '2026-09-26T18:00:00Z' }),
]

beforeEach(() => {
  vi.useFakeTimers()
  vi.clearAllMocks()
  recargar.mockResolvedValue(true)
  abrirLead.mockResolvedValue(true)
  pedidosCola.length = 0
  MODO.legado = false
  MODO.activo = true
  MODO.error = null
  MODO.data = { control_revision: 1 }
  VENDEDORES = [
    miembro(KAREN, 'KAREN ZAPATA'),
    miembro(JORGE, 'JORGE HUAMÁN'),
    miembro('v-ex', 'EX ANALISTA', { activo: false }),
  ]
  LEADS = [lead(), lead({ id: 'l-3', nombre_completo: 'MARTHA SOTO', monto_estimado: 15_000, moneda: 'USD' })]
  OBJETIVOS = objetivosCero('2026-09-01')
  CUMPLIMIENTO = null
  METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA' }, { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
  AGENDA_ERROR = null
  RESPONDER = (filtros) => {
    const todas = colaTodo().filter((i) => filtros.analista_id == null || i.lead.analista_id === filtros.analista_id)
    return {
      data: pagina(todas, {
        filtros: { ...filtros },
        totales: { pendientes: todas.length, primera_atencion: todas.filter((i) => i.bucket === 'primera_atencion').length, tareas_vencidas: todas.filter((i) => i.bucket === 'tarea_vencida').length },
      }),
      error: null,
      isFetching: false,
    }
  }
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Hoy · supervisor — puesto de mando: qué pantalla se elige', () => {
  it('en modo LEGADO (demo o seguimiento apagado) sigue la pantalla clásica', () => {
    MODO.legado = true
    MODO.activo = false
    montar()
    expect(screen.getByText('Pantalla clásica del supervisor')).toBeInTheDocument()
    expect(pedidosCola).toHaveLength(0)
  })

  it('mientras el modo se consulta no pide la cola ni inventa pendientes', () => {
    MODO.activo = false
    MODO.data = undefined
    montar()
    expect(screen.getByText('Consultando el seguimiento comercial…')).toHaveAttribute('role', 'status')
    expect(screen.queryByRole('tablist')).not.toBeInTheDocument()
    expect(pedidosCola.every((p) => !p.habilitada)).toBe(true)
  })

  it('si el modo falla lo dice y deja reintentar', () => {
    MODO.activo = false
    MODO.error = new Error('caído')
    montar()
    const alerta = screen.getByRole('alert')
    expect(alerta).toHaveTextContent('No se pudo cargar el seguimiento')
    fireEvent.click(within(alerta).getByRole('button', { name: /Reintentar/ }))
    expect(REFETCH_MODO).toHaveBeenCalledTimes(1)
  })
})

describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', () => {
  it('ESTADO DE PRODUCCIÓN: la cola sale del seguimiento con 7 filas, conteos del servidor y enlace al módulo', () => {
    montar()
    expect(pedidosCola.at(-1)).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
    const pestanas = screen.getByRole('tablist', { name: 'Filtrar los pendientes' })
    expect(within(pestanas).getByRole('tab', { name: 'Para atender ahora: 3' })).toHaveAttribute('aria-selected', 'true')
    expect(within(pestanas).getByRole('tab', { name: 'Primera gestión: 1' })).toBeInTheDocument()
    expect(within(pestanas).getByRole('tab', { name: 'Tareas vencidas: 1' })).toBeInTheDocument()
    // «Todas» no tiene total en `totales`: sin número hasta que se abre.
    expect(within(pestanas).getByRole('tab', { name: 'Todas' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
    expect(screen.getByText('3 de 3')).toBeInTheDocument()
  })

  it('cada fila dice de quién es, en qué estado está y desde cuándo, con la severidad en la tira', () => {
    montar()
    const lista = screen.getByRole('list', { name: /Pendientes del equipo/ })
    const filas = within(lista).getAllByRole('listitem')
    expect(filas).toHaveLength(3)
    expect(filas[0]).toHaveAttribute('data-sev', 'critica')
    expect(filas[0]).toHaveTextContent('Karen')
    expect(filas[0]).toHaveTextContent('Primera gestión pendiente · venció hace 2 días')
    expect(filas[1]).toHaveTextContent('Actividad vencida · venció hace 3 horas')
    expect(filas[2]).toHaveAttribute('data-sev', 'media')
    expect(filas[2]).toHaveTextContent('Seguimiento pendiente · vence en 3 horas')
  })

  it('monto y contacto SOLO con el lead completo del store (caché parcial: desconocido no es cero)', () => {
    montar()
    const filas = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')
    expect(filas[0]).toHaveTextContent('S/ 20k')
    expect(within(filas[0]!).getAllByRole('link', { name: /ROSA CHÁVEZ/ }).length + within(filas[0]!).queryAllByRole('button', { name: /número de ROSA CHÁVEZ|Llamar a ROSA CHÁVEZ/ }).length).toBeGreaterThan(0)
    // VÍCTOR no está en el store: ni monto ni acciones de contacto.
    expect(filas[1]).not.toHaveTextContent(/S\/|US\$/)
    expect(within(filas[1]!).getAllByRole('button')).toHaveLength(1)
    expect(filas[2]).toHaveTextContent('US$ 15k')
  })

  it('una fila sin fecha de referencia lo dice en vez de inventar un tiempo', () => {
    RESPONDER = () => ({ data: pagina([item({ lead_id: 'l-9', nombre: 'SIN FECHA', analistaId: KAREN, analista: 'KAREN ZAPATA', referencia_en: null })], { totales: { pendientes: 1 } }), error: null, isFetching: false })
    montar()
    expect(screen.getByText(/Primera gestión pendiente · sin fecha confirmada/)).toBeInTheDocument()
  })

  it('el filtro por analista lo hace el SERVIDOR y los conteos son los suyos', () => {
    montar()
    const chips = screen.getByRole('group', { name: 'Filtrar por analista' })
    // Solo analistas activos del equipo, sin conteos inventados en el cliente.
    expect(within(chips).getAllByRole('button').map((b) => b.textContent)).toEqual(['Todos', 'Jorge', 'Karen'])
    fireEvent.click(within(chips).getByRole('button', { name: 'KAREN ZAPATA' }))
    expect(pedidosCola.at(-1)?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Para atender ahora: 2' })).toBeInTheDocument()
    expect(screen.getByText('Mostrando los pendientes de Karen')).toHaveAttribute('aria-live', 'polite')
    // Con el filtro, la columna del analista sobra.
    const filas = within(screen.getByRole('list', { name: /Pendientes de Karen/ })).getAllByRole('listitem')
    expect(filas).toHaveLength(2)
    fireEvent.click(within(chips).getByRole('button', { name: 'Todos' }))
    expect(pedidosCola.at(-1)?.filtros.analista_id).toBeNull()
  })

  it('las flechas recorren las pestañas, mueven el foco y piden la señal al servidor', () => {
    montar()
    const primera = screen.getByRole('tab', { name: /Para atender ahora/ })
    primera.focus()
    fireEvent.keyDown(primera, { key: 'ArrowRight' })
    const segunda = screen.getByRole('tab', { name: /Primera gestión/ })
    expect(segunda).toHaveAttribute('aria-selected', 'true')
    expect(segunda).toHaveFocus()
    expect(pedidosCola.at(-1)?.filtros.senal).toBe('primera_atencion')
    fireEvent.keyDown(segunda, { key: 'End' })
    expect(screen.getByRole('tab', { name: /^Todas/ })).toHaveAttribute('aria-selected', 'true')
    // Con «Todas» abierta, su total sí es del servidor.
    expect(screen.getByRole('tab', { name: 'Todas: 3' })).toBeInTheDocument()
    fireEvent.keyDown(screen.getByRole('tab', { name: 'Todas: 3' }), { key: 'Home' })
    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveFocus()
  })

  it('fail-closed: con error NO enseña la cola retenida y deja reintentar', () => {
    RESPONDER = () => ({ data: pagina(colaTodo(), { totales: { pendientes: 3 } }), error: new Error('refetch caído'), isFetching: false })
    montar()
    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('No se pudo cargar la cola'))
    expect(alerta).toBeDefined()
    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
    expect(REFETCH_COLA).toHaveBeenCalledTimes(1)
  })

  it('una respuesta que ya no es del modo activo no se pinta como vigente', () => {
    RESPONDER = () => ({ data: pagina(colaTodo(), { modo: 'legado' }), error: null, isFetching: false })
    montar()
    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
    expect(screen.getByText(/Las reglas del seguimiento cambiaron/)).toBeInTheDocument()
  })

  it('cargando: lo dice, sin filas ni ceros', () => {
    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
    montar()
    expect(screen.getByText('Cargando los pendientes del equipo…')).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
  })

  it('vacío honesto por pestaña y por analista', () => {
    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
    montar()
    expect(screen.getByText(/Nada para atender ahora/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
    expect(screen.getByText('Jorge no tiene casos aquí.')).toBeInTheDocument()
  })

  it('abrir una ficha llama al store; si falla, lo avisa', async () => {
    abrirLead.mockResolvedValueOnce(false)
    montar()
    const fila = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')[0]!
    await act(async () => {
      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
    })
    expect(abrirLead).toHaveBeenCalledWith('l-1')
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo abrir la ficha')
  })
})

describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
  it('UNA severidad por analista: el no-show repetido es rojo en el punto, la cabecera y el detalle', () => {
    METRICAS_AGENDA = agenda([
      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, toques: 9, pct_completadas: 50 },
      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' },
    ])
    montar()
    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
    const karen = within(equipo).getByRole('button', { name: /KAREN ZAPATA/ })
    expect(karen).toHaveTextContent('2 citas sin asistir')
    expect(within(karen).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
    expect(karen).toHaveAttribute('aria-expanded', 'false')
    fireEvent.click(karen)
    expect(karen).toHaveAttribute('aria-expanded', 'true')
    const detalle = document.getElementById(karen.getAttribute('aria-controls')!)!
    expect(detalle).toBeVisible()
    // El detalle NO repite la señal principal: trae las demás y los hechos.
    expect(detalle).not.toHaveTextContent('2 citas sin asistir')
    expect(detalle).toHaveTextContent('1 tarea vencida')
    expect(detalle).toHaveTextContent('9 toques en 7 días · 50 % completadas')
    // Y filtra la cola a sus pendientes.
    expect(pedidosCola.at(-1)?.filtros.analista_id).toBe(KAREN)
    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
  })

  it('«Al día» solo con la agenda confirmada; sin ella no se afirma', () => {
    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
    montar()
    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
    expect(within(equipo).getByRole('button', { name: /JORGE HUAMÁN/ })).toHaveTextContent('Al día')
    // Karen no tiene actividad desde el 20/09: 6 días, rojo. Jorge no cuenta.
    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
  })

  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día»', () => {
    AGENDA_ERROR = new Error('agenda caída')
    montar()
    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('La agenda del equipo no respondió'))
    expect(alerta).toBeDefined()
    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
    expect(REFETCH_AGENDA).toHaveBeenCalledTimes(1)
    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
    expect(equipo).not.toHaveTextContent('Al día')
  })

  it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
    montar()
    expect(screen.getByRole('link', { name: 'Mi equipo hoy →' })).toHaveAttribute('href', '#/gestion-diaria')
  })
})
