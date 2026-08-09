// Tests de integración de la pantalla "Repartir leads" (C1): carga de cola +
// supervisores, capital PEN/USD SEPARADO, reparto con salida optimista de la
// fila, y los dos rechazos que importan — el veto legal (NO_INSISTA) y la fila
// que ya salió de la cola (FUERA_DE_COLA) — que además fuerzan una relectura.
// Se mockea la capa de datos (sin red).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ColaLead, SupervisorReparto } from '@/lib/tipos'

const toastSuccess = vi.fn()
const toastError = vi.fn()
vi.mock('sonner', () => ({ toast: { success: toastSuccess, error: toastError } }))

let COLA: ColaLead[] = []
let SUPERVISORES: SupervisorReparto[] = []
const repartirMock = vi.fn<(lead: string, sup: string) => Promise<void>>()
const colaMock = vi.fn(async () => COLA)
const supervisoresMock = vi.fn(async () => SUPERVISORES)

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real (la pantalla hace instanceof)
    leadsPorRepartir: () => colaMock(),
    supervisoresParaReparto: () => supervisoresMock(),
    repartirLead: (lead: string, sup: string) => repartirMock(lead, sup),
  }
})

// F1b tanda 3: los tiles ya NO los cuenta la pantalla, se los sirve el RPC. Se
// mockea el hook de fuente con el ESPEJO PURO sobre la misma cola del test —
// números derivados de verdad, sin red ni QueryClientProvider — y con un
// conmutador para el caso «RPC caído».
let RESUMEN_CAIDO = false
const recargarResumenMock = vi.fn(async () => {})

vi.mock('@/data/use-resumen-reparto-operativo', async () => {
  const { resumenRepartoDesdeCola } = await import('@/lib/resumen-reparto')
  return {
    useResumenRepartoOperativo: () => ({
      resumen: RESUMEN_CAIDO ? null : resumenRepartoDesdeCola(COLA, Date.now()),
      cargando: false,
      error: RESUMEN_CAIDO ? new Error('resumen caído') : null,
      recargar: recargarResumenMock,
    }),
  }
})

const { Repartir } = await import('./repartir')
const { CrmApiError } = await import('@/data/crm-api')

function lead(over: Partial<ColaLead> = {}): ColaLead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    distrito: 'Miraflores',
    origen: 'landing',
    categoria_interes: 'nuevo',
    monto_estimado: 12000,
    moneda: 'PEN',
    creado_en: new Date().toISOString(),
    ...over,
  }
}

const SUP: SupervisorReparto[] = [
  { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 2 },
  { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
]

beforeEach(() => {
  COLA = []
  SUPERVISORES = SUP
  RESUMEN_CAIDO = false
  recargarResumenMock.mockClear()
  repartirMock.mockReset().mockResolvedValue(undefined)
  colaMock.mockClear()
  supervisoresMock.mockClear()
  toastSuccess.mockClear()
  toastError.mockClear()
})

afterEach(() => vi.clearAllMocks())

/** El mini-KPI (Card `.ac-lift` del StatStrip) que lleva esa etiqueta. */
function tile(etiqueta: string): HTMLElement {
  const card = screen.getByText(etiqueta).closest('.ac-lift')
  if (!(card instanceof HTMLElement)) throw new Error(`Sin tile para «${etiqueta}»`)
  return card
}

/**
 * Espera el valor YA ASENTADO de un tile. Los KPIs pasan por `AnimatedValue`,
 * que cuenta de 0 al objetivo durante 700 ms con requestAnimationFrame: el
 * timeout por defecto de findBy* (1 s) se queda corto bajo cobertura y el test
 * ve una cifra intermedia. Aquí solo importa el número final.
 */
async function valorDelTile(etiqueta: string, esperado: string): Promise<void> {
  await waitFor(
    () => expect(tile(etiqueta)).toHaveTextContent(esperado),
    { timeout: 4000 },
  )
}

describe('pantalla Repartir leads', () => {
  it('pinta un vacío honesto cuando no hay nada por repartir', async () => {
    render(<Repartir />)
    expect(await screen.findByText('No hay leads por repartir')).toBeInTheDocument()
  })

  it('NUNCA suma PEN y USD: muestra el capital en juego por separado', async () => {
    COLA = [
      lead({ id: 'l-pen', monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'l-usd', monto_estimado: 30000, moneda: 'USD', nombre_completo: 'JUAN PEREZ' }),
    ]
    render(<Repartir />)

    await screen.findByText('ROSA QUISPE')
    // Cada cifra acotada a SU tile: "S/ 12k" también aparece —con razón— en la
    // fila del lead, y un selector global sería ambiguo, no una falla de UI.
    await valorDelTile('Capital en juego (PEN)', 'S/ 12k')
    await valorDelTile('Capital en juego (USD)', 'US$ 30k')
    // El total mezclado (42k) no debe existir en ninguna moneda.
    expect(screen.queryByText(/42k/)).not.toBeInTheDocument()
  })

  it('los tiles los sirve el resumen del servidor, no el conteo de filas', async () => {
    COLA = [
      lead({ id: 'l-1', monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'l-2', monto_estimado: 30000, moneda: 'USD', nombre_completo: 'JUAN PEREZ' }),
    ]
    render(<Repartir />)

    await screen.findByText('ROSA QUISPE')
    await valorDelTile('Por repartir', '2')
  })

  it('sin cola, la espera más larga se muestra como «—» (no como "hoy")', async () => {
    render(<Repartir />)

    await screen.findByText('No hay leads por repartir')
    expect(within(tile('Espera más larga')).getByText('—')).toBeInTheDocument()
  })

  it('si el resumen del servidor cae: tiles a «—» con aviso, y la cola sigue repartible', async () => {
    RESUMEN_CAIDO = true
    COLA = [lead({ monto_estimado: 12000, moneda: 'PEN' })]
    render(<Repartir />)

    // La lista tiene su propia fuente: no se cae con el resumen.
    await screen.findByText('ROSA QUISPE')
    expect(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' })).toBeInTheDocument()

    // Y ningún tile inventa una cifra: cuatro guiones, ni un "0" ni un "S/ 0".
    for (const etiqueta of ['Por repartir', 'Capital en juego (PEN)', 'Capital en juego (USD)', 'Espera más larga']) {
      expect(within(tile(etiqueta)).getByText('—')).toBeInTheDocument()
    }
    expect(within(tile('Capital en juego (PEN)')).queryByText('S/ 0')).not.toBeInTheDocument()

    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent(/No se pudieron cargar los indicadores de la cola/)
    // Nombre accesible distinguible del OTRO «Reintentar» (el del PanelError).
    const reintentar = within(aviso).getByRole('button', {
      name: 'Reintentar la carga de los indicadores de la cola',
    })
    await userEvent.setup().click(reintentar)
    expect(recargarResumenMock).toHaveBeenCalledTimes(1)
  })

  it('reparte a un supervisor, saca la fila de la cola y sube su bandeja', async () => {
    COLA = [lead()]
    const usuario = userEvent.setup()
    render(<Repartir />)

    await screen.findByText('ROSA QUISPE')
    await usuario.selectOptions(
      screen.getByLabelText('Asignar ROSA QUISPE a un supervisor'),
      'sup-1',
    )
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('lead-1', 'sup-1'))
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('SUPERVISOR UNO'))
    // La fila sale de la cola sin releerla entera.
    await waitFor(() => expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument())
    expect(screen.getByText('No hay leads por repartir')).toBeInTheDocument()
    expect(colaMock).toHaveBeenCalledTimes(1)
  })

  it('el veto legal (No Insista) avisa, NO mueve la fila y relee la cola', async () => {
    COLA = [lead()]
    repartirMock.mockRejectedValue(
      new CrmApiError('Lead marcado No Insista (Ley 29571): no se puede repartir', 'NO_INSISTA'),
    )
    const usuario = userEvent.setup()
    render(<Repartir />)

    await screen.findByText('ROSA QUISPE')
    await usuario.selectOptions(
      screen.getByLabelText('Asignar ROSA QUISPE a un supervisor'),
      'sup-1',
    )
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() =>
      expect(toastError).toHaveBeenCalledWith(
        'Lead marcado No Insista (Ley 29571): no se puede repartir',
      ),
    )
    expect(toastSuccess).not.toHaveBeenCalled()
    // La cola local estaba desfasada respecto del servidor → se relee.
    await waitFor(() => expect(colaMock).toHaveBeenCalledTimes(2))
  })

  it('si el lead ya salió de la cola avisa y resincroniza', async () => {
    COLA = [lead()]
    repartirMock.mockRejectedValue(
      new CrmApiError('El lead ya no está en la cola por repartir', 'FUERA_DE_COLA'),
    )
    const usuario = userEvent.setup()
    render(<Repartir />)

    await screen.findByText('ROSA QUISPE')
    await usuario.selectOptions(
      screen.getByLabelText('Asignar ROSA QUISPE a un supervisor'),
      'sup-2',
    )
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() => expect(toastError).toHaveBeenCalled())
    await waitFor(() => expect(colaMock).toHaveBeenCalledTimes(2))
  })

  it('sin supervisores activos no se puede repartir y lo dice', async () => {
    COLA = [lead()]
    SUPERVISORES = []
    render(<Repartir />)

    expect(await screen.findByText('No hay supervisores activos')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Repartir a / })).not.toBeInTheDocument()
  })

  it('el destino muestra la carga de cada bandeja (para repartir con criterio)', async () => {
    COLA = [lead()]
    render(<Repartir />)

    const select = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(within(select).getByText('SUPERVISOR UNO (2 en bandeja)')).toBeInTheDocument()
    expect(within(select).getByText('SUPERVISOR DOS (0 en bandeja)')).toBeInTheDocument()
  })
})
