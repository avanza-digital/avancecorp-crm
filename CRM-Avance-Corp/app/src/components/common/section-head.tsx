import type { LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

/** Encabezado de sección de card: ícono + título + slot derecho (patrón VITANOVA). */
export function SectionHead({
  icon: Icon,
  title,
  right,
  className,
  rightClassName,
}: {
  icon: LucideIcon
  title: string
  right?: ReactNode
  className?: string
  rightClassName?: string
}) {
  return (
    <div className={cn('flex items-center gap-2 px-5 pt-4 pb-3', className)}>
      <Icon className="size-4 text-accent" />
      <h3 className="text-[15px] font-bold tracking-tight">{title}</h3>
      {right != null && <div className={cn('ml-auto', rightClassName)}>{right}</div>}
    </div>
  )
}
