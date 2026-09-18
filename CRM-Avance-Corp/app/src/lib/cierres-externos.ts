// Cierres en cooperativas (COOPAC Qorilazo / Prodelco) — el CONTRATO del front
// con `crm.cierres_externos_fn` (migración 20260812000259).
//
// Fuente económica de una inversión en cooperativa. El cierre inicial conserva
// el lead y su conversión; F4 admite inversiones adicionales sin otro lead,
// incluso para una persona que ya tiene perfil Avance. El dinero se cuenta por
// fuente; la conversión sigue las reglas del servidor.
//
// Decisiones de contrato que NO son estilo:
// - `v.object` (no strict) A PROPÓSITO, como la conversión mensual: una clave
//   nueva del servidor no debe romper bundles viejos.
// - `cooperativa`/`moneda`/`documento_tipo`/`alcance` son picklists y SÍ
//   rechazan valores desconocidos aunque el objeto sea laxo: una cooperativa
//   nueva en el servidor exige tocar este archivo en el MISMO release (el chip,
//   el color y el rótulo no se inventan solos).
// - `monto`/`capital` pasan por `NumeroRpcSchema`: son `numeric` de Postgres y
//   PostgREST puede servirlos como string.
// - Los MINI-TOTALES salen de `totales` (servidor), NUNCA de sumar `cierres`:
//   las filas viajan con tope 200 (`cierres_total` dice cuántas hay de verdad)
//   y sumar una lista truncada mentiría.
import * as v from 'valibot'
import type { Moneda } from './format'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  UuidSchema,
} from './esquemas-rpc'

/** Las DOS cooperativas. Espejo del CHECK de `crm.cierres_externos`. */
export const COOPERATIVAS = ['qorilazo', 'prodelco'] as const
export type Cooperativa = (typeof COOPERATIVAS)[number]

/**
 * Rótulos, distintivo visual y MONEDAS ADMITIDAS por cooperativa (chips de Mi
 * cartera y reportes; el formulario de cierre usa `monedas`).
 *
 * `monedas` es un ESPEJO de `crm.empresas.monedas` en el servidor, igual que
 * `COOPERATIVAS` lo es del CHECK: aquí sirve para no ofrecerle al analista una
 * opción que el servidor rechazaría, no para imponer la regla. Quien la impone
 * es el catálogo del servidor, y por eso abrir o cerrar una moneda allí surte
 * efecto en el acto (lo que se pierde sin tocar esto es solo el selector).
 * Si mañana se abre otra combinación, este espejo se actualiza en ese release.
 *
 * Estado al 17/09/2026: Prodelco admite soles y dólares; Qorilazo solo soles.
 */
export const INFO_COOPERATIVA: Record<
  Cooperativa,
  {
    nombre: string
    corto: string
    chipClase: string
    /** Nunca vacío: una cooperativa sin moneda admitida no podría cerrar nada,
     *  y el tipo lo dice para que `monedas[0]` sea una moneda y no `undefined`. */
    monedas: readonly [Moneda, ...Moneda[]]
  }
> = {
  qorilazo: {
    nombre: 'COOPAC Qorilazo',
    corto: 'QORILAZO',
    // Ámbar: distinto del navy/azul de Avance y del rojo de estados de error.
    chipClase: 'bg-amber-100 text-amber-900 border border-amber-300',
    monedas: ['PEN'],
  },
  prodelco: {
    nombre: 'COOPAC Prodelco',
    corto: 'PRODELCO',
    // Violeta: nunca verde (regla de diseño de la casa).
    chipClase: 'bg-violet-100 text-violet-900 border border-violet-300',
    monedas: ['PEN', 'USD'],
  },
}

/** La moneda con la que se abre el formulario de una cooperativa. */
export function monedaPorDefecto(coop: Cooperativa): Moneda {
  return INFO_COOPERATIVA[coop].monedas[0]
}

/** ¿Hay que preguntar la moneda, o esta cooperativa solo admite una? */
export function pideMoneda(coop: Cooperativa): boolean {
  return INFO_COOPERATIVA[coop].monedas.length > 1
}

/** ¿Admite esta cooperativa esa moneda? Espejo del catálogo del servidor. */
export function admiteMoneda(coop: Cooperativa, moneda: Moneda): boolean {
  return INFO_COOPERATIVA[coop].monedas.includes(moneda)
}

const CooperativaSchema = v.picklist(COOPERATIVAS)
/** PEN o USD, espejo del CHECK de `crm.cierres_externos` (ensanchado el
 * 17/09/2026). QUÉ moneda admite cada cooperativa no se decide aquí: lo dice
 * `crm.empresas.monedas` en el servidor, reflejado en `INFO_COOPERATIVA`. */
const MonedaSchema = v.picklist(['PEN', 'USD'])

const CierreExternoSchema = v.object({
  cierre_id: UuidSchema,
  /** Inversión adicional F4: puede existir sin un nuevo lead. */
  lead_id: v.nullable(UuidSchema),
  cooperativa: CooperativaSchema,
  monto: v.pipe(NumeroRpcSchema, v.minValue(0)),
  moneda: MonedaSchema,
  nombre_completo: v.string(),
  documento_tipo: v.picklist(['DNI', 'CE', 'PASAPORTE']),
  documento: v.string(),
  telefono: v.nullable(v.string()),
  /** N.º de operación del depósito: la PRUEBA del cierre (obligatoria y única
   * por cooperativa en el servidor). Es lo que supervisor y gerencia contrastan. */
  numero_transaccion: v.string(),
  /** Certificado que emitió la coop: opcional, para papeleo. */
  referencia_externa: v.nullable(v.string()),
  vence_en: v.nullable(FechaSchema),
  plazo_meses: v.optional(v.nullable(v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)))),
  tasa_anual: v.optional(v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0)))),
  nota: v.nullable(v.string()),
  vendedor_id: UuidSchema,
  /** null si el perfil del analista ya no se puede resolver (left join). */
  vendedor_nombre: v.nullable(v.string()),
  creado_en: FechaHoraSchema,
  /** Opcionales para seguir admitiendo la respuesta anterior a F4. */
  fecha_comercial: v.optional(FechaSchema),
  fecha_imputacion: v.optional(FechaSchema),
  es_cierre_inicial: v.optional(v.boolean()),
  /** Anulado por gerencia (fraude o error). Las filas anuladas SÍ viajan —y se
   * marcan en pantalla— aunque no cuenten en `totales`: un analista tiene que
   * poder entender por qué le bajó el total, no encontrarse un hueco. */
  anulado_en: v.nullable(FechaHoraSchema),
  motivo_anulacion: v.nullable(v.string()),
})

const TotalCooperativaSchema = v.object({
  cooperativa: CooperativaSchema,
  moneda: MonedaSchema,
  capital: v.pipe(NumeroRpcSchema, v.minValue(0)),
  cierres: EnteroNoNegativoRpcSchema,
})

const EmpresaVendedorSchema = v.object({
  vendedor_id: UuidSchema,
  vendedor_nombre: v.nullable(v.string()),
  cooperativa: CooperativaSchema,
  moneda: MonedaSchema,
  capital: v.pipe(NumeroRpcSchema, v.minValue(0)),
  cierres: EnteroNoNegativoRpcSchema,
})

export const CierresExternosSchema = v.object({
  version: v.literal(1),
  /** El primer día del mes pedido — el eco que la API verifica. */
  periodo: FechaSchema,
  /** Lo decide el SERVIDOR (analista propio / supervisor equipo / gerencia y
   * lector global). El lector global recibe `cierres: []` a propósito: los
   * agregados son suyos, la PII de las filas es de los operadores. */
  alcance: v.picklist(['propio', 'equipo', 'global']),
  /** Histórico del ámbito, más reciente primero, TOPE 200. */
  cierres: v.array(CierreExternoSchema),
  /** Cuántos hay DE VERDAD en el ámbito (si supera 200, la lista vino trunca). */
  cierres_total: EnteroNoNegativoRpcSchema,
  /** Los cierres DEL MES pedido — la vista de revisión de supervisor y gerencia.
   * Viene del servidor y no de filtrar `cierres` en el cliente: esa lista llega
   * con tope 200 por antigüedad y podría no alcanzar el mes entero. */
  cierres_mes: v.array(CierreExternoSchema),
  cierres_mes_total: EnteroNoNegativoRpcSchema,
  /** Histórico del ámbito por cooperativa × moneda — la fuente de los
   * mini-totales (PEN/USD jamás sumados). */
  totales: v.array(TotalCooperativaSchema),
  /** El MES pedido, por analista × cooperativa × moneda — el desglose «Por
   * empresa» de supervisor y gerencia. La parte Avance NO viaja aquí: es
   * `capital_real` del cumplimiento menos estos agregados. */
  por_empresa: v.array(EmpresaVendedorSchema),
})

export type CierresExternos = v.InferOutput<typeof CierresExternosSchema>
export type CierreExterno = CierresExternos['cierres'][number]
export type TotalCooperativa = CierresExternos['totales'][number]
export type EmpresaVendedor = CierresExternos['por_empresa'][number]

/**
 * Capital Avance de un analista = su capital TOTAL del cumplimiento (que ya
 * incluye los cierres en coops) menos lo cerrado en coops en esa moneda.
 *
 * Clampa en 0 a propósito: entre dos fotografías (cumplimiento y cierres se
 * piden por separado) una carrera puede dejar la resta negativa un instante, y
 * un «Avance: −2.000» en pantalla sería un bug visible de un estado transitorio.
 */
export function capitalAvance(capitalTotal: number, capitalEnCoops: number): number {
  return Math.max(0, capitalTotal - capitalEnCoops)
}
