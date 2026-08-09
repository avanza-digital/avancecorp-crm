// stat-strip.tsx — resumen compacto sobre tablas/tableros (patrón VITANOVA).
// StatStrip: fila de mini-KPIs con entrada escalonada.
// SegmentBar: barra de distribución proporcional (etapas/estados) + leyenda.
import type { LucideIcon } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { AnimatedValue } from '@/components/common/animated-value'
import { cn } from '@/lib/utils'

const TONE: Record<string, string> = {
  default: 'text-foreground',
  accent: 'text-accent',
  primary: 'text-primary',
  warn: 'text-warning',
  bad: 'text-destructive',
}

export interface StatChipData {
  icon: LucideIcon
  label: string
  value: string
  /**
   * Qué debe OÍR el lector de pantalla cuando `value` es un símbolo mudo. El
   * em dash «—» de las métricas degradadas no se pronuncia con la puntuación
   * por defecto de NVDA/JAWS: el usuario oye la etiqueta y luego silencio, que
   * es indistinguible de un cero. Pasar aquí «sin dato» / «cargando».
   */
  valorAccesible?: string
  tone?: keyof typeof TONE
  sub?: string
}

/** Fila de mini-KPIs (2 en móvil, 4 en desktop) con entrada escalonada. */
export function StatStrip({ stats, className }: { stats: StatChipData[]; className?: string }) {
  return (
    <div className={cn('grid grid-cols-2 gap-3 lg:grid-cols-4', className)}>
      {stats.map((s, i) => {
        const Icon = s.icon
        return (
          <Card
            key={s.label}
            className="ac-lift ac-pop p-3.5"
            style={{ animationDelay: `${i * 60}ms` }}
          >
            <div className="flex items-center gap-1.5 text-[11px] font-semibold text-muted-foreground">
              <Icon className="size-3.5" />
              <span className="truncate">{s.label}</span>
            </div>
            <div className={cn('mt-1 text-xl font-extrabold leading-none tracking-tight tabular-nums', TONE[s.tone || 'default'])}>
              {s.valorAccesible ? (
                <>
                  <span aria-hidden="true"><AnimatedValue value={s.value} /></span>
                  <span className="sr-only">{s.valorAccesible}</span>
                </>
              ) : (
                <AnimatedValue value={s.value} />
              )}
            </div>
            {s.sub && <div className="mt-1 truncate text-[10.5px] text-muted-foreground">{s.sub}</div>}
          </Card>
        )
      })}
    </div>
  )
}

export interface Segment {
  label: string
  value: number
  color: string
  /** Texto del valor en la leyenda (default: el número). */
  valTxt?: string
}

/** Barra segmentada proporcional + leyenda (distribución por etapa/estado). */
export function SegmentBar({
  segments,
  className,
  legend = true,
}: {
  segments: Segment[]
  className?: string
  legend?: boolean
}) {
  const visibles = segments.filter((s) => s.value > 0)
  const total = visibles.reduce((a, s) => a + s.value, 0)
  if (!total) return null
  return (
    <div className={cn('space-y-2', className)}>
      {/* `aria-hidden`: la pista es ADORNO. Los tres colores del semáforo
          tienen entre sí 1.5–1.6:1, así que por sí sola no distingue nada para
          daltonismo — el dato real está siempre en la leyenda de abajo o en el
          texto contiguo cuando `legend={false}`. Los `title` de cada segmento
          eran además nombre accesible solo-ratón: ruido sin valor. */}
      <div className="flex h-2.5 overflow-hidden rounded-full bg-muted" aria-hidden="true">
        {visibles.map((s) => (
          <span
            key={s.label}
            title={`${s.label} · ${s.valTxt ?? s.value}`}
            className="h-full transition-[width] duration-500 ease-out first:rounded-l-full last:rounded-r-full"
            style={{ width: `${Math.max(1.5, (s.value / total) * 100)}%`, background: s.color }}
          />
        ))}
      </div>
      {legend && (
        <div className="flex flex-wrap gap-x-4 gap-y-1">
          {visibles.map((s) => (
            <span key={s.label} className="inline-flex items-center gap-1.5 text-[11.5px] text-muted-foreground">
              <span className="size-2 shrink-0 rounded-full" style={{ background: s.color }} />
              {s.label}
              <span className="font-bold tabular-nums text-foreground/80">{s.valTxt ?? s.value}</span>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
