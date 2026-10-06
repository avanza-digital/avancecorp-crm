import { gestionDiariaKeys } from './gestion-diaria-queries'
import { crmQueryKeys } from './crm-queries'
import { useQuery } from '@tanstack/react-query'
import { estadoPostventa, fichaPostventa, vencimientosPostventa } from './postventa-api'
import { inversionistasKeys } from './inversionistas-queries'
import type { EmpresaInversion } from '@/lib/inversionistas'
import { queryClient } from '@/lib/query-client'

export const postventaKeys = {actor: (actor: string) => ['crm', 'postventa', actor] as const}
// Cada 60 s (antes 15) y solo con la pestaña visible: el sondeo únicamente detecta si Gerencia
// apaga la postventa; las escrituras ya refrescan (refrescarPostventa), al volver a la pestaña se
// consulta al instante y el servidor rechaza cualquier acción con la postventa apagada.
export const POSTVENTA_REFRESCO_MS = 60_000
const vigente = {staleTime: 0, gcTime: 0, retry: false, refetchInterval: POSTVENTA_REFRESCO_MS,
  refetchOnMount: 'always' as const, refetchOnWindowFocus: 'always' as const, refetchOnReconnect: 'always' as const}
export function usePostventa(actor: string, habilitada = true) {
  return useQuery({...vigente, queryKey: [...postventaKeys.actor(actor), 'estado'],
    enabled: Boolean(actor) && habilitada, queryFn: ({signal}) => estadoPostventa(signal)})
}
export function useFichaPostventa(actor: string, persona: string, habilitada = true) {
  // Al apagar F6 la observación cambia de clave; gcTime: 0 retira la lectura
  // anterior. Reactivarlo exige una lectura nueva sin desmontar la ficha F5.
  return useQuery({...vigente, queryKey: [...postventaKeys.actor(actor), 'persona', persona, habilitada],
    enabled: Boolean(actor && persona) && habilitada, queryFn: ({signal}) => fichaPostventa(persona, signal)})
}
export function useVencimientosPostventa(actor: string, empresa: EmpresaInversion | '', pagina: number, habilitada: boolean) {
  return useQuery({...vigente, queryKey: [...postventaKeys.actor(actor), 'vencimientos', empresa, pagina],
    enabled: Boolean(actor) && habilitada, queryFn: ({signal}) => vencimientosPostventa(empresa, pagina, signal)})
}
export async function refrescarPostventa(actor: string) {
  const claves = [postventaKeys.actor(actor), inversionistasKeys.actor(actor), gestionDiariaKeys.raiz(), crmQueryKeys.metricas()]
  await Promise.all(claves.map(queryKey => queryClient.cancelQueries({ queryKey })))
  await Promise.all(claves.map(queryKey => queryClient.invalidateQueries({ queryKey })))
}
