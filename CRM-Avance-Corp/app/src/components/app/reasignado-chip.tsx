import { ArrowRightLeft } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import type { Lead } from '@/lib/tipos'

/** Una marca de trayectoria, independiente de Sistema/Manual (alta). */
export function ChipReasignado({ lead }: { lead: Pick<Lead, 'reasignado'> }) {
  if (lead.reasignado !== true) return null
  return (
    <Badge color="var(--chart-4)" title="Ya tuvo una asignación anterior a un analista">
      <ArrowRightLeft className="size-3" aria-hidden />
      Reasignado
    </Badge>
  )
}
