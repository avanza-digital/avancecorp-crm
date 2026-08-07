// Tests del menú lateral centrados en sus TEMPORIZADORES (asomo/repliegue del
// hover). El bug que fijan: en móvil, el toque que abre el menú programa un
// "asomar" que sobrevivía a la navegación, así que el menú se volvía a abrir
// ENCIMA de la pantalla recién elegida. `matchMedia` se stubbea (jsdom no evalúa
// media queries) y se usan timers falsos + fireEvent (userEvent necesitaría
// advanceTimers y aquí lo que se mide es justo el reloj).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import type { Rol } from '@/lib/roles'
import type { Vista } from '@/lib/router'
import type { Yo } from '@/lib/tipos'

let YO: Yo | null = null
const salir = vi.fn()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO, salir }) }))

const { Sidebar } = await import('./sidebar')

const ABRIR_MS = 120 // espejo del sidebar (retardo del asomo)

function montar({
  movil = true,
  rol = 'vendedor',
  vista = 'hoy',
  identidad = {},
}: {
  movil?: boolean
  rol?: Rol
  vista?: Vista
  identidad?: Partial<Yo>
} = {}) {
  vi.stubGlobal('matchMedia', () => ({ matches: movil }))
  YO = {
    id: 'u-v1',
    nombre_completo: 'Vendedor Real',
    rol,
    demo: true,
    puede_contratar: true,
    ...identidad,
  }
  const onNavegar = vi.fn()
  const { container, unmount } = render(<Sidebar vista={vista} onNavegar={onNavegar} />)
  const panel = container.querySelector('aside > div')
  if (!panel) throw new Error('no se montó el panel del menú')
  return { panel, unmount, onNavegar }
}

/** El panel asoma a w-60 y se repliega al riel de w-16. */
const asomado = (panel: Element) => panel.className.includes('w-60')

/** React deja una tarea propia en vuelo al montar: se drena para que el conteo
 *  de temporizadores mida SOLO los del menú. */
const drenarTareasDeReact = () => act(() => vi.advanceTimersByTime(1000))

describe('Sidebar — temporizadores del asomo', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    window.location.hash = ''
  })
  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('móvil: tras navegar, el menú NO se vuelve a abrir encima de la pantalla elegida', () => {
    const { panel, onNavegar } = montar()

    // El toque abre el menú (mouseEnter también lo dispara un tap real).
    fireEvent.mouseEnter(panel)
    act(() => vi.advanceTimersByTime(ABRIR_MS))
    expect(asomado(panel)).toBe(true)

    // El toque sobre el ítem vuelve a programar un asomo…
    fireEvent.mouseEnter(panel)
    fireEvent.click(screen.getByRole('button', { name: 'Pipeline' }))

    expect(onNavegar).toHaveBeenCalledOnce()
    expect(onNavegar).toHaveBeenCalledWith('pipeline')
    expect(asomado(panel)).toBe(false)
    // …y ese temporizador huérfano era el que reabría el menú solo.
    act(() => vi.advanceTimersByTime(1000))
    expect(asomado(panel)).toBe(false)
  })

  it('re-disparar el hover no acumula temporizadores (el ref solo guarda el último)', () => {
    const { panel } = montar()
    drenarTareasDeReact()
    fireEvent.mouseEnter(panel)
    fireEvent.mouseEnter(panel)
    fireEvent.mouseEnter(panel)
    // Sin cancelar antes de reprogramar quedarían 3 y el ref solo podría
    // cancelar el último: los otros dos seguirían vivos tras el desmontaje.
    expect(vi.getTimerCount()).toBe(1)
  })

  it('al desmontar no queda ningún temporizador vivo', () => {
    const { panel, unmount } = montar()
    drenarTareasDeReact()
    fireEvent.mouseEnter(panel)
    expect(vi.getTimerCount()).toBe(1)
    unmount()
    expect(vi.getTimerCount()).toBe(0)
  })

  it('escritorio: navegar no repliega el menú (el hover manda ahí)', () => {
    const { panel, onNavegar } = montar({ movil: false })
    fireEvent.mouseEnter(panel)
    act(() => vi.advanceTimersByTime(ABRIR_MS))
    fireEvent.click(screen.getByRole('button', { name: 'Pipeline' }))
    expect(onNavegar).toHaveBeenCalledWith('pipeline')
    expect(asomado(panel)).toBe(true)
  })

  it('Gerencia ve inteligencia y toda la navegación operativa', () => {
    montar({ movil: false, rol: 'gerencia' })
    const navegacion = screen.getByRole('navigation')

    const nombres = [
      'Resumen',
      'Conversiones',
      'Ranking',
      'Reuniones',
      'Metas',
      'Rendimiento',
      'Pipeline',
      'Leads',
      'Agenda',
      'Cartera',
      'Repartir leads',
      'Gestión de equipo',
      'Configuración',
    ]
    expect(within(navegacion).getAllByRole('button')).toHaveLength(nombres.length)
    expect(within(navegacion).getAllByRole('button').map((boton) => boton.textContent?.trim())).toEqual(nombres)
    for (const nombre of nombres) {
      expect(within(navegacion).getByRole('button', { name: nombre })).toBeVisible()
    }
    expect(within(navegacion).queryByRole('button', { name: 'Alertas' })).not.toBeInTheDocument()
    expect(within(navegacion).queryByRole('button', { name: 'Capital' })).not.toBeInTheDocument()
  })

  it('Superadmin sin Gerencia ve y navega únicamente a Usuarios y roles', () => {
    const { onNavegar } = montar({
      movil: false,
      rol: 'directorio',
      vista: 'config-usuarios',
      identidad: {
        demo: false,
        rol_portal: 'superadmin',
        capacidades_config: {
          puede_listar_usuarios: true,
          puede_administrar_usuarios: false,
          puede_organizar_jerarquia: false,
          puede_administrar_roles: true,
        },
      },
    })
    const navegacion = screen.getByRole('navigation')

    expect(within(navegacion).getAllByRole('button')).toHaveLength(1)
    expect(within(navegacion).getByRole('button', { name: 'Usuarios y roles' })).toBeVisible()
    expect(screen.getByText('Gobierno de roles CRM')).toBeVisible()
    expect(screen.queryByText(/Modo auditoría/)).not.toBeInTheDocument()

    fireEvent.click(within(navegacion).getByRole('button', { name: 'Usuarios y roles' }))
    expect(onNavegar).toHaveBeenCalledWith('config-usuarios')
  })
})
