// Pestaña «Bases» (F5). Primero el ESTADO DE PRODUCCIÓN (gate de realidad): sin la B10 el servidor no conoce
// `seguimiento_bases` → «Bases: disponible pronto» (nada más); con la B10 y sin bases → la hoja vacía con «Cargar base».
// Después: la hoja (todo número se abre), el reparto por cantidades y por selección (B9, o «disponible pronto»), el
// seguimiento con «Recoger», la carga de un CSV de punta a punta (vista previa → lotes → informe, con corte de red y
// reintento con el MISMO id) y «Armar desde el CRM».
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import type { FilaSeguimientoBase, FilaSeguimientoBases } from '@/lib/bases-cargadas'
import type { Miembro } from '@/lib/tipos'

const { fuente, toastSuccess, toastInfo, descargarCsv } = vi.hoisted(() => ({
  fuente: {
    seguimientoBases: vi.fn(), seguimientoBase: vi.fn(), seguimientoBaseDetalle: vi.fn(), contactosDeBase: vi.fn(),
    crearBase: vi.fn(), cargarBaseLote: vi.fn(), armarBaseCrm: vi.fn(), repartirBase: vi.fn(), recogerDeBase: vi.fn(),
  },
  toastSuccess: vi.fn(),
  toastInfo: vi.fn(),
  descargarCsv: vi.fn(() => true),
}))
let YO: { id: string; rol: string; demo: boolean; nombre_completo: string } | null = null
let EQUIPO: Miembro[] = []
let EQUIPO_BASE: FilaBaseGestion[] = []

vi.mock('sonner', () => ({ toast: { success: toastSuccess, info: toastInfo, error: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ leads: [], equipo: EQUIPO }) }))
vi.mock('@/data/bases-cargadas-fuente', () => ({ FUENTE_REAL: fuente }))
vi.mock('@/lib/exportar-csv', async (original) => ({ ...(await original<typeof import('@/lib/exportar-csv')>()), descargarCsv }))
vi.mock('@/data/crm-queries', async (original) => ({
  ...(await original<typeof import('@/data/crm-queries')>()),
  useBaseGestionEquipo: () => ({ data: { filas: EQUIPO_BASE, conVetados: true }, isPending: false, isError: false, isFetching: false, refetch: vi.fn() }),
}))

const { ErrorBases } = await import('@/data/bases-cargadas-api')
const { BasesSupervision } = await import('./bases')

const SUP = 'sup-1'
const ANA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const LUIS = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const BASE = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const miembro = (perfil_id: string, nombre_completo: string, rol_crm: Miembro['rol_crm'] = 'vendedor', supervisor_id: string | null = SUP): Miembro => ({ perfil_id, nombre_completo, rol_crm, supervisor_id, activo: true })

const filaBase = (sobre: Partial<FilaSeguimientoBases> = {}): FilaSeguimientoBases => ({
  base_id: BASE, nombre: 'Feria 2025', origen: 'archivo', supervisor_id: SUP, supervisor_nombre: 'SUPERVISOR UNO', creado_en: '2026-10-01T15:00:00Z',
  total: 155, sin_repartir: 85, repartidos: 70, sin_tocar: 22, trabajados: 40, en_descanso: 3, citas: 4, reactivados: 1, avance: 0.57, ...sobre,
})
const filaAnalista = (sobre: Partial<FilaSeguimientoBase> = {}): FilaSeguimientoBase => ({
  analista_id: ANA, analista_nombre: 'ANA PÉREZ', asignados: 40, sin_tocar: 12, sin_tocar_3_dias: 5, trabajados: 28, en_descanso: 2, citas: 3,
  reactivados: 1, ultimo_intento_en: '2026-10-03T15:00:00Z', movidos_otra_via: 1, ...sobre,
})

const onBase = vi.fn()
function montar(base: string | null = null) {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return render(<QueryClientProvider client={cliente}><BasesSupervision base={base} onBase={onBase} /></QueryClientProvider>)
}

beforeEach(() => {
  YO = { id: SUP, rol: 'supervisor', demo: false, nombre_completo: 'SUPERVISOR UNO' }
  EQUIPO = [miembro(ANA, 'ANA PÉREZ'), miembro(LUIS, 'LUIS RÍOS'), miembro(SUP, 'SUPERVISOR UNO', 'supervisor', null)]
  EQUIPO_BASE = []
  fuente.seguimientoBases.mockResolvedValue([filaBase()])
  fuente.seguimientoBase.mockResolvedValue([filaAnalista(), filaAnalista({ analista_id: LUIS, analista_nombre: 'LUIS RÍOS', asignados: 30, sin_tocar: 10, sin_tocar_3_dias: 0, trabajados: 12 })])
  fuente.seguimientoBaseDetalle.mockResolvedValue([{ lead_id: 'l1', nombre_completo: 'ROSA QUISPE', estado: 'sin_tocar', asignado_en: '2026-09-29T15:00:00Z', ultimo_intento_en: null, ultimo_resultado: null }])
  fuente.contactosDeBase.mockResolvedValue([
    { lead_id: 'c1', nombre_completo: 'CARLOS UNO', telefono: '+51987000001', distrito: 'Surco', agregado_en: '2026-10-01T15:00:00Z', analista_id: null, analista_nombre: null, estado: 'sin_repartir' },
    { lead_id: 'c2', nombre_completo: 'CARLOS DOS', telefono: '+51987000002', distrito: null, agregado_en: '2026-10-01T15:00:00Z', analista_id: null, analista_nombre: null, estado: 'sin_repartir' },
  ])
  fuente.repartirBase.mockResolvedValue({ repartidos: 70, por_analista: [{ analista_id: ANA, cantidad: 35 }, { analista_id: LUIS, cantidad: 35 }], omitidos: [] })
  fuente.recogerDeBase.mockResolvedValue({ recogidos: 12, omitidos: 28 })
  fuente.crearBase.mockResolvedValue({ ok: true, base_id: BASE, supervisor_id: SUP })
  fuente.cargarBaseLote.mockImplementation(async ({ filas }: { filas: { fila: number; telefono: string }[] }) => ({
    ok: true, base_id: BASE, lote: { cargadas: 0, ya_existian: 0, no_contactar: 0, invalidas: 0, repetidas: 0 }, base: { filas_recibidas: 0, cargadas: 0 },
    filas: filas.map((f) => (f.telefono.endsWith('7') ? { fila: f.fila, veredicto: 'ya_existia', motivo: 'con_dueno', lead_id: null } : { fila: f.fila, veredicto: 'cargada', motivo: null, lead_id: null })),
  }))
})
afterEach(() => { vi.clearAllMocks() })

describe('ESTADO DE PRODUCCIÓN (gate de realidad)', () => {
  it('sin la B10 (PGRST202 → null): «Bases: disponible pronto», sin «Cargar base» ni hoja', async () => {
    fuente.seguimientoBases.mockResolvedValue(null)
    montar()
    expect(await screen.findByText('Bases: disponible pronto')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Cargar base' })).toBeNull()
    expect(screen.queryByRole('region', { name: 'Bases cargadas' })).toBeNull()
  })

  it('con la B10 y ninguna base: lo dice y ofrece «Cargar base»', async () => {
    fuente.seguimientoBases.mockResolvedValue([])
    montar()
    expect(await screen.findByText('Todavía no hay bases')).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Cargar base' })).toHaveLength(2)
  })

  it('si la lectura falla, se dice y se puede reintentar (aria-disabled mientras reintenta)', async () => {
    fuente.seguimientoBases.mockRejectedValueOnce(new ErrorBases('boom', 'POSTGREST_ERROR')).mockResolvedValueOnce([filaBase()])
    montar()
    await userEvent.click(await screen.findByRole('button', { name: /Reintentar/ }))
    expect(await screen.findByRole('region', { name: 'Bases cargadas' })).toBeInTheDocument()
  })
})

describe('la hoja de bases', () => {
  it('una fila por base con su avance; cada número abre su lista; las pastillas filtran la hoja', async () => {
    fuente.seguimientoBases.mockResolvedValue([filaBase(), filaBase({ base_id: 'otra', nombre: 'Julio', origen: 'crm', sin_repartir: 0, sin_tocar: 0, avance: null })])
    montar()
    const hoja = await screen.findByRole('region', { name: 'Bases cargadas' })
    expect(within(hoja).getAllByRole('rowheader').map((c) => c.textContent)).toEqual(['Feria 2025', 'Julio'])
    expect(within(hoja).getByText('57 %')).toBeInTheDocument()
    expect(within(hoja).getByText('Desde el CRM')).toBeInTheDocument()
    await userEvent.click(within(hoja).getByRole('button', { name: /Feria 2025, sin repartir:\s?85/ }))
    const detalle = await screen.findByRole('dialog', { name: /Sin repartir · 85/ })
    expect(await within(detalle).findByText('ROSA QUISPE')).toBeInTheDocument()
    expect(fuente.seguimientoBaseDetalle).toHaveBeenCalledWith(BASE, null, 'sin_repartir', expect.anything())
    await userEvent.keyboard('{Escape}')
    await userEvent.click(screen.getByRole('button', { name: /Sin repartir:\s?85/ }))
    expect(within(hoja).getAllByRole('rowheader').map((c) => c.textContent)).toEqual(['Feria 2025'])
  })

  it('el nombre abre la base (la URL la lleva); una base de la URL que ya no está vuelve a la hoja con un aviso', async () => {
    montar()
    await userEvent.click(await screen.findByRole('button', { name: 'Feria 2025' }))
    expect(onBase).toHaveBeenCalledWith(BASE)
    onBase.mockClear()
    fuente.seguimientoBases.mockResolvedValue([])
    montar('dddddddd-dddd-4ddd-8ddd-dddddddddddd')
    await waitFor(() => expect(onBase).toHaveBeenCalledWith(null))
    expect(toastInfo).toHaveBeenCalledWith('Esa base ya no está entre tus bases.')
  })
})

describe('dentro de una base: repartir', () => {
  it('por cantidades: el contador «x de 85 por repartir», «En partes iguales», pasarse no envía y repartir manda el bloque', async () => {
    montar(BASE)
    expect(await screen.findByRole('heading', { level: 2, name: 'Feria 2025' })).toHaveFocus()
    expect(screen.getByText('0 de 85 por repartir')).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('ANA PÉREZ'), '90')
    expect(screen.getByText(/90 de 85 por repartir · te pasas por 5/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: /^Repartir 90/ }))
    expect(screen.getByRole('alert')).toHaveTextContent('Te pasas por 5')
    expect(fuente.repartirBase).not.toHaveBeenCalled()
    await userEvent.clear(screen.getByLabelText('ANA PÉREZ'))
    await userEvent.click(screen.getByRole('button', { name: /En partes iguales/ }))
    expect(screen.getByLabelText('ANA PÉREZ')).toHaveValue('43')
    expect(screen.getByLabelText('LUIS RÍOS')).toHaveValue('42')
    expect(screen.getByText('85 de 85 por repartir')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: /^Repartir 85/ }))
    await waitFor(() => expect(fuente.repartirBase).toHaveBeenCalledTimes(1))
    expect(fuente.repartirBase.mock.calls[0]?.[0]).toEqual({
      operacionId: expect.any(String), baseId: BASE,
      reparto: { modo: 'bloque', asignaciones: [{ analista_id: ANA, cantidad: 43 }, { analista_id: LUIS, cantidad: 42 }] },
    })
    expect(toastSuccess).toHaveBeenCalledWith('Repartidos 70: ANA PÉREZ 35 · LUIS RÍOS 35.')
  })

  it('si no alcanzan, el servidor no reparte ninguno y se dice cuántos hay; el MISMO pedido reusa su id', async () => {
    fuente.repartirBase.mockRejectedValue(new ErrorBases('No alcanzan: hay 60 contactos disponibles para repartir', 'SIN_DISPONIBLES', 60))
    montar(BASE)
    await userEvent.type(await screen.findByLabelText('ANA PÉREZ'), '70')
    await userEvent.click(screen.getByRole('button', { name: /^Repartir 70/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('hay 60 contactos disponibles')
    await userEvent.click(screen.getByRole('button', { name: /^Repartir 70/ }))
    await waitFor(() => expect(fuente.repartirBase).toHaveBeenCalledTimes(2))
    const [a, b] = fuente.repartirBase.mock.calls.map(([e]) => (e as { operacionId: string }).operacionId)
    expect(a).toBe(b)
  })

  it('antes de la B9: al repartir dice «disponible pronto»; por selección también', async () => {
    fuente.repartirBase.mockRejectedValue(new ErrorBases('disponible pronto', 'NO_DISPONIBLE'))
    fuente.contactosDeBase.mockResolvedValue(null)
    montar(BASE)
    await userEvent.type(await screen.findByLabelText('ANA PÉREZ'), '10')
    await userEvent.click(screen.getByRole('button', { name: /^Repartir 10/ }))
    expect(await screen.findByText('Repartir: disponible pronto')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('tab', { name: 'Por selección' }))
    expect(await screen.findByText('Repartir: disponible pronto')).toBeInTheDocument()
  })

  it('por selección: se marcan contactos y «Asignar a…» manda el reparto individual', async () => {
    montar(BASE)
    await userEvent.click(await screen.findByRole('tab', { name: 'Por selección' }))
    await userEvent.click(await screen.findByRole('checkbox', { name: 'Elegir a CARLOS DOS' }))
    await userEvent.selectOptions(screen.getByLabelText('Asignar a…'), LUIS)
    await userEvent.click(screen.getByRole('button', { name: /^Asignar 1/ }))
    await waitFor(() => expect(fuente.repartirBase).toHaveBeenCalled())
    expect(fuente.repartirBase.mock.calls[0]?.[0]).toMatchObject({ reparto: { modo: 'individual', asignaciones: [{ lead_id: 'c2', analista_id: LUIS }] } })
    expect(fuente.contactosDeBase).toHaveBeenCalledWith(BASE, 'sin_repartir', expect.anything())
    await userEvent.click(screen.getByRole('checkbox', { name: /Ver también los repartidos/ }))
    await waitFor(() => expect(fuente.contactosDeBase).toHaveBeenCalledWith(BASE, 'todos', expect.anything()))
  })
})

describe('dentro de una base: seguimiento por analista', () => {
  it('«sin tocar 3 días» en rojo y se abre; «Recoger» confirma y devuelve lo no tocado', async () => {
    montar(BASE)
    const region = await screen.findByRole('region', { name: 'Seguimiento de Feria 2025 por analista' })
    const ana = within(region).getByRole('rowheader', { name: 'ANA PÉREZ' }).closest('tr') as HTMLElement
    const rojo = within(ana).getByRole('button', { name: /ANA PÉREZ, sin tocar 3 días:\s?5/ })
    expect(rojo).toHaveClass('text-[var(--destructive-text)]')
    await userEvent.click(rojo)
    await screen.findByRole('dialog', { name: /Sin tocar 3 días · 5/ })
    expect(fuente.seguimientoBaseDetalle).toHaveBeenCalledWith(BASE, ANA, 'sin_tocar_3_dias', expect.anything())
    await userEvent.keyboard('{Escape}')
    await userEvent.click(within(ana).getByRole('button', { name: 'Recoger lo que ANA PÉREZ no tocó' }))
    const dialogo = await screen.findByRole('dialog', { name: '¿Recoger lo que ANA PÉREZ no tocó?' })
    await userEvent.click(within(dialogo).getByRole('button', { name: /Recoger/ }))
    await waitFor(() => expect(fuente.recogerDeBase).toHaveBeenCalledWith({ operacionId: expect.any(String), baseId: BASE, analistaId: ANA }))
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('Recogidos 12'))
  })

  it('aún sin repartir: lo dice (no una tabla vacía)', async () => {
    fuente.seguimientoBase.mockResolvedValue([])
    montar(BASE)
    expect(await screen.findByText(/Aún no repartiste esta base/)).toBeInTheDocument()
  })
})

const CSV = [
  'Nombres y apellidos;Celular;DNI;Monto',
  'ROSA QUISPE;987654321;45871236;30000',
  'LUIS RÍOS;987000117;;',
  'SIN TELÉFONO;123;;',
  'ROSA OTRA VEZ;987 654 321;;',
].join('\n')

async function abrirCarga() {
  montar()
  await userEvent.click(await screen.findByRole('button', { name: 'Cargar base' }))
  return screen.findByRole('dialog', { name: 'Cargar base' })
}

describe('cargar un archivo', () => {
  it('CSV → vista previa (se enviarán, inválidas, repetidas) → crear + lotes → informe por veredicto → descargar', async () => {
    const hoja = await abrirCarga()
    await userEvent.upload(within(hoja).getByLabelText('Elegir el archivo'), new File([CSV], 'Feria 2025.csv', { type: 'text/csv' }))
    expect(await within(hoja).findByText(/Feria 2025\.csv · 4 filas con datos/)).toBeInTheDocument()
    expect(within(hoja).getByLabelText(/Nombre.*obligatorio/)).toHaveDisplayValue('A · Nombres y apellidos')
    expect(within(hoja).getByRole('button', { name: /Se enviarán:\s?2/ })).toBeInTheDocument()
    expect(within(hoja).getByRole('button', { name: /Inválidas:\s?1/ })).toBeInTheDocument()
    expect(within(hoja).getByRole('button', { name: /Repetidas en el archivo:\s?1/ })).toBeInTheDocument()
    expect(within(hoja).getByText('El teléfono no es un celular peruano válido')).toBeInTheDocument()
    expect(within(hoja).getByLabelText('Nombre de la base')).toHaveValue('Feria 2025')
    await userEvent.click(within(hoja).getByRole('button', { name: /Cargar 2 contactos/ }))
    expect(await within(hoja).findByRole('heading', { name: /Informe de «Feria 2025»/ })).toBeInTheDocument()
    expect(fuente.crearBase).toHaveBeenCalledWith({ operacionId: expect.any(String), nombre: 'Feria 2025', supervisorId: null, archivoNombre: 'Feria 2025.csv' })
    expect(fuente.cargarBaseLote).toHaveBeenCalledWith({
      operacionId: expect.any(String), baseId: BASE,
      filas: [{ fila: 2, nombre: 'ROSA QUISPE', telefono: '+51987654321', dni: '45871236', capital: '30000' }, { fila: 3, nombre: 'LUIS RÍOS', telefono: '+51987000117' }],
    })
    const informe = within(hoja).getByRole('group', { name: 'Resultado por tipo' })
    expect(within(informe).getByRole('button', { name: /Cargadas:\s?1/ })).toBeInTheDocument()
    expect(within(informe).getByRole('button', { name: /Ya existían:\s?1/ })).toBeInTheDocument()
    expect(within(informe).getByRole('button', { name: /Inválidas:\s?1/ })).toBeInTheDocument()
    expect(within(informe).getByRole('button', { name: /Repetidas:\s?1/ })).toBeInTheDocument()
    await userEvent.click(within(hoja).getByRole('button', { name: /Descargar informe/ }))
    expect(descargarCsv).toHaveBeenCalledWith('informe-feria-2025.csv', expect.stringContaining('"3","Ya existía","Ya es lead de un analista"'))
    await userEvent.click(within(hoja).getByRole('button', { name: 'Ver la base y repartir' }))
    expect(onBase).toHaveBeenCalledWith(BASE)
  })

  it('la red se corta en un lote: se pausa, «Reintentar» repite ESE lote con el MISMO id y termina', async () => {
    fuente.cargarBaseLote.mockRejectedValueOnce(new ErrorBases('Se cortó la conexión. Revisa tu internet y vuelve a intentarlo.', 'RED'))
    const hoja = await abrirCarga()
    await userEvent.upload(within(hoja).getByLabelText('Elegir el archivo'), new File([CSV], 'feria.csv'))
    await userEvent.click(await within(hoja).findByRole('button', { name: /Cargar 2 contactos/ }))
    expect(await within(hoja).findByRole('alert')).toHaveTextContent('Se cortó la conexión')
    await userEvent.click(within(hoja).getByRole('button', { name: 'Reintentar' }))
    expect(await within(hoja).findByRole('heading', { name: /Informe de/ })).toBeInTheDocument()
    const ids = fuente.cargarBaseLote.mock.calls.map(([e]) => (e as { operacionId: string }).operacionId)
    expect(ids).toHaveLength(2)
    expect(ids[0]).toBe(ids[1])
    expect(fuente.crearBase).toHaveBeenCalledTimes(1)
  })

  it('Gerencia debe elegir el supervisor dueño; un nombre repetido vuelve al formulario con el error en el nombre', async () => {
    YO = { id: 'ger-1', rol: 'gerencia', demo: false, nombre_completo: 'GERENTE' }
    fuente.crearBase.mockRejectedValueOnce(new ErrorBases('Ya hay una base viva con ese nombre en la bandeja de ese supervisor', 'NOMBRE_REPETIDO'))
    const hoja = await abrirCarga()
    await userEvent.upload(within(hoja).getByLabelText('Elegir el archivo'), new File([CSV], 'feria.csv'))
    await userEvent.click(await within(hoja).findByRole('button', { name: /Cargar 2 contactos/ }))
    expect(within(hoja).getByLabelText('Supervisor dueño')).toHaveAccessibleDescription(/Elige el supervisor dueño/)
    expect(fuente.crearBase).not.toHaveBeenCalled()
    await userEvent.selectOptions(within(hoja).getByLabelText('Supervisor dueño'), SUP)
    await userEvent.click(within(hoja).getByRole('button', { name: /Cargar 2 contactos/ }))
    expect(await within(hoja).findByLabelText('Nombre de la base')).toHaveAccessibleDescription(/Ya hay una base viva con ese nombre/)
    expect(fuente.crearBase).toHaveBeenCalledWith(expect.objectContaining({ supervisorId: SUP }))
    expect(fuente.cargarBaseLote).not.toHaveBeenCalled()
  })

  it('un archivo que no sirve se dice (sin romper nada)', async () => {
    const hoja = await abrirCarga()
    await userEvent.upload(within(hoja).getByLabelText('Elegir el archivo'), new File(['x'], 'viejo.xls'), { applyAccept: false })
    expect(await within(hoja).findByRole('alert')).toHaveTextContent('Elige un archivo .xlsx o .csv')
  })
})

describe('armar desde el CRM', () => {
  const descartado = (n: number, sobre: Partial<FilaBaseGestion> = {}): FilaBaseGestion => ({
    lead_id: `lead-${n}`, nombre_completo: `DESCARTADO ${n}`, telefono: '+51987654321', distrito: null, origen: 'landing', categoria_interes: null,
    monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde', descartado_en: '2026-07-10T15:00:00Z', dias_desde_descarte: 80,
    etapa_maxima: 'contactado', intentos: 1, ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-07-11T15:00:00Z', proxima_llamada_en: null,
    rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: ANA, gestiona: 'ANA PÉREZ', recibido_en: '2026-07-01T15:00:00Z', ...sobre,
  })

  it('lo que tiene seguimiento activo sale en gris y no se envía; arma con el resto y dice quiénes quedaron fuera', async () => {
    EQUIPO_BASE = [
      descartado(1),
      descartado(2, { ultimo_intento_en: new Date(Date.now() - 86_400_000).toISOString() }),
      descartado(3, { base_id: 'otra', base_nombre: 'Otra' }),
      descartado(4, { no_contactar: true }),
      descartado(5, { vendedor_id: LUIS, gestiona: 'LUIS RÍOS' }),
    ]
    fuente.armarBaseCrm.mockResolvedValue({ ok: true, base_id: 'nueva', recibidos: 2, incluidos: 1, excluidos: 1, excluidos_por_motivo: { ocupado: [2] }, excluidos_detalle: [] })
    const hoja = await abrirCarga()
    await userEvent.click(within(hoja).getByRole('tab', { name: 'Armar desde el CRM' }))
    expect(within(hoja).getByText('Entrarían').closest('p')).toHaveTextContent(/Entrarían:?\s?2/)
    expect(within(hoja).getByText(/En gestión por ANA PÉREZ hasta el/)).toBeInTheDocument()
    expect(within(hoja).queryByText('DESCARTADO 3')).toBeNull()
    expect(within(hoja).queryByText('DESCARTADO 4')).toBeNull()
    await userEvent.type(within(hoja).getByLabelText('Nombre de la base'), 'Descartes de julio')
    await userEvent.click(within(hoja).getByRole('button', { name: /Armar base con 2 leads/ }))
    expect(await within(hoja).findByRole('heading', { name: 'Base «Descartes de julio» armada' })).toBeInTheDocument()
    expect(fuente.armarBaseCrm).toHaveBeenCalledWith({ operacionId: expect.any(String), nombre: 'Descartes de julio', supervisorId: null, leadIds: ['lead-1', 'lead-5'] })
    expect(within(hoja).getByText('Otro proceso lo tenía tomado: reintenta')).toBeInTheDocument()
  })

  it('ningún elegible según el servidor: no se crea nada y se dicen los motivos', async () => {
    EQUIPO_BASE = [descartado(1)]
    fuente.armarBaseCrm.mockRejectedValue(new ErrorBases('Ningún lead de la lista es elegible: no se creó la base.', 'SIN_ELEGIBLES', { en_otra_base: [1] }))
    const hoja = await abrirCarga()
    await userEvent.click(within(hoja).getByRole('tab', { name: 'Armar desde el CRM' }))
    await userEvent.type(within(hoja).getByLabelText('Nombre de la base'), 'Julio')
    await userEvent.click(within(hoja).getByRole('button', { name: /Armar base con 1 lead/ }))
    const alerta = await within(hoja).findByRole('alert')
    expect(alerta).toHaveTextContent('Ningún lead de la lista es elegible')
    expect(alerta).toHaveTextContent('Ya está en otra base')
  })
})
