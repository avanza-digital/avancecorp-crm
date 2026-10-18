import { Badge } from '@/components/ui/badge'
import type { Lead } from '@/lib/tipos'
import { muestraCampania } from '@/lib/campania'

/** Informativa: no transforma el canal ni ofrece edición de la atribución. */
export function ChipCampania({ lead, id }: { lead: Pick<Lead, 'campania_origen' | 'origen'>; id?: string }) {
  if (!muestraCampania(lead)) return null
  return (
    <Badge variant="outline" color="var(--accent)" className="max-w-full whitespace-normal break-words"
      title={`Campaña de origen: ${lead.campania_origen}`}>
      <span id={id} className="sr-only">{`Campaña de origen: ${lead.campania_origen}`}</span>
      <span aria-hidden="true">{lead.campania_origen}</span>
    </Badge>
  )
}
