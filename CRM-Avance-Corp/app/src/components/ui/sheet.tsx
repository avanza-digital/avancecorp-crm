// Drawer lateral derecho sobre Radix Dialog (accesibilidad completa:
// focus-trap real, fondo inerte, scroll lock, Esc por capas — un Dialog
// montado encima cierra primero — y retorno de foco al cerrar). El aspecto es
// el mismo de siempre: mismas clases, mismos keyframes. API sin cambios.
import { useRef, type HTMLAttributes, type ReactNode } from 'react'
import * as RadixDialog from '@radix-ui/react-dialog'
import { cn } from '@/lib/utils'

const KEYFRAMES = `
@keyframes ac-sheet-overlay { from { opacity: 0 } to { opacity: 1 } }
@keyframes ac-sheet-panel { from { opacity: 0; transform: translateX(48px) } to { opacity: 1; transform: none } }
@media (prefers-reduced-motion: reduce) {
  [data-slot='sheet'], [data-slot='sheet-overlay'] { animation: none !important }
}
`

interface SheetProps {
  open: boolean
  onClose: () => void
  children: ReactNode
  /** aria-label del dialog (SheetTitle también queda enlazado como labelledby). */
  ariaLabel?: string
  /** Clases extra para el panel (p. ej. ancho distinto). */
  className?: string
  /** Un inspector no modal permite seguir consultando la pantalla de fondo. */
  modal?: boolean
}

export function Sheet({ open, onClose, children, ariaLabel, className, modal = true }: SheetProps) {
  // Radix solo restaura el foco automáticamente cuando conoce un Dialog.Trigger.
  // Los drawers del CRM se abren desde filas y acciones globales, así que no
  // tienen Trigger declarativo: capturamos el origen justo antes del autofocus
  // y lo recuperamos al cerrar si el nodo sigue en la página.
  const origenFoco = useRef<HTMLElement | null>(null)
  const contenido = useRef<HTMLDivElement | null>(null)
  return (
    <RadixDialog.Root open={open} modal={modal} onOpenChange={(sigueAbierto) => { if (!sigueAbierto) onClose() }}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay
          data-slot="sheet-overlay"
          className="fixed inset-0 z-50 bg-primary/25 backdrop-blur-[2px]"
          style={{ animation: 'ac-sheet-overlay 0.25s ease both' }}
        />
        <RadixDialog.Content
          ref={contenido}
          onOpenAutoFocus={() => {
            const activo = document.activeElement
            origenFoco.current = activo instanceof HTMLElement ? activo : null
          }}
          onCloseAutoFocus={(evento) => {
            const destino = origenFoco.current
            origenFoco.current = null
            if (!modal) {
              evento.preventDefault()
              // Si el usuario ya pasó a un filtro u otro panel, conserva ese
              // foco. El inspector no tiene focus trap ni necesita diferirlo.
              if (document.activeElement === document.body || contenido.current?.contains(document.activeElement)) {
                if (destino?.isConnected) destino.focus()
              }
              return
            }
            if (!destino?.isConnected) return
            evento.preventDefault()
            requestAnimationFrame(() => destino.focus())
          }}
          onInteractOutside={(evento) => { if (!modal) evento.preventDefault() }}
          aria-label={ariaLabel}
          aria-describedby={undefined}
          data-slot="sheet"
          className={cn(
            'fixed inset-y-0 right-0 z-50 flex w-[460px] max-w-[92vw] flex-col border-l border-border bg-card text-card-foreground shadow-[var(--shadow-pop)] outline-none',
            className,
          )}
          style={{ animation: 'ac-sheet-panel 0.35s var(--ease-out-expo) both' }}
        >
          <style>{KEYFRAMES}</style>
          {children}
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  )
}

export function SheetHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('flex flex-col gap-1 border-b border-border px-5 py-4', className)} {...props} />
}

/** Título accesible: Radix lo enlaza como aria-labelledby del dialog. */
export function SheetTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return (
    <RadixDialog.Title asChild>
      <h2 className={cn('text-[15px] font-bold tracking-tight', className)} {...props} />
    </RadixDialog.Title>
  )
}

export function SheetDescription({ className, ...props }: HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn('text-xs text-muted-foreground', className)} {...props} />
}

/** Cuerpo con scroll interno (riel discreto `ac-scroll`). */
export function SheetBody({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('ac-scroll flex-1 overflow-y-auto px-5 py-4', className)} {...props} />
}

export function SheetFooter({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('flex items-center gap-2 border-t border-border px-5 py-3', className)} {...props} />
}
