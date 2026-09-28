// G4b: la lista exacta de citas agendadas. Filas limpias (hora de agenda, estado, lead que
// abre su ficha, analista cuando hay varios, cuándo es la cita) y estados que se dicen.
import { createRef } from 'react'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { CitaAgendada } from '@/lib/gestion-diaria-citas'
import { CrmApiError } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({ lista: {} as Record<string, unknown>, abrirLead: vi.fn() }))
vi.mock('@/data/gestion-diaria-citas-queries', () => ({ useCitasGestion: () => dobles.lista }))
vi.mock('@/lib/store-context', () => ({ usePanelesActions: () => ({ abrirLead: dobles.abrirLead }) }))
const { CitasAgendadas } = await import('./citas-agendadas')

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const cita = (n: number, extra: Partial<CitaAgendada> = {}): CitaAgendada => ({
  id: id(n), vendedor_id: id(90), vendedor_nombre: 'ANALISTA UNO', lead_id: id(200 + n), lead_nombre: `LEAD ${n}`,
  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', creado_en: '2026-09-24T19:32:00.000Z', ...extra,
})
const base = { items: [] as CitaAgendada[], total: 0, consultadoEn: '2026-09-24T22:00:00.000Z', cargando: false, enVuelo: false,
  error: null as unknown, sinPermiso: false, hayMas: false, cargarMas: vi.fn(), recargar: vi.fn() }
function montar(extra: Partial<typeof base>, mostrarAnalista = true) {
  dobles.lista = { ...base, ...extra }
  const revalidar = vi.fn()
  render(<CitasAgendadas dia="2026-09-24" esHoy ambito="operacion" id={null} mostrarAnalista={mostrarAnalista} visible actualizacion={0}
    revalidar={revalidar} encabezado={createRef<HTMLHeadingElement>()} />)
  return { revalidar }
}
beforeEach(() => { vi.clearAllMocks() })

describe('CitasAgendadas', () => {
  it('cada fila: hora de agenda, estado, lead que abre su ficha, analista y cuándo es la cita', () => {
    montar({ items: [cita(1), cita(2, { estado: 'no_show', lead_id: null, lead_nombre: null, vendedor_nombre: null }), cita(3, { estado: 'reprogramada' })], total: 3 })
    expect(screen.getByRole('status')).toHaveTextContent('3 citas agendadas hoy')
    const filas = within(screen.getByRole('list', { name: 'Citas agendadas' })).getAllByRole('listitem')
    expect(filas).toHaveLength(3)
    expect(filas[2]).toHaveTextContent('Reprogramada')
    expect(filas[0]).toHaveTextContent('Agendada a las 14:32')
    expect(filas[0]).toHaveTextContent('Pendiente')
    expect(filas[0]).toHaveTextContent('· ANALISTA UNO')
    expect(filas[0]).toHaveTextContent(/Cita: .*10:00/)
    fireEvent.click(within(filas[0]!).getByRole('button', { name: 'LEAD 1' }))
    expect(dobles.abrirLead).toHaveBeenCalledWith(id(201))
    expect(filas[1]).toHaveTextContent('No asistió')
    expect(filas[1]).toHaveTextContent('Lead no visible')
    expect(filas[1]).toHaveTextContent('Sin analista')
  })
  it('en la ficha de un analista no repite su nombre en cada fila', () => {
    montar({ items: [cita(1)], total: 1 }, false)
    expect(screen.getByRole('listitem')).not.toHaveTextContent('ANALISTA UNO')
    expect(screen.getByRole('status')).toHaveTextContent('1 cita agendada hoy')
  })
  it('cero es una lista vacía que se dice, no un error', () => {
    montar({ total: 0 })
    expect(screen.getByRole('status')).toHaveTextContent('Ninguna cita agendada hoy.')
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
  })
  it('un error sin filas no se presenta como «ninguna cita» y ofrece reintentar', () => {
    const recargar = vi.fn()
    montar({ error: new Error('sin red'), total: null as unknown as number, recargar })
    expect(screen.getByRole('alert')).toHaveTextContent('Esto no significa que no haya citas')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(recargar).toHaveBeenCalledOnce()
  })
  it('sin permiso retira la lista y avisa a la pantalla', () => {
    const { revalidar } = montar({ sinPermiso: true, error: new CrmApiError('revocado', '42501') })
    expect(screen.getByRole('alert')).toHaveTextContent('Ya no tienes autorización')
    expect(revalidar).toHaveBeenCalledOnce()
  })
  it('«Ver más» pide la página siguiente', () => {
    const cargarMas = vi.fn()
    montar({ items: [cita(1)], total: 30, hayMas: true, cargarMas })
    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
    expect(cargarMas).toHaveBeenCalledOnce()
  })
})
