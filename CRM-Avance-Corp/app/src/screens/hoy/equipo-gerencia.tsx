import { useMemo, type CSSProperties, type JSX } from 'react'
import type { EChartsOption } from 'echarts'
import { Target, UserRoundCheck, UsersRound } from 'lucide-react'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import { numero } from '@/lib/format'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import {
  adaptarConversionVendedores,
  clasificarRankingConversion,
  type ConversionVendedorAdaptada,
} from '@/lib/conversion-vendedores'
import type { MetricasConversiones } from '@/lib/metricas-conversiones'
import type { Miembro } from '@/lib/tipos'

function pct(valor: number | null): string {
  return valor == null ? '—' : `${numero(valor, 1)}%`
}

export function EquipoGerenciaPanel({
  datos,
  conversiones,
  miembros,
}: {
  datos: MetricasConversiones | null | undefined
  conversiones: ConversionEquipoVendedor[]
  miembros: Miembro[]
}): JSX.Element {
  const adaptada = useMemo(
    () => adaptarConversionVendedores(datos, conversiones),
    [conversiones, datos],
  )
  const ranking = useMemo(
    () => clasificarRankingConversion(adaptada.vendedores),
    [adaptada.vendedores],
  )
  const filas = ranking.conPuesto
  const detalleCompleto = adaptada.responsablesDisponibles
    && adaptada.vendedores.every((fila) => fila.detalle != null)
  const leads = detalleCompleto
    ? adaptada.vendedores.reduce((total, fila) => total + (fila.detalle?.leads ?? 0), 0)
    : null
  const clientes = detalleCompleto
    ? adaptada.vendedores.reduce((total, fila) => total + (fila.detalle?.clientes ?? 0), 0)
    : null
  const conversion = leads != null && clientes != null && leads > 0
    ? (clientes / leads) * 100
    : null
  const vendedores = adaptada.vendedores.length
  const supervisores = miembros.filter((m) => m.activo && m.rol_crm === 'supervisor').length
  const kpis = [
    { label: 'Vendedores', valor: numero(vendedores), icon: UsersRound, color: C.blue },
    { label: 'Supervisores', valor: numero(supervisores), icon: Target, color: C.amber },
    { label: 'Clientes', valor: clientes == null ? '—' : numero(clientes), icon: UserRoundCheck, color: C.green },
    { label: 'Conversión del equipo', valor: pct(conversion), icon: Target, color: C.teal },
  ]

  const opcion = useMemo<EChartsOption>(() => ({
    animationDuration: 600,
    grid: { left: 132, right: 58, top: 8, bottom: 28 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    xAxis: {
      type: 'value',
      min: 0,
      axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' },
      splitLine: { lineStyle: { color: C.grid } },
    },
    yAxis: {
      type: 'category',
      inverse: true,
      data: filas.map((fila) => fila.nombre),
      axisTick: { show: false },
      axisLine: { show: false },
      axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11, width: 120, overflow: 'truncate' },
    },
    series: [{
      type: 'bar',
      data: filas.map((fila) => fila.detalle.conversion_pct),
      barMaxWidth: 16,
      itemStyle: { color: C.teal, borderRadius: [0, 8, 8, 0] },
      label: { show: true, position: 'right', formatter: '{c}%', color: C.navy, fontWeight: 600, fontFamily: 'IBM Plex Sans' },
    }],
  }), [filas])

  const grupos = useMemo(() => {
    const mapa = new Map<string, ConversionVendedorAdaptada[]>()
    for (const fila of adaptada.vendedores) {
      mapa.set(fila.supervisorNombre, [...(mapa.get(fila.supervisorNombre) ?? []), fila])
    }
    return [...mapa.entries()].sort(([a], [b]) => a.localeCompare(b, 'es'))
  }, [adaptada.vendedores])

  if (adaptada.vendedores.length === 0) {
    return <div className="gi-card py-14 text-center"><UsersRound className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">No hay vendedores para mostrar</p></div>
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {kpis.map(({ label, valor, icon: Icono, color }) => {
          return <div key={label} data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as CSSProperties}><div className="flex justify-between"><p className="gi-label">{label}</p><Icono className="size-4" style={{ color }} /></div><p className="mt-2 text-3xl font-bold tabular-nums">{valor}</p></div>
        })}
      </div>

      {filas.length > 0 && (
        <section data-gi-panel className="gi-card p-5">
          <div className="flex items-center justify-between"><h2 className="gi-title">Conversión por vendedor</h2><span className="gi-caption">{numero(filas.length)} vendedores con leads</span></div>
          <GerenciaEChart tipo="barras" option={opcion} ariaLabel="Conversión a clientes por vendedor" className="mt-3 w-full" style={{ height: Math.max(290, filas.length * 38) }} />
        </section>
      )}

      <div className="space-y-4">
        {grupos.map(([supervisor, vendedoresGrupo]) => {
          const grupoDisponible = vendedoresGrupo.every((fila) => fila.detalle != null)
          const totalLeads = grupoDisponible
            ? vendedoresGrupo.reduce((n, fila) => n + (fila.detalle?.leads ?? 0), 0)
            : null
          const totalClientes = grupoDisponible
            ? vendedoresGrupo.reduce((n, fila) => n + (fila.detalle?.clientes ?? 0), 0)
            : null
          const conversionGrupo = totalLeads != null && totalClientes != null && totalLeads > 0
            ? (totalClientes / totalLeads) * 100
            : null
          return (
            <section key={supervisor} data-gi-panel className="gi-card overflow-hidden">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--gi-line)] bg-[var(--gi-soft)] px-5 py-4">
                <div><h2 className="gi-title">{supervisor}</h2><p className="gi-caption mt-1">{numero(vendedoresGrupo.length)} vendedores</p></div>
                <div className="text-right"><strong className="text-xl tabular-nums text-[var(--gi-blue)]">{pct(conversionGrupo)}</strong><p className="gi-caption">{totalClientes == null ? 'Datos no disponibles' : `${numero(totalClientes)} clientes`}</p></div>
              </div>
              <div className="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
                {vendedoresGrupo.map((fila) => (
                  <div key={fila.vendedorId} className="rounded-xl border border-[var(--gi-line)] bg-white p-4">
                    <div className="flex items-start justify-between gap-3"><div><p className="text-sm font-semibold">{fila.nombre}</p><p className="gi-caption mt-1">{fila.detalle == null ? 'Datos no disponibles' : `${numero(fila.detalle.leads)} leads · ${numero(fila.detalle.clientes)} clientes`}</p></div><strong className="tabular-nums text-[var(--gi-blue)]">{fila.estadoConversion === 'sin_muestra' ? 'Sin muestra' : fila.estadoConversion === 'indisponible' ? 'No disponible' : pct(fila.detalle?.conversion_pct ?? null)}</strong></div>
                    <div className="gi-track mt-3"><div className="gi-fill" style={{ width: `${Math.min(100, fila.detalle?.conversion_pct ?? 0)}%`, background: C.teal }} /></div>
                  </div>
                ))}
              </div>
            </section>
          )
        })}
      </div>
    </div>
  )
}
