import { useEffect, useRef } from 'react'
import { useCarteraPaginada } from '@/data/use-cartera-paginada'
import { fechaLima } from '@/lib/agenda-derivada'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'

/** Una consulta compartida por contador y lista. Permanece montada al ver la
 * agenda: las asignaciones hechas por otro usuario también deben avisar ahí. */
export function useLeadsRecibidosHoy(ahora: number) {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const dia = fechaLima(ahora)
  const cartera = useCarteraPaginada(ambito.leads, {
    vendedorId: yo?.id ?? 'sin_asignar',
    recepcion: { desde: dia, hasta: dia },
  })
  const sesionReal = Boolean(yo && !yo.demo)
  const recargarRef = useRef({ recargar: cartera.recargar, cargando: cartera.cargando || cartera.cargandoMas })
  useEffect(() => {
    recargarRef.current = { recargar: cartera.recargar, cargando: cartera.cargando || cartera.cargandoMas }
  }, [cartera.recargar, cartera.cargando, cartera.cargandoMas])
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
    cartera,
    // Un error no equivale a cero recibidos ni permite afirmar un total actual.
    total: cartera.cargando || cartera.error ? null : cartera.resumen?.totales.vivos ?? null,
    dia,
    demo: Boolean(yo?.demo),
  }
}

export type DatosLeadsRecibidosHoy = ReturnType<typeof useLeadsRecibidosHoy>
