// lib/tipo-cambio.ts — Tipo de cambio USD→PEN (promedio de 7 días hábiles),
// para convertir el capital en dólares a soles DENTRO de la meta del mes.
//
// ⚠️ La regla central "PEN y USD JAMÁS se suman" (ver lib/inteligencia.ts) sigue
// vigente para el capital CRUDO: nunca se muestran soles y dólares como un mismo
// total sin convertir. Aquí NO se suman a ciegas — se CONVIERTE el USD a PEN a un
// tipo de cambio conocido (promedio de ~7 días) y recién ese equivalente en soles
// entra a la meta. Convertir a una tasa real ≠ sumar peras con manzanas.
import { useCallback, useEffect, useState } from 'react'
import * as v from 'valibot'
import { useAuth } from './auth-context'
import { sb } from './supabase'
import { registrarAviso } from './observabilidad'

export interface TipoCambio {
  /** Soles por 1 USD — promedio de los últimos 7 días hábiles disponibles. */
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
  fecha_corte: v.optional(v.string()),
})

/**
 * Motivo legible de un fallo de la edge. supabase-js envuelve un 4xx/5xx en
 * `FunctionsHttpError` con la `Response` en `context` y un mensaje genérico;
 * el cuerpo `{ error }` es el que distingue la causa. Sin cuerpo legible se
 * conserva el mensaje del error.
 */
async function motivoDelFallo(e: unknown): Promise<string> {
  const contexto = (e as { context?: { json?: () => Promise<unknown> } } | null)?.context
  if (typeof contexto?.json === 'function') {
    try {
      const cuerpo = (await contexto.json()) as { error?: unknown } | null
      if (typeof cuerpo?.error === 'string' && cuerpo.error.trim() !== '') return cuerpo.error
    } catch {
      // Cuerpo no JSON o ya consumido: cae al mensaje genérico.
    }
  }
  return e instanceof Error ? e.message : 'desconocido'
}

export interface EstadoTipoCambio {
  /**
   * Tri-estado honesto: `undefined` = consultando (la UI muestra carga, no
   * afirma "no disponible" con el fetch en vuelo), `null` = no disponible
   * (fail-closed: se degrada a solo-PEN, jamás se inventa tasa), objeto = listo.
   */
  tc: TipoCambio | null | undefined
  /** Vuelve a consultar la edge (cablear al Reintentar de la pantalla). */
  recargar: () => void
}

/**
 * Tipo de cambio USD→PEN promedio de los últimos 7 días hábiles.
 * - Demo: promedio de una serie simulada, etiquetado "demo".
 * - Real: edge `crm-tipo-cambio` (promedio 7 días hábiles del TC SBS vía la API
 *   pública del BCRP; cache de 1 h por fecha de corte en la edge). `fechaCorte`
 *   permite congelar un mes histórico en su último día; sin fecha conserva el
 *   contrato previo y la edge usa hoy en Lima. Si la edge o el BCRP fallan →
 *   null y la pantalla degrada con honestidad a solo-PEN.
 * - `habilitado=false` (vistas que no muestran TC): ni consulta ni queda
 *   "consultando" — tc = null sin tocar la red ni la observabilidad.
 */
export function useTipoCambio(habilitado = true, fechaCorte?: string): EstadoTipoCambio {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const [version, setVersion] = useState(0)
  // La clave forma parte del estado para que un cambio agosto→julio invalide
  // el valor anterior durante EL MISMO render, antes de que corra el effect.
  // Así nunca se pinta el TC de un mes bajo la etiqueta de otro.
  const claveSolicitud = `${habilitado ? '1' : '0'}|${esDemo ? '1' : '0'}|${fechaCorte ?? 'hoy'}|${version}`
  const [estado, setEstado] = useState<{
    clave: string
    valor: TipoCambio | null | undefined
  }>(() => ({ clave: claveSolicitud, valor: undefined }))
  const recargar = useCallback(() => setVersion((n) => n + 1), [])
  const tc = estado.clave === claveSolicitud
    ? estado.valor
    : habilitado
      ? undefined
      : null

  useEffect(() => {
    if (!habilitado) {
      setEstado({ clave: claveSolicitud, valor: null })
      return
    }
    if (esDemo) {
      const fuente = fechaCorte === undefined
        ? 'demo · prom. 7d'
        : `demo · prom. 7d al ${fechaCorte.slice(8, 10)}/${fechaCorte.slice(5, 7)}/${fechaCorte.slice(0, 4)}`
      setEstado({ clave: claveSolicitud, valor: { promedio: promedioSemanal(SERIE_DEMO), fuente } })
      return
    }
    if (!sb) {
      setEstado({ clave: claveSolicitud, valor: null })
      return
    }
    let cancelado = false
    setEstado({ clave: claveSolicitud, valor: undefined }) // consultando (también al reintentar tras un fallo)
    const invocacion = fechaCorte === undefined
      ? sb.functions.invoke('crm-tipo-cambio')
      : sb.functions.invoke('crm-tipo-cambio', { body: { fecha_corte: fechaCorte } })
    invocacion
      .then(({ data, error }) => {
        if (cancelado) return
        if (error) throw error
        const r = v.safeParse(TipoCambioSchema, data)
        if (!r.success) throw new Error('Respuesta de tipo de cambio fuera de contrato')
        if (fechaCorte !== undefined && r.output.fecha_corte !== fechaCorte) {
          throw new Error('Respuesta de tipo de cambio con fecha de corte incorrecta')
        }
        const fuente = fechaCorte === undefined
          ? r.output.fuente
          : `${r.output.fuente} al ${fechaCorte.slice(8, 10)}/${fechaCorte.slice(5, 7)}/${fechaCorte.slice(0, 4)}`
        setEstado({ clave: claveSolicitud, valor: { promedio: r.output.promedio, fuente } })
      })
      .catch(async (e: unknown) => {
        // Aviso, no error: la pantalla ya degrada sola y esto puede ser
        // transitorio (BCRP caído, red). Sin TC no se inventa TC. El motivo
        // lleva el `{ error }` que respondió la edge (p. ej. «BCRP: formato de
        // período no reconocido: 02.Set.26»), no el «non-2xx» genérico de
        // supabase-js: con el genérico, un bug de parseo y un BCRP caído se
        // veían idénticos desde el CRM (septiembre 2026).
        const motivo = await motivoDelFallo(e)
        if (cancelado) return
        registrarAviso('crm.tipo_cambio_no_disponible', { motivo })
        setEstado({ clave: claveSolicitud, valor: null })
      })
    return () => {
      cancelado = true
    }
  }, [claveSolicitud, esDemo, fechaCorte, habilitado])

  return { tc, recargar }
}
