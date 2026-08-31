import { useId, type ReactNode, type Ref } from 'react'
import { ChevronDown, X, type LucideIcon } from 'lucide-react'
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

/**
 * Sección secundaria que conserva un resumen visible y deja el detalle bajo
 * demanda. Usa <details> nativo: teclado y lectores de pantalla reciben el
 * estado abierto/cerrado sin inventar otra convención interactiva.
 */
export function FichaComercialSeccionPlegable({
  icono: Icono,
  titulo,
  resumen,
  descripcion,
  children,
  abierta,
  onAbiertaChange,
  className,
  sectionRef,
}: {
  icono: LucideIcon
  titulo: string
  resumen: string
  descripcion?: string
  children: ReactNode
  abierta: boolean
  onAbiertaChange: (abierta: boolean) => void
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
        'focus-visible:rounded-xl focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35',
        className,
      )}
    >
      <details
        open={abierta}
        onToggle={(evento) => onAbiertaChange(evento.currentTarget.open)}
        className="group rounded-xl border border-border bg-muted/20"
      >
        <summary
          aria-label={`${titulo}. ${resumen}`}
          className="flex min-h-12 cursor-pointer list-none items-center gap-2.5 rounded-xl px-3 py-2.5 transition-colors hover:bg-muted/45 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35 [&::-webkit-details-marker]:hidden"
        >
          <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-primary/[0.07] text-primary">
            <Icono className="size-3.5" aria-hidden />
          </span>
          <span className="min-w-0 flex-1">
            <span id={tituloId} className="block text-xs font-extrabold tracking-tight text-foreground">
              {titulo}
            </span>
            <span className="mt-0.5 block text-[11px] leading-relaxed text-muted-foreground">{resumen}</span>
          </span>
          <ChevronDown
            className="size-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180"
            aria-hidden
          />
        </summary>
        <div className="space-y-3 border-t border-border/60 px-3 pb-3 pt-3">
          {descripcion && <p className="text-[11px] leading-relaxed text-muted-foreground">{descripcion}</p>}
          {children}
        </div>
      </details>
    </section>
  )
}
