import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { listarLeads, type FiltrosLeads } from './crm-api'

export const crmQueryKeys = {
  raiz: ['crm'] as const,
  leads: () => [...crmQueryKeys.raiz, 'leads'] as const,
  paginaLeads: (filtros: FiltrosLeads) => [...crmQueryKeys.leads(), 'pagina', filtros] as const,
}

export function usePaginaLeads(filtros: FiltrosLeads, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.paginaLeads(filtros),
    queryFn: ({ signal }) => listarLeads(filtros, signal),
    placeholderData: keepPreviousData,
    enabled: habilitada,
  })
}

