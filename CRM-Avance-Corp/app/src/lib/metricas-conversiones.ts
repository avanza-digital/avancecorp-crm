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
  // F1.3 (27/08): convertidos del rango sin rastro de capital (ni perfil ni
  // cierre externo). Opcional: el espejo demo y un servidor previo no la
  // emiten — ausente, la pantalla simplemente no rotula el hueco.
  sin_rastro: v.optional(v.number()),
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
  // F2.1 (decisión D6): cuánto pesa cada cierre de este origen en el numerador
  // del núcleo, y si el origen queda FUERA de la base (Referido). Opcionales:
  // el espejo demo no las emite.
  peso_en_nucleo: v.optional(v.number()),
  fuera_del_divisor_del_nucleo: v.optional(v.boolean()),
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
  // F2.1: la cifra del núcleo por responsable (misma aritmética que HOY).
  nucleo_divisor: v.optional(v.number()),
  nucleo_numerador: v.optional(v.number()),
  nucleo_conversion_pct: v.optional(PorcentajeSchema),
})

// ── F2.1 («Conversión única», decisión D2): la cifra principal y sus sondas ──
// Formas medidas en el payload REAL de producción el 27/08. Opcionales porque
// el espejo demo aún no las produce (deuda N4-N6): la pantalla degrada al
// comportamiento anterior cuando faltan, jamás fabrica ceros.

const NucleoConversionesSchema = v.object({
  base: v.string(),
  atribucion: v.optional(v.literal('primer_analista')),
  llegadas: v.optional(v.number()),
  altas_manuales: v.optional(v.number()),
  renovaciones: v.optional(v.number()),
  upgrades: v.optional(v.number()),
  aporte_cartera: v.optional(v.number()),
  peso_renovacion: v.optional(v.number()),
  divisor: v.number(),
  numerador: v.number(),
  conversion_pct: PorcentajeSchema,
  cierres_no_referidos: v.number(),
  cierres_referidos: v.number(),
  referidos_recibidos: v.number(),
  referidos_cierran_pct: PorcentajeSchema,
  operaciones_cartera: v.number(),
  peso_referido: v.number(),
  mes_peso: v.string(),
  incluye_cartera: v.boolean(),
})

const CosechaConversionesSchema = v.object({
  base: v.string(),
  leads: v.number(),
  cerraron: v.number(),
  conversion_pct: PorcentajeSchema,
  madura_hasta: v.string(),
})

const SondasConversionesSchema = v.object({
  cuadra: v.nullable(v.boolean()),
  paridad_nucleo: v.nullable(v.number()),
  paridad_filas: v.number(),
  divisor_fuera_del_roster: v.number(),
  numerador_fuera_del_roster: v.number(),
  cierres_sin_ficha_convertida: v.number(),
  cohorte_convertidos_sin_cierre_elegible: v.number(),
  cartera_fuera_del_rango: v.number(),
  cierres_anulados: v.number(),
  episodios_sin_origen: v.number(),
  origen_ficha_distinto_del_ledger: v.number(),
  // F1.3b: clientes con leads de MÁS de un analista — si sube de 0, el
  // capital por analista puede sumar más que el total (el mismo contrato
  // cuenta a ambos) y el front lo avisa. Opcional: servidores previos y el
  // espejo demo no la emiten.
  perfiles_con_leads_de_varios_vendedores: v.optional(v.number()),
})

export const MetricasConversionesSchema = v.object({
  // Filtro de origen aplicado por el servidor (null/ausente = todos). Se
  // declara SIEMPRE desde la migración del 28/08; opcional por servidores previos.
  origen_filtrado: v.optional(v.nullable(v.string())),
  version: v.literal(1),
  generado_en: v.string(),
  periodo: PeriodoMetricasSchema,
  cohorte: CohorteConversionesSchema,
  produccion: ProduccionConversionesSchema,
  embudo: v.array(PasoEmbudoSchema),
  origenes: v.array(ConversionPorOrigenSchema),
  categorias: v.array(ConversionPorCategoriaSchema),
  responsables: v.optional(v.array(DetalleConversionVendedorSchema)),
  nucleo: v.optional(NucleoConversionesSchema),
  cosecha: v.optional(CosechaConversionesSchema),
  sondas: v.optional(SondasConversionesSchema),
})

export type NucleoConversiones = v.InferOutput<typeof NucleoConversionesSchema>
export type CosechaConversiones = v.InferOutput<typeof CosechaConversionesSchema>
export type SondasConversiones = v.InferOutput<typeof SondasConversionesSchema>

export type MetricasConversiones = v.InferOutput<typeof MetricasConversionesSchema>
export type DetalleConversionVendedor = v.InferOutput<typeof DetalleConversionVendedorSchema>
