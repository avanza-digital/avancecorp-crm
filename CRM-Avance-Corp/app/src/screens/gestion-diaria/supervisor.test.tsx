import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within, waitFor } from '@testing-library/react'
import { useState } from 'react'
import { diaEquipoPrueba, filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import type { AvisosGestionDiaria } from '@/lib/gestion-diaria-avisos-context'
import { CrmApiError } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({ consulta: {} as DiaEquipoHook, recargar: vi.fn(), registro: vi.fn(), yo: { id: 's1', rol: 'supervisor', demo: false }, avisos: null as AvisosGestionDiaria | null, ahora: Date.parse('2026-09-21T15:00:00Z') }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => dobles.ahora }))
vi.mock('@/data/gestion-diaria-equipo-queries', () => ({ useDiaEquipo: () => dobles.consulta }))
vi.mock('@/lib/gestion-diaria-avisos-context', () => ({ useGestionDiariaAvisos: () => dobles.avisos }))
vi.mock('@/components/gestion-diaria/avisos-equipo', () => ({ AvisosEquipo: () => <p>Avisos del equipo</p> }))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({ RegistroActividad: (props: unknown) => {
  dobles.registro(props)
  const [pagina, setPagina] = useState(1)
  return <div><p>Registro cargado</p><button onClick={() => setPagina((p) => p + 1)}>Página {pagina}</button></div>
} }))
const { GestionDiariaSupervisor } = await import('./supervisor')
const seleccionar = () => fireEvent.click(screen.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }))
const abrirRegistro = () => { seleccionar(); fireEvent.click(screen.getByRole('tab', { name: 'Registro' })) }
beforeEach(() => {
  vi.clearAllMocks()
  dobles.avisos = null
  dobles.yo = { id: 's1', rol: 'supervisor', demo: false }
  dobles.ahora = Date.parse('2026-09-21T15:00:00Z')
  vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1400)
  dobles.consulta = { dia: diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO',
    tareas_pendientes: 270, tareas_vencidas: 270, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })]),
  cargando: false, enVuelo: false, error: null, recargar: dobles.recargar }
})

describe('Supervisor horizontal', () => {
  it('seis columnas, ceros, cifras completas y panel inicial sin consultas', () => {
    render(<GestionDiariaSupervisor />)
    const tabla = screen.getByRole('table')
    expect(within(tabla).getAllByRole('columnheader')).toHaveLength(6)
    expect(within(tabla).getAllByText('270')).toHaveLength(2)
    expect(within(tabla).getByText(/Tareas vencidas/)).toBeInTheDocument()
    expect(within(tabla).getAllByText('Sin llamadas útiles')).toHaveLength(2)
    expect(within(tabla).getByRole('rowheader', { name: /ANA PÉREZ/ })).toHaveAttribute('scope', 'row')
    expect(screen.getByText('Selecciona un analista de la tabla para consultar su día.')).toBeVisible()
    expect(dobles.registro).not.toHaveBeenCalled()
  })
  it('los filtros no cambian indicadores y la ordenación comunica su dirección', () => {
    render(<GestionDiariaSupervisor />)
    const resumen = screen.getByRole('group', { name: 'Resumen del equipo' }).textContent
    fireEvent.click(screen.getByRole('button', { name: /Con atención/ }))
    expect(screen.queryByText('ANA PÉREZ')).not.toBeInTheDocument()
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'ana' } })
    expect(screen.getByText('Ningún analista coincide con estos filtros.')).toBeVisible()
    expect(screen.getByRole('group', { name: 'Resumen del equipo' })).toHaveTextContent(resumen!)
    fireEvent.click(screen.getByRole('button', { name: 'Ordenar por vencidas' }))
    expect(screen.getByRole('button', { name: 'Ordenar por vencidas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
  })
  it('seleccionar conserva foco, volver a pulsar no cierra y sólo la fila activa ofrece ir al detalle', () => {
    render(<GestionDiariaSupervisor />)
    const boton = screen.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' })
    boton.focus(); seleccionar()
    expect(boton).toHaveFocus()
    expect(boton).toHaveAttribute('aria-current', 'true')
    expect(screen.getAllByRole('button', { name: /Ir al detalle/ })).toHaveLength(1)
    seleccionar()
    expect(screen.getByRole('region', { name: 'Detalle de ANA PÉREZ' })).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /Ir al detalle/ }))
    expect(screen.getByRole('heading', { name: 'Detalle de ANA PÉREZ' })).toHaveFocus()
  })
  it('Registro monta al visitarlo, conserva páginas entre pestañas, filtros y ampliar/restaurar', () => {
    render(<GestionDiariaSupervisor />)
    abrirRegistro()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-21', analistaIds: ['a1'], mostrarAnalista: false, permitirEquipo: false, permitirExportar: false, pestanaInicial: 'todo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
    const pagina = screen.getByRole('button', { name: 'Página 2' })
    fireEvent.click(screen.getByRole('tab', { name: 'Resumen' }))
    expect(pagina).not.toBeVisible()
    fireEvent.click(screen.getByRole('tab', { name: 'Registro' }))
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'bruno' } })
    expect(screen.getByText('La selección está fuera de los filtros.')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Ampliar panel' }))
    expect(screen.getByRole('dialog', { name: 'Detalle de ANA PÉREZ' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    screen.getByRole('button', { name: 'Restaurar panel' }).focus()
    fireEvent.click(screen.getByRole('button', { name: 'Restaurar panel' }))
    expect(screen.getByRole('button', { name: 'Ampliar panel' })).toHaveFocus()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle' }))
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it('la apertura deliberada de llamadas reinicia páginas y selecciona sólo esa persona', () => {
    render(<GestionDiariaSupervisor />)
    abrirRegistro()
    fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
    fireEvent.click(screen.getByRole('tab', { name: 'Resumen' }))
    fireEvent.click(screen.getByRole('button', { name: 'Ver llamadas del día de ANA PÉREZ' }))
    expect(screen.getByRole('button', { name: 'Página 1' })).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Registro de ANA PÉREZ' })).toHaveFocus()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
  })
  it('un fallo del resumen no desmonta el registro ni roba foco al recuperarse', () => {
    const vista = render(<GestionDiariaSupervisor />)
    abrirRegistro()
    const pagina = screen.getByRole('button', { name: 'Página 1' })
    fireEvent.click(pagina); pagina.focus()
    dobles.consulta.error = new Error('Sin red')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    expect(pagina).toHaveFocus()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(pagina).toHaveFocus()
  })
  it.each(['revocacion', 'fuera'])('una pérdida confirmada del ámbito %s cierra las listas', (caso) => {
    const vista = render(<GestionDiariaSupervisor />)
    abrirRegistro(); screen.getByRole('button', { name: 'Página 1' }).focus()
    if (caso === 'revocacion') dobles.consulta.error = new CrmApiError('Revocado', '42501')
    else dobles.consulta.dia = diaEquipoPrueba([])
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Se cerró el detalle')
    expect(screen.getByRole('heading', { level: 2 })).toHaveFocus()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it.each(['actor', 'demo', 'dia', 'rol'])('cambio de %s borra el contexto antes de pintar', (cambio) => {
    const vista = render(<GestionDiariaSupervisor />)
    abrirRegistro()
    if (cambio === 'actor') dobles.yo.id = 's2'
    if (cambio === 'demo') dobles.yo.demo = true
    if (cambio === 'dia') dobles.ahora += 86400000
    if (cambio === 'rol') dobles.yo.rol = 'gerencia'
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it('modo equipo abre Todo con selectores autorizados y sin pestañas de persona', () => {
    render(<GestionDiariaSupervisor />)
    fireEvent.click(screen.getByRole('button', { name: 'Registro del equipo' }))
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: null, mostrarAnalista: true, permitirEquipo: false, permitirExportar: false, pestanaInicial: 'todo' }))
    expect(screen.queryByRole('tab', { name: 'Resumen' })).not.toBeInTheDocument()
  })
  it('distingue error de red, permiso, carga y equipo vacío', () => {
    dobles.consulta.error = new Error('red')
    const vista = render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('alert')).toHaveTextContent('no significa que el equipo no tenga actividad')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(dobles.recargar).toHaveBeenCalledOnce()
    dobles.consulta.error = new CrmApiError('Revocado', '42501')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    dobles.consulta = { ...dobles.consulta, error: null, dia: null, cargando: true }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByText('Consultando el equipo completo…')).toBeVisible()
    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba([]), cargando: false }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByText('No tienes analistas activos asignados')).toBeVisible()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
})


describe('Pedido de registro desde avisos', () => {
  const preparar = () => {
    dobles.avisos = { datos: null, cargando: false, error: null, ocupada: false, recargar: vi.fn(), actuar: vi.fn(),
      registroPedido: null, abrirRegistro: vi.fn(), consumirRegistro: vi.fn(() => { dobles.avisos!.registroPedido = null }) }
  }
  it('transfiere foco desde el diálogo de avisos al registro solicitado', async () => {
    preparar()
    const vista = render(<GestionDiariaSupervisor />)
    const origen = screen.getByRole('button', { name: 'Cortes de llamadas y otros avisos' })
    origen.focus(); fireEvent.click(origen)
    expect(screen.getByRole('dialog')).toBeVisible()
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-21', analista: 'a1', secuencia: 1 } }
    vista.rerender(<GestionDiariaSupervisor />)
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Detalle de ANA PÉREZ' })).toHaveFocus())
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
  })
  it('consume el pedido revocado y no lo abre si se recupera el equipo', () => {
    preparar()
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-21', analista: 'a1', secuencia: 1 } }
    dobles.consulta.error = new CrmApiError('Revocado', '42501')
    const vista = render(<GestionDiariaSupervisor />)
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
})
