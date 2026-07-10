// KpiCard — card-hero de KPI reutilizable (extraída de la pantalla Hoy, F1c).
// Anatomía: icono en tile (ac-chip), valor grande animado (AnimatedValue),
// label y sub. Las 4 variantes de "Hoy" (vendedor/supervisor/gerencia/
// directorio) la comparten para no duplicar el mismo markup.
//
// Sprint A (A3, honestidad): el sparkline y el chip de tendencia (±%) YA NO se
// renderizan — sus series eran datos de demostración junto a cifras reales.
// Las props `spark` y `tendencia` se conservan en la firma por compatibilidad
// con los callers existentes, pero se ignoran. Cuando existan series reales,
// reactivar el render aquí (los callers no necesitarán cambios).
import type { CSSProperties, JSX } from 'react'
import type { LucideIcon } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { AnimatedValue } from '@/components/common/animated-value'

export interface KpiCardProps {
  label: string
  /** Valor ya formateado (money/moneyK/String) — AnimatedValue anima su parte numérica. */
  value: string
  icon: LucideIcon
  /** Color CSS del tile (ej. 'var(--chart-1)' o '#2563eb'). */
  color: string
  /** Línea secundaria bajo el label (ej. 'Pipeline activo (PEN) · +US$ 25k'). */
  sub?: string | undefined
  /** IGNORADA (A3): serie del sparkline. Se acepta por compatibilidad; no se dibuja. */
  spark?: number[] | undefined
  /** IGNORADA (A3): chip de tendencia. Se acepta por compatibilidad; no se dibuja. */
  tendencia?: string | undefined
  /** animationDelay del pop de entrada, en ms (escalonar: i * 60). */
  delay?: number | undefined
}

// `spark` y `tendencia` NO se destructuran a propósito: se aceptan (compat)
// pero no se usan (evita locals sin uso con las flags estrictas de TS).
export function KpiCard({ label, value, icon: Icon, color, sub, delay = 0 }: KpiCardProps): JSX.Element {
  return (
    <Card className="ac-lift ac-pop overflow-hidden" style={{ animationDelay: `${delay}ms` }}>
      <CardContent className="pb-3 pt-4">
        {/* Sin chip de tendencia, el tile del icono manda solo en la fila:
            misma altura (size-10), el espaciado no cambia. */}
        <div className="mb-3 flex items-center justify-between">
          <span
            className="ac-chip grid size-10 place-items-center rounded-xl"
            style={{ '--c': color } as CSSProperties}
          >
            <Icon className="size-5" />
          </span>
        </div>
        <div className="text-2xl font-extrabold tracking-tight tabular-nums text-primary">
          <AnimatedValue value={value} />
        </div>
        <div className="text-[13px] font-semibold text-foreground/80">{label}</div>
        {sub && <div className="text-xs text-muted-foreground">{sub}</div>}
      </CardContent>
    </Card>
  )
}
