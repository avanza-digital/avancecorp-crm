import { useMemo } from 'react'
import { useAuth } from '@/lib/auth-context'
import type { ResumenReparto } from '@/lib/resumen-reparto'
import { useResumenReparto } from './crm-queries'

export interface ResumenRepartoOperativo {
  /** Payload version:1 del RPC; null mientras carga, si el RPC cayó o en demo. */
  resumen: ResumenReparto | null
  cargando: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * Une el StatStrip de «Repartir» con el RPC crm.resumen_reparto_fn (F1b tanda
 * 3): la base de datos cuenta la cola global y el navegador solo pinta.
 *
 * En DEMO devuelve `null` a propósito, y esa es la diferencia con los espejos
 * hermanos de F1: no hay cola de reparto en los fixtures (todos los leads demo
 * tienen dueño o supervisor), así que un espejo daría siempre «0 por repartir ·
 * S/ 0 · US$ 0» al lado del panel que avisa que la cola no se pudo cargar —
 * mentiría dos veces. El espejo queda escrito en lib/resumen-reparto como
 * contrato; si algún día los fixtures modelan una cola, aquí cambia una línea.
 *
 * Si el RPC falla, `resumen` queda null: la pantalla degrada a «—» con aviso y
 * botón de reintentar, y JAMÁS vuelve a contar filas en el navegador (eso es
 * exactamente lo que esta tanda quita).
 */
export function useResumenRepartoOperativo(habilitado = true): ResumenRepartoOperativo {
  const { yo } = useAuth()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useResumenReparto(sesionReal)
  const resumen = useMemo(
    () => {
      if (!sesionReal) return null
      // Fail-closed TAMBIÉN en refetch: TanStack conserva `data` cuando un
      // refetch falla, y servir esa foto vieja mientras el banner promete «—»
      // sería mentir dos veces (hallazgo ALTA de la revisión Codex en F1b).
      if (consulta.error) return null
      return consulta.data ?? null
    },
    [consulta.data, consulta.error, sesionReal],
  )

  return {
    resumen,
    cargando: sesionReal && consulta.isPending,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
