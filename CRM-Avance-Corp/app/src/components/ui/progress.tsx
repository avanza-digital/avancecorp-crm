import { cn } from '@/lib/utils'

/** Barra de progreso simple (0–100). Color parametrizable por familia. */
export function Progress({
  value,
  className,
  color = 'var(--accent)',
}: {
  value: number
  className?: string
  color?: string
}) {
  const pct = Math.max(0, Math.min(100, value))
  return (
    <div className={cn('h-2 w-full overflow-hidden rounded-full bg-muted', className)}>
      <div
        className="h-full rounded-full transition-[width] duration-700 ease-out"
        style={{ width: `${pct}%`, background: color }}
      />
    </div>
  )
}
