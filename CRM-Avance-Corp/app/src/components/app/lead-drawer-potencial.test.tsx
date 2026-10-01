// Ficha del lead · potencial. Los hooks de datos se sustituyen: se prueba qué
// enseña la ficha con la bandera apagada (producción hoy), encendida sin marca
// y con marca, y que la sección va justo después de la etapa.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import type { PotencialLead } from '@/lib/potencial'
import { LeadDrawer } from './lead-drawer'

let POTENCIAL: { habilitada: boolean; item: PotencialLead | undefined } = { habilitada: false, item: undefined }
const marcar = vi.fn()
vi.mock('@/data/potencial-queries', () => ({
  usePotencialLead: () => POTENCIAL,
  useMarcarPotencial: () => ({ marcar, marcando: false }),
}))
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

const VENDEDOR = 'vendedor-1'
const LEAD: Lead = {
  id: 'lead-1', nombre_completo: 'GLORIA NAVARRO', telefono: '+51987654321', correo: null, etapa: 'contactado',
  origen: 'landing', monto_estimado: 65000, moneda: 'PEN', categoria_interes: null, vendedor_id: VENDEDOR, vendedor_nombre: 'ANA TORRES',
  asignado_supervisor_id: null, creado_en: '2026-09-01T12:00:00.000Z', activo: true, dni: '70000021', distrito: null, nota: null,
}
const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
const sesion = { fase: 'listo', yo: { id: VENDEDOR, nombre_completo: 'ANA TORRES', rol: 'vendedor', demo: false, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined,
  salir: async () => undefined } as unknown as AuthContextValue

function montar(lead: Lead = LEAD) {
  const api = {
    lead: (id: string) => (id === lead.id ? lead : undefined), ambito: { leads: [lead], vendedores: [], esGlobal: false },
    actividadesDe: () => [], tareasDe: () => [], crearTarea: vi.fn(), anularTarea: vi.fn(), editarLead: vi.fn(),
    reasignar: vi.fn(), cambiarEtapa: vi.fn(), registrarActividad: vi.fn(), anularCierreAvance: vi.fn(), reabrir: vi.fn(),
    cierresEstado: [], recargar: vi.fn(async () => true),
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
}

function item(sobre: Partial<PotencialLead> = {}): PotencialLead {
  return {
    lead_id: 'lead-1', nivel: null, origen: null, nivel_marcado: null, marcado_en: null,
    dias_sin_gestion: null, baja_a: null, baja_el: null, puede_marcar: true, ...sobre,
  }
}
const ESTRELLA = item({ nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella', marcado_en: '2026-09-29T15:00:00Z', dias_sin_gestion: 1, baja_a: 'tibio', baja_el: null })

beforeEach(() => { marcar.mockClear() })

describe('Ficha del lead · potencial', () => {
  it('ESTADO DE PRODUCCIÓN (potencial apagado): ni sección ni chip', () => {
    POTENCIAL = { habilitada: false, item: undefined }
    montar()
    expect(screen.getByRole('heading', { name: 'GLORIA NAVARRO' })).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Potencial' })).not.toBeInTheDocument()
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
  })

  it('ESTADO DE PRODUCCIÓN (encendido, lead sin marca): la sección dice «Sin marcar» y no hay chip', () => {
    POTENCIAL = { habilitada: true, item: item() }
    montar()
    const seccion = screen.getByRole('region', { name: 'Potencial' })
    expect(within(seccion).getByText('Sin marcar. La cambian el analista del lead y su supervisor.')).toBeInTheDocument()
    expect(within(seccion).getAllByRole('button').map((b) => b.getAttribute('aria-pressed'))).toEqual(['false', 'false', 'false'])
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
  })

  it('con marca: chip en la cabecera, botón pulsado y se puede cambiar', () => {
    POTENCIAL = { habilitada: true, item: ESTRELLA }
    montar()
    // El chip vive en la fila de chips de la cabecera, junto a la etapa.
    const chip = screen.getByTitle('Potencial: Estrella')
    expect(chip.parentElement).toContainElement(screen.getByText('Contactado', { selector: '.ac-chip' }))
    const seccion = screen.getByRole('region', { name: 'Potencial' })
    expect(within(seccion).getByRole('button', { name: 'Estrella' })).toHaveAttribute('aria-pressed', 'true')
    // Abrir la ficha de un lead marcado no anuncia nada: la región viva nace vacía.
    expect(within(seccion).getByRole('status')).toBeEmptyDOMElement()
    fireEvent.click(within(seccion).getByRole('button', { name: 'Tibio' }))
    expect(marcar).toHaveBeenCalledExactlyOnceWith('lead-1', 'tibio')
  })

  it('la sección va justo después de la etapa y antes de los datos', () => {
    POTENCIAL = { habilitada: true, item: item() }
    montar()
    const seccion = screen.getByRole('region', { name: 'Potencial' })
    const etapa = seccion.previousElementSibling
    expect(etapa).not.toBeNull()
    // El bloque anterior es el de la etapa (las pastillas del avance).
    expect(within(etapa as HTMLElement).getByRole('button', { name: /Contactado/ })).toBeInTheDocument()
    const datos = screen.getByRole('heading', { name: 'Datos' })
    expect(seccion.compareDocumentPosition(datos) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })

  it('lead descartado con marca: se ve, pero ya no se cambia', () => {
    POTENCIAL = { habilitada: true, item: ESTRELLA }
    montar({ ...LEAD, etapa: 'descartado', motivo_descarte: 'sin_interes' })
    const seccion = screen.getByRole('region', { name: 'Potencial' })
    expect(within(seccion).queryAllByRole('button')).toHaveLength(0)
    expect(within(seccion).getByText('Lead cerrado: la marca ya no cambia.')).toBeInTheDocument()
    expect(within(seccion).getByTitle('Potencial: Estrella')).toBeInTheDocument()
  })
})
