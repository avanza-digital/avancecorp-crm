// «Eliminar lead (error de carga)» (14/10/2026): reglas del motivo y acuse de
// crm.eliminar_lead_error_carga (migración 20261015044917). La pantalla solo
// evita el envío que el servidor rechazaría seguro; si el lead se puede borrar
// (sin contrato, sin conversión, de hace 30 días o menos, sin mes cerrado…) lo
// decide el servidor y su mensaje se muestra tal cual.
import * as v from 'valibot'
import { largoMotivoEliminacion } from '@/lib/inversionistas'

/**
 * Espejo de la puerta y del CHECK de crm.leads_eliminados:
 * char_length(private.motivo_normalizado(motivo)) entre 10 y 500. El recorte es el
 * mismo que el de «Eliminar inversión» (todos los blancos de los extremos), así que
 * el conteo también: caracteres como los cuenta Postgres, no unidades UTF-16.
 */
export const MOTIVO_ELIMINAR_LEAD_MIN = 10
export const MOTIVO_ELIMINAR_LEAD_MAX = 500

export function largoMotivoEliminarLead(motivo: string): number {
  return largoMotivoEliminacion(motivo)
}

export function motivoEliminarLeadValido(motivo: string): boolean {
  const largo = largoMotivoEliminarLead(motivo)
  return largo >= MOTIVO_ELIMINAR_LEAD_MIN && largo <= MOTIVO_ELIMINAR_LEAD_MAX
}

const Uuid = v.pipe(v.string(), v.uuid())
const Entero = v.pipe(v.number(), v.integer(), v.minValue(0))

/**
 * Acuse de crm.eliminar_lead_error_carga. Estricto en su forma: una clave de más o
 * un tipo distinto es otra respuesta. `filas` cuenta lo copiado y borrado por
 * tabla; sus claves las pone el servidor (crecen si aparece una tabla nueva).
 */
export const LeadEliminadoSchema = v.strictObject({
  ok: v.literal(true),
  lead_id: Uuid,
  copia_id: Uuid,
  filas: v.record(v.string(), Entero),
})
