import { QueryClient } from '@tanstack/react-query'
import { AUTH_CLEARED_EVENT } from './seguridad'

/**
 * Caché única de datos remotos del CRM.
 *
 * Supabase JS >= 2.102 ya reintenta las lecturas PostgREST transitorias. Por
 * eso React Query no vuelve a reintentar: dos capas de retry multiplicarían
 * tráfico y latencia justo cuando el backend está degradado.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: false,
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
    },
    mutations: {
      retry: false,
    },
  },
})

let limpiezaInstalada = false

/** Borra PII y resultados autorizados en cuanto Auth pierde la sesión/rol. */
export function instalarLimpiezaCacheAutenticacion(): () => void {
  if (limpiezaInstalada || typeof window === 'undefined') return () => undefined

  const limpiar = () => queryClient.clear()
  window.addEventListener(AUTH_CLEARED_EVENT, limpiar)
  limpiezaInstalada = true

  return () => {
    window.removeEventListener(AUTH_CLEARED_EVENT, limpiar)
    limpiezaInstalada = false
  }
}
