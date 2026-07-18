// Pantalla AGENDA (Fases C + D del plan v2) — la vista de planificación sobre
// las MISMAS tareas de crm.tareas que alimentan HOY (una sola fuente de verdad).
//
// Cuatro vistas: [Hoy] = el día operable (vencidas + hoy, la cola real de
// trabajo) · [Semana] = 7 columnas con el hint de ritmo mar–jue en los huecos
// (la evidencia SUGIERE, nunca impone) · [Mes] = densidad + día seleccionado
// operable · [Todo] = panorama agrupado por día. Buscador y filtros
// tipo/estado/etapa sobre todas; atajos de teclado en desktop (1–4 · ←/→ · H).
//
// La TARJETA es operable (no un calendario decorativo): abrir ficha,
// hover-card, capital en juego, llamar/WhatsApp (AccionesContacto), cerrar
// con resultado (motor Fase B), reprogramar rápido +1d/+3d/+1sem, y el
// anti no-show de Fase E: recordatorio wa.me que PIDE confirmación + chip
// Confirmada/Sin confirmar en reuniones.
import { useCallback, useEffect, useMemo, useState } from 'react'
import { toast } from 'sonner'
import {
  AlertTriangle,
  BellRing,
  CalendarClock,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleCheckBig,
  ExternalLink,
  Phone,
  Search,
  ShieldCheck,
  Sparkles,
  Users,
  X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { puedeEscribir } from '@/lib/roles'
import { COLOR_EVENTO, enlaceGoogleCalendar, esDeHoy, fechaLima, tareaAEvento } from '@/lib/agenda-derivada'
import {
  aplicarFiltros,
  diasDeSemana,
  FILTROS_APAGADOS,
  hayFiltros,
  rejillaMes,
  tareasPorDia,
  tituloSemana,
  type CeldaMes,
  type DiaAgenda,
  type FiltrosAgenda,
} from '@/lib/agenda-vistas'
import { ameritaRecordatorio, enlaceRecordatorio } from '@/lib/recordatorio'
import { AccionesContacto } from '@/components/app/contacto'
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import { money } from '@/lib/format'
import { ETAPAS, TIPO_EVENTO, TIPOS_TAREA, type Lead, type Tarea } from '@/lib/tipos'
import { cn } from '@/lib/utils'

// ── Mini-KPIs del día ─────────────────────────────────────────────────────────
function statsDe(tareas: Tarea[], ahora: number): StatChipData[] {
  const eventos = tareas.map((t) => tareaAEvento(t, ahora))
  const nBy = (t: string) => eventos.filter((a) => a.tipo === t).length
  return [
    { icon: CalendarDays, label: 'Pendientes', value: String(eventos.length), tone: 'primary', sub: 'en tu agenda' },
    { icon: Users, label: 'Reuniones', value: String(nBy('reunion')), tone: 'accent' },
    { icon: Phone, label: 'Llamadas', value: String(nBy('llamada')), tone: 'accent' },
    { icon: AlertTriangle, label: 'Vencidas', value: String(eventos.filter((a) => a.vencida).length), tone: 'warn' },
  ]
}

/** Reprogramar rápido: los 3 saltos del plan (posponer sin formulario). */
const SALTOS: ReadonlyArray<{ label: string; dias: number }> = [
  { label: '+1d', dias: 1 },
  { label: '+3d', dias: 3 },
  { label: '+1sem', dias: 7 },
]

function TarjetaTarea({
  t,
  lead,
  ahora,
  escribe,
  abrirLead,
  onCerrar,
}: {
  t: Tarea
  lead: Lead | undefined
  ahora: number
  escribe: boolean
  abrirLead: (id: string) => void
  onCerrar: (t: Tarea) => void
}) {
  const { reprogramarTarea, confirmarTarea } = useCRMData()
  const { yo } = useAuth()
  const ev = tareaAEvento(t, ahora)
  const hora = ev.cuando.split(' · ')[1] ?? ''
  const gcal = enlaceGoogleCalendar(t)
  const recordatorio = lead && ameritaRecordatorio(t, ahora) ? enlaceRecordatorio(t, lead, ahora) : null

  const posponer = (dias: number) => {
    const res = reprogramarTarea(t.id, new Date(Date.parse(t.vence_en) + dias * 86_400_000).toISOString())
    if (res.ok) toast.success(`Reprogramada ${dias === 7 ? '+1 semana' : `+${dias} día${dias > 1 ? 's' : ''}`}${yo?.demo ? ' (demo)' : ''}`)
    else toast.error(res.error ?? 'No se pudo reprogramar')
  }

  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${t.titulo}`}
      onClick={() => t.lead_id && abrirLead(t.lead_id)}
      onKeyDown={(e) => {
        if ((e.key === 'Enter' || e.key === ' ') && t.lead_id) {
          e.preventDefault()
          abrirLead(t.lead_id)
        }
      }}
      className="group flex cursor-pointer flex-wrap items-center gap-x-3 gap-y-1.5 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <span className="w-1 self-stretch rounded" style={{ background: ev.color, minHeight: 44 }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          {lead ? (
            <LeadHoverCard lead={lead}>
              <p className="truncate text-sm font-semibold">{t.titulo}</p>
            </LeadHoverCard>
          ) : (
            <p className="truncate text-sm font-semibold">{t.titulo}</p>
          )}
          <Badge color={ev.color} className="text-[10px]">{TIPO_EVENTO[t.tipo] ?? t.tipo}</Badge>
          {t.tipo === 'reunion' && !ev.vencida && (
            t.confirmada_en ? (
              <Badge color="#16a34a" className="text-[10px]">
                <ShieldCheck className="size-3" aria-hidden /> Confirmada
              </Badge>
            ) : (
              <Badge color="#d97706" className="text-[10px]">Sin confirmar</Badge>
            )
          )}
          {t.reprogramaciones > 0 && (
            <span className="text-[10px] font-medium text-muted-foreground">
              movida ×{t.reprogramaciones}
            </span>
          )}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5">
          {lead?.monto_estimado != null && (
            <span className="text-[11px] font-semibold tabular-nums text-muted-foreground">
              {money(lead.monto_estimado, lead.moneda)} en juego
            </span>
          )}
          {escribe && (
            <span className="hidden items-center gap-1 sm:flex">
              {SALTOS.map((s) => (
                <button
                  key={s.label}
                  type="button"
                  title={`Reprogramar ${s.label}`}
                  className="cursor-pointer rounded-md px-1.5 py-0.5 text-[10px] font-bold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                  onClick={(e) => {
                    e.stopPropagation()
                    posponer(s.dias)
                  }}
                >
                  <CalendarClock className="mr-0.5 inline size-3" aria-hidden />{s.label}
                </button>
              ))}
            </span>
          )}
        </div>
      </div>

      {/* Acciones de canal + anti no-show + cierre — cortan la propagación */}
      <span className="flex shrink-0 items-center gap-1">
        {recordatorio && escribe && (
          <a
            href={recordatorio}
            target="_blank"
            rel="noreferrer"
            title="Recordar por WhatsApp (pide confirmación y menciona el capital)"
            aria-label={`Recordar cita — ${t.titulo}`}
            onClick={(e) => e.stopPropagation()}
            className="grid size-8 place-items-center rounded-lg text-[#16a34a] transition-colors hover:bg-[#16a34a]/10"
          >
            <BellRing className="size-4" aria-hidden />
          </a>
        )}
        {t.tipo === 'reunion' && !t.confirmada_en && !ev.vencida && escribe && (
          <button
            type="button"
            title="El cliente confirmó la cita"
            aria-label={`Marcar confirmada — ${t.titulo}`}
            className="grid size-8 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            onClick={(e) => {
              e.stopPropagation()
              const res = confirmarTarea(t.id)
              if (res.ok) toast.success(`Cita confirmada${yo?.demo ? ' (demo)' : ''}`)
              else toast.error(res.error ?? 'No se pudo confirmar')
            }}
          >
            <ShieldCheck className="size-4" aria-hidden />
          </button>
        )}
        {gcal && (
          <a
            href={gcal}
            target="_blank"
            rel="noreferrer"
            title="Añadir a Google Calendar"
            aria-label={`Añadir a Google Calendar — ${t.titulo}`}
            onClick={(e) => e.stopPropagation()}
            className="grid size-8 place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <ExternalLink className="size-4" aria-hidden />
          </a>
        )}
        {lead && <AccionesContacto lead={lead} compacto soloIcono />}
        {escribe && (
          <button
            type="button"
            title="Cerrar tarea (resultado + siguiente)"
            aria-label={`Cerrar tarea — ${t.titulo}`}
            className="grid size-8 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground"
            onClick={(e) => {
              e.stopPropagation()
              onCerrar(t)
            }}
          >
            <CircleCheckBig className="size-4" aria-hidden />
          </button>
        )}
      </span>

      <span
        className={cn(
          'shrink-0 text-xs font-semibold tabular-nums',
          ev.vencida ? 'text-[#d97706]' : 'text-muted-foreground',
        )}
      >
        {ev.vencida ? ev.cuando : hora || ev.cuando}
      </span>
    </div>
  )
}

// ── Navegación temporal compartida (Semana/Mes) ───────────────────────────────
function NavTemporal({
  titulo,
  enBase,
  onPrev,
  onNext,
  onHoy,
}: {
  titulo: string
  /** true = ya estamos en la semana/mes actual (oculta el botón "Hoy"). */
  enBase: boolean
  onPrev: () => void
  onNext: () => void
  onHoy: () => void
}) {
  const flecha =
    'grid size-7 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground'
  return (
    <div className="flex items-center gap-1.5">
      <button type="button" aria-label="Anterior" className={flecha} onClick={onPrev}>
        <ChevronLeft className="size-4" aria-hidden />
      </button>
      <button type="button" aria-label="Siguiente" className={flecha} onClick={onNext}>
        <ChevronRight className="size-4" aria-hidden />
      </button>
      <p className="text-sm font-bold tracking-tight">{titulo}</p>
      {!enBase && (
        <button
          type="button"
          className="cursor-pointer rounded-full bg-muted px-2.5 py-1 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground"
          onClick={onHoy}
        >
          Hoy
        </button>
      )}
    </div>
  )
}

// ── Vista SEMANA: 7 columnas + hint de ritmo en los huecos ────────────────────

/** Tarjeta mínima de la columna: hora + título, color del tipo (ámbar vencida). */
function MiniTarea({ t, ahora, abrir }: { t: Tarea; ahora: number; abrir: () => void }) {
  const ev = tareaAEvento(t, ahora)
  const hora = ev.cuando.split(' · ')[1] ?? ''
  return (
    <button
      type="button"
      title={`${t.titulo} — ${ev.cuando}`}
      aria-label={`Abrir ficha — ${t.titulo}`}
      onClick={abrir}
      className="flex w-full cursor-pointer items-stretch gap-1.5 rounded-md p-1.5 text-left transition-colors hover:bg-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
    >
      <span className="w-0.5 shrink-0 rounded" style={{ background: ev.color }} aria-hidden />
      <span className="min-w-0 leading-tight">
        <span className="block text-[10px] font-bold tabular-nums" style={{ color: ev.color }}>
          {ev.vencida ? 'Vencida' : hora}
        </span>
        <span className="block truncate text-[11px] font-semibold text-foreground">{t.titulo}</span>
      </span>
    </button>
  )
}

function VistaSemana({
  dias,
  porDia,
  ahora,
  abrirLead,
}: {
  dias: DiaAgenda[]
  porDia: ReadonlyMap<string, Tarea[]>
  ahora: number
  abrirLead: (id: string) => void
}) {
  return (
    <Card className="overflow-x-auto p-2.5">
      <div className="grid min-w-[880px] grid-cols-7 gap-1.5">
        {dias.map((d) => {
          const tareas = porDia.get(d.fecha) ?? []
          const domingo = d.dow === 0
          return (
            <div
              key={d.fecha}
              title={domingo ? 'Domingo: fuera de la ventana legal de contacto (L–S 07:00–20:00)' : undefined}
              className={cn(
                'flex min-h-44 flex-col gap-1 rounded-lg p-1.5',
                d.esHoy ? 'bg-accent/10 ring-1 ring-accent/30' : 'bg-muted/30',
                domingo && 'opacity-55',
              )}
            >
              <div className="flex items-center justify-between gap-1 px-0.5">
                <span className={cn('text-[11px] font-bold', d.esHoy ? 'text-accent' : 'text-muted-foreground')}>
                  {d.label}
                </span>
                {tareas.length > 0 && (
                  <span className="rounded-full bg-muted px-1.5 text-[10px] font-bold tabular-nums text-muted-foreground">
                    {tareas.length}
                  </span>
                )}
              </div>
              {tareas.map((t) => (
                <MiniTarea key={t.id} t={t} ahora={ahora} abrir={() => t.lead_id && abrirLead(t.lead_id)} />
              ))}
              {/* Hueco en mar–jue futuro: el mejor momento para citas (Gong:
                  +30% de asistencia). Sugerencia, jamás candado. */}
              {tareas.length === 0 && d.esMarJue && !d.esPasado && (
                <div className="mt-auto rounded-md border border-dashed border-accent/30 p-1.5 text-center">
                  <Sparkles className="mx-auto size-3.5 text-accent/60" aria-hidden />
                  <p className="mt-0.5 text-[10px] font-semibold text-muted-foreground">Buen día para citas</p>
                  <p className="text-[10px] tabular-nums text-muted-foreground/80">10–11:30 · 16–18</p>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </Card>
  )
}

// ── Vista MES: densidad por día + día seleccionado operable ───────────────────

const CABECERA_MES = ['L', 'M', 'M', 'J', 'V', 'S', 'D']

function VistaMes({
  semanas,
  porDia,
  diaSel,
  onDia,
}: {
  semanas: CeldaMes[][]
  porDia: ReadonlyMap<string, Tarea[]>
  diaSel: string | null
  onDia: (fecha: string) => void
}) {
  const celda = (c: CeldaMes) => {
    const tareas = porDia.get(c.fecha) ?? []
    const vencidas = c.esPasado && tareas.length > 0 // pendientes en día pasado = vencidas
    const tipos = Array.from(new Set(tareas.map((t) => t.tipo))).slice(0, 3)
    const activa = diaSel === c.fecha
    return (
      <button
        key={c.fecha}
        type="button"
        aria-label={`${c.label} — ${tareas.length} ${tareas.length === 1 ? 'tarea' : 'tareas'}`}
        aria-pressed={activa}
        onClick={() => onDia(c.fecha)}
        className={cn(
          'flex h-14 cursor-pointer flex-col items-center justify-between rounded-lg py-1.5 transition-colors hover:bg-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40',
          !c.delMes && 'opacity-35',
          c.esHoy && 'bg-accent/10',
          activa && 'ring-2 ring-accent',
        )}
      >
        <span className={cn('text-xs font-extrabold tabular-nums', c.esHoy ? 'text-accent' : 'text-foreground')}>
          {c.num}
        </span>
        {tareas.length > 0 ? (
          <span className="flex items-center gap-1">
            <span
              className="text-[10px] font-bold tabular-nums"
              style={{ color: vencidas ? '#d97706' : 'var(--muted-foreground)' }}
            >
              {tareas.length}
            </span>
            <span className="flex gap-0.5">
              {tipos.map((tipo) => (
                <span key={tipo} className="size-1.5 rounded-full" style={{ background: COLOR_EVENTO[tipo] }} aria-hidden />
              ))}
            </span>
          </span>
        ) : (
          <span className="size-1.5" aria-hidden />
        )}
      </button>
    )
  }

  return (
    <Card className="p-2.5">
      <div className="grid grid-cols-7 gap-1">
        {CABECERA_MES.map((d, i) => (
          <span key={i} className="pb-1 text-center text-[10px] font-bold uppercase text-muted-foreground">
            {d}
          </span>
        ))}
        {semanas.flat().map(celda)}
      </div>
    </Card>
  )
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

const VISTAS = ['hoy', 'semana', 'mes', 'todo'] as const
type Vista = (typeof VISTAS)[number]

export function Agenda() {
  const { ambito, tareas } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  const ahora = useAhora()
  const escribe = puedeEscribir(yo?.rol)
  const [vista, setVista] = useState<Vista>('hoy')
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  const [filtros, setFiltros] = useState<FiltrosAgenda>(FILTROS_APAGADOS)
  const [offsetSemana, setOffsetSemana] = useState(0)
  const [offsetMes, setOffsetMes] = useState(0)
  const [diaSel, setDiaSel] = useState<string | null>(null)

  // Ámbito (espejo RLS): solo tareas de leads que el rol puede ver.
  const idsAmbito = useMemo(() => new Set(ambito.leads.map((l) => l.id)), [ambito.leads])
  const leadPorId = useCallback(
    (id: string | null): Lead | undefined => (id ? ambito.leads.find((l) => l.id === id) : undefined),
    [ambito.leads],
  )

  const pendientes = useMemo(
    () =>
      tareas
        .filter((t) => t.estado === 'pendiente' && t.activo && t.lead_id && idsAmbito.has(t.lead_id))
        .sort((a, b) => a.vence_en.localeCompare(b.vence_en)),
    [tareas, idsAmbito],
  )
  // Los KPIs cuentan la agenda COMPLETA (la verdad del día); los filtros solo
  // recortan lo que se lista — la nota "n de m" hace visible la diferencia.
  const stats = useMemo(() => statsDe(pendientes, ahora), [pendientes, ahora])
  const filtrados = useMemo(
    () => aplicarFiltros(pendientes, filtros, ahora, leadPorId),
    [pendientes, filtros, ahora, leadPorId],
  )
  const conFiltros = hayFiltros(filtros)

  // [Hoy] = vencidas + las de hoy (el día operable); [Todo] = panorama por día.
  const delDia = useMemo(
    () => filtrados.filter((t) => {
      const ev = tareaAEvento(t, ahora)
      return ev.vencida || esDeHoy(ev, ahora)
    }),
    [filtrados, ahora],
  )
  const visibles = vista === 'hoy' ? delDia : filtrados
  const grupos = useMemo(() => {
    const out: { dia: string; items: Tarea[] }[] = []
    for (const t of visibles) {
      const dia = tareaAEvento(t, ahora).cuando.split(' · ')[0] ?? 'Sin fecha'
      const g = out.find((x) => x.dia === dia)
      if (g) g.items.push(t)
      else out.push({ dia, items: [t] })
    }
    return out
  }, [visibles, ahora])

  // Geometría de las vistas nuevas (Fase D) — todo derivado del reloj vivo.
  const semana = useMemo(() => diasDeSemana(ahora, offsetSemana), [ahora, offsetSemana])
  const mes = useMemo(() => rejillaMes(ahora, offsetMes), [ahora, offsetMes])
  const porDia = useMemo(() => tareasPorDia(filtrados), [filtrados])
  const tiraSemana = useMemo(() => diasDeSemana(ahora, 0), [ahora])
  // Día operable del Mes: el elegido, o hoy cuando se mira el mes en curso.
  const diaMes = diaSel ?? (offsetMes === 0 ? fechaLima(ahora) : null)
  const tareasDiaMes = diaMes ? porDia.get(diaMes) ?? [] : []
  const celdaDiaMes = diaMes ? mes.semanas.flat().find((c) => c.fecha === diaMes) : undefined

  // Atajos desktop: 1–4 cambian de vista · ←/→ navegan semana/mes · H vuelve a
  // hoy. Mismas guardas que el "/" global del topbar: nada con modales abiertos
  // ni escribiendo en un campo.
  useEffect(() => {
    const alTecla = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (document.querySelector('[aria-modal="true"]')) return
      const t = e.target as HTMLElement | null
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return
      const idx = ['1', '2', '3', '4'].indexOf(e.key)
      if (idx >= 0) {
        const v = VISTAS[idx]
        if (v) setVista(v)
        e.preventDefault()
        return
      }
      if (e.key === 'h' || e.key === 'H') {
        setOffsetSemana(0)
        setOffsetMes(0)
        setDiaSel(null)
        e.preventDefault()
        return
      }
      if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && (vista === 'semana' || vista === 'mes')) {
        const paso = e.key === 'ArrowLeft' ? -1 : 1
        if (vista === 'semana') setOffsetSemana((o) => o + paso)
        else {
          setOffsetMes((o) => o + paso)
          setDiaSel(null)
        }
        e.preventDefault()
      }
    }
    window.addEventListener('keydown', alTecla)
    return () => window.removeEventListener('keydown', alTecla)
  }, [vista])

  const patch = (p: Partial<FiltrosAgenda>) => setFiltros((f) => ({ ...f, ...p }))

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      {/* Tira de la semana en curso (Lima, reloj vivo) — toca un día y saltas
          a la vista Semana. Solo en Hoy/Todo: en Semana/Mes sería redundante. */}
      {(vista === 'hoy' || vista === 'todo') && (
        <Card className="ac-pop p-2.5">
          <div className="flex items-stretch gap-1.5">
            {tiraSemana.map((c) => (
              <button
                key={c.fecha}
                type="button"
                aria-label={`Ver la semana — ${c.label}`}
                onClick={() => {
                  setOffsetSemana(0)
                  setVista('semana')
                }}
                className={cn(
                  'flex flex-1 cursor-pointer flex-col items-center gap-0.5 rounded-lg py-2 transition-colors',
                  c.esHoy
                    ? 'bg-accent text-accent-foreground shadow-[var(--shadow-card)]'
                    : 'text-muted-foreground hover:bg-muted/60',
                )}
              >
                <span className="text-[10px] font-bold uppercase">{c.label.split(' ')[0]?.charAt(0)}</span>
                <span className={cn('text-sm font-extrabold tabular-nums', c.esHoy ? 'text-accent-foreground' : 'text-foreground')}>
                  {c.num}
                </span>
              </button>
            ))}
          </div>
        </Card>
      )}

      {/* Selector de vista */}
      <div className="flex flex-wrap items-center gap-1.5">
        {(
          [
            { k: 'hoy', label: `Hoy${delDia.length > 0 ? ` · ${delDia.length}` : ''}` },
            { k: 'semana', label: 'Semana' },
            { k: 'mes', label: 'Mes' },
            { k: 'todo', label: `Todo · ${filtrados.length}` },
          ] as const
        ).map((v) => (
          <button
            key={v.k}
            type="button"
            aria-pressed={vista === v.k}
            onClick={() => setVista(v.k)}
            className={cn(
              'cursor-pointer rounded-full px-3 py-1.5 text-xs font-bold transition-colors',
              vista === v.k ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground',
            )}
          >
            {v.label}
          </button>
        ))}
      </div>

      {/* Buscador + filtros tipo/estado/etapa — recortan TODAS las vistas */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative min-w-44 flex-1 basis-52">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            value={filtros.q}
            onChange={(e) => patch({ q: e.target.value })}
            placeholder="Buscar tarea, nota o lead…"
            aria-label="Buscar en la agenda"
            className="h-8 pl-8 text-xs"
          />
        </div>
        <div className="w-36 shrink-0">
          <Select
            value={filtros.tipo}
            onChange={(e) => patch({ tipo: e.target.value as FiltrosAgenda['tipo'] })}
            aria-label="Filtrar por tipo"
            className="h-8 text-xs"
          >
            <option value="todos">Todos los tipos</option>
            {TIPOS_TAREA.map((t) => (
              <option key={t.k} value={t.k}>{t.label}</option>
            ))}
          </Select>
        </div>
        <div className="w-36 shrink-0">
          <Select
            value={filtros.estado}
            onChange={(e) => patch({ estado: e.target.value as FiltrosAgenda['estado'] })}
            aria-label="Filtrar por estado"
            className="h-8 text-xs"
          >
            <option value="todas">Todas</option>
            <option value="vencida">Vencidas</option>
            <option value="sin_confirmar">Sin confirmar</option>
            <option value="confirmada">Confirmadas</option>
          </Select>
        </div>
        <div className="w-40 shrink-0">
          <Select
            value={filtros.etapa}
            onChange={(e) => patch({ etapa: e.target.value as FiltrosAgenda['etapa'] })}
            aria-label="Filtrar por etapa del lead"
            className="h-8 text-xs"
          >
            <option value="todas">Todas las etapas</option>
            {ETAPAS.map((e) => (
              <option key={e.k} value={e.k}>{e.label}</option>
            ))}
          </Select>
        </div>
        {conFiltros && (
          <button
            type="button"
            onClick={() => setFiltros(FILTROS_APAGADOS)}
            className="flex cursor-pointer items-center gap-1 rounded-full bg-muted px-2.5 py-1.5 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground"
          >
            <X className="size-3" aria-hidden /> Limpiar · {filtrados.length} de {pendientes.length}
          </button>
        )}
      </div>

      {/* ── SEMANA ── */}
      {vista === 'semana' && (
        <>
          <NavTemporal
            titulo={tituloSemana(semana)}
            enBase={offsetSemana === 0}
            onPrev={() => setOffsetSemana((o) => o - 1)}
            onNext={() => setOffsetSemana((o) => o + 1)}
            onHoy={() => setOffsetSemana(0)}
          />
          <VistaSemana dias={semana} porDia={porDia} ahora={ahora} abrirLead={abrirLead} />
        </>
      )}

      {/* ── MES ── */}
      {vista === 'mes' && (
        <>
          <NavTemporal
            titulo={mes.titulo}
            enBase={offsetMes === 0}
            onPrev={() => {
              setOffsetMes((o) => o - 1)
              setDiaSel(null)
            }}
            onNext={() => {
              setOffsetMes((o) => o + 1)
              setDiaSel(null)
            }}
            onHoy={() => {
              setOffsetMes(0)
              setDiaSel(null)
            }}
          />
          <VistaMes semanas={mes.semanas} porDia={porDia} diaSel={diaMes} onDia={setDiaSel} />
          {diaMes ? (
            <Card>
              <SectionHead
                icon={CalendarDays}
                title={celdaDiaMes ? `${celdaDiaMes.label} — ${mes.titulo}` : diaMes}
                right={
                  tareasDiaMes.length > 0 ? (
                    <Badge color="var(--accent)">
                      {tareasDiaMes.length} {tareasDiaMes.length === 1 ? 'tarea' : 'tareas'}
                    </Badge>
                  ) : undefined
                }
              />
              <CardContent className="space-y-1 pt-0">
                {tareasDiaMes.length === 0 ? (
                  <p className="pb-3 text-xs text-muted-foreground">
                    Sin tareas ese día — agenda la próxima acción desde la ficha de un lead.
                  </p>
                ) : (
                  tareasDiaMes.map((t) => (
                    <TarjetaTarea
                      key={t.id}
                      t={t}
                      lead={leadPorId(t.lead_id)}
                      ahora={ahora}
                      escribe={escribe}
                      abrirLead={abrirLead}
                      onCerrar={setTareaACerrar}
                    />
                  ))
                )}
              </CardContent>
            </Card>
          ) : (
            <p className="text-xs text-muted-foreground">Elige un día para ver y trabajar sus tareas.</p>
          )}
        </>
      )}

      {/* ── HOY / TODO ── */}
      {(vista === 'hoy' || vista === 'todo') && (
        <>
          {/* Vacío accionable */}
          {grupos.length === 0 && (
            <Card>
              <CardContent className="flex flex-col items-center gap-1.5 py-10 text-center">
                <CalendarDays className="size-8 text-muted-foreground/50" />
                <p className="text-sm font-semibold text-foreground">
                  {conFiltros
                    ? 'Nada coincide con los filtros'
                    : vista === 'hoy'
                      ? 'Nada pendiente para hoy'
                      : 'Sin tareas pendientes en tu agenda'}
                </p>
                {conFiltros ? (
                  <button
                    type="button"
                    onClick={() => setFiltros(FILTROS_APAGADOS)}
                    className="cursor-pointer text-xs font-bold text-accent hover:underline"
                  >
                    Limpiar filtros
                  </button>
                ) : (
                  <p className="max-w-md text-xs text-muted-foreground">
                    Agenda la próxima acción desde la ficha de un lead — ningún lead activo debería quedarse sin una.
                  </p>
                )}
              </CardContent>
            </Card>
          )}

          {/* Timeline agrupado por día — tarjetas OPERABLES */}
          {grupos.map((g) => (
            <Card key={g.dia}>
              <SectionHead
                icon={g.dia === 'Vencida' ? AlertTriangle : CalendarDays}
                title={g.dia === 'Vencida' ? 'Vencidas' : g.dia}
                right={
                  <Badge color={g.dia === 'Vencida' ? '#d97706' : 'var(--accent)'}>
                    {g.items.length} {g.items.length === 1 ? 'tarea' : 'tareas'}
                  </Badge>
                }
              />
              <CardContent className="space-y-1 pt-0">
                {g.items.map((t) => (
                  <TarjetaTarea
                    key={t.id}
                    t={t}
                    lead={leadPorId(t.lead_id)}
                    ahora={ahora}
                    escribe={escribe}
                    abrirLead={abrirLead}
                    onCerrar={setTareaACerrar}
                  />
                ))}
              </CardContent>
            </Card>
          ))}
        </>
      )}

      <p className="text-[11px] text-muted-foreground">
        La agenda es real: cerrar una tarea registra el resultado en el timeline y te propone la siguiente;
        “Recordar” manda un WhatsApp que pide confirmación de la cita.
        <span className="hidden md:inline"> Atajos: 1–4 cambian de vista · ←/→ navegan semana y mes · H vuelve a hoy.</span>
      </p>

      <CerrarTareaDialog tarea={tareaACerrar} onCerrar={() => setTareaACerrar(null)} />
    </div>
  )
}
