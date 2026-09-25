import { useQuery, type UseQueryResult } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { gestionDiariaKeys, INTERVALO_REGISTRO_MS } from './gestion-diaria-queries'
import { obtenerPulsoGerencia, obtenerHabitosGerencia } from './gestion-diaria-pulso-api'
import { obtenerDiaEquipo } from './gestion-diaria-api'

export const clavePulso = (actor: string | null, rol: string | null, tipo: string, dia: string, alcance: number | string | null = null) =>
  [...gestionDiariaKeys.raiz(), actor, rol, 'gerencia', tipo, dia, alcance] as const
function estadoConsulta<T>(consulta: UseQueryResult<T>, habilitada: boolean) {
  return { datos: habilitada && !consulta.error ? consulta.data ?? null : null,
    cargando: habilitada && consulta.isPending, enVuelo: habilitada && consulta.isFetching,
    error: habilitada ? consulta.error : null,
    recargar: async () => { if (habilitada) await consulta.refetch() } }
}
const refresco = { refetchInterval: INTERVALO_REGISTRO_MS, refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' } as const
export function usePulsoGerencia(dia: string) {
  const { yo } = useAuth()
  const real = yo?.rol === 'gerencia' && !yo.demo
  const consulta = useQuery({ queryKey: clavePulso(yo?.id ?? null, yo?.rol ?? null, 'pulso', dia),
    queryFn: ({ signal }) => obtenerPulsoGerencia(dia, signal), enabled: real, ...refresco })
  return estadoConsulta(consulta, real)
}
export function useHabitosGerencia(hasta: string, dias: 7 | 14 | 30, abierta: boolean) {
  const { yo } = useAuth()
  const real = yo?.rol === 'gerencia' && !yo.demo && abierta
  const consulta = useQuery({ queryKey: clavePulso(yo?.id ?? null, yo?.rol ?? null, 'habitos', hasta, dias),
    queryFn: ({ signal }) => obtenerHabitosGerencia(hasta, dias, signal), enabled: real,
    refetchInterval: false, refetchOnWindowFocus: false, refetchOnReconnect: 'always' })
  return estadoConsulta(consulta, real)
}
export function useDetallePulso(dia: string, abierto: boolean) {
  const { yo } = useAuth()
  const real = yo?.rol === 'gerencia' && !yo.demo && abierto
  // NULL = operación completa autorizada para gerencia. El pulso particiona
  // al supervisor más cercano; la tabla se restringe con esos IDs confirmados.
  const consulta = useQuery({ queryKey: clavePulso(yo?.id ?? null, yo?.rol ?? null, 'detalle', dia),
    queryFn: ({ signal }) => obtenerDiaEquipo(dia, null, signal), enabled: real, ...refresco })
  return estadoConsulta(consulta, real)
}
