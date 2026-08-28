import { useMemo } from 'react'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import {
  mapearMetricasVendedores,
  metricasVendedoresDesdeAmbito,
  type MetricasVendedoresOperativas,
} from '@/lib/metricas-vendedores'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import type { Actividad, Lead, Miembro } from '@/lib/tipos'
import { useMetricasVendedores } from './crm-queries'

export interface MetricasVendedoresOperativasHook {
  /** Ranking + comparativa (RPC en real, espejo vivo en demo); null mientras carga o si el RPC cayó. */
  metricas: MetricasVendedoresOperativas | null
  cargando: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * Une crm.metricas_vendedores_fn con su espejo demo (F1b). El payload real
 * viaja SIN nombres: aquí se une con `roster` (las filas que la pantalla
 * muestra) y con `equipo` (el roster completo, para nombrar supervisores de
 * la comparativa). En demo, la foto operativa sale del ámbito vivo y la
 * conversión del mismo espejo mensual canónico que alimenta Hoy/Ranking.
 */
export function useMetricasVendedoresOperativas(
  roster: readonly Miembro[],
  equipo: readonly Miembro[],
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  habilitado = true,
): MetricasVendedoresOperativasHook {
  const { yo } = useAuth()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useMetricasVendedores(sesionReal)
  // Reloj vivo: los «días sin actividad» del espejo demo avanzan solos.
  const ahora = useAhora()
  const metricas = useMemo(
    () => {
      if (!habilitado || !yo) return null
      if (yo.demo) {
        const ambitoMensual = yo.rol === 'supervisor'
          ? { alcance: 'equipo' as const, actorId: yo.id }
          : yo.rol === 'gerencia' || yo.rol === 'directorio'
            ? { alcance: 'global' as const }
            : { alcance: 'propio' as const, actorId: yo.id }
        return metricasVendedoresDesdeAmbito(
          roster,
          equipo,
          leads,
          actividades,
          ahora,
          conversionMensualDemo(ahora, ambitoMensual),
        )
      }
      // Fail-closed TAMBIÉN en refetch (hallazgo ALTA de la revisión Codex).
      if (consulta.error) return null
      if (!consulta.data) return null
      // La foto envejece contra el reloj LOCAL (ver use-cola-accion-operativa):
      // sin deriva, el «Última actividad hace X» del supervisor se congela
      // entre refetches — y en segundo plano el intervalo ni siquiera corre.
      const derivaDias = Math.max(0, (ahora - consulta.dataUpdatedAt) / 86_400_000)
      return mapearMetricasVendedores(consulta.data, roster, equipo, derivaDias)
    },
    [actividades, ahora, consulta.data, consulta.dataUpdatedAt, consulta.error, equipo, habilitado, leads, roster, yo],
  )

  return {
    metricas,
    cargando: sesionReal && consulta.isPending,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
