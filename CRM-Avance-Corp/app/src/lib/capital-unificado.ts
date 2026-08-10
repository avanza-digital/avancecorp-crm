// lib/capital-unificado.ts — la política ÚNICA de «capital total en soles».
//
// Nace de la decisión #10 de Miguel (2026-08-10): las filas de equipo muestran un
// monto unificado ADEMÁS del desglose por moneda. Hasta ahora esa conversión vivía
// solo dentro de `clasificarRankingCapitalTotal`, duplicada en sus dos puntos
// (capital y meta); llevarla a seis celdas más habría sido clonarla ocho veces.
//
// ⚠️ La regla de la casa —PEN y USD JAMÁS se suman— sigue intacta: aquí no se suman
// a ciegas, se CONVIERTE el USD a soles a una tasa real y conocida, y el resultado
// se rotula SIEMPRE con esa tasa. Convertir a tasa real ≠ sumar peras con manzanas.
// Sin tasa, el USD queda FUERA del total y se muestra aparte: jamás se inventa una.
import { numero } from './format'
import { usdAPen } from './tipo-cambio'

export type EstadoCapitalUnificado =
  /** PEN + USD convertido: el total incluye ambas monedas. */
  | 'convertido'
  /** Hay total, pero SOLO con el PEN: no había TC y el USD se rotula aparte. */
  | 'solo_pen'
  /** No se puede afirmar un total (falta algún componente). El total es null, NUNCA 0. */
  | 'indisponible'

export interface CapitalUnificado {
  pen: number | null
  usd: number | null
  /**
   * Total en soles, o `null` si no se puede afirmar.
   *
   * Es `null` —y no 0— a propósito: `money(null)` y `moneyK(null)` imprimen «S/ 0»,
   * así que un total ausente convertido en cero se leería como un hecho («este
   * vendedor no tiene capital») cuando lo cierto es que no lo sabemos.
   */
  total: number | null
  /** TC realmente APLICADO. null = el USD quedó fuera del total. */
  tc: number | null
  estado: EstadoCapitalUnificado
}

/**
 * Valida un tipo de cambio antes de dejarlo multiplicar dinero.
 *
 * Misma guardia que ya aplicaba el ranking: null, 0, negativo o no finito colapsan
 * a `null` — un TC inválido no degrada el total a una cifra rara, lo saca del juego.
 */
export function tcAplicable(tc: number | null | undefined): number | null {
  return tc != null && Number.isFinite(tc) && tc > 0 ? tc : null
}

/**
 * Unifica capital en soles. Devuelve el TC que REALMENTE se aplicó, para que quien
 * rotule lea de aquí y no del TC que creía tener: así es imposible anunciar una tasa
 * que no entró en el número (invariante heredada del ranking).
 */
export function totalEnSoles(
  pen: number | null | undefined,
  usd: number | null | undefined,
  tc: number | null | undefined,
): CapitalUnificado {
  const penNum = pen ?? null
  const usdNum = usd ?? null
  const tcValido = tcAplicable(tc)

  // Sin alguno de los dos componentes no hay total que afirmar.
  if (penNum == null || usdNum == null) {
    return { pen: penNum, usd: usdNum, total: null, tc: tcValido, estado: 'indisponible' }
  }

  if (tcValido == null) {
    // Fail-closed: el total es solo-PEN y el USD viaja aparte, rotulado.
    return { pen: penNum, usd: usdNum, total: penNum, tc: null, estado: 'solo_pen' }
  }

  return {
    pen: penNum,
    usd: usdNum,
    total: penNum + usdAPen(usdNum, tcValido),
    tc: tcValido,
    estado: 'convertido',
  }
}

/**
 * Rótulo del tipo de cambio aplicado. Se le pasa el TC que devolvió
 * `totalEnSoles`, nunca el que se pidió.
 */
export function rotuloTipoCambio(tcAplicado: number, fuente: string): string {
  return `TC S/ ${numero(tcAplicado, 4)} (${fuente})`
}
