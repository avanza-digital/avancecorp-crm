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
  semanticaMetaMensual,
  validarPeriodoGerencia,
  type PeriodoGerencia,
} from '@/components/gerencia/periodo'
import { useCRMData } from '@/lib/store-context'
import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
import { useAuth } from '@/lib/auth-context'
import { money, moneyK, porcentajeConversionCanonica } from '@/lib/format'
import { colorMeta, pctMeta } from '@/lib/inteligencia'
import {
  agregarObjetivos,
  capitalObjetivo,
  metaVigente,
  capitalReal,
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
  isFetching: boolean
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
  return sesionReal && (consulta.isPending || consulta.isFetching)
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

function CabeceraGerencia({ periodo, borrador, onCambiarBorrador, onAplicar, origen, onCambiarOrigen, origenDeshabilitado }: { periodo: PeriodoGerencia; borrador: PeriodoGerencia; onCambiarBorrador: (campo: keyof PeriodoGerencia, valor: string) => void; onAplicar: () => void; origen: string | null; onCambiarOrigen: (origen: string | null) => void; origenDeshabilitado: boolean }): JSX.Element {
  const validacion = validarPeriodoGerencia(borrador)
  const sinCambios = borrador.desde === periodo.desde && borrador.hasta === periodo.hasta
  const hoyLima = periodoInicialGerencia().hasta
  const maximoDesde = borrador.hasta && borrador.hasta < hoyLima ? borrador.hasta : hoyLima
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
        </div>
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
    cumplimientoMetasError,
    recargar,
  } = useCRMData()
  const { yo } = useAuth()
  // TC USD→PEN del servidor (edge crm-tipo-cambio · BCRP): lo consume SOLO el
  // ranking de capital total — en las demás secciones ni se consulta (hallazgo
  // de la verificación: cada cambio de vista remonta la pantalla).
  const tipoCambio = useTipoCambio(
    seccion === 'ranking-vendedores' || seccion === 'metas'
    || seccion === 'completo' || seccion === 'resumen',
  )
  const { periodo, setPeriodo, diaLima, origenFiltrado, setOrigenFiltrado } = usePeriodoGerencia()
  const [borrador, setBorrador] = useState<PeriodoGerencia>(periodo)
  const periodoAnterior = useRef(periodo)
  const [ejemploConversiones, setEjemploConversiones] = useState(false)
  const [ejemploReuniones, setEjemploReuniones] = useState(false)
  const metaMensual = useMemo(() => {
    const semantica = semanticaMetaMensual(periodo, Date.parse(`${diaLima}T12:00:00Z`))
    return objetivosError
      ? { ...semantica, comparable: false, errorCarga: true }
      : semantica
  }, [diaLima, objetivosError, periodo])
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
  const necesitaConversiones = ['completo', 'resumen', 'conversiones', 'ranking-vendedores', 'metas', 'rendimiento'].includes(seccion)
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
  // Meta y producción del MISMO snapshot: ver `metaVigente`.
  const meta = metaVigente(objetivos.gerencia, cumplimientoMetas?.gerencia ?? null)
  const cumplimiento = cumplimientoMetas?.gerencia ?? null
  // LA CONVERSIÓN DEL MES de la empresa (crm.conversion_mensual_fn). La RPC es
  // MENSUAL por contrato y este panel se gobierna con un rango LIBRE: se pide
  // el mes de la FECHA FINAL del rango (decisión E2, plan §4bis) — mismo
  // criterio que ya usa el aviso del panel de metas.
  const periodoConversionMes = `${periodoMetricas.hasta.slice(0, 7)}-01`
  const qConversionMensual = useConversionMensual(sesionReal && necesitaConversiones, periodoConversionMes)
  // Cosecha por vendedor del ranking (F2.2/D2): mismo MES que la mensual del
  // tab — del 01 al final del rango elegido — para que las dos lecturas de una
  // fila hablen del mismo período. Solo se consulta en la sección que la pinta.
  const qCosechaRanking = useMetricasConversionesEquipo(
    sesionReal && seccion === 'ranking-vendedores',
    periodoConversionMes,
    periodoMetricas.hasta,
  )
  const cosechaRanking = seccion !== 'ranking-vendedores' || modoDemo
    ? undefined
    : qCosechaRanking.isPending || qCosechaRanking.isFetching
      ? undefined
      : (qCosechaRanking.data ?? null)
  const conversionesDeEjemplo = modoDemo || ejemploConversiones
  const reunionesDeEjemplo = modoDemo || ejemploReuniones
  // El mundo demo de gerencia es `demo-v*` (el de inteligencia comercial): el
  // tile héroe y los paneles de la familia beben del MISMO payload derivado —
  // un total en el héroe y otro en el ranking sería la demo enseñando dos
  // negocios distintos.
  const conversionMensualDemoIntel = useMemo(
    () => (conversionesDeEjemplo ? conversionMensualInteligenciaDemo(Date.now()) : null),
    [conversionesDeEjemplo],
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
    : estaCargando(sesionReal, qConversionMensual)
      ? undefined
      : (qConversionMensual.data ?? null)
  const equipoConversion = useMemo(
    () => identidadesEquipoConversion(ambito.vendedores, equipo),
    [ambito.vendedores, equipo],
  )
  // Nombres del roster completo para la traza de compromisos (F4.4).
  const nombresEquipo = useMemo(
    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
    [equipo],
  )
  const datosConversion = conversionesDeEjemplo ? metricasConversionesDemo(periodoMetricas.desde, periodoMetricas.hasta) : conversiones.data
  const datosEquipoConversion = conversionesDeEjemplo ? conversionEquipoDemo() : equipoConversion
  const metasVendedoresVisuales = useMemo(
    () => conversionesDeEjemplo
      ? metasConversionEquipoDemo()
      : (objetivos.porVendedor ?? {}),
    [conversionesDeEjemplo, objetivos.porVendedor],
  )
  const cumplimientoVisual = useMemo(
    () => conversionesDeEjemplo ? cumplimientoMetasConversionEquipoDemo() : cumplimientoMetas,
    [conversionesDeEjemplo, cumplimientoMetas],
  )
  const metaConversionVisual = conversionesDeEjemplo
    ? agregarObjetivos(Object.values(metasVendedoresVisuales)).conversionObjetivo
    : meta.conversionObjetivo
  const metaMensualConversion = conversionesDeEjemplo
    ? semanticaMetaMensual(periodo)
    : metaMensual
  const datosReuniones = reunionesDeEjemplo ? metricasReunionesDemo(periodoMetricas.desde, periodoMetricas.hasta) : reuniones.data
  const datosDistribucion = modoDemo ? metricasDistribucionDemo(periodo.desde, periodo.hasta) : distribucion.data
  const errorConversiones = conversionesDeEjemplo ? null : errorConsulta(sesionReal, conversiones.error, 'No se pudieron cargar las conversiones.')
  // La MENSUAL es LA fuente del tab de conversión del ranking: si falla, el
  // panel lo dice con Reintentar — no degrada mudo a «indisponible» (exigencia
  // pre-release de Miguel, 2026-08-15).
  const errorConversionMensual = conversionesDeEjemplo
    ? null
    : errorConsulta(sesionReal, qConversionMensual.error, 'No se pudo calcular la conversión mensual.')
  const errorReuniones = reunionesDeEjemplo ? null : errorConsulta(sesionReal, reuniones.error, 'No se pudieron cargar las métricas de citas.')
  // La MENSUAL también alimenta al Resumen (su bloque de conversión): su fallo
  // es un error del panel, con reintento — la tercera pantalla del mismo hueco
  // (inteligencia y ranking ya lo tenían cerrado).
  const errorResumen = [errorConversiones, errorConversionMensual, errorReuniones].filter(Boolean).join(' ') || null
  const capitalActualPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalActualUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  // PEN y USD no se suman a ciegas: se convierte a tasa real y se rotula cuál
  // se aplicó. Mismo criterio que el panel del asesor (decisión #10).
  const tcPromedio = tipoCambio.tc?.promedio ?? null
  const capitalTotal = totalEnSoles(capitalActualPen, capitalActualUsd, tcPromedio)
  const metaTotalCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tcPromedio)
  // Sin dólares el tipo de cambio es irrelevante y no debe degradar nada; con
  // dólares y el TC en vuelo, no se puede afirmar todavía ni el total ni el %.
  const hayDolares = (capitalActualUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tipoCambio.tc === undefined && hayDolares
  const tcCaido = tipoCambio.tc === null && hayDolares
  const totalConversion = totalConversionPublicable(conversionMensual)
  const conversionActual = totalConversion?.conversion_pct ?? null
  const reintentarConversiones = () => { if (sesionReal) void conversiones.refetch() }
  const reintentarConversionMensual = () => { if (sesionReal) void qConversionMensual.refetch() }
  const reintentarReuniones = () => { if (sesionReal) void reuniones.refetch() }
  const reintentarDistribucion = () => { if (sesionReal) void distribucion.refetch() }
  const esResumen = seccion === 'completo' || seccion === 'resumen'
  const claveMotion = `${seccion}|${periodo.desde}|${periodo.hasta}|${conversionesDeEjemplo}|${reunionesDeEjemplo}`

  return (
    <GerenciaMotion clave={claveMotion} className="mx-auto max-w-[1640px] space-y-4">
      <CabeceraGerencia periodo={periodo} borrador={borrador} onCambiarBorrador={(campo, valor) => setBorrador((actual) => ({ ...actual, [campo]: valor }))} onAplicar={() => setPeriodo(borrador)} origen={origenFiltrado} onCambiarOrigen={setOrigenFiltrado} origenDeshabilitado={modoDemo} />

      {/* El aviso del ciclo del cierre de mes, en TODAS las secciones: la
          alarma de un ciclo atascado no puede depender de qué pestaña se mire.
          Solo en sesión real — el estado habla de la maquinaria de verdad. */}
      {sesionReal && <AvisoCierreMesPanel />}

      {esResumen && <ResumenGerenciaPanel conversiones={datosConversion} conversionMensual={conversionMensualPaneles} origenFiltrado={modoDemo ? null : origenActivo} reuniones={datosReuniones} equipo={datosEquipoConversion} meta={meta} cumplimiento={cumplimiento} metaMensual={metaMensual} tc={tipoCambio.tc} cargando={estaCargando(sesionReal, conversiones) || estaCargando(sesionReal, reuniones)} error={errorResumen} modoDemo={modoDemo} onReintentar={() => { reintentarConversiones(); reintentarConversionMensual(); reintentarReuniones() }} />}

      {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC), por vendedor.
          Se oculta solo si el mes no tiene cierres en cooperativas. */}
      {esResumen && (
        <DesglosePorEmpresa demo={modoDemo} porVendedor={cumplimientoMetas?.porVendedor ?? null} />
      )}

      {/* F4.4: la trazabilidad de los reconocimientos — qué alertas atenuaron
          o pospusieron los supervisores y hasta cuándo rigen. Lectura pura. */}
      {esResumen && (
        <CompromisosSupervisoresPanel demo={modoDemo} nombrePorId={nombresEquipo} />
      )}

      {seccion === 'conversiones' && <InteligenciaComercialPanel datos={datosConversion} conversionMensual={conversionMensualPaneles} cumplimiento={cumplimientoVisual?.gerencia ?? null} origenFiltrado={conversionesDeEjemplo ? null : origenActivo} equipo={datosEquipoConversion} metaConversion={metaConversionVisual} metasVendedores={metasVendedoresVisuales} cumplimientoVendedores={cumplimientoVisual?.porVendedor ?? {}} metaMensual={metaMensualConversion} cargando={!conversionesDeEjemplo && estaCargando(sesionReal, conversiones)} error={errorConversiones ?? errorConversionMensual} modoDemo={conversionesDeEjemplo} puedeAlternarEjemplo={sesionReal} onAlternarEjemplo={() => setEjemploConversiones((actual) => !actual)} onReintentar={() => { reintentarConversiones(); reintentarConversionMensual() }} />}

      {seccion === 'ranking-vendedores' && <RankingVendedoresPanel datos={datosConversion} conversionMensual={conversionMensualPaneles} cosecha={cosechaRanking} equipo={datosEquipoConversion} metasVendedores={metasVendedoresVisuales} cumplimientoVendedores={cumplimientoVisual?.porVendedor ?? {}} metaMensual={metaMensual} tc={tipoCambio.tc} cargando={!conversionesDeEjemplo && estaCargando(sesionReal, conversiones)} error={errorConversiones ?? errorConversionMensual} onReintentar={() => { reintentarConversiones(); reintentarConversionMensual(); tipoCambio.recargar() }} />}

      {seccion === 'reuniones' && <ReunionesGerenciaPanel datos={datosReuniones} cargando={!reunionesDeEjemplo && estaCargando(sesionReal, reuniones)} error={errorReuniones} modoDemo={reunionesDeEjemplo} puedeAlternarEjemplo={sesionReal} onAlternarEjemplo={() => setEjemploReuniones((actual) => !actual)} onReintentar={reintentarReuniones} />}

      {seccion === 'metas' && (
        <Card className="gi-card overflow-hidden border-0 shadow-none">
          <div className="flex items-center gap-2 border-b border-[var(--gi-line)] bg-white px-5 py-4">
            <Target className="size-4 text-[var(--gi-blue)]" />
            <div>
              <h2 className="gi-title">Metas mensuales</h2>
              <p className="gi-caption mt-0.5">Meta mensual · {metaMensual.etiqueta}</p>
            </div>
          </div>
          <CardContent className="space-y-5 bg-[var(--gi-canvas)] p-4 sm:p-5">
            {/* Las metas son MENSUALES y estas tarjetas SIEMPRE miden el mes en
                curso: el selector de rango de arriba no las toca. Antes se
                desactivaba la comparación y se rotulaba «rango aplicado», pero
                el importe que quedaba en pantalla seguía siendo el del mes —
                una cifra mensual con etiqueta de rango. */}
            {!metaMensual.comparable && !metaMensual.errorCarga && (
              <p role="status" className="rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">
                Estas cifras son del mes en curso ({metaMensual.etiqueta}), no del rango que elegiste arriba: las metas se pactan por mes.
              </p>
            )}

            {cumplimientoMetasError && (
              <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4">
                <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
                  <AlertTriangle className="size-4" aria-hidden /> No se pudo calcular el cumplimiento confirmado de las metas.
                </span>
                <Button type="button" variant="outline" size="sm" onClick={() => void recargar()}>
                  <RefreshCw aria-hidden /> Reintentar cumplimiento
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

            <div className="grid gap-4 sm:grid-cols-2">
                <MetaItem
                  label="Capital confirmado del mes"
                  actual={capitalTotal.total == null ? '—' : money(capitalTotal.total, 'PEN')}
                  objetivo={metaMensual.errorCarga
                    ? 'meta no disponible'
                    : (metaTotalCapital.total ?? 0) > 0
                        ? `de ${money(metaTotalCapital.total ?? 0, 'PEN')}`
                        : 'meta por definir'}
                  nota={<DesgloseMonedas capital={capitalTotal} fuenteTc={tipoCambio.tc?.fuente ?? null} />}
                  progreso={!tcEnVuelo && (metaTotalCapital.total ?? 0) > 0 && capitalTotal.total != null
                    ? pctMeta(capitalTotal.total, metaTotalCapital.total ?? 0)
                    : null}
                  mensajeSinProgreso={metaMensual.errorCarga
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
                  objetivo={metaMensual.errorCarga
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
                    : metaMensual.errorCarga
                        ? 'No pudimos cargar la meta mensual'
                        : meta.conversionObjetivo <= 0
                            ? undefined
                            : conversionActual == null
                                ? 'Todavía no hay leads recibidos este mes'
                                : undefined}
                />
            </div>

            {objetivosError ? (
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
          {errorConversiones && (
            <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4">
              <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
                <AlertTriangle className="size-4" aria-hidden /> {errorConversiones}
              </span>
              <Button type="button" variant="outline" size="sm" onClick={reintentarConversiones}>
                <RefreshCw aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {estaCargando(sesionReal, conversiones) && !datosConversion
            ? <Skeleton className="h-72 rounded-2xl" aria-label="Cargando rendimiento del equipo" />
            : datosConversion || !errorConversiones
              ? <EquipoGerenciaPanel conversionMensual={conversionMensualPaneles} conversiones={datosEquipoConversion} miembros={equipo} />
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
            ? `${periodo.desde} al ${periodo.hasta} · Capital total: US$ convertido a S/ al TC rotulado; desglose por moneda en cada fila.`
            : `${periodo.desde} al ${periodo.hasta} · PEN y USD se muestran por separado.`}
      </p>
    </GerenciaMotion>
  )
}
