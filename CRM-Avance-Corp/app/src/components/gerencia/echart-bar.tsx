import type { JSX } from 'react'
import * as echarts from 'echarts/core'
import { BarChart } from 'echarts/charts'
import {
  GerenciaEChartRuntime,
  type GerenciaEChartRuntimeProps,
} from './echart'

echarts.use([BarChart])

export function GerenciaBarChart(props: GerenciaEChartRuntimeProps): JSX.Element {
  return <GerenciaEChartRuntime {...props} />
}
