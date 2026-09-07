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
  leads_con_cierre_previo: v.optional(EnteroNoNegativoRpcSchema),
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
  divisor_realizacion: v.optional(EnteroNoNegativoRpcSchema),
  divisor_asistencia: v.optional(EnteroNoNegativoRpcSchema),
  canceladas_sistema_vencidas: v.optional(EnteroNoNegativoRpcSchema),
  reprogramadas_vencidas: v.optional(EnteroNoNegativoRpcSchema),
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
  leads_con_cierre_previo: v.optional(EnteroNoNegativoRpcSchema),
  clientes: v.number(),
  contratos: v.number(),
  conversion_contrato_pct: PorcentajeSchema,
})

const ReunionesPorResponsableSchema = v.pipe(v.object({
  responsable_id: v.nullable(v.string()),
  nombre: v.string(),
  rol: v.nullable(v.string()),
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.string(),
  pactadas: v.number(),
  debieron_ocurrir: v.optional(EnteroNoNegativoRpcSchema),
  divisor_realizacion: v.optional(EnteroNoNegativoRpcSchema),
  canceladas_sistema_vencidas: v.optional(EnteroNoNegativoRpcSchema),
  canceladas_ajenas_vencidas: v.optional(EnteroNoNegativoRpcSchema),
  reprogramadas_vencidas: v.optional(EnteroNoNegativoRpcSchema),
  programadas_futuras: v.optional(EnteroNoNegativoRpcSchema),
  realizadas: v.number(),
  no_show: v.number(),
  canceladas: v.number(),
  reprogramadas: v.number(),
  pendientes_cierre: v.number(),
  pct_realizacion: PorcentajeSchema,
}), v.check((fila) => {
  if (fila.divisor_realizacion == null || fila.debieron_ocurrir == null
      || fila.canceladas_sistema_vencidas == null || fila.canceladas_ajenas_vencidas == null
      || fila.reprogramadas_vencidas == null) return true
  return fila.divisor_realizacion === fila.debieron_ocurrir
      - fila.canceladas_sistema_vencidas - fila.canceladas_ajenas_vencidas - fila.reprogramadas_vencidas
    && fila.realizadas <= fila.divisor_realizacion
    && fila.debieron_ocurrir <= fila.pactadas
    && fila.canceladas_ajenas_vencidas <= fila.canceladas
    && fila.reprogramadas_vencidas <= fila.reprogramadas
}, 'Base o exclusiones incompatibles con las citas del responsable'))

const ResultadoReunionSchema = v.object({
  resultado: v.string(),
  cantidad: v.number(),
})

export const MetricasReunionesSchema = v.pipe(v.object({
  version: v.literal(1),
  generado_en: v.string(),
  periodo: PeriodoMetricasSchema,
  resumen: ResumenReunionesSchema,
  conversion: CapitalConversionSchema,
  modalidades: v.array(ModalidadReunionesSchema),
  origenes: v.array(ReunionesPorOrigenSchema),
  responsables: v.array(ReunionesPorResponsableSchema),
  resultados: v.array(ResultadoReunionSchema),
}), v.check((datos) => {
  const r = datos.resumen
  if (r.divisor_realizacion != null && r.canceladas_sistema_vencidas != null
      && r.reprogramadas_vencidas != null
      && (r.divisor_realizacion !== r.debieron_ocurrir - r.canceladas_sistema_vencidas - r.reprogramadas_vencidas
        || r.realizadas > r.divisor_realizacion)) return false
  if (r.divisor_asistencia != null && r.divisor_asistencia !== r.realizadas + r.no_show) return false
  // El total incluye responsables que ya no aparecen en el desglose. Un
  // residual negativo es un contrato inválido, no un cero que debamos ocultar.
  return ['pactadas', 'realizadas', 'pendientes_cierre'].every((campo) => {
    const clave = campo as 'pactadas' | 'realizadas' | 'pendientes_cierre'
    return datos.responsables.every((fila) => fila[clave] >= 0)
      && datos.responsables.reduce((suma, fila) => suma + fila[clave], 0) <= r[clave]
  }) && [datos.conversion, ...datos.modalidades, ...datos.origenes].every((fila) =>
    fila.leads_con_cierre_previo == null
    || fila.leads_con_cierre_previo + fila.contratos <= fila.leads_reunidos,
  )
}, 'Las bases, cierres o responsables no concilian con el resumen de citas'))

export type MetricasReuniones = v.InferOutput<typeof MetricasReunionesSchema>
