import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { AlertTriangle, CalendarRange, RefreshCw, Target } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { Skeleton } from '@/components/ui/skeleton'
import { GerenciaMotion } from '@/components/gerencia/motion'
import { usePeriodoGerencia } from '@/components/gerencia/use-periodo-gerencia'
import {
  mensajeMetaNoComparable,
  periodoInicialGerencia,
  semanticaMetaMensual,
  validarPeriodoGerencia,
  type PeriodoGerencia,
} from '@/components/gerencia/periodo'
import { useCRMData } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { money } from '@/lib/format'
import { colorMeta, pctMeta } from '@/lib/inteligencia'
import { agregarObjetivos } from '@/lib/objetivos'
import { derivarAlertasGerencia, periodoAnteriorComparable } from '@/lib/alertas-gerencia'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import { metricasDistribucionDemo } from '@/lib/demo-metricas-distribucion'
import {
  conversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { identidadesEquipoConversion } from '@/lib/conversion-equipo'
import {
  useActualizarCapacidadLeadsObjetivo,
  useMetricasAgenda,
  useMetricasConversiones,
  useMetricasDistribucionLeads,
  useMetricasReuniones,
} from '@/data/crm-queries'
import { mensajeDeError } from '@/data/crm-api'
import { AlertasGerenciaPanel } from './alertas-gerencia'
import { DistribucionLeadsGerencia } from './distribucion-leads-gerencia'
import { EquipoGerenciaPanel } from './equipo-gerencia'
import { InteligenciaComercialPanel } from './inteligencia-comercial'
import { MetasEditor } from './metas-editor'
import { RankingVendedoresPanel } from './ranking-vendedores'
import { ReunionesGerenciaPanel } from './reuniones-gerencia'
import { ResumenGerenciaPanel } from './resumen-gerencia'

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
}

function estaCargando(sesionReal: boolean, consulta: ConsultaCargable): boolean {
  return sesionReal && (consulta.isPending || consulta.isFetching)
}

function errorConsulta(sesionReal: boolean, error: unknown, mensajeSeguro: string): string | null {
  return sesionReal && error ? mensajeDeError(error, mensajeSeguro) : null
}

function MetaItem({ label, actual, objetivo, progreso, mensajeSinProgreso }: MetaItemProps): JSX.Element {
  return (
    <div data-gi-kpi className="gi-kpi-card">
      <p className="gi-label">{label}</p>
      <div className="mt-2 flex items-baseline gap-2"><span className="text-2xl font-bold tabular-nums text-[var(--gi-blue)]">{actual}</span><span className="text-xs text-[var(--gi-muted)]">{objetivo}</span></div>
      {progreso == null ? <p className="mt-3 text-xs text-[var(--gi-muted)]">{mensajeSinProgreso ?? 'Meta del mes todavía sin fijar'}</p> : <div className="mt-3 flex items-center gap-2"><Progress value={Math.min(100, progreso)} color={colorMeta(progreso)} className="flex-1" /><span className="w-10 text-right text-xs font-bold tabular-nums" style={{ color: colorMeta(progreso) }}>{Math.round(progreso)}%</span></div>}
    </div>
  )
}

function CabeceraGerencia({ periodo, borrador, onCambiarBorrador, onAplicar }: { periodo: PeriodoGerencia; borrador: PeriodoGerencia; onCambiarBorrador: (campo: keyof PeriodoGerencia, valor: string) => void; onAplicar: () => void }): JSX.Element {
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

export type SeccionGerencia = 'completo' | 'resumen' | 'alertas' | 'conversiones' | 'ranking-vendedores' | 'reuniones' | 'metas' | 'rendimiento' | 'capital-cierres'

export function HoyGerencia({ seccion = 'completo' }: { seccion?: SeccionGerencia }): JSX.Element {
  const { ambito, equipo, objetivos, objetivosError = false, fijarObjetivos, recargar } = useCRMData()
  const { yo } = useAuth()
  const { periodo, setPeriodo, diaLima } = usePeriodoGerencia()
  const [borrador, setBorrador] = useState<PeriodoGerencia>(periodo)
  const periodoAnterior = useRef(periodo)
  const [ejemploConversiones, setEjemploConversiones] = useState(false)
  const [ejemploReuniones, setEjemploReuniones] = useState(false)
  const periodoAlertas = useMemo<PeriodoGerencia>(
    () => ({ desde: `${diaLima.slice(0, 7)}-01`, hasta: diaLima }),
    [diaLima],
  )
  const periodoAlertasAnterior = useMemo(
    () => periodoAnteriorComparable(diaLima),
    [diaLima],
  )
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
  const esAlertas = seccion === 'alertas'
  const periodoMetricas = esAlertas ? periodoAlertas : periodo
  const necesitaConversiones = ['completo', 'resumen', 'alertas', 'conversiones', 'ranking-vendedores', 'metas', 'rendimiento', 'capital-cierres'].includes(seccion)
  const necesitaReuniones = ['completo', 'resumen', 'alertas', 'reuniones', 'capital-cierres'].includes(seccion)
  const necesitaDistribucion = seccion === 'rendimiento'
  // La comparación va primero para conservar la consulta principal como la
  // última invocación del hook en pruebas y diagnósticos. Ambas claves incluyen
  // las fechas, así TanStack las mantiene separadas sin carreras.
  const conversionesAnteriores = useMetricasConversiones(
    sesionReal && esAlertas,
    periodoAlertasAnterior.desde,
    periodoAlertasAnterior.hasta,
  )
  const conversiones = useMetricasConversiones(
    sesionReal && necesitaConversiones,
    periodoMetricas.desde,
    periodoMetricas.hasta,
  )
  const reuniones = useMetricasReuniones(
    sesionReal && necesitaReuniones,
    periodoMetricas.desde,
    periodoMetricas.hasta,
  )
  const agendaAlertas = useMetricasAgenda(
    sesionReal && esAlertas,
    periodoAlertas.desde,
    periodoAlertas.hasta,
  )
  const distribucion = useMetricasDistribucionLeads(sesionReal && necesitaDistribucion, periodo.desde, periodo.hasta)
  const actualizarCapacidad = useActualizarCapacidadLeadsObjetivo()
  const meta = objetivos.gerencia
  const conversionesDeEjemplo = modoDemo || ejemploConversiones
  const reunionesDeEjemplo = modoDemo || ejemploReuniones
  const equipoConversion = useMemo(
    () => identidadesEquipoConversion(ambito.vendedores, equipo),
    [ambito.vendedores, equipo],
  )
  const datosConversion = conversionesDeEjemplo ? metricasConversionesDemo(periodoMetricas.desde, periodoMetricas.hasta) : conversiones.data
  const datosEquipoConversion = conversionesDeEjemplo ? conversionEquipoDemo() : equipoConversion
  const metasVendedoresVisuales = useMemo(
    () => conversionesDeEjemplo
      ? metasConversionEquipoDemo()
      : (objetivos.porVendedor ?? {}),
    [conversionesDeEjemplo, objetivos.porVendedor],
  )
  const metaConversionVisual = conversionesDeEjemplo
    ? agregarObjetivos(Object.values(metasVendedoresVisuales)).conversionObjetivo
    : meta.conversionObjetivo
  const metaMensualConversion = conversionesDeEjemplo
    ? semanticaMetaMensual(periodo)
    : metaMensual
  const datosReuniones = reunionesDeEjemplo ? metricasReunionesDemo(periodoMetricas.desde, periodoMetricas.hasta) : reuniones.data
  const datosAgendaAlertas = modoDemo
    ? metricasAgendaDemo(periodoAlertas.desde, periodoAlertas.hasta)
    : agendaAlertas.data
  const datosDistribucion = modoDemo ? metricasDistribucionDemo(periodo.desde, periodo.hasta) : distribucion.data
  const errorConversiones = conversionesDeEjemplo ? null : errorConsulta(sesionReal, conversiones.error, 'No se pudieron cargar las conversiones.')
  const errorReuniones = reunionesDeEjemplo ? null : errorConsulta(sesionReal, reuniones.error, 'No se pudieron cargar las métricas de reuniones.')
  const errorAgendaAlertas = errorConsulta(sesionReal, agendaAlertas.error, 'No se pudo cargar la agenda del equipo.')
  const errorComparacionAlertas = errorConsulta(sesionReal, conversionesAnteriores.error, 'No se pudo comparar la conversión con el mes anterior.')
  const errorResumen = [errorConversiones, errorReuniones].filter(Boolean).join(' ') || null
  const capitalActual = datosConversion?.produccion.capital_pen ?? null
  const conversionActual = datosConversion?.cohorte.conversion_contratos_pct ?? null
  const cargandoMetricasMetas = !conversionesDeEjemplo
    && estaCargando(sesionReal, conversiones)
    && datosConversion == null
  const alertas = useMemo(
    () => derivarAlertasGerencia({
      conversiones: datosConversion,
      conversionesAnteriores: modoDemo ? undefined : conversionesAnteriores.data,
      agenda: datosAgendaAlertas,
      reuniones: datosReuniones,
      equipoConversion: datosEquipoConversion,
      metasVendedores: metasVendedoresVisuales,
      objetivosError,
    }),
    [
      conversionesAnteriores.data,
      datosAgendaAlertas,
      datosConversion,
      datosEquipoConversion,
      datosReuniones,
      metasVendedoresVisuales,
      modoDemo,
      objetivosError,
    ],
  )

  const reintentarConversiones = () => { if (sesionReal) void conversiones.refetch() }
  const reintentarReuniones = () => { if (sesionReal) void reuniones.refetch() }
  const reintentarDistribucion = () => { if (sesionReal) void distribucion.refetch() }
  const reintentarAlertas = () => {
    if (!sesionReal) return
    void conversiones.refetch()
    void conversionesAnteriores.refetch()
    void reuniones.refetch()
    void agendaAlertas.refetch()
    if (objetivosError) void recargar()
  }
  const esResumen = seccion === 'completo' || seccion === 'resumen' || seccion === 'capital-cierres'
  const periodoMotion = esAlertas ? periodoAlertas : periodo
  const claveMotion = `${seccion}|${periodoMotion.desde}|${periodoMotion.hasta}|${conversionesDeEjemplo}|${reunionesDeEjemplo}`

  return (
    <GerenciaMotion clave={claveMotion} className="mx-auto max-w-[1640px] space-y-4">
      {!esAlertas && <CabeceraGerencia periodo={periodo} borrador={borrador} onCambiarBorrador={(campo, valor) => setBorrador((actual) => ({ ...actual, [campo]: valor }))} onAplicar={() => setPeriodo(borrador)} />}

      {esResumen && <ResumenGerenciaPanel conversiones={datosConversion} reuniones={datosReuniones} equipo={datosEquipoConversion} meta={meta} metaMensual={metaMensual} cargando={estaCargando(sesionReal, conversiones) || estaCargando(sesionReal, reuniones)} error={errorResumen} modoDemo={modoDemo} onReintentar={() => { reintentarConversiones(); reintentarReuniones() }} />}

      {esAlertas && (
        <AlertasGerenciaPanel
          alertas={alertas}
          generadoEn={datosAgendaAlertas?.generado_en ?? datosConversion?.generado_en ?? datosReuniones?.generado_en ?? null}
          cargando={!modoDemo && (
            estaCargando(sesionReal, conversiones)
            || estaCargando(sesionReal, conversionesAnteriores)
            || estaCargando(sesionReal, reuniones)
            || estaCargando(sesionReal, agendaAlertas)
          )}
          errores={[
            errorConversiones,
            errorReuniones,
            errorAgendaAlertas,
            errorComparacionAlertas,
            objetivosError ? 'No se pudieron cargar las metas individuales.' : null,
          ].filter((mensaje): mensaje is string => Boolean(mensaje))}
          onReintentar={reintentarAlertas}
          modoDemo={modoDemo}
        />
      )}

      {seccion === 'conversiones' && <InteligenciaComercialPanel datos={datosConversion} equipo={datosEquipoConversion} metaConversion={metaConversionVisual} metasVendedores={metasVendedoresVisuales} metaMensual={metaMensualConversion} cargando={!conversionesDeEjemplo && estaCargando(sesionReal, conversiones)} error={errorConversiones} modoDemo={conversionesDeEjemplo} puedeAlternarEjemplo={sesionReal} onAlternarEjemplo={() => setEjemploConversiones((actual) => !actual)} onReintentar={reintentarConversiones} />}

      {seccion === 'ranking-vendedores' && <RankingVendedoresPanel datos={datosConversion} equipo={datosEquipoConversion} metasVendedores={metasVendedoresVisuales} metaMensual={metaMensual} cargando={!conversionesDeEjemplo && estaCargando(sesionReal, conversiones)} error={errorConversiones} onReintentar={reintentarConversiones} />}

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
            {!metaMensual.comparable && !metaMensual.errorCarga && (
              <p role="status" className="rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">
                {mensajeMetaNoComparable(metaMensual)}
              </p>
            )}

            {errorConversiones && (
              <div role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4">
                <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
                  <AlertTriangle className="size-4" aria-hidden /> {errorConversiones}
                </span>
                <Button type="button" variant="outline" size="sm" onClick={reintentarConversiones}>
                  <RefreshCw aria-hidden /> Reintentar métricas
                </Button>
              </div>
            )}

            {cargandoMetricasMetas ? (
              <div className="grid gap-4 sm:grid-cols-2" aria-label="Cargando avance de metas">
                <Skeleton className="h-32 rounded-2xl" />
                <Skeleton className="h-32 rounded-2xl" />
              </div>
            ) : (
              <div className="grid gap-4 sm:grid-cols-2">
                <MetaItem
                  label="Meta en monto"
                  actual={capitalActual == null ? '—' : money(capitalActual, 'PEN')}
                  objetivo={metaMensual.errorCarga ? 'meta no disponible' : !metaMensual.comparable ? 'rango aplicado' : meta.capitalObjetivo > 0 ? `de ${money(meta.capitalObjetivo, 'PEN')}` : 'meta por definir'}
                  progreso={metaMensual.comparable && meta.capitalObjetivo > 0 && capitalActual != null ? pctMeta(capitalActual, meta.capitalObjetivo) : null}
                  mensajeSinProgreso={metaMensual.errorCarga ? 'No pudimos cargar la meta mensual' : !metaMensual.comparable ? 'Comparación no disponible para este rango' : meta.capitalObjetivo <= 0 ? undefined : capitalActual == null ? 'Monto alcanzado no disponible' : undefined}
                />
                <MetaItem
                  label="Meta de conversión"
                  actual={conversionActual == null ? '—' : `${conversionActual}%`}
                  objetivo={metaMensual.errorCarga ? 'meta no disponible' : !metaMensual.comparable ? 'rango aplicado' : meta.conversionObjetivo > 0 ? `de ${meta.conversionObjetivo}%` : 'meta por definir'}
                  progreso={metaMensual.comparable && meta.conversionObjetivo > 0 && conversionActual != null ? pctMeta(conversionActual, meta.conversionObjetivo) : null}
                  mensajeSinProgreso={metaMensual.errorCarga ? 'No pudimos cargar la meta mensual' : !metaMensual.comparable ? 'Comparación no disponible para este rango' : meta.conversionObjetivo <= 0 ? undefined : datosConversion == null ? 'Conversión alcanzada no disponible' : conversionActual == null ? 'Todavía no hay clientes para medir' : undefined}
                />
              </div>
            )}

            {objetivosError ? (
              <div data-gi-panel role="alert" className="gi-card flex flex-wrap items-center justify-between gap-3 border border-destructive/25 p-4 sm:p-5">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
                  <div>
                    <p className="text-sm font-bold text-[var(--gi-navy)]">No pudimos cargar las metas mensuales</p>
                    <p className="mt-1 text-xs text-[var(--gi-muted)]">No se mostrará ni guardará ningún objetivo hasta recuperar los datos.</p>
                  </div>
                </div>
                <Button type="button" variant="outline" size="sm" onClick={() => void recargar()}>
                  <RefreshCw aria-hidden /> Reintentar
                </Button>
              </div>
            ) : (
              <div data-gi-panel className="gi-card p-4 sm:p-5">
                <MetasEditor objetivos={objetivos} equipo={equipo} demo={modoDemo} onGuardar={fijarObjetivos} />
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
              ? <EquipoGerenciaPanel datos={datosConversion} conversiones={datosEquipoConversion} miembros={equipo} />
              : null}
          <div data-gi-panel>
            <DistribucionLeadsGerencia datos={datosDistribucion} cargando={estaCargando(sesionReal, distribucion)} error={errorConsulta(sesionReal, distribucion.error, 'No se pudo cargar la capacidad por analista.')} modoDemo={modoDemo} mostrarOperacion={false} mostrarPeriodo={false} desde={periodo.desde} hasta={periodo.hasta} onCambiarPeriodo={(desde, hasta) => setPeriodo({ desde, hasta })} onReintentar={reintentarDistribucion} onEditarCapacidad={async (analistaId, capacidad) => { await actualizarCapacidad.mutateAsync({ analistaId, capacidad }) }} />
          </div>
        </>
      )}

      <p className="px-1 text-[11px] text-[var(--gi-muted)]">
        {modoDemo
          ? 'Datos de ejemplo. No modifican información real.'
          : esAlertas
            ? `Estado actual al ${periodoAlertas.hasta} · métricas agregadas sin descargar datos sensibles.`
            : `${periodo.desde} al ${periodo.hasta} · PEN y USD se muestran por separado.`}
      </p>
    </GerenciaMotion>
  )
}
