import { useLayoutEffect, useState, type RefObject } from 'react'

/** Medir el área real respeta el espacio que ocupa el menú, incluso al cambiarlo. */
export function usePanelGerencia(pantalla: RefObject<HTMLElement | null>) {
  const [estrecho, setEstrecho] = useState(false)
  useLayoutEffect(() => {
    const nodo = pantalla.current
    if (!nodo || typeof ResizeObserver === 'undefined') return
    const medir = () => setEstrecho(nodo.clientWidth < 1236)
    const observer = new ResizeObserver(medir)
    observer.observe(nodo)
    medir()
    return () => observer.disconnect()
  }, [pantalla])
  return { estrecho }
}
