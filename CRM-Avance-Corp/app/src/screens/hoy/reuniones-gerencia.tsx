import { useMemo, type JSX } from 'react'
import type { EChartsOption } from 'echarts'
import {
  AlertTriangle,
  CalendarCheck,
  CalendarClock,
  Eye,
  RefreshCw,
  UserRoundCheck,
  UserRoundX,
  type LucideIcon,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import { money, numero } from '@/lib/format'
import type { MetricasReuniones } from '@/lib/metricas-reuniones'
import { presentarCitas } from '@/lib/terminologia'

type Modalidad = MetricasReuniones['modalidades'][number]['modalidad']

interface ReunionesGerenciaPanelProps {
  datos: MetricasReuniones | null | undefined
  cargando: boolean
  error: string | null
  modoDemo: boolean
  puedeAlternarEjemplo: boolean
  onAlternarEjemplo: () => void
  onReintentar: () => void
}

const MODALIDAD: Record<Modalidad, string> = {
  presencial: 'Presencial',
  virtual: 'Virtual',
  sin_clasificar: 'Sin clasificar',
}

function pct(valor: number | null): string {
  return valor == null ? '—' : `${numero(valor, 1)}%`
}

function textoResultado(valor: string): string {
  const limpio = valor.replaceAll('_', ' ')
  return limpio.charAt(0).toUpperCase() + limpio.slice(1)
}

function ErrorPanel({ error, onReintentar }: Pick<ReunionesGerenciaPanelProps, 'error' | 'onReintentar'>): JSX.Element | null {
  if (!error) return null
  return <div className="m-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3" role="alert"><span className="flex items-center gap-2 text-sm font-semibold"><AlertTriangle className="size-4 text-destructive" />{presentarCitas(error)}</span><Button type="button" variant="outline" size="sm" onClick={onReintentar}><RefreshCw /> Reintentar</Button></div>
}

function Cargando(): JSX.Element {
  return <CardContent className="grid gap-4 py-6 sm:grid-cols-2 xl:grid-cols-5">{Array.from({ length: 10 }, (_, i) => <Skeleton key={i} className="h-28 rounded-2xl" />)}</CardContent>
}

function Vacio(): JSX.Element {
  return <CardContent className="py-14 text-center"><CalendarCheck className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">Aún no hay citas en este período</p></CardContent>
}

function Kpi({ label, value, detail, Icon, color }: { label: string; value: string; detail: string; Icon: LucideIcon; color: string }): JSX.Element {
  return <div data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as React.CSSProperties}><div className="flex justify-between gap-2"><p className="gi-label">{label}</p><Icon className="size-4" style={{ color }} /></div><p className="mt-2 text-3xl font-bold tracking-[-.03em] tabular-nums">{value}</p><p className="mt-1 text-xs text-[var(--gi-muted)]">{detail}</p></div>
}

function ResultadosPorVendedor({ datos }: { datos: MetricasReuniones }): JSX.Element {
  return (
    <section data-gi-panel className="gi-card min-w-0 overflow-hidden">
      <div className="border-b border-[var(--gi-line)] bg-[var(--gi-soft)] px-5 py-4"><h3 className="gi-title">Resultados por analista</h3></div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[680px] text-xs">
          <thead className="text-left text-[10px] uppercase tracking-wide text-[var(--gi-muted)]"><tr><th className="px-5 py-3">Analista</th><th className="px-3 py-3">Supervisor</th><th className="px-3 py-3 text-right">Pactadas</th><th className="px-3 py-3 text-right">Realizadas</th><th className="px-3 py-3 text-right">Sin resultado</th><th className="px-5 py-3 text-right">Efectividad</th></tr></thead>
          <tbody className="divide-y divide-[var(--gi-line)]">{datos.responsables.map((fila) => <tr key={fila.responsable_id ?? fila.nombre}><td className="px-5 py-3 font-semibold">{fila.nombre}</td><td className="px-3 py-3 text-[var(--gi-muted)]">{fila.supervisor_nombre}</td><td className="px-3 py-3 text-right tabular-nums">{numero(fila.pactadas)}</td><td className="px-3 py-3 text-right tabular-nums">{numero(fila.realizadas)}</td><td className="px-3 py-3 text-right font-semibold tabular-nums">{numero(fila.pendientes_cierre)}</td><td className="px-5 py-3 text-right font-bold tabular-nums text-[var(--gi-blue)]">{pct(fila.pct_realizacion)}</td></tr>)}</tbody>
        </table>
      </div>
    </section>
  )
}

export function ReunionesGerenciaPanel({ datos, cargando, error, modoDemo, puedeAlternarEjemplo, onAlternarEjemplo, onReintentar }: ReunionesGerenciaPanelProps): JSX.Element {
  const modalidades = useMemo(() => (datos?.modalidades ?? []).map((fila) => ({ ...fila, nombre: MODALIDAD[fila.modalidad] })), [datos])
  const opcionModalidades = useMemo<EChartsOption>(() => ({
    animationDuration: 650,
    grid: { left: 42, right: 18, top: 48, bottom: 34 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    xAxis: { type: 'category', data: modalidades.map((fila) => fila.nombre), axisTick: { show: false }, axisLine: { lineStyle: { color: C.grid } }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans' } },
    yAxis: { type: 'value', minInterval: 1, axisLine: { show: false }, axisTick: { show: false }, splitLine: { lineStyle: { color: C.grid } }, axisLabel: { color: C.muted, fontFamily: 'IBM Plex Sans' } },
    series: [
      { name: 'Pactadas', type: 'bar', data: modalidades.map((fila) => fila.pactadas), barMaxWidth: 28, itemStyle: { color: C.blue, borderRadius: [5, 5, 0, 0] }, label: { show: true, position: 'top', formatter: 'Pactadas\n{c}', color: C.blue, fontFamily: 'IBM Plex Sans', fontSize: 10, lineHeight: 13 } },
      { name: 'Realizadas', type: 'bar', data: modalidades.map((fila) => fila.realizadas), barMaxWidth: 28, itemStyle: { color: C.teal, borderRadius: [5, 5, 0, 0] }, label: { show: true, position: 'top', formatter: 'Realizadas\n{c}', color: C.teal, fontFamily: 'IBM Plex Sans', fontSize: 10, lineHeight: 13 } },
    ],
  }), [modalidades])

  const origenes = useMemo(() => [...(datos?.origenes ?? [])].sort((a, b) => (b.conversion_contrato_pct ?? -1) - (a.conversion_contrato_pct ?? -1)), [datos])
  const opcionOrigen = useMemo<EChartsOption>(() => ({
    animationDuration: 650,
    grid: { left: 105, right: 58, top: 8, bottom: 28 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    xAxis: { type: 'value', min: 0, axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: origenes.map((fila) => fila.origen), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11 } },
    series: [{ type: 'bar', data: origenes.map((fila) => fila.conversion_contrato_pct ?? 0), barMaxWidth: 18, itemStyle: { color: C.green, borderRadius: [0, 8, 8, 0] }, label: { show: true, position: 'right', formatter: '{c}%', color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
  }), [origenes])

  return (
    <Card className="gi-card overflow-hidden border-0 shadow-none">
      <CardHeader className="border-b border-[var(--gi-line)] bg-white px-5 py-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><p className="gi-label">Citas</p><CardTitle className="mt-1 text-lg">Citas del equipo</CardTitle></div>{puedeAlternarEjemplo && <Button type="button" variant={modoDemo ? 'default' : 'outline'} size="sm" onClick={onAlternarEjemplo}><Eye aria-hidden /> {modoDemo ? 'Ver datos reales' : 'Ver ejemplo'}</Button>}</div></CardHeader>
      <ErrorPanel error={error} onReintentar={onReintentar} />
      {cargando && !datos ? <Cargando /> : !datos && error ? null : !datos || datos.resumen.pactadas === 0 ? <Vacio /> : (
        <CardContent className="space-y-4 bg-[var(--gi-canvas)] p-4 sm:p-5">
          <section data-gi-hero className="gi-summary-hero">
            <div><p className="gi-label text-white/65">Citas realizadas</p><p className="mt-2 text-6xl font-bold tracking-[-.05em] tabular-nums text-white">{numero(datos.resumen.realizadas)}</p><p className="mt-2 text-xs text-white/65">de {numero(datos.resumen.pactadas)} pactadas</p></div>
            <div className="grid flex-1 gap-3 sm:grid-cols-3"><div className="gi-hero-metric"><span>Asistencia</span><strong>{pct(datos.resumen.pct_asistencia)}</strong></div><div className="gi-hero-metric"><span>No concretadas</span><strong>{numero(datos.resumen.no_concretadas)}</strong></div><div className="gi-hero-metric"><span>Terminan en cliente</span><strong>{pct(datos.conversion.conversion_contrato_pct)}</strong></div></div>
            {modoDemo && <span className="gi-demo-badge">Datos de ejemplo</span>}
          </section>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
            <Kpi label="Pactadas" value={numero(datos.resumen.pactadas)} detail={`${numero(datos.resumen.programadas_futuras)} próximas`} Icon={CalendarCheck} color={C.blue} />
            <Kpi label="Realizadas" value={numero(datos.resumen.realizadas)} detail={pct(datos.resumen.pct_realizacion)} Icon={UserRoundCheck} color={C.teal} />
            <Kpi label="No concretadas" value={numero(datos.resumen.no_concretadas)} detail={`${numero(datos.resumen.no_show)} no asistieron`} Icon={UserRoundX} color={C.red} />
            <Kpi label="Reprogramadas" value={numero(datos.resumen.reprogramadas)} detail={`${numero(datos.resumen.pendientes_cierre)} sin resultado`} Icon={CalendarClock} color={C.amber} />
            <Kpi label="Terminan en cliente" value={pct(datos.conversion.conversion_contrato_pct)} detail={`${numero(datos.conversion.contratos)} clientes`} Icon={UserRoundCheck} color={C.green} />
          </div>

          <div className="grid gap-4 xl:grid-cols-[minmax(0,1.25fr)_minmax(330px,.85fr)]">
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Presencial vs. virtual</h3><GerenciaEChart tipo="barras" option={opcionModalidades} ariaLabel="Comparación de citas pactadas y realizadas por modalidad" className="mt-3 h-[290px] w-full" /></section>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-1">{modalidades.map((fila) => <section key={fila.modalidad} data-gi-panel className="gi-card p-5"><div className="flex items-start justify-between gap-3"><div><p className="gi-label">{fila.nombre}</p><p className="mt-2 text-4xl font-bold tabular-nums text-[var(--gi-blue)]">{pct(fila.pct_realizacion)}</p><p className="gi-caption mt-1">{numero(fila.realizadas)} de {numero(fila.debieron_ocurrir)}</p></div><div className="text-right"><p className="gi-caption">A clientes</p><strong className="mt-1 block text-xl tabular-nums text-[var(--gi-green)]">{pct(fila.conversion_contrato_pct)}</strong></div></div><div className="mt-4 border-t border-[var(--gi-line)] pt-3"><p className="gi-caption">Capital invertido</p><strong className="mt-1 block text-sm">{money(fila.capital_pen, 'PEN')}</strong>{fila.capital_usd > 0 && <span className="gi-caption">{money(fila.capital_usd, 'USD')}</span>}</div></section>)}</div>
          </div>

          <div className="grid gap-4 xl:grid-cols-2">
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Citas que terminan en cliente</h3><GerenciaEChart tipo="barras" option={opcionOrigen} ariaLabel="Conversión de citas a clientes por origen" className="mt-3 w-full" style={{ height: Math.max(280, origenes.length * 50) }} /></section>
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Resultado final</h3><div className="mt-4 flex flex-wrap gap-2">{datos.resultados.map((fila) => <span key={fila.resultado} className="rounded-full border border-[var(--gi-line)] bg-[var(--gi-soft)] px-3 py-1.5 text-xs"><strong>{numero(fila.cantidad)}</strong> · {textoResultado(fila.resultado)}</span>)}</div></section>
          </div>

          <ResultadosPorVendedor datos={datos} />
        </CardContent>
      )}
    </Card>
  )
}
