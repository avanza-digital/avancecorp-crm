import { useEffect, useRef, type CSSProperties, type JSX } from 'react'
import * as echarts from 'echarts/core'
import {
  AriaComponent,
  GridComponent,
  TooltipComponent,
} from 'echarts/components'
import { LabelLayout } from 'echarts/features'
import { CanvasRenderer } from 'echarts/renderers'
import type { EChartsOption } from 'echarts'
import type { EChartsType } from 'echarts/core'
import { cn } from '@/lib/utils'

echarts.use([
  AriaComponent,
  GridComponent,
  TooltipComponent,
  LabelLayout,
  CanvasRenderer,
])

export interface GerenciaEChartRuntimeProps {
  option: EChartsOption
  ariaLabel: string
  className?: string | undefined
  style?: CSSProperties | undefined
}

/**
 * Único borde React → ECharts del módulo gerencial.
 *
 * Mantiene una instancia por nodo, observa el tamaño real del contenedor y la
 * destruye al desmontar. Así ninguna pantalla crea listeners o canvases
 * huérfanos al navegar entre Resumen, Conversiones, Reuniones y Equipo.
 */
export function GerenciaEChartRuntime({
  option,
  ariaLabel,
  className,
  style,
}: GerenciaEChartRuntimeProps): JSX.Element {
  const contenedorRef = useRef<HTMLDivElement>(null)
  const graficaRef = useRef<EChartsType | null>(null)

  useEffect(() => {
    const contenedor = contenedorRef.current
    if (!contenedor) return undefined

    const grafica = echarts.init(contenedor, undefined, { renderer: 'canvas' })
    graficaRef.current = grafica
    let cuadro = 0
    const ajustar = () => {
      window.cancelAnimationFrame(cuadro)
      cuadro = window.requestAnimationFrame(() => grafica.resize())
    }

    const observador = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(ajustar)
    if (observador) observador.observe(contenedor)
    else window.addEventListener('resize', ajustar)

    return () => {
      window.cancelAnimationFrame(cuadro)
      observador?.disconnect()
      if (!observador) window.removeEventListener('resize', ajustar)
      grafica.dispose()
      graficaRef.current = null
    }
  }, [])

  useEffect(() => {
    const grafica = graficaRef.current
    if (!grafica) return
    const reducirMovimiento = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    const opcionAccesible: EChartsOption = {
      ...option,
      aria: {
        enabled: true,
        label: { description: ariaLabel },
      },
    }
    if (reducirMovimiento) opcionAccesible.animation = false
    grafica.setOption(opcionAccesible, { notMerge: true, lazyUpdate: true })
  }, [ariaLabel, option])

  return (
    <div
      ref={contenedorRef}
      role="img"
      aria-label={ariaLabel}
      className={cn('min-h-0 min-w-0', className)}
      style={style}
    />
  )
}
