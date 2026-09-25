import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import * as v from 'valibot'
import fixture from '@/lib/gestion-diaria-f5.test.fixture.json'
import { PulsoGerenciaSchema } from '@/lib/gestion-diaria-pulso'
import { HabitosGerenciaSchema } from '@/lib/gestion-diaria-habitos'
import { DiaEquipoSchema } from '@/lib/gestion-diaria-equipo'
import { CrmApiError } from '@/data/crm-api'
import type { Yo } from '@/lib/tipos'

const recargar = vi.fn(async () => {})
const estado = <T,>(datos: T | null) => ({ datos, cargando: false, enVuelo: false, error: null as unknown, recargar })
let yo: Yo, pulso = estado(v.parse(PulsoGerenciaSchema, fixture.pulso)), habitos = estado(v.parse(HabitosGerenciaSchema, fixture.habitos)), detalle = estado(v.parse(DiaEquipoSchema, fixture.equipo))
const pedidos: string[] = [], periodos: number[] = []
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-24T17:00:00Z') }))
vi.mock('@/data/gestion-diaria-pulso-queries', () => ({
  usePulsoGerencia: (dia: string) => { pedidos.push(dia); return pulso },
  useHabitosGerencia: (_dia: string, dias: number) => { periodos.push(dias); return habitos }, useDetallePulso: () => detalle,
}))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({ RegistroActividad: (p: { dia: string; analistaIds: string[] | null }) => <div data-testid="registro">{p.dia}:{JSON.stringify(p.analistaIds)}</div> }))
const { GestionDiariaGerencia } = await import('./gerencia')
beforeEach(() => {
  yo = { id: 'g1', rol: 'gerencia', demo: false } as Yo
  sessionStorage.clear(); history.replaceState(null, '', '#/gestion-diaria')
  pulso = estado(v.parse(PulsoGerenciaSchema, fixture.pulso)); habitos = estado(v.parse(HabitosGerenciaSchema, fixture.habitos)); detalle = estado(v.parse(DiaEquipoSchema, fixture.equipo))
  pedidos.length = 0; periodos.length = 0; recargar.mockClear()
})
const ruta = (hash: string) => act(() => { history.replaceState(null, '', hash); window.dispatchEvent(new HashChangeEvent('hashchange')) })
describe('Gerencia F5', () => {
  it('muestra comparación explícita, pendientes actuales y fila de cuadre', () => {
    render(<GestionDiariaGerencia />)
    expect(screen.getByRole('region', { name: 'Indicadores de la operación' })).toHaveTextContent('2026-09-22 completo')
    expect(screen.getByRole('region', { name: 'Equipos de la operación' })).toHaveTextContent('1008 tareas vencidas')
    expect(screen.getByRole('link', { name: 'Fuera de equipos comerciales' })).toBeInTheDocument()
  })
  it('recuerda la fecha por actor y conserva la última válida al introducir otra imposible', () => {
    const { rerender } = render(<GestionDiariaGerencia />)
    const input = screen.getByLabelText('Día de la operación')
    fireEvent.change(input, { target: { value: '2026-09-10' } })
    expect(pedidos.at(-1)).toBe('2026-09-24')
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(pedidos.at(-1)).toBe('2026-09-10')
    fireEvent.change(input, { target: { value: '2026-12-01' } }); fireEvent.keyDown(input, { key: 'Enter' })
    expect(input).toHaveValue('2026-09-10'); expect(screen.getByRole('alert')).toHaveTextContent('fecha válida')
    yo = { ...yo, id: 'g2' }; rerender(<GestionDiariaGerencia />)
    expect(screen.getByLabelText('Día de la operación')).toHaveValue('2026-09-24')
    yo = { ...yo, id: 'g1' }; rerender(<GestionDiariaGerencia />)
    expect(screen.getByLabelText('Día de la operación')).toHaveValue('2026-09-10')
    fireEvent.click(screen.getByRole('button', { name: 'Hoy' }))
    expect(pedidos.at(-1)).toBe('2026-09-24')
  })
  it('editar la fecha con un detalle abierto sólo consulta al confirmar y conserva el foco tras recargar', () => {
    const e = pulso.datos!.equipos.find((g) => g.metricas.llamadas === 4)!
    ruta(`#/gestion-diaria/equipo/${e.clave}`)
    const { rerender } = render(<GestionDiariaGerencia />)
    const input = screen.getByLabelText('Día de la operación')
    input.focus()
    fireEvent.change(input, { target: { value: '2026-09-22' } })
    expect(pedidos.at(-1)).toBe('2026-09-24')
    fireEvent.keyDown(input, { key: 'Enter' })
    expect(pedidos.at(-1)).toBe('2026-09-22')
    expect(input).toHaveFocus()
    const previa = pulso
    pulso = { ...pulso, datos: null!, cargando: true }; rerender(<GestionDiariaGerencia />)
    pulso = previa; rerender(<GestionDiariaGerencia />)
    expect(input).toHaveFocus()
  })
  it('abre un equipo por URL, sólo muestra sus analistas y permite buscar sin perder el día', () => {
    const e = pulso.datos!.equipos.find((g) => g.metricas.llamadas === 4)!
    ruta(`#/gestion-diaria/equipo/${e.clave}`)
    render(<GestionDiariaGerencia />)
    const panel = screen.getByRole('region', { name: 'Detalle de la operación' })
    expect(within(panel).getByRole('heading', { name: e.nombre })).toHaveFocus()
    expect(within(panel).getAllByRole('button', { name: /^Seleccionar a / })).toHaveLength(e.metricas.analistas_activos)
    fireEvent.change(within(panel).getByRole('searchbox'), { target: { value: 'No existe' } })
    expect(within(panel).queryAllByRole('button', { name: /^Seleccionar a / })).toHaveLength(0)
  })
  it('enlace a analista conserva su registro al abrir una ficha y oculta identidades ausentes', () => {
    const p = pulso.datos!.equipos.flatMap((e) => e.personas).find((p) => p.activo && p.llamadas === 4)!
    ruta(`#/gestion-diaria/analista/${p.analista_id}`)
    render(<GestionDiariaGerencia />)
    const panel = screen.getByRole('region', { name: 'Detalle de la operación' })
    expect(within(panel).getByTestId('registro')).toHaveTextContent(JSON.stringify([p.analista_id]))
    ruta(`#/gestion-diaria/analista/${p.analista_id}/lead/otro`)
    expect(within(panel).getByTestId('registro')).toBeInTheDocument()
    ruta('#/gestion-diaria/analista/00000000-0000-4000-8000-000000000000')
    expect(screen.getByRole('status')).toHaveTextContent('ya no aparece')
  })
  it('un error de refresco no conserva las cifras ni el registro; ofrece reintentar', () => {
    const { rerender } = render(<GestionDiariaGerencia />)
    pulso = { ...pulso, datos: null!, error: new Error('sin red') }
    rerender(<GestionDiariaGerencia />)
    expect(screen.getByRole('alert')).toHaveTextContent('datos anteriores se han ocultado')
    expect(screen.queryByRole('table', { name: 'Resumen por supervisor' })).not.toBeInTheDocument()
    expect(screen.queryByTestId('registro')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' })); expect(recargar).toHaveBeenCalledOnce()
  })
  it('una denegación en el detalle también oculta el pulso de gerencia', () => {
    ruta(`#/gestion-diaria/equipo/${pulso.datos!.equipos[0]!.clave}`)
    detalle = { ...detalle, error: new CrmApiError('Revocado', '42501') }
    render(<GestionDiariaGerencia />)
    expect(screen.getByRole('alert')).toHaveTextContent('ya no tiene permiso')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
  it('hábitos identifica período, distribución y hueco con horario; cambiar ventana consulta de nuevo', () => {
    render(<GestionDiariaGerencia />)
    fireEvent.click(screen.getByRole('tab', { name: 'Hábitos del equipo' }))
    const informe = screen.getByRole('region', { name: 'Reporte de hábitos' })
    expect(informe).toHaveTextContent('La alerta de tasa muy baja sigue apagada')
    expect(informe).toHaveTextContent('165 min')
    fireEvent.change(screen.getByLabelText(/Período hasta/), { target: { value: '30' } })
    expect(periodos.at(-1)).toBe(30)
  })
  it('el guard no monta consultas ni registro para otro rol', () => {
    yo = { ...yo, rol: 'supervisor' }; render(<GestionDiariaGerencia />)
    expect(screen.getByRole('alert')).toHaveTextContent('requiere una sesión de gerencia')
    expect(pedidos).toHaveLength(0)
  })
})
