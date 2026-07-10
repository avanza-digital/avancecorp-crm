// Pipeline (kanban) VIVO — F1b: lee y muta el store demo (useStore).
// Card clicable → drawer; menú "…" y drag & drop HTML5 para mover de etapa;
// alta por columna. Todo write-gated (rol directorio = solo lectura total).
// F1c: consciente del rol — trabaja SIEMPRE sobre useStore().ambito y, para
// supervisor/gerencia/directorio, ofrece pills de filtro por vendedor
// (+ bandeja "Por repartir" de parkeados). El vendedor solo ve lo suyo.
import { useRef, useState, type CSSProperties, type DragEvent } from 'react'
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
import { ETAPAS, ORIGENES, TERMINALES, type EtapaActiva, type Lead } from '@/lib/tipos'
import { money, moneyK } from '@/lib/format'
import { can, puedeEscribir } from '@/lib/roles'
import { useAuth } from '@/lib/auth'
import { useStore } from '@/lib/store'

// "hace X" compacto a partir de un ISO.
function hace(iso: string): string {
  const d = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
  if (d <= 0) return 'hoy'
  if (d === 1) return 'ayer'
  if (d < 7) return `hace ${d} d`
  return `hace ${Math.floor(d / 7)} sem`
}

const CAT_LABEL: Record<string, string> = { nuevo: 'Nuevo', renovacion: 'Renovación', upgrade: 'Upgrade' }

/** Label es-PE del origen (la clave cruda capitalizada muestra "Campania"). */
const origenLabel = (k: string) => ORIGENES.find((o) => o.k === k)?.label ?? k

/** Suma montos SOLO de una moneda (no se mezclan PEN y USD en un total). */
const capitalDe = (ls: Lead[], moneda: 'PEN' | 'USD') =>
  ls.filter((l) => l.moneda === moneda).reduce((s, l) => s + (l.monto_estimado ?? 0), 0)

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
  escribe: boolean
  arrastrando: boolean
  onAbrir: () => void
  onMover: (etapa: EtapaActiva) => void
  onDragStart: (e: DragEvent<HTMLDivElement>) => void
  onDragEnd: () => void
}

function LeadCard({ l, escribe, arrastrando, onAbrir, onMover, onDragStart, onDragEnd }: LeadCardProps) {
  // ac-lift (will-change) crea un stacking context por card: mientras el menú
  // está abierto hay que elevar ESTA card o el panel queda bajo la siguiente.
  const [menuAbierto, setMenuAbierto] = useState(false)
  return (
    <Card
      className={`ac-lift cursor-pointer p-3 ${arrastrando ? 'opacity-40' : ''} ${menuAbierto ? 'relative z-30' : ''}`}
      onClick={onAbrir}
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
          <span className="text-[11px] tabular-nums text-muted-foreground">{hace(l.creado_en)}</span>
          {escribe && (
            // stopPropagation: el menú vive dentro de una card clicable
            <div onClick={(e) => e.stopPropagation()}>
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
  const { ambito, abrirLead, abrirNuevoLead, cambiarEtapa } = useStore()
  // F1c: el tablero SIEMPRE trabaja sobre el ámbito del rol, nunca el global.
  const leads = ambito.leads

  // ── Filtro por vendedor (pills) — solo roles con la capacidad y >1 vendedor ──
  const [fVend, setFVend] = useState<string>('todos') // 'todos' | 'por_repartir' | perfil_id
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

  const abrir = (id: string) => {
    if (huboDrag.current) return
    abrirLead(id)
  }

  const mover = (id: string, etapa: EtapaActiva) => {
    const r = cambiarEtapa(id, etapa)
    if (!r.ok && r.error) toast.error(r.error)
  }

  const alDragStart = (id: string) => (e: DragEvent<HTMLDivElement>) => {
    e.dataTransfer.setData('text/plain', id)
    e.dataTransfer.effectAllowed = 'move'
    huboDrag.current = true
    setDragId(id)
  }

  const alDragEnd = () => {
    setDragId(null)
    setColDestino(null)
    // El click posterior al drop se dispara antes que este timeout → se ignora.
    setTimeout(() => { huboDrag.current = false }, 0)
  }

  const alDrop = (etapa: EtapaActiva) => (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    setColDestino(null)
    const id = e.dataTransfer.getData('text/plain')
    if (id) mover(id, etapa)
  }

  // Convención de KPIs (misma que Hoy y Equipo): solo abiertos VIVOS (l.activo)
  // y CON vendedor — los parkeados van aparte en la pill "Por repartir".
  const activos = leads.filter(
    (l) => l.activo && l.vendedor_id != null && !['convertido', 'descartado'].includes(l.etapa),
  )
  const capitalPEN = capitalDe(activos, 'PEN')
  const capitalUSD = capitalDe(activos, 'USD')
  const stats: StatChipData[] = [
    { icon: Users, label: 'Leads activos', value: String(activos.length), tone: 'primary' },
    {
      icon: TrendingUp,
      label: 'Capital en proceso',
      value: money(capitalPEN),
      tone: 'accent',
      sub: capitalUSD > 0 ? `PEN · +${moneyK(capitalUSD, 'USD')}` : 'PEN',
    },
    { icon: FileText, label: 'Propuestas', value: String(leads.filter((l) => l.etapa === 'propuesta_enviada').length) },
    { icon: Target, label: 'Convertidos', value: String(leads.filter((l) => l.etapa === 'convertido').length), tone: 'primary' },
  ]

  return (
    <div className="mx-auto max-w-[1440px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

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
          const totalPEN = capitalDe(enCol, 'PEN')
          const totalUSD = capitalDe(enCol, 'USD')
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
                {enCol.map((l) => (
                  <LeadCard
                    key={l.id}
                    l={l}
                    escribe={escribe}
                    arrastrando={dragId === l.id}
                    onAbrir={() => abrir(l.id)}
                    onMover={(etapa) => mover(l.id, etapa)}
                    onDragStart={alDragStart(l.id)}
                    onDragEnd={alDragEnd}
                  />
                ))}
                {enCol.length === 0 && (
                  <div className="rounded-xl border border-dashed border-border px-3 py-6 text-center text-[11px] text-muted-foreground">
                    {destino ? 'Suelta aquí para mover el lead' : 'Sin leads en esta etapa'}
                  </div>
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
          {escribe
            ? 'Demo — arrastra una card a otra columna o usa su menú "⋯" para moverla de etapa. Los cambios viven solo en esta sesión.'
            : 'Demo — tu rol es de solo lectura; los datos viven solo en esta sesión.'}
        </p>
      </div>
    </div>
  )
}
