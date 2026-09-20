import { abrirInversionista } from '@/lib/router'
import { SlaOperacionBoundary } from '@/components/app/sla-operacion'
import { useModoSla } from '@/data/sla-operacion-queries'
// Hoy · ANALISTA (F1c) — la pantalla diaria del analista: SU cartera, SU cola de
// acción y SU meta. ambito.leads YA viene recortado por el store (solo los
// suyos), así que aquí no hay ni ranking ni datos de otros analistas — ni en
// los totales. Semáforos sin verde: azul ok · ámbar atención · rojo crítico.
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type JSX,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
} from 'react'
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
  Plus,
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
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { SectionHead } from '@/components/common/section-head'
import { PanelVacio } from '@/components/common/estado-panel'
import { AnimatedValue } from '@/components/common/animated-value'
import { AccionesContacto } from '@/components/app/contacto'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import {
  BUCKET_LABEL,
  capitalPorMoneda,
  capitalPrincipal,
  colorMeta,
  diasDesdeReferencia,
  diasTxt,
  haceTexto,
  pctMeta,
  type ItemCola,
} from '@/lib/inteligencia'
import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { planPorLead } from '@/lib/plan-lead'
import { colaHigiene, esViernesDeHigiene, siguienteMarJue, type ItemHigiene } from '@/lib/agenda-vistas'
import { agendaDeTareas, esDeHoy, fechaLima, tareaAEvento, type EventoAgenda } from '@/lib/agenda-derivada'
import { capitalObjetivo, metaVigente, capitalReal, metaConversionAplicable, objetivosCero, periodoLima } from '@/lib/objetivos'
import { useConversionMensual, useLeadsPropios } from '@/data/crm-queries'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import { descuentoArrastre, lecturaCobertura, lineaProcedencia } from '@/lib/conversion-mensual'
import { ChipArrastre } from '@/components/common/chip-arrastre'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { TIPO_EVENTO, type Lead, type Tarea } from '@/lib/tipos'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { money, moneyK, numero, porcentajeConversionCanonica, primerNombre } from '@/lib/format'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import { useTipoCambio } from '@/lib/tipo-cambio'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { seleccionarPrioridadesVendedor, type PrioridadVendedor } from './prioridades-vendedor'
import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'

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

// ── Cumplimiento del mes (animaciones sutiles) ────────────────────────────────

// Respeta prefers-reduced-motion: sin animación de barras para quien la desactiva.
const PREFERS_REDUCED =
  typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true

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

/** Motivo neutro más frecuente: gerencia no fijó ESA meta del mes. Constante
 * porque lo usan las tres filas y el texto tiene que ser idéntico. */
const SIN_META = 'Sin meta fijada para este mes'

/** Una fila de la meta: chip de icono + label + valor actual (contador) arriba;
 * barra que sube sola; abajo "% del objetivo" + la meta a la derecha. El color
 * (chip/barra/pct) es el semáforo del avance.
 *
 * `neutro` = por qué esta fila NO se puede juzgar todavía (el texto que se pinta
 * en lugar de la barra). Dos casos, misma cura: gerencia dejó ESA meta en blanco
 * (objetivo 0), o el indicador aún no tiene con qué calcularse (conversión sin
 * nada resuelto en el mes). En los dos el semáforo se cortocircuitaba solo:
 * `pctMeta(x, 0)` —y `pctMeta(0, y)`— devuelven 0, y `colorMeta(0)` es ROJO
 * CRÍTICO, así que una meta que nadie fijó, o un mes recién estrenado, se leían
 * como un incumplimiento grave del analista. Sin dato ≠ incumplido. */
function MetaFila({
  icon: Icon,
  label,
  valorTxt,
  metaTxt,
  pct,
  delay,
  nota,
  neutro,
}: {
  icon: LucideIcon
  label: string
  valorTxt: string
  metaTxt: string
  pct: number
  delay: number
  nota?: ReactNode
  neutro?: string | undefined
}): JSX.Element {
  const sinObjetivo = neutro != null
  const color = sinObjetivo ? 'var(--muted-foreground)' : colorMeta(pct)
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
      {sinObjetivo ? (
        <p className="mt-1.5 text-[11px] text-muted-foreground">{neutro}</p>
      ) : (
        <>
          <Progress value={pctAnimado} color={color} className="mt-1.5" />
          <div className="mt-1 flex items-baseline justify-between gap-2 text-[11px] tabular-nums text-muted-foreground">
            <span>
              <AnimatedValue value={`${Math.round(pct)}%`} /> del objetivo
            </span>
            <span>meta {metaTxt}</span>
          </div>
        </>
      )}
      {nota && <div className="mt-1.5">{nota}</div>}
    </div>
  )
}

/**
 * Sub-línea del capital consolidado: cuánto entró en cada moneda y a qué tasa se
 * unificó. Va DEBAJO del total y no al lado a propósito — el analista mira una
 * cifra, y el desglose está para responder «¿de dónde sale?», no para competir
 * con ella.
 *
 * Los tres estados de `totalEnSoles` se dicen en voz alta:
 *   · `convertido` → «S/ X + US$ Y · TC S/ Z (fuente)»: la tasa que DE VERDAD
 *     entró en el número, leída del resultado y no del TC que se creía tener.
 *   · `solo_pen`   → el USD existe pero no hubo tasa: se muestra aparte y con la
 *     advertencia, porque el total de arriba NO lo incluye. Callarlo haría que
 *     el analista leyera su avance como completo cuando le falta media moneda.
 *   · `indisponible` → no hay nada que desglosar todavía.
 */
function DesgloseCapital({
  capital,
  fuenteTc,
}: {
  capital: ReturnType<typeof totalEnSoles>
  fuenteTc: string | null
}): JSX.Element | null {
  if (capital.estado === 'indisponible') return null
  const soloPen = capital.estado === 'solo_pen'
  const hayUsd = (capital.usd ?? 0) > 0
  // Sin dólares, el desglose repetiría el total: se calla.
  if (!hayUsd) return null
  return (
    <p className="text-[11px] tabular-nums text-muted-foreground">
      {moneyK(capital.pen ?? 0, 'PEN')} + {moneyK(capital.usd ?? 0, 'USD')}
      {soloPen || capital.tc == null ? (
        <span className="text-warning-text"> · sin tipo de cambio: el total NO incluye los dólares</span>
      ) : (
        <span> · {rotuloTipoCambio(capital.tc, fuenteTc ?? 'TC del día')}</span>
      )}
    </p>
  )
}

// ── Agenda de hoy (HÉROE del analista) ────────────────────────────────────────
// Lógica comercial: el día del analista lo manda su agenda — dónde estar y qué
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

/** Cuántas vencidas LISTA de verdad la franja ámbar (el resto colapsa en
 * "+N más"). Vive fuera de <AgendaHoy> porque la cola de al lado necesita el
 * mismo número: solo puede callarse los leads que la agenda está mostrando. */
const VENCIDAS_VISIBLES = 3

/** Las vencidas que la franja ámbar pinta REALMENTE, en su mismo orden y con
 * su mismo corte. Única fuente de verdad del anti-duplicado agenda↔cola: si
 * la cola escondiera TODAS las vencidas, las que caen bajo el "+N más" se
 * perderían de la pantalla (la agenda no las pinta y la cola tampoco), y con
 * ellas el motivo y el capital en juego que solo la cola sabe calificar. */
function vencidasListadas(eventos: EventoAgenda[]): EventoAgenda[] {
  return eventos
    .filter((e) => e.vencida)
    .sort((a, b) => a.vence_en.localeCompare(b.vence_en))
    .slice(0, VENCIDAS_VISIBLES)
}

/**
 * El pie del "+N más vencidas" — y por qué NO puede prometer la cola de al lado
 * sin haberlo comprobado.
 *
 * EL DEFECTO QUE CIERRA (pedido de Miguel, 2026-07-26): este pie decía SIEMPRE
 * "las tienes en la cola de al lado", y para las vencidas de HOY era falso. La
 * agenda marca «vencida» por HORA (`tareaAEvento`, lib/agenda-derivada) y el
 * plan de un lead muere por DÍA (`planPorLead`, lib/plan-lead): una tarea que
 * venció hoy a las 09:00 ya es vencida arriba y sigue siendo plan VIGENTE
 * abajo, así que `colaDe` salta a ese lead y su fila NO existe. El analista leía
 * "+2 más vencidas — las tienes en la cola" sobre una cola que, encima, se
 * declaraba sin pendientes.
 *
 * Los dos criterios se dejan como están porque los dos son correctos, y son
 * respuestas a preguntas DISTINTAS: la agenda responde "¿ya pasó la hora?" (una
 * llamada de las 09:00 a las 15:00 llegó tarde, y esconderlo sería peor) y el
 * plan responde "¿este lead tiene dueño de su siguiente paso?" — que se contesta
 * por día a propósito, para que el analista ordene su jornada como quiera y la
 * cola no sea un eco minuto a minuto de la agenda (ver la REGLA en
 * lib/plan-lead.ts, compartida con `tareaQueCierra` y consumida por cuatro
 * pantallas más el botón Agendar). Lo único que mentía era la frase, y es la
 * frase la que se corrige: `abajo` es cuántas de esas vencidas pinta DE VERDAD
 * la mitad de abajo de la pantalla, contadas por quien puede saberlo.
 */
function textoRestoVencidas(resto: number, abajo: number): string {
  if (abajo <= 0) return `+${resto} más vencidas — ábrelas desde Agenda.`
  if (abajo >= resto) return `+${resto} más vencidas — las tienes en la cola de al lado y en Agenda.`
  return `+${resto} más vencidas — ${abajo} en la cola de al lado; todas en Agenda.`
}

// Fila base COMÚN de agenda/cola/higiene/amarillos: mismo ritmo vertical
// (p-2.5 · rounded-lg · título text-sm) entre las dos tarjetas vecinas — cada
// fila solo varía su ancla izquierda (hora vs dot) y su metadato derecho.
const FILA_BASE =
  'group flex cursor-pointer items-center gap-3 rounded-lg p-2.5 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'

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
  const abreFichaLead = ev.lead_id !== '' || Boolean(ev.inversionista_id)
  const abrir = () => {
    if (ev.inversionista_id) abrirInversionista(ev.inversionista_id)
    else if (ev.lead_id) abrirLead(ev.lead_id)
  }
  const interaccionFicha = abreFichaLead
    ? {
        role: 'button' as const,
        tabIndex: 0,
        'aria-label': `Abrir ficha — ${ev.titulo}`,
        onClick: abrir,
        onKeyDown: (e: ReactKeyboardEvent<HTMLDivElement>) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            abrir()
          }
        },
      }
    : {}
  return (
    <div
      {...interaccionFicha}
      className={`${FILA_BASE}${abreFichaLead ? '' : ' cursor-default hover:bg-transparent'}`}
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
        <p className="truncate text-sm font-semibold">{ev.titulo}</p>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <Badge color={ev.color} className="text-[10px]">
            {TIPO_EVENTO[ev.tipo] ?? ev.tipo}
          </Badge>
          {ev.perfil_id && (
            <Badge color="var(--primary)" className="text-[10px]">
              Cliente
            </Badge>
          )}
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
      {abreFichaLead && (
        <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
      )}
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
          ? 'Agenda tareas desde la ficha de un lead o un cliente y aparecerán aquí.'
          : 'Agenda la próxima acción desde la ficha de un lead o desde Mi cartera para un cliente.'}
      </p>
      {(nReuniones > 0 || nPropuestas > 0) && (
        <p className="text-[11px] font-semibold text-foreground/70">
          {nReuniones > 0 && `${nReuniones} ${nReuniones === 1 ? 'cita agendada' : 'citas agendadas'}`}
          {nReuniones > 0 && nPropuestas > 0 && ' · '}
          {nPropuestas > 0 &&
            `${nPropuestas} ${nPropuestas === 1 ? 'entrevista por cerrar' : 'entrevistas por cerrar'}`}
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
  vencidasAbajo,
  className,
  title = 'Tu agenda de hoy',
}: {
  eventos: EventoAgenda[]
  leadPorId: (id: string) => Lead | undefined
  abrirLead: (id: string) => void
  onCompletar?: ((id: string) => void) | undefined
  demo: boolean
  nReuniones: number
  nPropuestas: number
  /** Cuántas de las vencidas que NO caben en la franja pinta la mitad de abajo
   *  de la pantalla (cola + higiene). Solo la pantalla puede saberlo, y sin ese
   *  dato el pie no puede prometer nada (ver `textoRestoVencidas`). */
  vencidasAbajo: number
  className?: string
  title?: string
}): JSX.Element {
  const ordenados = [...eventos].sort((a, b) => a.vence_en.localeCompare(b.vence_en))
  const nHoy = eventos.filter((e) => e.cuando.startsWith('Hoy')).length
  const nVence = eventos.filter((e) => e.vencida).length
  // Vencidas como GRUPO (inocultables, pero sin robarle protagonismo a HOY):
  // franja ámbar arriba con las más viejas + capital en juego; debajo la
  // cronología limpia del día con su hora como ancla.
  const vencidas = ordenados.filter((e) => e.vencida)
  const alDia = ordenados.filter((e) => !e.vencida)
  // Las filas que se pintan salen del MISMO helper que consulta la cola: si
  // este corte y el de allá se separaran, o se duplicaría una vencida o se
  // perdería de las dos superficies.
  const visibles = vencidasListadas(eventos)
  const leadsVencidos = Array.from(new Set(vencidas.map((e) => e.lead_id)))
    .map(leadPorId)
    .filter((l): l is Lead => l != null)
  const { pen: penVenc, usd: usdVenc } = capitalPorMoneda(leadsVencidos)
  // Capital en juego HOY = citas de hoy + vencidas que siguen esperando
  // (dedupe por lead; PEN y USD SIEMPRE por separado).
  const leadsHoy = Array.from(
    new Set(eventos.filter((e) => e.cuando.startsWith('Hoy') || e.vencida).map((e) => e.lead_id)),
  )
    .map(leadPorId)
    .filter((l): l is Lead => l != null)
  const { pen, usd } = capitalPorMoneda(leadsHoy)

  return (
    <Card className={className}>
      <SectionHead
        icon={CalendarDays}
        title={title}
        right={
          nHoy > 0 || nVence > 0 ? (
            <Badge color={nVence > 0 ? '#d97706' : 'var(--accent)'}>
              {nHoy} hoy
              {nVence > 0 ? ` · ${nVence} vencida${nVence === 1 ? '' : 's'}` : ''}
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
            {/* Vencidas agrupadas: presionan sin mezclarse con la cronología. */}
            {vencidas.length > 0 && (
              <div className="mb-3 space-y-1 rounded-lg bg-warning/10 p-1.5">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-1.5 pt-1 text-xs">
                  <AlertTriangle className="size-4 shrink-0 text-warning" aria-hidden />
                  <Badge color={SEMAFORO.atencion}>
                    {vencidas.length} {vencidas.length === 1 ? 'vencida' : 'vencidas'}
                  </Badge>
                  {(penVenc > 0 || usdVenc > 0) && (
                    <span className="font-semibold tabular-nums text-muted-foreground">
                      {penVenc > 0 && money(penVenc)}
                      {penVenc > 0 && usdVenc > 0 && ' + '}
                      {usdVenc > 0 && money(usdVenc, 'USD')} en juego
                    </span>
                  )}
                </div>
                {visibles.map((ev) => (
                  <FilaAgenda
                    key={ev.id}
                    ev={ev}
                    lead={leadPorId(ev.lead_id)}
                    abrirLead={abrirLead}
                    onCompletar={onCompletar}
                  />
                ))}
                {vencidas.length > visibles.length && (
                  <p className="px-2.5 pb-1 text-[11px] text-muted-foreground">
                    {textoRestoVencidas(vencidas.length - visibles.length, vencidasAbajo)}
                  </p>
                )}
              </div>
            )}
            {/* Cronología de HOY anclada arriba: ancla de lectura estable; el
                remanente se llena con un pie accionable de bajo peso, no con aire. */}
            <div className="flex flex-1 flex-col justify-start gap-1.5">
              {alDia.map((ev) => (
                <FilaAgenda
                  key={ev.id}
                  ev={ev}
                  lead={leadPorId(ev.lead_id)}
                  abrirLead={abrirLead}
                  onCompletar={onCompletar}
                />
              ))}
              {alDia.length <= 2 && (
                <div className="mt-auto flex flex-col items-center gap-1 pb-2 pt-6 text-center">
                  <p className="text-xs text-muted-foreground">
                    {alDia.length === 0 ? 'Sin citas para hoy' : 'Día con espacio'} — agenda la siguiente acción desde
                    una ficha de lead o desde Mi cartera.
                  </p>
                  {(nReuniones > 0 || nPropuestas > 0) && (
                    <p className="text-[11px] font-semibold text-foreground/70">
                      {nReuniones > 0 &&
                        `${nReuniones} ${nReuniones === 1 ? 'cita agendada' : 'citas agendadas'}`}
                      {nReuniones > 0 && nPropuestas > 0 && ' · '}
                      {nPropuestas > 0 &&
                        `${nPropuestas} ${nPropuestas === 1 ? 'entrevista por cerrar' : 'entrevistas por cerrar'}`}
                    </p>
                  )}
                </div>
              )}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

/** Postventa no entra al motor de prioridades de leads: tiene su propia franja
 * para que una reunión con un cliente nunca se pierda ni altere SLA, etapas o
 * capital estimado del pipeline. Cerrar aquí escribe el historial del cliente. */
function AgendaClientesHoy({
  eventos,
  abrirLead,
  onCompletar,
}: {
  eventos: EventoAgenda[]
  abrirLead: (id: string) => void
  onCompletar: (id: string) => void
}): JSX.Element | null {
  if (eventos.length === 0) return null
  const vencidas = eventos.filter((evento) => evento.vencida).length

  return (
    <Card className="border-primary/20">
      <SectionHead
        icon={CalendarClock}
        title="Clientes por gestionar hoy"
        right={
          <Badge color={vencidas > 0 ? '#d97706' : 'var(--primary)'}>
            {eventos.length} {eventos.length === 1 ? 'gestión' : 'gestiones'}
            {vencidas > 0 ? ` · ${vencidas} vencida${vencidas === 1 ? '' : 's'}` : ''}
          </Badge>
        }
      />
      <CardContent className="ac-scroll max-h-80 space-y-1 overflow-y-auto pt-0">
        {eventos.map((evento) => (
          <FilaAgenda key={evento.id} ev={evento} lead={undefined} abrirLead={abrirLead} onCompletar={onCompletar} />
        ))}
        <p className="px-2 pt-1 text-[11px] text-muted-foreground">
          Gestiones creadas desde Mi cartera · también están disponibles en Agenda.
        </p>
      </CardContent>
    </Card>
  )
}

// ── Franja «Ahora» ───────────────────────────────────────────────────────────
// La firma visual del analista: una hoja de llamada compacta, ordenada y con
// máximo tres decisiones. No es otro resumen de alertas: las filas elevadas se
// retiran de Agenda/Cola para que una persona no aparezca dos veces en la vista.

function TarjetaPrioridad({
  prioridad,
  indice,
  lead,
  abrirLead,
  onCompletar,
}: {
  prioridad: PrioridadVendedor
  indice: number
  lead: Lead | undefined
  abrirLead: (id: string) => void
  onCompletar: (id: string) => void
}): JSX.Element {
  const esCola = prioridad.fuente === 'cola'
  const item = esCola ? prioridad.item : null
  const evento = esCola ? null : prioridad.evento
  const leadFinal = item?.lead ?? lead
  const color = item ? SEV_COLOR[item.sev] : evento?.vencida ? SEMAFORO.atencion : SEMAFORO.ok
  const etiqueta = item ? BUCKET_LABEL[item.bucket] : evento?.vencida ? 'Vencida' : (evento?.cuando ?? 'Agenda')
  const titulo = leadFinal?.nombre_completo ?? evento?.titulo ?? 'Acción pendiente'
  const accionAgenda = evento?.titulo.split(' — ')[0]
  const detalleAgenda = accionAgenda ?? TIPO_EVENTO[evento?.tipo ?? ''] ?? 'Seguimiento'
  const capitalTxt = leadFinal?.monto_estimado != null ? money(leadFinal.monto_estimado, leadFinal.moneda) : null

  return (
    <article className="relative flex min-h-52 flex-col overflow-hidden rounded-xl border border-white/15 bg-white p-4 text-foreground shadow-[0_18px_38px_-28px_rgba(2,8,23,0.9)]">
      <span className="absolute inset-y-0 left-0 w-1" style={{ background: color }} aria-hidden />
      <div className="flex items-center justify-between gap-3 pl-1">
        <span className="text-[10px] font-bold uppercase tracking-[0.16em] text-muted-foreground">
          Prioridad {String(indice + 1).padStart(2, '0')}
        </span>
        <Badge color={color} className="text-[10px]">
          {etiqueta}
        </Badge>
      </div>
      <div className="mt-3 pl-1">
        <p className="line-clamp-2 text-base font-extrabold leading-tight tracking-tight text-primary">{titulo}</p>
        <p className="mt-2 line-clamp-2 text-xs leading-relaxed text-muted-foreground">
          {item ? (
            item.motivo
          ) : (
            <>
              <span>{detalleAgenda}</span> · {evento?.cuando ?? ''}
            </>
          )}
        </p>
        {capitalTxt && (
          <p className="mt-2 text-[11px] font-bold tabular-nums text-foreground/75">{capitalTxt} en juego</p>
        )}
      </div>
      <div className="mt-auto flex flex-wrap items-center gap-2 pl-1 pt-4">
        {item && <AccionesContacto lead={item.lead} destacada />}
        {evento && (
          <Button variant="accent" size="sm" className="h-11 sm:h-9" onClick={() => onCompletar(evento.id)}>
            <CircleCheckBig aria-hidden /> Registrar resultado
          </Button>
        )}
        <Button
          variant="ghost"
          size="sm"
          className="ml-auto h-11 px-2 text-muted-foreground hover:text-foreground sm:h-9"
          onClick={() => abrirLead(prioridad.leadId)}
        >
          Ver ficha <ChevronRight aria-hidden />
        </Button>
      </div>
    </article>
  )
}

function FranjaAhora({
  prioridades,
  totalSenales,
  estadoCola,
  leadPorId,
  abrirLead,
  onCompletar,
}: {
  prioridades: PrioridadVendedor[]
  totalSenales: number
  estadoCola: 'lista' | 'cargando' | 'error'
  leadPorId: (id: string) => Lead | undefined
  abrirLead: (id: string) => void
  onCompletar: (id: string) => void
}): JSX.Element {
  const prioridadesParciales = estadoCola !== 'lista' && prioridades.length > 0
  return (
    <section
      aria-labelledby="ahora-vendedor"
      aria-busy={estadoCola === 'cargando'}
      className="relative isolate overflow-hidden rounded-2xl bg-primary px-4 py-5 text-primary-foreground shadow-[0_24px_54px_-32px_rgba(17,30,61,0.9)] sm:px-5"
    >
      <div
        className="pointer-events-none absolute -right-24 -top-28 -z-10 size-80 rounded-full bg-accent/25 blur-3xl"
        aria-hidden
      />
      <div>
        <div className="flex items-center gap-2">
          <span className="rounded-full bg-accent px-2.5 py-1 text-[10px] font-extrabold uppercase tracking-[0.16em] text-white">
            Ahora
          </span>
          <span className="text-[11px] font-semibold text-white/65">
            {estadoCola === 'lista'
              ? `${prioridades.length} de ${totalSenales} ${totalSenales === 1 ? 'señal' : 'señales'} priorizadas`
              : estadoCola === 'cargando'
                ? 'Completando tus prioridades…'
                : 'Prioridad parcial · falta la cola'}
          </span>
        </div>
        <h2
          id="ahora-vendedor"
          className="mt-3 text-[clamp(1.35rem,3vw,2rem)] font-extrabold leading-tight tracking-[-0.03em]"
        >
          Tu siguiente movimiento
        </h2>
        <p className="mt-1 max-w-2xl text-sm leading-relaxed text-white/65">
          Agenda y pendientes reunidos sin duplicados. Resuelve de izquierda a derecha y vuelve al ritmo del día.
        </p>
      </div>

      {prioridades.length === 0 && estadoCola === 'cargando' ? (
        <div
          role="status"
          aria-label="Cargando próximas acciones"
          className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
        >
          {[0, 1, 2].map((n) => (
            <div key={n} className="min-h-40 animate-pulse rounded-xl border border-white/15 bg-white/8 p-4">
              <div className="h-3 w-24 rounded bg-white/20" />
              <div className="mt-5 h-5 w-3/4 rounded bg-white/25" />
              <div className="mt-3 h-3 w-full rounded bg-white/15" />
              <div className="mt-2 h-3 w-2/3 rounded bg-white/15" />
              <div className="mt-6 h-10 w-32 rounded-lg bg-white/20" />
            </div>
          ))}
          <span className="sr-only">Estamos reuniendo agenda y pendientes.</span>
        </div>
      ) : prioridades.length === 0 && estadoCola === 'error' ? (
        <div
          role="status"
          className="mt-5 flex min-h-40 flex-col items-center justify-center rounded-xl border border-white/15 bg-white/8 px-5 text-center"
        >
          <AlertTriangle className="size-9 text-warning" aria-hidden />
          <p className="mt-3 text-base font-bold">No pudimos completar tus prioridades</p>
          <p className="mt-1 max-w-lg text-xs text-white/65">
            Tu agenda sigue disponible, pero falta la cola de acción. Reintenta desde el aviso superior para evitar leer
            un vacío como “al día”.
          </p>
        </div>
      ) : prioridades.length === 0 ? (
        <div className="mt-5 flex min-h-40 flex-col items-center justify-center rounded-xl border border-white/15 bg-white/8 px-5 text-center">
          <CircleCheckBig className="size-9 text-white" aria-hidden />
          <p className="mt-3 text-base font-bold">
            {totalSenales > 0 ? 'Sin urgencias inmediatas' : 'No tienes una intervención pendiente'}
          </p>
          <p className="mt-1 max-w-lg text-xs text-white/65">
            {totalSenales > 0
              ? `Tienes ${totalSenales} ${totalSenales === 1 ? 'acción de preparación' : 'acciones de preparación'} en “Después”; no las marcamos como resueltas.`
              : 'Tu agenda y tu cartera están al día. Puedes preparar el siguiente contacto.'}
          </p>
          <a
            href="#/agenda"
            className="mt-4 inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-white/25 bg-white/10 px-4 text-xs font-bold text-white transition-colors hover:bg-white/20 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-white/55"
          >
            <CalendarDays className="size-4" aria-hidden /> Revisar Agenda
          </a>
        </div>
      ) : (
        <div className="mt-5 grid gap-3 lg:grid-cols-3">
          {prioridades.map((prioridad, indice) => (
            <TarjetaPrioridad
              key={prioridad.id}
              prioridad={prioridad}
              indice={indice}
              lead={leadPorId(prioridad.leadId)}
              abrirLead={abrirLead}
              onCompletar={onCompletar}
            />
          ))}
        </div>
      )}

      {prioridadesParciales && (
        <p
          role="status"
          className="mt-3 rounded-lg border border-white/15 bg-white/8 px-3 py-2 text-[11px] font-medium text-white/70"
        >
          Mostramos lo que sí llegó de tu agenda. La cola no está disponible todavía, así que este orden puede estar
          incompleto.
        </p>
      )}

      <p className="mt-3 text-[10px] font-medium text-white/50">
        Una señal dominante por lead · el detalle completo permanece en Agenda y Cartera.
      </p>
    </section>
  )
}

function PulsoCartera({
  items,
}: {
  items: Array<{ label: string; value: string; sub: string; icon: LucideIcon }>
}): JSX.Element {
  return (
    <Card className="min-w-0 overflow-hidden">
      <div className="flex flex-wrap items-center gap-2 border-b border-border/80 px-5 py-3">
        <span className="grid size-7 place-items-center rounded-lg bg-secondary text-primary">
          <TrendingUp className="size-4" aria-hidden />
        </span>
        <h3 className="text-sm font-bold tracking-tight">Tu cartera en contexto</h3>
        <span className="ml-auto text-[10px] font-semibold uppercase tracking-[0.1em] text-muted-foreground">
          Información · no requiere acción
        </span>
      </div>
      <div className="grid grid-cols-2 divide-x divide-y divide-border/80 lg:grid-cols-4 lg:divide-y-0">
        {items.map(({ label, value, sub, icon: Icon }) => (
          <div key={label} className="min-w-0 p-4">
            <div className="flex items-start justify-between gap-2">
              <p className="text-[10px] font-bold uppercase tracking-[0.09em] text-muted-foreground">{label}</p>
              <span
                className="ac-chip grid size-7 shrink-0 place-items-center rounded-lg"
                style={{ '--c': 'var(--accent)' } as CSSProperties}
              >
                <Icon className="size-3.5" aria-hidden />
              </span>
            </div>
            <p className="mt-2 text-xl font-extrabold leading-none tracking-tight tabular-nums text-primary">
              <AnimatedValue value={value} />
            </p>
            <p className="mt-2 line-clamp-2 text-[11px] leading-relaxed text-muted-foreground">{sub}</p>
          </div>
        ))}
      </div>
    </Card>
  )
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

export function HoyVendedor(): JSX.Element {
  const modoSla = useModoSla()
  const {
    ambito,
    actividades,
    tareas,
    objetivos,
    objetivosError,
    cumplimientoMetas,
    cumplimientoMetasError,
    recargar,
    reprogramarTarea,
  } = useCRMData()
  const { abrirLead, abrirNuevoLead } = usePanelesActions()
  const { yo } = useAuth()
  // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola — en real esos
  // vencimientos llegan resueltos dentro de cola_accion_fn (ni se pide el RPC).
  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
  // Motor (Fase B): tarea seleccionada para cerrar desde la agenda héroe.
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  // Reloj vivo: re-tick por minuto y al volver a la pestaña — entra como
  // dependencia de la cola para que los "hace X" y semáforos se refresquen solos.
  const ahora = useAhora()
  const periodoVigente = periodoLima(ahora)
  const periodoStoreIntentado = useRef<string | null>(null)
  const [recargaPeriodoFallida, setRecargaPeriodoFallida] = useState(false)
  const fotoMensualStoreVigente = yo?.demo === true || (
    objetivos.periodo === periodoVigente
    && (cumplimientoMetas == null || cumplimientoMetas.periodo === periodoVigente)
  )
  useEffect(() => {
    if (yo?.demo || fotoMensualStoreVigente
      || periodoStoreIntentado.current === periodoVigente) return
    periodoStoreIntentado.current = periodoVigente
    setRecargaPeriodoFallida(false)
    void recargar().then((ok) => {
      if (!ok) setRecargaPeriodoFallida(true)
    })
  }, [fotoMensualStoreVigente, periodoVigente, recargar, yo?.demo])

  // Universo del analista — ambito.leads ya es SOLO su cartera. Memoizado porque
  // de él cuelgan `idsMios` y la agenda derivada: un array nuevo en cada render
  // reventaría esos memos sin que haya cambiado un solo dato.
  // Fase 4d «sin topes»: en sesión real la cartera propia la sirve el servidor
  // (`cartera_pagina_fn` bajo la RLS del analista, por cursor hasta agotarla);
  // la demo sigue con su foto local.
  const sesionRealPropios = yo != null && !yo.demo
  const propios = useLeadsPropios(sesionRealPropios)
  const mios = useMemo(
    () => (sesionRealPropios ? (propios.data ?? []) : ambito.leads).filter((l) => l.activo),
    [sesionRealPropios, propios.data, ambito.leads],
  )
  const cargandoMios = sesionRealPropios && propios.isPending
  // Fase 4e: el store conoce la cartera propia (verbos de escritura por id).
  const { conocerLeads } = useCRMData()
  useEffect(() => { conocerLeads(propios.data ?? []) }, [conocerLeads, propios.data])
  // Sin la cartera propia (cargando o caída) NO se filtra: las tareas ya llegan
  // autorizadas por la RLS y ocultarlas leería «sin trabajo» (Codex 20/09).
  const idsMios = useMemo<ReadonlySet<string> | null>(
    () => (sesionRealPropios && (propios.isPending || propios.error) ? null : new Set(mios.map((l) => l.id))),
    [sesionRealPropios, propios.isPending, propios.error, mios],
  )

  // ── F1b: los KPIs llegan del servidor (resumen_cartera_fn) o del espejo
  // demo vivo — esta pantalla ya no cuenta filas para sus tiles. Sin payload
  // (cargando o RPC caída): «—», jamás una cifra inventada. La MONEDA QUE
  // MANDA en el número grande sigue saliendo de capitalPrincipal (criterio
  // compartido con Cartera/Pipeline — jamás un total mixto PEN+USD).
  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
  const resumen = resumenOp.resumen
  const capital = resumen ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd) : null
  const nAbiertos = resumen?.totales.abiertos
  const nConvertidos = resumen?.totales.convertidos
  const nPropuestas = resumen?.embudo.find((p) => p.etapa === 'propuesta_enviada')?.n ?? 0
  const reunionesAgendadas = resumen?.embudo.find((p) => p.etapa === 'reunion_agendada')?.n ?? 0

  // La meta viene de la revisión publicada; el numerador viene únicamente del
  // RPC de cumplimiento confirmado. El pipeline abierto no entra aquí.
  // Meta y producción del MISMO snapshot: ver `metaVigente`. Para el analista
  // importa igual, porque un cambio de equipo a mitad de mes no debe borrarle
  // la meta con la que se le está midiendo.
  const fotoMensualStoreCargando = !yo?.demo
    && !fotoMensualStoreVigente
    && !recargaPeriodoFallida
  const objetivosMensualesError = fotoMensualStoreVigente
    ? objetivosError
    : recargaPeriodoFallida
  const cumplimientoMensualError = fotoMensualStoreVigente
    ? cumplimientoMetasError
    : recargaPeriodoFallida
  const objetivosMensuales = fotoMensualStoreVigente
    ? objetivos
    : objetivosCero(periodoVigente)
  const cumplimientoMensual = fotoMensualStoreVigente ? cumplimientoMetas : null
  const meta = metaVigente(objetivosMensuales.vendedor, cumplimientoMensual?.vendedor ?? null)
  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
  const cumplimiento = cumplimientoMensual?.vendedor ?? null
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null

  // LA CONVERSIÓN DEL MES — de `crm.conversion_mensual_fn` (la definición
  // acordada), NO del cumplimiento: hasta la migración B el cumplimiento sigue
  // con la fórmula vieja y este tile ya enseña la buena (decisión E1, plan
  // §4bis). El alcance 'propio' devuelve EXACTAMENTE una fila: la suya.
  const periodoConversion = periodoVigente
  const esDemo = yo?.demo === true
  const qConversionMensual = useConversionMensual(
    !esDemo,
    periodoConversion,
    'propio',
    yo?.id,
  )
  const conversionMensualCargando = !esDemo
    && qConversionMensual.isPending
    && qConversionMensual.data === undefined
  const conversionMensual = esDemo
    ? conversionMensualDemo(Date.now(), {
        alcance: 'propio',
        actorId: yo?.id ?? 'd-v1',
      })
    : conversionMensualCargando
      ? undefined
      : (qConversionMensual.data ?? null)
  const conversionMensualError = !esDemo && qConversionMensual.isError
  const miConversion = conversionMensual?.responsables.find(
    (fila) => fila.vendedor_id === yo?.id,
  ) ?? null
  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
  // 2026-08-14). La regla vive en `lecturaCobertura`, no aquí: cuatro pantallas
  // pintan esta misma cifra y escrita cuatro veces acabarían discrepando.
  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
  const conversion = lecturaConversion.mostrar ? (miConversion?.conversion_pct ?? null) : null
  // CAPITAL CONSOLIDADO (decisión de Miguel 2026-08-10, extendiendo la #10 al
  // analista): lo que manda es UN solo número —cuánto ha metido en total, en
  // soles— y el desglose por moneda vive debajo como sub-línea. Si cierra en
  // dólares, su avance sube igual, convertido al TC real.
  //
  // La regla de la casa (PEN y USD JAMÁS se suman) sigue intacta: `totalEnSoles`
  // no suma a ciegas, convierte a una tasa conocida y devuelve el TC que
  // REALMENTE aplicó, que es el que se rotula. Sin tasa, el USD queda fuera del
  // total y se dice — nunca se inventa una.
  //
  // El MISMO tc entra en el capital y en la meta: si falta, los dos quedan
  // solo-PEN y el porcentaje sigue comparando peras con peras.
  const { tc: tipoCambio, recargar: recargarTipoCambio } = useTipoCambio()
  const diaTipoCambio = fechaLima(ahora)
  const diaTipoCambioAnterior = useRef(diaTipoCambio)
  useEffect(() => {
    if (diaTipoCambioAnterior.current === diaTipoCambio) return
    diaTipoCambioAnterior.current = diaTipoCambio
    recargarTipoCambio()
  }, [diaTipoCambio, recargarTipoCambio])
  const tcPromedio = tipoCambio?.promedio ?? null
  const capitalTotal = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tcPromedio)
  const metaTotal = totalEnSoles(metaCapitalPen, metaCapitalUsd, tcPromedio)
  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tipoCambio === undefined && hayDolares
  const tcCaido = tipoCambio === null && hayDolares
  const ajusteCierre = cumplimiento?.ajuste
  const hayAjusteCierre = ajusteCierre != null && (
    ajusteCierre.aplicadoPen > 0
    || ajusteCierre.aplicadoUsd > 0
    || ajusteCierre.contratosAplicados > 0
  )

  // Cola de acción personal (el ámbito del analista no trae parkeados).
  // Fase B: los leads CON tarea pendiente ya tienen plan — su cola es la
  // agenda; aquí solo quedan speed-to-lead y los que se quedaron sin plan.
  // ⚠️ `plan.vigente` y NO "tiene alguna tarea": una pendiente que venció hace
  // dos semanas no es un plan (ver lib/plan-lead.ts). `plan.conTarea` —viva o
  // muerta— es el que necesita la higiene del viernes, que ya lista las
  // vencidas por su cuenta y duplicaría el lead si recibiera `vigente`.
  const plan = useMemo(() => planPorLead(tareas, ahora), [tareas, ahora])
  const conTarea = plan.conTarea
  // F1b: la cola la calcula el SERVIDOR (cola_accion_fn) — buckets, severidad,
  // relojes SLA y plan vigente incluidos; en demo, el espejo vivo (colaDe).
  // Todo el contrato anti-duplicado de abajo opera sobre los items mapeados.
  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
  const colaDisponible = colaOp.cola != null
  const cola = useMemo(() => colaOp.cola?.items ?? [], [colaOp.cola])
  // Excedente que el servidor conoce y el recorte de p_limite dejó fuera: el
  // pie «+N más en cola» lo suma para no mentir por defecto. Aproximación
  // asumida: el excedente no pasa por el anti-duplicado agenda↔cola (sus leads
  // no viajaron), así que uno ya pintado en la franja ámbar contaría doble en
  // el pie — solo posible con >100 items en cola PERSONAL, hoy irreal.
  const restoServidor = Math.max(0, (colaOp.cola?.total ?? 0) - cola.length)

  // Agenda héroe — se deriva AQUÍ, con el reloj vivo, y NO se consume la del
  // store: allí sale de un `agendaDeTareas(tareas, Date.now())` encerrado en un
  // memo cuyas dependencias no cambian con el tiempo, así que `vencida` y las
  // etiquetas Hoy/Mañana quedaban CONGELADAS en el instante de la carga — la
  // alarma ámbar no saltaba en toda la jornada y, pasada la medianoche, "Hoy"
  // seguía siendo ayer mientras la cola de al lado (useAhora) decía otra cosa.
  // El filtro por idsMios es el espejo RLS; v1 solo opera tareas de lead.
  //
  // Y se recorta al DÍA OPERABLE con el mismo criterio que la vista [Hoy] de la
  // pantalla Agenda (vencidas + las de hoy): sin ese recorte la tarjeta listaba
  // TODA la agenda futura mientras su badge y el chip "En juego hoy" ya contaban
  // solo hoy — los números no cuadraban con las filas de abajo y un día
  // realmente vacío se leía como un día lleno.
  const agenda = useMemo(() => {
    const mias = tareas.filter((t) => t.lead_id && (idsMios === null || idsMios.has(t.lead_id)))
    return agendaDeTareas(mias, ahora).filter((ev) => ev.vencida || esDeHoy(ev, ahora))
  }, [tareas, idsMios, ahora])

  // Postventa: tareas cuyo sujeto es un cliente de Mi cartera. Se mantienen
  // separadas del motor de leads para no contaminar SLA, etapas ni la cola,
  // pero comparten el mismo reloj y el mismo diálogo de cierre.
  const agendaClientes = useMemo(() => {
    const mias = tareas.filter((t) => (t.perfil_id != null || t.inversionista_id != null) && (yo?.id == null || t.vendedor_id === yo.id))
    return agendaDeTareas(mias, ahora).filter((evento) => evento.vencida || esDeHoy(evento, ahora))
  }, [tareas, yo?.id, ahora])

  // Modo "viernes 13:00" (Fase D): viernes p.m. es el peor momento para citas
  // nuevas → la cola deja de perseguir y ORDENA la próxima semana (vencidas,
  // reagendas de no-show fuera de mar–jue, leads sin próxima acción). El
  // speed-to-lead NUNCA se entierra: los "sin responder" siguen arriba.
  const higiene = esViernesDeHigiene(ahora)
  // ANTI-DUPLICADO agenda ↔ cola. La regla es "manda la agenda", pero SOLO
  // sobre lo que la agenda enseña de verdad: la franja ámbar corta en
  // VENCIDAS_VISIBLES y colapsa el resto en un "+N más" sin nombre ni motivo.
  // Esconder de la cola TODAS las vencidas borraba de la pantalla a los leads
  // del excedente —con su capital en juego y su "Propuesta sin movimiento hace
  // 12 d"— mientras la cola, encima, se declaraba al día.
  const listadasEnAgenda = useMemo(() => vencidasListadas(agenda), [agenda])
  // Por LEAD para la cola (sus filas son leads) …
  const leadsListadosEnAgenda = useMemo(() => new Set(listadasEnAgenda.map((ev) => ev.lead_id)), [listadasEnAgenda])
  // … y por TAREA para la higiene del viernes (sus filas son tareas; el id del
  // evento de agenda ES el id de la tarea, ver onCompletar).
  const tareasListadasEnAgenda = useMemo(() => new Set(listadasEnAgenda.map((ev) => ev.id)), [listadasEnAgenda])
  // EXCEPCIÓN deliberada — el speed-to-lead: un lead sin primer contacto NUNCA
  // se entierra (regla de la casa), y su fila es la única que trae el cronómetro
  // en minutos, que la agenda no muestra.
  const colaSinRepetir = cola.filter((i) => i.bucket === 'sin_responder' || !leadsListadosEnAgenda.has(i.lead.id))
  const colaVisible = higiene ? colaSinRepetir.filter((i) => i.bucket === 'sin_responder') : colaSinRepetir
  // Los leads que la cola ya pinta (speed-to-lead) se excluyen de los
  // amarillos — sin esto el mismo lead saldría dos veces y el badge contaría
  // doble. El filtro por idsMios es el espejo RLS; v1 solo opera tareas de
  // lead (las de cliente/perfil_id llegan con la fase de postventa).
  //
  // Y la MISMA regla de arriba sobre las vencidas: `colaHigiene` las lista
  // todas, así que las que la franja ámbar ya está pintando se quitan aquí —
  // el viernes salían dos veces en la misma pantalla, con su mismo botón de
  // cerrar, y las contaban los dos badges. Cede la higiene, no la agenda: la
  // agenda es el héroe del día y su fila trae la hora. Las que NO caben en la
  // franja se quedan en la higiene, que es donde el viernes toca cerrarlas.
  const itemsHigiene = (
    higiene
      ? colaHigiene(
          tareas.filter((t) => t.lead_id && (idsMios === null || idsMios.has(t.lead_id))),
          mios,
          conTarea,
          ahora,
          new Set(colaVisible.map((i) => i.lead.id)),
        )
      : []
  ).filter((i) => i.k !== 'vencida' || !tareasListadasEnAgenda.has(i.tarea.id))
  const tareasHigiene = itemsHigiene.filter(
    (i): i is Extract<ItemHigiene, { k: 'vencida' | 'no_show_fuera_ritmo' }> => i.k !== 'sin_accion',
  )
  const amarillos = itemsHigiene.filter((i): i is Extract<ItemHigiene, { k: 'sin_accion' }> => i.k === 'sin_accion')
  const AMARILLOS_VISIBLES = 8
  // La cola también se capa (mismo patrón que los amarillos): colaDe ya ordena
  // por severidad, así que los primeros N son la plata y el resto va a Cartera.
  const COLA_VISIBLES = 7
  // Lookup de lead por id (capital en juego de cada cita) + señales reales para
  // el vacío honesto de la agenda (mientras no exista calendario real).
  const leadPorId = (id: string): Lead | undefined => mios.find((l) => l.id === id)

  // Contrato perceptual del nuevo «Ahora»: máximo tres decisiones, una por
  // lead. Lo elevado se retira de las superficies inferiores; no es un resumen
  // que vuelva a repetir la misma alerta unos píxeles más abajo.
  const prioridadesAhora = seleccionarPrioridadesVendedor(agenda, colaVisible)
  const leadsAhora = new Set(prioridadesAhora.map((p) => p.leadId))

  // Tras sacar las tres prioridades, cada señal restante tiene UN dueño visual.
  // Un speed-to-lead conserva la cola (allí vive su reloj); para el resto manda
  // lo que Agenda pinta de verdad. Las vencidas bajo su "+N" siguen en la cola o
  // en la higiene: así no duplicamos trabajo ni escondemos el excedente.
  const colaBaseDespues = colaVisible.filter((item) => !leadsAhora.has(item.lead.id))
  const leadsSpeedDespues = new Set(
    colaBaseDespues.filter((item) => item.bucket === 'sin_responder').map((item) => item.lead.id),
  )
  const agendaDespues = agenda.filter((ev) => !leadsAhora.has(ev.lead_id) && !leadsSpeedDespues.has(ev.lead_id))
  const eventosAgendaPintadosDespues = [
    ...vencidasListadas(agendaDespues),
    ...agendaDespues.filter((ev) => !ev.vencida),
  ]
  const leadsPintadosAgendaDespues = new Set(eventosAgendaPintadosDespues.map((ev) => ev.lead_id))
  const tareasPintadasAgendaDespues = new Set(eventosAgendaPintadosDespues.map((ev) => ev.id))
  const colaDespues = colaBaseDespues.filter((item) => !leadsPintadosAgendaDespues.has(item.lead.id))
  const tareasHigieneDespues = tareasHigiene.filter(
    (item) =>
      (item.tarea.lead_id == null || !leadsAhora.has(item.tarea.lead_id)) &&
      !tareasPintadasAgendaDespues.has(item.tarea.id),
  )
  const amarillosDespues = amarillos.filter((item) => !leadsAhora.has(item.lead.id))
  const colaPintadaDespues = colaDespues.slice(0, COLA_VISIBLES)
  const leadsEnColaDespues = new Set(colaPintadaDespues.map((item) => item.lead.id))
  const tareasEnHigieneDespues = new Set(tareasHigieneDespues.map((item) => item.tarea.id))
  const vencidasAbajoDespues = agendaDespues.filter(
    (ev) =>
      ev.vencida &&
      !tareasPintadasAgendaDespues.has(ev.id) &&
      (tareasEnHigieneDespues.has(ev.id) || leadsEnColaDespues.has(ev.lead_id)),
  ).length
  const nVencidasAgendaDespues = agendaDespues.filter((ev) => ev.vencida).length
  const nColaDespues = colaDespues.length + (higiene ? tareasHigieneDespues.length + amarillosDespues.length : 0)
  const porSevDespues = { critica: 0, media: 0, baja: 0 }
  for (const item of colaDespues) porSevDespues[item.sev] += 1
  const totalSenales = new Set([
    ...agenda.map((ev) => ev.lead_id),
    ...colaVisible.map((item) => item.lead.id),
    ...tareasHigiene.map((item) => item.tarea.lead_id).filter((id): id is string => id != null),
    ...amarillos.map((item) => item.lead.id),
  ]).size

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Encabezado de jornada: orientación, no otro bloque de métricas. */}
      <header className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-[10px] font-extrabold uppercase tracking-[0.18em] text-accent">Mi jornada</p>
          <h2 className="mt-1 text-2xl font-extrabold tracking-[-0.03em] text-primary">
            Hola, {primerNombre(yo?.nombre_completo) || 'analista'}.
          </h2>
          <p className="mt-1 text-xs text-muted-foreground">
            {fechaLarga(ahora)} · primero resolvemos; después revisamos el contexto.
          </p>
        </div>
        <p className="rounded-full border border-border bg-card px-3 py-1.5 text-[10px] font-semibold text-muted-foreground shadow-sm">
          Vista personal · solo ves tu cartera
        </p>
      </header>

      {/* Rentabilidad R3: qué decidió Gerencia sobre tus solicitudes de tasa (solo si hay alguna en curso). */}
      <TasasAutorizadasAnalistaPanel />

      <AvisoDegradacion
        activo={Boolean(resumenOp.error || (modoSla.legado && colaOp.error)) && !yo?.demo}
        queReintenta="de tus indicadores"
        onReintentar={() => {
          if (resumenOp.error) void resumenOp.recargar()
          if (colaOp.error) void colaOp.recargar()
        }}
      >
        No se pudieron cargar algunos indicadores. Se muestran «—» para no inventar cifras; tu agenda sigue completa.
      </AvisoDegradacion>

      {/* El trabajo gana el primer pantallazo. Sin cartera, el vacío ofrece una
          salida real; con cartera, «Ahora» reemplaza la antigua fila de KPI. */}
      {modoSla.legado && (mios.length === 0 && !cargandoMios ? (
        <Card>
          <PanelVacio
            icono={Users}
            titulo="Aún no tienes leads en tu cartera"
            detalle="Pídele asignación a tu supervisor o registra tu primer lead — tus KPIs aparecerán aquí en cuanto tengas cartera."
          >
            <Button variant="accent" size="sm" onClick={() => abrirNuevoLead()}>
              <Plus aria-hidden /> Registrar mi primer lead
            </Button>
          </PanelVacio>
        </Card>
      ) : (
        <FranjaAhora
          prioridades={prioridadesAhora}
          totalSenales={totalSenales}
          estadoCola={colaDisponible ? 'lista' : colaOp.error ? 'error' : 'cargando'}
          leadPorId={leadPorId}
          abrirLead={abrirLead}
          onCompletar={(id) => {
            const tarea = tareas.find((x) => x.id === id)
            if (tarea) setTareaACerrar(tarea)
          }}
        />
      ))}

      <AgendaClientesHoy
        eventos={agendaClientes}
        abrirLead={abrirLead}
        onCompletar={(id) => {
          const tarea = tareas.find((item) => item.id === id)
          if (tarea) setTareaACerrar(tarea)
        }}
      />

      {/* Después de las tres prioridades: solo el remanente. La proximidad
          separa lo inmediato de lo que mantiene el ritmo del resto del día. */}
      <SlaOperacionBoundary legado={(
      <div className="grid gap-5 lg:grid-cols-5">
        <AgendaHoy
          eventos={agendaDespues}
          leadPorId={leadPorId}
          abrirLead={abrirLead}
          onCompletar={(id) => {
            const t = tareas.find((x) => x.id === id)
            if (t) setTareaACerrar(t)
          }}
          demo={yo?.demo ?? false}
          nReuniones={reunionesAgendadas}
          nPropuestas={nPropuestas}
          vencidasAbajo={vencidasAbajoDespues}
          title="Después en tu agenda"
          className="min-w-0 flex flex-col lg:col-span-3"
        />
        {/* Cola de acción personal — el viernes desde las 13:00 (Lima) cambia
            a higiene de pipeline: ordenar la próxima semana, no perseguir. */}
        <Card className="min-w-0 lg:col-span-2">
          <SectionHead
            icon={higiene ? Sparkles : Zap}
            title={higiene ? 'Después: viernes de higiene' : 'Después: mantén el ritmo'}
            right={
              nColaDespues > 0 ? (
                <Badge color={higiene ? '#d97706' : 'var(--accent)'}>
                  {nColaDespues} {nColaDespues === 1 ? 'pendiente' : 'pendientes'}
                </Badge>
              ) : undefined
            }
          />
          <CardContent className="space-y-1.5 pt-0">
            {higiene && nColaDespues > 0 && (
              <p className="rounded-lg bg-muted/50 px-3 py-2 text-[11px] text-muted-foreground">
                Viernes p.m. rinde poco para citas nuevas — deja la próxima semana ordenada: cierra lo vencido, mueve a
                mar–jue las citas de quien no asistió y que ningún lead quede sin próxima acción.
              </p>
            )}
            {!colaDisponible ? (
              <div className="flex flex-col items-center gap-2 py-10 text-center">
                <p className="text-sm font-bold">{colaOp.error ? 'Tu cola no está disponible' : 'Cargando tu cola…'}</p>
                <p className="text-xs text-muted-foreground">
                  {colaOp.error
                    ? 'No se pudo consultar la cola de acción. Tu agenda de al lado sigue completa.'
                    : 'Un momento — estamos trayendo tus pendientes.'}
                </p>
              </div>
            ) : nColaDespues === 0 ? (
              nVencidasAgendaDespues > 0 ? (
                // Cola vacía NO es "al día": lo vencido está en la agenda de al
                // lado (donde vive su botón de cerrar). Decir "sin pendientes"
                // mientras el badge vecino canta N vencidas es la pantalla
                // contradiciéndose, y el analista se va a casa creyendo que
                // terminó. El vacío REMITE a la agenda en vez de negarla.
                <div className="flex flex-col items-center gap-2 py-10 text-center">
                  <AlertTriangle className="size-8 text-warning" />
                  <p className="text-sm font-bold">Lo pendiente está en tu agenda</p>
                  <p className="text-xs text-muted-foreground">
                    {nVencidasAgendaDespues === 1
                      ? 'Tienes 1 seguimiento vencido'
                      : `Tienes ${nVencidasAgendaDespues} seguimientos vencidos`}{' '}
                    en «Después en tu agenda» — ciérralos o reprográmalos desde ahí.
                  </p>
                </div>
              ) : (
                <div className="flex flex-col items-center gap-2 py-10 text-center">
                  <CircleCheckBig className="size-8 text-accent" />
                  <p className="text-sm font-bold">
                    {prioridadesAhora.length > 0
                      ? 'Sin trabajo adicional'
                      : higiene
                        ? 'Pipeline limpio ✦'
                        : 'Al día ✦ sin pendientes'}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {higiene
                      ? 'Nada vencido, las citas reagendadas en su día y toda tu cartera con próxima acción. Buen fin de semana.'
                      : prioridadesAhora.length > 0
                        ? 'Tus intervenciones están arriba. Aquí no queda trabajo adicional.'
                        : 'No tienes leads esperando respuesta ni seguimientos vencidos.'}
                  </p>
                </div>
              )
            ) : (
              <>
                {/* Mini-resumen por severidad: la respuesta a "¿cómo viene mi
                    cola?" antes de bajar a las filas (rojo/ámbar/azul, sin verde). */}
                {colaDespues.length > 1 && (
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-muted/50 px-3 py-2 text-[11px]">
                    {(['critica', 'media', 'baja'] as const).map(
                      (sev) =>
                        porSevDespues[sev] > 0 && (
                          <span key={sev} className="inline-flex items-center gap-1.5 font-semibold text-foreground/80">
                            <span
                              className="size-2 shrink-0 rounded-full"
                              style={{ background: SEV_COLOR[sev] }}
                              aria-hidden
                            />
                            <span className="tabular-nums">{porSevDespues[sev]}</span>{' '}
                            {sev === 'critica'
                              ? porSevDespues.critica === 1
                                ? 'crítica'
                                : 'críticas'
                              : sev === 'media'
                                ? porSevDespues.media === 1
                                  ? 'media'
                                  : 'medias'
                                : porSevDespues.baja === 1
                                  ? 'baja'
                                  : 'bajas'}
                          </span>
                        ),
                    )}
                  </div>
                )}
                {colaPintadaDespues.map((item) => (
                  <FilaCola key={item.lead.id} item={item} abrirLead={abrirLead} ahora={ahora} />
                ))}
                {Math.max(0, colaDespues.length - COLA_VISIBLES) + restoServidor > 0 && (
                  <p className="px-2 text-[11px] text-muted-foreground">
                    +{Math.max(0, colaDespues.length - COLA_VISIBLES) + restoServidor} más en cola — trabájalos desde
                    Cartera.
                  </p>
                )}
                {tareasHigieneDespues.map((item) => (
                  <FilaHigiene
                    key={item.tarea.id}
                    item={item}
                    lead={item.tarea.lead_id ? leadPorId(item.tarea.lead_id) : undefined}
                    ahora={ahora}
                    abrirLead={abrirLead}
                    onCerrar={() => setTareaACerrar(item.tarea)}
                    onMarJue={async (destino) => {
                      const res = reprogramarTarea(item.tarea.id, destino)
                      if (res.ok && await (res.persistido ?? Promise.resolve(true))) {
                        const cuando = tareaAEvento({ ...item.tarea, vence_en: destino }, ahora).cuando
                        toast.success(`Movida al ${cuando}${yo?.demo ? ' (demo)' : ''}`)
                        return true
                      } else if (!res.ok) toast.error(res.error ?? 'No se pudo mover')
                      return false
                    }}
                  />
                ))}
                {amarillosDespues.slice(0, AMARILLOS_VISIBLES).map((item) => (
                  <FilaAmarillo key={item.lead.id} lead={item.lead} abrirLead={abrirLead} />
                ))}
                {amarillosDespues.length > AMARILLOS_VISIBLES && (
                  <p className="px-2 text-[11px] text-muted-foreground">
                    +{amarillosDespues.length - AMARILLOS_VISIBLES} más sin próxima acción — trabájalos desde Cartera.
                  </p>
                )}
              </>
            )}
          </CardContent>
        </Card>
      </div>

      )}>
        <AgendaHoy eventos={agenda} leadPorId={leadPorId} abrirLead={abrirLead}
          onCompletar={(id) => { const tarea = tareas.find((item) => item.id === id); if (tarea) setTareaACerrar(tarea) }}
          demo={false} nReuniones={reunionesAgendadas} nPropuestas={nPropuestas}
          vencidasAbajo={0} title="Tu agenda de hoy" />
      </SlaOperacionBoundary>

      {mios.length > 0 && (
        <PulsoCartera
          items={[
            {
              label: 'Capital abierto',
              value: capital?.valor ?? '—',
              icon: Wallet,
              sub: capital?.otra
                ? `Pipeline activo (PEN) · +${capital.otra} aparte`
                : capital?.soloDolares
                  ? 'Pipeline activo (USD)'
                  : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.abiertos > 0
                    ? 'Sin montos estimados — complétalos en cada ficha'
                    : 'Pronóstico de tu pipeline activo',
            },
            {
              label: 'Leads activos',
              value: nAbiertos != null ? String(nAbiertos) : '—',
              icon: Users,
              sub: 'Abiertos en tu cartera',
            },
            {
              label: 'Entrevistas realizadas',
              value: resumen ? String(nPropuestas) : '—',
              icon: FileText,
              sub:
                resumen == null
                  ? 'Sin dato por ahora'
                  : nPropuestas > 0
                    ? 'Entrevista hecha, cierre pendiente'
                    : (nAbiertos ?? 0) > 0
                      ? 'Ninguna enviada — revisa tus citas'
                      : 'Sin leads abiertos por ahora',
            },
            {
              label: 'Convertidos',
              value: nConvertidos != null ? String(nConvertidos) : '—',
              icon: Trophy,
              // F3.1 (H9/D1): este número es la VISTA de cartera — ganados aún
              // visibles dentro de la ventana operativa — y el rótulo lee esa
              // ventana del payload en vez de afirmar «45» por su cuenta. La
              // conversión del MES vive abajo, en «Tu cumplimiento del mes».
              sub:
                resumen == null
                  ? 'Sin dato por ahora'
                  : (nConvertidos ?? 0) > 0
                    ? `Ganados aún en tu cartera · ventana de ${resumen.ventana_convertidos_dias} días`
                    : 'Aún sin cierres — tu primera venta sale de la cola',
            },
          ]}
        />
      )}

      {/* Progressive disclosure: el avance mensual está disponible, pero no
          compite con el trabajo del día hasta que el analista decide abrirlo. */}
      <Card className="min-w-0">
        <details className="group">
          <summary className="flex min-h-14 cursor-pointer list-none items-center gap-3 rounded-xl px-5 py-3 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 [&::-webkit-details-marker]:hidden">
            <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-secondary text-accent">
              <Target className="size-4" aria-hidden />
            </span>
            <div className="min-w-0">
              <h3 className="text-sm font-bold tracking-tight">Tu cumplimiento del mes</h3>
              <p className="text-[11px] text-muted-foreground">
                {yo?.demo ? 'Datos confirmados demo' : 'Contratos confirmados'} · abre para ver metas y procedencia
              </p>
            </div>
            <span className="ml-auto hidden text-right text-[11px] font-semibold tabular-nums text-muted-foreground sm:block">
              {tcEnVuelo ? 'Capital consultando…' : capitalTotal.total == null ? 'Capital —' : `Capital ${moneyK(capitalTotal.total, 'PEN')}`}
              {' · '}
              {conversionMensualCargando ? 'Conversión consultando…' : `Conversión ${porcentajeConversionCanonica(conversion)}`}
            </span>
            <ChevronRight
              className="size-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-90"
              aria-hidden
            />
          </summary>
          <CardContent className="border-t border-border/80 pt-4">
            <div className="grid gap-x-8 gap-y-4 md:grid-cols-2">
              <MetaFila
                icon={Wallet}
                label="Capital confirmado"
                valorTxt={tcEnVuelo ? 'Calculando…' : capitalTotal.total == null ? '—' : moneyK(capitalTotal.total, 'PEN')}
                metaTxt={metaTotal.total == null ? '—' : moneyK(metaTotal.total, 'PEN')}
                pct={pctMeta(capitalTotal.total ?? 0, metaTotal.total ?? 0)}
                delay={0}
                nota={(
                  <>
                    {!tcEnVuelo && <DesgloseCapital capital={capitalTotal} fuenteTc={tipoCambio?.fuente ?? null} />}
                    {hayAjusteCierre && ajusteCierre && (
                      <p
                        className="text-[11px] font-semibold tabular-nums text-warning-text"
                        title="El capital confirmado ya es neto: estos importes y contratos se descontaron al cerrar el mes."
                      >
                        Neto tras ajuste de cierre
                        {ajusteCierre.aplicadoPen > 0 ? ` · −${money(ajusteCierre.aplicadoPen, 'PEN')}` : ''}
                        {ajusteCierre.aplicadoUsd > 0 ? ` · −${money(ajusteCierre.aplicadoUsd, 'USD')}` : ''}
                        {ajusteCierre.contratosAplicados > 0
                          ? ` · −${numero(ajusteCierre.contratosAplicados)} ${ajusteCierre.contratosAplicados === 1 ? 'contrato' : 'contratos'}`
                          : ''}
                      </p>
                    )}
                  </>
                )}
                neutro={
                  fotoMensualStoreCargando
                    ? 'Actualizando la meta y el cumplimiento de este mes…'
                    : objetivosMensualesError
                    ? 'Meta mensual no disponible'
                    : tcEnVuelo
                      ? 'Consultando el tipo de cambio para consolidar los dólares…'
                      : (metaTotal.total ?? 0) <= 0
                      ? SIN_META
                      : cumplimientoMensualError || capitalTotal.total == null
                        ? 'Cumplimiento confirmado no disponible'
                        : undefined
                }
              />
              <MetaFila
                icon={TrendingUp}
                label="Conversión del mes"
                valorTxt={conversionMensualCargando ? 'Calculando…' : porcentajeConversionCanonica(conversion)}
                metaTxt={metaConversion == null ? 'Sin meta' : `${metaConversion}%`}
                pct={pctMeta(conversion ?? 0, metaConversion ?? 0)}
                delay={180}
                nota={
                  miConversion && lecturaConversion.mostrar ? (
                    <span className="text-[11px] text-muted-foreground">
                      {/* `text-muted-foreground` y NO var(--gi-muted): ese token
                        solo resuelve dentro de `.gerencia-inteligencia`, y esta
                        pantalla no está en él — el color salía de la herencia
                        por accidente (revisor a11y, F2.3). Mismo hex.
                        El divisor SIEMPRE al lado del % (riesgo 3 del plan): se
                        lo llena el reparto, no el analista, y el número solo
                        miente por omisión. */}
                      Recibidos {numero(miConversion.divisor)} · cierres{' '}
                      {numero(miConversion.cierres_no_referidos + miConversion.cierres_referidos)}
                      {miConversion.cierres_de_arrastre > 0 &&
                        ` · ${lineaProcedencia(miConversion.procedencia, conversionMensual?.periodo.anio ?? 0)}`}
                      {(() => {
                        // El porqué al lado del número que baja: su conversión ya
                        // llega NETA de anulaciones de meses cerrados, y un
                        // número que baja sin explicación es una llamada a
                        // soporte. El detalle (mes, motivo, cuánto) va en title.
                        const descuento = descuentoArrastre(miConversion.ajuste)
                        return descuento ? (
                          <>
                            {' · '}
                            <ChipArrastre descuento={descuento} />
                          </>
                        ) : null
                      })()}
                      {/* ⚠️ El aviso de «provisional» NO se le pone al analista
                        (decisión de Miguel, 2026-08-14): él necesita ver su
                        número, no la contabilidad de por qué el mes va corto.
                        Ese matiz sí viaja a supervisor y gerencia, que son
                        quienes comparan y deciden. */}
                    </span>
                  ) : undefined
                }
                neutro={
                  conversionMensualCargando
                    ? 'Consultando la conversión del mes…'
                    : conversionMensualError
                      ? 'Conversión del mes no disponible'
                      : !lecturaConversion.mostrar
                      ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
                      : miConversion?.estado === 'solo_referidos'
                        ? 'Solo recibió referidos este mes — al cerrarse suman al 15 %'
                        : miConversion?.estado === 'solo_arrastre'
                          ? `${numero(miConversion.cierres_no_referidos + miConversion.cierres_referidos)} cierres arrastrados · sin leads recibidos`
                          : miConversion?.estado === 'sin_actividad' || conversion == null
                            ? 'Sin leads recibidos este mes'
                            : fotoMensualStoreCargando
                              ? 'Actualizando la meta de este mes…'
                              : objetivosMensualesError
                              ? 'Meta mensual no disponible'
                              : metaConversion == null
                                ? SIN_META
                                : undefined
                }
              />
            </div>
            {(objetivosMensualesError || cumplimientoMensualError || conversionMensualError || tcCaido) && (
              <div className="mt-4 flex flex-wrap items-center gap-2">
                <p className="text-[11px] text-warning-text">No pudimos cargar toda la información mensual.</p>
                {/* El reintento cubre TAMBIÉN la conversión mensual (observación
                  #4 de la revisión externa: el tile decía «no disponible» sin
                  salida — recargar() solo repone el store, no esta query). */}
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    if (objetivosMensualesError || cumplimientoMensualError) {
                      setRecargaPeriodoFallida(false)
                      void recargar().then((ok) => {
                        if (!ok && !fotoMensualStoreVigente) setRecargaPeriodoFallida(true)
                      })
                    }
                    if (conversionMensualError) void qConversionMensual.refetch()
                    if (tcCaido) recargarTipoCambio()
                  }}
                >
                  Reintentar
                </Button>
              </div>
            )}
          </CardContent>
        </details>
      </Card>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} únicamente tu propia cartera; cada analista trabaja solo con sus leads.
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
  // El reloj arranca cuando el lead LLEGÓ A SUS MANOS (`tenencia_desde`), no
  // cuando entró al CRM: entre una cosa y otra hay cola de Rosa y bandeja del
  // supervisor, y esa espera no es suya. Sin el dato (demo, o base sin la
  // migración) degrada a `creado_en`, el comportamiento de siempre.
  const desde = item.lead.tenencia_desde ?? item.lead.creado_en
  const minutos =
    item.bucket === 'sin_responder' && ahora != null
      ? Math.max(0, Math.floor((ahora - Date.parse(desde)) / 60_000))
      : null
  const cronometro =
    minutos != null && minutos < 24 * 60
      ? {
          texto: minutos < 60 ? `${minutos} min` : `${Math.floor(minutos / 60)} h ${minutos % 60} m`,
          // Escala de la casa (semáforo sin verde): "aún a tiempo" = azul ok, no
          // verde — el verde queda reservado a WhatsApp/éxito.
          color: minutos <= 5 ? SEMAFORO.ok : minutos <= 15 ? SEMAFORO.atencion : SEMAFORO.critico,
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
      // Fondo tenue rojo SOLO en la fila crítica: el ojo aterriza primero en el
      // speed-to-lead (lo que genera ingreso), el resto de filas quedan planas.
      className={`${FILA_BASE}${item.sev === 'critica' ? ' bg-destructive/5' : ''}`}
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
          style={{
            color: cronometro.color,
            background: `color-mix(in srgb, ${cronometro.color} 12%, transparent)`,
          }}
          title="Tiempo desde que el lead llegó a tus manos — contactar en minutos multiplica el contacto"
        >
          {cronometro.texto}
        </span>
      ) : (
        <span className="hidden shrink-0 text-[11px] font-semibold tabular-nums text-muted-foreground sm:block">
          {diasTxt(item.dias)}
        </span>
      )}
      <AccionesContacto lead={item.lead} compacto soloIcono conAgendar />
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
  onMarJue: (destino: string) => Promise<boolean>
}): JSX.Element {
  const [moviendo, setMoviendo] = useState(false)
  const envioMovimiento = useRef(false)
  const [destinoSinConfirmar, setDestinoSinConfirmar] = useState<string | null>(null)
  const t = item.tarea
  const ev = tareaAEvento(t, ahora)
  const vencida = item.k === 'vencida'
  const c = vencida ? SEMAFORO.critico : SEMAFORO.violeta
  const abrir = () => t.lead_id && abrirLead(t.lead_id)
  const motivo = vencida
    ? `Venció ${haceTexto(diasDesdeReferencia(t.vence_en, ahora))} — ciérrala o reprográmala`
    : `El cliente no asistió — la nueva cita cae ${ev.cuando}; mejor mar–jue`
  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${ev.titulo}`}
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
      className={FILA_BASE}
    >
      <span className="size-2.5 shrink-0 rounded-full" style={{ background: c }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          {lead ? (
            <LeadHoverCard lead={lead}>
              <p className="truncate text-sm font-semibold">{ev.titulo}</p>
            </LeadHoverCard>
          ) : (
            <p className="truncate text-sm font-semibold">{ev.titulo}</p>
          )}
          <Badge color={c} className="text-[10px]">
            {vencida ? 'Vencida' : 'No asistió'}
          </Badge>
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{motivo}</p>
      </div>
      {vencida ? (
        <button
          type="button"
          title="Cerrar tarea (registra el resultado y agenda la siguiente)"
          aria-label={`Cerrar tarea — ${ev.titulo}`}
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
          disabled={moviendo}
          title="Mover al siguiente mar–jue a las 10:00 (la franja que sí asiste)"
          aria-label={`${destinoSinConfirmar ? 'Reintentar reprogramación' : 'Mover a martes–jueves'} — ${ev.titulo}`}
          className="shrink-0 cursor-pointer rounded-md px-2 py-1 text-[10px] font-bold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          onClick={(e) => {
            e.stopPropagation()
            if (envioMovimiento.current) return
            const destino = destinoSinConfirmar ?? siguienteMarJue(ahora)
            envioMovimiento.current = true
            setMoviendo(true)
            void onMarJue(destino).then((confirmado) => setDestinoSinConfirmar(confirmado ? null : destino), () => setDestinoSinConfirmar(destino))
              .finally(() => { setMoviendo(false); envioMovimiento.current = false })
          }}
        >
          <CalendarClock className="mr-0.5 inline size-3" aria-hidden />{moviendo ? 'Guardando…' : destinoSinConfirmar ? 'Reintentar' : '→ mar–jue'}
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
      className={FILA_BASE}
    >
      <span className="size-2.5 shrink-0 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          <LeadHoverCard lead={lead}>
            <p className="truncate text-sm font-semibold">{lead.nombre_completo}</p>
          </LeadHoverCard>
          <Badge color={SEMAFORO.atencion} className="text-[10px]">
            Sin próxima acción
          </Badge>
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">
          {money(lead.monto_estimado, lead.moneda)} en juego — agéndale el siguiente paso
        </p>
      </div>
      {/* `conAgendar` es justo lo que pide esta fila: son los leads SIN próxima
          acción, y el texto de arriba les dice "agéndale el siguiente paso" —
          mandarlos a abrir la ficha para hacerlo era la fricción que el botón
          quita. Nunca se oculta por anti-duplicado: sin plan vivo, por
          definición (ver BotonAgendar). */}
      <AccionesContacto lead={lead} compacto soloIcono conAgendar />
      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </div>
  )
}
