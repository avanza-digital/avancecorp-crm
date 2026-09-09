import { agruparAnalistas, type CitaEjemplo } from './modelo'
export type CitaConLead = CitaEjemplo
export { defaults as consultaInicial, filtrar as consultarCitas, rango as rangoConsulta } from './modelo'
export type { FiltrosCitas as ConsultaCitas } from './modelo'
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
export interface Recuperacion { original: CitaConLead; nueva: CitaConLead | null; estado: EstadoRecuperacion; recorrido: CitaConLead[] }

/** La cohorte son las inasistencias filtradas. El seguimiento mira relaciones
 * explícitas hasta el corte, aunque la nueva fecha esté fuera del período.
 * Cada inasistencia se cuenta una sola vez; varias citas de un lead no bastan.
 * Si hay varias sucesoras, sigue la registrada más recientemente; a igual
 * registro, desempata por id. Sólo se aceptan sucesoras explícitas del mismo lead. */
export function seguimientoInasistencias(cohorte: CitaConLead[], todas: CitaConLead[], corte: string): Recuperacion[] {
  return cohorte.filter(cita => cita.estado === 'no_show').map(original => {
    let actual = original
    const recorrido: CitaConLead[] = []
    const visitadas = new Set([original.id])
    while (true) {
      const siguiente = todas.filter(cita => cita.citaAnteriorId === actual.id && cita.leadId === original.leadId
        && cita.reprogramadaEn && Date.parse(cita.reprogramadaEn) <= Date.parse(corte)
        && Date.parse(cita.reprogramadaEn) >= Date.parse(`${actual.fecha}T${actual.hora}:00-05:00`)
        && `${cita.fecha} ${cita.hora}` > `${actual.fecha} ${actual.hora}` && !visitadas.has(cita.id))
        .sort((a, b) => Date.parse(b.reprogramadaEn!) - Date.parse(a.reprogramadaEn!) || a.id.localeCompare(b.id))[0]
      if (!siguiente) break
      visitadas.add(siguiente.id)
      recorrido.push(siguiente)
      actual = siguiente
    }
    const nueva = actual.id === original.id ? null : actual
    const estado: EstadoRecuperacion = !nueva ? 'sin_reprogramar' : nueva.estado === 'realizada' ? 'recuperada'
      : nueva.estado === 'no_show' ? 'otra_inasistencia' : ['cancelada', 'sistema'].includes(nueva.estado) ? 'cancelada'
        : Date.parse(`${nueva.fecha}T${nueva.hora}:00-05:00`) > Date.parse(corte) ? 'pendiente' : 'sin_resultado'
    return { original, nueva, estado, recorrido }
  })
}
