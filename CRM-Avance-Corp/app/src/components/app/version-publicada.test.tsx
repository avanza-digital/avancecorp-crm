import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { VersionPublicadaAviso } from './version-publicada'

function fetchConVersion(buildId: string) {
  return vi.fn().mockResolvedValue({
    ok: true,
    json: vi.fn().mockResolvedValue({ schema: 1, buildId }),
  })
}

describe('VersionPublicadaAviso', () => {
  it('avisa una version nueva sin recargar automaticamente', async () => {
    const actualizar = vi.fn()
    render(
      <VersionPublicadaAviso
        activo
        buildActual="build-anterior"
        fetchVersion={fetchConVersion('build-nuevo')}
        onActualizar={actualizar}
      />,
    )

    expect(await screen.findByText('Nueva versión disponible')).toBeInTheDocument()
    expect(actualizar).not.toHaveBeenCalled()
    expect(screen.getByText(/Esta pantalla no se recargará sola/)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Ya guardé, actualizar' }))
    expect(actualizar).toHaveBeenCalledWith('build-nuevo')
  })

  it('permanece oculto cuando el marcador corresponde al build abierto', async () => {
    const fetchVersion = fetchConVersion('build-actual')
    render(
      <VersionPublicadaAviso
        activo
        buildActual="build-actual"
        fetchVersion={fetchVersion}
      />,
    )

    await waitFor(() => expect(fetchVersion).toHaveBeenCalledOnce())
    expect(screen.queryByText('Nueva versión disponible')).not.toBeInTheDocument()
  })

  it('convierte un chunk obsoleto de Vite en una salida segura', async () => {
    const actualizar = vi.fn()
    render(
      <VersionPublicadaAviso
        activo
        buildActual="build-actual"
        fetchVersion={fetchConVersion('build-actual')}
        onActualizar={actualizar}
      />,
    )

    const evento = new Event('vite:preloadError', { cancelable: true })
    window.dispatchEvent(evento)

    expect(evento.defaultPrevented).toBe(true)
    expect(await screen.findByText('Nueva versión disponible')).toBeInTheDocument()
    expect(actualizar).not.toHaveBeenCalled()
  })
})
