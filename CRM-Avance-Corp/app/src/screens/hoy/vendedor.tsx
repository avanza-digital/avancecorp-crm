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
import { KpiCard } from '@/components/common/kpi-card'
import { AnimatedValue } from '@/components/common/animated-value'
import { AccionesContacto } from '@/components/app/contacto'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import {
  BUCKET_LABEL,
  capitalPorMoneda,
  capitalPrincipal,
  colaDe,
  colorMeta,
  diasDesdeReferencia,
  diasTxt,
  haceTexto,
  pctMeta,
  type ItemCola,
} from '@/lib/inteligencia'
import { planPorLead } from '@/lib/plan-lead'
import { colaHigiene, esViernesDeHigiene, siguienteMarJue, type ItemHigiene } from '@/lib/agenda-vistas'
import {
  agendaDeTareas,
  esDeHoy,
  fechaLima,
  tareaAEvento,
  type EventoAgenda,
} from '@/lib/agenda-derivada'
import { periodoLima } from '@/lib/objetivos'
import { useTipoCambio, usdAPen, type TipoCambio } from '@/lib/tipo-cambio'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { TIPO_EVENTO, type Lead, type Tarea } from '@/lib/tipos'
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
 * como un incumplimiento grave del asesor. Sin dato ≠ incumplido. */
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
 * abajo, así que `colaDe` salta a ese lead y su fila NO existe. El asesor leía
 * "+2 más vencidas — las tienes en la cola" sobre una cola que, encima, se
 * declaraba sin pendientes.
 *
 * Los dos criterios se dejan como están porque los dos son correctos, y son
 * respuestas a preguntas DISTINTAS: la agenda responde "¿ya pasó la hora?" (una
 * llamada de las 09:00 a las 15:00 llegó tarde, y esconderlo sería peor) y el
 * plan responde "¿este lead tiene dueño de su siguiente paso?" — que se contesta
 * por día a propósito, para que el asesor ordene su jornada como quiera y la
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
      className={FILA_BASE}
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
  vencidasAbajo,
  className,
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
                  <FilaAgenda key={ev.id} ev={ev} lead={leadPorId(ev.lead_id)} abrirLead={abrirLead} onCompletar={onCompletar} />
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
                <FilaAgenda key={ev.id} ev={ev} lead={leadPorId(ev.lead_id)} abrirLead={abrirLead} onCompletar={onCompletar} />
              ))}
              {alDia.length <= 2 && (
                <div className="mt-auto flex flex-col items-center gap-1 pb-2 pt-6 text-center">
                  <p className="text-xs text-muted-foreground">
                    {alDia.length === 0 ? 'Sin citas para hoy' : 'Día con espacio'} — agenda la
                    siguiente acción desde la ficha de un lead.
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
              )}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

export function HoyVendedor(): JSX.Element {
  const { ambito, actividades, tareas, objetivos, objetivosError, recargar, reprogramarTarea } = useCRMData()
  const { abrirLead, abrirNuevoLead } = usePanelesActions()
  const { yo } = useAuth()
  // Motor (Fase B): tarea seleccionada para cerrar desde la agenda héroe.
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  // Reloj vivo: re-tick por minuto y al volver a la pestaña — entra como
  // dependencia de la cola para que los "hace X" y semáforos se refresquen solos.
  const ahora = useAhora()

  // Universo del asesor — ambito.leads ya es SOLO su cartera. Memoizado porque
  // de él cuelgan `idsMios` y la agenda derivada: un array nuevo en cada render
  // reventaría esos memos sin que haya cambiado un solo dato.
  const mios = useMemo(() => ambito.leads.filter((l) => l.activo), [ambito.leads])
  const idsMios = useMemo(() => new Set(mios.map((l) => l.id)), [mios])
  const abiertos = mios.filter((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado')
  const convertidos = mios.filter((l) => l.etapa === 'convertido')
  const propuestas = abiertos.filter((l) => l.etapa === 'propuesta_enviada')

  // Capital en proceso — PEN y USD SIEMPRE por separado (jamás un total mixto).
  const { pen: capPEN, usd: capUSD } = capitalPorMoneda(abiertos)
  // …y la MONEDA QUE MANDA en el número grande sale del criterio compartido
  // (lib/inteligencia). Esta pantalla fijaba PEN a mano: el asesor con cartera
  // 100 % en dólares abría su día leyendo "S/ 0.00" mientras Cartera y Pipeline
  // —que ya usan este criterio— le mostraban su capital real. Tres pantallas
  // contradiciéndose sobre el mismo lead.
  const capital = capitalPrincipal(capPEN, capUSD)
  // …salvo para la META: el USD cuenta CONVERTIDO a soles al TC promedio de la
  // semana. La regla sigue viva (no se suman crudos): capMeta es soles + soles.
  const tc = useTipoCambio()
  const capUSDenPEN = usdAPen(capUSD, tc?.promedio ?? 0)
  const capMeta = capPEN + capUSDenPEN

  // Meta del mes: objetivos demo estáticos vs actuales calculados de SUS leads.
  // Misma semántica que supervisor/gerencia: capital EN PROCESO (PEN) vs objetivo.
  const meta = objetivos.vendedor
  // Sin NINGUNA meta configurada: no inventamos cuotas — mostramos "por definir".
  // Las tres cuentan: antes bastaba con que capital y ventas estuvieran fijadas
  // para que la conversión en blanco se colara al bloque de meta y se pintara.
  const sinMeta = meta.capitalObjetivo <= 0 && meta.ventasObjetivo <= 0 && meta.conversionObjetivo <= 0
  // La meta es MENSUAL, así que el numerador tiene que serlo también: comparar
  // el histórico de vida contra la cuota del mes dejaba a un asesor con 7
  // conversiones y meta 3 en "233 %" para siempre, y encima la misma pantalla
  // rotula ese conteo como "Histórico" doce líneas más arriba.
  //
  // Mes de CIERRE = `actualizado_en`: un lead terminal es inmutable para el API
  // (editar un cerrado está bloqueado), así que ese sello ≡ instante del cierre.
  // Es el MISMO contrato que ya usan lib/series-comerciales y
  // crm.metricas_agenda_fn — una segunda fórmula haría que Hoy y las tendencias
  // de gerencia contaran cierres distintos. Sin el dato (demo, o alta optimista
  // local) cae al mes de creación, igual que allí.
  const periodo = periodoLima(ahora)
  const cerradoEnElMes = (l: Lead): boolean => {
    const ms = Date.parse(l.actualizado_en ?? l.creado_en)
    return Number.isFinite(ms) && `${fechaLima(ms).slice(0, 7)}-01` === periodo
  }
  const convertidosMes = mios.filter((l) => l.etapa === 'convertido' && cerradoEnElMes(l))
  // Conversión DEL MES sobre lo RESUELTO en el mes (convertidos + descartados),
  // la misma definición que la serie de tendencia de gerencia. Sobre `mios`
  // (toda la cartera de vida) el porcentaje ni siquiera era del periodo.
  const resueltosMes = convertidosMes.length + mios.filter((l) => l.etapa === 'descartado' && cerradoEnElMes(l)).length
  // `null` = SIN DENOMINADOR, que no es lo mismo que 0 %. Antes esta rama
  // devolvía 0 y la fila se pintaba en rojo crítico —chip, barra al 0 % y
  // "0 % del objetivo"— junto a la nota "Sin leads resueltos este mes todavía":
  // la pantalla contradiciéndose sola, y le pasaba a TODO asesor cada día 1 de
  // mes. La fila lo trata como sin dato (ver `neutro` en MetaFila).
  const conversion = resueltosMes > 0 ? Math.round((convertidosMes.length / resueltosMes) * 100) : null

  // Cola de acción personal (el ámbito del vendedor no trae parkeados).
  // Fase B: los leads CON tarea pendiente ya tienen plan — su cola es la
  // agenda; aquí solo quedan speed-to-lead y los que se quedaron sin plan.
  // ⚠️ `plan.vigente` y NO "tiene alguna tarea": una pendiente que venció hace
  // dos semanas no es un plan (ver lib/plan-lead.ts). `plan.conTarea` —viva o
  // muerta— es el que necesita la higiene del viernes, que ya lista las
  // vencidas por su cuenta y duplicaría el lead si recibiera `vigente`.
  const plan = useMemo(() => planPorLead(tareas, ahora), [tareas, ahora])
  const conTarea = plan.conTarea
  const cola = useMemo(
    () => colaDe(ambito.leads, actividades, ahora, plan),
    [ambito.leads, actividades, ahora, plan],
  )

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
    const mias = tareas.filter((t) => t.lead_id && idsMios.has(t.lead_id))
    return agendaDeTareas(mias, ahora).filter((ev) => ev.vencida || esDeHoy(ev, ahora))
  }, [tareas, idsMios, ahora])

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
  const leadsListadosEnAgenda = useMemo(
    () => new Set(listadasEnAgenda.map((ev) => ev.lead_id)),
    [listadasEnAgenda],
  )
  // … y por TAREA para la higiene del viernes (sus filas son tareas; el id del
  // evento de agenda ES el id de la tarea, ver onCompletar).
  const tareasListadasEnAgenda = useMemo(
    () => new Set(listadasEnAgenda.map((ev) => ev.id)),
    [listadasEnAgenda],
  )
  // Cuántas vencidas hay EN TOTAL: el vacío de la cola las necesita para no
  // cantar "al día" mientras la tarjeta vecina cuenta N vencidas.
  const nVencidasAgenda = useMemo(() => agenda.filter((ev) => ev.vencida).length, [agenda])
  // EXCEPCIÓN deliberada — el speed-to-lead: un lead sin primer contacto NUNCA
  // se entierra (regla de la casa), y su fila es la única que trae el cronómetro
  // en minutos, que la agenda no muestra.
  const colaSinRepetir = cola.filter(
    (i) => i.bucket === 'sin_responder' || !leadsListadosEnAgenda.has(i.lead.id),
  )
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
          tareas.filter((t) => t.lead_id && idsMios.has(t.lead_id)),
          ambito.leads,
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
  const colaPintada = colaVisible.slice(0, COLA_VISIBLES)
  // ¿DÓNDE están de verdad las vencidas que la franja ámbar colapsa en "+N más"?
  // Se cuenta lo que la mitad de abajo PINTA (cola ya recortada + filas de
  // higiene), no lo que se supone que debería pintar: el pie de la agenda
  // prometía la cola de al lado para todas y para las vencidas de HOY era
  // mentira — su lead sigue con plan vigente y `colaDe` lo salta (el porqué,
  // largo, en `textoRestoVencidas`). Un lead con varias vencidas cuenta por cada
  // una: su fila está abajo, que es lo que el pie afirma.
  const leadsEnCola = new Set(colaPintada.map((i) => i.lead.id))
  const tareasEnHigiene = new Set(tareasHigiene.map((i) => i.tarea.id))
  const vencidasAbajo = agenda.filter(
    (ev) =>
      ev.vencida &&
      !tareasListadasEnAgenda.has(ev.id) &&
      (tareasEnHigiene.has(ev.id) || leadsEnCola.has(ev.lead_id)),
  ).length
  // Conteo por severidad para el mini-resumen de la cola (rojo/ámbar/azul).
  const porSev = { critica: 0, media: 0, baja: 0 }
  for (const i of colaVisible) porSev[i.sev] += 1
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

      {/* KPIs personales — capital PEN con el USD aparte (nunca sumados).
          Sin cartera NO pintamos una fila de ceros extrabold: vacío honesto que
          encamina a la acción real (pedir asignación o registrar el primer lead). */}
      {mios.length === 0 ? (
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
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <KpiCard
            label="Capital en proceso"
            value={capital.valor}
            icon={Wallet}
            color="#2563eb"
            sub={
              capital.otra
                ? `Pipeline activo (PEN) · +${capital.otra} aparte`
                : capital.soloDolares
                  ? 'Pipeline activo (USD)'
                  : capPEN === 0 && abiertos.length > 0
                    ? 'Sin montos estimados — complétalos en cada ficha'
                    : 'Pipeline activo (PEN)'
            }
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
            sub={
              propuestas.length > 0
                ? 'Esperando respuesta del cliente'
                : abiertos.length > 0
                  ? 'Ninguna en la calle — revisa tus reuniones'
                  : 'Sin leads abiertos por ahora'
            }
            delay={120}
          />
          <KpiCard
            label="Convertidos"
            value={String(convertidos.length)}
            icon={Trophy}
            color="#111e3d"
            sub={
              convertidos.length > 0
                ? 'Histórico · clientes ganados'
                : 'Aún sin cierres — tu primera venta sale de la cola'
            }
            delay={180}
          />
        </div>
      )}

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
          vencidasAbajo={vencidasAbajo}
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
                vencido, mueve a mar–jue las citas de quien no asistió y que ningún lead quede sin próxima acción.
              </p>
            )}
            {nCola === 0 ? (
              nVencidasAgenda > 0 ? (
                // Cola vacía NO es "al día": lo vencido está en la agenda de al
                // lado (donde vive su botón de cerrar). Decir "sin pendientes"
                // mientras el badge vecino canta N vencidas es la pantalla
                // contradiciéndose, y el asesor se va a casa creyendo que
                // terminó. El vacío REMITE a la agenda en vez de negarla.
                <div className="flex flex-col items-center gap-2 py-10 text-center">
                  <AlertTriangle className="size-8 text-warning" />
                  <p className="text-sm font-bold">Lo pendiente está en tu agenda</p>
                  <p className="text-xs text-muted-foreground">
                    {nVencidasAgenda === 1
                      ? 'Tienes 1 seguimiento vencido'
                      : `Tienes ${nVencidasAgenda} seguimientos vencidos`}{' '}
                    en «Tu agenda de hoy» — ciérralos o reprográmalos desde ahí.
                  </p>
                </div>
              ) : (
                <div className="flex flex-col items-center gap-2 py-10 text-center">
                  <CircleCheckBig className="size-8 text-accent" />
                  <p className="text-sm font-bold">{higiene ? 'Pipeline limpio ✦' : 'Al día ✦ sin pendientes'}</p>
                  <p className="text-xs text-muted-foreground">
                    {higiene
                      ? 'Nada vencido, las citas reagendadas en su día y toda tu cartera con próxima acción. Buen fin de semana.'
                      : 'No tienes leads esperando respuesta ni seguimientos vencidos.'}
                  </p>
                </div>
              )
            ) : (
              <>
                {/* Mini-resumen por severidad: la respuesta a "¿cómo viene mi
                    cola?" antes de bajar a las filas (rojo/ámbar/azul, sin verde). */}
                {colaVisible.length > 1 && (
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-muted/50 px-3 py-2 text-[11px]">
                    {(['critica', 'media', 'baja'] as const).map(
                      (sev) =>
                        porSev[sev] > 0 && (
                          <span key={sev} className="inline-flex items-center gap-1.5 font-semibold text-foreground/80">
                            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_COLOR[sev] }} aria-hidden />
                            <span className="tabular-nums">{porSev[sev]}</span>{' '}
                            {sev === 'critica'
                              ? porSev.critica === 1 ? 'crítica' : 'críticas'
                              : sev === 'media'
                                ? porSev.media === 1 ? 'media' : 'medias'
                                : porSev.baja === 1 ? 'baja' : 'bajas'}
                          </span>
                        ),
                    )}
                  </div>
                )}
                {colaPintada.map((item) => (
                  <FilaCola key={item.lead.id} item={item} abrirLead={abrirLead} ahora={ahora} />
                ))}
                {colaVisible.length > COLA_VISIBLES && (
                  <p className="px-2 text-[11px] text-muted-foreground">
                    +{colaVisible.length - COLA_VISIBLES} más en cola — trabájalos desde Cartera.
                  </p>
                )}
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
                <p className="text-xs font-semibold text-foreground/80">Ventas cerradas este mes</p>
                <p className="text-xs font-bold tabular-nums">{convertidosMes.length}</p>
              </div>
              <NotaUSD capUSD={capUSD} enPEN={capUSDenPEN} tc={tc} />
              {objetivosError ? (
                // Ceros por FALLO DE LECTURA ≠ ceros porque gerencia no fijó
                // nada (`objetivosError` del store). Decir "por definir" cuando
                // lo que hubo fue un error de red le hace creer al asesor que
                // nadie le puso meta, y deja de buscarla. Los dos números de
                // arriba SÍ son reales (salen de su cartera): lo único que
                // falta es el denominador.
                <div className="flex flex-wrap items-center gap-2">
                  <p className="text-[11px] text-warning-text">
                    No pudimos cargar tu meta del mes — los datos de arriba son tuyos y son reales.
                  </p>
                  <Button variant="ghost" size="sm" onClick={() => void recargar()}>
                    Reintentar
                  </Button>
                </div>
              ) : (
                <p className="text-[11px] text-muted-foreground">
                  Meta mensual por definir — cuando la establezcan, verás aquí tu avance.
                </p>
              )}
            </div>
          ) : (
            <div className="grid gap-x-8 gap-y-4 md:grid-cols-3">
              {/* Cada fila mira SU propio objetivo: que gerencia haya fijado
                  capital no significa que haya fijado conversión, y una fila con
                  objetivo 0 no puede pintarse como incumplida (ver MetaFila). */}
              <MetaFila
                icon={Wallet}
                label="Capital"
                valorTxt={moneyK(capMeta)}
                metaTxt={moneyK(meta.capitalObjetivo)}
                pct={pctMeta(capMeta, meta.capitalObjetivo)}
                delay={0}
                neutro={meta.capitalObjetivo <= 0 ? SIN_META : undefined}
                nota={<NotaUSD capUSD={capUSD} enPEN={capUSDenPEN} tc={tc} />}
              />
              <MetaFila
                icon={Trophy}
                label="Ventas cerradas"
                valorTxt={String(convertidosMes.length)}
                metaTxt={String(meta.ventasObjetivo)}
                pct={pctMeta(convertidosMes.length, meta.ventasObjetivo)}
                delay={90}
                neutro={meta.ventasObjetivo <= 0 ? SIN_META : undefined}
                // El KPI de arriba dice "Histórico"; esta fila es del MES. Si
                // los dos números difieren se dice en voz alta, o la misma
                // pantalla parece contradecirse.
                nota={
                  convertidos.length > convertidosMes.length ? (
                    <p className="text-[11px] text-muted-foreground">
                      Cerradas este mes · {convertidos.length} en total desde que llevas cartera.
                    </p>
                  ) : undefined
                }
              />
              {/* El valor es "—" y no "0 %" cuando no hay resueltos: un
                  porcentaje sin denominador no existe, y escribirlo como 0 %
                  ya es afirmar que el asesor no convirtió nada. */}
              <MetaFila
                icon={TrendingUp}
                label="Conversión"
                valorTxt={conversion == null ? '—' : `${conversion}%`}
                metaTxt={`${meta.conversionObjetivo}%`}
                pct={pctMeta(conversion ?? 0, meta.conversionObjetivo)}
                delay={180}
                neutro={
                  meta.conversionObjetivo <= 0
                    ? SIN_META
                    : conversion == null
                      ? 'Sin leads resueltos este mes todavía — el % sale con el primer cierre'
                      : undefined
                }
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
  // El reloj arranca cuando el lead LLEGÓ A SUS MANOS (`tenencia_desde`), no
  // cuando entró al CRM: entre una cosa y otra hay cola de Rosa y bandeja del
  // supervisor, y esa espera no es suya. Sin el dato (demo, o base sin la
  // migración) degrada a `creado_en`, el comportamiento de siempre.
  const desde = item.lead.tenencia_desde ?? item.lead.creado_en
  const minutos = item.bucket === 'sin_responder' && ahora != null
    ? Math.max(0, Math.floor((ahora - Date.parse(desde)) / 60_000))
    : null
  const cronometro = minutos != null && minutos < 24 * 60
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
          style={{ color: cronometro.color, background: `color-mix(in srgb, ${cronometro.color} 12%, transparent)` }}
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
  onMarJue: () => void
}): JSX.Element {
  const t = item.tarea
  const vencida = item.k === 'vencida'
  const c = vencida ? SEMAFORO.critico : SEMAFORO.violeta
  const abrir = () => t.lead_id && abrirLead(t.lead_id)
  const motivo = vencida
    ? `Venció ${haceTexto(diasDesdeReferencia(t.vence_en, ahora))} — ciérrala o reprográmala`
    : `El cliente no asistió — la nueva cita cae ${tareaAEvento(t, ahora).cuando}; mejor mar–jue`
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
      className={FILA_BASE}
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
          <Badge color={c} className="text-[10px]">{vencida ? 'Vencida' : 'No asistió'}</Badge>
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
      className={FILA_BASE}
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
