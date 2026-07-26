// Estados de panel: el foco es la HONESTIDAD sin red. Un skeleton perpetuo
// ("cargando" cuando nadie está cargando nada) dejaba al asesor esperando para
// siempre en «Mi cartera» y en los diálogos de cliente/contrato.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { act } from 'react'
import { Inbox } from 'lucide-react'
import { PanelCargando, PanelError, PanelSinConexion, PanelVacio } from './estado-panel'

/** Fija lo que el navegador dice de la red (navigator.onLine es solo-lectura). */
function fingirRed(enLinea: boolean) {
  Object.defineProperty(navigator, 'onLine', { value: enLinea, configurable: true })
}

afterEach(() => fingirRed(true))

describe('PanelCargando', () => {
  it('con red pinta skeletons y marca aria-busy', () => {
    fingirRed(true)
    const { container } = render(<PanelCargando filas={4} />)
    expect(container.querySelector('[aria-busy]')).not.toBeNull()
    expect(screen.queryByText('Sin conexión')).toBeNull()
  })

  it('SIN red no miente con un skeleton: dice que no hay conexión', () => {
    fingirRed(false)
    const { container } = render(<PanelCargando />)
    expect(screen.getByText('Sin conexión')).toBeInTheDocument()
    expect(container.querySelector('[aria-busy]')).toBeNull()
  })

  it('sin red ofrece reintentar cuando la pantalla pasa el callback', async () => {
    fingirRed(false)
    const reintentar = vi.fn()
    render(<PanelCargando onReintentar={reintentar} />)
    await userEvent.click(screen.getByRole('button', { name: /reintentar/i }))
    expect(reintentar).toHaveBeenCalledTimes(1)
  })

  it('vuelve al skeleton en cuanto regresa la conexión (evento online)', () => {
    fingirRed(false)
    const { container } = render(<PanelCargando />)
    expect(screen.getByText('Sin conexión')).toBeInTheDocument()

    fingirRed(true)
    act(() => {
      window.dispatchEvent(new Event('online'))
    })
    expect(container.querySelector('[aria-busy]')).not.toBeNull()
  })
})

describe('PanelSinConexion', () => {
  it('sin callback no inventa un botón muerto, pero promete recuperación sola', () => {
    render(<PanelSinConexion />)
    expect(screen.queryByRole('button')).toBeNull()
    expect(screen.getByText(/en cuanto vuelva la conexión/i)).toBeInTheDocument()
  })
})

describe('PanelError / PanelVacio', () => {
  it('el error deshabilita el botón MIENTRAS reintenta', () => {
    render(<PanelError mensaje="No se pudo cargar la cartera" onReintentar={vi.fn()} reintentando />)
    expect(screen.getByRole('button', { name: /reintentar/i })).toBeDisabled()
  })

  it('el vacío es un vacío de verdad: sin reintentar ni tono de error', () => {
    render(<PanelVacio icono={Inbox} titulo="Aún no tienes clientes" detalle="Da de alta el primero" />)
    expect(screen.getByText('Aún no tienes clientes')).toBeInTheDocument()
    expect(screen.queryByRole('button')).toBeNull()
  })
})
