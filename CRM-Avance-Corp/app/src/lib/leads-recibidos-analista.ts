import * as v from 'valibot'
import { fechaLima } from './agenda-derivada'
import { EnteroNoNegativoRpcSchema, FechaHoraSchema, FechaSchema } from './esquemas-rpc'
import type { Lead } from './tipos'
import { desplazarFechaDerivaciones } from './use-periodo-derivaciones'

const PeriodoLeadsRecibidosSchema = v.object({
  desde: FechaSchema,
  hasta: FechaSchema,
  dias: EnteroNoNegativoRpcSchema,
  zona: v.literal('America/Lima'),
})

const DiaLeadsRecibidosSchema = v.object({
  fecha: FechaSchema,
  total: EnteroNoNegativoRpcSchema,
  aproximados: EnteroNoNegativoRpcSchema,
})

/** Contrato sin PII del conteo diario propio del analista. */
export const LeadsRecibidosAnalistaSchema = v.object({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  periodo: PeriodoLeadsRecibidosSchema,
  total: EnteroNoNegativoRpcSchema,
  aproximados: EnteroNoNegativoRpcSchema,
  dias: v.array(DiaLeadsRecibidosSchema),
})

export type LeadsRecibidosAnalista = v.InferOutput<typeof LeadsRecibidosAnalistaSchema>
export type DiaLeadsRecibidos = v.InferOutput<typeof DiaLeadsRecibidosSchema>

/**
 * Certifica período, continuidad y sumas. Un JSON válido pero cruzado desde
 * otra clave de caché no puede mostrarse como si perteneciera al rango pedido.
 */
export function leadsRecibidosAnalistaConsistente(
  reporte: LeadsRecibidosAnalista,
  desde: string,
  hasta: string,
): boolean {
  if (reporte.periodo.desde !== desde || reporte.periodo.hasta !== hasta) return false
  if (reporte.dias.length !== reporte.periodo.dias) return false

  let fechaEsperada = desde
  let total = 0
  let aproximados = 0
  for (const dia of reporte.dias) {
    if (dia.fecha !== fechaEsperada || dia.aproximados > dia.total) return false
    total += dia.total
    aproximados += dia.aproximados
    fechaEsperada = desplazarFechaDerivaciones(fechaEsperada, 1)
  }

  return total === reporte.total
    && aproximados === reporte.aproximados
    && reporte.aproximados <= reporte.total
    && fechaEsperada === desplazarFechaDerivaciones(hasta, 1)
}

/**
 * Espejo de práctica: el demo no tiene el ledger histórico, así que representa
 * el episodio vigente mediante `tenencia_desde` y marca el fallback como
 * aproximado. La sesión real siempre consume la RPC autoritativa.
 */
export function leadsRecibidosAnalistaDesdeAmbito(
  leads: readonly Lead[],
  analistaId: string,
  desde: string,
  hasta: string,
  ahora = Date.now(),
): LeadsRecibidosAnalista {
  const porFecha = new Map<string, { total: number; aproximados: number }>()
  for (const lead of leads) {
    if (lead.vendedor_id !== analistaId) continue
    const sello = lead.tenencia_desde ?? lead.creado_en
    const instante = Date.parse(sello)
    if (!Number.isFinite(instante)) continue
    const fecha = fechaLima(instante)
    if (fecha < desde || fecha > hasta) continue
    const actual = porFecha.get(fecha) ?? { total: 0, aproximados: 0 }
    actual.total += 1
    if (!lead.tenencia_desde) actual.aproximados += 1
    porFecha.set(fecha, actual)
  }

  const dias: DiaLeadsRecibidos[] = []
  for (let fecha = desde; fecha <= hasta; fecha = desplazarFechaDerivaciones(fecha, 1)) {
    const valor = porFecha.get(fecha) ?? { total: 0, aproximados: 0 }
    dias.push({ fecha, ...valor })
  }

  return {
    version: 1,
    generado_en: new Date(ahora).toISOString(),
    periodo: {
      desde,
      hasta,
      dias: dias.length,
      zona: 'America/Lima',
    },
    total: dias.reduce((suma, dia) => suma + dia.total, 0),
    aproximados: dias.reduce((suma, dia) => suma + dia.aproximados, 0),
    dias,
  }
}
