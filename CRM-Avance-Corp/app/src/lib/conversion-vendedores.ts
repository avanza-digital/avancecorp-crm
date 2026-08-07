import type { ConversionEquipoVendedor } from './conversion-equipo'
import type {
  DetalleConversionVendedor,
  MetricasConversiones,
} from './metricas-conversiones'
import {
  capitalObjetivo,
  capitalReal,
  type CumplimientoVendedor,
  type MonedaMeta,
  type ObjetivosPorVendedor,
} from './objetivos'

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

export interface CapitalVendedorAdaptado {
  vendedor: ConversionVendedorAdaptada
  moneda: MonedaMeta
  capitalReal: number | null
  metaCapital: number | null
  avance: number | null
  estadoCapital: EstadoCapitalVendedor
}

export type CapitalVendedorConPuesto = CapitalVendedorAdaptado & {
  capitalReal: number
  metaCapital: number
  avance: number
  estadoCapital: 'comparable'
}

export type CapitalVendedorSinMeta = CapitalVendedorAdaptado & {
  capitalReal: number
  metaCapital: null
  avance: null
  estadoCapital: 'sin_meta'
}

export interface RankingCapitalVendedores {
  conPuesto: CapitalVendedorConPuesto[]
  sinMeta: CapitalVendedorSinMeta[]
  indisponibles: CapitalVendedorAdaptado[]
}

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

export function clasificarRankingCapital(
  vendedores: readonly ConversionVendedorAdaptada[],
  metas: ObjetivosPorVendedor,
  cumplimientos: Record<string, CumplimientoVendedor>,
  moneda: MonedaMeta,
): RankingCapitalVendedores {
  const filas = vendedores.map<CapitalVendedorAdaptado>((vendedor) => {
    const cumplimiento = cumplimientos[vendedor.vendedorId]
    const capitalConfirmado = cumplimiento ? capitalReal(cumplimiento, moneda) : null
    const meta = metas[vendedor.vendedorId]
    const objetivo = meta ? capitalObjetivo(meta, moneda) : null
    const metaCapital = objetivo != null && objetivo > 0 ? objetivo : null
    const estadoCapital: EstadoCapitalVendedor = cumplimiento == null
      ? 'indisponible'
      : metaCapital == null
        ? 'sin_meta'
        : 'comparable'

    return {
      vendedor,
      moneda,
      capitalReal: capitalConfirmado,
      metaCapital,
      avance: estadoCapital === 'comparable' && capitalConfirmado != null && metaCapital != null
        ? Math.max(0, (capitalConfirmado / metaCapital) * 100)
        : null,
      estadoCapital,
    }
  })

  const conPuesto = filas
    .filter((fila): fila is CapitalVendedorConPuesto => (
      fila.estadoCapital === 'comparable'
      && fila.capitalReal != null
      && fila.metaCapital != null
      && fila.avance != null
    ))
    .sort((a, b) => (b.avance ?? -1) - (a.avance ?? -1)
      || (b.capitalReal ?? -1) - (a.capitalReal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const sinMeta = filas
    .filter((fila): fila is CapitalVendedorSinMeta => (
      fila.estadoCapital === 'sin_meta'
      && fila.capitalReal != null
      && fila.metaCapital == null
      && fila.avance == null
    ))
    .sort((a, b) => (b.capitalReal ?? -1) - (a.capitalReal ?? -1)
      || porNombre(a.vendedor, b.vendedor))
  const indisponibles = filas
    .filter((fila) => fila.estadoCapital === 'indisponible')
    .sort((a, b) => porNombre(a.vendedor, b.vendedor))

  return { conPuesto, sinMeta, indisponibles }
}
