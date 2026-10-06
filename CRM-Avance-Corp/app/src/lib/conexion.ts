import { useSyncExternalStore } from 'react'

function suscribir(cambiar: () => void) {
  window.addEventListener('online', cambiar)
  window.addEventListener('offline', cambiar)
  return () => {
    window.removeEventListener('online', cambiar)
    window.removeEventListener('offline', cambiar)
  }
}
const leer = () => typeof navigator === 'undefined' || navigator.onLine !== false
/** Señal del navegador; nunca se usa para bloquear una petición. */
export function useEstaEnLinea() {
  return useSyncExternalStore(suscribir, leer, () => true)
}
