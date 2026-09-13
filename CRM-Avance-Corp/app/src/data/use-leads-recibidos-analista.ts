import { useQuery } from '@tanstack/react-query'
import { listarLeadsRecibidosAnalista } from './crm-api'
import { crmQueryKeys } from './crm-queries'

export const claveLeadsRecibidosAnalista = (desde: string, hasta: string) => [
  ...crmQueryKeys.metricasAmbito(),
  'leads-recibidos-analista',
  desde,
  hasta,
] as const

/** La clave incluye el rango; la RPC decide y verifica el actor autenticado. */
export function useLeadsRecibidosAnalista(
  habilitada: boolean,
  desde: string,
  hasta: string,
) {
  return useQuery({
    queryKey: claveLeadsRecibidosAnalista(desde, hasta),
    queryFn: ({ signal }) => listarLeadsRecibidosAnalista(desde, hasta, signal),
    enabled: habilitada && Boolean(desde) && Boolean(hasta),
  })
}
