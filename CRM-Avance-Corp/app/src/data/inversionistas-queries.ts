import { useQuery } from '@tanstack/react-query'
import type { FiltrosInversionistas } from '@/lib/inversionistas'
import { listarInversionistas, obtenerCuentasInversionista, obtenerEstadoCarteraInversionistas, obtenerFichaInversionista } from './inversionistas-api'

export const inversionistasKeys = {
  actor: (actor: string) => ['crm', 'inversionistas', actor] as const,
  estado: (actor: string) => [...inversionistasKeys.actor(actor), 'estado'] as const,
  lista: (actor: string, filtros: FiltrosInversionistas) => [...inversionistasKeys.actor(actor), 'lista', filtros] as const,
  ficha: (actor: string, id: string, inversiones = 1, historial = 1) =>
    [...inversionistasKeys.actor(actor), 'persona', id, 'ficha', inversiones, historial] as const,
  cuentas: (actor: string, id: string, perfil: string, moneda: 'PEN' | 'USD') =>
    [...inversionistasKeys.actor(actor), 'persona', id, 'cuentas', perfil, moneda] as const,
}
const lecturaVigente = {
  staleTime: 0, gcTime: 0, retry: false, refetchOnMount: 'always' as const,
  refetchOnWindowFocus: 'always' as const, refetchOnReconnect: 'always' as const,
  refetchInterval: 15_000,
}
export function useEstadoCarteraInversionistas(actor: string, habilitado = true) {
  return useQuery({...lecturaVigente, queryKey: inversionistasKeys.estado(actor),
    enabled: habilitado && Boolean(actor), queryFn: ({signal}) => obtenerEstadoCarteraInversionistas(signal)})
}
export function useInversionistas(actor: string, filtros: FiltrosInversionistas) {
  return useQuery({...lecturaVigente, queryKey: inversionistasKeys.lista(actor, filtros),
    enabled: Boolean(actor), queryFn: ({signal}) => listarInversionistas(filtros, signal)})
}
export function useFichaInversionista(actor: string, id: string, inversiones: number, historial: number) {
  return useQuery({...lecturaVigente, queryKey: inversionistasKeys.ficha(actor, id, inversiones, historial),
    enabled: Boolean(actor && id), queryFn: ({signal}) => obtenerFichaInversionista(id, inversiones, historial, signal)})
}
export function useCuentasInversionista(actor: string, id: string, perfil: string, moneda: 'PEN' | 'USD', autorizada: boolean) {
  return useQuery({...lecturaVigente, queryKey: inversionistasKeys.cuentas(actor, id, perfil, moneda),
    enabled: autorizada && Boolean(actor && id && perfil),
    queryFn: ({signal}) => obtenerCuentasInversionista(id, perfil, moneda, signal)})
}
