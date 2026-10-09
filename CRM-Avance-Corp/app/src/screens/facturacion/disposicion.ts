import { useCallback, useLayoutEffect, useRef, useState } from 'react'
import { useEsMovil } from '@/lib/media'

/** La región manda incluso con el menú abierto o con zoom; el móvil es solo el valor inicial. */
export function useDisposicionFacturacion() {
  const esMovil = useEsMovil()
  const contenedorRef = useRef<HTMLDivElement>(null)
  const [estrecha, setEstrecha] = useState<boolean | null>(null)
  useLayoutEffect(() => {
    const nodo = contenedorRef.current
    if (!nodo || typeof ResizeObserver === 'undefined') return
    const medir = () => {
      // Los 8 px son el margen exterior del foco (4 px por lado).
      if (nodo.clientWidth > 0) setEstrecha(nodo.clientWidth - 8 < 730)
    }
    const observador = new ResizeObserver(medir)
    observador.observe(nodo)
    medir()
    return () => observador.disconnect()
  }, [])

  const mallaRef = useCallback((nodo: HTMLDivElement | null) => {
    if (!nodo) return
    const cabecera = nodo.querySelector('thead')
    const numero = nodo.querySelector('thead .facturacion-numero')
    const nombre = nodo.querySelector('thead .facturacion-nombre')
    const total = nodo.querySelector('thead .facturacion-total')
    if (!cabecera || !numero || !nombre || !total) return
    const medir = () => {
      // Medidas reales: cambian con las fuentes, la vista Día, el zoom y el ancho disponible.
      nodo.style.setProperty('--reserva-cabecera', `${cabecera.getBoundingClientRect().height + 4}px`)
      nodo.style.setProperty('--reserva-izquierda', `${numero.getBoundingClientRect().width + nombre.getBoundingClientRect().width}px`)
      nodo.style.setProperty('--reserva-derecha', `${total.getBoundingClientRect().width}px`)
    }
    medir()
    if (typeof ResizeObserver === 'undefined') return
    const observador = new ResizeObserver(medir)
    for (const elemento of [cabecera, numero, nombre, total]) observador.observe(elemento)
    return () => observador.disconnect()
  }, [])

  return { contenedorRef, mallaRef, usarTarjetas: estrecha ?? esMovil }
}
