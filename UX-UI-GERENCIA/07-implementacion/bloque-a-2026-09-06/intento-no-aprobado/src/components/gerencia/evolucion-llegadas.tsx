import { useMemo, useState } from 'react'
import type { EChartsOption } from 'echarts'
import { GerenciaEChart } from './echart-lazy'
import { ValoresGrafico } from './valores-grafico'
import { fmtFecha, numero } from '@/lib/format'

interface PuntoLlegada { desde: string; hasta: string; leads: number; clientes: number }
function fechaCorta(fecha: string) { return fmtFecha(fecha).replace(/\s+\d{4}$/, '') }
export function EvolucionLlegadas({ puntos }: { puntos: PuntoLlegada[] | null | undefined }) {
  const [serie, setSerie] = useState<'ambas' | 'llegadas' | 'cerrados'>('ambas')
  const opcion = useMemo<EChartsOption>(() => ({
    animationDuration: 500, animationDurationUpdate: 350,
    grid: { left: 34, right: 12, top: 26, bottom: 32 },
    tooltip: { trigger: 'axis', confine: true, axisPointer: { type: 'shadow' } },
    xAxis: { type: 'category', data: (puntos ?? []).map((p) => p.desde === p.hasta ? fechaCorta(p.desde) : p.desde.slice(0, 7) === p.hasta.slice(0, 7) ? `${p.desde.slice(8)}–${fechaCorta(p.hasta)}` : `${fechaCorta(p.desde)}–${fechaCorta(p.hasta)}`), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { color: '#64748b', fontFamily: 'IBM Plex Sans', fontSize: 10, hideOverlap: true } },
    yAxis: { type: 'value', min: 0, minInterval: 1, axisLabel: { color: '#64748b', fontSize: 10 }, splitLine: { lineStyle: { color: '#eef2f6' } } },
    series: [
      { id: 'llegadas', name: 'Llegadas', type: 'bar', data: (puntos ?? []).map((p) => serie === 'cerrados' ? null : p.leads), barMaxWidth: 48, itemStyle: { color: '#2563eb', borderRadius: [7, 7, 0, 0] }, label: { show: true, position: 'top', color: '#16334d', fontFamily: 'IBM Plex Sans', fontWeight: 600 } },
      { id: 'cerrados', name: 'Cerrados', type: 'bar', data: (puntos ?? []).map((p) => serie === 'llegadas' ? null : p.clientes), barMaxWidth: 48, itemStyle: { color: '#16a34a', borderRadius: [7, 7, 0, 0] }, label: { show: true, position: 'top', color: '#16334d', fontFamily: 'IBM Plex Sans', fontWeight: 600 } },
    ],
  }), [puntos, serie])
  return <section data-gi-panel className="gi-card gi-evolution p-4">
    <div className="gi-panel-heading"><h2 className="gi-title">Evolución de llegadas y cierres</h2></div>
    <p className="gi-caption mt-2">Llegadas y leads que cerraron, agrupados por su fecha de llegada.</p>
    <div className="gi-series-controls" role="group" aria-label="Series de la evolución">
      {(['ambas', 'llegadas', 'cerrados'] as const).map((valor) => <button key={valor} type="button" aria-pressed={serie === valor} onClick={() => setSerie(valor)}>{valor !== 'ambas' && <span className={`gi-series-dot gi-dot-${valor}`} aria-hidden="true" />}{valor === 'ambas' ? 'Ambas' : valor === 'llegadas' ? 'Llegadas' : 'Cerrados'}</button>)}
    </div>
    {puntos == null ? <p className="gi-chart-empty">Tendencia no disponible</p> : puntos.length === 0 ? <p className="gi-chart-empty">Aún no hay semanas para mostrar</p> : <>
      <GerenciaEChart tipo="barras" option={opcion} ariaLabel="Leads por semana de llegada y resultados" className="gi-evolution-chart w-full" />
      <p className="gi-caption">Barras desde cero · Cerrados atribuidos a su llegada.</p>
      <ValoresGrafico titulo="Llegadas y cerrados por semana de llegada" columnas={['Período', 'Llegadas', 'Cerrados']} filas={puntos.map((p) => [p.desde === p.hasta ? fmtFecha(p.desde) : `${fmtFecha(p.desde)} – ${fmtFecha(p.hasta)}`, numero(p.leads), numero(p.clientes)])} />
    </>}
  </section>
}
