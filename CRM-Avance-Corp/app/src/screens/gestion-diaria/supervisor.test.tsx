import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { useState } from 'react'
import { diaEquipoPrueba, filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import { CrmApiError } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({ consulta: {} as DiaEquipoHook, recargar: vi.fn(), registro: vi.fn() }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 's1', rol: 'supervisor', demo: false } }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-21T15:00:00Z') }))
vi.mock('@/data/gestion-diaria-equipo-queries', () => ({ useDiaEquipo: () => dobles.consulta }))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({ RegistroActividad: (props: unknown) => {
  dobles.registro(props)
  const [pagina, setPagina] = useState(1)
  return <div><p>Registro cargado</p><button onClick={() => setPagina((p) => p + 1)}>Página {pagina}</button></div>
} }))
const { GestionDiariaSupervisor } = await import('./supervisor')
beforeEach(() => {
  vi.clearAllMocks()
  dobles.consulta = { dia: diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO',
    tareas_pendientes: 270, tareas_vencidas: 270, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })]),
  cargando: false, enVuelo: false, error: null, recargar: dobles.recargar }
})

describe('Supervisor — Mi equipo hoy', () => {
  it('muestra ceros, pendientes completos y el motivo, sin atribuir presencia', () => {
    render(<GestionDiariaSupervisor />)
    const tabla = screen.getByRole('table', { name: 'Actividad y pendientes por analista' })
    expect(within(tabla).getByText('ANA PÉREZ')).toBeVisible()
    expect(within(tabla).getAllByText('Sin actividad registrada hoy')).toHaveLength(2)
    expect(within(tabla).getByText('270 tareas pendientes')).toBeVisible()
    expect(within(tabla).getByText('Tareas vencidas')).toBeVisible()
    const cabecera = within(tabla).getByRole('rowheader', { name: /ANA PÉREZ/ })
    expect(cabecera).toHaveAttribute('scope', 'rowgroup')
    expect(cabecera.closest('tbody')).toHaveAttribute('aria-labelledby', cabecera.id)
    expect(cabecera.closest('tbody')?.querySelector('td[headers]')).toHaveAttribute('headers', cabecera.id)
    expect(screen.queryByText('Trabajando ahora')).not.toBeInTheDocument()
  })
  it('busca, filtra, distingue vacío de filtro y ordena con aria-sort', () => {
    render(<GestionDiariaSupervisor />)
    fireEvent.click(screen.getByRole('button', { name: /Con problema hoy/ }))
    expect(screen.queryByText('ANA PÉREZ')).not.toBeInTheDocument()
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'ana' } })
    expect(screen.getByText('Ningún analista coincide con estos filtros.')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /Con problema hoy/ }))
    expect(screen.getByText('ANA PÉREZ')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Ordenar por analista' }))
    expect(screen.getByRole('button', { name: 'Ordenar por analista' }).closest('th')).toHaveAttribute('aria-sort', 'ascending')
  })
  it('abre únicamente el registro seleccionado y permite cerrarlo', () => {
    render(<GestionDiariaSupervisor />)
    expect(dobles.registro).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: 'Ver registro de ANA PÉREZ' }))
    expect(screen.getByRole('heading', { name: 'Registro de ANA PÉREZ' })).toHaveFocus()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-21', analistaIds: ['a1'], permitirExportar: false, pestanaInicial: 'todo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar registro' }))
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it('el detalle horario abre llamadas de ese analista y se oculta si sale del equipo autorizado', () => {
    const vista = render(<GestionDiariaSupervisor />)
    const detalle = screen.getByText('Detalle de ANA PÉREZ').closest('details')!
    detalle.open = true
    fireEvent.click(within(detalle).getByRole('button', { name: 'Ver llamadas del día de ANA PÉREZ' }))
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
    dobles.consulta.dia = diaEquipoPrueba([filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO' })])
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Se cerró el registro')
  })
  it('reabrir la misma entrada reinicia filtros/páginas y aplica otra vez la pestaña solicitada', () => {
    render(<GestionDiariaSupervisor />)
    const abrir = screen.getByRole('button', { name: 'Ver registro de ANA PÉREZ' })
    fireEvent.click(abrir)
    fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
    expect(screen.getByRole('button', { name: 'Página 2' })).toBeVisible()
    fireEvent.click(abrir)
    expect(screen.getByRole('button', { name: 'Página 1' })).toBeVisible()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ pestanaInicial: 'todo' }))
  })
  it('un fallo del resumen no desmonta el registro ni roba foco al recuperarse', () => {
    const vista = render(<GestionDiariaSupervisor />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver registro de ANA PÉREZ' }))
    const pagina = screen.getByRole('button', { name: 'Página 1' })
    fireEvent.click(pagina)
    pagina.focus()
    dobles.consulta.error = new Error('Sin red')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    expect(pagina).toHaveFocus()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(pagina).toHaveFocus()
    expect(screen.getByRole('button', { name: 'Página 2' })).toBeVisible()
  })
  it('una revocación del resumen cierra el registro, devuelve foco y no lo reabre sola', () => {
    const vista = render(<GestionDiariaSupervisor />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver registro de ANA PÉREZ' }))
    screen.getByRole('button', { name: 'Página 1' }).focus()
    dobles.consulta.error = new CrmApiError('Revocado', '42501')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2 })).toHaveFocus()
    expect(screen.getByRole('status')).toHaveTextContent('Se cerró el registro')
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it('un error de refresco oculta la foto anterior, nunca presenta ceros', () => {
    dobles.consulta.error = new Error('red')
    render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('alert')).toHaveTextContent('no significa que el equipo no tenga actividad')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(dobles.recargar).toHaveBeenCalledOnce()
  })
  it('distingue acceso revocado de red y no ofrece un reintento engañoso', () => {
    dobles.consulta.error = new CrmApiError('Revocado', '42501')
    render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('alert')).toHaveTextContent('Ya no tienes autorización')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
  })
  it('distingue carga y equipo sin analistas de actividad cero', () => {
    dobles.consulta = { ...dobles.consulta, dia: null, cargando: true }
    const vista = render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('status')).toHaveTextContent('Consultando')
    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba([]), cargando: false }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByText('No tienes analistas activos asignados')).toBeVisible()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
})
