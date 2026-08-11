// La conversión mensual ponderada del asesor — el CONTRATO del front con
// `crm.conversion_mensual_fn` (migración 20260811154434).
//
// La definición (vault: «Conversion mensual - definicion cerrada», 2026-08-10):
//   divisor   = leads NO referidos que el asesor RECIBIÓ en el mes (asignación,
//               hora de Lima); entran abiertos y descartados, nada se cae.
//   numerador = cierres DEL MES: no referidos al 100 % + referidos × el peso
//               vigente (hoy 15 %). Un lead de julio cerrado en agosto suma
//               arriba en agosto y NO abajo.
//
// Decisiones de contrato que NO son estilo:
// - `v.object` (no strict) A PROPÓSITO: una clave nueva del servidor no debe
//   romper bundles viejos. Es lo contrario del cumplimiento (`v.strictObject`,
//   fail-closed) y está decidido así en el plan (§4).
// - `estado` es un `v.picklist` y un picklist SÍ rechaza valores desconocidos
//   aunque el objeto sea laxo: si faltara uno de los CUATRO estados aquí, el
//   payload ENTERO se caería por CONVERSION_MENSUAL_CONTRACT y las pantallas se
//   quedarían sin conversión (mismo tipo de defecto que el `maxValue(100)` que
//   este ciclo corrige en objetivos.ts).
// - `conversion_pct` NO tiene techo. Puede superar 100 con `estado='medible'` y
//   sin ninguna fila enferma (referidos que suman arriba y no abajo, cierres de
//   arrastre). El front NO recorta a 100 ni pinta barras acotadas con él.
// - `fuentes.*` son LITERALES fail-closed: si un servidor viejo (u otra
//   definición) colara otro reloj para el divisor, el parseo rechaza en vez de
//   pintar un número de otra fórmula.
// - `NumeroRpcSchema` en vez de `v.number()` crudo (a diferencia de sus
//   hermanas `metricas-conversiones*.ts`): `numerador` es `numeric` de Postgres
//   y PostgREST puede servirlo como string; el pipe lo normaliza a número.
import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  NumeroRpcSchema,
  UuidSchema,
} from './esquemas-rpc'
import { numero } from './format'

/** Porcentaje sin techo: la definición supera el 100 % por diseño. */
const PorcentajeSinTechoSchema = v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0)))

/** Los CUATRO estados que emite el servidor. `indisponible` NO está aquí a
 * propósito: es el quinto estado y lo produce SOLO el cliente (fail-closed de
 * colección incompleta en conversion-vendedores.ts), jamás el payload. */
export const ESTADOS_CONVERSION_MENSUAL = [
  'medible',
  'solo_referidos',
  'solo_arrastre',
  'sin_actividad',
] as const

const EstadoResponsableSchema = v.picklist(ESTADOS_CONVERSION_MENSUAL)

/** Vocabulario CERRADO — espejo del `case` de la migración. Añadir un motivo en
 * el servidor exige añadirlo aquí en el MISMO release. */
const MotivoNoMedibleSchema = v.nullable(
  v.picklist([
    'sin_ledger',
    'anterior_al_ledger',
    'mes_parcial',
    'sin_supervisor',
    'supervisor_inactivo',
    'supervisor_no_es_supervisor',
  ]),
)

const TramoProcedenciaSchema = v.object({
  /** null en el cubo `anteriores` (cierres de más de 11 meses atrás). */
  mes: v.nullable(v.string()),
  mes_nombre: v.string(),
  anio: v.nullable(v.pipe(NumeroRpcSchema, v.integer())),
  cierres: EnteroNoNegativoRpcSchema,
  cierres_referidos: EnteroNoNegativoRpcSchema,
})

const ReferidosResponsableSchema = v.object({
  recibidos: EnteroNoNegativoRpcSchema,
  cerrados: EnteroNoNegativoRpcSchema,
  dados_de_alta: EnteroNoNegativoRpcSchema,
  aporta_pct: PorcentajeSinTechoSchema,
})

const ResponsableConversionSchema = v.object({
  vendedor_id: UuidSchema,
  supervisor_id: v.nullable(UuidSchema),
  divisor: EnteroNoNegativoRpcSchema,
  cierres_no_referidos: EnteroNoNegativoRpcSchema,
  cierres_referidos: EnteroNoNegativoRpcSchema,
  /** Cierres del mes cuyo divisor fue OTRO mes: el sumando que explica un
   * ratio por encima de 100 sin recorrer `procedencia`. */
  cierres_de_arrastre: EnteroNoNegativoRpcSchema,
  numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
  conversion_pct: PorcentajeSinTechoSchema,
  estado: EstadoResponsableSchema,
  procedencia: v.array(TramoProcedenciaSchema),
  referidos: ReferidosResponsableSchema,
})

const TotalConversionSchema = v.object({
  analistas: EnteroNoNegativoRpcSchema,
  divisor: EnteroNoNegativoRpcSchema,
  cierres_no_referidos: EnteroNoNegativoRpcSchema,
  cierres_referidos: EnteroNoNegativoRpcSchema,
  cierres_de_arrastre: EnteroNoNegativoRpcSchema,
  referidos_recibidos: EnteroNoNegativoRpcSchema,
  numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
  conversion_pct: PorcentajeSinTechoSchema,
  referidos_aporta_pct: PorcentajeSinTechoSchema,
})

export const ConversionMensualSchema = v.object({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  /** Lo decide el SERVIDOR, que conoce el recorte; el front solo lo lee. */
  alcance: v.picklist(['propio', 'equipo', 'global']),
  periodo: v.object({
    mes: v.pipe(v.string(), v.regex(/^\d{4}-\d{2}$/)),
    mes_nombre: v.string(),
    anio: v.pipe(NumeroRpcSchema, v.integer()),
    zona: v.literal('America/Lima'),
    desde: FechaHoraSchema,
    hasta: FechaHoraSchema,
  }),
  ponderacion: v.object({
    referido: v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(1)),
    fuente: v.literal('crm.conversion_pesos'),
  }),
  // Tokens de versión del contrato, no la fórmula (la migración documenta por
  // qué `numerador` dice `resultado_en` aunque la consulta defienda con
  // coalesce). Cambiarlos exige cambiar servidor y front en el MISMO deploy —
  // que es exactamente lo que este literal existe para impedir por accidente.
  fuentes: v.object({
    divisor: v.literal('crm.lead_asignaciones.asignado_en'),
    numerador: v.literal('crm.lead_asignaciones.resultado_en'),
    referido: v.literal('crm.lead_asignaciones.origen'),
  }),
  cobertura: v.object({
    /** false = «sin datos», que es una frase MUY distinta de «0 %». */
    medible: v.boolean(),
    suelo_historico: v.nullable(FechaHoraSchema),
    motivo_no_medible: MotivoNoMedibleSchema,
    divisor_aproximado: EnteroNoNegativoRpcSchema,
    divisor_por_motivo: v.record(v.string(), EnteroNoNegativoRpcSchema),
    /** Sonda: cierres cuya ficha dice «convertido» sin episodio que lo respalde
     * en la ventana. Avisa en vez de mentir; > 0 es un aviso de integridad. */
    cierres_sin_episodio: EnteroNoNegativoRpcSchema,
    /** Agregado SIN identidad a propósito (ni un uuid): producción fuera del
     * roster ni se pierde ni se atribuye. */
    fuera_de_roster: v.object({
      analistas: EnteroNoNegativoRpcSchema,
      divisor: EnteroNoNegativoRpcSchema,
      cierres: EnteroNoNegativoRpcSchema,
      numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
    }),
  }),
  total: TotalConversionSchema,
  responsables: v.array(ResponsableConversionSchema),
})

export type ConversionMensual = v.InferOutput<typeof ConversionMensualSchema>
export type ResponsableConversionMensual = ConversionMensual['responsables'][number]
export type EstadoResponsableConversion = ResponsableConversionMensual['estado']
export type TramoProcedencia = ResponsableConversionMensual['procedencia'][number]

/**
 * «de agosto 12, de julio 3, de junio 1» — la línea que responde a la pregunta
 * de gerencia: ¿de qué mes venía cada cierre?
 *
 * El mes ya viene NOMBRADO del servidor (array literal en la migración, inmune
 * al locale). El año solo se escribe cuando difiere del año del periodo — «de
 * diciembre 2025 2» — y el cubo de más de 11 meses atrás se rotula «de meses
 * anteriores». Sin cierres devuelve '' y la pantalla decide su vacío.
 */
export function lineaProcedencia(
  procedencia: readonly TramoProcedencia[],
  anioPeriodo: number,
): string {
  return procedencia
    .filter((tramo) => tramo.cierres > 0)
    .map((tramo) => {
      if (tramo.mes === null) return `de meses anteriores ${tramo.cierres}`
      const anio = tramo.anio != null && tramo.anio !== anioPeriodo ? ` ${tramo.anio}` : ''
      return `de ${tramo.mes_nombre}${anio} ${tramo.cierres}`
    })
    .join(', ')
}

/**
 * «20 registrados · 12 cerrados · aporta 2,0 %» — el bloque de referidos.
 *
 * «Registrados» son los RECIBIDOS (decisión D3): con T10 ya no están en el
 * divisor, pero son la población de la que salen los cierres que ponderan.
 * `aporta_pct` viene en PUNTOS de porcentaje y aquí se escribe como «%» porque
 * así lo pidió Miguel (definición cerrada, «expresado en %, no en puntos»).
 * Con divisor 0 (`solo_referidos`) el aporte no existe y el tramo se omite.
 */
export function lineaReferidos(
  referidos: ResponsableConversionMensual['referidos'],
): string {
  const base = `${numero(referidos.recibidos)} registrados · ${numero(referidos.cerrados)} cerrados`
  if (referidos.aporta_pct == null) return base
  // SIEMPRE un decimal («aporta 2.0 %», no «aporta 2 %»): con el 15 % la cifra
  // casi nunca es entera y un «2 %» pelado parecería otra magnitud al lado de
  // un «1.6 %». `numero()` no fuerza decimales mínimos, así que se fija aquí.
  // es-PE usa PUNTO decimal (como el resto del CRM); la coma del vault era prosa.
  const aporta = referidos.aporta_pct.toLocaleString('es-PE', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })
  return `${base} · aporta ${aporta} %`
}
