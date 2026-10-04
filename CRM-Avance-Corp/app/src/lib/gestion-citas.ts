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
    // null: base cargada sin capital (F5a). El contrato se valida entero: un null no puede apagar el avance.
    moneda: v.picklist(['PEN', 'USD']), monto_estimado: v.nullable(Importe),
    registro_manual: v.boolean(), creado_por: v.nullable(Id),
    analista_origen_id: v.nullable(Id), primera_asignacion_en: v.nullable(Instante),
    analista_origen_nombre: v.string(), supervisor_origen_id: v.nullable(Id), supervisor_origen_nombre: v.string(),
  })), v.maxLength(10000)),
  conversiones: v.pipe(v.array(v.object({
    lead_id: Id, perfil_id: Id, convertido_en: Instante, analista_id: v.nullable(Id),
    analista_nombre: v.string(), supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
    contrato_id: v.nullable(Id),
  })), v.maxLength(10000)),
  // Todo el capital del mes por analista (contratos nuevos, upgrades, renovaciones
  // y cooperativas). Los campos nuevos son opcionales para leer también la
  // respuesta del lector anterior, que sólo traía contratos nuevos de leads.
  capital: v.pipe(v.array(v.object({
    contrato_id: v.nullable(Id), cierre_externo_id: v.nullish(Id),
    tipo: v.nullish(v.picklist(['contrato_nuevo', 'contrato_upgrade', 'contrato_renovacion', 'cooperativa'])),
    lead_id: v.nullable(Id), perfil_id: v.nullable(Id),
    identidad_persona: v.nullish(v.pipe(v.string(), v.regex(/^(perfil|persona|lead|externo):[0-9a-f-]{36}$/i))),
    analista_id: v.nullable(Id), analista_nombre: v.nullish(v.string()),
    supervisor_id: v.nullish(Id), supervisor_nombre: v.nullish(v.string()),
    moneda: v.picklist(['PEN', 'USD']), monto: Importe, fecha: Instante,
  })), v.maxLength(10000)),
}
export const GestionMensualCitasSchema = v.object(CamposGestionMensualSchema)

/** Testigo del servidor (F2, 21/09/2026): el «Depósito %» del TOTAL del mes sin
 * filtros, calculado por `private.citas_testigo_mes` con sus propias consultas.
 * El front lo compara con su propio total; si no cuadra, no publica el número. */
export const TestigoCitasSchema = v.object({
  version: v.literal(1),
  calculado_en: Instante,
  reglas_listas: v.boolean(),
  configuracion: v.object({
    mes_resultado: v.nullable(v.string()), analista_resultado: v.nullable(v.string()),
    base_depositos: v.nullable(v.string()), actividad_manuales: v.nullable(v.string()),
  }),
  entrevistas: v.pipe(v.number(), v.integer(), v.minValue(0)),
  personas_entrevistadas: v.pipe(v.number(), v.integer(), v.minValue(0)),
  clientes_periodo: v.pipe(v.number(), v.integer(), v.minValue(0)),
  clientes_vinculados: v.pipe(v.number(), v.integer(), v.minValue(0)),
  base_conversion: v.pipe(v.number(), v.integer(), v.minValue(0)),
  conversion_pct: v.nullable(v.pipe(v.number(), v.finite(), v.minValue(0))),
})
export type TestigoCitas = v.InferOutput<typeof TestigoCitasSchema>
export type GestionMensualCitas = v.InferOutput<typeof GestionMensualCitasSchema>
