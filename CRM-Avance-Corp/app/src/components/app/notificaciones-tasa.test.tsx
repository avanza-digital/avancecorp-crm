import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
const dobles = vi.hoisted(() => ({
  yo: { id: 'gerencia-1', rol: 'gerencia', demo: false },
  consultar: vi.fn(), activar: vi.fn(), desactivar: vi.fn(), probar: vi.fn(),
  soporte: 'disponible',
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/notificaciones-tasa', () => ({
  consultarPushTasa: dobles.consultar, activarPushTasa: dobles.activar,
  desactivarPushTasa: dobles.desactivar, probarPushTasa: dobles.probar,
  soportePushTasa: () => dobles.soporte, vincularCuentaPushTasa: vi.fn(),
}))
const { NotificacionesTasa } = await import('./notificaciones-tasa')
beforeEach(() => {
  dobles.yo = { id: 'gerencia-1', rol: 'gerencia', demo: false }; dobles.soporte = 'disponible'
  dobles.consultar.mockReset().mockResolvedValue({ configurado: true, clavePublica: 'clave-publica', dispositivo: null })
  dobles.activar.mockReset().mockResolvedValue('dispositivo-1')
  dobles.desactivar.mockReset().mockResolvedValue({ pendiente: false }); dobles.probar.mockReset().mockResolvedValue(undefined)
  Object.defineProperty(window, 'Notification', { configurable: true, value: { permission: 'granted' } })
})
describe('Avisos en el teléfono', () => {
  it('activar, enviar prueba y desactivar tienen respuesta visible y accesible', async () => {
    render(<NotificacionesTasa />)
    fireEvent.click(await screen.findByRole('button', { name: 'Activar notificaciones' }))
    expect(await screen.findByText('Activados en este dispositivo')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Enviar prueba' }))
    expect(await screen.findByText(/Aviso de prueba enviado/)).toHaveAttribute('role', 'status')
    fireEvent.click(screen.getByRole('button', { name: 'Desactivar' }))
    await waitFor(() => expect(dobles.desactivar).toHaveBeenCalledWith('dispositivo-1'))
    expect(await screen.findByRole('button', { name: 'Activar notificaciones' })).toBeInTheDocument()
  })
  it('un error no deja el botón como activado', async () => {
    dobles.activar.mockRejectedValue(new Error('Permiso bloqueado'))
    render(<NotificacionesTasa />)
    const anuncio = screen.getByRole('alert')
    expect(anuncio).toBeEmptyDOMElement()
    fireEvent.click(await screen.findByRole('button', { name: 'Activar notificaciones' }))
    await waitFor(() => expect(anuncio).toHaveTextContent('Permiso bloqueado'))
    expect(screen.getByRole('alert')).toBe(anuncio)
    expect(screen.queryByText('Activados en este dispositivo')).not.toBeInTheDocument()
  })
  it('estado real sin servidor configurado explica que todavía se está preparando', async () => {
    dobles.consultar.mockResolvedValue({ configurado: false, clavePublica: '', dispositivo: null })
    render(<NotificacionesTasa />)
    expect(await screen.findByText(/Los avisos se están preparando/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Activar notificaciones' })).not.toBeInTheDocument()
  })
  it('una baja pendiente en servidor retira la activación visible y lo explica', async () => {
    dobles.consultar.mockResolvedValue({ configurado: true, clavePublica: 'clave-publica', dispositivo: { id: 'dispositivo-1', activo: true } })
    dobles.desactivar.mockResolvedValue({ pendiente: true })
    render(<NotificacionesTasa />)
    fireEvent.click(await screen.findByRole('button', { name: 'Desactivar' }))
    expect(await screen.findByRole('button', { name: 'Activar notificaciones' })).toBeInTheDocument()
    expect(screen.queryByText('Activados en este dispositivo')).not.toBeInTheDocument()
    expect(await screen.findByText(/Confirmaremos la baja/)).toHaveAttribute('role', 'status')
  })
  it('en iPhone sin instalar orienta al usuario sin pedir permisos', () => {
    dobles.soporte = 'instalar'; render(<NotificacionesTasa />)
    expect(screen.getByText(/Añadir a pantalla de inicio/)).toBeInTheDocument()
    expect(dobles.consultar).not.toHaveBeenCalled(); expect(dobles.activar).not.toHaveBeenCalled()
  })
  it('la demostración no contacta al servidor y otros roles no reciben el control', () => {
    dobles.yo.demo = true
    const vista = render(<NotificacionesTasa />)
    expect(screen.getByText(/Disponible al iniciar sesión/)).toBeInTheDocument()
    expect(dobles.consultar).not.toHaveBeenCalled()
    dobles.yo = { id: 'vendedor', rol: 'vendedor', demo: false }; vista.rerender(<NotificacionesTasa />)
    expect(screen.queryByRole('region')).not.toBeInTheDocument()
  })
})
