// KpiCard — card-hero de KPI reutilizable (extraída de la pantalla Hoy, F1c).
// Anatomía: icono en tile (ac-chip), valor grande animado (AnimatedValue),
// label y sub. Las 4 variantes de "Hoy" (vendedor/supervisor/gerencia/
// directorio) la comparten para no duplicar el mismo markup.
//
// Sprint A (A3, honestidad): el sparkline y el chip de tendencia (±%) NO se
// renderizan — sus series eran datos de demostración junto a cifras reales, y
// las props `spark`/`tendencia` ya se retiraron de la firma (estaban muertas).
// Cuando existan series reales, reintroducirlas junto con su render (la base
// del chip sigue viva en lib/inteligencia.tendenciaDe, marcada @deprecated).
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
  /** animationDelay del pop de entrada, en ms (escalonar: i * 60). */
  delay?: number | undefined
}

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
