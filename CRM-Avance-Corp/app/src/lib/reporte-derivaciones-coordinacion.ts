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

const EntregaDerivacionDiaSchema = v.object({
  analista_id: UuidSchema,
  analista_nombre: TextoNoVacioSchema,
  supervisor_id: UuidSchema,
  supervisor_nombre: TextoNoVacioSchema,
  origen: TextoNoVacioSchema,
  derivados: EnteroNoNegativoRpcSchema,
})

const DerivacionesDiaSchema = v.object({
  fecha: FechaSchema,
  total_derivados: EnteroNoNegativoRpcSchema,
  analistas: v.array(AnalistaDerivacionesDiaSchema),
  /** Mismo total de `analistas`, abierto por el origen histórico del ledger. */
  entregas: v.array(EntregaDerivacionDiaSchema),
})

/** Reporte agregado sin PII de leads que Coordinación usa para su rendición diaria. */
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
export type EntregaDerivacionDia = v.InferOutput<typeof EntregaDerivacionDiaSchema>

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

    const clavesAnalistas = new Set<string>()
    const totalesAnalista = new Map<string, number>()
    for (const analista of dia.analistas) {
      const clave = `${analista.supervisor_id}:${analista.analista_id}`
      if (clavesAnalistas.has(clave)) return false
      clavesAnalistas.add(clave)
      totalesAnalista.set(clave, analista.derivados)
    }

    const clavesEntregas = new Set<string>()
    const totalesOrigenPorAnalista = new Map<string, number>()
    for (const entrega of dia.entregas) {
      const claveAnalista = `${entrega.supervisor_id}:${entrega.analista_id}`
      const claveEntrega = `${claveAnalista}:${entrega.origen}`
      if (clavesEntregas.has(claveEntrega)) return false
      clavesEntregas.add(claveEntrega)
      totalesOrigenPorAnalista.set(
        claveAnalista,
        (totalesOrigenPorAnalista.get(claveAnalista) ?? 0) + entrega.derivados,
      )
    }

    if (totalesAnalista.size !== totalesOrigenPorAnalista.size) return false
    for (const [clave, derivados] of totalesAnalista) {
      if (totalesOrigenPorAnalista.get(clave) !== derivados) return false
    }

    const totalDia = dia.analistas.reduce((suma, analista) => suma + analista.derivados, 0)
    if (totalDia !== dia.total_derivados) return false
    total += totalDia
  }
  return total === reporte.total_derivados
}
