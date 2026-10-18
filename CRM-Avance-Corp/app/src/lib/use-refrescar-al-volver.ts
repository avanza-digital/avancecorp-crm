import { useEffect } from 'react'

/** Relee al volver a una pantalla; el llamante decide si un borrador lo impide. */
export function useRefrescarAlVolver(actualizar: () => void | Promise<void>, bloqueado = false) {
  useEffect(() => {
    if (bloqueado) return
    let pendiente: ReturnType<typeof setTimeout> | undefined
    const alVolver = () => {
      clearTimeout(pendiente)
      if (document.visibilityState === 'hidden') return
      pendiente = setTimeout(() => {
        if (document.visibilityState !== 'hidden') void actualizar()
      }, 250)
    }
    window.addEventListener('focus', alVolver)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      clearTimeout(pendiente)
      window.removeEventListener('focus', alVolver)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [actualizar, bloqueado])
}
