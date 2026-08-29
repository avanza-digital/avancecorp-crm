import { useMemo, type CSSProperties, type JSX } from 'react'
import type { EChartsOption } from 'echarts'
import { Inbox, Target, UserRoundCheck, UsersRound } from 'lucide-react'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import { numero, porcentajeConversionCanonica } from '@/lib/format'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import {
  totalConversionPublicable,
  type ConversionMensual,
} from '@/lib/conversion-mensual'
import {
  adaptarConversionMensual,
  clasificarRankingConversion,
  type ConversionVendedorAdaptada,
  type DetalleConversionMensual,
} from '@/lib/conversion-vendedores'
import type { Miembro } from '@/lib/tipos'

function pct(valor: number | null): string {
  return porcentajeConversionCanonica(valor)
}

/** Rótulo corto de tarjeta para los estados sin % — jamás un «0 %» inventado. */
function etiquetaEstado(fila: ConversionVendedorAdaptada<DetalleConversionMensual>): string | null {
  switch (fila.estadoConversion) {
    case 'sin_muestra': return 'Sin muestra'
    case 'solo_referidos': return 'Solo referidos'
    case 'solo_arrastre': return 'Solo arrastre'
    case 'indisponible': return 'No disponible'
    default: return null
  }
}

export function EquipoGerenciaPanel({
  conversionMensual,
  conversiones,
  miembros,
}: {
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`) — única
   * fuente de los números de este panel. Tri-estado: `undefined` consultando,
   * `null` no disponible; ambos degradan a «—»/«No disponible» (fail-closed),
   * nunca a ceros ni a la fórmula vieja del rango.
   */
  conversionMensual: ConversionMensual | null | undefined
  conversiones: ConversionEquipoVendedor[]
  miembros: Miembro[]
}): JSX.Element {
  const adaptada = useMemo(
    () => adaptarConversionMensual(conversionMensual ?? null, conversiones),
    [conversionMensual, conversiones],
  )
  const ranking = useMemo(
    () => clasificarRankingConversion(adaptada.vendedores),
    [adaptada.vendedores],
  )
  // La gráfica compara %: solo entran los MEDIBLES (solo_arrastre compite en el
  // ranking pero no tiene % que barra pueda representar).
  const medibles = ranking.conPuesto.filter((fila) => fila.detalle.conversion_pct != null)
  // Los agregados del equipo los sirve la RPC — aquí no se divide nada global.
  const total = totalConversionPublicable(conversionMensual)
  const recibidos = total?.divisor ?? null
  const cierres = total == null ? null : total.cierres_no_referidos + total.cierres_referidos
  const conversion = total?.conversion_pct ?? null
  const vendedores = adaptada.vendedores.length
  const supervisores = miembros.filter((m) => m.activo && m.rol_crm === 'supervisor').length
  const kpis = [
    { label: 'Analistas', valor: numero(vendedores), icon: UsersRound, color: C.blue },
    { label: 'Supervisores', valor: numero(supervisores), icon: Target, color: C.amber },
    { label: 'Recibidos del mes', valor: recibidos == null ? '—' : numero(recibidos), icon: Inbox, color: C.navy },
    { label: 'Cierres del mes', valor: cierres == null ? '—' : numero(cierres), icon: UserRoundCheck, color: C.green },
    { label: 'Conversión del mes', valor: pct(conversion), icon: Target, color: C.teal },
  ]

  const opcion = useMemo<EChartsOption>(() => ({
    animationDuration: 600,
    grid: { left: 132, right: 58, top: 8, bottom: 28 },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      valueFormatter: (valor) => porcentajeConversionCanonica(
        typeof valor === 'number' ? valor : null,
      ),
    },
    xAxis: {
      type: 'value',
      min: 0,
      axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' },
      splitLine: { lineStyle: { color: C.grid } },
    },
    yAxis: {
      type: 'category',
      inverse: true,
      data: medibles.map((fila) => fila.nombre),
      axisTick: { show: false },
      axisLine: { show: false },
      axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11, width: 120, overflow: 'truncate' },
    },
    series: [{
      type: 'bar',
      data: medibles.map((fila) => fila.detalle.conversion_pct),
      barMaxWidth: 16,
      itemStyle: { color: C.teal, borderRadius: [0, 8, 8, 0] },
      label: {
        show: true,
        position: 'right',
        formatter: (parametros) => porcentajeConversionCanonica(
          typeof parametros.value === 'number' ? parametros.value : null,
        ),
        color: C.navy,
        fontWeight: 600,
        fontFamily: 'IBM Plex Sans',
      },
    }],
  }), [medibles])

  const grupos = useMemo(() => {
    const mapa = new Map<string, ConversionVendedorAdaptada<DetalleConversionMensual>[]>()
    for (const fila of adaptada.vendedores) {
      mapa.set(fila.supervisorNombre, [...(mapa.get(fila.supervisorNombre) ?? []), fila])
    }
    return [...mapa.entries()].sort(([a], [b]) => a.localeCompare(b, 'es'))
  }, [adaptada.vendedores])

  if (adaptada.vendedores.length === 0) {
    return <div className="gi-card py-14 text-center"><UsersRound className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">No hay analistas para mostrar</p></div>
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        {kpis.map(({ label, valor, icon: Icono, color }) => {
          return <div key={label} data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as CSSProperties}><div className="flex justify-between"><p className="gi-label">{label}</p><Icono className="size-4" style={{ color }} /></div><p className="mt-2 text-3xl font-bold tabular-nums">{valor}</p></div>
        })}
      </div>

      {medibles.length > 0 && (
        <section data-gi-panel className="gi-card p-5">
          <div className="flex items-center justify-between"><h2 className="gi-title">Conversión por analista</h2><span className="gi-caption">{numero(medibles.length)} {medibles.length === 1 ? 'analista medible' : 'analistas medibles'} este mes</span></div>
          <GerenciaEChart tipo="barras" option={opcion} ariaLabel="Conversión a clientes por analista" className="mt-3 w-full" style={{ height: Math.max(290, medibles.length * 38) }} />
        </section>
      )}

      <div className="space-y-4">
        {grupos.map(([supervisor, vendedoresGrupo]) => {
          const grupoDisponible = vendedoresGrupo.every((fila) => fila.detalle != null)
          // F3: el navegador ya no divide el % del grupo (era la última
          // aritmética de conversión que quedaba aquí). El servidor no sirve
          // todavía una cifra por supervisor con el núcleo — hasta que exista,
          // la cabecera enseña los enteros SERVIDOS (cierres y recibidos son
          // sumas de lo que manda la RPC), no un % fabricado.
          const totalRecibidos = grupoDisponible
            ? vendedoresGrupo.reduce((n, fila) => n + (fila.detalle?.divisor ?? 0), 0)
            : null
          const totalCierres = grupoDisponible
            ? vendedoresGrupo.reduce((n, fila) => n + (fila.detalle?.clientes ?? 0), 0)
            : null
          const maximoGrupo = Math.max(1, ...vendedoresGrupo.map((fila) => fila.detalle?.conversion_pct ?? 0))
          return (
            <section key={supervisor} data-gi-panel className="gi-card overflow-hidden">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--gi-line)] bg-[var(--gi-soft)] px-5 py-4">
                <div><h2 className="gi-title">{supervisor}</h2><p className="gi-caption mt-1">{numero(vendedoresGrupo.length)} {vendedoresGrupo.length === 1 ? 'analista' : 'analistas'}</p></div>
                <div className="text-right"><strong className="text-xl tabular-nums text-[var(--gi-blue)]">{totalCierres == null ? '—' : numero(totalCierres)}</strong><p className="gi-caption">{totalCierres == null || totalRecibidos == null ? 'Datos no disponibles' : `cierres del mes · ${numero(totalRecibidos)} recibidos`}</p></div>
              </div>
              <div className="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
                {vendedoresGrupo.map((fila) => {
                  const conversionFila = fila.detalle?.conversion_pct ?? null
                  return (
                    <div key={fila.vendedorId} className="rounded-xl border border-[var(--gi-line)] bg-white p-4">
                      <div className="flex items-start justify-between gap-3"><div><p className="text-sm font-semibold">{fila.nombre}</p><p className="gi-caption mt-1">{fila.detalle == null ? 'Datos no disponibles' : `${numero(fila.detalle.leads)} recibidos · ${numero(fila.detalle.clientes)} cierres`}</p></div><strong className="tabular-nums text-[var(--gi-blue)]">{etiquetaEstado(fila) ?? pct(conversionFila)}</strong></div>
                      {/* Barra RELATIVA al máximo del grupo: un 120 % no se disfraza de 100. */}
                      <div className="gi-track mt-3"><div className="gi-fill" style={{ width: `${conversionFila == null ? 0 : (conversionFila / maximoGrupo) * 100}%`, background: C.teal }} /></div>
                    </div>
                  )
                })}
              </div>
            </section>
          )
        })}
      </div>
    </div>
  )
}
