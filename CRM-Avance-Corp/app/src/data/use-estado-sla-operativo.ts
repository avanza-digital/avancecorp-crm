import { useMemo } from 'react'
import { useAuth } from '@/lib/auth-context'
import { crearEstadosSlaDemo } from '@/lib/demo-sla'
import {
  indexarEstadoSlaLeads,
  type IndiceEstadoSlaLeads,
} from '@/lib/sla-versionado'
import type { Actividad, Lead } from '@/lib/tipos'
import { useEstadoSlaLeads } from './crm-config-queries'

export interface EstadoSlaOperativo {
  indice: IndiceEstadoSlaLeads
  cargando: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * Une el RPC real con un fixture demo aislado. Si el RPC falla devuelve un
 * índice vacío: es preferible omitir colores/alertas SLA a inventar vencimientos
 * con la política actual sobre episodios históricos.
 */
export function useEstadoSlaOperativo(
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  habilitado = true,
): EstadoSlaOperativo {
  const { yo } = useAuth()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useEstadoSlaLeads(sesionReal)
  const estados = useMemo(
    () => {
      if (!habilitado || !yo) return []
      return yo.demo
        ? crearEstadosSlaDemo(leads, actividades)
        : consulta.data ?? []
    },
    [actividades, consulta.data, habilitado, leads, yo],
  )
  const indice = useMemo(() => indexarEstadoSlaLeads(estados), [estados])

  return {
    indice,
    cargando: sesionReal && consulta.isPending,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
