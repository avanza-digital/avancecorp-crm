const auth = vi.hoisted(() => ({demo: true}))
vi.mock('@/lib/auth-context', () => ({useAuth: () => ({yo: {id: '11111111-1111-4111-8111-111111111111', demo: auth.demo}})}))
vi.mock('@/data/postventa-api', () => ({personaDePerfil: vi.fn()}))
vi.mock('@/data/postventa-envios', () => ({ejecutarEnvioPostventa: vi.fn()}))
vi.mock('@/data/postventa-queries', () => ({refrescarPostventa: vi.fn().mockResolvedValue(undefined)}))
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { toast } from 'sonner'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import { Dialog } from '@/components/ui/dialog'
import { ClienteGestion } from './cliente-gestion'
import { personaDePerfil } from '@/data/postventa-api'
import { ejecutarEnvioPostventa } from '@/data/postventa-envios'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/lib/ahora', () => ({
  useAhora: () => Date.parse('2026-08-25T15:00:00.000Z'),
}))

function diferida<T>() {
  let resolver!: (valor: T) => void
  const promesa = new Promise<T>((res) => {
    resolver = res
  })
  return { promesa, resolver }
}

function montar(resultado: ReturnType<StoreDataApi['crearTarea']>) {
  const crearTarea = vi.fn<StoreDataApi['crearTarea']>(() => resultado)
  const onCerrar = vi.fn()
  const onEnviandoCambio = vi.fn()
  const api = {
    crearTarea,
    tareasDeCliente: () => [],
    tareas: [],
    recargar: vi.fn().mockResolvedValue(true),
  } as unknown as StoreDataApi

  render(
    <StoreDataContext.Provider value={api}>
      <Dialog open onClose={onCerrar} ariaLabel="Gestionar a ROSA TORRES">
        <ClienteGestion
          clienteId="99999999-9999-4999-8999-999999999999"
          clienteNombre="ROSA TORRES"
          onCerrar={onCerrar}
          onEnviandoCambio={onEnviandoCambio}
        />
      </Dialog>
    </StoreDataContext.Provider>,
  )

  return { crearTarea, onCerrar, onEnviandoCambio }
}

describe('ClienteGestion', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    auth.demo = true
    sessionStorage.clear()
  })

  it('no anuncia éxito ni cierra hasta que el INSERT real queda confirmado', async () => {
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { crearTarea, onCerrar, onEnviandoCambio } = montar({
      ok: true,
      id: '77777777-7777-4777-8777-777777777777',
      persistido: commit.promesa,
    })

    const clic = user.click(screen.getByRole('button', { name: 'Agendar gestión' }))
    await waitFor(() => expect(crearTarea).toHaveBeenCalledTimes(1))

    expect(crearTarea).toHaveBeenCalledWith(
      expect.objectContaining({
        perfil_id: '99999999-9999-4999-8999-999999999999',
        tipo: 'llamada',
        titulo: 'Llamar a ROSA',
      }),
    )
    expect(screen.getByRole('button', { name: 'Agendando…' })).toBeDisabled()
    expect(onEnviandoCambio).toHaveBeenLastCalledWith(true)
    expect(toast.success).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()

    await act(async () => commit.resolver(true))
    await clic

    expect(onEnviandoCambio).toHaveBeenLastCalledWith(false)
    expect(toast.success).toHaveBeenCalledWith('Gestión agendada · la verás en Hoy y en Agenda')
    expect(onCerrar).toHaveBeenCalledTimes(1)
  })

  it('si el servidor rechaza la tarea, mantiene el formulario abierto y reintentable', async () => {
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { crearTarea, onCerrar, onEnviandoCambio } = montar({
      ok: true,
      id: '77777777-7777-4777-8777-777777777777',
      persistido: commit.promesa,
    })

    const clic = user.click(screen.getByRole('button', { name: 'Agendar gestión' }))
    await waitFor(() => expect(crearTarea).toHaveBeenCalledTimes(1))
    await act(async () => commit.resolver(false))
    await clic

    expect(onEnviandoCambio).toHaveBeenLastCalledWith(false)
    expect(screen.getByRole('button', { name: 'Agendar gestión' })).toBeEnabled()
    expect(toast.success).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()
  })

  it('con F6 encendida resuelve el perfil y agenda sobre la persona, sin alta legada', async () => {
    auth.demo = false
    const persona = '33333333-3333-4333-8333-333333333333'
    vi.mocked(personaDePerfil).mockResolvedValue({habilitada: true, inversionista_id: persona})
    vi.mocked(ejecutarEnvioPostventa).mockResolvedValue(undefined)
    const {crearTarea, onCerrar} = montar({ok: true})
    await userEvent.setup().click(await screen.findByRole('button', {name: 'Agendar gestión'}))
    expect(ejecutarEnvioPostventa).toHaveBeenCalledWith('11111111-1111-4111-8111-111111111111', 'agendar', persona,
      expect.objectContaining({p_inversionista: persona, p_datos: expect.objectContaining({tipo: 'llamada'})}))
    expect(crearTarea).not.toHaveBeenCalled()
    expect(onCerrar).toHaveBeenCalledOnce()
  })

  it('no usa el alta legada cuando no puede verificar el modo y la identidad', async () => {
    auth.demo = false
    vi.mocked(personaDePerfil).mockRejectedValue(new Error('Sin conexión'))
    const {crearTarea} = montar({ok: true})
    await screen.findByRole('button', {name: 'Reintentar'})
    expect(screen.queryByRole('button', {name: 'Agendar gestión'})).not.toBeInTheDocument()
    expect(crearTarea).not.toHaveBeenCalled()
  })
})
