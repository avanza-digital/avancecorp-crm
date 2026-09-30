import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import type { PedidoColaTrabajo } from '@/lib/gestion-diaria-cola'
import { gestionDiariaKeys } from './gestion-diaria-queries'
import { intervaloReconsultaSla } from './sla-operacion-reloj'
import { obtenerColaTrabajo } from './gestion-diaria-cola-api'

export const colaTrabajoKey = (actor: string | null, rol: string | null, dia: string, pedido: PedidoColaTrabajo, revision = 0) =>
  [...gestionDiariaKeys.raiz(), 'cola-trabajo', actor, rol, dia, revision, pedido] as const

/** Una foto por petición. No conserva páginas de otra selección como actuales. */
export function useColaTrabajo(pedido: PedidoColaTrabajo, dia: string, revision = 0) {
  const { yo } = useAuth()
  const queryKey = colaTrabajoKey(yo?.id ?? null, yo?.rol ?? null, dia, pedido, revision)
  const consulta = useQuery({
    queryKey,
    queryFn: ({ signal }) => obtenerColaTrabajo(pedido, yo!.id, dia, signal),
    enabled: Boolean(yo && !yo.demo),
    staleTime: 0,
    retry: (n, error) => !('code' in error && error.code === 'GESTION_COLA_CONTRACT') && n < 2,
    // Fijar al entrar con el teclado la persona YA elegida no desmonta sus
    // controles. No sirve para cambiar de persona, filtro, día o identidad.
    placeholderData: (anterior, consultaAnterior) => pedido.elegido !== null
      && anterior?.elegido === pedido.elegido && anterior.filtro === pedido.filtro && anterior.limite === pedido.limite
      && queryKey.slice(0, -1).every((v, i) => consultaAnterior?.queryKey[i] === v) ? anterior : undefined,
    refetchOnMount: 'always', refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
    refetchInterval: (q) => intervaloReconsultaSla(q.state.data ? {
      calculado_en: q.state.data.generado_en, proximo_cambio_en: q.state.data.proximo_cambio_en,
    } : undefined, q.state.dataUpdatedAt),
  })
  return { ...consulta, data: consulta.error ? undefined : consulta.data }
}
