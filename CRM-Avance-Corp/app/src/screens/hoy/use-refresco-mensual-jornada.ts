import { useEffect, useEffectEvent } from 'react'

/** La actividad ya sondea cada minuto y Facturación cada cinco. El mes debe
 * avanzar también con Hoy abierto. Foco/reconexión los atiende el store. */
export function useRefrescoMensualJornada({ actor, habilitado, recargar }: {
  actor: string | null; habilitado: boolean; recargar: () => Promise<void>
}) {
  const refrescar = useEffectEvent(recargar)
  useEffect(() => {
    if (!habilitado || !actor) return
    let enVuelo = false
    const intervalo = window.setInterval(() => {
      if (document.visibilityState === 'hidden' || enVuelo) return
      enVuelo = true
      // Las fuentes conservan su error y su reintento; el temporizador no debe
      // crear un rechazo sin gestionar ni lanzar una segunda vuelta en paralelo.
      void refrescar().catch(() => {}).finally(() => { enVuelo = false })
    }, 5 * 60_000)
    return () => window.clearInterval(intervalo)
  }, [actor, habilitado])
}
