import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { ProximaAccion } from './lead-drawer'

vi.mock('@/data/use-actividades-de-lead', () => ({ useActividadesDeLead: () => ({ items: [], cargando: false, error: null, senales: {} }) }))
vi.mock('@/data/sla-operacion-queries', () => ({ useEstadosSlaV2: () => ({ data: null, error: null }) }))
const sesion = { yo: { id: 'vendedor', rol: 'vendedor', demo: true } } as AuthContextValue
const lead = { id: 'lead-prueba', nombre_completo: 'PERSONA PRUEBA', vendedor_id: 'vendedor', etapa: 'nuevo' } as Lead

describe('agendar desde la guía', () => {
  it('abre el formulario vigente como cita, mueve el foco y conserva lo ya escrito', async () => {
    Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', { configurable: true, value: vi.fn() })
    const crearTarea = vi.fn()
    const store = { tareasDe: () => [], crearTarea, anularTarea: vi.fn(), obtenerTareaParaRevision: vi.fn() } as unknown as StoreDataApi
    function Pantalla() {
      const [peticion, setPeticion] = useState(0)
      return <AuthContext.Provider value={sesion}><StoreDataContext.Provider value={store}>
        <button type="button" onClick={() => setPeticion((n) => n + 1)}>Agendar desde la guía</button>
        <ProximaAccion l={lead} escribe activa pedirCita={peticion} />
      </StoreDataContext.Provider></AuthContext.Provider>
    }
    render(<Pantalla />)
    const usuario = userEvent.setup()
    await usuario.clear(screen.getByLabelText('Título de la tarea'))
    await usuario.type(screen.getByLabelText('Título de la tarea'), 'Acuerdo ya escrito')
    await usuario.click(screen.getByRole('button', { name: 'Agendar desde la guía' }))
    expect(screen.getByLabelText('Tipo de tarea')).toHaveValue('reunion')
    await waitFor(() => expect(screen.getByLabelText('Tipo de tarea')).toHaveFocus())
    expect(screen.getByLabelText('Título de la tarea')).toHaveValue('Acuerdo ya escrito')
    expect(crearTarea).not.toHaveBeenCalled()
    expect(HTMLElement.prototype.scrollIntoView).toHaveBeenCalled()
  })
})
