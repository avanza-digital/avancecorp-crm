import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { useDatosCitas } from '@/components/citas/contexto'
import { CitasGerencia } from './citas-gerencia'

// El proveedor de Citas: con sesión real la Proyección SIEMPRE recibe su cargador, aunque aún no haya pedido
// sus meses (Codex, 19/10: sin él se pintaban un instante solo las citas del mes, sin las reuniones con clientes).
const sesion = vi.hoisted(() => ({ demo: false }))
const cargador = { meses: [], rango: null, citas: [], reunionesClientes: [], gestion: undefined, corte: '', cargando: true, error: null, onReintentar: () => {} }
vi.mock('./use-datos-citas-gerencia', () => ({
  useDatosCitasGerencia: () => ({ yo: { id: 'g', rol: 'gerencia', demo: sesion.demo }, ahora: Date.parse('2026-10-19T17:00:00Z'), datos: undefined, citas: [],
    consulta: { isPending: false, isError: false, error: null, refetch: vi.fn() } }),
  useDatosProyeccionCitas: () => cargador,
}))
vi.mock('@/lib/store-context', () => ({ usePanelesActions: () => ({ abrirLead: vi.fn() }) }))
vi.mock('@/components/gerencia/use-consulta-gerencia', () => ({ useConsultaGerencia: () => null }))
vi.mock('@/components/citas/citas-clientes', () => ({ CitasClientes: () => null }))
vi.mock('@/components/citas/propuesta', () => ({
  TableroCitas: () => { const datos = useDatosCitas(); return <p data-testid="cargador">{datos.proyeccion ? 'con cargador' : 'sin cargador'}</p> },
}))

afterEach(() => { cleanup(); sesion.demo = false })

describe('CitasGerencia: cargador de la Proyección', () => {
  it('con sesión real lo entrega aunque la Proyección aún no haya pedido meses; en demostración no', () => {
    render(<CitasGerencia />)
    expect(screen.getByTestId('cargador')).toHaveTextContent('con cargador')
    cleanup()
    sesion.demo = true
    render(<CitasGerencia />)
    expect(screen.getByTestId('cargador')).toHaveTextContent('sin cargador')
  })
})
