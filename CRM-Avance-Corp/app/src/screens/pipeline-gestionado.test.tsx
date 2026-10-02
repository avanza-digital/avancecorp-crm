// El tablero con sus listas DE VERDAD (01/10/2026, columna «Gestionado»).
//
// `pipeline.test.tsx` sustituye entero el hook que sirve las columnas: prueba
// la pantalla, pero no puede ver los fallos que esta columna hace posibles:
//   1. que «Nuevo» y «Gestionado» compartan caché. Piden la misma etapa y el
//      mismo analista: si la gestión no estuviera en la clave de la consulta,
//      saldría UNA petición y las dos columnas pintarían la misma lista;
//   2. que al registrar un intento la tarjeta no cambie de columna hasta
//      recargar, porque una de las dos listas no se volvió a pedir;
//   3. que una relectura fallida borre lo que la columna ya tenía cargado.
// Aquí corre lo real —`useCarteraPaginada`, `useCarteraInfinita`, las claves y
// un QueryClient— contra un servidor simulado que APLICA LA REGLA de
// `p_gestion` sobre un timeline y pagina por cursor como `cartera_filtrada_fn`.
// Los casos se escriben con HECHOS (registrar un intento, reasignar, deshacer),
// no marcando a mano qué lead «está gestionado».
import { createElement, type ReactNode } from 'react'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { TAMANO_PAGINA_CARTERA } from '@/lib/cartera-keyset'
import type { Lead } from '@/lib/tipos'

interface FiltrosPedidos {
  etapa?: string
  vendedorId?: string
  gestion?: string
  integrada?: boolean
}
interface CursorPedido { actualizadoEn: string; id: string }
interface Gestion { lead_id: string; tipo: string; creado_en: string; metadata?: Record<string, unknown> }

const servidor = vi.hoisted(() => ({
  leads: [] as unknown[],
  /** Timeline (`crm.actividades`): de aquí sale la gestión vigente. */
  actividades: [] as unknown[],
  /** `true` = servidor anterior a la migración: no conoce `p_gestion`. */
  sinParametroGestion: false,
  /** `true` = todas las listas fallan (caída después de haber cargado). */
  caido: false,
  listarCarteraPagina: vi.fn(),
}))

vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))
vi.mock('@/lib/supabase', () => ({ sb: null }))
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: { id: 'v-1', rol: 'vendedor', demo: false } }),
}))
vi.mock('@/data/crm-api', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/data/crm-api')>(),
  listarCarteraPagina: servidor.listarCarteraPagina,
  listarLeadsSinAsignar: async () => [],
}))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({ indice: new Map(), cargando: false, error: null, recargar: vi.fn() }),
}))
vi.mock('@/data/use-resumen-cartera-operativo', () => ({
  useResumenCarteraOperativo: () => ({ resumen: null, cargando: false, error: null, recargar: vi.fn() }),
}))
const cambiarEtapa = vi.fn(() => ({ ok: true }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    conocerLeads: () => {},
    ambito: { leads: [], vendedores: [], esGlobal: false },
    actividadesDelAmbito: [],
    cambiarEtapa,
  }),
  usePanelesActions: () => ({ abrirLead: vi.fn(), abrirNuevoLead: vi.fn() }),
}))

const { CrmApiError } = await import('@/data/crm-api')
const { crmQueryKeys } = await import('@/data/crm-queries')
const { Pipeline } = await import('./pipeline')

// ── Servidor simulado ────────────────────────────────────────────────────────

/** Reloj del servidor: cada hecho ocurre un minuto después del anterior. */
let reloj = 0
const ahoraServidor = () => new Date((reloj += 60_000)).toISOString()
const INICIO = '2026-09-01T10:00:00.000Z'

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
    creado_en: INICIO,
    actualizado_en: INICIO,
    tenencia_desde: INICIO,
    activo: true,
    ...over,
  }
}
const leadsDelServidor = () => servidor.leads as Lead[]
const gestiones = () => servidor.actividades as Gestion[]
const TIPOS_CONTACTO = ['llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada']

/** El predicado de `p_gestion`, tal cual está en la migración. */
function conGestion(l: Lead): boolean {
  if (l.vendedor_id == null || l.tenencia_desde == null) return false
  const desde = Date.parse(l.tenencia_desde)
  return gestiones().some((g) => g.lead_id === l.id && TIPOS_CONTACTO.includes(g.tipo)
    && Date.parse(g.creado_en) >= desde && !(g.metadata && 'deshecho_en' in g.metadata))
}

/** Espejo de `crm.cartera_filtrada_fn`: filtro, orden `(actualizado_en desc, id asc)` y cursor. */
async function cartera(filtros: FiltrosPedidos, cursor: CursorPedido | null) {
  if (servidor.caido) throw new CrmApiError('No se pudo cargar la cartera.', 'PGRST000')
  if (filtros.gestion && servidor.sinParametroGestion) {
    throw new CrmApiError('No se pudo cargar la cartera.', 'PGRST202')
  }
  const base = leadsDelServidor()
    .filter((l) => l.etapa === filtros.etapa
      && (!filtros.gestion || conGestion(l) === (filtros.gestion === 'con_gestion')))
    .sort((a, b) => (a.actualizado_en! === b.actualizado_en! ? (a.id < b.id ? -1 : 1) : a.actualizado_en! < b.actualizado_en! ? 1 : -1))
  const resto = cursor
    ? base.filter((l) => l.actualizado_en! < cursor.actualizadoEn || (l.actualizado_en === cursor.actualizadoEn && l.id > cursor.id))
    : base
  const items = resto.slice(0, TAMANO_PAGINA_CARTERA)
  const ultima = items.at(-1)
  return {
    items,
    cursor: resto.length > TAMANO_PAGINA_CARTERA && ultima ? { actualizadoEn: ultima.actualizado_en!, id: ultima.id } : null,
    // El total es de TODA la lista filtrada, no de la página.
    resumen: { totales: { vivos: base.length } },
  }
}

// Hechos, como los escribe el servidor real.
const hechos = {
  /** Una gestión entra al timeline. NO toca la fila del lead (`actualizado_en` no cambia). */
  registrar(leadId: string, tipo = 'llamada_no_contestada', metadata?: Record<string, unknown>) {
    gestiones().push({ lead_id: leadId, tipo, creado_en: ahoraServidor(), ...(metadata ? { metadata } : {}) })
  },
  /** Deshacer un resultado de llamada: la gestión queda marcada, no se borra. */
  deshacerUltima(leadId: string) {
    const ultima = gestiones().filter((g) => g.lead_id === leadId).at(-1)
    if (!ultima) throw new Error(`Sin gestiones que deshacer en ${leadId}`)
    ultima.metadata = { ...ultima.metadata, deshecho_en: ahoraServidor() }
  },
  /** Cambio de titular: el trigger renueva `tenencia_desde` y la fila se actualiza. */
  reasignar(leadId: string, vendedorId: string) {
    const instante = ahoraServidor()
    servidor.leads = leadsDelServidor().map((l) => (l.id === leadId
      ? { ...l, vendedor_id: vendedorId, tenencia_desde: instante, actualizado_en: instante }
      : l))
  },
  /** Cambio de etapa dentro de lo operativo: NO renueva la tenencia. */
  moverEtapa(leadId: string, etapa: Lead['etapa']) {
    const instante = ahoraServidor()
    servidor.leads = leadsDelServidor().map((l) => (l.id === leadId ? { ...l, etapa, actualizado_en: instante } : l))
  },
}

function montar() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  render(<Pipeline />, { wrapper })
  return cliente
}

/**
 * Lo que hace el store tras CONFIRMAR una escritura (`resincronizarReal`,
 * fijado en store-real.test): cancela lo que esté en vuelo y caduca todo lo que
 * cuelga de `leads()`. Aquí se reproduce tal cual, sin montar el store.
 */
async function resincronizarComoElStore(cliente: QueryClient) {
  await act(async () => {
    await cliente.cancelQueries({ queryKey: crmQueryKeys.leads() })
    await cliente.invalidateQueries({ queryKey: crmQueryKeys.leads() })
  })
}

const columna = (nombre: string) => screen.getByRole('group', { name: nombre })
const tarjetasDe = (nombre: string) =>
  [...columna(nombre).querySelectorAll('[role="button"][draggable="true"]')].map((c) => c.querySelector('p')?.textContent)
/** Copia ordenada: cuando el orden entre tarjetas no es lo que se prueba. */
const ordenadas = (nombres: Array<string | null | undefined>) => [...nombres].sort()
const pedidosDe = (gestion: string | undefined, etapa = 'nuevo') =>
  servidor.listarCarteraPagina.mock.calls.filter(([f]) => (f as FiltrosPedidos).etapa === etapa && (f as FiltrosPedidos).gestion === gestion)

beforeEach(() => {
  reloj = Date.parse('2026-09-10T15:00:00.000Z')
  servidor.leads = [
    lead(),
    lead({ id: 'lead-2', nombre_completo: 'JUAN PEREZ' }),
    lead({ id: 'lead-3', nombre_completo: 'LUISA RAMOS', etapa: 'contactado' }),
  ]
  servidor.actividades = []
  servidor.sinParametroGestion = false
  servidor.caido = false
  servidor.listarCarteraPagina.mockReset().mockImplementation(cartera)
  cambiarEtapa.mockReset().mockReturnValue({ ok: true })
  // Estado inicial: a JUAN ya le intentaron llamar; a LUISA le contestaron.
  hechos.registrar('lead-2')
  hechos.registrar('lead-3', 'llamada_realizada')
})

describe('Pipeline con listas reales · «Nuevo» y «Gestionado» no comparten caché', () => {
  it('cada mitad de `nuevo` pinta SU lista, y cada columna pide lo suyo al servidor', async () => {
    montar()

    await waitFor(() => { expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ']) })
    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
    expect(tarjetasDe('Contactado')).toEqual(['LUISA RAMOS'])
    expect(within(columna('Nuevo')).getByText('1')).toHaveTextContent('1 lead')
    expect(within(columna('Gestionado')).getByText('1')).toHaveTextContent('1 lead')

    // Cinco listas, cinco peticiones: la gestión solo viaja en las dos de `nuevo`.
    const pedidos = servidor.listarCarteraPagina.mock.calls.map(([f]) => f as FiltrosPedidos)
    expect(pedidos).toHaveLength(5)
    expect(pedidos.map((f) => [f.etapa, f.gestion])).toEqual([
      ['nuevo', 'sin_gestion'],
      ['nuevo', 'con_gestion'],
      ['contactado', undefined],
      ['reunion_agendada', undefined],
      ['propuesta_enviada', undefined],
    ])
    for (const f of pedidos.slice(2)) expect(f).not.toHaveProperty('gestion')
    expect(pedidos.every((f) => f.integrada === true)).toBe(true)
  })

  it('las dos listas viven bajo claves distintas del mismo prefijo `leads()`', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ']) })

    const claves = cliente.getQueryCache().findAll({ queryKey: [...crmQueryKeys.leads(), 'cartera-pagina', 'nuevo'] })
      .map((q) => q.queryKey)
    expect(claves).toHaveLength(2)
    // La gestión es el PENÚLTIMO componente de la clave; el último es el potencial
    // (filtro de Leads), que el Pipeline no usa: `null`.
    expect(claves.map((clave) => clave.at(-2)).sort()).toEqual(['con_gestion', 'sin_gestion'])
    expect(claves.map((clave) => clave.at(-1))).toEqual([null, null])
  })
})

describe('Pipeline con listas reales · el tablero sigue al servidor sin recargar', () => {
  it('al registrar un intento la tarjeta pasa de «Nuevo» a «Gestionado», sin remontar el tablero', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE']) })
    const tablero = columna('Nuevo').parentElement
    servidor.listarCarteraPagina.mockClear()

    // El analista registra «no contestó» sobre ROSA: el servidor guarda la
    // gestión (la etapa sigue en `nuevo`) y el store resincroniza.
    hechos.registrar('lead-1')
    await resincronizarComoElStore(cliente)

    await waitFor(() => { expect(ordenadas(tarjetasDe('Gestionado'))).toEqual(['JUAN PEREZ', 'ROSA QUISPE']) })
    expect(tarjetasDe('Nuevo')).toEqual([])
    // Los totales de las dos columnas se mueven con las tarjetas.
    expect(within(columna('Nuevo')).getByText('0')).toHaveTextContent('0 leads')
    expect(within(columna('Gestionado')).getByText('2')).toHaveTextContent('2 leads')
    expect(within(columna('Nuevo')).getByText('Sin leads en esta etapa')).toBeInTheDocument()
    // Se volvieron a pedir LAS DOS mitades, no solo una…
    expect(pedidosDe('sin_gestion')).toHaveLength(1)
    expect(pedidosDe('con_gestion')).toHaveLength(1)
    // …y es el mismo tablero: nada se desmontó para conseguirlo.
    expect(columna('Nuevo').parentElement).toBe(tablero)
  })

  it('una NOTA no la mueve: no es un intento de contacto', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE']) })

    hechos.registrar('lead-1', 'nota')
    await resincronizarComoElStore(cliente)

    await waitFor(() => { expect(pedidosDe('sin_gestion').length).toBeGreaterThan(1) })
    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
    expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ'])
  })

  // DECISIÓN DE MIGUEL: reasignado, lo que intentó el analista anterior ya no
  // cuenta. Aquí el hecho es la reasignación (el servidor renueva la tenencia),
  // no un lead quitado a mano de un conjunto.
  it('al reasignar un lead ya intentado vuelve a «Nuevo», hasta que el titular ACTUAL lo intente', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ']) })

    hechos.reasignar('lead-2', 'v-2')
    await resincronizarComoElStore(cliente)

    // El intento del analista anterior sigue en el timeline, pero es ANTERIOR a
    // la tenencia nueva: la tarjeta es «Nuevo» para quien la recibe.
    await waitFor(() => { expect(ordenadas(tarjetasDe('Nuevo'))).toEqual(['JUAN PEREZ', 'ROSA QUISPE']) })
    expect(tarjetasDe('Gestionado')).toEqual([])
    expect(within(columna('Gestionado')).getByText('Sin leads gestionados por ahora')).toBeInTheDocument()
    expect(gestiones().filter((g) => g.lead_id === 'lead-2')).toHaveLength(1)

    hechos.registrar('lead-2', 'whatsapp_enviado')
    await resincronizarComoElStore(cliente)

    await waitFor(() => { expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ']) })
    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
  })

  // Regla del 01/10: un resultado de llamada DESHECHO no cuenta como gestión.
  it('al deshacer el resultado de la llamada la tarjeta vuelve a «Nuevo»', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE']) })
    hechos.registrar('lead-1', 'llamada_no_contestada', { evento: 'resultado_llamada', resultado: 'no_contesto' })
    await resincronizarComoElStore(cliente)
    await waitFor(() => { expect(tarjetasDe('Gestionado')).toContain('ROSA QUISPE') })

    hechos.deshacerUltima('lead-1')
    await resincronizarComoElStore(cliente)

    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE']) })
    expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ'])
    // La llamada sigue existiendo (marcada); lo que cambió es que ya no cuenta.
    expect(gestiones().filter((g) => g.lead_id === 'lead-1')).toHaveLength(1)
  })

  it('…y si le queda OTRO intento vivo, deshacer uno no la saca de «Gestionado»', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE']) })
    hechos.registrar('lead-1', 'whatsapp_enviado')
    hechos.registrar('lead-1', 'llamada_no_contestada', { evento: 'resultado_llamada', resultado: 'no_contesto' })
    await resincronizarComoElStore(cliente)
    await waitFor(() => { expect(tarjetasDe('Gestionado')).toContain('ROSA QUISPE') })
    servidor.listarCarteraPagina.mockClear()

    hechos.deshacerUltima('lead-1')
    await resincronizarComoElStore(cliente)

    await waitFor(() => { expect(pedidosDe('con_gestion')).toHaveLength(1) })
    expect(ordenadas(tarjetasDe('Gestionado'))).toEqual(['JUAN PEREZ', 'ROSA QUISPE'])
    expect(tarjetasDe('Nuevo')).toEqual([])
  })

  it('una tarjeta recién llegada a «Gestionado» se mueve a Contactado como cualquier `nuevo`', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE']) })
    hechos.registrar('lead-1')
    await resincronizarComoElStore(cliente)
    await waitFor(() => { expect(tarjetasDe('Gestionado')).toContain('ROSA QUISPE') })

    fireEvent.click(within(columna('Gestionado')).getByRole('button', { name: 'Acciones de ROSA QUISPE' }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Contactado' }))

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
  })

  // Revisión, punto 3: es la regla y puede sorprender, así que se fija.
  it('devolver a «Nuevo» un lead con gestión en su tenencia lo deja en «Gestionado»', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Contactado')).toEqual(['LUISA RAMOS']) })

    fireEvent.click(within(columna('Contactado')).getByRole('button', { name: 'Acciones de LUISA RAMOS' }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Nuevo' }))
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-3', 'nuevo')
    // El servidor aplica el cambio de etapa (la tenencia NO se renueva)…
    hechos.moverEtapa('lead-3', 'nuevo')
    await resincronizarComoElStore(cliente)

    // …y su llamada sigue contando: cae en «Gestionado», no en «Nuevo».
    await waitFor(() => { expect(ordenadas(tarjetasDe('Gestionado'))).toEqual(['JUAN PEREZ', 'LUISA RAMOS']) })
    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
    expect(tarjetasDe('Contactado')).toEqual([])
  })
})

// Revisión, punto 2. La lista se ordena por `actualizado_en` y registrar un
// intento NO toca la fila del lead: la tarjeta entra en «Gestionado» en su
// posición de siempre. Con más de una página puede quedar tras «Cargar más».
// No se reordena (es el mismo paginado de las demás columnas y decide Miguel):
// se fija que el total la cuenta y que se alcanza cargando más.
describe('Pipeline con listas reales · «Gestionado» con más de una página', () => {
  const dia = (n: number) => new Date(Date.parse('2026-09-05T10:00:00.000Z') + n * 60_000).toISOString()

  it('un lead antiguo recién intentado sube el contador y se alcanza con «Cargar más»', async () => {
    // 60 gestionados recientes y un lead ANTIGUO que todavía nadie ha intentado.
    servidor.leads = [
      ...Array.from({ length: 60 }, (_, i) => lead({
        id: `g-${String(i).padStart(2, '0')}`, nombre_completo: `GESTIONADO ${String(i).padStart(2, '0')}`, actualizado_en: dia(100 + i),
      })),
      lead({ id: 'antiguo', nombre_completo: 'LEAD ANTIGUO', actualizado_en: dia(0) }),
    ]
    servidor.actividades = []
    for (let i = 0; i < 60; i += 1) hechos.registrar(`g-${String(i).padStart(2, '0')}`)
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual(['LEAD ANTIGUO']) })
    expect(within(columna('Gestionado')).getByText(`${TAMANO_PAGINA_CARTERA} de 60`)).toBeInTheDocument()

    hechos.registrar('antiguo')
    await resincronizarComoElStore(cliente)

    // Sale de «Nuevo» y el total de «Gestionado» ya la cuenta…
    await waitFor(() => { expect(tarjetasDe('Nuevo')).toEqual([]) })
    await waitFor(() => { expect(within(columna('Gestionado')).getByText('61')).toHaveTextContent('61 leads') })
    expect(within(columna('Gestionado')).getByText(`${TAMANO_PAGINA_CARTERA} de 61`)).toBeInTheDocument()
    // …pero entra en su posición de siempre (la última): no está entre las
    // cargadas. No se ha perdido: está tras «Cargar más».
    expect(screen.queryByText('LEAD ANTIGUO')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Cargar más leads de Gestionado' }))

    await waitFor(() => { expect(within(columna('Gestionado')).getByText('LEAD ANTIGUO')).toBeInTheDocument() })
    expect(within(columna('Gestionado')).getByText('61 de 61')).toBeInTheDocument()
    expect(tarjetasDe('Gestionado').at(-1)).toBe('LEAD ANTIGUO')
    expect(screen.queryByRole('button', { name: 'Cargar más leads de Gestionado' })).not.toBeInTheDocument()
  })
})

// Revisión, punto 5, con el comportamiento REAL de la caché: una relectura que
// falla conserva la última respuesta buena. «No se pudo cargar» es para la
// lista que nunca llegó; aquí lo honesto es «no se pudo actualizar».
describe('Pipeline con listas reales · lista que cargó y luego falla al releer', () => {
  it('conserva tarjetas y totales, y ofrece reintentar la actualización', async () => {
    const cliente = montar()
    await waitFor(() => { expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ']) })

    servidor.caido = true
    await resincronizarComoElStore(cliente)

    await waitFor(() => {
      expect(screen.getAllByRole('button', { name: /^No se pudo actualizar · Reintentar la columna / })).toHaveLength(5)
    })
    expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ'])
    expect(tarjetasDe('Nuevo')).toEqual(['ROSA QUISPE'])
    expect(within(columna('Gestionado')).getByText('1')).toHaveTextContent('1 lead')
    // La columna que estaba VACÍA sigue diciendo que está vacía.
    expect(within(columna('Cita agendada')).getByText('0')).toHaveTextContent('0 leads')
    expect(within(columna('Cita agendada')).getByText('Sin leads en esta etapa')).toBeInTheDocument()
    expect(screen.queryByText('No se pudo cargar esta columna')).not.toBeInTheDocument()
    expect(screen.queryByText('Total no disponible')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /^No se pudo cargar/ })).not.toBeInTheDocument()

    // El servidor vuelve: reintentar una columna la pone al día.
    servidor.caido = false
    hechos.registrar('lead-1')
    fireEvent.click(screen.getByRole('button', { name: 'No se pudo actualizar · Reintentar la columna Gestionado' }))

    await waitFor(() => { expect(ordenadas(tarjetasDe('Gestionado'))).toEqual(['JUAN PEREZ', 'ROSA QUISPE']) })
    expect(within(columna('Gestionado')).queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
  })
})

// ESTADO DE PRODUCCIÓN («gate de realidad»): la pantalla puede publicarse antes
// que la migración. Un servidor que aún no conoce `p_gestion` rechaza las dos
// listas que lo mandan — y solo esas.
describe('Pipeline con listas reales · servidor todavía sin el parámetro', () => {
  it('caen las dos mitades de `nuevo`, lo dicen sin inventar cifras, y el resto sigue operable', async () => {
    servidor.sinParametroGestion = true
    montar()

    await waitFor(() => { expect(tarjetasDe('Contactado')).toEqual(['LUISA RAMOS']) })
    await waitFor(() => {
      expect(screen.getAllByRole('button', { name: /^No se pudo cargar · Reintentar la columna / })).toHaveLength(2)
    })
    for (const nombre of ['Nuevo', 'Gestionado']) {
      expect(within(columna(nombre)).getByText('Total no disponible')).toBeInTheDocument()
      expect(within(columna(nombre)).getByText('No se pudo cargar esta columna')).toBeInTheDocument()
      expect(within(columna(nombre)).queryByText('0')).not.toBeInTheDocument()
      expect(within(columna(nombre)).queryByText('Sin leads')).not.toBeInTheDocument()
      expect(tarjetasDe(nombre)).toEqual([])
    }
    // La explicación de la columna no depende del servidor.
    expect(within(columna('Gestionado')).getByText('Se llena sola al registrar un intento de contacto.')).toBeVisible()
    // Las otras tres columnas no mandan el parámetro: cargan y se operan.
    expect(within(columna('Contactado')).getByText('1')).toHaveTextContent('1 lead')
    expect(within(columna('Cita agendada')).getByText('0')).toHaveTextContent('0 leads')
    fireEvent.click(within(columna('Contactado')).getByRole('button', { name: 'Acciones de LUISA RAMOS' }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Cita agendada' }))
    expect(cambiarEtapa).toHaveBeenCalledWith('lead-3', 'reunion_agendada')
  })

  it('cuando el servidor ya lo conoce, «Reintentar» recupera la columna sin recargar la página', async () => {
    servidor.sinParametroGestion = true
    montar()
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' })).toBeInTheDocument()
    })

    servidor.sinParametroGestion = false
    fireEvent.click(screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Gestionado' }))

    await waitFor(() => { expect(tarjetasDe('Gestionado')).toEqual(['JUAN PEREZ']) })
    expect(within(columna('Gestionado')).queryByText('Total no disponible')).not.toBeInTheDocument()
    expect(within(columna('Gestionado')).getByText('1')).toHaveTextContent('1 lead')
    // «Nuevo» sigue caída hasta que se reintenta la suya: cada lista es propia.
    expect(screen.getByRole('button', { name: 'No se pudo cargar · Reintentar la columna Nuevo' })).toBeInTheDocument()
  })
})
