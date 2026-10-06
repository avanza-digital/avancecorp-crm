import { beforeEach, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { CrmApiError } from '@/data/crm-api'
const d = vi.hoisted(() => ({ data: null as unknown, error: false, recargar: vi.fn(), pedido: vi.fn() }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'actor', rol: 'supervisor', demo: false } }) }))
vi.mock('@/data/gestiones-clientes', () => ({ useResumenGestiones: () => ({ data: d.data, isError: d.error, refetch: d.recargar }) }))
vi.mock('./registro-actividad', () => ({ RegistroActividad: (p: unknown) => { d.pedido(p); return <div>Registro consultado</div> } }))
import { ResumenGestionesClientes } from './resumen-gestiones'
const cero = { gestiones: 0, llamadas: 0, contestadas: 0, entrevistas: 0, ultima_llamada_en: null }
const cliente = { ...cero, gestiones: 4, llamadas: 3, contestadas: 2, entrevistas: 1 }
const metricas = { leads: cero, clientes: cliente, total: cliente }
beforeEach(() => { vi.clearAllMocks(); d.error = false; d.data = { totales: metricas, analistas: [{ id: 'analista', nombre: 'ANA', metricas }] } })
it('el superior ve el desglose y abre las gestiones del autor seleccionado', () => {
  render(<ResumenGestionesClientes dia="2026-10-05" />)
  expect(within(screen.getByRole('row', { name: /Clientes/ })).getAllByRole('cell').map(c => c.textContent)).toEqual(['3', '2', '1', '4'])
  fireEvent.click(screen.getByText('Ver actividad por analista'))
  fireEvent.click(screen.getByRole('button', { name: 'ANA' }))
  expect(d.pedido).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-10-05', analistaIds: ['analista'], pestanaInicial: 'todo' }))
})
it('un error posterior retira los datos anteriores y el registro abierto', () => {
  const r = render(<ResumenGestionesClientes dia="2026-10-05" />)
  fireEvent.click(screen.getByRole('button', { name: 'Ver gestiones' }))
  d.error = Boolean(new CrmApiError('Revocado', '42501'))
  r.rerender(<ResumenGestionesClientes dia="2026-10-05" />)
  expect(screen.queryByRole('table')).not.toBeInTheDocument()
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  expect(screen.getByRole('alert')).toHaveTextContent('No se pudo consultar')
})
