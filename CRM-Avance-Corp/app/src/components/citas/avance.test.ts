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
  const calcular = (tc: number | null = null) => calcularAvanceCitas(gestion, citas, filtros, corte, tc)
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
  it('7 clientes de 10 personas cumplen el 70%, aunque realicen 15 entrevistas', () => {
    const e = ejemplo()
    e.config.base_depositos = controlCitasInicial().base_depositos
    for (let i = 2; i <= 10; i++) {
      const leadId = `lead-${i}`
      e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: leadId })
      e.citas.push({ ...e.cita, id: `cita-${i}`, leadId })
      if (i <= 7) e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: leadId, perfil_id: `cliente-${i}` })
    }
    for (let i = 1; i <= 5; i++) e.citas.push({ ...e.cita, id: `segunda-visita-${i}`, leadId: `lead-${i}` })
    expect(e.calcular().total).toMatchObject({ entrevistas: 15, unicas: 10, clientes: 7, baseConversion: 10, conversion: 0.7 })
    expect(e.calcular().filas.find(f => f.id === 'ana')).toMatchObject({ entrevistas: 15, clientes: 7, conversion: 0.7 })
  })
  it('el mes del evento usa la entrevista registrada aunque la cita estuviera prevista antes', () => {
    const e = ejemplo()
    e.cita.fecha = '2026-08-31'
    e.cita.creadoEn = '2026-08-30T12:00:00Z'
    expect(e.calcular().total).toMatchObject({ citas: 0, entrevistas: 1, clientes: 1, conversion: 1 })
    e.cita.asistioEn = '2026-08-31T12:00:00Z'
    expect(e.calcular().total).toMatchObject({ entrevistas: 0, clientes: 0, clientesPeriodo: 1, clientesFueraCohorte: 1 })
  })
  it('un cierre cuenta para Luis aunque Ana recibiera y entrevistara antes al lead', () => {
    const e = ejemplo()
    Object.assign(e.datos.conversiones[0]!, { analista_id: 'luis', analista_nombre: 'Luis' })
    e.datos.capital[0]!.analista_id = 'luis'
    const r = e.calcular()
    expect(r.filas.find(f => f.id === 'luis')).toMatchObject({ clientesPeriodo: 1, clientesFueraCohorte: 1, clientes: 0, entrevistas: 0, conversion: null, ticket: 1000 })
    expect(r.filas.find(f => f.id === 'ana')).toMatchObject({ clientesPeriodo: 0, entrevistas: 1 })
    expect(r.total).toMatchObject({ clientesPeriodo: 1, clientes: 1, unicas: 1, conversion: 1 })
    e.filtros.analista = 'luis'
    expect(e.calcular().total).toMatchObject({ clientesPeriodo: 1, conversion: null, entrevistas: 0 })
  })
  it('deduplica la identidad vinculada aunque solo uno de sus leads se convierta', () => {
    const e = ejemplo()
    e.config.base_depositos = 'personas_entrevistadas'
    e.datos.poblacion[0]!.identidad_persona = 'perfil:cliente-1'
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    e.citas.push({ ...e.cita, id: 'cita-2', leadId: 'lead-2' })
    expect(e.calcular().total).toMatchObject({ entrevistas: 2, unicas: 1, clientes: 1, conversion: 1 })
    e.datos.conversiones = []
    expect(e.calcular().total).toMatchObject({ entrevistas: 2, unicas: 1, clientes: 0, conversion: 0 })
  })
  it('una persona con dos leads vinculados al mismo perfil sigue siendo una persona y un cliente', () => {
    const e = ejemplo()
    e.config.base_depositos = 'personas_entrevistadas'
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: 'lead-2' })
    e.citas.push({ ...e.cita, id: 'cita-2', leadId: 'lead-2' })
    expect(e.calcular().total).toMatchObject({ entrevistas: 2, unicas: 1, clientes: 1, clientesPeriodo: 1, clientesFueraCohorte: 0, conversion: 1 })
  })
  it('dos perfiles bajo la misma persona no inflan clientes ni reducen el ticket mensual', () => {
    const e = ejemplo()
    e.config.base_depositos = 'personas_entrevistadas'
    e.datos.poblacion[0]!.identidad_persona = 'persona:persona-1'
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: 'lead-2', perfil_id: 'cliente-2' })
    e.datos.capital.push({ ...e.datos.capital[0]!, lead_id: 'lead-2', perfil_id: 'cliente-2', contrato_id: 'contrato-2', monto: 500 })
    e.citas.push({ ...e.cita, id: 'cita-2', leadId: 'lead-2' })
    expect(e.calcular().total).toMatchObject({ entrevistas: 2, unicas: 1, clientes: 1, clientesPeriodo: 1, conversion: 1, clientesTicket: 1, capital: 1500, ticket: 1500 })
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
  it('convierte la moneda real del contrato sin cambiar el filtro de moneda estimada', () => {
    const e = ejemplo()
    e.datos.capital[0]!.moneda = 'USD'
    e.filtros.moneda = 'PEN'
    expect(e.calcular(3.75).total).toMatchObject({ leads: 1, ticket: 3750, capital: 3750, proyeccion: 3750, capitalPen: 0, capitalUsd: 1000 })
    expect(e.calcular().total).toMatchObject({ leads: 1, ticket: null, capital: null, proyeccion: null, faltaTipoCambio: true, capitalPen: 0, capitalUsd: 1000 })
  })
  it('suma ambas monedas convertidas y cuenta una sola persona aunque tenga dos perfiles', () => {
    const e = ejemplo()
    e.datos.poblacion[0]!.identidad_persona = 'persona:1'
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: 'lead-2', perfil_id: 'cliente-2' })
    e.datos.capital.push({ ...e.datos.capital[0]!, lead_id: 'lead-2', perfil_id: 'cliente-2', contrato_id: 'contrato-2', moneda: 'USD', monto: 500 })
    expect(e.calcular(4)).toMatchObject({ tc: 4, total: { capitalPen: 1000, capitalUsd: 500, capital: 3000, ticket: 3000, clientesTicket: 1, proyeccion: 3000 } })
    expect(calcularAvanceCitas(e.gestion, e.citas, e.filtros, '2026-10-04T15:00:00Z', 4).total).toMatchObject({ capital: 3000, proyeccion: 3000 })
  })
  it('el total pondera clientes y suma proyecciones; filtrar un analista conserva su capital original', () => {
    const e = ejemplo()
    for (let n = 2; n <= 3; n++) {
      const lead = `lead-${n}`, perfil = `cliente-${n}`
      e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: lead, analista_origen_id: 'luis', analista_origen_nombre: 'Luis' })
      e.citas.push({ ...e.cita, id: `cita-${n}`, leadId: lead, analista: 'luis', analistaNombre: 'Luis' })
      e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: lead, perfil_id: perfil, analista_id: 'luis', analista_nombre: 'Luis' })
      e.datos.capital.push({ ...e.datos.capital[0]!, contrato_id: `contrato-${n}`, lead_id: lead, perfil_id: perfil, analista_id: 'luis', moneda: 'USD', monto: 1000 })
    }
    const resumen = e.calcular(4)
    expect(resumen.filas.find(f => f.id === 'ana')).toMatchObject({ ticket: 1000, clientesTicket: 1 })
    expect(resumen.filas.find(f => f.id === 'luis')).toMatchObject({ ticket: 4000, clientesTicket: 2, proyeccion: 8000 })
    expect(resumen.total).toMatchObject({ capital: 9000, ticket: 3000, clientesTicket: 3, proyeccion: 9000, capitalPen: 1000, capitalUsd: 2000 })
    expect(e.calcular().total).toMatchObject({ capital: null, ticket: null, proyeccion: 1000, parciales: 1, analistas: 2 })
    e.filtros.analista = 'luis'
    expect(e.calcular(4).total).toMatchObject({ capital: 8000, ticket: 4000, clientesTicket: 2, capitalPen: 0, capitalUsd: 2000 })
    e.filtros.analista = 'ana'
    expect(e.calcular().total).toMatchObject({ capital: 1000, ticket: 1000, proyeccion: 1000, faltaTipoCambio: false, capitalPen: 1000, capitalUsd: 0 })
    expect(e.calcular(4).tc).toBeNull()
  })
  it.each([null, 0, -1, Number.NaN, Number.POSITIVE_INFINITY])('con TC %s nunca divide solo soles entre clientes de ambas monedas', tc => {
    const e = ejemplo()
    e.datos.capital.push({ ...e.datos.capital[0]!, contrato_id: 'contrato-2', moneda: 'USD', monto: 500 })
    expect(e.calcular(tc)).toMatchObject({ tc: null, total: { ticket: null, capital: null, proyeccion: null, faltaTipoCambio: true, capitalPen: 1000, capitalUsd: 500, motivoTicket: 'Falta el tipo de cambio para incluir dólares' } })
  })
  it('soles y un importe USD cero no necesitan una cotización ni anuncian una tasa sin aplicar', () => {
    const e = ejemplo()
    e.datos.capital.push({ ...e.datos.capital[0]!, contrato_id: 'contrato-2', moneda: 'USD', monto: 0 })
    expect(e.calcular()).toMatchObject({ tc: null, total: { ticket: 1000, capital: 1000, proyeccion: 1000, faltaTipoCambio: false, capitalPen: 1000, capitalUsd: 0 } })
    expect(e.calcular(4).tc).toBeNull()
  })
  it('el capital cuenta para el analista del núcleo y una conversión sin capital no anula el ticket', () => {
    const e = ejemplo()
    e.datos.capital[0]!.analista_id = 'otro'
    const r = e.calcular()
    expect(r.filas.find(f => f.id === 'ana')).toMatchObject({ ticket: null, motivoTicket: 'Sin capital cerrado en el mes', sinContrato: 0, proyeccion: null })
    expect(r.filas.find(f => f.id === 'otro')).toMatchObject({ ticket: 1000, clientesTicket: 1, leads: 0, citas: 0 })
    expect(r.total).toMatchObject({ ticket: 1000, capital: 1000, sinContrato: 0 })
    e.datos.capital = []
    expect(e.calcular().total).toMatchObject({ ticket: null, motivoTicket: 'Sin capital cerrado en el mes', sinContrato: 1, proyeccion: null })
  })
  it('varios contratos suman capital una vez y varios leads del mismo perfil no duplican clientes ni anulan el ticket', () => {
    const e = ejemplo()
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-2' })
    e.datos.conversiones.push({ ...e.datos.conversiones[0]!, lead_id: 'lead-2' })
    e.datos.capital.push({ ...e.datos.capital[0]!, contrato_id: 'contrato-2', monto: 500 })
    expect(e.calcular().total).toMatchObject({ capital: 1500, ticket: 1500, clientesTicket: 1, sinContrato: 0 })
  })
  it('todo el capital del mes cuenta: clientes sin lead, upgrades, renovaciones y cooperativas, una vez por persona', () => {
    const e = ejemplo()
    e.datos.capital.push(
      { contrato_id: 'contrato-2', lead_id: null, perfil_id: 'cliente-9', identidad_persona: 'persona:9', analista_id: 'ana', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 130000, fecha: '2026-09-10T05:00:00Z' },
      { contrato_id: 'contrato-3', lead_id: null, perfil_id: 'cliente-9', identidad_persona: 'persona:9', analista_id: 'ana', tipo: 'contrato_upgrade', moneda: 'PEN', monto: 20000, fecha: '2026-09-12T05:00:00Z' },
      { contrato_id: 'contrato-4', lead_id: null, perfil_id: 'cliente-8', analista_id: 'ana', tipo: 'contrato_renovacion', moneda: 'PEN', monto: 10000, fecha: '2026-09-08T05:00:00Z' },
      { contrato_id: null, cierre_externo_id: 'coop-1', lead_id: null, perfil_id: null, analista_id: 'ana', tipo: 'cooperativa', moneda: 'PEN', monto: 5000, fecha: '2026-09-09T05:00:00Z' },
    )
    expect(e.calcular().total).toMatchObject({ capital: 166000, clientesTicket: 4, ticket: 41500, proyeccion: 166000, sinContrato: 0,
      operaciones: { nuevos: 2, upgrades: 1, renovaciones: 1, cooperativas: 1 } })
  })
  it('un analista con capital pero sin leads ni citas aparece con su ticket, y el filtro de equipo lo respeta', () => {
    const e = ejemplo()
    e.datos.capital.push({ contrato_id: 'contrato-2', lead_id: null, perfil_id: 'cliente-9', analista_id: 'luis', analista_nombre: 'Luis',
      supervisor_id: 'sup2', supervisor_nombre: 'Otro supervisor', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 4000, fecha: '2026-09-10T05:00:00Z' })
    const r = e.calcular()
    expect(r.filas.find(f => f.id === 'luis')).toMatchObject({ nombre: 'Luis', supervisor: 'Otro supervisor', leads: 0, citas: 0, ticket: 4000, clientesTicket: 1 })
    expect(r.total).toMatchObject({ capital: 5000, clientesTicket: 2, ticket: 2500 })
    e.filtros.equipo = 'sup2'
    expect(e.calcular().total).toMatchObject({ capital: 4000, clientesTicket: 1, ticket: 4000 })
  })
  it('los filtros de persona acotan el capital a los leads que los cumplen; un texto en blanco no acota', () => {
    const e = ejemplo()
    e.datos.capital.push({ contrato_id: 'contrato-2', lead_id: null, perfil_id: 'cliente-9', analista_id: 'ana', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 4000, fecha: '2026-09-10T05:00:00Z' })
    expect(e.calcular().total).toMatchObject({ capital: 5000, clientesTicket: 2 })
    e.filtros.q = '   '
    expect(e.calcular().total).toMatchObject({ capital: 5000, clientesTicket: 2 })
    e.filtros.q = 'Persona uno'
    expect(e.calcular().total).toMatchObject({ capital: 1000, clientesTicket: 1, ticket: 1000 })
    e.filtros.q = 'Persona inexistente'
    expect(e.calcular().total).toMatchObject({ capital: 0, clientesTicket: 0, ticket: null })
  })
  it('el lead de una renovación sin citas en el mes llega en la población y su capital responde al filtro por lead', () => {
    const e = ejemplo()
    e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: 'lead-9', nombre: 'Cliente antiguo', analista_origen_id: null, primera_asignacion_en: null })
    e.datos.capital.push({ contrato_id: 'contrato-9', lead_id: 'lead-9', perfil_id: 'cliente-9', analista_id: 'ana', tipo: 'contrato_renovacion', moneda: 'PEN', monto: 4000, fecha: '2026-09-10T05:00:00Z' })
    e.filtros.leadId = 'lead-9'
    expect(e.calcular().total).toMatchObject({ capital: 4000, clientesTicket: 1, ticket: 4000, leads: 0, citas: 0 })
    e.filtros.leadId = 'lead-1'
    expect(e.calcular().total).toMatchObject({ capital: 1000, clientesTicket: 1 })
  })
  it('«convertidos sin capital» no cambia al filtrar por analista: mira el capital del mes antes del recorte', () => {
    const e = ejemplo()
    e.datos.capital[0]!.analista_id = 'otro'
    expect(e.calcular().filas.find(f => f.id === 'ana')).toMatchObject({ sinContrato: 0, ticket: null })
    e.filtros.analista = 'ana'
    expect(e.calcular().total).toMatchObject({ sinContrato: 0, ticket: null, capital: 0 })
  })
  it('en un mes cerrado el resultado es el capital realizado aunque no haya entrevistas ni reglas', () => {
    const e = ejemplo()
    e.datos.capital.push({ contrato_id: 'contrato-2', lead_id: null, perfil_id: 'cliente-9', analista_id: 'luis', analista_nombre: 'Luis', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 4000, fecha: '2026-09-10T05:00:00Z' })
    const cerrado = calcularAvanceCitas(e.gestion, e.citas, e.filtros, '2026-10-04T15:00:00Z', null)
    expect(cerrado.filas.find(f => f.id === 'luis')).toMatchObject({ entrevistas: 0, capital: 4000, proyeccion: 4000, motivoProyeccion: null })
    expect(cerrado.total).toMatchObject({ capital: 5000, proyeccion: 5000, parciales: 2, analistas: 2 })
    e.config.base_depositos = null
    expect(calcularAvanceCitas(e.gestion, e.citas, e.filtros, '2026-10-04T15:00:00Z', null).total).toMatchObject({ proyeccion: 5000, reglasListas: false })
    expect(e.calcular().total).toMatchObject({ proyeccion: null, motivoProyeccion: 'Completa las reglas de gestión' })
  })
  it('la proyección suma al capital cerrado los clientes que aún se esperan del flujo × ticket', () => {
    const e = ejemplo()
    for (const n of [2, 3]) {
      e.datos.poblacion.push({ ...e.datos.poblacion[0]!, lead_id: `lead-${n}` })
      e.citas.push({ ...e.cita, id: `cita-${n}`, leadId: `lead-${n}` })
    }
    // 3 citas al día 13 → 6,92 esperadas; conversión 1/3 → 2,31 clientes esperados, 1 ya real.
    const antes = e.calcular().total
    expect(antes.clientesEsperados).toBeCloseTo(2.3077, 3)
    expect(antes.proyeccion).toBeCloseTo(1000 + 1.3077 * 1000, 0)
    e.datos.capital.push({ contrato_id: 'contrato-9', lead_id: null, perfil_id: 'cliente-9', analista_id: 'ana', tipo: 'contrato_renovacion', moneda: 'PEN', monto: 9000, fecha: '2026-09-08T05:00:00Z' })
    const despues = e.calcular().total
    expect(despues).toMatchObject({ capital: 10000, clientesTicket: 2, ticket: 5000 })
    expect(despues.proyeccion).toBeCloseTo(10000 + 1.3077 * 5000, 0)
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
  it('una configuración completa sin aplicación no activa las tasas', () => {
    const e = ejemplo()
    e.datos.control.version = 0
    expect(e.calcular().total).toMatchObject({ clientesPeriodo: 1, tasaEntrevistas: null, conversion: null, proyeccion: null, reglasListas: false })
  })
  it('el calendario respeta Lima, febrero bisiesto y meses completos', () => {
    expect(periodoAvance('2026-09', '2026-09-14T02:00:00Z')).toMatchObject({ dias: 30, transcurridos: 13, cerrado: false })
    expect(periodoAvance('2024-02', corte)).toMatchObject({ dias: 29, transcurridos: 29, cerrado: true, ritmo: 100 })
    expect(periodoAvance('2026-10', corte)).toMatchObject({ transcurridos: 0, ritmo: null })
  })
})
