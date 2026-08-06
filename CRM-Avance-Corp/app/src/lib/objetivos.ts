import * as v from 'valibot'
import { fechaLima } from './agenda-derivada'

export interface ObjetivoComercial {
  capitalObjetivo: number
  ventasObjetivo: number
  conversionObjetivo: number
}

/** Única unidad editable: la meta mensual de una persona vendedora. */
export interface ObjetivoVendedor extends ObjetivoComercial {
  vendedorId: string
  /** Snapshot de la jerarquía al guardar; el servidor nunca confía en el cliente. */
  supervisorId: string | null
}

export type ObjetivosPorVendedor = Record<string, ObjetivoVendedor>

export interface VendedorObjetivoVisible {
  vendedorId: string
  supervisorId: string | null
}

/** Meta inicial visible hasta que Gerencia guarde una meta individual distinta. */
export const META_CONVERSION_PREDETERMINADA = 15

/**
 * Meta de conversión que puede mostrarse y compararse en los paneles.
 *
 * Un cero leído correctamente significa que todavía no existe una meta
 * guardada y activa el valor inicial. En cambio, los objetivos también llegan
 * en cero cuando su lectura falla; en ese caso no inventamos el 15 %.
 */
export function metaConversionAplicable(
  conversionGuardada: number,
  errorCarga = false,
): number | null {
  if (errorCarga) return null
  return conversionGuardada > 0
    ? conversionGuardada
    : META_CONVERSION_PREDETERMINADA
}

/**
 * Lectura derivada para las pantallas existentes. Supervisor y empresa jamás
 * se persisten: siempre se recalculan desde `porVendedor`.
 */
export interface ObjetivosJerarquicos {
  vendedor: ObjetivoComercial
  supervisor: ObjetivoComercial
  gerencia: ObjetivoComercial
  porVendedor: ObjetivosPorVendedor
}

/** Compatibilidad de consumidores de lectura; ya no representa metas editables por rol. */
export type ObjetivosPorRol = Omit<ObjetivosJerarquicos, 'porVendedor'> & {
  porVendedor?: ObjetivosPorVendedor
}

const OBJETIVO_CERO: Readonly<ObjetivoComercial> = {
  capitalObjetivo: 0,
  ventasObjetivo: 0,
  conversionObjetivo: 0,
}

function cero(): ObjetivoComercial {
  return { ...OBJETIVO_CERO }
}

export function objetivosCero(): ObjetivosJerarquicos {
  return { vendedor: cero(), supervisor: cero(), gerencia: cero(), porVendedor: {} }
}

const NumeroServidor = v.pipe(
  v.union([v.number(), v.string()]),
  v.transform((x) => (typeof x === 'string' ? Number(x) : x)),
  v.check((n) => Number.isFinite(n), 'número inválido'),
)

export const FilaObjetivoSchema = v.object({
  vendedor_id: v.string(),
  supervisor_id: v.string(),
  capital_objetivo: NumeroServidor,
  ventas_objetivo: NumeroServidor,
  conversion_objetivo: NumeroServidor,
})
export type FilaObjetivo = v.InferOutput<typeof FilaObjetivoSchema>

/**
 * El monto se suma. La conversión del supervisor y de la empresa es el promedio
 * de las metas individuales que sí fueron definidas; un porcentaje nunca se suma.
 */
export function agregarObjetivos(items: Iterable<ObjetivoComercial>): ObjetivoComercial {
  const metas = Array.from(items)
  if (metas.length === 0) return cero()

  const capitalObjetivo = metas.reduce((total, meta) => total + meta.capitalObjetivo, 0)
  const metasConConversion = metas.filter((meta) => meta.conversionObjetivo > 0)
  const conversionObjetivo = metasConConversion.length > 0
    ? metasConConversion.reduce((total, meta) => total + meta.conversionObjetivo, 0)
      / metasConConversion.length
    : 0

  return {
    capitalObjetivo,
    ventasObjetivo: 0,
    conversionObjetivo: Math.round(conversionObjetivo * 100) / 100,
  }
}

export function objetivosParaActor(
  porVendedor: ObjetivosPorVendedor,
  actorId?: string | null,
  vendedores: readonly VendedorObjetivoVisible[] = [],
): ObjetivosJerarquicos {
  const metasCompletas: ObjetivosPorVendedor = { ...porVendedor }
  for (const vendedor of vendedores) {
    if (metasCompletas[vendedor.vendedorId]) continue
    metasCompletas[vendedor.vendedorId] = {
      vendedorId: vendedor.vendedorId,
      supervisorId: vendedor.supervisorId,
      capitalObjetivo: 0,
      ventasObjetivo: 0,
      conversionObjetivo: META_CONVERSION_PREDETERMINADA,
    }
  }

  const filas = Object.values(metasCompletas)
  const propia = actorId ? metasCompletas[actorId] : undefined
  return {
    vendedor: propia
      ? {
          capitalObjetivo: propia.capitalObjetivo,
          ventasObjetivo: 0,
          conversionObjetivo: propia.conversionObjetivo,
        }
      : cero(),
    supervisor: agregarObjetivos(filas.filter((meta) => meta.supervisorId === actorId)),
    gerencia: agregarObjetivos(filas),
    porVendedor: metasCompletas,
  }
}

export function aObjetivosPorRol(
  filas: FilaObjetivo[],
  actorId?: string | null,
  vendedores: readonly VendedorObjetivoVisible[] = [],
): ObjetivosJerarquicos {
  const porVendedor: ObjetivosPorVendedor = {}
  for (const fila of filas) {
    porVendedor[fila.vendedor_id] = {
      vendedorId: fila.vendedor_id,
      supervisorId: fila.supervisor_id,
      capitalObjetivo: fila.capital_objetivo,
      ventasObjetivo: 0,
      conversionObjetivo: fila.conversion_objetivo,
    }
  }
  return objetivosParaActor(porVendedor, actorId, vendedores)
}

export function esObjetivosJerarquicos(
  metas: ObjetivosPorVendedor | ObjetivosPorRol,
): metas is ObjetivosPorRol {
  return Object.hasOwn(metas, 'vendedor')
    && Object.hasOwn(metas, 'supervisor')
    && Object.hasOwn(metas, 'gerencia')
}

export function metasEditablesDe(
  metas: ObjetivosPorVendedor | ObjetivosPorRol,
): ObjetivosPorVendedor {
  return esObjetivosJerarquicos(metas) ? (metas.porVendedor ?? {}) : metas
}

export function aPayloadObjetivos(
  metas: ObjetivosPorVendedor | ObjetivosPorRol,
): Record<string, Record<string, number>> {
  const payload: Record<string, Record<string, number>> = {}
  for (const [vendedorId, meta] of Object.entries(metasEditablesDe(metas))) {
    payload[vendedorId] = {
      capital_objetivo: meta.capitalObjetivo,
      // Compatibilidad con la RPC vigente: cierres dejó de ser una meta y viaja en cero.
      ventas_objetivo: 0,
      conversion_objetivo: meta.conversionObjetivo,
    }
  }
  return payload
}

export function periodoLima(ahoraMs: number): string {
  return `${fechaLima(ahoraMs).slice(0, 7)}-01`
}

export function validarObjetivos(
  metas: ObjetivosPorVendedor | ObjetivosPorRol,
): string | null {
  const editables = metasEditablesDe(metas)
  const filas = Object.entries(editables)
  const valores = filas.length > 0
    ? filas.map(([, meta]) => meta)
    : esObjetivosJerarquicos(metas)
      ? [metas.vendedor, metas.supervisor, metas.gerencia]
      : []

  for (const [vendedorId, meta] of filas) {
    if (meta.vendedorId !== vendedorId) return 'La meta no corresponde al vendedor indicado'
    if (!meta.supervisorId) return 'Todos los vendedores deben tener un supervisor activo antes de fijar metas'
  }

  for (const meta of valores) {
    const numeros = [meta.capitalObjetivo, meta.conversionObjetivo]
    if (numeros.some((n) => !Number.isFinite(n) || n < 0)) return 'Las metas deben ser números positivos'
    if (meta.capitalObjetivo > 100_000_000) return 'El capital objetivo no puede pasar de 100 millones (PEN)'
    if (meta.conversionObjetivo > 100) return 'La conversión objetivo es un porcentaje (0 a 100)'
  }
  return null
}
