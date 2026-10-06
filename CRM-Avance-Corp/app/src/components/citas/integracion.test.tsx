import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ContextoCitas, type DatosCitas } from './contexto'
import { TableroCitas } from './propuesta'
import { CITAS_CRM } from '@/prototypes/citas-crm/datos'
import type { GestionCitas, LeadBaseCitas } from './metas'

afterEach(cleanup)
beforeEach(() => window.history.replaceState(null, '', '#/reuniones'))
const fuente: DatosCitas = {citas:CITAS_CRM,corte:'2026-09-08T18:00:00Z',depositos:[],depositosDisponibles:false,mesInicial:'2026-09',modoDemo:false,meses:[]}
const montar = (cambios: Partial<DatosCitas> = {}) => render(<ContextoCitas value={{...fuente,...cambios}}><TableroCitas /></ContextoCitas>)

describe('Citas conectadas al CRM',() => {
  it('conserva en recargas el día al cambiar equipo y el equipo al quitar el día', () => {
    const citas = [
      { ...CITAS_CRM[0]!, id: 'a', analista: 'a', fecha: '2026-09-04', supervisorId: 'd-sup1' },
      { ...CITAS_CRM[0]!, id: 'b', analista: 'b', fecha: '2026-09-04', supervisorId: 'd-sup2' },
      { ...CITAS_CRM[0]!, id: 'c', analista: 'b', fecha: '2026-09-05', supervisorId: 'd-sup2' },
    ]
    window.history.replaceState(null, '', '#/reuniones/dia/2026-09-04/equipo/d-sup1')
    let vista = montar({ citas })
    fireEvent.change(screen.getByLabelText('Supervisor'), { target: { value: 'd-sup2' } })
    expect(window.location.hash).toBe('#/reuniones/dia/2026-09-04/equipo/d-sup2')
    vista.unmount()
    vista = montar({ citas })
    expect(screen.getByLabelText('Supervisor')).toHaveValue('d-sup2')
    expect(screen.getByTestId('conteo-citas')).toHaveTextContent('1 citas de tu consulta')
    fireEvent.click(screen.getByRole('button', { name: /Quitar Día:/ }))
    expect(window.location.hash).toBe('#/reuniones/mes/2026-09/equipo/d-sup2')
    vista.unmount()
    montar({ citas })
    expect(screen.getByLabelText('Supervisor')).toHaveValue('d-sup2')
    expect(screen.getByTestId('conteo-citas')).toHaveTextContent('2 citas de tu consulta')
  })
  it('el enlace del Resumen abre el día y equipo exactos y permite volver al mes completo', () => {
    window.history.replaceState(null, '', '#/reuniones/dia/2026-09-04/equipo/d-sup1')
    const onMes = vi.fn()
    montar({ onMes, citas: [
      { ...CITAS_CRM[0]!, id: 'a', fecha: '2026-09-04', supervisorId: 'd-sup1' },
      { ...CITAS_CRM[0]!, id: 'b', fecha: '2026-09-05', supervisorId: 'd-sup1' },
      { ...CITAS_CRM[0]!, id: 'c', fecha: '2026-09-04', supervisorId: 'd-sup2' },
    ] })
    expect(screen.getByRole('tab', { name: 'Agenda' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByTestId('conteo-citas')).toHaveTextContent('1 citas de tu consulta')
    expect(screen.getByLabelText('Supervisor')).toHaveValue('d-sup1')
    expect(screen.getByRole('button', { name: /Quitar Día:/ })).toBeVisible()
    expect(onMes).toHaveBeenLastCalledWith('2026-09')
    fireEvent.change(screen.getByLabelText('Semana'), { target: { value: '1' } })
    expect(screen.queryByRole('button', { name: /Quitar Día:/ })).not.toBeInTheDocument()
    expect(screen.getByTestId('conteo-citas')).toHaveTextContent('2 citas de tu consulta')
    expect(window.location.hash).toBe('#/reuniones/mes/2026-09/semana/1/equipo/d-sup1')
    fireEvent.click(screen.getByRole('button', { name: 'Restablecer consulta' }))
    expect(screen.getByTestId('conteo-citas')).toHaveTextContent('3 citas de tu consulta')
  })

  it('un nuevo enlace en la misma vista cambia día/equipo sin conservar filtros anteriores', () => {
    montar()
    fireEvent.change(screen.getByLabelText('Semana'), { target: { value: '4' } })
    window.history.replaceState(null, '', '#/reuniones/dia/2026-08-31/equipo/sin_supervisor')
    fireEvent(window, new HashChangeEvent('hashchange'))
    expect(screen.getByLabelText('Mes')).toHaveValue('2026-08')
    expect(screen.getByLabelText('Semana')).toHaveValue('')
    expect(screen.getByLabelText('Supervisor')).toHaveValue('sin_supervisor')
  })
  it('compara contra los asignados e incluye al analista con cero citas sin mostrar la meta interna',async () => {
    const usuario=userEvent.setup()
    const base = (n: number, analista='ana'): LeadBaseCitas => ({
      leadId:`sin-cita-${n}`,id:analista,nombre:analista==='ana'?'Ana':'Analista sin citas',
      supervisor:'Supervisor',supervisorId:'sup',nombreLead:`Asignado ${n}`,telefono:'900000000',
      asignadoEn:'2026-09-01T15:00:00Z',manualPropio:false,origen:'Referido',moneda:'PEN',monto:5000,
    })
    const gestion: GestionCitas={citasPorLead:1.25,entrevistasPorcentaje:70,depositosPorcentaje:70,
      asignaciones:[base(1),base(2),base(3),base(4),base(5,'sin-citas')]}
    montar({gestion,citas:Array.from({length:5},(_,n)=>({...CITAS_CRM[0]!,id:`cita-${n}`,analista:'ana',analistaNombre:'Ana',manualPropio:false}))})
    const tabla=screen.getByRole('table',{name:'Resultados por analista de las citas filtradas'})
    expect(within(tabla).getByRole('row',{name:/^Ana\b/})).toHaveTextContent('100%')
    const sinCitas=within(tabla).getByRole('row',{name:/Analista sin citas/})
    expect(sinCitas).toHaveTextContent('0%')
    expect(within(sinCitas).getAllByRole('cell')[1]).toHaveTextContent('1')
    expect(tabla).not.toHaveTextContent('Meta 3')
    expect(tabla).not.toHaveTextContent('3+ citas')
    await usuario.click(screen.getByRole('button',{name:'Cómo se calculan las métricas'}))
    expect(screen.getByRole('dialog')).not.toHaveTextContent('3.75')
    expect(screen.getByRole('dialog')).not.toHaveTextContent('1,25')
  })
  it('muestra depósitos sin verificar y conserva la recuperación y la meta',() => {
    montar()
    const conversion = screen.getByRole('region',{name:'Conversión de inasistencias a depósito'})
    expect(conversion).toHaveTextContent('Sin verificar')
    expect(conversion).not.toHaveTextContent('0%')
    expect(screen.getByRole('button',{name:'Depositó —'})).toBeDisabled()
    expect(screen.getByRole('button',{name:'Reprogramaron 3'})).toBeEnabled()
    expect(screen.getByText(/falta la base de leads asignados/)).toBeInTheDocument()
    expect(screen.getByRole('table',{name:'Resultados por analista de las citas filtradas'})).not.toHaveTextContent('3+ citas')
  })
  it('una consulta fallida no enseña métricas anteriores ni permite exportarlas',() => {
    const reintentar = vi.fn()
    montar({error:'No se pudieron cargar las citas.',onReintentar:reintentar})
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.queryByText('No hay citas con esta combinación')).not.toBeInTheDocument()
    expect(screen.getByRole('button',{name:'Exportar citas'})).toBeDisabled()
    fireEvent.click(screen.getByRole('tab',{name:'Bandeja comercial'}))
    expect(screen.getByRole('group',{name:'Consultas rápidas por estado'})).toHaveTextContent('Todas —')
    expect(screen.getByTestId('conteo-citas')).toHaveTextContent('Consulta no disponible')
    fireEvent.click(screen.getByRole('button',{name:'Reintentar'}))
    expect(reintentar).toHaveBeenCalledTimes(1)
  })
  it('durante carga bloquea cifras y exportación; vacío confirmado permite cambiar filtros',() => {
    const vista = montar({cargando:true})
    expect(screen.getByRole('tabpanel')).toHaveTextContent('Cargando las citas de tu consulta…')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.getByRole('button',{name:'Exportar citas'})).toBeDisabled()
    vista.rerender(<ContextoCitas value={{...fuente,citas:[]}}><TableroCitas /></ContextoCitas>)
    expect(screen.getByText('No hay citas con esta combinación')).toBeInTheDocument()
    expect(screen.getByLabelText('Mes')).toBeEnabled()
  })
  it('acepta otro año, conserva filtros entre vistas y comunica el mes al lector',async () => {
    const usuario=userEvent.setup(), onMes=vi.fn()
    montar({onMes})
    fireEvent.change(screen.getByLabelText('Mes'),{target:{value:'2027-02'}})
    expect(onMes).toHaveBeenLastCalledWith('2027-02')
    await usuario.click(screen.getByRole('tab',{name:'Agenda'}))
    expect(screen.getByLabelText('Mes')).toHaveValue('2027-02')
    expect(screen.getByText('No hay citas con esta combinación')).toBeInTheDocument()
  })
  it('abre la ficha real del prospecto desde el detalle de cita',async () => {
    const usuario=userEvent.setup(), abrir=vi.fn()
    montar({onAbrirLead:abrir})
    await usuario.click(screen.getByRole('tab',{name:'Bandeja comercial'}))
    const tabla=screen.getByRole('table',{name:/Citas que coinciden/})
    await usuario.click(within(tabla).getAllByRole('button',{name:/Ver detalle de/})[0]!)
    await usuario.click(screen.getByRole('button',{name:'Abrir ficha del prospecto'}))
    await vi.waitFor(() => expect(abrir).toHaveBeenCalledTimes(1))
    expect(abrir.mock.calls[0]![0]).toMatch(/^L-/)
  })
  it('muestra la conversión como depósito sin presentar un monto estimado como abonado',async () => {
    const usuario=userEvent.setup()
    montar({depositosDisponibles:true,depositoPorConversion:true,depositos:[{
      id:'conversion-L-031',leadId:'L-031',fuente:'conversion_cliente',monto:null,moneda:null,
      depositadoEn:'2026-09-04T15:00:00Z',confirmadoEn:'2026-09-04T15:00:00Z',
    }]})
    const indicador=screen.getByRole('region',{name:'Conversión de inasistencias a depósito'})
    expect(indicador).toHaveTextContent('25%')
    expect(indicador).not.toHaveTextContent('S/')
    await usuario.click(screen.getByRole('button',{name:'Depositó 1'}))
    const personas=screen.getByRole('table',{name:'Personas del flujo de recuperación'})
    expect(within(personas).getAllByRole('row')).toHaveLength(2)
    expect(personas).toHaveTextContent('Convertido a cliente')
    expect(personas).not.toHaveTextContent('35,000')
  })
})
