// lib/tipo-cambio.ts — Tipo de cambio USD→PEN (promedio de la última semana),
// para convertir el capital en dólares a soles DENTRO de la meta del mes.
//
// ⚠️ La regla central "PEN y USD JAMÁS se suman" (ver lib/inteligencia.ts) sigue
// vigente para el capital CRUDO: nunca se muestran soles y dólares como un mismo
// total sin convertir. Aquí NO se suman a ciegas — se CONVIERTE el USD a PEN a un
// tipo de cambio conocido (promedio de ~7 días) y recién ese equivalente en soles
// entra a la meta. Convertir a una tasa real ≠ sumar peras con manzanas.
import { useEffect, useState } from 'react'
import { useAuth } from './auth-context'

export interface TipoCambio {
  /** Soles por 1 USD — promedio de los últimos ~7 días. */
  promedio: number
  /** Origen legible para mostrar bajo la meta (ej. "SUNAT · prom. 7d", "demo"). */
  fuente: string
}

/** Promedio de una serie de cotizaciones diarias; ignora ceros/negativos/NaN. */
export function promedioSemanal(serie: number[]): number {
  const validos = serie.filter((x) => Number.isFinite(x) && x > 0)
  if (validos.length === 0) return 0
  return validos.reduce((a, b) => a + b, 0) / validos.length
}

/** Convierte un monto en USD a su equivalente en PEN al TC dado (0 si no hay TC). */
export const usdAPen = (usd: number, tc: number): number => (tc > 0 ? usd * tc : 0)

// Serie demo de la última semana (S/ por USD), realista (~3.75). NO es dato real:
// en modo demo no hay backend de cotizaciones. El real llegará por una edge.
const SERIE_DEMO = [3.742, 3.738, 3.751, 3.76, 3.755, 3.749, 3.762]

/**
 * Tipo de cambio USD→PEN promedio de la última semana.
 * - Demo: promedio de una serie simulada, etiquetado "demo".
 * - Real: por ahora `null` (aún no hay fuente de cotizaciones conectada) → la meta
 *   cae con honestidad a solo-PEN y avisa que el USD queda pendiente. Cuando exista
 *   la edge de tipo de cambio, este hook la consumirá y devolverá el promedio real.
 */
export function useTipoCambio(): TipoCambio | null {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const [tc, setTc] = useState<TipoCambio | null>(null)

  useEffect(() => {
    if (esDemo) {
      setTc({ promedio: promedioSemanal(SERIE_DEMO), fuente: 'demo · prom. 7d' })
      return
    }
    // TODO(real): consumir la edge `crm-tipo-cambio` (promedio 7 días de una fuente
    // oficial). Hasta que exista, sin TC → la meta suma solo PEN.
    setTc(null)
  }, [esDemo])

  return tc
}
