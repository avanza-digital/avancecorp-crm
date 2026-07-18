// Hoy · VENDEDOR (F1c) — la pantalla diaria del asesor: SU cartera, SU cola de
// acción y SU meta. ambito.leads YA viene recortado por el store (solo los
// suyos), así que aquí no hay ni ranking ni datos de otros vendedores — ni en
// los totales. Semáforos sin verde: azul ok · ámbar atención · rojo crítico.
import { useEffect, useMemo, useState, type CSSProperties, type JSX, type ReactNode } from 'react'
import { toast } from 'sonner'
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import {
  AlertTriangle,
  CalendarClock,
  CalendarDays,
  ChevronRight,
  CircleCheckBig,
  ClipboardList,
  FileText,
  MessageCircle,
  Phone,
  Sparkles,
  Target,
  TrendingUp,
  Trophy,
  Users,
  Wallet,
  Zap,
  type LucideIcon,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import { SectionHead } from '@/components/common/section-head'
import { KpiCard } from '@/components/common/kpi-card'
import { AnimatedValue } from '@/components/common/animated-value'
import { AccionesContacto } from '@/components/app/contacto'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import {
  BUCKET_LABEL,
  capitalPorMoneda,
  colaDe,
  colorMeta,
  diasDesdeReferencia,
  diasTxt,
  haceTexto,
  pctMeta,
  type ItemCola,
} from '@/lib/inteligencia'
import { colaHigiene, esViernesDeHigiene, siguienteMarJue, type ItemHigiene } from '@/lib/agenda-vistas'
import { tareaAEvento } from '@/lib/agenda-derivada'
import { useTipoCambio, usdAPen, type TipoCambio } from '@/lib/tipo-cambio'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { TIPO_EVENTO, type Lead, type Tarea } from '@/lib/tipos'
import type { EventoAgenda } from '@/lib/store'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { money, moneyK, primerNombre } from '@/lib/format'

// ── Helpers puros ─────────────────────────────────────────────────────────────

/** Fecha larga es-PE con la primera letra en mayúscula (sobre el reloj vivo).
 * En Lima SIEMPRE: con la TZ del navegador, un viernes 22:00 de Lima visto
 * desde otra zona diría "Sábado…" mientras la cola anuncia viernes de higiene. */
function fechaLarga(ahora: number): string {
  const s = new Date(ahora).toLocaleDateString('es-PE', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    timeZone: 'America/Lima',
  })
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// ── Meta del mes (animaciones sutiles + USD convertido) ───────────────────────

// Respeta prefers-reduced-motion: sin animación de barras para quien la desactiva.
const PREFERS_REDUCED =
  typeof window !== 'undefined' &&
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true

/** Barra que arranca en 0 y sube a `pct` al montar (aprovecha la transición de
 * ancho de <Progress>). Micro-animación sutil; instantánea con reduced-motion. */
function useProgresoAnimado(pct: number): number {
  const [v, setV] = useState(PREFERS_REDUCED ? pct : 0)
  useEffect(() => {
    if (PREFERS_REDUCED) {
      setV(pct)
      return
    }
    const id = requestAnimationFrame(() => setV(pct))
    return () => cancelAnimationFrame(id)
  }, [pct])
  return v
}

/** Una fila de la meta: chip de icono + label + valor actual (contador) arriba;
 * barra que sube sola; abajo "% del objetivo" + la meta a la derecha. El color
 * (chip/barra/pct) es el semáforo del avance. */
function MetaFila({
  icon: Icon,
  label,
  valorTxt,
  metaTxt,
  pct,
  delay,
  nota,
}: {
  icon: LucideIcon
  label: string
  valorTxt: string
  metaTxt: string
  pct: number
  delay: number
  nota?: ReactNode
}): JSX.Element {
  const color = colorMeta(pct)
  const pctAnimado = useProgresoAnimado(pct)
  return (
    <div className="ac-rise" style={{ animationDelay: `${delay}ms` }}>
      <div className="flex items-center gap-2">
        <span
          className="ac-chip grid size-6 shrink-0 place-items-center rounded-lg [&_svg]:size-3.5"
          style={{ '--c': color } as CSSProperties}
        >
          <Icon aria-hidden />
        </span>
        <p className="min-w-0 flex-1 truncate text-xs font-semibold text-foreground/80">{label}</p>
        <p className="shrink-0 text-sm font-extrabold tabular-nums" style={{ color }}>
          <AnimatedValue value={valorTxt} />
        </p>
      </div>
      <Progress value={pctAnimado} color={color} className="mt-1.5" />
      <div className="mt-1 flex items-baseline justify-between gap-2 text-[11px] tabular-nums text-muted-foreground">
        <span>
          <AnimatedValue value={`${Math.round(pct)}%`} /> del objetivo
        </span>
        <span>meta {metaTxt}</span>
      </div>
      {nota && <div className="mt-1.5">{nota}</div>}
    </div>
  )
}

/** Nota bajo el capital: cómo entró el USD a la meta (convertido a soles), o que
 * queda pendiente de tipo de cambio (modo real sin fuente conectada aún). */
function NotaUSD({
  capUSD,
  enPEN,
  tc,
}: {
  capUSD: number
  enPEN: number
  tc: TipoCambio | null
}): JSX.Element | null {
  if (capUSD <= 0) return null
  if (!tc) {
    return (
      <p className="text-[11px] text-muted-foreground">
        Tienes {moneyK(capUSD, 'USD')} en dólares — pendiente de tipo de cambio para sumarlos a la meta.
      </p>
    )
  }
  return (
    <p className="text-[11px] text-muted-foreground">
      Incluye {moneyK(capUSD, 'USD')} → {moneyK(enPEN)} al TC {tc.fuente} S/ {tc.promedio.toFixed(3)}.
    </p>
  )
}

// ── Agenda de hoy (HÉROE del vendedor) ────────────────────────────────────────
// Lógica comercial: el día del asesor lo manda su agenda — dónde estar y qué
// vence hoy es lo que gana (o pierde) ingreso HOY; por eso es el protagonista.
// Cada evento muestra el CAPITAL en juego de su lead y los vencimientos se
// marcan (una propuesta que vence = dinero a punto de enfriarse).

const ICONO_EVENTO: Record<string, LucideIcon> = {
  reunion: Users,
  llamada: Phone,
  whatsapp: MessageCircle,
  tarea: ClipboardList,
  vencimiento: AlertTriangle,
}

// El orden ES el timestamp: vence_en asc pone las VENCIDAS primero (regla de
// la investigación: nadie esconde vencidas) y el resto cronológico.

/** Una cita de la agenda: hora (ancla) + tipo + título + CAPITAL en juego. */
function FilaAgenda({
  ev,
  lead,
  abrirLead,
  onCompletar,
}: {
  ev: EventoAgenda
  lead: Lead | undefined
  abrirLead: (id: string) => void
  onCompletar?: ((id: string) => void) | undefined
}): JSX.Element {
  const [dia, hora] = ev.cuando.split(' · ')
  const Icono = ICONO_EVENTO[ev.tipo] ?? CalendarDays
  const abrir = () => abrirLead(ev.lead_id)
  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${ev.titulo}`}
      onClick={abrir}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          abrir()
        }
      }}
      className="group flex cursor-pointer items-center gap-3 rounded-xl p-2.5 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      {/* Hora — el ancla del día */}
      <div className="w-12 shrink-0 text-center leading-none">
        <p className="text-base font-extrabold tabular-nums" style={{ color: ev.color }}>
          {hora ?? dia}
        </p>
        {hora && <p className="mt-1 text-[10px] font-medium text-muted-foreground">{dia}</p>}
      </div>
      <span className="w-1 self-stretch rounded" style={{ background: ev.color, minHeight: 46 }} aria-hidden />
      <span
        className="ac-chip grid size-9 shrink-0 place-items-center rounded-lg [&_svg]:size-[18px]"
        style={{ '--c': ev.color } as CSSProperties}
      >
        <Icono aria-hidden />
      </span>
      <div className="min-w-0 flex-1 leading-tight">
        <p className="truncate text-[13px] font-semibold">{ev.titulo}</p>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <Badge color={ev.color} className="text-[10px]">
            {TIPO_EVENTO[ev.tipo] ?? ev.tipo}
          </Badge>
          {lead?.monto_estimado != null && (
            <span className="text-[11px] font-semibold tabular-nums text-muted-foreground">
              {money(lead.monto_estimado, lead.moneda)} en juego
            </span>
          )}
        </div>
      </div>
      {onCompletar && (
        <button
          type="button"
          aria-label={`Cerrar tarea — ${ev.titulo}`}
          title="Cerrar tarea (registra el resultado y agenda la siguiente)"
          className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground"
          onClick={(e) => {
            e.stopPropagation()
            onCompletar(ev.id)
          }}
        >
          <CircleCheckBig className="size-4" aria-hidden />
        </button>
      )}
      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </div>
  )
}

/** Vacío honesto + útil: sin calendario real todavía, encamina a las señales
 * comerciales que SÍ tenemos (reuniones agendadas, propuestas por responder). */
function AgendaVacia({
  demo,
  nReuniones,
  nPropuestas,
}: {
  demo: boolean
  nReuniones: number
  nPropuestas: number
}): JSX.Element {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-2 py-10 text-center">
      <CalendarDays className="size-8 text-muted-foreground/60" />
      <p className="text-sm font-bold">Sin citas para hoy</p>
      <p className="max-w-[44ch] text-xs text-muted-foreground">
        {demo
          ? 'Agenda tareas desde la ficha de un lead y aparecerán aquí.'
          : 'Agenda la próxima acción desde la ficha de un lead — ningún lead activo debería quedarse sin una.'}
      </p>
      {(nReuniones > 0 || nPropuestas > 0) && (
        <p className="text-[11px] font-semibold text-foreground/70">
          {nReuniones > 0 && `${nReuniones} ${nReuniones === 1 ? 'reunión agendada' : 'reuniones agendadas'}`}
          {nReuniones > 0 && nPropuestas > 0 && ' · '}
          {nPropuestas > 0 &&
            `${nPropuestas} ${nPropuestas === 1 ? 'propuesta por responder' : 'propuestas por responder'}`}
        </p>
      )}
    </div>
  )
}

function AgendaHoy({
  eventos,
  leadPorId,
  abrirLead,
  onCompletar,
  demo,
  nReuniones,
  nPropuestas,
  className,
}: {
  eventos: EventoAgenda[]
  leadPorId: (id: string) => Lead | undefined
  abrirLead: (id: string) => void
  onCompletar?: ((id: string) => void) | undefined
  demo: boolean
  nReuniones: number
  nPropuestas: number
  className?: string
}): JSX.Element {
  const ordenados = [...eventos].sort((a, b) => a.vence_en.localeCompare(b.vence_en))
  const nHoy = eventos.filter((e) => e.cuando.startsWith('Hoy')).length
  const nVence = eventos.filter((e) => e.vencida).length
  // Capital en juego HOY = citas de hoy + vencidas que siguen esperando
  // (dedupe por lead; PEN y USD SIEMPRE por separado).
  const leadsHoy = Array.from(new Set(
    eventos.filter((e) => e.cuando.startsWith('Hoy') || e.vencida).map((e) => e.lead_id),
  ))
    .map(leadPorId)
    .filter((l): l is Lead => l != null)
  const { pen, usd } = capitalPorMoneda(leadsHoy)

  return (
    <Card className={className}>
      <SectionHead
        icon={CalendarDays}
        title="Tu agenda de hoy"
        right={
          nHoy > 0 || nVence > 0 ? (
            <Badge color={nVence > 0 ? '#d97706' : 'var(--accent)'}>
              {nHoy} hoy{nVence > 0 ? ` · ${nVence} vencida${nVence === 1 ? '' : 's'}` : ''}
            </Badge>
          ) : undefined
        }
      />
      <CardContent className="flex flex-1 flex-col pt-0">
        {eventos.length === 0 ? (
          <AgendaVacia demo={demo} nReuniones={nReuniones} nPropuestas={nPropuestas} />
        ) : (
          <>
            {(pen > 0 || usd > 0) && (
              <div className="mb-3 flex flex-wrap items-center gap-x-2 gap-y-1 rounded-lg bg-muted/50 px-3 py-2.5 text-xs">
                <Wallet className="size-4 text-muted-foreground" />
                <span className="font-semibold text-foreground/80">En juego hoy:</span>
                {pen > 0 && <span className="font-bold tabular-nums text-primary">{money(pen)}</span>}
                {usd > 0 && <span className="font-bold tabular-nums text-primary">· {money(usd, 'USD')}</span>}
              </div>
            )}
            {/* Citas centradas en el alto disponible → llenan la tarjeta sin hueco. */}
            <div className="flex flex-1 flex-col justify-center gap-1.5">
              {ordenados.map((ev) => (
                <FilaAgenda key={ev.id} ev={ev} lead={leadPorId(ev.lead_id)} abrirLead={abrirLead} onCompletar={onCompletar} />
              ))}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

export function HoyVendedor(): JSX.Element {
  const { ambito, actividades, agenda: agendaGlobal, tareas, objetivos, reprogramarTarea } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  // Motor (Fase B): tarea seleccionada para cerrar desde la agenda héroe.
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  // Reloj vivo: re-tick por minuto y al volver a la pestaña — entra como
  // dependencia de la cola para que los "hace X" y semáforos se refresquen solos.
  const ahora = useAhora()

  // Universo del asesor — ambito.leads ya es SOLO su cartera.
  const mios = ambito.leads.filter((l) => l.activo)
  const abiertos = mios.filter((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado')
  const convertidos = mios.filter((l) => l.etapa === 'convertido')
  const propuestas = abiertos.filter((l) => l.etapa === 'propuesta_enviada')

  // Capital en proceso — PEN y USD SIEMPRE por separado (jamás un total mixto).
  const { pen: capPEN, usd: capUSD } = capitalPorMoneda(abiertos)
  // …salvo para la META: el USD cuenta CONVERTIDO a soles al TC promedio de la
  // semana. La regla sigue viva (no se suman crudos): capMeta es soles + soles.
  const tc = useTipoCambio()
  const capUSDenPEN = usdAPen(capUSD, tc?.promedio ?? 0)
  const capMeta = capPEN + capUSDenPEN

  // Meta del mes: objetivos demo estáticos vs actuales calculados de SUS leads.
  // Misma semántica que supervisor/gerencia: capital EN PROCESO (PEN) vs objetivo.
  const meta = objetivos.vendedor
  // Sin meta configurada (objetivo 0): no inventamos cuotas — mostramos "por definir".
  const sinMeta = meta.capitalObjetivo <= 0 && meta.ventasObjetivo <= 0
  const conversion = mios.length > 0 ? Math.round((convertidos.length / mios.length) * 100) : 0

  // Cola de acción personal (el ámbito del vendedor no trae parkeados).
  // Fase B: los leads CON tarea pendiente ya tienen plan — su cola es la
  // agenda; aquí solo quedan speed-to-lead y los que se quedaron sin plan.
  const conTarea = useMemo(
    () => new Set(tareas.filter((t) => t.estado === 'pendiente' && t.activo && t.lead_id).map((t) => t.lead_id as string)),
    [tareas],
  )
  const cola = useMemo(
    () => colaDe(ambito.leads, actividades, ahora, undefined, conTarea),
    [ambito.leads, actividades, ahora, conTarea],
  )

  // Agenda demo recortada a SUS leads.
  const idsMios = new Set(mios.map((l) => l.id))
  const agenda = agendaGlobal.filter((ev) => idsMios.has(ev.lead_id))

  // Modo "viernes 13:00" (Fase D): viernes p.m. es el peor momento para citas
  // nuevas → la cola deja de perseguir y ORDENA la próxima semana (vencidas,
  // reagendas de no-show fuera de mar–jue, leads sin próxima acción). El
  // speed-to-lead NUNCA se entierra: los "sin responder" siguen arriba.
  const higiene = esViernesDeHigiene(ahora)
  const colaVisible = higiene ? cola.filter((i) => i.bucket === 'sin_responder') : cola
  // Los leads que la cola ya pinta (speed-to-lead) se excluyen de los
  // amarillos — sin esto el mismo lead saldría dos veces y el badge contaría
  // doble. El filtro por idsMios es el espejo RLS; v1 solo opera tareas de
  // lead (las de cliente/perfil_id llegan con la fase de postventa).
  const itemsHigiene = higiene
    ? colaHigiene(
        tareas.filter((t) => t.lead_id && idsMios.has(t.lead_id)),
        ambito.leads,
        conTarea,
        ahora,
        new Set(colaVisible.map((i) => i.lead.id)),
      )
    : []
  const tareasHigiene = itemsHigiene.filter(
    (i): i is Extract<ItemHigiene, { k: 'vencida' | 'no_show_fuera_ritmo' }> => i.k !== 'sin_accion',
  )
  const amarillos = itemsHigiene.filter((i): i is Extract<ItemHigiene, { k: 'sin_accion' }> => i.k === 'sin_accion')
  const AMARILLOS_VISIBLES = 8
  const nCola = colaVisible.length + (higiene ? itemsHigiene.length : 0)
  // Lookup de lead por id (capital en juego de cada cita) + señales reales para
  // el vacío honesto de la agenda (mientras no exista calendario real).
  const leadPorId = (id: string): Lead | undefined => mios.find((l) => l.id === id)
  const reunionesAgendadas = abiertos.filter((l) => l.etapa === 'reunion_agendada').length

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Saludo del día */}
      <div>
        <h2 className="text-lg font-extrabold tracking-tight text-primary">
          Hola, {primerNombre(yo?.nombre_completo) || 'asesor'}
        </h2>
        <p className="text-xs text-muted-foreground">
          {fechaLarga(ahora)} · Tu cartera y tus pendientes — solo ves lo tuyo
        </p>
      </div>

      {/* KPIs personales — capital PEN con el USD aparte (nunca sumados) */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard
          label="Capital en proceso"
          value={money(capPEN)}
          icon={Wallet}
          color="#2563eb"
          sub={capUSD > 0 ? `Pipeline activo (PEN) · +${moneyK(capUSD, 'USD')} aparte` : 'Pipeline activo (PEN)'}
          delay={0}
        />
        <KpiCard
          label="Leads activos"
          value={String(abiertos.length)}
          icon={Users}
          color="#7c3aed"
          sub="Abiertos en tu cartera"
          delay={60}
        />
        <KpiCard
          label="Propuestas enviadas"
          value={String(propuestas.length)}
          icon={FileText}
          color="#d97706"
          sub="Esperando respuesta del cliente"
          delay={120}
        />
        <KpiCard
          label="Convertidos"
          value={String(convertidos.length)}
          icon={Trophy}
          color="#111e3d"
          sub="Histórico · clientes ganados"
          delay={180}
        />
      </div>

      {/* Héroe + cola — lógica comercial: la AGENDA (dónde estar / qué vence hoy)
          manda el día del vendedor; la cola es a quién perseguir en los huecos. */}
      <div className="grid gap-5 lg:grid-cols-5">
        <AgendaHoy
          eventos={agenda}
          leadPorId={leadPorId}
          abrirLead={abrirLead}
          onCompletar={(id) => {
            const t = tareas.find((x) => x.id === id)
            if (t) setTareaACerrar(t)
          }}
          demo={yo?.demo ?? false}
          nReuniones={reunionesAgendadas}
          nPropuestas={propuestas.length}
          className="flex flex-col lg:col-span-3"
        />
        {/* Cola de acción personal — el viernes desde las 13:00 (Lima) cambia
            a higiene de pipeline: ordenar la próxima semana, no perseguir. */}
        <Card className="lg:col-span-2">
          <SectionHead
            icon={higiene ? Sparkles : Zap}
            title={higiene ? 'Viernes de higiene' : 'Tu siguiente acción hoy'}
            right={
              nCola > 0 ? (
                <Badge color={higiene ? '#d97706' : 'var(--accent)'}>
                  {nCola} {nCola === 1 ? 'pendiente' : 'pendientes'}
                </Badge>
              ) : undefined
            }
          />
          <CardContent className="space-y-1.5 pt-0">
            {higiene && nCola > 0 && (
              <p className="rounded-lg bg-muted/50 px-3 py-2 text-[11px] text-muted-foreground">
                Viernes p.m. rinde poco para citas nuevas — deja la próxima semana ordenada: cierra lo
                vencido, mueve los no-shows a mar–jue y que ningún lead quede sin próxima acción.
              </p>
            )}
            {nCola === 0 ? (
              <div className="flex flex-col items-center gap-2 py-10 text-center">
                <CircleCheckBig className="size-8 text-accent" />
                <p className="text-sm font-bold">{higiene ? 'Pipeline limpio ✦' : 'Al día ✦ sin pendientes'}</p>
                <p className="text-xs text-muted-foreground">
                  {higiene
                    ? 'Nada vencido, no-shows en su sitio y toda tu cartera con próxima acción. Buen fin de semana.'
                    : 'No tienes leads esperando respuesta ni seguimientos vencidos.'}
                </p>
              </div>
            ) : (
              <>
                {colaVisible.map((item) => (
                  <FilaCola key={item.lead.id} item={item} abrirLead={abrirLead} ahora={ahora} />
                ))}
                {tareasHigiene.map((item) => (
                  <FilaHigiene
                    key={item.tarea.id}
                    item={item}
                    lead={item.tarea.lead_id ? leadPorId(item.tarea.lead_id) : undefined}
                    ahora={ahora}
                    abrirLead={abrirLead}
                    onCerrar={() => setTareaACerrar(item.tarea)}
                    onMarJue={() => {
                      const destino = siguienteMarJue(ahora)
                      const res = reprogramarTarea(item.tarea.id, destino)
                      if (res.ok) {
                        const cuando = tareaAEvento({ ...item.tarea, vence_en: destino }, ahora).cuando
                        toast.success(`Movida al ${cuando}${yo?.demo ? ' (demo)' : ''}`)
                      } else toast.error(res.error ?? 'No se pudo mover')
                    }}
                  />
                ))}
                {amarillos.slice(0, AMARILLOS_VISIBLES).map((item) => (
                  <FilaAmarillo key={item.lead.id} lead={item.lead} abrirLead={abrirLead} />
                ))}
                {amarillos.length > AMARILLOS_VISIBLES && (
                  <p className="px-2 text-[11px] text-muted-foreground">
                    +{amarillos.length - AMARILLOS_VISIBLES} más sin próxima acción — trabájalos desde Cartera.
                  </p>
                )}
              </>
            )}
          </CardContent>
        </Card>

      </div>

      {/* Meta del mes — franja compacta full-width: es el marcador, no una acción. */}
      <Card>
        <SectionHead
          icon={Target}
          title="Tu meta del mes"
          right={<span className="text-[11px] text-muted-foreground">{yo?.demo ? 'objetivos demo' : 'objetivo mensual'}</span>}
        />
        <CardContent className="pt-0">
          {sinMeta ? (
            <div className="space-y-2">
              <div className="flex items-baseline justify-between gap-2">
                <p className="text-xs font-semibold text-foreground/80">Capital en proceso</p>
                <p className="text-xs font-bold tabular-nums">
                  <AnimatedValue value={moneyK(capMeta)} />
                </p>
              </div>
              <div className="flex items-baseline justify-between gap-2">
                <p className="text-xs font-semibold text-foreground/80">Ventas cerradas</p>
                <p className="text-xs font-bold tabular-nums">{convertidos.length}</p>
              </div>
              <NotaUSD capUSD={capUSD} enPEN={capUSDenPEN} tc={tc} />
              <p className="text-[11px] text-muted-foreground">
                Meta mensual por definir — cuando la establezcan, verás aquí tu avance.
              </p>
            </div>
          ) : (
            <div className="grid gap-x-8 gap-y-4 md:grid-cols-3">
              <MetaFila
                icon={Wallet}
                label="Capital"
                valorTxt={moneyK(capMeta)}
                metaTxt={moneyK(meta.capitalObjetivo)}
                pct={pctMeta(capMeta, meta.capitalObjetivo)}
                delay={0}
                nota={<NotaUSD capUSD={capUSD} enPEN={capUSDenPEN} tc={tc} />}
              />
              <MetaFila
                icon={Trophy}
                label="Ventas cerradas"
                valorTxt={String(convertidos.length)}
                metaTxt={String(meta.ventasObjetivo)}
                pct={pctMeta(convertidos.length, meta.ventasObjetivo)}
                delay={90}
              />
              <MetaFila
                icon={TrendingUp}
                label="Conversión"
                valorTxt={`${conversion}%`}
                metaTxt={`${meta.conversionObjetivo}%`}
                pct={pctMeta(conversion, meta.conversionObjetivo)}
                delay={180}
              />
            </div>
          )}
        </CardContent>
      </Card>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} únicamente tu propia cartera; cada asesor trabaja solo con sus leads.
      </p>

      {/* Motor Fase B: cierre 1-tap + siguiente sugerida desde la agenda héroe. */}
      <CerrarTareaDialog tarea={tareaACerrar} onCerrar={() => setTareaACerrar(null)} />
    </div>
  )
}

// ── Fila de la cola de acción ─────────────────────────────────────────────────
// Dot de severidad + badge del bucket + motivo (con días) + acciones reales
// (AccionesContacto: tel:/wa.me con registro del resultado) + abrir ficha.
// El propio componente corta la propagación para no abrir la ficha al
// llamar/escribir.

function FilaCola({
  item,
  abrirLead,
  ahora,
}: {
  item: ItemCola
  abrirLead: (id: string) => void
  ahora?: number | undefined
}): JSX.Element {
  const c = SEV_COLOR[item.sev]
  const abrir = () => abrirLead(item.lead.id)
  // Speed-to-lead (evidencia: contactar cae ~100x entre el minuto 5 y el 30):
  // para un lead SIN primer contacto el reloj se muestra en MINUTOS con
  // semáforo, no en días — cumplir minutos es la ventaja más barata que hay.
  const minutos = item.bucket === 'sin_responder' && ahora != null
    ? Math.max(0, Math.floor((ahora - Date.parse(item.lead.creado_en)) / 60_000))
    : null
  const cronometro = minutos != null && minutos < 24 * 60
    ? {
        texto: minutos < 60 ? `${minutos} min` : `${Math.floor(minutos / 60)} h ${minutos % 60} m`,
        color: minutos <= 5 ? '#16a34a' : minutos <= 15 ? '#d97706' : '#dc2626',
      }
    : null
  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${item.lead.nombre_completo}`}
      onClick={abrir}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          abrir()
        }
      }}
      className="group flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <span className="size-2.5 shrink-0 rounded-full" style={{ background: c }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          <LeadHoverCard lead={item.lead}>
            <p className="truncate text-sm font-semibold">{item.lead.nombre_completo}</p>
          </LeadHoverCard>
          <Badge color={c} className="text-[10px]">
            {BUCKET_LABEL[item.bucket]}
          </Badge>
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{item.motivo}</p>
      </div>
      {cronometro ? (
        <span
          className="hidden shrink-0 rounded-md px-1.5 py-0.5 text-[11px] font-bold tabular-nums sm:block"
          style={{ color: cronometro.color, background: `color-mix(in srgb, ${cronometro.color} 12%, transparent)` }}
          title="Tiempo desde que entró el lead — contactar en minutos multiplica el contacto"
        >
          {cronometro.texto}
        </span>
      ) : (
        <span className="hidden shrink-0 text-[11px] font-semibold tabular-nums text-muted-foreground sm:block">
          {diasTxt(item.dias)}
        </span>
      )}
      <AccionesContacto lead={item.lead} compacto soloIcono />
      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </div>
  )
}

// ── Filas del modo "viernes de higiene" (Fase D) ──────────────────────────────
// Cada ítem lleva su acción obvia a un toque: vencida → cerrarla (resultado +
// siguiente); reagenda de no-show fuera de mar–jue → moverla al siguiente
// mar–jue 10:00 (la franja que sí asiste); amarillo → abrir la ficha y
// agendarle la próxima acción.

function FilaHigiene({
  item,
  lead,
  ahora,
  abrirLead,
  onCerrar,
  onMarJue,
}: {
  item: Extract<ItemHigiene, { k: 'vencida' | 'no_show_fuera_ritmo' }>
  lead: Lead | undefined
  ahora: number
  abrirLead: (id: string) => void
  onCerrar: () => void
  onMarJue: () => void
}): JSX.Element {
  const t = item.tarea
  const vencida = item.k === 'vencida'
  const c = vencida ? SEMAFORO.critico : SEMAFORO.violeta
  const abrir = () => t.lead_id && abrirLead(t.lead_id)
  const motivo = vencida
    ? `Venció ${haceTexto(diasDesdeReferencia(t.vence_en, ahora))} — ciérrala o reprográmala`
    : `Reagendada tras no-show — cae ${tareaAEvento(t, ahora).cuando}, mejor mar–jue`
  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${t.titulo}`}
      onClick={abrir}
      onKeyDown={(e) => {
        // Solo teclas sobre la FILA: un Enter en los botones anidados burbujea
        // hasta aquí y el preventDefault les robaría su click nativo.
        if (e.target !== e.currentTarget) return
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          abrir()
        }
      }}
      className="group flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <span className="size-2.5 shrink-0 rounded-full" style={{ background: c }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          {lead ? (
            <LeadHoverCard lead={lead}>
              <p className="truncate text-sm font-semibold">{t.titulo}</p>
            </LeadHoverCard>
          ) : (
            <p className="truncate text-sm font-semibold">{t.titulo}</p>
          )}
          <Badge color={c} className="text-[10px]">{vencida ? 'Vencida' : 'No-show'}</Badge>
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{motivo}</p>
      </div>
      {vencida ? (
        <button
          type="button"
          title="Cerrar tarea (registra el resultado y agenda la siguiente)"
          aria-label={`Cerrar tarea — ${t.titulo}`}
          className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground"
          onClick={(e) => {
            e.stopPropagation()
            onCerrar()
          }}
        >
          <CircleCheckBig className="size-4" aria-hidden />
        </button>
      ) : (
        <button
          type="button"
          title="Mover al siguiente mar–jue a las 10:00 (la franja que sí asiste)"
          aria-label={`Mover a martes–jueves — ${t.titulo}`}
          className="shrink-0 cursor-pointer rounded-md px-2 py-1 text-[10px] font-bold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          onClick={(e) => {
            e.stopPropagation()
            onMarJue()
          }}
        >
          <CalendarClock className="mr-0.5 inline size-3" aria-hidden />→ mar–jue
        </button>
      )}
      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </div>
  )
}

/** Amarillo del semáforo: lead abierto SIN próxima acción — la lista inocultable. */
function FilaAmarillo({ lead, abrirLead }: { lead: Lead; abrirLead: (id: string) => void }): JSX.Element {
  const abrir = () => abrirLead(lead.id)
  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${lead.nombre_completo}`}
      onClick={abrir}
      onKeyDown={(e) => {
        // Mismo guard que FilaHigiene: no robarle Enter/Espacio a AccionesContacto.
        if (e.target !== e.currentTarget) return
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          abrir()
        }
      }}
      className="group flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <span className="size-2.5 shrink-0 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          <LeadHoverCard lead={lead}>
            <p className="truncate text-sm font-semibold">{lead.nombre_completo}</p>
          </LeadHoverCard>
          <Badge color={SEMAFORO.atencion} className="text-[10px]">Sin próxima acción</Badge>
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">
          {money(lead.monto_estimado, lead.moneda)} en juego — agéndale el siguiente paso
        </p>
      </div>
      <AccionesContacto lead={lead} compacto soloIcono />
      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </div>
  )
}
