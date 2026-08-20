import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  UuidSchema,
} from './esquemas-rpc'

const MonedaSchema = v.picklist(['PEN', 'USD'] as const)
const CapitalSchema = v.pipe(NumeroRpcSchema, v.minValue(0))
const PorcentajeSchema = v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(100))

const PeriodoDerivacionesSchema = v.object({
  desde: FechaSchema,
  hasta: FechaSchema,
  dias: EnteroNoNegativoRpcSchema,
  zona: v.literal('America/Lima'),
})

const AsesorDerivacionesSchema = v.object({
  asesor_id: UuidSchema,
  asesor_nombre: v.string(),
  derivados: EnteroNoNegativoRpcSchema,
  capital_pen: CapitalSchema,
  capital_usd: CapitalSchema,
  sin_primer_contacto: EnteroNoNegativoRpcSchema,
  contactados: EnteroNoNegativoRpcSchema,
  contactabilidad_pct: PorcentajeSchema,
  repartido_hoy: EnteroNoNegativoRpcSchema,
})

const MovimientoDerivacionHoySchema = v.object({
  lead_id: UuidSchema,
  asesor_id: UuidSchema,
  asesor_nombre: v.string(),
  nombre_completo: v.string(),
  monto_estimado: v.nullable(CapitalSchema),
  moneda: MonedaSchema,
  derivado_en: FechaHoraSchema,
  reversible: v.boolean(),
})

/** Contrato de la foto de derivaciones del supervisor, siempre en hora Lima. */
export const ReporteDerivacionesEquipoSchema = v.object({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  periodo: PeriodoDerivacionesSchema,
  asesores: v.array(AsesorDerivacionesSchema),
  movimientos_hoy: v.array(MovimientoDerivacionHoySchema),
})

export type ReporteDerivacionesEquipo = v.InferOutput<typeof ReporteDerivacionesEquipoSchema>
export type AsesorDerivaciones = v.InferOutput<typeof AsesorDerivacionesSchema>
export type MovimientoDerivacionHoy = v.InferOutput<typeof MovimientoDerivacionHoySchema>

export const ResultadoDerivarLeadsEquipoSchema = v.object({
  version: v.literal(1),
  derivados: EnteroNoNegativoRpcSchema,
  lead_ids: v.array(UuidSchema),
})

export const ResultadoRevertirDerivacionEquipoSchema = v.object({
  version: v.literal(1),
  lead_id: UuidSchema,
  devuelto_a_bandeja: v.literal(true),
})

export type ResultadoDerivarLeadsEquipo = v.InferOutput<typeof ResultadoDerivarLeadsEquipoSchema>
export type ResultadoRevertirDerivacionEquipo = v.InferOutput<typeof ResultadoRevertirDerivacionEquipoSchema>
