// Pipeline (kanban) VIVO — F1b: lee y muta el store demo (useCRMData).
// Card clicable → drawer; menú "…" y drag & drop HTML5 para mover de etapa;
// alta por columna. Todo write-gated (rol directorio = solo lectura total).
// F1c: consciente del rol — trabaja SIEMPRE sobre useCRMData().ambito y, para
// supervisor/gerencia/directorio, ofrece pills de filtro por vendedor
// (+ bandeja "Por repartir" de parkeados). El vendedor solo ve lo suyo.
import { useEffect, useRef, useState, type CSSProperties, type DragEvent, useMemo } from 'react'
import { Users, TrendingUp, FileText, Target, Plus, MoreHorizontal, ExternalLink, Inbox } from 'lucide-react'
import { toast } from 'sonner'
import { Card } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import {
  DropdownMenu,
  DropdownItem,
  DropdownLabel,
  DropdownSeparator,
} from '@/components/ui/dropdown-menu'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { CAT_LABEL, ETAPA_INFO, ETAPAS, TERMINALES, origenLabel, type EtapaActiva, type Lead } from '@/lib/tipos'
import { capitalPorMoneda, capitalPrincipal, indexarUltimoContacto } from '@/lib/inteligencia'
import { semaforoEstancamiento, type SemaforoEtapa } from '@/lib/estancamiento'
import { DialogCapitalPropuesta } from '@/components/app/capital-propuesta'
import { moneyK } from '@/lib/format'
import { can, puedeEscribir } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { minutosLegibles } from '@/lib/sla-versionado'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'

// "hace X" compacto a partir de DÍAS ya calculados (el reloj lo decide
// `semaforoEstancamiento`, para que color y número no puedan divergir).
function haceDias(dias: number): string {
  const d = Math.floor(dias)
  if (d <= 0) return 'hoy'
  if (d === 1) return 'ayer'
  if (d < 7) return `hace ${d} d`
  return `hace ${Math.floor(d / 7)} sem`
}

// Ventana (ms) durante la que un click se atribuye al arrastre recién soltado y
// no al asesor. Solo tiene que cubrir el click sintético que el navegador
// dispara pegado al drop; cualquier click humano llega muchísimo después.
const MS_CLICK_FANTASMA = 60

// Pills del filtro por vendedor (sin verde: activo = azul primario; bandeja = ámbar)
const PILL_BASE =
  'flex cursor-pointer items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-semibold transition-colors'
const pillCls = (activo: boolean) =>
  `${PILL_BASE} ${
    activo
      ? 'border-primary/60 bg-primary/10 text-primary'
      : 'border-border bg-card text-muted-foreground hover:bg-muted hover:text-foreground'
  }`

interface LeadCardProps {
  l: Lead
  /** Semáforo por ETAPA — lo calcula la pantalla, que es quien tiene el índice
   *  de contacto (construirlo por card sería O(actividades) × O(leads)). */
  semaforo: SemaforoEtapa
  escribe: boolean
  arrastrando: boolean
  onAbrir: () => void
  onMover: (etapa: EtapaActiva) => void
  onDragStart: (e: DragEvent<HTMLDivElement>) => void
  onDragEnd: () => void
}

function LeadCard({ l, semaforo, escribe, arrastrando, onAbrir, onMover, onDragStart, onDragEnd }: LeadCardProps) {
  // ac-lift (will-change) crea un stacking context por card: mientras el menú
  // está abierto hay que elevar ESTA card o el panel queda bajo la siguiente.
  const [menuAbierto, setMenuAbierto] = useState(false)
  return (
    <Card
      className={`ac-lift cursor-pointer p-3 ${arrastrando ? 'opacity-40' : ''} ${menuAbierto ? 'relative z-30' : ''}`}
      role="button"
      tabIndex={0}
      onClick={onAbrir}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onAbrir()
        }
      }}
      draggable={escribe || undefined}
      onDragStart={escribe ? onDragStart : undefined}
      onDragEnd={escribe ? onDragEnd : undefined}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="min-w-0 truncate text-sm font-semibold text-foreground">{l.nombre_completo}</p>
        {l.monto_estimado != null && (
          <p className="shrink-0 text-sm font-extrabold tabular-nums text-primary">{moneyK(l.monto_estimado, l.moneda)}</p>
        )}
      </div>
      <div className="mt-2 flex items-center gap-1.5">
        {l.categoria_interes ? (
          <Badge color="var(--chart-4)" className="text-[10px]">Inversión · {CAT_LABEL[l.categoria_interes]}</Badge>
        ) : (
          <Badge color="var(--muted-foreground)" className="text-[10px]">{origenLabel(l.origen)}</Badge>
        )}
      </div>
      <div className="mt-2.5 flex items-center justify-between border-t border-border pt-2">
        {l.vendedor_nombre ? (
          <span className="flex items-center gap-1.5">
            <Avatar nombre={l.vendedor_nombre} className="size-5 text-[8px]" />
            <span className="text-[11px] text-muted-foreground">{l.vendedor_nombre.split(' ')[0]}</span>
          </span>
        ) : (
          <Badge color="var(--warning)" className="text-[10px]">sin asignar</Badge>
        )}
        <span className="flex items-center gap-1">
          {/* El punto y el número salen del MISMO episodio de etapa sellado en
              BD. Sin fotografía SLA no se inventa color con la política actual. */}
          {semaforo.color && (
            <span
              aria-hidden
              className="size-1.5 shrink-0 rounded-full"
              style={{ backgroundColor: semaforo.color }}
            />
          )}
          <span
            className="text-[11px] tabular-nums"
            style={{ color: semaforo.estancado ? semaforo.color ?? undefined : undefined }}
            title={
              semaforo.objetivoMinutos == null
                ? `Sin fotografía SLA disponible · referencia operativa ${haceDias(semaforo.dias)}`
                : `Lleva ${haceDias(semaforo.dias)} en ${ETAPA_INFO[l.etapa].label} · plazo sellado ${minutosLegibles(semaforo.objetivoMinutos)} · SLA v${semaforo.politicaVersion ?? '—'}${semaforo.aproximado ? ' (aproximado)' : ''}`
            }
          >
            {haceDias(semaforo.dias)}
          </span>
          {escribe && (
            // stopPropagation (click y keydown): el menú vive dentro de una card
            // clicable e interactiva por teclado — sin esto, Enter/Space sobre el
            // trigger o un ítem abriría la ficha en vez de operar el menú.
            // role=presentation: solo intercepta burbujeo, no es un control.
            <div role="presentation" onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
              <DropdownMenu
                onOpenChange={setMenuAbierto}
                trigger={
                  <button
                    type="button"
                    aria-label={`Acciones de ${l.nombre_completo}`}
                    className="grid size-6 cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                  >
                    <MoreHorizontal className="size-3.5" />
                  </button>
                }
              >
                <DropdownItem onSelect={onAbrir}>
                  <ExternalLink /> Abrir ficha
                </DropdownItem>
                <DropdownSeparator />
                <DropdownLabel>Mover a</DropdownLabel>
                {ETAPAS.filter((e) => e.k !== l.etapa).map((e) => (
                  <DropdownItem key={e.k} onSelect={() => onMover(e.k)}>
                    <span className="size-2 shrink-0 rounded-full" style={{ background: e.color }} />
                    {e.label}
                  </DropdownItem>
                ))}
              </DropdownMenu>
            </div>
          )}
        </span>
      </div>
    </Card>
  )
}

export function Pipeline() {
  const { yo } = useAuth()
  const escribe = puedeEscribir(yo?.rol)
  const { ambito, cambiarEtapa, actividadesDelAmbito } = useCRMData()
  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividadesDelAmbito)
  // Índice de CONTACTO REAL (no de cualquier actividad): la `reasignacion` que
  // el sistema escribe al repartir apagaría el semáforo de un lead que nadie
  // ha llamado. Se construye UNA vez por render, no una por card.
  const indiceContacto = useMemo(() => indexarUltimoContacto(actividadesDelAmbito), [actividadesDelAmbito])
  const { abrirLead, abrirNuevoLead } = usePanelesActions()
  const ahora = useAhora() // reloj vivo: "hace X" de las cards se refresca solo
  // F1c: el tablero SIEMPRE trabaja sobre el ámbito del rol, nunca el global.
  const leads = ambito.leads

  // ── Filtro por vendedor (pills) — solo roles con la capacidad y >1 vendedor ──
  const [fVend, setFVend] = useState<string>('todos') // 'todos' | 'por_repartir' | perfil_id
  const [limites, setLimites] = useState<Record<EtapaActiva, number>>({
    nuevo: 60,
    contactado: 60,
    reunion_agendada: 60,
    propuesta_enviada: 60,
  })
  const mostrarFiltro = can(yo?.rol, 'filtrarPorVendedor') && ambito.vendedores.length > 1
  // Bandeja "por repartir": sin vendedor asignado y aún en etapa de trabajo.
  const porRepartir = leads.filter(
    (l) => l.vendedor_id == null && !['convertido', 'descartado'].includes(l.etapa),
  )
  // El filtro degrada solo a "Todos" cuando deja de tener sentido (vendedor
  // fuera del ámbito, o bandeja vacía tras repartir el último parkeado).
  const filtro = !mostrarFiltro
    ? 'todos'
    : fVend === 'por_repartir'
      ? porRepartir.length > 0
        ? fVend
        : 'todos'
      : fVend !== 'todos' && !ambito.vendedores.some((v) => v.perfil_id === fVend)
        ? 'todos'
        : fVend
  // Solo las COLUMNAS se filtran; los stats y terminales resumen el ámbito completo.
  const enTablero =
    filtro === 'todos'
      ? leads
      : filtro === 'por_repartir'
        ? leads.filter((l) => l.vendedor_id == null)
        : leads.filter((l) => l.vendedor_id === filtro)

  // Drag & drop HTML5 (solo con permiso de escritura)
  const [dragId, setDragId] = useState<string | null>(null)
  const [colDestino, setColDestino] = useState<EtapaActiva | null>(null)
  const huboDrag = useRef(false) // evita que el click fantasma tras soltar abra la ficha
  const timerClickFantasma = useRef<number | null>(null)

  // Limpia el timeout del click fantasma si el tablero se desmonta con un drag en vuelo.
  useEffect(() => () => {
    if (timerClickFantasma.current != null) clearTimeout(timerClickFantasma.current)
  }, [])

  /**
   * Fin del arrastre, en UN solo sitio y con salida garantizada.
   * Se invoca desde el DROP *además* de desde `onDragEnd` porque `onDragEnd` no
   * es de fiar: al soltar, el lead cambia de etapa y React DESMONTA la card de
   * la columna vieja, así que su handler no llega a correr — y ese es el caso
   * NORMAL, no el raro. Confiar solo en él dejaba `huboDrag` en true para
   * siempre (el tablero no volvía a abrir ninguna ficha con un click) y `dragId`
   * pegado, con una card fantasma en opacity-40.
   */
  const terminarArrastre = () => {
    setDragId(null)
    setColDestino(null)
    if (timerClickFantasma.current != null) clearTimeout(timerClickFantasma.current)
    // El click sintético que sigue a soltar cae DENTRO de la ventana → se
    // ignora (que es para lo que existe `huboDrag`); pasada la ventana el guard
    // se levanta pase lo que pase, sin depender de un `dragEnd` que quizá no
    // llegue nunca.
    timerClickFantasma.current = window.setTimeout(() => {
      huboDrag.current = false
      timerClickFantasma.current = null
    }, MS_CLICK_FANTASMA)
  }

  const abrir = (id: string) => {
    if (huboDrag.current) return
    abrirLead(id)
  }

  // Pasar a "Propuesta enviada" es el ÚNICO momento en que el capital es un
  // HECHO y no una corazonada del primer contacto — y de esa cifra viven el
  // capital en proceso y las metas del mes. Se pregunta ahí, con un campo ya
  // precargado: Enter confirma tal cual.
  const [pidiendoCapital, setPidiendoCapital] = useState<Lead | null>(null)

  const mover = (id: string, etapa: EtapaActiva) => {
    if (etapa === 'propuesta_enviada') {
      const l = ambito.leads.find((x) => x.id === id)
      if (l && l.etapa !== 'propuesta_enviada') {
        setPidiendoCapital(l)
        return
      }
    }
    const r = cambiarEtapa(id, etapa)
    if (!r.ok && r.error) toast.error(r.error)
  }

  const alDragStart = (id: string) => (e: DragEvent<HTMLDivElement>) => {
    e.dataTransfer.setData('text/plain', id)
    e.dataTransfer.effectAllowed = 'move'
    huboDrag.current = true
    setDragId(id)
  }

  const alDrop = (etapa: EtapaActiva) => (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    // Cerrar el arrastre ANTES de mover: `mover` cambia la etapa y con ella
    // desmonta la card de origen (y su `onDragEnd`) en el mismo latido.
    terminarArrastre()
    if (id) mover(id, etapa)
  }

  // ── KPIs del tablero — F1: servidos por resumen_cartera_fn (o espejo demo
  // vivo); la pantalla ya no cuenta filas. Convención (misma que Hoy y Equipo):
  // solo abiertos CON vendedor — los parkeados van aparte en la pill "Por
  // repartir". La cifra grande del capital es la moneda que DE VERDAD tiene
  // volumen (capitalPrincipal) — PEN y USD JAMÁS se suman ni se convierten.
  // Sin payload (cargando o RPC caída): «—», jamás una cifra inventada.
  const resumenOp = useResumenCarteraOperativo(leads, actividadesDelAmbito)
  const resumen = resumenOp.resumen
  const capital = resumen
    ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd)
    : null
  const propuestas = resumen?.embudo.find((p) => p.etapa === 'propuesta_enviada')?.n
  const stats: StatChipData[] = [
    { icon: Users, label: 'Leads activos', value: resumen ? String(resumen.totales.asignados) : '—', tone: 'primary' },
    {
      icon: TrendingUp,
      label: 'Capital en proceso',
      value: capital?.valor ?? '—',
      tone: 'accent',
      // exactOptionalPropertyTypes: sin capital el sub se OMITE, no viaja undefined.
      ...(capital ? { sub: capital.sub } : {}),
    },
    { icon: FileText, label: 'Propuestas', value: propuestas != null ? String(propuestas) : '—' },
    { icon: Target, label: 'Convertidos', value: resumen ? String(resumen.totales.convertidos) : '—', tone: 'primary' },
  ]

  return (
    <div className="mx-auto max-w-[1440px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      <AvisoDegradacion
        activo={Boolean(estadoSla.error) && !yo?.demo}
        queReintenta="de los plazos del reloj SLA"
        onReintentar={estadoSla.recargar}
      >
        No se pudo cargar el reloj SLA. Los plazos se ocultan para no mostrar vencimientos incorrectos.
      </AvisoDegradacion>

      {/* Degradación honesta de los KPIs (precedente objetivosError): el
          tablero sigue operable; solo los chips quedan en «—». */}
      <AvisoDegradacion
        activo={Boolean(resumenOp.error) && !yo?.demo}
        queReintenta="de los indicadores del tablero"
        onReintentar={() => { void resumenOp.recargar() }}
      >
        No se pudieron cargar los indicadores del tablero. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      {/* Filtro por vendedor — supervisor: su equipo; gerencia/directorio: todos */}
      {mostrarFiltro && (
        <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filtrar tablero por vendedor">
          <button
            type="button"
            aria-pressed={filtro === 'todos'}
            onClick={() => setFVend('todos')}
            className={pillCls(filtro === 'todos')}
          >
            Todos
          </button>
          {ambito.vendedores.map((v) => (
            <button
              key={v.perfil_id}
              type="button"
              aria-pressed={filtro === v.perfil_id}
              onClick={() => setFVend((f) => (f === v.perfil_id ? 'todos' : v.perfil_id))}
              className={pillCls(filtro === v.perfil_id)}
              title={v.nombre_completo}
            >
              <Avatar nombre={v.nombre_completo} className="size-5 text-[8px]" />
              {v.nombre_completo.split(' ')[0]}
            </button>
          ))}
          {porRepartir.length > 0 && (
            <button
              type="button"
              aria-pressed={filtro === 'por_repartir'}
              onClick={() => setFVend((f) => (f === 'por_repartir' ? 'todos' : 'por_repartir'))}
              className={PILL_BASE}
              style={{
                borderColor: 'color-mix(in srgb, var(--warning) 45%, transparent)',
                color: 'var(--warning)',
                background:
                  filtro === 'por_repartir'
                    ? 'color-mix(in srgb, var(--warning) 12%, transparent)'
                    : 'var(--card)',
              }}
            >
              <Inbox className="size-3.5" />
              Por repartir <span className="tabular-nums">({porRepartir.length})</span>
            </button>
          )}
        </div>
      )}

      {/* Kanban */}
      <div className="ac-scroll -mx-1 flex gap-3 overflow-x-auto px-1 pb-3">
        {ETAPAS.map((col) => {
          const enCol = enTablero.filter((l) => l.etapa === col.k)
          const visibles = enCol.slice(0, limites[col.k])
          const { pen: totalPEN, usd: totalUSD } = capitalPorMoneda(enCol)
          const totalTxt = [
            totalPEN > 0 ? moneyK(totalPEN) : '',
            totalUSD > 0 ? `+${moneyK(totalUSD, 'USD')}` : '',
          ]
            .filter(Boolean)
            .join(' · ')
          const destino = colDestino === col.k
          return (
            <div key={col.k} className="flex w-[290px] shrink-0 flex-col">
              {/* Cabecera de columna */}
              <div className="mb-2.5 flex items-center gap-2 px-1">
                <span
                  className="size-2.5 rounded-full"
                  style={{ background: col.color, boxShadow: `0 0 0 3px color-mix(in srgb, ${col.color} 20%, transparent)` }}
                />
                <p className="text-[13px] font-bold text-foreground">{col.label}</p>
                <span className="grid min-w-5 place-items-center rounded-full bg-muted px-1.5 text-[11px] font-bold tabular-nums text-muted-foreground">
                  {enCol.length}
                </span>
                <p className="ml-auto text-[11px] font-extrabold tabular-nums" style={{ color: col.color }}>
                  {totalTxt}
                </p>
              </div>

              {/* Cards (la columna entera es zona de drop) */}
              <div
                className={`flex-1 space-y-2.5 rounded-2xl p-2 transition-colors ${
                  destino ? 'bg-primary/[0.08] ring-2 ring-primary/50' : 'bg-primary/[0.03] ring-1 ring-border/60'
                }`}
                onDragOver={
                  escribe
                    ? (e) => {
                        e.preventDefault()
                        e.dataTransfer.dropEffect = 'move'
                        if (colDestino !== col.k) setColDestino(col.k)
                      }
                    : undefined
                }
                onDragLeave={
                  escribe
                    ? (e) => {
                        if (!e.currentTarget.contains(e.relatedTarget as Node)) {
                          setColDestino((c) => (c === col.k ? null : c))
                        }
                      }
                    : undefined
                }
                onDrop={escribe ? alDrop(col.k) : undefined}
              >
                {visibles.map((l) => (
                  <LeadCard
                    key={l.id}
                    l={l}
                    semaforo={semaforoEstancamiento(
                      l,
                      indiceContacto,
                      ahora,
                      estadoSla.indice.get(l.id),
                    )}
                    escribe={escribe}
                    arrastrando={dragId === l.id}
                    onAbrir={() => abrir(l.id)}
                    onMover={(etapa) => mover(l.id, etapa)}
                    onDragStart={alDragStart(l.id)}
                    // Red de seguridad, no el camino principal: cubre el
                    // arrastre ABORTADO (soltar fuera de una columna), el único
                    // en el que la card sigue montada para recibirlo.
                    onDragEnd={terminarArrastre}
                  />
                ))}
                {enCol.length === 0 && (
                  <div className="rounded-xl border border-dashed border-border px-3 py-6 text-center text-[11px] text-muted-foreground">
                    {destino ? 'Suelta aquí para mover el lead' : 'Sin leads en esta etapa'}
                  </div>
                )}
                {visibles.length < enCol.length && (
                  <button
                    type="button"
                    className="w-full rounded-lg border border-border bg-card px-3 py-2 text-[11px] font-semibold text-muted-foreground hover:text-foreground"
                    onClick={() => setLimites((actual) => ({
                      ...actual,
                      [col.k]: actual[col.k] + 60,
                    }))}
                  >
                    Mostrar 60 más · faltan {enCol.length - visibles.length}
                  </button>
                )}
                {escribe && (
                  <button
                    onClick={() => abrirNuevoLead(col.k)}
                    className="ac-nav-item flex w-full items-center justify-center gap-1.5 rounded-lg py-2 text-[11px] font-semibold text-muted-foreground hover:bg-muted hover:text-foreground cursor-pointer"
                  >
                    <Plus className="size-3.5" /> Agregar lead
                  </button>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {/* Terminales */}
      <div className="flex flex-wrap items-center gap-3">
        {TERMINALES.map((t) => {
          const n = leads.filter((l) => l.etapa === t.k).length
          return (
            <div key={t.k} className="ac-chip flex items-center gap-2 rounded-xl px-3 py-2 text-xs font-bold" style={{ '--c': t.color } as CSSProperties}>
              {t.label}
              <span className="tabular-nums">{n}</span>
            </div>
          )
        })}
        <p className="self-center text-[11px] text-muted-foreground">
          {yo?.demo
            ? escribe
              ? 'Demo — arrastra una card a otra columna o usa su menú "⋯" para moverla de etapa. Los cambios viven solo en esta sesión.'
              : 'Demo — tu rol es de solo lectura; los datos viven solo en esta sesión.'
            : escribe
              ? 'Arrastra una card a otra columna o usa su menú "⋯" para moverla de etapa.'
              : 'Tu rol es de solo lectura.'}
        </p>
      </div>
      {pidiendoCapital && (
        <DialogCapitalPropuesta lead={pidiendoCapital} onClose={() => setPidiendoCapital(null)} />
      )}
    </div>
  )
}
