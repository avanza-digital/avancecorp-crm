// Topbar — título de vista (+ chip DEMO si la sesión es demo), búsqueda global
// real (leads del ÁMBITO por nombre/teléfono/DNI — espejo RLS F1c: un vendedor
// no encuentra leads ajenos), campana honesta (sin punto rojo fijo) y alta de
// lead. La búsqueda abre el drawer vía usePanelesActions().abrirLead.
import {
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent as TeclaReact,
} from 'react'
import { Plus, Bell, Search } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { puedeEscribir } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, type Lead } from '@/lib/tipos'
import { moneyK } from '@/lib/format'
import type { Vista } from '@/lib/router'

const TITULOS: Record<Vista, { t: string; s: string }> = {
  hoy: { t: 'Hoy', s: 'Tu siguiente acción y el pulso del día' },
  pipeline: { t: 'Pipeline', s: 'Leads de inversión por etapa' },
  cartera: { t: 'Cartera', s: 'Todos tus leads y clientes captados' },
  agenda: { t: 'Agenda', s: 'Reuniones, llamadas y vencimientos' },
  equipo: { t: 'Equipo', s: 'Jerarquía comercial y reparto' },
  config: { t: 'Configuración', s: 'Productos, metas y usuarios' },
}

/** Minúsculas y sin acentos (es-PE) para comparar texto. */
function norm(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
}

/** Filtra leads por nombre/teléfono/DNI — insensible a mayúsculas y acentos, máx. 8. */
function buscarLeads(leads: Lead[], q: string): Lead[] {
  const nq = norm(q.trim())
  if (!nq) return []
  const dq = nq.replace(/\D/g, '') // versión solo-dígitos para tel/DNI
  if (nq.length < 2 && dq.length < 3) return []
  return leads
    .filter(
      (l) =>
        norm(l.nombre_completo).includes(nq) ||
        norm(l.telefono).includes(nq) ||
        (dq !== '' && l.telefono.replace(/\D/g, '').includes(dq)) ||
        (dq !== '' && !!l.dni && l.dni.includes(dq)),
    )
    .slice(0, 8)
}

export function Topbar({ vista }: { vista: Vista }) {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const { abrirLead, abrirNuevoLead } = usePanelesActions()
  const info = TITULOS[vista]

  // Aún no hay origen real de notificaciones: cuando exista, este número
  // vendrá de ahí y el punto de la campana volverá solo.
  const notificacionesPendientes: number = 0

  const inputRef = useRef<HTMLInputElement>(null)
  const [q, setQ] = useState('')
  const qDiferida = useDeferredValue(q)
  const [abierto, setAbierto] = useState(false)
  const [activo, setActivo] = useState(0)

  const resultados = useMemo(
    () => buscarLeads(ambito.leads, qDiferida),
    [ambito.leads, qDiferida],
  )
  // Índice resaltado, siempre dentro de rango aunque cambien los resultados.
  const iActivo = resultados.length > 0 ? Math.min(activo, resultados.length - 1) : 0

  // Atajo global "/": enfoca el buscador salvo que el foco ya esté en un campo editable.
  useEffect(() => {
    const alTeclaGlobal = (e: KeyboardEvent) => {
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return
      // Con un drawer/modal abierto, "/" no debe enfocar un input tapado por el overlay.
      if (document.querySelector('[aria-modal="true"]')) return
      const t = e.target as HTMLElement | null
      if (
        t &&
        (t.tagName === 'INPUT' ||
          t.tagName === 'TEXTAREA' ||
          t.tagName === 'SELECT' ||
          t.isContentEditable)
      ) {
        return
      }
      e.preventDefault()
      inputRef.current?.focus()
      inputRef.current?.select()
    }
    window.addEventListener('keydown', alTeclaGlobal)
    return () => window.removeEventListener('keydown', alTeclaGlobal)
  }, [])

  const elegir = (id: string) => {
    abrirLead(id)
    setQ('')
    setAbierto(false)
    inputRef.current?.blur()
  }

  const alTeclearBusqueda = (e: TeclaReact<HTMLInputElement>) => {
    if (e.key === 'Escape') {
      // Esc "cierra lo de más arriba": el buscador, no el panel que haya debajo.
      e.stopPropagation()
      setAbierto(false)
      inputRef.current?.blur()
      return
    }
    if (resultados.length === 0) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setAbierto(true)
      setActivo((iActivo + 1) % resultados.length)
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setAbierto(true)
      setActivo((iActivo - 1 + resultados.length) % resultados.length)
    } else if (e.key === 'Enter' && abierto) {
      e.preventDefault()
      const r = resultados[iActivo]
      if (r) elegir(r.id)
    }
  }

  return (
    <header className="sticky top-0 z-20 flex h-16 items-center justify-between gap-4 border-b border-border bg-card/80 px-6 backdrop-blur-md">
      <div className="min-w-0 leading-tight">
        <div className="flex min-w-0 items-center gap-2">
          <h1 className="truncate text-lg font-extrabold tracking-tight text-primary">{info.t}</h1>
          {/* Chip discreto: deja claro que los datos son de demostración */}
          {yo?.demo && (
            <span className="shrink-0 rounded-full border border-border bg-muted px-2 py-px text-[9px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
              Demo
            </span>
          )}
        </div>
        <p className="truncate text-xs text-muted-foreground">{info.s}</p>
      </div>

      <div className="flex items-center gap-2">
        <div className="relative hidden md:block">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
          <input
            ref={inputRef}
            type="text"
            value={q}
            onChange={(e) => {
              setQ(e.target.value)
              setActivo(0)
              setAbierto(true)
            }}
            onFocus={() => setAbierto(true)}
            onBlur={() => setAbierto(false)}
            onKeyDown={alTeclearBusqueda}
            placeholder="Buscar lead o cliente…"
            role="combobox"
            aria-expanded={abierto && q.trim() !== ''}
            aria-controls="topbar-busqueda-lista"
            aria-autocomplete="list"
            aria-label="Buscar lead o cliente por nombre, teléfono o DNI"
            className="h-8 w-60 rounded-lg border border-input bg-background pl-8 pr-8 text-xs text-foreground transition-colors placeholder:text-muted-foreground focus-visible:border-ring focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30 lg:w-72"
          />
          <kbd className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded border border-border bg-muted px-1.5 py-0.5 text-[10px] font-semibold text-muted-foreground">
            /
          </kbd>

          {abierto && q.trim() !== '' && (
            <div
              id="topbar-busqueda-lista"
              className="ac-pop absolute left-0 right-0 top-full z-30 mt-1.5 overflow-hidden rounded-xl border border-border bg-card shadow-[var(--shadow-pop)]"
            >
              {resultados.length === 0 ? (
                <p className="px-3 py-2.5 text-[11px] text-muted-foreground">
                  Sin resultados para «{q.trim()}»
                </p>
              ) : (
                <ul role="listbox" aria-label="Resultados de búsqueda" className="ac-scroll max-h-72 overflow-y-auto py-1">
                  {resultados.map((l, i) => {
                    const et = ETAPA_INFO[l.etapa]
                    return (
                      <li key={l.id} role="option" aria-selected={i === iActivo}>
                        <button
                          type="button"
                          tabIndex={-1}
                          onMouseDown={(e) => e.preventDefault() /* no robar el foco al input */}
                          onClick={() => elegir(l.id)}
                          onMouseEnter={() => setActivo(i)}
                          className={cn(
                            'flex w-full cursor-pointer items-center gap-2 px-3 py-2 text-left transition-colors',
                            i === iActivo && 'bg-muted',
                          )}
                        >
                          <span className="min-w-0 flex-1 truncate text-xs font-semibold text-foreground">
                            {l.nombre_completo}
                          </span>
                          <span
                            className="shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-bold"
                            style={{ backgroundColor: `${et.color}1a`, color: et.color }}
                          >
                            {et.label}
                          </span>
                          {/* Sin monto no se muestra "S/ 0" (igual que drawer y cartera) */}
                          {l.monto_estimado != null && (
                            <span className="shrink-0 text-[11px] font-extrabold tabular-nums text-primary">
                              {moneyK(l.monto_estimado, l.moneda)}
                            </span>
                          )}
                        </button>
                      </li>
                    )
                  })}
                </ul>
              )}
            </div>
          )}
        </div>

        <Button
          variant="ghost"
          size="icon"
          title="Las notificaciones llegan pronto"
          aria-label="Notificaciones"
          onClick={() => toast.info('Las notificaciones llegan pronto')}
          className="relative"
        >
          <Bell className="size-4" />
          {/* Campana honesta: el punto solo aparece con conteo REAL de
              notificaciones pendientes — hoy no existe ese origen, así que
              nunca se pinta (nada de badges decorativos). */}
          {notificacionesPendientes > 0 && (
            <span className="ac-flick absolute right-2 top-2 size-1.5 rounded-full bg-destructive" />
          )}
        </Button>

        {puedeEscribir(yo?.rol) && (
          <Button variant="accent" onClick={() => abrirNuevoLead()}>
            <Plus /> Nuevo lead
          </Button>
        )}
      </div>
    </header>
  )
}
