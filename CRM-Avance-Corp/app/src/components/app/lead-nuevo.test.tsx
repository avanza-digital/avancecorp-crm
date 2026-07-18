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
import { validarCamposLead } from '@/lib/validacion'
import { LeadNuevo } from './lead-nuevo'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

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
  const crearLead = vi.fn<StoreDataApi['crearLead']>((input) => {
    const validacion = validarCamposLead({
      monto_estimado: input.monto_estimado,
      moneda: input.moneda,
    })
    return validacion.ok ? { ok: true, id: 'lead-nuevo-1' } : validacion
  })
  const api = {
    ambito: { leads: [], vendedores: [], esGlobal: false },
    crearLead,
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
          value={{ leadAbiertoId: null, nuevoLeadAbierto: true, etapaInicial: 'nuevo' }}
        >
          <PanelActionsContext.Provider value={actions}>
            <LeadNuevo />
          </PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )

  return { crearLead, actions }
}

async function completarBase(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Nombre completo *'), 'ANA NUEVO LEAD')
  await user.type(screen.getByLabelText('Teléfono *'), '987654321')
  await user.selectOptions(screen.getByLabelText('Origen *'), 'landing')
}

describe('LeadNuevo — capital obligatorio', () => {
  it('bloquea capital vacío y cero antes de crear', async () => {
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Ingresa un capital estimado mayor que 0')
    expect(crearLead).not.toHaveBeenCalled()

    await user.type(screen.getByLabelText('Capital estimado *'), '0')
    await user.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(crearLead).not.toHaveBeenCalled()
  })

  it.each(['0.001', '5000.999', '10000000000'])(
    'muestra el rechazo del contrato compartido para %s',
    async (monto) => {
      const user = userEvent.setup()
      const { crearLead } = montar()
      await completarBase(user)
      await user.type(screen.getByLabelText('Capital estimado *'), monto)

      await user.click(screen.getByRole('button', { name: 'Crear lead' }))

      expect(crearLead).toHaveBeenCalledTimes(1)
      expect(screen.getByRole('alert')).toHaveTextContent(/capital estimado/i)
    },
  )

  it('crea en USD conservando monto y moneda', async () => {
    const user = userEvent.setup()
    const { crearLead, actions } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')
    await user.selectOptions(screen.getByLabelText('Moneda'), 'USD')

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ monto_estimado: 5000, moneda: 'USD' }),
    )
    expect(actions.abrirLead).toHaveBeenCalledWith('lead-nuevo-1')
  })
})
