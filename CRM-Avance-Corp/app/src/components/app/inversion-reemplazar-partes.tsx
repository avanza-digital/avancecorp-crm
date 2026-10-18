// Piezas comunes de «Reemplazar inversión» (Avance, Fase 2, y cooperativas, Fase 4): el marco de tres columnas, «La
// original» con su candado, la región viva del mes, la lista de cambios, el motivo y las acciones. Un solo lenguaje
// visual y los mismos patrones de accesibilidad en los dos diálogos.
import type { ButtonHTMLAttributes, ReactNode, Ref, RefObject } from 'react'
import { LoaderCircle, Lock, RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { mensajeDeError } from '@/data/crm-api'
import { MOTIVO_ELIMINACION_MAX, MOTIVO_ELIMINACION_MIN, largoMotivoEliminacion, mesLargo } from '@/lib/inversionistas'
import { cn } from '@/lib/utils'

/** El marco: título, la consecuencia y las tres columnas (la original, la correcta, antes de confirmar). */
export function DialogoReemplazo({ id, titulo, cabecera, onClose, focoAlCerrar, original, medio, confirmar }: {
  /** Base de los ids: `${id}-consecuencia`, `${id}-medio` y `${id}-confirmar`. */
  id: string
  titulo: string
  /** Lo que va a la derecha del título (p. ej. el selector de modo). */
  cabecera?: ReactNode
  onClose: () => void
  focoAlCerrar?: RefObject<HTMLElement | null> | undefined
  original: ReactNode
  medio: ReactNode
  confirmar: ReactNode
}) {
  return <Dialog open onClose={onClose} ariaLabel={titulo} focoAlCerrar={focoAlCerrar}
    className="w-[1160px] max-w-[95vw] max-h-[92svh]">
    <DialogHeader className="flex-row flex-wrap items-center justify-between gap-3">
      <div className="min-w-0">
        <DialogTitle className="text-base">{titulo}</DialogTitle>
        <p id={`${id}-consecuencia`} className="mt-0.5 text-sm text-muted-foreground">La venta se conserva. La original se elimina y queda una copia «reemplazada por».</p>
      </div>
      {cabecera}
    </DialogHeader>

    {/* Un solo desplazamiento en celular; en escritorio, cada columna el suyo. */}
    <div className="ac-scroll flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-5 py-4 lg:flex-row lg:overflow-hidden">
      {original}
      <div id={`${id}-medio`} className="flex min-w-0 flex-col rounded-xl border border-border lg:min-h-0 lg:flex-1 lg:overflow-hidden">
        {medio}
      </div>
      {/* Antes de confirmar: el mes (lo calcula el servidor), los cambios, el motivo y, al final, las acciones. */}
      <section aria-labelledby={`${id}-confirmar`} className="ac-scroll lg:w-[300px] lg:shrink-0 lg:overflow-y-auto">
        <h3 id={`${id}-confirmar`} className="mb-2 text-xs font-extrabold uppercase tracking-wide text-[var(--muted-foreground-strong)]">Antes de confirmar</h3>
        {confirmar}
      </section>
    </div>
  </Dialog>
}

/** La original: solo lectura. Cliente y analista a lo ancho (son largos) y con candado; `children` son pares dt/dd. */
export function SeccionOriginal({ id, cliente, analista, nota, children }: {
  id: string
  cliente: string
  analista: string
  nota: ReactNode
  children: ReactNode
}) {
  return <section aria-labelledby={`${id}-original`} className="lg:w-[270px] lg:shrink-0 lg:overflow-y-auto">
    <h3 id={`${id}-original`} className="mb-2 text-xs font-extrabold uppercase tracking-wide text-[var(--muted-foreground-strong)]">La original</h3>
    <div className="rounded-xl border border-border bg-muted/40 p-3.5 text-sm">
      <dl className="space-y-2 border-b border-border pb-2.5">
        <div className="space-y-0.5">
          <dt className="text-muted-foreground">Cliente</dt>
          <dd className="flex items-start gap-1.5 text-base font-bold [overflow-wrap:anywhere]"><Lock aria-hidden className="mt-1 size-3.5 shrink-0 text-muted-foreground" />{cliente}</dd>
        </div>
        <div className="space-y-0.5">
          <dt className="text-muted-foreground">Analista de la venta</dt>
          <dd className="flex items-start gap-1.5 font-semibold [overflow-wrap:anywhere]"><Lock aria-hidden className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />{analista}</dd>
        </div>
      </dl>
      <dl className="mt-2.5 grid grid-cols-[auto_1fr] gap-x-3 gap-y-2">{children}</dl>
    </div>
    <p className="mt-2 text-sm text-muted-foreground">{nota}</p>
  </section>
}

/** Lo que la región del mes necesita de la vista previa (la de Avance y la de cooperativas lo traen igual). */
interface MesDeLaPrevia { mes_resultante: string; mes_actual: string; cambia_mes: boolean }

/**
 * «La venta queda en»: región viva con el mes que calcula el servidor. El botón de reintentar va FUERA de la región
 * (un control no se anuncia como estado) y no se desmonta mientras reintenta (si se desmontara, el foco caería al
 * diálogo).
 */
export function RegionMes<P extends MesDeLaPrevia>({ previa, vacio, reintentando, reintento, onReintentar, detalle }: {
  previa: { data: P | undefined; error: unknown; isError: boolean; isFetching: boolean; isPending: boolean }
  /** Por qué todavía no hay mes que calcular (null: hay consulta). */
  vacio: string | null
  reintentando: boolean
  /** Mostrar «Reintentar el cálculo». */
  reintento: boolean
  onReintentar: (boton: HTMLButtonElement) => void
  /** Una línea propia bajo el mes (p. ej. la fecha corregida por Gerencia). */
  detalle?: ((p: P) => ReactNode) | undefined
}) {
  const p = previa.data
  return <>
    <div role="status" aria-live="polite" aria-busy={previa.isFetching || undefined}
      className={`rounded-xl border p-3.5 ${p?.cambia_mes ? 'border-warning/40 bg-warning/5' : 'border-accent/25 bg-accent/5'}`}>
      <p className="flex items-center justify-between gap-2 text-sm font-bold text-[var(--muted-foreground-strong)]">La venta queda en
        {previa.isFetching && !previa.isPending && <LoaderCircle aria-hidden className="size-3.5 animate-spin" />}</p>
      {vacio !== null ? <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">{vacio}</p>
        : previa.isPending || reintentando ? <p className="mt-1 flex items-center gap-2 text-sm text-[var(--muted-foreground-strong)]"><LoaderCircle aria-hidden className="size-4 animate-spin" />Calculando el mes…</p>
        : previa.isError ? <p className="mt-1 text-sm text-destructive-text">{mensajeDeError(previa.error, 'No se pudo calcular el mes.')}</p>
        : p && <>
          <p className="mt-1 text-xl font-extrabold tracking-tight text-primary">{mesLargo(p.mes_resultante)}</p>
          <p className={`mt-1 text-sm font-bold ${p.cambia_mes ? 'text-warning-text' : 'text-accent'}`}>
            {p.cambia_mes ? `Se muda desde ${mesLargo(p.mes_actual).toLowerCase()} (ese mes tiene que estar abierto)` : 'Igual que ahora'}</p>
          {detalle?.(p)}
        </>}
    </div>
    {reintento && <Button type="button" variant="outline" size="lg"
      className={cn('mt-2 px-4', reintentando && 'pointer-events-none opacity-50')}
      aria-disabled={reintentando || undefined} aria-busy={reintentando || undefined} onClick={e => onReintentar(e.currentTarget)}>
      {reintentando ? <LoaderCircle className="animate-spin" aria-hidden /> : <RefreshCw aria-hidden />}
      {reintentando ? 'Calculando…' : 'Reintentar el cálculo'}</Button>}
  </>
}

/** Un aviso que impide confirmar (o el rechazo del servidor). `id`: para que el campo culpable lo enlace. */
export function AvisoReemplazo({ id, children }: { id?: string | undefined; children: ReactNode }) {
  return <p id={id} role="alert" className="mt-3 rounded-lg border border-destructive/25 bg-destructive/5 px-3 py-2 text-sm font-semibold text-destructive-text">{children}</p>
}

export interface CambioReemplazo { etiqueta: string; antes?: string; ahora: string }

/** Lo que cambia respecto de la original, con el antes tachado (y dicho al lector de pantalla). */
export function ListaCambios({ cambios }: { cambios: readonly CambioReemplazo[] }) {
  if (cambios.length === 0) return null
  // role explícito: Safari + VoiceOver le quita la semántica de lista a un ul con estilos.
  // oxlint-disable-next-line jsx-a11y/no-redundant-roles
  return <ul role="list" className="mt-3 text-sm" aria-label="Cambios">
    {cambios.map(cambio => <li key={cambio.etiqueta} className="flex justify-between gap-3 border-t border-dashed border-border py-2">
      <span className="text-muted-foreground">{cambio.etiqueta}</span>
      <span className="text-right font-bold tabular-nums">{cambio.antes !== undefined && <><span className="sr-only">antes </span><span className="mr-1.5 font-medium text-muted-foreground line-through">{cambio.antes}</span><span className="sr-only">, ahora </span></>}{cambio.ahora}</span>
    </li>)}
  </ul>
}

/** El motivo (5 a 300 caracteres, como los cuenta Postgres), con su contador y la pista de lo que falta. */
export function CampoMotivo({ id, valor, onCambio, deshabilitado, placeholder, pista, ref }: {
  id: string
  valor: string
  onCambio: (valor: string) => void
  deshabilitado: boolean
  placeholder: string
  /** Lo primero que falta para confirmar, en palabras (null: nada). */
  pista: string | null
  ref?: Ref<HTMLTextAreaElement> | undefined
}) {
  const largo = largoMotivoEliminacion(valor)
  const excedido = largo > MOTIVO_ELIMINACION_MAX
  return <div className="mt-4 space-y-2">
    {/* 14 px como mínimo para el detalle (regla de la casa); la etiqueta base es de 12 px. */}
    <Label htmlFor={`${id}-motivo`} className="text-sm">Motivo del reemplazo</Label>
    <Textarea ref={ref} id={`${id}-motivo`} rows={3} value={valor} disabled={deshabilitado} aria-required="true"
      placeholder={placeholder} aria-invalid={excedido || undefined}
      aria-describedby={[`${id}-consecuencia`, `${id}-contador`, pista ? `${id}-pista` : null].filter(Boolean).join(' ')}
      onChange={e => onCambio(e.target.value)} />
    <p id={`${id}-contador`} className={excedido ? 'text-sm font-semibold text-destructive-text' : 'text-sm text-muted-foreground'}>
      {largo} de {MOTIVO_ELIMINACION_MAX} caracteres · mínimo {MOTIVO_ELIMINACION_MIN}</p>
    {/* Montada desde el inicio: se anuncia al pasarse del tope, cuando el botón queda inactivo. */}
    <p role="status" className="sr-only">{excedido ? `El motivo pasa de ${MOTIVO_ELIMINACION_MAX} caracteres: acórtalo para poder reemplazar.` : ''}</p>
    {pista && <p id={`${id}-pista`} className="text-sm text-muted-foreground">{pista}</p>}
  </div>
}

/**
 * Las acciones van DESPUÉS del motivo (orden de foco y de lectura). Mientras envía, el botón de confirmar lleva
 * `aria-disabled` y no `disabled`: deshabilitar de verdad tira el foco a <body>. El segundo envío lo impide quien llama.
 */
export function AccionesReemplazo({ enviando, onCancelar, children }: { enviando: boolean; onCancelar: () => void; children: ReactNode }) {
  return <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-border pt-3">
    <Button type="button" variant="ghost" size="lg" className="px-4" disabled={enviando} onClick={onCancelar}>Cancelar</Button>
    {children}
  </div>
}

export function BotonReemplazo({ enviando, habilitado, etiqueta, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & {
  enviando: boolean
  habilitado: boolean
  etiqueta: string
}) {
  return <Button size="lg" className={cn('px-4', enviando && 'pointer-events-none opacity-50')}
    disabled={!habilitado} aria-disabled={enviando || undefined} aria-busy={enviando || undefined} {...props}>
    {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : <RefreshCw aria-hidden />}
    {enviando ? 'Reemplazando…' : etiqueta}
  </Button>
}
