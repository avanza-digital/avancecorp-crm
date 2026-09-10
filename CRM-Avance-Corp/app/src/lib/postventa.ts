import * as v from 'valibot'
import { EMPRESAS_INVERSION } from './inversionistas'
import { TareaRowSchema } from './tarea-schema'

const Uuid = v.pipe(v.string(), v.uuid())
export const EstadoPostventaSchema = v.object({version: v.literal(1), habilitada: v.boolean()})
export const TareaPostventaSchema = v.object({...TareaRowSchema.entries,
  inversionista_id: Uuid, postventa_revision: v.pipe(v.number(), v.integer(), v.minValue(1)),
})
export const ResultadoAgendaPostventaSchema = v.object({ok: v.literal(true), tarea: TareaPostventaSchema,
  siguiente: v.optional(v.nullable(TareaPostventaSchema)),
})
export const RetiroPostventaSchema = v.object({
  id: Uuid, inversionista_id: Uuid, fuente_id: Uuid, empresa: v.picklist(['qorilazo', 'prodelco']),
  estado: v.picklist(['solicitada', 'en_revision', 'revisada', 'rechazada', 'cancelada']),
  motivo: v.string(), resolucion: v.nullable(v.string()), revision: v.pipe(v.number(), v.integer(), v.minValue(1)),
  creado_por: Uuid, revisado_por: v.nullable(Uuid), creado_en: v.string(), actualizado_en: v.string(),
})
export const FichaPostventaSchema = v.object({version: v.literal(1), habilitada: v.boolean(), retiros: v.array(RetiroPostventaSchema)})
export const VencimientosPostventaSchema = v.object({
  version: v.literal(1), habilitada: v.boolean(), pagina: v.pipe(v.number(), v.integer(), v.minValue(1)),
  tamano: v.literal(25), total: v.pipe(v.number(), v.integer(), v.minValue(0)),
  filas: v.array(v.object({fuente_id: Uuid, inversionista_id: Uuid, empresa: v.picklist(EMPRESAS_INVERSION),
    numero: v.nullable(v.string()), capital: v.pipe(v.number(), v.finite(), v.minValue(0)),
    moneda: v.picklist(['PEN', 'USD']), vence_en: v.string(), nombre: v.string()})),
})
export type RetiroPostventa = v.InferOutput<typeof RetiroPostventaSchema>
export type TareaPostventa = v.InferOutput<typeof TareaPostventaSchema>
export type EstadoRetiro = RetiroPostventa['estado']
export const RETIRO_ETIQUETA: Record<EstadoRetiro, string> = {
  solicitada: 'Solicitada', en_revision: 'En revisión', revisada: 'Revisada', rechazada: 'Rechazada', cancelada: 'Cancelada',
}
