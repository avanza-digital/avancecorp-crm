import * as v from 'valibot'
import { FechaHoraSchema, UuidSchema } from './esquemas-rpc'

const Natural = v.pipe(v.number(), v.safeInteger(), v.minValue(0))
const IdOpcional = v.nullable(UuidSchema)

/** Hechos del ciclo actual, evaluados por el servidor. La etapa no es evidencia. */
export const RecorridoLeadSchema = v.pipe(v.object({
  lead_id: UuidSchema,
  ciclo_n: v.nullable(Natural),
  ciclo_inicio: v.nullable(FechaHoraSchema),
  aplica: v.boolean(),
  estado: v.picklist(['completo', 'ambiguo', 'incompleto']),
  habilita_conversion: v.boolean(),
  exigible: v.boolean(),
  pasos: v.object({
    gestionado: v.boolean(), contactado: v.boolean(), cita_agendada: v.boolean(),
    asistencia: v.boolean(), entrevista: v.boolean(),
  }),
  evidencias: v.object({
    gestion_id: IdOpcional, contacto_id: IdOpcional, cita_id: IdOpcional,
    entrevista_tarea_id: IdOpcional, asistencia_tarea_id: IdOpcional, asistencia_id: IdOpcional,
  }),
  pendiente: v.picklist(['listo', 'asignar_analista', 'esperar_cita', 'cerrar_entrevista',
    'revisar_historial', 'revisar_entrevista', 'agendar_cita']),
  tarea_pendiente_id: IdOpcional,
  cita_pendiente_en: v.nullable(FechaHoraSchema),
}), v.check((r) => !r.habilita_conversion || (
  r.estado === 'completo' && r.pasos.asistencia && r.pasos.entrevista
  && r.ciclo_n !== null && r.ciclo_inicio !== null && r.evidencias.entrevista_tarea_id !== null
  && r.evidencias.asistencia_id !== null
)))

export const RecorridosSchema = v.pipe(v.object({
  version: v.literal(1),
  modo: v.picklist(['apagado', 'observacion', 'exigir']),
  revision: Natural,
  cohorte_desde: v.nullable(FechaHoraSchema),
  filas: v.array(RecorridoLeadSchema),
}), v.check((r) => r.modo === 'exigir' || r.filas.every((f) => !f.exigible)))

export type RecorridoLead = v.InferOutput<typeof RecorridoLeadSchema>
export type Recorridos = v.InferOutput<typeof RecorridosSchema>

/** Textos de orientación. Ninguna de estas etiquetas autoriza una conversión. */
export function siguienteDelRecorrido(r: RecorridoLead): string {
  switch (r.pendiente) {
    case 'listo': return 'Asistencia y entrevista registradas'
    case 'asignar_analista': return 'Asignar un analista'
    case 'esperar_cita': return 'Cita pendiente de realizar'
    case 'cerrar_entrevista': return 'Registrar qué pasó en la cita'
    case 'revisar_historial': return 'Revisar asistencia y entrevista'
    case 'revisar_entrevista': return 'Completar el resultado de la entrevista'
    case 'agendar_cita': return 'Agendar una cita'
  }
}
