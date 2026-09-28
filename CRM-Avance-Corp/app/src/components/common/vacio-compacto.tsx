import type { LucideIcon } from 'lucide-react'
import type { JSX, ReactNode } from 'react'

/** Estado vacío en horizontal: icono a la izquierda y texto a la derecha, en
 * una franja baja. La caja centrada con aire arriba y abajo dejaba huecos en
 * la pantalla, sobre todo cuando la tarjeta vecina sí tenía filas.
 *
 * Nació dentro de «Hoy · analista» y lo comparten desde el 28/09/2026 la
 * pantalla y la ficha «Tus citas» (`screens/hoy/citas-analista.tsx`). */
export function VacioCompacto({
  icono: Icono,
  colorIcono = 'text-muted-foreground/60',
  titulo,
  detalle,
  extra,
}: {
  icono?: LucideIcon
  colorIcono?: string
  titulo: string
  detalle: ReactNode
  extra?: ReactNode
}): JSX.Element {
  return (
    <div className="flex items-center gap-3 rounded-lg bg-muted/40 px-3 py-3">
      {Icono && <Icono className={`size-6 shrink-0 ${colorIcono}`} aria-hidden />}
      <div className="min-w-0">
        <p className="text-sm font-bold">{titulo}</p>
        <p className="text-xs text-[var(--muted-foreground-strong)]">{detalle}</p>
        {extra && <p className="mt-0.5 text-[11px] font-semibold text-foreground/70">{extra}</p>}
      </div>
    </div>
  )
}
