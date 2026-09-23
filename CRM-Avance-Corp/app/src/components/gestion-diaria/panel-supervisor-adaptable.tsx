import { useCallback, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import { createPortal } from 'react-dom'
import * as Dialog from '@radix-ui/react-dialog'
import { protegerEscapeAnidado } from '@/components/ui/escape-dialogo'

/** El portal conserva SIEMPRE el mismo destino DOM. Mover su contenedor entre
 * región y diálogo mantiene filtros, páginas, scroll e instancias React.
 * Radix conserva la modalidad, capas y foco, también sobre la ficha del lead.
 * Content no debe tener animación de salida: el destino se traslada en el commit. */
export function PanelSupervisorAdaptable({ modal, cerrar, tituloRef, children }: {
  modal: boolean
  cerrar: () => void
  tituloRef: RefObject<HTMLHeadingElement | null>
  children: ReactNode
}) {
  const [destino] = useState(() => {
    const nodo = document.createElement('div')
    nodo.className = 'gd-panel-host'
    return nodo
  })
  const contenido = useRef<HTMLDivElement | null>(null)
  const focoInterno = useRef<HTMLElement | null>(null)
  useLayoutEffect(() => {
    // Guardar al enfocar, antes de que React pueda retirar el alojamiento modal.
    // Leer activeElement después de retirarlo devolvería body en algunos ciclos.
    const recordar = (e: FocusEvent) => { if (e.target instanceof HTMLElement) focoInterno.current = e.target }
    destino.addEventListener('focusin', recordar)
    return () => destino.removeEventListener('focusin', recordar)
  }, [destino])
  const mover = useCallback((nodo: HTMLDivElement) => {
    const activo = document.activeElement
    if (activo instanceof HTMLElement && destino.contains(activo)) focoInterno.current = activo
    nodo.appendChild(destino)
  }, [destino])
  const alojarEnLinea = useCallback((nodo: HTMLDivElement | null) => {
    if (nodo && !modal) mover(nodo)
  }, [modal, mover])
  const alojarEnDialogo = useCallback((nodo: HTMLDivElement | null) => {
    contenido.current = nodo
    if (nodo) mover(nodo)
  }, [mover])
  useLayoutEffect(() => {
    if (!modal && focoInterno.current?.isConnected) {
      focoInterno.current.focus({ preventScroll: true })
    }
  }, [modal])
  return (
    <Dialog.Root open={modal} onOpenChange={(abierto) => { if (!abierto) cerrar() }}>
      <div ref={alojarEnLinea} className="gd-panel-alojamiento" hidden={modal} />
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-primary/25 backdrop-blur-[2px]" />
        <Dialog.Content ref={alojarEnDialogo} className="gd-panel-modal" data-slot="dialog" aria-describedby={undefined}
          onEscapeKeyDown={(e) => protegerEscapeAnidado(e, contenido.current)}
          onInteractOutside={(e) => {
            // Los eventos de React del portal conservan su ascendencia lógica,
            // distinta de Content. El DOM decide si el clic pertenece al panel.
            if (e.target instanceof Node && destino.contains(e.target)) e.preventDefault()
          }}
          onOpenAutoFocus={(e) => {
            e.preventDefault()
            ;(focoInterno.current?.isConnected ? focoInterno.current : tituloRef.current)?.focus({ preventScroll: true })
          }}
          onCloseAutoFocus={(e) => { e.preventDefault() }}>
        </Dialog.Content>
      </Dialog.Portal>
      {createPortal(children, destino)}
    </Dialog.Root>
  )
}
