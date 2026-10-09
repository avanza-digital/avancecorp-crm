import { X } from 'lucide-react'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'

/** Cifra del resumen, pequeña a propósito: el protagonismo es de la hoja. Con `onAbrir` es un botón (todo número se
 *  abre); con `presionada`, un interruptor de filtro. */
export function Pastilla({ etiqueta, valor, urgente = false, presionada, pista, title, onAbrir }: {
  etiqueta: string
  valor: number | string
  urgente?: boolean
  presionada?: boolean
  /** Redundancia opcional: todo contexto necesario debe mostrarse también como texto visible. */
  title?: string | undefined
  /** Acción que completa el nombre accesible («ver el desglose»); no sustituye al contexto visible. */
  pista?: string
  onAbrir?: (() => void) | undefined
}) {
  const clase = cn(
    'inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm',
    urgente ? 'border-destructive/40 bg-destructive/[0.06] text-[var(--destructive-text)]'
      : presionada ? 'border-accent bg-accent/10 text-foreground'
        : 'border-border bg-card text-[var(--muted-foreground-strong)]',
  )
  const contenido = (
    <>
      {/* El «:» oculto separa la etiqueta del número para el lector («De Agosto 2026: 2», no «20262»). */}
      <span>{etiqueta}<span className="sr-only">:</span></span>
      <strong className={cn('font-bold tabular-nums', urgente ? 'text-[var(--destructive-text)]' : 'text-foreground')}>{valor}</strong>
    </>
  )
  if (!onAbrir) return <p className={clase} title={title}>{contenido}</p>
  return (
    <button
      type="button"
      title={title}
      onClick={onAbrir}
      aria-pressed={presionada}
      className={cn(clase, 'cursor-pointer transition-colors pointer-coarse:min-h-11', urgente ? 'hover:bg-destructive/10' : 'hover:border-[var(--border-strong)]', FOCO)}
    >
      {contenido}
      {pista && <span className="sr-only">, {pista}</span>}
      {presionada && <X className="size-3.5 text-[var(--muted-foreground-strong)]" aria-hidden />}
    </button>
  )
}
