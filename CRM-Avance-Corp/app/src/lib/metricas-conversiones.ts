import * as v from 'valibot'
import { FechaHoraSchema, FechaSchema } from './esquemas-rpc'

const PorcentajeSchema = v.nullable(v.number())
const ConteoAmpliacionSchema = v.pipe(v.number(), v.integer(), v.minValue(0))
const AporteAmpliacionSchema = v.pipe(v.number(), v.finite(), v.minValue(0))
const FechaAmpliacionSchema = v.pipe(
  FechaSchema,
  v.check(
    (fecha) => new Date(`${fecha}T00:00:00.000Z`).toISOString().slice(0, 10) === fecha,
    'Fecha de calendario inválida',
  ),
)
const InstanteAmpliacionSchema = FechaHoraSchema

// Ampliaciones aditivas: faltar o venir null significa no disponible, nunca
// cero. Los aportes y porcentajes son valores servidos; aquí sólo se valida.
const CitasRealesSchema = v.pipe(v.object({
  version: v.literal(1),
  unidad: v.literal('lead_id'),
  base: v.literal('llegadas_unicas'),
  fecha_cita: v.literal('vence_en'),
  seguimiento_hasta: InstanteAmpliacionSchema,
  origen_filtrado: v.nullable(v.string()),
  atribucion: v.literal('primer_analista'),
  leads_base: ConteoAmpliacionSchema,
  leads_con_cita_real: ConteoAmpliacionSchema,
  citas_realizadas: ConteoAmpliacionSchema,
  citas_anteriores_al_alta: ConteoAmpliacionSchema,
  pct_llegadas_con_cita_real: v.nullable(AporteAmpliacionSchema),
}), v.check((dato) => dato.leads_con_cita_real <= dato.leads_base
  && dato.leads_con_cita_real <= dato.citas_realizadas
  && (dato.pct_llegadas_con_cita_real == null || dato.pct_llegadas_con_cita_real <= 100)))

const ConversionOperacionesSchema = v.pipe(v.object({
  version: v.literal(1),
  lectura: v.literal('viva'),
  completo: v.boolean(),
  desde: FechaAmpliacionSchema,
  hasta: FechaAmpliacionSchema,
  zona: v.literal('America/Lima'),
  origen_filtrado: v.null(),
  cantidad: ConteoAmpliacionSchema,
  aporte_total: AporteAmpliacionSchema,
  detalle: v.array(v.object({
    operacion_id: v.string(),
    analista_id: v.nullable(v.string()),
    categoria: v.picklist(['renovacion', 'upgrade']),
    periodo: FechaAmpliacionSchema,
    fecha_numerador: InstanteAmpliacionSchema,
    aporte_numerador: AporteAmpliacionSchema,
  })),
}), v.check((dato) => dato.cantidad === dato.detalle.length
  && new Set(dato.detalle.map((operacion) => operacion.operacion_id)).size === dato.detalle.length))

const SemanaCierresSchema = v.object({
  semana: v.pipe(ConteoAmpliacionSchema, v.minValue(1)),
  desde: FechaAmpliacionSchema,
  hasta: FechaAmpliacionSchema,
  cierres: ConteoAmpliacionSchema,
  aporte_cierres: AporteAmpliacionSchema,
})

const SemanaCierresGlobalSchema = v.intersect([
  SemanaCierresSchema,
  v.object({
    cierres_fuera_del_roster: ConteoAmpliacionSchema,
    aporte_cierres_fuera_del_roster: AporteAmpliacionSchema,
  }),
])

type SemanaCierreValidable = v.InferOutput<typeof SemanaCierresSchema>
const DIA_MS = 86_400_000

/** Valida la geometría temporal servida; no calcula ni sustituye métricas. */
function semanasCubrenPeriodo(
  semanas: readonly SemanaCierreValidable[],
  desde: string,
  hasta: string,
): boolean {
  const inicio = Date.parse(`${desde}T00:00:00.000Z`)
  const fin = Date.parse(`${hasta}T00:00:00.000Z`)
  if (!Number.isFinite(inicio) || !Number.isFinite(fin) || inicio > fin) return false
  if (semanas.length !== Math.floor((fin - inicio) / (7 * DIA_MS)) + 1) return false

  return semanas.every((semana, indice) => {
    const esperadoDesdeMs = inicio + indice * 7 * DIA_MS
    const esperadoHastaMs = Math.min(fin, esperadoDesdeMs + 6 * DIA_MS)
    return semana.semana === indice + 1
      && semana.desde === new Date(esperadoDesdeMs).toISOString().slice(0, 10)
      && semana.hasta === new Date(esperadoHastaMs).toISOString().slice(0, 10)
  })
}

const CierresPorSemanaSchema = v.pipe(v.object({
  version: v.literal(1),
  base: v.literal('fecha_numerador'),
  atribucion: v.literal('autor_cierre'),
  agrupacion: v.literal('bloques_7_dias_desde_inicio'),
  desde: FechaAmpliacionSchema,
  hasta: FechaAmpliacionSchema,
  zona: v.literal('America/Lima'),
  origen_filtrado: v.nullable(v.string()),
  incluye_operaciones_cartera: v.literal(false),
  cierres: ConteoAmpliacionSchema,
  aporte_cierres: AporteAmpliacionSchema,
  cierres_fuera_del_roster: ConteoAmpliacionSchema,
  aporte_cierres_fuera_del_roster: AporteAmpliacionSchema,
  semanas: v.array(SemanaCierresGlobalSchema),
}), v.check((dato) => semanasCubrenPeriodo(dato.semanas, dato.desde, dato.hasta)
  && dato.cierres_fuera_del_roster <= dato.cierres
  && dato.aporte_cierres_fuera_del_roster <= dato.aporte_cierres + Number.EPSILON
  && dato.semanas.reduce((total, semana) => total + semana.cierres, 0) === dato.cierres
  && Math.abs(dato.semanas.reduce((total, semana) => total + semana.aporte_cierres, 0) - dato.aporte_cierres) < 1e-9
  && dato.semanas.reduce((total, semana) => total + semana.cierres_fuera_del_roster, 0) === dato.cierres_fuera_del_roster
  && Math.abs(dato.semanas.reduce((total, semana) => total + semana.aporte_cierres_fuera_del_roster, 0) - dato.aporte_cierres_fuera_del_roster) < 1e-9,
'Semanas de cierre incompatibles con el período o sus totales'))
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
  // La misma cifra de la fila con cada cierre pesando lo que pesa en la
  // conversión general (el referido, a su peso). La calcula el SERVIDOR
  // (20260923185001); la pantalla solo la muestra. Opcional: un servidor previo
  // o el espejo demo no la emiten.
  conversion_ponderada_pct: v.optional(PorcentajeSchema),
  leads_con_cita_real: v.optional(v.nullable(ConteoAmpliacionSchema)),
  citas_realizadas: v.optional(v.nullable(ConteoAmpliacionSchema)),
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
  leads_con_cita_real: v.optional(v.nullable(ConteoAmpliacionSchema)),
  citas_realizadas: v.optional(v.nullable(ConteoAmpliacionSchema)),
  cierres_por_semana: v.optional(v.nullable(v.array(SemanaCierresSchema))),
})

// ── F2.1 («Conversión única», decisión D2): la cifra principal y sus sondas ──
// Formas medidas en el payload REAL de producción el 27/08. Opcionales porque
// el espejo demo aún no las produce (deuda N4-N6): la pantalla degrada al
// comportamiento anterior cuando faltan, jamás fabrica ceros.

const NucleoConversionesSchema = v.object({
  // ── EL CONTRATO DE LA UNIFICACIÓN (Ola 1 de las doce puertas) ─────────────
  // Cuatro claves que dicen DE DÓNDE salió la cifra, para que una pantalla
  // nunca vuelva a publicar un porcentaje sin decir qué es.
  //
  // 🔴 VAN OPCIONALES A PROPÓSITO, y el front entra PRIMERO. Regla de la casa:
  // una clave nueva en la RESPUESTA obliga a publicar el front antes que el
  // servidor. Si entrara el servidor primero, un bundle viejo con
  // `strictObject` rechazaría el payload entero y la pantalla se caería.
  // Mientras el servidor no las emita, `undefined` = «servidor previo».
  es_mes_calendario: v.optional(v.boolean()),
  fuente: v.optional(v.picklist(['mensual', 'rango_vivo'])),
  sellado: v.optional(v.nullable(v.boolean())),
  ajuste_aplicado: v.optional(v.boolean()),
  // Ola 1b: cuando la puerta DELEGA, lo que ella misma habría calculado viaja
  // al lado. Sirve para dos cosas concretas:
  //   · rotular en pantalla la distancia («4,16 % oficial · 4,32 % recalculado»)
  //     en vez de dejar un panel en blanco;
  //   · comparar los desgloses CON filtro de fuente —que nunca delegan— contra
  //     el divisor que de verdad usaron, no contra el de la foto oficial.
  // Ausente cuando no hubo delegación: lo publicado ya es el recálculo vivo.
  recalculo_vivo: v.optional(v.object({
    divisor: v.number(),
    numerador: v.number(),
    conversion_pct: PorcentajeSchema,
  })),
  base: v.string(),
  atribucion: v.optional(v.literal('primer_analista')),
  llegadas: v.optional(v.number()),
  altas_manuales: v.optional(v.number()),
  renovaciones: v.optional(v.number()),
  upgrades: v.optional(v.number()),
  aporte_cartera: v.optional(v.number()),
  peso_renovacion: v.optional(v.number()),
  // La ponderación con la que se calculó LA CIFRA OFICIAL de arriba: para un
  // mes sellado, la que guardó la foto. `peso_referido`/`peso_renovacion` son
  // otra cosa —los pesos VIVOS, que rotulan el desglose recalculado— y por eso
  // viven aparte. Opcional: servidor previo a `20260923172517` no la emite, y
  // tampoco aparece cuando no hubo delegación (no hay cifra sellada que rotular).
  ponderacion_oficial: v.optional(v.object({
    referido: v.number(),
    renovacion: v.number(),
    fuente: v.optional(v.string()),
  })),
  divisor: v.number(),
  numerador: v.number(),
  conversion_pct: PorcentajeSchema,
  cierres_no_referidos: v.number(),
  cierres_referidos: v.number(),
  referidos_recibidos: v.number(),
  referidos_cierran_pct: PorcentajeSchema,
  operaciones_cartera: v.number(),
  peso_referido: v.number(),
  /** Desde octubre 2026 los referidos de un analista cuentan como máximo este
   * porcentaje (0–100) de sus cierres de leads asignados. null o ausente = mes sin tope.
   * Con tope, `peso_referido × cierres` ya NO es el aporte: el servidor lo
   * entrega calculado. */
  tope_referidos_pct: v.optional(v.nullable(v.pipe(v.number(), v.minValue(0), v.maxValue(100)))),
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
  // Las dos sondas del contrato de unificación: si la puerta delegó, se
  // contrastó contra la mensual y se publica la diferencia. Opcionales por
  // servidores previos, igual que las de arriba.
  mensual_comparada: v.optional(v.boolean()),
  paridad_mensual: v.optional(v.nullable(v.number())),
})

export const MetricasConversionesSchema = v.pipe(v.object({
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
  citas_reales: v.optional(v.nullable(CitasRealesSchema)),
  conversion_operaciones: v.optional(v.nullable(ConversionOperacionesSchema)),
  cierres_por_semana: v.optional(v.nullable(CierresPorSemanaSchema)),
}), v.check((dato) => dato.responsables?.every((responsable) => (
  responsable.cierres_por_semana == null
    || semanasCubrenPeriodo(
      responsable.cierres_por_semana,
      dato.periodo.desde,
      dato.periodo.hasta,
    )
)) ?? true, 'Semanas por responsable incompatibles con el período'))

export type NucleoConversiones = v.InferOutput<typeof NucleoConversionesSchema>
export type CosechaConversiones = v.InferOutput<typeof CosechaConversionesSchema>
export type SondasConversiones = v.InferOutput<typeof SondasConversionesSchema>

export type MetricasConversiones = v.InferOutput<typeof MetricasConversionesSchema>
export type DetalleConversionVendedor = v.InferOutput<typeof DetalleConversionVendedorSchema>
