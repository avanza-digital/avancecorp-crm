import { beforeEach, expect, it, vi } from 'vitest'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { GuardadosSlaPendientes } from './guardados-sla-pendientes'

const doble = vi.hoisted(() => ({ actor: { id: 'actor', rol: 'vendedor', demo: false },
  confirmar: vi.fn(), recargar: vi.fn(), listar: vi.fn() }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: doble.actor }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ recargar: doble.recargar }) }))
vi.mock('@/data/sla-operacion-comandos', () => ({ confirmarPendienteSla: doble.confirmar,
  listarPendientesSla: doble.listar, suscribirPendientesSla: () => () => undefined }))
beforeEach(() => {
  vi.clearAllMocks()
  doble.actor = { id: 'actor', rol: 'vendedor', demo: false }
  doble.listar.mockReturnValue([{ operacion: 'id-opaco', comando: 'registrar_actividad_v2', enCurso: false }])
  doble.recargar.mockResolvedValue(true)
})
function montar() {
  render(<QueryClientProvider client={new QueryClient()}><GuardadosSlaPendientes /></QueryClientProvider>)
}
it('recupera solo mediante acción explícita y espera ACK antes de recargar o anunciar éxito', async () => {
  let confirmar!: () => void
  doble.confirmar.mockReturnValue(new Promise<void>((resolve) => { confirmar = resolve }))
  montar()
  expect(doble.confirmar).not.toHaveBeenCalled()
  expect(screen.queryByText('id-opaco')).not.toBeInTheDocument()
  await userEvent.setup().click(screen.getByRole('button', { name: 'Verificar guardado' }))
  expect(doble.confirmar).toHaveBeenCalledWith('actor', 'id-opaco')
  expect(doble.recargar).not.toHaveBeenCalled()
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
  doble.listar.mockReturnValue([])
  confirmar()
  expect(await screen.findByRole('status')).toHaveTextContent('Guardado confirmado y vista actualizada')
  expect(doble.recargar).toHaveBeenCalledTimes(1)
})
it('un error mantiene el reintento y no anuncia éxito', async () => {
  doble.confirmar.mockRejectedValue(new Error('Sin conexión'))
  montar()
  await userEvent.setup().click(screen.getByRole('button', { name: 'Verificar guardado' }))
  expect(await screen.findByRole('alert')).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Verificar guardado' })).toBeEnabled()
  expect(doble.recargar).not.toHaveBeenCalled()
})
it.each(['coordinador', 'directorio'])('omite acciones de escritura para %s', (rol) => {
  doble.actor.rol = rol
  montar()
  expect(screen.queryByRole('region')).not.toBeInTheDocument()
})
it('pagina cinco guardados por vez sin acumular filas', async () => {
  doble.listar.mockReturnValue(Array.from({ length: 7 }, (_, i) => ({ operacion: String(i), comando: 'registrar_actividad_v2', enCurso: false })))
  montar()
  expect(screen.getAllByRole('button', { name: 'Verificar guardado' })).toHaveLength(5)
  await userEvent.setup().click(screen.getByRole('button', { name: 'Siguientes' }))
  expect(screen.getAllByRole('button', { name: 'Verificar guardado' })).toHaveLength(2)
  expect(screen.queryByText('Contacto · Operación 1')).not.toBeInTheDocument()
  expect(screen.getByText('Página 2 de 2 · 7 guardados')).toBeInTheDocument()
})
