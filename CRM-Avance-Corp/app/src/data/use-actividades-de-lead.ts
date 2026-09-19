import { useCallback, useMemo } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import {
  SENALES_VACIAS,
  combinarSenales,
  fusionarHistorial,
  localesVivas,
  senalesDesdeActividades,
  type SenalesLead,
} from '@/lib/historial-lead'
import type { Actividad } from '@/lib/tipos'
import { useHistorialLead } from './crm-queries'

export interface ActividadesDeLead {
  /** Historial del lead, más reciente primero: páginas servidas + optimistas vivas. */
  items: Actividad[]
  /** Señales «alguna vez» sobre TODO el historial (no solo lo cargado). */
  senales: SenalesLead
  hayMas: boolean
  /** Primera página en vuelo: todavía no hay historial que pintar. */
  cargando: boolean
  cargandoMas: boolean
  error: unknown
  cargarMas: () => void
  reintentar: () => void
}

const SIN_ITEMS: Actividad[] = []

/**
 * Une la RPC `crm.actividades_de_lead_fn` (historial POR LEAD, cursor keyset,
 * Fase 1 «sin topes») con su espejo demo y con las filas optimistas del store.
 *
 * En sesión real el servidor decide QUÉ filas y en qué orden; el navegador
 * concatena páginas y antepone las gestiones recién registradas mientras el
 * servidor no las devuelva (ver `fusionarHistorial`). En demo no se toca la
 * red (fail-closed): el historial es el del ámbito vivo del store, igual que
 * hasta hoy, y las señales se derivan de él.
 *
 * Lo que este hook NO hace: caer a la lista global del ámbito cuando la RPC
 * falla. Esa lista es la que PostgREST recorta a 1 000 filas y pintaba un
 * historial incompleto sin decirlo; ante un fallo se dice «no se pudo cargar»
 * y se ofrece reintentar.
 */
export function useActividadesDeLead(leadId: string | null): ActividadesDeLead {
  const { yo } = useAuth()
  const { actividadesDe } = useCRMData()
  const esDemo = Boolean(yo?.demo)
  const sesionReal = Boolean(yo && !yo.demo)
  const consulta = useHistorialLead(sesionReal && leadId != null, leadId ?? '')

  // Demo: la lista del store ya viene DESC por creado_en (contrato de actividadesDe).
  const locales = useMemo(() => (leadId ? actividadesDe(leadId) : SIN_ITEMS), [actividadesDe, leadId])

  const paginas = consulta.data?.pages
  const leidoEn = consulta.dataUpdatedAt
  const servidor = useMemo(() => (paginas ?? []).flatMap((p) => p.items), [paginas])
  const itemsReales = useMemo(
    () => fusionarHistorial(locales, servidor, leidoEn),
    [locales, servidor, leidoEn],
  )
  const senalesReales = useMemo(() => {
    const servidas = paginas?.[0]?.senales ?? SENALES_VACIAS
    return combinarSenales(servidas, senalesDesdeActividades(localesVivas(locales, leidoEn)))
  }, [paginas, locales, leidoEn])
  const senalesDemo = useMemo(() => senalesDesdeActividades(locales), [locales])

  const cargarMas = useCallback(() => {
    if (esDemo) return
    if (consulta.hasNextPage && !consulta.isFetchingNextPage) void consulta.fetchNextPage()
  }, [consulta, esDemo])
  const reintentar = useCallback(() => {
    if (esDemo) return
    void consulta.refetch()
  }, [consulta, esDemo])

  if (esDemo || leadId == null) {
    return {
      items: locales,
      senales: senalesDemo,
      hayMas: false,
      cargando: false,
      cargandoMas: false,
      error: null,
      cargarMas,
      reintentar,
    }
  }

  return {
    items: itemsReales,
    senales: senalesReales,
    // `hasNextPage` lo decide el cursor que devolvió el SERVIDOR. Con error se
    // fuerza a false: prometer una página que no se puede pedir es peor que
    // decir que ahí termina lo cargado; el banner de error es quien explica.
    hayMas: Boolean(consulta.hasNextPage) && !consulta.error,
    cargando: consulta.isPending,
    cargandoMas: consulta.isFetchingNextPage,
    error: consulta.error,
    cargarMas,
    reintentar,
  }
}
