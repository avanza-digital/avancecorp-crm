// G0: la gerencia demo entra a «Toda la operación» con la operación de ejemplo
// del store. A diferencia de gerencia.test.tsx, aquí las consultas son las
// REALES en su rama demo: se prueba el camino completo sin red.
import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { Yo } from '@/lib/tipos'

const d = vi.hoisted(() => ({ yo: null as Yo | null, store: {}, rpc: vi.fn() }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: d.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-24T17:00:00Z') }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => d.store }))
vi.mock('@/data/gestion-diaria-pulso-api', () => ({ obtenerPulsoGerencia: d.rpc, obtenerHabitosGerencia: d.rpc }))
vi.mock('@/data/gestion-diaria-api', () => ({ obtenerDiaEquipo: d.rpc }))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({
  RegistroActividad: (p: { dia: string; analistaIds: readonly string[] | null }) => <div data-testid="registro">{p.dia}:{JSON.stringify(p.analistaIds)}</div>,
}))
// El mundo demo se siembra relativo al reloj: el mismo instante que `useAhora`.
vi.useFakeTimers()
vi.setSystemTime(Date.parse('2026-09-24T17:00:00Z'))
const demo = await import('@/lib/demo')
vi.useRealTimers()
d.store = { equipo: demo.EQUIPO_DEMO, ambito: { leads: demo.LEADS_DEMO }, actividadesDelAmbito: demo.ACTIVIDADES_DEMO, tareas: demo.TAREAS_DEMO }
const { GestionDiariaGerencia } = await import('./gerencia')

let cliente: QueryClient
const montar = () => render(<GestionDiariaGerencia />, { wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider> })
beforeEach(() => {
  cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  d.yo = { id: 'd-ger', rol: 'gerencia', demo: true, nombre_completo: 'GERENCIA DEMO' } as Yo
  sessionStorage.clear(); history.replaceState(null, '', '#/gestion-diaria')
})

describe('Gerencia en modo demo (G0)', () => {
  it('entra al tablero con los equipos y los pendientes de ejemplo, sin pedir nada al servidor', () => {
    montar()
    const vista = screen.getByRole('region', { name: 'Toda la operación' })
    expect(screen.queryByText(/requiere una sesión de gerencia/)).not.toBeInTheDocument()
    expect(within(vista).getByRole('region', { name: 'Indicadores de la operación' })).toBeInTheDocument()
    for (const equipo of ['SUPERVISOR UNO', 'SUPERVISOR DOS', 'Fuera de equipos comerciales']) {
      expect(within(vista).getByRole('link', { name: equipo })).toBeInTheDocument()
    }
    expect(vista).toHaveTextContent('1 tareas vencidas')
    expect(d.rpc).not.toHaveBeenCalled()
  })
  it('abre un equipo por URL con sus analistas del detalle demo, y el registro recibe sus ids', () => {
    history.replaceState(null, '', '#/gestion-diaria/equipo/d-sup1')
    montar()
    const tabla = screen.getByRole('region', { name: 'Analistas del equipo' })
    expect(within(tabla).getAllByRole('button', { name: /^Seleccionar a / }).map((b) => b.getAttribute('aria-label')).toSorted())
      .toEqual(['Seleccionar a ANALISTA DOS', 'Seleccionar a ANALISTA UNO'])
    const panel = screen.getByRole('region', { name: 'Detalle de la operación' })
    fireEvent.click(within(panel).getByRole('button', { name: 'Ver registro del equipo' }))
    expect(within(panel).getByTestId('registro')).toHaveTextContent('2026-09-24:["d-v1","d-v2"]')
    expect(d.rpc).not.toHaveBeenCalled()
  })
  it('los hábitos de ejemplo listan a los tres analistas del organigrama', () => {
    montar()
    fireEvent.click(screen.getByRole('tab', { name: 'Hábitos del equipo' }))
    const tabla = screen.getByRole('table', { name: 'Comparación de hábitos por analista' })
    expect(within(tabla).getAllByRole('button', { name: /^Ver hábitos de / })).toHaveLength(3)
    expect(d.rpc).not.toHaveBeenCalled()
  })
  it('el guardia sigue bloqueando a otro rol, aunque sea demo', () => {
    d.yo = { id: 'd-sup1', rol: 'supervisor', demo: true, nombre_completo: 'SUPERVISOR UNO' } as Yo
    montar()
    expect(screen.getByRole('alert')).toHaveTextContent('requiere una sesión de gerencia')
    expect(screen.queryByRole('region', { name: 'Toda la operación' })).not.toBeInTheDocument()
  })
})
