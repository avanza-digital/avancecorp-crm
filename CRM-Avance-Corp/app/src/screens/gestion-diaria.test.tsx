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
const { GestionDiaria } = await import('./gestion-diaria')

beforeEach(() => { yo = { id: 'u1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }; RECIBIDO.props = null })

describe('GestionDiaria por rol', () => {
  it('analista: «Mi día» primero y su propio registro debajo, sin filtro de analista ni exportación', () => {
    render(<GestionDiaria />)
    expect(screen.getByLabelText('Mi día (mock)')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2, name: '¿Qué hice hoy?' })).toBeInTheDocument()
    expect(RECIBIDO.props).toMatchObject({ dia: '2026-09-19', analistaIds: ['u1'], mostrarAnalista: false, permitirExportar: false })
  })
  it('supervisor: su equipo (la RLS recorta), con filtro de analista y sin exportación', () => {
    yo = { id: 'u-sup', rol: 'supervisor', demo: false, nombre_completo: 'SUP' }
    render(<GestionDiaria />)
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('mi equipo')
    // «Mi día» es del analista: el supervisor lo recibe en la Fase 4.
    expect(screen.queryByLabelText('Mi día (mock)')).not.toBeInTheDocument()
    expect(RECIBIDO.props).toMatchObject({ dia: '2026-09-19', analistaIds: null, mostrarAnalista: true, permitirExportar: false })
    expect(screen.queryByLabelText('Día del registro')).not.toBeInTheDocument()
  })
  it('gerencia: todo, exportable, y elige el día sin poder ir al futuro', () => {
    yo = { id: 'u-ger', rol: 'gerencia', demo: false, nombre_completo: 'GER' }
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
})
