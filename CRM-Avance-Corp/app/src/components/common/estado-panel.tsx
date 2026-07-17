// Estados de panel compartidos (cargando / error / vacío) — extracción del
// mejor patrón existente (clientes.tsx). Los TEXTOS llegan SIEMPRE por props:
// los copys por rol son negocio ('Aún no registraste contratos.' es texto
// exacto del portal) y estos componentes JAMÁS los inventan.
import type { ReactNode } from 'react'
import { RotateCcw, WifiOff, type LucideIcon } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

/** Skeletons de carga — aria-busy SIEMPRE en el contenedor (convención única). */
export function PanelCargando({ filas = 3, className }: { filas?: number; className?: string }) {
  return (
    <div className={cn('space-y-2 px-5 pb-5', className)} aria-busy>
      {Array.from({ length: filas }, (_, i) => (
        <Skeleton key={i} className="h-9 w-full" />
      ))}
    </div>
  )
}

/**
 * Error de carga con reintento: chip destructive + WifiOff, botón deshabilitado
 * MIENTRAS reintenta y el recordatorio de que la sesión sigue viva (el error es
 * de red/datos, no de auth — no hay que volver a loguearse).
 */
export function PanelError({
  mensaje,
  onReintentar,
  reintentando,
}: {
  mensaje: string
  onReintentar: () => void
  reintentando: boolean
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
      <span className="grid size-11 place-items-center rounded-2xl bg-destructive/10 text-destructive">
        <WifiOff className="size-5" aria-hidden />
      </span>
      <div className="space-y-1">
        <p className="text-sm font-semibold text-foreground">{mensaje}</p>
        <p className="text-xs text-muted-foreground">
          Revisa tu conexión y vuelve a intentarlo — tu sesión sigue activa.
        </p>
      </div>
      <Button variant="outline" size="sm" disabled={reintentando} onClick={onReintentar}>
        <RotateCcw aria-hidden /> Reintentar
      </Button>
    </div>
  )
}

/**
 * Estado vacío honesto (cartera sin filas o filtro sin coincidencias): chip
 * neutro + título; `detalle` es el párrafo secundario y `children` permite
 * extras propios de la pantalla (p.ej. la pista de acción solo si el rol puede).
 */
export function PanelVacio({
  icono: Icono,
  titulo,
  detalle,
  children,
}: {
  icono: LucideIcon
  titulo: string
  detalle?: ReactNode
  children?: ReactNode
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
      <span className="grid size-11 place-items-center rounded-2xl bg-muted text-muted-foreground">
        <Icono className="size-5" aria-hidden />
      </span>
      <p className="text-sm font-semibold text-foreground">{titulo}</p>
      {detalle != null && <p className="max-w-xs text-xs text-muted-foreground">{detalle}</p>}
      {children}
    </div>
  )
}
