import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema, FechaHoraSchema, FechaSchema, NumeroRpcSchema, TextoNoVacioSchema, UuidSchema,
} from './esquemas-rpc'

export function fechaCorteCapital(fecha: string): string {
  return `${fecha.slice(8, 10)}/${fecha.slice(5, 7)}/${fecha.slice(0, 4)}`
}

const Importe = v.pipe(NumeroRpcSchema, v.minValue(0))
const ConteoMonedas = v.strictObject({ cantidad: EnteroNoNegativoRpcSchema, pen: Importe, usd: Importe })
const DetalleCapitalValoradoSchema = v.strictObject({
  categoria: v.picklist(['nuevo', 'renovacion', 'upgrade']),
  moneda: v.picklist(['PEN', 'USD']),
  capital_real: Importe,
  equivalente_pen: Importe,
  contratos_real: EnteroNoNegativoRpcSchema,
  capital_objetivo: Importe,
  contratos_objetivo: EnteroNoNegativoRpcSchema,
})

export const CapitalResumenSchema = v.strictObject({
  version: v.literal(1),
  corte: FechaSchema,
  generado_en: FechaHoraSchema,
  corte_id: UuidSchema,
  equivalente_pen: Importe,
  capital_pen: Importe,
  capital_usd: Importe,
  contratos: EnteroNoNegativoRpcSchema,
  objetivo_pen: Importe,
  meta_revision: EnteroNoNegativoRpcSchema,
  detalles: v.pipe(v.array(DetalleCapitalValoradoSchema), v.length(6), v.check((filas) => (
    new Set(filas.map((fila) => `${fila.categoria}:${fila.moneda}`)).size === 6
  ), 'El capital valorado debe conservar sus seis dimensiones')),
})
export type CapitalResumen = v.InferOutput<typeof CapitalResumenSchema>

export const CoberturaCapitalSchema = v.strictObject({
  corte: v.nullable(FechaSchema),
  generado_en: v.optional(v.nullable(FechaHoraSchema)),
  estado: v.picklist(['sin_corte', 'completo', 'pendiente', 'atascado']),
  pendientes: ConteoMonedas,
  por_incorporar: ConteoMonedas,
  ventas_pendientes: v.array(v.strictObject({
    fuente: v.picklist(['contrato', 'cierre_externo']),
    fuente_id: UuidSchema,
    fecha_comercial: v.nullable(FechaSchema),
    fecha_imputacion: FechaSchema,
    moneda: v.picklist(['PEN', 'USD']),
    monto: Importe,
    motivo: v.picklist(['fecha_comercial_sin_acreditar', 'cotizacion_pendiente', 'revision_pendiente']),
  })),
})
export type CoberturaCapital = v.InferOutput<typeof CoberturaCapitalSchema>

export const CapitalValoracionSchema = v.strictObject({
  activa: v.literal(true),
  version: v.literal(1),
  corte_id: v.nullable(UuidSchema),
  sellado: v.boolean(),
  personas: v.array(v.strictObject({
    vendedor_id: UuidSchema,
    nombre: TextoNoVacioSchema,
    supervisor_id: v.nullable(UuidSchema),
    supervisor_nombre: TextoNoVacioSchema,
    en_meta: v.boolean(),
    en_ranking: v.boolean(),
    rol_crm: v.string(),
    motivo: v.string(),
    capital_valorado: CapitalResumenSchema,
  })),
  cobertura: CoberturaCapitalSchema,
})
export type CapitalValoracion = v.InferOutput<typeof CapitalValoracionSchema>

export const CapitalOperacionesSchema = v.variant('valoracion_activa', [
  v.strictObject({ version: v.literal(1), valoracion_activa: v.literal(false) }),
  v.strictObject({
    version: v.literal(1), valoracion_activa: v.literal(true),
    corte_id: UuidSchema, corte: FechaSchema, total_pen: Importe,
    operaciones: v.array(v.strictObject({
      fuente: v.picklist(['contrato', 'cierre_externo']), fuente_id: UuidSchema,
      numero: TextoNoVacioSchema, fecha_comercial: FechaSchema, fecha_imputacion: FechaSchema,
      categoria: v.picklist(['nuevo', 'renovacion', 'upgrade']), moneda: v.picklist(['PEN', 'USD']),
      monto: Importe, tasa: v.pipe(NumeroRpcSchema, v.minValue(0.0001)), equivalente_pen: Importe,
      valoracion_id: UuidSchema, fecha_tc: v.nullable(FechaSchema), politica_tc: v.nullable(v.string()),
    })),
  }),
])
export type CapitalOperaciones = v.InferOutput<typeof CapitalOperacionesSchema>

/** Una medida ya aceptada por operación nunca vuelve a multiplicarse por TC. */
export function totalCapitalValorado(capital: CapitalResumen | null): number | null {
  return capital?.equivalente_pen ?? null
}

/** Solo se agregan filas de una misma publicación completa. */
export function sumarCapitalValorado(filas: readonly (CapitalResumen | null | undefined)[]): CapitalResumen | null | undefined {
  if (filas.every((fila) => fila === undefined)) return undefined
  const primera = filas[0]
  if (primera == null || filas.some((fila) => fila == null || fila.corte_id !== primera.corte_id)) return null
  const completas = filas as CapitalResumen[]
  const sumar = (valores: readonly number[]) => valores.reduce((suma, valor) => suma + Math.round(valor * 100), 0) / 100
  return {
    ...primera,
    equivalente_pen: sumar(completas.map((fila) => fila.equivalente_pen)),
    capital_pen: sumar(completas.map((fila) => fila.capital_pen)),
    capital_usd: sumar(completas.map((fila) => fila.capital_usd)),
    objetivo_pen: sumar(completas.map((fila) => fila.objetivo_pen)),
    contratos: completas.reduce((suma, fila) => suma + fila.contratos, 0),
    detalles: primera.detalles.map((dimension) => {
      const detalles = completas.flatMap((fila) => fila.detalles.filter((d) => (
        d.categoria === dimension.categoria && d.moneda === dimension.moneda
      )))
      return {
        ...dimension,
        capital_real: sumar(detalles.map((d) => d.capital_real)),
        equivalente_pen: sumar(detalles.map((d) => d.equivalente_pen)),
        capital_objetivo: sumar(detalles.map((d) => d.capital_objetivo)),
        contratos_real: detalles.reduce((suma, d) => suma + d.contratos_real, 0),
        contratos_objetivo: detalles.reduce((suma, d) => suma + d.contratos_objetivo, 0),
      }
    }),
  }
}
