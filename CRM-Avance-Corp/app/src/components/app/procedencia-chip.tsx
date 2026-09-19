import { Bot, PenLine } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { etiquetaProcedencia, type Lead } from '@/lib/tipos'

/**
 * Procedencia del lead, a simple vista: «Sistema» (entró solo por el puente)
 * o «Manual» (lo registró una persona). Un solo acento: lo manual es la
 * minoría y es lo que un supervisor quiere ver de un vistazo; lo del sistema
 * queda en gris para no competir con la etapa.
 * Si el dato no viaja (servidor anterior a la migración) no pinta nada:
 * inventar «Sistema» sería mentir.
 */
export function ChipProcedencia({ lead, conNombre = false, className }: {
  lead: Pick<Lead, 'procedencia' | 'cargado_por_nombre'>
  /** Añade «· NOMBRE» al chip manual (ficha); en la fila el nombre va aparte. */
  conNombre?: boolean
  className?: string
}) {
  if (lead.procedencia === 'manual') {
    return (
      <Badge color="var(--accent)" className={className} title="Registrado a mano por un miembro del equipo">
        <PenLine className="size-3" aria-hidden />
        {etiquetaProcedencia('manual')}
        {conNombre && lead.cargado_por_nombre && <span className="font-medium">· {lead.cargado_por_nombre}</span>}
      </Badge>
    )
  }
  if (lead.procedencia === 'sistema') {
    return (
      <Badge variant="outline" color="var(--muted-foreground)" className={className} title="Entró solo, por el puente automático">
        <Bot className="size-3" aria-hidden />
        {etiquetaProcedencia('sistema')}
      </Badge>
    )
  }
  return null
}

