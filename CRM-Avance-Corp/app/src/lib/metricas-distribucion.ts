import * as v from 'valibot'

/**
 * Contrato runtime de `crm.metricas_distribucion_leads_v2_fn` (JSON V2).
 *
 * La respuesta es una sola fotografía atómica. Por eso se valida completa y
 * con objetos estrictos: si una migración parcial, un dato corrupto o una V2
 * incompatible cambia cualquier rama, la pantalla falla cerrada en vez de
 * mezclar métricas con semánticas distintas.
 */

export const RANGOS_CAPITAL_PEN = [
  'pen_0_1000',
  'pen_1000_5000',
  'pen_5000_10000',
  'pen_10000_20000',
  'pen_20000_50000',
  'pen_50000_100000',
  'pen_mas_100000',
  'sin_monto',
] as const

export type RangoCapitalPenId = (typeof RANGOS_CAPITAL_PEN)[number]

const NUMERICO_RPC_RE = /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/

const NumericoRpcSchema = v.pipe(
  v.union([v.number(), v.string()]),
  v.check(
    (valor) => typeof valor === 'number' || NUMERICO_RPC_RE.test(valor.trim()),
    'Número RPC inválido',
  ),
  v.transform((valor) => Number(valor)),
  v.number(),
  v.finite(),
)

const EnteroNoNegativoSchema = v.pipe(
  NumericoRpcSchema,
  v.integer(),
  v.minValue(0),
)

const CapitalNoNegativoSchema = v.pipe(NumericoRpcSchema, v.minValue(0))
const IdSchema = v.pipe(v.string(), v.uuid())
const TextoNoVacioSchema = v.pipe(v.string(), v.minLength(1))
const FechaSchema = v.pipe(v.string(), v.isoDate())
const FechaHoraSchema = v.pipe(
  v.string(),
  v.check((valor) => Number.isFinite(Date.parse(valor)), 'Fecha/hora inválida'),
)

const RangoCapitalSchema = v.strictObject({
  id: v.picklist(RANGOS_CAPITAL_PEN),
  orden: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(8)),
  etiqueta: TextoNoVacioSchema,
  desde_exclusivo: v.nullable(CapitalNoNegativoSchema),
  hasta_inclusivo: v.nullable(CapitalNoNegativoSchema),
})

const RangosCapitalSchema = v.pipe(
  v.array(RangoCapitalSchema),
  v.length(RANGOS_CAPITAL_PEN.length),
  v.check(
    (rangos) => rangos.every(
      (rango, indice) =>
        rango.id === RANGOS_CAPITAL_PEN[indice]
        && rango.orden === indice + 1,
    ),
    'Catálogo de rangos PEN incompatible',
  ),
)

const CarteraActualSchema = v.strictObject({
  episodios: EnteroNoNegativoSchema,
  capital: CapitalNoNegativoSchema,
})

const CohorteRangoSchema = v.strictObject({
  episodios_recibidos: EnteroNoNegativoSchema,
  leads_unicos_recibidos: EnteroNoNegativoSchema,
  convertidos: EnteroNoNegativoSchema,
  descartados: EnteroNoNegativoSchema,
  leads_unicos_resueltos: EnteroNoNegativoSchema,
})

const RangoAnalistaSchema = v.strictObject({
  rango_id: v.picklist(RANGOS_CAPITAL_PEN),
  cartera_actual: CarteraActualSchema,
  cohorte: CohorteRangoSchema,
})

const RangosAnalistaSchema = v.pipe(
  v.array(RangoAnalistaSchema),
  v.length(RANGOS_CAPITAL_PEN.length),
  v.check(
    (rangos) => rangos.every(
      (rango, indice) => rango.rango_id === RANGOS_CAPITAL_PEN[indice],
    ),
    'Rangos del analista incompatibles',
  ),
)

const CapacidadAnalistaSchema = v.strictObject({
  objetivo: v.nullable(v.pipe(EnteroNoNegativoSchema, v.minValue(1), v.maxValue(1000))),
  carga_activa: EnteroNoNegativoSchema,
  carga_pen: EnteroNoNegativoSchema,
  carga_usd: EnteroNoNegativoSchema,
})

const PenAnalistaSchema = v.strictObject({
  cartera_actual: CarteraActualSchema,
  cohorte: v.strictObject({
    episodios_recibidos: EnteroNoNegativoSchema,
    leads_unicos_recibidos: EnteroNoNegativoSchema,
    convertidos: EnteroNoNegativoSchema,
    descartados: EnteroNoNegativoSchema,
    ciclos_resueltos: EnteroNoNegativoSchema,
    leads_unicos_resueltos: EnteroNoNegativoSchema,
  }),
  rangos: RangosAnalistaSchema,
})

const UsdAnalistaSchema = v.strictObject({
  cartera_actual_episodios: EnteroNoNegativoSchema,
  cartera_actual_capital: CapitalNoNegativoSchema,
  cohorte_episodios_recibidos: EnteroNoNegativoSchema,
  cohorte_leads_unicos: EnteroNoNegativoSchema,
  convertidos: EnteroNoNegativoSchema,
  descartados: EnteroNoNegativoSchema,
})

const OperacionAnalistaSchema = v.strictObject({
  cohorte_episodios: EnteroNoNegativoSchema,
  transferidos: EnteroNoNegativoSchema,
  parqueados: EnteroNoNegativoSchema,
  desactivados: EnteroNoNegativoSchema,
  sin_tocar_actual: EnteroNoNegativoSchema,
})

const AnalistaDistribucionSchema = v.strictObject({
  analista_id: IdSchema,
  nombre: TextoNoVacioSchema,
  rol: v.picklist(['vendedor', 'supervisor']),
  supervisor_id: v.nullable(IdSchema),
  supervisor_nombre: v.nullable(TextoNoVacioSchema),
  activo: v.boolean(),
  disponible_para_recibir: v.boolean(),
  capacidad: CapacidadAnalistaSchema,
  pen: PenAnalistaSchema,
  usd_no_segmentado: UsdAnalistaSchema,
  operacion: OperacionAnalistaSchema,
})

const RangoColaSchema = v.strictObject({
  rango_id: v.picklist(RANGOS_CAPITAL_PEN),
  cantidad: EnteroNoNegativoSchema,
  capital: CapitalNoNegativoSchema,
})

const RangosColaSchema = v.pipe(
  v.array(RangoColaSchema),
  v.length(RANGOS_CAPITAL_PEN.length),
  v.check(
    (rangos) => rangos.every(
      (rango, indice) => rango.rango_id === RANGOS_CAPITAL_PEN[indice],
    ),
    'Rangos de la cola incompatibles',
  ),
)

const PenColaSchema = v.strictObject({
  cantidad: EnteroNoNegativoSchema,
  capital: CapitalNoNegativoSchema,
  rangos: RangosColaSchema,
})

const UsdColaSchema = v.strictObject({
  cantidad: EnteroNoNegativoSchema,
  capital: CapitalNoNegativoSchema,
})

const ColaTotalSchema = v.strictObject({
  carga_total: EnteroNoNegativoSchema,
  pen: PenColaSchema,
  usd: UsdColaSchema,
})

const ColaGlobalSchema = v.strictObject({
  responsabilidad: v.literal('gerencia'),
  carga_total: EnteroNoNegativoSchema,
  pen: PenColaSchema,
  usd: UsdColaSchema,
})

const BandejaSupervisorSchema = v.strictObject({
  supervisor_id: IdSchema,
  supervisor_nombre: TextoNoVacioSchema,
  supervisor_activo: v.boolean(),
  carga_total: EnteroNoNegativoSchema,
  pen: PenColaSchema,
  usd: UsdColaSchema,
})

const ResumenDistribucionSchema = v.strictObject({
  leads_operativos_actuales: EnteroNoNegativoSchema,
  asignados_actuales: EnteroNoNegativoSchema,
  por_repartir_actuales: EnteroNoNegativoSchema,
  capital_pen_asignado_actual: CapitalNoNegativoSchema,
  capital_usd_asignado_actual: CapitalNoNegativoSchema,
  cohorte_episodios: EnteroNoNegativoSchema,
  cohorte_leads_unicos: EnteroNoNegativoSchema,
  convertidos_pen: EnteroNoNegativoSchema,
  descartados_pen: EnteroNoNegativoSchema,
  reasignaciones_cohorte: EnteroNoNegativoSchema,
})

const CalidadDistribucionSchema = v.strictObject({
  episodios_aproximados_actuales: EnteroNoNegativoSchema,
  episodios_aproximados_cohorte: EnteroNoNegativoSchema,
  episodios_sin_monto_actuales: EnteroNoNegativoSchema,
  episodios_sin_monto_cohorte: EnteroNoNegativoSchema,
})

export const MetricasDistribucionLeadsSchema = v.strictObject({
  version: v.literal(2),
  generado_en: FechaHoraSchema,
  cohorte: v.strictObject({
    desde_inclusivo: FechaSchema,
    hasta_inclusivo: FechaSchema,
    hasta_exclusivo: FechaSchema,
    criterio: v.literal('episodio_asignado_en'),
    zona_horaria: v.literal('America/Lima'),
  }),
  alcances: v.strictObject({
    matriz: v.literal('PEN'),
    capacidad: v.literal('TODAS_LAS_MONEDAS'),
    montos: v.literal('SEPARADOS_SIN_CONVERSION'),
  }),
  rangos: RangosCapitalSchema,
  resumen: ResumenDistribucionSchema,
  analistas: v.array(AnalistaDistribucionSchema),
  por_repartir: v.strictObject({
    total: ColaTotalSchema,
    global: ColaGlobalSchema,
    bandejas: v.array(BandejaSupervisorSchema),
  }),
  calidad: CalidadDistribucionSchema,
})

export type RangoCapitalPen = v.InferOutput<typeof RangoCapitalSchema>
export type RangoDistribucionAnalista = v.InferOutput<typeof RangoAnalistaSchema>
export type MetricaDistribucionAnalista = v.InferOutput<typeof AnalistaDistribucionSchema>
export type MetricasPorRepartir = v.InferOutput<
  typeof MetricasDistribucionLeadsSchema
>['por_repartir']
export type MetricasDistribucionLeads = v.InferOutput<
  typeof MetricasDistribucionLeadsSchema
>
