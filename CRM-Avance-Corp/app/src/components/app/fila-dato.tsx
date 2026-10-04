// Una fila «etiqueta → valor» de una lista de datos (<dl>): la de la sección Datos de
// la ficha del lead. Vive aparte para que otras fichas (la de «Base para gestión»)
// pinten sus datos con la MISMA rejilla y tipografía, sin copiarla.
import type { ReactNode } from 'react'

/** Va dentro de un `<dl>`: pinta su `<dt>` (etiqueta) y su `<dd>` (valor). */
export function Fila({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[96px_1fr] items-baseline gap-2 py-1">
      <dt className="text-[11px] font-semibold text-muted-foreground">{label}</dt>
      <dd className="min-w-0 text-[13px] text-foreground">{children}</dd>
    </div>
  )
}
