// «Nuevo lead» → «Buscar a este cliente» abre la búsqueda de venta cruzada REAL. Su
// formulario vive en un portal, pero React propaga el submit por su árbol: si la búsqueda
// quedaba dentro del <form> del alta, cada «Buscar» también enviaba el alta del lead (errores
// de validación detrás, otro precheck y, degradado, un crearLead). Revisión a11y, P1.
import { act, fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { verificarDisponibilidadLead } from '@/data/crm-api'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import { LeadNuevo } from './lead-nuevo'

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
vi.mock('@/data/crm-api', async (importActual) => ({
  ...await importActual<typeof import('@/data/crm-api')>(),
  verificarDisponibilidadLead: vi.fn(), tomarLeadLibre: vi.fn(), guardarRecordatorioDisponibilidad: vi.fn(),
}))
const { buscar } = vi.hoisted(() => ({ buscar: vi.fn() }))
vi.mock('@/data/cliente-existente-api', () => ({ buscarClienteExistente: buscar }))
vi.mock('./inversion-nueva', () => ({ InversionNueva: () => null }))

const verificarDisponibilidad = vi.mocked(verificarDisponibilidadLead)
const SESION = {
  fase: 'listo', yo: { id: 'vendedor-1', nombre_completo: 'ANALISTA PRUEBA', rol: 'vendedor', demo: false, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined, salir: async () => undefined,
} as unknown as AuthContextValue

function montar() {
  const crearLead = vi.fn<StoreDataApi['crearLead']>(() => ({ ok: true, id: 'lead-nuevo-1', persistido: Promise.resolve({ ok: true }) }))
  const api = { ambito: { leads: [], vendedores: [], esGlobal: false }, crearLead, recargar: vi.fn(async () => true) } as unknown as StoreDataApi
  const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
  render(
    <QueryClientProvider client={new QueryClient()}>
      <AuthContext.Provider value={SESION}>
        <StoreDataContext.Provider value={api}>
          <PanelStateContext.Provider value={{ leadAbiertoId: null, nuevoLeadAbierto: true, etapaInicial: 'nuevo', telefonoInicial: null }}>
            <PanelActionsContext.Provider value={actions}><LeadNuevo /></PanelActionsContext.Provider>
          </PanelStateContext.Provider>
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )
  return { crearLead }
}

beforeEach(() => {
  vi.clearAllMocks()
  verificarDisponibilidad.mockResolvedValue({ estado: 'ya_es_cliente', asesor: 'VC ANALISTA A' })
  buscar.mockResolvedValue({ estado: 'no_encontrado', busqueda_id: '11111111-1111-4111-8111-111111111111', criterio: 'documento' })
})

describe('LeadNuevo — la búsqueda de un cliente no envía el alta del lead', () => {
  it('buscar dentro del diálogo no dispara el submit del formulario de detrás', async () => {
    vi.useFakeTimers()
    const { crearLead } = montar()
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    vi.useRealTimers()
    expect(verificarDisponibilidad).toHaveBeenCalledTimes(1)

    const user = userEvent.setup()
    await user.click(screen.getByRole('button', { name: 'Buscar a este cliente' }))
    // Abre buscando por el teléfono tecleado.
    expect(await screen.findByText(/No encontramos a un cliente/)).toBeInTheDocument()
    expect(buscar).toHaveBeenCalledWith({ tipo: 'telefono', telefono: '987654321' })

    await user.click(screen.getByRole('button', { name: 'Documento' }))
    await user.type(screen.getByLabelText('Número'), '70000021')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(buscar).toHaveBeenLastCalledWith({ tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' })

    // Nada del alta se movió: ni validación, ni otro precheck, ni crearLead.
    expect(screen.queryByText(/El nombre es obligatorio/i)).not.toBeInTheDocument()
    expect(verificarDisponibilidad).toHaveBeenCalledTimes(1)
    expect(crearLead).not.toHaveBeenCalled()
  })
})
