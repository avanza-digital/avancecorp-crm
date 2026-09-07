// Topbar — título de vista (+ chip DEMO si la sesión es demo), búsqueda global
// real (leads del ÁMBITO por nombre/teléfono/DNI — espejo RLS F1c: un analista
// no encuentra leads ajenos), bandeja de pendientes con conteo real por rol y
// alta de lead. La búsqueda
// abre el drawer vía usePanelesActions().abrirLead.
//
// POR QUÉ el buscador NO alcanza a los CLIENTES (2026-07-25): prometía «lead o
// cliente» y solo miraba leads, así que un cliente de la propia cartera salía
// como «Sin resultados» — el CRM negando a alguien que sí existe. Los clientes
// no están en el store (useCRMData() expone leads/ámbito/agenda/tareas, nunca
// clientes: viven en useClientes() de TanStack, apagado en demo) y un resultado
// de cliente no tendría a dónde aterrizar: `abrirLead` y el router solo conocen
// #/<vista>/lead/<id>. Decisión: el texto promete SOLO lo que busca y el vacío
// NOMBRA la pantalla donde el cliente sí está, en vez de afirmar que no existe.
import {
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent as TeclaReact,
} from 'react'
import { Plus, Bell, HelpCircle, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { funcionesLeadsVisibles } from '@/lib/config'
import { administraSoloRolesCrm, can, puedeEscribir, type Rol } from '@/lib/roles'
import { vistaPermitida } from '@/lib/vistas'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, type Lead } from '@/lib/tipos'
import { moneyK } from '@/lib/format'
import { hashDe, type Vista } from '@/lib/router'
import { useAlertasCRM } from '@/lib/alertas-context'
import { normalizarTelefono } from '@/lib/validacion'

/** ¿Lo tecleado parece un TELÉFONO? (dígitos y separadores, ≥6 dígitos).
 *  Habilita el atajo «Verificar disponibilidad» del vacío del buscador. */
const esPosibleTelefono = (q: string): boolean => {
  const t = q.trim()
  return /^[+\d][\d\s().-]*$/.test(t) && (t.match(/\d/g)?.length ?? 0) >= 6
}

const TITULOS: Record<Vista, { t: string; s: string }> = {
  hoy: { t: 'Hoy', s: 'Tu siguiente acción y el pulso del día' },
  alertas: { t: 'Pendientes', s: 'Acciones y señales que requieren tu atención' },
  seguimiento: { t: 'Seguimiento', s: 'Prioridades y plazos de la cartera activa' },
  conversiones: { t: 'Conversiones', s: 'Conversión de leads a clientes' },
  'ranking-vendedores': { t: 'Ranking', s: 'Desempeño general de todos los analistas' },
  reuniones: { t: 'Citas', s: 'Pactadas, concretadas, no realizadas y modalidad' },
  metas: { t: 'Metas', s: 'Objetivos individuales y suma automática de la organización' },
  rendimiento: { t: 'Equipo', s: 'Desempeño comercial por responsable' },
  pipeline: { t: 'Pipeline', s: 'Leads de inversión por etapa' },
  cartera: { t: 'Leads', s: 'Todos tus prospectos captados' },
  agenda: { t: 'Agenda', s: 'Citas, llamadas y vencimientos' },
  'mi-cartera': { t: 'Cartera', s: 'Tus clientes y el capital invertido' },
  repartir: { t: 'Repartir leads', s: 'Reparte la cola de leads nuevos a los supervisores' },
  rescate: { t: 'Base para gestión', s: 'Descartes del equipo para revisar y redistribuir' },
  'rescate-carpeta': { t: 'Carpeta de rescate', s: 'Revisa, selecciona y redistribuye este bloque de leads' },
  derivaciones: { t: 'Derivar leads', s: 'Reparte hoy con la carga de cada analista a la vista' },
  equipo: { t: 'Equipo', s: 'Jerarquía y desempeño comercial' },
  config: { t: 'Configuración', s: 'Productos, metas y usuarios' },
  'config-usuarios': { t: 'Usuarios y jerarquía', s: 'Personas, acceso y estructura comercial' },
  'config-productos': { t: 'Productos de inversión', s: 'Catálogo, condiciones y vigencias' },
  'config-metas': { t: 'Metas', s: 'Objetivos mensuales versionados' },
  'config-sla': { t: 'Tiempos de atención', s: 'Políticas y cumplimiento de SLA' },
  'config-rentabilidad': { t: 'Política de rentabilidad', s: 'Tasa base, herencia y excepciones de Gerencia' },
}

/**
 * Rótulo de la pantalla de cartera SEGÚN EL ROL — mismo criterio que el sidebar
 * (una sola regla en el archivo): el analista ve "Mi cartera" en el menú y quien
 * supervisa ve "Cartera". Cualquier texto que mande al usuario allí debe llamarla
 * EXACTAMENTE como la ve en su menú, o lo manda a buscar un ítem que no existe.
 */
function rotuloCartera(rol: Rol | null | undefined): string {
  return can(rol, 'verEquipo') ? 'Cartera' : 'Mi cartera'
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

export function Topbar({
  vista,
  ayudaAbierta = false,
  onAlternarAyuda,
}: {
  vista: Vista
  ayudaAbierta?: boolean
  onAlternarAyuda?: () => void
}) {
  const { yo } = useAuth()
  const soloRoles = administraSoloRolesCrm(yo)
  const { ambito } = useCRMData()
  // F4: la campana cuenta `pendientes` (las que piden acción hoy), no todo lo
  // visible — una alerta reconocida sigue en la lista, atenuada, sin sumar.
  const { pendientes, cargando: cargandoAlertas, errores: erroresAlertas } = useAlertasCRM()
  const { abrirLead, abrirNuevoLead } = usePanelesActions()
  // Rótulo por rol de la pantalla fusionada: "Mi cartera" para el analista, "Cartera" para quien supervisa.
  const info =
    vista === 'hoy' && yo?.rol === 'gerencia'
      ? { t: 'Resumen', s: 'Estado comercial del equipo' }
      : vista === 'mi-cartera'
      ? { t: rotuloCartera(yo?.rol), s: 'Tus clientes y el capital invertido' }
      : TITULOS[vista]
  // Gate de leads (espejo del sidebar): con las funciones de leads sin aprobar,
  // la búsqueda de leads y el alta de lead no se ofrecen a cuentas reales.
  const leadsVisibles = !soloRoles
    && funcionesLeadsVisibles(yo?.demo === true, yo?.rol)

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
    <header className={cn('sticky top-0 z-20 flex h-16 items-center justify-between gap-4 border-b border-border bg-card/80 px-6 backdrop-blur-md', vista === 'seguimiento' && 'max-sm:gap-2 max-sm:px-3')}>
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
        {leadsVisibles && (
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
            placeholder="Buscar lead…"
            role="combobox"
            aria-expanded={abierto && q.trim() !== ''}
            aria-controls="topbar-busqueda-lista"
            aria-autocomplete="list"
            aria-label="Buscar lead por nombre, teléfono o DNI"
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
                <div className="px-3 py-2.5">
                  {/* "en tus leads" acota el vacío a lo que este buscador SÍ mira:
                      un "Sin resultados" a secas se lee como "esa persona no existe". */}
                  <p className="text-[11px] text-muted-foreground">
                    Sin resultados en tus leads para «{q.trim()}»
                  </p>
                  {/* Y si ya es cliente, se le nombra la pantalla REAL donde está
                      (rótulo del menú según su rol) en vez de dejarlo buscando. */}
                  {can(yo?.rol, 'verCartera') && (
                    <p className="mt-1 text-[11px] text-muted-foreground/80">
                      ¿Ya es cliente? Búscalo en «{rotuloCartera(yo?.rol)}», en el menú lateral.
                    </p>
                  )}
                  {/* Puerta de la verificación por contacto (plan «lead libre»,
                      F1): si lo tecleado parece un teléfono, se ofrece verificar
                      contra TODO el CRM — este buscador solo mira tus leads y el
                      que atiende otro analista jamás va a aparecer aquí. Solo
                      roles de escritura: directorio mira, no verifica. Y solo
                      con un CELULAR normalizable: para otros dígitos (un DNI)
                      el atajo prometía una verificación que el alta no puede
                      hacer y su silencio se leía como «libre» (hallazgo de
                      Miguel, 2026-08-17) — a esos se les dice la verdad. */}
                  {puedeEscribir(yo?.rol) && esPosibleTelefono(q) && (
                    normalizarTelefono(q) ? (
                      <button
                        type="button"
                        tabIndex={-1}
                        onMouseDown={(e) => e.preventDefault() /* no robar el foco al input */}
                        onClick={() => {
                          abrirNuevoLead(undefined, q.trim())
                          setQ('')
                          setAbierto(false)
                        }}
                        className="mt-1.5 cursor-pointer text-[11px] font-semibold text-primary hover:underline"
                      >
                        Verificar disponibilidad de este contacto →
                      </button>
                    ) : (
                      <p className="mt-1.5 text-[11px] font-medium text-muted-foreground">
                        La disponibilidad se verifica con el celular (9 dígitos).
                        Un DNI no dice si el contacto está libre u ocupado.
                      </p>
                    )
                  )}
                </div>
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
        )}

        {onAlternarAyuda && !soloRoles && (
          <button
            type="button"
            onClick={onAlternarAyuda}
            aria-label={ayudaAbierta ? 'Minimizar ayuda del analista' : 'Abrir ayuda del analista'}
            aria-pressed={ayudaAbierta}
            className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg border border-border bg-card px-2.5 text-xs font-semibold text-primary transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          >
            <HelpCircle className="size-4 text-accent" aria-hidden />
            <span className="hidden lg:inline">Ayuda</span>
          </button>
        )}

        {/* La campana se pinta con la MISMA función que decide si la vista se
            puede abrir. Antes usaba `can(rol, 'verAlertas')` —que vendedor y
            supervisor tienen— mientras el router exige además el gate de leads:
            con las funciones de leads sin aprobar, el clic intentaba ir a
            #/alertas, `sanearVista` lo devolvía a su landing con `replaceState`
            —que NO redispara hashchange— y no pasaba absolutamente nada. Ni
            error, ni cambio de pantalla: indistinguible de un botón muerto, y
            encima con burbuja roja encima. Fuente única: si no se puede abrir,
            no se pinta. */}
        {!soloRoles && vistaPermitida('alertas', yo?.rol, leadsVisibles) && (
          <a
            href={hashDe('alertas')}
            title="Abrir pendientes"
            aria-label={pendientes > 0
              ? `Abrir pendientes: ${pendientes} ${pendientes === 1 ? 'activo' : 'activos'}`
              : 'Abrir pendientes'}
            aria-current={vista === 'alertas' ? 'page' : undefined}
            className="relative inline-flex size-9 cursor-pointer items-center justify-center rounded-lg transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          >
            <Bell className="size-4" aria-hidden />
            {pendientes > 0 && (
              <span className="absolute -right-1 -top-1 grid min-w-4 place-items-center rounded-full bg-destructive px-1 text-[9px] font-extrabold leading-4 text-destructive-foreground" aria-hidden>
                {pendientes > 99 ? '99+' : pendientes}
              </span>
            )}
            {pendientes === 0 && erroresAlertas.length > 0 && (
              <span className="absolute right-0.5 top-0.5 size-2 rounded-full bg-warning ring-2 ring-card" aria-hidden />
            )}
            {pendientes === 0 && erroresAlertas.length === 0 && cargandoAlertas && (
              <span className="absolute right-0.5 top-0.5 size-2 animate-pulse rounded-full bg-primary ring-2 ring-card motion-reduce:animate-none" aria-hidden />
            )}
          </a>
        )}

        {leadsVisibles && puedeEscribir(yo?.rol) && (
          <Button variant="accent" aria-label="Nuevo lead" title="Nuevo lead" onClick={() => abrirNuevoLead()}>
            <Plus aria-hidden /> <span className={vista === 'seguimiento' ? 'sr-only sm:not-sr-only' : undefined}>Nuevo lead</span>
          </Button>
        )}
      </div>
    </header>
  )
}
