import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ContextoCitas, type DatosCitas } from './contexto'
import { TableroCitas } from './propuesta'
import { CITAS_CRM } from '@/prototypes/citas-crm/datos'

afterEach(cleanup)
const fuente: DatosCitas = {citas:CITAS_CRM,corte:'2026-09-08T18:00:00Z',depositos:[],depositosDisponibles:false,mesInicial:'2026-09',modoDemo:false,meses:[]}
const montar = (cambios: Partial<DatosCitas> = {}) => render(<ContextoCitas value={{...fuente,...cambios}}><TableroCitas /></ContextoCitas>)

describe('Citas conectadas al CRM',() => {
  it('muestra depósitos sin verificar y conserva la recuperación y la meta',() => {
    montar()
    const conversion = screen.getByRole('region',{name:'Conversión de inasistencias a depósito'})
    expect(conversion).toHaveTextContent('Sin verificar')
    expect(conversion).not.toHaveTextContent('0%')
    expect(screen.getByRole('button',{name:'Depositó —'})).toBeDisabled()
    expect(screen.getByRole('button',{name:'Reprogramaron 3'})).toBeEnabled()
    expect(screen.getByRole('table',{name:'Resultados por analista de las citas filtradas'})).toHaveTextContent('40 / 26')
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
})
