// La pantalla enruta por rol como Hoy: el analista abre con «Mi día» (Fase 3),
// que desde el 27/09/2026 trae dentro su registro y en su cabecera el acceso a
// «Seguimiento completo»; el supervisor ve su
// equipo con filtro de analista, y gerencia además elige el día y exporta. Los
// roles que no entran reciben un mensaje, nunca datos fabricados.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { Yo } from '@/lib/tipos'

let yo: Pick<Yo, 'id' | 'rol' | 'demo' | 'nombre_completo'> | null
const RECIBIDO = vi.hoisted(() => ({ props: null as Record<string, unknown> | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-19T18:00:00Z') }))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({
  RegistroActividad: (props: Record<string, unknown>) => { RECIBIDO.props = props; return <section aria-label="Registro (mock)" /> },
}))
vi.mock('@/screens/gestion-diaria/analista', () => ({
  GestionDiariaAnalista: ({ accesoSeguimiento }: { accesoSeguimiento?: import('react').ReactNode }) => <section aria-label="Mi día (mock)">{accesoSeguimiento}</section>,
}))
vi.mock('@/screens/gestion-diaria/supervisor', () => ({
  GestionDiariaSupervisor: () => <section aria-label="Mi equipo hoy (mock)" />,
}))
vi.mock('@/screens/gestion-diaria/gerencia', () => ({
  GestionDiariaGerencia: () => <section aria-label="Toda la operación (mock)" />,
}))
vi.mock('@/components/app/cola-seguimiento', () => ({
  ColaSeguimiento: () => <section aria-label="Cola completa (mock)"><input aria-label="Filtro conservado" defaultValue="" /></section>,
}))
const { GestionDiaria } = await import('./gestion-diaria')

beforeEach(() => { yo = { id: 'u1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }; RECIBIDO.props = null; window.history.replaceState(null, '', '#/gestion-diaria') })

describe('GestionDiaria por rol', () => {
  it('analista: «Mi día» con «Seguimiento completo» en su cabecera; el registro ya no vive fuera', () => {
    render(<GestionDiaria />)
    const miDia = screen.getByLabelText('Mi día (mock)')
    // Un solo acceso en la cabecera, como el «Mi Hoy completo ›» del diseño.
    expect(within(miDia).getByRole('link', { name: /Seguimiento completo/ })).toHaveAttribute('href', expect.stringContaining('cola'))
    expect(screen.queryByRole('link', { name: 'Resumen del día' })).not.toBeInTheDocument()
    // El registro del analista vive en la pestaña «Mi actividad» de «Mi día».
    expect(screen.queryByRole('heading', { name: /¿Qué hice hoy\?/ })).not.toBeInTheDocument()
    expect(RECIBIDO.props).toBeNull()
  })
  it('supervisor: su equipo (la RLS recorta), con filtro de analista y sin exportación', () => {
    yo = { id: 'u-sup', rol: 'supervisor', demo: false, nombre_completo: 'SUP' }
    render(<GestionDiaria />)
    expect(screen.getByLabelText('Mi equipo hoy (mock)')).toBeInTheDocument()
    // «Mi día» es del analista: el supervisor lo recibe en la Fase 4.
    expect(screen.queryByLabelText('Mi día (mock)')).not.toBeInTheDocument()
    expect(RECIBIDO.props).toBeNull()
    expect(screen.queryByLabelText('Día del registro')).not.toBeInTheDocument()
  })
  it('gerencia real abre el tablero de operación completo', () => {
    yo = { id: 'u-ger', rol: 'gerencia', demo: false, nombre_completo: 'GER' }
    render(<GestionDiaria />)
    expect(screen.getByLabelText('Toda la operación (mock)')).toBeInTheDocument()
    expect(RECIBIDO.props).toBeNull()
  })
  it('gerencia demo abre el MISMO tablero con la operación de ejemplo (G0), no el registro suelto', () => {
    yo = { id: 'd-ger', rol: 'gerencia', demo: true, nombre_completo: 'GERENCIA DEMO' }
    render(<GestionDiaria />)
    expect(screen.getByLabelText('Toda la operación (mock)')).toBeInTheDocument()
    expect(screen.queryByLabelText('Día del registro')).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Resumen del día' })).not.toBeInTheDocument()
    expect(RECIBIDO.props).toBeNull()
  })
  it('un rol que no entra recibe un mensaje y no se monta el registro', () => {
    yo = { id: 'u-dir', rol: 'directorio', demo: false, nombre_completo: 'DIR' }
    render(<GestionDiaria />)
    expect(screen.getByText(/no está disponible para tu rol/)).toBeInTheDocument()
    expect(RECIBIDO.props).toBeNull()
  })

  it.each(['vendedor', 'supervisor', 'gerencia'] as const)('%s accede a la cola actual por enlace sin montar las consultas del resumen', (rol) => {
    yo = { id: 'actor', rol, demo: false, nombre_completo: 'ACTOR' }
    window.history.replaceState(null, '', '#/gestion-diaria/cola')
    render(<GestionDiaria />)
    expect(screen.getByRole('region', { name: 'Cola completa (mock)' })).toBeVisible()
    expect(screen.getByRole('link', { name: 'Seguimiento completo' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByText(/La fecha del resumen no cambia esta cola/)).toBeVisible()
    expect(screen.queryByLabelText('Mi día (mock)')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Mi equipo hoy (mock)')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Toda la operación (mock)')).not.toBeInTheDocument()
    expect(RECIBIDO.props).toBeNull()
  })

  it.each(['directorio', 'coordinador'] as const)('un enlace a la cola no concede acceso a %s', (rol) => {
    yo = { id: 'actor', rol, demo: false, nombre_completo: 'ACTOR' }
    window.history.replaceState(null, '', '#/gestion-diaria/cola/lead/l1')
    render(<GestionDiaria />)
    expect(screen.queryByLabelText('Cola completa (mock)')).not.toBeInTheDocument()
    expect(screen.getByText(/no está disponible para tu rol/)).toBeVisible()
  })

  it('abrir/cerrar ficha conserva la cola; cambiar de actor o perder sesión retira su estado', () => {
    window.history.replaceState(null, '', '#/gestion-diaria/cola')
    const vista = render(<GestionDiaria />)
    fireEvent.change(screen.getByLabelText('Filtro conservado'), { target: { value: 'mi selección' } })
    for (const hash of ['#/gestion-diaria/cola/lead/l1', '#/gestion-diaria/cola']) {
      window.history.replaceState(null, '', hash)
      fireEvent(window, new HashChangeEvent('hashchange'))
      expect(screen.getByLabelText('Filtro conservado')).toHaveValue('mi selección')
    }
    yo = { ...yo!, id: 'otro-actor' }
    vista.rerender(<GestionDiaria />)
    expect(screen.getByLabelText('Filtro conservado')).toHaveValue('')
    yo = null
    vista.rerender(<GestionDiaria />)
    expect(screen.queryByLabelText('Cola completa (mock)')).not.toBeInTheDocument()
    expect(screen.getByText('Sin sesión')).toBeVisible()
  })
})
