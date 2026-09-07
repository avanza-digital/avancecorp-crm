import { SlaOperacionBoundary } from '@/components/app/sla-operacion'
import { useModoSla } from '@/data/sla-operacion-queries'
// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
// ya trae: sus leads + los de sus analistas + parkeados de SU bandeja.
// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
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
import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
import { TresCosas } from './tres-cosas'
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
import {
  derivarNovedades,
  fotoDeVisita,
  guardarFotoVisita,
  leerFotoVisita,
  resumenNovedades,
  type NovedadesVisita,
} from '@/lib/visita-sin-movimiento'
import { useSplashVisible } from '@/lib/splash-visible'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  capitalObjetivo,
  metaVigente,
  capitalReal,
  metaConversionAplicable,
  objetivosCero,
  periodoLima,
} from '@/lib/objetivos'
import { useConversionMensual } from '@/data/crm-queries'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import { useAhora } from '@/lib/ahora'
import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { mensajeDeError } from '@/data/crm-api'
import { useMetricasAgenda } from '@/data/crm-queries'
import { money, moneyK, numero, porcentajeConversionCanonica } from '@/lib/format'
import { cn } from '@/lib/utils'
import { hashDe } from '@/lib/router'
import { tresCosasDeHoy } from '@/lib/tres-cosas'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
import { textoConversionOperativa } from '@/lib/metricas-vendedores'
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
  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
  const cola = colaOp.cola
  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividades)
  const rank = vendedoresOp.metricas?.filas ?? null
  // TC izado UNA vez por pantalla: el hook no pasa por TanStack (sin cache ni
  // dedupe), así que uno por fila multiplicaría las llamadas a la edge.
  const { tc, recargar: recargarTipoCambio } = useTipoCambio()
  const diaTipoCambio = fechaLima(ahora)
  const diaTipoCambioAnterior = useRef(diaTipoCambio)
  useEffect(() => {
    if (diaTipoCambioAnterior.current === diaTipoCambio) return
    diaTipoCambioAnterior.current = diaTipoCambio
    recargarTipoCambio()
  }, [diaTipoCambio, recargarTipoCambio])
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
    // F4.3: la visita la cierra el USUARIO al irse de la pestaña. Un vaivén
    // automático de `primeraConFilas` (refetch caído que salta a «Todo» y
    // vuelve al recuperarse) no borra las marcas ni fabrica otra visita.
    if (pestana === 'sin_movimiento' && siguiente !== 'sin_movimiento') {
      visitaAnotadaRef.current = null
      setVisitaCongelada(null)
    }
    setPestanaElegida(siguiente)
  }
  // El colapso se reinicia con CUALQUIER cambio de pestaña — también el
  // automático: la cola se refresca cada minuto y sin esto una pestaña recién
  // aparecida heredaba la expansión de la anterior (hasta 100 filas de golpe).
  useEffect(() => {
    setColaExpandida(false)
  }, [pestana])
  // F4.3: qué EMPEORÓ en «Sin movimiento» desde la última visita. TODO se
  // CONGELA en el instante de anotar: la foto anterior Y las marcas derivadas
  // — una marca que aparece «bajo el cursor» porque la cola se refrescó
  // debajo sería ruido, no memoria (la severidad de la tira sí sigue viva).
  // La visita queda anotada en localStorage en ese mismo instante — anotar
  // «al salir» exigiría un unload handler, y perder una anotación solo marca
  // DE MÁS la próxima vez, la dirección segura. La anotación ESPERA a que el
  // payload esté fresco (enVuelo: persistir una cola vieja podría CALLAR una
  // novedad futura) y a que el workspace sea visible (splash: una «visita»
  // que nadie vio también calla). El ref la hace idempotente (StrictMode
  // ejecuta el efecto dos veces) y fiel a la identidad: si `yo` cambiara en
  // caliente se anota de nuevo para el id nuevo.
  const splashVisible = useSplashVisible()
  const [visitaCongelada, setVisitaCongelada] = useState<{
    novedades: NovedadesVisita | null
    recortada: boolean
  } | null>(null)
  const visitaAnotadaRef = useRef<string | null>(null)
  useEffect(() => {
    if (pestana !== 'sin_movimiento' || yo?.id == null || cola == null) return
    if (colaOp.enVuelo || splashVisible) return
    if (visitaAnotadaRef.current === yo.id) return
    visitaAnotadaRef.current = yo.id
    const fotoAnterior = leerFotoVisita(yo.id)
    guardarFotoVisita(yo.id, fotoDeVisita(cola.estancados, Date.now()))
    setVisitaCongelada({
      novedades: derivarNovedades(cola.estancados, fotoAnterior),
      recortada: cola.estancados.length >= TOPE_ESTANCADOS,
    })
  }, [pestana, cola, colaOp.enVuelo, splashVisible, yo?.id])
  const novedadesVisita = visitaCongelada?.novedades ?? null
  const resumenVisita = resumenNovedades(
    novedadesVisita,
    visitaCongelada?.recortada === true ? TOPE_ESTANCADOS : undefined,
  )
  const filasCola = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
  // Total real de la pestaña activa, para que el botón de expandir no prometa
  // menos de lo que existe cuando el RPC recortó las filas.
  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal

  const errorIndicadores = !yo?.demo
    && Boolean(resumenOp.error || (modoSla.legado && colaOp.error) || vendedoresOp.error)
  const reintentarIndicadores = () => {
    if (resumenOp.error) void resumenOp.recargar()
    if (colaOp.error) void colaOp.recargar()
    if (vendedoresOp.error) void vendedoresOp.recargar()
  }

  // La meta sale del snapshot cuando lo hay: si un analista se fue o cambió
  // de equipo, su meta y su producción viajan juntas (ver `metaVigente`).
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
  const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
  const cumplimiento = cumplimientoMensual?.supervisor ?? null
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null

  // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
  // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
  // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
  // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
  const esDemoConversion = yo?.demo === true
  const qConversionMensual = useConversionMensual(
    !esDemoConversion,
    periodoVigente,
    'equipo',
    yo?.id,
  )
  const conversionMensualCargando = !esDemoConversion
    && qConversionMensual.isPending
    && qConversionMensual.data === undefined
  const conversionMensual = esDemoConversion
    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
    : conversionMensualCargando
      ? undefined
      : (qConversionMensual.data ?? null)
  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
  // 2026-08-14). La regla vive en `lecturaCobertura`, compartida con las otras
  // tres pantallas que pintan esta misma cifra.
  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
  const totalConversion = totalConversionPublicable(conversionMensual)
  const conversionConfirmada = totalConversion?.conversion_pct ?? null
  const recibidosEquipo = totalConversion?.divisor ?? null
  // ── Cumplimiento del mes ──────────────────────────────────────────────────
  // PEN y USD ya NO van por separado: la meta se pacta en soles (el editor
  // escribe todo en `nuevo/PEN`), así que la fila de dólares vivía en «Sin meta
  // fijada» para siempre mientras el capital real en USD no movía ninguna
  // barra. Se consolida con el MISMO tipo de cambio en numerador y denominador
  // —comparar a tasas distintas es comparar peras con manzanas— igual que en el
  // panel del analista y en el de gerencia.
  const capitalConfirmado = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tc?.promedio)
  const metaCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tc === undefined && hayDolares
  const tcCaido = tc === null && hayDolares
  const ajusteCierre = cumplimiento?.ajuste
  const notaAjusteCierre = ajusteCierre != null && (
    ajusteCierre.aplicadoPen > 0
    || ajusteCierre.aplicadoUsd > 0
    || ajusteCierre.contratosAplicados > 0
  )
    ? [
        'Neto tras ajuste de cierre',
        ajusteCierre.aplicadoPen > 0 ? `−${money(ajusteCierre.aplicadoPen, 'PEN')}` : null,
        ajusteCierre.aplicadoUsd > 0 ? `−${money(ajusteCierre.aplicadoUsd, 'USD')}` : null,
        ajusteCierre.contratosAplicados > 0
          ? `−${numero(ajusteCierre.contratosAplicados)} ${ajusteCierre.contratosAplicados === 1 ? 'contrato' : 'contratos'}`
          : null,
      ].filter(Boolean).join(' · ')
    : null
  const notaCapitalMonedas = !tcEnVuelo && (capitalConfirmadoUsd ?? 0) > 0
    ? `${moneyK(capitalConfirmadoPen ?? 0, 'PEN')} + ${moneyK(capitalConfirmadoUsd ?? 0, 'USD')}`
      + (capitalConfirmado.tc == null
        ? ' · sin tipo de cambio: el total NO incluye los dólares'
        : ` · ${rotuloTipoCambio(capitalConfirmado.tc, tc?.fuente ?? 'TC del día')}`)
    : null
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
        tcEnVuelo
          ? 'Calculando…'
          : (metaCapital.total ?? 0) > 0 && capitalConfirmado.total != null
          ? `${moneyK(capitalConfirmado.total, 'PEN')} de ${moneyK(metaCapital.total ?? 0, 'PEN')}`
          : capitalConfirmado.total == null ? '—' : moneyK(capitalConfirmado.total, 'PEN'),
      pct: tcEnVuelo ? 0 : pctMeta(capitalConfirmado.total ?? 0, metaCapital.total ?? 0),
      // El desglose solo aporta cuando hay dólares; si no, repetiría el total.
      nota: [notaCapitalMonedas, notaAjusteCierre].filter(Boolean).join(' · ') || null,
      sinDato: fotoMensualStoreCargando
        ? 'Actualizando la meta y el cumplimiento de este mes…'
        : objetivosMensualesError
        ? 'Meta mensual no disponible'
        : tcEnVuelo
          ? 'Consultando el tipo de cambio para consolidar los dólares…'
          : (metaCapital.total ?? 0) <= 0
            ? SIN_META
            : cumplimientoMensualError || capitalConfirmado.total == null
              ? 'Cumplimiento confirmado no disponible'
              : null,
    },
    {
      label: 'Conversión del mes',
      txt:
        conversionMensualCargando
          ? 'Calculando…'
          : conversionConfirmada == null
          ? '—'
          : metaConversion != null
            ? `${porcentajeConversionCanonica(conversionConfirmada)} de ${metaConversion}% · ${numero(recibidosEquipo)} recibidos`
            : `${porcentajeConversionCanonica(conversionConfirmada)} · ${numero(recibidosEquipo)} recibidos`,
      // El porqué de que la cifra no sea definitiva viaja PEGADO a ella. Antes
      // esto la sustituía, y un mes con recibidos y cierres decía «sin datos».
      nota: lecturaConversion.aviso,
      pct: pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0),
      sinDato: conversionMensualCargando
        ? 'Consultando la conversión del mes…'
        : conversionMensualError
          ? 'Conversión del mes no disponible'
          : !lecturaConversion.mostrar
          ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
          : conversionConfirmada == null
            ? 'Sin leads recibidos este mes'
            : fotoMensualStoreCargando
              ? 'Actualizando la meta de este mes…'
              : objetivosMensualesError
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

  // ── F3: «Hoy, tres cosas» — el sistema prioriza el día (ley de Tesler). ──
  // Mismas fuentes que ya están en pantalla; sin dato no hay tarjeta.
  const cosas = useMemo(
    () => tresCosasDeHoy({
      cola,
      totalPorRepartir,
      esperaMasLargaReparto,
      vendedoresAgenda: datosAgenda?.vendedores ?? [],
    }),
    [cola, totalPorRepartir, esperaMasLargaReparto, datosAgenda],
  )
  // «Ver →» de la franja: selecciona la pestaña y le LLEVA el foco (el
  // focus() también hace scroll hasta la tarjeta de la cola).
  const irAPestanaCola = (destino: PestanaCola) => {
    elegirPestana(destino)
    requestAnimationFrame(() => {
      document.getElementById(`tab-cola-${destino}`)?.focus()
    })
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* ── F3: la franja manda — máximo tres intervenciones, luego consulta ── */}
      {modoSla.legado && <TresCosas cosas={cosas} onIrAPestana={irAPestanaCola} />}

      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {/* F2 (figura-fondo): los KPIs son CONSULTA, no alarma — iconos en
            neutro. Desde F3 TODOS: la urgencia de «Nuevos sin responder»
            vive en la franja, que es su reemplazo. */}
        <KpiCard
          label="Pronóstico de capital abierto"
          // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
          // cumplimiento, y no se convierte a una tasa que aquí no se rotula.
          // Fijar PEN a mano titulaba «S/ 0» a un equipo que vende en dólares.
          value={capitalPronostico ? capitalPronostico.valor : '—'}
          icon={Wallet}
          color={SEMAFORO.neutro}
          sub={
            capitalPronostico?.otra
              ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte`
              : capitalPronostico?.soloDolares
                ? 'Pipeline (USD)'
                : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0
                  ? 'Sin montos estimados — complétalos en cada ficha'
                  : 'Pipeline (PEN) · abiertos con analista'
          }
          delay={0}
        />
        <KpiCard
          label="Leads activos del equipo"
          value={resumen ? String(resumen.totales.asignados) : '—'}
          icon={Users}
          color={SEMAFORO.neutro}
          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
          delay={60}
        />
        {/* Sin payload, los subs NO afirman estados positivos («todos
            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
        <KpiCard
          label="Nuevos sin responder"
          value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
          icon={AlertTriangle}
          color={SEMAFORO.neutro}
          sub={
            cola == null
              ? 'Sin dato por ahora'
              : (cola.porBucket.sin_responder ?? 0) > 0
                ? 'Sin primer contacto'
                : 'Todos los nuevos fueron contactados'
          }
          delay={120}
        />
        <a
          href={hashDe('derivaciones')}
          aria-label={etiquetaAccesoReparto}
          className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          {/* F2: fuera el acento ámbar — la urgencia del reparto vive en la
              campana (grupo) y desde F3 en la franja; el KPI es el conteo. */}
          <KpiCard
            label="Por repartir"
            value={totalPorRepartir == null ? '—' : String(totalPorRepartir)}
            icon={Inbox}
            color={SEMAFORO.neutro}
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
          <SlaOperacionBoundary legado={(
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
                          // Flechas con vuelta + Home/End (patrón APG completo).
                          const destino = e.key === 'ArrowRight'
                            ? (indice + 1) % PESTANAS_COLA.length
                            : e.key === 'ArrowLeft'
                              ? (indice - 1 + PESTANAS_COLA.length) % PESTANAS_COLA.length
                              : e.key === 'Home'
                                ? 0
                                : e.key === 'End'
                                  ? PESTANAS_COLA.length - 1
                                  : null
                          if (destino == null) return
                          e.preventDefault()
                          const siguiente = PESTANAS_COLA[destino]
                          if (!siguiente) return
                          elegirPestana(siguiente.id)
                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
                        }}
                        className={cn(
                          // Fitts: min-h para un objetivo táctil cómodo.
                          'min-h-7 cursor-pointer rounded-md px-3 py-1.5 text-[11px] font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                          pestana === p.id
                            ? 'bg-card text-foreground shadow-sm'
                            // Gris FUERTE: 11px sobre bg-muted no llega a 4.5:1
                            // con el muted normal (revisor a11y, M1).
                            : 'text-muted-foreground-strong hover:text-foreground',
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
                  <>
                    {/* F4.3: el resumen de novedades va ANTES de la lista —
                        es la razón para escanearla. Solo existe si hay algo
                        que decir (el silencio también es información). */}
                    {resumenVisita != null && (
                      <p className="border-t border-border/60 px-5 py-2 text-[11px] font-semibold text-muted-foreground-strong">
                        {resumenVisita}
                      </p>
                    )}
                    <div className="divide-y divide-border/60 border-t border-border/60">
                      {cola.estancados.map((a) => {
                        // F2: la gravedad va UNA vez, en la tira (rojo desde 7
                        // días, ámbar 5–6); el texto queda en gris de contexto.
                        // F4.3: la novedad es CATEGÓRICA, no de severidad —
                        // chip violeta para el que entró; el que cruzó a
                        // crítico ya tiene la tira roja y lo dice el texto.
                        const esNuevo = novedadesVisita?.nuevos.has(a.leadId) === true
                        const cruzoACritico = novedadesVisita?.agravados.has(a.leadId) === true
                        const vendedor = (a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'
                        return (
                          <button
                            key={a.leadId}
                            type="button"
                            onClick={() => abrirLead(a.leadId)}
                            // El label DICTA todo lo visible: el aria-label
                            // pisa el contenido para un SR, así que lleva al
                            // analista (a11y M1: de quién es el lead es parte
                            // de la decisión), los días (la criticidad no
                            // puede vivir solo en la tira de color) y el
                            // literal del chip («nuevo aquí») para que el
                            // dictado por voz también lo alcance (2.5.3).
                            aria-label={`Abrir ficha de ${a.nombre} (${vendedor}), sin actividad ${haceTexto(a.dias)}${
                              esNuevo
                                ? ', nuevo aquí desde tu última visita'
                                : cruzoACritico ? ', crítico desde tu última visita' : ''
                            }`}
                            className="flex w-full cursor-pointer items-center gap-2.5 border-l-[3px] py-2.5 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
                            style={{ borderLeftColor: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
                          >
                            <div className="min-w-0 flex-1 leading-tight">
                              <p className="truncate text-sm font-semibold">
                                {a.nombre}{' '}
                                <span className="text-xs font-medium text-muted-foreground">
                                  ({vendedor})
                                </span>
                              </p>
                              <p className="text-[11px] font-medium text-muted-foreground">
                                Sin actividad {haceTexto(a.dias)}
                                {/* Gris FUERTE (a11y F4.3 #2): es la única
                                    señal textual del cruce y el gris débil a
                                    11px roza el 4.5:1 en hover. */}
                                {cruzoACritico && (
                                  <span className="text-muted-foreground-strong"> · crítico desde tu última visita</span>
                                )}
                              </p>
                            </div>
                            {esNuevo && (
                              <Badge color={SEMAFORO.violeta} variant="outline" className="shrink-0 whitespace-nowrap">
                                Nuevo aquí
                              </Badge>
                            )}
                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                          </button>
                        )
                      })}
                    </div>
                  </>
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
                    AccionesContacto y un botón no puede anidar interactivos).
                    F2 (pregnancia): la severidad se dice UNA vez — la tira de
                    3 px. Fuera el punto, el badge de etapa y el azul del monto;
                    la etapa va en texto plano delante del motivo. El pl de
                    17 px compensa los 3 px de la tira: el contenido queda a
                    20 px, alineado con la cabecera (Codex F2). */}
                {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map((i) => {
                  const abrir = () => abrirLead(i.lead.id)
                  return (
                    <div
                      key={i.lead.id}
                      role="button"
                      tabIndex={0}
                      data-sev={i.sev}
                      onClick={abrir}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault()
                          abrir()
                        }
                      }}
                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
                      className="flex w-full cursor-pointer items-center gap-3 border-l-[3px] py-3 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
                      style={{ borderLeftColor: i.sev === 'baja' ? 'transparent' : SEV_COLOR[i.sev] }}
                    >
                      <div className="min-w-0 flex-1 leading-tight">
                        <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
                        <p className="truncate text-xs text-muted-foreground">
                          {BUCKET_LABEL[i.bucket]} · {i.motivo}
                        </p>
                      </div>
                      {i.lead.monto_estimado != null && (
                        <span className="hidden shrink-0 text-xs font-semibold tabular-nums text-muted-foreground sm:inline">
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
                        <span className="shrink-0 text-xs font-medium text-muted-foreground">sin asignar</span>
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
                    className="flex w-full cursor-pointer items-center justify-center gap-1 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
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
          )}>
            <Card>
              <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
                <div className="space-y-1">
                  <h2 className="text-sm font-bold">Seguimiento del equipo</h2>
                  <p className="text-xs text-muted-foreground">Prioriza las gestiones y revisa los plazos de cada analista.</p>
                </div>
                <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
                  Abrir seguimiento <ChevronRight className="size-4" aria-hidden />
                </a>
              </CardContent>
            </Card>
          </SlaOperacionBoundary>

          {/* Rentabilidad R3: tus solicitudes de tasa en curso (solo si hay). */}
          <TasasAutorizadasAnalistaPanel />

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
          {/* ── Tu equipo hoy (semáforo por analista) ── */}
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
                    ? 'El resumen por analista no está disponible en este momento.'
                    : 'Cargando el resumen por analista…'}
                </p>
              </CardContent>
            ) : rank.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {rank.map((r) => {
                  const c = semaforoDias(r.diasSinActividadMax)
                  // Rezago de agenda del miembro (mismos umbrales del panel
                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
                  const rez = rezagosAgenda.get(r.m.perfil_id)
                  // El rezago de agenda TAMBIÉN es señal: sin esto, quien tocó
                  // ayer pero arrastra 10 vencidas quedaba sin ninguna marca
                  // visual (hallazgo IMPORTANTE de Codex sobre F2).
                  const conRezagoAgenda = rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)
                  const colorPunto = r.activos === 0
                    ? SEMAFORO.neutro
                    : c !== SEMAFORO.ok
                      ? c
                      : SEMAFORO.atencion
                  const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
                  return (
                    <div key={r.m.perfil_id} className="px-5 py-3">
                      <div className="flex items-center gap-2.5">
                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
                        <div className="min-w-0 flex-1 leading-tight">
                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
                          <p className="text-[11px] tabular-nums text-muted-foreground">
                            {r.activos} activos · {r.conversion == null
                              ? r.conversionDisponible && r.divisorConversion === 0
                                ? 'sin divisor mensual'
                                : 'dato de conversión no disponible'
                              : `${textoConversionOperativa(r.conversion)} conversión`}
                            {r.operacionesCartera != null && r.operacionesCartera > 0
                              ? ` · ${numero(r.operacionesCartera)} de cartera`
                              : ''}
                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
                          </p>
                        </div>
                        {/* Decisión #10: el total unificado es el número grande y el
                            desglose por moneda va debajo. Sin TC degrada al PEN de
                            siempre — el USD no entra al total sin una tasa real. */}
                        <div className="shrink-0 text-right leading-tight">
                          <p className="text-sm font-extrabold tabular-nums text-foreground">
                            {cap.total != null ? moneyK(cap.total) : '—'}
                          </p>
                          <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
                        </div>
                      </div>
                      <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 gap-y-1 pl-[46px]">
                        {/* F2: el punto solo cuando HAY señal (ámbar 2–5 d,
                            rojo >5 d, neutro sin cartera). Pintar «al día» de
                            azul en cada fila gastaba el color en nada. Sin
                            leads abiertos no hay «al día» que celebrar:
                            `semaforoDias(0)` devolvía azul y un analista sin
                            cartera se pintaba como el que va al corriente. */}
                        {(r.activos === 0 || c !== SEMAFORO.ok || conRezagoAgenda) && (
                          <span
                            data-testid="equipo-semaforo"
                            className="size-2 shrink-0 rounded-full"
                            style={{ background: colorPunto }}
                            aria-hidden
                          />
                        )}
                        <span className="text-[11px] text-muted-foreground">
                          {r.activos === 0
                            ? 'Sin leads abiertos'
                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
                          {/* El rezago va en TEXTO pegado a la persona (aquí se
                              juzga, decisión 1 del 2026-08-23); el único chip
                              es el no-show repetido — uno de los dos rojos del
                              presupuesto de color. */}
                          {rez != null && rez.vencidas > 0
                            && ` · ${rez.vencidas} ${rez.vencidas === 1 ? 'vencida' : 'vencidas'}`}
                          {rez != null && rez.leads_sin_accion > 0
                            && ` · ${rez.leads_sin_accion} sin acción`}
                        </span>
                        {rez != null && rez.no_asistio >= 2 && (
                          <span className="ml-auto">
                            {/* solid: el soft (rojo sobre tinte) da 4.01:1 a 11px
                                y no llega a AA (revisor a11y, M2). */}
                            <Badge color={SEMAFORO.critico} variant="solid">{rez.no_asistio} no asistió</Badge>
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
              {(objetivosMensualesError || cumplimientoMensualError || conversionMensualError || tcCaido) && (
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
              )}
            </CardContent>
          </Card>

          {/* ── Por empresa: de dónde vino cada sol (Avance vs. COOPAC). Se
               oculta solo si el mes no tiene cierres en cooperativas. ── */}
          <DesglosePorEmpresa
            demo={yo?.demo === true}
            porVendedor={cumplimientoMensual?.porVendedor ?? null}
          />
        </div>
      </div>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
      </p>
    </div>
  )
}
