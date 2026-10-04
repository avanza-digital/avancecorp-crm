// Piezas compartidas de la pestaña «Bases» (F5): el número que se abre (todo número se abre), el aviso de un refresco
// fallido con «Reintentar» y el aviso de «disponible pronto» (el servidor aún no tiene B9/B10).
import type { ReactNode } from 'react'
import { Clock3, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'

/** Una cifra: botón si hay algo detrás (azul de acción; rojo solo si es urgente); en 0, un número quieto. */
export function NumeroAbrible({ valor, contexto, pista = 'ver la lista', urgente = false, onAbrir }: {
  valor: number
  /** Para el lector: de qué es la cifra («Feria 2025, sin repartir»). */
  contexto: string
  pista?: string
  urgente?: boolean
  onAbrir?: (() => void) | undefined
}): ReactNode {
  if (!onAbrir || valor === 0) {
    return <span className={cn('tabular-nums', urgente && valor > 0 ? 'font-bold text-[var(--destructive-text)]' : 'text-[var(--muted-foreground-strong)]')}>{valor.toLocaleString('es-PE')}</span>
  }
  return (
    <button
      type="button"
      onClick={onAbrir}
      className={cn(
        'inline-flex min-h-8 min-w-10 cursor-pointer items-center justify-center rounded-md px-2 font-bold tabular-nums underline decoration-dotted underline-offset-4 transition-colors hover:decoration-solid pointer-coarse:min-h-11 pointer-coarse:min-w-11',
        urgente ? 'text-[var(--destructive-text)] hover:bg-destructive/10' : 'text-[var(--accent-press)] hover:bg-accent/10',
        FOCO,
      )}
    >
      <span className="sr-only">{contexto}: </span>
      {valor.toLocaleString('es-PE')}
      <span className="sr-only">, {pista}</span>
    </button>
  )
}

/**
 * Un refresco o una lectura que falló, con «Reintentar» (aria-disabled mientras reintenta: el foco no se pierde). Si aún se
 * muestran los últimos datos (`conDatos`) es un aviso cortés (`status`); si no hay nada que ver, una alerta.
 */
export function AvisoReintentar({ mensaje, reintentando, onReintentar, conDatos = false }: { mensaje: string; reintentando: boolean; onReintentar: () => void; conDatos?: boolean }) {
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-card px-4 py-2.5">
      <p role={conDatos ? 'status' : 'alert'} className="text-sm text-[var(--muted-foreground-strong)]">{mensaje}</p>
      <Button variant="outline" size="sm" className="pointer-coarse:h-11" aria-disabled={reintentando || undefined} onClick={() => { if (!reintentando) onReintentar() }}>
        <RotateCcw aria-hidden /> Reintentar
      </Button>
    </div>
  )
}

/** Lo que el servidor todavía no tiene (PGRST202): se dice, no se inventa un cero. */
export function DisponiblePronto({ titulo, detalle }: { titulo: string; detalle: string }) {
  return (
    <div className="flex items-start gap-3 rounded-lg border border-border bg-card px-4 py-3">
      <Clock3 className="mt-0.5 size-4 shrink-0 text-[var(--muted-foreground-strong)]" aria-hidden />
      <div>
        <p className="text-sm font-semibold text-foreground">{titulo}</p>
        <p className="text-[13px] text-[var(--muted-foreground-strong)]">{detalle}</p>
      </div>
    </div>
  )
}

/** Rótulo de sección (escala VitaNova: 11 px en versalitas). */
export const ROTULO = 'text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]'
/** Celdas de las tablas compactas de la pestaña. */
export const CELDA_COMPACTA = 'whitespace-nowrap border-b border-border px-3 py-1.5 text-sm'
export const ENCABEZADO_COMPACTO = 'sticky top-0 z-10 whitespace-nowrap border-b border-[var(--border-strong)] bg-muted px-3 py-2 text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]'
