// Hoy · supervisor — puesto de mando (27/09/2026). Se prueba en el MUNDO DE
// PRODUCCIÓN: seguimiento ACTIVO (la cola legada no se consulta), sin metas
// publicadas y con la agenda que llegue o no llegue. La derivación compartida
// (./datos-supervisor.ts) corre de verdad sobre los mismos mocks que usa
// supervisor.test.tsx; lo que se sustituye es la red.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { objetivosCero, type CumplimientoMetasJerarquico, type ObjetivosPorRol } from '@/lib/objetivos'
import type { Actividad, Lead, Miembro, Yo } from '@/lib/tipos'
import type { ColaDiaPagina, FiltrosSla } from '@/lib/sla-operacion'
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
let CONVERSION: { data: unknown; isError: boolean } = { data: undefined, isError: false }
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
  useConversionMensual: () => ({ data: CONVERSION.data, isError: CONVERSION.isError, isPending: false, isFetching: false, refetch: vi.fn() }),
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
type RespuestaCola = { data: ColaDiaPagina | undefined; error: Error | null; isFetching: boolean }
let RESPONDER: (filtros: FiltrosSla) => RespuestaCola = () => ({ data: undefined, error: null, isFetching: false })
const REFETCH_COLA = vi.fn()
const pedidosCola: Array<{ filtros: FiltrosSla; limite: number; habilitada: boolean }> = []
vi.mock('@/data/sla-operacion-queries', () => ({
  useModoSla: () => ({ ...MODO, refetch: REFETCH_MODO }),
  useColaDiaPagina: (filtros: FiltrosSla, _cursor: unknown, limite: number, habilitada: boolean) => {
    pedidosCola.push({ filtros, limite, habilitada })
    return { ...RESPONDER(filtros), refetch: REFETCH_COLA }
  },
}))

const { HoySupervisorMando } = await import('./supervisor-mando')

/** Cada render pide la cola (con el filtro por analista) y luego la del equipo (sin él). */
const pedidoCola = () => pedidosCola.at(-2)
const pedidoEquipo = () => pedidosCola.at(-1)

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

type ItemCola = ColaDiaPagina['items'][number]
function item(over: { lead_id: string; nombre: string; analistaId: string | null; analista: string | null; bucket?: string; severidad?: ItemCola['severidad']; referencia_en?: string | null }): ItemCola {
  return {
    clave: `lead:${over.lead_id}`, sujeto: { tipo: 'lead', id: over.lead_id, nombre: over.nombre },
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

const TOTALES_CERO = { pendientes: 0, primera_atencion: 0, tareas_vencidas: 0, seguimientos_pendientes: 0, revisiones: 0, datos_incompletos: 0, por_repartir: 0, clientes: 0 }
function pagina(items: ItemCola[], over: Partial<Omit<ColaDiaPagina, 'totales'>> & { totales?: Partial<ColaDiaPagina['totales']> } = {}): ColaDiaPagina {
  const { totales, ...resto } = over
  return {
    version: 3, modo: 'activo', control_revision: 1, calculado_en: '2026-09-26T15:00:00Z', modelo_avisos: 3,
    filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7,
    total_items: items.length, hay_mas: false, cursor_siguiente: null, rango: { desde: 1, hasta: items.length },
    totales: { ...TOTALES_CERO, ...totales },
    items,
    ...resto,
  } as ColaDiaPagina
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
  CONVERSION = { data: undefined, isError: false }
  RESPONDER = (filtros) => {
    const todas = colaTodo().filter((i) => filtros.analista_id == null || i.lead?.analista_id === filtros.analista_id)
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
    // Aunque la caché conserve una página de la misma revisión, sin modo confirmado no se pinta.
    RESPONDER = () => ({ data: pagina([item({ lead_id: 'l-1', nombre: 'ROSA CHÁVEZ', analistaId: KAREN, analista: 'KAREN ZAPATA' })], { totales: { pendientes: 1 } }), error: null, isFetching: false })
    montar()
    expect(screen.getByText(/No se pudo cargar el seguimiento/)).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: /^Pendientes del equipo/ })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga del seguimiento' }))
    expect(REFETCH_MODO).toHaveBeenCalledTimes(1)
  })
})

describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', () => {
  it('ESTADO DE PRODUCCIÓN: la cola sale del seguimiento con 7 filas, conteos del servidor y enlace al módulo', () => {
    montar()
    expect(pedidoCola()).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
    expect(pedidoEquipo()).toEqual(pedidoCola())
    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
    const pestanas = screen.getByRole('tablist', { name: 'Filtrar los pendientes' })
    expect(within(pestanas).getByRole('tab', { name: 'Para atender ahora: 3' })).toHaveAttribute('aria-selected', 'true')
    expect(within(pestanas).getByRole('tab', { name: 'Primera gestión: 1' })).toBeInTheDocument()
    expect(within(pestanas).getByRole('tab', { name: 'Tareas vencidas: 1' })).toBeInTheDocument()
    // «Todas» no tiene total en `totales`: sin número hasta que se abre.
    expect(within(pestanas).getByRole('tab', { name: 'Todas' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
    // Con todo a la vista, el enlace no promete más filas de las que hay.
    expect(screen.getByRole('link', { name: 'Ver todo en Seguimiento' })).toBeInTheDocument()
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
    expect(pedidoCola()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
    // Las decisiones siguen mirando a TODO el equipo.
    expect(pedidoEquipo()?.filtros.analista_id).toBeNull()
    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Para atender ahora: 2' })).toBeInTheDocument()
    expect(screen.getByText('Mostrando los pendientes de Karen')).toHaveAttribute('aria-live', 'polite')
    // Con el filtro, la columna del analista sobra.
    const filas = within(screen.getByRole('list', { name: /Pendientes de Karen/ })).getAllByRole('listitem')
    expect(filas).toHaveLength(2)
    fireEvent.click(within(chips).getByRole('button', { name: 'Todos' }))
    expect(pedidoCola()?.filtros.analista_id).toBeNull()
  })

  it('las flechas recorren las pestañas, mueven el foco y piden la señal al servidor', () => {
    montar()
    const primera = screen.getByRole('tab', { name: /Para atender ahora/ })
    primera.focus()
    fireEvent.keyDown(primera, { key: 'ArrowRight' })
    const segunda = screen.getByRole('tab', { name: /Primera gestión/ })
    expect(segunda).toHaveAttribute('aria-selected', 'true')
    expect(segunda).toHaveFocus()
    expect(pedidoCola()?.filtros.senal).toBe('primera_atencion')
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
    expect(screen.getByText(/No se pudo cargar la cola/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de los pendientes del equipo' }))
    expect(REFETCH_COLA).toHaveBeenCalledTimes(1)
  })

  it('una página de OTRA revisión de reglas (caché) no se pinta mientras refresca', () => {
    RESPONDER = (filtros) => ({ data: pagina(colaTodo(), { filtros: { ...filtros }, control_revision: 1 }), error: null, isFetching: true })
    MODO.data = { control_revision: 2 }
    montar()
    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
    expect(screen.getByText('Actualizando los pendientes con las reglas vigentes…')).toBeInTheDocument()
    // Las decisiones tampoco usan esos conteos viejos.
    expect(screen.queryByRole('button', { name: /primera gestión vencida/ })).not.toBeInTheDocument()
  })

  it('si el analista elegido sale del equipo, la cola deja de filtrarse por su id', () => {
    const { rerender } = montar()
    fireEvent.click(screen.getByRole('button', { name: 'KAREN ZAPATA' }))
    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
    VENDEDORES = VENDEDORES.filter((m) => m.perfil_id !== KAREN)
    rerender(<HoySupervisorMando />)
    expect(pedidoCola()?.filtros.analista_id).toBeNull()
    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('si el analista elegido se DESACTIVA (sigue en el roster), el filtro también cae', () => {
    const { rerender } = montar()
    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
    expect(pedidoCola()?.filtros.analista_id).toBe(JORGE)
    VENDEDORES = VENDEDORES.map((m) => (m.perfil_id === JORGE ? { ...m, activo: false } : m))
    rerender(<HoySupervisorMando />)
    expect(pedidoCola()?.filtros.analista_id).toBeNull()
    expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
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
      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen, urgente: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
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
    expect(screen.getByRole('button', { name: '1 en rojo' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '0 en ámbar' })).toBeDisabled()
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
    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
  })

  it('«Al día» solo con la agenda confirmada; sin ella no se afirma', () => {
    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
    montar()
    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
    expect(within(equipo).getByRole('button', { name: /JORGE HUAMÁN/ })).toHaveTextContent('Al día')
    // Karen no tiene actividad desde el 20/09: 6 días, rojo. Jorge no cuenta.
    expect(screen.getByRole('button', { name: '1 en rojo' })).toBeInTheDocument()
  })

  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día» ni «Sin alertas»', () => {
    AGENDA_ERROR = new Error('agenda caída')
    // Todos con actividad fresca: sin agenda, cero señales es DESCONOCIDO.
    LEADS = [
      lead({ creado_en: '2026-09-26T14:00:00Z' }),
      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
    ]
    montar()
    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
    expect(screen.getByText(/La agenda del equipo no respondió/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de la agenda del equipo' }))
    expect(REFETCH_AGENDA).toHaveBeenCalledTimes(1)
    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
    expect(equipo).not.toHaveTextContent('Al día')
  })

  it('«Sin alertas» solo con la agenda confirmada y todos sin señal', () => {
    LEADS = [
      lead({ creado_en: '2026-09-26T14:00:00Z' }),
      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
    ]
    montar()
    expect(screen.getByText('Sin alertas en el equipo')).toBeInTheDocument()
  })

  it('mientras la agenda carga tampoco afirma «Sin alertas»', () => {
    METRICAS_AGENDA = undefined
    LEADS = [lead({ creado_en: '2026-09-26T14:00:00Z' })]
    montar()
    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
  })

  it('un analista sin leads abiertos conserva su alerta roja de agenda', () => {
    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', no_asistio: 3 }])
    montar()
    const jorge = within(screen.getByRole('list', { name: 'Analistas del equipo' })).getByRole('button', { name: /JORGE HUAMÁN/ })
    expect(jorge).toHaveTextContent('3 citas sin asistir')
    expect(within(jorge).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
  })

  it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
    montar()
    expect(screen.getByRole('link', { name: 'Mi equipo hoy' })).toHaveAttribute('href', '#/gestion-diaria')
  })
})

describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
  const conAgendaYReparto = () => {
    METRICAS_AGENDA = agenda([
      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, leads_sin_accion: 1 },
      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 3 },
    ])
    // Un lead SIN analista: el reparto lo cuenta el resumen (espejo del RPC).
    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
  }

  it('ESTADO DE PRODUCCIÓN: tres tarjetas, el rojo primero, cifra grande y la severidad en texto', () => {
    conAgendaYReparto()
    montar()
    expect(screen.getByRole('heading', { name: 'Decide primero' })).toBeInTheDocument()
    const tarjetas = document.querySelectorAll('[data-decision]')
    // Rojo primero; entre los ámbar manda el peso fijo: el reparto antes que «sin próxima acción».
    expect([...tarjetas].map((t) => t.getAttribute('data-decision'))).toEqual(['primera_gestion', 'no_asistio', 'por_repartir'])
    const primera = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
    expect(primera).toHaveTextContent('1')
    expect(primera).toHaveTextContent('primera gestión vencida')
    expect(screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })).toHaveTextContent('citas sin asistir · Karen')
    // Lo que no entra en tres, a «Esta semana».
    expect(screen.getByRole('button', { name: /Esta semana · 1/ })).toBeInTheDocument()
  })

  it('la primera gestión filtra la cola a ESA pestaña para todo el equipo; el segundo clic la devuelve', () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
    const tarjeta = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
    fireEvent.click(tarjeta)
    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!)).toHaveTextContent('Revisa la primera gestión con cada analista')
    expect(screen.getByRole('tab', { name: /Primera gestión/ })).toHaveAttribute('aria-selected', 'true')
    expect(pedidoCola()?.filtros).toEqual({ senal: 'primera_atencion', etapa: null, analista_id: null })
    // La fuente de la tarjeta NO cambia de clave al cambiar la pestaña (Codex F2/F3).
    expect(pedidoEquipo()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: null })
    expect(tarjeta).toBeInTheDocument()
    fireEvent.click(tarjeta)
    expect(tarjeta).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveAttribute('aria-selected', 'true')
  })

  it('«Ver» lleva a la cola y le pasa el foco a la pestaña', () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Ver en la cola: 1 primera gestión vencida' }))
    act(() => { vi.advanceTimersByTime(32) })
    const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
    expect(pestana).toHaveAttribute('aria-selected', 'true')
    expect(pestana).toHaveFocus()
  })

  it('citas sin asistir NO filtran la cola (no contiene esos casos): despliegan y llevan al día del equipo', () => {
    conAgendaYReparto()
    montar()
    const antes = pedidoCola()?.filtros
    const tarjeta = screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })
    fireEvent.click(tarjeta)
    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
    expect(pedidoCola()?.filtros).toEqual(antes)
    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!))
      .toHaveTextContent('En 7 días: 2 citas sin asistir · 1 tarea vencida · 1 lead sin próxima acción.')
    expect(screen.getByRole('link', { name: 'Ver su día: KAREN ZAPATA: 2 citas sin asistir' })).toHaveAttribute('href', '#/gestion-diaria')
  })

  it('«Esta semana» lista lo que no entró, con su acción; Esc lo cierra y devuelve el foco', () => {
    conAgendaYReparto()
    montar()
    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
    fireEvent.click(disparador)
    expect(disparador).toHaveAttribute('aria-expanded', 'true')
    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
    expect(lista).toHaveTextContent('Esta semana: JORGE HUAMÁN: 3 leads sin próxima acción')
    const verDia = within(lista).getByRole('link', { name: 'Ver su día: JORGE HUAMÁN: 3 leads sin próxima acción' })
    expect(verDia).toHaveAttribute('href', '#/gestion-diaria')
    verDia.focus()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(disparador).toHaveAttribute('aria-expanded', 'false')
    expect(disparador).toHaveFocus()
  })

  it('el reparto como tarjeta conserva la etiqueta accesible del servidor', () => {
    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
    montar()
    expect(screen.getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
  })

  it('con TODAS las fuentes confirmadas y nada pendiente dice «Nada que decidir»', () => {
    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
    montar()
    expect(screen.getByText('Nada que decidir ahora mismo.')).toBeInTheDocument()
    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
  })

  it('con una fuente AÚN cargando no ordena: ni la tarjeta que ya se conoce ocupa un puesto', () => {
    // El seguimiento ya trae 1 primera gestión, pero la agenda no llegó.
    METRICAS_AGENDA = undefined
    montar()
    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
  })

  it('mientras el seguimiento carga no afirma que no hay nada: «Revisando…»', () => {
    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
    montar()
    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
  })

  it('fail-closed: con el seguimiento o la agenda caídos lo dice, deja reintentar y nunca «Nada que decidir»', () => {
    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: new Error('caído'), isFetching: false })
    AGENDA_ERROR = new Error('agenda caída')
    montar()
    expect(screen.getByText(/Algunas decisiones no se pudieron confirmar/)).toHaveTextContent('no respondió el seguimiento ni la agenda')
    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de las decisiones del día' }))
    expect(REFETCH_COLA).toHaveBeenCalled()
    expect(REFETCH_AGENDA).toHaveBeenCalled()
  })

  it('sin el modo activo confirmado no hay banda de decisiones', () => {
    MODO.activo = false
    MODO.data = undefined
    montar()
    expect(screen.queryByRole('heading', { name: 'Decide primero' })).not.toBeInTheDocument()
  })
})

describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () => {
  it('ESTADO DE PRODUCCIÓN (sin metas publicadas): la franja da cifras con «—» donde no hay dato y sin jerga', () => {
    METRICAS_AGENDA = agenda([
      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', toques: 6, completadas: 3, no_asistio: 1, pct_completadas: 75 },
      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', toques: 4, completadas: 0, no_asistio: 1 },
    ])
    montar()
    const cifras = screen.getByRole('list', { name: 'Cifras del equipo' })
    expect(cifras).toHaveTextContent('S/ 20k pronóstico · +US$ 15k aparte')
    expect(cifras).toHaveTextContent('2 leads activos')
    // Sin meta publicada no hay % de meta que inventar.
    expect(cifras).toHaveTextContent('— de la meta')
    expect(cifras).toHaveTextContent('— conversión del mes')
    expect(cifras).toHaveTextContent('10 toques en 7 días')
    expect(cifras).toHaveTextContent('60 % completadas')
    // 2 no asistió en el equipo: el número va en rojo de TEXTO, con su palabra al lado.
    const itemNoAsistio = within(cifras).getAllByRole('listitem').find((li) => li.textContent === '2 citas sin asistir')!
    expect(itemNoAsistio.querySelector('strong')).toHaveStyle({ color: 'var(--destructive-text)' })
    expect(document.body).not.toHaveTextContent(/pipeline|suma÷suma|solo producción/i)
  })

  it('«Detalle» abre un diálogo con TODO lo que la pantalla clásica mostraba; Esc lo cierra y el foco vuelve', () => {
    vi.useRealTimers()
    montar()
    const boton = screen.getByRole('button', { name: 'Detalle' })
    boton.focus()
    fireEvent.click(boton)
    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
    for (const kpi of ['Pronóstico de capital abierto', 'Leads activos del equipo', 'Primeras gestiones vencidas', 'Por repartir']) {
      expect(within(dialogo).getByText(kpi)).toBeInTheDocument()
    }
    expect(within(dialogo).getByText('Ver cuáles son →')).toBeInTheDocument()
    expect(within(dialogo).getByRole('heading', { name: 'Cumplimiento del mes' })).toBeInTheDocument()
    expect(within(dialogo).getAllByText('Sin meta fijada para este mes').length).toBeGreaterThan(0)
    expect(within(dialogo).getByRole('region', { name: 'Agenda del equipo' })).toBeInTheDocument()
    expect(within(dialogo).getByText(/Ves solo a tu equipo/)).toBeInTheDocument()
    expect(within(dialogo).getByRole('link', { name: 'Por repartir: Ver derivaciones; bandeja sin pendientes' })).toHaveAttribute('href', '#/derivaciones')
    fireEvent.keyDown(dialogo, { key: 'Escape' })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('«Cerrar» también cierra el detalle', () => {
    vi.useRealTimers()
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cerrar' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

describe('Hoy · supervisor — puesto de mando: arreglos de la revisión F2/F3', () => {
  it('una conversión RETENIDA tras un error no se publica en la franja y el aviso es visible sin abrir el detalle', () => {
    CONVERSION = {
      data: {
        version: 1, generado_en: '2026-09-26T15:00:00Z', alcance: 'equipo',
        periodo: { mes: '2026-09', mes_nombre: 'septiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01T05:00:00Z', hasta: '2026-10-01T05:00:00Z' },
        ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
        fuentes: { divisor: 'x', numerador: 'x', referido: 'x' },
        cobertura: { medible: true, suelo_historico: null, motivo_no_medible: null, divisor_aproximado: 0, divisor_por_motivo: { ingreso: 10 }, cierres_sin_episodio: 0, fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 } },
        cartera: {},
        total: { analistas: 1, divisor: 10, cierres_no_referidos: 0, cierres_referidos: 0, cierres_de_arrastre: 0, referidos_recibidos: 0, numerador: 4, conversion_pct: 40, referidos_aporta_pct: null, cartera: {} },
        responsables: [],
      },
      isError: true,
    }
    vi.useRealTimers()
    montar()
    expect(screen.getByRole('list', { name: 'Cifras del equipo' })).toHaveTextContent('— conversión del mes')
    expect(screen.getByText(/No se pudieron cargar algunos indicadores del equipo/)).toBeInTheDocument()
    // Tampoco dentro del detalle: ni porcentaje ni divisor retenidos.
    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
    expect(dialogo).toHaveTextContent('Conversión del mes no disponible')
    expect(dialogo).not.toHaveTextContent(/40[,.]?\d*\s?%|10 recibidos/)
  })

  it('«Detalle» abre con el foco en su título, no en mitad de la rejilla', async () => {
    vi.useRealTimers()
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
    await waitFor(() => expect(document.activeElement).toHaveTextContent('Detalle del equipo'))
  })

  it('«Esta semana» se cierra cuando el foco SALE con el teclado', () => {
    METRICAS_AGENDA = agenda([
      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2 },
      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 5 },
    ])
    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
    montar()
    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
    fireEvent.click(disparador)
    const fuera = screen.getByRole('button', { name: 'Detalle' })
    fireEvent.focusOut(disparador, { relatedTarget: fuera })
    expect(disparador).toHaveAttribute('aria-expanded', 'false')
  })

  it('al cerrar «Detalle» con Esc el foco VUELVE al botón', async () => {
    vi.useRealTimers()
    montar()
    const boton = screen.getByRole('button', { name: 'Detalle' })
    boton.focus()
    fireEvent.click(boton)
    fireEvent.keyDown(screen.getByRole('dialog', { name: 'Detalle del equipo' }), { key: 'Escape' })
    await waitFor(() => expect(boton).toHaveFocus())
  })

  it('«Esta semana» se cierra con un clic fuera y usa la etiqueta del reparto del servidor', () => {
    METRICAS_AGENDA = agenda([
      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2 },
      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 5 },
    ])
    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
    montar()
    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
    fireEvent.click(disparador)
    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
    expect(within(lista).getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
    fireEvent.pointerDown(document.body)
    expect(disparador).toHaveAttribute('aria-expanded', 'false')
  })
})

describe('Hoy · supervisor — puesto de mando: todo número se abre (Miguel, 27/09)', () => {
  it('cada cifra de la franja lleva a su lista: pipeline, leads o el detalle', () => {
    vi.useRealTimers()
    montar()
    const cifras = screen.getByRole('list', { name: 'Cifras del equipo' })
    expect(within(cifras).getByRole('link', { name: /pronóstico/ })).toHaveAttribute('href', '#/pipeline')
    expect(within(cifras).getByRole('link', { name: /leads activos/ })).toHaveAttribute('href', '#/cartera')
    for (const nombre of [/de la meta/, /conversión del mes/, /toques en 7 días/, /completadas/, /sin asistir/]) {
      expect(within(cifras).getByRole('button', { name: nombre })).toBeInTheDocument()
    }
    fireEvent.click(within(cifras).getByRole('button', { name: /sin asistir/ }))
    expect(screen.getByRole('dialog', { name: 'Detalle del equipo' })).toBeInTheDocument()
  })

  it('«Primeras gestiones vencidas» del detalle cierra el diálogo y deja la cola en esa pestaña, con el foco en ella', async () => {
    vi.useRealTimers()
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
    expect(within(dialogo).getByRole('link', { name: /Pronóstico de capital abierto/ })).toHaveAttribute('href', '#/pipeline')
    expect(within(dialogo).getByRole('link', { name: /Leads activos del equipo/ })).toHaveAttribute('href', '#/cartera')
    fireEvent.click(within(dialogo).getByRole('button', { name: /Primeras gestiones vencidas/ }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
    expect(pestana).toHaveAttribute('aria-selected', 'true')
    expect(pedidoCola()?.filtros.senal).toBe('primera_atencion')
    await waitFor(() => expect(pestana).toHaveFocus())
  })
})

describe('Hoy · supervisor — puesto de mando: todo número se abre, segunda tanda (Codex)', () => {
  it('«N en rojo» deja en la lista solo a esos analistas; «Ver todos» los devuelve', () => {
    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
    montar()
    const equipo = () => screen.getByRole('list', { name: 'Analistas del equipo' })
    // El roster trae también al ex analista (sin cartera): 3 filas.
    const todas = within(equipo()).getAllByRole('listitem').length
    fireEvent.click(screen.getByRole('button', { name: '1 en rojo' }))
    expect(screen.getByRole('button', { name: '1 en rojo' })).toHaveAttribute('aria-pressed', 'true')
    expect(within(equipo()).getAllByRole('listitem')).toHaveLength(1)
    expect(equipo()).toHaveTextContent('KAREN ZAPATA')
    fireEvent.click(screen.getByRole('button', { name: 'Ver todos' }))
    expect(within(equipo()).getAllByRole('listitem')).toHaveLength(todas)
  })

  it('si el nivel elegido se queda sin nadie tras una actualización, la lista vuelve entera (Codex)', () => {
    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', no_asistio: 2 }])
    LEADS = [
      lead({ creado_en: '2026-09-26T14:00:00Z' }),
      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
    ]
    const { rerender } = montar()
    fireEvent.click(screen.getByRole('button', { name: '1 en rojo' }))
    const equipo = () => screen.getByRole('list', { name: 'Analistas del equipo' })
    expect(within(equipo()).getAllByRole('listitem')).toHaveLength(1)
    // La agenda se refresca y Jorge ya no tiene no-shows: nadie en rojo.
    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
    rerender(<HoySupervisorMando />)
    expect(screen.getByText('Sin alertas en el equipo')).toBeInTheDocument()
    expect(within(equipo()).getAllByRole('listitem').length).toBeGreaterThan(1)
  })

  it('con más casos que filas, el enlace dice cuántos hay y lleva a Seguimiento', () => {
    RESPONDER = (filtros) => ({ data: pagina(colaTodo(), { filtros: { ...filtros }, total_items: 12, totales: { pendientes: 12 } }), error: null, isFetching: false })
    montar()
    expect(screen.getByRole('link', { name: 'Ver los 12 en Seguimiento' })).toHaveAttribute('href', '#/seguimiento')
  })

  it('los hechos del analista llevan a su día y a la agenda del equipo', () => {
    METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA', toques: 9, pct_completadas: 50 }])
    vi.useRealTimers()
    montar()
    fireEvent.click(within(screen.getByRole('list', { name: 'Analistas del equipo' })).getByRole('button', { name: /KAREN ZAPATA/ }))
    expect(screen.getByRole('link', { name: /activos .* Ver su día/ })).toHaveAttribute('href', '#/gestion-diaria')
    fireEvent.click(screen.getByRole('button', { name: /9 toques en 7 días .* Ver agenda/ }))
    expect(screen.getByRole('dialog', { name: 'Detalle del equipo' })).toBeInTheDocument()
  })

  it('el capital confirmado del detalle se abre en Facturación', () => {
    vi.useRealTimers()
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
    expect(within(screen.getByRole('dialog')).getByRole('link', { name: /→$/ })).toHaveAttribute('href', '#/facturacion')
  })

  it('sin el modo activo la tarjeta «Primeras gestiones vencidas» no tiene acción (no hay cola a la que ir)', () => {
    vi.useRealTimers()
    MODO.activo = false
    MODO.data = undefined
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
    expect(within(screen.getByRole('dialog')).queryByRole('button', { name: /Primeras gestiones vencidas/ })).not.toBeInTheDocument()
  })
})

// Cola v3 (F3, 29/09/2026): las tareas de CLIENTES del equipo entran en la cola
// del supervisor. Sin analista en el payload: la columna dice «Cliente» y la
// fila ENLAZA a la ficha de «Mi cartera» si el cliente tiene una.
describe('HoySupervisorMando · tareas de clientes (cola v3)', () => {
  const INV = 'dddddddd-0000-4000-8000-0000000000a1'
  const senalesCliente = (vencida: boolean) => ({ pendientes: vencida, tareas_vencidas: vencida, primera_atencion: false,
    seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false })
  const cliente = (tarea: string, bucket: 'tarea_vencida' | 'tarea_hoy', sujeto: { perfil_id: string | null; inversionista_id: string | null; nombre: string }) => ({
    clave: `tarea:${tarea}`, tarea_id: tarea, lead_id: null, lead: null, estado: null, bucket,
    severidad: bucket === 'tarea_vencida' ? 'critica' : 'media', prioridad: bucket === 'tarea_vencida' ? 20 : 30,
    referencia_en: bucket === 'tarea_vencida' ? '2026-09-26T12:00:00Z' : '2099-01-01T12:00:00Z',
    senales: senalesCliente(bucket === 'tarea_vencida'), sujeto: { tipo: 'cliente', ...sujeto },
  }) as unknown as ItemCola

  beforeEach(() => {
    // Como el servidor: la de HOY de un cliente solo entra en «Todas»; la vencida, también en «Para atender ahora».
    RESPONDER = (filtros) => ({ data: pagina([
      item({ lead_id: 'l-1', nombre: 'ROSA CHÁVEZ', analistaId: KAREN, analista: 'KAREN ZAPATA' }),
      cliente('t-inv', 'tarea_vencida', { perfil_id: null, inversionista_id: INV, nombre: 'CLIENTA INVERSIONISTA' }),
      ...(filtros.senal === 'todas' ? [cliente('t-portal', 'tarea_hoy', { perfil_id: 'p-1', inversionista_id: null, nombre: 'CLIENTE PORTAL' })] : []),
    ], { filtros: { senal: filtros.senal, etapa: null, analista_id: filtros.analista_id }, totales: { pendientes: 2, tareas_vencidas: 1, clientes: 2 } }), error: null, isFetching: false })
  })

  it('la tarea del cliente dice que es de un cliente, qué toca y desde cuándo, y enlaza a su ficha', () => {
    render(<HoySupervisorMando />)
    const fila = screen.getByRole('link', { name: /^Abrir la ficha de CLIENTA INVERSIONISTA, cliente de la cartera, urgente: Gestión con cliente · venció/ })
    expect(fila).toHaveTextContent('Cliente')
    expect(fila).not.toHaveTextContent('Sin analista')
    expect(fila).toHaveAttribute('href', `#/mi-cartera/inversionista/${INV}`)
    expect(abrirLead).not.toHaveBeenCalled()
  })

  it('mientras se abre la ficha de un lead, el enlace del cliente queda aria-disabled y no navega', () => {
    abrirLead.mockImplementation(() => new Promise<boolean>(() => {}))
    render(<HoySupervisorMando />)
    fireEvent.click(screen.getByRole('button', { name: /^Abrir ficha de ROSA CHÁVEZ/ }))
    const fila = screen.getByRole('link', { name: /^Abrir la ficha de CLIENTA INVERSIONISTA/ })
    expect(fila).toHaveAttribute('aria-disabled', 'true')
    // `fireEvent.click` devuelve false si el manejador llamó a preventDefault.
    expect(fireEvent.click(fila)).toBe(false)
  })

  it('un cliente solo del portal (en «Todas») se lee: la nota va en su línea de estado y no hay enlace', () => {
    render(<HoySupervisorMando />)
    expect(screen.queryByText('CLIENTE PORTAL')).toBeNull()
    fireEvent.click(screen.getByRole('tab', { name: /^Todas/ }))
    expect(screen.queryByRole('link', { name: /CLIENTE PORTAL/ })).toBeNull()
    expect(screen.queryByRole('button', { name: /CLIENTE PORTAL/ })).toBeNull()
    const fila = screen.getByText('CLIENTE PORTAL').closest('li')!
    expect(fila).toHaveTextContent(/Gestión con cliente · vence en .* · Sin ficha en la cartera/)
  })
})
