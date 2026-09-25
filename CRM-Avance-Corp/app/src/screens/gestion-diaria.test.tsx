// La pantalla enruta por rol como Hoy: el analista abre con «Mi día» (Fase 3) y
// conserva SU registro debajo (su id viaja al componente), el supervisor ve su
// equipo con filtro de analista, y gerencia además elige el día y exporta. Los
// roles que no entran reciben un mensaje, nunca datos fabricados.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import type { Yo } from '@/lib/tipos'

let yo: Pick<Yo, 'id' | 'rol' | 'demo' | 'nombre_completo'> | null
const RECIBIDO = vi.hoisted(() => ({ props: null as Record<string, unknown> | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-19T18:00:00Z') }))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({
  RegistroActividad: (props: Record<string, unknown>) => { RECIBIDO.props = props; return <section aria-label="Registro (mock)" /> },
}))
vi.mock('@/screens/gestion-diaria/analista', () => ({
  GestionDiariaAnalista: () => <section aria-label="Mi día (mock)" />,
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
  it('analista: «Mi día» primero y su propio registro debajo, sin filtro de analista ni exportación', () => {
    render(<GestionDiaria />)
    expect(screen.getByLabelText('Mi día (mock)')).toBeInTheDocument()
    // Densidad (20/09/2026): el registro propio es un plegable — su título es
    // el h3 del `summary` y lleva el resumen al lado; arranca cerrado.
    const registro = screen.getByRole('heading', { level: 3, name: /¿Qué hice hoy\?/ })
    expect(registro.closest('details')).not.toHaveAttribute('open')
    expect(RECIBIDO.props).toMatchObject({ dia: '2026-09-19', analistaIds: ['u1'], mostrarAnalista: false, permitirExportar: false })
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
  it('gerencia demo conserva el registro ficticio con fecha y exportación', () => {
    yo = { id: 'u-ger', rol: 'gerencia', demo: true, nombre_completo: 'GER' }
    render(<GestionDiaria />)
    expect(RECIBIDO.props).toMatchObject({ dia: '2026-09-19', analistaIds: null, mostrarAnalista: true, permitirEquipo: true, permitirExportar: true })
    const dia = screen.getByLabelText('Día del registro')
    expect(dia).toHaveAttribute('max', '2026-09-19')
    fireEvent.change(dia, { target: { value: '2026-09-18' } })
    expect(RECIBIDO.props).toMatchObject({ dia: '2026-09-18' })
    fireEvent.change(dia, { target: { value: '2026-12-31' } })
    expect(RECIBIDO.props).toMatchObject({ dia: '2026-09-19' })
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
