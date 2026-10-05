import { useCallback, useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import {
  LayoutDashboard, KanbanSquare, Users, CalendarDays, UsersRound, Settings, LogOut, Eye,
  PanelLeftClose, PanelLeftOpen, Wallet, Split, BarChart3, Handshake, Target,
  Gauge, Trophy, ArchiveRestore, SendHorizontal, ListChecks, ReceiptText, CalendarCheck2, ChevronDown,
} from 'lucide-react'
import { administraSoloRolesCrm, can, puedeAdministrarRolesCrm, ROL_LABEL } from '@/lib/roles'
import { funcionesLeadsVisibles } from '@/lib/config'
import { useAuth } from '@/lib/auth-context'
import { Avatar } from '@/components/ui/avatar'
import { BrandLockup } from '@/components/app/brand'
import { cn } from '@/lib/utils'
import {
  VISTAS,
  esVistaConfiguracion,
  esVistaInterna,
  type Vista,
  type VistaConfiguracion,
} from '@/lib/router'
import { vistaPermitida } from '@/lib/vistas'

type SeccionNav = 'principal' | 'administracion'
/** Gerencia conserva los accesos principales y despliega los secundarios. */
type GrupoNav = SeccionNav | 'analisis' | 'operacion'
const GRUPO_LABEL: Record<GrupoNav, string> = {
  principal: 'Principal',
  administracion: 'Administración',
  analisis: 'Análisis',
  operacion: 'Operación',
}

interface NavMeta {
  label: string
  icon: typeof LayoutDashboard
  seccion: SeccionNav
}

type VistaSidebar = Exclude<Vista, 'alertas' | VistaConfiguracion | 'rescate-carpeta'>

/** Metadatos visuales exhaustivos; la autorización vive solo en vistas.ts. */
const NAV_META = {
  hoy: { label: 'Hoy', icon: LayoutDashboard, seccion: 'principal' },
  seguimiento: { label: 'Seguimiento', icon: ListChecks, seccion: 'principal' },
  'gestion-diaria': { label: 'Gestión Diaria', icon: CalendarCheck2, seccion: 'principal' },
  conversiones: { label: 'Conversiones', icon: BarChart3, seccion: 'principal' },
  'ranking-vendedores': { label: 'Ranking', icon: Trophy, seccion: 'principal' },
  reuniones: { label: 'Citas', icon: Handshake, seccion: 'principal' },
  metas: { label: 'Metas', icon: Target, seccion: 'principal' },
  rendimiento: { label: 'Equipo', icon: Gauge, seccion: 'principal' },
  facturacion: { label: 'Facturación', icon: ReceiptText, seccion: 'principal' },
  'informes-empresas': { label: 'Empresas', icon: BarChart3, seccion: 'principal' },
  pipeline: { label: 'Pipeline', icon: KanbanSquare, seccion: 'principal' },
  cartera: { label: 'Leads', icon: Users, seccion: 'principal' },
  agenda: { label: 'Agenda', icon: CalendarDays, seccion: 'principal' },
  // "Cartera" (mi-cartera) reemplaza a Clientes y Contratos, retiradas del todo
  // en Fase 6 (2026-07-21): ya no existen como vistas ni son alcanzables por URL.
  'mi-cartera': { label: 'Mi cartera', icon: Wallet, seccion: 'principal' },
  // Reparto de la cola global (C1): solo coordinador.
  repartir: { label: 'Repartir leads', icon: Split, seccion: 'principal' },
  rescate: { label: 'Base para gestión', icon: ArchiveRestore, seccion: 'principal' },
  derivaciones: { label: 'Derivar leads', icon: SendHorizontal, seccion: 'principal' },
  equipo: { label: 'Gestión de equipo', icon: UsersRound, seccion: 'principal' },
  config: { label: 'Configuración', icon: Settings, seccion: 'administracion' },
} as const satisfies Record<VistaSidebar, NavMeta>

// Alertas vive en la campana superior: no duplica un módulo en el menú lateral.
const VISTAS_SIDEBAR = VISTAS.filter(
  (id): id is VistaSidebar =>
    id !== 'alertas' && !esVistaConfiguracion(id) && !esVistaInterna(id),
)
const NAV = VISTAS_SIDEBAR.map((id) => ({ id, ...NAV_META[id] }))

/**
 * Menú aprobado por Gerencia (05/10/2026): siete accesos directos y tres
 * grupos desplegables. El orden de las claves fija el orden visual.
 * Solo organiza lo que `vistaPermitida` ya dejó pasar; no concede permisos.
 */
const GRUPO_GERENCIA = {
  hoy: 'principal',
  facturacion: 'principal',
  'ranking-vendedores': 'principal',
  reuniones: 'principal',
  'gestion-diaria': 'principal',
  metas: 'principal',
  'mi-cartera': 'principal',
  rendimiento: 'analisis',
  conversiones: 'analisis',
  'informes-empresas': 'analisis',
  cartera: 'operacion',
  pipeline: 'operacion',
  agenda: 'operacion',
  repartir: 'operacion',
  rescate: 'operacion',
  seguimiento: 'operacion',
  derivaciones: 'operacion',
  equipo: 'administracion',
  config: 'administracion',
} as const satisfies Record<VistaSidebar, GrupoNav>
const ORDEN_GERENCIA = Object.keys(GRUPO_GERENCIA) as VistaSidebar[]
const GRUPOS_GERENCIA: readonly GrupoNav[] = ['principal', 'analisis', 'operacion', 'administracion']
const GRUPOS_HISTORICOS: readonly GrupoNav[] = ['principal', 'administracion']

interface ItemNav {
  id: Vista
  label: string
  icon: typeof LayoutDashboard
  seccion: SeccionNav
}

/** Reparte los ítems ya autorizados en grupos con etiqueta; omite grupos vacíos. */
function agruparNav(items: readonly ItemNav[], rol: string | undefined) {
  const esGerencia = rol === 'gerencia'
  const grupoDe = (n: ItemNav): GrupoNav =>
    esGerencia && n.id in GRUPO_GERENCIA ? GRUPO_GERENCIA[n.id as VistaSidebar] : n.seccion
  const ordenados = esGerencia
    ? [...items].sort((a, b) => ORDEN_GERENCIA.indexOf(a.id as VistaSidebar) - ORDEN_GERENCIA.indexOf(b.id as VistaSidebar))
    : items
  return (esGerencia ? GRUPOS_GERENCIA : GRUPOS_HISTORICOS)
    .map((grupo) => ({ grupo, label: GRUPO_LABEL[grupo], items: ordenados.filter((n) => grupoDe(n) === grupo) }))
    .filter((g) => g.items.length > 0)
}
const NAV_GOBIERNO_ROLES = [{
  id: 'config-usuarios',
  label: 'Usuarios y roles',
  icon: UsersRound,
  seccion: 'administracion',
}, {
  id: 'config-citas',
  label: 'Control de Citas',
  icon: Target,
  seccion: 'administracion',
}] as const

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
// Arranca plegado en TODO lo que se toca con el dedo, no solo en teléfono. Un
// iPad tiene 820 px en vertical y el riel se comía 240: casi un tercio de la
// pantalla para un menú que no se usa mientras se mira un tablero. El botón de
// abrirlo sigue donde estaba, y la preferencia guardada manda sobre esto.
// (Miguel, 11/09/2026: «esto está pensado para usar en tablet».)
const esPantallaMovil = () =>
  typeof window !== 'undefined' &&
  (window.matchMedia('(max-width: 767px)').matches ||
    window.matchMedia('(hover: none) and (pointer: coarse) and (max-width: 1279px)').matches)

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
      aria-current={active ? 'page' : undefined}
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

/** Las subrutas mantienen seleccionado su acceso del menú. */
function esEntradaActiva(id: Vista, vista: Vista): boolean {
  return id === vista || (id === 'config' && esVistaConfiguracion(vista)) ||
    (id === 'rescate' && vista === 'rescate-carpeta')
}

function GrupoDesplegable({
  grupo, vista, activo, expandido, abrirMenu, children,
}: {
  grupo: Exclude<GrupoNav, 'principal'>
  vista: Vista
  activo: boolean
  expandido: boolean
  abrirMenu: () => void
  children: ReactNode
}) {
  const [estado, setEstado] = useState({ vista, abierto: activo })
  // Un enlace directo o Atrás debe revelar el destino, incluso si la persona
  // había cerrado su grupo. Conserva los otros grupos abiertos manualmente.
  if (estado.vista !== vista) {
    setEstado({ vista, abierto: activo || estado.abierto })
  }
  const abierto = expandido && estado.abierto
  const Icono = grupo === 'analisis' ? BarChart3 : grupo === 'operacion' ? ListChecks : Settings
  const label = GRUPO_LABEL[grupo]

  return (
    <div role="group" aria-label={label} className={cn(grupo === 'analisis' && 'mt-4 border-t border-sidebar-border pt-3')}>
      <button
        type="button"
        aria-label={label}
        aria-expanded={abierto}
        aria-controls={`nav-${grupo}`}
        title={expandido ? undefined : label}
        onClick={() => {
          abrirMenu()
          setEstado({ vista, abierto: !abierto })
        }}
        className={cn(
          'ac-nav-item group relative flex w-full items-center rounded-lg py-2 text-sm font-medium cursor-pointer text-sidebar-foreground hover:bg-white/[0.06] hover:text-white',
          expandido ? 'gap-3 px-3' : 'justify-center px-2',
          activo && 'bg-white/[0.06]',
        )}
      >
        <Icono className="size-[18px] shrink-0 text-sidebar-foreground/80" aria-hidden />
        {expandido && <>
          <span className="min-w-0 flex-1 text-left">{label}</span>
          <ChevronDown className={cn('size-3.5 shrink-0', !abierto && '-rotate-90')} aria-hidden />
        </>}
      </button>
      <div id={`nav-${grupo}`} hidden={!abierto} className="mt-1 mb-2 ml-[19px] border-l border-sidebar-border pl-[7px]">
        {children}
      </div>
    </div>
  )
}

// App.tsx recibe la intención de navegación y sincroniza estado + hash.
// El menú se puede FIJAR colapsado (botón) a un riel de íconos; estando
// colapsado, al pasar el mouse ASOMA el menú completo (overlay animado) y se
// repliega solo al salir. El <main> ocupa el ancho del riel en TODO el CRM.
export function Sidebar({ vista, onNavegar }: { vista: Vista; onNavegar: (destino: Vista) => void }) {
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

  /**
   * Cancela el asomo y el repliegue EN VUELO. Se llama antes de programar uno
   * nuevo (re-disparar no debe dejar temporizadores huérfanos: el ref solo
   * guarda el último id, así que el anterior ya no se podría cancelar), al
   * navegar en móvil y al desmontar.
   */
  const cancelarTemporizadores = useCallback(() => {
    window.clearTimeout(abrirRef.current)
    abrirRef.current = undefined
    window.clearTimeout(cerrarRef.current)
    cerrarRef.current = undefined
  }, [])

  const abrirMenu = () => {
    cancelarTemporizadores()
    setColapsado(false)
    setAsomando(false)
    // Abrir un grupo es temporal: solo el botón de fijar cambia la preferencia.
  }

  const navegar = (destino: Vista) => {
    onNavegar(destino)
    if (esPantallaMovil()) {
      // En móvil, el toque sobre el menú también dispara mouseEnter → hay un
      // "asomar" programado que sobrevivía a la navegación y volvía a abrir el
      // menú ENCIMA de la pantalla recién elegida. Se cancela antes de replegar.
      cancelarTemporizadores()
      setColapsado(true)
      setAsomando(false)
    }
  }

  const entrar = () => {
    if (!colapsado) return
    cancelarTemporizadores()
    abrirRef.current = window.setTimeout(() => setAsomando(true), ABRIR_MS)
  }
  const salirHover = () => {
    cancelarTemporizadores()
    cerrarRef.current = window.setTimeout(() => setAsomando(false), CERRAR_MS)
  }
  useEffect(() => cancelarTemporizadores, [cancelarTemporizadores])

  const leadsVisibles = funcionesLeadsVisibles(yo?.demo === true, yo?.rol)
  const rolPortalAutorizado = puedeAdministrarRolesCrm(yo) ? 'superadmin' : null
  const soloRoles = administraSoloRolesCrm(yo)
  const candidatos = soloRoles ? NAV_GOBIERNO_ROLES : NAV
  const items = candidatos
    .filter((n) => vistaPermitida(n.id, rol, leadsVisibles, rolPortalAutorizado))
    // La misma ruta base se presenta como resumen ejecutivo solo a Gerencia.
    .map((n) => {
      if (n.id === 'hoy' && rol === 'gerencia') return { ...n, label: 'Resumen' }
      if (n.id === 'metas' && rol === 'gerencia') return { ...n, label: 'Metas y cumplimiento' }
      if (n.id === 'rendimiento' && rol === 'gerencia') return { ...n, label: 'Rendimiento' }
      return n.id === 'mi-cartera' && can(rol, 'verEquipo')
        ? { ...n, label: 'Cartera' }
        : n
    })
  // La marca acompaña a la navegación operativa; el gobierno de roles va sin ella.
  const muestraMarca = items.some((n) => n.seccion === 'principal')
  const grupos = agruparNav(items, rol)
  // Índice de cascada: cada cabecera y cada ítem entran escalonados, en orden.
  let cascada = 1
  const gruposConIndice = grupos.map((g) => ({
    ...g,
    indiceCabecera: cascada++,
    items: g.items.map((n) => ({ ...n, indice: cascada++ })),
  }))
  const indiceUsuario = cascada

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
        <div className={cn('relative flex h-16 items-center border-b border-sidebar-border', expandido ? 'justify-between px-4' : 'justify-center px-2')}>
          {/* Destino geométrico estable de la salida del splash. Existe también
              con el menú colapsado, cuando el BrandLockup no está montado. */}
          <span
            data-splash-destino
            data-splash-destino-visible={expandido ? 'true' : 'false'}
            aria-hidden
            className={cn(
              'pointer-events-none absolute top-[13px] size-[38px]',
              expandido ? 'left-4' : 'left-[13px]',
            )}
          />
          {expandido && muestraMarca && (
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
          {gruposConIndice.map((g, gi) => {
            const desplegable = rol === 'gerencia' && g.grupo !== 'principal'
            const entradas = g.items.map((n) => (
              <NavButton
                key={n.id}
                item={n}
                active={esEntradaActiva(n.id, vista)}
                onClick={() => navegar(n.id)}
                expandido={expandido}
                animar={animar && !desplegable}
                indice={n.indice}
              />
            ))
            if (desplegable && g.grupo !== 'principal') {
              return (
                <GrupoDesplegable
                  key={g.grupo}
                  grupo={g.grupo}
                  vista={vista}
                  activo={g.items.some((n) => esEntradaActiva(n.id, vista))}
                  expandido={expandido}
                  abrirMenu={abrirMenu}
                >
                  {entradas}
                </GrupoDesplegable>
              )
            }
            return (
              <div key={g.grupo} role="group" aria-label={g.label} className="space-y-1">
                {expandido && (
                  <p
                    className={cn(
                      'px-2 pb-1.5 text-[10px] font-bold uppercase tracking-[0.14em] text-sidebar-foreground/45',
                      gi > 0 && 'pt-5',
                    )}
                    data-peek-anim={animar ? '' : undefined}
                    style={animar ? estiloCascada(g.indiceCabecera) : undefined}
                  >
                    {g.label}
                  </p>
                )}
                {entradas}
              </div>
            )
          })}
        </nav>

        {/* Autoridad visible sin confundir gobierno de roles con auditoría CRM. */}
        {soloRoles && expandido ? (
          <div className="mx-3 mb-3 flex items-center gap-2 rounded-lg bg-white/[0.06] px-3 py-2 text-[11px] font-medium text-sidebar-foreground/85 ring-1 ring-white/10">
            <UsersRound className="size-3.5 shrink-0 text-accent" aria-hidden />
            Gobierno de roles CRM
          </div>
        ) : can(rol, 'soloLecturaTotal') && expandido && (
          <div className="mx-3 mb-3 flex items-center gap-2 rounded-lg bg-white/[0.06] px-3 py-2 text-[11px] font-medium text-sidebar-foreground/85 ring-1 ring-white/10">
            <Eye className="size-3.5 shrink-0 text-accent" aria-hidden />
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
            <div className="min-w-0 flex-1 leading-tight" data-peek-anim={animar ? '' : undefined} style={animar ? estiloCascada(indiceUsuario) : undefined}>
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
