import { useContext, useMemo } from 'react'
import { QueryClientContext, useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { queryClient } from '@/lib/query-client'
import { normalizarLeadIds } from '@/lib/cierre-estado'
import type { RecorridoLead } from '@/lib/recorrido-lead'
import { obtenerRecorridos } from './recorrido-api'

export const recorridoKeys = {
  raiz: () => ['crm', 'leads', 'recorrido'] as const,
  leads: (actor: string, rol: string, ids: readonly string[]) => [...recorridoKeys.raiz(), actor, rol, ids] as const,
}

export type EstadoConsultaRecorrido = 'inactivo' | 'cargando' | 'error' | 'listo'
const VACIO: ReadonlyMap<string, RecorridoLead> = new Map()

export function useRecorridoLeads(leadIds: readonly string[]) {
  const { yo } = useAuth()
  const proveedor = useContext(QueryClientContext)
  const ids = normalizarLeadIds(leadIds)
  const enabled = Boolean(proveedor && yo && !yo.demo && ids.length)
  const consulta = useQuery({
    queryKey: recorridoKeys.leads(yo?.id ?? '', yo?.rol ?? '', ids),
    queryFn: ({ signal }) => obtenerRecorridos(ids, signal),
    enabled,
    // Nunca se arrastra un «completo» del actor/página/ciclo anterior.
    staleTime: 15_000,
  }, proveedor ?? queryClient)
  const estado: EstadoConsultaRecorrido = !enabled ? 'inactivo'
    : consulta.isError ? 'error'
      : consulta.isFetching || consulta.isPending ? 'cargando'
        : !consulta.data || consulta.data.modo === 'apagado' ? 'inactivo' : 'listo'
  const datos = estado === 'listo' ? consulta.data : undefined
  const porLead = useMemo(() => datos ? new Map(datos.filas.map((r) => [r.lead_id, r])) : VACIO, [datos])
  return { estado, porLead, refetch: consulta.refetch }
}
