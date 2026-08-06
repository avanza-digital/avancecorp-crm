import {
  lazy,
  Suspense,
  type CSSProperties,
  type JSX,
} from 'react'
import type { EChartsOption } from 'echarts'
import { cn } from '@/lib/utils'

const BarRuntime = lazy(async () => {
  const modulo = await import('./echart-bar')
  return { default: modulo.GerenciaBarChart }
})

const LineRuntime = lazy(async () => {
  const modulo = await import('./echart-line')
  return { default: modulo.GerenciaLineChart }
})

interface GerenciaEChartProps {
  tipo: 'barras' | 'lineas'
  option: EChartsOption
  ariaLabel: string
  className?: string | undefined
  style?: CSSProperties | undefined
}

/**
 * Carga ECharts solo cuando una gráfica gerencial entra a la interfaz. El
 * placeholder conserva dimensiones y semántica para evitar saltos de diseño.
 */
export function GerenciaEChart(props: GerenciaEChartProps): JSX.Element {
  const Runtime = props.tipo === 'lineas' ? LineRuntime : BarRuntime
  const { tipo: _tipo, ...runtimeProps } = props
  return (
    <Suspense
      fallback={(
        <div
          role="img"
          aria-label={props.ariaLabel}
          aria-busy="true"
          className={cn('min-h-0 min-w-0 animate-pulse rounded-lg bg-[var(--gi-soft)]', props.className)}
          style={props.style}
        />
      )}
    >
      <Runtime {...runtimeProps} />
    </Suspense>
  )
}
