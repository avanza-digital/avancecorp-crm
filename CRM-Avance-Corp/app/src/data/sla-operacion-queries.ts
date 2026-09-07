import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { crmQueryKeys } from './crm-queries'
import { cambiarModoSla, publicarReglasSlaAprobadas, obtenerConfiguracionSlaV2, listarColaSla, obtenerEstadosSlaV2, obtenerResumenAvisosSla } from './sla-operacion-api'
import { CrmApiError } from './crm-api'
import type { CursorSla, FiltrosSla } from '@/lib/sla-operacion'
import { intervaloReconsultaSla } from './sla-operacion-reloj'

// Ambas lecturas heredan la invalidación existente de cada gestión, tarea y cambio de ámbito.
export const slaOperacionKeys = {
  raiz: () => [...crmQueryKeys.metricasAmbito(), 'sla-v2'] as const,
  estado: (actor: string | null, ids: string[]) => [...slaOperacionKeys.raiz(), actor, 'estado', ids] as const,
  cola: (actor: string | null, filtros: FiltrosSla, cursor: CursorSla | null, limite: number) => [...slaOperacionKeys.raiz(), actor, 'cola', filtros, cursor, limite] as const,
  avisos: (actor: string | null) => [...slaOperacionKeys.raiz(), actor, 'avisos'] as const,
}
export function useResumenAvisosSla(habilitada: boolean) {
  const { yo } = useAuth()
  return useQuery({ queryKey: slaOperacionKeys.avisos(yo?.id ?? null),
    queryFn: ({ signal }) => obtenerResumenAvisosSla(signal), enabled: Boolean(habilitada && yo && !yo.demo),
    refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
}
export function useEstadosSlaV2(ids: string[]) {
  const { yo } = useAuth()
  return useQuery({ queryKey: slaOperacionKeys.estado(yo?.id ?? null, ids),
    queryFn: ({ signal }) => obtenerEstadosSlaV2(ids, signal), enabled: Boolean(yo && !yo.demo), refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
}
export function useModoSla() {
  const { yo } = useAuth()
  const consulta = useEstadosSlaV2([])
  return { ...consulta, legado: Boolean(yo?.demo || (!consulta.error && consulta.data && consulta.data.modo !== 'activo')),
    activo: Boolean(!yo?.demo && !consulta.error && consulta.data?.modo === 'activo') }
}
export function useColaSlaPagina(filtros: FiltrosSla, cursor: CursorSla | null, limite: number, habilitada: boolean) {
  const { yo } = useAuth()
  return useQuery({ queryKey: slaOperacionKeys.cola(yo?.id ?? null, filtros, cursor, limite),
    queryFn: ({ signal }) => listarColaSla(filtros, cursor, limite, signal), enabled: Boolean(habilitada && yo && !yo.demo),
    refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
  })
}

export function useConfiguracionSlaV2() {
  const { yo } = useAuth()
  return useQuery({ queryKey: [...crmQueryKeys.configSla(), 'operacion-v2', yo?.id],
    queryFn: ({ signal }) => obtenerConfiguracionSlaV2(signal), enabled: Boolean(yo && !yo.demo) })
}
export function useCambiarModoSla() {
  const cliente = useQueryClient()
  return useMutation({ mutationFn: ({ revision, modo }: { revision: number; modo: 'activo' | 'legado' }) => cambiarModoSla(revision, modo),
    retry: false,
    onError: async (error) => {
      if (error instanceof CrmApiError && (error.code === 'P0409' || error.code === '40001')) {
        await cliente.invalidateQueries({ queryKey: crmQueryKeys.configSla() })
      }
    },
    onSuccess: async () => { await Promise.all([
      cliente.invalidateQueries({ queryKey: crmQueryKeys.configSla() }),
      cliente.invalidateQueries({ queryKey: slaOperacionKeys.raiz() }),
    ]) } })
}

export function usePublicarReglasSlaAprobadas() {
  const cliente = useQueryClient()
  return useMutation({ mutationFn: publicarReglasSlaAprobadas, retry: false,
    onSettled: async () => { await Promise.all([
      cliente.invalidateQueries({ queryKey: crmQueryKeys.configSla() }),
      cliente.invalidateQueries({ queryKey: slaOperacionKeys.raiz() }),
    ]) },
  })
}
