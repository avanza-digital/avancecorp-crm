import { useId } from 'react'
import { cn } from '@/lib/utils'

/**
 * Sparkline SVG autocontenido (sin dependencias). Línea + relleno degradado.
 * Escala a su ancho con preserveAspectRatio="none".
 */
export function Sparkline({
  points,
  color = 'var(--accent)',
  height = 36,
  className,
  title,
}: {
  points: number[]
  color?: string
  height?: number
  className?: string
  title?: string
}) {
  const id = useId()
  if (!points || points.length < 2) return null

  const W = 100
  const H = height
  const min = Math.min(...points)
  const max = Math.max(...points)
  const span = max - min || 1
  const step = W / (points.length - 1)
  const xy = points.map((p, i) => [i * step, H - 4 - ((p - min) / span) * (H - 8)] as const)

  const line = xy.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`).join(' ')
  const area = `${line} L${W},${H} L0,${H} Z`

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      width="100%"
      height={H}
      preserveAspectRatio="none"
      className={cn('block', className)}
      role="img"
      aria-label={title}
    >
      {title && <title>{title}</title>}
      <defs>
        <linearGradient id={`sg-${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.20" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#sg-${id})`} />
      <path d={line} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
    </svg>
  )
}
