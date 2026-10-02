// Recargar la página con el wizard de conversión abierto: la ficha lo reabre sola,
// pero solo cuando ya conoce las condiciones de tasa (el contrato las toma al
// montarse), con el mismo permiso que el botón y solo si la marca de ESTA pestaña
// sigue ahí.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import type { CondicionesTasaLead } from '@/data/crm-api'
import { guardarConversionAbierta, limpiarConversionAbierta } from '@/lib/inversion-solicitud'
import type { EstadoCondicionesLead } from './condiciones-tasa-lead'
import { LeadDrawer } from './lead-drawer'

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
vi.mock('@/data/documento-lead', () => ({ useDocumentoLead: () => ({ data: undefined, isPending: false, isError: false }) }))
vi.mock('@/data/cliente-existente-api', () => ({ buscarClienteExistente: vi.fn(), obtenerContextoClienteExistente: vi.fn(),
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
// Las condiciones de tasa llegan cuando la prueba lo decide y, como en la ficha real,
// sin que nadie toque nada: es una consulta que termina, no un gesto de la persona.
const tasa = vi.hoisted(() => ({ avisar: null as ((estado: EstadoCondicionesLead | null) => void) | null }))
vi.mock('./condiciones-tasa-lead', () => ({
  SolicitudTasaLeadPlegable: ({ onCambio }: { onCambio: (estado: EstadoCondicionesLead | null) => void }) => {
    tasa.avisar = onCambio
    return <p>Condiciones de tasa</p>
  },
}))
vi.mock('./inversion-desde-lead', () => ({
  InversionDesdeLead: ({ onClose, condicionesTasa }: { onClose: () => void; condicionesTasa?: CondicionesTasaLead }) =>
    <div role="dialog" aria-label="Wizard de conversión">
      <span data-testid="tasa-al-abrir">{condicionesTasa?.tasa_anual ?? 'sin condiciones'}</span>
      <button onClick={onClose}>Cerrar el wizard</button>
    </div>,
}))
vi.mock('./inversion-desde-lead-demo', () => ({
  InversionDesdeLeadDemo: () => <div role="dialog" aria-label="Wizard de conversión demo" />,
}))

const VENDEDOR = '11111111-1111-4111-8111-111111111111'
const OTRO = '22222222-2222-4222-8222-222222222222'
const LEAD: Lead = {
  id: '33333333-3333-4333-8333-333333333333', nombre_completo: 'PERSONA EN CONVERSIÓN', telefono: '+51987654321', correo: null,
  etapa: 'propuesta_enviada', origen: 'landing', monto_estimado: 5000, moneda: 'PEN', categoria_interes: null, vendedor_id: VENDEDOR,
  vendedor_nombre: 'ANALISTA A', asignado_supervisor_id: null, creado_en: '2026-09-01T12:00:00.000Z', activo: true, dni: '70000021',
  distrito: null, nota: null, motivo_descarte: null,
}
const PERSONA = '44444444-4444-4444-8444-444444444444'
const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }

function montar({ lead = LEAD, demo = false, puedeContratar = true }: { lead?: Lead; demo?: boolean; puedeContratar?: boolean } = {}) {
  const sesion = { fase: 'listo', yo: { id: VENDEDOR, nombre_completo: 'ANALISTA A', rol: 'vendedor', demo, puede_contratar: puedeContratar },
    error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined,
    salir: async () => undefined } as unknown as AuthContextValue
  const api = {
    lead: (id: string) => (id === lead.id ? lead : undefined), ambito: { leads: [lead], vendedores: [], esGlobal: false },
    actividadesDe: () => [], tareasDe: () => [], crearTarea: vi.fn(), anularTarea: vi.fn(), editarLead: vi.fn(),
    reasignar: vi.fn(), cambiarEtapa: vi.fn(), registrarActividad: vi.fn(), anularCierreAvance: vi.fn(),
    cierresEstado: [], recargar: vi.fn(async () => true), reabrir: vi.fn(),
  } as unknown as StoreDataApi
  render(
    <AuthContext.Provider value={sesion}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider value={{ leadAbiertoId: lead.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}>
          <PanelActionsContext.Provider value={actions}><LeadDrawer /></PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )
  return userEvent.setup()
}
const wizard = () => screen.queryByRole('dialog', { name: 'Wizard de conversión' })
const lleganLasCondiciones = () => act(() => {
  tasa.avisar?.({ condiciones: { tasa_anual: 18 }, bloqueo: null } as EstadoCondicionesLead)
})
beforeEach(() => { vi.clearAllMocks(); sessionStorage.clear(); tasa.avisar = null })

describe('la ficha retoma el wizard de conversión tras recargar', () => {
  it('lo reabre sola en cuanto conoce las condiciones de tasa, no antes, y se las entrega al abrir', async () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar()
    expect(wizard()).not.toBeInTheDocument()
    await lleganLasCondiciones()
    expect(wizard()).toBeInTheDocument()
    expect(screen.getByTestId('tasa-al-abrir')).toHaveTextContent('18')
  })

  it('sin wizard abierto antes de recargar, la ficha no abre nada', async () => {
    montar()
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
  })

  it('el wizard de otra cuenta o de otro lead no se abre en esta ficha', async () => {
    guardarConversionAbierta(OTRO, LEAD.id, PERSONA)
    guardarConversionAbierta(VENDEDOR, OTRO, PERSONA)
    montar()
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
  })

  it('si la marca desaparece mientras llegan las condiciones, no reaparece', async () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar()
    limpiarConversionAbierta(VENDEDOR, LEAD.id)
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
  })

  it('cerrado a mano no se reabre cuando las condiciones vuelven a cambiar', async () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    const user = montar()
    await lleganLasCondiciones()
    await user.click(screen.getByRole('button', { name: 'Cerrar el wizard' }))
    expect(wizard()).not.toBeInTheDocument()
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
  })

  it.each([['una tecla', (user: ReturnType<typeof userEvent.setup>) => user.keyboard('a')],
    ['un clic', (user: ReturnType<typeof userEvent.setup>) => user.click(screen.getByText('Condiciones de tasa'))],
  ] as const)('si la persona ya está usando la ficha (%s), el wizard no aparece solo; el botón lo retoma', async (_gesto, gesto) => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    const user = montar()
    await gesto(user)
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Convertir a cliente/ }))
    expect(wizard()).toBeInTheDocument()
  })

  it('un lead ya convertido no espera condiciones: no las tiene', () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar({ lead: { ...LEAD, etapa: 'convertido' } })
    expect(wizard()).toBeInTheDocument()
  })

  it('quien ya no puede contratar no ve reabrirse el wizard aunque lleguen las condiciones', async () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar({ puedeContratar: false })
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Convertir a cliente/ })).not.toBeInTheDocument()
  })

  it('un lead que pasó a otro analista no reabre el wizard del anterior', async () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar({ lead: { ...LEAD, vendedor_id: OTRO, vendedor_nombre: 'ANALISTA B' } })
    await lleganLasCondiciones()
    expect(wizard()).not.toBeInTheDocument()
  })

  it('un lead descartado no reabre nada', () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar({ lead: { ...LEAD, etapa: 'descartado', motivo_descarte: 'sin_interes' } })
    expect(wizard()).not.toBeInTheDocument()
  })

  it('el modo demo nunca retoma un wizard real', () => {
    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
    montar({ demo: true, lead: { ...LEAD, etapa: 'convertido' } })
    expect(screen.queryByRole('dialog', { name: /Wizard de conversión/ })).not.toBeInTheDocument()
  })
})
