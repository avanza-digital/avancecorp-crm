import { QueryClient } from '@tanstack/react-query'
import { AUTH_CLEARED_EVENT } from './seguridad'

/**
 * Caché única de datos remotos del CRM.
 *
 * Supabase JS >= 2.102 ya reintenta las lecturas PostgREST transitorias. Por
 * eso React Query no vuelve a reintentar: dos capas de retry multiplicarían
 * tráfico y latencia justo cuando el backend está degradado.
 *
 * `networkMode: 'offlineFirst'` (el default es 'online') — POR QUÉ:
 * en 'online' TanStack ni siquiera LANZA la petición si el navegador se declara
 * offline: la query queda en `status: 'pending'` con `fetchStatus: 'paused'`
 * PARA SIEMPRE. Como las pantallas bifurcan por `isPending`, eso pintaba un
 * skeleton eterno en «Mi cartera» y en los diálogos de cliente/contrato: la UI
 * decía "cargando" cuando en realidad nadie estaba cargando nada. Con
 * 'offlineFirst' la petición SALE igual (el flag del navegador es orientativo:
 * hay redes que reportan online sin salida a internet, y captivas al revés) y,
 * si falla, la query cae en `error` — que la pantalla sí sabe contar con un
 * estado honesto y un botón de reintentar. `refetchOnReconnect` sigue
 * recuperando solo en cuanto vuelve la red.
 *
 * Lo mismo en mutaciones: una escritura PAUSADA en silencio le hace creer al
 * asesor que guardó. Preferimos que falle, avise y revierta.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: false,
      networkMode: 'offlineFirst',
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
    },
    mutations: {
      retry: false,
      networkMode: 'offlineFirst',
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
