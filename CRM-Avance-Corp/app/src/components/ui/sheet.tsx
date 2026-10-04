// Drawer lateral derecho sobre Radix Dialog (accesibilidad completa:
// focus-trap real, fondo inerte, scroll lock, Esc por capas — un Dialog
// montado encima cierra primero — y retorno de foco al cerrar). El aspecto es
// el mismo de siempre: mismas clases, mismos keyframes. API sin cambios.
import { useRef, type HTMLAttributes, type ReactNode } from 'react'
import * as RadixDialog from '@radix-ui/react-dialog'
import { cn } from '@/lib/utils'
import { cerrarEscapeAnidado, protegerEscapeAnidado } from './escape-dialogo'

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
  /** Dónde empieza el foco al abrir, en vez del primer control (p. ej. el primer resultado de un formulario). */
  focoInicial?: () => HTMLElement | null
  /**
   * Destino del foco al cerrar cuando el origen YA NO existe y tampoco su gemela (p. ej. la fila salió de la lista
   * al registrar algo): el vecino o la propia lista. Sin él, el foco caería en <body> (WCAG 2.4.3).
   */
  focoRespaldo?: () => HTMLElement | null
}

/**
 * La «gemela» de un origen que ya no existe: el elemento de la página que
 * declara su misma `data-foco-clave`. Se compara el atributo (sin selector por
 * valor: la clave lleva ids y no hay que escaparla).
 */
function gemelaDeFoco(clave: string): HTMLElement | null {
  for (const candidata of document.querySelectorAll<HTMLElement>('[data-foco-clave]')) {
    if (candidata.getAttribute('data-foco-clave') === clave) return candidata
  }
  return null
}

export function Sheet({ open, onClose, children, ariaLabel, className, modal = true, focoInicial, focoRespaldo }: SheetProps) {
  // Radix solo restaura el foco automáticamente cuando conoce un Dialog.Trigger.
  // Los drawers del CRM se abren desde filas y acciones globales, así que no
  // tienen Trigger declarativo: capturamos el origen justo antes del autofocus
  // y lo recuperamos al cerrar si el nodo sigue en la página.
  const origenFoco = useRef<HTMLElement | null>(null)
  // Clave ESTABLE del origen (`data-foco-clave`, suya o de quien lo contiene).
  // El nodo puede desaparecer con la ficha abierta —en el Pipeline, registrar
  // un intento saca la tarjeta de «Nuevo» y la pinta en «Gestionado»: mismo
  // lead, otro nodo— y entonces el foco se devuelve a la gemela. Solo actúa si
  // el origen ya no está conectado Y había clave: lo demás, como siempre.
  const claveFoco = useRef<string | null>(null)
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
          onEscapeKeyDown={(evento) => protegerEscapeAnidado(evento, contenido.current)}
          onKeyDown={(evento) => cerrarEscapeAnidado(evento, onClose)}
          onOpenAutoFocus={(evento) => {
            const activo = document.activeElement
            origenFoco.current = activo instanceof HTMLElement ? activo : null
            claveFoco.current = origenFoco.current?.closest('[data-foco-clave]')?.getAttribute('data-foco-clave') ?? null
            const inicial = focoInicial?.()
            if (inicial) {
              evento.preventDefault()
              inicial.focus()
            }
          }}
          onCloseAutoFocus={(evento) => {
            const destino = origenFoco.current
            const clave = claveFoco.current
            origenFoco.current = null
            claveFoco.current = null
            if (!modal) {
              evento.preventDefault()
              // Si el usuario ya pasó a un filtro u otro panel, conserva ese
              // foco. El inspector no tiene focus trap ni necesita diferirlo.
              if (document.activeElement === document.body || contenido.current?.contains(document.activeElement)) {
                if (destino?.isConnected) destino.focus()
                else if (clave != null) gemelaDeFoco(clave)?.focus()
              }
              return
            }
            if (!destino?.isConnected) {
              // El origen se desmontó con la ficha abierta: a su gemela, si la
              // hay; si no, al respaldo que diga quien abrió la ficha. Sin
              // ninguno de los dos no se inventa destino (como antes).
              const buscar = (): HTMLElement | null => (clave != null ? gemelaDeFoco(clave) : null) ?? focoRespaldo?.() ?? null
              if (buscar() == null) return
              evento.preventDefault()
              // Se vuelve a buscar dentro del cuadro: entre el cierre y el
              // siguiente pintado la lista puede haberse vuelto a renderizar.
              requestAnimationFrame(() => buscar()?.focus())
              return
            }
            evento.preventDefault()
            requestAnimationFrame(() => destino.focus())
          }}
          // Un clic en un toast (p. ej. «Deshacer» del resultado de llamada) no
          // es «fuera»: no cierra la ficha. Los toasts viven en un portal ajeno.
          onInteractOutside={(evento) => {
            if (!modal || (evento.target instanceof Element && evento.target.closest('[data-sonner-toaster]'))) evento.preventDefault()
          }}
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
