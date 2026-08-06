// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
// ya trae: sus leads + los de sus vendedores + parkeados de SU bandeja.
// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
import { useMemo, useState, type JSX } from 'react'
import { toast } from 'sonner'
import {
  AlarmClock,
  AlertTriangle,
  ChevronRight,
  Inbox,
  ListChecks,
  Target,
  UserPlus,
  Users,
  UsersRound,
  Wallet,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Progress } from '@/components/ui/progress'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { AccionesContacto } from '@/components/app/contacto'
import { AgendaEquipoPanel } from './agenda-equipo'
import {
  BUCKET_LABEL,
  DIA_MS,
  capitalPorMoneda,
  colaDe,
  colorMeta,
  diasSinActividad,
  estancados,
  haceTexto,
  indexarUltimaActividad,
  metricasPorVendedor,
  pctMeta,
} from '@/lib/inteligencia'
import { cierresDelMes } from '@/lib/cierres-del-mes'
import { planPorLead } from '@/lib/plan-lead'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { fechaLima } from '@/lib/agenda-derivada'
import { metaConversionAplicable } from '@/lib/objetivos'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { mensajeDeError } from '@/data/crm-api'
import { useMetricasAgenda } from '@/data/crm-queries'
import { money, moneyK } from '@/lib/format'
import { cn } from '@/lib/utils'
import { ETAPA_INFO, origenLabel, type Lead } from '@/lib/tipos'

// Tope de la cola del equipo: los primeros son la plata (colaDe ya ordena por
// severidad); el resto vive tras "Ver los N pendientes" para que la Agenda del
// equipo (montada debajo) no quede varios pantallazos abajo.
const COLA_VISIBLES = 8

// Texto neutro de una meta que gerencia todavía no fijó para el mes.
const SIN_META = 'Sin meta fijada para este mes'

/** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
function semaforoDias(d: number): string {
  if (d > 5) return SEMAFORO.critico
  if (d >= 2) return SEMAFORO.atencion
  return SEMAFORO.ok
}

export function HoySupervisor(): JSX.Element {
  const {
    ambito,
    actividades,
    tareas,
    reasignar,
    objetivos,
    objetivosError,
    recargar,
    equipo,
  } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  // Reloj vivo: tick por minuto y al volver a la pestaña — dependencia del memo
  // para que cola/ranking/alertas SLA se refresquen solos al pasar el tiempo.
  const ahora = useAhora()
  // Vendedor elegido en el select de cada lead parkeado (leadId → perfil_id).
  const [sel, setSel] = useState<Record<string, string>>({})
  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
  const [colaExpandida, setColaExpandida] = useState(false)

  const d = useMemo(() => {
    const abiertos = ambito.leads.filter(
      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado',
    )
    const parkeados = abiertos.filter((l) => l.vendedor_id == null)
    const asignados = abiertos.filter((l) => l.vendedor_id != null)
    // Capital en proceso del EQUIPO: solo abiertos CON vendedor. Los parkeados
    // no suman (nadie los trabaja aún) y PEN/USD jamás se mezclan en un total.
    const { pen: capitalPEN, usd: capitalUSD } = capitalPorMoneda(asignados)
    // Índice de última actividad compartido: se calcula UNA vez y se reutiliza
    // en cola/ranking/alertas (y en la bandeja) en lugar de reindexar por llamada.
    const indice = indexarUltimaActividad(actividades)
    // Fase B: un lead con tarea pendiente tiene PLAN — sale de la cola por
    // inactividad y de "estancados" (la señal de riesgo deja de pelearse con
    // la reunión agendada del vendedor).
    // `vigente` y no "tiene alguna tarea": una pendiente vencida hace semanas
    // no es un plan, y escondía al lead justo cuando más abandonado estaba.
    const plan = planPorLead(tareas, ahora)
    // colaDe ya no recibe índice: construye el suyo de CONTACTO (ver
    // indexarUltimoContacto — la `reasignacion` del sistema vaciaba la cola).
    const cola = colaDe(ambito.leads, actividades, ahora, plan)
    const sinTocar = cola.filter((i) => i.bucket === 'sin_responder').length
    const rank = metricasPorVendedor(ambito.vendedores, ambito.leads, actividades, ahora, indice)
    const alertas = estancados(ambito.leads, actividades, 5, ahora, indice, plan.vigente)
    // Marcador del MES. La tarjeta "Meta del equipo" se rotula "este mes" y su
    // objetivo sale de crm.objetivos, que guarda UNA fila por mes calendario;
    // aquí se contaban los `etapa === 'convertido'` de toda la vida (y la
    // conversión salía de conversionGlobal, que tampoco mira el periodo), así
    // que desde el segundo mes el avance mentía hacia arriba para siempre —
    // con esta cifra se juzga al equipo, así que importa más que la propia.
    // Definición ÚNICA en lib/cierres-del-mes: el mismo contrato de
    // `actualizado_en` que ya usan las series de tendencia de gerencia.
    const cierres = cierresDelMes(ambito.leads, ahora)
    return { abiertos, parkeados, asignados, capitalPEN, capitalUSD, indice, cola, sinTocar, rank, alertas, cierres }
  }, [ambito, actividades, tareas, ahora])

  const meta = objetivos.supervisor
  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosError)
  // ── Marcador del mes: cada fila mira SU propio objetivo ──
  // Capital sin objetivo sigue neutro. Conversión, en cambio, arranca en 15 %
  // hasta que Gerencia guarde otra meta; una lectura fallida queda indisponible.
  const filasMeta: Array<{ label: string; txt: string; pct: number; sinDato: string | null }> = [
    {
      label: 'Capital en proceso',
      txt:
        meta.capitalObjetivo > 0
          ? `${moneyK(d.capitalPEN)} de ${moneyK(meta.capitalObjetivo)}`
          : moneyK(d.capitalPEN),
      pct: pctMeta(d.capitalPEN, meta.capitalObjetivo),
      sinDato: meta.capitalObjetivo > 0 ? null : SIN_META,
    },
    {
      label: 'Conversión',
      // Sin nada resuelto en el mes no hay porcentaje que mostrar: un "0 %" ahí
      // es "sin dato", no incumplimiento (el caso natural el día 1 del mes).
      txt:
        d.cierres.conversion == null
          ? '—'
          : metaConversion != null
            ? `${d.cierres.conversion}% de ${metaConversion}%`
            : `${d.cierres.conversion}%`,
      pct: pctMeta(d.cierres.conversion ?? 0, metaConversion ?? 0),
      sinDato:
        metaConversion == null
          ? 'Meta de conversión no disponible'
          : d.cierres.conversion == null
            ? 'Todavía no se resolvió ningún lead este mes'
            : null,
    },
  ]

  // ── Fase F — Agenda del equipo (RPC crm.metricas_agenda_fn) ──
  // Periodo fijo: últimos 7 días con el reloj vivo (se corre solo al pasar la
  // medianoche de Lima). En demo se alimenta del fixture sin tocar la red.
  const sesionReal = Boolean(yo && !yo.demo)
  const hastaMA = fechaLima(ahora)
  const desdeMA = fechaLima(ahora - 6 * DIA_MS)
  const consultaAgenda = useMetricasAgenda(sesionReal, desdeMA, hastaMA)
  // En sesión real con data aún undefined y sin error, viaja undefined a
  // propósito: el panel muestra su estado de carga.
  const datosAgenda = sesionReal ? consultaAgenda.data : metricasAgendaDemo(desdeMA, hastaMA)
  const errorAgenda =
    sesionReal && consultaAgenda.error
      ? mensajeDeError(
          consultaAgenda.error,
          'No pudimos consultar la agenda del equipo. Revisa tu conexión e inténtalo otra vez.',
        )
      : null
  const cargandoAgenda =
    sesionReal && (consultaAgenda.isPending || consultaAgenda.isFetching)
  // Rezagos de agenda por miembro (vendedor_id → métrica) para que la señal de
  // vencidas / sin acción / no-shows viva DENTRO de la fila de "Tu equipo hoy":
  // la persona se juzga en un solo lugar, sin cruzar a la tabla de la izquierda.
  const rezagosAgenda = useMemo(
    () => new Map((datosAgenda?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
    [datosAgenda],
  )

  /** Asigna un parkeado al vendedor elegido en su select. */
  const asignar = (l: Lead) => {
    const vId = sel[l.id]
    if (!vId) return
    const res = reasignar(l.id, vId)
    if (!res.ok) {
      // Los errores de permiso ya los toastea el store (doble defensa).
      if (res.error && !res.error.startsWith('Sin permiso')) toast.error(res.error)
      return
    }
    const v = ambito.vendedores.find((m) => m.perfil_id === vId)
    toast.success(`${l.nombre_completo} asignado a ${v?.nombre_completo ?? 'vendedor'}${yo?.demo ? ' (demo)' : ''}`)
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* ── KPIs del equipo ── */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Capital en proceso del equipo"
          value={money(d.capitalPEN)}
          icon={Wallet}
          color={SEMAFORO.ok}
          sub={d.capitalUSD > 0 ? `PEN · +${moneyK(d.capitalUSD, 'USD')} aparte` : 'PEN · abiertos con vendedor'}
          delay={0}
        />
        <KpiCard
          label="Leads activos del equipo"
          value={String(d.asignados.length)}
          icon={Users}
          color={SEMAFORO.violeta}
          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'vendedor' : 'vendedores'} a cargo`}
          delay={60}
        />
        <KpiCard
          label="Nuevos sin responder"
          value={String(d.sinTocar)}
          icon={AlertTriangle}
          color={d.sinTocar > 0 ? SEMAFORO.critico : SEMAFORO.ok}
          sub={d.sinTocar > 0 ? 'Nuevos sin primer contacto — urge' : 'Todos los nuevos fueron contactados'}
          delay={120}
        />
        <KpiCard
          label="Por repartir"
          value={String(d.parkeados.length)}
          icon={Inbox}
          color={d.parkeados.length > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
          sub={d.parkeados.length > 0 ? 'En tu bandeja sin vendedor' : 'Bandeja de reparto vacía'}
          delay={180}
        />
      </div>

      {/* ── Bandeja prioritaria: parkeados por repartir ── */}
      {d.parkeados.length > 0 && (
        <Card className="overflow-hidden" style={{ borderColor: `color-mix(in srgb, ${SEMAFORO.atencion} 45%, transparent)` }}>
          <SectionHead
            icon={Inbox}
            title="Por repartir — tu bandeja"
            right={
              <Badge color={SEMAFORO.atencion} dot>
                {d.parkeados.length} {d.parkeados.length === 1 ? 'pendiente' : 'pendientes'}
              </Badge>
            }
          />
          <div className="divide-y divide-border/60 border-t border-border/60">
            {d.parkeados.map((l) => {
              const dias = diasSinActividad(l, actividades, ahora, d.indice)
              return (
                <div key={l.id} className="flex flex-wrap items-center gap-3 px-5 py-3">
                  <button
                    type="button"
                    onClick={() => abrirLead(l.id)}
                    aria-label={`Abrir ficha de ${l.nombre_completo}`}
                    className="flex min-w-0 flex-1 basis-56 cursor-pointer items-center gap-2.5 rounded-lg text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30"
                  >
                    <Avatar nombre={l.nombre_completo} genero={l.genero ?? null} />
                    <div className="min-w-0 leading-tight">
                      <p className="truncate text-sm font-semibold">{l.nombre_completo}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {origenLabel(l.origen)} · {l.monto_estimado != null ? money(l.monto_estimado, l.moneda) : 'sin monto'} · sin movimiento {haceTexto(dias)}
                      </p>
                    </div>
                  </button>
                  <Badge color={ETAPA_INFO[l.etapa].color} dot>
                    {ETAPA_INFO[l.etapa].label}
                  </Badge>
                  <div className="flex items-center gap-2">
                    <div className="w-[180px]">
                      <Select
                        aria-label={`Vendedor para ${l.nombre_completo}`}
                        className="h-8 text-xs"
                        value={sel[l.id] ?? ''}
                        onChange={(e) => setSel((s) => ({ ...s, [l.id]: e.target.value }))}
                      >
                        <option value="" disabled>
                          Elegir vendedor…
                        </option>
                        {ambito.vendedores.map((v) => (
                          <option key={v.perfil_id} value={v.perfil_id}>
                            {v.nombre_completo}
                          </option>
                        ))}
                      </Select>
                    </div>
                    <Button size="sm" disabled={!sel[l.id]} onClick={() => asignar(l)}>
                      <UserPlus /> Asignar
                    </Button>
                  </div>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-5">
        <div className="space-y-4 lg:col-span-3">
          {/* ── Cola del equipo (con dueño de cada item) ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={ListChecks}
              title="Cola del equipo"
              right={
                d.cola.length > 0 ? (
                  <Badge color={SEV_COLOR[d.cola[0]!.sev]} dot>
                    {d.cola.length} {d.cola.length === 1 ? 'pendiente' : 'pendientes'}
                  </Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">al día</span>
                )
              }
            />
            {d.cola.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  Sin pendientes — el equipo está al día con todos sus leads abiertos.
                </p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {/* Fila = div role="button" (no <button>: contiene los links de
                    AccionesContacto y un botón no puede anidar interactivos). */}
                {(colaExpandida ? d.cola : d.cola.slice(0, COLA_VISIBLES)).map((i) => {
                  const abrir = () => abrirLead(i.lead.id)
                  return (
                    <div
                      key={i.lead.id}
                      role="button"
                      tabIndex={0}
                      onClick={abrir}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault()
                          abrir()
                        }
                      }}
                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
                      className="flex w-full cursor-pointer items-center gap-3 px-5 py-3 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                    >
                      <span
                        className="size-2 shrink-0 rounded-full"
                        style={{ background: SEV_COLOR[i.sev] }}
                        aria-hidden
                      />
                      <div className="min-w-0 flex-1 leading-tight">
                        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                          <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
                          <Badge color={SEV_COLOR[i.sev]}>{BUCKET_LABEL[i.bucket]}</Badge>
                        </div>
                        <p className="truncate text-xs text-muted-foreground">{i.motivo}</p>
                      </div>
                      {i.lead.monto_estimado != null && (
                        <span className="hidden shrink-0 text-xs font-extrabold tabular-nums text-primary sm:inline">
                          {moneyK(i.lead.monto_estimado, i.lead.moneda)}
                        </span>
                      )}
                      {i.lead.vendedor_nombre ? (
                        <span className="flex shrink-0 items-center gap-1.5">
                          <Avatar nombre={i.lead.vendedor_nombre} className="size-6 text-[9px]" />
                          <span className="hidden max-w-[110px] truncate text-xs text-muted-foreground md:inline">
                            {i.lead.vendedor_nombre}
                          </span>
                        </span>
                      ) : (
                        <Badge color={SEMAFORO.atencion}>sin asignar</Badge>
                      )}
                      <AccionesContacto lead={i.lead} compacto />
                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                    </div>
                  )
                })}
                {d.cola.length > COLA_VISIBLES && (
                  <button
                    type="button"
                    onClick={() => setColaExpandida((e) => !e)}
                    aria-expanded={colaExpandida}
                    className="flex w-full cursor-pointer items-center justify-center gap-1 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none"
                  >
                    <ChevronRight
                      className={cn('size-3.5 shrink-0 transition-transform', colaExpandida && 'rotate-90')}
                      aria-hidden
                    />
                    {colaExpandida
                      ? `Mostrar solo los ${COLA_VISIBLES} más urgentes`
                      : `Ver los ${d.cola.length} pendientes`}
                  </button>
                )}
              </div>
            )}
          </Card>

          {/* ── Agenda del equipo (Fase F — quién registra, cierra y arrastra) ── */}
          <AgendaEquipoPanel
            datos={datosAgenda}
            cargando={cargandoAgenda}
            error={errorAgenda}
            modoDemo={yo?.demo === true}
            onReintentar={() => {
              if (sesionReal) void consultaAgenda.refetch()
            }}
            equipo={equipo}
          />
        </div>
        <div className="space-y-4 lg:col-span-2">
          {/* ── Tu equipo hoy (semáforo por vendedor) ── */}
          <Card className="overflow-hidden">
            <SectionHead icon={UsersRound} title="Tu equipo hoy" />
            {d.rank.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">Sin vendedores a cargo.</p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {d.rank.map((r) => {
                  const c = semaforoDias(r.diasSinActividadMax)
                  // Rezago de agenda del miembro (mismos umbrales del panel
                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
                  const rez = rezagosAgenda.get(r.m.perfil_id)
                  const conRezago =
                    rez != null && (rez.no_asistio >= 2 || rez.vencidas > 0 || rez.leads_sin_accion > 0)
                  return (
                    <div key={r.m.perfil_id} className="px-5 py-3">
                      <div className="flex items-center gap-2.5">
                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
                        <div className="min-w-0 flex-1 leading-tight">
                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
                          <p className="text-[11px] tabular-nums text-muted-foreground">
                            {r.activos} activos · {r.conversion}% conversión
                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
                          </p>
                        </div>
                        <div className="shrink-0 text-right leading-tight">
                          <p className="text-sm font-extrabold tabular-nums text-primary">
                            {moneyK(r.capitalPEN)}
                          </p>
                          {r.capitalUSD > 0 && (
                            <p className="text-[10.5px] tabular-nums text-muted-foreground">
                              +{moneyK(r.capitalUSD, 'USD')}
                            </p>
                          )}
                        </div>
                      </div>
                      <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 gap-y-1 pl-[46px]">
                        <span className="size-2 shrink-0 rounded-full" style={{ background: c }} aria-hidden />
                        <span className="text-[11px] text-muted-foreground">
                          {r.activos === 0
                            ? 'Sin leads abiertos'
                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
                        </span>
                        {conRezago && rez != null && (
                          <span className="ml-auto flex flex-wrap items-center gap-1">
                            {rez.no_asistio >= 2 && (
                              <Badge color={SEMAFORO.critico}>{rez.no_asistio} no asistió</Badge>
                            )}
                            {rez.vencidas > 0 && (
                              <Badge color={SEMAFORO.atencion}>
                                {rez.vencidas} {rez.vencidas === 1 ? 'vencida' : 'vencidas'}
                              </Badge>
                            )}
                            {rez.leads_sin_accion > 0 && (
                              <Badge color={SEMAFORO.atencion}>{rez.leads_sin_accion} sin acción</Badge>
                            )}
                          </span>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </Card>

          {/* ── Meta del equipo (objetivo MENSUAL vs avance del mes) ── */}
          <Card>
            <SectionHead
              icon={Target}
              title="Meta del equipo"
              right={<span className="text-xs text-muted-foreground">este mes</span>}
            />
            <CardContent className="space-y-4 pb-5 pt-0">
              {metaConversion == null ? (
                <div className="space-y-2">
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-xs font-semibold text-foreground/80">Capital en proceso (PEN)</span>
                    <span className="text-xs font-bold tabular-nums text-primary">{moneyK(d.capitalPEN)}</span>
                  </div>
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-xs font-semibold text-foreground/80">Conversión este mes</span>
                    <span className="text-xs font-bold tabular-nums text-primary">{d.cierres.conversion == null ? '—' : `${d.cierres.conversion}%`}</span>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-[10.5px] text-warning-text">
                      No pudimos cargar la meta mensual del equipo.
                    </p>
                    <Button variant="ghost" size="sm" onClick={() => void recargar()}>
                      Reintentar
                    </Button>
                  </div>
                </div>
              ) : (
                <>
                  {filasMeta.map((f) => (
                    <div key={f.label}>
                      <div className="mb-1.5 flex items-baseline justify-between gap-2">
                        <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
                        <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
                      </div>
                      {/* Sin dato ≠ incumplimiento: ni una meta que gerencia no
                          fijó ni un mes sin nada resuelto pueden pintarse como
                          un 0 % en rojo crítico. Van en neutro y sin barra. */}
                      {f.sinDato ? (
                        <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
                      ) : (
                        <Progress value={f.pct} color={colorMeta(f.pct)} />
                      )}
                    </div>
                  ))}
                  {/* El marcador es del MES; si el equipo acumula más cierres de
                      vida se dice en voz alta, o el número parece perdido. */}
                  <p className="text-[10.5px] text-muted-foreground">
                    Meta en PEN — lo captado en USD no entra a este total.
                  </p>
                </>
              )}
            </CardContent>
          </Card>

          {/* ── Alertas SLA (≥5 días sin actividad) ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={AlarmClock}
              title="Leads sin movimiento"
              right={
                d.alertas.length > 0 ? (
                  <Badge color={SEMAFORO.critico} dot>
                    {d.alertas.length}
                  </Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">sin alertas</span>
                )
              }
            />
            {d.alertas.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  Ningún lead del equipo lleva 5 días o más sin actividad.
                </p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {d.alertas.map((a) => (
                  <button
                    key={a.lead.id}
                    type="button"
                    onClick={() => abrirLead(a.lead.id)}
                    aria-label={`Abrir ficha de ${a.lead.nombre_completo}`}
                    className="flex w-full cursor-pointer items-center gap-2.5 px-5 py-2.5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                  >
                    <div className="min-w-0 flex-1 leading-tight">
                      <p className="truncate text-sm font-semibold">
                        {a.lead.nombre_completo}{' '}
                        <span className="text-xs font-medium text-muted-foreground">
                          ({a.lead.vendedor_nombre ?? 'sin asignar'})
                        </span>
                      </p>
                      <p
                        className="text-[11px] font-semibold"
                        style={{ color: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
                      >
                        Sin actividad {haceTexto(a.dias)}
                      </p>
                    </div>
                    <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                  </button>
                ))}
              </div>
            )}
          </Card>
        </div>
      </div>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
      </p>
    </div>
  )
}
