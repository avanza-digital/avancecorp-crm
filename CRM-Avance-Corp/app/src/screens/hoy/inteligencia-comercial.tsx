import { useMemo, useState, type CSSProperties, type JSX, type ReactNode } from 'react'
import type { EChartsOption } from 'echarts'
import {
  AlertTriangle,
  CalendarCheck,
  Eye,
  RefreshCw,
  Target,
  UserRoundCheck,
  WalletCards,
  X,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Sheet,
  SheetBody,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet'
import { Skeleton } from '@/components/ui/skeleton'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import {
  mensajeMetaNoComparable,
  type MetaMensualGerencia,
} from '@/components/gerencia/periodo'
import { fmtFecha, money, moneyCompacta, numero, porcentajeConversionCanonica } from '@/lib/format'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import {
  descuentoArrastre,
  lecturaCobertura,
  lineaProcedencia,
  lineaReferidos,
  totalConversionPublicable,
  type ConversionMensual,
} from '@/lib/conversion-mensual'
import { ChipArrastre } from '@/components/common/chip-arrastre'
import {
  adaptarConversionMensual,
  adaptarConversionVendedores,
  clasificarRankingConversion,
  type ConversionVendedorAdaptada,
  type DetalleConversionMensual,
} from '@/lib/conversion-vendedores'
import type { MetricasConversiones } from '@/lib/metricas-conversiones'
import { sondasNucleoVerificadas } from '@/lib/sondas-conversion'
import { etiquetaOrigen } from '@/lib/tipos'
import {
  capitalObjetivo,
  capitalReal,
  type CumplimientoAgregado,
  type CumplimientoVendedor,
  type ObjetivoComercial,
  type ObjetivosPorVendedor,
} from '@/lib/objetivos'

interface InteligenciaComercialPanelProps {
  datos: MetricasConversiones | null | undefined
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`) alimenta el
   * bloque «del mes» de la ficha del analista, metas y el fallback compatible
   * cuando un servidor antiguo no trae `datos.nucleo`. Tri-estado:
   * `undefined` consultando · `null` no disponible (fail-closed, «—»/rótulo).
   * El héroe real usa `datos.nucleo`, servido para el rango exacto.
   */
  conversionMensual: ConversionMensual | null | undefined
  /**
   * Cumplimiento agregado del equipo: la fuente del capital que se ENSEÑA.
   * `datos.produccion.capital_*` suma contratos enlazados a un lead vía
   * `crm.leads.contrato_id`, y ese enlace jamás se ha escrito (auditoría en
   * prod 27/08: 0 enlaces históricos → «S/ 0» eterno con S/ 3,7 M cerrados).
   * Decisión de Miguel 27/08 (opción A): el capital visible es el confirmado
   * del mes, mismo nombre y fuente que Metas. `null` = «—», jamás un 0 falso.
   */
  cumplimiento: CumplimientoAgregado | null
  /** Origen del lote aplicado por el servidor (null = todos). Con filtro, las
   * cifras de EMPRESA (capital confirmado, meta mensual) se retiran: mezclar
   * un lote recortado con totales de toda la casa es la contradicción que
   * Miguel vetó. El capital del lote filtrado sale de `origenes[]` (F1.3b). */
  origenFiltrado: string | null
  /** Población vigente de la RPC por rango. */
  equipo: ConversionEquipoVendedor[]
  /** Foto mensual; puede diferir del roster vigente en un histórico. */
  equipoMensual?: ConversionEquipoVendedor[]
  metaConversion: number
  metasVendedores: ObjetivosPorVendedor
  cumplimientoVendedores: Record<string, CumplimientoVendedor>
  metaMensual: MetaMensualGerencia
  /** Estado exclusivo de `crm.conversion_mensual_fn` y su foto mensual. */
  mensualCargando: boolean
  mensualError: string | null
  /** Estado exclusivo de `crm.metricas_conversiones_fn` (rango/Cosecha). */
  rangoCargando: boolean
  rangoError: string | null
  modoDemo: boolean
  puedeAlternarEjemplo: boolean
  onAlternarEjemplo: () => void
  onReintentarMensual: () => void
  onReintentarRango: () => void
}

const ETAPA_LABEL: Record<MetricasConversiones['embudo'][number]['etapa'], string> = {
  leads: 'Llegadas del rango',
  contactados: 'Contacto o avance posterior',
  reuniones_agendadas: 'Agenda o avance posterior',
  reuniones_realizadas: 'Reunión o avance posterior',
  propuestas: 'Propuesta o cierre',
  clientes: 'Perfiles creados',
  contratos: 'Leads cerrados',
}

function pct(valor: number | null): string {
  return valor == null ? '—' : `${numero(valor, 1)}%`
}

function nombreOrigen(valor: string): string {
  const limpio = valor.replaceAll('_', ' ')
  return limpio.charAt(0).toUpperCase() + limpio.slice(1)
}

function ErrorPanel({
  error,
  onReintentar,
}: {
  error: string | null
  onReintentar: () => void
}): JSX.Element | null {
  if (!error) return null
  return (
    <div className="m-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3" role="alert">
      <span className="flex items-center gap-2 text-sm font-semibold">
        <AlertTriangle className="size-4 text-destructive" /> {error}
      </span>
      <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
        <RefreshCw /> Reintentar
      </Button>
    </div>
  )
}

function Cargando(): JSX.Element {
  return (
    <CardContent className="grid gap-4 py-6 sm:grid-cols-2 xl:grid-cols-4">
      {Array.from({ length: 8 }, (_, indice) => <Skeleton key={indice} className="h-28 rounded-2xl" />)}
    </CardContent>
  )
}

function Vacio(): JSX.Element {
  return (
    <CardContent className="py-14 text-center">
      <Target className="mx-auto size-8 text-[var(--gi-muted)]" aria-hidden />
      <p className="mt-3 text-sm font-semibold">Aún no hay leads para analizar</p>
    </CardContent>
  )
}

function iniciales(nombre: string): string {
  const partes = nombre.trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return '—'
  const seleccion = partes.length === 1 ? partes : [partes[0], partes.at(-1)]
  return seleccion.map((parte) => parte?.charAt(0) ?? '').join('').toUpperCase()
}

function etiquetaPeriodo(periodo: MetricasConversiones['periodo'] | null): string {
  if (!periodo) return ''
  return periodo.desde === periodo.hasta
    ? fmtFecha(periodo.desde)
    : `${fmtFecha(periodo.desde)} al ${fmtFecha(periodo.hasta)}`
}

function progreso(actual: number | null, objetivo: number): number | null {
  return actual != null && objetivo > 0 ? Math.max(0, (actual / objetivo) * 100) : null
}

function numeroDisponible(valor: number | null): string {
  return valor == null ? '—' : numero(valor)
}

function capitalDisponible(valor: number | null, moneda: 'PEN' | 'USD'): string {
  return valor == null ? '—' : money(valor, moneda)
}

function etiquetaSemana({ desde, hasta }: { desde: string; hasta: string }): string {
  return desde === hasta ? desde : `${desde} – ${hasta}`
}

function DatoDetalle({
  label,
  valor,
  capital = false,
}: {
  label: string
  valor: ReactNode
  capital?: boolean
}): JSX.Element {
  return (
    <div className="min-w-0 px-3 py-3 sm:px-4">
      <dt className="text-[10px] font-bold uppercase leading-tight tracking-[0.08em] text-[var(--gi-muted)]">
        {label}
      </dt>
      <dd className={`${capital ? 'break-words text-lg sm:text-xl' : 'text-2xl'} mt-1 font-bold tracking-[-.035em] tabular-nums text-[var(--gi-navy)]`}>
        {valor}
      </dd>
    </div>
  )
}

function DetalleVendedor({
  fila,
  filaMensual,
  mensual,
  conversionPublicable,
  meta,
  cumplimiento,
  periodo,
  metaMensual,
  mensualCargando,
  onCerrar,
}: {
  fila: ConversionVendedorAdaptada | null
  /** La fila del MISMO analista en la conversión mensual (null = no llegó). */
  filaMensual: ConversionVendedorAdaptada<DetalleConversionMensual> | null
  mensual: ConversionMensual | null | undefined
  /** Las sondas autorizaron publicar cualquier cifra de conversión. */
  conversionPublicable: boolean
  meta: ObjetivoComercial | null
  cumplimiento: CumplimientoVendedor | null
  periodo: MetricasConversiones['periodo'] | null
  metaMensual: MetaMensualGerencia
  mensualCargando: boolean
  onCerrar: () => void
}): JSX.Element {
  const detalle = fila?.detalle ?? null
  const leads = detalle?.leads ?? null
  const clientes = detalle?.clientes ?? null
  const reuniones = detalle?.reuniones_realizadas ?? null
  // El número grande de la ficha es LA conversión del MES (la misma fórmula
  // que el ranking y los tiles): el mismo nombre jamás puede valer dos cosas.
  const detalleMes = filaMensual?.detalle ?? null
  const conversionMes = detalleMes?.conversion_pct ?? null
  const capitalPen = detalle?.capital_pen ?? null
  const capitalUsd = detalle?.capital_usd ?? null
  const metaConversion = meta?.conversionObjetivo ?? 0
  const metaCapitalPen = meta ? capitalObjetivo(meta, 'PEN') : 0
  const metaCapitalUsd = meta ? capitalObjetivo(meta, 'USD') : 0
  const metasComparables = metaMensual.comparable && metaMensual.errorCarga !== true
  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  const progresoCapitalPen = metasComparables ? progreso(capitalConfirmadoPen, metaCapitalPen) : null
  const progresoCapitalUsd = metasComparables ? progreso(capitalConfirmadoUsd, metaCapitalUsd) : null
  // El progreso de conversión se mide con EL MISMO número grande de la ficha, no
  // con `cumplimiento.conversionReal`: son dos fórmulas distintas (recibidos
  // ponderados vs. resueltos crudos) y la ficha las pintaba juntas bajo el mismo
  // nombre, justo lo que el comentario de arriba prohíbe.
  const progresoConversion = metasComparables ? progreso(conversionMes, metaConversion) : null
  const lecturaMensual = lecturaCobertura(mensual?.cobertura)
  const tendencia = useMemo(
    () => detalle?.tendencia_semanal ?? null,
    [detalle?.tendencia_semanal],
  )
  const puntosTendencia = useMemo(() => tendencia ?? [], [tendencia])
  const enMeta = metasComparables && metaConversion > 0
    && conversionMes != null && conversionMes >= metaConversion
  // La cadena arranca por los estados de la conversión MENSUAL (fuente del
  // número grande) y solo si el analista es medible baja a los estados de meta.
  const estado = mensual != null && !lecturaMensual.mostrar
    ? 'Sin datos del mes'
    : filaMensual == null || filaMensual.estadoConversion === 'indisponible'
      ? 'No disponible'
      : filaMensual.estadoConversion === 'solo_referidos'
        ? 'Solo recibió referidos'
        : filaMensual.estadoConversion === 'solo_arrastre'
          ? 'Solo arrastre'
          : filaMensual.estadoConversion === 'sin_muestra'
            ? 'Sin muestra'
            : metaMensual.errorCarga || meta == null
              ? 'Meta no disponible'
              : !metaMensual.comparable
                ? 'No comparable'
                : metaConversion <= 0
                  ? 'Sin meta'
                  : enMeta
                    ? 'En meta'
                    : 'Por alcanzar'
  const opcionTendencia = useMemo<EChartsOption>(() => {
    const valores = puntosTendencia.flatMap((punto) => (
      punto.conversion_pct == null ? [] : [punto.conversion_pct]
    ))
    const maximo = Math.max(25, ...valores)
    return {
      color: [C.blue, C.amber],
      animationDuration: 650,
      grid: { left: 40, right: 12, top: 14, bottom: 28 },
      tooltip: {
        trigger: 'axis',
        valueFormatter: (valor) => valor == null ? 'Sin muestra' : `${numero(Number(valor), 1)}%`,
      },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: puntosTendencia.map(etiquetaSemana),
        axisTick: { show: false },
        axisLine: { lineStyle: { color: C.grid } },
        axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans', fontSize: 10, hideOverlap: true },
      },
      yAxis: {
        type: 'value',
        min: 0,
        max: Math.ceil(maximo / 5) * 5,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: C.grid } },
        axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans', fontSize: 10 },
      },
      series: [{
        name: 'Cerrados hasta hoy',
        type: 'line',
        data: puntosTendencia.map((punto) => punto.conversion_pct),
        connectNulls: false,
        smooth: 0.25,
        symbol: 'circle',
        symbolSize: 6,
        lineStyle: { width: 2.5 },
        itemStyle: { borderWidth: 2, borderColor: '#fff' },
        areaStyle: { color: 'rgba(31,78,121,.10)' },
      }],
    }
  }, [puntosTendencia])

  return (
    <Sheet open={fila != null} onClose={onCerrar} ariaLabel="Detalle comercial del analista" className="w-[calc(100vw-8px)] max-w-[560px] sm:w-[560px]">
      {fila && (
        <>
          <SheetHeader className="border-b-0 px-4 pb-3 pt-5 sm:px-5">
            <div className="flex min-w-0 items-center gap-3">
              <div className="grid size-12 shrink-0 place-items-center rounded-full bg-[var(--gi-navy)] text-base font-bold text-white">
                {iniciales(fila.nombre)}
              </div>
              <div className="min-w-0 flex-1">
                <SheetTitle className="truncate text-xl font-bold tracking-[-.025em] sm:text-2xl">{fila.nombre}</SheetTitle>
                <SheetDescription className="mt-0.5 truncate text-xs font-medium text-[var(--gi-muted)]">
                  Equipo de {fila.supervisorNombre} · {etiquetaPeriodo(periodo)}
                </SheetDescription>
              </div>
              <button
                type="button"
                onClick={onCerrar}
                aria-label="Cerrar detalle de analista"
                className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-[var(--gi-muted)] transition-colors hover:bg-[#f7f5f1] hover:text-[var(--gi-navy)] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              >
                <X className="size-4" aria-hidden />
              </button>
            </div>
          </SheetHeader>
          <SheetBody className="space-y-3.5 px-4 pb-5 pt-0 sm:px-5">
            {mensualCargando ? (
              <>
                <section
                  className="rounded-2xl border border-[var(--gi-line)] bg-[#f7f5f1] px-4 py-4"
                  role="status"
                  aria-busy="true"
                >
                  <Skeleton className="h-12 rounded-xl" />
                  <p className="mt-2 text-xs font-semibold text-[var(--gi-muted)]">
                    Consultando la conversión, las metas y el capital confirmado del mes…
                  </p>
                </section>
                <section aria-label="Capital producido por el analista" className="overflow-hidden rounded-2xl border border-[var(--gi-line)] bg-white">
                  <p className="px-4 pt-3 text-[11px] font-medium text-[var(--gi-muted)]">Capital atribuido · operaciones del rango</p>
                  <dl className="grid grid-cols-2 divide-x divide-[var(--gi-line)]">
                    <DatoDetalle label="Capital atribuido (PEN)" valor={capitalDisponible(capitalPen, 'PEN')} capital />
                    <DatoDetalle label="Capital atribuido (USD)" valor={capitalDisponible(capitalUsd, 'USD')} capital />
                  </dl>
                </section>
              </>
            ) : conversionPublicable ? (
              <>
            <section className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded-2xl bg-[#f7f5f1] px-4 py-3.5">
              <div className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-0.5">
                <strong className="text-4xl font-bold tracking-[-.055em] tabular-nums text-[var(--gi-blue)] sm:text-5xl">{porcentajeConversionCanonica(conversionMes)}</strong>
                <span className="text-xs font-semibold text-[var(--gi-muted)]">conversión del mes</span>
                {detalleMes != null && (
                  <span className="w-full text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">
                    {mensual?.fuentes.divisor === 'crm.leads.creado_en' ? 'Base automática' : 'Base histórica'} {numero(detalleMes.divisor)} · cierres del mes {numero(detalleMes.clientes)}
                  </span>
                )}
                {lecturaMensual.aviso && (
                  <span className="w-full text-[11px] font-semibold text-amber-700">{lecturaMensual.aviso}</span>
                )}
                {(() => {
                  // El MISMO porqué que el ranking: este % ya llega NETO de
                  // anulaciones de meses cerrados. Sin esto, gerencia veía el
                  // chip en el ranking, abría al mismo analista y la
                  // explicación desaparecía (hallazgo #6 de la revisión).
                  const descuento = descuentoArrastre(detalleMes?.ajuste)
                  return descuento
                    ? (
                      <ChipArrastre
                        descuento={descuento}
                        className="w-full text-[11px] font-semibold text-[var(--muted-foreground-strong)]"
                      />
                    )
                    : null
                })()}
              </div>
              <span className={`w-fit rounded-full px-2.5 py-1 text-[11px] font-bold ${enMeta ? 'bg-emerald-100 text-emerald-700' : !metaMensual.comparable || !lecturaMensual.mostrar || filaMensual?.estadoConversion !== 'comparable' ? 'bg-slate-200 text-slate-600' : 'bg-amber-100 text-amber-700'}`}>{estado}</span>
            </section>

            <section aria-label="Resultados del periodo" className="overflow-hidden rounded-2xl border border-[var(--gi-line)] bg-white">
              <dl className="grid grid-cols-3 divide-x divide-[var(--gi-line)]">
                <DatoDetalle label="Llegadas del rango" valor={numeroDisponible(leads)} />
                <DatoDetalle label="Leads ya cerrados" valor={numeroDisponible(clientes)} />
                <DatoDetalle label="Reunión o avance posterior" valor={numeroDisponible(reuniones)} />
              </dl>
              <p className="px-4 py-2 text-[11px] text-[var(--gi-muted)]">Resultados hasta hoy, atribuidos al primer analista. La señal de reunión puede inferirse de una propuesta o cierre; no confirma asistencia.</p>
              {/* La atribución de capital del rango usa la cartera actual y
                  los episodios económicos; no comparte la atribución al
                  primer analista de las llegadas mostradas arriba. */}
              <dl className="grid grid-cols-2 divide-x divide-[var(--gi-line)] border-t border-[var(--gi-line)]">
                <DatoDetalle label="Capital atribuido (PEN)" valor={capitalDisponible(capitalPen, 'PEN')} capital />
                <DatoDetalle label="Capital atribuido (USD)" valor={capitalDisponible(capitalUsd, 'USD')} capital />
              </dl>
              <p className="px-4 pb-2 text-[11px] text-[var(--gi-muted)]">Operaciones del rango: cartera actual y operaciones atribuidas. No se limita a las llegadas del rango ni al origen filtrado.</p>
            </section>

            {detalleMes != null && (
              <section aria-label="Conversión del mes" className="rounded-2xl border border-[var(--gi-line)] bg-white px-4 py-3">
                <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                  <span className="text-xs font-bold">Cierres del mes</span>
                  <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">
                    {lineaProcedencia(detalleMes.procedencia, mensual?.periodo.anio ?? new Date().getFullYear()) || 'Sin cierres este mes'}
                  </span>
                </div>
                <div className="mt-1.5 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                  <span className="text-xs font-bold">Referidos</span>
                  <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">{lineaReferidos(detalleMes.referidos)}</span>
                </div>
                <p className="mt-2 text-[11px] font-medium text-[var(--gi-muted)]">
                  {mensual == null
                    ? 'Fórmula servida por el núcleo comercial.'
                    : mensual.fuentes.divisor === 'crm.leads.creado_en'
                      ? `Fórmula: (cierres Landing/Formulario + referidos ×${numero(mensual.ponderacion.referido, 2)} + renovaciones ×${numero(mensual.ponderacion.renovacion ?? mensual.ponderacion.referido, 2)} + upgrades) ÷ llegadas automáticas Landing/Formulario. La llegada queda en el primer analista; las altas manuales no agregan base.`
                      : 'Base histórica: conserva la definición con la que se calculó este mes; no equivale a llegadas únicas.'}
                </p>
              </section>
            )}

            {metasComparables ? (
              <section aria-label="Avance de metas" className="divide-y divide-[var(--gi-line)] overflow-hidden rounded-2xl border border-[var(--gi-line)] bg-white">
                {([
                  ['PEN', metaCapitalPen, capitalConfirmadoPen, progresoCapitalPen],
                  ['USD', metaCapitalUsd, capitalConfirmadoUsd, progresoCapitalUsd],
                ] as const).map(([moneda, objetivo, real, avance], indice) => (
                  <div className="px-4 py-3" key={moneda}>
                    {indice === 0 && <p className="mb-2 text-[11px] font-medium text-[var(--gi-muted)]">Cumplimiento confirmado · {metaMensual.etiqueta}</p>}
                    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                      <span className="text-xs font-bold">Capital en {moneda}</span>
                      <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">{meta == null ? 'Meta no disponible' : objetivo > 0 ? `${capitalDisponible(real, moneda)} de ${money(objetivo, moneda)}` : 'Meta por definir'}</span>
                    </div>
                    <div
                      className="mt-2 h-2 overflow-hidden rounded-full bg-[#e6e1d8]"
                      role={objetivo > 0 && avance != null ? 'progressbar' : undefined}
                      aria-label={objetivo > 0 && avance != null ? `Cumplimiento de capital en ${moneda}` : undefined}
                      aria-valuemin={objetivo > 0 && avance != null ? 0 : undefined}
                      aria-valuemax={objetivo > 0 && avance != null ? 100 : undefined}
                      aria-valuenow={objetivo > 0 && avance != null ? Math.min(100, avance) : undefined}
                    >
                      <div className="h-full rounded-full bg-emerald-600 transition-[width] duration-500 motion-reduce:transition-none" style={{ width: `${Math.min(100, avance ?? 0)}%` }} />
                    </div>
                  </div>
                ))}
                <div className="px-4 py-3">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                    <span className="text-xs font-bold">Meta de conversión</span>
                    <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">{meta == null ? 'Meta no disponible' : metaConversion > 0 ? `${porcentajeConversionCanonica(conversionMes)} de ${numero(metaConversion, 1)}%` : 'Meta por definir'}</span>
                  </div>
                  <div
                    className="mt-2 h-2 overflow-hidden rounded-full bg-[#e6e1d8]"
                    role={progresoConversion != null ? 'progressbar' : undefined}
                    aria-label={progresoConversion != null ? 'Avance de la meta de conversión' : undefined}
                    aria-valuemin={progresoConversion != null ? 0 : undefined}
                    aria-valuemax={progresoConversion != null ? 100 : undefined}
                    aria-valuenow={progresoConversion != null ? Math.min(100, progresoConversion) : undefined}
                  >
                    <div className="h-full rounded-full bg-emerald-600 transition-[width] duration-500 motion-reduce:transition-none" style={{ width: `${Math.min(100, progresoConversion ?? 0)}%` }} />
                  </div>
                </div>
              </section>
            ) : (
              <section aria-label="Avance de metas" className="rounded-2xl border border-amber-300/70 bg-amber-50 px-4 py-3">
                <p className="text-[11px] font-medium text-amber-800">Meta mensual · {metaMensual.etiqueta}</p>
                <p role="status" className="mt-1 text-xs font-semibold text-amber-900">{mensajeMetaNoComparable(metaMensual)}</p>
              </section>
            )}

            <section>
              <div className="flex items-baseline justify-between gap-3">
                <h3 className="text-sm font-bold tracking-[-.015em]">Resultados por semana de llegada</h3>
                <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">Porcentaje cerrado hasta hoy</span>
              </div>
              <p className="mt-1 text-[11px] font-medium text-[var(--gi-muted)]">Agrupa por llegada, no por fecha del cierre. No se compara con la meta mensual ponderada.</p>
              {tendencia == null ? (
                <div className="mt-2 grid h-28 place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Tendencia no disponible</div>
              ) : tendencia.length > 0 ? (
                <GerenciaEChart tipo="lineas" option={opcionTendencia} ariaLabel={`Resultados por semana de llegada de ${fila.nombre}`} className="mt-1 h-[220px] w-full" />
              ) : (
                <div className="mt-2 grid h-28 place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Aún no hay semanas para comparar</div>
              )}
            </section>
              </>
            ) : (
              <>
                <section className="rounded-2xl border border-amber-300/70 bg-amber-50 px-4 py-3" role="status">
                  <p className="text-xs font-bold text-amber-900">Conversión del mes no disponible</p>
                  <p className="mt-1 text-[11px] font-medium leading-relaxed text-amber-800">
                    {lecturaMensual.aviso ?? 'No se recibió una lectura mensual completa. El capital atribuido sigue disponible en su lectura del rango.'}
                  </p>
                </section>
                <section aria-label="Capital producido por el analista" className="overflow-hidden rounded-2xl border border-[var(--gi-line)] bg-white">
                  <p className="px-4 pt-3 text-[11px] font-medium text-[var(--gi-muted)]">Capital atribuido · operaciones del rango</p>
                  <dl className="grid grid-cols-2 divide-x divide-[var(--gi-line)]">
                    <DatoDetalle label="Capital atribuido (PEN)" valor={capitalDisponible(capitalPen, 'PEN')} capital />
                    <DatoDetalle label="Capital atribuido (USD)" valor={capitalDisponible(capitalUsd, 'USD')} capital />
                  </dl>
                </section>
              </>
            )}
          </SheetBody>
        </>
      )}
    </Sheet>
  )
}

export function InteligenciaComercialPanel({
  datos,
  conversionMensual,
  cumplimiento,
  origenFiltrado,
  equipo,
  equipoMensual,
  metaConversion,
  metasVendedores,
  cumplimientoVendedores,
  metaMensual,
  mensualCargando,
  mensualError,
  rangoCargando,
  rangoError,
  modoDemo,
  puedeAlternarEjemplo,
  onAlternarEjemplo,
  onReintentarMensual,
  onReintentarRango,
}: InteligenciaComercialPanelProps): JSX.Element {
  const [vendedorId, setVendedorId] = useState('')
  const [detalleAbierto, setDetalleAbierto] = useState(false)
  const adaptada = useMemo(
    () => adaptarConversionVendedores(datos, equipo),
    [datos, equipo],
  )
  const adaptadaMensual = useMemo(
    () => adaptarConversionMensual(conversionMensual ?? null, equipoMensual ?? equipo),
    [conversionMensual, equipo, equipoMensual],
  )
  const ranking = useMemo(
    () => clasificarRankingConversion(adaptada.vendedores),
    [adaptada.vendedores],
  )
  const vendedores = useMemo(
    () => [...ranking.conPuesto, ...ranking.sinMuestra, ...ranking.indisponibles],
    [ranking],
  )
  const vendedor = vendedores.find((fila) => fila.vendedorId === vendedorId) ?? vendedores[0] ?? null
  const vendedorMensual = vendedor
    ? adaptadaMensual.vendedores.find((fila) => fila.vendedorId === vendedor.vendedorId) ?? null
    : null
  const metaVendedor = vendedor ? metasVendedores[vendedor.vendedorId] ?? null : null
  const cumplimientoVendedor = vendedor ? cumplimientoVendedores[vendedor.vendedorId] ?? null : null
  const metaConversionVisual = metaConversion > 0 ? metaConversion : 0

  const opcionEquipo = useMemo<EChartsOption>(() => ({
    animationDuration: 650,
    grid: { left: 132, right: 60, top: 8, bottom: 30 },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      valueFormatter: (valor) => pct(
        typeof valor === 'number' ? valor : null,
      ),
    },
    xAxis: { type: 'value', min: 0, axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: vendedores.map((fila) => fila.nombre), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11, width: 120, overflow: 'truncate' } },
    series: [{ type: 'bar', data: vendedores.map((fila) => fila.detalle?.conversion_pct ?? null), barMaxWidth: 17, itemStyle: { color: C.teal, borderRadius: [0, 8, 8, 0] }, label: { show: true, position: 'right', formatter: (parametros) => pct(typeof parametros.value === 'number' ? parametros.value : null), color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
  }), [vendedores])

  const pasos = useMemo(() => (datos?.embudo ?? [])
    .filter((paso) => paso.etapa !== 'clientes')
    .map((paso) => ({ ...paso, label: ETAPA_LABEL[paso.etapa] })), [datos])
  const opcionRecorrido = useMemo<EChartsOption>(() => ({
    animationDuration: 650,
    grid: { left: 150, right: 48, top: 8, bottom: 24 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    xAxis: { type: 'value', axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: pasos.map((paso) => paso.label), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11 } },
    series: [{ type: 'bar', data: pasos.map((paso) => paso.cantidad), barMaxWidth: 22, itemStyle: { color: C.blue, borderRadius: [0, 7, 7, 0] }, label: { show: true, position: 'right', color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
  }), [pasos])

  const origenes = useMemo(() => [...(datos?.origenes ?? [])]
    .sort((a, b) => (b.conversion_contratos_pct ?? -1) - (a.conversion_contratos_pct ?? -1)), [datos])
  const opcionOrigen = useMemo<EChartsOption>(() => ({
    animationDuration: 650,
    grid: { left: 105, right: 60, top: 8, bottom: 28 },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      valueFormatter: (valor) => pct(
        typeof valor === 'number' ? valor : null,
      ),
    },
    xAxis: { type: 'value', min: 0, axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: origenes.map((fila) => nombreOrigen(fila.origen)), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11 } },
    series: [{ type: 'bar', data: origenes.map((fila) => fila.conversion_contratos_pct), barMaxWidth: 18, itemStyle: { color: C.blue, borderRadius: [0, 8, 8, 0] }, label: { show: true, position: 'right', formatter: (parametros) => pct(typeof parametros.value === 'number' ? parametros.value : null), color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
  }), [origenes])

  const tendenciaEquipo = adaptada.tendenciaSemanal
  // F3 (H12): sin % semanal fabricado en el navegador ni meta MENSUAL cruzada
  // con semanas — la curva pinta los enteros SERVIDOS (recibidos y cierres).
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
    legend: { top: 0, right: 0, itemWidth: 14, itemHeight: 8, textStyle: { color: C.muted, fontFamily: 'IBM Plex Sans', fontSize: 11 } },
    xAxis: { type: 'category', boundaryGap: false, data: etiquetas, axisTick: { show: false }, axisLine: { lineStyle: { color: C.grid } }, axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans' } },
    yAxis: { type: 'value', min: 0, axisLine: { show: false }, axisTick: { show: false }, splitLine: { lineStyle: { color: C.grid } }, axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans' } },
    series: [
      { name: 'Llegadas', type: 'line', data: valoresRecibidos, smooth: true, symbolSize: 6, lineStyle: { width: 1.5, type: 'dashed' } },
      { name: 'Cerrados hasta hoy', type: 'line', data: valoresEvolucion, smooth: true, symbolSize: 7, lineStyle: { width: 2.5 }, areaStyle: { color: 'rgba(31,78,121,.12)' } },
    ],
  }), [etiquetas, valoresEvolucion, valoresRecibidos])

  const clientes = datos?.cohorte.contratos ?? null
  const nucleoVerificado = datos?.nucleo != null && sondasNucleoVerificadas(datos.sondas)
  const nucleo = nucleoVerificado ? datos.nucleo ?? null : null
  const sondasConv = datos?.sondas ?? null
  const cosechaLeads = datos?.cohorte.leads ?? null
  const cosechaCierres = datos?.cohorte.contratos ?? null
  const cosechaPct = datos?.cohorte.conversion_contratos_pct ?? null
  // La cifra principal obedece al filtro visible: `nucleo` ya viene calculado
  // por la RPC canónica para el rango exacto. No se divide ni se reconstruye en
  // el navegador. La mensual sigue aparte para metas y detalle del analista.
  const lecturaMensual = lecturaCobertura(conversionMensual?.cobertura)
  const totalMensual = totalConversionPublicable(conversionMensual)
  const conversionMensualPublicable = lecturaMensual.mostrar
  const conversionMesPct = totalMensual?.conversion_pct ?? null
  const cierresMes = totalMensual == null
    ? null
    : totalMensual.cierres_no_referidos + totalMensual.cierres_referidos
  const operacionesCarteraMes = totalMensual?.cartera.conversiones_clientes ?? null
  // Capital CONFIRMADO del mes (cumplimiento de cierres), no `produccion`:
  // ver la nota del prop `cumplimiento`. PEN y USD por separado — este panel
  // no consulta el tipo de cambio y la casa prohíbe sumarlos a ciegas.
  const capitalMesPen = cumplimiento == null ? null : capitalReal(cumplimiento, 'PEN')
  const capitalMesUsd = cumplimiento == null ? null : capitalReal(cumplimiento, 'USD')
  const hayFiltroOrigen = origenFiltrado != null
  // Capital del LOTE filtrado (lo que esos leads han producido hasta hoy):
  // suma de origenes[], que el servidor ya recorto al origen elegido.
  const capitalLotePen = datos == null ? null : origenes.reduce((total, fila) => total + fila.capital_pen, 0)
  const capitalLoteUsd = datos == null ? null : origenes.reduce((total, fila) => total + fila.capital_usd, 0)
  const kpiCapital = hayFiltroOrigen
    ? { label: 'Capital vinculado a las llegadas', valor: capitalDisponible(capitalLotePen, 'PEN'), detalle: capitalLoteUsd == null ? 'Dato no disponible' : capitalLoteUsd > 0 ? money(capitalLoteUsd, 'USD') : 'Todo en soles', icon: WalletCards, color: C.amber }
    : { label: 'Capital confirmado del mes', valor: capitalMesPen == null ? '—' : money(capitalMesPen, 'PEN'), detalle: capitalMesPen == null ? 'Cumplimiento confirmado no disponible' : (capitalMesUsd ?? 0) > 0 ? money(capitalMesUsd ?? 0, 'USD') : 'Todo en soles', icon: WalletCards, color: C.amber }
  const kpis = [
    { label: 'Resultados de las llegadas', valor: pct(cosechaPct), detalle: `${numeroDisponible(cosechaCierres)} cerrados de ${numeroDisponible(cosechaLeads)} llegadas · hasta hoy`, icon: UserRoundCheck, color: C.blue },
    { label: 'Leads que ya cerraron', valor: numeroDisponible(clientes), detalle: `de ${numeroDisponible(cosechaLeads)} llegadas del rango · hasta hoy`, icon: UserRoundCheck, color: C.green },
    { label: 'Reunión o avance posterior', valor: numeroDisponible(datos?.cohorte.reuniones_realizadas ?? null), detalle: `${numeroDisponible(datos?.cohorte.reuniones_agendadas ?? null)} con señal de agenda o avance posterior · no confirma asistencia`, icon: CalendarCheck, color: C.teal },
    kpiCapital,
  ]
  const mensualEsperando = mensualCargando && conversionMensual === undefined
  const rangoEsperando = rangoCargando && datos === undefined
  // Compatibilidad con respuestas antiguas y el mundo demo: si el payload no
  // trae `nucleo`, se conserva la cifra mensual, pero con su rótulo mensual. En
  // producción el contrato vigente sí trae el núcleo y por eso manda el rango.
  const usaNucleoRango = datos?.nucleo != null || rangoEsperando
  const conversionPrincipal = usaNucleoRango ? nucleo?.conversion_pct ?? null : conversionMesPct
  const conversionPrincipalEsperando = usaNucleoRango ? rangoEsperando : mensualEsperando
  const etiquetaConversionPrincipal = usaNucleoRango
    ? `Conversión del rango${datos == null ? '' : ` · ${etiquetaPeriodo(datos.periodo)}`}`
    : `Conversión del mes · ${metaMensual.etiqueta}`
  const cosechaHero = datos != null
    ? pct(cosechaPct)
    : rangoCargando
      ? 'Cargando…'
      : rangoError
        ? 'No disponible'
        : '—'
  const capitalLoteHero = capitalLotePen != null
    ? moneyCompacta(capitalLotePen, 'PEN')
    : rangoCargando
      ? 'Cargando…'
      : rangoError
        ? 'No disponible'
        : '—'

  return (
    <Card className="gi-card overflow-hidden border-0 shadow-none">
      <CardHeader className="border-b border-[var(--gi-line)] bg-white px-5 py-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div><p className="gi-label">Conversiones</p><CardTitle className="mt-1 text-lg">Conversión del equipo</CardTitle></div>
          {puedeAlternarEjemplo && <Button type="button" variant={modoDemo ? 'default' : 'outline'} size="sm" onClick={onAlternarEjemplo}><Eye aria-hidden /> {modoDemo ? 'Ver datos reales' : 'Ver ejemplo'}</Button>}
        </div>
      </CardHeader>
      <ErrorPanel error={mensualError} onReintentar={onReintentarMensual} />
      <CardContent className="bg-[var(--gi-canvas)] p-4 sm:p-5">
          <section
            data-gi-hero
            className="gi-summary-hero"
            aria-label={usaNucleoRango ? 'Conversión canónica del rango' : 'Conversión mensual canónica'}
            aria-busy={conversionPrincipalEsperando}
          >
            <div className="min-w-[280px]">
              <p className="gi-label text-white/65">{etiquetaConversionPrincipal}</p>
              <p className="mt-2 text-6xl font-bold tracking-[-.05em] tabular-nums text-white sm:text-7xl">
                {conversionPrincipalEsperando ? 'Calculando…' : porcentajeConversionCanonica(conversionPrincipal)}
              </p>
              <p className="mt-2 text-xs text-white/65">
                {usaNucleoRango
                  ? rangoEsperando
                    ? 'Todos los orígenes · consultando el núcleo del rango…'
                    : nucleo == null
                      ? 'Cifras en revisión: falta verificar la conversión del rango.'
                      : `${nucleo.base === 'llegada_unica' ? 'Base:' : 'Base histórica ·'} ${numero(nucleo.divisor)} ${nucleo.base === 'llegada_unica' ? 'leads automáticos' : 'registros en la base histórica'} · ${numero(nucleo.cierres_no_referidos)} ${nucleo.base === 'llegada_unica' && nucleo.cierres_referidos === 0 ? 'cierres' : 'cierres no referidos'}`
                        + (nucleo.cierres_referidos > 0 ? ` · ${numero(nucleo.cierres_referidos)} cierres referidos` : '')
                        + (nucleo.operaciones_cartera > 0 ? ` · ${numero(nucleo.operaciones_cartera)} operaciones de cartera` : '')
                  : mensualEsperando
                    ? 'Todos los orígenes · consultando el núcleo mensual…'
                    : `${conversionMensual?.fuentes.divisor === 'crm.leads.creado_en' ? 'Base:' : 'Base histórica ·'} ${totalMensual == null ? 'base no disponible' : `${numero(totalMensual.divisor)} ${conversionMensual?.fuentes.divisor === 'crm.leads.creado_en' ? 'leads automáticos' : 'registros históricos'} · ${numero(cierresMes ?? 0)} cierres`}`
                      + ((operacionesCarteraMes ?? 0) > 0 ? ` · ${numero(operacionesCarteraMes ?? 0)} operaciones de cartera` : '')}
              </p>
              {usaNucleoRango && nucleo?.base === 'llegada_unica' && nucleo.llegadas != null && (
                <p className="mt-1 text-xs text-white/65">{numero(nucleo.llegadas)} llegadas únicas: {numero(nucleo.divisor)} automáticas · {nucleo.altas_manuales == null ? 'altas manuales no disponibles' : `${numero(nucleo.altas_manuales)} manuales`} · {numero(nucleo.referidos_recibidos)} {nucleo.referidos_recibidos === 1 ? 'referido' : 'referidos'}</p>
              )}
              {usaNucleoRango && nucleo?.peso_renovacion != null && (
                <p className="mt-1 text-xs text-white/65">Peso: referidos y renovaciones ×{numero(nucleo.peso_renovacion, 2)} · Upgrades ×1</p>
              )}
              {usaNucleoRango && nucleo != null && !nucleo.incluye_cartera && (
                <p className="mt-1 text-xs font-semibold text-amber-200">El rango parcial no incluye operaciones de cartera.</p>
              )}
              {!usaNucleoRango && !mensualEsperando && lecturaMensual.aviso && <p className="mt-1 text-xs font-semibold text-amber-200">{lecturaMensual.aviso}</p>}
            </div>
            <div className="grid flex-1 gap-3 sm:grid-cols-3">
              <div className="gi-hero-metric"><span>Resultados de las llegadas{hayFiltroOrigen ? ` · ${etiquetaOrigen(origenFiltrado ?? '')}` : ''} · hasta hoy</span><strong>{cosechaHero}</strong></div>
              {/* Con filtro de origen, las cifras de EMPRESA se retiran del
                  héroe: capital del mes y meta al lado de un lote recortado
                  eran la contradicción vetada. */}
              {hayFiltroOrigen ? (
                <div className="gi-hero-metric"><span>Capital vinculado a las llegadas</span><strong>{capitalLoteHero}</strong></div>
              ) : (
                <>
                  <div className="gi-hero-metric"><span>Capital del mes</span><strong>{mensualEsperando ? 'Consultando…' : capitalMesPen == null ? '—' : moneyCompacta(capitalMesPen, 'PEN')}</strong></div>
                  <div className="gi-hero-metric"><span>Meta · {metaMensual.etiqueta}</span><strong>{mensualEsperando ? 'Consultando…' : metaMensual.errorCarga ? 'No disponible' : metaMensual.comparable ? metaConversionVisual > 0 ? `${numero(metaConversionVisual, 1)}%` : 'Sin meta' : 'No comparable'}</strong></div>
                </>
              )}
            </div>
            {modoDemo && <span className="gi-demo-badge">Datos de ejemplo</span>}
          </section>
      </CardContent>

      <section
        aria-label="Análisis de resultados de los leads recibidos"
        aria-busy={rangoCargando && datos === undefined}
        className="border-t border-[var(--gi-line)] bg-[var(--gi-canvas)]"
      >
        <ErrorPanel error={rangoError} onReintentar={onReintentarRango} />
        {rangoCargando && !datos ? <Cargando /> : !datos && rangoError ? null : !datos ? <ErrorPanel error="Resultados del rango no disponibles. No se recibió una respuesta válida." onReintentar={onReintentarRango} /> : datos.cohorte.leads === 0 ? <Vacio /> : (
        <CardContent className="space-y-4 p-4 sm:p-5">

          {/* Los avisos de detalle no reemplazan la guarda del núcleo y de
              resultados por origen. El capital conserva su propia lectura. */}
          {((sondasConv != null && sondasConv.origen_ficha_distinto_del_ledger > 0)
            || (sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0) > 0) && (
            <div className="flex items-start gap-2.5 rounded-2xl border border-amber-300/70 bg-amber-50 px-4 py-3" role="status">
              <AlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-700" aria-hidden />
              <div className="text-xs leading-relaxed text-amber-900">
                {sondasConv != null && sondasConv.origen_ficha_distinto_del_ledger > 0 && (
                  <p>
                    {numero(sondasConv.origen_ficha_distinto_del_ledger)} {sondasConv.origen_ficha_distinto_del_ledger === 1 ? 'lead tiene' : 'leads tienen'} un origen distinto entre su ficha y el
                    ledger: la lectura por origen puede no cuadrar con la cifra del mes.
                  </p>
                )}
                {/* F1.3b: un cliente con leads de dos analistas cuenta su
                    capital de portal ENTERO para ambos — el desglose puede
                    sumar más que el total y hay que decirlo. */}
                {(sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0) > 0 && (
                  <p>
                    {numero(sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0)} {(sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0) === 1 ? 'cliente tiene' : 'clientes tienen'} leads de más de un analista:
                    su capital cuenta para cada uno y el desglose por analista puede sumar más que el total.
                  </p>
                )}
              </div>
            </div>
          )}

          <p role="status" className="text-xs leading-relaxed text-[var(--gi-muted)]">
            {hayFiltroOrigen ? `Origen: ${etiquetaOrigen(origenFiltrado ?? '')} · ` : ''}Las llegadas y sus resultados siguen el rango{hayFiltroOrigen ? ' y el origen elegido' : ''}, hasta hoy. La conversión principal incluye toda la empresa; el detalle de metas es mensual.
          </p>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {kpis.map(({ label, valor, detalle, icon: Icono, color }) => {
              return <div key={label} data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as CSSProperties}><div className="flex justify-between gap-3"><p className="gi-label">{label}</p><Icono className="size-4" style={{ color }} /></div><p className="mt-2 text-3xl font-bold tracking-[-.03em] tabular-nums">{valor}</p><p className="mt-1 text-xs text-[var(--gi-muted)]">{detalle}</p></div>
            })}
          </div>

          <section data-gi-panel className="gi-card p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div><h3 className="gi-title">Resultados por analista</h3><p className="gi-caption mt-1">Porcentaje de sus llegadas que cerró hasta hoy · atribuido al primer analista, no al autor del cierre</p></div>
              {vendedor && <div className="flex items-center gap-2"><select aria-label="Analista para abrir detalle" value={vendedor.vendedorId} onChange={(e) => setVendedorId(e.target.value)} className="h-9 rounded-lg border border-[var(--gi-line)] bg-white px-3 text-xs font-medium">{vendedores.map((fila) => <option key={fila.vendedorId} value={fila.vendedorId}>{fila.nombre}</option>)}</select><Button type="button" size="sm" variant="outline" onClick={() => setDetalleAbierto(true)}>Ver detalle</Button></div>}
            </div>
            {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El contenedor desplazable debe poder recorrerse con teclado. */}
            <div className="mt-3 overflow-x-auto" role="region" aria-label="Gráfico de resultados por analista" tabIndex={0}>
              <GerenciaEChart tipo="barras" option={opcionEquipo} ariaLabel="Resultados de los leads recibidos por analista" className="w-full min-w-[430px]" style={{ height: Math.max(300, vendedores.length * 38) }} />
            </div>
            <p className="gi-caption mt-1 sm:hidden">Desliza el gráfico para ver todas las cifras.</p>
          </section>

          <div className="grid gap-4 xl:grid-cols-2">
            <section data-gi-panel className="gi-card min-w-0 p-5">
              <h3 className="gi-title">Avance comercial inferido</h3>
              <p className="gi-caption mt-1">Señales del historial o de etapas posteriores; no son conteos de citas ni asistencias confirmadas.</p>
              {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El contenedor desplazable debe poder recorrerse con teclado. */}
              <div className="mt-3 overflow-x-auto" role="region" aria-label="Gráfico de avance inferido" tabIndex={0}>
                <GerenciaEChart tipo="barras" option={opcionRecorrido} ariaLabel="Señales de avance inferido de las llegadas del rango" className="h-[330px] w-full min-w-[430px]" />
              </div>
              <p className="gi-caption mt-1 sm:hidden">Desliza el gráfico para ver todas las cifras.</p>
            </section>
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Resultados por origen</h3><p className="gi-caption mt-1">De las llegadas de cada origen, qué porcentaje cerró hasta hoy. No es la conversión ponderada.</p>{nucleoVerificado ? <GerenciaEChart tipo="barras" option={opcionOrigen} ariaLabel="Resultados hasta hoy de las llegadas por origen" className="mt-3 w-full" style={{ height: Math.max(280, origenes.length * 48) }} /> : <p role="status" className="mt-4 rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">Cifras en revisión: los resultados por origen permanecen ocultos.</p>}{nucleoVerificado && origenes.some((fila) => fila.fuera_del_divisor_del_nucleo === true) && (
              // D6: los referidos quedan FUERA de la base general del rango y sus
              // cierres ponderan 0,15 — su barra mide otra cosa y se rotula.
              <p className="mt-2 text-[11px] leading-relaxed text-[var(--gi-muted)]">
                {origenes.filter((fila) => fila.fuera_del_divisor_del_nucleo === true).map((fila) => nombreOrigen(fila.origen)).join(', ')}: sus llegadas no aumentan la base automática. Su barra sigue midiendo resultados de esas llegadas, no el aporte ponderado a la conversión.
              </p>
            )}
            </section>
          </div>

        {/* F1.3b: el capital producido permanece separado del contrato mensual;
            una foto mensual no publicable no invalida contratos ya atribuidos. */}
          {origenes.some((fila) => fila.capital_pen > 0 || fila.capital_usd > 0) && (
            <section data-gi-panel className="gi-card p-5" aria-label="Capital producido por origen">
              <h3 className="gi-title">Capital vinculado por origen</h3>
              <p className="gi-caption mt-1">Capital enlazado a las llegadas del rango, sin filtro de fecha de operación · PEN y USD por separado</p>
              <dl className="mt-3 grid gap-1.5 sm:grid-cols-2">
                {origenes.filter((fila) => fila.capital_pen > 0 || fila.capital_usd > 0).map((fila) => (
                  <div key={fila.origen} className="flex items-baseline justify-between gap-3 text-xs">
                    <dt className="font-medium">{nombreOrigen(fila.origen)}</dt>
                    <dd className="font-bold tabular-nums">
                      {[
                        fila.capital_pen > 0 ? money(fila.capital_pen, 'PEN') : null,
                        fila.capital_usd > 0 ? money(fila.capital_usd, 'USD') : null,
                      ].filter(Boolean).join(' + ')}
                    </dd>
                  </div>
                ))}
              </dl>
            </section>
          )}

          <section data-gi-panel className="gi-card p-5"><div className="flex flex-wrap items-center justify-between gap-3"><h3 className="gi-title">Resultados por semana de llegada</h3><span className="gi-caption">Llegadas del rango y cuántas cerraron hasta hoy; no cierres ocurridos esa semana</span></div>{tendenciaEquipo == null ? <div className="mt-3 grid h-[280px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Tendencia no disponible</div> : tendenciaEquipo.length > 0 ? <GerenciaEChart tipo="lineas" option={opcionEvolucion} ariaLabel="Llegadas por semana y resultados de esas llegadas hasta hoy" className="mt-3 h-[280px] w-full" /> : <div className="mt-3 grid h-[280px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Aún no hay semanas para comparar</div>}</section>
        </CardContent>
      )}
      </section>
      <DetalleVendedor fila={detalleAbierto ? vendedor : null} filaMensual={detalleAbierto ? vendedorMensual : null} mensual={conversionMensual} conversionPublicable={conversionMensualPublicable} meta={metaVendedor} cumplimiento={cumplimientoVendedor} periodo={datos?.periodo ?? null} metaMensual={metaMensual} mensualCargando={mensualEsperando} onCerrar={() => setDetalleAbierto(false)} />
    </Card>
  )
}
