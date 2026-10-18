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
    let vigente = true
    const consultar = () => {
      if (!vigente || document.visibilityState === 'hidden' || enVuelo) return
      enVuelo = true
      // Las fuentes conservan su error y su reintento; el temporizador no debe
      // crear un rechazo sin gestionar ni lanzar una segunda vuelta en paralelo.
      void refrescar().catch(() => {}).finally(() => { enVuelo = false })
    }
    // Volver de otro módulo también revalida la foto: no esperar el primer
    // intervalo con cifras que el store pudo cargar mucho antes. Diferir un
    // microturno evita duplicar el arranque al remontar efectos en StrictMode.
    queueMicrotask(consultar)
    const intervalo = window.setInterval(consultar, 5 * 60_000)
    return () => { vigente = false; window.clearInterval(intervalo) }
  }, [actor, habilitado])
}
