// Tests de integración del tablero (Pipeline) — la pantalla de trabajo del
// analista. Fijan dos regresiones que se pagan caras:
//  1) tras arrastrar una card a otra columna el tablero se quedaba MUDO: al
//     cambiar de etapa React desmonta la card de la columna vieja, su
//     `onDragEnd` no llega a correr y el guard del click fantasma se quedaba
//     pegado en true — ningún click volvía a abrir una ficha. Por eso el test
//     NO dispara `dragEnd`: reproduce lo que pasa de verdad, no el caso cómodo.
//  2) el chip de capital cantaba "S/ 0" cuando la cartera está en dólares.
//  3) (01/10/2026) la columna «Gestionado»: una vista calculada de la etapa
//     `nuevo` que se llena sola. Lo que se fija es que NO es un destino, que
//     pide su propia lista al servidor y que una lista caída no inventa cifras.
// Se mockean auth y store (sin red, sin providers): aquí se prueba la pantalla.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import type { Actividad, EtapaActiva, Lead, Miembro } from '@/lib/tipos'

const abrirLead = vi.fn()
const abrirNuevoLead = vi.fn()

let YO: { id: string; rol: string; demo: boolean } | null = null
let LEADS: Lead[] = []
let ACTIVIDADES: Actividad[] = []
let VENDEDORES: Miembro[] = []
let CIERRES_MES: number | null = null
/** Fotografía de plazos por lead (vacía = el servidor no la dio). */
let SLA = new Map<string, unknown>()

// Espejo mínimo de `cambiarEtapa`: mueve el lead de columna como haría el store
// real, que es lo que provoca el desmontaje de la card en el drop.
const cambiarEtapa = vi.fn((id: string, etapa: EtapaActiva) => {
  LEADS = LEADS.map((l) => (l.id === id ? { ...l, etapa } : l))
  return { ok: true }
})

vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
// Fase 4d: en sesión real cada columna viene del servidor (etapa + analista);
// aquí, la misma foto del fixture filtrada como lo haría cartera_filtrada_fn.
// Desde el 01/10/2026 el servidor simulado entiende también `gestion`
// (`p_gestion`): `gestionados` son los leads con gestión vigente. Sin eso cada
// lead `nuevo` saldría en «Nuevo» Y en «Gestionado».
const COLUMNAS = vi.hoisted(() => ({
  cargarMas: vi.fn(),
  recargar: vi.fn(),
  pagina: 20,
  gestionados: new Set<string>(),
  /** Gestionados cuya lista «con gestión» todavía no llegó: ya no están en «Nuevo» ni aún en «Gestionado». */
  enCamino: new Set<string>(),
  /** Listas que el servidor simulado no logra servir, como `etapa:gestion`. */
  caidas: new Set<string>(),
  /** Listas cuya primera página sigue en vuelo. */
  cargando: new Set<string>(),
  /** Listas que YA cargaron y cuya relectura falla: conservan lo cargado y traen error. */
  desactualizadas: new Set<string>(),
  /** Filtros con los que la pantalla pidió cada lista (uno por render). */
  pedidos: [] as Array<Record<string, unknown>>,
}))
vi.mock('@/data/use-cartera-paginada', () => ({
  useCarteraPaginada: (_foto: readonly Lead[], f: { etapa?: string; vendedorId?: string; gestion?: string }) => {
    COLUMNAS.pedidos.push({ ...f })
    const base = { hayMas: false, cargando: false, cargandoMas: false, error: null, cargarMas: COLUMNAS.cargarMas, recargar: COLUMNAS.recargar }
    // En demo el hook real recibe una foto vacía y no toca la red: no sirve nada.
    if (YO?.demo) return { ...base, leads: [], resumen: { totales: { vivos: 0 } } }
    const lista = `${f.etapa}:${f.gestion ?? 'entera'}`
    if (COLUMNAS.cargando.has(lista)) return { ...base, leads: [], resumen: undefined, cargando: true }
    if (COLUMNAS.caidas.has(lista)) return { ...base, leads: [], resumen: undefined, error: new Error('PGRST202') }
    const todos = LEADS.filter((l) => l.activo && (f.etapa === 'todas' || !f.etapa || l.etapa === f.etapa)
      && (f.vendedorId === 'todos' || !f.vendedorId ? true : f.vendedorId === 'sin_asignar' ? l.vendedor_id == null : l.vendedor_id === f.vendedorId)
      && (!f.gestion || COLUMNAS.gestionados.has(l.id) === (f.gestion === 'con_gestion'))
      && !(f.gestion === 'con_gestion' && COLUMNAS.enCamino.has(l.id)))
    // Como el servidor: una página de 20 y «hay más»; el total lo dice el resumen.
    return {
      ...base, leads: todos.slice(0, COLUMNAS.pagina), resumen: { totales: { vivos: todos.length } }, hayMas: todos.length > COLUMNAS.pagina,
      // TanStack conserva la última respuesta buena cuando una relectura falla.
      error: COLUMNAS.desactualizadas.has(lista) ? new Error('relectura caída') : null,
    }
  },
}))
vi.mock('@/data/crm-queries', () => ({
  useLeadsSinAsignar: () => ({ data: LEADS.filter((l) => l.vendedor_id == null), isPending: false, isFetching: false, error: null, refetch: vi.fn() }),
}))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({
    indice: SLA,
    cargando: false,
    error: null,
    recargar: vi.fn(),
  }),
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true,
    ambito: { leads: LEADS, vendedores: VENDEDORES, esGlobal: YO?.rol === 'gerencia' },
    actividadesDelAmbito: ACTIVIDADES,
    cambiarEtapa,
  }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead }),
}))
// F1: el hook operativo se sustituye por el espejo puro sobre los MISMOS leads
// del mock — los chips se prueban con números derivados de verdad, sin red ni
// QueryClientProvider (el shape es el del RPC, validado en resumen-cartera.test).
vi.mock('@/data/use-resumen-cartera-operativo', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useResumenCarteraOperativo: (leads: Lead[]) => ({
      resumen: (() => {
        const resumen = resumenCarteraDesdeAmbito(leads, [], Date.now())
        if (CIERRES_MES != null) resumen.totales.convertidos = CIERRES_MES
        return resumen
      })(),
      cargando: false,
      error: null,
      recargar: vi.fn(),
    }),
  }
})

const { Pipeline } = await import('./pipeline')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    telefono: '999888777',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 12000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    vendedor_nombre: 'ANA TORRES',
    creado_en: new Date().toISOString(),
    activo: true,
    ...over,
  }
}

function montar(leads: Lead[] = [lead()]) {
  YO = { id: 'v-1', rol: 'vendedor', demo: false }
  LEADS = leads
  render(<Pipeline />)
}

/** La card clicable del lead (el kanban la expone como role=button). */
function cardDe(nombre: string): HTMLElement {
  const card = screen.getByText(nombre).closest('[role="button"]')
  if (!(card instanceof HTMLElement)) throw new Error(`Sin card para ${nombre}`)
  return card
}

/** Zona de drop de una columna: el hermano de su cabecera (es un contenedor de
 *  cards, no un control — no tiene rol propio al que agarrarse). */
function zonaDe(columna: string): HTMLElement {
  const zona = screen.getByText(columna).parentElement?.nextElementSibling
  if (!(zona instanceof HTMLElement)) throw new Error(`Sin zona de drop en ${columna}`)
  return zona
}

/** DataTransfer de mentira: jsdom no lo implementa. */
function transferencia() {
  const datos = new Map<string, string>()
  return {
    setData: (tipo: string, valor: string) => void datos.set(tipo, valor),
    getData: (tipo: string) => datos.get(tipo) ?? '',
    effectAllowed: 'none',
    dropEffect: 'none',
  }
}

/** La columna entera, por su nombre accesible (cabecera + carril + pie). */
function columna(nombre: string): HTMLElement {
  return screen.getByRole('group', { name: nombre })
}

/** Filtros distintos con los que la pantalla pidió sus listas al servidor. */
function listasPedidas(): Array<Record<string, unknown>> {
  const vistos = new Map<string, Record<string, unknown>>()
  for (const f of COLUMNAS.pedidos) vistos.set(JSON.stringify(f), f)
  return [...vistos.values()]
}

function actividad(over: Partial<Actividad> = {}): Actividad {
  return {
    id: `act-${ACTIVIDADES.length + 1}`,
    lead_id: 'lead-1',
    tipo: 'llamada_no_contestada',
    detalle: null,
    autor_nombre: 'ANA TORRES',
    creado_en: new Date().toISOString(),
    ...over,
  }
}

beforeEach(() => {
  VENDEDORES = []
  ACTIVIDADES = []
  CIERRES_MES = null
  SLA = new Map()
  COLUMNAS.gestionados.clear()
  COLUMNAS.enCamino.clear()
  COLUMNAS.caidas.clear()
  COLUMNAS.cargando.clear()
  COLUMNAS.desactualizadas.clear()
  COLUMNAS.pedidos.length = 0
  abrirLead.mockReset()
  abrirNuevoLead.mockReset()
  cambiarEtapa.mockReset().mockImplementation((id: string, etapa: EtapaActiva) => {
    LEADS = LEADS.map((l) => (l.id === id ? { ...l, etapa } : l))
    return { ok: true }
  })
})

describe('Pipeline · alcance y período de los indicadores', () => {
  it('conserva los cierres mensuales servidos y los totales globales al filtrar columnas', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    VENDEDORES = [
      { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', activo: true, supervisor_id: null },
      { perfil_id: 'v-2', nombre_completo: 'LUIS LOPEZ', rol_crm: 'vendedor', activo: true, supervisor_id: null },
    ]
    LEADS = [lead(), lead({ id: 'l-2', nombre_completo: 'LEAD LUIS', vendedor_id: 'v-2', vendedor_nombre: 'LUIS LOPEZ' })]
    CIERRES_MES = 8
    render(<Pipeline />)
    const abiertos = screen.getByText('Leads abiertos con analista').closest('[data-slot="card"]') as HTMLElement
    const cierres = screen.getAllByText('Cierres de leads del mes')[0]!.closest('[data-slot="card"]') as HTMLElement

    expect(within(abiertos).getByText('2')).toBeInTheDocument()
    expect(within(cierres).getByText('8')).toBeInTheDocument()
    expect(screen.getByText(/Indicadores de toda la empresa/)).toHaveTextContent('Los filtros sólo cambian las columnas')
    fireEvent.click(screen.getByRole('button', { name: 'ANA' }))

    expect(screen.queryByText('LEAD LUIS')).not.toBeInTheDocument()
    expect(within(abiertos).getByText('2')).toBeInTheDocument()
    expect(within(cierres).getByText('8')).toBeInTheDocument()
    expect(screen.getByText('Mes calendario actual')).toBeInTheDocument()
  })
})

describe('tablero Pipeline · arrastrar y seguir trabajando', () => {
  it('tras soltar una card en otra columna el tablero SIGUE abriendo fichas', async () => {
    montar()
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })
    // Sin `dragEnd` a propósito: la card se desmonta al cambiar de columna, así
    // que en el navegador ese evento tampoco llega nunca.
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
    expect(zonaDe('Contactado')).toContainElement(cardDe('ROSA QUISPE'))
    // Sin card fantasma: el atenuado del arrastre se limpia con el drop.
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')

    // El click sintético pegado al drop se sigue ignorando (para eso existe el
    // guard: soltar una card no debe abrir su ficha).
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).not.toHaveBeenCalled()

    // Pasada esa ventana el tablero responde otra vez, sin `dragEnd` que valga.
    await act(async () => {
      await new Promise((listo) => setTimeout(listo, 120))
    })
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('un arrastre abortado (dragEnd sin drop) tampoco deja el tablero mudo', async () => {
    montar()
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragEnd(cardDe('ROSA QUISPE'), { dataTransfer: dt })

    await act(async () => {
      await new Promise((listo) => setTimeout(listo, 120))
    })
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
    expect(cambiarEtapa).not.toHaveBeenCalled()
  })
})

describe('tablero Pipeline · chip de capital', () => {
  it('con la cartera en dólares la cifra principal es USD, no "S/ 0"', () => {
    montar([lead({ monto_estimado: 30000, moneda: 'USD' })])

    expect(screen.getByText('US$ 30,000')).toBeInTheDocument()
    expect(screen.getByText('USD')).toBeInTheDocument()
    expect(screen.queryByText('S/ 0')).not.toBeInTheDocument()
  })

  it('con las dos monedas muestra las dos y NUNCA las suma', () => {
    montar([
      lead({ monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'lead-2', nombre_completo: 'JUAN PEREZ', monto_estimado: 30000, moneda: 'USD' }),
    ])

    expect(screen.getByText('S/ 12,000')).toBeInTheDocument()
    expect(screen.getByText('PEN · +US$ 30k')).toBeInTheDocument()
    // 42k = la suma prohibida (PEN+USD): no puede existir en ninguna moneda.
    expect(screen.queryByText(/42/)).not.toBeInTheDocument()
  })
})

describe('tablero Pipeline · bandeja compacta', () => {
  it('en sesión real la columna pinta la página servida y pide «Cargar más» al servidor (Fase 4d)', () => {
    VENDEDORES = [
      { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', activo: true, supervisor_id: null },
    ]
    montar(
      Array.from({ length: 21 }, (_, i) => lead({
        id: `lead-${i + 1}`,
        nombre_completo: `LEAD ${String(i + 1).padStart(2, '0')}`,
        // Las páginas reales traen el id, sin el nombre resuelto por el store.
        vendedor_id: i === 1 ? 'v-fuera-del-equipo' : i === 2 ? null : 'v-1',
        vendedor_nombre: null,
      })),
    )

    // 20 cargadas de 21 (el total lo dice el servidor), sin paginador local.
    expect(screen.getByText('20 de 21')).toBeInTheDocument()
    expect(cardDe('LEAD 01')).toBeInTheDocument()
    expect(within(cardDe('LEAD 01')).getByText('ANA')).toBeInTheDocument()
    expect(within(cardDe('LEAD 02')).getByText('Analista asignado')).toBeInTheDocument()
    expect(within(cardDe('LEAD 03')).getByText('sin asignar')).toBeInTheDocument()
    expect(screen.getAllByText('sin asignar')).toHaveLength(1)
    expect(screen.queryByText('LEAD 21')).not.toBeInTheDocument()
    expect(zonaDe('Nuevo').className).toContain('overflow-y-auto')
    expect(screen.queryByRole('button', { name: 'Ver página siguiente de Nuevo' })).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Cargar más leads de Nuevo' }))
    expect(COLUMNAS.cargarMas).toHaveBeenCalledTimes(1)
  })
})

// ── «Gestionado» (01/10/2026) ────────────────────────────────────────────────
// Entre «Nuevo» y «Contactado»: leads que ya se intentaron contactar y cuyo
// cliente aún no responde. NO es una etapa (por dentro siguen en `nuevo`): es
// una vista que calcula el servidor. Estas pruebas fijan lo que la pantalla
// promete alrededor de esa columna.
const ROSA = lead()
const JUAN = lead({ id: 'lead-2', nombre_completo: 'JUAN PEREZ' })

describe('tablero Pipeline · columna «Gestionado»', () => {
  it('pinta cinco columnas en orden, con nombre accesible y contador propios', () => {
    COLUMNAS.gestionados.add('lead-2')
    montar([ROSA, JUAN, lead({ id: 'lead-3', nombre_completo: 'LUISA RAMOS', etapa: 'contactado' })])

    expect(screen.getAllByRole('group').map((g) => g.getAttribute('aria-labelledby'))).toEqual([
      'pipeline-columna-nuevo',
      'pipeline-columna-gestionado',
      'pipeline-columna-contactado',
      'pipeline-columna-reunion_agendada',
      'pipeline-columna-propuesta_enviada',
    ])
    for (const nombre of ['Nuevo', 'Gestionado', 'Contactado', 'Cita agendada', 'Entrevista realizada']) {
      expect(columna(nombre)).toBeInTheDocument()
    }
    // Cada lead `nuevo` cae en UNA de las dos mitades, nunca en las dos.
    expect(within(columna('Nuevo')).getByText('ROSA QUISPE')).toBeInTheDocument()
    expect(within(columna('Nuevo')).queryByText('JUAN PEREZ')).not.toBeInTheDocument()
    expect(within(columna('Gestionado')).getByText('JUAN PEREZ')).toBeInTheDocument()
    expect(within(columna('Gestionado')).queryByText('ROSA QUISPE')).not.toBeInTheDocument()
    // El contador se lee entero: la cifra y a qué se refiere.
    expect(within(columna('Gestionado')).getByText('1')).toHaveTextContent('1 lead')
    expect(within(columna('Cita agendada')).getByText('0')).toHaveTextContent('0 leads')
  })

  it('cada columna pide SU lista: `gestion` solo en las dos mitades de `nuevo`', () => {
    montar([ROSA])

    expect(listasPedidas()).toEqual([
      { etapa: 'nuevo', vendedorId: 'todos', integrada: true, gestion: 'sin_gestion' },
      { etapa: 'nuevo', vendedorId: 'todos', integrada: true, gestion: 'con_gestion' },
      { etapa: 'contactado', vendedorId: 'todos', integrada: true },
      { etapa: 'reunion_agendada', vendedorId: 'todos', integrada: true },
      { etapa: 'propuesta_enviada', vendedorId: 'todos', integrada: true },
    ])
    // AUSENTE, no `undefined`: lo que no recorta no viaja al servidor.
    for (const f of listasPedidas().slice(2)) expect(f).not.toHaveProperty('gestion')
  })

  it('el filtro de analista viaja también con las dos mitades de `nuevo`', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    VENDEDORES = [
      { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', activo: true, supervisor_id: null },
      { perfil_id: 'v-2', nombre_completo: 'LUIS LOPEZ', rol_crm: 'vendedor', activo: true, supervisor_id: null },
    ]
    LEADS = [ROSA, lead({ id: 'lead-2', nombre_completo: 'LEAD LUIS', vendedor_id: 'v-2' })]
    COLUMNAS.gestionados.add('lead-1').add('lead-2')
    render(<Pipeline />)
    expect(within(columna('Gestionado')).getByText('LEAD LUIS')).toBeInTheDocument()

    COLUMNAS.pedidos.length = 0
    fireEvent.click(screen.getByRole('button', { name: 'ANA' }))

    expect(listasPedidas().slice(0, 2)).toEqual([
      { etapa: 'nuevo', vendedorId: 'v-1', integrada: true, gestion: 'sin_gestion' },
      { etapa: 'nuevo', vendedorId: 'v-1', integrada: true, gestion: 'con_gestion' },
    ])
    expect(within(columna('Gestionado')).getByText('ROSA QUISPE')).toBeInTheDocument()
    expect(screen.queryByText('LEAD LUIS')).not.toBeInTheDocument()
  })

  it('explica en la propia columna que se llena sola, y no ofrece dar de alta ahí', () => {
    montar([ROSA])

    expect(within(columna('Gestionado')).getByText('Se llena sola al registrar un intento de contacto.')).toBeVisible()
    // La misma frase es la descripción accesible de la columna (y solo de esa).
    expect(columna('Gestionado')).toHaveAccessibleDescription('Se llena sola al registrar un intento de contacto.')
    for (const nombre of ['Nuevo', 'Contactado', 'Cita agendada', 'Entrevista realizada']) {
      expect(columna(nombre)).not.toHaveAttribute('aria-describedby')
    }
    expect(within(columna('Gestionado')).queryByRole('button', { name: /agregar lead/i })).not.toBeInTheDocument()
    // Las cuatro etapas reales conservan su alta; ninguna nace «Gestionado».
    const altas = screen.getAllByRole('button', { name: /agregar lead/i })
    expect(altas).toHaveLength(4)
    altas.forEach((boton) => fireEvent.click(boton))
    expect(abrirNuevoLead.mock.calls.map(([etapa]) => etapa)).toEqual([
      'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada',
    ])
  })

  it('con rol de solo lectura la explicación sigue visible y nadie puede arrastrar', () => {
    YO = { id: 'd-1', rol: 'directorio', demo: false }
    LEADS = [ROSA]
    COLUMNAS.gestionados.add('lead-1')
    render(<Pipeline />)

    expect(within(columna('Gestionado')).getByText('Se llena sola al registrar un intento de contacto.')).toBeVisible()
    expect(cardDe('ROSA QUISPE')).not.toHaveAttribute('draggable')
    expect(screen.queryByRole('button', { name: /agregar lead/i })).not.toBeInTheDocument()
  })
})

describe('tablero Pipeline · arrastre y menú con «Gestionado»', () => {
  it('una tarjeta de «Gestionado» se mueve a Contactado igual que una de «Nuevo»', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])
    const dt = transferencia()
    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    // `false` = el destino canceló el evento, que es como un navegador sabe
    // que ahí SÍ se puede soltar.
    expect(fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })).toBe(false)
    expect(zonaDe('Contactado').className).toContain('ring-2')
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })

    expect(cambiarEtapa).toHaveBeenCalledTimes(1)
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
    expect(zonaDe('Contactado')).toContainElement(cardDe('ROSA QUISPE'))
  })

  it.each(['Cita agendada', 'Entrevista realizada'])('una tarjeta de «Gestionado» también acepta soltarse en «%s»', (destino) => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })

    expect(fireEvent.dragOver(zonaDe(destino), { dataTransfer: dt })).toBe(false)
    expect(zonaDe(destino).className).toContain('ring-2')
  })

  it('«Gestionado» NO es destino: ni se resalta ni acepta una tarjeta de «Nuevo»', () => {
    montar([ROSA])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    // `true` = nadie canceló el evento: el navegador no deja soltar ahí.
    expect(fireEvent.dragOver(zonaDe('Gestionado'), { dataTransfer: dt })).toBe(true)
    expect(zonaDe('Gestionado').className).not.toContain('ring-2')
    expect(within(columna('Gestionado')).queryByText('Suelta aquí para mover el lead')).not.toBeInTheDocument()
    // Aunque un navegador llegara a disparar el soltar, no se mueve nada.
    fireEvent.drop(zonaDe('Gestionado'), { dataTransfer: dt })

    expect(cambiarEtapa).not.toHaveBeenCalled()
    expect(zonaDe('Nuevo')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')
  })

  it.each([
    ['Contactado', 'contactado'],
    ['Cita agendada', 'reunion_agendada'],
    ['Entrevista realizada', 'propuesta_enviada'],
  ] as const)('«Gestionado» tampoco recibe tarjetas de «%s»', (_origen, etapa) => {
    montar([lead({ etapa })])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    expect(fireEvent.dragOver(zonaDe('Gestionado'), { dataTransfer: dt })).toBe(true)
    fireEvent.drop(zonaDe('Gestionado'), { dataTransfer: dt })

    expect(zonaDe('Gestionado').className).not.toContain('ring-2')
    expect(cambiarEtapa).not.toHaveBeenCalled()
  })

  it('soltar una tarjeta de «Gestionado» sobre «Nuevo» no hace nada ni llama al servidor', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    expect(fireEvent.dragOver(zonaDe('Nuevo'), { dataTransfer: dt })).toBe(true)
    expect(zonaDe('Nuevo').className).not.toContain('ring-2')
    fireEvent.drop(zonaDe('Nuevo'), { dataTransfer: dt })

    expect(cambiarEtapa).not.toHaveBeenCalled()
    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
  })

  it('soltar una tarjeta en su propia columna tampoco llama al servidor', () => {
    montar([lead({ etapa: 'contactado' })])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    expect(fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })).toBe(true)
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })

    expect(cambiarEtapa).not.toHaveBeenCalled()
  })

  it('devolver un lead a «Nuevo» desde una etapa posterior sigue funcionando', () => {
    montar([lead({ etapa: 'contactado' })])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    expect(fireEvent.dragOver(zonaDe('Nuevo'), { dataTransfer: dt })).toBe(false)
    fireEvent.drop(zonaDe('Nuevo'), { dataTransfer: dt })

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'nuevo')
  })

  it('tras rechazar un soltar el tablero sigue abriendo fichas (no queda mudo)', async () => {
    montar([ROSA])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Gestionado'), { dataTransfer: dt })
    // El navegador no dispara `drop` sobre quien no lo acepta: llega el
    // `dragEnd` de la tarjeta, que sigue montada.
    fireEvent.dragEnd(cardDe('ROSA QUISPE'), { dataTransfer: dt })

    await act(async () => {
      await new Promise((listo) => setTimeout(listo, 120))
    })
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('sin un arrastre del propio tablero ninguna columna acepta que se suelte algo', () => {
    montar([ROSA])
    const ajeno = transferencia()
    ajeno.setData('text/plain', 'lead-1')

    for (const nombre of ['Nuevo', 'Gestionado', 'Contactado', 'Cita agendada', 'Entrevista realizada']) {
      expect(fireEvent.dragOver(zonaDe(nombre), { dataTransfer: ajeno }), nombre).toBe(true)
    }
  })

  it('el menú «Mover a» de una tarjeta de «Gestionado» no ofrece «Gestionado» ni «Nuevo»', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])

    fireEvent.click(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' }))
    const opciones = screen.getAllByRole('menuitem').map((item) => item.textContent?.trim())
    expect(opciones).toEqual(['Abrir ficha', 'Contactado', 'Cita agendada', 'Entrevista realizada'])

    fireEvent.click(screen.getByRole('menuitem', { name: 'Contactado' }))
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
  })

  it.each([
    ['nuevo', ['Abrir ficha', 'Contactado', 'Cita agendada', 'Entrevista realizada']],
    ['contactado', ['Abrir ficha', 'Nuevo', 'Cita agendada', 'Entrevista realizada']],
    ['reunion_agendada', ['Abrir ficha', 'Nuevo', 'Contactado', 'Entrevista realizada']],
    ['propuesta_enviada', ['Abrir ficha', 'Nuevo', 'Contactado', 'Cita agendada']],
  ] as const)('el menú de una tarjeta en `%s` nunca ofrece «Gestionado»', (etapa, esperadas) => {
    montar([lead({ etapa })])

    fireEvent.click(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' }))

    expect(screen.getAllByRole('menuitem').map((item) => item.textContent?.trim())).toEqual(esperadas)
  })

  it('el aviso del plazo nombra la etapa GUARDADA: una tarjeta de «Gestionado» sigue midiendo su tiempo en Nuevo', () => {
    // El reloj es el del episodio de la etapa `nuevo`, sellado por el servidor.
    const episodio = {
      etapa: 'nuevo',
      etapa_iniciada_en: new Date(Date.now() - 2 * 3_600_000).toISOString(),
      etapa_limite_en: new Date(Date.now() + 22 * 3_600_000).toISOString(),
      etapa_objetivo_minutos: 1_440,
      etapa_politica_version: 3,
      etapa_aproximada: false,
    }
    SLA = new Map([['lead-1', episodio], ['lead-2', episodio]])
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA, JUAN])

    const avisoDe = (nombre: string) => within(cardDe(nombre)).getByTitle(/^Lleva /).getAttribute('title')
    // En «Gestionado»: dice Nuevo y aclara que ya se gestionó; jamás «en Gestionado».
    expect(avisoDe('ROSA QUISPE')).toContain(' en Nuevo (ya gestionado) · plazo sellado 1 día')
    expect(avisoDe('ROSA QUISPE')).not.toContain('en Gestionado')
    // En «Nuevo» el aviso es el de siempre.
    expect(avisoDe('JUAN PEREZ')).toContain(' en Nuevo · plazo sellado 1 día')
  })
})

// REGLA DEL PROYECTO («gate de realidad»): el arreglo se prueba también en el
// estado que hay en PRODUCCIÓN, no solo con el fixture lleno. Aquí son dos:
// la columna vacía (nadie ha registrado un intento todavía) y el servidor que
// aún no sirve una lista (p. ej. sin el parámetro `p_gestion` publicado).
describe('tablero Pipeline · ESTADO DE PRODUCCIÓN de «Gestionado»', () => {
  it('columna vacía: lo dice, explica cómo se llena y no inventa tarjetas', () => {
    montar([ROSA])

    const gestionado = columna('Gestionado')
    expect(within(gestionado).getByText('Sin leads gestionados por ahora')).toBeInTheDocument()
    expect(within(gestionado).getByText('Se llena sola al registrar un intento de contacto.')).toBeVisible()
    expect(within(gestionado).getByText('0')).toHaveTextContent('0 leads')
    expect(within(gestionado).queryAllByRole('button')).toHaveLength(0)
    // El lead sin intentos sigue donde estaba.
    expect(within(columna('Nuevo')).getByText('ROSA QUISPE')).toBeInTheDocument()
  })

  it('tablero sin ningún lead: las cinco columnas vacías, cada una con su texto', () => {
    montar([])

    expect(screen.getAllByText('Sin leads en esta etapa')).toHaveLength(4)
    expect(screen.getAllByText('Sin leads gestionados por ahora')).toHaveLength(1)
  })

  it('lista de «Gestionado» caída: «—» en vez de un cero, lo dice y deja reintentar', () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    montar([ROSA, lead({ id: 'lead-3', nombre_completo: 'LUISA RAMOS', etapa: 'contactado' })])

    const gestionado = columna('Gestionado')
    // Ni «0» ni «Sin leads»: de lo que no se pudo leer no se afirma nada.
    expect(within(gestionado).getByText('Total no disponible')).toBeInTheDocument()
    expect(within(gestionado).queryByText('0')).not.toBeInTheDocument()
    expect(within(gestionado).queryByText('Sin leads')).not.toBeInTheDocument()
    expect(within(gestionado).queryByText('Sin leads gestionados por ahora')).not.toBeInTheDocument()
    expect(within(gestionado).getByText('No se pudo cargar esta columna')).toBeInTheDocument()

    fireEvent.click(within(gestionado).getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' }))
    expect(COLUMNAS.recargar).toHaveBeenCalledTimes(1)
  })

  it('con «Gestionado» caída el resto del tablero sigue operable', async () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    montar([ROSA, lead({ id: 'lead-3', nombre_completo: 'LUISA RAMOS', etapa: 'contactado' })])
    const dt = transferencia()

    // Las demás columnas pintan sus tarjetas y su total…
    expect(within(columna('Nuevo')).getByText('ROSA QUISPE')).toBeInTheDocument()
    expect(within(columna('Nuevo')).getByText('1')).toHaveTextContent('1 lead')
    expect(within(columna('Contactado')).getByText('LUISA RAMOS')).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: /^No se pudo cargar · Reintentar la columna / })).toHaveLength(1)
    // …se abre una ficha…
    fireEvent.click(cardDe('LUISA RAMOS'))
    expect(abrirLead).toHaveBeenCalledWith('lead-3')
    // …y se mueve una tarjeta de etapa.
    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
  })

  it('servidor todavía sin el parámetro: caen las DOS mitades de `nuevo` y el resto no', () => {
    // Un servidor que no conoce `p_gestion` rechaza las dos listas que lo mandan.
    COLUMNAS.caidas.add('nuevo:sin_gestion').add('nuevo:con_gestion')
    montar([ROSA, lead({ id: 'lead-3', nombre_completo: 'LUISA RAMOS', etapa: 'contactado' })])

    for (const nombre of ['Nuevo', 'Gestionado']) {
      expect(within(columna(nombre)).getByText('Total no disponible')).toBeInTheDocument()
      expect(within(columna(nombre)).getByText('No se pudo cargar esta columna')).toBeInTheDocument()
    }
    // El lead `nuevo` no se pinta en ninguna parte: no hay lista que lo traiga.
    expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument()
    expect(within(columna('Contactado')).getByText('LUISA RAMOS')).toBeInTheDocument()
    expect(within(columna('Contactado')).getByText('1')).toHaveTextContent('1 lead')
    expect(screen.getAllByRole('button', { name: /^No se pudo cargar · Reintentar la columna / }).map((b) => b.textContent)).toEqual([
      'No se pudo cargar · Reintentar la columna Nuevo',
      'No se pudo cargar · Reintentar la columna Gestionado',
    ])
  })

  it('mientras una lista carga no se canta un total: «—», no «0»', () => {
    COLUMNAS.cargando.add('nuevo:con_gestion')
    montar([ROSA])

    const gestionado = columna('Gestionado')
    expect(within(gestionado).getByText('Total no disponible')).toBeInTheDocument()
    expect(within(gestionado).getByText('Cargando leads…')).toBeInTheDocument()
    expect(within(gestionado).queryByText('0')).not.toBeInTheDocument()
  })
})

describe('tablero Pipeline · «Gestionado» en modo demo', () => {
  const hace = (horas: number) => new Date(Date.now() - horas * 3_600_000).toISOString()
  /** Lead del fixture demo: entró hace dos días y NO trae `tenencia_desde`. */
  const leadDemo = (over: Partial<Lead> = {}) => lead({ creado_en: hace(48), ...over })

  function montarDemo(leads: Lead[], actividades: Actividad[] = []) {
    YO = { id: 'v-1', rol: 'vendedor', demo: true }
    LEADS = leads
    ACTIVIDADES = actividades
    return render(<Pipeline />)
  }

  /** Nombres de las tarjetas de una columna, en el orden en que se pintan. */
  const tarjetasDe = (nombre: string) =>
    [...zonaDe(nombre).querySelectorAll('[role="button"][draggable="true"]')].map((c) => c.querySelector('p')?.textContent)

  it('reparte las tarjetas con la regla del servidor, calculada en el navegador', () => {
    montarDemo(
      [
        leadDemo(),
        leadDemo({ id: 'lead-2', nombre_completo: 'JUAN PEREZ' }),
        leadDemo({ id: 'lead-3', nombre_completo: 'LUISA RAMOS' }),
        leadDemo({ id: 'lead-4', nombre_completo: 'SIN DUEÑO', vendedor_id: null }),
        leadDemo({ id: 'lead-5', nombre_completo: 'YA CONTACTADA', etapa: 'contactado' }),
        leadDemo({ id: 'lead-6', nombre_completo: 'INTENTO ANTIGUO' }),
      ],
      [
        actividad({ lead_id: 'lead-2', tipo: 'llamada_no_contestada', creado_en: hace(1) }),
        // Una nota no es un intento…
        actividad({ lead_id: 'lead-3', tipo: 'nota', creado_en: hace(1) }),
        // …sin titular no hay gestión, aunque haya un WhatsApp enviado…
        actividad({ lead_id: 'lead-4', tipo: 'whatsapp_enviado', creado_en: hace(1) }),
        actividad({ lead_id: 'lead-5', tipo: 'llamada_realizada', creado_en: hace(1) }),
        // …y lo que se intentó antes de que el lead cambiara de mano, tampoco.
        actividad({ lead_id: 'lead-6', tipo: 'llamada_no_contestada', creado_en: hace(5) }),
        actividad({ lead_id: 'lead-6', tipo: 'reasignacion', creado_en: hace(3) }),
      ],
    )

    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE', 'LUISA RAMOS', 'SIN DUEÑO', 'INTENTO ANTIGUO'])
    expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ'])
    expect(tarjetasDe('Contactado')).toEqual(['YA CONTACTADA'])
    expect(within(columna('Gestionado')).getByText('1')).toHaveTextContent('1 lead')
    expect(within(columna('Nuevo')).getByText('4')).toHaveTextContent('4 leads')
  })

  it('al registrar un intento la tarjeta pasa de «Nuevo» a «Gestionado» sin recargar', () => {
    const vista = montarDemo([leadDemo()])
    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
    expect(tarjetasDe('Gestionado')).toEqual([])

    // Lo que hace el store demo al registrar: añade la gestión al timeline.
    ACTIVIDADES = [actividad({ tipo: 'whatsapp_enviado' })]
    vista.rerender(<Pipeline />)

    expect(tarjetasDe('Gestionado')).toEqual(['ROSA QUISPE'])
    expect(tarjetasDe('Nuevo')).toEqual([])
  })

  it('un lead reasignado vuelve a «Nuevo»: lo que intentó el analista anterior no cuenta', () => {
    const vista = montarDemo([leadDemo()], [actividad({ creado_en: hace(1) })])
    expect(tarjetasDe('Gestionado')).toEqual(['ROSA QUISPE'])

    // El store demo no sella `tenencia_desde`: deja una `reasignacion` en el timeline.
    ACTIVIDADES = [...ACTIVIDADES, actividad({ tipo: 'reasignacion' })]
    vista.rerender(<Pipeline />)

    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
    expect(tarjetasDe('Gestionado')).toEqual([])
  })

  it('en demo el reparto es local: no depende de ninguna lista servida', () => {
    montarDemo([leadDemo()], [actividad({ creado_en: hace(1) })])

    // Los hooks reciben una foto vacía (no sirven nada) y aun así hay tablero.
    expect(tarjetasDe('Gestionado')).toEqual(['ROSA QUISPE'])
    expect(screen.queryByRole('button', { name: /No se pudo cargar/ })).not.toBeInTheDocument()
    expect(screen.queryByText('Total no disponible')).not.toBeInTheDocument()
  })

  it('las reglas de arrastre son las mismas en demo', () => {
    montarDemo([leadDemo()], [actividad({ creado_en: hace(1) })])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    expect(fireEvent.dragOver(zonaDe('Nuevo'), { dataTransfer: dt })).toBe(true)
    fireEvent.drop(zonaDe('Nuevo'), { dataTransfer: dt })
    expect(cambiarEtapa).not.toHaveBeenCalled()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
  })
})

// ── Segunda pasada (01/10/2026): correcciones de las revisiones ───────────────

const GERENCIA = { id: 'g-1', rol: 'gerencia', demo: false }
const EQUIPO: Miembro[] = [
  { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', activo: true, supervisor_id: null },
  { perfil_id: 'v-2', nombre_completo: 'LUIS LOPEZ', rol_crm: 'vendedor', activo: true, supervisor_id: null },
]
const pausa = (ms = 120) => act(async () => { await new Promise((listo) => setTimeout(listo, ms)) })

// Revisión de código, punto 1. Las columnas que no reciben la tarjeta ya no
// cancelan `dragover`, así que el navegador no dispara `drop` sobre ellas: el
// arrastre solo terminaba por el `dragEnd` de la tarjeta de origen. Si ese nodo
// se desmonta en pleno arrastre —la tarjeta salta sola de «Nuevo» a
// «Gestionado» tras un intento o una relectura—, `dragEnd` no llega nunca y el
// tablero dejaba de abrir fichas hasta recargar la página.
describe('tablero Pipeline · el arrastre siempre tiene salida', () => {
  function montarYArrastrar() {
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [ROSA]
    const vista = render(<Pipeline />)
    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: transferencia() })
    expect(cardDe('ROSA QUISPE').className).toContain('opacity-40')
    return vista
  }
  /** El servidor pasa la tarjeta a «Gestionado»: su nodo se desmonta de «Nuevo». */
  function saltarAGestionado(vista: ReturnType<typeof render>) {
    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)
    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
  }

  it('si la tarjeta cambia de columna en pleno arrastre, un clic vuelve a abrir su ficha', async () => {
    const vista = montarYArrastrar()
    // Sin `drop` ni `dragEnd`: el nodo arrastrado ya no existe para recibirlos.
    saltarAGestionado(vista)

    await pausa()
    // Tampoco queda una tarjeta fantasma atenuada en la columna nueva.
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('…y también por teclado y desde «Abrir ficha» del menú', async () => {
    const vista = montarYArrastrar()
    saltarAGestionado(vista)
    await pausa()

    fireEvent.keyDown(cardDe('ROSA QUISPE'), { key: 'Enter' })
    expect(abrirLead).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Abrir ficha' }))
    expect(abrirLead).toHaveBeenCalledTimes(2)
  })

  it('si la tarjeta desaparece del tablero en pleno arrastre, las demás siguen abriendo', async () => {
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [ROSA, JUAN]
    const vista = render(<Pipeline />)
    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: transferencia() })

    // Otro usuario la reasigna o la cierra: ya no está en ninguna columna.
    LEADS = [JUAN]
    vista.rerender(<Pipeline />)
    await pausa()

    fireEvent.click(cardDe('JUAN PEREZ'))
    expect(abrirLead).toHaveBeenCalledWith('lead-2')
  })

  it('si el `dragEnd` se pierde con la tarjeta en su sitio, el siguiente gesto de puntero cierra el arrastre', () => {
    montarYArrastrar()

    // Nadie avisó del final del arrastre. Un `pointerdown` solo puede ocurrir
    // cuando el arrastre ya terminó: es la salida que no depende de ningún nodo.
    fireEvent.pointerDown(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')
    // Es un gesto NUEVO del usuario, no el clic fantasma pegado al soltar: abre ya.
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('…y una tecla también: Enter abre la ficha tras un arrastre que nunca terminó', () => {
    montarYArrastrar()

    fireEvent.keyDown(cardDe('ROSA QUISPE'), { key: 'Enter' })

    expect(abrirLead).toHaveBeenCalledWith('lead-1')
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')
  })

  it('tras cerrarse sola, un arrastre nuevo funciona con normalidad', async () => {
    const vista = montarYArrastrar()
    saltarAGestionado(vista)
    await pausa()
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    expect(fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })).toBe(false)
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
  })

  // Visto en navegador real: tras un soltar RECHAZADO el `dragEnd` sí llega y
  // abre la ventana del clic fantasma. Un clic de verdad trae su `pointerdown`
  // y no tiene por qué esperar a que esa ventana se cierre.
  it('un clic deliberado justo después de soltar (con su `pointerdown`) abre la ficha sin esperar', () => {
    montar([ROSA, JUAN])
    const dt = transferencia()
    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    // «Gestionado» no recibe: no hay `drop`; la tarjeta sigue montada y avisa.
    fireEvent.dragEnd(cardDe('ROSA QUISPE'), { dataTransfer: dt })

    fireEvent.pointerDown(cardDe('ROSA QUISPE'))
    fireEvent.click(cardDe('ROSA QUISPE'))

    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('…y tras un soltar aceptado también: el gesto nuevo sobre OTRA tarjeta la abre al instante', () => {
    montar([ROSA, JUAN])
    const dt = transferencia()
    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })

    fireEvent.pointerDown(cardDe('JUAN PEREZ'))
    fireEvent.click(cardDe('JUAN PEREZ'))

    expect(abrirLead).toHaveBeenCalledWith('lead-2')
  })

  it('sin arrastre de por medio, pulsar o teclear no toca nada del tablero', () => {
    montar([ROSA])

    fireEvent.pointerDown(cardDe('ROSA QUISPE'))
    fireEvent.keyDown(document.body, { key: 'Tab' })
    fireEvent.click(cardDe('ROSA QUISPE'))

    expect(abrirLead).toHaveBeenCalledTimes(1)
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')
  })

  it('el clic fantasma pegado a un soltar aceptado se sigue ignorando (el guard no se debilitó)', () => {
    montar([ROSA, JUAN])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })
    // Ningún `pointerdown` de por medio: es el clic sintético del propio soltar.
    fireEvent.click(cardDe('ROSA QUISPE'))

    expect(abrirLead).not.toHaveBeenCalled()
  })
})

// Revisión de código, punto 3: es la regla, y se fija para que no sorprenda.
describe('tablero Pipeline · devolver un lead a «Nuevo»', () => {
  it('si ya tiene gestión en la tenencia vigente, cae en «Gestionado» y no en «Nuevo»', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([lead({ etapa: 'contactado' })])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Nuevo'), { dataTransfer: dt })
    fireEvent.drop(zonaDe('Nuevo'), { dataTransfer: dt })

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'nuevo')
    // Se soltó en «Nuevo», pero la columna la decide la gestión, no el gesto.
    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(within(columna('Nuevo')).queryByText('ROSA QUISPE')).not.toBeInTheDocument()
  })

  it('sin gestión vigente sí queda en «Nuevo»', () => {
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [lead({ etapa: 'contactado' })]
    const vista = render(<Pipeline />)

    fireEvent.click(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Nuevo' }))
    // En la app el store repinta al cambiar la etapa; aquí se le pide.
    vista.rerender(<Pipeline />)

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'nuevo')
    expect(zonaDe('Nuevo')).toContainElement(cardDe('ROSA QUISPE'))
    expect(within(columna('Gestionado')).queryByText('ROSA QUISPE')).not.toBeInTheDocument()
  })
})

// Revisión de código, punto 7: el capital se pregunta al pasar a «Entrevista
// realizada» venga la tarjeta de donde venga — también de «Gestionado».
describe('tablero Pipeline · capital al pasar una tarjeta de «Gestionado» a «Entrevista realizada»', () => {
  it('por el menú: pide el capital ANTES de cambiar la etapa, y lo guarda en la misma escritura', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])

    fireEvent.click(within(columna('Gestionado')).getByRole('button', { name: 'Acciones de ROSA QUISPE' }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Entrevista realizada' }))

    const dialogo = screen.getByRole('dialog')
    expect(within(dialogo).getByText('¿Cuánto le propusiste a Rosa?')).toBeInTheDocument()
    expect(cambiarEtapa).not.toHaveBeenCalled()
    // Precargado con el estimado del lead: confirmar cuesta un gesto.
    expect(within(dialogo).getByLabelText('Capital propuesto')).toHaveValue(12000)

    fireEvent.click(within(dialogo).getByRole('button', { name: 'Confirmar propuesta' }))

    expect(cambiarEtapa).toHaveBeenCalledTimes(1)
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'propuesta_enviada', { monto_estimado: 12000, moneda: 'PEN' })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('arrastrando: el soltar abre el mismo diálogo y cancelar no mueve nada', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Entrevista realizada'), { dataTransfer: dt })
    fireEvent.drop(zonaDe('Entrevista realizada'), { dataTransfer: dt })

    const dialogo = screen.getByRole('dialog')
    fireEvent.click(within(dialogo).getByRole('button', { name: 'Cancelar' }))

    expect(cambiarEtapa).not.toHaveBeenCalled()
    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
  })
})

// Revisión de código, punto 4. En la bandeja «Por repartir» solo hay leads SIN
// analista, y la regla exige titular: ahí «Gestionado» no puede llenarse nunca.
describe('tablero Pipeline · «Gestionado» en la bandeja «Por repartir»', () => {
  function montarBandeja() {
    YO = GERENCIA
    VENDEDORES = EQUIPO
    LEADS = [ROSA, lead({ id: 'lead-9', nombre_completo: 'SIN ANALISTA', vendedor_id: null })]
    COLUMNAS.gestionados.add('lead-1')
    render(<Pipeline />)
  }

  it('con el filtro puesto la columna no promete llenarse: dice dónde están esos leads', () => {
    montarBandeja()
    expect(within(columna('Gestionado')).getByText('Se llena sola al registrar un intento de contacto.')).toBeVisible()

    fireEvent.click(screen.getByRole('button', { name: /Por repartir/ }))

    const gestionado = columna('Gestionado')
    expect(within(gestionado).queryByText('Se llena sola al registrar un intento de contacto.')).not.toBeInTheDocument()
    expect(within(gestionado).getByText('Los leads sin analista se muestran en Nuevo.')).toBeVisible()
    expect(gestionado).toHaveAccessibleDescription('Los leads sin analista se muestran en Nuevo.')
    // Y el recuadro vacío tampoco insinúa que «por ahora» falte algo.
    expect(within(gestionado).queryByText('Sin leads gestionados por ahora')).not.toBeInTheDocument()
    expect(within(columna('Nuevo')).getByText('SIN ANALISTA')).toBeInTheDocument()
  })

  it('al quitar el filtro vuelve la explicación de siempre', () => {
    montarBandeja()
    fireEvent.click(screen.getByRole('button', { name: /Por repartir/ }))
    fireEvent.click(screen.getByRole('button', { name: 'Todos' }))

    expect(columna('Gestionado')).toHaveAccessibleDescription('Se llena sola al registrar un intento de contacto.')
  })
})

// Revisión de código, punto 5. «No se pudo cargar» se reserva para la lista que
// NUNCA llegó. Si ya había datos y lo que falla es la relectura, se conservan y
// se dice que no se pudieron actualizar: nada de «0 leads» junto a «no cargó».
describe('tablero Pipeline · lista que cargó y luego falla al releer', () => {
  it('conserva las tarjetas y el total, y avisa de que no se pudo actualizar', () => {
    COLUMNAS.gestionados.add('lead-1')
    COLUMNAS.desactualizadas.add('nuevo:con_gestion')
    montar([ROSA])

    const gestionado = columna('Gestionado')
    expect(within(gestionado).getByText('ROSA QUISPE')).toBeInTheDocument()
    expect(within(gestionado).getByText('1')).toHaveTextContent('1 lead')
    expect(within(gestionado).getByText('1 de 1')).toBeInTheDocument()
    expect(within(gestionado).queryByText('No se pudo cargar esta columna')).not.toBeInTheDocument()
    expect(within(gestionado).queryByText('Total no disponible')).not.toBeInTheDocument()

    const reintentar = within(gestionado).getByRole('button', { name: 'No se pudo actualizar · Reintentar la columna Gestionado' })
    fireEvent.click(reintentar)
    expect(COLUMNAS.recargar).toHaveBeenCalledTimes(1)
  })

  it('si lo que había cargado era una columna VACÍA, sigue diciendo que está vacía (no «no se pudo cargar»)', () => {
    COLUMNAS.desactualizadas.add('nuevo:con_gestion')
    montar([ROSA])

    const gestionado = columna('Gestionado')
    expect(within(gestionado).getByText('0')).toHaveTextContent('0 leads')
    expect(within(gestionado).getByText('Sin leads gestionados por ahora')).toBeInTheDocument()
    expect(within(gestionado).queryByText('No se pudo cargar esta columna')).not.toBeInTheDocument()
    expect(within(gestionado).getByRole('button', { name: /^No se pudo actualizar · Reintentar/ })).toBeInTheDocument()
    expect(within(gestionado).queryByRole('button', { name: /^No se pudo cargar/ })).not.toBeInTheDocument()
  })

  it('la que nunca llegó conserva su mensaje: «No se pudo cargar»', () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    montar([ROSA])

    const gestionado = columna('Gestionado')
    expect(within(gestionado).getByText('No se pudo cargar esta columna')).toBeInTheDocument()
    expect(within(gestionado).getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' })).toBeInTheDocument()
    expect(within(gestionado).queryByRole('button', { name: /^No se pudo actualizar/ })).not.toBeInTheDocument()
  })
})

// ── Accesibilidad ────────────────────────────────────────────────────────────

// Punto 1. Al registrar el intento la tarjeta cambia de columna: es un nodo
// NUEVO. Si el foco estaba en la vieja, cae a <body> y el siguiente Tab
// reinicia la página. El tablero lo rescata a la gemela — solo si quedó
// huérfano y no hay un diálogo abierto (ahí manda el diálogo).
describe('tablero Pipeline · el foco sigue a la tarjeta cuando cambia de columna', () => {
  function montarConFoco(leads: Lead[] = [ROSA, JUAN]) {
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = leads
    const vista = render(<Pipeline />)
    act(() => cardDe('ROSA QUISPE').focus())
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
    return vista
  }

  it('la tarjeta lleva una clave de foco estable, la misma en cualquier columna', () => {
    const vista = montarConFoco()
    expect(cardDe('ROSA QUISPE')).toHaveAttribute('data-foco-clave', 'lead-lead-1')

    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)

    expect(cardDe('ROSA QUISPE')).toHaveAttribute('data-foco-clave', 'lead-lead-1')
    expect(cardDe('JUAN PEREZ')).toHaveAttribute('data-foco-clave', 'lead-lead-2')
  })

  it('con el foco en la tarjeta, al saltar a «Gestionado» el foco va con ella', () => {
    const vista = montarConFoco()

    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)

    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  it('…y también al cambiar de etapa por una relectura (otro usuario la movió)', () => {
    const vista = montarConFoco()

    LEADS = [lead({ etapa: 'contactado' }), JUAN]
    vista.rerender(<Pipeline />)

    expect(zonaDe('Contactado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  it('NO roba el foco si el usuario ya está en otro control', () => {
    const vista = montarConFoco()
    act(() => cardDe('JUAN PEREZ').focus())

    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)

    expect(cardDe('JUAN PEREZ')).toHaveFocus()
  })

  it('NO rescata nada si el usuario había soltado el foco antes de que la tarjeta se moviera', async () => {
    const vista = montarConFoco()
    // El usuario pulsa en un hueco: la tarjeta sigue en la página, sin foco. Entre
    // ese gesto y una relectura del servidor siempre media, al menos, un respiro.
    await act(async () => { cardDe('ROSA QUISPE').blur() })

    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)

    expect(document.body).toHaveFocus()
  })

  // Chromium, al QUITAR de la página el nodo enfocado, dispara un `focusout` sin
  // destino con el nodo todavía conectado (medido en navegador real). Es el
  // mismo evento que deja un clic en un hueco: no puede leerse como «el usuario
  // se fue», o el rescate no ocurre nunca en Chrome.
  it('rescata el foco aunque el navegador avise de la retirada con un `focusout` sin destino', async () => {
    const vista = montarConFoco()

    act(() => {
      // Mismo orden que en Chromium: el aviso llega con el nodo aún conectado y,
      // sin soltar el hilo, el nodo desaparece.
      fireEvent.focusOut(cardDe('ROSA QUISPE'), { relatedTarget: null })
      COLUMNAS.gestionados.add('lead-1')
      vista.rerender(<Pipeline />)
    })
    await act(async () => {})

    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  it('cambiar de ventana no borra la marca: la tarjeta conserva el foco del documento', async () => {
    const vista = montarConFoco()
    // La ventana pierde el foco: `focusout` sin destino, pero `activeElement`
    // sigue siendo la tarjeta.
    await act(async () => { fireEvent.focusOut(cardDe('ROSA QUISPE'), { relatedTarget: null }) })
    expect(cardDe('ROSA QUISPE')).toHaveFocus()

    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)

    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  it('…tampoco si el foco estaba en el botón «···» de la tarjeta', async () => {
    const vista = montarConFoco()
    const acciones = screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' })
    act(() => acciones.focus())
    // La ventana pierde el foco: el documento lo conserva en el botón, DENTRO de la tarjeta.
    await act(async () => { fireEvent.focusOut(acciones, { relatedTarget: null }) })
    expect(acciones).toHaveFocus()

    COLUMNAS.gestionados.add('lead-1')
    vista.rerender(<Pipeline />)

    // El botón de antes ya no existe: el foco va a la tarjeta, en su columna nueva.
    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  // «Nuevo» y «Gestionado» son dos listas y dos respuestas: la tarjeta puede
  // salir de una antes de aparecer en la otra.
  it('si sale de «Nuevo» antes de llegar a «Gestionado», el foco la espera y la sigue', () => {
    const vista = montarConFoco()

    COLUMNAS.gestionados.add('lead-1')
    COLUMNAS.enCamino.add('lead-1')
    vista.rerender(<Pipeline />)
    // Llegó la lista de «Nuevo»; la de «Gestionado» todavía no.
    expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument()
    expect(document.body).toHaveFocus()

    COLUMNAS.enCamino.clear()
    vista.rerender(<Pipeline />)

    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  it('…pero no la espera para siempre: si reaparece mucho después, el foco no salta a ella', () => {
    const reloj = vi.spyOn(Date, 'now')
    try {
      const inicio = 1_800_000_000_000
      reloj.mockReturnValue(inicio)
      const vista = montarConFoco()
      COLUMNAS.gestionados.add('lead-1')
      COLUMNAS.enCamino.add('lead-1')
      vista.rerender(<Pipeline />)
      expect(document.body).toHaveFocus()

      // Pasa el plazo: el lead salió del tablero. Si un rato después vuelve a
      // aparecer, enfocarlo sería mover al usuario sin que haya hecho nada.
      reloj.mockReturnValue(inicio + 5_001)
      COLUMNAS.enCamino.clear()
      vista.rerender(<Pipeline />)

      expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
      expect(document.body).toHaveFocus()
    } finally {
      reloj.mockRestore()
    }
  })

  it('…y dentro del plazo sí: a los 4,9 s todavía se le devuelve el foco', () => {
    const reloj = vi.spyOn(Date, 'now')
    try {
      const inicio = 1_800_000_000_000
      reloj.mockReturnValue(inicio)
      const vista = montarConFoco()
      COLUMNAS.gestionados.add('lead-1')
      COLUMNAS.enCamino.add('lead-1')
      vista.rerender(<Pipeline />)

      reloj.mockReturnValue(inicio + 4_900)
      COLUMNAS.enCamino.clear()
      vista.rerender(<Pipeline />)

      expect(cardDe('ROSA QUISPE')).toHaveFocus()
    } finally {
      reloj.mockRestore()
    }
  })

  // La marca se entera de los cambios de foco por `focusin`. Un control que no
  // deja subir ese evento (los hay) cambia el foco sin que el tablero lo vea:
  // ahí lo único que impide el robo es comprobar que el foco quedó HUÉRFANO.
  it('NO roba el foco de un control cuyo `focusin` no llegó al tablero', () => {
    const vista = montarConFoco()
    const sigiloso = document.createElement('button')
    sigiloso.textContent = 'Control que no avisa'
    sigiloso.addEventListener('focusin', (e) => e.stopPropagation())
    document.body.append(sigiloso)
    try {
      act(() => sigiloso.focus())
      expect(sigiloso).toHaveFocus()

      COLUMNAS.gestionados.add('lead-1')
      vista.rerender(<Pipeline />)

      expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
      expect(sigiloso).toHaveFocus()
    } finally {
      sigiloso.remove()
    }
  })

  it('mientras espera, si el usuario se va a otro control ya no se le quita el foco', () => {
    const vista = montarConFoco()
    COLUMNAS.gestionados.add('lead-1')
    COLUMNAS.enCamino.add('lead-1')
    vista.rerender(<Pipeline />)

    act(() => cardDe('JUAN PEREZ').focus())
    COLUMNAS.enCamino.clear()
    vista.rerender(<Pipeline />)

    expect(zonaDe('Gestionado')).toContainElement(cardDe('ROSA QUISPE'))
    expect(cardDe('JUAN PEREZ')).toHaveFocus()
  })

  it('NO rescata nada mientras haya un diálogo abierto: al cerrarse, él devuelve el foco', () => {
    const vista = montarConFoco()
    const dialogo = document.createElement('div')
    dialogo.setAttribute('role', 'dialog')
    document.body.append(dialogo)
    try {
      COLUMNAS.gestionados.add('lead-1')
      vista.rerender(<Pipeline />)

      expect(cardDe('ROSA QUISPE')).not.toHaveFocus()
    } finally {
      dialogo.remove()
    }
  })

  it('si la tarjeta sale del tablero no hay a quién enfocar, y no revienta', () => {
    const vista = montarConFoco()

    LEADS = [JUAN]
    vista.rerender(<Pipeline />)

    expect(document.body).toHaveFocus()
    expect(cardDe('JUAN PEREZ')).toBeInTheDocument()
  })
})

// Punto 2. El pie es la región viva de la columna: tiene que anunciarse entero
// y decir DE QUÉ columna habla; al caerse la lista ya no puede quedar mudo.
describe('tablero Pipeline · el pie de cada columna se anuncia', () => {
  const pieDe = (nombre: string) => {
    const pie = columna(nombre).querySelector('[aria-live="polite"]')
    if (!(pie instanceof HTMLElement)) throw new Error(`Sin región viva en ${nombre}`)
    return pie
  }

  it('nombra la columna y se lee completo', () => {
    COLUMNAS.gestionados.add('lead-1')
    montar([ROSA])

    expect(pieDe('Gestionado')).toHaveAttribute('aria-atomic', 'true')
    expect(pieDe('Gestionado')).toHaveTextContent('Gestionado: 1 de 1')
    expect(pieDe('Nuevo')).toHaveTextContent('Nuevo: Sin leads')
    // Lo visible no cambia: el nombre va solo para el lector de pantalla.
    expect(within(pieDe('Gestionado')).getByText('1 de 1')).toBeVisible()
    expect(within(pieDe('Gestionado')).getByText('Gestionado:')).toHaveClass('sr-only')
  })

  it('al caerse la lista dice que no se pudo cargar, en vez de quedarse vacío', () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    montar([ROSA])

    expect(pieDe('Gestionado')).toHaveTextContent('Gestionado: no se pudo cargar')
    expect(within(pieDe('Gestionado')).getByText('no se pudo cargar')).toHaveClass('sr-only')
    // Un solo anuncio: el recuadro de la columna no es otra región viva.
    expect(columna('Gestionado').querySelectorAll('[role="status"], [role="alert"]')).toHaveLength(0)
    expect(columna('Gestionado').querySelectorAll('[aria-live]')).toHaveLength(1)
  })

  it('mientras carga lo dice, también con el nombre de la columna', () => {
    COLUMNAS.cargando.add('nuevo:con_gestion')
    montar([ROSA])

    expect(pieDe('Gestionado')).toHaveTextContent('Gestionado: Cargando…')
  })

  it('si lo que falla es una relectura, conserva la cifra y añade que no se pudo actualizar', () => {
    COLUMNAS.gestionados.add('lead-1')
    COLUMNAS.desactualizadas.add('nuevo:con_gestion')
    montar([ROSA])

    expect(pieDe('Gestionado')).toHaveTextContent('Gestionado: 1 de 1, no se pudo actualizar')
    expect(within(pieDe('Gestionado')).getByText(', no se pudo actualizar')).toHaveClass('sr-only')
    expect(pieDe('Gestionado')).not.toHaveTextContent('no se pudo cargar')
    // Las columnas que sí se releyeron no dicen nada de más.
    expect(pieDe('Nuevo')).toHaveTextContent(/^Nuevo: Sin leads$/)
  })
})

// Punto 3 (anterior a «Gestionado»): el menú «···» vive dentro de una tarjeta
// que también responde al teclado. El escudo que evita que Enter/Espacio abran
// la ficha no puede tragarse las flechas, Inicio/Fin ni Escape del propio menú.
describe('tablero Pipeline · menú «···» de la tarjeta por teclado', () => {
  function abrirMenu() {
    montar([ROSA])
    fireEvent.click(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' }))
    return screen.getAllByRole('menuitem')
  }

  it('al abrir, el foco entra en la primera opción; las flechas lo mueven', () => {
    const opciones = abrirMenu()
    expect(opciones[0]).toHaveFocus()

    fireEvent.keyDown(opciones[0]!, { key: 'ArrowDown' })
    expect(opciones[1]).toHaveFocus()

    fireEvent.keyDown(opciones[1]!, { key: 'End' })
    expect(opciones.at(-1)).toHaveFocus()

    fireEvent.keyDown(opciones.at(-1)!, { key: 'Home' })
    expect(opciones[0]).toHaveFocus()

    fireEvent.keyDown(opciones[0]!, { key: 'ArrowUp' })
    expect(opciones.at(-1)).toHaveFocus()
  })

  it('Escape cierra el menú y devuelve el foco al botón «···»', () => {
    const opciones = abrirMenu()

    fireEvent.keyDown(opciones[0]!, { key: 'Escape' })

    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' })).toHaveFocus()
    expect(abrirLead).not.toHaveBeenCalled()
  })

  it('Enter y Espacio sobre el menú siguen SIN abrir la ficha de la tarjeta', () => {
    const opciones = abrirMenu()

    fireEvent.keyDown(opciones[1]!, { key: 'Enter' })
    fireEvent.keyDown(opciones[1]!, { key: ' ' })
    fireEvent.keyDown(screen.getByRole('button', { name: 'Acciones de ROSA QUISPE' }), { key: 'Enter' })

    expect(abrirLead).not.toHaveBeenCalled()
  })

  it('las opciones de destino forman un grupo con nombre: «Mover a»', () => {
    abrirMenu()

    const grupo = screen.getByRole('group', { name: 'Mover a' })
    expect(within(grupo).getAllByRole('menuitem').map((o) => o.textContent?.trim())).toEqual([
      'Contactado', 'Cita agendada', 'Entrevista realizada',
    ])
    // «Abrir ficha» no es un destino: queda fuera del grupo.
    expect(within(grupo).queryByRole('menuitem', { name: 'Abrir ficha' })).not.toBeInTheDocument()
  })
})

// Puntos 4, 5 y 7.
describe('tablero Pipeline · detalles de accesibilidad de la columna', () => {
  it('los textos nuevos de 11 px y el «—» del contador usan el gris oscuro (contraste)', () => {
    COLUMNAS.caidas.add('nuevo:sin_gestion')
    montar([ROSA])

    expect(within(columna('Gestionado')).getByText('Sin leads gestionados por ahora')).toHaveClass('text-muted-foreground-strong')
    expect(within(columna('Nuevo')).getByText('No se pudo cargar esta columna')).toHaveClass('text-muted-foreground-strong')
    expect(within(columna('Nuevo')).getByText('—')).toHaveClass('text-muted-foreground-strong')
  })

  it('el contador ancla su texto oculto: el contenedor es `relative`', () => {
    montar([ROSA])

    const contador = within(columna('Nuevo')).getByText('1')
    expect(contador).toHaveClass('relative')
    expect(contador.querySelector('.sr-only')).not.toBeNull()
  })

  it('«Reintentar» dice de qué columna es', () => {
    COLUMNAS.caidas.add('nuevo:sin_gestion').add('nuevo:con_gestion')
    montar([ROSA])

    expect(screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Nuevo' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' })).toBeInTheDocument()
  })

  it('al recuperarse la columna, el foco que tenía «Reintentar» pasa a la columna y no se pierde', () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [ROSA]
    const vista = render(<Pipeline />)
    const reintentar = screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' })
    act(() => reintentar.focus())
    fireEvent.click(reintentar)

    // El servidor responde: el botón se desmonta y el foco quedaría en <body>.
    COLUMNAS.caidas.clear()
    vista.rerender(<Pipeline />)

    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(columna('Gestionado')).toHaveFocus()
  })

  it('si el usuario ya se fue a otro control, la recuperación no le quita el foco', () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [ROSA]
    const vista = render(<Pipeline />)
    const reintentar = screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' })
    act(() => reintentar.focus())
    fireEvent.click(reintentar)
    act(() => cardDe('ROSA QUISPE').focus())

    COLUMNAS.caidas.clear()
    vista.rerender(<Pipeline />)

    expect(cardDe('ROSA QUISPE')).toHaveFocus()
  })

  // Con ratón el botón puede no llegar a tener el foco (Safari no enfoca al
  // hacer clic). Entonces no se pierde nada al desmontarlo, y enfocar la
  // columna sería mover al usuario sin motivo.
  it('si «Reintentar» se pulsó sin tener el foco, al recuperarse no se enfoca nada', () => {
    COLUMNAS.caidas.add('nuevo:con_gestion')
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [ROSA]
    const vista = render(<Pipeline />)
    fireEvent.click(screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' }))
    expect(document.body).toHaveFocus()

    COLUMNAS.caidas.clear()
    vista.rerender(<Pipeline />)

    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(document.body).toHaveFocus()
  })
})
