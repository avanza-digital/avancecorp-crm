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
  repartirMock.mockReset().mockResolvedValue(undefined)
  colaMock.mockClear()
  supervisoresMock.mockClear()
  toastSuccess.mockClear()
  toastError.mockClear()
})

afterEach(() => vi.clearAllMocks())

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
    expect(screen.getByText('Capital en juego (PEN)')).toBeInTheDocument()
    expect(screen.getByText('Capital en juego (USD)')).toBeInTheDocument()
    expect(screen.getByText('S/ 12k')).toBeInTheDocument()
    expect(screen.getByText('US$ 30k')).toBeInTheDocument()
    // El total mezclado (42k) no debe existir en ninguna moneda.
    expect(screen.queryByText(/42k/)).not.toBeInTheDocument()
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
