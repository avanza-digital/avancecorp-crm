// La franja de cifras del día (diseño de Gestión Diaria, 27/09/2026): UNA
// tarjeta plana con las cifras separadas por rayas finas, la etiqueta en
// versalitas arriba, el número grande y su apoyo al lado. Nace para «Mi día»
// del analista y la reusan supervisor y gerencia, así que no sabe de negocio:
// recibe las cifras ya calculadas por el servidor.
//
// Escala y aire: los del diseño (Miguel, 27/09/2026: «que prevalezca el diseño,
// lo limpio que se ve»). Etiqueta 11 px, número 28 px, apoyo 12 px.
import type { JSX, ReactNode } from 'react'
import { cn } from '@/lib/utils'

export interface CifraDelDia {
  etiqueta: string
  valor: string
  /** Lo que debe OÍR un lector de pantalla cuando el valor es un símbolo mudo («—»). */
  valorAccesible?: string | undefined
  /** Texto o chip que acompaña al número («de 18», «hoy», el nivel). */
  apoyo?: ReactNode
  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy». */
  tono?: 'normal' | 'alerta' | undefined
}

// Clases escritas enteras: Tailwind no ve las que se arman con plantillas.
const COLUMNAS: Record<number, string> = {
  1: 'sm:grid-cols-1', 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4', 5: 'sm:grid-cols-5', 6: 'sm:grid-cols-6',
}

export function FranjaCifras({ etiqueta, cifras, className }: {
  /** Nombre del grupo para el lector de pantalla («Tu día en cifras»). */
  etiqueta: string
  cifras: readonly CifraDelDia[]
  className?: string | undefined
}): JSX.Element {
  return (
    <section aria-label={etiqueta} className={cn('rounded-2xl border border-border bg-card', className)}>
      <dl className={cn('grid grid-cols-2 gap-y-4 py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
        {cifras.map((c, i) => (
          // En el celular son 2 por fila (raya solo en la segunda); desde tablet,
          // raya a la izquierda de todas menos la primera.
          <div key={c.etiqueta} className={cn('flex min-w-0 flex-col gap-1 px-5', i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
            <dt className="text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
            <dd className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', c.tono === 'alerta' ? 'text-[var(--destructive-text)]' : 'text-primary')}>
                {c.valorAccesible !== undefined ? (
                  <>
                    <span aria-hidden="true">{c.valor}</span>
                    <span className="sr-only">{c.valorAccesible}</span>
                  </>
                ) : c.valor}
              </span>
              {c.apoyo !== undefined && c.apoyo !== null && (
                typeof c.apoyo === 'string'
                  ? <span className="text-xs text-[var(--muted-foreground-strong)]">{c.apoyo}</span>
                  : c.apoyo
              )}
            </dd>
          </div>
        ))}
      </dl>
    </section>
  )
}
