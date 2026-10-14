import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'

const Id = v.pipe(v.string(), v.uuid())
const EfectoSchema = v.object({
  tipo: v.picklist(['contrato', 'cooperativa']), id: Id, numero: v.nullable(v.string()),
  fecha: v.nullable(v.string()), moneda: v.picklist(['PEN', 'USD']), monto: v.number(),
  anterior: v.nullable(Id), previsto: v.nullable(Id), anterior_nombre: v.nullable(v.string()), previsto_nombre: v.nullable(v.string()),
  desglose_anterior: v.nullable(Id), desglose_previsto: v.nullable(Id),
})
const PreviaSchema = v.object({
  version: v.pipe(v.string(), v.regex(/^[a-f0-9]{32}$/)),
  accion: v.picklist(['venta', 'atencion_persona', 'atencion_cliente']), id: Id, destino: Id,
  anterior: v.nullable(Id), anterior_nombre: v.nullable(v.string()), destino_nombre: v.string(),
  persona_id: v.nullable(Id), cliente_id: v.nullable(Id), perfil_cambia: v.boolean(),
  leads: v.number(), tareas: v.number(), aviso: v.string(), efectos: v.array(EfectoSchema),
})
export type PreviaResponsabilidad = v.InferOutput<typeof PreviaSchema>
export type AccionResponsabilidad = PreviaResponsabilidad['accion']
function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb.schema('crm')
}
export async function previsualizarResponsabilidad(accion: AccionResponsabilidad, id: string, destino: string) {
  const previa = respuestaInversionistas(PreviaSchema, await cliente().rpc('previsualizar_cambio_responsabilidad_fn', {
    p_accion: accion, p_id: id, p_destino: destino,
  }))
  if (previa.accion !== accion || previa.id !== id || previa.destino !== destino) {
    throw new CrmApiError('La revisión no corresponde a esta acción.', 'RESPUESTA_INCOMPLETA')
  }
  return previa
}
export async function confirmarResponsabilidad(previa: PreviaResponsabilidad, motivo: string) {
  const r = respuestaInversionistas(v.object({ok: v.literal(true), version_confirmada: v.string(), efectos: v.array(EfectoSchema)}),
    await cliente().rpc('confirmar_cambio_responsabilidad_fn', {
      p_accion: previa.accion, p_id: previa.id, p_destino: previa.destino, p_motivo: motivo.trim(), p_version: previa.version,
    }))
  if (r.version_confirmada !== previa.version) throw new CrmApiError('Actualiza la ficha para comprobar el resultado.', 'RESPUESTA_INCOMPLETA')
  return r
}
