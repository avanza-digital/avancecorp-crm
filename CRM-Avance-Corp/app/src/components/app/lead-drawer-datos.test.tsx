import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
} from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { LeadDrawer } from './lead-drawer'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

const LEAD: Lead = {
  id: 'lead-capital-1',
  nombre_completo: 'ANA CAPITAL PRUEBA',
  telefono: '+51987654321',
  correo: 'ana@prueba.invalid',
  etapa: 'nuevo',
  origen: 'landing',
  monto_estimado: 5_000,
  moneda: 'PEN',
  categoria_interes: null,
  vendedor_id: 'vendedor-1',
  vendedor_nombre: 'VENDEDOR PRUEBA',
  asignado_supervisor_id: null,
  creado_en: '2026-07-17T12:00:00.000Z',
  activo: true,
  dni: null,
  distrito: null,
  nota: null,
  motivo_descarte: null,
}

const SESION: AuthContextValue = {
  fase: 'listo',
  yo: {
    id: 'vendedor-1',
    nombre_completo: 'VENDEDOR PRUEBA',
    rol: 'vendedor',
    demo: true,
    puede_contratar: true,
  },
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => undefined,
  reintentar: () => undefined,
  salir: async () => undefined,
}

function montar() {
  const editarLead = vi.fn<StoreDataApi['editarLead']>(() => ({ ok: true }))
  const api = {
    lead: (id: string) => (id === LEAD.id ? LEAD : undefined),
    ambito: { leads: [LEAD], vendedores: [], esGlobal: false },
    actividadesDe: () => [],
    tareasDe: () => [],
    crearTarea: vi.fn(() => ({ ok: true, id: 't-test' })),
    editarLead,
    reasignar: vi.fn(() => ({ ok: true })),
    cambiarEtapa: vi.fn(() => ({ ok: true })),
    registrarActividad: vi.fn(() => ({ ok: true })),
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }

  render(
    <AuthContext.Provider value={SESION}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider
          value={{ leadAbiertoId: LEAD.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo' }}
        >
          <PanelActionsContext.Provider value={actions}>
            <LeadDrawer />
          </PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )

  return { editarLead }
}

describe('LeadDrawer — edición de clasificación por capital', () => {
  it('guarda capital y moneda juntos', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    const monto = screen.getByLabelText('Capital estimado *')
    await user.clear(monto)
    await user.type(monto, '25000')
    await user.selectOptions(screen.getByLabelText('Moneda del capital estimado'), 'USD')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(editarLead).toHaveBeenCalledWith(
      LEAD.id,
      expect.objectContaining({ monto_estimado: 25_000, moneda: 'USD' }),
    )
  })

  it('no permite borrar ni guardar en cero el capital', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    const monto = screen.getByLabelText('Capital estimado *')
    await user.clear(monto)
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(screen.getByText('El capital estimado es obligatorio y debe ser mayor que 0')).toBeInTheDocument()
    expect(editarLead).not.toHaveBeenCalled()

    await user.type(monto, '0')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    expect(editarLead).not.toHaveBeenCalled()
  })
})
