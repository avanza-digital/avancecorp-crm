import { useEffect, useMemo, useRef } from 'react'
import { useInfiniteQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { analistasDelEquipo } from '@/lib/gestion-diaria'
import { pendientesDesdeDemo, unirPaginasPendientes, type CursorPendientes } from '@/lib/gestion-diaria-pendientes'
import { CrmApiError } from './crm-api'
import { gestionDiariaKeys, INTERVALO_REGISTRO_MS } from './gestion-diaria-queries'
import { listarPendientesSupervisor } from './gestion-diaria-pendientes-api'

export const LIMITE_PENDIENTES = 25
export const clavePendientes = (actor: string | null, rol: string | null, demo: boolean | null, dia: string, analista: string, soloVencidas: boolean) =>
  [...gestionDiariaKeys.raiz(), actor, rol, demo, 'pendientes-supervisor', dia, analista, soloVencidas, LIMITE_PENDIENTES] as const

export function usePendientesSupervisor(dia: string, analista: string, soloVencidas: boolean, visible: boolean, apertura = 0) {
  const { yo } = useAuth()
  const { tareas, equipo, ambito } = useCRMData()
  const ahora = useAhora()
  const cliente = useQueryClient()
  const revocada = useRef(false)
  const autorizado = yo?.rol === 'supervisor'
  const clave = useMemo(() => [...clavePendientes(yo?.id ?? null, yo?.rol ?? null, yo?.demo ?? null, dia, analista, soloVencidas), apertura],
    [yo?.id, yo?.rol, yo?.demo, dia, analista, soloVencidas, apertura])
  const ambitoClave = useMemo(() => clave.slice(0, -3), [clave])
  // La denegación pertenece al analista, no a un filtro concreto.
  const identidad = JSON.stringify(ambitoClave)
  const ultimaIdentidad = useRef(identidad)
  if (ultimaIdentidad.current !== identidad) {
    ultimaIdentidad.current = identidad
    revocada.current = false
  }
  const consulta = useInfiniteQuery({
    queryKey: clave,
    initialPageParam: null as CursorPendientes | null,
    queryFn: ({ pageParam, signal }) => {
      if (!yo || !autorizado) throw new CrmApiError('Consulta no autorizada.', '42501')
      const pedido = { supervisor: yo.id, analista, soloVencidas, limite: LIMITE_PENDIENTES, cursor: pageParam }
      if (yo.demo) {
        if (!analistasDelEquipo(equipo, yo.id).includes(analista)) throw new CrmApiError('Consulta no autorizada.', '42501')
        return Promise.resolve(pendientesDesdeDemo(pedido, tareas, ambito.leads, ahora))
      }
      return listarPendientesSupervisor(pedido, signal)
    },
    getNextPageParam: ultima => ultima.siguiente_cursor,
    // Todas las páginas viven en una entrada, con cursores en pageParams.
    // Deshabilitar al tener dos congela también la primera, incluidos foco,
    // reconexión y regreso a la pestaña. Cargar más sigue siendo explícito.
    enabled: q => autorizado && visible && !revocada.current && (q.state.data?.pages.length ?? 0) < 2,
    refetchInterval: q => (q.state.data?.pages.length ?? 0) < 2 ? INTERVALO_REGISTRO_MS : false,
    refetchOnMount: 'always', refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
    staleTime: 0, gcTime: 0, retry: false,
  })
  const denegada = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  const sinPermiso = denegada || revocada.current
  useEffect(() => {
    if (!denegada) return
    // Bloquear primero: limpiar la caché no debe provocar otra consulta automática.
    revocada.current = true
    void cliente.cancelQueries({ queryKey: ambitoClave })
    cliente.setQueriesData({ queryKey: ambitoClave }, { pages: [], pageParams: [] })
  }, [denegada, cliente, ambitoClave])
  const paginas = autorizado && !sinPermiso ? consulta.data?.pages ?? [] : []
  const ultima = paginas.at(-1)
  return {
    items: unirPaginasPendientes(paginas), pagina: ultima ?? null,
    congelada: paginas.length > 1, consultadoDesde: paginas[0]?.generado_en ?? null,
    cargando: autorizado && !sinPermiso && consulta.isPending,
    enVuelo: consulta.isFetching, error: sinPermiso ? new CrmApiError('Ya no tienes acceso a estas tareas.', '42501') : consulta.error,
    sinPermiso, hayMas: !sinPermiso && !consulta.error && consulta.hasNextPage,
    cargarMas: async () => { if (autorizado && !sinPermiso && !consulta.isFetching && consulta.hasNextPage) await consulta.fetchNextPage() },
    recargar: async () => {
      if (!autorizado) return
      revocada.current = false
      // Volver a initialPageParam, cancelando cualquier respuesta de la foto vieja.
      await cliente.cancelQueries({ queryKey: clave, exact: true })
      await cliente.resetQueries({ queryKey: clave, exact: true })
    },
  }
}
