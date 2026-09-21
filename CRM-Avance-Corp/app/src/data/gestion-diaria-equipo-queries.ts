import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { diaEquipoDesdeDemo } from '@/lib/gestion-diaria-equipo-demo'
import type { DiaEquipo } from '@/lib/gestion-diaria-equipo'
import { gestionDiariaKeys, INTERVALO_REGISTRO_MS } from './gestion-diaria-queries'
import { obtenerDiaEquipo } from './gestion-diaria-api'

export interface DiaEquipoHook {
  dia: DiaEquipo | null
  cargando: boolean
  enVuelo: boolean
  error: unknown
  recargar: () => Promise<void>
}

export const claveDiaEquipo = (actor: string | null, rol: string | null, dia: string) =>
  [...gestionDiariaKeys.raiz(), actor, rol, 'equipo', dia] as const

export function useDiaEquipo(diaPedido: string): DiaEquipoHook {
  const { yo } = useAuth()
  const { equipo, ambito, actividadesDelAmbito, tareas } = useCRMData()
  const ahora = useAhora()
  const autorizado = yo?.rol === 'supervisor'
  const real = autorizado && !yo.demo
  const consulta = useQuery({
    queryKey: claveDiaEquipo(yo?.id ?? null, yo?.rol ?? null, diaPedido),
    queryFn: ({ signal }) => obtenerDiaEquipo(diaPedido, yo!.id, signal),
    enabled: real,
    refetchInterval: INTERVALO_REGISTRO_MS,
    refetchOnWindowFocus: 'always',
    refetchOnReconnect: 'always',
  })
  const dia = useMemo(() => {
    if (!autorizado) return null
    if (yo.demo) return diaEquipoDesdeDemo(yo.id, equipo, ambito.leads, actividadesDelAmbito, tareas, ahora, diaPedido)
    // No convertir un fallo de refresco/revocación en cifras antiguas o ceros.
    return consulta.error ? null : consulta.data ?? null
  }, [autorizado, yo, equipo, ambito.leads, actividadesDelAmbito, tareas, ahora, diaPedido, consulta.error, consulta.data])
  return { dia, cargando: real && consulta.isPending, enVuelo: real && consulta.isFetching,
    error: real ? consulta.error : null, recargar: async () => { if (real) await consulta.refetch() } }
}
