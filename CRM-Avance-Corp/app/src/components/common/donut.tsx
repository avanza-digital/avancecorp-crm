import { cn } from '@/lib/utils'

export interface DonutSlice {
  label: string
  value: number
  color: string
}

/**
 * Donut SVG autocontenido (sin dependencias) con label central + leyenda
 * (conteo + %). Los segmentos se dibujan con stroke-dasharray sobre un círculo.
 */
export function Donut({
  slices,
  centerValue,
  centerLabel,
  size = 190,
  thickness = 22,
  className,
  legend = true,
}: {
  slices: DonutSlice[]
  centerValue?: string
  centerLabel?: string
  size?: number
  thickness?: number
  className?: string
  legend?: boolean
}) {
  const data = slices.filter((s) => s.value > 0)
  const total = data.reduce((a, s) => a + s.value, 0)
  const r = (size - thickness) / 2
  const c = 2 * Math.PI * r
  const cx = size / 2

  let offset = 0
  const segs = data.map((s) => {
    const frac = total ? s.value / total : 0
    const seg = { ...s, dash: frac * c, gap: c - frac * c, off: offset }
    offset += frac * c
    return seg
  })

  return (
    <div className={cn('flex flex-col items-center gap-4', className)}>
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="-rotate-90">
          <circle cx={cx} cy={cx} r={r} fill="none" stroke="var(--muted)" strokeWidth={thickness} />
          {total > 0 &&
            segs.map((s, i) => (
              <circle
                key={i}
                cx={cx}
                cy={cx}
                r={r}
                fill="none"
                stroke={s.color}
                strokeWidth={thickness}
                strokeLinecap="butt"
                strokeDasharray={`${s.dash} ${s.gap}`}
                strokeDashoffset={-s.off}
                style={{ transition: 'stroke-dasharray 0.6s var(--ease-out-expo)' }}
              />
            ))}
        </svg>
        {(centerValue || centerLabel) && (
          <div className="absolute inset-0 grid place-items-center text-center">
            <div>
              {centerValue && <div className="text-3xl font-extrabold tracking-tight tabular-nums">{centerValue}</div>}
              {centerLabel && <div className="text-[11px] text-muted-foreground">{centerLabel}</div>}
            </div>
          </div>
        )}
      </div>
      {legend && total > 0 && (
        <div className="w-full space-y-1.5">
          {data.map((s) => {
            const pct = total ? Math.round((s.value / total) * 100) : 0
            return (
              <div key={s.label} className="flex items-center gap-2 text-sm">
                <span className="size-2.5 shrink-0 rounded-full" style={{ background: s.color }} />
                <span className="truncate text-foreground/80">{s.label}</span>
                <span className="ml-auto font-semibold tabular-nums">{s.value}</span>
                <span className="w-9 text-right tabular-nums text-muted-foreground">{pct}%</span>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
