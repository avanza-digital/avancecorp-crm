// Grupo de radios NATIVOS con etiqueta envolvente (patrón de rescate-descartados
// y cuenta-pago-contrato, extraído a primitiva en la Fase 0 de Gestión Diaria).
// Cada opción es un objetivo de 44 px; el estado marcado se ve en el borde de
// 2 px y en el texto, nunca solo en color. `fieldset` + `legend` dan nombre al
// grupo; el input nativo resuelve teclado (flechas) y lector de pantalla.
import { useId, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

export interface OpcionRadio<V extends string> {
  valor: V
  etiqueta: ReactNode
  /** Segunda línea en gris (qué implica elegirla). */
  detalle?: ReactNode | undefined
  /** Atajo visible a la derecha (p. ej. «1»); la pantalla decide si lo escucha. */
  atajo?: string | undefined
  deshabilitada?: boolean | undefined
}

interface RadioGroupProps<V extends string> {
  /** Título del grupo (se pinta como `legend`). */
  leyenda: ReactNode
  opciones: readonly OpcionRadio<V>[]
  valor: V | null
  onCambio: (valor: V) => void
  /** `name` del grupo; por defecto se genera uno estable. */
  nombre?: string | undefined
  obligatorio?: boolean | undefined
  className?: string | undefined
  /** Texto de ayuda o error, enlazado por `aria-describedby`. */
  descripcion?: ReactNode | undefined
  invalido?: boolean | undefined
  /** Formularios operativos: todas las etiquetas y ayudas con piso de 16 px. */
  grande?: boolean | undefined
  /** Ids de textos de FUERA del grupo (p. ej. el error de un formulario) que
   *  también lo describen. Se SUMAN a la `descripcion` propia, nunca la tapan. */
  describedBy?: string | undefined
}

export function RadioGroup<V extends string>({ leyenda, opciones, valor, onCambio, nombre, obligatorio, className, descripcion, invalido, grande, describedBy }: RadioGroupProps<V>) {
  const idAuto = useId()
  const name = nombre ?? `radio${idAuto.replaceAll(':', '')}`
  const idDescripcion = `${name}-descripcion`
  const descritoPor = [descripcion !== undefined ? idDescripcion : null, describedBy?.trim() || null].filter(Boolean).join(' ') || undefined
  return (
    <fieldset className={cn('space-y-2', className)} aria-describedby={descritoPor} aria-invalid={invalido || undefined}>
      <legend className={cn('mb-1 text-[11px] font-bold uppercase tracking-wide text-muted-foreground', grande && 'text-base normal-case tracking-normal')}>
        {leyenda}
        {obligatorio && <span className="ml-1 normal-case tracking-normal text-[var(--muted-foreground-strong)]">· obligatorio</span>}
      </legend>
      {opciones.map((opcion) => {
        const marcada = opcion.valor === valor
        return (
          <label
            key={opcion.valor}
            className={cn(
              'flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border-2 px-3 py-2 transition-colors has-[:focus-visible]:ring-[3px] has-[:focus-visible]:ring-accent/40',
              marcada ? 'border-accent bg-accent/5' : 'border-border hover:border-[var(--muted-foreground)]',
              opcion.deshabilitada && 'cursor-not-allowed opacity-50',
            )}
          >
            <input
              type="radio"
              name={name}
              value={opcion.valor}
              checked={marcada}
              disabled={opcion.deshabilitada}
              required={obligatorio}
              onChange={() => onCambio(opcion.valor)}
              className={cn('size-4 shrink-0 accent-[var(--accent)]', grande && 'size-5')}
            />
            <span className="min-w-0 flex-1">
              <span className={cn('block text-sm', grande && 'text-base', marcada ? 'font-bold text-primary' : 'font-semibold')}>{opcion.etiqueta}</span>
              {opcion.detalle !== undefined && <span className={cn('block text-xs text-muted-foreground', grande && 'text-base')}>{opcion.detalle}</span>}
            </span>
            {opcion.atajo !== undefined && (
              <kbd aria-hidden className={cn('rounded border border-border bg-muted px-1.5 text-[11px] font-bold text-[var(--muted-foreground-strong)]', grande && 'text-base')}>{opcion.atajo}</kbd>
            )}
          </label>
        )
      })}
      {descripcion !== undefined && (
        <p id={idDescripcion} className={cn('text-xs', grande && 'text-base', invalido ? 'font-semibold text-destructive' : 'text-muted-foreground')}>{descripcion}</p>
      )}
    </fieldset>
  )
}
