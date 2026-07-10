// Modal centrado (F1b) — a mano, sin deps. Mismas reglas que el Sheet:
// overlay con blur, Esc y click fuera cierran, entrada animada, aria básico.
// Puede montarse ENCIMA de un Sheet: Esc cierra solo el modal de más arriba.
import { useEffect, useRef, type HTMLAttributes, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'
import { esModalSuperior } from '@/lib/modal-stack'

const KEYFRAMES = `
@keyframes ac-dialog-overlay { from { opacity: 0 } to { opacity: 1 } }
@keyframes ac-dialog-panel { from { opacity: 0; transform: translateY(10px) scale(0.96) } to { opacity: 1; transform: none } }
@media (prefers-reduced-motion: reduce) {
  [data-slot='dialog'], [data-slot='dialog-overlay'] { animation: none !important }
}
`

interface DialogProps {
  open: boolean
  onClose: () => void
  children: ReactNode
  ariaLabel?: string
  /** Clases extra para el panel (p. ej. ancho distinto). */
  className?: string
}

export function Dialog({ open, onClose, children, ariaLabel, className }: DialogProps) {
  const panel = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    // Al cerrar, el foco vuelve a donde estaba (p. ej. al Sheet de abajo).
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
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <style>{KEYFRAMES}</style>
      <div
        data-slot="dialog-overlay"
        aria-hidden
        onClick={onClose}
        className="absolute inset-0 bg-primary/25 backdrop-blur-[2px]"
        style={{ animation: 'ac-dialog-overlay 0.2s ease both' }}
      />
      <div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        tabIndex={-1}
        data-slot="dialog"
        className={cn(
          'relative flex max-h-[85vh] w-[520px] max-w-[92vw] flex-col rounded-xl border border-border bg-card text-card-foreground shadow-[var(--shadow-pop)] outline-none',
          className,
        )}
        style={{ animation: 'ac-dialog-panel 0.3s var(--ease-out-expo) both' }}
      >
        {children}
      </div>
    </div>,
    document.body,
  )
}

export function DialogHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('flex flex-col gap-1 border-b border-border px-5 py-4', className)} {...props} />
}

export function DialogTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn('text-[15px] font-bold tracking-tight', className)} {...props} />
}

export function DialogDescription({ className, ...props }: HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn('text-xs text-muted-foreground', className)} {...props} />
}

/** Cuerpo con scroll interno si el contenido crece (`ac-scroll`). */
export function DialogBody({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('ac-scroll flex-1 overflow-y-auto px-5 py-4', className)} {...props} />
}

export function DialogFooter({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('flex items-center justify-end gap-2 border-t border-border px-5 py-3', className)} {...props} />
}
