import { citasPorLead, resumenLeads, type CitaConLead } from './datos'

export const META_CITAS_POR_LEAD = 3
export const OBJETIVO_CUMPLIMIENTO = 125
export const OBJETIVO_CITAS_POR_LEAD = META_CITAS_POR_LEAD * OBJETIVO_CUMPLIMIENTO / 100

/** Meta de la propuesta sobre la misma consulta; no prorratea semanas ni
 * incluye leads sin cita. El porcentaje se obtiene antes de redondear. */
export function metaCitas(citas: CitaConLead[]) {
  const resumen = resumenLeads(citas)
  return {
    ...resumen,
    citas: citas.length,
    cumplimiento: resumen.promedio === null ? null : resumen.promedio / META_CITAS_POR_LEAD * 100,
    leadsConMeta: citasPorLead(citas).filter(lead => lead.citas.length >= META_CITAS_POR_LEAD).length,
  }
}
