// «Gestión de la base» (F4): el panel por analista (todo número se abre), la hoja del equipo con «Gestiona», el filtro
// Analista y páginas de 50, «Ver no contactar» con el bloque al final, y la ficha de consulta. Primero el ESTADO DE
// PRODUCCIÓN (gate de realidad): la B6b no está aplicada (sin vetados ni detalle), la base puede estar vacía y un
// supervisor puede no tener analistas.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { FilaBaseGestion, FilaDetalleCifra, FilaResumenBase } from '@/lib/base-gestion'
import type { LecturaBaseGestion } from '@/data/crm-api'
import type { Lead, Miembro } from '@/lib/tipos'

let YO: { id: string; rol: string; demo: boolean } | null = null
let LEADS: Lead[] = []
let EQUIPO: Miembro[] = []
const refetch = vi.fn()
type Consulta<T> = { data?: T; isPending: boolean; isError: boolean; isFetching: boolean; isPlaceholderData?: boolean; refetch: () => void }
let BASE: (incluirVetados: boolean) => Consulta<LecturaBaseGestion>
let PANEL: Consulta<FilaResumenBase[]>
let DETALLE: Consulta<FilaDetalleCifra[] | null>
const useBaseGestionEquipo = vi.fn((_h: boolean, v: boolean) => BASE(v))
const useBaseGestionResumen = vi.fn((_h: boolean) => PANEL)
const useBaseGestionResumenDetalle = vi.fn((_h: boolean, _id: string | null, _c: string | null) => DETALLE)
const abrirLead = vi.fn()

vi.mock('sonner', () => ({ toast: { success: vi.fn(), info: vi.fn(), error: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ leads: LEADS, equipo: EQUIPO, lead: (id: string) => (id === 'en-cartera' ? ({ id } as Lead) : undefined), recargar: async () => true }),
  usePanelesActions: () => ({ abrirLead }),
}))
vi.mock('@/data/crm-queries', () => ({
  useBaseGestionEquipo: (h: boolean, v: boolean) => useBaseGestionEquipo(h, v),
  useBaseGestionResumen: (h: boolean) => useBaseGestionResumen(h),
  useBaseGestionResumenDetalle: (h: boolean, id: string | null, c: string | null) => useBaseGestionResumenDetalle(h, id, c),
}))
// La ficha tiene sus propias pruebas: aquí basta con saber que se abre EN CONSULTA y con qué lead.
vi.mock('@/components/base-gestion/ficha-base', () => ({
  FichaBase: ({ fila, modo }: { fila: { nombre_completo: string } | null; modo?: string }) => (fila ? <p>Ficha de {fila.nombre_completo} ({modo ?? 'analista'})</p> : null),
}))

const { GestionSupervisor } = await import('./gestion-supervisor')

const ANA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const BETO = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'

function fila(n: number, sobre: Partial<FilaBaseGestion> = {}): FilaBaseGestion {
  return {
    lead_id: `lead-${n}`, nombre_completo: `LEAD BASE ${n}`, telefono: `+5198765${String(4000 + n)}`, distrito: 'Surco', origen: 'landing',
    categoria_interes: null, monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde',
    descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
    ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
    rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: ANA, gestiona: 'ANA PÉREZ', recibido_en: '2026-08-15T15:00:00Z', ...sobre,
  }
}
const vetada = (n: number, sobre: Partial<FilaBaseGestion> = {}) => fila(n, {
  no_contactar: true, no_contactar_en: '2026-09-28T16:00:00Z', no_contactar_motivo: 'Pidió que no lo llamen más', no_contactar_por: 'ANA PÉREZ', ...sobre,
})
const resumen = (sobre: Partial<FilaResumenBase> = {}): FilaResumenBase => ({ vendedor_id: ANA, nombre: 'ANA PÉREZ', en_base: 2, rellamadas_hoy: 1, intentos_hoy: 3, reactivaciones_mes: 0, ...sobre })

const listo = <T,>(data: T, extra: Partial<Consulta<T>> = {}): Consulta<T> => ({ data, isPending: false, isError: false, isFetching: false, refetch, ...extra })
const onAnalista = vi.fn()
const montar = (analistaInicial: string | null = null) => render(<GestionSupervisor analistaInicial={analistaInicial} onAnalista={onAnalista} />)

const panel = () => screen.getByRole('region', { name: 'Por analista' })
const hoja = () => screen.getByRole('region', { name: /^Base para gestión de tu equipo/ })
const filasDeLeads = (contenedor: HTMLElement = within(hoja()).getByRole('table')) =>
  within(contenedor).getAllByRole('row').filter((r) => within(r).queryByRole('rowheader') !== null)
const nombres = (filas: HTMLElement[]) => filas.map((f) => within(f).getByRole('rowheader').textContent?.replace(' — toca llamar hoy', ''))
const numeros = (filas: HTMLElement[]) => filas.map((f) => f.querySelector('td')?.textContent)

beforeEach(() => {
  YO = { id: 'sup-1', rol: 'supervisor', demo: false }
  LEADS = []
  EQUIPO = []
  BASE = (v) => listo({ filas: [fila(1), fila(2, { vendedor_id: BETO, gestiona: 'BETO RÍOS' })], conVetados: true }, { isPlaceholderData: false, ...(v ? {} : {}) })
  PANEL = listo([resumen(), resumen({ vendedor_id: BETO, nombre: 'BETO RÍOS', en_base: 1, rellamadas_hoy: 0, intentos_hoy: 0, reactivaciones_mes: 2 })])
  DETALLE = { isPending: true, isError: false, isFetching: true, refetch }
})
afterEach(() => { vi.clearAllMocks(); vi.useRealTimers() })

describe('ESTADO DE PRODUCCIÓN (gate de realidad)', () => {
  it('B6b sin aplicar: la hoja llega igual, sin «Ver no contactar» y las cifras de detalle se leen pero no se abren', () => {
    BASE = () => listo({ filas: [fila(1)], conVetados: false })
    montar()
    expect(screen.queryByRole('button', { name: 'Ver no contactar' })).toBeNull()
    // «Intentos de hoy» (3) no es botón; «En base» (2) sí (filtra la hoja, eso no depende de la B6b).
    expect(within(panel()).queryByRole('button', { name: /intentos de hoy/ })).toBeNull()
    expect(within(panel()).getByRole('button', { name: /ANA PÉREZ, en base:\s?2/ })).toBeInTheDocument()
    expect(screen.getByText(/El detalle de intentos y reactivaciones llega con la próxima actualización del servidor/)).toBeInTheDocument()
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 1'])
  })

  it('base vacía: el panel dice sus ceros (ninguno se abre) y la hoja explica qué pasa', () => {
    BASE = () => listo({ filas: [], conVetados: false })
    PANEL = listo([resumen({ en_base: 0, rellamadas_hoy: 0, intentos_hoy: 0, reactivaciones_mes: 0 })])
    montar()
    expect(within(panel()).queryAllByRole('button')).toHaveLength(0)
    expect(screen.getByText('No hay leads descartados por gestionar de tu equipo')).toBeInTheDocument()
    expect(screen.queryByRole('group', { name: 'Filtrar la base' })).toBeNull()
  })

  it('supervisor sin analistas: el panel lo dice (no una tabla vacía) y la bandeja del equipo se sigue viendo', () => {
    PANEL = listo([])
    BASE = () => listo({ filas: [fila(1, { vendedor_id: null, gestiona: null })], conVetados: false })
    montar()
    expect(screen.queryByRole('region', { name: 'Por analista' })).toBeNull()
    expect(screen.getByText(/No hay analistas activos en tu ámbito/)).toBeInTheDocument()
    const [primera] = filasDeLeads()
    expect(within(primera!).getByText('Sin analista')).toBeInTheDocument()
  })

  it('si el panel falla, la hoja sigue y ofrece reintentar; al salir bien el foco va al título del panel (no a <body>)', async () => {
    PANEL = { isPending: false, isError: true, isFetching: false, refetch: vi.fn(async () => { PANEL = listo([resumen()]); return { isSuccess: true } }) }
    const { rerender } = montar()
    expect(screen.getByRole('alert')).toHaveTextContent(/No se pudo cargar el panel por analista/)
    expect(filasDeLeads()).toHaveLength(2)
    await userEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    rerender(<GestionSupervisor analistaInicial={null} onAnalista={onAnalista} />)
    await vi.waitFor(() => expect(screen.getByRole('heading', { name: 'Por analista' })).toHaveFocus())
  })

  it('si la base falla sin datos, error con reintento', () => {
    BASE = () => ({ isPending: false, isError: true, isFetching: false, refetch })
    montar()
    expect(screen.getByText('No se pudo cargar la base de tu equipo.')).toBeInTheDocument()
  })
})

describe('la hoja del equipo', () => {
  it('«Gestiona» es la tercera columna (fija), el teléfono se lee pero no marca ni copia, y el nombre abre la ficha EN CONSULTA', async () => {
    montar()
    const encabezados = within(hoja()).getAllByRole('columnheader').map((c) => c.textContent)
    expect(encabezados.slice(0, 3)).toEqual(['#', 'Lead', 'Gestiona'])
    expect(within(hoja()).getAllByRole('columnheader')[2]).toHaveClass('sticky')
    expect(within(hoja()).queryByRole('button', { name: /Llamar a/ })).toBeNull()
    expect(within(hoja()).getByText('987 654 001')).toBeInTheDocument()
    await userEvent.click(within(hoja()).getByRole('button', { name: 'LEAD BASE 2' }))
    expect(screen.getByText('Ficha de LEAD BASE 2 (supervision)')).toBeInTheDocument()
  })

  it('filtro Analista: cada analista con su conteo, «Sin analista» al final; elegirlo filtra y avisa a la URL', async () => {
    BASE = () => listo({ filas: [fila(1), fila(2, { vendedor_id: BETO, gestiona: 'BETO RÍOS' }), fila(3), fila(4, { vendedor_id: null, gestiona: null })], conVetados: true })
    montar()
    const selector = screen.getByRole('combobox', { name: 'Analista' })
    expect(within(selector).getAllByRole('option').map((o) => o.textContent)).toEqual(['Todos (4)', 'ANA PÉREZ (2)', 'BETO RÍOS (1)', 'Sin analista (1)'])
    await userEvent.selectOptions(selector, BETO)
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 2'])
    expect(onAnalista).toHaveBeenLastCalledWith(BETO)
    const resumenBase = screen.getByRole('region', { name: 'Resumen de la base' })
    expect(within(resumenBase).getByText('De BETO RÍOS')).toBeInTheDocument()
  })

  it('el analista que trae la URL filtra la hoja al cargar', () => {
    montar(BETO)
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 2'])
    expect(screen.getByRole('combobox', { name: 'Analista' })).toHaveValue(BETO)
  })

  it('un analista de la URL que no está en la base no filtra nada (vuelve a «Todos» y se borra de la URL)', () => {
    montar('cccccccc-cccc-4ccc-8ccc-cccccccccccc')
    expect(filasDeLeads()).toHaveLength(2)
    expect(onAnalista).toHaveBeenLastCalledWith(null)
  })

  it('mientras la lista carga, el analista de la URL NO se pierde', () => {
    BASE = () => ({ isPending: true, isError: false, isFetching: true, refetch })
    const { rerender } = montar(BETO)
    expect(onAnalista).not.toHaveBeenCalledWith(null)
    BASE = () => listo({ filas: [fila(1), fila(2, { vendedor_id: BETO, gestiona: 'BETO RÍOS' })], conVetados: true })
    rerender(<GestionSupervisor analistaInicial={BETO} onAnalista={onAnalista} />)
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 2'])
  })

  it('páginas de 50 con el número de fila continuo; «Llamar hoy» arriba con su conteo total', async () => {
    const muchas = Array.from({ length: 120 }, (_, i) => fila(i + 1, i < 3 ? { rellamada_hoy: true, proxima_llamada_en: '2026-10-03T20:00:00Z' } : {}))
    BASE = () => listo({ filas: muchas, conVetados: true })
    montar()
    expect(numeros(filasDeLeads())).toHaveLength(50)
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(expect.arrayContaining(['Llamar hoy:3', 'El resto:117']))
    expect(screen.getByText('Página 1 de 3 · 120 registros')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Siguiente' }))
    const pagina2 = filasDeLeads()
    expect(numeros(pagina2)[0]).toBe('51')
    expect(numeros(pagina2).at(-1)).toBe('100')
    // En la página 2 no hay filas de «Llamar hoy»: no se pinta su banda.
    expect(screen.queryByRole('heading', { name: /^Llamar hoy/ })).toBeNull()
    // Filtrar vuelve a la página 1.
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), 'no_responde')
    expect(numeros(filasDeLeads())[0]).toBe('1')
  })
})

describe('el panel por analista: todo número se abre', () => {
  it('«En base» filtra la hoja SOLO por ese analista (quita los otros filtros) y lleva el foco a la hoja', async () => {
    montar()
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), 'no_responde')
    await userEvent.click(within(panel()).getByRole('button', { name: /BETO RÍOS, en base:\s?1/ }))
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 2'])
    expect(screen.getByRole('combobox', { name: 'Motivo del descarte' })).toHaveValue('todos')
    expect(hoja()).toHaveFocus()
    // El renglón del analista elegido se marca.
    expect(within(panel()).getByText('En la hoja')).toBeInTheDocument()
  })

  it('«Para llamar hoy» filtra por el analista y lleva el foco al bloque «Llamar hoy»', async () => {
    BASE = () => listo({ filas: [fila(1, { rellamada_hoy: true, proxima_llamada_en: '2026-10-03T20:00:00Z' }), fila(3), fila(2, { vendedor_id: BETO, gestiona: 'BETO RÍOS' })], conVetados: true })
    montar()
    await userEvent.click(within(panel()).getByRole('button', { name: /ANA PÉREZ, para llamar hoy:\s?1/ }))
    expect(screen.getByRole('heading', { name: /^Llamar hoy/ })).toHaveFocus()
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 1', 'LEAD BASE 3'])
  })

  it('una cifra en 0 no es botón', () => {
    montar()
    expect(within(panel()).queryByRole('button', { name: /BETO RÍOS, para llamar hoy/ })).toBeNull()
    expect(within(panel()).queryByRole('button', { name: /BETO RÍOS, intentos de hoy/ })).toBeNull()
  })

  it('«Intentos de hoy» abre su detalle en una hoja lateral (pide ese analista y esa cifra); el lead en la base abre su ficha', async () => {
    DETALLE = listo([
      { lead_id: 'lead-1', nombre_completo: 'LEAD BASE 1', en: '2026-10-03T15:00:00Z', detalle: 'no_contesto', autor: 'ANA PÉREZ', sigue_en_base: true },
      { lead_id: 'en-cartera', nombre_completo: 'YA REACTIVADO', en: '2026-10-03T14:00:00Z', detalle: 'agendo_reunion', autor: 'SUPERVISOR UNO', sigue_en_base: false },
      { lead_id: 'fuera', nombre_completo: 'NO CARGADO', en: '2026-10-03T13:00:00Z', detalle: null, autor: null, sigue_en_base: false },
    ])
    montar()
    await userEvent.click(within(panel()).getByRole('button', { name: /ANA PÉREZ, intentos de hoy:\s?3/ }))
    const detalle = screen.getByRole('dialog', { name: /Intentos de hoy/ })
    expect(useBaseGestionResumenDetalle).toHaveBeenLastCalledWith(true, ANA, 'intentos_hoy')
    expect(within(detalle).getByText('No contestó')).toBeInTheDocument()
    expect(within(detalle).getAllByText('Salió de la base')).toHaveLength(2)
    // El que no está ni en la base ni en el CRM se lee pero no se abre.
    expect(within(detalle).queryByRole('button', { name: 'NO CARGADO' })).toBeNull()
    await userEvent.click(within(detalle).getByRole('button', { name: 'YA REACTIVADO' }))
    expect(abrirLead).toHaveBeenCalledWith('en-cartera')
    await userEvent.click(within(detalle).getByRole('button', { name: 'LEAD BASE 1' }))
    expect(screen.getByText('Ficha de LEAD BASE 1 (supervision)')).toBeInTheDocument()
  })

  it('el detalle que el servidor aún no tiene (null) dice «no disponible», nunca «cero»', async () => {
    DETALLE = listo(null)
    montar()
    await userEvent.click(within(panel()).getByRole('button', { name: /BETO RÍOS, reactivaciones del mes:\s?2/ }))
    expect(screen.getByText('El detalle aún no está disponible')).toBeInTheDocument()
  })
})

describe('«Ver no contactar»', () => {
  it('el interruptor pide los vetados y los pone en un bloque AL FINAL con su marca: cuándo, motivo y quién', async () => {
    BASE = (v) => listo({ filas: v ? [fila(1), fila(2, { vendedor_id: BETO, gestiona: 'BETO RÍOS' }), vetada(9), vetada(8, { no_contactar_en: null, no_contactar_motivo: null, no_contactar_por: null })] : [fila(1), fila(2, { vendedor_id: BETO, gestiona: 'BETO RÍOS' })], conVetados: true })
    montar()
    const interruptor = screen.getByRole('button', { name: 'Ver no contactar' })
    expect(interruptor).toHaveAttribute('aria-pressed', 'false')
    await userEvent.click(interruptor)
    expect(useBaseGestionEquipo).toHaveBeenLastCalledWith(true, true)
    expect(screen.getByRole('button', { name: 'Ver no contactar' })).toHaveAttribute('aria-pressed', 'true')
    const bloque = screen.getByRole('region', { name: /^No contactar/ })
    // Después de la hoja (al final).
    expect(hoja().compareDocumentPosition(bloque) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(within(bloque).getByText('Pidió que no lo llamen más')).toBeInTheDocument()
    expect(within(bloque).getAllByText('ANA PÉREZ').length).toBeGreaterThanOrEqual(1)
    expect(within(bloque).getByText('Viene de otro lead de la persona')).toBeInTheDocument()
    // Los vetados NO están en la hoja principal, ni su teléfono se ofrece.
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 1', 'LEAD BASE 2'])
    expect(within(bloque).queryByRole('button', { name: /Llamar/ })).toBeNull()
    // La pastilla «No contactar» cuenta lo del bloque y se abre.
    await userEvent.click(screen.getByRole('button', { name: /^No contactar:\s?2, ver el bloque$/ }))
    expect(screen.getByRole('heading', { name: /^No contactar/ })).toHaveFocus()
    // El nombre abre la ficha (donde se quita la marca).
    await userEvent.click(within(bloque).getByRole('button', { name: 'LEAD BASE 9' }))
    expect(screen.getByText('Ficha de LEAD BASE 9 (supervision)')).toBeInTheDocument()
  })

  it('mientras llega la lista con los vetados, la hoja no se vacía y el bloque dice que carga', async () => {
    BASE = (v) => listo({ filas: [fila(1)], conVetados: true }, { isPlaceholderData: v })
    montar()
    await userEvent.click(screen.getByRole('button', { name: 'Ver no contactar' }))
    expect(filasDeLeads()).toHaveLength(1)
    expect(screen.getAllByText('Cargando los leads con «No contactar»…').length).toBeGreaterThanOrEqual(1)
  })

  it('el resultado del interruptor se anuncia en una región de estado que YA existía (vacía) antes de encenderlo', async () => {
    BASE = (v) => listo({ filas: v ? [fila(1), vetada(9)] : [fila(1)], conVetados: true })
    montar()
    const estado = screen.getAllByRole('status').find((e) => e.classList.contains('sr-only') && e.textContent === '')
    expect(estado).toBeDefined()
    await userEvent.click(screen.getByRole('button', { name: 'Ver no contactar' }))
    expect(estado).toHaveTextContent('1 lead con «No contactar», al final de la hoja.')
  })

  it('los filtros también recortan el bloque (el analista elegido ve solo sus vetados)', async () => {
    BASE = (v) => listo({ filas: v ? [fila(1), vetada(9), vetada(8, { vendedor_id: BETO, gestiona: 'BETO RÍOS' })] : [fila(1)], conVetados: true })
    montar()
    await userEvent.click(screen.getByRole('button', { name: 'Ver no contactar' }))
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Analista' }), BETO)
    const bloque = screen.getByRole('region', { name: /^No contactar/ })
    expect(within(bloque).getAllByRole('rowheader').map((c) => c.textContent)).toEqual(['LEAD BASE 8'])
  })

  it('si el servidor resulta no tener la B6b, el interruptor se apaga y desaparece', async () => {
    BASE = (v) => listo({ filas: [fila(1)], conVetados: !v })
    montar()
    await userEvent.click(screen.getByRole('button', { name: 'Ver no contactar' }))
    expect(useBaseGestionEquipo).toHaveBeenLastCalledWith(true, false)
  })
})

describe('demo (sin red)', () => {
  it('el supervisor ve el panel de SUS analistas, la hoja con «Gestiona» y algún vetado al encender el interruptor; no sale ni un request', async () => {
    YO = { id: 'd-sup1', rol: 'supervisor', demo: true }
    EQUIPO = [
      { perfil_id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true },
      { perfil_id: 'd-v2', nombre_completo: 'ANALISTA DOS', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true },
      { perfil_id: 'd-v3', nombre_completo: 'ANALISTA TRES', rol_crm: 'vendedor', supervisor_id: 'd-sup2', activo: true },
    ]
    BASE = () => ({ isPending: true, isError: false, isFetching: false, refetch })
    PANEL = { isPending: true, isError: false, isFetching: false, refetch }
    montar()
    expect(useBaseGestionEquipo).toHaveBeenCalledWith(false, false)
    expect(useBaseGestionResumen).toHaveBeenCalledWith(false)
    const renglones = within(panel()).getAllByRole('rowheader').map((c) => c.textContent)
    expect(renglones).toEqual(['ANALISTA DOS', 'ANALISTA UNO'])
    expect(within(hoja()).getAllByRole('columnheader')[2]).toHaveTextContent('Gestiona')
    await userEvent.click(screen.getByRole('button', { name: 'Ver no contactar' }))
    expect(within(screen.getByRole('region', { name: /^No contactar/ })).getAllByRole('rowheader').length).toBeGreaterThanOrEqual(1)
    // El detalle de la demo también se abre.
    await userEvent.click(within(panel()).getAllByRole('button', { name: /intentos de hoy/ })[0]!)
    expect(screen.getByRole('dialog', { name: /Intentos de hoy/ })).toBeInTheDocument()
    expect(useBaseGestionResumenDetalle).toHaveBeenLastCalledWith(false, expect.any(String), 'intentos_hoy')
  })
})
