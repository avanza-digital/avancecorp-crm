// Drawer lateral derecho (F1b) — a mano, sin deps. Overlay con blur suave,
// cierra con Esc y click fuera, entrada animada, cuerpo con scroll interno.
// Con varios modales apilados (p. ej. Dialog encima del Sheet), Esc cierra
// SOLO el de más arriba (se detecta por orden de [aria-modal] en el DOM).
import { useEffect, useRef, type HTMLAttributes, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'
import { esModalSuperior } from '@/lib/modal-stack'

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
  /** aria-label del dialog (o usa aria-labelledby vía SheetTitle id propio). */
  ariaLabel?: string
  /** Clases extra para el panel (p. ej. ancho distinto). */
  className?: string
}

export function Sheet({ open, onClose, children, ariaLabel, className }: SheetProps) {
  const panel = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    // Al cerrar, el foco vuelve a donde estaba (usuario de teclado no cae a <body>).
    const previo = document.activeElement as HTMLElement | null
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && esModalSuperior(panel.current)) onClose()
    }
    document.addEventListener('keydown', tecla)
    panel.current?.focus()
    return () => {
      document.removeEventListener('keydown', tecla)
      previo?.focus?.()
    }
  }, [open, onClose])

  if (!open) return null
  return createPortal(
    <div className="fixed inset-0 z-50">
      <style>{KEYFRAMES}</style>
      <div
        data-slot="sheet-overlay"
        aria-hidden
        onClick={onClose}
        className="absolute inset-0 bg-primary/25 backdrop-blur-[2px]"
        style={{ animation: 'ac-sheet-overlay 0.25s ease both' }}
      />
      <div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        tabIndex={-1}
        data-slot="sheet"
        className={cn(
          'absolute inset-y-0 right-0 flex w-[460px] max-w-[92vw] flex-col border-l border-border bg-card text-card-foreground shadow-[var(--shadow-pop)] outline-none',
          className,
        )}
        style={{ animation: 'ac-sheet-panel 0.35s var(--ease-out-expo) both' }}
      >
        {children}
      </div>
    </div>,
    document.body,
  )
}

export function SheetHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('flex flex-col gap-1 border-b border-border px-5 py-4', className)} {...props} />
}

export function SheetTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn('text-[15px] font-bold tracking-tight', className)} {...props} />
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
