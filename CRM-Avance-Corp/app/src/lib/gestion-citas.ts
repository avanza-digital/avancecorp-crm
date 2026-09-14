import * as v from 'valibot'
import { ControlCitasSchema } from './control-citas'

const Id = v.pipe(v.string(), v.uuid())
const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Importe = v.pipe(v.number(), v.finite(), v.minValue(0))
export const CamposGestionMensualSchema = {
  control: v.object({
    version: v.pipe(v.number(), v.integer(), v.minValue(0)),
    mes_inicio: v.nullable(v.pipe(v.string(), v.regex(/^20\d{2}-(0[1-9]|1[0-2])$/))),
    configuracion: ControlCitasSchema,
  }),
  poblacion: v.pipe(v.array(v.object({
    lead_id: Id, nombre: v.string(), telefono: v.string(), origen: v.string(),
    identidad_persona: v.optional(v.pipe(v.string(), v.regex(/^(perfil|persona|lead):[0-9a-f-]{36}$/i))),
    moneda: v.picklist(['PEN', 'USD']), monto_estimado: Importe,
    registro_manual: v.boolean(), creado_por: v.nullable(Id),
    analista_origen_id: v.nullable(Id), primera_asignacion_en: v.nullable(Instante),
    analista_origen_nombre: v.string(), supervisor_origen_id: v.nullable(Id), supervisor_origen_nombre: v.string(),
  })), v.maxLength(10000)),
  conversiones: v.pipe(v.array(v.object({
    lead_id: Id, perfil_id: Id, convertido_en: Instante, analista_id: v.nullable(Id),
    analista_nombre: v.string(), supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
    contrato_id: v.nullable(Id),
  })), v.maxLength(10000)),
  capital: v.pipe(v.array(v.object({
    contrato_id: Id, lead_id: Id, perfil_id: Id, analista_id: v.nullable(Id),
    moneda: v.picklist(['PEN', 'USD']), monto: Importe, fecha: Instante,
  })), v.maxLength(10000)),
}
export const GestionMensualCitasSchema = v.object(CamposGestionMensualSchema)
export type GestionMensualCitas = v.InferOutput<typeof GestionMensualCitasSchema>
