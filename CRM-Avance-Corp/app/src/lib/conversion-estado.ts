import * as v from 'valibot'
import { FechaHoraSchema, FechaSchema, TextoNoVacioSchema, UuidSchema } from './esquemas-rpc'

/** Decisión del servidor. No se deduce crédito a partir del monto ni del reloj
 * del navegador. Una respuesta ausente/inválida es error, nunca «sin crédito». */
export const ConversionEstadoSchema = v.object({
  version: v.literal(1),
  lead_id: UuidSchema,
  estado: v.picklist([
    'acreditada', 'fuera_de_plazo', 'mes_sellado', 'pendiente_fuente',
    'fuente_retirada', 'fecha_futura', 'fuente_demo', 'operacion_cartera',
    'anulada', 'politica_anterior', 'anterior_vigencia', 'no_convertido', 'pendiente_activacion',
  ]),
  mensaje: TextoNoVacioSchema,
  periodo_comercial: v.nullable(FechaSchema),
  fecha_comercial: v.nullable(FechaSchema),
  plazo_hasta: v.nullable(FechaHoraSchema),
  confirmado_en: v.nullable(FechaHoraSchema),
  vinculado_en: v.nullable(FechaHoraSchema),
})

export type ConversionEstado = v.InferOutput<typeof ConversionEstadoSchema>
