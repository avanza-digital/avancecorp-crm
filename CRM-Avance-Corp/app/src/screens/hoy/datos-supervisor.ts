// Datos COMPARTIDOS de Hoy · supervisor (27/09/2026). Los usan las dos
// pantallas del rol: la clásica (./supervisor.tsx, que sigue sirviendo el modo
// legado y el demo) y el puesto de mando (./supervisor-mando.tsx, modo activo).
// Se extrajeron tal cual de supervisor.tsx para que la meta, el reparto, la
// agenda y el tipo de cambio tengan UNA sola derivación: dos copias de esta
// lógica divergirían en silencio. La cola NO vive aquí: cada modo trae la suya.
import { useEffect, useMemo, useRef, useState } from 'react'
import {
  DIA_MS,
  capitalPrincipal,
  diasSinActividad,
  haceCortoTexto,
  indexarUltimaActividad,
  pctMeta,
} from '@/lib/inteligencia'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  capitalObjetivo,
  metaVigente,
  capitalReal,
  metaConversionAplicable,
  objetivosCero,
  periodoLima,
} from '@/lib/objetivos'
import { useConversionMensual, useMetricasAgenda } from '@/data/crm-queries'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import { useAhora } from '@/lib/ahora'
import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { mensajeDeError } from '@/data/crm-api'
import { money, moneyK, numero, porcentajeConversionCanonica } from '@/lib/format'
import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import { useTipoCambio } from '@/lib/tipo-cambio'

// Texto neutro de una meta que gerencia todavía no fijó para el mes.
const SIN_META = 'Sin meta fijada para este mes'

export interface FilaMeta {
  label: string
  txt: string
  pct: number
  sinDato: string | null
  nota?: string | null
}

export function useDatosSupervisor() {
  const {
    ambito,
    actividades,
    objetivos,
    objetivosError,
    cumplimientoMetas,
    cumplimientoMetasError,
    recargar,
    equipo,
  } = useCRMData()
  const { yo } = useAuth()
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

  // ── F1b: los agregados llegan del servidor (o del espejo demo vivo) ──
  // resumen_cartera_fn → tiles de capital/activos/parkeados;
  // metricas_vendedores_fn → ranking.
  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
  const resumen = resumenOp.resumen
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
  // Fase 3 «sin topes»: en sesión real el arranque ya no baja el registro de
  // actividades, y sin él la «espera» de un parkeado caería a `creado_en`
  // (un lead de 30 días parkeado hace una hora diría «30 días»; su
  // `tenencia_desde` se anula al quedar sin analista). Antes que exagerar, en
  // sesión real se omite la antigüedad: el conteo del RPC sigue siendo la
  // verdad y el CTA lo dice sin cifra. En demo sigue el timeline del fixture.
  const bandejaReparto = useMemo(() => {
    const parkeados = ambito.leads.filter(
      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null,
    )
    const indice = indexarUltimaActividad(actividades)
    return { parkeados, indice }
  }, [ambito, actividades])

  const esperaMasLargaReparto = useMemo(() => {
    if (!yo?.demo) return null
    if (bandejaReparto.parkeados.length === 0) return null
    let maxima = 0
    for (const lead of bandejaReparto.parkeados) {
      maxima = Math.max(
        maxima,
        diasSinActividad(lead, actividades, ahora, bandejaReparto.indice),
      )
    }
    return maxima
  }, [actividades, ahora, bandejaReparto, yo?.demo])

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
  const filasMeta: FilaMeta[] = [
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
  const hayErrorMensual = objetivosMensualesError || cumplimientoMensualError || conversionMensualError || tcCaido
  const reintentarMensual = () => {
    if (objetivosMensualesError || cumplimientoMensualError) {
      setRecargaPeriodoFallida(false)
      void recargar().then((ok) => {
        if (!ok && !fotoMensualStoreVigente) setRecargaPeriodoFallida(true)
      })
    }
    if (conversionMensualError) void qConversionMensual.refetch()
    if (tcCaido) recargarTipoCambio()
  }

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
  const recargarAgenda = () => {
    if (sesionReal) void consultaAgenda.refetch()
  }
  // Rezagos de agenda por miembro (vendedor_id → métrica) para que la señal de
  // vencidas / sin acción / no-shows viva DENTRO de la fila de "Tu equipo hoy":
  // la persona se juzga en un solo lugar, sin cruzar a la tabla de la izquierda.
  const rezagosAgenda = useMemo(
    () => new Map((datosAgenda?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
    [datosAgenda],
  )
  // Para DECIDIR (franja y semáforos del puesto de mando) la agenda cuenta
  // solo si está confirmada: TanStack conserva la última respuesta tras un
  // refetch fallido, y una señal vieja no puede pasar por vigente.
  const agendaConfirmada = errorAgenda == null ? datosAgenda : undefined

  return {
    ahora,
    ambito,
    actividades,
    equipo,
    resumenOp,
    resumen,
    vendedoresOp,
    rank,
    tc,
    capitalPronostico,
    esperaMasLargaReparto,
    totalPorRepartir,
    hayPorRepartir,
    detalleReparto,
    etiquetaAccesoReparto,
    cumplimientoMensual,
    conversionConfirmada,
    conversionMensualError,
    filasMeta,
    hayErrorMensual,
    reintentarMensual,
    sesionReal,
    datosAgenda,
    agendaConfirmada,
    errorAgenda,
    cargandoAgenda,
    recargarAgenda,
    rezagosAgenda,
  }
}
