import { useMemo, type JSX } from 'react'
import type { EChartsOption } from 'echarts'
import {
  AlertTriangle,
  CalendarCheck,
  CalendarClock,
  Eye,
  RefreshCw,
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
  const visibles = datos.responsables.reduce((total, fila) => ({
    pactadas: total.pactadas + fila.pactadas,
    realizadas: total.realizadas + fila.realizadas,
    pendientes_cierre: total.pendientes_cierre + fila.pendientes_cierre,
  }), { pactadas: 0, realizadas: 0, pendientes_cierre: 0 })
  // Conciliación de conteos recibidos; no recalcula la efectividad ni elimina
  // del total las citas cuyos responsables ya no integran el desglose.
  const fuera = {
    pactadas: datos.resumen.pactadas - visibles.pactadas,
    realizadas: datos.resumen.realizadas - visibles.realizadas,
    pendientes_cierre: datos.resumen.pendientes_cierre - visibles.pendientes_cierre,
  }
  const concilia = Object.values(fuera).every((valor) => valor >= 0)
  return (
    <section data-gi-panel className="gi-card min-w-0 overflow-hidden">
      <div className="border-b border-[var(--gi-line)] bg-[var(--gi-soft)] px-5 py-4"><h3 className="gi-title">Resultados por analista</h3></div>
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El área desplazable necesita foco para navegar con las flechas. */}
      <div className="overflow-x-auto focus-visible:outline-2 focus-visible:outline-offset-2" role="region" aria-label="Resultados por analista" tabIndex={0}>
        <table className="w-full min-w-[680px] text-xs">
          <thead className="text-left text-[10px] uppercase tracking-wide text-[var(--gi-muted)]"><tr><th scope="col" className="px-5 py-3">Analista</th><th scope="col" className="px-3 py-3">Supervisor</th><th scope="col" className="px-3 py-3 text-right">Pactadas</th><th scope="col" className="px-3 py-3 text-right">Realizadas</th><th scope="col" className="px-3 py-3 text-right">Sin resultado</th><th scope="col" className="px-5 py-3 text-right">Realización</th></tr></thead>
          <tbody className="divide-y divide-[var(--gi-line)]">{datos.responsables.map((fila) => {
            const tieneBase = fila.divisor_realizacion != null && fila.debieron_ocurrir != null
              && fila.canceladas_sistema_vencidas != null && fila.canceladas_ajenas_vencidas != null
              && fila.reprogramadas_vencidas != null && fila.programadas_futuras != null
            return (
              <tr key={fila.responsable_id ?? fila.nombre}>
                <th scope="row" className="px-5 py-3 text-left font-semibold">{fila.nombre}</th>
                <td className="px-3 py-3 text-[var(--gi-muted)]">{fila.supervisor_nombre}</td>
                <td className="px-3 py-3 text-right tabular-nums">{numero(fila.pactadas)}</td>
                <td className="px-3 py-3 text-right tabular-nums">{numero(fila.realizadas)}</td>
                <td className="px-3 py-3 text-right font-semibold tabular-nums">{numero(fila.pendientes_cierre)}</td>
                <td className="px-5 py-3 text-right tabular-nums">
                  <strong className="text-[var(--gi-blue)]">{pct(fila.pct_realizacion)}</strong>
                  {tieneBase ? <details className="mt-1 min-w-40 text-[var(--gi-muted)]">
                    <summary className="cursor-pointer focus-visible:outline-2">{numero(fila.realizadas)} de {numero(fila.divisor_realizacion!)} computables</summary>
                    <p className="mt-2 max-w-64 text-left leading-relaxed">{numero(fila.debieron_ocurrir!)} vencidas. Excluidas: {numero(fila.canceladas_sistema_vencidas!)} canceladas por sistema, {numero(fila.canceladas_ajenas_vencidas!)} por otro asesor y {numero(fila.reprogramadas_vencidas!)} reprogramadas. {numero(fila.programadas_futuras!)} próximas dentro del período.</p>
                  </details> : <p className="mt-1 text-[var(--gi-muted)]">Base no disponible</p>}
                </td>
              </tr>
            )
          })}</tbody>
          <tfoot className="border-t border-[var(--gi-line)] bg-[var(--gi-soft)]">
            {concilia && Object.values(fuera).some((valor) => valor > 0) && <tr>
              <th scope="row" colSpan={2} className="px-5 py-3 text-left font-medium">Fuera del desglose actual</th>
              <td className="px-3 py-3 text-right tabular-nums">{numero(fuera.pactadas)}</td>
              <td className="px-3 py-3 text-right tabular-nums">{numero(fuera.realizadas)}</td>
              <td className="px-3 py-3 text-right tabular-nums">{numero(fuera.pendientes_cierre)}</td><td className="px-5 py-3 text-right">—</td>
            </tr>}
            <tr className="font-bold"><th scope="row" colSpan={2} className="px-5 py-3 text-left">Total del período</th><td className="px-3 py-3 text-right tabular-nums">{numero(datos.resumen.pactadas)}</td><td className="px-3 py-3 text-right tabular-nums">{numero(datos.resumen.realizadas)}</td><td className="px-3 py-3 text-right tabular-nums">{numero(datos.resumen.pendientes_cierre)}</td><td className="px-5 py-3 text-right">—</td></tr>
          </tfoot>
        </table>
      </div>
      {!concilia && <p role="alert" className="px-5 py-3 text-sm text-destructive">El desglose no concilia con el total de citas.</p>}
      <p className="border-t border-[var(--gi-line)] px-5 py-3 text-xs text-[var(--gi-muted)]">Cada base descuenta las canceladas por sistema, por otro asesor y las reprogramadas. Las citas fuera del desglose se conservan en el total.</p>
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
    grid: { left: 105, right: 150, top: 8, bottom: 28 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    xAxis: { type: 'value', min: 0, axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' }, splitLine: { lineStyle: { color: C.grid } } },
    yAxis: { type: 'category', inverse: true, data: origenes.map((fila) => fila.origen), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11 } },
    series: [{ type: 'bar', data: origenes.map((fila) => fila.conversion_contrato_pct), barMaxWidth: 18, itemStyle: { color: C.green, borderRadius: [0, 8, 8, 0] }, label: { show: true, position: 'right', formatter: (parametros) => {
      const fila = origenes[parametros.dataIndex]
      return fila ? `${numero(fila.clientes)} de ${numero(fila.leads_reunidos)} · ${pct(fila.conversion_contrato_pct)}` : ''
    }, color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' } }],
  }), [origenes])
  const baseGlobalDisponible = datos?.resumen.divisor_realizacion != null
    && datos.resumen.canceladas_sistema_vencidas != null && datos.resumen.reprogramadas_vencidas != null
  const corte = datos && Number.isFinite(Date.parse(datos.generado_en))
    ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Lima' }).format(new Date(datos.generado_en))
    : 'no disponible'

  return (
    <Card className="gi-card overflow-hidden border-0 shadow-none">
      <CardHeader className="border-b border-[var(--gi-line)] bg-white px-5 py-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><p className="gi-label">Citas</p><CardTitle className="mt-1 text-lg">Citas del equipo</CardTitle></div>{puedeAlternarEjemplo && <Button type="button" variant={modoDemo ? 'default' : 'outline'} size="sm" onClick={onAlternarEjemplo}><Eye aria-hidden /> {modoDemo ? 'Ver datos reales' : 'Ver ejemplo'}</Button>}</div></CardHeader>
      <ErrorPanel error={error} onReintentar={onReintentar} />
      {cargando && !datos ? <Cargando /> : !datos && error ? null : !datos || datos.resumen.pactadas === 0 ? <Vacio /> : (
        <CardContent className="space-y-4 bg-[var(--gi-canvas)] p-4 sm:p-5">
          <section data-gi-hero className="gi-summary-hero">
            <div><p className="gi-label text-white/80">Realización de citas</p><p className="mt-2 text-6xl font-bold tracking-[-.05em] tabular-nums text-white">{pct(datos.resumen.pct_realizacion)}</p><p className="mt-2 text-sm text-white/80">{baseGlobalDisponible ? `${numero(datos.resumen.realizadas)} de ${numero(datos.resumen.divisor_realizacion!)} citas computables` : `${numero(datos.resumen.realizadas)} realizadas · base no disponible`}</p></div>
            <div className="grid flex-1 gap-3 sm:grid-cols-3">
              <div className="gi-hero-metric"><span>Pactadas</span><strong>{numero(datos.resumen.pactadas)}</strong><span className="text-xs">{numero(datos.resumen.programadas_futuras)} próximas dentro del período</span></div>
              <div className="gi-hero-metric"><span>Realizadas</span><strong>{numero(datos.resumen.realizadas)}</strong></div>
              <div className="gi-hero-metric"><span>Vencidas sin resultado</span><strong>{numero(datos.resumen.pendientes_cierre)}</strong></div>
            </div>
            {modoDemo && <span className="gi-demo-badge">Datos de ejemplo</span>}
          </section>

          <details className="gi-card px-5 py-3 text-sm">
            <summary className="cursor-pointer font-semibold focus-visible:outline-2">Ver bases y asistencia</summary>
            <div className="mt-3 grid gap-4 sm:grid-cols-2">
              <div><p className="font-semibold">Realización</p><p className="gi-caption mt-1">Citas realizadas sobre citas vencidas, excluyendo las reprogramadas y canceladas por el sistema.</p>{baseGlobalDisponible && <p className="gi-caption mt-1">{numero(datos.resumen.debieron_ocurrir)} vencidas · {numero(datos.resumen.canceladas_sistema_vencidas!)} canceladas por sistema · {numero(datos.resumen.reprogramadas_vencidas!)} reprogramadas.</p>}</div>
              <div><p className="font-semibold">Asistencia</p><p className="mt-1 text-xl font-bold">{pct(datos.resumen.pct_asistencia)}</p><p className="gi-caption mt-1">{datos.resumen.divisor_asistencia != null ? `${numero(datos.resumen.realizadas)} de ${numero(datos.resumen.divisor_asistencia)} citas con asistencia o inasistencia registrada.` : 'Base no disponible.'} {numero(datos.resumen.no_show)} no asistieron.</p></div>
            </div>
            <p className="gi-caption mt-3">Citas por fecha prevista. Un prospecto puede tener varias citas; las pactadas incluyen las canceladas.</p>
          </details>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <Kpi label="No asistieron" value={numero(datos.resumen.no_show)} detail="Inasistencia registrada" Icon={UserRoundX} color={C.red} />
            <Kpi label="Canceladas por asesor" value={numero(datos.resumen.canceladas)} detail="Dentro del período" Icon={UserRoundX} color={C.red} />
            <Kpi label="Reprogramadas" value={numero(datos.resumen.reprogramadas)} detail="Con una nueva fecha" Icon={CalendarClock} color={C.amber} />
            <Kpi label="Canceladas por sistema" value={numero(datos.resumen.canceladas_sistema)} detail="Incluidas en pactadas" Icon={CalendarClock} color={C.muted} />
          </div>

          <div className="grid gap-4 xl:grid-cols-[minmax(0,1.25fr)_minmax(330px,.85fr)]">
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Presencial vs. virtual</h3><GerenciaEChart tipo="barras" option={opcionModalidades} ariaLabel="Comparación de citas pactadas y realizadas por modalidad" className="mt-3 h-[290px] w-full" /></section>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-1">{modalidades.map((fila) => {
              const detalleRealizacionDisponible = fila.divisor_realizacion != null
                && fila.canceladas_sistema_vencidas != null
                && fila.reprogramadas_vencidas != null
              return (
                <section key={fila.modalidad} data-gi-panel className="gi-card p-5">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="gi-label">{fila.nombre}</p>
                      <p className="gi-caption mt-1">Realización</p>
                      <p className="mt-2 text-4xl font-bold tabular-nums text-[var(--gi-blue)]">{pct(fila.pct_realizacion)}</p>
                      {detalleRealizacionDisponible ? (
                        <>
                          <p className="gi-caption mt-1">{numero(fila.realizadas)} realizadas{fila.divisor_realizacion === 0 ? ' · sin citas computables' : ` de ${numero(fila.divisor_realizacion)} computables`}</p>
                          <p className="gi-caption mt-1">Excluidas: {numero(fila.canceladas_sistema_vencidas)} canceladas por sistema · {numero(fila.reprogramadas_vencidas)} reprogramadas</p>
                        </>
                      ) : (
                        <>
                          <p className="gi-caption mt-1">{numero(fila.realizadas)} realizadas</p>
                          <p className="gi-caption mt-1">Base y exclusiones no disponibles.</p>
                        </>
                      )}
                    </div>
                    <div className="text-right"><p className="gi-caption">Con cierre posterior</p><strong className="mt-1 block text-xl tabular-nums text-[var(--gi-green)]">{numero(fila.clientes)} de {numero(fila.leads_reunidos)}</strong><p className="gi-caption">prospectos atendidos</p></div>
                  </div>
                  <div className="mt-4 border-t border-[var(--gi-line)] pt-3"><p className="gi-caption">Capital asociado a estos cierres</p><strong className="mt-1 block text-sm">{money(fila.capital_pen, 'PEN')}</strong>{fila.capital_usd > 0 && <span className="gi-caption">{money(fila.capital_usd, 'USD')}</span>}<p className="gi-caption mt-1">Acumulado, sin recorte por fecha.</p></div>
                </section>
              )
            })}</div>
          </div>

          <div className="grid gap-4 xl:grid-cols-2">
            <section data-gi-panel className="gi-card p-5">
              <h3 className="gi-title">Cierres posteriores a citas</h3>
              <p className="mt-2 text-lg font-bold">{numero(datos.conversion.clientes)} de {numero(datos.conversion.leads_reunidos)} prospectos atendidos</p>
              {datos.conversion.leads_con_cierre_previo != null && datos.conversion.leads_con_cierre_previo > 0 && <p className="mt-3 rounded-lg border border-[var(--gi-line)] bg-[var(--gi-soft)] px-3 py-2 text-sm">Con cierre anterior a la hora programada: <strong>{numero(datos.conversion.leads_con_cierre_previo)}</strong>. Se muestran aparte.</p>}
              {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Permite recorrer con teclado el gráfico en pantallas pequeñas. */}
              <div role="region" aria-label="Gráfico de cierres posteriores por origen" tabIndex={0} className="mt-3 overflow-x-auto focus-visible:outline-2 focus-visible:outline-offset-2"><GerenciaEChart tipo="barras" option={opcionOrigen} ariaLabel="Cierres posteriores a citas por origen" className="min-w-[430px] w-full" style={{ height: Math.max(220, origenes.length * 50) }} /></div>
              {origenes.filter((fila) => fila.conversion_contrato_pct == null).map((fila) => <p key={fila.origen} className="gi-caption">{fila.origen}: — (sin base para calcular)</p>)}
              <details className="mt-3 border-t border-[var(--gi-line)] pt-3 text-sm"><summary className="cursor-pointer font-semibold focus-visible:outline-2">Qué cierres y capital incluye</summary><p className="gi-caption mt-2">Cierres registrados desde la hora programada de la última cita realizada de cada prospecto. El seguimiento incluye cierres posteriores al período. Los cierres anteriores se buscan desde el inicio del período. El capital reúne los importes asociados a esos cierres, en la moneda del prospecto y sin recorte por fecha.</p>{datos.conversion.leads_con_cierre_previo == null && <p className="gi-caption mt-2">El detalle de cierres anteriores no está disponible.</p>}<p className="gi-caption mt-2">Seguimiento al {corte} (Lima).</p></details>
            </section>
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Resultado registrado de la cita</h3><div className="mt-4 flex flex-wrap gap-2">{datos.resultados.map((fila) => <span key={fila.resultado} className="rounded-full border border-[var(--gi-line)] bg-[var(--gi-soft)] px-3 py-1.5 text-xs"><strong>{numero(fila.cantidad)}</strong> · {textoResultado(fila.resultado)}</span>)}</div></section>
          </div>

          <ResultadosPorVendedor datos={datos} />
        </CardContent>
      )}
    </Card>
  )
}
