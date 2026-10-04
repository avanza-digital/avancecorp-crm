// Una fila «etiqueta → valor» de una lista de datos (<dl>): la de la sección Datos de
// la ficha del lead. Vive aparte para que otras fichas (la de «Base para gestión»)
// pinten sus datos con la MISMA rejilla y tipografía, sin copiarla.
import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

/** Va dentro de un `<dl>`: pinta su `<dt>` (etiqueta) y su `<dd>` (valor). `className` acomoda la fila en la
 *  rejilla de quien la monta (p. ej. ocupar dos columnas). */
export function Fila({ label, children, className }: { label: string; children: ReactNode; className?: string | undefined }) {
  return (
    <div className={cn('grid grid-cols-[96px_1fr] items-baseline gap-2 py-1', className)}>
      <dt className="text-[11px] font-semibold text-muted-foreground">{label}</dt>
      <dd className="min-w-0 text-[13px] text-foreground">{children}</dd>
    </div>
  )
}
