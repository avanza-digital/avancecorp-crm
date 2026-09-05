import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { FilaAltasAnalista } from '@/lib/metricas'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  habilitada: undefined as boolean | undefined,
  meses: undefined as number | undefined,
  refetch: vi.fn(),
  yo: { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: false } as {
    id: string
    rol: string
    demo: boolean
  },
}))

vi.mock('@/data/crm-queries', () => ({
  useAltasNuevasPorAnalista: (habilitada: boolean, meses: number) => {
    dobles.habilitada = habilitada
    dobles.meses = meses
    return { refetch: dobles.refetch, ...dobles.consulta }
  },
}))

// Sesión real por defecto: el panel se apaga solo en demo, desde dentro.
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

const { AltasNuevasAnalistaPanel } = await import('./altas-nuevas-analista')

const FILAS: FilaAltasAnalista[] = [
  { mes: '2026-08-01', analista_id: 'a-ana', analista_nombre: 'Ana Torres', altas: 5 },
  { mes: '2026-09-01', analista_id: 'a-ana', analista_nombre: 'Ana Torres', altas: 2 },
  { mes: '2026-09-01', analista_id: 'a-luis', analista_nombre: 'Luis Paredes', altas: 4 },
  // Un contrato sin analista de cierre: solo lo ve gerencia, como fila propia.
  { mes: '2026-07-01', analista_id: 'sin-analista', analista_nombre: 'Sin analista', altas: 1 },
]

function ok(data: FilaAltasAnalista[]) {
  return { data, isPending: false, isError: false }
}

beforeEach(() => {
  dobles.consulta = ok(FILAS)
  dobles.habilitada = undefined
  dobles.meses = undefined
  dobles.refetch.mockReset()
  dobles.yo = { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: false }
})

describe('AltasNuevasAnalistaPanel', () => {
  // ESTADO DE PRODUCCIÓN (regla gate:realidad): el mundo real puede llegar
  // VACÍO (sin contratos nuevos en el horizonte). El panel debe consultar de
  // verdad y mostrar un vacío honesto y accionable, jamás cifras inventadas.
  it('ESTADO DE PRODUCCIÓN: sin altas en el horizonte → vacío honesto, con la RPC habilitada', () => {
    dobles.consulta = ok([])
    render(<AltasNuevasAnalistaPanel />)

    expect(dobles.habilitada).toBe(true)
    expect(dobles.meses).toBe(6) // horizonte inicial
    expect(screen.getByText('Sin altas nuevas en los últimos 6 meses')).toBeInTheDocument()
    expect(screen.getByText(/renovaciones y upgrades no cuentan/i)).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: /ranking/i })).not.toBeInTheDocument()
    expect(screen.queryByText(/\d+ altas?$/)).not.toBeInTheDocument()
  })

  it('con datos: ranking descendente sumando meses, total del período y la fila "Sin analista"', () => {
    render(<AltasNuevasAnalistaPanel />)

    const items = screen.getAllByRole('listitem')
    // Ana 5+2=7 > Luis 4 > Sin analista 1
    expect(items.map((li) => li.textContent)).toEqual([
      expect.stringMatching(/^1Ana Torres7 altas$/),
      expect.stringMatching(/^2Luis Paredes4 altas$/),
      expect.stringMatching(/^3Sin analista1 alta$/),
    ])
    expect(screen.getByText('12 altas')).toBeInTheDocument()
    expect(screen.getByText(/los cierres anulados se excluyen/i)).toBeInTheDocument()
  })

  it('un total de 1 se escribe en singular', () => {
    dobles.consulta = ok([FILAS[3]!])
    render(<AltasNuevasAnalistaPanel />)
    expect(screen.getByText('1 alta')).toBeInTheDocument()
  })

  it('cargando (sin datos previos): skeleton, sin ranking', () => {
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    const { container } = render(<AltasNuevasAnalistaPanel />)
    expect(container.querySelector('[aria-busy]')).not.toBeNull()
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
  })

  it('un refetch con datos previos NO vuelve al skeleton (conserva la cifra)', () => {
    dobles.consulta = { data: FILAS, isPending: true, isError: false }
    render(<AltasNuevasAnalistaPanel />)
    expect(screen.getByRole('list', { name: /ranking/i })).toBeInTheDocument()
  })

  it('error: mensaje y Reintentar dispara refetch', () => {
    dobles.consulta = { data: undefined, isPending: false, isError: true }
    render(<AltasNuevasAnalistaPanel />)
    // El mensaje va visible Y en la región viva (role=status): dos apariciones.
    expect(screen.getAllByText(/No se pudieron cargar las altas/).length).toBeGreaterThanOrEqual(1)
    expect(screen.getByRole('status')).toHaveTextContent('No se pudieron cargar las altas')
    fireEvent.click(screen.getByRole('button', { name: /reintentar/i }))
    expect(dobles.refetch).toHaveBeenCalledTimes(1)
  })

  it('el selector de horizonte re-consulta con los meses elegidos', () => {
    render(<AltasNuevasAnalistaPanel />)
    const doce = screen.getByRole('button', { name: '12 meses' })
    fireEvent.click(doce)
    expect(dobles.meses).toBe(12)
    expect(doce).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: '6 meses' })).toHaveAttribute('aria-pressed', 'false')
  })

  it('la región viva (role=status) anuncia el resultado del horizonte', () => {
    render(<AltasNuevasAnalistaPanel />)
    expect(screen.getByRole('status')).toHaveTextContent('12 altas en los últimos 6 meses')
  })

  it('en DEMO la RPC queda inerte (enabled=false): ningún request sale', () => {
    dobles.yo = { ...dobles.yo, demo: true }
    render(<AltasNuevasAnalistaPanel />)
    expect(dobles.habilitada).toBe(false)
  })
})
