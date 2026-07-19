// Metas comerciales del mes (crm.objetivos) — contrato y lógica pura.
// La tabla guarda UNA fila por (mes, rol); capital SIEMPRE en PEN (regla de la
// casa: PEN y USD jamás se suman — la UI convierte USD con el TC semanal).
// La escritura va por la RPC crm.fijar_objetivos (solo gerencia); aquí vive el
// espejo cliente: validación, mapeos fila↔rol y el periodo vigente en Lima.
import * as v from 'valibot'
import { fechaLima } from './agenda-derivada'

export const ROLES_OBJETIVO = ['vendedor', 'supervisor', 'gerencia'] as const
export type RolObjetivo = (typeof ROLES_OBJETIVO)[number]

export interface ObjetivoComercial {
  capitalObjetivo: number
  ventasObjetivo: number
  conversionObjetivo: number
}

export type ObjetivosPorRol = Record<RolObjetivo, ObjetivoComercial>

export function objetivosCero(): ObjetivosPorRol {
  return {
    vendedor: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
    supervisor: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
    gerencia: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
  }
}

// numeric de Postgres puede llegar como number o como string por PostgREST
// (mismo criterio defensivo que contratos_cartera en database.types).
const NumeroServidor = v.pipe(
  v.union([v.number(), v.string()]),
  v.transform((x) => (typeof x === 'string' ? Number(x) : x)),
  v.check((n) => Number.isFinite(n), 'número inválido'),
)

// Fila cruda del borde (SELECT de crm.objetivos / retorno de la RPC).
export const FilaObjetivoSchema = v.object({
  rol: v.picklist(ROLES_OBJETIVO),
  capital_objetivo: NumeroServidor,
  ventas_objetivo: NumeroServidor,
  conversion_objetivo: NumeroServidor,
})
export type FilaObjetivo = v.InferOutput<typeof FilaObjetivoSchema>

/** Filas del servidor → mapa por rol; los roles sin fila quedan en cero. */
export function aObjetivosPorRol(filas: FilaObjetivo[]): ObjetivosPorRol {
  const metas = objetivosCero()
  for (const fila of filas) {
    metas[fila.rol] = {
      capitalObjetivo: fila.capital_objetivo,
      ventasObjetivo: fila.ventas_objetivo,
      conversionObjetivo: fila.conversion_objetivo,
    }
  }
  return metas
}

/** Payload de la RPC (snake_case del servidor) a partir del mapa por rol. */
export function aPayloadObjetivos(metas: ObjetivosPorRol): Record<string, Record<string, number>> {
  const payload: Record<string, Record<string, number>> = {}
  for (const rol of ROLES_OBJETIVO) {
    payload[rol] = {
      capital_objetivo: metas[rol].capitalObjetivo,
      ventas_objetivo: metas[rol].ventasObjetivo,
      conversion_objetivo: metas[rol].conversionObjetivo,
    }
  }
  return payload
}

/** Primer día del mes calendario vigente en Lima: 'YYYY-MM-01'. */
export function periodoLima(ahoraMs: number): string {
  return `${fechaLima(ahoraMs).slice(0, 7)}-01`
}

/**
 * Espejo cliente de los CHECK del servidor (doble defensa, feedback inmediato).
 * Devuelve el mensaje de error o null si las metas son válidas.
 */
export function validarObjetivos(metas: ObjetivosPorRol): string | null {
  for (const rol of ROLES_OBJETIVO) {
    const m = metas[rol]
    const numeros = [m.capitalObjetivo, m.ventasObjetivo, m.conversionObjetivo]
    if (numeros.some((n) => !Number.isFinite(n) || n < 0)) {
      return 'Las metas deben ser números positivos'
    }
    if (m.capitalObjetivo > 100_000_000) {
      return 'El capital objetivo no puede pasar de 100 millones (PEN)'
    }
    if (!Number.isInteger(m.ventasObjetivo) || m.ventasObjetivo > 1000) {
      return 'Las ventas objetivo van de 0 a 1000 (número entero)'
    }
    if (m.conversionObjetivo > 100) {
      return 'La conversión objetivo es un porcentaje (0 a 100)'
    }
  }
  return null
}
