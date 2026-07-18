// lib/tipo-cambio.ts — Tipo de cambio USD→PEN (promedio de la última semana),
// para convertir el capital en dólares a soles DENTRO de la meta del mes.
//
// ⚠️ La regla central "PEN y USD JAMÁS se suman" (ver lib/inteligencia.ts) sigue
// vigente para el capital CRUDO: nunca se muestran soles y dólares como un mismo
// total sin convertir. Aquí NO se suman a ciegas — se CONVIERTE el USD a PEN a un
// tipo de cambio conocido (promedio de ~7 días) y recién ese equivalente en soles
// entra a la meta. Convertir a una tasa real ≠ sumar peras con manzanas.
import { useEffect, useState } from 'react'
import * as v from 'valibot'
import { useAuth } from './auth-context'
import { sb } from './supabase'
import { registrarAviso } from './observabilidad'

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
// en modo demo no hay backend de cotizaciones.
const SERIE_DEMO = [3.742, 3.738, 3.751, 3.76, 3.755, 3.749, 3.762]

// Frontera validada en runtime (misma regla que crm-api): la respuesta de la
// edge se parsea antes de tocar la meta — un promedio 0/negativo/no-numérico
// degrada a null, jamás entra a multiplicar capital.
const TipoCambioSchema = v.object({
  promedio: v.pipe(v.number(), v.check((x) => Number.isFinite(x) && x > 0)),
  fuente: v.string(),
})

/**
 * Tipo de cambio USD→PEN promedio de la última semana.
 * - Demo: promedio de una serie simulada, etiquetado "demo".
 * - Real: edge `crm-tipo-cambio` (promedio 7 días hábiles del TC SBS vía la API
 *   pública del BCRP; cache de 1 h en la edge). Si la edge o el BCRP fallan →
 *   null y la meta cae con honestidad a solo-PEN ("pendiente de tipo de cambio").
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
    if (!sb) {
      setTc(null)
      return
    }
    let cancelado = false
    sb.functions
      .invoke('crm-tipo-cambio')
      .then(({ data, error }) => {
        if (cancelado) return
        if (error) throw error
        const r = v.safeParse(TipoCambioSchema, data)
        if (!r.success) throw new Error('Respuesta de tipo de cambio fuera de contrato')
        setTc({ promedio: r.output.promedio, fuente: r.output.fuente })
      })
      .catch((e: unknown) => {
        if (cancelado) return
        // Aviso, no error: la pantalla ya degrada sola y esto puede ser
        // transitorio (BCRP caído, red). Sin TC no se inventa TC.
        registrarAviso('crm.tipo_cambio_no_disponible', {
          motivo: e instanceof Error ? e.message : 'desconocido',
        })
        setTc(null)
      })
    return () => {
      cancelado = true
    }
  }, [esDemo])

  return tc
}
