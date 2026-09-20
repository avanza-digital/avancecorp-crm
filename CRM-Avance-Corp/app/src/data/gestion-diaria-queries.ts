// Hooks operativos de Gestión Diaria (patrón useColaAccionOperativa): en sesión
// real el servidor decide y este hook solo valida y expone; en demo, el espejo
// puro sobre el ámbito en memoria; ante error, `null` y la pantalla pinta «—».
// Fail-closed también en refetch: TanStack conserva `data` cuando un refetch
// falla y servir esa foto vieja como fresca sería mentir.
import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import {
  limiteConSonda,
  registroDesdeDemo,
  type CursorRegistro,
  type FiltrosRegistro,
  type RegistroPagina,
} from '@/lib/gestion-diaria'
import { crmQueryKeys } from './crm-queries'
import { listarRegistroActividad } from './gestion-diaria-api'

export const gestionDiariaKeys = {
  raiz: () => [...crmQueryKeys.raiz, 'gestion-diaria'] as const,
  registro: (actor: string | null, filtros: FiltrosRegistro, cursor: CursorRegistro | null, limite: number) =>
    [...gestionDiariaKeys.raiz(), actor, 'registro', filtros, cursor, limite] as const,
}

/** Sin realtime en el CRM: la primera página se refresca sola cada minuto. */
export const INTERVALO_REGISTRO_MS = 60_000

export interface RegistroActividadHook {
  /** Página validada (real) o espejo (demo); null mientras carga o si el RPC cayó. */
  pagina: RegistroPagina | null
  cargando: boolean
  enVuelo: boolean
  error: unknown
  recargar: () => Promise<void>
}

export function useRegistroActividadOperativo(
  filtros: FiltrosRegistro,
  cursor: CursorRegistro | null,
  limite: number,
  habilitado = true,
): RegistroActividadHook {
  const { yo } = useAuth()
  const { actividadesDelAmbito, ambito, equipo } = useCRMData()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useQuery({
    queryKey: gestionDiariaKeys.registro(yo?.id ?? null, filtros, cursor, limite),
    queryFn: ({ signal }) => listarRegistroActividad(filtros, cursor, limite, signal),
    enabled: sesionReal,
    // Las páginas con cursor son estables (keyset hacia atrás): solo la primera late.
    refetchInterval: cursor === null ? INTERVALO_REGISTRO_MS : false,
    refetchOnWindowFocus: 'always',
    refetchOnReconnect: 'always',
  })
  const pagina = useMemo(() => {
    if (!habilitado || !yo) return null
    if (yo.demo) {
      // El ámbito ya viene recortado por rol (espejo de la RLS): un supervisor
      // demo no ve al otro equipo, igual que en real.
      const porId = new Map(ambito.leads.map((l) => [l.id, { nombre_completo: l.nombre_completo, etapa: l.etapa, activo: l.activo }]))
      return registroDesdeDemo(actividadesDelAmbito, porId, equipo, filtros, cursor, limiteConSonda(limite))
    }
    if (consulta.error) return null
    return consulta.data ?? null
  }, [actividadesDelAmbito, ambito.leads, consulta.data, consulta.error, cursor, equipo, filtros, habilitado, limite, yo])
  return {
    pagina,
    cargando: sesionReal && consulta.isPending,
    enVuelo: sesionReal && consulta.isFetching,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
