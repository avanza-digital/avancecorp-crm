import {
  LayoutDashboard, KanbanSquare, Users, Users2, FileText, CalendarDays, UsersRound, Settings, LogOut, Eye,
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
  { id: 'cartera', label: 'Cartera', icon: Users },
  { id: 'agenda', label: 'Agenda', icon: CalendarDays },
  { id: 'clientes', label: 'Clientes', icon: Users2 },
  { id: 'contratos', label: 'Contratos', icon: FileText },
  { id: 'equipo', label: 'Equipo', icon: UsersRound, cap: 'verEquipo' },
]

function NavButton({
  item, active, onClick,
}: { item: { label: string; icon: typeof LayoutDashboard }; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'ac-nav-item group relative flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium cursor-pointer',
        active
          ? 'is-active bg-sidebar-primary text-sidebar-primary-foreground shadow-[0_8px_20px_-10px_rgba(37,99,235,0.9)]'
          : 'text-sidebar-foreground hover:bg-white/[0.06] hover:text-white',
      )}
    >
      {active && (
        <span className="absolute -left-3 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-white/90" />
      )}
      <item.icon className={cn('size-[18px] shrink-0', active ? 'text-white' : 'text-sidebar-foreground/80 group-hover:text-white')} />
      {item.label}
    </button>
  )
}

// Navega escribiendo el hash (#/vista): App.tsx lo sincroniza con el estado,
// así back/forward y recargar funcionan igual que un click en el menú.
export function Sidebar({ vista }: { vista: Vista }) {
  const { yo, salir } = useAuth()
  const rol = yo?.rol
  // Gate de leads (decisión de Miguel 2026-07-16): las vistas de leads solo se
  // ofrecen en demo o cuando estén aprobadas. Espejo del guard de App.tsx.
  const leadsVisibles = funcionesLeadsVisibles(yo?.demo === true)

  return (
    <aside
      className="flex h-full w-60 shrink-0 flex-col border-r border-sidebar-border text-sidebar-foreground"
      style={{ background: 'linear-gradient(180deg, var(--sidebar) 0%, var(--sidebar-2) 100%)' }}
    >
      {/* Marca oficial */}
      <div className="flex h-16 items-center border-b border-sidebar-border px-4">
        <BrandLockup tone="dark" size={38} />
      </div>

      {/* Nav por capacidad (lo que can() oculta, la RLS también lo niega) */}
      <nav className="ac-scroll flex-1 space-y-1 overflow-y-auto px-3 pt-4">
        <p className="px-2 pb-1.5 text-[10px] font-bold uppercase tracking-[0.14em] text-sidebar-foreground/45">
          Principal
        </p>
        {NAV.filter((n) => (leadsVisibles || !esVistaLeads(n.id)) && (!n.cap || can(rol, n.cap))).map((n) => (
          <NavButton key={n.id} item={n} active={vista === n.id} onClick={() => escribirHash(n.id)} />
        ))}

        {can(rol, 'verConfiguracion') && (
          <>
            <p className="px-2 pb-1.5 pt-5 text-[10px] font-bold uppercase tracking-[0.14em] text-sidebar-foreground/45">
              Administración
            </p>
            <NavButton
              item={{ label: 'Configuración', icon: Settings }}
              active={vista === 'config'}
              onClick={() => escribirHash('config')}
            />
          </>
        )}
      </nav>

      {/* Modo auditoría del directorio */}
      {can(rol, 'soloLecturaTotal') && (
        <div className="mx-3 mb-3 flex items-center gap-2 rounded-lg bg-white/[0.06] px-3 py-2 text-[11px] font-medium text-sidebar-foreground/85 ring-1 ring-white/10">
          <Eye className="size-3.5 shrink-0 text-accent" />
          Modo auditoría · solo lectura
        </div>
      )}

      {/* Usuario */}
      <div className="flex items-center gap-3 border-t border-sidebar-border px-4 py-3">
        <Avatar nombre={yo?.nombre_completo} color="#7aa6ff" className="size-9" />
        <div className="min-w-0 flex-1 leading-tight">
          <p className="truncate text-[13px] font-semibold text-white">{yo?.nombre_completo ?? '—'}</p>
          <p className="text-[10px] uppercase tracking-wider text-sidebar-foreground/60">
            {rol ? ROL_LABEL[rol] : ''}{yo?.demo ? ' · demo' : ''}
          </p>
        </div>
        <button
          onClick={() => void salir()}
          title="Cerrar sesión"
          className="rounded-md p-1.5 text-sidebar-foreground/70 transition-colors hover:bg-white/10 hover:text-white cursor-pointer"
        >
          <LogOut className="size-4" />
        </button>
      </div>
    </aside>
  )
}
