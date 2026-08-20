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
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { toast } from 'sonner'
import {
  AlertTriangle,
  BellRing,
  CalendarClock,
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CircleCheckBig,
  ExternalLink,
  Phone,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Users,
  X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { PanelVacio } from '@/components/common/estado-panel'
import { SegmentBar, StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useEsMovil } from '@/lib/media'
import { slotHabil } from '@/lib/motor-siguiente'
import { can, puedeEscribir } from '@/lib/roles'
import { COLOR_EVENTO, enlaceGoogleCalendar, esDeHoy, fechaLima, LIMA_OFFSET_MS, MESES, tareaAEvento } from '@/lib/agenda-derivada'
import {
  agruparPorPersona,
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
import { etiquetaModalidadReunion } from '@/components/app/campos-reunion'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import { money } from '@/lib/format'
import { ETAPAS, TIPO_EVENTO, TIPOS_TAREA, type Lead, type Tarea } from '@/lib/tipos'
import { cn } from '@/lib/utils'

// ── Mini-KPIs del día ─────────────────────────────────────────────────────────
function statsDe(tareas: Tarea[], ahora: number): StatChipData[] {
  const eventos = tareas.map((t) => tareaAEvento(t, ahora))
  const nBy = (t: string) => eventos.filter((a) => a.tipo === t).length
  const nVencidas = eventos.filter((a) => a.vencida).length
  return [
    // El alcance va declarado en el chip: estos números son de TODA la agenda,
    // aunque abajo se navegue a otra semana/mes (el resumen del período visible
    // vive pegado al título que cambia, en NavTemporal).
    { icon: CalendarDays, label: 'Pendientes', value: String(eventos.length), tone: 'primary', sub: 'toda la agenda' },
    { icon: Users, label: 'Reuniones', value: String(nBy('reunion')), tone: 'accent' },
    { icon: Phone, label: 'Llamadas', value: String(nBy('llamada')), tone: 'accent' },
    // Ámbar SOLO cuando hay algo vencido: un 0 sano no grita.
    nVencidas > 0
      ? { icon: AlertTriangle, label: 'Vencidas', value: String(nVencidas), tone: 'warn' }
      : { icon: AlertTriangle, label: 'Vencidas', value: '0', tone: 'default', sub: 'nada vencido' },
  ]
}

/** Reprogramar rápido: los 3 saltos del plan (posponer sin formulario).
 *  `aria` va aparte del label: "+1d" se lee "más un de" en un lector. */
const SALTOS: ReadonlyArray<{ label: string; aria: string; dias: number }> = [
  { label: '+1d', aria: '+1 día', dias: 1 },
  { label: '+3d', aria: '+3 días', dias: 3 },
  { label: '+1sem', aria: '+1 semana', dias: 7 },
]

/**
 * Instante de destino de un salto rápido, con la ventana legal ya aplicada.
 *
 * La base NO es siempre `vence_en`: sobre una tarea VENCIDA se cuenta desde
 * AHORA. Sumar sobre su fecha dejaba "+1d" de algo vencido hace 5 días todavía
 * vencido (hace 4): la tarjeta no salía de la franja de vencidas, el asesor leía
 * "Reprogramada" y volvía a pulsar — y cada pulsación inútil suma una
 * `reprogramaciones` (la métrica con la que supervisión lo juzga, visible en la
 * propia tarjeta como "movida ×N") y borra `confirmada_en`, el anti no-show.
 *
 * Sobre una tarea FUTURA la base sigue siendo su propia fecha: posponer "+1d"
 * una cita del viernes es el sábado, que es lo que el asesor espera al aplazar
 * algo que aún no vence (y no "mañana", que la ADELANTARÍA).
 *
 * `slotHabil` es el mismo normalizador del motor de la siguiente acción: ningún
 * salto puede aterrizar en domingo ni fuera de 07:00–20:00 (Ley 29571).
 *
 * No se exporta (regla `react/only-export-components`: este archivo solo exporta
 * componentes); se ejercita desde la pantalla en agenda.test.tsx.
 */
function destinoSalto(venceEn: string, dias: number, ahora: number): string {
  const vence = Date.parse(venceEn)
  // Fecha ilegible (dato corrupto) → se trata como vencida: base = ahora. Sin
  // esta guarda, un NaN llegaría a new Date(NaN).toISOString() y reventaría.
  const base = Number.isFinite(vence) && vence > ahora ? vence : ahora
  return slotHabil(base + dias * 86_400_000)
}

function TarjetaTarea({
  t,
  lead,
  ahora,
  escribe,
  esMovil,
  abrirLead,
  onCerrar,
}: {
  t: Tarea
  lead: Lead | undefined
  ahora: number
  escribe: boolean
  /** Táctil: los saltos rápidos se pintan con área de toque, nunca en hover. */
  esMovil: boolean
  abrirLead: (id: string) => void
  onCerrar: (t: Tarea) => void
}) {
  const { reprogramarTarea, confirmarTarea } = useCRMData()
  const { yo } = useAuth()
  // Supervisión: quien ve equipo necesita saber de QUIÉN es cada tarea.
  const verEquipo = can(yo?.rol, 'verEquipo')
  const ev = tareaAEvento(t, ahora)
  const hora = ev.cuando.split(' · ')[1] ?? ''
  const modalidadReunion = t.tipo === 'reunion'
    ? etiquetaModalidadReunion(t.modalidad_reunion)
    : null
  const gcal = enlaceGoogleCalendar(t)
  const recordatorio = lead && ameritaRecordatorio(t, ahora) ? enlaceRecordatorio(t, lead, ahora) : null

  const posponer = (dias: number) => {
    const destino = destinoSalto(t.vence_en, dias, ahora)
    const res = reprogramarTarea(t.id, destino)
    // El toast nombra el DÍA de destino en vez del salto pedido ("+1d"): si la
    // base fue AHORA (vencida) o la ventana legal corrió el slot, el asesor lo
    // ve — nunca vuelve a pulsar creyendo que no pasó nada (patrón de
    // FilaHigiene en hoy/vendedor.tsx, que ya anuncia "Movida al …").
    const cuando = tareaAEvento({ ...t, vence_en: destino }, ahora).cuando
    if (res.ok) toast.success(`Reprogramada — ${cuando}${yo?.demo ? ' (demo)' : ''}`)
    else toast.error(res.error ?? 'No se pudo reprogramar')
  }

  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${t.titulo}`}
      onClick={() => t.lead_id && abrirLead(t.lead_id)}
      onKeyDown={(e) => {
        // Solo teclas sobre la TARJETA misma: un Enter/Espacio en un botón
        // anidado (cerrar, confirmar, +1d…) burbujea hasta aquí, y el
        // preventDefault le robaría su click nativo — se abría la ficha del
        // lead en vez de ejecutar el botón que el asesor tenía enfocado.
        // Mismo guard que FilaHigiene en hoy/vendedor.tsx.
        if (e.target !== e.currentTarget) return
        if ((e.key === 'Enter' || e.key === ' ') && t.lead_id) {
          e.preventDefault()
          abrirLead(t.lead_id)
        }
      }}
      className="group flex cursor-pointer flex-wrap items-center gap-x-3 gap-y-1.5 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      {/* Riel de HORA a la izquierda: la clave primaria de escaneo de una
          agenda, alineada verticalmente entre filas (ámbar si venció). */}
      <span
        title={ev.cuando}
        className={cn(
          'w-12 shrink-0 text-right text-xs font-semibold tabular-nums',
          ev.vencida ? 'text-[#d97706]' : 'text-muted-foreground',
        )}
      >
        {hora || '—'}
      </span>
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
          {modalidadReunion && (
            <Badge color="var(--accent)" className="text-[10px]">
              {modalidadReunion}
            </Badge>
          )}
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
          {/* Dueño de la tarea — solo para quien supervisa (la lista del
              vendedor no necesita decirle que las tareas son suyas). */}
          {verEquipo && lead && (
            <span className="flex items-center gap-1 text-[11px] font-medium text-muted-foreground">
              <Avatar nombre={lead.vendedor_nombre} className="size-4 text-[7px]" />
              <span className="max-w-32 truncate">{lead.vendedor_nombre ?? 'Sin asignar'}</span>
            </span>
          )}
          {escribe && (
            // Reprogramar rápido, SIEMPRE alcanzable. Antes iba `hidden sm:flex`
            // y en el celular —donde el asesor de calle trabaja— no quedaba
            // NINGUNA forma de posponer una tarea: en táctil no hay hover ni
            // ancho ≥ 640 px.
            <span className="flex items-center gap-1">
              {SALTOS.map((s) => (
                <button
                  key={s.label}
                  type="button"
                  title={`Reprogramar ${s.aria}`}
                  aria-label={`Reprogramar ${s.aria} — ${t.titulo}`}
                  className={cn(
                    'cursor-pointer rounded-md font-bold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground',
                    // Escritorio: discreto, pero nunca por debajo de 24 px de
                    // alto (mínimo de WCAG 2.5.8 — y aquí el objetivo vive
                    // DENTRO de otro objetivo, la tarjeta, así que la excepción
                    // de espaciado no aplica).
                    'min-h-6 px-1.5 py-0.5 text-[10px]',
                    // Puntero GRUESO (el dedo) a cualquier ancho: celular en
                    // horizontal y tablet también son táctiles y no tienen
                    // hover. Mismo criterio de interacción que usa la fila
                    // hermana de acciones secundarias (`pointer-coarse:`).
                    'pointer-coarse:min-h-8 pointer-coarse:px-2 pointer-coarse:py-1.5 pointer-coarse:text-[11px] pointer-coarse:ring-1 pointer-coarse:ring-muted-foreground/40',
                    // Viewport angosto (incluye la ventana de escritorio a
                    // ancho de celular, donde el `hidden sm:flex` mordía).
                    esMovil && 'min-h-8 px-2 py-1.5 text-[11px] ring-1 ring-muted-foreground/40',
                  )}
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
        {/* Secundarias (recordar/confirmar/gcal): aparecen al hover o con foco
            de teclado; en táctil (sin hover) quedan siempre visibles. Las
            comerciales — contacto y cerrar — nunca se esconden. */}
        <span className="flex items-center gap-1 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 pointer-coarse:opacity-100">
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
        </span>
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
    </div>
  )
}

// ── Navegación temporal compartida (Semana/Mes) ───────────────────────────────
function NavTemporal({
  unidad,
  titulo,
  enBase,
  onPrev,
  onNext,
  onHoy,
  right,
}: {
  /** Contexto de las flechas para lectores de pantalla ("Semana anterior"…). */
  unidad: 'semana' | 'mes'
  titulo: string
  /** true = ya estamos en la semana/mes actual (deshabilita "Hoy"). */
  enBase: boolean
  onPrev: () => void
  onNext: () => void
  onHoy: () => void
  /** Slot derecho (patrón SectionHead): el resumen del período VISIBLE vive
      pegado al título que cambia al navegar. */
  right?: ReactNode
}) {
  const U = unidad === 'semana' ? 'Semana' : 'Mes'
  const flecha =
    'grid size-7 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground'
  return (
    <div className="flex items-center gap-1.5">
      <button type="button" aria-label={`${U} anterior`} className={flecha} onClick={onPrev}>
        <ChevronLeft className="size-4" aria-hidden />
      </button>
      <button type="button" aria-label={`${U} siguiente`} className={flecha} onClick={onNext}>
        <ChevronRight className="size-4" aria-hidden />
      </button>
      {/* aria-live: al navegar, el lector anuncia el período nuevo solo. */}
      <p className="text-sm font-bold tracking-tight" aria-live="polite">{titulo}</p>
      {/* Siempre montado (disabled en base): si se desmontara al llegar a hoy,
          el foco del teclado se perdería en el body. */}
      <button
        type="button"
        disabled={enBase}
        className="cursor-pointer rounded-full bg-muted px-2.5 py-1 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground disabled:cursor-default disabled:opacity-40"
        onClick={onHoy}
      >
        Hoy
      </button>
      {right != null && <div className="ml-auto">{right}</div>}
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
      aria-label={`Abrir ficha — ${t.titulo} · ${ev.cuando}`}
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
  // Una semana cargada no convierte cada día en una columna interminable.
  // El límite es deliberadamente pequeño: la vista semanal sirve para decidir
  // el ritmo, mientras que Hoy/Mes abren la bandeja detallada y operable.
  const TAREAS_SEMANA_POR_DIA = 4
  const [paginaPorDia, setPaginaPorDia] = useState<Record<string, number>>({})
  // Hora actual en Lima: el hint de ritmo se apaga en el propio día cuando
  // ambos picos (10–11:30 y 16–18) ya quedaron atrás.
  const horaLima = new Date(ahora - LIMA_OFFSET_MS).getUTCHours()
  const celdas = dias.map((d) => ({
    d,
    tareas: porDia.get(d.fecha) ?? [],
    domingo: d.dow === 0,
    // Hueco en mar–jue futuro: el mejor momento para citas (Gong: +30% de
    // asistencia). Sugerencia, jamás candado — hoy se apaga pasadas las 18:00.
    hint:
      (porDia.get(d.fecha) ?? []).length === 0 &&
      d.esMarJue &&
      !d.esPasado &&
      !(d.esHoy && horaLima >= 18),
  }))
  const tooltipDomingo = 'Domingo: fuera de la ventana legal de contacto (L–S 07:00–20:00)'
  const srDomingo = (
    <span className="sr-only"> — fuera de la ventana legal de contacto (L–S 07:00–20:00)</span>
  )
  return (
    <Card className="overflow-x-auto p-2.5">
      {/* < lg: la semana APILADA en 7 filas — cero scroll horizontal en
          laptops medianas / iPad, que era todo el punto de esta vista. */}
      <div className="space-y-1.5 lg:hidden">
        {celdas.map(({ d, tareas, domingo, hint }) => (
          (() => {
            const paginas = Math.max(1, Math.ceil(tareas.length / TAREAS_SEMANA_POR_DIA))
            const pagina = Math.min(paginaPorDia[d.fecha] ?? 0, paginas - 1)
            const tareasPagina = tareas.slice(pagina * TAREAS_SEMANA_POR_DIA, (pagina + 1) * TAREAS_SEMANA_POR_DIA)
            return <div
              key={d.fecha}
              title={domingo ? tooltipDomingo : undefined}
              className={cn(
                'rounded-lg p-2',
                d.esHoy ? 'bg-accent/10 ring-1 ring-accent/30' : 'bg-muted/30',
                domingo && 'opacity-55',
              )}
            >
            <div className="flex items-center gap-2">
              <span className={cn('text-[11px] font-bold', d.esHoy ? 'text-accent' : 'text-muted-foreground')}>
                {d.label}
                {domingo && srDomingo}
              </span>
              {tareas.length > 0 && (
                <span className="rounded-full bg-muted px-1.5 text-[10px] font-bold tabular-nums text-muted-foreground">
                  {tareas.length}
                </span>
              )}
              {hint && (
                <span className="ml-auto flex items-center gap-1 text-[10px] font-semibold text-muted-foreground">
                  <Sparkles className="size-3 text-accent/60" aria-hidden />
                  Buen día para citas · 10–11:30 · 16–18
                </span>
              )}
            </div>
            {tareas.length > 0 && (
              <div className="mt-1 grid gap-1 sm:grid-cols-2">
                {tareasPagina.map((t) => (
                  <MiniTarea key={t.id} t={t} ahora={ahora} abrir={() => t.lead_id && abrirLead(t.lead_id)} />
                ))}
              </div>
            )}
            {paginas > 1 && (
              <div className="mt-1.5 flex items-center justify-end gap-1 text-[10px] font-bold tabular-nums text-muted-foreground">
                <button
                  type="button"
                  aria-label={`Ver tareas anteriores de ${d.label}`}
                  disabled={pagina === 0}
                  onClick={() => setPaginaPorDia((actual) => ({ ...actual, [d.fecha]: pagina - 1 }))}
                  className="grid size-6 cursor-pointer place-items-center rounded border border-border bg-card disabled:cursor-default disabled:opacity-40"
                >
                  <ChevronLeft className="size-3" aria-hidden />
                </button>
                {pagina + 1}/{paginas}
                <button
                  type="button"
                  aria-label={`Ver tareas siguientes de ${d.label}`}
                  disabled={pagina + 1 >= paginas}
                  onClick={() => setPaginaPorDia((actual) => ({ ...actual, [d.fecha]: pagina + 1 }))}
                  className="grid size-6 cursor-pointer place-items-center rounded border border-border bg-card disabled:cursor-default disabled:opacity-40"
                >
                  <ChevronRight className="size-3" aria-hidden />
                </button>
              </div>
            )}
            </div>
          })()
        ))}
      </div>

      {/* lg+: rejilla de 7 columnas. El domingo — fuera de la ventana legal,
          casi siempre vacío — va en columna angosta FIJA (sin condicional al
          contenido: nada de layout-shift semana a semana), devolviendo su
          ancho a los 6 días operables. */}
      <div className="hidden min-w-[700px] gap-1.5 lg:grid lg:grid-cols-[repeat(6,minmax(0,1fr))_minmax(3rem,0.45fr)]">
        {celdas.map(({ d, tareas, domingo, hint }) => (
          (() => {
            const paginas = Math.max(1, Math.ceil(tareas.length / TAREAS_SEMANA_POR_DIA))
            const pagina = Math.min(paginaPorDia[d.fecha] ?? 0, paginas - 1)
            const tareasPagina = tareas.slice(pagina * TAREAS_SEMANA_POR_DIA, (pagina + 1) * TAREAS_SEMANA_POR_DIA)
            return <div
              key={d.fecha}
              title={domingo ? tooltipDomingo : undefined}
              className={cn(
                'flex min-h-44 flex-col gap-1 rounded-lg p-1.5',
                d.esHoy ? 'bg-accent/10 ring-1 ring-accent/30' : 'bg-muted/30',
                domingo && 'opacity-55',
              )}
            >
            <div className="flex items-center justify-between gap-1 px-0.5">
              <span className={cn('truncate text-[11px] font-bold', d.esHoy ? 'text-accent' : 'text-muted-foreground')}>
                {domingo ? `D ${d.num}` : d.label}
                {domingo && srDomingo}
              </span>
              {tareas.length > 0 && (
                <span className="rounded-full bg-muted px-1.5 text-[10px] font-bold tabular-nums text-muted-foreground">
                  {tareas.length}
                </span>
              )}
            </div>
            {tareasPagina.map((t) => (
              <MiniTarea key={t.id} t={t} ahora={ahora} abrir={() => t.lead_id && abrirLead(t.lead_id)} />
            ))}
            {hint && (
              <div className="mt-auto rounded-md border border-dashed border-accent/30 p-1.5 text-center">
                <Sparkles className="mx-auto size-3.5 text-accent/60" aria-hidden />
                <p className="mt-0.5 text-[10px] font-semibold text-muted-foreground">Buen día para citas</p>
                <p className="text-[10px] tabular-nums text-muted-foreground/80">10–11:30 · 16–18</p>
              </div>
            )}
            {paginas > 1 && (
              <div className="mt-auto flex items-center justify-end gap-1 px-0.5 pt-1 text-[10px] font-bold tabular-nums text-muted-foreground">
                <button
                  type="button"
                  aria-label={`Ver tareas anteriores de ${d.label}`}
                  disabled={pagina === 0}
                  onClick={() => setPaginaPorDia((actual) => ({ ...actual, [d.fecha]: pagina - 1 }))}
                  className="grid size-6 cursor-pointer place-items-center rounded border border-border bg-card disabled:cursor-default disabled:opacity-40"
                >
                  <ChevronLeft className="size-3" aria-hidden />
                </button>
                {pagina + 1}/{paginas}
                <button
                  type="button"
                  aria-label={`Ver tareas siguientes de ${d.label}`}
                  disabled={pagina + 1 >= paginas}
                  onClick={() => setPaginaPorDia((actual) => ({ ...actual, [d.fecha]: pagina + 1 }))}
                  className="grid size-6 cursor-pointer place-items-center rounded border border-border bg-card disabled:cursor-default disabled:opacity-40"
                >
                  <ChevronRight className="size-3" aria-hidden />
                </button>
              </div>
            )}
            </div>
          })()
        ))}
      </div>
    </Card>
  )
}

// ── Vista MES: densidad por día + día seleccionado operable ───────────────────

const CABECERA_MES = ['L', 'M', 'M', 'J', 'V', 'S', 'D']

function VistaMes({
  semanas,
  porDia,
  ahora,
  diaSel,
  onDia,
}: {
  semanas: CeldaMes[][]
  porDia: ReadonlyMap<string, Tarea[]>
  ahora: number
  diaSel: string | null
  onDia: (fecha: string) => void
}) {
  const celda = (c: CeldaMes) => {
    const tareas = porDia.get(c.fecha) ?? []
    // La MISMA derivada canónica de todo el CRM (vence_en < ahora): cubre
    // también las vencidas de HOY, que "día pasado" dejaba en gris.
    const nVencidas = tareas.filter((t) => Date.parse(t.vence_en) < ahora).length
    const tipos = Array.from(new Set(tareas.map((t) => t.tipo))).slice(0, 3)
    const activa = diaSel === c.fecha
    return (
      <button
        key={c.fecha}
        type="button"
        aria-label={`${c.label} — ${tareas.length} ${tareas.length === 1 ? 'tarea' : 'tareas'}${
          nVencidas > 0 ? `, ${nVencidas} vencida${nVencidas === 1 ? '' : 's'}` : ''
        }`}
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
            {/* El triángulo es el canal NO cromático de "hay vencidas". */}
            {nVencidas > 0 && <AlertTriangle className="size-2.5" style={{ color: '#d97706' }} aria-hidden />}
            <span
              className="text-[10px] font-bold tabular-nums"
              style={{ color: nVencidas > 0 ? '#d97706' : 'var(--muted-foreground)' }}
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
        {/* Decorativa (dos "M" idénticas): cada celda ya anuncia su día completo. */}
        {CABECERA_MES.map((d, i) => (
          <span key={i} aria-hidden className="pb-1 text-center text-[10px] font-bold uppercase text-muted-foreground">
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

/** Agrupa tareas (ya cronológicas) por su etiqueta de día ("Vencida", "Hoy"…). */
function agruparPorDiaLabel(tareas: Tarea[], ahora: number): { dia: string; items: Tarea[] }[] {
  const out: { dia: string; items: Tarea[] }[] = []
  for (const t of tareas) {
    const dia = tareaAEvento(t, ahora).cuando.split(' · ')[0] ?? 'Sin fecha'
    const g = out.find((x) => x.dia === dia)
    if (g) g.items.push(t)
    else out.push({ dia, items: [t] })
  }
  return out
}

/** La cola operable no crece junto con la página. */
const TAREAS_POR_PAGINA = 12
const PERSONAS_POR_PAGINA = 8

function NavegacionPagina({
  pagina,
  total,
  porPagina,
  etiqueta,
  onCambiar,
}: {
  pagina: number
  total: number
  porPagina: number
  etiqueta: string
  onCambiar: (pagina: number) => void
}) {
  const paginas = Math.max(1, Math.ceil(total / porPagina))
  if (total === 0) return null
  const inicio = pagina * porPagina + 1
  const fin = Math.min(total, inicio + porPagina - 1)
  return (
    <nav className="flex shrink-0 items-center justify-between gap-2 border-t border-border/70 pt-2" aria-label={`Paginación de ${etiqueta}`}>
      <p className="text-[11px] font-semibold tabular-nums text-muted-foreground" aria-live="polite">
        {inicio}–{fin} de {total} {etiqueta}
      </p>
      {paginas > 1 && (
        <span className="flex items-center gap-1.5">
          <button
            type="button"
            aria-label={`Ver página anterior de ${etiqueta}`}
            disabled={pagina === 0}
            onClick={() => onCambiar(pagina - 1)}
            className="grid size-7 cursor-pointer place-items-center rounded-lg border border-border bg-card text-muted-foreground transition-colors hover:text-foreground disabled:cursor-default disabled:opacity-40"
          >
            <ChevronLeft className="size-3.5" aria-hidden />
          </button>
          <span className="text-[10px] font-bold tabular-nums text-muted-foreground">
            {pagina + 1}/{paginas}
          </span>
          <button
            type="button"
            aria-label={`Ver página siguiente de ${etiqueta}`}
            disabled={pagina + 1 >= paginas}
            onClick={() => onCambiar(pagina + 1)}
            className="grid size-7 cursor-pointer place-items-center rounded-lg border border-border bg-card text-muted-foreground transition-colors hover:text-foreground disabled:cursor-default disabled:opacity-40"
          >
            <ChevronRight className="size-3.5" aria-hidden />
          </button>
        </span>
      )}
    </nav>
  )
}

export function Agenda() {
  const { ambito, tareas, equipo } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  const ahora = useAhora()
  const escribe = puedeEscribir(yo?.rol)
  // Una sola suscripción a matchMedia para TODA la lista (la agenda pinta
  // decenas de tarjetas): el hook vive aquí y baja como prop.
  const esMovil = useEsMovil()
  // Supervisor/gerencia/directorio: la agenda se agrupa por PERSONA, no por día
  // — imposible supervisar una lista plana con las tareas de 20 anónimos.
  const verEquipo = can(yo?.rol, 'verEquipo')
  const [vista, setVista] = useState<Vista>('hoy')
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  const [filtros, setFiltros] = useState<FiltrosAgenda>(FILTROS_APAGADOS)
  const [mostrarFiltros, setMostrarFiltros] = useState(false)
  const [offsetSemana, setOffsetSemana] = useState(0)
  const [offsetMes, setOffsetMes] = useState(0)
  const [diaSel, setDiaSel] = useState<string | null>(null)
  // La página es por tarea para vendedor y por persona para supervisión: ambos
  // conservan el mismo tope visual sin disfrazar una cola enorme como pantalla.
  const [paginaBandeja, setPaginaBandeja] = useState(0)
  const [paginaMes, setPaginaMes] = useState(0)
  // Supervisión abre el detalle cuando lo necesita; ese detalle desplaza dentro
  // de su propia tarjeta para no estirar la agenda completa.
  const [personasAbiertas, setPersonasAbiertas] = useState<ReadonlySet<string>>(new Set())

  // Ámbito (espejo RLS): solo tareas de leads que el rol puede ver.
  const idsAmbito = useMemo(() => new Set(ambito.leads.map((l) => l.id)), [ambito.leads])
  // Lookup O(1): aplicarFiltros lo llama por CADA tarea en cada pulsación del
  // buscador — con la cartera de gerencia un find lineal se vuelve cuadrático.
  const leadPorId = useMemo(() => {
    const porId = new Map(ambito.leads.map((l) => [l.id, l] as const))
    return (id: string | null): Lead | undefined => (id ? porId.get(id) : undefined)
  }, [ambito.leads])

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
  // Conteo para el chip "Filtros · n": con la banda colapsada, lo activo se ve.
  const nFiltrosActivos = [
    filtros.q.trim() !== '',
    filtros.tipo !== 'todos',
    filtros.estado !== 'todas',
    filtros.etapa !== 'todas',
  ].filter(Boolean).length

  // [Hoy] = vencidas + las de hoy (el día operable); [Todo] = panorama por día.
  const delDia = useMemo(
    () => filtrados.filter((t) => {
      const ev = tareaAEvento(t, ahora)
      return ev.vencida || esDeHoy(ev, ahora)
    }),
    [filtrados, ahora],
  )
  const visibles = vista === 'hoy' ? delDia : filtrados
  const grupos = useMemo(() => agruparPorDiaLabel(visibles, ahora), [visibles, ahora])
  // Supervisión: las mismas tareas visibles, pero por dueño (vencidas y carga
  // primero — donde se acumula el problema). El vendedor no pasa por aquí.
  const gruposPersona = useMemo(
    () => (verEquipo ? agruparPorPersona(visibles, leadPorId, equipo, ahora) : []),
    [verEquipo, visibles, leadPorId, equipo, ahora],
  )
  const porPaginaBandeja = verEquipo ? PERSONAS_POR_PAGINA : TAREAS_POR_PAGINA
  const totalBandeja = verEquipo ? gruposPersona.length : visibles.length
  const paginasBandeja = Math.max(1, Math.ceil(totalBandeja / porPaginaBandeja))
  const paginaBandejaActual = Math.min(paginaBandeja, paginasBandeja - 1)
  const inicioBandeja = paginaBandejaActual * porPaginaBandeja
  const gruposPagina = useMemo(
    () => agruparPorDiaLabel(visibles.slice(inicioBandeja, inicioBandeja + TAREAS_POR_PAGINA), ahora),
    [visibles, inicioBandeja, ahora],
  )
  const gruposPersonaPagina = gruposPersona.slice(inicioBandeja, inicioBandeja + PERSONAS_POR_PAGINA)
  // Distribución por tipo del rango visible en [Todo] — el resumen del muro.
  const distTipos = useMemo(
    () =>
      TIPOS_TAREA.map(({ k, label }) => ({
        label,
        value: filtrados.filter((t) => t.tipo === k).length,
        color: COLOR_EVENTO[k],
      })),
    [filtrados],
  )

  // Geometría de las vistas nuevas (Fase D) — todo derivado del reloj vivo.
  const semana = useMemo(() => diasDeSemana(ahora, offsetSemana), [ahora, offsetSemana])
  const mes = useMemo(() => rejillaMes(ahora, offsetMes), [ahora, offsetMes])
  const porDia = useMemo(() => tareasPorDia(filtrados), [filtrados])
  // Resumen del período VISIBLE (Semana/Mes): el StatStrip de arriba cuenta la
  // agenda completa y NO cambia al navegar — este número sí, y por eso vive
  // pegado al título que cambia (slot derecho de NavTemporal).
  const resumenSemana = useMemo(() => {
    let n = 0
    let v = 0
    for (const d of semana) {
      for (const t of porDia.get(d.fecha) ?? []) {
        n++
        if (Date.parse(t.vence_en) < ahora) v++
      }
    }
    return { n, v }
  }, [semana, porDia, ahora])
  const resumenMes = useMemo(() => {
    let n = 0
    let v = 0
    for (const c of mes.semanas.flat()) {
      if (!c.delMes) continue
      for (const t of porDia.get(c.fecha) ?? []) {
        n++
        if (Date.parse(t.vence_en) < ahora) v++
      }
    }
    return { n, v }
  }, [mes, porDia, ahora])
  const tiraSemana = useMemo(() => diasDeSemana(ahora, 0), [ahora])
  // Día operable del Mes: el elegido, o hoy cuando se mira el mes en curso.
  const diaMes = diaSel ?? (offsetMes === 0 ? fechaLima(ahora) : null)
  const tareasDiaMes = diaMes ? porDia.get(diaMes) ?? [] : []
  const paginasMes = Math.max(1, Math.ceil(tareasDiaMes.length / TAREAS_POR_PAGINA))
  const paginaMesActual = Math.min(paginaMes, paginasMes - 1)
  const tareasDiaMesPagina = tareasDiaMes.slice(
    paginaMesActual * TAREAS_POR_PAGINA,
    (paginaMesActual + 1) * TAREAS_POR_PAGINA,
  )
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
        // Solo con el foco "libre" (body): si el usuario tabuló a un botón o
        // está dentro del grid desplazable, las flechas conservan su función
        // nativa (scroll/foco) — preventDefault aquí rompería el teclado.
        if (e.target !== document.body) return
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

  const patch = (p: Partial<FiltrosAgenda>) => {
    setPaginaBandeja(0)
    setFiltros((f) => ({ ...f, ...p }))
  }

  return (
    <div className="mx-auto flex min-h-0 max-w-[1240px] flex-col gap-5 ac-rise md:h-full">
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
                aria-current={c.esHoy ? 'date' : undefined}
                onClick={() => {
                  setOffsetSemana(0)
                  setVista('semana')
                  setPaginaBandeja(0)
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
            onClick={() => {
              setVista(v.k)
              setPaginaBandeja(0)
            }}
            className={cn(
              'cursor-pointer rounded-full px-3 py-1.5 text-xs font-bold transition-colors',
              vista === v.k ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground',
            )}
          >
            {v.label}
          </button>
        ))}
        {/* Filtros COLAPSADOS tras un chip: la banda solo baja la cola del día
            cuando de verdad se está filtrando. El conteo delata lo activo. */}
        <button
          type="button"
          aria-expanded={mostrarFiltros}
          aria-controls="agenda-filtros"
          onClick={() => setMostrarFiltros((v) => !v)}
          className={cn(
            'ml-auto flex cursor-pointer items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-bold transition-colors',
            mostrarFiltros || conFiltros
              ? 'bg-primary text-primary-foreground'
              : 'bg-muted text-muted-foreground hover:text-foreground',
          )}
        >
          <SlidersHorizontal className="size-3.5" aria-hidden />
          Filtros{nFiltrosActivos > 0 ? ` · ${nFiltrosActivos}` : ''}
        </button>
        {/* Limpiar vive FUERA de la banda: visible aun con filtros colapsados. */}
        {conFiltros && (
          <button
            type="button"
            onClick={() => {
              setPaginaBandeja(0)
              setFiltros(FILTROS_APAGADOS)
            }}
            className="flex cursor-pointer items-center gap-1 rounded-full bg-muted px-2.5 py-1.5 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground"
          >
            <X className="size-3" aria-hidden /> Limpiar · {filtrados.length} de {pendientes.length}
          </button>
        )}
      </div>

      {/* Buscador + filtros tipo/estado/etapa — recortan TODAS las vistas */}
      {mostrarFiltros && (
      <div id="agenda-filtros" className="flex flex-wrap items-center gap-2">
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
      </div>
      )}

      {/* El encabezado queda estable. Solo la bandeja cambia de contenido y,
          en escritorio, se desplaza dentro de este espacio en vez de alargar
          toda la pantalla. */}
      <div className="ac-scroll min-h-0 space-y-5 md:flex-1 md:overflow-y-auto md:pr-1">
      {/* ── SEMANA ── */}
      {vista === 'semana' && (
        <>
          <NavTemporal
            unidad="semana"
            titulo={tituloSemana(semana)}
            enBase={offsetSemana === 0}
            onPrev={() => setOffsetSemana((o) => o - 1)}
            onNext={() => setOffsetSemana((o) => o + 1)}
            onHoy={() => setOffsetSemana(0)}
            right={
              <Badge color={resumenSemana.v > 0 ? '#d97706' : resumenSemana.n > 0 ? 'var(--accent)' : 'var(--muted-foreground)'}>
                {resumenSemana.n === 0
                  ? 'Sin tareas esta semana'
                  : `${resumenSemana.n} ${resumenSemana.n === 1 ? 'tarea' : 'tareas'}${
                      resumenSemana.v > 0 ? ` · ${resumenSemana.v} vencida${resumenSemana.v === 1 ? '' : 's'}` : ''
                    }`}
              </Badge>
            }
          />
          <VistaSemana dias={semana} porDia={porDia} ahora={ahora} abrirLead={abrirLead} />
        </>
      )}

      {/* ── MES ── */}
      {vista === 'mes' && (
        <>
          <NavTemporal
            unidad="mes"
            titulo={mes.titulo}
            enBase={offsetMes === 0}
            onPrev={() => {
              setOffsetMes((o) => o - 1)
              setDiaSel(null)
              setPaginaMes(0)
            }}
            onNext={() => {
              setOffsetMes((o) => o + 1)
              setDiaSel(null)
              setPaginaMes(0)
            }}
            onHoy={() => {
              setOffsetMes(0)
              setDiaSel(null)
              setPaginaMes(0)
            }}
            right={
              <Badge color={resumenMes.v > 0 ? '#d97706' : resumenMes.n > 0 ? 'var(--accent)' : 'var(--muted-foreground)'}>
                {resumenMes.n === 0
                  ? 'Sin tareas este mes'
                  : `${resumenMes.n} ${resumenMes.n === 1 ? 'tarea' : 'tareas'}${
                      resumenMes.v > 0 ? ` · ${resumenMes.v} vencida${resumenMes.v === 1 ? '' : 's'}` : ''
                    }`}
              </Badge>
            }
          />
          <VistaMes
            semanas={mes.semanas}
            porDia={porDia}
            ahora={ahora}
            diaSel={diaMes}
            onDia={(fecha) => {
              setDiaSel(fecha)
              setPaginaMes(0)
            }}
          />
          {diaMes ? (
            <Card className="flex min-h-0 flex-col">
              {/* Mes/año salen de la FECHA elegida, no de la rejilla: una
                  celda de relleno (1 de agosto en julio) titula su mes real. */}
              <SectionHead
                icon={CalendarDays}
                title={
                  celdaDiaMes
                    ? `${celdaDiaMes.label} — ${MESES[Number(diaMes.slice(5, 7)) - 1]} ${diaMes.slice(0, 4)}`
                    : diaMes
                }
                right={
                  tareasDiaMes.length > 0 ? (
                    <Badge color="var(--accent)">
                      {tareasDiaMes.length} {tareasDiaMes.length === 1 ? 'tarea' : 'tareas'}
                    </Badge>
                  ) : undefined
                }
              />
              <CardContent className="ac-scroll min-h-0 space-y-1 overflow-y-auto pt-0 md:max-h-[min(27rem,calc(100svh-29rem))]">
                {tareasDiaMes.length === 0 ? (
                  <PanelVacio
                    icono={CalendarDays}
                    titulo="Sin tareas ese día"
                    detalle="Agenda la próxima acción desde la ficha de un lead — ningún lead activo debería quedarse sin una."
                  />
                ) : (
                  tareasDiaMesPagina.map((t) => (
                    <TarjetaTarea
                      key={t.id}
                      t={t}
                      lead={leadPorId(t.lead_id)}
                      ahora={ahora}
                      escribe={escribe}
                      esMovil={esMovil}
                      abrirLead={abrirLead}
                      onCerrar={setTareaACerrar}
                    />
                  ))
                )}
              </CardContent>
              <div className="px-5 pb-4">
                <NavegacionPagina
                  pagina={paginaMesActual}
                  total={tareasDiaMes.length}
                  porPagina={TAREAS_POR_PAGINA}
                  etiqueta="tareas del día"
                  onCambiar={setPaginaMes}
                />
              </div>
            </Card>
          ) : (
            <Card>
              <PanelVacio
                icono={CalendarDays}
                titulo="Elige un día del mes"
                detalle="Toca cualquier día de la rejilla para ver y trabajar sus tareas."
              />
            </Card>
          )}
        </>
      )}

      {/* ── HOY / TODO ── */}
      {(vista === 'hoy' || vista === 'todo') && (
        <>
          {/* [Todo] Resumen del rango: de qué se compone el panorama, antes
              de bajar al muro de días. */}
          {vista === 'todo' && visibles.length > 0 && (
            <Card className="ac-pop p-3.5">
              <SegmentBar segments={distTipos} />
            </Card>
          )}

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

          {/* Supervisión: agrupado por PERSONA (vencidas y carga primero),
              colapsado a resumen — el detalle se abre solo cuando hace falta,
              igual que la tabla por rangos de Distribución de leads. */}
          {verEquipo &&
            gruposPersonaPagina.map((g) => {
              const abierto = personasAbiertas.has(g.id)
              return (
                <Card key={g.id}>
                  <button
                    type="button"
                    aria-expanded={abierto}
                    onClick={() =>
                      setPersonasAbiertas((prev) => {
                        const s = new Set(prev)
                        if (s.has(g.id)) s.delete(g.id)
                        else s.add(g.id)
                        return s
                      })
                    }
                    className="flex w-full cursor-pointer items-center gap-2.5 rounded-t-[inherit] px-5 pt-4 pb-3 text-left transition-colors hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                  >
                    <Avatar nombre={g.nombre} className="size-7 text-[10px]" />
                    <span className="min-w-0">
                      <span className="block truncate text-[15px] font-bold tracking-tight">{g.nombre}</span>
                      {g.supervisor && (
                        <span className="block truncate text-[11px] text-muted-foreground">
                          Equipo de {g.supervisor}
                        </span>
                      )}
                    </span>
                    <span className="ml-auto flex shrink-0 items-center gap-1.5">
                      <Badge color="var(--accent)">
                        {g.items.length} {g.items.length === 1 ? 'tarea' : 'tareas'}
                      </Badge>
                      {g.nVencidas > 0 && (
                        <Badge color="#d97706">
                          {g.nVencidas} vencida{g.nVencidas === 1 ? '' : 's'}
                        </Badge>
                      )}
                      <ChevronDown
                        className={cn('size-4 text-muted-foreground transition-transform', abierto && 'rotate-180')}
                        aria-hidden
                      />
                    </span>
                  </button>
                  {abierto && (
                    <CardContent className="ac-scroll max-h-80 space-y-2 overflow-y-auto pt-0">
                      {agruparPorDiaLabel(g.items, ahora).map((sub) => (
                        <div key={sub.dia} className="space-y-1">
                          <p
                            className={cn(
                              'px-2 text-[11px] font-bold',
                              sub.dia === 'Vencida' ? 'text-[#d97706]' : 'text-muted-foreground',
                            )}
                          >
                            {sub.dia === 'Vencida' ? 'Vencidas' : sub.dia}
                          </p>
                          {sub.items.map((t) => (
                            <TarjetaTarea
                              key={t.id}
                              t={t}
                              lead={leadPorId(t.lead_id)}
                              ahora={ahora}
                              escribe={escribe}
                              esMovil={esMovil}
                              abrirLead={abrirLead}
                              onCerrar={setTareaACerrar}
                            />
                          ))}
                        </div>
                      ))}
                    </CardContent>
                  )}
                </Card>
              )
            })}

          {/* Vendedor: timeline operable agrupado por día. La paginación es
              por tarea, así que la cola conserva su orden sin crear un muro
              de cards iguales al abrir Todo. */}
          {!verEquipo &&
            gruposPagina.map((g) => {
              return (
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
                        esMovil={esMovil}
                        abrirLead={abrirLead}
                        onCerrar={setTareaACerrar}
                      />
                    ))}
                  </CardContent>
                </Card>
              )
            })}
          {grupos.length > 0 && (
            <NavegacionPagina
              pagina={paginaBandejaActual}
              total={totalBandeja}
              porPagina={porPaginaBandeja}
              etiqueta={verEquipo ? 'personas' : 'tareas'}
              onCambiar={setPaginaBandeja}
            />
          )}
        </>
      )}

      </div>

      <p className="shrink-0 text-[11px] text-muted-foreground">
        La agenda es real: cerrar una tarea registra el resultado en el timeline y te propone la siguiente;
        “Recordar” manda un WhatsApp que pide confirmación de la cita.
        <span className="hidden md:inline"> Atajos: 1–4 cambian de vista · ←/→ navegan semana y mes · H vuelve a hoy.</span>
      </p>

      <CerrarTareaDialog tarea={tareaACerrar} onCerrar={() => setTareaACerrar(null)} />
    </div>
  )
}
