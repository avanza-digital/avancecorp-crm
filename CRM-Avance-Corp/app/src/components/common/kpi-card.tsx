// KpiCard — card-hero de KPI reutilizable (extraída de la pantalla Hoy, F1c).
// Anatomía: icono en tile (ac-chip), chip de tendencia opcional, valor grande
// animado (AnimatedValue), label, sub y sparkline al pie. Las 4 variantes de
// "Hoy" (vendedor/supervisor/gerencia/directorio) la comparten para no
// duplicar el mismo markup.
import type { CSSProperties, JSX } from 'react'
import type { LucideIcon } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { AnimatedValue } from '@/components/common/animated-value'
import { Sparkline } from '@/components/common/sparkline'

export interface KpiCardProps {
  label: string
  /** Valor ya formateado (money/moneyK/String) — AnimatedValue anima su parte numérica. */
  value: string
  icon: LucideIcon
  /** Color CSS del tile, el chip de tendencia y el sparkline (ej. 'var(--chart-1)' o '#2563eb'). */
  color: string
  /** Línea secundaria bajo el label (ej. 'Pipeline activo (PEN) · +US$ 25k'). */
  sub?: string
  /** Serie del sparkline al pie (se omite si falta o tiene <2 puntos). */
  spark?: number[]
  /** Texto del chip de tendencia TAL CUAL se muestra (ej. '▲ +13%', '▼ −2'). */
  tendencia?: string
  /** animationDelay del pop de entrada, en ms (escalonar: i * 60). */
  delay?: number
}

export function KpiCard({
  label,
  value,
  icon: Icon,
  color,
  sub,
  spark,
  tendencia,
  delay = 0,
}: KpiCardProps): JSX.Element {
  return (
    <Card className="ac-lift ac-pop overflow-hidden" style={{ animationDelay: `${delay}ms` }}>
      <CardContent className="pb-3 pt-4">
        <div className="mb-3 flex items-center justify-between">
          <span
            className="ac-chip grid size-10 place-items-center rounded-xl"
            style={{ '--c': color } as CSSProperties}
          >
            <Icon className="size-5" />
          </span>
          {tendencia && (
            <Badge color={color} variant="outline">
              {tendencia}
            </Badge>
          )}
        </div>
        <div className="text-2xl font-extrabold tracking-tight tabular-nums text-primary">
          <AnimatedValue value={value} />
        </div>
        <div className="text-[13px] font-semibold text-foreground/80">{label}</div>
        {sub && <div className="text-xs text-muted-foreground">{sub}</div>}
        {spark && spark.length > 1 && (
          <Sparkline
            points={spark}
            color={color}
            height={34}
            className="mt-3 -mb-1"
            title="Tendencia · últimas 7 semanas"
          />
        )}
      </CardContent>
    </Card>
  )
}
