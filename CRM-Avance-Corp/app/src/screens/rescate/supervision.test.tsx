// Las dos pestañas de Supervisión y Gerencia (F4, decisión 2 de Miguel): «Descartes del mes» —el Centro de rescate
// de siempre, INTACTO y por defecto— y «Gestión de la base». La pestaña y el analista viven en la URL (el patrón de la
// carpeta), sobreviven a recargar y se limpian al salir de la pantalla.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

const montajesDescartes = vi.fn()
const montajesGestion = vi.fn()
/** Cuenta MONTAJES (no repintados) del Centro de rescate: volver a su pestaña no debe recargarlo. */
const montadoDescartes = vi.fn()
let avisarAnalista: ((a: string | null) => void) | null = null
vi.mock('@/screens/rescate-descartados', async () => {
  const { useEffect } = await import('react')
  return {
    RescateDescartados: (props: Record<string, unknown>) => {
      montajesDescartes(props)
      useEffect(() => { montadoDescartes() }, [])
      return <p>Centro de rescate del equipo</p>
    },
  }
})
vi.mock('@/screens/rescate/gestion-supervisor', () => ({
  GestionSupervisor: ({ analistaInicial, onAnalista }: { analistaInicial: string | null; onAnalista: (a: string | null) => void }) => {
    montajesGestion(analistaInicial)
    avisarAnalista = onAnalista
    return <p>Gestión de la base del equipo · {analistaInicial ?? 'todos'}</p>
  },
}))

const { BaseGestionSupervision } = await import('./supervision')

const ANA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const irA = (ruta: string) => window.history.replaceState(null, '', ruta)
const parametros = () => new URLSearchParams(window.location.search)

beforeEach(() => { irA('/#/rescate'); avisarAnalista = null })
afterEach(() => { vi.clearAllMocks(); irA('/') })

describe('pestañas de la base para gestión', () => {
  it('al entrar abre «Descartes del mes» con el Centro de rescate tal cual (sin props nuevas); «Gestión» no se monta hasta pedirla', () => {
    render(<BaseGestionSupervision />)
    expect(screen.getByRole('tablist', { name: 'Base para gestión' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Descartes del mes' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('tab', { name: 'Gestión de la base' })).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByText('Centro de rescate del equipo')).toBeVisible()
    expect(montajesDescartes).toHaveBeenCalledWith({})
    expect(montajesGestion).not.toHaveBeenCalled()
    expect(window.location.search).toBe('')
  })

  it('cambiar de pestaña escribe la URL; volver a «Descartes» la limpia y NO recarga el Centro de rescate', async () => {
    render(<BaseGestionSupervision />)
    await userEvent.click(screen.getByRole('tab', { name: 'Gestión de la base' }))
    expect(screen.getByText(/Gestión de la base del equipo/)).toBeVisible()
    expect(screen.getByText('Centro de rescate del equipo')).not.toBeVisible()
    expect(parametros().get('rescate_vista')).toBe('gestion')
    expect(window.location.hash).toBe('#/rescate')
    await userEvent.click(screen.getByRole('tab', { name: 'Descartes del mes' }))
    expect(window.location.search).toBe('')
    expect(screen.getByText('Centro de rescate del equipo')).toBeVisible()
    // Se conservó montado (oculto): ni el mes ni la carpeta elegidos se pierden.
    expect(montadoDescartes).toHaveBeenCalledTimes(1)
  })

  it('las flechas del teclado cambian de pestaña (patrón de pestañas accesibles)', async () => {
    render(<BaseGestionSupervision />)
    screen.getByRole('tab', { name: 'Descartes del mes' }).focus()
    await userEvent.keyboard('{ArrowRight}')
    expect(screen.getByRole('tab', { name: 'Gestión de la base' })).toHaveFocus()
    expect(screen.getByRole('tab', { name: 'Gestión de la base' })).toHaveAttribute('aria-selected', 'true')
  })

  it('una URL con ?rescate_vista=gestion&rescate_analista=… abre «Gestión» con ese analista (recargar no pierde nada)', () => {
    irA(`/?rescate_vista=gestion&rescate_analista=${ANA}#/rescate`)
    render(<BaseGestionSupervision />)
    expect(screen.getByRole('tab', { name: 'Gestión de la base' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByText(`Gestión de la base del equipo · ${ANA}`)).toBeVisible()
    expect(montajesDescartes).not.toHaveBeenCalled()
  })

  it('la bandeja (sin analista) viaja como «sin-analista» en la URL y como la clave «sin dato» en el filtro', () => {
    irA('/?rescate_vista=gestion&rescate_analista=sin-analista#/rescate')
    render(<BaseGestionSupervision />)
    expect(montajesGestion).toHaveBeenCalledWith('(sin dato)')
  })

  it('un analista inválido en la URL no se usa', () => {
    irA('/?rescate_vista=gestion&rescate_analista=<script>#/rescate')
    render(<BaseGestionSupervision />)
    expect(montajesGestion).toHaveBeenCalledWith(null)
  })

  it('el analista que elige la hoja se escribe en la URL (y se borra al quitarlo)', async () => {
    render(<BaseGestionSupervision />)
    await userEvent.click(screen.getByRole('tab', { name: 'Gestión de la base' }))
    const { act } = await import('@testing-library/react')
    act(() => avisarAnalista?.(ANA))
    expect(parametros().get('rescate_analista')).toBe(ANA)
    act(() => avisarAnalista?.('(sin dato)'))
    expect(parametros().get('rescate_analista')).toBe('sin-analista')
    act(() => avisarAnalista?.(null))
    expect(parametros().has('rescate_analista')).toBe(false)
    expect(parametros().get('rescate_vista')).toBe('gestion')
  })

  it('al salir de la pantalla la URL se limpia: al volver se entra por «Descartes del mes»', async () => {
    const { unmount } = render(<BaseGestionSupervision />)
    await userEvent.click(screen.getByRole('tab', { name: 'Gestión de la base' }))
    expect(parametros().get('rescate_vista')).toBe('gestion')
    irA(`${window.location.pathname}${window.location.search}#/hoy`)
    unmount()
    expect(window.location.search).toBe('')
    expect(window.location.hash).toBe('#/hoy')
  })
})
