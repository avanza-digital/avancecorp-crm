import { useId, type ReactNode, type Ref } from 'react'
import { ChevronDown, Mail, MessageCircle, Phone, X, type LucideIcon } from 'lucide-react'
import { numeroWhatsapp, enlaceTel } from '@/lib/telefono'
import { SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { cn } from '@/lib/utils'

const CLASE_CONTACTO =
  'inline-flex h-10 items-center gap-1.5 rounded-lg border border-input bg-card px-3 text-[11px] font-bold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35 [&_svg]:size-3.5'


export function FichaComercialContacto({
  nombre,
  telefono,
  correo,
  habilitado = true,
}: {
  nombre: string
  telefono: string | null
  correo: string | null
  habilitado?: boolean
}) {
  const tel = telefono ? enlaceTel(telefono) : null
  const wa = telefono ? numeroWhatsapp(telefono) : null
  return (
    <div className="flex flex-wrap items-center gap-1.5" aria-label="Formas de contactar al cliente">
      {tel && (
        <a href={habilitado ? tel : undefined} role={habilitado ? undefined : 'link'} tabIndex={0} aria-disabled={!habilitado} className={CLASE_CONTACTO} aria-label={`Llamar a ${nombre}`}>
          <Phone aria-hidden /> Llamar
        </a>
      )}
      {wa && (
        <a
          href={habilitado ? `https://wa.me/${wa}` : undefined}
          role={habilitado ? undefined : 'link'} tabIndex={0}
          aria-disabled={!habilitado}
          target={habilitado ? '_blank' : undefined}
          rel="noreferrer"
          className={CLASE_CONTACTO}
          aria-label={`Abrir WhatsApp de ${nombre}`}
        >
          <MessageCircle aria-hidden /> Abrir WhatsApp
        </a>
      )}
      {correo && (
        <a href={habilitado ? `mailto:${correo}` : undefined} role={habilitado ? undefined : 'link'} tabIndex={0} aria-disabled={!habilitado} className={CLASE_CONTACTO} aria-label={`Escribir correo a ${nombre}`}>
          <Mail aria-hidden /> Escribir correo
        </a>
      )}
    </div>
  )
}


/** Presentación original de Ficha 360; cada núcleo aporta sus cifras autorizadas. */
export function FichaComercialContinuidad({items}: {
  items: {etiqueta: string; contenido: ReactNode; ayuda: string}[]
}) {
  return (
    <section
      aria-label="Continuidad comercial del cliente"
      className="overflow-hidden rounded-2xl border border-primary/10 bg-primary/[0.035] shadow-[inset_3px_0_0_var(--accent)]"
    >
      <div className="border-b border-primary/10 px-4 py-2.5">
        <p className="text-xs font-extrabold uppercase tracking-[0.12em] text-primary">Continuidad comercial</p>
      </div>
      <div className="grid sm:grid-cols-3">
        {items.map((item) => (
          <div
            key={item.etiqueta}
            className="border-t border-primary/10 px-4 py-3 first:border-t-0 sm:border-l sm:border-t-0 sm:first:border-l-0"
          >
            <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">{item.etiqueta}</p>
            <div className="mt-1">{item.contenido}</div>
            <p className="mt-1 line-clamp-2 text-[11px] leading-relaxed text-muted-foreground">{item.ayuda}</p>
          </div>
        ))}
      </div>
    </section>
  )
}


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
