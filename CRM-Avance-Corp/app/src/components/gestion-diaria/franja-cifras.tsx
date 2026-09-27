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
  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy».
   * `aviso` lo pinta en ámbar: una señal que NO es un vencimiento (p. ej. «Necesitan atención»,
   * que mezcla vencidas con cortes y tiempo sin llamar). */
  tono?: 'normal' | 'alerta' | 'aviso' | undefined
}

// Clases escritas enteras: Tailwind no ve las que se arman con plantillas.
const COLUMNAS: Record<number, string> = {
  1: 'sm:grid-cols-1', 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4', 5: 'sm:grid-cols-5', 6: 'sm:grid-cols-6',
}

const TONO: Record<NonNullable<CifraDelDia['tono']>, string> = {
  normal: 'text-primary', alerta: 'text-[var(--destructive-text)]', aviso: 'text-[var(--warning-text)]',
}

export function FranjaCifras({ etiqueta, cifras, className, disposicion = 'apilada' }: {
  /** Nombre del grupo para el lector de pantalla («Tu día en cifras»). */
  etiqueta: string
  cifras: readonly CifraDelDia[]
  className?: string | undefined
  /** `apilada`: etiqueta arriba y número debajo (analista). `en-linea`: número y
   * etiqueta en una línea, como la franja del supervisor en el diseño. El DOM
   * conserva término → definición; solo cambia el orden visual. */
  disposicion?: 'apilada' | 'en-linea' | undefined
}): JSX.Element {
  const enLinea = disposicion === 'en-linea'
  return (
    // Grupo con nombre, no una región más: la pantalla ya tiene las suyas.
    <section role="group" aria-label={etiqueta} className={cn('rounded-2xl border border-border bg-card', className)}>
      <dl className={cn('grid grid-cols-2 gap-y-4', enLinea ? 'py-[18px]' : 'py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
        {cifras.map((c, i) => (
          // En el celular son 2 por fila (raya solo en la segunda); desde tablet,
          // raya a la izquierda de todas menos la primera.
          <div key={c.etiqueta} className={cn('flex min-w-0 px-5', enLinea ? 'flex-row-reverse items-baseline justify-end gap-2.5' : 'flex-col gap-1',
            i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
            <dt className={enLinea ? 'min-w-0 text-[13px] text-[var(--muted-foreground-strong)]' : 'text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]'}>{c.etiqueta}</dt>
            <dd className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', TONO[c.tono ?? 'normal'])}>
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
