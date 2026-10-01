// Reabrir un descarte de alguien que ya es cliente no reabre nada: la ficha muestra quién
// es («Esta persona ya es cliente») y ofrece su venta cruzada, sin tocar el lead. El
// «reabierto» solo se anuncia cuando el servidor lo confirma.
//
// El arnés hace lo mismo que el store real: el reabrir es OPTIMISTA (el lead pasa a «Nuevo»
// y el banner del descarte se desmonta en el mismo clic) y, si el servidor lo rechaza, la
// resincronización lo devuelve a «Descartado». Con un store inmóvil la tarjeta parecía
// funcionar aunque en producción nunca aparecía (revisión a11y, P1).
import { useMemo, useState } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, ResultadoPersistencia, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { LeadDrawer } from './lead-drawer'

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
vi.mock('@/data/documento-lead', () => ({ useDocumentoLead: () => ({ data: undefined, isPending: false, isError: false }) }))
const { buscar } = vi.hoisted(() => ({ buscar: vi.fn() }))
vi.mock('@/data/cliente-existente-api', () => ({ buscarClienteExistente: buscar, obtenerContextoClienteExistente: vi.fn(),
  cuentasClienteExistente: vi.fn(), datosLegalesClienteExistente: vi.fn(), contratosUpgradeClienteExistente: vi.fn() }))
vi.mock('@/data/crm-queries', () => ({
  useHistorialLead: () => ({ data: undefined, dataUpdatedAt: 0, hasNextPage: false, isFetchingNextPage: false,
    isPending: false, error: null, fetchNextPage: vi.fn(), refetch: vi.fn() }),
  usePoliticaRentabilidad: () => ({ data: undefined, isPending: true, isError: false }),
  useSolicitudesTasa: () => ({ data: [], isPending: true, isError: false }),
  useCierresEstado: () => ({ data: [] }),
  useConversionEstado: () => ({ data: undefined, isError: false }),
  useAnularCierreAvance: () => ({ mutateAsync: vi.fn() }),
  useConvertirLeadExterno: () => ({ mutateAsync: vi.fn() }),
  useCuentasBancariasCliente: () => ({ data: [], isPending: false, isError: false, isFetching: false, refetch: vi.fn() }),
}))
vi.mock('@/data/sla-operacion-queries', () => ({ useEstadosSlaV2: () => ({ data: { modo: 'legado', filas: [] }, error: null }) }))

const VENDEDOR = 'vendedor-1'
const LEAD: Lead = {
  id: 'lead-descartado-1', nombre_completo: 'PERSONA DESCARTADA', telefono: '+51987654321', correo: null, etapa: 'descartado',
  origen: 'landing', monto_estimado: 2000, moneda: 'PEN', categoria_interes: null, vendedor_id: VENDEDOR, vendedor_nombre: 'ANALISTA B',
  asignado_supervisor_id: null, creado_en: '2026-09-01T12:00:00.000Z', activo: true, dni: '70000021', distrito: null, nota: null,
  motivo_descarte: 'sin_interes',
}
const RECHAZO = { ok: false, codigo: 'P0409', error: 'La persona ya es cliente o ya tiene su lead: no se puede reabrir' }
const CLIENTE = {
  estado: 'encontrado', busqueda_id: '11111111-1111-4111-8111-111111111111', criterio: 'lead',
  cliente: { inversionista_id: null, nombre: 'VC CLIENTE X', documento_tipo: 'DNI', documento_enmascarado: '•••••021',
    responsable_nombre: 'VC ANALISTA A', empresas: ['avance'], es_mi_cartera: false },
  acciones: { ver_ficha: false, nueva_inversion: false, requiere_documento: true, motivo_codigo: null, motivo_no_operable: null },
}
const reabrirLlamado = vi.fn()
const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
const sesion = { fase: 'listo', yo: { id: VENDEDOR, nombre_completo: 'ANALISTA B', rol: 'vendedor', demo: false, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined,
  salir: async () => undefined } as unknown as AuthContextValue

function Arnes({ persistido }: { persistido: Promise<ResultadoPersistencia> }) {
  const [lead, setLead] = useState<Lead>(LEAD)
  const api = useMemo(() => ({
    lead: (id: string) => (id === lead.id ? lead : undefined), ambito: { leads: [lead], vendedores: [], esGlobal: false },
    actividadesDe: () => [], tareasDe: () => [], crearTarea: vi.fn(), anularTarea: vi.fn(), editarLead: vi.fn(),
    reasignar: vi.fn(), cambiarEtapa: vi.fn(), registrarActividad: vi.fn(), anularCierreAvance: vi.fn(),
    cierresEstado: [], recargar: vi.fn(async () => true),
    reabrir: (id: string) => {
      reabrirLlamado(id)
      setLead((l) => ({ ...l, etapa: 'nuevo', motivo_descarte: null }))
      void persistido.then((r) => {if (!r.ok) setTimeout(() => setLead(LEAD), 0)})
      return { ok: true, persistido }
    },
  }) as unknown as StoreDataApi, [lead, persistido])
  return (
    <AuthContext.Provider value={sesion}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider value={{ leadAbiertoId: LEAD.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}>
          <PanelActionsContext.Provider value={actions}><LeadDrawer /></PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>
  )
}
function montar(persistido: Promise<ResultadoPersistencia>) {
  render(<Arnes persistido={persistido} />)
  return userEvent.setup()
}
beforeEach(() => {vi.clearAllMocks()})

describe('reabrir un descarte que ya es cliente', () => {
  it('muestra quién es y su responsable aunque el reabrir optimista haya desmontado el banner', async () => {
    buscar.mockResolvedValue(CLIENTE)
    const user = montar(Promise.resolve(RECHAZO))
    await user.click(screen.getByRole('button', { name: /Reabrir/ }))
    expect(reabrirLlamado).toHaveBeenCalledWith(LEAD.id)
    const tarjeta = await screen.findByRole('region', { name: 'Esta persona ya es cliente' })
    expect(tarjeta).toHaveTextContent('VC CLIENTE X')
    expect(tarjeta).toHaveTextContent('VC ANALISTA A')
    expect(buscar).toHaveBeenCalledWith({ tipo: 'lead', leadId: LEAD.id })
    expect(toast.success).not.toHaveBeenCalled()
    expect(toast.error).not.toHaveBeenCalled()
    // La resincronización devuelve el lead a «Descartado» (detrás del diálogo, inerte); la tarjeta sigue ahí.
    expect(await screen.findByRole('button', { name: /Reabrir/, hidden: true })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Esta persona ya es cliente' })).toBeInTheDocument()
    // La acción principal de la tarjeta recibe el foco; buscar por documento propone el DNI.
    expect(screen.getByRole('button', { name: 'Buscar por documento' })).toHaveFocus()
    await user.click(screen.getByRole('button', { name: 'Buscar por documento' }))
    expect(screen.getByLabelText('Número')).toHaveValue('70000021')
    // Al cerrar, el foco vuelve a la etapa del lead (el «Reabrir» que la abrió ya no existe).
    await user.click(screen.getByRole('button', { name: 'Cerrar' }))
    await waitFor(() => expect(document.activeElement).toContainElement(screen.getByRole('button', { name: /Reabrir/ })))
  })

  it('si no es cliente (ya tiene otro lead), queda el mensaje del servidor', async () => {
    buscar.mockResolvedValue({ estado: 'no_encontrado', busqueda_id: '11111111-1111-4111-8111-111111111111', criterio: 'lead' })
    const user = montar(Promise.resolve(RECHAZO))
    await user.click(screen.getByRole('button', { name: /Reabrir/ }))
    await waitFor(() => expect(toast.error).toHaveBeenCalledWith(RECHAZO.error))
    expect(screen.queryByRole('region', { name: 'Esta persona ya es cliente' })).not.toBeInTheDocument()
  })

  it('otro rechazo no busca clientes', async () => {
    const user = montar(Promise.resolve({ ok: false, codigo: 'P0429', error: 'La persona tiene la restricción «No insistir»: no se puede reabrir' }))
    await user.click(screen.getByRole('button', { name: /Reabrir/ }))
    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    expect(buscar).not.toHaveBeenCalled()
  })

  it('el «reabierto» se anuncia cuando el servidor lo confirma', async () => {
    const user = montar(Promise.resolve({ ok: true }))
    await user.click(screen.getByRole('button', { name: /Reabrir/ }))
    await waitFor(() => expect(toast.success).toHaveBeenCalledWith('Lead reabierto — vuelve a Nuevo'))
    expect(buscar).not.toHaveBeenCalled()
  })
})
