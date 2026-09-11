// Modal centrado sobre Radix Dialog (accesibilidad completa: focus-trap real,
// fondo inerte, scroll lock, Esc por capas — con modales apilados cierra SOLO
// el de más arriba — y retorno de foco al cerrar). El aspecto es el mismo de
// siempre: mismas clases, mismos keyframes. API sin cambios: open/onClose.
import { useRef, type HTMLAttributes, type ReactNode } from 'react'
import * as RadixDialog from '@radix-ui/react-dialog'
import { cn } from '@/lib/utils'

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
  // Estos modales se controlan desde acciones externas, sin Radix.Trigger.
  // Una resolución puede retirar la acción: conservamos también su ficha.
  const origenFoco = useRef<HTMLElement | null>(null)
  const ambitoFoco = useRef<HTMLElement | null>(null)
  return (
    <RadixDialog.Root open={open} onOpenChange={(sigueAbierto) => { if (!sigueAbierto) onClose() }}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay
          data-slot="dialog-overlay"
          className="fixed inset-0 z-50 bg-primary/25 backdrop-blur-[2px]"
          style={{ animation: 'ac-dialog-overlay 0.2s ease both' }}
        />
        {/* Contenedor de layout no interactivo: el click en el padding cae al overlay. */}
        <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center p-4">
          <RadixDialog.Content
            onOpenAutoFocus={() => {
              const activo = document.activeElement
              const origen = activo instanceof HTMLElement && activo !== document.body ? activo : null
              origenFoco.current = origen
              ambitoFoco.current = origen?.closest<HTMLElement>('[role="dialog"]') ?? null
            }}
            onCloseAutoFocus={(evento) => {
              const origen = origenFoco.current
              const ambito = ambitoFoco.current
              origenFoco.current = null
              ambitoFoco.current = null
              if (!origen?.isConnected && !ambito?.isConnected) return
              evento.preventDefault()
              // Esperar a que Radix retire la trampa del diálogo que se cierra.
              requestAnimationFrame(() => {
                const destino = origen?.isConnected && !origen.matches(':disabled, [aria-disabled="true"]')
                  ? origen : ambito?.isConnected ? ambito : null
                destino?.focus({ preventScroll: true })
                // Un nodo conectado también puede quedar oculto o inerte.
                if (document.activeElement !== destino && ambito?.isConnected) ambito.focus({ preventScroll: true })
              })
            }}
            aria-label={ariaLabel}
            aria-describedby={undefined}
            data-slot="dialog"
            className={cn(
              'pointer-events-auto relative flex max-h-[85vh] w-[520px] max-w-[92vw] flex-col rounded-xl border border-border bg-card text-card-foreground shadow-[var(--shadow-pop)] outline-none',
              className,
            )}
            style={{ animation: 'ac-dialog-panel 0.3s var(--ease-out-expo) both' }}
          >
            <style>{KEYFRAMES}</style>
            {children}
          </RadixDialog.Content>
        </div>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  )
}

export function DialogHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('flex flex-col gap-1 border-b border-border px-5 py-4', className)} {...props} />
}

/** Título accesible: Radix lo enlaza como aria-labelledby del dialog. */
export function DialogTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return (
    <RadixDialog.Title asChild>
      <h2 className={cn('text-[15px] font-bold tracking-tight', className)} {...props} />
    </RadixDialog.Title>
  )
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
