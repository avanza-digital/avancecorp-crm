import { cn } from '@/lib/utils'
import { iniciales } from '@/lib/format'

export function Avatar({
  nombre,
  color = 'var(--accent)',
  className,
}: {
  nombre: string | null | undefined
  color?: string | undefined
  className?: string | undefined
}) {
  return (
    <span
      className={cn(
        'inline-flex size-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold',
        className,
      )}
      style={{ background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
      aria-hidden
    >
      {iniciales(nombre)}
    </span>
  )
}
