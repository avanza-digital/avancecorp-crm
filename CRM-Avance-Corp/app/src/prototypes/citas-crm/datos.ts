import { CITAS, CORTE, defaults, agruparAnalistas, filtrar, type CitaEjemplo, type FiltrosCitas } from '../../../prototypes/citas-assets/model.mjs'

export interface CitaConLead extends CitaEjemplo { leadId: string; citaAnteriorId?: string; reprogramadaEn?: string }
export interface ConsultaCitas extends FiltrosCitas { leadId?: string; mes?: string; semana?: string }

export function consultaInicial(): ConsultaCitas { return { ...defaults(), mes: '2026-09', semana: '' } }

/** Cuatro tramos comerciales: 1–7, 8–14, 15–21 y 22–fin. No son semanas ISO. */
export function rangoConsulta(filtros: ConsultaCitas): [string, string] {
  const mes = filtros.mes || '2026-09'
  const [anio, numeroMes] = mes.split('-').map(Number)
  const ultimo = new Date(Date.UTC(anio!, numeroMes!, 0)).getUTCDate()
  const semana = Number(filtros.semana || 0)
  const desde = semana ? (semana - 1) * 7 + 1 : 1
  const hasta = semana && semana < 4 ? semana * 7 : ultimo
  return [`${mes}-${String(desde).padStart(2, '0')}`, `${mes}-${String(hasta).padStart(2, '0')}`]
}

// Solo para esta adaptación: varios episodios del mismo prospecto. Su identidad
// se conserva por id, nunca por nombre o teléfono. La primera propuesta queda igual.
const REPETICIONES: Record<number, number> = { 10: 28, 11: 29, 18: 30, 24: 0, 36: 0, 19: 1, 25: 1, 37: 1, 20: 2, 26: 8, 21: 3, 27: 3, 22: 4, 23: 5 }
export const CITAS_CRM: CitaConLead[] = CITAS.map((cita, indice) => {
  const indiceLead = REPETICIONES[indice] ?? indice
  const lead = CITAS[indiceLead]!
  const vinculo = indice === 10 ? { citaAnteriorId: CITAS[28]!.id, reprogramadaEn: '2026-09-06T10:00:00-05:00' }
    : indice === 11 ? { citaAnteriorId: CITAS[29]!.id, reprogramadaEn: '2026-09-07T10:00:00-05:00' }
      : indice === 18 ? { citaAnteriorId: CITAS[30]!.id, reprogramadaEn: '2026-09-01T17:00:00-05:00', fecha: '2026-09-03', hora: '11:00' } : {}
  return { ...cita, ...vinculo, leadId: `L-${String(indiceLead + 1).padStart(3, '0')}`, nombre: lead.nombre, telefono: lead.telefono, origen: lead.origen, monto: lead.monto, moneda: lead.moneda }
})

export function consultarCitas(filtros: ConsultaCitas, datos = CITAS_CRM) {
  const [desde, hasta] = rangoConsulta(filtros)
  return filtrar({ ...filtros, periodo: 'custom', desde, hasta }, datos).filter(cita => !filtros.leadId || cita.leadId === filtros.leadId)
}

export function citasPorLead(citas: CitaConLead[]) {
  const leads = new Map<string, { id: string; nombre: string; citas: CitaConLead[] }>()
  for (const cita of citas) {
    const lead = leads.get(cita.leadId) ?? { id: cita.leadId, nombre: cita.nombre, citas: [] }
    lead.citas.push(cita)
    leads.set(cita.leadId, lead)
  }
  return [...leads.values()].sort((a, b) => b.citas.length - a.citas.length || a.nombre.localeCompare(b.nombre, 'es'))
}

/** Promedio de los episodios de la consulta, no de toda la cartera asignada.
 * El total del equipo se calcula con ids distintos, no promediando promedios. */
export function resumenLeads(citas: CitaConLead[]) {
  const leads = citasPorLead(citas)
  return { leads: leads.length, promedio: leads.length ? citas.length / leads.length : null, repetidos: leads.filter(lead => lead.citas.length > 1).length }
}

export function resultadosConLeads(citas: CitaConLead[]) {
  return agruparAnalistas(citas).map(persona => ({ ...persona, ...resumenLeads(citas.filter(cita => cita.analista === persona.id)) }))
}

export type EstadoRecuperacion = 'sin_reprogramar' | 'pendiente' | 'recuperada' | 'otra_inasistencia' | 'cancelada' | 'sin_resultado'
export interface Recuperacion { original: CitaConLead; nueva: CitaConLead | null; estado: EstadoRecuperacion }

/** La cohorte son las inasistencias filtradas. El seguimiento mira relaciones
 * explícitas hasta el corte, aunque la nueva fecha esté fuera del período.
 * Cada inasistencia se cuenta una sola vez; varias citas de un lead no bastan.
 * Si hay varias sucesoras, sigue la registrada más recientemente; a igual
 * registro, desempata por id. Es una regla del ejemplo, pendiente de contrato real. */
export function seguimientoInasistencias(cohorte: CitaConLead[], todas = CITAS_CRM, corte = CORTE): Recuperacion[] {
  return cohorte.filter(cita => cita.estado === 'no_show').map(original => {
    let actual = original
    const visitadas = new Set([original.id])
    while (true) {
      const siguiente = todas.filter(cita => cita.citaAnteriorId === actual.id && cita.leadId === original.leadId
        && cita.reprogramadaEn && Date.parse(cita.reprogramadaEn) <= Date.parse(corte)
        && Date.parse(cita.reprogramadaEn) >= Date.parse(`${actual.fecha}T${actual.hora}:00-05:00`)
        && `${cita.fecha} ${cita.hora}` > `${actual.fecha} ${actual.hora}` && !visitadas.has(cita.id))
        .sort((a, b) => Date.parse(b.reprogramadaEn!) - Date.parse(a.reprogramadaEn!) || a.id.localeCompare(b.id))[0]
      if (!siguiente) break
      visitadas.add(siguiente.id)
      actual = siguiente
    }
    const nueva = actual.id === original.id ? null : actual
    const estado: EstadoRecuperacion = !nueva ? 'sin_reprogramar' : nueva.estado === 'realizada' ? 'recuperada'
      : nueva.estado === 'no_show' ? 'otra_inasistencia' : ['cancelada', 'sistema'].includes(nueva.estado) ? 'cancelada'
        : Date.parse(`${nueva.fecha}T${nueva.hora}:00-05:00`) > Date.parse(corte) ? 'pendiente' : 'sin_resultado'
    return { original, nueva, estado }
  })
}
