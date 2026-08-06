import type { JSX } from 'react'
import * as echarts from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { LegendComponent } from 'echarts/components'
import {
  GerenciaEChartRuntime,
  type GerenciaEChartRuntimeProps,
} from './echart'

echarts.use([LineChart, LegendComponent])

export function GerenciaLineChart(props: GerenciaEChartRuntimeProps): JSX.Element {
  return <GerenciaEChartRuntime {...props} />
}
