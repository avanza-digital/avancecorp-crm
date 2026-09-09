import type { ReactNode } from 'react'

/** Presentación del dato ya calculado por su fuente. */
export function IndicadorGerencia({ etiqueta, valor, contexto }: {
  etiqueta: string
  valor: string
  contexto: ReactNode
}) {
  return (
    <section data-gi-kpi className="gi-indicador min-w-0 space-y-3 rounded-2xl border border-[var(--gi-line)] bg-white p-4" aria-label={etiqueta}>
      <p className="gi-label">{etiqueta}</p>
      <p className="break-words text-2xl font-bold leading-8 tabular-nums text-[var(--gi-navy)]">{valor}</p>
      <div className="space-y-1 text-xs leading-[18px] text-[var(--muted-foreground-strong)]">{contexto}</div>
    </section>
  )
}
