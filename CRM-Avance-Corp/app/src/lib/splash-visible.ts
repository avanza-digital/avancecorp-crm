import { createContext, useContext } from 'react'

/**
 * true mientras la capa del splash cubre el workspace (`inert` + `aria-hidden`
 * en App): lo que se monta debajo todavía NO lo vio nadie. Quien registre
 * «visitas» u otras huellas de lectura debe esperar a que esto sea false —
 * anotar como vista una pantalla tapada puede CALLAR novedades después.
 *
 * Default false: fuera de App (tests, montajes sueltos) el contenido se asume
 * visible.
 */
export const ContextoSplashVisible = createContext(false)

export function useSplashVisible(): boolean {
  return useContext(ContextoSplashVisible)
}
