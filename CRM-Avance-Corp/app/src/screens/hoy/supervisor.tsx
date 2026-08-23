// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
// ya trae: sus leads + los de sus vendedores + parkeados de SU bandeja.
// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
import { useEffect, useMemo, useState, type JSX } from 'react'
import {
  AlertTriangle,
  ChevronRight,
  Inbox,
  ListChecks,
  Target,
  Users,
  UsersRound,
  Wallet,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
import { AccionesContacto } from '@/components/app/contacto'
import { AgendaEquipoPanel } from './agenda-equipo'
import {
  BUCKET_LABEL,
  DIA_MS,
  capitalPrincipal,
  colorMeta,
  diasSinActividad,
  haceCortoTexto,
  haceTexto,
  indexarUltimaActividad,
  pctMeta,
} from '@/lib/inteligencia'
import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  capitalObjetivo,
  metaVigente,
  capitalReal,
  metaConversionAplicable,
  periodoLima,
} from '@/lib/objetivos'
import { useConversionMensual } from '@/data/crm-queries'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import { useAhora } from '@/lib/ahora'
import { lecturaCobertura } from '@/lib/conversion-mensual'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { mensajeDeError } from '@/data/crm-api'
import { useMetricasAgenda } from '@/data/crm-queries'
import { moneyK, numero } from '@/lib/format'
import { cn } from '@/lib/utils'
import { hashDe } from '@/lib/router'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import { useTipoCambio } from '@/lib/tipo-cambio'

// Tope de la cola del equipo: los primeros son la plata (colaDe ya ordena por
// severidad); el resto vive tras "Ver los N pendientes" para que la Agenda del
// equipo (montada debajo) no quede varios pantallazos abajo.
const COLA_VISIBLES = 8

// Pestañas de la cola (2026-08-23, «una cosa se avisa en un solo lugar»):
// «Leads sin movimiento» era una tercera tarjeta sobre los MISMOS leads
// abiertos que la cola, así que un lead con 6 días salía dos veces en el mismo
// pantallazo. Ahora es una pestaña de la misma tarjeta: mismo conteo, mismo
// tope del RPC, un solo lugar. Urgente = severidad crítica y media.
type PestanaCola = 'urgente' | 'sin_movimiento' | 'todo'
const PESTANAS_COLA: ReadonlyArray<{ id: PestanaCola; label: string }> = [
  { id: 'urgente', label: 'Urgente' },
  { id: 'sin_movimiento', label: 'Sin movimiento' },
  { id: 'todo', label: 'Todo' },
]

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
  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
  const [colaExpandida, setColaExpandida] = useState(false)
  // Pestaña elegida a mano; `null` = automática (la primera con filas), así
  // un supervisor que entra por la mañana aterriza donde hay trabajo.
  const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)

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
  // Pronóstico: `capitalPrincipal` (criterio compartido con Cartera/Pipeline),
  // NUNCA un total mixto. Antes se fijaba PEN a mano y un equipo que vende en
  // dólares se titulaba «S/ 0».
  const capitalPronostico = resumen
    ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd)
    : null
  // HOY solo resume la bandeja; la operación completa vive en Derivar leads.
  // Conservamos el índice local para resumir la espera observable del caso más
  // rezagado sin añadir otra consulta; si no hubo actividad, parte del ingreso.
  const bandejaReparto = useMemo(() => {
    const parkeados = ambito.leads.filter(
      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null,
    )
    const indice = indexarUltimaActividad(actividades)
    return { parkeados, indice }
  }, [ambito, actividades])

  const esperaMasLargaReparto = useMemo(() => {
    if (bandejaReparto.parkeados.length === 0) return null
    let maxima = 0
    for (const lead of bandejaReparto.parkeados) {
      maxima = Math.max(
        maxima,
        diasSinActividad(lead, actividades, ahora, bandejaReparto.indice),
      )
    }
    return maxima
  }, [actividades, ahora, bandejaReparto])

  // El conteo del RPC sigue siendo la autoridad. Si el detalle local aún no
  // está disponible, el CTA conserva la verdad y omite la antigüedad.
  const totalPorRepartir = resumen?.totales.parkeados ?? null
  const hayPorRepartir = (totalPorRepartir ?? 0) > 0
  const detalleReparto = totalPorRepartir == null
    ? 'Sin dato por ahora · Ver derivaciones →'
    : hayPorRepartir
      ? esperaMasLargaReparto == null
        ? 'Pendientes en tu bandeja · Repartir →'
        : `Más rezagado: ${haceCortoTexto(esperaMasLargaReparto)} · Repartir →`
      : 'Bandeja al día · Ver historial →'
  const etiquetaAccesoReparto = totalPorRepartir == null
    ? 'Ver derivaciones; total por repartir no disponible'
    : hayPorRepartir
      ? `Repartir ${totalPorRepartir} ${totalPorRepartir === 1 ? 'lead pendiente' : 'leads pendientes'}`
      : 'Ver derivaciones; bandeja sin pendientes'

  // Nombres para los estancados del payload (el servidor no manda nombres de
  // personas): join con el roster completo, una sola vez por render.
  const nombrePorId = useMemo(
    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
    [equipo],
  )

  // Filas y conteos por pestaña. «Todo» cuenta el universo del RPC (`total`),
  // no las filas recortadas por p_limite; «Urgente» solo puede contar lo que
  // llegó. Con estancados al tope, el conteo dice «50+» y no miente.
  const urgentes = useMemo(
    () => (cola?.items ?? []).filter((i) => i.sev !== 'baja'),
    [cola],
  )
  // El conteo de «Urgente» sale de porSev (el resumen COMPLETO del RPC), no de
  // las filas: p_limite recorta items a 100 y con 120 urgentes la pestaña
  // habría dicho 100 mientras «Todo» decía 120 (hallazgo de Codex).
  const urgenteTotal = (cola?.porSev.critica ?? 0) + (cola?.porSev.media ?? 0)
  const conteoPestana: Record<PestanaCola, string> = {
    urgente: String(urgenteTotal),
    sin_movimiento: cola && cola.estancados.length >= TOPE_ESTANCADOS
      ? `${TOPE_ESTANCADOS}+`
      : String(cola?.estancados.length ?? 0),
    todo: String(cola?.total ?? 0),
  }
  const primeraConFilas: PestanaCola = urgentes.length > 0
    ? 'urgente'
    : (cola?.estancados.length ?? 0) > 0
      ? 'sin_movimiento'
      : 'todo'
  const pestana = pestanaElegida ?? primeraConFilas
  const elegirPestana = (siguiente: PestanaCola) => {
    setPestanaElegida(siguiente)
  }
  // El colapso se reinicia con CUALQUIER cambio de pestaña — también el
  // automático: la cola se refresca cada minuto y sin esto una pestaña recién
  // aparecida heredaba la expansión de la anterior (hasta 100 filas de golpe).
  useEffect(() => {
    setColaExpandida(false)
  }, [pestana])
  const filasCola = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
  // Total real de la pestaña activa, para que el botón de expandir no prometa
  // menos de lo que existe cuando el RPC recortó las filas.
  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal

  const errorIndicadores = !yo?.demo
    && Boolean(resumenOp.error || colaOp.error || vendedoresOp.error)
  const reintentarIndicadores = () => {
    if (resumenOp.error) void resumenOp.recargar()
    if (colaOp.error) void colaOp.recargar()
    if (vendedoresOp.error) void vendedoresOp.recargar()
  }

  // La meta sale del snapshot cuando lo hay: si un analista se fue o cambió
  // de equipo, su meta y su producción viajan juntas (ver `metaVigente`).
  const meta = metaVigente(objetivos.supervisor, cumplimientoMetas?.supervisor ?? null)
  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosError)
  const cumplimiento = cumplimientoMetas?.supervisor ?? null
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null

  // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
  // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
  // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
  // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
  const esDemoConversion = yo?.demo === true
  const qConversionMensual = useConversionMensual(!esDemoConversion, periodoLima(Date.now()))
  const conversionMensual = esDemoConversion
    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
    : (qConversionMensual.data ?? null)
  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
  // 2026-08-14). La regla vive en `lecturaCobertura`, compartida con las otras
  // tres pantallas que pintan esta misma cifra.
  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
  const conversionConfirmada = lecturaConversion.mostrar
    ? (conversionMensual?.total.conversion_pct ?? null)
    : null
  const recibidosEquipo = conversionMensual?.total.divisor ?? null
  // ── Cumplimiento del mes ──────────────────────────────────────────────────
  // PEN y USD ya NO van por separado: la meta se pacta en soles (el editor
  // escribe todo en `nuevo/PEN`), así que la fila de dólares vivía en «Sin meta
  // fijada» para siempre mientras el capital real en USD no movía ninguna
  // barra. Se consolida con el MISMO tipo de cambio en numerador y denominador
  // —comparar a tasas distintas es comparar peras con manzanas— igual que en el
  // panel del asesor y en el de gerencia.
  const capitalConfirmado = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tc?.promedio)
  const metaCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tc === undefined && hayDolares
  const filasMeta: Array<{
    label: string
    txt: string
    pct: number
    sinDato: string | null
    nota?: string | null
  }> = [
    {
      label: 'Capital confirmado',
      txt:
        (metaCapital.total ?? 0) > 0 && capitalConfirmado.total != null
          ? `${moneyK(capitalConfirmado.total, 'PEN')} de ${moneyK(metaCapital.total ?? 0, 'PEN')}`
          : capitalConfirmado.total == null ? '—' : moneyK(capitalConfirmado.total, 'PEN'),
      pct: tcEnVuelo ? 0 : pctMeta(capitalConfirmado.total ?? 0, metaCapital.total ?? 0),
      // El desglose solo aporta cuando hay dólares; si no, repetiría el total.
      nota: (capitalConfirmadoUsd ?? 0) > 0
        ? `${moneyK(capitalConfirmadoPen ?? 0, 'PEN')} + ${moneyK(capitalConfirmadoUsd ?? 0, 'USD')}`
          + (capitalConfirmado.tc == null
            ? ' · sin tipo de cambio: el total NO incluye los dólares'
            : ` · ${rotuloTipoCambio(capitalConfirmado.tc, tc?.fuente ?? 'TC del día')}`)
        : null,
      sinDato: objetivosError
        ? 'Meta mensual no disponible'
        : tcEnVuelo
          ? 'Consultando el tipo de cambio para consolidar los dólares…'
          : (metaCapital.total ?? 0) <= 0
            ? SIN_META
            : cumplimientoMetasError || capitalConfirmado.total == null
              ? 'Cumplimiento confirmado no disponible'
              : null,
    },
    {
      label: 'Conversión del mes',
      txt:
        conversionConfirmada == null
          ? '—'
          : metaConversion != null
            ? `${numero(conversionConfirmada, 1)}% de ${metaConversion}% · ${numero(recibidosEquipo)} recibidos`
            : `${numero(conversionConfirmada, 1)}% · ${numero(recibidosEquipo)} recibidos`,
      // El porqué de que la cifra no sea definitiva viaja PEGADO a ella. Antes
      // esto la sustituía, y un mes con recibidos y cierres decía «sin datos».
      nota: lecturaConversion.aviso,
      pct: pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0),
      sinDato: conversionMensualError
        ? 'Conversión del mes no disponible'
        : !lecturaConversion.mostrar
          ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
          : conversionConfirmada == null
            ? 'Sin leads recibidos este mes'
            : objetivosError
              ? 'Meta mensual no disponible'
              : metaConversion == null
                ? SIN_META
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

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Pronóstico de capital abierto"
          // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
          // cumplimiento, y no se convierte a una tasa que aquí no se rotula.
          // Fijar PEN a mano titulaba «S/ 0» a un equipo que vende en dólares.
          value={capitalPronostico ? capitalPronostico.valor : '—'}
          icon={Wallet}
          color={SEMAFORO.ok}
          sub={
            capitalPronostico?.otra
              ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte`
              : capitalPronostico?.soloDolares
                ? 'Pipeline (USD)'
                : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0
                  ? 'Sin montos estimados — complétalos en cada ficha'
                  : 'Pipeline (PEN) · abiertos con vendedor'
          }
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
        <a
          href={hashDe('derivaciones')}
          aria-label={etiquetaAccesoReparto}
          className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          {hayPorRepartir && (
            <span
              aria-hidden="true"
              data-testid="reparto-pendiente-acento"
              className="pointer-events-none absolute inset-y-3 left-0 z-10 w-[3px] rounded-r-full"
              style={{ backgroundColor: SEMAFORO.atencion }}
            />
          )}
          <KpiCard
            label="Por repartir"
            value={totalPorRepartir == null ? '—' : String(totalPorRepartir)}
            icon={Inbox}
            color={hayPorRepartir ? SEMAFORO.atencion : SEMAFORO.ok}
            sub={detalleReparto}
            delay={180}
          />
        </a>
      </div>

      <AvisoDegradacion
        activo={errorIndicadores}
        queReintenta="de los indicadores del equipo"
        onReintentar={reintentarIndicadores}
      >
        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      <div className="grid gap-4 lg:grid-cols-5">
        <div className="space-y-4 lg:col-span-3">
          {/* ── Cola del equipo (con dueño de cada item) ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={ListChecks}
              title="Cola del equipo"
              right={
                cola ? (
                  // Patrón tablist de la casa (ranking-vendedores): aria-selected
                  // + aria-controls, tabindex itinerante y flechas. Sin el
                  // conteo en el nombre accesible el lector de pantalla no
                  // sabría cuál pestaña tiene trabajo.
                  <div role="tablist" aria-label="Filtrar la cola" className="inline-flex rounded-lg bg-muted/60 p-0.5">
                    {PESTANAS_COLA.map((p, indice) => (
                      <button
                        key={p.id}
                        id={`tab-cola-${p.id}`}
                        type="button"
                        role="tab"
                        aria-selected={pestana === p.id}
                        aria-controls="panel-cola"
                        aria-label={`${p.label}: ${conteoPestana[p.id]}`}
                        tabIndex={pestana === p.id ? 0 : -1}
                        onClick={() => elegirPestana(p.id)}
                        onKeyDown={(e) => {
                          const salto = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
                          if (salto === 0) return
                          e.preventDefault()
                          const siguiente = PESTANAS_COLA[(indice + salto + PESTANAS_COLA.length) % PESTANAS_COLA.length]
                          if (!siguiente) return
                          elegirPestana(siguiente.id)
                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
                        }}
                        className={cn(
                          'cursor-pointer rounded-md px-2.5 py-1 text-[11px] font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                          pestana === p.id
                            ? 'bg-card text-foreground shadow-sm'
                            : 'text-muted-foreground hover:text-foreground',
                        )}
                      >
                        {p.label} <span aria-hidden>{conteoPestana[p.id]}</span>
                      </button>
                    ))}
                  </div>
                ) : (
                  <span className="text-xs text-muted-foreground">—</span>
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
            ) : pestana === 'sin_movimiento' ? (
              // ── Sin movimiento (≥5 días) — bloque estancados del RPC. El tope
              //    de 50 es señal, no listado: con 50 justos la pestaña dice 50+.
              //    tabIndex 0 SOLO en el panel vacío (patrón WAI-ARIA: el panel
              //    sin interactivos debe ser enfocable para que Tab no lo salte). ──
              <div
                id="panel-cola"
                role="tabpanel"
                aria-labelledby="tab-cola-sin_movimiento"
                tabIndex={cola.estancados.length === 0 ? 0 : undefined}
              >
                {cola.estancados.length === 0 ? (
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
              </div>
            ) : filasCola.length === 0 ? (
              <CardContent id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} tabIndex={0} className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {pestana === 'urgente'
                    ? 'Nada urgente — ninguna fila crítica ni media en la cola.'
                    : 'Sin pendientes — el equipo está al día con todos sus leads abiertos.'}
                </p>
              </CardContent>
            ) : (
              <div id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} className="divide-y divide-border/60 border-t border-border/60">
                {/* Fila = div role="button" (no <button>: contiene los links de
                    AccionesContacto y un botón no puede anidar interactivos). */}
                {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map((i) => {
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
                {filasCola.length > COLA_VISIBLES && (
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
                      // puede prometer el total de la pestaña: dice lo que muestra.
                      : totalPestanaActiva > filasCola.length
                        ? `Ver los ${filasCola.length} más urgentes de ${totalPestanaActiva}`
                        : `Ver los ${filasCola.length} pendientes`}
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
            <SectionHead
              icon={UsersRound}
              title="Tu equipo hoy"
              right={tc ? (
                <span className="text-xs text-muted-foreground">
                  Capital en proceso · {rotuloTipoCambio(tc.promedio, tc.fuente)}
                </span>
              ) : undefined}
            />
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
                        {/* Sin leads abiertos no hay «al día» que celebrar:
                            `semaforoDias(0)` devolvía azul y un analista sin
                            cartera se pintaba como el que va al corriente. */}
                        <span
                          className="size-2 shrink-0 rounded-full"
                          style={{ background: r.activos === 0 ? SEMAFORO.neutro : c }}
                          aria-hidden
                        />
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
                  {f.nota && (
                    <p className="mb-1 text-[10.5px] tabular-nums text-muted-foreground">{f.nota}</p>
                  )}
                  {f.sinDato ? (
                    <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
                  ) : (
                    <Progress value={f.pct} color={colorMeta(f.pct)} />
                  )}
                </div>
              ))}
              <p className="text-[10.5px] text-muted-foreground">
                El capital en dólares entra al total convertido a tipo de cambio real. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
              </p>
              {(objetivosError || cumplimientoMetasError) && (
                <Button variant="ghost" size="sm" onClick={() => void recargar()}>Reintentar</Button>
              )}
            </CardContent>
          </Card>

          {/* ── Por empresa: de dónde vino cada sol (Avance vs. COOPAC). Se
               oculta solo si el mes no tiene cierres en cooperativas. ── */}
          <DesglosePorEmpresa
            demo={yo?.demo === true}
            porVendedor={cumplimientoMetas?.porVendedor ?? null}
          />
        </div>
      </div>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
      </p>
    </div>
  )
}
