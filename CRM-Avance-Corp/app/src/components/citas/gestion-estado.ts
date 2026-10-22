import * as v from 'valibot'
import { CamposGestionMensualSchema } from '@/lib/gestion-citas'

/**
 * D-53 (bloque 2.14): el estado de hoy del analista que nombra cada elemento de la consulta de Citas. Opcional en el
 * contrato: el servidor anterior no lo manda y la pantalla sigue igual (sin marcas).
 */
export const EstadoAnalistaSchema = v.optional(v.picklist(['activo', 'de_baja', 'suspendido']))

/**
 * Las tres listas de la gestión mensual que nombran analistas (población —analista de origen—, conversiones y capital) con
 * su estado. El contrato de `@/lib/gestion-citas` se extiende aquí, sin tocarlo: la clave nueva es opcional y `v.object`
 * ignoraría la clave si no se declarara.
 */
export const CamposGestionMensualConEstado = {
  ...CamposGestionMensualSchema,
  poblacion: v.pipe(v.array(v.object({
    ...CamposGestionMensualSchema.poblacion.pipe[0].item.entries,
    analista_origen_estado: EstadoAnalistaSchema,
  })), v.maxLength(10000)),
  conversiones: v.pipe(v.array(v.object({
    ...CamposGestionMensualSchema.conversiones.pipe[0].item.entries,
    analista_estado: EstadoAnalistaSchema,
  })), v.maxLength(10000)),
  capital: v.pipe(v.array(v.object({
    ...CamposGestionMensualSchema.capital.pipe[0].item.entries,
    analista_estado: EstadoAnalistaSchema,
  })), v.maxLength(10000)),
}
export const GestionMensualCitasConEstadoSchema = v.object(CamposGestionMensualConEstado)
export type GestionMensualCitasConEstado = v.InferOutput<typeof GestionMensualCitasConEstadoSchema>
