import { CITAS, CORTE, EQUIPO } from '../../../prototypes/citas-assets/model.mjs'
import { defaults, filtrar } from '@/components/citas/modelo'
import { seguimientoInasistencias as seguir, type CitaConLead } from '@/components/citas/datos'
export type { CitaConLead, ConsultaCitas } from '@/components/citas/datos'
export { citasPorLead, resumenLeads, resultadosConLeads, rangoConsulta } from '@/components/citas/datos'
export const consultaInicial = () => defaults('2026-09')
// Solo para esta adaptación: varios episodios del mismo prospecto. Su identidad
// se conserva por id, nunca por nombre o teléfono. La primera propuesta queda igual.
const REPETICIONES: Record<number, number> = { 10: 28, 11: 29, 18: 30, 24: 0, 36: 0, 19: 1, 25: 1, 37: 1, 20: 2, 26: 8, 21: 3, 27: 3, 22: 4, 23: 5 }
export const CITAS_CRM: CitaConLead[] = CITAS.map((cita, indice) => {
  const indiceLead = REPETICIONES[indice] ?? indice
  const lead = CITAS[indiceLead]!
  const vinculo = indice === 10 ? { citaAnteriorId: CITAS[28]!.id, reprogramadaEn: '2026-09-06T10:00:00-05:00' }
    : indice === 11 ? { citaAnteriorId: CITAS[29]!.id, reprogramadaEn: '2026-09-07T10:00:00-05:00' }
      : indice === 18 ? { citaAnteriorId: CITAS[30]!.id, reprogramadaEn: '2026-09-01T17:00:00-05:00', fecha: '2026-09-03', hora: '11:00', asistioEn: '2026-09-03T11:05:00-05:00' } : {}
  return { ...cita, ...vinculo, leadId: `L-${String(indiceLead + 1).padStart(3, '0')}`, analistaNombre: EQUIPO.find(p => p.id === cita.analista)!.nombre, supervisorId: cita.supervisor, nombre: lead.nombre, telefono: lead.telefono, origen: lead.origen, monto: lead.monto, moneda: lead.moneda }
})


export const consultarCitas = (filtros: ReturnType<typeof consultaInicial>, datos = CITAS_CRM) => filtrar(filtros, datos)
export const seguimientoInasistencias = (cohorte: CitaConLead[], todas = CITAS_CRM, corte = CORTE) => seguir(cohorte,todas,corte)
