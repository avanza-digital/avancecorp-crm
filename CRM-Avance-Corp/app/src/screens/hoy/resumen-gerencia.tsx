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
import { fmtFecha, money, moneyCompacta, numero, porcentajeConversionCanonica } from '@/lib/format'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import {
  capitalObjetivo,
  capitalReal,
  metaConversionAplicable,
  type CumplimientoAgregado,
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
import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
import { etiquetaOrigen } from '@/lib/tipos'
import { presentarCitas } from '@/lib/terminologia'
import { sondasNucleoVerificadas } from '@/lib/sondas-conversion'

interface ResumenGerenciaPanelProps {
  conversiones: MetricasConversiones | null | undefined
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`) alimenta
   * metas, «Mejores analistas» y el fallback compatible si un servidor antiguo
   * no trae `conversiones.nucleo`. El héroe real usa el núcleo del rango exacto.
   */
  conversionMensual: ConversionMensual | null | undefined
  reuniones: MetricasReuniones | null | undefined
  /** Población vigente de la RPC por rango. */
  equipo: ConversionEquipoVendedor[]
  /** Foto mensual; puede diferir del roster vigente en un histórico. */
  equipoMensual?: ConversionEquipoVendedor[]
  meta: ObjetivoComercial
  cumplimiento: CumplimientoAgregado | null
  metaMensual: MetaMensualGerencia
  tc: { promedio: number, fuente: string } | null | undefined
  /** Origen del lote aplicado a Cosecha y embudo (null = todos). La conversión
   * canónica del rango y «Avance de metas» permanecen a nivel empresa: el chip
   * lo dice para que las dos aguas no se confundan. */
  origenFiltrado: string | null
  cargando: boolean
  /** Estado exclusivo de `crm.metricas_conversiones_fn` (rango). */
  rangoCargando?: boolean
  /** Carga inicial de conversión + meta/capital mensual; no bloquea el rango. */
  mensualCargando?: boolean
  error: string | null
  modoDemo: boolean
  onReintentar: () => void
}

function pct(valor: number | null): string {
  return porcentajeConversionCanonica(valor)
}

function numeroDisponible(valor: number | null): string {
  return valor == null ? '—' : numero(valor)
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
        <AlertTriangle className="size-4" /> {presentarCitas(error)}
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
  equipoMensual,
  meta,
  cumplimiento,
  metaMensual,
  tc,
  origenFiltrado,
  cargando,
  rangoCargando = false,
  mensualCargando = false,
  error,
  modoDemo,
  onReintentar,
}: ResumenGerenciaPanelProps): JSX.Element {
  const clientes = conversiones?.cohorte.contratos ?? null
  const leads = conversiones?.cohorte.leads ?? null
  // El número grande obedece al rango visible y toma el porcentaje YA SERVIDO
  // en `nucleo`; aquí no se divide ni se reconstruye ninguna conversión. La foto
  // mensual sigue alimentando metas y el ranking, que sí son mensuales.
  const origenesVerificados = conversiones?.nucleo != null
    && sondasNucleoVerificadas(conversiones.sondas)
  const nucleoRango = origenesVerificados ? conversiones.nucleo ?? null : null
  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
  const totalMes = totalConversionPublicable(conversionMensual)
  const conversionMes = totalMes?.conversion_pct ?? null
  const cierresMes = totalMes == null ? null : totalMes.cierres_no_referidos + totalMes.cierres_referidos
  const rangoEsperando = rangoCargando && conversiones === undefined
  const usaNucleoRango = conversiones?.nucleo != null || rangoEsperando
  const conversionPrincipal = usaNucleoRango ? nucleoRango?.conversion_pct ?? null : conversionMes
  const conversionPrincipalCargando = usaNucleoRango ? rangoEsperando : mensualCargando
  const etiquetaPeriodoRango = conversiones == null
    ? ''
    : `${fmtFecha(conversiones.periodo.desde)} al ${fmtFecha(conversiones.periodo.hasta)}`
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
  const tcCaido = tc === null && hayDolares
  // El capital del héroe y del KPI es el CONFIRMADO del mes (cumplimiento de
  // cierres) — la misma fuente y el mismo nombre que Metas y «Avance de metas».
  // Antes leía `produccion.capital_*`, que suma contratos enlazados a un lead
  // vía `crm.leads.contrato_id`: ese enlace jamás se ha escrito (auditoría en
  // producción 27/08: 0 enlaces históricos), así que afirmaba «S/ 0» con
  // S/ 3,7 M cerrados. Decisión de Miguel 27/08: fuente de cierres (opción A).
  const capitalMesTexto = tcEnVuelo
    ? 'Calculando…'
    : capitalTotal.total == null ? '—' : money(capitalTotal.total, 'PEN')
  const capitalMesDetalle = cumplimiento == null
    ? 'Cumplimiento confirmado no disponible'
    : tcEnVuelo
      ? 'Consultando el tipo de cambio para consolidar los dólares…'
      : (cumplimientoCapitalUsd ?? 0) > 0
        ? `${money(cumplimientoCapitalPen ?? 0, 'PEN')} + ${money(cumplimientoCapitalUsd ?? 0, 'USD')}${
          capitalTotal.tc == null
            ? ' · sin tipo de cambio: el total NO incluye los dólares'
            : ` · ${rotuloTipoCambio(capitalTotal.tc, tc?.fuente ?? 'TC del día')}`}`
        : (capitalTotal.total ?? 0) > 0
          ? 'Todo en soles'
          : 'Sin capital confirmado este mes'
  const avanceCapital = metasComparables && !tcEnVuelo
    && (metaTotalCapital.total ?? 0) > 0 && capitalTotal.total != null
    ? Math.max(0, (capitalTotal.total / (metaTotalCapital.total ?? 1)) * 100)
    : null
  // La barra avanza con EL MISMO número que el titular: la conversión del mes
  // servida. Hasta 2026-08-13 medía `cumplimiento.conversionReal`, que es otra
  // fórmula (convertidos/RESUELTOS, sin ponderar referidos ni arrastre): la
  // pantalla enseñaba un porcentaje arriba y avanzaba la meta con otro, y los
  // dos se llamaban «conversión». Un solo número bajo un solo nombre. Si el mes
  // no es medible no hay barra, que es más honesto que una barra de mentira.
  const avanceConversion = metasComparables && metaConversion != null && conversionMes != null
    ? Math.max(0, (conversionMes / metaConversion) * 100)
    : null

  const vendedoresAdaptados = useMemo(
    () => adaptarConversionVendedores(conversiones, equipo),
    [conversiones, equipo],
  )
  const tendenciaEquipo = vendedoresAdaptados.tendenciaSemanal
  // F3 (H12): el navegador ya no fabrica un % semanal del equipo ni lo compara
  // con la meta MENSUAL (dos preguntas distintas disfrazadas de una). La curva
  // pinta los enteros SERVIDOS: recibidos y cierres por semana.
  const valoresEvolucion = useMemo(
    () => (tendenciaEquipo ?? []).map((punto) => punto.clientes),
    [tendenciaEquipo],
  )
  const valoresRecibidos = useMemo(
    () => (tendenciaEquipo ?? []).map((punto) => punto.leads),
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
      axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans' },
    },
    series: [
      {
        name: 'Llegadas',
        type: 'line',
        smooth: true,
        data: valoresRecibidos,
        symbolSize: 6,
        lineStyle: { width: 1.5, type: 'dashed' },
      },
      {
        name: 'Cerrados hasta hoy',
        type: 'line',
        smooth: true,
        data: valoresEvolucion,
        symbolSize: 7,
        lineStyle: { width: 2.5 },
        areaStyle: { color: 'rgba(31,78,121,.12)' },
      },
    ],
  }), [etiquetas, valoresEvolucion, valoresRecibidos])

  const adaptadaMensual = useMemo(
    () => adaptarConversionMensual(conversionMensual ?? null, equipoMensual ?? equipo),
    [conversionMensual, equipo, equipoMensual],
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
    // Capital confirmado sin actividad de leads (p. ej. solo cierres de
    // cartera): el resumen tiene algo verdadero que enseñar, no es «vacío».
    || (cumplimientoCapitalPen ?? 0) > 0
    || (cumplimientoCapitalUsd ?? 0) > 0
    || (conversiones?.nucleo?.divisor ?? 0) > 0
    || (conversiones?.nucleo?.numerador ?? 0) > 0
    || (conversionMensual?.total.divisor ?? 0) > 0
    || (conversionMensual?.total.numerador ?? 0) > 0
    || metaMensual.errorCarga === true
    || mensualCargando

  if (cargando && !conversiones && !reuniones) {
    return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="h-32 rounded-2xl" />)}</div>
  }
  if (!hayContenidoResumen) {
    if (error) return <ErrorResumen error={error} onReintentar={onReintentar} />
    if (conversiones == null || reuniones == null) {
      return <ErrorResumen error="Datos del resumen no disponibles. No se recibió una lectura completa del rango." onReintentar={onReintentar} />
    }
    return <div className="gi-card py-14 text-center"><Target className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">Aún no hay actividad comercial en este período</p></div>
  }

  return (
    <div className="space-y-4">
      {error && <ErrorResumen error={error} onReintentar={onReintentar} />}
      {tcCaido && (
        <div className="gi-card flex flex-wrap items-center justify-between gap-3 p-5" role="alert">
          <span className="flex items-center gap-2 text-sm font-semibold text-amber-900">
            <AlertTriangle className="size-4" aria-hidden /> Sin tipo de cambio, el total no incluye los dólares.
          </span>
          <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
            <RefreshCw aria-hidden /> Reintentar tipo de cambio
          </Button>
        </div>
      )}
      {origenFiltrado != null && (
        <p role="status" className="rounded-xl border border-[var(--gi-line)] bg-white px-4 py-2.5 text-xs font-semibold text-[var(--gi-navy)]">
          Origen: {etiquetaOrigen(origenFiltrado)} · filtra las llegadas y sus resultados; las citas, la conversión del rango, el capital mensual y las metas muestran toda la empresa.
        </p>
      )}
      <section data-gi-hero className="gi-summary-hero">
        <div>
          <p className="gi-label text-white/65">
            {usaNucleoRango ? `Conversión del rango${etiquetaPeriodoRango ? ` · ${etiquetaPeriodoRango}` : ''}` : 'Conversión del mes'}
          </p>
          <p className="mt-2 text-5xl font-bold tracking-[-0.045em] tabular-nums text-white sm:text-6xl">{conversionPrincipalCargando ? 'Calculando…' : pct(conversionPrincipal)}</p>
          <p className="mt-2 text-xs text-white/65">
            {usaNucleoRango
              ? rangoEsperando
                ? 'Todos los orígenes · consultando el núcleo del rango…'
                : nucleoRango == null
                  ? 'Cifras en revisión: falta verificar la conversión del rango.'
                  : `${nucleoRango.base === 'llegada_unica' ? 'Base:' : 'Base histórica ·'} ${numero(nucleoRango.divisor)} ${nucleoRango.base === 'llegada_unica' ? 'leads automáticos' : 'registros en la base histórica'} · ${numero(nucleoRango.cierres_no_referidos)} ${nucleoRango.base === 'llegada_unica' && nucleoRango.cierres_referidos === 0 ? 'cierres' : 'cierres no referidos'}`
                    + (nucleoRango.cierres_referidos > 0 ? ` · ${numero(nucleoRango.cierres_referidos)} cierres referidos` : '')
                    + (nucleoRango.operaciones_cartera > 0 ? ` · ${numero(nucleoRango.operaciones_cartera)} operaciones de cartera` : '')
              : mensualCargando
                ? 'Consultando conversión, capital y meta del mes…'
                : conversionMensual != null && !lecturaConversion.mostrar
                  ? (lecturaConversion.aviso ?? 'Sin base comercial para este mes')
                  : totalMes == null
                    ? 'Conversión del mes no disponible'
                    : `${numero(cierresMes ?? 0)} cierres este mes`
                      + (lecturaConversion.aviso != null ? ` · ${lecturaConversion.aviso}` : '')}
          </p>
          {usaNucleoRango && nucleoRango?.base === 'llegada_unica' && nucleoRango.llegadas != null && (
            <p className="mt-1 text-xs text-white/65">{numero(nucleoRango.llegadas)} llegadas únicas: {numero(nucleoRango.divisor)} automáticas · {nucleoRango.altas_manuales == null ? 'altas manuales no disponibles' : `${numero(nucleoRango.altas_manuales)} manuales`} · {numero(nucleoRango.referidos_recibidos)} {nucleoRango.referidos_recibidos === 1 ? 'referido' : 'referidos'}</p>
          )}
          {usaNucleoRango && nucleoRango != null && !nucleoRango.incluye_cartera && (
            <p className="mt-1 text-xs font-semibold text-amber-200">El rango parcial no incluye operaciones de cartera.</p>
          )}
        </div>
        <div className="grid flex-1 gap-3 sm:grid-cols-3">
          {/* Pastilla ESTRECHA: monto compacto (el exacto vive en el KPI de
              abajo). La captura de Miguel mostro «S/ 4,700,021.9» truncado. */}
          <div className="gi-hero-metric"><span>Capital del mes</span><strong>{mensualCargando || tcEnVuelo ? 'Consultando…' : capitalTotal.total == null ? '—' : moneyCompacta(capitalTotal.total, 'PEN')}</strong></div>
          <div className="gi-hero-metric"><span>Citas realizadas</span><strong>{numeroDisponible(reunionesRealizadas)}</strong></div>
          <div className="gi-hero-metric">
            <span>Meta · {metaMensual.etiqueta}</span>
            <strong>
              {mensualCargando
                ? 'Consultando…'
                : metaMensual.errorCarga
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
        <Kpi
          label={usaNucleoRango ? 'Conversión del rango' : 'Conversión del mes'}
          valor={conversionPrincipalCargando ? 'Calculando…' : pct(conversionPrincipal)}
          detalle={usaNucleoRango
            ? rangoEsperando
              ? 'Consultando el rango…'
              : nucleoRango == null ? 'Dato no disponible' : `${numero(nucleoRango.divisor)} ${nucleoRango.base === 'llegada_unica' ? 'leads automáticos' : 'registros en la base histórica'}`
            : mensualCargando ? 'Consultando el mes…' : cierresMes == null ? 'Dato no disponible' : `${numero(cierresMes)} cierres`}
          Icon={TrendingUp}
          color={C.blue}
        />
        {/* «del período», sin más: Miguel vetó «dados de alta» (27/08). La
            distinción con el divisor la explica el héroe, no este detalle. */}
        <Kpi label="Leads que ya cerraron" valor={numeroDisponible(clientes)} detalle={`de ${numeroDisponible(leads)} llegadas del rango · hasta hoy`} Icon={UserRoundCheck} color={C.green} />
        <Kpi label="Capital confirmado del mes" valor={mensualCargando ? 'Calculando…' : capitalMesTexto} detalle={mensualCargando ? 'Consultando capital y meta…' : capitalMesDetalle} Icon={WalletCards} color={C.teal} />
        <Kpi label="Citas realizadas" valor={numeroDisponible(reunionesRealizadas)} detalle={reunionesPactadas == null ? cargando ? 'Cargando citas…' : 'Dato no disponible' : `${numero(reunionesPactadas)} pactadas`} Icon={CalendarCheck} color={C.amber} />
      </div>

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1.35fr)_minmax(330px,.8fr)]">
        <section data-gi-panel className="gi-card p-5">
          <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="gi-title">Resultados por semana de llegada</h2><span className="gi-caption">Llegadas del rango y cuántas cerraron hasta hoy; no cierres ocurridos esa semana</span></div>
          {tendenciaEquipo == null
            ? <div className="mt-3 grid h-[260px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] px-4 text-center text-xs font-medium text-[var(--gi-muted)]">Tendencia no disponible</div>
            : valoresEvolucion.length > 0
              ? <GerenciaEChart tipo="lineas" option={opcionEvolucion} ariaLabel="Llegadas por semana y resultados de esas llegadas hasta hoy" className="mt-3 h-[260px] w-full" />
              : <div className="mt-3 grid h-[260px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] px-4 text-center text-xs font-medium text-[var(--gi-muted)]">Aún no hay semanas para mostrar</div>}
        </section>
        <section
          data-gi-panel
          className="gi-card group relative cursor-pointer p-5 transition-[transform,box-shadow,border-color] duration-200 hover:-translate-y-0.5 hover:border-[var(--gi-blue)]/30 hover:shadow-[0_16px_38px_rgba(17,30,61,.10)] focus-within:ring-[3px] focus-within:ring-ring/35 motion-reduce:transform-none motion-reduce:transition-none"
        >
          <div className="flex items-center justify-between gap-3">
            <h2 className="gi-title">Mejores analistas</h2>
            <a
              href="#/ranking-vendedores"
              aria-label="Ver ranking general de analistas"
              className="after:absolute after:inset-0 after:content-[''] flex items-center gap-1 text-[11px] font-bold text-[var(--gi-blue)] outline-none"
            >
              Ver ranking
              <ChevronRight className="size-3.5 transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none" aria-hidden />
            </a>
          </div>
          <div className="mt-5 space-y-4">
            {mensualCargando
              ? <Skeleton className="h-28 rounded-2xl" aria-label="Consultando ranking mensual" />
              : mejores.length > 0
              ? mejores.map((fila, indice) => (
                  <div key={fila.vendedorId}>
                    <div className="mb-1.5 flex justify-between gap-3 text-xs"><span className="font-medium">{fila.nombre}</span><strong className="tabular-nums">{pct(fila.detalle.conversion_pct)}</strong></div>
                    <div className="gi-track"><div className="gi-fill motion-reduce:transition-none" style={{ width: `${((fila.detalle.conversion_pct ?? 0) / maxMejor) * 100}%`, background: indice < 3 ? C.green : indice === 3 ? C.amber : C.red }} /></div>
                  </div>
                ))
              : <p className="rounded-xl border border-dashed border-[var(--gi-line)] px-4 py-8 text-center text-xs font-medium text-[var(--gi-muted)]">{adaptadaMensual.responsablesDisponibles ? 'Aún no hay analistas medibles este mes' : 'Detalle por analista no disponible'}</p>}
          </div>
        </section>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <section data-gi-panel className="gi-card p-5 lg:col-span-2">
          <h2 className="gi-title">Resultados por origen</h2>
          <p className="gi-caption mt-1">De las llegadas de cada origen, qué porcentaje cerró hasta hoy. No es la conversión ponderada.</p>
          {!origenesVerificados
            ? <p role="status" className="mt-4 rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">Cifras en revisión: los resultados por origen permanecen ocultos.</p>
            : <div className="mt-4 grid gap-3 sm:grid-cols-2">
                {origenes.length > 0
                  ? origenes.map((fila) => (
                      <div key={fila.origen}>
                        <div className="mb-1.5 flex justify-between gap-3 text-xs"><span className="font-medium">{fila.origen}</span><strong>{pct(fila.conversion_contratos_pct)}</strong></div>
                        <div className="gi-track"><div className="gi-fill" style={{ width: `${((fila.conversion_contratos_pct ?? 0) / maxOrigen) * 100}%`, background: C.blue }} /></div>
                      </div>
                    ))
                  : <p className="rounded-xl border border-dashed border-[var(--gi-line)] px-4 py-8 text-center text-xs font-medium text-[var(--gi-muted)] sm:col-span-2">Aún no hay orígenes con leads en este período</p>}
              </div>}
          {origenesVerificados && origenes.some((fila) => fila.fuera_del_divisor_del_nucleo === true) && (
            // D6: el origen Referido queda fuera de la base general de la
            // conversión — su barra mide cierres sobre SUS recibidos.
            <p className="mt-3 text-[11px] leading-relaxed text-[var(--gi-muted)]">
              {origenes.filter((fila) => fila.fuera_del_divisor_del_nucleo === true).map((fila) => fila.origen).join(', ')}: de los recibidos por ese origen, cuánto cerró — queda fuera de la base general de la conversión.
            </p>
          )}
        </section>
        <section data-gi-panel className="gi-card p-5">
          <h2 className="gi-title">Avance de metas</h2>
          <p className="gi-caption mt-1">Meta mensual · {metaMensual.etiqueta}</p>
          {mensualCargando ? (
            <Skeleton className="mt-5 h-24 rounded-2xl" aria-label="Consultando avance de metas" />
          ) : metasComparables ? (
            <div className="mt-5 space-y-5">
              <div>
                <div className="mb-2 flex justify-between text-xs">
                  <span>Capital</span>
                  <strong>{avanceCapital == null ? (tcEnVuelo ? 'Consultando TC…' : capitalTotal.total == null ? 'Dato no disponible' : 'Sin meta') : `${numero(avanceCapital, 0)}%`}</strong>
                </div>
                <div className="gi-track h-2.5"><div className="gi-fill" style={{ width: `${limitar(avanceCapital ?? 0)}%`, background: C.teal }} /></div>
                {(cumplimientoCapitalUsd ?? 0) > 0 && (
                  <p className="mt-1 text-[11px] tabular-nums text-[var(--gi-muted)]">
                    {money(cumplimientoCapitalPen ?? 0, 'PEN')} + {money(cumplimientoCapitalUsd ?? 0, 'USD')}
                    {capitalTotal.tc == null
                      ? ' · sin tipo de cambio: el total NO incluye los dólares'
                      : ` · ${rotuloTipoCambio(capitalTotal.tc, tc?.fuente ?? 'TC del día')}`}
                  </p>
                )}
              </div>
              <div><div className="mb-2 flex justify-between text-xs"><span>Conversión</span><strong>{avanceConversion == null ? conversionMes == null ? 'Dato no disponible' : 'Sin meta' : `${numero(avanceConversion, 0)}%`}</strong></div><div className="gi-track h-2.5"><div className="gi-fill" style={{ width: `${limitar(avanceConversion ?? 0)}%`, background: C.amber }} /></div></div>
            </div>
          ) : <p role="status" className="mt-5 rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">{mensajeMetaNoComparable(metaMensual)}</p>}
        </section>
      </div>
    </div>
  )
}
