import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { AlertTriangle, CalendarRange, RefreshCw, Target } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { Skeleton } from '@/components/ui/skeleton'
import { GerenciaMotion } from '@/components/gerencia/motion'
import { usePeriodoGerencia } from '@/components/gerencia/use-periodo-gerencia'
import {
  periodoInicialGerencia,
  periodoMesCalendario,
  semanticaMetaMensual,
  validarPeriodoGerencia,
  type PeriodoGerencia,
} from '@/components/gerencia/periodo'
import { useCRMData } from '@/lib/store-context'
import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
import { useAuth } from '@/lib/auth-context'
import { fmtFecha, money, moneyK, numero, porcentajeConversionCanonica } from '@/lib/format'
import { colorMeta, pctMeta } from '@/lib/inteligencia'
import {
  capitalObjetivo,
  metaVigente,
  capitalReal,
  objetivosCero,
} from '@/lib/objetivos'
import { metricasDistribucionDemo } from '@/lib/demo-metricas-distribucion'
import {
  conversionMensualInteligenciaDemo,
  cumplimientoMetasConversionEquipoDemo,
  conversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { identidadesEquipoConversion } from '@/lib/conversion-equipo'
import { ORIGENES_TODOS } from '@/lib/tipos'
import { useTipoCambio } from '@/lib/tipo-cambio'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import {
  useActualizarCapacidadLeadsObjetivo,
  useConversionMensual,
  useCumplimientoMetas,
  useMetricasConversiones,
  useMetricasConversionesEquipo,
  useMetricasDistribucionLeadsV3,
  useMetricasReuniones,
} from '@/data/crm-queries'
import { mensajeDeError } from '@/data/crm-api'
import { DistribucionLeadsGerencia } from './distribucion-leads-gerencia'
import { EquipoGerenciaPanel } from './equipo-gerencia'
import { InteligenciaComercialPanel } from './inteligencia-comercial'
import { MetasEditor } from './metas-editor'
import { RankingVendedoresPanel } from './ranking-vendedores'
import { ReunionesGerenciaPanel } from './reuniones-gerencia'
import { AvisoCierreMesPanel } from './aviso-cierre-mes'
import { ResumenGerenciaPanel } from './resumen-gerencia'
import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
import { CompromisosSupervisoresPanel } from './compromisos-supervisores'

interface ConsultaCargable {
  isPending: boolean
  data?: unknown
}

interface MetaItemProps {
  label: string
  actual: string
  objetivo: string
  progreso: number | null
  mensajeSinProgreso?: string | undefined
  nota?: JSX.Element | string | undefined
}

function estaCargando(sesionReal: boolean, consulta: ConsultaCargable): boolean {
  // Un refetch con datos previos no es una carga inicial: conservar la cifra
  // evita que los paneles desaparezcan mientras TanStack la revalida.
  return sesionReal && consulta.isPending && consulta.data === undefined
}

function errorConsulta(sesionReal: boolean, error: unknown, mensajeSeguro: string): string | null {
  return sesionReal && error ? mensajeDeError(error, mensajeSeguro) : null
}

function DesgloseMonedas({
  capital,
  fuenteTc,
}: {
  capital: ReturnType<typeof totalEnSoles>
  fuenteTc: string | null
}): JSX.Element | null {
  if (capital.estado === 'indisponible') return null
  const hayUsd = (capital.usd ?? 0) > 0
  return (
    <p className="text-[11px] tabular-nums text-[var(--gi-muted)]">
      {moneyK(capital.pen ?? 0, 'PEN')} + {moneyK(capital.usd ?? 0, 'USD')}
      {!hayUsd ? null : capital.tc == null ? (
        <span className="text-amber-700"> · sin tipo de cambio: el total NO incluye los dólares</span>
      ) : (
        <span> · {rotuloTipoCambio(capital.tc, fuenteTc ?? 'TC del día')}</span>
      )}
    </p>
  )
}

function MetaItem({ label, actual, objetivo, progreso, mensajeSinProgreso, nota }: MetaItemProps): JSX.Element {
  return (
    <div data-gi-kpi className="gi-kpi-card">
      <p className="gi-label">{label}</p>
      <div className="mt-2 flex items-baseline gap-2"><span className="text-2xl font-bold tabular-nums text-[var(--gi-blue)]">{actual}</span><span className="text-xs text-[var(--gi-muted)]">{objetivo}</span></div>
      {nota && <div className="mt-1">{nota}</div>}
      {progreso == null ? <p className="mt-3 text-xs text-[var(--gi-muted)]">{mensajeSinProgreso ?? 'Meta del mes todavía sin fijar'}</p> : <div className="mt-3 flex items-center gap-2"><Progress value={Math.min(100, progreso)} color={colorMeta(progreso)} className="flex-1" /><span className="w-10 text-right text-xs font-bold tabular-nums" style={{ color: colorMeta(progreso) }}>{Math.round(progreso)}%</span></div>}
    </div>
  )
}

function CabeceraGerencia({ periodo, borrador, onCambiarBorrador, onAplicar, origen, onCambiarOrigen, origenDeshabilitado, modo, mes, mesMaximo, etiquetaMes, onCambiarMes }: { periodo: PeriodoGerencia; borrador: PeriodoGerencia; onCambiarBorrador: (campo: keyof PeriodoGerencia, valor: string) => void; onAplicar: () => void; origen: string | null; onCambiarOrigen: (origen: string | null) => void; origenDeshabilitado: boolean; modo: 'rango' | 'mes' | 'mixto'; mes: string; mesMaximo: string; etiquetaMes: string; onCambiarMes: (mes: string) => void }): JSX.Element {
  const validacion = validarPeriodoGerencia(borrador)
  const sinCambios = borrador.desde === periodo.desde && borrador.hasta === periodo.hasta
  const hoyLima = periodoInicialGerencia().hasta
  const maximoDesde = borrador.hasta && borrador.hasta < hoyLima ? borrador.hasta : hoyLima
  const etiquetaRango = `${fmtFecha(periodo.desde)} al ${fmtFecha(periodo.hasta)}`
  if (modo === 'mes') {
    return (
      <div data-gi-toolbar className="gi-toolbar">
        <div className="flex items-center gap-2"><CalendarRange className="size-4 text-[var(--gi-blue)]" /><label htmlFor="mes-gerencia" className="gi-label">Mes calendario</label></div>
        <input
          id="mes-gerencia"
          aria-label="Mes calendario"
          type="month"
          value={mes}
          max={mesMaximo}
          onChange={(e) => onCambiarMes(e.target.value)}
          className="gi-date"
        />
      </div>
    )
  }
  return (
    <div data-gi-toolbar className="gi-toolbar">
      <div className="flex items-center gap-2"><CalendarRange className="size-4 text-[var(--gi-blue)]" /><span className="gi-label">Período</span></div>
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <input aria-label="Desde" aria-describedby={!validacion.valido ? 'error-periodo-gerencia' : undefined} type="date" value={borrador.desde} max={maximoDesde} onChange={(e) => onCambiarBorrador('desde', e.target.value)} className="gi-date" />
          <span className="text-xs text-[var(--gi-muted)]">a</span>
          <input aria-label="Hasta" aria-describedby={!validacion.valido ? 'error-periodo-gerencia' : undefined} type="date" value={borrador.hasta} min={borrador.desde} max={hoyLima} onChange={(e) => onCambiarBorrador('hasta', e.target.value)} className="gi-date" />
          <button type="button" disabled={!validacion.valido || sinCambios} onClick={onAplicar} className="gi-apply">Aplicar</button>
          {/* Filtro de ORIGEN del lote (Miguel, 27/08): recorta las lecturas
              del período en Resumen y Conversiones. En demo se apaga: el
              mundo de ejemplo no filtra. */}
          {modo === 'mixto' && (
            <select
              aria-label="Origen del lead"
              value={origen ?? ''}
              disabled={origenDeshabilitado}
              onChange={(e) => onCambiarOrigen(e.target.value === '' ? null : e.target.value)}
              className="gi-date"
              title={origenDeshabilitado ? 'Los datos de ejemplo no se filtran' : undefined}
            >
              <option value="">Todos los orígenes</option>
              {ORIGENES_TODOS.map((o) => <option key={o.k} value={o.k}>{o.label}</option>)}
              <option value="sin_origen">Sin origen registrado</option>
            </select>
          )}
        </div>
        {modo === 'mixto' && (
          <p role="status" className="mt-1.5 text-[11px] font-medium text-[var(--gi-muted)]">
            {origenDeshabilitado
              ? `Conversión, metas y capital: ${etiquetaMes} completo · el rango recorta Cosecha, citas y embudo. Los datos de ejemplo no se filtran por origen.`
              : `Conversión y citas: ${etiquetaRango} · metas y capital: ${etiquetaMes}. El origen recorta Cosecha y embudo; la conversión canónica sigue mostrando todos los orígenes.`}
          </p>
        )}
        {!validacion.valido && (
          <p id="error-periodo-gerencia" role="alert" className="mt-1.5 text-[11px] font-semibold text-destructive">
            {validacion.mensaje}
          </p>
        )}
      </div>
    </div>
  )
}

export type SeccionGerencia = 'completo' | 'resumen' | 'conversiones' | 'ranking-vendedores' | 'reuniones' | 'metas' | 'rendimiento'

export function HoyGerencia({ seccion = 'completo' }: { seccion?: SeccionGerencia }): JSX.Element {
  const {
    ambito,
    equipo,
    objetivos,
    objetivosError = false,
    cumplimientoMetas,
    recargar,
  } = useCRMData()
  const { yo } = useAuth()
  const { periodo, setPeriodo, diaLima, origenFiltrado, setOrigenFiltrado } = usePeriodoGerencia()
  const [borrador, setBorrador] = useState<PeriodoGerencia>(periodo)
  const periodoAnterior = useRef(periodo)
  const [ejemploConversiones, setEjemploConversiones] = useState(false)
  const [ejemploReuniones, setEjemploReuniones] = useState(false)
  const [recargaPeriodoFallida, setRecargaPeriodoFallida] = useState(false)
  useEffect(() => {
    const anterior = periodoAnterior.current
    setBorrador((actual) => (
      actual.desde === anterior.desde && actual.hasta === anterior.hasta
        ? periodo
        : actual
    ))
    periodoAnterior.current = periodo
  }, [periodo])
  const sesionReal = Boolean(yo && !yo.demo)
  const modoDemo = yo?.demo === true
  const periodoMetricas = periodo
  const ahoraPeriodo = Date.parse(`${diaLima}T12:00:00Z`)
  const periodoVigenteStore = periodoInicialGerencia(ahoraPeriodo).desde
  const fotoMensualStoreVigente = !sesionReal || (
    objetivos.periodo === periodoVigenteStore
    && (cumplimientoMetas == null || cumplimientoMetas.periodo === periodoVigenteStore)
  )
  const periodoStoreIntentado = useRef<string | null>(null)
  useEffect(() => {
    if (!sesionReal || fotoMensualStoreVigente
      || periodoStoreIntentado.current === periodoVigenteStore) return
    periodoStoreIntentado.current = periodoVigenteStore
    setRecargaPeriodoFallida(false)
    void recargar().then((ok) => {
      if (!ok) setRecargaPeriodoFallida(true)
    })
  }, [fotoMensualStoreVigente, periodoVigenteStore, recargar, sesionReal])
  // Los rankings son estrictamente mensuales: la fecha final elige el mes y
  // este corte único gobierna conversión, capital y cosecha. Para el mes vivo
  // termina hoy; para uno cerrado usa su último día calendario.
  const periodoRanking = useMemo(
    () => modoDemo
      ? periodoInicialGerencia(ahoraPeriodo)
      : periodoMesCalendario(periodoMetricas.hasta.slice(0, 7), ahoraPeriodo),
    [ahoraPeriodo, modoDemo, periodoMetricas.hasta],
  )
  const rankingHistorico = periodoRanking.desde !== periodoInicialGerencia(ahoraPeriodo).desde
  const vistaMensual = seccion === 'ranking-vendedores' || seccion === 'metas' || seccion === 'rendimiento'
  const vistaConRangoYOrigen = seccion === 'completo' || seccion === 'resumen' || seccion === 'conversiones'
  const modoCabecera: 'rango' | 'mes' | 'mixto' = vistaMensual
    ? 'mes'
    : vistaConRangoYOrigen ? 'mixto' : 'rango'
  // Todo capital histórico se convierte con el corte de SU mes. El hook
  // conserva la búsqueda de los últimos siete días aprobada para el TC.
  const usaTipoCambioHistorico = rankingHistorico
    && ['completo', 'resumen', 'ranking-vendedores', 'metas'].includes(seccion)
  const fechaCorteTipoCambio = usaTipoCambioHistorico
    ? periodoRanking.hasta
    : undefined
  const tipoCambio = useTipoCambio(
    seccion === 'ranking-vendedores' || seccion === 'metas'
    || seccion === 'completo' || seccion === 'resumen',
    fechaCorteTipoCambio,
  )
  const recargarTipoCambio = tipoCambio.recargar
  const diaTipoCambioAnterior = useRef(diaLima)
  useEffect(() => {
    if (diaTipoCambioAnterior.current === diaLima) return
    diaTipoCambioAnterior.current = diaLima
    if (!usaTipoCambioHistorico) recargarTipoCambio()
  }, [diaLima, recargarTipoCambio, usaTipoCambioHistorico])
  // `metricas_conversiones_fn` alimenta inteligencia/resumen, NO el ranking.
  // El ranking tiene tres fuentes propias y todas nacen de los núcleos: mensual,
  // cumplimiento de metas/capital y cosecha. Mantenerlo en esta lista hacía que
  // una consulta lateral pudiera apagar sus tres pestañas.
  const necesitaConversiones = ['completo', 'resumen', 'conversiones'].includes(seccion)
  const necesitaConversionMensual = ['completo', 'resumen', 'conversiones', 'ranking-vendedores', 'metas', 'rendimiento'].includes(seccion)
  const necesitaReuniones = ['completo', 'resumen', 'reuniones'].includes(seccion)
  const necesitaDistribucion = seccion === 'rendimiento'
  // El filtro de origen SOLO gobierna las lecturas del LOTE (Resumen y
  // Conversiones); las demas secciones piden sin filtro.
  const origenActivo = seccion === 'completo' || seccion === 'resumen' || seccion === 'conversiones'
    ? origenFiltrado
    : null
  const conversiones = useMetricasConversiones(
    sesionReal && necesitaConversiones,
    periodoMetricas.desde,
    periodoMetricas.hasta,
    origenActivo,
  )
  const reuniones = useMetricasReuniones(
    sesionReal && necesitaReuniones,
    periodoMetricas.desde,
    periodoMetricas.hasta,
  )
  const distribucion = useMetricasDistribucionLeadsV3(sesionReal && necesitaDistribucion, periodo.desde, periodo.hasta)
  const actualizarCapacidad = useActualizarCapacidadLeadsObjetivo()
  // LA CONVERSIÓN DEL MES de la empresa (crm.conversion_mensual_fn). La RPC es
  // MENSUAL por contrato y este panel se gobierna con un rango LIBRE: se pide
  // el mes de la FECHA FINAL del rango (decisión E2, plan §4bis) — mismo
  // criterio que ya usa el aviso del panel de metas.
  const periodoConversionMes = periodoRanking.desde
  const qConversionMensual = useConversionMensual(
    sesionReal && necesitaConversionMensual,
    periodoConversionMes,
    'global',
    yo?.id,
  )
  const consultaMensualRealActiva = sesionReal && necesitaConversionMensual
  const qCumplimientoRanking = useCumplimientoMetas(
    consultaMensualRealActiva,
    periodoRanking.desde,
    yo?.id,
  )
  // Cosecha por analista del ranking (F2.2/D2): mismo MES que la mensual del
  // tab — del 01 al final del rango elegido — para que las dos lecturas de una
  // fila hablen del mismo período. Solo se consulta en la sección que la pinta.
  const qCosechaRanking = useMetricasConversionesEquipo(
    sesionReal && seccion === 'ranking-vendedores',
    periodoRanking.desde,
    periodoRanking.hasta,
    'global',
    yo?.id,
  )
  const cosechaRanking = seccion !== 'ranking-vendedores' || modoDemo
    ? undefined
    : (qCosechaRanking.isPending && qCosechaRanking.data === undefined)
        || (rankingHistorico && qCosechaRanking.isFetching)
      ? undefined
      : (qCosechaRanking.data ?? null)
  const cosechaRankingCargando = sesionReal
    && seccion === 'ranking-vendedores'
    && ((qCosechaRanking.isPending && qCosechaRanking.data === undefined)
      || (rankingHistorico && qCosechaRanking.isFetching))
  const conversionesDeEjemplo = modoDemo || ejemploConversiones
  const reunionesDeEjemplo = modoDemo || ejemploReuniones
  const conversionMensualCargando = consultaMensualRealActiva
    && !conversionesDeEjemplo
    && ((qConversionMensual.isPending && qConversionMensual.data === undefined)
      || (rankingHistorico && qConversionMensual.isFetching))
  // El mundo demo de gerencia es `demo-v*` (el de inteligencia comercial): el
  // tile héroe y los paneles de la familia beben del MISMO payload derivado —
  // un total en el héroe y otro en el ranking sería la demo enseñando dos
  // negocios distintos.
  const conversionMensualDemoIntel = useMemo(
    () => (conversionesDeEjemplo
      ? conversionMensualInteligenciaDemo(Date.parse(`${periodoRanking.desde}T12:00:00-05:00`))
      : null),
    [conversionesDeEjemplo, periodoRanking.desde],
  )
  const conversionMensual = modoDemo
    ? conversionMensualDemoIntel
    : (qConversionMensual.data ?? null)
  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
  // 2026-08-14): la regla compartida decide, no cada pantalla por su cuenta.
  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
  const conversionMensualMedible = lecturaConversion.mostrar
  // Para los paneles: tri-estado como el TC — `undefined` mientras consulta
  // (skeleton), `null` cuando no está (fail-closed: jamás ceros ni fórmulas
  // viejas bajo el rótulo nuevo).
  const conversionMensualPaneles = conversionesDeEjemplo
    ? conversionMensualDemoIntel
    : conversionMensualCargando
      ? undefined
      : (qConversionMensual.data ?? null)
  const equipoConversionVigente = useMemo(
    () => identidadesEquipoConversion(ambito.vendedores, equipo),
    [ambito.vendedores, equipo],
  )
  // Nombres del roster completo para la traza de compromisos (F4.4).
  const nombresEquipo = useMemo(
    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
    [equipo],
  )
  const cumplimientoDemo = useMemo(
    () => {
      if (!conversionesDeEjemplo) return null
      return { ...cumplimientoMetasConversionEquipoDemo(), periodo: periodoRanking.desde }
    },
    [conversionesDeEjemplo, periodoRanking.desde],
  )
  const cumplimientoRankingCargando = consultaMensualRealActiva && !conversionesDeEjemplo
    && ((qCumplimientoRanking.isPending && qCumplimientoRanking.data === undefined)
      || (rankingHistorico && qCumplimientoRanking.isFetching))
  const cumplimientoRanking = conversionesDeEjemplo
    ? cumplimientoDemo
    : sesionReal
      ? cumplimientoRankingCargando
        ? undefined
        : (qCumplimientoRanking.data ?? null)
      : cumplimientoMetas
  // Meta, capital e identidad salen de la MISMA foto mensual. Si la foto no
  // llegó, se falla cerrado con ceros de objetivo y capital «—»: nunca se
  // recicla el store del mes vigente dentro de un histórico.
  const cumplimiento = cumplimientoRanking?.gerencia ?? null
  const metaBase = useMemo(
    () => objetivosCero(periodoRanking.desde).gerencia,
    [periodoRanking.desde],
  )
  const meta = metaVigente(sesionReal ? metaBase : objetivos.gerencia, cumplimiento)
  const equipoConversionHistorico = useMemo(
    () => Object.values(cumplimientoRanking?.porVendedor ?? {}).map((fila) => ({
      vendedorId: fila.vendedorId,
      nombre: fila.nombre,
      supervisorId: fila.supervisorId,
      supervisorNombre: fila.supervisorNombre,
      leads: 0,
      contactados: 0,
      reunionesPactadas: 0,
      reunionesRealizadas: 0,
      clientes: 0,
      descartados: 0,
      conversionPct: null,
    })).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es') || (a.vendedorId ?? '').localeCompare(b.vendedorId ?? '')),
    [cumplimientoRanking?.porVendedor],
  )
  const datosConversion = conversionesDeEjemplo ? metricasConversionesDemo(periodoMetricas.desde, periodoMetricas.hasta) : conversiones.data
  const datosEquipoConversionRango = conversionesDeEjemplo
    ? conversionEquipoDemo()
    : equipoConversionVigente
  const datosEquipoConversion = conversionesDeEjemplo
    ? conversionEquipoDemo()
    : rankingHistorico ? equipoConversionHistorico : equipoConversionVigente
  const metasVendedoresVisuales = conversionesDeEjemplo
    ? metasConversionEquipoDemo()
    : (cumplimientoRanking?.porVendedor ?? {})
  // `CumplimientoVendedor` contiene la meta de la misma revisión que el capital.
  // La identidad/población se decide aparte en el panel: roster vivo hoy y foto
  // congelada únicamente para históricos.
  const metasVendedoresRanking = cumplimientoRanking?.porVendedor ?? {}
  const metaMensualRanking = useMemo(() => {
    const semantica = semanticaMetaMensual(periodoRanking, ahoraPeriodo, periodoRanking)
    const errorCarga = !conversionesDeEjemplo
      && (sesionReal ? qCumplimientoRanking.isError : objetivosError)
    return errorCarga
      ? { ...semantica, comparable: false, errorCarga: true }
      : semantica
  }, [ahoraPeriodo, conversionesDeEjemplo, objetivosError, periodoRanking, qCumplimientoRanking.isError, sesionReal])
  const metaConversionVisual = meta.conversionObjetivo
  const metaMensualConversion = metaMensualRanking
  const datosReuniones = reunionesDeEjemplo ? metricasReunionesDemo(periodoMetricas.desde, periodoMetricas.hasta) : reuniones.data
  const datosDistribucion = modoDemo ? metricasDistribucionDemo(periodo.desde, periodo.hasta) : distribucion.data
  const errorConversiones = conversionesDeEjemplo ? null : errorConsulta(sesionReal, conversiones.error, 'No se pudieron cargar las conversiones.')
  const mesFotoMensualEsperado = periodoRanking.desde.slice(0, 7)
  const mesConversionMensual = qConversionMensual.data?.periodo.mes
  const mesCumplimientoMensual = qCumplimientoRanking.data?.periodo.slice(0, 7)
  const mesCosechaMensual = qCosechaRanking.data?.periodo.desde.slice(0, 7)
  const cierreConversionMensual = qConversionMensual.data?.cierre?.cerrado
  const cierreCumplimientoMensual = qCumplimientoRanking.data?.cierre?.cerrado
  const cierreCosechaMensual = qCosechaRanking.data?.cierre?.cerrado
  const conversionPublicaRevision = qConversionMensual.data != null
    && 'revision' in qConversionMensual.data
  const cosechaPublicaRevision = qCosechaRanking.data != null
    && 'revision' in qCosechaRanking.data
  const cosechaPublicaCierre = qCosechaRanking.data != null
    && 'cierre' in qCosechaRanking.data
  const fotoMensualBaseLista = !conversionesDeEjemplo
    && consultaMensualRealActiva
    && qConversionMensual.data != null
    && qCumplimientoRanking.data != null
  const fotoMensualCompletaLista = fotoMensualBaseLista
    && seccion === 'ranking-vendedores'
    && qCosechaRanking.data != null
  const fotoMensualBaseDesalineada = fotoMensualBaseLista && (
    mesConversionMensual !== mesFotoMensualEsperado
    || mesCumplimientoMensual !== mesFotoMensualEsperado
    || (
      conversionPublicaRevision
      && qConversionMensual.data?.revision !== qCumplimientoRanking.data?.revision
    )
    || (
      typeof cierreConversionMensual === 'boolean'
      && typeof cierreCumplimientoMensual === 'boolean'
      && cierreConversionMensual !== cierreCumplimientoMensual
    )
  )
  // Rollout compatible: con el backend anterior, conversión y cosecha no traen
  // `revision`/`cierre` y se conserva la verificación previa entre las dos fotos.
  // Apenas cualquiera publique la revisión nueva, las TRES deben publicarla y
  // coincidir; una mezcla de respuestas antes/después del deploy falla cerrada.
  const fotoMensualRankingDesalineada = fotoMensualBaseDesalineada
    || Boolean(fotoMensualCompletaLista && (
      mesCosechaMensual !== mesFotoMensualEsperado
      || qCosechaRanking.data?.periodo.desde !== periodoRanking.desde
      || qCosechaRanking.data?.periodo.hasta !== periodoRanking.hasta
      || ((conversionPublicaRevision || cosechaPublicaRevision) && (
        typeof qConversionMensual.data?.revision !== 'number'
        || typeof qCosechaRanking.data?.revision !== 'number'
        || qConversionMensual.data.revision !== qCumplimientoRanking.data?.revision
        || qCosechaRanking.data.revision !== qCumplimientoRanking.data?.revision
      ))
      || (cosechaPublicaCierre && (
        typeof cierreConversionMensual !== 'boolean'
        || typeof cierreCumplimientoMensual !== 'boolean'
        || typeof cierreCosechaMensual !== 'boolean'
        || cierreConversionMensual !== cierreCumplimientoMensual
        || cierreCosechaMensual !== cierreCumplimientoMensual
      ))
    ))
  const mensajeFotoMensualDesalineada = 'Las fuentes de la foto mensual no corresponden al mismo mes, revisión o estado de cierre. Reintenta para completar la actualización.'
  // La MENSUAL es LA fuente del tab de conversión del ranking: si falla, el
  // panel lo dice con Reintentar — no degrada mudo a «indisponible» (exigencia
  // pre-release de Miguel, 2026-08-15).
  const errorConversionMensual = conversionesDeEjemplo
    ? null
    : fotoMensualBaseDesalineada
      ? mensajeFotoMensualDesalineada
      : errorConsulta(sesionReal, qConversionMensual.error, 'No se pudo calcular la conversión mensual.')
  const errorCosechaRanking = modoDemo
    ? null
    : errorConsulta(sesionReal, qCosechaRanking.error, 'No se pudo calcular la cosecha del lote.')
  const errorFotoMensualRanking = !conversionesDeEjemplo && consultaMensualRealActiva
    ? qCumplimientoRanking.isError
      ? 'No se pudieron cargar la identidad, las metas y el capital del mes elegido.'
      : fotoMensualRankingDesalineada
        ? mensajeFotoMensualDesalineada
        : null
    : null
  const errorReuniones = reunionesDeEjemplo ? null : errorConsulta(sesionReal, reuniones.error, 'No se pudieron cargar las métricas de citas.')
  // La foto MENSUAL alimenta metas, capital, ranking y el fallback compatible
  // del Resumen. Su fallo sigue siendo un error reintentable del panel, pero la
  // cifra principal toma el núcleo canónico del rango cuando está disponible.
  const errorResumen = [errorConversiones, errorConversionMensual, errorFotoMensualRanking, errorReuniones].filter(Boolean).join(' ') || null
  const capitalActualPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalActualUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  // PEN y USD no se suman a ciegas: se convierte a tasa real y se rotula cuál
  // se aplicó. Mismo criterio que el panel del analista (decisión #10).
  const tcPromedio = tipoCambio.tc?.promedio ?? null
  const capitalTotal = totalEnSoles(capitalActualPen, capitalActualUsd, tcPromedio)
  const metaTotalCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tcPromedio)
  // Sin dólares el tipo de cambio es irrelevante y no debe degradar nada; con
  // dólares y el TC en vuelo, no se puede afirmar todavía ni el total ni el %.
  const hayDolares = (capitalActualUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tipoCambio.tc === undefined && hayDolares
  const tcCaido = tipoCambio.tc === null && hayDolares
  const ajusteCierre = cumplimiento?.ajuste
  const hayAjusteCierre = ajusteCierre != null && (
    ajusteCierre.aplicadoPen > 0
    || ajusteCierre.aplicadoUsd > 0
    || ajusteCierre.contratosAplicados > 0
  )
  const totalConversion = totalConversionPublicable(conversionMensual)
  const conversionActual = totalConversion?.conversion_pct ?? null
  const reintentarConversiones = () => { if (sesionReal) void conversiones.refetch() }
  const reintentarConversionMensual = () => { if (sesionReal) void qConversionMensual.refetch() }
  const reintentarReuniones = () => { if (sesionReal) void reuniones.refetch() }
  const reintentarDistribucion = () => { if (sesionReal) void distribucion.refetch() }
  const esResumen = seccion === 'completo' || seccion === 'resumen'
  const errorRendimiento = errorConversionMensual ?? errorFotoMensualRanking
  const periodoPie = vistaMensual ? periodoRanking : periodo
  const claveMotion = `${seccion}|${periodo.desde}|${periodo.hasta}|${conversionesDeEjemplo}|${reunionesDeEjemplo}`

  return (
    <GerenciaMotion clave={claveMotion} className="mx-auto max-w-[1640px] space-y-4">
      <CabeceraGerencia
        periodo={periodo}
        borrador={borrador}
        onCambiarBorrador={(campo, valor) => setBorrador((actual) => ({ ...actual, [campo]: valor }))}
        onAplicar={() => setPeriodo(borrador)}
        origen={conversionesDeEjemplo ? null : origenFiltrado}
        onCambiarOrigen={setOrigenFiltrado}
        origenDeshabilitado={conversionesDeEjemplo}
        modo={modoCabecera}
        mes={periodoRanking.desde.slice(0, 7)}
        mesMaximo={diaLima.slice(0, 7)}
        etiquetaMes={metaMensualRanking.etiqueta}
        onCambiarMes={(mes) => {
          if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(mes) || mes > diaLima.slice(0, 7)) return
          setPeriodo(periodoMesCalendario(mes, ahoraPeriodo))
        }}
      />

      {/* El aviso del ciclo del cierre de mes, en TODAS las secciones: la
          alarma de un ciclo atascado no puede depender de qué pestaña se mire.
          Solo en sesión real — el estado habla de la maquinaria de verdad. */}
      {sesionReal && <AvisoCierreMesPanel />}

      {esResumen && <ResumenGerenciaPanel conversiones={datosConversion} conversionMensual={cumplimientoRankingCargando ? undefined : conversionMensualPaneles} origenFiltrado={modoDemo ? null : origenActivo} reuniones={datosReuniones} equipo={datosEquipoConversionRango} equipoMensual={datosEquipoConversion} meta={meta} cumplimiento={cumplimiento} metaMensual={metaMensualRanking} tc={tipoCambio.tc} cargando={estaCargando(sesionReal, conversiones) || conversionMensualCargando || cumplimientoRankingCargando || estaCargando(sesionReal, reuniones)} rangoCargando={!conversionesDeEjemplo && estaCargando(sesionReal, conversiones)} mensualCargando={!conversionesDeEjemplo && (conversionMensualCargando || cumplimientoRankingCargando)} error={errorResumen} modoDemo={modoDemo} onReintentar={() => { reintentarConversiones(); reintentarConversionMensual(); void qCumplimientoRanking.refetch(); reintentarReuniones(); tipoCambio.recargar() }} />}

      {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC), por analista.
          Se oculta solo si el mes no tiene cierres en cooperativas. */}
      {esResumen && (
        <DesglosePorEmpresa demo={modoDemo} porVendedor={cumplimientoRanking?.porVendedor ?? null} />
      )}

      {/* F4.4: la trazabilidad de los reconocimientos — qué alertas atenuaron
          o pospusieron los supervisores y hasta cuándo rigen. Lectura pura. */}
      {esResumen && (
        <CompromisosSupervisoresPanel demo={modoDemo} nombrePorId={nombresEquipo} />
      )}

      {seccion === 'conversiones' && (
        <InteligenciaComercialPanel
          datos={datosConversion}
          conversionMensual={cumplimientoRankingCargando ? undefined : conversionMensualPaneles}
          cumplimiento={cumplimiento}
          origenFiltrado={conversionesDeEjemplo ? null : origenActivo}
          equipo={datosEquipoConversionRango}
          equipoMensual={datosEquipoConversion}
          metaConversion={metaConversionVisual}
          metasVendedores={metasVendedoresVisuales}
          cumplimientoVendedores={cumplimientoRanking?.porVendedor ?? {}}
          metaMensual={metaMensualConversion}
          mensualCargando={!conversionesDeEjemplo
            && (conversionMensualCargando || cumplimientoRankingCargando)}
          mensualError={errorConversionMensual ?? errorFotoMensualRanking}
          rangoCargando={!conversionesDeEjemplo && estaCargando(sesionReal, conversiones)}
          rangoError={errorConversiones}
          modoDemo={conversionesDeEjemplo}
          puedeAlternarEjemplo={sesionReal}
          onAlternarEjemplo={() => {
            if (!ejemploConversiones) setOrigenFiltrado(null)
            setEjemploConversiones((actual) => !actual)
          }}
          onReintentarMensual={() => {
            reintentarConversionMensual()
            void qCumplimientoRanking.refetch()
          }}
          onReintentarRango={reintentarConversiones}
        />
      )}

      {seccion === 'ranking-vendedores' && (
        <RankingVendedoresPanel
          conversionMensual={conversionMensualPaneles}
          conversionError={errorConversionMensual}
          onReintentarConversion={() => {
            reintentarConversionMensual()
            if (fotoMensualBaseDesalineada) void qCumplimientoRanking.refetch()
          }}
          cosecha={cosechaRanking}
          cosechaCargando={cosechaRankingCargando}
          cosechaError={errorCosechaRanking}
          onReintentarCosecha={() => { if (sesionReal) void qCosechaRanking.refetch() }}
          equipo={datosEquipoConversion}
          metasVendedores={metasVendedoresRanking}
          cumplimientoVendedores={cumplimientoRanking?.porVendedor ?? {}}
          fueraRanking={cumplimientoRanking?.fueraRanking ?? []}
          metaMensual={metaMensualRanking}
          // El mes vivo sigue el roster activo; solo un mes histórico congela
          // nombre, supervisor y población en la foto mensual.
          usarIdentidadSnapshot={rankingHistorico}
          {...(rankingHistorico && cumplimientoRanking?.cierre
            ? { estadoFotoMensual: cumplimientoRanking.cierre.cerrado ? 'sellada' as const : 'abierta' as const }
            : {})}
          fotoMensualCargando={cumplimientoRankingCargando}
          fotoMensualError={errorFotoMensualRanking}
          onReintentarFotoMensual={() => {
            void qConversionMensual.refetch()
            void qCumplimientoRanking.refetch()
            void qCosechaRanking.refetch()
          }}
          capitalError={null}
          onReintentarCapital={() => {
            tipoCambio.recargar()
          }}
          tc={tipoCambio.tc}
          etiquetaAlcance={modoDemo ? 'Demo · mes vigente' : 'Equipo completo'}
        />
      )}

      {seccion === 'reuniones' && <ReunionesGerenciaPanel datos={datosReuniones} cargando={!reunionesDeEjemplo && estaCargando(sesionReal, reuniones)} error={errorReuniones} modoDemo={reunionesDeEjemplo} puedeAlternarEjemplo={sesionReal} onAlternarEjemplo={() => setEjemploReuniones((actual) => !actual)} onReintentar={reintentarReuniones} />}

      {seccion === 'metas' && (
        <Card className="gi-card overflow-hidden border-0 shadow-none">
          <div className="flex items-center gap-2 border-b border-[var(--gi-line)] bg-white px-5 py-4">
            <Target className="size-4 text-[var(--gi-blue)]" />
            <div>
              <h2 className="gi-title">Metas mensuales</h2>
              <p className="gi-caption mt-0.5">Meta mensual · {metaMensualRanking.etiqueta}</p>
            </div>
          </div>
          <CardContent className="space-y-5 bg-[var(--gi-canvas)] p-4 sm:p-5">
            {errorFotoMensualRanking && (
              <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4">
                <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
                  <AlertTriangle className="size-4" aria-hidden /> {errorFotoMensualRanking}
                </span>
                <Button type="button" variant="outline" size="sm" onClick={() => void qCumplimientoRanking.refetch()}>
                  <RefreshCw aria-hidden /> Reintentar cumplimiento
                </Button>
              </div>
            )}

            {errorConversionMensual && (
              <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4">
                <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
                  <AlertTriangle className="size-4" aria-hidden /> {errorConversionMensual}
                </span>
                <Button type="button" variant="outline" size="sm" onClick={reintentarConversionMensual}>
                  <RefreshCw aria-hidden /> Reintentar conversión
                </Button>
              </div>
            )}

            {tcCaido && (
              <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-amber-300/70 p-4">
                <span className="flex items-center gap-2 text-sm font-semibold text-amber-900">
                  <AlertTriangle className="size-4" aria-hidden /> Sin tipo de cambio, el total no incluye los dólares.
                </span>
                <Button type="button" variant="outline" size="sm" onClick={() => tipoCambio.recargar()}>
                  <RefreshCw aria-hidden /> Reintentar tipo de cambio
                </Button>
              </div>
            )}

            {conversionMensualCargando || cumplimientoRankingCargando ? (
              <Skeleton className="h-44 rounded-2xl" aria-label="Cargando metas del mes seleccionado" />
            ) : <div className="grid gap-4 sm:grid-cols-2">
                <MetaItem
                  label="Capital confirmado del mes"
                  actual={capitalTotal.total == null ? '—' : money(capitalTotal.total, 'PEN')}
                  objetivo={metaMensualRanking.errorCarga
                    ? 'meta no disponible'
                    : (metaTotalCapital.total ?? 0) > 0
                        ? `de ${money(metaTotalCapital.total ?? 0, 'PEN')}`
                        : 'meta por definir'}
                  nota={(
                    <>
                      <DesgloseMonedas capital={capitalTotal} fuenteTc={tipoCambio.tc?.fuente ?? null} />
                      {hayAjusteCierre && ajusteCierre && (
                        <p
                          className="text-[11px] font-semibold tabular-nums text-amber-800"
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
                  progreso={!tcEnVuelo && (metaTotalCapital.total ?? 0) > 0 && capitalTotal.total != null
                    ? pctMeta(capitalTotal.total, metaTotalCapital.total ?? 0)
                    : null}
                  mensajeSinProgreso={metaMensualRanking.errorCarga
                    ? 'No pudimos cargar la meta mensual'
                    : tcEnVuelo
                        ? 'Consultando el tipo de cambio para consolidar los dólares…'
                        : (metaTotalCapital.total ?? 0) <= 0
                            ? undefined
                            : capitalTotal.total == null
                                ? 'Cumplimiento confirmado no disponible'
                                : undefined}
                />
                <MetaItem
                  label="Conversión de la empresa"
                  actual={porcentajeConversionCanonica(conversionActual)}
                  objetivo={metaMensualRanking.errorCarga
                    ? 'meta no disponible'
                    : meta.conversionObjetivo > 0 ? `de ${meta.conversionObjetivo}%` : 'meta por definir'}
                  nota={[
                    // Sin conteo de base aquí (veto del doble contador,
                    // 27/08): el detalle vive en Conversiones.
                    'El detalle por analista está en Conversiones.',
                    // Por qué la cifra no es definitiva, PEGADO a ella y no en
                    // su lugar: sustituirla era lo que hacía que un mes con
                    // recibidos y cierres dijera «sin datos».
                    lecturaConversion.mostrar ? lecturaConversion.aviso : null,
                  ].filter(Boolean).join(' · ')}
                  progreso={meta.conversionObjetivo > 0 && conversionActual != null
                    ? pctMeta(conversionActual, meta.conversionObjetivo)
                    : null}
                  mensajeSinProgreso={!conversionMensualMedible && conversionMensual != null
                    ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
                    : metaMensualRanking.errorCarga
                        ? 'No pudimos cargar la meta mensual'
                        : meta.conversionObjetivo <= 0
                            ? undefined
                            : conversionActual == null
                                ? 'Todavía no hay leads recibidos este mes'
                                : undefined}
                />
            </div>}

            {rankingHistorico ? (
              <p role="status" className="rounded-xl border border-[var(--gi-line)] bg-white px-4 py-3 text-xs font-medium text-[var(--gi-muted)]">
                Vista histórica de {metaMensualRanking.etiqueta}.
                {cumplimientoRanking?.cierre
                  ? cumplimientoRanking.cierre.cerrado
                    ? ' Foto sellada: sus cifras son definitivas.'
                    : ' Mes aún abierto: sus cifras pueden cambiar hasta el cierre.'
                  : ''}
                {' '}La edición solo está disponible en el mes vigente.
              </p>
            ) : !fotoMensualStoreVigente ? (
              <div
                data-gi-panel
                role={recargaPeriodoFallida ? 'alert' : 'status'}
                className="gi-card flex flex-wrap items-center justify-between gap-3 border border-[var(--gi-line)] p-4 sm:p-5"
              >
                <div className="flex items-start gap-3">
                  {recargaPeriodoFallida
                    ? <AlertTriangle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
                    : <RefreshCw className="mt-0.5 size-4 shrink-0 animate-spin text-[var(--gi-blue)]" aria-hidden />}
                  <div>
                    <p className="text-sm font-bold text-[var(--gi-navy)]">
                      {recargaPeriodoFallida
                        ? 'No pudimos cargar las metas del mes vigente'
                        : 'Actualizando las metas del mes vigente…'}
                    </p>
                    <p className="mt-1 text-xs text-[var(--gi-muted)]">
                      La revisión del mes anterior no se mostrará bajo el período nuevo.
                    </p>
                  </div>
                </div>
                {recargaPeriodoFallida && (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      setRecargaPeriodoFallida(false)
                      void recargar().then((ok) => {
                        if (!ok && !fotoMensualStoreVigente) setRecargaPeriodoFallida(true)
                      })
                    }}
                  >
                    <RefreshCw aria-hidden /> Reintentar
                  </Button>
                )}
              </div>
            ) : objetivosError ? (
              <div data-gi-panel role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4 sm:p-5">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
                  <div>
                    <p className="text-sm font-bold text-[var(--gi-navy)]">No pudimos cargar las metas mensuales</p>
                    <p className="mt-1 text-xs text-[var(--gi-muted)]">No se mostrará ningún objetivo hasta recuperar la revisión publicada.</p>
                  </div>
                </div>
                <Button type="button" variant="outline" size="sm" onClick={() => void recargar()}>
                  <RefreshCw aria-hidden /> Reintentar
                </Button>
              </div>
            ) : (
              <div data-gi-panel className="gi-card p-4 sm:p-5">
                <MetasEditor objetivos={objetivos} demo={modoDemo} />
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {seccion === 'rendimiento' && (
        <>
          {errorRendimiento && (
            <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4">
              <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
                <AlertTriangle className="size-4" aria-hidden /> {errorRendimiento}
              </span>
              <Button type="button" variant="outline" size="sm" onClick={() => { reintentarConversionMensual(); void qCumplimientoRanking.refetch() }}>
                <RefreshCw aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {(conversionMensualCargando || cumplimientoRankingCargando) && conversionMensualPaneles === undefined
            ? <Skeleton className="h-72 rounded-2xl" aria-label="Cargando rendimiento del equipo" />
            : conversionMensualPaneles != null || !errorRendimiento
              ? <EquipoGerenciaPanel conversionMensual={conversionMensualPaneles} conversiones={datosEquipoConversion} />
              : null}
          <div data-gi-panel>
            <DistribucionLeadsGerencia datos={datosDistribucion} cargando={estaCargando(sesionReal, distribucion)} error={errorConsulta(sesionReal, distribucion.error, 'No se pudo cargar la capacidad por analista.')} modoDemo={modoDemo} mostrarOperacion={false} mostrarPeriodo={false} desde={periodo.desde} hasta={periodo.hasta} onCambiarPeriodo={(desde, hasta) => setPeriodo({ desde, hasta })} onReintentar={reintentarDistribucion} onEditarCapacidad={async (analistaId, capacidad) => { await actualizarCapacidad.mutateAsync({ analistaId, capacidad }) }} />
          </div>
        </>
      )}

      <p className="px-1 text-[11px] text-[var(--gi-muted)]">
        {modoDemo
          ? 'Datos de ejemplo. No modifican información real.'
          // En el ranking el capital SÍ se unifica (US$ convertido al TC rotulado);
          // repetir aquí «por separado» contradiría el total (hallazgo Codex).
          : seccion === 'ranking-vendedores'
            ? `${periodoPie.desde} al ${periodoPie.hasta} · Capital total: US$ convertido a S/ al TC rotulado; desglose por moneda en cada fila.`
            : `${periodoPie.desde} al ${periodoPie.hasta} · PEN y USD se muestran por separado.`}
      </p>
    </GerenciaMotion>
  )
}
