import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { toast } from 'sonner'
import type { ResultadoPersistencia } from '@/lib/store'
import { Dialog } from '@/components/ui/dialog'

const store = vi.hoisted(() => ({
  crearTarea: vi.fn(),
  tareasDeCliente: vi.fn(() => []),
}))

vi.mock('@/lib/store-context', () => ({
  useCRMData: () => store,
}))

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn() },
}))

const { ClienteGestion } = await import('./cliente-gestion')

function diferida<T>() {
  let resolver!: (valor: T) => void
  const promesa = new Promise<T>((resolve) => {
    resolver = resolve
  })
  return { promesa, resolver }
}

describe('ClienteGestion — confirmación persistida', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    store.tareasDeCliente.mockReturnValue([])
  })

  it('no anuncia éxito ni cierra hasta que el servidor confirma el alta', async () => {
    const user = userEvent.setup()
    const confirmacion = diferida<ResultadoPersistencia>()
    const onCerrar = vi.fn()
    const onEnviandoCambio = vi.fn()
    store.crearTarea.mockReturnValue({
      ok: true,
      id: 'tarea-1',
      persistido: confirmacion.promesa,
    })
    render(
      <Dialog open onClose={vi.fn()} ariaLabel="Gestionar cliente">
        <ClienteGestion
          clienteId="cliente-1"
          clienteNombre="Rosa"
          onCerrar={onCerrar}
          onEnviandoCambio={onEnviandoCambio}
        />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Agendar gestión' }))

    expect(screen.getByRole('button', { name: 'Guardando…' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled()
    expect(onEnviandoCambio).toHaveBeenLastCalledWith(true)
    expect(toast.success).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()

    act(() => confirmacion.resolver({ ok: true }))
    await waitFor(() => expect(onCerrar).toHaveBeenCalledTimes(1))
    expect(onEnviandoCambio).toHaveBeenLastCalledWith(false)
    expect(toast.success).toHaveBeenCalledWith('Gestión agendada · la verás en Hoy y en Agenda')
  })

  it('si el servidor rechaza, no muestra falso éxito ni cierra el diálogo', async () => {
    const user = userEvent.setup()
    const onCerrar = vi.fn()
    const onEnviandoCambio = vi.fn()
    store.crearTarea.mockReturnValue({
      ok: true,
      id: 'tarea-1',
      persistido: Promise.resolve({ ok: false, error: 'Cliente inactivo' }),
    })
    render(
      <Dialog open onClose={vi.fn()} ariaLabel="Gestionar cliente">
        <ClienteGestion
          clienteId="cliente-1"
          clienteNombre="Rosa"
          onCerrar={onCerrar}
          onEnviandoCambio={onEnviandoCambio}
        />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Agendar gestión' }))

    await waitFor(() => expect(screen.getByRole('button', { name: 'Agendar gestión' })).toBeEnabled())
    expect(onEnviandoCambio).toHaveBeenLastCalledWith(false)
    expect(toast.success).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()
  })
})
