import type { ConversionEquipoVendedor } from './conversion-equipo'
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

export type EstadoConversionVendedor = 'comparable' | 'sin_muestra' | 'indisponible'

export interface ConversionVendedorAdaptada {
  vendedorId: string
  nombre: string
  supervisorNombre: string
  detalle: DetalleConversionVendedor | null
  estadoConversion: EstadoConversionVendedor
}

export interface ConversionVendedoresAdaptada {
  /**
   * `true` solo cuando la RPC entregó una fila única para cada vendedor visible.
   * Una colección ausente, vacía o parcial nunca equivale a métricas en cero ni
   * permite construir un ranking representativo del equipo completo.
   */
  responsablesDisponibles: boolean
  vendedores: ConversionVendedorAdaptada[]
  tendenciaSemanal: DetalleConversionVendedor['tendencia_semanal'] | null
}

export type ConversionVendedorConDetalle = ConversionVendedorAdaptada & {
  detalle: DetalleConversionVendedor
}

export interface RankingConversionVendedores {
  conPuesto: ConversionVendedorConDetalle[]
  sinMuestra: ConversionVendedorConDetalle[]
  indisponibles: ConversionVendedorAdaptada[]
}

export type EstadoCapitalVendedor = 'comparable' | 'sin_meta' | 'indisponible'

function porNombre(
  a: Pick<ConversionVendedorAdaptada, 'nombre' | 'vendedorId'>,
  b: Pick<ConversionVendedorAdaptada, 'nombre' | 'vendedorId'>,
): number {
  return a.nombre.localeCompare(b.nombre, 'es') || a.vendedorId.localeCompare(b.vendedorId)
}

function estadoConversion(
  detalle: DetalleConversionVendedor | null,
): EstadoConversionVendedor {
  if (!detalle || (detalle.leads > 0 && detalle.conversion_pct == null)) return 'indisponible'
  return detalle.leads === 0 ? 'sin_muestra' : 'comparable'
}

function agregarTendenciaSemanal(
  responsables: NonNullable<MetricasConversiones['responsables']>,
): DetalleConversionVendedor['tendencia_semanal'] {
  const semanas = new Map<string, Omit<DetalleConversionVendedor['tendencia_semanal'][number], 'conversion_pct'>>()

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
    .map((punto) => ({
      ...punto,
      conversion_pct: punto.leads > 0
        ? Math.round((1000 * punto.clientes) / punto.leads) / 10
        : null,
    }))
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
    tendenciaSemanal: responsablesCompletos ? agregarTendenciaSemanal(responsables) : null,
  }
}

export function clasificarRankingConversion(
  vendedores: readonly ConversionVendedorAdaptada[],
): RankingConversionVendedores {
  const conPuesto = vendedores
    .filter((fila): fila is ConversionVendedorConDetalle => (
      fila.estadoConversion === 'comparable' && fila.detalle != null
    ))
    .sort((a, b) => {
      const detalleA = a.detalle
      const detalleB = b.detalle
      return (detalleB?.conversion_pct ?? -1) - (detalleA?.conversion_pct ?? -1)
        || (detalleB?.clientes ?? -1) - (detalleA?.clientes ?? -1)
        || (detalleB?.leads ?? -1) - (detalleA?.leads ?? -1)
        || porNombre(a, b)
    })
  const sinMuestra = vendedores
    .filter((fila): fila is ConversionVendedorConDetalle => (
      fila.estadoConversion === 'sin_muestra' && fila.detalle != null
    ))
    .sort(porNombre)
  const indisponibles = vendedores
    .filter((fila) => fila.estadoConversion === 'indisponible')
    .sort(porNombre)

  return { conPuesto, sinMuestra, indisponibles }
}

export interface CapitalTotalVendedor {
  vendedor: ConversionVendedorAdaptada
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

export type CapitalTotalConPuesto = CapitalTotalVendedor & {
  capitalPen: number
  capitalUsd: number
  capitalTotal: number
  metaCapital: number
  avance: number
  estadoCapital: 'comparable'
}

export type CapitalTotalSinMeta = CapitalTotalVendedor & {
  capitalPen: number
  capitalUsd: number
  capitalTotal: number
  metaCapital: null
  avance: null
  estadoCapital: 'sin_meta'
}

export interface RankingCapitalTotalVendedores {
  conPuesto: CapitalTotalConPuesto[]
  sinMeta: CapitalTotalSinMeta[]
  indisponibles: CapitalTotalVendedor[]
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
export function clasificarRankingCapitalTotal(
  vendedores: readonly ConversionVendedorAdaptada[],
  metas: ObjetivosPorVendedor,
  cumplimientos: Record<string, CumplimientoVendedor>,
  tc: number | null,
): RankingCapitalTotalVendedores {
  // La política de conversión vive en lib/capital-unificado (fuente única): la
  // comparten este ranking y las filas de equipo desde la decisión #10.
  const tcValido = tcAplicable(tc)

  const filas = vendedores.map<CapitalTotalVendedor>((vendedor) => {
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
    .filter((fila): fila is CapitalTotalConPuesto => (
      fila.estadoCapital === 'comparable'
      && fila.capitalTotal != null
      && fila.metaCapital != null
      && fila.avance != null
    ))
    .sort((a, b) => (b.avance ?? -1) - (a.avance ?? -1)
      || (b.capitalTotal ?? -1) - (a.capitalTotal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const sinMeta = filas
    .filter((fila): fila is CapitalTotalSinMeta => (
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

