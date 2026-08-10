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
  colorMeta,
  diasSinActividad,
  haceTexto,
  indexarUltimaActividad,
  pctMeta,
} from '@/lib/inteligencia'
import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  capitalObjetivo,
  capitalReal,
  metaConversionAplicable,
} from '@/lib/objetivos'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { mensajeDeError } from '@/data/crm-api'
import { useMetricasAgenda } from '@/data/crm-queries'
import { money, moneyK } from '@/lib/format'
import { cn } from '@/lib/utils'
import { ETAPA_INFO, origenLabel, type Lead } from '@/lib/tipos'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { totalEnSoles } from '@/lib/capital-unificado'
import { useTipoCambio } from '@/lib/tipo-cambio'

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
    cumplimientoMetas,
    cumplimientoMetasError,
    recargar,
    equipo,
  } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola — en sesión real
  // esos vencimientos ya llegan resueltos dentro de cola_accion_fn, así que el
  // RPC de estado SLA ni se pide (habilitado = demo).
  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
  // Reloj vivo: tick por minuto y al volver a la pestaña — la bandeja y los
  // "hace N" se refrescan solos al pasar el tiempo.
  const ahora = useAhora()
  // Vendedor elegido en el select de cada lead parkeado (leadId → perfil_id).
  const [sel, setSel] = useState<Record<string, string>>({})
  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
  const [colaExpandida, setColaExpandida] = useState(false)

  // ── F1b: los agregados llegan del servidor (o del espejo demo vivo) ──
  // resumen_cartera_fn → tiles de capital/activos/parkeados; cola_accion_fn →
  // cola + estancados + tile "sin responder"; metricas_vendedores_fn → ranking.
  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
  const resumen = resumenOp.resumen
  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice)
  const cola = colaOp.cola
  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividades)
  const rank = vendedoresOp.metricas?.filas ?? null
  // TC izado UNA vez por pantalla: el hook no pasa por TanStack (sin cache ni
  // dedupe), así que uno por fila multiplicaría las llamadas a la edge.
  const { tc } = useTipoCambio()

  // La BANDEJA es una lista operable (select + Asignar): sigue en cliente
  // hasta F2/F3. Su índice de actividad solo recorre lo que se pinta.
  const d = useMemo(() => {
    const parkeados = ambito.leads.filter(
      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null,
    )
    const indice = indexarUltimaActividad(actividades)
    return { parkeados, indice }
  }, [ambito, actividades])

  // Nombres para los estancados del payload (el servidor no manda nombres de
  // personas): join con el roster completo, una sola vez por render.
  const nombrePorId = useMemo(
    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
    [equipo],
  )

  const errorIndicadores = !yo?.demo
    && Boolean(resumenOp.error || colaOp.error || vendedoresOp.error)
  const reintentarIndicadores = () => {
    if (resumenOp.error) void resumenOp.recargar()
    if (colaOp.error) void colaOp.recargar()
    if (vendedoresOp.error) void vendedoresOp.recargar()
  }

  const meta = objetivos.supervisor
  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosError)
  const cumplimiento = cumplimientoMetas?.supervisor ?? null
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  const conversionConfirmada = cumplimiento?.conversionReal ?? null
  // ── Cumplimiento del mes: cada fila conserva su propia moneda ──
  const filasMeta: Array<{ label: string; txt: string; pct: number; sinDato: string | null }> = [
    {
      label: 'Capital confirmado PEN',
      txt:
        metaCapitalPen > 0 && capitalConfirmadoPen != null
          ? `${moneyK(capitalConfirmadoPen, 'PEN')} de ${moneyK(metaCapitalPen, 'PEN')}`
          : capitalConfirmadoPen == null ? '—' : moneyK(capitalConfirmadoPen, 'PEN'),
      pct: pctMeta(capitalConfirmadoPen ?? 0, metaCapitalPen),
      sinDato: objetivosError
        ? 'Meta mensual no disponible'
        : metaCapitalPen <= 0
          ? SIN_META
          : cumplimientoMetasError || capitalConfirmadoPen == null
            ? 'Cumplimiento confirmado no disponible'
            : null,
    },
    {
      label: 'Capital confirmado USD',
      txt:
        metaCapitalUsd > 0 && capitalConfirmadoUsd != null
          ? `${moneyK(capitalConfirmadoUsd, 'USD')} de ${moneyK(metaCapitalUsd, 'USD')}`
          : capitalConfirmadoUsd == null ? '—' : moneyK(capitalConfirmadoUsd, 'USD'),
      pct: pctMeta(capitalConfirmadoUsd ?? 0, metaCapitalUsd),
      sinDato: objetivosError
        ? 'Meta mensual no disponible'
        : metaCapitalUsd <= 0
          ? SIN_META
          : cumplimientoMetasError || capitalConfirmadoUsd == null
            ? 'Cumplimiento confirmado no disponible'
            : null,
    },
    {
      label: 'Conversión resuelta',
      txt:
        conversionConfirmada == null
          ? '—'
          : metaConversion != null
            ? `${conversionConfirmada}% de ${metaConversion}%`
            : `${conversionConfirmada}%`,
      pct: pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0),
      sinDato: objetivosError
        ? 'Meta mensual no disponible'
        : metaConversion == null
          ? SIN_META
          : cumplimientoMetasError
            ? 'Cumplimiento confirmado no disponible'
            : conversionConfirmada == null
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
      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Pronóstico de capital abierto"
          value={resumen ? money(resumen.capital.asignado.pen) : '—'}
          icon={Wallet}
          color={SEMAFORO.ok}
          sub={resumen && resumen.capital.asignado.usd > 0 ? `Pipeline PEN · +${moneyK(resumen.capital.asignado.usd, 'USD')} aparte` : 'Pipeline PEN · abiertos con vendedor'}
          delay={0}
        />
        <KpiCard
          label="Leads activos del equipo"
          value={resumen ? String(resumen.totales.asignados) : '—'}
          icon={Users}
          color={SEMAFORO.violeta}
          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'vendedor' : 'vendedores'} a cargo`}
          delay={60}
        />
        {/* Sin payload, los subs NO afirman estados positivos («todos
            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
        <KpiCard
          label="Nuevos sin responder"
          value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
          icon={AlertTriangle}
          color={(cola?.porBucket.sin_responder ?? 0) > 0 ? SEMAFORO.critico : SEMAFORO.ok}
          sub={
            cola == null
              ? 'Sin dato por ahora'
              : (cola.porBucket.sin_responder ?? 0) > 0
                ? 'Nuevos sin primer contacto — urge'
                : 'Todos los nuevos fueron contactados'
          }
          delay={120}
        />
        <KpiCard
          label="Por repartir"
          value={resumen ? String(resumen.totales.parkeados) : '—'}
          icon={Inbox}
          color={(resumen?.totales.parkeados ?? 0) > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
          sub={
            resumen == null
              ? 'Sin dato por ahora'
              : resumen.totales.parkeados > 0
                ? 'En tu bandeja sin vendedor'
                : 'Bandeja de reparto vacía'
          }
          delay={180}
        />
      </div>

      <AvisoDegradacion
        activo={errorIndicadores}
        queReintenta="de los indicadores del equipo"
        onReintentar={reintentarIndicadores}
      >
        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

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
                cola && cola.total > 0 ? (
                  <Badge color={SEV_COLOR[cola.items[0]?.sev ?? 'baja']} dot>
                    {cola.total} {cola.total === 1 ? 'pendiente' : 'pendientes'}
                  </Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">{cola ? 'al día' : '—'}</span>
                )
              }
            />
            {cola == null ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {colaOp.error
                    ? 'La cola del equipo no está disponible en este momento.'
                    : 'Cargando la cola del equipo…'}
                </p>
              </CardContent>
            ) : cola.items.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  Sin pendientes — el equipo está al día con todos sus leads abiertos.
                </p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {/* Fila = div role="button" (no <button>: contiene los links de
                    AccionesContacto y un botón no puede anidar interactivos). */}
                {(colaExpandida ? cola.items : cola.items.slice(0, COLA_VISIBLES)).map((i) => {
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
                {cola.items.length > COLA_VISIBLES && (
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
                      // Con más pendientes que el p_limite del RPC, el botón no
                      // puede prometer el total del badge: dice lo que muestra.
                      : cola.total > cola.items.length
                        ? `Ver los ${cola.items.length} más urgentes de ${cola.total}`
                        : `Ver los ${cola.items.length} pendientes`}
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
            {rank == null ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {vendedoresOp.error
                    ? 'El resumen por vendedor no está disponible en este momento.'
                    : 'Cargando el resumen por vendedor…'}
                </p>
              </CardContent>
            ) : rank.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">Sin vendedores a cargo.</p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {rank.map((r) => {
                  const c = semaforoDias(r.diasSinActividadMax)
                  // Rezago de agenda del miembro (mismos umbrales del panel
                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
                  const rez = rezagosAgenda.get(r.m.perfil_id)
                  const conRezago =
                    rez != null && (rez.no_asistio >= 2 || rez.vencidas > 0 || rez.leads_sin_accion > 0)
                  const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
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
                        {/* Decisión #10: el total unificado es el número grande y el
                            desglose por moneda va debajo. Sin TC degrada al PEN de
                            siempre — el USD no entra al total sin una tasa real. */}
                        <div className="shrink-0 text-right leading-tight">
                          <p className="text-sm font-extrabold tabular-nums text-primary">
                            {cap.total != null ? moneyK(cap.total) : '—'}
                          </p>
                          <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
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

          {/* ── Cumplimiento confirmado del equipo ── */}
          <Card>
            <SectionHead
              icon={Target}
              title="Cumplimiento del equipo"
              right={<span className="text-xs text-muted-foreground">contratos confirmados · este mes</span>}
            />
            <CardContent className="space-y-4 pb-5 pt-0">
              {filasMeta.map((f) => (
                <div key={f.label}>
                  <div className="mb-1.5 flex items-baseline justify-between gap-2">
                    <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
                    <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
                  </div>
                  {f.sinDato ? (
                    <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
                  ) : (
                    <Progress value={f.pct} color={colorMeta(f.pct)} />
                  )}
                </div>
              ))}
              <p className="text-[10.5px] text-muted-foreground">
                PEN y USD se evalúan por separado. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
              </p>
              {(objetivosError || cumplimientoMetasError) && (
                <Button variant="ghost" size="sm" onClick={() => void recargar()}>Reintentar</Button>
              )}
            </CardContent>
          </Card>

          {/* ── Alertas SLA (≥5 días sin actividad) — bloque estancados del RPC.
               El tope de 50 es señal, no listado: con 50 justos el badge dice 50+. ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={AlarmClock}
              title="Leads sin movimiento"
              right={
                cola && cola.estancados.length > 0 ? (
                  <Badge color={SEMAFORO.critico} dot>
                    {cola.estancados.length >= TOPE_ESTANCADOS ? `${TOPE_ESTANCADOS}+` : cola.estancados.length}
                  </Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">{cola ? 'sin alertas' : '—'}</span>
                )
              }
            />
            {cola == null ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {colaOp.error
                    ? 'Las alertas de inactividad no están disponibles en este momento.'
                    : 'Cargando las alertas de inactividad…'}
                </p>
              </CardContent>
            ) : cola.estancados.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  Ningún lead del equipo lleva 5 días o más sin actividad.
                </p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {cola.estancados.map((a) => (
                  <button
                    key={a.leadId}
                    type="button"
                    onClick={() => abrirLead(a.leadId)}
                    aria-label={`Abrir ficha de ${a.nombre}`}
                    className="flex w-full cursor-pointer items-center gap-2.5 px-5 py-2.5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                  >
                    <div className="min-w-0 flex-1 leading-tight">
                      <p className="truncate text-sm font-semibold">
                        {a.nombre}{' '}
                        <span className="text-xs font-medium text-muted-foreground">
                          ({(a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'})
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
