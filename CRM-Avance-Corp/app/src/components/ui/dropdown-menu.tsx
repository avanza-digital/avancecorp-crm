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

  /** El disparador real es el botón del consumidor: el primero dentro de la raíz. */
  const enfocarDisparador = () => {
    raiz.current?.querySelector<HTMLElement>('button, [href], [tabindex]:not([tabindex="-1"])')?.focus()
  }

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

  /** Las opciones enfocables del panel, en orden de lectura. */
  const opciones = () =>
    [...(raiz.current?.querySelectorAll<HTMLElement>('[role="menuitem"]:not([disabled])') ?? [])]

  useEffect(() => {
    if (!open) return
    // Al abrir, el foco entra al menú: quien lo anuncia como `menu` promete el
    // patrón del APG, y hasta hoy solo cumplía Escape (revisión de a11y,
    // 20/09/2026). Sin esto, las flechas no hacían nada y el foco se quedaba
    // fuera de lo que el lector de pantalla acababa de anunciar.
    opciones()[0]?.focus()
    const click = (e: MouseEvent) => {
      if (raiz.current && !raiz.current.contains(e.target as Node)) setOpen(false)
    }
    const tecla = (e: KeyboardEvent) => {
      // Escape cierra Y devuelve el foco al disparador: cerrarlo con el foco
      // dentro de un ítem que se desmonta lo mandaba al `body`, y el siguiente
      // TAB reiniciaba la página (hallazgo de Codex, 20/09/2026).
      if (e.key === 'Escape') { setOpen(false); enfocarDisparador(); return }
      // Tab sale del menú, así que el menú se cierra: si no, queda un panel
      // flotante con `aria-expanded="true"` y el foco en otra parte.
      if (e.key === 'Tab') { setOpen(false); return }
      const items = opciones()
      if (items.length === 0) return
      const i = items.indexOf(document.activeElement as HTMLElement)
      const destino = e.key === 'Home' ? items[0]
        : e.key === 'End' ? items[items.length - 1]
          : e.key === 'ArrowDown' ? items[i < 0 ? 0 : (i + 1) % items.length]
            : e.key === 'ArrowUp' ? items[i < 0 ? items.length - 1 : (i - 1 + items.length) % items.length]
              : undefined
      if (destino === undefined) return
      e.preventDefault()
      destino.focus()
    }
    document.addEventListener('mousedown', click)
    document.addEventListener('keydown', tecla)
    return () => {
      document.removeEventListener('mousedown', click)
      document.removeEventListener('keydown', tecla)
    }
  }, [open])

  // El aria Y el click del disparador van en el elemento interactivo real (el
  // botón del consumidor), no en un span envolvente — los lectores de pantalla
  // asocian así el estado expandido al control enfocable, y teclado/AT operan
  // el menú nativamente.
  const disparador = isValidElement(trigger)
    ? cloneElement(trigger as ReactElement<Record<string, unknown>>, {
        'aria-haspopup': 'menu',
        'aria-expanded': open,
        onClick: (e: unknown) => {
          const original = (trigger.props as Record<string, unknown>).onClick
          if (typeof original === 'function') original(e)
          alternar()
        },
      })
    : trigger

  return (
    <div ref={raiz} className={cn('relative inline-flex', className)}>
      <span className="inline-flex">
        {disparador}
      </span>
      {open && (
        <MenuCtx.Provider value={{ cerrar: () => { setOpen(false); enfocarDisparador() } }}>
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
        // 14 px: 13 px quedaba por debajo del piso de lectura que pidió el dueño.
        'flex w-full cursor-pointer items-center gap-2 rounded-md px-2.5 py-2 text-left text-sm font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-3.5 [&_svg]:shrink-0',
        destructive ? 'text-destructive hover:bg-destructive/10' : 'text-foreground hover:bg-muted',
        className,
      )}
    >
      {children}
    </button>
  )
}

export function DropdownSeparator() {
  // Decorativo: <hr> semántico, fuera del árbol de accesibilidad.
  return <hr aria-hidden="true" className="my-1 h-px border-0 bg-border" />
}

export function DropdownLabel({ children }: { children: ReactNode }) {
  return (
    <div className="px-2.5 pb-1 pt-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
      {children}
    </div>
  )
}
