import * as v from 'valibot'

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

const ModalidadReunionesSchema = v.intersect([
  v.object({
    modalidad: v.picklist(['presencial', 'virtual', 'sin_clasificar']),
    pactadas: v.number(),
    debieron_ocurrir: v.number(),
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
])

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
