import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { registrarAtencionOficina } from '@/data/recorrido-oficina-api'
import { AtenderOficinaDialog } from './cerrar-tarea'

vi.mock('@/data/recorrido-oficina-api', () => ({ registrarAtencionOficina: vi.fn() }))
vi.mock('@/data/use-actividades-de-lead', () => ({ useActividadesDeLead: () => ({ items: [], cargando: false, error: null, senales: {} }) }))
vi.mock('@/lib/use-etapa-visible', () => ({ useEtapaVisible: () => () => ({ label: 'Nuevo', color: '#2456d8' }) }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))

const lead = { id: 'lead-oficina', nombre_completo: 'PERSONA DE PRUEBA', telefono: '999888777',
  etapa: 'nuevo', origen: 'oficina', activo: true, monto_estimado: 5000, moneda: 'PEN', no_contactar: false } as Lead
const sesion: AuthContextValue = { fase: 'listo', yo: { id: 'analista', nombre_completo: 'ANALISTA', rol: 'vendedor', demo: false, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => {}, reintentar: () => {}, salir: async () => {} }

function montar(recarga = true) {
  const cerrar = vi.fn()
  const completar = vi.fn()
  const asegurar = vi.fn().mockResolvedValue(true)
  const recargar = vi.fn().mockResolvedValue(recarga)
  const api = { lead: () => lead, completarTarea: completar, anularTarea: vi.fn(), descartar: vi.fn(),
    tareasDe: () => [], asegurarLead: asegurar, recargar } as unknown as StoreDataApi
  render(<AuthContext.Provider value={sesion}><StoreDataContext.Provider value={api}>
    <AtenderOficinaDialog lead={lead} onCerrar={cerrar} />
  </StoreDataContext.Provider></AuthContext.Provider>)
  return { cerrar, completar, asegurar, recargar }
}

async function completarFormulario(saltar = false) {
  const usuario = userEvent.setup()
  await usuario.click(screen.getByRole('button', { name: 'Asistió y realizamos la entrevista' }))
  await usuario.selectOptions(screen.getByLabelText('Resultado comercial'), 'interesado')
  await usuario.type(screen.getByLabelText('Nota del resultado (opcional)'), 'Entrevista realizada')
  if (saltar) await usuario.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
  return usuario
}

beforeEach(() => vi.clearAllMocks())

describe('atención en oficina con el formulario de cierre vigente', () => {
  it('exige marcar asistencia, conserva el motor y espera confirmación antes de cerrar', async () => {
    let resolver!: () => void
    vi.mocked(registrarAtencionOficina).mockImplementationOnce(() => new Promise<void>((r) => { resolver = r }))
    const { cerrar, completar } = montar()
    expect(screen.getByRole('button', { name: 'Guardar entrevista' })).toBeDisabled()
    expect(screen.queryByText('Ya no hace falta — anular esta tarea')).not.toBeInTheDocument()
    const usuario = await completarFormulario()
    expect(screen.getByText('Siguiente acción propuesta')).toBeVisible()
    const guardar = screen.getByRole('button', { name: 'Guardar entrevista' })
    fireEvent.click(guardar); fireEvent.click(guardar)
    expect(registrarAtencionOficina).toHaveBeenCalledTimes(1)
    expect(registrarAtencionOficina).toHaveBeenCalledWith('analista', lead.id, expect.objectContaining({
      estado: 'completada', resultado_reunion: 'interesado', resultado_detalle: 'Entrevista realizada',
      capital: { monto_estimado: 5000, moneda: 'PEN' }, siguiente: expect.objectContaining({ titulo: expect.any(String) }),
    }))
    expect(completar).not.toHaveBeenCalled()
    expect(cerrar).not.toHaveBeenCalled()
    expect(toast.success).not.toHaveBeenCalled()
    await usuario.keyboard('{Escape}')
    expect(cerrar).not.toHaveBeenCalled()
    await act(async () => resolver())
    await waitFor(() => expect(cerrar).toHaveBeenCalledTimes(1))
    expect(toast.success).toHaveBeenCalledWith('Visita y entrevista registradas. Siguiente acción agendada.')
  })

  it('un error conserva los campos y permite reintentar; Saltar esta vez no crea siguiente', async () => {
    vi.mocked(registrarAtencionOficina).mockRejectedValueOnce(new Error('respuesta perdida')).mockResolvedValueOnce()
    const { cerrar } = montar()
    const usuario = await completarFormulario(true)
    await usuario.click(screen.getByRole('button', { name: 'Guardar entrevista' }))
    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    expect(cerrar).not.toHaveBeenCalled()
    expect(screen.getByLabelText('Nota del resultado (opcional)')).toHaveValue('Entrevista realizada')
    expect(screen.getByLabelText('Resultado comercial')).toHaveValue('interesado')
    await usuario.click(screen.getByRole('button', { name: 'Guardar entrevista' }))
    await waitFor(() => expect(cerrar).toHaveBeenCalledTimes(1))
    expect(registrarAtencionOficina).toHaveBeenLastCalledWith('analista', lead.id, expect.objectContaining({ siguiente: null }))
  })

  it('un fallo de refresco posterior no transforma una visita confirmada en un fallo de guardado', async () => {
    vi.mocked(registrarAtencionOficina).mockResolvedValueOnce()
    const { cerrar } = montar(false)
    const usuario = await completarFormulario(true)
    await usuario.click(screen.getByRole('button', { name: 'Guardar entrevista' }))
    await waitFor(() => expect(cerrar).toHaveBeenCalledTimes(1))
    expect(toast.success).toHaveBeenCalled()
    await waitFor(() => expect(toast.warning).toHaveBeenCalledWith('Visita registrada. Actualiza la ficha para ver los datos más recientes.'))
    expect(toast.error).not.toHaveBeenCalled()
    expect(registrarAtencionOficina).toHaveBeenCalledTimes(1)
  })
})
