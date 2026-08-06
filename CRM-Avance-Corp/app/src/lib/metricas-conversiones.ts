import * as v from 'valibot'

const PorcentajeSchema = v.nullable(v.number())
const PeriodoMetricasSchema = v.object({
  desde: v.string(),
  hasta: v.string(),
  dias: v.number(),
  zona: v.literal('America/Lima'),
})

const CohorteConversionesSchema = v.object({
  leads: v.number(),
  asignados: v.number(),
  contactados: v.number(),
  reuniones_agendadas: v.number(),
  reuniones_realizadas: v.number(),
  propuestas: v.number(),
  clientes: v.number(),
  contratos: v.number(),
  descartados: v.number(),
  conversion_clientes_pct: PorcentajeSchema,
  conversion_contratos_pct: PorcentajeSchema,
  conversion_resueltos_pct: PorcentajeSchema,
})

const ProduccionConversionesSchema = v.object({
  clientes: v.number(),
  contratos: v.number(),
  capital_pen: v.number(),
  capital_usd: v.number(),
})

const PasoEmbudoSchema = v.object({
  etapa: v.picklist([
    'leads',
    'contactados',
    'reuniones_agendadas',
    'reuniones_realizadas',
    'propuestas',
    'clientes',
    'contratos',
  ]),
  cantidad: v.number(),
  pct_anterior: PorcentajeSchema,
  pct_total: PorcentajeSchema,
})

const ConversionPorOrigenSchema = v.object({
  origen: v.string(),
  leads: v.number(),
  contactados: v.number(),
  reuniones_agendadas: v.number(),
  reuniones_realizadas: v.number(),
  clientes: v.number(),
  contratos: v.number(),
  descartados: v.number(),
  conversion_clientes_pct: PorcentajeSchema,
  conversion_contratos_pct: PorcentajeSchema,
  conversion_resueltos_pct: PorcentajeSchema,
  capital_pen: v.number(),
  capital_usd: v.number(),
})

const ConversionPorCategoriaSchema = v.object({
  categoria: v.string(),
  leads: v.number(),
  clientes: v.number(),
  contratos: v.number(),
  descartados: v.number(),
  conversion_pct: PorcentajeSchema,
})

const TendenciaSemanalVendedorSchema = v.object({
  semana: v.number(),
  desde: v.string(),
  hasta: v.string(),
  leads: v.number(),
  clientes: v.number(),
  conversion_pct: PorcentajeSchema,
})

const DetalleConversionVendedorSchema = v.object({
  vendedor_id: v.string(),
  leads: v.number(),
  contactados: v.number(),
  reuniones_realizadas: v.number(),
  clientes: v.number(),
  conversion_pct: PorcentajeSchema,
  capital_pen: v.number(),
  capital_usd: v.number(),
  tendencia_semanal: v.array(TendenciaSemanalVendedorSchema),
})

export const MetricasConversionesSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  periodo: PeriodoMetricasSchema,
  cohorte: CohorteConversionesSchema,
  produccion: ProduccionConversionesSchema,
  embudo: v.array(PasoEmbudoSchema),
  origenes: v.array(ConversionPorOrigenSchema),
  categorias: v.array(ConversionPorCategoriaSchema),
  responsables: v.optional(v.array(DetalleConversionVendedorSchema)),
})

export type MetricasConversiones = v.InferOutput<typeof MetricasConversionesSchema>
export type DetalleConversionVendedor = v.InferOutput<typeof DetalleConversionVendedorSchema>
