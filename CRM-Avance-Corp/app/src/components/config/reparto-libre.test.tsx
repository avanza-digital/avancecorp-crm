import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { RepartoLibre } from './reparto-libre'

const api = vi.hoisted(() => ({ leer: vi.fn(), guardar: vi.fn() }))
vi.mock('@/data/reparto-config-api', () => ({
  obtenerConfiguracionReparto: (...args: unknown[]) => api.leer(...args),
  guardarConfiguracionReparto: (...args: unknown[]) => api.guardar(...args),
}))
const config = (libre = false, revision = 1) => ({ version: 1, coordinacion_libre: libre, revision, actualizado_en: '2026-10-07T15:00:00Z' })

beforeEach(() => {
  api.leer.mockReset().mockResolvedValue(config())
  api.guardar.mockReset()
})

describe('Control de reparto libre de Gerencia', () => {
  it('activa y desactiva usando la revisión confirmada por el servidor', async () => {
    api.guardar.mockResolvedValueOnce(config(true, 2)).mockResolvedValueOnce(config(false, 3))
    const usuario = userEvent.setup()
    render(<RepartoLibre />)
    await usuario.click(await screen.findByRole('button', { name: 'Activar reparto libre' }))
    expect(api.guardar).toHaveBeenCalledWith(true, 1)
    await usuario.click(await screen.findByRole('button', { name: 'Desactivar reparto libre' }))
    expect(api.guardar).toHaveBeenLastCalledWith(false, 2)
    expect(await screen.findByText('Desactivado', { exact: true })).toBeInTheDocument()
  })

  it('conserva el estado anterior y bloquea dobles envíos mientras guarda', async () => {
    let resolver!: (value: ReturnType<typeof config>) => void
    api.guardar.mockImplementation(() => new Promise((resolve) => { resolver = resolve }))
    const usuario = userEvent.setup()
    render(<RepartoLibre />)
    await usuario.dblClick(await screen.findByRole('button', { name: 'Activar reparto libre' }))
    expect(api.guardar).toHaveBeenCalledTimes(1)
    expect(screen.getByText('Desactivado', { exact: true })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Guardando…' })).toBeDisabled()
    await act(async () => resolver(config(true, 2)))
    expect(screen.getByText('Activado', { exact: true })).toBeInTheDocument()
  })

  it('un conflicto o respuesta perdida obliga a releer y no anuncia éxito', async () => {
    api.leer.mockResolvedValueOnce(config()).mockResolvedValueOnce(config(true, 5))
    api.guardar.mockRejectedValue(new Error('Otra sesión cambió el reparto libre.'))
    const usuario = userEvent.setup()
    render(<RepartoLibre />)
    await usuario.click(await screen.findByRole('button', { name: 'Activar reparto libre' }))
    await waitFor(() => expect(api.leer).toHaveBeenCalledTimes(2))
    expect(await screen.findByText('Activado', { exact: true })).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Otra sesión')
    expect(screen.queryByText('Reparto libre activado para todo el rol Coordinadora.')).not.toBeInTheDocument()
  })

  it('una lectura fallida no presenta el permiso como apagado ni permite escribir', async () => {
    api.leer.mockRejectedValueOnce(new Error('No se pudo consultar')).mockResolvedValueOnce(config(true))
    const usuario = userEvent.setup()
    render(<RepartoLibre />)
    expect(await screen.findByText('Estado no disponible')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Activar reparto libre' })).not.toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Reintentar estado del reparto' }))
    expect(await screen.findByText('Activado', { exact: true })).toBeInTheDocument()
    expect(api.guardar).not.toHaveBeenCalled()
  })
})
