import { useMemo, type JSX, type ReactNode } from 'react'
import type { EChartsOption } from 'echarts'
import {
  AlertTriangle,
  CalendarCheck,
  ChevronRight,
  RefreshCw,
  Target,
  TrendingUp,
  UserRoundCheck,
  WalletCards,
  type LucideIcon,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import {
  mensajeMetaNoComparable,
  type MetaMensualGerencia,
} from '@/components/gerencia/periodo'
import { money, numero } from '@/lib/format'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import {
  capitalObjetivo,
  capitalReal,
  metaConversionAplicable,
  type CumplimientoComercial,
  type ObjetivoComercial,
} from '@/lib/objetivos'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import type { ConversionMensual } from '@/lib/conversion-mensual'
import {
  adaptarConversionMensual,
  adaptarConversionVendedores,
  clasificarRankingConversion,
} from '@/lib/conversion-vendedores'
import type { MetricasConversiones } from '@/lib/metricas-conversiones'
import type { MetricasReuniones } from '@/lib/metricas-reuniones'

interface ResumenGerenciaPanelProps {
  conversiones: MetricasConversiones | null | undefined
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`): alimenta el
   * héroe, el KPI de conversión y «Mejores vendedores». Tri-estado: `undefined`
   * consultando · `null` no disponible (todo degrada a «—», jamás a la fórmula
   * del rango). La evolución semanal y los orígenes siguen midiendo el RANGO.
   */
  conversionMensual: ConversionMensual | null | undefined
  reuniones: MetricasReuniones | null | undefined
  equipo: ConversionEquipoVendedor[]
  meta: ObjetivoComercial
  cumplimiento: CumplimientoComercial | null
  metaMensual: MetaMensualGerencia
  tc: { promedio: number, fuente: string } | null | undefined
  cargando: boolean
  error: string | null
  modoDemo: boolean
  onReintentar: () => void
}

function pct(valor: number | null): string {
  return valor == null ? '—' : `${numero(valor, 1)}%`
}

function numeroDisponible(valor: number | null): string {
  return valor == null ? '—' : numero(valor)
}

function moneyDisponible(valor: number | null, moneda: 'PEN' | 'USD'): string {
  return valor == null ? '—' : money(valor, moneda)
}

function limitar(valor: number): number {
  return Math.min(100, Math.max(0, valor))
}

function etiquetaSemana({ desde, hasta }: { desde: string; hasta: string }): string {
  return desde === hasta ? desde : `${desde} – ${hasta}`
}

function Kpi({
  label,
  valor,
  detalle,
  Icon,
  color,
}: {
  label: string
  valor: string
  detalle: ReactNode
  Icon: LucideIcon
  color: string
}): JSX.Element {
  return (
    <div data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as React.CSSProperties}>
      <div className="flex items-center justify-between gap-2">
        <p className="gi-label">{label}</p>
        <Icon className="size-4" style={{ color }} aria-hidden />
      </div>
      <p className="mt-2 text-[2rem] font-bold leading-none tracking-[-0.035em] tabular-nums text-[var(--gi-ink)]">
        {valor}
      </p>
      <div className="mt-2 text-xs text-[var(--gi-muted)]">{detalle}</div>
    </div>
  )
}

function ErrorResumen({ error, onReintentar }: { error: string; onReintentar: () => void }): JSX.Element {
  return (
    <div className="gi-card flex flex-wrap items-center justify-between gap-3 p-5" role="alert">
      <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
        <AlertTriangle className="size-4" /> {error}
      </span>
      <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
        <RefreshCw /> Reintentar
      </Button>
    </div>
  )
}

export function ResumenGerenciaPanel({
  conversiones,
  conversionMensual,
  reuniones,
  equipo,
  meta,
  cumplimiento,
  metaMensual,
  tc,
  cargando,
  error,
  modoDemo,
  onReintentar,
}: ResumenGerenciaPanelProps): JSX.Element {
  const clientes = conversiones?.cohorte.contratos ?? null
  const leads = conversiones?.cohorte.leads ?? null
  // El número grande del resumen es LA conversión del MES (servida, jamás
  // dividida aquí); «medible: false» del servidor degrada a «—» con rótulo.
  const totalMes = conversionMensual != null && conversionMensual.cobertura.medible
    ? conversionMensual.total
    : null
  const conversionMes = totalMes?.conversion_pct ?? null
  const recibidosMes = totalMes?.divisor ?? null
  const cierresMes = totalMes == null ? null : totalMes.cierres_no_referidos + totalMes.cierres_referidos
  const capitalPen = conversiones?.produccion.capital_pen ?? null
  const capitalUsd = conversiones?.produccion.capital_usd ?? null
  const reunionesRealizadas = reuniones?.resumen.realizadas ?? null
  const reunionesPactadas = reuniones?.resumen.pactadas ?? null
  const metasComparables = metaMensual.comparable && metaMensual.errorCarga !== true
  const metaConversion = metaConversionAplicable(
    meta.conversionObjetivo,
    metaMensual.errorCarga === true,
  )
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  const cumplimientoCapitalPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const cumplimientoCapitalUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  // Capital CONSOLIDADO, no dos barras: la meta se pacta en soles, así que la
  // barra de dólares no podía tener meta y decía «Sin meta» para siempre
  // mientras el capital real en USD no contaba para nada.
  const capitalTotal = totalEnSoles(cumplimientoCapitalPen, cumplimientoCapitalUsd, tc?.promedio)
  const metaTotalCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
  const hayDolares = (cumplimientoCapitalUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tc === undefined && hayDolares
  const avanceCapital = metasComparables && !tcEnVuelo
    && (metaTotalCapital.total ?? 0) > 0 && capitalTotal.total != null
    ? limitar((capitalTotal.total / (metaTotalCapital.total ?? 1)) * 100)
    : null
  // La barra avanza con EL MISMO número que el titular: la conversión del mes
  // servida. Hasta 2026-08-13 medía `cumplimiento.conversionReal`, que es otra
  // fórmula (convertidos/RESUELTOS, sin ponderar referidos ni arrastre): la
  // pantalla enseñaba un porcentaje arriba y avanzaba la meta con otro, y los
  // dos se llamaban «conversión». Un solo número bajo un solo nombre. Si el mes
  // no es medible no hay barra, que es más honesto que una barra de mentira.
  const avanceConversion = metasComparables && metaConversion != null && conversionMes != null
    ? limitar((conversionMes / metaConversion) * 100)
    : null

  const vendedoresAdaptados = useMemo(
    () => adaptarConversionVendedores(conversiones, equipo),
    [conversiones, equipo],
  )
  const tendenciaEquipo = vendedoresAdaptados.tendenciaSemanal
  const valoresEvolucion = useMemo(
    () => (tendenciaEquipo ?? []).map((punto) => punto.conversion_pct),
    [tendenciaEquipo],
  )
  const etiquetas = useMemo(
    () => (tendenciaEquipo ?? []).map(etiquetaSemana),
    [tendenciaEquipo],
  )
  const opcionEvolucion = useMemo<EChartsOption>(() => ({
    color: [C.blue, C.amber],
    animationDuration: 650,
    grid: { left: 42, right: 18, top: 38, bottom: 30 },
    tooltip: { trigger: 'axis' },
    legend: {
      top: 0,
      right: 0,
      itemWidth: 14,
      itemHeight: 8,
      textStyle: { color: C.muted, fontFamily: 'IBM Plex Sans', fontSize: 11 },
    },
    xAxis: {
      type: 'category',
      data: etiquetas,
      boundaryGap: false,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: C.grid } },
      axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans', fontSize: 11 },
    },
    yAxis: {
      type: 'value',
      min: 0,
      axisTick: { show: false },
      axisLine: { show: false },
      splitLine: { lineStyle: { color: C.grid } },
      axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' },
    },
    series: metasComparables && metaConversion != null
      ? [
          {
            name: 'Conversión real',
            type: 'line',
            smooth: true,
            data: valoresEvolucion,
            symbolSize: 7,
            lineStyle: { width: 2.5 },
            areaStyle: { color: 'rgba(31,78,121,.12)' },
          },
          {
            name: 'Meta',
            type: 'line',
            symbol: 'none',
            data: etiquetas.map(() => metaConversion),
            lineStyle: { type: 'dashed', width: 1.5 },
          },
        ]
      : [{ name: 'Conversión real', type: 'line', smooth: true, data: valoresEvolucion, symbolSize: 7, lineStyle: { width: 2.5 }, areaStyle: { color: 'rgba(31,78,121,.12)' } }],
  }), [etiquetas, metaConversion, metasComparables, valoresEvolucion])

  const adaptadaMensual = useMemo(
    () => adaptarConversionMensual(conversionMensual ?? null, equipo),
    [conversionMensual, equipo],
  )
  const rankingMes = useMemo(
    () => clasificarRankingConversion(adaptadaMensual.vendedores),
    [adaptadaMensual.vendedores],
  )
  // Top 5 MEDIBLES del mes (solo_arrastre compite en el ranking pero sin %,
  // y una lista de «mejores» sin número no ordena nada).
  const mejores = rankingMes.conPuesto.filter((fila) => fila.detalle.conversion_pct != null).slice(0, 5)
  const maxMejor = Math.max(1, ...mejores.map((fila) => fila.detalle.conversion_pct ?? 0))
  const origenes = [...(conversiones?.origenes ?? [])]
    .sort((a, b) => (b.conversion_contratos_pct ?? -1) - (a.conversion_contratos_pct ?? -1))
    .slice(0, 5)
  const maxOrigen = Math.max(1, ...origenes.map((fila) => fila.conversion_contratos_pct ?? 0))
  const hayActividadConversiones = [
    conversiones?.cohorte.leads,
    conversiones?.cohorte.asignados,
    conversiones?.cohorte.contactados,
    conversiones?.cohorte.reuniones_agendadas,
    conversiones?.cohorte.reuniones_realizadas,
    conversiones?.cohorte.propuestas,
    conversiones?.cohorte.clientes,
    conversiones?.cohorte.contratos,
    conversiones?.cohorte.descartados,
    conversiones?.produccion.clientes,
    conversiones?.produccion.contratos,
    conversiones?.produccion.capital_pen,
    conversiones?.produccion.capital_usd,
  ].some((valor) => (valor ?? 0) > 0)
  const hayActividadReuniones = [
    reuniones?.resumen.pactadas,
    reuniones?.resumen.debieron_ocurrir,
    reuniones?.resumen.realizadas,
    reuniones?.resumen.no_concretadas,
    reuniones?.resumen.no_show,
    reuniones?.resumen.canceladas,
    reuniones?.resumen.canceladas_sistema,
    reuniones?.resumen.reprogramadas,
    reuniones?.resumen.pendientes_cierre,
    reuniones?.resumen.programadas_futuras,
    reuniones?.conversion.leads_reunidos,
    reuniones?.conversion.clientes,
    reuniones?.conversion.contratos,
    reuniones?.conversion.capital_pen,
    reuniones?.conversion.capital_usd,
  ].some((valor) => (valor ?? 0) > 0)
  const hayMetas = metaCapitalPen > 0
    || metaCapitalUsd > 0
    || meta.conversionObjetivo > 0
  const hayActividadEquipo = vendedoresAdaptados.vendedores.some((fila) => fila.detalle != null && [
    fila.detalle.leads,
    fila.detalle.contactados,
    fila.detalle.reuniones_realizadas,
    fila.detalle.clientes,
    fila.detalle.capital_pen,
    fila.detalle.capital_usd,
  ].some((valor) => valor > 0))
  const hayContenidoResumen = hayActividadConversiones
    || hayActividadReuniones
    || hayMetas
    || hayActividadEquipo
    || (conversionMensual?.total.divisor ?? 0) > 0
    || (conversionMensual?.total.numerador ?? 0) > 0
    || metaMensual.errorCarga === true

  if (cargando && !conversiones && !reuniones) {
    return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="h-32 rounded-2xl" />)}</div>
  }
  if (!hayContenidoResumen) {
    if (error) return <ErrorResumen error={error} onReintentar={onReintentar} />
    return <div className="gi-card py-14 text-center"><Target className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">Aún no hay actividad comercial en este período</p></div>
  }

  return (
    <div className="space-y-4">
      {error && <ErrorResumen error={error} onReintentar={onReintentar} />}
      <section data-gi-hero className="gi-summary-hero">
        <div>
          <p className="gi-label text-white/65">Conversión del mes</p>
          <p className="mt-2 text-5xl font-bold tracking-[-0.045em] tabular-nums text-white sm:text-6xl">{pct(conversionMes)}</p>
          <p className="mt-2 text-xs text-white/65">
            {conversionMensual != null && !conversionMensual.cobertura.medible
              ? 'Sin datos de asignación para este mes'
              : totalMes == null
                ? 'Conversión del mes no disponible'
                : `${numero(cierresMes ?? 0)} cierres de ${numero(recibidosMes ?? 0)} recibidos este mes`}
          </p>
        </div>
        <div className="grid flex-1 gap-3 sm:grid-cols-3">
          <div className="gi-hero-metric"><span>Capital</span><strong>{moneyDisponible(capitalPen, 'PEN')}</strong></div>
          <div className="gi-hero-metric"><span>Reuniones</span><strong>{numeroDisponible(reunionesRealizadas)}</strong></div>
          <div className="gi-hero-metric">
            <span>Meta mensual · {metaMensual.etiqueta}</span>
            <strong>
              {metaMensual.errorCarga
                ? 'No disponible'
                : metasComparables && metaConversion != null
                  ? `${numero(metaConversion, 1)}%`
                  : metasComparables
                    ? 'Sin meta'
                    : 'No comparable'}
            </strong>
          </div>
        </div>
        {modoDemo && <span className="gi-demo-badge">Datos de ejemplo</span>}
      </section>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi label="Conversión del mes" valor={pct(conversionMes)} detalle={cierresMes == null ? 'Dato no disponible' : `${numero(cierresMes)} cierres`} Icon={TrendingUp} color={C.blue} />
        <Kpi label="Clientes que invirtieron" valor={numeroDisponible(clientes)} detalle={`de ${numeroDisponible(leads)} leads`} Icon={UserRoundCheck} color={C.green} />
        <Kpi label="Capital invertido" valor={moneyDisponible(capitalPen, 'PEN')} detalle={capitalUsd == null || capitalPen == null ? 'Dato no disponible' : capitalUsd > 0 ? money(capitalUsd, 'USD') : capitalPen > 0 ? 'Todo en soles' : 'Sin capital confirmado'} Icon={WalletCards} color={C.teal} />
        <Kpi label="Reuniones realizadas" valor={numeroDisponible(reunionesRealizadas)} detalle={reunionesPactadas == null ? cargando ? 'Cargando reuniones…' : 'Dato no disponible' : `${numero(reunionesPactadas)} pactadas`} Icon={CalendarCheck} color={C.amber} />
      </div>

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1.35fr)_minmax(330px,.8fr)]">
        <section data-gi-panel className="gi-card p-5">
          <div className="flex items-center justify-between gap-3"><h2 className="gi-title">Evolución de la conversión</h2><span className="gi-caption">{metasComparables ? `Semanal vs. meta mensual · ${metaMensual.etiqueta}` : 'Semanas del rango aplicado'}</span></div>
          {!metasComparables && <p className="mt-2 text-xs font-medium text-[var(--gi-muted)]">{mensajeMetaNoComparable(metaMensual)}</p>}
          {tendenciaEquipo == null
            ? <div className="mt-3 grid h-[260px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] px-4 text-center text-xs font-medium text-[var(--gi-muted)]">Tendencia no disponible</div>
            : valoresEvolucion.length > 0
              ? <GerenciaEChart tipo="lineas" option={opcionEvolucion} ariaLabel="Evolución semanal de la conversión a clientes en el rango aplicado" className="mt-3 h-[260px] w-full" />
              : <div className="mt-3 grid h-[260px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] px-4 text-center text-xs font-medium text-[var(--gi-muted)]">Aún no hay conversiones para mostrar</div>}
        </section>
        <section
          data-gi-panel
          className="gi-card group relative cursor-pointer p-5 transition-[transform,box-shadow,border-color] duration-200 hover:-translate-y-0.5 hover:border-[var(--gi-blue)]/30 hover:shadow-[0_16px_38px_rgba(17,30,61,.10)] focus-within:ring-[3px] focus-within:ring-ring/35 motion-reduce:transform-none motion-reduce:transition-none"
        >
          <div className="flex items-center justify-between gap-3">
            <h2 className="gi-title">Mejores vendedores</h2>
            <a
              href="#/ranking-vendedores"
              aria-label="Ver ranking general de vendedores"
              className="after:absolute after:inset-0 after:content-[''] flex items-center gap-1 text-[11px] font-bold text-[var(--gi-blue)] outline-none"
            >
              Ver ranking
              <ChevronRight className="size-3.5 transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none" aria-hidden />
            </a>
          </div>
          <div className="mt-5 space-y-4">
            {mejores.length > 0
              ? mejores.map((fila, indice) => (
                  <div key={fila.vendedorId}>
                    <div className="mb-1.5 flex justify-between gap-3 text-xs"><span className="font-medium">{fila.nombre}</span><strong className="tabular-nums">{pct(fila.detalle.conversion_pct)}</strong></div>
                    <div className="gi-track"><div className="gi-fill motion-reduce:transition-none" style={{ width: `${((fila.detalle.conversion_pct ?? 0) / maxMejor) * 100}%`, background: indice < 3 ? C.green : indice === 3 ? C.amber : C.red }} /></div>
                  </div>
                ))
              : <p className="rounded-xl border border-dashed border-[var(--gi-line)] px-4 py-8 text-center text-xs font-medium text-[var(--gi-muted)]">{adaptadaMensual.responsablesDisponibles ? 'Aún no hay vendedores medibles este mes' : 'Detalle por vendedor no disponible'}</p>}
          </div>
        </section>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <section data-gi-panel className="gi-card p-5 lg:col-span-2">
          <h2 className="gi-title">Conversión por origen</h2>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            {origenes.length > 0
              ? origenes.map((fila) => (
                  <div key={fila.origen}>
                    <div className="mb-1.5 flex justify-between gap-3 text-xs"><span className="font-medium">{fila.origen}</span><strong>{pct(fila.conversion_contratos_pct)}</strong></div>
                    <div className="gi-track"><div className="gi-fill" style={{ width: `${((fila.conversion_contratos_pct ?? 0) / maxOrigen) * 100}%`, background: C.blue }} /></div>
                  </div>
                ))
              : <p className="rounded-xl border border-dashed border-[var(--gi-line)] px-4 py-8 text-center text-xs font-medium text-[var(--gi-muted)] sm:col-span-2">Aún no hay orígenes con leads en este período</p>}
          </div>
        </section>
        <section data-gi-panel className="gi-card p-5">
          <h2 className="gi-title">Avance de metas</h2>
          <p className="gi-caption mt-1">Meta mensual · {metaMensual.etiqueta}</p>
          {metasComparables ? (
            <div className="mt-5 space-y-5">
              <div>
                <div className="mb-2 flex justify-between text-xs">
                  <span>Capital</span>
                  <strong>{avanceCapital == null ? (tcEnVuelo ? 'Consultando TC…' : 'Sin meta') : `${numero(avanceCapital, 0)}%`}</strong>
                </div>
                <div className="gi-track h-2.5"><div className="gi-fill" style={{ width: `${avanceCapital ?? 0}%`, background: C.teal }} /></div>
                {(cumplimientoCapitalUsd ?? 0) > 0 && (
                  <p className="mt-1 text-[11px] tabular-nums text-[var(--gi-muted)]">
                    {money(cumplimientoCapitalPen ?? 0, 'PEN')} + {money(cumplimientoCapitalUsd ?? 0, 'USD')}
                    {capitalTotal.tc == null
                      ? ' · sin tipo de cambio: el total NO incluye los dólares'
                      : ` · ${rotuloTipoCambio(capitalTotal.tc, tc?.fuente ?? 'TC del día')}`}
                  </p>
                )}
              </div>
              <div><div className="mb-2 flex justify-between text-xs"><span>Conversión</span><strong>{avanceConversion == null ? 'Sin meta' : `${numero(avanceConversion, 0)}%`}</strong></div><div className="gi-track h-2.5"><div className="gi-fill" style={{ width: `${avanceConversion ?? 0}%`, background: C.amber }} /></div></div>
            </div>
          ) : <p role="status" className="mt-5 rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">{mensajeMetaNoComparable(metaMensual)}</p>}
        </section>
      </div>
    </div>
  )
}
