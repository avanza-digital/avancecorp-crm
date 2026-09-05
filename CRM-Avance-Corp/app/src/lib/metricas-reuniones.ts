import * as v from 'valibot'
import { EnteroNoNegativoRpcSchema } from './esquemas-rpc'

const PorcentajeSchema = v.nullable(v.number())
const PeriodoMetricasSchema = v.object({
  desde: v.string(),
  hasta: v.string(),
  dias: v.number(),
  zona: v.literal('America/Lima'),
})

const CapitalConversionSchema = v.object({
  leads_reunidos: v.number(),
  clientes: v.number(),
  contratos: v.number(),
  conversion_cliente_pct: PorcentajeSchema,
  conversion_contrato_pct: PorcentajeSchema,
  capital_pen: v.number(),
  capital_usd: v.number(),
})

const ResumenReunionesSchema = v.object({
  pactadas: v.number(),
  debieron_ocurrir: v.number(),
  realizadas: v.number(),
  no_concretadas: v.number(),
  no_show: v.number(),
  canceladas: v.number(),
  canceladas_sistema: v.number(),
  reprogramadas: v.number(),
  pendientes_cierre: v.number(),
  programadas_futuras: v.number(),
  pct_realizacion: PorcentajeSchema,
  pct_asistencia: PorcentajeSchema,
})

const ModalidadReunionesSchema = v.pipe(v.intersect([
  v.object({
    modalidad: v.picklist(['presencial', 'virtual', 'sin_clasificar']),
    pactadas: v.number(),
    debieron_ocurrir: v.number(),
    // N2: proyección del divisor y las exclusiones ya usados por el servidor.
    // Opcionales para payloads anteriores; ausencia nunca equivale a cero.
    divisor_realizacion: v.optional(EnteroNoNegativoRpcSchema),
    canceladas_sistema_vencidas: v.optional(EnteroNoNegativoRpcSchema),
    reprogramadas_vencidas: v.optional(EnteroNoNegativoRpcSchema),
    realizadas: v.number(),
    no_concretadas: v.number(),
    no_show: v.number(),
    canceladas: v.number(),
    reprogramadas: v.number(),
    pendientes_cierre: v.number(),
    pct_realizacion: PorcentajeSchema,
    pct_asistencia: PorcentajeSchema,
  }),
  CapitalConversionSchema,
]), v.check((fila) => {
  if (fila.divisor_realizacion == null
      || fila.canceladas_sistema_vencidas == null
      || fila.reprogramadas_vencidas == null) return true
  return fila.canceladas_sistema_vencidas + fila.reprogramadas_vencidas <= fila.debieron_ocurrir
    && fila.reprogramadas_vencidas <= fila.reprogramadas
    && fila.divisor_realizacion
      === fila.debieron_ocurrir - fila.canceladas_sistema_vencidas - fila.reprogramadas_vencidas
    && fila.realizadas <= fila.divisor_realizacion
}, 'Divisor o exclusiones incompatibles con los estados de la modalidad'))

const ReunionesPorOrigenSchema = v.object({
  origen: v.string(),
  pactadas: v.number(),
  realizadas: v.number(),
  no_show: v.number(),
  canceladas: v.number(),
  pct_realizacion: PorcentajeSchema,
  leads_reunidos: v.number(),
  clientes: v.number(),
  contratos: v.number(),
  conversion_contrato_pct: PorcentajeSchema,
})

const ReunionesPorResponsableSchema = v.object({
  responsable_id: v.nullable(v.string()),
  nombre: v.string(),
  rol: v.nullable(v.string()),
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.string(),
  pactadas: v.number(),
  realizadas: v.number(),
  no_show: v.number(),
  canceladas: v.number(),
  reprogramadas: v.number(),
  pendientes_cierre: v.number(),
  pct_realizacion: PorcentajeSchema,
})

const ResultadoReunionSchema = v.object({
  resultado: v.string(),
  cantidad: v.number(),
})

export const MetricasReunionesSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  periodo: PeriodoMetricasSchema,
  resumen: ResumenReunionesSchema,
  conversion: CapitalConversionSchema,
  modalidades: v.array(ModalidadReunionesSchema),
  origenes: v.array(ReunionesPorOrigenSchema),
  responsables: v.array(ReunionesPorResponsableSchema),
  resultados: v.array(ResultadoReunionSchema),
})

export type MetricasReuniones = v.InferOutput<typeof MetricasReunionesSchema>
