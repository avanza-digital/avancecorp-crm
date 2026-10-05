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
    nombre_completo: 'Analista Real',
    rol,
    demo: true,
    puede_contratar: true,
    ...identidad,
  }
  const onNavegar = vi.fn()
  const { container, unmount, rerender } = render(<Sidebar vista={vista} onNavegar={onNavegar} />)
  const panel = container.querySelector('aside > div')
  if (!panel) throw new Error('no se montó el panel del menú')
  return { panel, unmount, onNavegar, cambiarVista: (destino: Vista) => rerender(<Sidebar vista={destino} onNavegar={onNavegar} />) }
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
    localStorage.clear()
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

  it('Gerencia prioriza siete accesos y conserva los demás en tres grupos desplegables', () => {
    montar({ movil: false, rol: 'gerencia' })
    const navegacion = within(screen.getByRole('navigation'))
    const principales = ['Resumen', 'Facturación', 'Ranking', 'Citas', 'Gestión Diaria', 'Metas y cumplimiento', 'Cartera']
    const grupos = {
      Análisis: ['Rendimiento', 'Conversiones', 'Empresas'],
      Operación: ['Leads', 'Pipeline', 'Agenda', 'Repartir leads', 'Base para gestión', 'Seguimiento'],
      Administración: ['Gestión de equipo', 'Configuración'],
    } as const
    expect(navegacion.getAllByRole('button').map((b) => b.textContent?.trim())).toEqual([...principales, ...Object.keys(grupos)])
    expect(navegacion.getByRole('button', { name: 'Resumen' })).toHaveAttribute('aria-current', 'page')
    for (const [grupo, entradas] of Object.entries(grupos)) {
      const seccion = within(navegacion.getByRole('group', { name: grupo }))
      const cabecera = seccion.getByRole('button', { name: grupo })
      expect(cabecera).toHaveAttribute('aria-expanded', 'false')
      const contenido = document.getElementById(cabecera.getAttribute('aria-controls')!)
      expect(contenido).not.toBeVisible()
      expect(seccion.queryByRole('button', { name: entradas[0] })).not.toBeInTheDocument()
      fireEvent.click(cabecera)
      expect(cabecera).toHaveAttribute('aria-expanded', 'true')
      expect(contenido).toBeVisible()
      expect(seccion.getAllByRole('button').slice(1).map((b) => b.textContent?.trim())).toEqual(entradas)
    }
    // 18 destinos autorizados + tres controles para desplegarlos.
    expect(navegacion.getAllByRole('button')).toHaveLength(21)
    expect(navegacion.queryByRole('button', { name: 'Alertas' })).not.toBeInTheDocument()
    expect(navegacion.queryByRole('button', { name: 'Derivar leads' })).not.toBeInTheDocument()
  })

  it.each([
    ['conversiones', 'Análisis', 'Conversiones'],
    ['pipeline', 'Operación', 'Pipeline'],
    ['config-usuarios', 'Administración', 'Configuración'],
    ['rescate-carpeta', 'Operación', 'Base para gestión'],
  ] as const)('Gerencia revela el destino directo %s y marca su entrada activa', (vista, grupo, entrada) => {
    montar({ movil: false, rol: 'gerencia', vista })
    expect(screen.getByRole('button', { name: grupo })).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('button', { name: entrada })).toHaveAttribute('aria-current', 'page')
  })

  it('volver por una ruta abre su grupo aunque se hubiese cerrado manualmente', () => {
    const { cambiarVista } = montar({ movil: false, rol: 'gerencia', vista: 'conversiones' })
    const analisis = screen.getByRole('button', { name: 'Análisis' })
    fireEvent.click(analisis)
    expect(analisis).toHaveAttribute('aria-expanded', 'false')
    cambiarVista('hoy')
    cambiarVista('conversiones')
    expect(analisis).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('button', { name: 'Conversiones' })).toBeVisible()
  })

  it('móvil: tocar un grupo desde el riel abre sus destinos y navegar cierra sin rebote', () => {
    const { panel, onNavegar } = montar({ rol: 'gerencia' })
    fireEvent.mouseEnter(panel)
    fireEvent.click(screen.getByRole('button', { name: 'Operación' }))
    expect(asomado(panel)).toBe(true)
    fireEvent.mouseLeave(panel)
    act(() => vi.advanceTimersByTime(1000))
    expect(asomado(panel)).toBe(true)
    fireEvent.click(screen.getByRole('button', { name: 'Pipeline' }))
    expect(onNavegar).toHaveBeenCalledWith('pipeline')
    expect(asomado(panel)).toBe(false)
    act(() => vi.advanceTimersByTime(1000))
    expect(asomado(panel)).toBe(false)
    expect(localStorage.getItem('ac-crm-sidebar-colapsado')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Fijar menú abierto' }))
    fireEvent.click(screen.getByRole('button', { name: 'Ocultar menú' }))
    act(() => vi.advanceTimersByTime(1000))
    expect(asomado(panel)).toBe(false)
  })

  it('escritorio: abrir un grupo durante el asomo conserva la preferencia del riel', () => {
    localStorage.setItem('ac-crm-sidebar-colapsado', '1')
    const { panel } = montar({ movil: false, rol: 'gerencia' })
    fireEvent.mouseEnter(panel)
    act(() => vi.advanceTimersByTime(ABRIR_MS))
    fireEvent.click(screen.getByRole('button', { name: 'Análisis' }))
    fireEvent.mouseLeave(panel)
    act(() => vi.advanceTimersByTime(1000))
    expect(asomado(panel)).toBe(true)
    expect(localStorage.getItem('ac-crm-sidebar-colapsado')).toBe('1')
    fireEvent.click(screen.getByRole('button', { name: 'Ocultar menú' }))
    expect(asomado(panel)).toBe(false)
  })

  it('un grupo abierto manualmente se conserva al navegar a un acceso principal', () => {
    const { cambiarVista } = montar({ movil: false, rol: 'gerencia' })
    fireEvent.click(screen.getByRole('button', { name: 'Operación' }))
    cambiarVista('facturacion')
    expect(screen.getByRole('button', { name: 'Operación' })).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('button', { name: 'Pipeline' })).toBeVisible()
  })

  it('Directorio conserva Configuración seleccionada dentro de sus subrutas', () => {
    montar({ movil: false, rol: 'directorio', vista: 'config-usuarios' })
    expect(screen.getByRole('button', { name: 'Configuración' })).toHaveAttribute('aria-current', 'page')
  })

  it('los demás roles conservan el menú histórico (Principal, y Administración si aplica)', () => {
    const { unmount } = montar({ movil: false, rol: 'supervisor' })
    let navegacion = screen.getByRole('navigation')
    expect(within(navegacion).getAllByRole('group').map((g) => g.getAttribute('aria-label'))).toEqual(['Principal'])
    expect(within(navegacion).queryByText('Dirección')).not.toBeInTheDocument()
    // Facturación (16/09/2026): Supervisión la tiene en su menú histórico, para
    // ver el avance de su equipo; las demás páginas ejecutivas siguen sin estar.
    expect(within(navegacion).getByRole('button', { name: 'Facturación' })).toBeVisible()
    expect(within(navegacion).queryByRole('button', { name: 'Ranking' })).not.toBeInTheDocument()
    expect(within(navegacion).queryByRole('button', { name: 'Conversiones' })).not.toBeInTheDocument()
    unmount()

    const analista = montar({ movil: false, rol: 'vendedor' })
    navegacion = screen.getByRole('navigation')
    expect(within(navegacion).queryByRole('button', { name: 'Facturación' })).not.toBeInTheDocument()
    analista.unmount()

    montar({ movil: false, rol: 'directorio' })
    navegacion = screen.getByRole('navigation')
    expect(within(navegacion).getAllByRole('group').map((g) => g.getAttribute('aria-label'))).toEqual(['Principal', 'Administración'])
    expect(within(navegacion).getByRole('group', { name: 'Administración' }).textContent).toContain('Configuración')
  })

  it('Supervisión abre Derivar leads como módulo separado de Gestión de equipo', () => {
    const { onNavegar } = montar({ movil: false, rol: 'supervisor', vista: 'equipo' })
    const navegacion = screen.getByRole('navigation')

    const derivaciones = within(navegacion).getByRole('button', { name: 'Derivar leads' })
    expect(derivaciones).toBeVisible()
    expect(
      within(navegacion).getByRole('button', { name: 'Gestión de equipo' }),
    ).toBeVisible()

    fireEvent.click(derivaciones)
    expect(onNavegar).toHaveBeenCalledWith('derivaciones')
  })

  it.each(['gerencia', 'supervisor', 'vendedor'] as const)('%s navega a Seguimiento desde su entrada propia', (rol) => {
    const { onNavegar } = montar({ movil: false, rol, vista: 'seguimiento' })
    const acceso = screen.getByRole('button', { name: 'Seguimiento' })
    expect(acceso).toBeVisible()
    fireEvent.click(acceso)
    expect(onNavegar).toHaveBeenCalledWith('seguimiento')
  })

  it.each(['directorio', 'coordinador'] as const)('no ofrece Seguimiento a %s', (rol) => {
    montar({ movil: false, rol })
    expect(screen.queryByRole('button', { name: 'Seguimiento' })).not.toBeInTheDocument()
  })

  it('Superadmin sin Gerencia accede a Usuarios y roles y Control de Citas', () => {
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

    expect(within(navegacion).getAllByRole('button')).toHaveLength(2)
    expect(within(navegacion).getByRole('button', { name: 'Usuarios y roles' })).toBeVisible()
    expect(screen.getByText('Gobierno de roles CRM')).toBeVisible()
    expect(screen.queryByText(/Modo auditoría/)).not.toBeInTheDocument()

    fireEvent.click(within(navegacion).getByRole('button', { name: 'Usuarios y roles' }))
    expect(onNavegar).toHaveBeenCalledWith('config-usuarios')
    fireEvent.click(within(navegacion).getByRole('button', { name: 'Control de Citas' }))
    expect(onNavegar).toHaveBeenCalledWith('config-citas')
  })
})
