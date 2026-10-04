// Las cifras pequeñas de arriba (pastillas) y la barra de filtros de la base para gestión (F3), extraídas de la vista
// del analista en F4 (03/10/2026) para que la vista del supervisor use las mismas. Forma (Miguel): las cifras son
// PEQUEÑAS (el protagonismo es de la hoja) y todo número se abre; los filtros van en UNA fila (horizontal antes que
// vertical) y cada opción dice cuántos leads deja ver.
import { useId, type Ref } from 'react'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import {
  FILTRO_TODOS,
  hayFiltros,
  type DimensionFiltro,
  type FacetaFiltro,
  type FiltrosBase,
  type OpcionesFiltro,
} from '@/lib/base-gestion'

/** Cifra del resumen, pequeña a propósito: el protagonismo es de la hoja. Con `onAbrir` es un botón (todo número se
 *  abre); con `presionada`, un interruptor de filtro. */
export function Pastilla({ etiqueta, valor, urgente = false, presionada, pista, onAbrir }: {
  etiqueta: string
  valor: number
  urgente?: boolean
  presionada?: boolean
  /** Qué hace al pulsarla, solo para el lector («ver el bloque»): a la vista ya lo dice el puntero. */
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
  if (!onAbrir) return <p className={clase}>{contenido}</p>
  return (
    <button
      type="button"
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

/** Los filtros en UNA fila (Miguel: horizontal antes que vertical), junto al Mes. En el celular, de dos en dos.
 *  `conAnalista` (F4) pone primero «Analista»: la vista del supervisor filtra la base de su equipo por quién la gestiona.
 *  `conBase` (F6) pone «Base» junto al Mes («Base: Todas · Feria 2025 (40)»). */
export function BarraFiltros({ conMes, conAnalista = false, conBase = false, opciones, filtros, onCambiar, onQuitar, mostrados, total, primerFiltro, etiqueta = 'Filtrar tu base' }: {
  conMes: boolean
  conAnalista?: boolean
  conBase?: boolean
  opciones: OpcionesFiltro
  filtros: FiltrosBase
  onCambiar: (dimension: DimensionFiltro, valor: string) => void
  onQuitar: () => void
  mostrados: number
  total: number
  primerFiltro: Ref<HTMLSelectElement>
  /** Nombre del grupo para el lector. */
  etiqueta?: string
}) {
  const filtrando = hayFiltros(filtros)
  const filtro = (dimension: DimensionFiltro, rotulo: string, primero: boolean, rotuloTodos = 'Todos') => (
    <FiltroSelect
      etiqueta={rotulo}
      faceta={opciones[dimension]}
      valor={filtros[dimension]}
      onCambiar={(v) => onCambiar(dimension, v)}
      selectRef={primero ? primerFiltro : undefined}
      rotuloTodos={rotuloTodos}
    />
  )
  return (
    <div role="group" aria-label={etiqueta} className="grid w-full grid-cols-2 items-end gap-x-3 gap-y-2 sm:flex sm:w-auto sm:flex-wrap">
      {conAnalista && filtro('analista', 'Analista', true)}
      {conMes && filtro('mes', 'Mes', !conAnalista)}
      {conBase && filtro('base', 'Base', !conAnalista && !conMes, 'Todas')}
      {filtro('motivo', 'Motivo del descarte', !conAnalista && !conMes && !conBase)}
      {filtro('etapa', 'Etapa máxima', false)}
      {filtro('resultado', 'Último resultado', false)}
      <div className="col-span-2 flex min-h-9 items-center gap-3">
        {/* Siempre montado: el lector anuncia el cambio del conteo al filtrar (una región que nace con texto no se lee). */}
        <p role="status" className="text-sm font-semibold tabular-nums text-[var(--muted-foreground-strong)]">
          {filtrando ? `${mostrados} de ${total} ${total === 1 ? 'lead' : 'leads'}` : ''}
        </p>
        {filtrando && (
          <Button type="button" variant="outline" className="h-9 pointer-coarse:h-11" onClick={onQuitar}>
            <X aria-hidden /> Quitar filtros
          </Button>
        )}
      </div>
    </div>
  )
}

function FiltroSelect({ etiqueta, faceta, valor, onCambiar, selectRef, rotuloTodos }: {
  etiqueta: string
  faceta: FacetaFiltro
  valor: string
  onCambiar: (valor: string) => void
  selectRef?: Ref<HTMLSelectElement> | undefined
  /** «Todos» o «Todas» (la Base). */
  rotuloTodos: string
}) {
  const id = useId()
  const activo = valor !== FILTRO_TODOS
  return (
    <div className="flex min-w-0 flex-col gap-1 sm:min-w-40">
      <label htmlFor={id} className="text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]">{etiqueta}</label>
      <Select
        ref={selectRef}
        id={id}
        value={valor}
        onChange={(e) => onCambiar(e.target.value)}
        // El outline del foco lo devuelve la regla global de index.css (`[class*='focus-visible:outline-none']`); el anillo
        // con desplazamiento lo refuerza. El activo NO usa anillos: se marca con borde y fondo.
        className={cn('pointer-coarse:h-11 pointer-coarse:text-base focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2', activo && 'border-accent bg-accent/[0.06] font-semibold text-foreground')}
      >
        <option value={FILTRO_TODOS}>{rotuloTodos} ({faceta.total})</option>
        {faceta.opciones.map((o) => <option key={o.clave} value={o.clave}>{o.etiqueta} ({o.leads})</option>)}
      </Select>
    </div>
  )
}
