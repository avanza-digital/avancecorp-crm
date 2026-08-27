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
import { money, numero, porcentajeConversionCanonica } from '@/lib/format'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import {
  descuentoArrastre,
  lineaProcedencia,
  lineaReferidos,
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
import {
  capitalObjetivo,
  capitalReal,
  type CumplimientoAgregado,
  type CumplimientoVendedor,
  type ObjetivoComercial,
  type ObjetivosPorVendedor,
} from '@/lib/objetivos'
import { estadoVerificacionNucleo } from '@/lib/sondas-conversion'

interface InteligenciaComercialPanelProps {
  datos: MetricasConversiones | null | undefined
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`) — alimenta
   * el héroe y el bloque «del mes» de la ficha del vendedor. Tri-estado:
   * `undefined` consultando · `null` no disponible (fail-closed, «—»/rótulo).
   * Los análisis del RANGO (embudo, orígenes, tendencia) siguen en `datos`:
   * miden otra pregunta y conservan su rótulo de periodo.
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
  equipo: ConversionEquipoVendedor[]
  metaConversion: number
  metasVendedores: ObjetivosPorVendedor
  cumplimientoVendedores: Record<string, CumplimientoVendedor>
  metaMensual: MetaMensualGerencia
  cargando: boolean
  error: string | null
  modoDemo: boolean
  puedeAlternarEjemplo: boolean
  onAlternarEjemplo: () => void
  onReintentar: () => void
}

const ETAPA_LABEL: Record<MetricasConversiones['embudo'][number]['etapa'], string> = {
  leads: 'Leads recibidos',
  contactados: 'Contactados',
  reuniones_agendadas: 'Citas pactadas',
  reuniones_realizadas: 'Citas realizadas',
  propuestas: 'Propuestas',
  clientes: 'Perfiles creados',
  contratos: 'Clientes',
}

function pct(valor: number | null): string {
  return porcentajeConversionCanonica(valor)
}

function nombreOrigen(valor: string): string {
  const limpio = valor.replaceAll('_', ' ')
  return limpio.charAt(0).toUpperCase() + limpio.slice(1)
}

function ErrorPanel({
  error,
  onReintentar,
}: Pick<InteligenciaComercialPanelProps, 'error' | 'onReintentar'>): JSX.Element | null {
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
  const fecha = (iso: string): Date => new Date(`${iso}T12:00:00Z`)
  if (periodo.desde.slice(0, 7) === periodo.hasta.slice(0, 7)) {
    const texto = new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(fecha(periodo.desde))
    return texto.charAt(0).toUpperCase() + texto.slice(1)
  }
  const formato = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })
  return `${formato.format(fecha(periodo.desde))} – ${formato.format(fecha(periodo.hasta))}`
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
  meta,
  cumplimiento,
  periodo,
  metaMensual,
  onCerrar,
}: {
  fila: ConversionVendedorAdaptada | null
  /** La fila del MISMO vendedor en la conversión mensual (null = no llegó). */
  filaMensual: ConversionVendedorAdaptada<DetalleConversionMensual> | null
  mensual: ConversionMensual | null | undefined
  meta: ObjetivoComercial | null
  cumplimiento: CumplimientoVendedor | null
  periodo: MetricasConversiones['periodo'] | null
  metaMensual: MetaMensualGerencia
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
  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  const progresoCapitalPen = metaMensual.comparable ? progreso(capitalConfirmadoPen, metaCapitalPen) : null
  const progresoCapitalUsd = metaMensual.comparable ? progreso(capitalConfirmadoUsd, metaCapitalUsd) : null
  // El progreso de conversión se mide con EL MISMO número grande de la ficha, no
  // con `cumplimiento.conversionReal`: son dos fórmulas distintas (recibidos
  // ponderados vs. resueltos crudos) y la ficha las pintaba juntas bajo el mismo
  // nombre, justo lo que el comentario de arriba prohíbe.
  const progresoConversion = metaMensual.comparable ? progreso(conversionMes, metaConversion) : null
  const tendencia = useMemo(
    () => detalle?.tendencia_semanal ?? null,
    [detalle?.tendencia_semanal],
  )
  const puntosTendencia = useMemo(() => tendencia ?? [], [tendencia])
  const enMeta = metaMensual.comparable && metaConversion > 0
    && conversionMes != null && conversionMes >= metaConversion
  // La cadena arranca por los estados de la conversión MENSUAL (fuente del
  // número grande) y solo si el vendedor es medible baja a los estados de meta.
  const estado = mensual != null && !mensual.cobertura.medible
    ? 'Sin datos del mes'
    : filaMensual == null || filaMensual.estadoConversion === 'indisponible'
      ? 'No disponible'
      : filaMensual.estadoConversion === 'solo_referidos'
        ? 'Solo recibió referidos'
        : filaMensual.estadoConversion === 'solo_arrastre'
          ? 'Solo arrastre'
          : filaMensual.estadoConversion === 'sin_muestra'
            ? 'Sin muestra'
            : metaMensual.errorCarga
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
    const maximo = Math.max(25, metaConversion, ...valores)
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
      series: metaMensual.comparable && metaConversion > 0
        ? [
            {
              name: 'Conversión real',
              type: 'line',
              data: puntosTendencia.map((punto) => punto.conversion_pct),
              connectNulls: false,
              smooth: 0.25,
              symbol: 'circle',
              symbolSize: 6,
              lineStyle: { width: 2.5 },
              itemStyle: { borderWidth: 2, borderColor: '#fff' },
              areaStyle: { color: 'rgba(31,78,121,.10)' },
            },
            {
              name: 'Meta',
              type: 'line',
              data: puntosTendencia.map(() => metaConversion),
              symbol: 'none',
              lineStyle: { type: 'dashed', width: 2 },
            },
          ]
        : [{
            name: 'Conversión real',
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
  }, [metaConversion, metaMensual.comparable, puntosTendencia])

  return (
    <Sheet open={fila != null} onClose={onCerrar} ariaLabel="Detalle comercial del vendedor" className="w-[calc(100vw-8px)] max-w-[560px] sm:w-[560px]">
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
                aria-label="Cerrar detalle de vendedor"
                className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-[var(--gi-muted)] transition-colors hover:bg-[#f7f5f1] hover:text-[var(--gi-navy)] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              >
                <X className="size-4" aria-hidden />
              </button>
            </div>
          </SheetHeader>
          <SheetBody className="space-y-3.5 px-4 pb-5 pt-0 sm:px-5">
            <section className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded-2xl bg-[#f7f5f1] px-4 py-3.5">
              <div className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-0.5">
                <strong className="text-4xl font-bold tracking-[-.055em] tabular-nums text-[var(--gi-blue)] sm:text-5xl">{pct(conversionMes)}</strong>
                <span className="text-xs font-semibold text-[var(--gi-muted)]">conversión del mes</span>
                {detalleMes != null && (
                  <span className="w-full text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">
                    Recibidos {numero(detalleMes.divisor)} · cierres {numero(detalleMes.clientes)}
                  </span>
                )}
                {(() => {
                  // El MISMO porqué que el ranking: este % ya llega NETO de
                  // anulaciones de meses cerrados. Sin esto, gerencia veía el
                  // chip en el ranking, abría al mismo vendedor y la
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
              <span className={`w-fit rounded-full px-2.5 py-1 text-[11px] font-bold ${enMeta ? 'bg-emerald-100 text-emerald-700' : !metaMensual.comparable || (mensual != null && !mensual.cobertura.medible) || filaMensual?.estadoConversion !== 'comparable' ? 'bg-slate-200 text-slate-600' : 'bg-amber-100 text-amber-700'}`}>{estado}</span>
            </section>

            <section aria-label="Resultados del periodo" className="overflow-hidden rounded-2xl border border-[var(--gi-line)] bg-white">
              <dl className="grid grid-cols-3 divide-x divide-[var(--gi-line)]">
                <DatoDetalle label="Leads recibidos" valor={numeroDisponible(leads)} />
                <DatoDetalle label="Clientes" valor={numeroDisponible(clientes)} />
                <DatoDetalle label="Citas" valor={numeroDisponible(reuniones)} />
              </dl>
              {/* F1.3b: esta cifra es el capital que produjeron SUS leads en el
                  rango (contratos del portal vía el perfil del lead + coops) —
                  «confirmado» era el nombre del cumplimiento, otra pregunta, y
                  además la fuente vieja (enlace lead→contrato jamás poblado)
                  la dejaba en S/ 0 eterno. */}
              <dl className="grid grid-cols-2 divide-x divide-[var(--gi-line)] border-t border-[var(--gi-line)]">
                <DatoDetalle label="Capital por sus leads (PEN)" valor={capitalDisponible(capitalPen, 'PEN')} capital />
                <DatoDetalle label="Capital por sus leads (USD)" valor={capitalDisponible(capitalUsd, 'USD')} capital />
              </dl>
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
                    ? 'Fórmula: (cierres no referidos + referidos ponderados + operaciones de cartera) ÷ leads no referidos recibidos en el mes.'
                    : `Fórmula: (cierres no referidos + referidos ×${numero(mensual.ponderacion.referido, 2)} + operaciones de cartera) ÷ leads no referidos recibidos en el mes.`}
                </p>
              </section>
            )}

            {metaMensual.comparable ? (
              <section aria-label="Avance de metas" className="divide-y divide-[var(--gi-line)] overflow-hidden rounded-2xl border border-[var(--gi-line)] bg-white">
                {([
                  ['PEN', metaCapitalPen, capitalConfirmadoPen, progresoCapitalPen],
                  ['USD', metaCapitalUsd, capitalConfirmadoUsd, progresoCapitalUsd],
                ] as const).map(([moneda, objetivo, real, avance], indice) => (
                  <div className="px-4 py-3" key={moneda}>
                    {indice === 0 && <p className="mb-2 text-[11px] font-medium text-[var(--gi-muted)]">Cumplimiento confirmado · {metaMensual.etiqueta}</p>}
                    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                      <span className="text-xs font-bold">Capital en {moneda}</span>
                      <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">{objetivo > 0 ? `${capitalDisponible(real, moneda)} de ${money(objetivo, moneda)}` : 'Meta por definir'}</span>
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
                    <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">{metaConversion > 0 ? `${pct(conversionMes)} de ${numero(metaConversion, 1)}%` : 'Meta por definir'}</span>
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
                <h3 className="text-sm font-bold tracking-[-.015em]">Tendencia semanal</h3>
                <span className="text-[11px] font-medium tabular-nums text-[var(--gi-muted)]">{metaMensual.comparable ? `Meta mensual · ${metaMensual.etiqueta}` : 'Solo resultados del rango'}</span>
              </div>
              {!metaMensual.comparable && <p className="mt-1 text-[11px] font-medium text-[var(--gi-muted)]">{mensajeMetaNoComparable(metaMensual)}</p>}
              {tendencia == null ? (
                <div className="mt-2 grid h-28 place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Tendencia no disponible</div>
              ) : tendencia.length > 0 ? (
                <GerenciaEChart tipo="lineas" option={opcionTendencia} ariaLabel={`Tendencia semanal de conversión de ${fila.nombre}`} className="mt-1 h-[220px] w-full" />
              ) : (
                <div className="mt-2 grid h-28 place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Aún no hay semanas para comparar</div>
              )}
            </section>
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
  equipo,
  metaConversion,
  metasVendedores,
  cumplimientoVendedores,
  metaMensual,
  cargando,
  error,
  modoDemo,
  puedeAlternarEjemplo,
  onAlternarEjemplo,
  onReintentar,
}: InteligenciaComercialPanelProps): JSX.Element {
  const [vendedorId, setVendedorId] = useState('')
  const [detalleAbierto, setDetalleAbierto] = useState(false)
  const adaptada = useMemo(
    () => adaptarConversionVendedores(datos, equipo),
    [datos, equipo],
  )
  const adaptadaMensual = useMemo(
    () => adaptarConversionMensual(conversionMensual ?? null, equipo),
    [conversionMensual, equipo],
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
      valueFormatter: (valor) => porcentajeConversionCanonica(
        typeof valor === 'number' ? valor : null,
      ),
    },
    xAxis: { type: 'value', min: 0, axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: vendedores.map((fila) => fila.nombre), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11, width: 120, overflow: 'truncate' } },
    series: [{ type: 'bar', data: vendedores.map((fila) => fila.detalle?.conversion_pct ?? null), barMaxWidth: 17, itemStyle: { color: C.teal, borderRadius: [0, 8, 8, 0] }, label: { show: true, position: 'right', formatter: (parametros) => porcentajeConversionCanonica(typeof parametros.value === 'number' ? parametros.value : null), color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
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
      valueFormatter: (valor) => porcentajeConversionCanonica(
        typeof valor === 'number' ? valor : null,
      ),
    },
    xAxis: { type: 'value', min: 0, axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: origenes.map((fila) => nombreOrigen(fila.origen)), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11 } },
    series: [{ type: 'bar', data: origenes.map((fila) => fila.conversion_contratos_pct), barMaxWidth: 18, itemStyle: { color: C.blue, borderRadius: [0, 8, 8, 0] }, label: { show: true, position: 'right', formatter: (parametros) => porcentajeConversionCanonica(typeof parametros.value === 'number' ? parametros.value : null), color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
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
      { name: 'Leads recibidos', type: 'line', data: valoresRecibidos, smooth: true, symbolSize: 6, lineStyle: { width: 1.5, type: 'dashed' } },
      { name: 'Cierres', type: 'line', data: valoresEvolucion, smooth: true, symbolSize: 7, lineStyle: { width: 2.5 }, areaStyle: { color: 'rgba(31,78,121,.12)' } },
    ],
  }), [etiquetas, valoresEvolucion, valoresRecibidos])

  const clientes = datos?.cohorte.contratos ?? 0
  // F3.1 (decisión D2): la cifra principal es el NÚCLEO servido — la misma de
  // HOY/Metas/Ranking — y la foto por cosecha es la segunda lectura. F3.4: si
  // las DOS sondas de paridad no confirmaron (`cuadra=true` Y desvío 0), el
  // número se oculta;
  // solo el espejo demo, identificado por `modoDemo`, puede degradar cuando no
  // trae ni `nucleo` ni `sondas`. Una respuesta REAL vieja o incompleta se
  // oculta: ausencia de evidencia nunca autoriza a revivir otra fórmula.
  const nucleo = datos?.nucleo ?? null
  const sondasConv = datos?.sondas ?? null
  const verificacionNucleo = estadoVerificacionNucleo(sondasConv)
  const nucleoVisible = nucleo != null && verificacionNucleo === 'verificada'
  // Núcleo + DOS sondas verificadas son obligatorios en real. La única
  // excepción es la demo heredada, explícita y sin ninguno de los dos bloques.
  const demoSinContratoCanonico = modoDemo && nucleo == null && sondasConv == null
  const conversionEnRevision = !nucleoVisible && !demoSinContratoCanonico
  const conversion = nucleoVisible
    ? nucleo.conversion_pct
    : conversionEnRevision
      ? null
      : (datos?.cohorte.conversion_contratos_pct ?? null)
  // Veto de Miguel (27/08): bajo la cifra NO va aritmética — ni «puntos» (son
  // leads), ni el desglose ×peso + cartera, ni la cosecha, ni el capital por
  // leads. Una sola línea, con la MISMA letra que el héroe del Resumen. El
  // detalle fino sigue viajando en el payload para quien lo audite.
  const cierresDelMes = nucleoVisible
    ? nucleo.cierres_no_referidos + nucleo.cierres_referidos
    : null
  // Capital CONFIRMADO del mes (cumplimiento de cierres), no `produccion`:
  // ver la nota del prop `cumplimiento`. PEN y USD por separado — este panel
  // no consulta el tipo de cambio y la casa prohíbe sumarlos a ciegas.
  const capitalMesPen = cumplimiento == null ? null : capitalReal(cumplimiento, 'PEN')
  const capitalMesUsd = cumplimiento == null ? null : capitalReal(cumplimiento, 'USD')
  const kpis = [
    nucleoVisible
      ? { label: 'Conversión del mes', valor: pct(conversion), detalle: `${numero(cierresDelMes ?? 0)} cierres`, icon: UserRoundCheck, color: C.blue }
      : { label: conversionEnRevision ? 'Conversión del mes' : 'Conversión', valor: conversionEnRevision ? '—' : pct(conversion), detalle: conversionEnRevision ? 'Cifras en revisión' : `${numero(clientes)} clientes`, icon: UserRoundCheck, color: C.blue },
    { label: 'Clientes que invirtieron', valor: numero(clientes), detalle: `de ${numero(datos?.cohorte.leads ?? 0)} leads del rango`, icon: UserRoundCheck, color: C.green },
    { label: 'Citas realizadas', valor: numero(datos?.cohorte.reuniones_realizadas ?? 0), detalle: `${numero(datos?.cohorte.reuniones_agendadas ?? 0)} pactadas`, icon: CalendarCheck, color: C.teal },
    { label: 'Capital confirmado del mes', valor: capitalMesPen == null ? '—' : money(capitalMesPen, 'PEN'), detalle: capitalMesPen == null ? 'Cumplimiento confirmado no disponible' : (capitalMesUsd ?? 0) > 0 ? money(capitalMesUsd ?? 0, 'USD') : 'Todo en soles', icon: WalletCards, color: C.amber },
  ]

  return (
    <Card className="gi-card overflow-hidden border-0 shadow-none">
      <CardHeader className="border-b border-[var(--gi-line)] bg-white px-5 py-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div><p className="gi-label">Conversiones</p><CardTitle className="mt-1 text-lg">Conversión del equipo</CardTitle></div>
          {puedeAlternarEjemplo && <Button type="button" variant={modoDemo ? 'default' : 'outline'} size="sm" onClick={onAlternarEjemplo}><Eye aria-hidden /> {modoDemo ? 'Ver datos reales' : 'Ver ejemplo'}</Button>}
        </div>
      </CardHeader>
      <ErrorPanel error={error} onReintentar={onReintentar} />
      {cargando && !datos ? <Cargando /> : !datos && error ? null : !datos ? <Vacio /> : (
        <CardContent className="space-y-4 bg-[var(--gi-canvas)] p-4 sm:p-5">
          <section data-gi-hero className="gi-summary-hero">
            {/* D2: cifra principal = NÚCLEO servido (la misma de HOY/Metas/
                Ranking). Un núcleo con verificación incompleta se oculta sin
                rescatar otra fórmula; solo la demo heredada conserva su
                lectura de rango explícitamente rotulada. */}
            <div className="min-w-[280px]">
              <p className="gi-label text-white/65">
                {demoSinContratoCanonico ? 'Conversión a clientes' : 'Conversión del mes'}
              </p>
              <p className="mt-2 text-6xl font-bold tracking-[-.05em] tabular-nums text-white sm:text-7xl">{conversionEnRevision ? '—' : pct(conversion)}</p>
              <p className="mt-2 text-xs text-white/65">
                {conversionEnRevision
                  ? verificacionNucleo === 'descuadre'
                    ? 'Cifras en revisión: la verificación interna del mes no cuadró.'
                    : 'Cifras en revisión: la verificación interna del mes no está completa.'
                  : cierresDelMes != null && nucleoVisible
                    ? `${numero(cierresDelMes)} cierres · base del mes: ${numero(nucleo.divisor)} leads asignados (los referidos cierran aparte, sin dividir)`
                    : `${numero(clientes)} clientes de ${numero(datos.cohorte.leads)} leads del rango`}
              </p>
            </div>
            <div className="grid flex-1 gap-3 sm:grid-cols-3">
              <div className="gi-hero-metric"><span>Clientes</span><strong>{numero(clientes)}</strong></div>
              <div className="gi-hero-metric"><span>Capital del mes</span><strong>{capitalMesPen == null ? '—' : money(capitalMesPen, 'PEN')}</strong></div>
              <div className="gi-hero-metric"><span>Meta mensual · {metaMensual.etiqueta}</span><strong>{metaMensual.errorCarga ? 'No disponible' : metaMensual.comparable ? metaConversionVisual > 0 ? `${numero(metaConversionVisual, 1)}%` : 'Sin meta' : 'No comparable'}</strong></div>
            </div>
            {modoDemo && <span className="gi-demo-badge">Datos de ejemplo</span>}
          </section>

          {/* F3.4: lo que dicen las sondas se dice — el descuadre además ocultó la cifra arriba. */}
          {(conversionEnRevision
            || (sondasConv != null && sondasConv.origen_ficha_distinto_del_ledger > 0)
            || (sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0) > 0) && (
            <div className="flex items-start gap-2.5 rounded-2xl border border-amber-300/70 bg-amber-50 px-4 py-3" role="status">
              <AlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-700" aria-hidden />
              <div className="text-xs leading-relaxed text-amber-900">
                {conversionEnRevision && (
                  <p className="font-semibold">
                    {verificacionNucleo === 'descuadre'
                      ? 'Cifras en revisión: la verificación interna del mes no cuadró y la conversión del mes se oculta hasta revisarla.'
                      : 'Cifras en revisión: la verificación interna del mes no está completa y la conversión del mes se oculta hasta revisarla.'}
                  </p>
                )}
                {sondasConv != null && sondasConv.origen_ficha_distinto_del_ledger > 0 && (
                  <p>
                    {numero(sondasConv.origen_ficha_distinto_del_ledger)} {sondasConv.origen_ficha_distinto_del_ledger === 1 ? 'lead tiene' : 'leads tienen'} un origen distinto entre su ficha y el
                    ledger: la lectura por origen puede no cuadrar con la cifra del mes.
                  </p>
                )}
                {/* F1.3b: un cliente con leads de dos vendedores cuenta su
                    capital de portal ENTERO para ambos — el desglose puede
                    sumar más que el total y hay que decirlo. */}
                {(sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0) > 0 && (
                  <p>
                    {numero(sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0)} {(sondasConv?.perfiles_con_leads_de_varios_vendedores ?? 0) === 1 ? 'cliente tiene' : 'clientes tienen'} leads de más de un vendedor:
                    su capital cuenta para cada uno y el desglose por vendedor puede sumar más que el total.
                  </p>
                )}
              </div>
            </div>
          )}

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {kpis.map(({ label, valor, detalle, icon: Icono, color }) => {
              return <div key={label} data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as CSSProperties}><div className="flex justify-between gap-3"><p className="gi-label">{label}</p><Icono className="size-4" style={{ color }} /></div><p className="mt-2 text-3xl font-bold tracking-[-.03em] tabular-nums">{valor}</p><p className="mt-1 text-xs text-[var(--gi-muted)]">{detalle}</p></div>
            })}
          </div>

          {conversionEnRevision ? (
            <section data-gi-panel className="gi-card p-5" role="status">
              <h3 className="gi-title">Conversión por vendedor</h3>
              <p className="mt-3 rounded-2xl border border-dashed border-amber-300 bg-amber-50 px-4 py-6 text-center text-xs font-medium text-amber-900">
                Cifras en revisión: la tabla y la gráfica por vendedor permanecen ocultas.
              </p>
            </section>
          ) : (
            <section data-gi-panel className="gi-card p-5">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div><h3 className="gi-title">Conversión por vendedor</h3><p className="gi-caption mt-1">Equipo completo</p></div>
                {vendedor && <div className="flex items-center gap-2"><select aria-label="Vendedor para abrir detalle" value={vendedor.vendedorId} onChange={(e) => setVendedorId(e.target.value)} className="h-9 rounded-lg border border-[var(--gi-line)] bg-white px-3 text-xs font-medium">{vendedores.map((fila) => <option key={fila.vendedorId} value={fila.vendedorId}>{fila.nombre}</option>)}</select><Button type="button" size="sm" variant="outline" onClick={() => setDetalleAbierto(true)}>Ver detalle</Button></div>}
              </div>
              <GerenciaEChart tipo="barras" option={opcionEquipo} ariaLabel="Conversión a clientes por vendedor" className="mt-3 w-full" style={{ height: Math.max(300, vendedores.length * 38) }} />
            </section>
          )}

          <div className="grid gap-4 xl:grid-cols-2">
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Avance comercial</h3><GerenciaEChart tipo="barras" option={opcionRecorrido} ariaLabel="Avance de los leads hasta convertirse en clientes" className="mt-3 h-[330px] w-full" /></section>
            {conversionEnRevision ? (
              <section data-gi-panel className="gi-card p-5" role="status">
                <h3 className="gi-title">Conversión por origen</h3>
                <p className="mt-3 rounded-2xl border border-dashed border-amber-300 bg-amber-50 px-4 py-6 text-center text-xs font-medium text-amber-900">
                  Cifras en revisión: la gráfica por origen permanece oculta.
                </p>
              </section>
            ) : (
              <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Conversión por origen</h3><GerenciaEChart tipo="barras" option={opcionOrigen} ariaLabel="Conversión a clientes por origen del lead" className="mt-3 w-full" style={{ height: Math.max(280, origenes.length * 48) }} />{origenes.some((fila) => fila.fuera_del_divisor_del_nucleo === true) && (
              // D6: los referidos quedan FUERA de la base general del mes y sus
              // cierres ponderan 0,15 — su barra mide otra cosa y se rotula.
              <p className="mt-2 text-[11px] leading-relaxed text-[var(--gi-muted)]">
                {origenes.filter((fila) => fila.fuera_del_divisor_del_nucleo === true).map((fila) => nombreOrigen(fila.origen)).join(', ')}: de los recibidos por ese origen, cuánto cerró. Ese origen queda fuera de la base de la conversión del mes (sus cierres ponderan {numero(nucleo?.peso_referido ?? 0.15, 2)} en el numerador) — no compares su barra con la cifra grande.
              </p>
              )}
              {/* F1.3b: cuánto capital ha producido cada origen (lo cerrado
                  hasta hoy por los leads del rango, portal + coops). Servido
                  por origenes[].capital_* — vivo desde la migración F1.3b;
                  antes leía el enlace muerto y era 0 invisible. PEN y USD por
                  separado: aquí no hay tipo de cambio. Solo orígenes con algo. */}
              {origenes.some((fila) => fila.capital_pen > 0 || fila.capital_usd > 0) && (
                <div className="mt-3 border-t border-[var(--gi-line)] pt-3">
                  <p className="gi-caption">Capital producido por origen · leads del rango, cerrado hasta hoy</p>
                  <dl className="mt-2 grid gap-1.5 sm:grid-cols-2">
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
                </div>
              )}
            </section>
            )}
          </div>

          <section data-gi-panel className="gi-card p-5"><div className="flex items-center justify-between"><h3 className="gi-title">Ritmo semanal del equipo</h3><span className="gi-caption">Leads recibidos y cierres por semana del rango</span></div>{tendenciaEquipo == null ? <div className="mt-3 grid h-[280px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Tendencia no disponible</div> : tendenciaEquipo.length > 0 ? <GerenciaEChart tipo="lineas" option={opcionEvolucion} ariaLabel="Leads recibidos y cierres por semana del rango aplicado" className="mt-3 h-[280px] w-full" /> : <div className="mt-3 grid h-[280px] place-items-center rounded-2xl border border-dashed border-[var(--gi-line)] text-xs font-medium text-[var(--gi-muted)]">Aún no hay semanas para comparar</div>}</section>
        </CardContent>
      )}
      <DetalleVendedor fila={detalleAbierto && !conversionEnRevision ? vendedor : null} filaMensual={detalleAbierto && !conversionEnRevision ? vendedorMensual : null} mensual={conversionMensual} meta={metaVendedor} cumplimiento={cumplimientoVendedor} periodo={datos?.periodo ?? null} metaMensual={metaMensual} onCerrar={() => setDetalleAbierto(false)} />
    </Card>
  )
}
