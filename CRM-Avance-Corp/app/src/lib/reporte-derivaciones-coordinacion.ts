import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'

const PeriodoDerivacionesCoordinacionSchema = v.object({
  desde: FechaSchema,
  hasta: FechaSchema,
  dias: EnteroNoNegativoRpcSchema,
  zona: v.literal('America/Lima'),
})

const AnalistaDerivacionesDiaSchema = v.object({
  analista_id: UuidSchema,
  analista_nombre: TextoNoVacioSchema,
  supervisor_id: UuidSchema,
  supervisor_nombre: TextoNoVacioSchema,
  derivados: EnteroNoNegativoRpcSchema,
})

const DerivacionesDiaSchema = v.object({
  fecha: FechaSchema,
  total_derivados: EnteroNoNegativoRpcSchema,
  analistas: v.array(AnalistaDerivacionesDiaSchema),
})

/** Reporte agregado y sin PII que Coordinación usa para su rendición diaria. */
export const ReporteDerivacionesCoordinacionSchema = v.object({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  periodo: PeriodoDerivacionesCoordinacionSchema,
  total_derivados: EnteroNoNegativoRpcSchema,
  dias: v.array(DerivacionesDiaSchema),
})

export type ReporteDerivacionesCoordinacion = v.InferOutput<typeof ReporteDerivacionesCoordinacionSchema>
export type DerivacionesDia = v.InferOutput<typeof DerivacionesDiaSchema>
export type AnalistaDerivacionesDia = v.InferOutput<typeof AnalistaDerivacionesDiaSchema>

/**
 * Candado semántico adicional al schema: evita pintar totales o fechas que no
 * reconcilien con el período solicitado aunque el JSON tenga tipos válidos.
 */
export function reporteDerivacionesCoordinacionConsistente(
  reporte: ReporteDerivacionesCoordinacion,
  desde: string,
  hasta: string,
): boolean {
  if (reporte.periodo.desde !== desde || reporte.periodo.hasta !== hasta) return false
  const diasEsperados = Math.round(
    (Date.parse(`${hasta}T12:00:00-05:00`) - Date.parse(`${desde}T12:00:00-05:00`))
      / 86_400_000,
  ) + 1
  if (reporte.periodo.dias !== diasEsperados) return false
  if (reporte.dias.length !== reporte.periodo.dias) return false

  const fechas = new Set<string>()
  let total = 0
  for (const dia of reporte.dias) {
    if (dia.fecha < desde || dia.fecha > hasta || fechas.has(dia.fecha)) return false
    fechas.add(dia.fecha)
    const totalDia = dia.analistas.reduce((suma, analista) => suma + analista.derivados, 0)
    if (totalDia !== dia.total_derivados) return false
    total += totalDia
  }
  return total === reporte.total_derivados
}
