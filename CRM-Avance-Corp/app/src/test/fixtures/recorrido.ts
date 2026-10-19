import type { RecorridoLead, Recorridos } from '@/lib/recorrido-lead'

export const recorridoId = (n: number) => `b0000000-0000-4000-8000-${String(n).padStart(12, '0')}`
export function recorridoFixture(leadId = recorridoId(1), sobre: Partial<RecorridoLead> = {}): RecorridoLead {
  return {
    lead_id: leadId, ciclo_n: 1, ciclo_inicio: '2026-10-18T15:00:00Z', aplica: true,
    estado: 'incompleto', habilita_conversion: false, exigible: false,
    pasos: { gestionado: false, contactado: false, cita_agendada: false, asistencia: false, entrevista: false },
    evidencias: { gestion_id: null, contacto_id: null, cita_id: null, entrevista_tarea_id: null, asistencia_tarea_id: null, asistencia_id: null },
    pendiente: 'agendar_cita', tarea_pendiente_id: null, cita_pendiente_en: null, ...sobre,
  }
}
export function recorridosFixture(filas: RecorridoLead[], sobre: Partial<Recorridos> = {}): Recorridos {
  return { version: 1, modo: 'observacion', revision: 1, cohorte_desde: null, filas, ...sobre }
}
