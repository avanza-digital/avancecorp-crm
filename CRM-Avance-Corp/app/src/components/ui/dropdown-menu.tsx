// Popover controlado simple (F1b) — trigger + items; click fuera y Esc
// cierran; elegir un ítem también cierra. Sin deps, sin portal (se posiciona
// relativo al trigger).
import {
  cloneElement,
  createContext,
  isValidElement,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactElement,
  type ReactNode,
} from 'react'
import { cn } from '@/lib/utils'

const MenuCtx = createContext<{ cerrar: () => void } | null>(null)

/** Alto estimado del panel para decidir si se abre hacia arriba. */
const ALTO_PANEL = 240

/** Ancestro que puede recortar el panel (overflow ≠ visible), p. ej. el carril del kanban. */
function contenedorRecorte(el: HTMLElement | null): HTMLElement | null {
  let n = el?.parentElement ?? null
  while (n && n !== document.body) {
    const s = getComputedStyle(n)
    if (/(auto|scroll|hidden)/.test(`${s.overflowX} ${s.overflowY}`)) return n
    n = n.parentElement
  }
  return null
}

interface DropdownMenuProps {
  /** Lo que se renderiza como disparador (un Button, un icono, etc.). */
  trigger: ReactNode
  children: ReactNode
  /** Alineación del panel respecto al trigger. */
  align?: 'start' | 'end'
  /** Clases del contenedor (relative inline-flex). */
  className?: string
  /** Clases extra del panel del menú. */
  menuClassName?: string
  /**
   * Avisa cuando el menú abre/cierra. Necesario si el trigger vive dentro de un
   * ancestro con stacking context propio (p. ej. Card con ac-lift/will-change):
   * el consumidor debe subir el z-index de ese ancestro mientras el menú está
   * abierto, o el panel queda pintado DEBAJO de los hermanos siguientes.
   */
  onOpenChange?: (open: boolean) => void
}

export function DropdownMenu({
  trigger,
  children,
  align = 'end',
  className,
  menuClassName,
  onOpenChange,
}: DropdownMenuProps) {
  const [open, setOpen] = useState(false)
  const [arriba, setArriba] = useState(false)
  const raiz = useRef<HTMLDivElement>(null)

  useEffect(() => {
    onOpenChange?.(open)
  }, [open, onOpenChange])

  const alternar = () => {
    if (!open && raiz.current) {
      // Si el trigger está al fondo de su contenedor de scroll (o del viewport),
      // el menú abre hacia arriba para no quedar recortado.
      const r = raiz.current.getBoundingClientRect()
      const cont = contenedorRecorte(raiz.current)
      const limite = cont
        ? Math.min(cont.getBoundingClientRect().bottom, window.innerHeight)
        : window.innerHeight
      setArriba(limite - r.bottom < ALTO_PANEL)
    }
    setOpen((v) => !v)
  }

  useEffect(() => {
    if (!open) return
    const click = (e: MouseEvent) => {
      if (raiz.current && !raiz.current.contains(e.target as Node)) setOpen(false)
    }
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', click)
    document.addEventListener('keydown', tecla)
    return () => {
      document.removeEventListener('mousedown', click)
      document.removeEventListener('keydown', tecla)
    }
  }, [open])

  // El aria del disparador va en el elemento interactivo real (el botón del
  // consumidor), no en el span envolvente — los lectores de pantalla asocian
  // así el estado expandido al control enfocable.
  const disparador = isValidElement(trigger)
    ? cloneElement(trigger as ReactElement<Record<string, unknown>>, {
        'aria-haspopup': 'menu',
        'aria-expanded': open,
      })
    : trigger

  return (
    <div ref={raiz} className={cn('relative inline-flex', className)}>
      <span className="inline-flex" onClick={alternar}>
        {disparador}
      </span>
      {open && (
        <MenuCtx.Provider value={{ cerrar: () => setOpen(false) }}>
          <div
            role="menu"
            data-slot="dropdown-menu"
            className={cn(
              'ac-pop absolute z-50 min-w-44 rounded-lg border border-border bg-card p-1 shadow-[var(--shadow-pop)]',
              arriba ? 'bottom-full mb-1.5' : 'top-full mt-1.5',
              align === 'end' ? 'right-0' : 'left-0',
              menuClassName,
            )}
          >
            {children}
          </div>
        </MenuCtx.Provider>
      )}
    </div>
  )
}

interface DropdownItemProps {
  children: ReactNode
  /** Acción al elegir el ítem (el menú se cierra solo después). */
  onSelect?: () => void
  disabled?: boolean
  /** Ítem peligroso (rojo). */
  destructive?: boolean
  className?: string
}

export function DropdownItem({ children, onSelect, disabled, destructive, className }: DropdownItemProps) {
  const ctx = useContext(MenuCtx)
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      onClick={() => {
        onSelect?.()
        ctx?.cerrar()
      }}
      className={cn(
        'flex w-full cursor-pointer items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-3.5 [&_svg]:shrink-0',
        destructive ? 'text-destructive hover:bg-destructive/10' : 'text-foreground hover:bg-muted',
        className,
      )}
    >
      {children}
    </button>
  )
}

export function DropdownSeparator() {
  return <div role="separator" className="my-1 h-px bg-border" />
}

export function DropdownLabel({ children }: { children: ReactNode }) {
  return (
    <div className="px-2.5 pb-1 pt-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
      {children}
    </div>
  )
}
