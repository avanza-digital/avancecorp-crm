// lib/ahora.ts — reloj vivo compartido del CRM.
// useAhora() devuelve el epoch en ms y re-renderiza al componente:
//  (a) cada `intervaloMs` (default 1 minuto), y
//  (b) al recuperar el foco de la ventana o la visibilidad de la pestaña
//      (así "hace X días" y los semáforos se refrescan al volver del almuerzo
//      sin esperar el siguiente tick).
// El valor está pensado para entrar como dependencia de useMemo y como
// argumento `ahora` de las funciones de lib/inteligencia.ts.
import { useEffect, useState } from 'react'

export function useAhora(intervaloMs = 60_000): number {
  const [ahora, setAhora] = useState<number>(() => Date.now())

  useEffect(() => {
    const tick = () => setAhora(Date.now())
    const alCambiarVisibilidad = () => {
      if (document.visibilityState === 'visible') tick()
    }
    const id = setInterval(tick, intervaloMs)
    window.addEventListener('focus', tick)
    document.addEventListener('visibilitychange', alCambiarVisibilidad)
    return () => {
      clearInterval(id)
      window.removeEventListener('focus', tick)
      document.removeEventListener('visibilitychange', alCambiarVisibilidad)
    }
  }, [intervaloMs])

  return ahora
}
