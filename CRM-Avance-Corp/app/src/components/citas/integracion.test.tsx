import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ContextoCitas, type DatosCitas } from './contexto'
import { TableroCitas } from './propuesta'
import { CITAS_CRM } from '@/prototypes/citas-crm/datos'
import type { GestionCitas, LeadBaseCitas } from './metas'

vi.mock('@/lib/tipo-cambio', () => ({ useTipoCambio: () => ({ tc: undefined, recargar: () => {} }) }))
import { controlCitasInicial } from '@/lib/control-citas'

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
      id:'conversion-L-031',leadId:'L-031',fuente:'conversion_cliente',fechaComercial:'2026-09-04',monto:null,moneda:null,
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

// D-53 (bloque 2.14): en «Citas del equipo» el analista dado de baja sale con «de baja» y el suspendido en el Portal con
// «suspendido», junto a su nombre, donde aparece (filtro, bandeja, agenda, ficha, resultados, recorrido, avance mensual).
// El total cuadra por construcción: el roster sale de las propias citas (medido aquí; no hace falta la fila «Otros», D-47).
describe('Citas del equipo · analista de baja o suspendido (D-53)', () => {
  const base = CITAS_CRM[0]!
  const marcadas = (): typeof CITAS_CRM => [
    { ...base, id: 'c-a1', leadId: 'L-A1', nombre: 'Prospecto A1', analista: 'ana-baja', analistaNombre: 'ANA BAJA', analistaEstado: 'de_baja', supervisor: 'Supervisora Uno', supervisorId: 'sup-1', fecha: '2026-09-04', hora: '09:00', estado: 'realizada', manualPropio: false, creadoEn: '2026-09-03T15:00:00Z' },
    { ...base, id: 'c-a2', leadId: 'L-A2', nombre: 'Prospecto A2', analista: 'ana-baja', analistaNombre: 'ANA BAJA', analistaEstado: 'de_baja', supervisor: 'Supervisora Uno', supervisorId: 'sup-1', fecha: '2026-09-05', hora: '10:00', estado: 'no_show', manualPropio: false, creadoEn: '2026-09-03T15:00:00Z' },
    { ...base, id: 'c-b1', leadId: 'L-B1', nombre: 'Prospecto B1', analista: 'beto-susp', analistaNombre: 'BETO SUSPENDIDO', analistaEstado: 'suspendido', supervisor: 'Supervisora Uno', supervisorId: 'sup-1', fecha: '2026-09-04', hora: '11:00', estado: 'realizada', manualPropio: false, creadoEn: '2026-09-03T15:00:00Z' },
    { ...base, id: 'c-c1', leadId: 'L-C1', nombre: 'Prospecto C1', analista: 'cata', analistaNombre: 'CATA ACTIVA', analistaEstado: 'activo', supervisor: 'Supervisora Uno', supervisorId: 'sup-1', fecha: '2026-09-04', hora: '12:00', estado: 'realizada', manualPropio: false, creadoEn: '2026-09-03T15:00:00Z' },
  ]
  const asignacion = (id: string, nombre: string, leadId: string, estado?: 'activo' | 'de_baja' | 'suspendido'): LeadBaseCitas => ({
    id, nombre, supervisor: 'Supervisora Uno', supervisorId: 'sup-1', leadId, nombreLead: `Lead ${leadId}`, telefono: '900000000',
    asignadoEn: '2026-09-01T15:00:00Z', manualPropio: false, registroManual: false, origen: 'Referido', moneda: 'PEN', monto: 5000, ...(estado ? { estado } : {}),
  })
  const gestionBase = (): GestionCitas => ({ citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, actividadManuales: 'excluir',
    asignaciones: [asignacion('ana-baja', 'ANA BAJA', 'L-A1', 'de_baja'), asignacion('ana-baja', 'ANA BAJA', 'L-A2', 'de_baja'),
      asignacion('beto-susp', 'BETO SUSPENDIDO', 'L-B1', 'suspendido'), asignacion('cata', 'CATA ACTIVA', 'L-C1', 'activo')] })
  const numeroDe = (celda: HTMLElement) => Number(celda.textContent!.replace(/[^0-9]/g, '').slice(0, 2) || '0')

  it('marca «de baja» y «suspendido» junto al nombre en el filtro, la bandeja, la agenda y la ficha; nada para el activo', async () => {
    const usuario = userEvent.setup()
    montar({ citas: marcadas() })
    const opciones = within(screen.getByLabelText('Analista')).getAllByRole('option').map(o => o.textContent)
    expect(opciones).toEqual(expect.arrayContaining(['ANA BAJA · de baja', 'BETO SUSPENDIDO · suspendido', 'CATA ACTIVA']))
    await usuario.click(screen.getByRole('tab', { name: 'Bandeja comercial' }))
    const tabla = screen.getByRole('table', { name: /Citas que coinciden/ })
    const filaA1 = within(tabla).getByRole('row', { name: /Prospecto A1/ })
    expect(within(filaA1).getByText('de baja')).toHaveAttribute('title', expect.stringMatching(/dado de baja del equipo/i))
    expect(within(filaA1).getByText('ANA BAJA')).toBeInTheDocument()
    const filaB1 = within(tabla).getByRole('row', { name: /Prospecto B1/ })
    expect(within(filaB1).getByText('suspendido')).toHaveAttribute('title', expect.stringMatching(/suspendido en el Portal/i))
    const filaC1 = within(tabla).getByRole('row', { name: /Prospecto C1/ })
    expect(within(filaC1).queryByText('de baja')).not.toBeInTheDocument()
    expect(within(filaC1).queryByText('suspendido')).not.toBeInTheDocument()
    // La etiqueta del filtro aplicado también lo dice.
    fireEvent.change(screen.getByLabelText('Analista'), { target: { value: 'ana-baja' } })
    expect(screen.getByRole('button', { name: 'Quitar Analista: ANA BAJA · de baja' })).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Analista'), { target: { value: '' } })
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    const agenda = screen.getByRole('tabpanel')
    const itemB1 = within(agenda).getByRole('button', { name: 'Ver detalle de Prospecto B1' }).closest('li')!
    expect(within(itemB1).getByText('suspendido')).toBeInTheDocument()
    const itemC1 = within(agenda).getByRole('button', { name: 'Ver detalle de Prospecto C1' }).closest('li')!
    expect(within(itemC1).queryByText('de baja')).not.toBeInTheDocument()
    await usuario.click(within(agenda).getByRole('button', { name: 'Ver detalle de Prospecto A1' }))
    const ficha = screen.getByRole('dialog')
    expect(within(ficha).getByText('ANA BAJA')).toBeInTheDocument()
    expect(within(ficha).getByText('de baja')).toHaveAttribute('title', expect.stringMatching(/dado de baja/i))
  })

  it('resultados por analista y recorrido: la marca junto al nombre, y la suma de las filas es el total (sin fila «Otros»)', async () => {
    const usuario = userEvent.setup()
    montar({ citas: marcadas(), gestion: gestionBase() })
    const tabla = screen.getByRole('table', { name: 'Resultados por analista de las citas filtradas' })
    const filaAna = within(tabla).getByRole('row', { name: /ANA BAJA/ })
    expect(within(filaAna).getByText('de baja')).toBeInTheDocument()
    expect(within(within(tabla).getByRole('row', { name: /BETO SUSPENDIDO/ })).getByText('suspendido')).toBeInTheDocument()
    expect(within(within(tabla).getByRole('row', { name: /CATA ACTIVA/ })).queryByText('de baja')).not.toBeInTheDocument()
    const filas = within(tabla).getAllByRole('row').filter(fila => /ANA BAJA|BETO SUSPENDIDO|CATA ACTIVA/.test(fila.textContent ?? ''))
    const suma = filas.reduce((n, fila) => n + numeroDe(within(fila).getAllByRole('cell')[0]!), 0)
    const total = numeroDe(within(within(tabla).getByRole('row', { name: /Total de la consulta/ })).getAllByRole('cell')[0]!)
    expect(filas).toHaveLength(3)
    expect(suma).toBe(4)
    expect(total).toBe(4)
    expect(within(tabla).queryByText('Otros')).not.toBeInTheDocument()
    // El recorrido de inasistencias nombra al analista con su marca.
    const flujo = screen.getByRole('table', { name: 'Personas del flujo de recuperación' })
    expect(within(within(flujo).getByRole('row', { name: /Prospecto A2/ })).getByText('de baja')).toBeInTheDocument()
    await usuario.click(within(flujo).getByRole('button', { name: 'Ver recorrido de Prospecto A2' }))
    expect(within(screen.getByRole('dialog')).getByText('de baja')).toBeInTheDocument()
  })

  it('avance mensual: la marca junto al nombre y la suma de las citas por analista es el total del equipo', () => {
    const persona = (leadId: string, analista: string, nombre: string, estado: 'activo' | 'de_baja' | 'suspendido') => ({
      lead_id: leadId, nombre: `Lead ${leadId}`, telefono: '900000000', origen: 'referido', moneda: 'PEN' as const, monto_estimado: 5000,
      registro_manual: false, creado_por: null, analista_origen_id: analista, analista_origen_nombre: nombre, analista_origen_estado: estado,
      primera_asignacion_en: '2026-09-01T15:00:00Z', supervisor_origen_id: 'sup-1', supervisor_origen_nombre: 'Supervisora Uno',
    })
    const gestion: GestionCitas = { ...gestionBase(), avance: {
      control: { version: 1, mes_inicio: '2026-09', configuracion: controlCitasInicial() },
      poblacion: [persona('L-A1', 'ana-baja', 'ANA BAJA', 'de_baja'), persona('L-A2', 'ana-baja', 'ANA BAJA', 'de_baja'),
        persona('L-B1', 'beto-susp', 'BETO SUSPENDIDO', 'suspendido'), persona('L-C1', 'cata', 'CATA ACTIVA', 'activo')],
      conversiones: [], capital: [],
    } }
    montar({ citas: marcadas(), gestion })
    // La sección y la tabla desplazable comparten el nombre: la tabla vive en la región interior (el div desplazable).
    const region = screen.getAllByRole('region', { name: 'Avance mensual por analista' }).find(r => r.tagName === 'DIV')!
    const filaAna = within(region).getByRole('row', { name: /ANA BAJA/ })
    expect(within(filaAna).getByText('de baja')).toHaveAttribute('title', expect.stringMatching(/dado de baja/i))
    expect(within(within(region).getByRole('row', { name: /BETO SUSPENDIDO/ })).getByText('suspendido')).toBeInTheDocument()
    expect(within(within(region).getByRole('row', { name: /CATA ACTIVA/ })).queryByText('de baja')).not.toBeInTheDocument()
    const filas = within(region).getAllByRole('row').filter(fila => /ANA BAJA|BETO SUSPENDIDO|CATA ACTIVA/.test(fila.textContent ?? ''))
    // La celda «Citas» lleva la cifra en <strong> y el promedio por lead en <small>.
    const citasDe = (fila: HTMLElement) => Number(within(fila).getAllByRole('cell')[1]!.querySelector('strong')!.textContent)
    const suma = filas.reduce((n, fila) => n + citasDe(fila), 0)
    const total = citasDe(within(region).getByRole('row', { name: /Total del equipo/ }))
    expect(filas).toHaveLength(3)
    expect(suma).toBe(4)
    expect(total).toBe(4)
  })

  it('sin bajas ni suspendidos (o con el servidor anterior) no aparece ninguna marca', async () => {
    const usuario = userEvent.setup()
    montar()
    await usuario.click(screen.getByRole('tab', { name: 'Bandeja comercial' }))
    expect(screen.queryByText('de baja')).not.toBeInTheDocument()
    expect(screen.queryByText('suspendido')).not.toBeInTheDocument()
    expect(within(screen.getByLabelText('Analista')).getAllByRole('option').some(o => / · /.test(o.textContent ?? ''))).toBe(false)
  })
})
