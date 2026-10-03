// El teléfono de un lead de la base: marca en el celular (`tel:`) y copia en la laptop (ahí un `tel:` no marca
// nada). Lo comparten la hoja del analista y la ficha del lead (F2): un número que no sirve no se ofrece.
import { Phone } from 'lucide-react'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { enlaceTel } from '@/lib/telefono'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import { copiarNumero } from './copiar-numero'

/** En la hoja, el teléfono ES el botón de llamar: marca en el celular, copia en la laptop. */
export function TelefonoLlamable({ fila, puedeMarcar }: { fila: FilaBaseGestion; puedeMarcar: boolean }) {
  const tel = enlaceTel(fila.telefono)
  if (!tel || !fila.telefono) return <span className="text-[var(--muted-foreground-strong)]">Sin teléfono</span>
  const legible = telefonoLegible(fila.telefono)
  const estilo = cn('inline-flex items-center gap-1.5 rounded px-1 font-semibold tabular-nums text-accent underline-offset-2 hover:underline', FOCO)
  if (puedeMarcar) {
    return (
      <a href={tel} aria-label={`Llamar a ${fila.nombre_completo}, ${legible}`} className={estilo}>
        <Phone className="size-3.5" aria-hidden />{legible}
      </a>
    )
  }
  return (
    <button type="button" onClick={() => copiarNumero(tel, legible)} aria-label={`Llamar a ${fila.nombre_completo}, ${legible}: copia su número`} title="Copiar el número" className={estilo}>
      <Phone className="size-3.5" aria-hidden />{legible}
    </button>
  )
}
