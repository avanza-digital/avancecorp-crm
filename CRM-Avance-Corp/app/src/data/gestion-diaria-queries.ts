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
import { diaAnalistaDesdeDemo, type DiaAnalista } from '@/lib/gestion-diaria-analista'
import { fechaLima } from '@/lib/agenda-derivada'
import { useAhora } from '@/lib/ahora'
import { crmQueryKeys } from './crm-queries'
import { listarRegistroActividad, obtenerDiaAnalista } from './gestion-diaria-api'

export const gestionDiariaKeys = {
  raiz: () => [...crmQueryKeys.raiz, 'gestion-diaria'] as const,
  registro: (actor: string | null, filtros: FiltrosRegistro, cursor: CursorRegistro | null, limite: number) =>
    [...gestionDiariaKeys.raiz(), actor, 'registro', filtros, cursor, limite] as const,
  dia: (actor: string | null, dia: string | null, analista: string | null) =>
    [...gestionDiariaKeys.raiz(), actor, 'dia', dia, analista] as const,
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
    queryKey: [...gestionDiariaKeys.registro(yo?.id ?? null, filtros, cursor, limite), yo?.rol ?? null, yo?.demo ?? null],
    queryFn: ({ signal }) => listarRegistroActividad(filtros, cursor, limite, signal),
    enabled: sesionReal,
    // «Actualizar» desde una página posterior vuelve a la primera. Debe
    // reconsultarla incluso si la caché global aún la considera fresca.
    staleTime: 0,
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

export interface DiaAnalistaHook {
  /** El día validado (real) o el espejo (demo); null mientras carga o si el RPC cayó. */
  dia: DiaAnalista | null
  cargando: boolean
  enVuelo: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * El día del analista. En sesión real manda el servidor y la pantalla solo
 * presenta; en demo, el espejo puro sobre el ámbito en memoria. Fail-closed:
 * si el RPC cae, `dia` es null y la pantalla dice que no pudo leerlo — servir
 * la foto anterior como fresca sería mentir. Se refresca cada minuto.
 */
export function useDiaAnalista(diaPedido: string | null, analistaId: string | null, habilitado = true): DiaAnalistaHook {
  const { yo } = useAuth()
  const { ambito, actividadesDelAmbito, tareas } = useCRMData()
  const ahora = useAhora()
  const sesionReal = Boolean(habilitado && yo && !yo.demo)
  const consulta = useQuery({
    queryKey: gestionDiariaKeys.dia(yo?.id ?? null, diaPedido, analistaId),
    queryFn: ({ signal }) => obtenerDiaAnalista(diaPedido, analistaId, signal),
    enabled: sesionReal,
    refetchInterval: INTERVALO_REGISTRO_MS,
    refetchOnWindowFocus: 'always',
    refetchOnReconnect: 'always',
  })
  const dia = useMemo(() => {
    if (!habilitado || !yo) return null
    if (yo.demo) {
      return diaAnalistaDesdeDemo(analistaId ?? yo.id, ambito.leads, actividadesDelAmbito, tareas, ahora, diaPedido ?? fechaLima(ahora))
    }
    if (consulta.error) return null
    return consulta.data ?? null
  }, [actividadesDelAmbito, ahora, ambito.leads, analistaId, consulta.data, consulta.error, diaPedido, habilitado, tareas, yo])
  return {
    dia,
    cargando: sesionReal && consulta.isPending,
    enVuelo: sesionReal && consulta.isFetching,
    error: sesionReal ? consulta.error : null,
    recargar: async () => { await consulta.refetch() },
  }
}
