import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { AuthContext, type AuthContextValue } from './auth-context'
import { useCRMData } from './store-context'

vi.stubEnv('VITE_ENABLE_DEMO', 'true')
const { StoreProvider } = await import('./store')

const sesionDemo: AuthContextValue = {
  fase: 'listo',
  yo: {
    id: 'd-v1',
    nombre_completo: 'VENDEDOR UNO',
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

function ResumenDatos() {
  const { leads, equipo, agenda } = useCRMData()
  return <output>{leads.length}/{equipo.length}/{agenda.length}</output>
}

describe('StoreProvider demo', () => {
  beforeEach(() => window.sessionStorage.clear())
  afterAll(() => vi.unstubAllEnvs())

  it('carga los fixtures solo para una sesión demo habilitada', async () => {
    render(
      <AuthContext.Provider value={sesionDemo}>
        <StoreProvider>
          <ResumenDatos />
        </StoreProvider>
      </AuthContext.Provider>,
    )

    await waitFor(() => expect(screen.getByText('20/6/5')).toBeInTheDocument())
  })
})
