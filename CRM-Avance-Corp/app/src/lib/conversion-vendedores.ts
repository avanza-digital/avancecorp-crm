import type { ConversionEquipoVendedor } from './conversion-equipo'
import type {
  ConversionMensual,
  ResponsableConversionMensual,
} from './conversion-mensual'
import type {
  DetalleConversionVendedor,
  MetricasConversiones,
} from './metricas-conversiones'
import {
  capitalObjetivo,
  capitalReal,
  type CumplimientoVendedor,
  type ObjetivosPorVendedor,
} from './objetivos'
import { tcAplicable, totalEnSoles } from './capital-unificado'

/**
 * Los estados del vendedor en el ranking. Mapa CERRADO servidor→front (la
 * conversión mensual emite cuatro; el quinto lo produce SOLO el cliente):
 *
 *   medible         → 'comparable'      (tiene divisor: compite por puesto)
 *   solo_arrastre   → 'solo_arrastre'   (divisor 0 pero CERRÓ cartera vieja:
 *                                        entra al ranking, al fondo, sin %)
 *   solo_referidos  → 'solo_referidos'  (divisor 0 pero RECIBIÓ referidos:
 *                                        trabajó; se rotula aparte, jamás como
 *                                        «sin muestra» — leerlo como «no
 *                                        trabajó» es la confusión que este
 *                                        estado existe para impedir)
 *   sin_actividad   → 'sin_muestra'     (ni recibió ni cerró)
 *   (fail-closed)   → 'indisponible'    (colección incompleta: SOLO cliente)
 *
 * Los payloads viejos (metricas_conversiones_fn / _equipo_fn) no traen estado
 * del servidor y siguen derivando comparable/sin_muestra de sus números — sus
 * casos de test NO se invierten (miden otro payload).
 */
export type EstadoConversionVendedor =
  | 'comparable'
  | 'solo_arrastre'
  | 'solo_referidos'
  | 'sin_muestra'
  | 'indisponible'

/**
 * Lo ÚNICO que el ranking de conversión necesita de un vendedor.
 *
 * Se nombra aparte porque hay dos payloads que lo satisfacen: el de gerencia
 * (`metricas_conversiones_fn`, que trae mucho más) y el del equipo del supervisor
 * (`metricas_conversiones_equipo_fn`, que a propósito trae solo esto — menos
 * superficie que auditar). El clasificador y la tabla usan estos tres campos y
 * nada más: verificado en clasificarRankingConversion y en RankingConversion.
 */
export interface DetalleRankeable {
  leads: number
  clientes: number
  conversion_pct: number | null
  /**
   * Solo el payload de la conversión MENSUAL los trae (los dos viejos no):
   * con numerador ponderado, el entero `clientes` deja de ordenar bien y el
   * desempate baja a numerador y luego divisor. Opcionales para que los
   * payloads viejos sigan satisfaciendo la interfaz sin cambiar.
   */
  numerador?: number
  divisor?: number
}

/**
 * `D` es el detalle que trae cada payload. Por defecto el COMPLETO de gerencia,
 * para que sus pantallas (inteligencia-comercial, resumen-gerencia) sigan viendo
 * capital, contactados y tendencia con el tipo exacto; el ranking del supervisor
 * la instancia con su detalle reducido. Un genérico y no un estrechamiento: lo
 * segundo habría dejado sin tipar a esas dos pantallas.
 */
export interface ConversionVendedorAdaptada<D extends DetalleRankeable = DetalleConversionVendedor> {
  vendedorId: string
  nombre: string
  supervisorNombre: string
  detalle: D | null
  estadoConversion: EstadoConversionVendedor
}

/**
 * Punto semanal del EQUIPO: solo los enteros servidos, sumados. Desde F3 el
 * navegador NO deriva un % semanal del equipo — el servidor no lo sirve, y
 * fabricarlo aquí era exactamente la clase de aritmética paralela (H12) que
 * «Conversión única» vino a matar. Si algún día hace falta la curva de %, se
 * sirve desde la tabla-base, no se divide en el cliente.
 */
export interface PuntoTendenciaEquipo {
  semana: number
  desde: string
  hasta: string
  leads: number
  clientes: number
}

export interface ConversionVendedoresAdaptada<D extends DetalleRankeable = DetalleConversionVendedor> {
  /**
   * `true` solo cuando la RPC entregó una fila única para cada vendedor visible.
   * Una colección ausente, vacía o parcial nunca equivale a métricas en cero ni
   * permite construir un ranking representativo del equipo completo.
   */
  responsablesDisponibles: boolean
  vendedores: ConversionVendedorAdaptada<D>[]
  tendenciaSemanal: PuntoTendenciaEquipo[] | null
}

export type ConversionVendedorConDetalle<D extends DetalleRankeable = DetalleConversionVendedor> =
  ConversionVendedorAdaptada<D> & { detalle: D }

export interface RankingConversionVendedores<D extends DetalleRankeable = DetalleConversionVendedor> {
  conPuesto: ConversionVendedorConDetalle<D>[]
  sinMuestra: ConversionVendedorConDetalle<D>[]
  indisponibles: ConversionVendedorAdaptada<D>[]
}

export type EstadoCapitalVendedor = 'comparable' | 'sin_meta' | 'indisponible'

function porNombre(
  a: Pick<ConversionVendedorAdaptada, 'nombre' | 'vendedorId'>,
  b: Pick<ConversionVendedorAdaptada, 'nombre' | 'vendedorId'>,
): number {
  return a.nombre.localeCompare(b.nombre, 'es') || a.vendedorId.localeCompare(b.vendedorId)
}

export function estadoConversion(
  detalle: DetalleRankeable | null,
  estadoServidor?: 'medible' | 'solo_referidos' | 'solo_arrastre' | 'sin_actividad',
): EstadoConversionVendedor {
  if (!detalle) return 'indisponible'
  // El payload de la conversión mensual DECLARA el estado y el servidor es la
  // única fuente que puede distinguir «solo recibió referidos» de «no recibió
  // nada» (los dos tienen divisor 0). Derivarlo aquí sería inventar.
  if (estadoServidor !== undefined) {
    if (estadoServidor === 'medible') {
      // Con divisor > 0 el % es obligatorio; si falta, la fila está enferma y
      // se declara indisponible en vez de competir con un dato a medias.
      return detalle.conversion_pct == null ? 'indisponible' : 'comparable'
    }
    if (estadoServidor === 'sin_actividad') return 'sin_muestra'
    return estadoServidor
  }
  // Payloads viejos (sin estado del servidor): la derivación de siempre.
  if (detalle.leads > 0 && detalle.conversion_pct == null) return 'indisponible'
  return detalle.leads === 0 ? 'sin_muestra' : 'comparable'
}

/** Suma por semana los enteros SERVIDOS por responsable. Sin divisiones (F3). */
function tendenciaSemanalEquipo(
  responsables: NonNullable<MetricasConversiones['responsables']>,
): PuntoTendenciaEquipo[] {
  const semanas = new Map<string, PuntoTendenciaEquipo>()

  for (const responsable of responsables) {
    for (const punto of responsable.tendencia_semanal) {
      const clave = `${punto.semana}|${punto.desde}|${punto.hasta}`
      const existente = semanas.get(clave)
      if (existente) {
        existente.leads += punto.leads
        existente.clientes += punto.clientes
      } else {
        semanas.set(clave, {
          semana: punto.semana,
          desde: punto.desde,
          hasta: punto.hasta,
          leads: punto.leads,
          clientes: punto.clientes,
        })
      }
    }
  }

  return [...semanas.values()]
    .sort((a, b) => a.desde.localeCompare(b.desde) || a.semana - b.semana)
}

/**
 * Une identidad visible del equipo con métricas autoritativas de la RPC.
 * Ninguna métrica operativa de `equipo` se usa como fallback: sus contadores
 * pueden pertenecer a otro corte y una ausencia de la RPC no representa cero.
 */
export function adaptarConversionVendedores(
  datos: MetricasConversiones | null | undefined,
  equipo: readonly ConversionEquipoVendedor[],
): ConversionVendedoresAdaptada {
  const responsables = datos?.responsables
  const detallePorId = new Map(
    (responsables ?? []).map((detalle) => [detalle.vendedor_id, detalle]),
  )
  const identidadPorId = new Map<string, Pick<ConversionEquipoVendedor, 'nombre' | 'supervisorNombre'>>()

  for (const integrante of equipo) {
    if (!integrante.vendedorId || identidadPorId.has(integrante.vendedorId)) continue
    identidadPorId.set(integrante.vendedorId, {
      nombre: integrante.nombre,
      supervisorNombre: integrante.supervisorNombre,
    })
  }

  // Una fila válida de la RPC no debe desaparecer si todavía no llegó su
  // identidad al store. La etiqueta genérica evita exponer el UUID en pantalla.
  for (const detalle of responsables ?? []) {
    if (identidadPorId.has(detalle.vendedor_id)) continue
    identidadPorId.set(detalle.vendedor_id, {
      nombre: 'Vendedor no identificado',
      supervisorNombre: 'Equipo no disponible',
    })
  }

  const responsablesCompletos = responsables !== undefined
    && detallePorId.size === responsables.length
    && [...identidadPorId.keys()].every((vendedorId) => detallePorId.has(vendedorId))

  const vendedores = [...identidadPorId.entries()].map(([vendedorId, identidad]) => {
    // Una respuesta parcial no puede otorgar puestos solo al subconjunto que
    // llegó: todo el bloque se marca como no disponible hasta recuperar el
    // contrato completo de la RPC.
    const detalle = responsablesCompletos ? (detallePorId.get(vendedorId) ?? null) : null
    return {
      vendedorId,
      ...identidad,
      detalle,
      estadoConversion: estadoConversion(detalle),
    }
  })

  return {
    responsablesDisponibles: responsablesCompletos,
    vendedores,
    tendenciaSemanal: responsablesCompletos ? tendenciaSemanalEquipo(responsables) : null,
  }
}

/**
 * El detalle del ranking cuando la fuente es la conversión MENSUAL ponderada.
 * `leads`/`clientes` se rellenan con divisor/cierres para satisfacer
 * DetalleRankeable (las columnas se re-rotulan «Recibidos»/«Cierres» en
 * pantalla); el resto viaja para el sheet: procedencia, referidos y el
 * arrastre que explica un % por encima de 100.
 */
export interface DetalleConversionMensual extends DetalleRankeable {
  numerador: number
  divisor: number
  estado: ResponsableConversionMensual['estado']
  cierres_de_arrastre: number
  procedencia: ResponsableConversionMensual['procedencia']
  referidos: ResponsableConversionMensual['referidos']
  /** El descuento por anulaciones de meses cerrados que su numerador ya trae restado. */
  ajuste: ResponsableConversionMensual['ajuste']
  supervisorId: string | null
}

/**
 * Adapta el payload de `crm.conversion_mensual_fn` al ranking. MISMO
 * fail-closed que `adaptarConversionVendedores`: una colección ausente o
 * parcial marca TODO como indisponible — jamás ceros, jamás puestos con un
 * subconjunto.
 */
export function adaptarConversionMensual(
  datos: ConversionMensual | null | undefined,
  equipo: readonly ConversionEquipoVendedor[],
): ConversionVendedoresAdaptada<DetalleConversionMensual> {
  const responsables = datos?.responsables
  const detallePorId = new Map(
    (responsables ?? []).map((fila) => [fila.vendedor_id, fila]),
  )
  const identidadPorId = new Map<string, Pick<ConversionEquipoVendedor, 'nombre' | 'supervisorNombre'>>()

  for (const integrante of equipo) {
    if (!integrante.vendedorId || identidadPorId.has(integrante.vendedorId)) continue
    identidadPorId.set(integrante.vendedorId, {
      nombre: integrante.nombre,
      supervisorNombre: integrante.supervisorNombre,
    })
  }
  for (const fila of responsables ?? []) {
    if (identidadPorId.has(fila.vendedor_id)) continue
    identidadPorId.set(fila.vendedor_id, {
      nombre: 'Vendedor no identificado',
      supervisorNombre: 'Equipo no disponible',
    })
  }

  const responsablesCompletos = responsables !== undefined
    && detallePorId.size === responsables.length
    && [...identidadPorId.keys()].every((vendedorId) => detallePorId.has(vendedorId))

  const vendedores = [...identidadPorId.entries()].map(([vendedorId, identidad]) => {
    const fila = responsablesCompletos ? (detallePorId.get(vendedorId) ?? null) : null
    const detalle: DetalleConversionMensual | null = fila === null ? null : {
      leads: fila.divisor,
      clientes: fila.cierres_no_referidos + fila.cierres_referidos,
      conversion_pct: fila.conversion_pct,
      numerador: fila.numerador,
      divisor: fila.divisor,
      estado: fila.estado,
      cierres_de_arrastre: fila.cierres_de_arrastre,
      procedencia: fila.procedencia,
      referidos: fila.referidos,
      ajuste: fila.ajuste,
      supervisorId: fila.supervisor_id,
    }
    return {
      vendedorId,
      ...identidad,
      detalle,
      estadoConversion: estadoConversion(detalle, fila?.estado),
    }
  })

  return {
    responsablesDisponibles: responsablesCompletos,
    vendedores,
    // El payload mensual no trae tendencia semanal: mide OTRA pregunta.
    tendenciaSemanal: null,
  }
}

export function clasificarRankingConversion<D extends DetalleRankeable>(
  vendedores: readonly ConversionVendedorAdaptada<D>[],
): RankingConversionVendedores<D> {
  // Tres cubos y CINCO estados: los nuevos viven DENTRO de los cubos de
  // siempre a propósito — un cubo nuevo haría desaparecer a esa gente de toda
  // pantalla que concatene los tres (el modo de fallo que ya costó caro: verde
  // en 1.600 tests y nadie en pantalla). El rótulo distinto lo pone la pantalla
  // leyendo `estadoConversion`, no la estructura.
  //   conPuesto  ← comparable + solo_arrastre (cerró: compite; sin %, al fondo)
  //   sinMuestra ← sin_muestra + solo_referidos (sin divisor; rótulo propio)
  //   indisponibles ← fail-closed del cliente
  const conPuesto = vendedores
    .filter((fila): fila is ConversionVendedorConDetalle<D> => (
      (fila.estadoConversion === 'comparable' || fila.estadoConversion === 'solo_arrastre')
      && fila.detalle != null
    ))
    .sort((a, b) => {
      const detalleA = a.detalle
      const detalleB = b.detalle
      // `?? -1` deja los % en NULL (solo_arrastre) al fondo del ranking: ya no
      // es código muerto, es la regla que impide que un null encabece nada.
      // El desempate baja a numerador y luego divisor (payload mensual); los
      // payloads viejos no los traen y caen a clientes/leads, su orden de
      // siempre.
      return (detalleB?.conversion_pct ?? -1) - (detalleA?.conversion_pct ?? -1)
        || (detalleB?.numerador ?? detalleB?.clientes ?? -1)
          - (detalleA?.numerador ?? detalleA?.clientes ?? -1)
        || (detalleB?.divisor ?? detalleB?.leads ?? -1)
          - (detalleA?.divisor ?? detalleA?.leads ?? -1)
        || porNombre(a, b)
    })
  const sinMuestra = vendedores
    .filter((fila): fila is ConversionVendedorConDetalle<D> => (
      (fila.estadoConversion === 'sin_muestra' || fila.estadoConversion === 'solo_referidos')
      && fila.detalle != null
    ))
    .sort(porNombre)
  const indisponibles = vendedores
    .filter((fila) => fila.estadoConversion === 'indisponible')
    .sort(porNombre)

  return { conPuesto, sinMuestra, indisponibles }
}

export interface CapitalTotalVendedor<D extends DetalleRankeable = DetalleConversionVendedor> {
  vendedor: ConversionVendedorAdaptada<D>
  capitalPen: number | null
  capitalUsd: number | null
  /** PEN + USD convertido al TC; sin TC, solo PEN (el USD se rotula aparte). */
  capitalTotal: number | null
  /** Split crudo de la meta (0 si no hay meta): permite rotular el recorte sin TC. */
  metaPen: number
  metaUsd: number
  metaCapital: number | null
  avance: number | null
  estadoCapital: EstadoCapitalVendedor
}

export type CapitalTotalConPuesto<D extends DetalleRankeable = DetalleConversionVendedor> = CapitalTotalVendedor<D> & {
  capitalPen: number
  capitalUsd: number
  capitalTotal: number
  metaCapital: number
  avance: number
  estadoCapital: 'comparable'
}

export type CapitalTotalSinMeta<D extends DetalleRankeable = DetalleConversionVendedor> = CapitalTotalVendedor<D> & {
  capitalPen: number
  capitalUsd: number
  capitalTotal: number
  metaCapital: null
  avance: null
  estadoCapital: 'sin_meta'
}

export interface RankingCapitalTotalVendedores<D extends DetalleRankeable = DetalleConversionVendedor> {
  conPuesto: CapitalTotalConPuesto<D>[]
  sinMeta: CapitalTotalSinMeta<D>[]
  indisponibles: CapitalTotalVendedor<D>[]
  /** TC realmente aplicado; null = el USD quedó FUERA del total (jamás se inventa tasa). */
  tc: number | null
}

/**
 * Ranking por capital TOTAL en soles: PEN + USD convertido al TC del BCRP que
 * resuelve el servidor (edge crm-tipo-cambio). Es la única conversión admitida
 * por la regla PEN≠USD (decisión 2026-07-17: la meta se mide en soles y el USD
 * cuenta convertido, no sumado a ciegas). Sin TC el total degrada a solo-PEN y
 * el USD se muestra aparte — mismo fail-closed que la meta del vendedor.
 * La meta también unifica (objetivo USD legado convertido; hoy las metas están
 * normalizadas a PEN, así que suele ser solo el objetivo en soles).
 */
export function clasificarRankingCapitalTotal<D extends DetalleRankeable>(
  vendedores: readonly ConversionVendedorAdaptada<D>[],
  metas: ObjetivosPorVendedor,
  cumplimientos: Record<string, CumplimientoVendedor>,
  tc: number | null,
): RankingCapitalTotalVendedores<D> {
  // La política de conversión vive en lib/capital-unificado (fuente única): la
  // comparten este ranking y las filas de equipo desde la decisión #10.
  const tcValido = tcAplicable(tc)

  const filas = vendedores.map<CapitalTotalVendedor<D>>((vendedor) => {
    // Un cumplimiento SIN detalles no es «S/ 0 confirmado»: es un payload que la
    // frontera RPC no debería producir — se degrada a indisponible, no a puesto
    // con cero (hallazgo Codex: el tipo público no garantiza la matriz completa).
    const crudo = cumplimientos[vendedor.vendedorId]
    const cumplimiento = crudo != null && crudo.detalles.length > 0 ? crudo : undefined
    const capitalPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
    const capitalUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
    const capitalTotal = totalEnSoles(capitalPen, capitalUsd, tcValido).total
    const meta = metas[vendedor.vendedorId]
    const metaPen = meta ? capitalObjetivo(meta, 'PEN') : 0
    const metaUsd = meta ? capitalObjetivo(meta, 'USD') : 0
    const objetivo = meta ? totalEnSoles(metaPen, metaUsd, tcValido).total : null
    const metaCapital = objetivo != null && objetivo > 0 ? objetivo : null
    const estadoCapital: EstadoCapitalVendedor = cumplimiento == null
      ? 'indisponible'
      : metaCapital == null
        ? 'sin_meta'
        : 'comparable'

    return {
      vendedor,
      capitalPen,
      capitalUsd,
      capitalTotal,
      metaPen,
      metaUsd,
      metaCapital,
      avance: estadoCapital === 'comparable' && capitalTotal != null && metaCapital != null
        ? Math.max(0, (capitalTotal / metaCapital) * 100)
        : null,
      estadoCapital,
    }
  })

  const conPuesto = filas
    .filter((fila): fila is CapitalTotalConPuesto<D> => (
      fila.estadoCapital === 'comparable'
      && fila.capitalTotal != null
      && fila.metaCapital != null
      && fila.avance != null
    ))
    .sort((a, b) => (b.avance ?? -1) - (a.avance ?? -1)
      || (b.capitalTotal ?? -1) - (a.capitalTotal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const sinMeta = filas
    .filter((fila): fila is CapitalTotalSinMeta<D> => (
      fila.estadoCapital === 'sin_meta'
      && fila.capitalTotal != null
      && fila.metaCapital == null
      && fila.avance == null
    ))
    .sort((a, b) => (b.capitalTotal ?? -1) - (a.capitalTotal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const indisponibles = filas
    .filter((fila) => fila.estadoCapital === 'indisponible')
    .sort((a, b) => porNombre(a.vendedor, b.vendedor))

  return { conPuesto, sinMeta, indisponibles, tc: tcValido }
}

