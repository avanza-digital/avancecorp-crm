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
/**
 * Lo que «Ahora» puede usar de la ficha para llamar: el número y si se le puede
 * contactar. Se contacta SOLO si la ficha lo permite (`capacidades.contactar`)
 * Y la persona no pidió que no la llamen (`no_contactar`): si los dos campos se
 * contradicen, gana el «no» (Codex, 29/09/2026).
 */
export function contactoDeFicha(ficha: { persona: { telefono: string | null; no_contactar: boolean }; capacidades: { contactar: boolean } }) {
  return { telefono: ficha.persona.telefono, contactar: ficha.capacidades.contactar === true && ficha.persona.no_contactar === false }
}

/**
 * Teléfono y permiso de contacto de un cliente, leídos de su ficha AUTORIZADA
 * (`crm.inversionista_ficha_fn`): la cola del día no trae teléfonos. Lo pide
 * «Ahora» de Gestión diaria al elegir una tarea de cliente y se RELEE cada vez
 * que se elige y al volver a la pestaña (sin sondeo: la ficha entera se relee
 * cada 15 s y aquí solo hace falta el número). Quien lo pinta es fail-closed:
 * con error no se muestra el número, aunque TanStack conserve el anterior.
 */
export function useContactoInversionista(actor: string, id: string) {
  return useQuery({ queryKey: [...inversionistasKeys.actor(actor), 'persona', id, 'contacto'] as const,
    enabled: Boolean(actor && id), retry: false, staleTime: 0,
    refetchOnMount: 'always', refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
    queryFn: async ({signal}) => contactoDeFicha(await obtenerFichaInversionista(id, 1, 1, signal))})
}
export function useCuentasInversionista(actor: string, id: string, perfil: string, moneda: 'PEN' | 'USD', autorizada: boolean) {
  return useQuery({...lecturaVigente, queryKey: inversionistasKeys.cuentas(actor, id, perfil, moneda),
    enabled: autorizada && Boolean(actor && id && perfil),
    queryFn: ({signal}) => obtenerCuentasInversionista(id, perfil, moneda, signal)})
}
