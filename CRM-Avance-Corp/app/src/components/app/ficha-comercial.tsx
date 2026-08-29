import { useId, type ReactNode, type Ref } from 'react'
import { X, type LucideIcon } from 'lucide-react'
import { SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { cn } from '@/lib/utils'

/**
 * Cabecera común de las fichas comerciales. Comparte la jerarquía y el cierre,
 * pero deja que cada dominio aporte sus propios badges, cifras y acciones:
 * Leads conserva su pipeline; Clientes conserva contratos y postventa.
 */
export function FichaComercialCabecera({
  avatar,
  titulo,
  badges,
  resumen,
  acciones,
  onCerrar,
}: {
  avatar: ReactNode
  titulo: string
  badges?: ReactNode
  resumen?: ReactNode
  acciones?: ReactNode
  onCerrar: () => void
}) {
  return (
    <SheetHeader className="gap-2.5">
      <div className="flex items-start gap-3">
        {avatar}
        <div className="min-w-0 flex-1">
          <SheetTitle className="line-clamp-2 leading-tight [overflow-wrap:anywhere]">{titulo}</SheetTitle>
          {badges && <div className="mt-1.5 flex flex-wrap items-center gap-1.5">{badges}</div>}
        </div>
        {resumen}
        <button
          type="button"
          onClick={onCerrar}
          aria-label="Cerrar ficha"
          className="grid size-10 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
        >
          <X className="size-4" aria-hidden />
        </button>
      </div>
      {acciones}
    </SheetHeader>
  )
}

/** Bloque semántico común dentro de una ficha; el contenido decide su layout. */
export function FichaComercialSeccion({
  icono: Icono,
  titulo,
  descripcion,
  accion,
  children,
  className,
  sectionRef,
}: {
  icono: LucideIcon
  titulo: string
  descripcion?: string
  accion?: ReactNode
  children: ReactNode
  className?: string
  sectionRef?: Ref<HTMLElement>
}) {
  const tituloId = useId()
  return (
    <section
      ref={sectionRef}
      tabIndex={sectionRef ? -1 : undefined}
      aria-labelledby={tituloId}
      className={cn(
        'space-y-3 focus-visible:rounded-xl focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35',
        className,
      )}
    >
      <div className="flex flex-col items-start gap-2 sm:flex-row sm:justify-between sm:gap-3">
        <div className="flex min-w-0 items-start gap-2.5">
          <span className="mt-0.5 grid size-7 shrink-0 place-items-center rounded-lg bg-primary/[0.07] text-primary">
            <Icono className="size-3.5" aria-hidden />
          </span>
          <div className="min-w-0">
            <h3 id={tituloId} className="text-xs font-extrabold tracking-tight text-foreground">
              {titulo}
            </h3>
            {descripcion && <p className="mt-0.5 text-[11px] leading-relaxed text-muted-foreground">{descripcion}</p>}
          </div>
        </div>
        {accion && <div className="w-full sm:w-auto">{accion}</div>}
      </div>
      {children}
    </section>
  )
}
