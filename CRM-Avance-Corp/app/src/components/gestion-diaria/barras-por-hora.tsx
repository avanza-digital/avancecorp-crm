// Llamadas por hora, 08–20 Lima (decisión #8 de Miguel): UNA pieza para el
// analista, el supervisor y gerencia (diseño del 27/09/2026). Cada columna
// apila lo que contestaron (azul) debajo de lo que no (azul tenue) y lleva su
// número encima: se lee sin pasar el ratón. Antes eran barras navy macizas con
// el azul dentro, que no se distinguían.
//
// Accesible: el dibujo es decorativo (`aria-hidden`) y el dato viaja en una
// lista de solo lectura para el lector de pantalla, con las horas que tuvieron
// llamadas. La escala de letra es la del diseño (Miguel, 27/09/2026).
import { useId, type JSX } from 'react'
import { barrasPorHora, llamadasFueraDeFranja, type Marcador } from '@/lib/gestion-diaria-analista'
import { cn } from '@/lib/utils'

const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`

export function BarrasPorHora({ porHora, titulo, apoyo, alto = 110, className }: {
  porHora: Marcador['por_hora']
  titulo: string
  /** Texto a la derecha del título («Última llamada 16:05»). */
  apoyo?: string | undefined
  /** Alto del dibujo en px, sin contar números ni horas. */
  alto?: number | undefined
  className?: string | undefined
}): JSX.Element {
  const id = useId()
  const barras = barrasPorHora({ por_hora: porHora })
  const conLlamadas = barras.filter((b) => b.llamadas > 0)
  const fuera = llamadasFueraDeFranja({ por_hora: porHora })
  return (
    <div className={cn('space-y-2', className)}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <h4 id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">{titulo}</h4>
        {apoyo !== undefined && <p className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">{apoyo}</p>}
      </div>
      {conLlamadas.length === 0 ? (
        <p className="text-[13px] text-[var(--muted-foreground-strong)]">
          {fuera > 0 ? `Sin llamadas entre las 08 y las 20; ${plural(fuera, 'llamada', 'llamadas')} fuera de esa franja.` : 'Todavía no hay llamadas hoy.'}
        </p>
      ) : (
        <>
          <div aria-hidden="true" className="flex items-end gap-1.5" style={{ height: alto + 40 }}>
            {barras.map((b) => {
              const noContestadas = Math.round(((b.llamadas - b.contestadas) / b.maximo) * alto)
              const contestadas = Math.round((b.contestadas / b.maximo) * alto)
              return (
                <div key={b.hora} className="flex h-full min-w-0 flex-1 flex-col items-center justify-end">
                  <span className={cn('mb-[3px] text-[11px] font-bold tabular-nums text-foreground/80', b.llamadas === 0 && 'invisible')}>{b.llamadas}</span>
                  <span className={cn('w-full max-w-[22px] bg-accent/25', noContestadas > 0 && 'rounded-t')} style={{ height: noContestadas }} />
                  <span className={cn('w-full max-w-[22px] bg-accent', noContestadas === 0 && contestadas > 0 && 'rounded-t')} style={{ height: contestadas }} />
                  <span className="mt-[5px] text-[11px] tabular-nums text-[var(--muted-foreground-strong)]">{String(b.hora).padStart(2, '0')}</span>
                </div>
              )
            })}
          </div>
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ul role="list" aria-labelledby={`${id}-titulo`} className="sr-only">
            {conLlamadas.map((b) => (
              <li key={b.hora}>{b.hora}:00 — {plural(b.llamadas, 'llamada', 'llamadas')}, {plural(b.contestadas, 'contestada', 'contestadas')}</li>
            ))}
          </ul>
          <div className="flex flex-wrap items-center gap-x-3.5 gap-y-1 text-xs text-foreground/80">
            <span className="inline-flex items-center gap-1.5"><span aria-hidden="true" className="size-2.5 rounded-[3px] bg-accent" />Contestaron</span>
            <span className="inline-flex items-center gap-1.5"><span aria-hidden="true" className="size-2.5 rounded-[3px] bg-accent/25" />No contestaron</span>
            {fuera > 0 && <span>{plural(fuera, 'llamada', 'llamadas')} fuera de la franja 08–20.</span>}
          </div>
        </>
      )}
    </div>
  )
}
