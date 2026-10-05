import { useCallback, useEffect, useMemo, useRef } from 'react'
import { useCarteraPaginada } from '@/data/use-cartera-paginada'
import { fechaLima } from '@/lib/agenda-derivada'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { tieneGestionVigente } from '@/lib/pipeline-columnas'

/** Lista completa y resumen de pendientes, con el mismo titular y día.
 * Permanecen montados al ver agenda; un único sondeo refresca ambas lecturas. */
export function useLeadsRecibidosHoy(ahora: number) {
  const { yo } = useAuth()
  const { ambito, actividadesDelAmbito } = useCRMData()
  const dia = fechaLima(ahora)
  const filtros = {
    vendedorId: yo?.id ?? 'sin_asignar',
    recepcion: { desde: dia, hasta: dia },
  }
  const cartera = useCarteraPaginada(ambito.leads, filtros)
  // El espejo demo tiene todo el timeline; en real manda el filtro del
  // servidor, nunca la página visible ni el último contacto (puede deshacerse).
  const sinGestionDemo = useMemo(() => yo?.demo
    ? ambito.leads.filter(lead => !tieneGestionVigente(lead, actividadesDelAmbito))
    : [], [yo?.demo, ambito.leads, actividadesDelAmbito])
  const sinGestion = useCarteraPaginada(sinGestionDemo, {
    ...filtros, gestion: 'sin_gestion',
  })
  const recargar = useCallback(async () => {
    await Promise.all([cartera.recargar(), sinGestion.recargar()])
  }, [cartera.recargar, sinGestion.recargar])
  const sesionReal = Boolean(yo && !yo.demo)
  const cargando = cartera.cargando || cartera.cargandoMas || sinGestion.cargando
  const recargarRef = useRef({ recargar, cargando })
  useEffect(() => {
    recargarRef.current = { recargar, cargando }
  }, [recargar, cargando])
  // Foco y reconexión ya refrescan la caché. El sondeo cubre quedarse en HOY.
  useEffect(() => {
    if (!sesionReal) return
    const intervalo = window.setInterval(() => {
      // Un refetch durante fetchNextPage cancelaría la página y su foco.
      if (document.visibilityState !== 'hidden' && !recargarRef.current.cargando) void recargarRef.current.recargar()
    }, 60_000)
    return () => window.clearInterval(intervalo)
  }, [yo?.id, sesionReal])

  return {
    cartera: { ...cartera, recargar },
    // Un error no equivale a cero recibidos ni permite afirmar un total actual.
    total: cartera.cargando || cartera.error ? null : cartera.resumen?.totales.vivos ?? null,
    // Cerrados no requieren gestión. «abiertos» cuenta TODA la base filtrada,
    // incluso los pendientes de páginas que el usuario todavía no ha abierto.
    pendientes: cartera.error || sinGestion.cargando || sinGestion.error
      ? null : sinGestion.resumen?.totales.abiertos ?? null,
    errorPendientes: sinGestion.error,
    cargandoPendientes: sinGestion.cargando,
    dia,
    demo: Boolean(yo?.demo),
  }
}

export type DatosLeadsRecibidosHoy = ReturnType<typeof useLeadsRecibidosHoy>
