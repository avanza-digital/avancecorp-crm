import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import type { Yo } from '@/lib/tipos'

const ESTADO = vi.hoisted(() => ({ modo: 'activo' as 'activo' | 'legado' | 'cargando' | 'error', refetch: vi.fn() }))
let yo: Pick<Yo, 'id' | 'rol' | 'demo'>
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo }) }))
vi.mock('@/data/sla-operacion-queries', () => ({
  useModoSla: () => ({ legado: ESTADO.modo === 'legado', activo: ESTADO.modo === 'activo',
    error: ESTADO.modo === 'error' ? Error('Sin conexión') : null, refetch: ESTADO.refetch }),
}))
vi.mock('@/components/app/sla-operacion', async (original) => ({
  ...(await original<typeof import('@/components/app/sla-operacion')>()),
  ColaSlaPanel: () => <section aria-label="Cola operativa del servidor" />,
}))
const { Seguimiento } = await import('./seguimiento')

beforeEach(() => {
  yo = { id: 'actor', rol: 'gerencia', demo: false }
  ESTADO.modo = 'activo'
  vi.clearAllMocks()
})

describe('Seguimiento como módulo operativo', () => {
  it('monta la cola activa sin necesitar el contexto de período de Gerencia', () => {
    render(<Seguimiento />)
    expect(screen.getByRole('region', { name: 'Cola operativa del servidor' })).toBeInTheDocument()
    expect(screen.queryByLabelText('Desde')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Hasta')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Origen del lead')).not.toBeInTheDocument()
  })

  it('explica el modo legado confirmado sin fabricar una cola ni afirmar que está al día', () => {
    ESTADO.modo = 'legado'
    render(<Seguimiento />)
    expect(screen.getByRole('status')).toHaveTextContent('El seguimiento comercial no está activo.')
    expect(screen.queryByRole('region', { name: 'Cola operativa del servidor' })).not.toBeInTheDocument()
  })

  it('explica la disponibilidad del módulo en demo', () => {
    ESTADO.modo = 'legado'
    yo.demo = true
    render(<Seguimiento />)
    expect(screen.getByRole('status')).toHaveTextContent('disponible en la sesión real')
  })

  it('mantiene la consulta y el error separados de un modo desactivado', () => {
    ESTADO.modo = 'cargando'
    const vista = render(<Seguimiento />)
    expect(screen.getByRole('status')).toHaveTextContent('Consultando el seguimiento comercial')
    ESTADO.modo = 'error'
    vista.rerender(<Seguimiento />)
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo cargar el seguimiento')
    expect(screen.queryByText('El seguimiento comercial no está activo.')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(ESTADO.refetch).toHaveBeenCalledOnce()
  })
})
