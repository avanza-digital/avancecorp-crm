import { useMemo } from 'react'
import { useAuth } from '@/lib/auth-context'
import {
  resumenCarteraDesdeAmbito,
  type ResumenCartera,
} from '@/lib/resumen-cartera'
import type { Actividad, Lead } from '@/lib/tipos'
import { useResumenCartera } from './crm-queries'

export interface ResumenCarteraOperativo {
  /** Payload version:1 (RPC en real, espejo vivo en demo); null mientras carga o si el RPC cayó. */
  resumen: ResumenCartera | null
  cargando: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * Une el RPC crm.resumen_cartera_fn con su espejo demo (F1). En sesión real la
 * base de datos cuenta; el navegador solo pinta. En demo el MISMO shape se
 * calcula del ámbito VIVO del store — crear un lead en demo mueve los tiles al
 * instante (bloqueante del plan F1: el espejo jamás lee la semilla estática).
 * Si el RPC falla, `resumen` queda null: la pantalla degrada a «—» con aviso,
 * nunca inventa cifras contando filas parciales.
 */
export function useResumenCarteraOperativo(
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  habilitado = true,
): ResumenCarteraOperativo {
  const { yo } = useAuth()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useResumenCartera(sesionReal)
  const resumen = useMemo(
    () => {
      if (!habilitado || !yo) return null
      return yo.demo
        ? resumenCarteraDesdeAmbito(leads, actividades, Date.now())
        : consulta.data ?? null
    },
    [actividades, consulta.data, habilitado, leads, yo],
  )

  return {
    resumen,
    cargando: sesionReal && consulta.isPending,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
