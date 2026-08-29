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

/**
 * "Este aparato PUEDE marcar", que NO es lo mismo que "la pantalla es chica".
 *
 * El criterio es de INTERACCIÓN, no de ancho: `hover: none` + `pointer: coarse`
 * describen el puntero PRIMARIO del dispositivo —el dedo— y solo son ciertos en
 * teléfono y tablet. Una laptop con la ventana a media pantalla, con devtools
 * abiertas o en split-screen sigue siendo `hover: hover` + `pointer: fine`, así
 * que el escritorio conserva intacto su copiar-al-portapapeles. Por eso NO se
 * reutiliza CONSULTA_MOVIL: con un max-width a secas, media laptop del equipo
 * se volvería "celular" y el analista perdería el número copiado.
 *
 * El segundo filtro mira el LADO CORTO del viewport, no el ancho: el ancho
 * cambia al ROTAR y con `max-width` a secas el mismo celular perdía el marcador
 * en horizontal (932×430) mientras un iPad vertical (744×1133) sí recibía un
 * `tel:` muerto — un iPad cumple `hover:none`+`pointer:coarse` pero no tiene
 * radio. Con `(max-width: 500px) or (max-height: 500px)` entran los teléfonos
 * en las dos orientaciones y quedan fuera las tablets.
 *
 * Por qué NO user-agent: el UA miente por diseño (el "modo escritorio" de
 * Chrome Android; iPadOS se anuncia como Macintosh desde iOS 13) y
 * `navigator.userAgentData.mobile` solo existe en Chromium → falso negativo en
 * TODO Safari, o sea en media flota. Si un navegador no entiende estas
 * features la consulta es inválida y `matches` da false: el fallback es
 * escritorio, que es exactamente el comportamiento de siempre.
 */
export const CONSULTA_PUEDE_MARCAR =
  '(hover: none) and (pointer: coarse) and ((max-width: 500px) or (max-height: 500px))'

/** ¿El aparato marca solo (celular)? Reactivo: acoplar un mouse lo cambia. */
export function usePuedeMarcar(): boolean {
  return useMediaQuery(CONSULTA_PUEDE_MARCAR)
}
