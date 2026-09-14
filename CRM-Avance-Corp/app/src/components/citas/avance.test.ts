import { describe, expect, it } from 'vitest'
import { calcularAvanceCitas, periodoAvance } from './avance'
import { defaults, type CitaEjemplo } from './modelo'
import type { GestionCitas } from './metas'
import { controlCitasInicial } from '@/lib/control-citas'

const corte = '2026-09-13T15:00:00Z'
function ejemplo() {
  const cita: CitaEjemplo = {
    id: 'cita-1', leadId: 'lead-1', nombre: 'Persona uno', telefono: '900000001',
    analista: 'ana', analistaNombre: 'Ana', supervisor: 'Supervisor', supervisorId: 'sup',
    fecha: '2026-09-02', hora: '11:00', estado: 'realizada', modalidad: 'Virtual',
    origen: 'Referido', moneda: 'PEN', monto: 2500, resultado: 'Interesado',
    cerrado: true, seguimiento: false, nuevaFecha: null, nota: '',
    creadoEn: '2026-09-01T15:00:00Z', asistioEn: '2026-09-02T17:00:00Z',
    manualPropio: true, registroManual: true,
  }
  const persona = { lead_id: 'lead-1', nombre: 'Persona uno', telefono: '900000001', origen: 'referido',
    moneda: 'PEN' as const, monto_estimado: 2500, registro_manual: true, creado_por: 'ana',
    analista_origen_id: 'ana', analista_origen_nombre: 'Ana', supervisor_origen_id: 'sup', supervisor_origen_nombre: 'Supervisor',
    primera_asignacion_en: '2026-09-01T14:00:00Z' }
  const gestion: GestionCitas = {
    citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70,
    asignaciones: [{ id: 'ana', nombre: 'Ana', supervisor: 'Supervisor', supervisorId: 'sup',
      leadId: 'lead-1', nombreLead: 'Persona uno', telefono: '900000001', asignadoEn: '2026-09-01T14:00:00Z',
      manualPropio: true, registroManual: true, origen: 'Referido', moneda: 'PEN', monto: 2500 }],
    avance: { control: { version: 1, mes_inicio: '2026-09', configuracion: { ...controlCitasInicial(),
      base_depositos: 'entrevistas', mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: '2026-09' } },
    poblacion: [persona], conversiones: [{ lead_id: 'lead-1', perfil_id: 'cliente-1', convertido_en: '2026-09-03T15:00:00Z',
      analista_id: 'ana', analista_nombre: 'Ana', supervisor_id: 'sup', supervisor_nombre: 'Supervisor', contrato_id: 'contrato-1' }],
    capital: [{ contrato_id: 'contrato-1', lead_id: 'lead-1', perfil_id: 'cliente-1', analista_id: 'ana', moneda: 'PEN', monto: 1000, fecha: '2026-09-03T05:00:00Z' }] },
  }
  const citas = [cita]
  const filtros = defaults('2026-09')
  const calcular = (moneda: 'PEN' | 'USD' = 'PEN') => calcularAvanceCitas(gestion, citas, filtros, corte, moneda)
  return { gestion, datos: gestion.avance!, config: gestion.avance!.control.configuracion, citas, cita, filtros, calcular }
}

describe('Avance mensual conectado a hechos de Citas', () => {
  it('incluye altas manuales y calcula 1,25 como configuración interna', () => {
    const { calcular } = ejemplo()
    expect(calcular().total).toMatchObject({ leads: 1, citas: 1, promedio: 1, cumplimiento: 80,
      entrevistas: 1, clientes: 1, tasaEntrevistas: 1, conversion: 1, ticket: 1000, manuales: 1 })
  })
  it('conserva leads sin citas y un analista con cero actividad', () => {
    const e = ejemplo()
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2', analista_origen_id: 'luis', analista_origen_nombre: 'Luis' })
    e.gestion.asignaciones.push({ ...e.gestion.asignaciones[0]!, id: 'luis', nombre: 'Luis', leadId: 'lead-2' })
    expect(e.calcular().filas.find(f => f.id === 'luis')).toMatchObject({ leads: 1, citas: 0, cumplimiento: 0, tasaEntrevistas: null, conversion: null, ticket: null, proyeccion: null })
    expect(e.calcular().total).toMatchObject({ leads: 2, citas: 1, cumplimiento: 40 })
  })
  it('cada visita suma, cada cliente es único y el divisor es configurable', () => {
    const e = ejemplo()
    e.citas.push({ ...e.cita, id: 'cita-2', fecha: '2026-09-03', asistioEn: '2026-09-03T12:00:00Z' })
    expect(e.calcular().total).toMatchObject({ entrevistas: 2, unicas: 1, clientes: 1, conversion: 0.5, baseConversion: 2 })
    e.config.base_depositos = 'personas_entrevistadas'
    expect(e.calcular().total).toMatchObject({ entrevistas: 2, clientes: 1, conversion: 1, baseConversion: 1 })
  })
  it('un depósito anterior a la entrevista y una visita sin registro no acreditan conversión', () => {
    const e = ejemplo()
    e.cita.asistioEn = '2026-09-05T15:00:00Z'
    expect(e.calcular().total).toMatchObject({ entrevistas: 1, clientes: 0, clientesFueraCohorte: 1, conversion: 0 })
    delete e.cita.asistioEn
    expect(e.calcular().total).toMatchObject({ entrevistas: 0, clientes: 0, conversion: null })
  })
  it('el mes del evento usa la entrevista registrada aunque la cita estuviera prevista antes', () => {
    const e = ejemplo()
    e.cita.fecha = '2026-08-31'
    e.cita.creadoEn = '2026-08-30T12:00:00Z'
    expect(e.calcular().total).toMatchObject({ citas: 0, entrevistas: 1, clientes: 1, conversion: 1 })
    e.cita.asistioEn = '2026-08-31T12:00:00Z'
    expect(e.calcular().total).toMatchObject({ entrevistas: 0, clientes: 0 })
  })
  it('ignora filtros operativos para conservar el acumulado y su base mensual', () => {
    const e = ejemplo()
    const antes = e.calcular().total
    Object.assign(e.filtros, { semana: '4', estados: ['no_show'], modalidad: 'Presencial', resultado: 'No interesado', seguimiento: 'pendiente' })
    expect(e.calcular().total).toEqual(antes)
    e.filtros.q = 'Persona inexistente'
    expect(e.calcular().total).toMatchObject({ leads: 0, citas: 0, cumplimiento: null })
  })
  it('la atribución al origen incorpora al primer analista, aunque ya no tenga actividad propia', () => {
    const e = ejemplo()
    e.config.analista_resultado = 'asignacion'
    e.datos.poblacion[0]!.primera_asignacion_en = '2026-08-01T15:00:00Z'
    Object.assign(e.cita, { analista: 'luis', analistaNombre: 'Luis' })
    Object.assign(e.gestion.asignaciones[0]!, { id: 'luis', nombre: 'Luis' })
    Object.assign(e.datos.conversiones[0]!, { analista_id: 'luis', analista_nombre: 'Luis' })
    e.datos.capital[0]!.analista_id = 'luis'
    const r = e.calcular()
    expect(r.filas.find(f => f.id === 'ana')).toMatchObject({ entrevistas: 1, clientes: 1 })
    expect(r.filas.find(f => f.id === 'luis')).toMatchObject({ entrevistas: 0, clientes: 0, ticket: 1000 })
    expect(r.filas.reduce((n,f) => n + f.entrevistas, 0)).toBe(r.total.entrevistas)
  })
  it('el seguimiento por cohorte usa la primera asignación, y el ticket conserva su mes real', () => {
    const e = ejemplo()
    e.config.mes_resultado = 'asignacion'
    e.datos.poblacion[0]!.primera_asignacion_en = '2026-08-01T15:00:00Z'
    expect(e.calcular().total).toMatchObject({ entrevistas: 0, clientes: 0, ticket: 1000 })
  })
  it('el importe real puede tener otra moneda que la estimación; el selector monetario es independiente', () => {
    const e = ejemplo()
    e.datos.capital[0]!.moneda = 'USD'
    expect(e.calcular('USD').total).toMatchObject({ leads: 1, ticket: 1000, capital: 1000, proyeccion: 1000 })
    expect(e.calcular('PEN').total).toMatchObject({ leads: 1, ticket: null, capital: 0, proyeccion: null })
  })
  it('distingue un importe ausente de una atribución monetaria contradictoria', () => {
    const e = ejemplo()
    e.datos.capital[0]!.analista_id = 'otro'
    expect(e.calcular().total).toMatchObject({ ticket: null, sinImporte: 0, atribucionPendiente: 1, proyeccion: null })
    e.datos.capital = []
    expect(e.calcular().total).toMatchObject({ ticket: null, sinImporte: 1, atribucionPendiente: 0, proyeccion: null })
  })
  it('varios contratos suman capital una vez y varios leads del mismo perfil no duplican clientes ni anulan el ticket', () => {
    const e = ejemplo()
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: 'lead-2' })
    e.datos.capital.push({ ...e.datos.capital[0]!, contrato_id: 'contrato-2', monto: 500 })
    expect(e.calcular().total).toMatchObject({ capital: 1500, ticket: 1500, clientesTicket: 1, sinImporte: 0 })
  })
  it('una cita creada para octubre suma citas pero no incrementa el pronóstico de septiembre', () => {
    const e = ejemplo()
    const antes = e.calcular().total.proyeccion
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    const futura = { ...e.cita, id: 'cita-2', leadId: 'lead-2', fecha: '2026-10-02', estado: 'programada' as const }
    delete futura.asistioEn
    e.citas.push(futura)
    expect(e.calcular().total.citas).toBe(2)
    expect(e.calcular().total.proyeccion).toBe(antes)
  })
  it('no convierte reglas pendientes en tasas ni pronósticos supuestos', () => {
    const e = ejemplo()
    e.config.base_depositos = null
    expect(e.calcular().total).toMatchObject({ entrevistas: 1, clientes: 1, tasaEntrevistas: null, conversion: null, proyeccion: null })
  })
  it('el calendario respeta Lima, febrero bisiesto y meses completos', () => {
    expect(periodoAvance('2026-09', '2026-09-14T02:00:00Z')).toMatchObject({ dias: 30, transcurridos: 13, cerrado: false })
    expect(periodoAvance('2024-02', corte)).toMatchObject({ dias: 29, transcurridos: 29, cerrado: true, ritmo: 100 })
    expect(periodoAvance('2026-10', corte)).toMatchObject({ transcurridos: 0, ritmo: null })
  })
})
