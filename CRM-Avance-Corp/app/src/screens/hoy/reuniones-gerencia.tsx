import { useMemo, useRef, type JSX, type RefObject } from 'react'
import type { EChartsOption } from 'echarts'
import {
  AlertTriangle,
  CalendarCheck,
  Eye,
  RefreshCw,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import { AtencionCitas } from '@/components/gerencia/atencion-citas'
import { IndicadorGerencia } from '@/components/gerencia/indicador-gerencia'
import { money, numero, fmtFecha } from '@/lib/format'
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

function ResultadosPorVendedor({ datos, destino }: { datos: MetricasReuniones; destino: RefObject<HTMLElement | null> }): JSX.Element {
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
    <section ref={destino} id="citas-resultados-analistas" tabIndex={-1} aria-label="Resultados por analista" data-gi-panel className="gi-card min-w-0 scroll-mt-4 overflow-hidden focus-visible:ring-[3px] focus-visible:ring-accent/40">
      <div className="border-b border-[var(--gi-line)] bg-[var(--gi-soft)] px-5 py-4"><h3 className="gi-title">Resultados por analista</h3></div>
      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El área desplazable necesita foco para navegar con las flechas. */}
      <div className="hidden overflow-x-auto focus-visible:outline-2 focus-visible:outline-offset-2 md:block" role="region" aria-label="Tabla de resultados por analista" tabIndex={0}>
        <table className="w-full min-w-[680px] text-xs">
          <caption className="sr-only">Citas por analista en el período consultado</caption><thead className="text-left text-xs text-[var(--muted-foreground-strong)]"><tr><th scope="col" className="px-5 py-3">Analista</th><th scope="col" className="px-3 py-3">Supervisor</th><th scope="col" className="px-3 py-3 text-right">Pactadas</th><th scope="col" className="px-3 py-3 text-right">Realizadas</th><th scope="col" className="px-3 py-3 text-right">Sin resultado</th><th scope="col" className="px-5 py-3 text-right">Realización</th></tr></thead>
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
      <ul className="divide-y divide-[var(--gi-line)] md:hidden" aria-label="Citas por analista">{datos.responsables.map((fila) => <li key={fila.responsable_id ?? fila.nombre} className="space-y-3 p-4"><div><h4 className="text-sm font-semibold">{fila.nombre}</h4><p className="text-xs text-[var(--muted-foreground-strong)]">{fila.supervisor_nombre}</p></div><dl className="grid grid-cols-2 gap-3 text-xs">{[['Pactadas', numero(fila.pactadas)], ['Realizadas', numero(fila.realizadas)], ['Sin resultado', numero(fila.pendientes_cierre)], ['Realización', pct(fila.pct_realizacion)]].map(([etiqueta, valor]) => <div key={etiqueta}><dt className="text-[var(--muted-foreground-strong)]">{etiqueta}</dt><dd className="mt-1 text-sm font-semibold tabular-nums">{valor}</dd></div>)}</dl><p className="text-xs text-[var(--gi-muted)]">{fila.divisor_realizacion == null ? 'Base no disponible' : `${numero(fila.realizadas)} de ${numero(fila.divisor_realizacion)} computables`}</p></li>)}</ul>
      <div className="space-y-2 border-t border-[var(--gi-line)] p-4 text-xs md:hidden">{concilia && Object.values(fuera).some((valor) => valor > 0) && <p>Fuera del desglose actual: {numero(fuera.pactadas)} pactadas · {numero(fuera.realizadas)} realizadas · {numero(fuera.pendientes_cierre)} sin resultado.</p>}<p className="font-semibold">Total del período: {numero(datos.resumen.pactadas)} pactadas · {numero(datos.resumen.realizadas)} realizadas · {numero(datos.resumen.pendientes_cierre)} sin resultado.</p></div>
      {!concilia && <p role="alert" className="px-5 py-3 text-sm text-destructive">El desglose no concilia con el total de citas.</p>}
      <p className="border-t border-[var(--gi-line)] px-5 py-3 text-xs text-[var(--gi-muted)]">Cada base descuenta las canceladas por sistema, por otro asesor y las reprogramadas. Las citas fuera del desglose se conservan en el total.</p>
    </section>
  )
}

export function ReunionesGerenciaPanel({ datos, cargando, error, modoDemo, puedeAlternarEjemplo, onAlternarEjemplo, onReintentar }: ReunionesGerenciaPanelProps): JSX.Element {
  const resultadosRef = useRef<HTMLElement>(null)
  const verResponsables = () => { resultadosRef.current?.focus(); resultadosRef.current?.scrollIntoView?.({ block: 'start' }) }
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
    <Card className="gap-4 border-0 bg-transparent py-0 shadow-none">
      <CardHeader className="px-0 py-0"><div className="flex flex-wrap items-center justify-between gap-3"><div className="space-y-2"><CardTitle className="text-2xl font-bold leading-8 tracking-[-.025em] text-[var(--gi-navy)]">Citas del equipo</CardTitle><p className="text-xs leading-[18px] text-[var(--muted-foreground-strong)]">Citas por fecha prevista. Un prospecto puede tener varias citas; las pactadas incluyen las canceladas.{modoDemo ? ' Datos de ejemplo.' : ''}</p></div>{puedeAlternarEjemplo && <Button type="button" variant={modoDemo ? 'default' : 'outline'} className="min-h-11" onClick={onAlternarEjemplo}><Eye aria-hidden /> {modoDemo ? 'Ver datos reales' : 'Ver ejemplo'}</Button>}</div></CardHeader>
      <ErrorPanel error={error} onReintentar={onReintentar} />
      {datos && (cargando || error) && <p role="status" className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">{cargando ? 'Actualizando citas.' : 'No se pudo confirmar la actualización.'} Las cifras visibles corresponden a la última respuesta del {fmtFecha(datos.periodo.desde)} al {fmtFecha(datos.periodo.hasta)}.</p>}
      {cargando && !datos ? <Cargando /> : !datos && error ? null : !datos ? <CardContent className="space-y-3 px-0"><p role="status">Datos de citas no disponibles. Una respuesta ausente no demuestra que el período esté vacío.</p><Button variant="outline" onClick={onReintentar}>Reintentar</Button></CardContent> : datos.resumen.pactadas === 0 ? <Vacio /> : (
        <CardContent className="space-y-4 px-0">
          <div className="flex flex-col gap-4">
            <section data-gi-hero className="order-2 grid items-start gap-4 sm:order-1 sm:grid-cols-2 xl:grid-cols-4">
              <IndicadorGerencia etiqueta="Realización de citas" valor={pct(datos.resumen.pct_realizacion)} contexto={baseGlobalDisponible ? `${numero(datos.resumen.realizadas)} de ${numero(datos.resumen.divisor_realizacion!)} citas computables` : `${numero(datos.resumen.realizadas)} realizadas · base no disponible`} />
              <IndicadorGerencia etiqueta="Pactadas" valor={numero(datos.resumen.pactadas)} contexto={`${numero(datos.resumen.programadas_futuras)} próximas dentro del período`} />
              <IndicadorGerencia etiqueta="Realizadas" valor={numero(datos.resumen.realizadas)} contexto="Con resultado registrado" />
              <IndicadorGerencia etiqueta="Vencidas sin resultado" valor={numero(datos.resumen.pendientes_cierre)} contexto="Pendientes de registrar su resultado" />
            </section>
            <div className="order-1 sm:order-2"><AtencionCitas datos={datos} cargando={cargando} error={error} onVerResponsables={verResponsables} /></div>
          </div>

          <details className="gi-card px-5 py-3 text-sm">
            <summary className="cursor-pointer font-semibold focus-visible:outline-2">Ver bases y asistencia</summary>
            <div className="mt-3 grid gap-4 sm:grid-cols-2">
              <div><p className="font-semibold">Realización</p><p className="gi-caption mt-1">Citas realizadas sobre citas vencidas, excluyendo las reprogramadas y canceladas por el sistema.</p>{baseGlobalDisponible && <p className="gi-caption mt-1">{numero(datos.resumen.debieron_ocurrir)} vencidas · {numero(datos.resumen.canceladas_sistema_vencidas!)} canceladas por sistema · {numero(datos.resumen.reprogramadas_vencidas!)} reprogramadas.</p>}</div>
              <div><p className="font-semibold">Asistencia</p><p className="mt-1 text-xl font-bold">{pct(datos.resumen.pct_asistencia)}</p><p className="gi-caption mt-1">{datos.resumen.divisor_asistencia != null ? `${numero(datos.resumen.realizadas)} de ${numero(datos.resumen.divisor_asistencia)} citas con asistencia o inasistencia registrada.` : 'Base no disponible.'} {numero(datos.resumen.no_show)} no asistieron.</p></div>
            </div>
          </details>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <IndicadorGerencia etiqueta="No asistieron" valor={numero(datos.resumen.no_show)} contexto="Inasistencia registrada" />
            <IndicadorGerencia etiqueta="Canceladas por asesor" valor={numero(datos.resumen.canceladas)} contexto="Dentro del período" />
            <IndicadorGerencia etiqueta="Reprogramadas" valor={numero(datos.resumen.reprogramadas)} contexto="Con una nueva fecha" />
            <IndicadorGerencia etiqueta="Canceladas por sistema" valor={numero(datos.resumen.canceladas_sistema)} contexto="Incluidas en pactadas" />
          </div>

          <ResultadosPorVendedor datos={datos} destino={resultadosRef} />
          <div className="grid gap-4 xl:grid-cols-[minmax(0,1.25fr)_minmax(330px,.85fr)]">
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Presencial vs. virtual</h3><GerenciaEChart tipo="barras" option={opcionModalidades} ariaLabel="Comparación de citas pactadas y realizadas por modalidad" className="mt-3 h-[290px] w-full" /><details className="mt-3 text-xs"><summary className="w-fit cursor-pointer py-2 font-semibold text-[var(--gi-blue)]">Ver valores por modalidad</summary><table className="w-full text-left"><caption className="sr-only">Valores de citas por modalidad</caption><thead><tr><th scope="col" className="p-2">Modalidad</th><th scope="col" className="p-2">Pactadas</th><th scope="col" className="p-2">Realizadas</th></tr></thead><tbody>{modalidades.map((fila) => <tr key={fila.modalidad}><th scope="row" className="p-2 font-medium">{fila.nombre}</th><td className="p-2">{numero(fila.pactadas)}</td><td className="p-2">{numero(fila.realizadas)}</td></tr>)}</tbody></table></details></section>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-1">{modalidades.map((fila) => {
              const detalleRealizacionDisponible = fila.divisor_realizacion != null
                && fila.canceladas_sistema_vencidas != null
                && fila.reprogramadas_vencidas != null
              return (
                <section key={fila.modalidad} aria-label={`Resultados de citas ${fila.nombre}`} data-gi-panel className="gi-card p-5">
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
              <details className="mt-3 text-xs"><summary className="w-fit cursor-pointer py-2 font-semibold text-[var(--gi-blue)]">Ver valores por origen</summary><table className="w-full text-left"><caption className="sr-only">Cierres posteriores a citas por origen</caption><thead><tr><th scope="col" className="p-2">Origen</th><th scope="col" className="p-2">Conversión</th></tr></thead><tbody>{origenes.map((fila) => <tr key={fila.origen}><th scope="row" className="p-2 font-medium">{fila.origen}</th><td className="p-2">{pct(fila.conversion_contrato_pct)}</td></tr>)}</tbody></table></details>
              <details className="mt-3 border-t border-[var(--gi-line)] pt-3 text-sm"><summary className="cursor-pointer font-semibold focus-visible:outline-2">Qué cierres y capital incluye</summary><p className="gi-caption mt-2">Cierres registrados desde la hora programada de la última cita realizada de cada prospecto. El seguimiento incluye cierres posteriores al período. Los cierres anteriores se buscan desde el inicio del período. El capital reúne los importes asociados a esos cierres, en la moneda del prospecto y sin recorte por fecha.</p>{datos.conversion.leads_con_cierre_previo == null && <p className="gi-caption mt-2">El detalle de cierres anteriores no está disponible.</p>}<p className="gi-caption mt-2">Seguimiento al {corte} (Lima).</p></details>
            </section>
            <section data-gi-panel className="gi-card p-5"><h3 className="gi-title">Resultado registrado de la cita</h3><div className="mt-4 flex flex-wrap gap-2">{datos.resultados.map((fila) => <span key={fila.resultado} className="rounded-full border border-[var(--gi-line)] bg-[var(--gi-soft)] px-3 py-1.5 text-xs"><strong>{numero(fila.cantidad)}</strong> · {textoResultado(fila.resultado)}</span>)}</div></section>
          </div>

        </CardContent>
      )}
    </Card>
  )
}
