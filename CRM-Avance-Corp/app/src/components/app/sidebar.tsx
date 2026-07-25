import { useEffect, useRef, useState, type CSSProperties } from 'react'
import {
  LayoutDashboard, KanbanSquare, Users, CalendarDays, UsersRound, Settings, LogOut, Eye,
  PanelLeftClose, PanelLeftOpen, Wallet, Split,
} from 'lucide-react'
import { can, ROL_LABEL, type Accion } from '@/lib/roles'
import { funcionesLeadsVisibles } from '@/lib/config'
import { useAuth } from '@/lib/auth-context'
import { Avatar } from '@/components/ui/avatar'
import { BrandLockup } from '@/components/app/brand'
import { cn } from '@/lib/utils'
import { escribirHash, esVistaLeads, type Vista } from '@/lib/router'

interface NavItem {
  id: Vista
  label: string
  icon: typeof LayoutDashboard
  cap?: Accion // si se define, solo se muestra con can()
}

const NAV: NavItem[] = [
  { id: 'hoy', label: 'Hoy', icon: LayoutDashboard },
  { id: 'pipeline', label: 'Pipeline', icon: KanbanSquare },
  { id: 'cartera', label: 'Leads', icon: Users },
  { id: 'agenda', label: 'Agenda', icon: CalendarDays },
  // "Cartera" (mi-cartera) reemplaza a Clientes y Contratos, retiradas del todo
  // en Fase 6 (2026-07-21): ya no existen como vistas ni son alcanzables por URL.
  { id: 'mi-cartera', label: 'Mi cartera', icon: Wallet, cap: 'verCartera' },
  // Reparto de la cola global (C1): coordinador y gerencia.
  { id: 'repartir', label: 'Repartir leads', icon: Split, cap: 'repartirCola' },
  { id: 'equipo', label: 'Equipo', icon: UsersRound, cap: 'verEquipo' },
]

// Estado de colapso persistido: se recuerda entre recargas (por navegador).
const LS_COLAPSADO = 'ac-crm-sidebar-colapsado'
function leerColapsado(): boolean {
  try {
    return localStorage.getItem(LS_COLAPSADO) === '1'
  } catch {
    return false
  }
}
function guardarColapsado(v: boolean): void {
  try {
    localStorage.setItem(LS_COLAPSADO, v ? '1' : '0')
  } catch {
    /* almacenamiento no disponible — no pasa nada */
  }
}

const ABRIR_MS = 120 // retardo antes de asomar (un paso rápido no lo dispara)
const CERRAR_MS = 200 // retardo antes de replegar (permite ir al panel sin cortar)
const esPantallaMovil = () =>
  typeof window !== 'undefined' && window.matchMedia('(max-width: 767px)').matches

// Animación del "peek": el panel crece anclando los íconos y los labels entran
// en cascada con un rebote sutil. Se desactiva con prefers-reduced-motion.
const KEYFRAMES = `
@keyframes acPeekLabel { from { opacity: 0; transform: translateX(-10px) } to { opacity: 1; transform: none } }
@media (prefers-reduced-motion: reduce) {
  [data-peek-anim] { transition: none !important; animation: none !important }
}
`
/** Estilo de entrada escalonada para un label del menú al asomar (índice → delay). */
function estiloCascada(indice: number): CSSProperties {
  return {
    animation: 'acPeekLabel 0.34s both',
    animationDelay: `${indice * 22}ms`,
    animationTimingFunction: 'cubic-bezier(.34,1.56,.64,1)',
  }
}

function NavButton({
  item, active, onClick, expandido, animar, indice,
}: {
  item: { label: string; icon: typeof LayoutDashboard }
  active: boolean
  onClick: () => void
  expandido: boolean
  animar: boolean
  indice: number
}) {
  return (
    <button
      onClick={onClick}
      title={expandido ? undefined : item.label}
      aria-label={expandido ? undefined : item.label}
      className={cn(
        'ac-nav-item group relative flex w-full items-center rounded-lg py-2 text-sm font-medium cursor-pointer',
        expandido ? 'gap-3 px-3' : 'justify-center px-2',
        active
          ? 'is-active bg-sidebar-primary text-sidebar-primary-foreground shadow-[0_8px_20px_-10px_rgba(37,99,235,0.9)]'
          : 'text-sidebar-foreground hover:bg-white/[0.06] hover:text-white',
      )}
    >
      {active && expandido && (
        <span className="absolute -left-3 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-white/90" />
      )}
      <item.icon className={cn('size-[18px] shrink-0', active ? 'text-white' : 'text-sidebar-foreground/80 group-hover:text-white')} />
      {expandido && (
        <span className="truncate" data-peek-anim={animar ? '' : undefined} style={animar ? estiloCascada(indice) : undefined}>
          {item.label}
        </span>
      )}
    </button>
  )
}

// Navega escribiendo el hash (#/vista): App.tsx lo sincroniza con el estado.
// El menú se puede FIJAR colapsado (botón) a un riel de íconos; estando
// colapsado, al pasar el mouse ASOMA el menú completo (overlay animado) y se
// repliega solo al salir. El <main> ocupa el ancho del riel en TODO el CRM.
export function Sidebar({ vista }: { vista: Vista }) {
  const { yo, salir } = useAuth()
  const rol = yo?.rol
  const [colapsado, setColapsado] = useState(() => esPantallaMovil() || leerColapsado())
  const [asomando, setAsomando] = useState(false)
  const abrirRef = useRef<number | undefined>(undefined)
  const cerrarRef = useRef<number | undefined>(undefined)

  // Muestra completa = fijado abierto, o colapsado pero asomando por hover.
  const expandido = !colapsado || asomando
  // La cascada solo corre en el asomo real (no al fijar ni al cargar).
  const animar = colapsado && asomando

  const alternar = () =>
    setColapsado((v) => {
      const siguiente = !v
      if (!esPantallaMovil()) guardarColapsado(siguiente)
      if (!siguiente) setAsomando(false) // al fijar abierto, no queda "asomando"
      return siguiente
    })

  const navegar = (destino: Vista) => {
    escribirHash(destino)
    if (esPantallaMovil()) {
      setColapsado(true)
      setAsomando(false)
    }
  }

  const entrar = () => {
    if (!colapsado) return
    window.clearTimeout(cerrarRef.current)
    abrirRef.current = window.setTimeout(() => setAsomando(true), ABRIR_MS)
  }
  const salirHover = () => {
    window.clearTimeout(abrirRef.current)
    cerrarRef.current = window.setTimeout(() => setAsomando(false), CERRAR_MS)
  }
  useEffect(
    () => () => {
      window.clearTimeout(abrirRef.current)
      window.clearTimeout(cerrarRef.current)
    },
    [],
  )

  const leadsVisibles = funcionesLeadsVisibles(yo?.demo === true, yo?.rol, yo?.id)
  const items = NAV.filter((n) => (leadsVisibles || !esVistaLeads(n.id)) && (!n.cap || can(rol, n.cap)))
    // Rótulo por rol de la pantalla fusionada: el vendedor ve "Mi cartera"; quien supervisa, "Cartera".
    .map((n) => (n.id === 'mi-cartera' && can(rol, 'verEquipo') ? { ...n, label: 'Cartera' } : n))

  return (
    <aside
      className={cn('relative z-30 h-full w-16 shrink-0', !colapsado && 'md:w-60')}
      data-peek-anim=""
      style={{ transition: `width ${ABRIR_MS}ms var(--ease-out-expo)` }}
    >
      <style>{KEYFRAMES}</style>
      {/* Panel visual: absoluto, así al asomar FLOTA sobre el contenido sin moverlo.
          El hover vive aquí (div): mover los listeners al <aside> dispara el aviso
          a11y de "elemento no interactivo con eventos de mouse". */}
      <div
        data-peek-anim=""
        onMouseEnter={entrar}
        onMouseLeave={salirHover}
        className={cn(
          'absolute inset-y-0 left-0 flex flex-col border-r border-sidebar-border text-sidebar-foreground',
          expandido ? 'w-60' : 'w-16',
          asomando && 'shadow-[var(--shadow-pop)]',
        )}
        style={{
          background: 'linear-gradient(180deg, var(--sidebar) 0%, var(--sidebar-2) 100%)',
          transition: 'width 240ms var(--ease-out-expo)',
        }}
      >
        {/* Marca + botón ocultar/fijar */}
        <div className={cn('flex h-16 items-center border-b border-sidebar-border', expandido ? 'justify-between px-4' : 'justify-center px-2')}>
          {expandido && (
            <div data-peek-anim={animar ? '' : undefined} style={animar ? estiloCascada(0) : undefined}>
              <BrandLockup tone="dark" size={38} />
            </div>
          )}
          <button
            onClick={alternar}
            title={colapsado ? 'Fijar menú abierto' : 'Ocultar menú'}
            aria-label={colapsado ? 'Fijar menú abierto' : 'Ocultar menú'}
            aria-expanded={!colapsado}
            className="rounded-md p-1.5 text-sidebar-foreground/70 transition-colors hover:bg-white/10 hover:text-white cursor-pointer"
          >
            {colapsado ? <PanelLeftOpen className="size-5" /> : <PanelLeftClose className="size-5" />}
          </button>
        </div>

        {/* Nav por capacidad (lo que can() oculta, la RLS también lo niega) */}
        <nav className={cn('ac-scroll flex-1 space-y-1 overflow-y-auto pt-4', expandido ? 'px-3' : 'px-2')}>
          {expandido && (
            <p
              className="px-2 pb-1.5 text-[10px] font-bold uppercase tracking-[0.14em] text-sidebar-foreground/45"
              data-peek-anim={animar ? '' : undefined}
              style={animar ? estiloCascada(1) : undefined}
            >
              Principal
            </p>
          )}
          {items.map((n, i) => (
            <NavButton key={n.id} item={n} active={vista === n.id} onClick={() => navegar(n.id)} expandido={expandido} animar={animar} indice={i + 2} />
          ))}

          {can(rol, 'verConfiguracion') && (
            <>
              {expandido && (
                <p
                  className="px-2 pb-1.5 pt-5 text-[10px] font-bold uppercase tracking-[0.14em] text-sidebar-foreground/45"
                  data-peek-anim={animar ? '' : undefined}
                  style={animar ? estiloCascada(items.length + 2) : undefined}
                >
                  Administración
                </p>
              )}
              <NavButton
                item={{ label: 'Configuración', icon: Settings }}
                active={vista === 'config'}
                onClick={() => navegar('config')}
                expandido={expandido}
                animar={animar}
                indice={items.length + 3}
              />
            </>
          )}
        </nav>

        {/* Modo auditoría del directorio (se oculta el texto en el riel) */}
        {can(rol, 'soloLecturaTotal') && expandido && (
          <div className="mx-3 mb-3 flex items-center gap-2 rounded-lg bg-white/[0.06] px-3 py-2 text-[11px] font-medium text-sidebar-foreground/85 ring-1 ring-white/10">
            <Eye className="size-3.5 shrink-0 text-accent" />
            Modo auditoría · solo lectura
          </div>
        )}

        {/* Usuario */}
        <div
          className={cn(
            'border-t border-sidebar-border py-3',
            expandido ? 'flex items-center gap-3 px-4' : 'flex flex-col items-center gap-2 px-2',
          )}
        >
          <Avatar nombre={yo?.nombre_completo} color="#7aa6ff" className="size-9" />
          {expandido && (
            <div className="min-w-0 flex-1 leading-tight" data-peek-anim={animar ? '' : undefined} style={animar ? estiloCascada(items.length + 4) : undefined}>
              <p className="truncate text-[13px] font-semibold text-white">{yo?.nombre_completo ?? '—'}</p>
              <p className="text-[10px] uppercase tracking-wider text-sidebar-foreground/60">
                {rol ? ROL_LABEL[rol] : ''}{yo?.demo ? ' · demo' : ''}
              </p>
            </div>
          )}
          <button
            onClick={() => void salir()}
            title="Cerrar sesión"
            aria-label="Cerrar sesión"
            className="rounded-md p-1.5 text-sidebar-foreground/70 transition-colors hover:bg-white/10 hover:text-white cursor-pointer"
          >
            <LogOut className="size-4" />
          </button>
        </div>
      </div>
    </aside>
  )
}
