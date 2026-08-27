import { useMemo } from 'react'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import {
  LIMITE_COLA_ACCION,
  colaAccionDesdeAmbito,
  mapearColaAccion,
  type ColaAccionOperativa,
} from '@/lib/cola-accion'
import type { EstadoSlaLead } from '@/lib/sla-versionado'
import type { Actividad, Lead, Tarea } from '@/lib/tipos'
import { useColaAccion } from './crm-queries'

export interface ColaAccionOperativaHook {
  /** Cola operativa (RPC en real, espejo vivo en demo); null mientras carga o si el RPC cayó. */
  cola: ColaAccionOperativa | null
  cargando: boolean
  /** true mientras un fetch del RPC está EN VUELO (primera carga o refetch):
   *  `cola` puede ser todavía la foto anterior, y quien PERSISTA algo derivado
   *  de ella (la visita de F4.3) debe esperar al payload fresco. En demo el
   *  espejo es síncrono: siempre false. */
  enVuelo: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * Une crm.cola_accion_fn con su espejo demo (F1b). En sesión real el servidor
 * decide buckets/severidad/orden y este hook solo re-une cada item con el Lead
 * COMPLETO del ámbito en memoria (hover, drawer y cronómetros conservan toda
 * la ficha hasta F3) y redacta los motivos. En demo, colaDe sobre el estado
 * VIVO — mover un lead recoloca su fila al instante.
 *
 * `indiceSla` solo alimenta el espejo demo: en real esos vencimientos ya
 * vienen resueltos dentro del payload (la pantalla puede dejar de pedir el
 * RPC de estado SLA si no lo usa para nada más).
 */
export function useColaAccionOperativa(
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  tareas: readonly Tarea[],
  indiceSla?: ReadonlyMap<string, EstadoSlaLead>,
  habilitado = true,
  limite: number = LIMITE_COLA_ACCION,
): ColaAccionOperativaHook {
  const { yo } = useAuth()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useColaAccion(sesionReal, limite)
  const porId = useMemo(() => new Map(leads.map((l) => [l.id, l])), [leads])
  // Reloj vivo (tick por minuto): el espejo demo debe recolocar buckets al
  // pasar el tiempo, como hacía colaDe en las pantallas antes de F1b.
  const ahora = useAhora()
  const cola = useMemo(
    () => {
      if (!habilitado || !yo) return null
      if (yo.demo) {
        return colaAccionDesdeAmbito(leads, actividades, tareas, ahora, indiceSla, limite)
      }
      // Fail-closed TAMBIÉN en refetch: TanStack conserva `data` cuando un
      // refetch falla, y servir esa foto vieja mientras el banner promete
      // «—» sería mentir dos veces (hallazgo ALTA de la revisión Codex).
      if (consulta.error) return null
      if (!consulta.data) return null
      // La foto envejece contra el reloj LOCAL: dataUpdatedAt es el instante
      // (de este navegador) en que llegó el payload, así el desfase con el
      // reloj del servidor no infla los números. El clamp cubre el tick de
      // useAhora que aún no corrió tras un refetch recién aterrizado.
      const derivaDias = Math.max(0, (ahora - consulta.dataUpdatedAt) / 86_400_000)
      return mapearColaAccion(consulta.data, (id) => porId.get(id), derivaDias)
    },
    [actividades, ahora, consulta.data, consulta.dataUpdatedAt, consulta.error, habilitado, indiceSla, leads, limite, porId, tareas, yo],
  )

  return {
    cola,
    cargando: sesionReal && consulta.isPending,
    enVuelo: sesionReal && consulta.isFetching,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
