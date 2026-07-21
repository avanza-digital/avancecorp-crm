// lib/media.ts — hook reactivo de media query. El CRM lo usa para decidir EN
// TIEMPO REAL si una vista pinta una tabla (desktop) o un card-stack (móvil)
// SIN montar las dos a la vez: renderizar ambas y ocultar una con CSS duplicaría
// los intervalos de useVentana. Elegir el camino por JS monta solo uno.
//
// Seguro en jsdom/SSR: si window.matchMedia no existe, reporta "no coincide"
// (→ desktop). Por eso los tests que no lo stubbean ven la tabla, como antes.
import { useCallback, useSyncExternalStore } from 'react'

/** Breakpoint móvil de la casa (espejo del sidebar): < 768 px = teléfono. */
export const CONSULTA_MOVIL = '(max-width: 767px)'

/** ¿matchMedia disponible? (falso en jsdom sin stub y en SSR). */
function hayMatchMedia(): boolean {
  return typeof window !== 'undefined' && typeof window.matchMedia === 'function'
}

/** true si la media query coincide AHORA; re-renderiza al cruzar el umbral. */
export function useMediaQuery(consulta: string): boolean {
  const suscribir = useCallback(
    (alCambiar: () => void) => {
      if (!hayMatchMedia()) return () => {}
      const mql = window.matchMedia(consulta)
      mql.addEventListener('change', alCambiar)
      return () => mql.removeEventListener('change', alCambiar)
    },
    [consulta],
  )
  const leer = () => (hayMatchMedia() ? window.matchMedia(consulta).matches : false)
  // getServerSnapshot = desktop por defecto (sin ventana no hay "móvil").
  return useSyncExternalStore(suscribir, leer, () => false)
}

/** ¿Viewport de teléfono (< 768 px)? Reactivo al rotar/redimensionar. */
export function useEsMovil(): boolean {
  return useMediaQuery(CONSULTA_MOVIL)
}
