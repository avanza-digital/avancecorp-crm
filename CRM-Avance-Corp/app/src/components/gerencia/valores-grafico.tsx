import type { ReactNode } from 'react'

/** Respaldo textual de las mismas series visibles; no calcula ni agrega datos. */
export function ValoresGrafico({ titulo, columnas, filas }: {
  titulo: string
  columnas: readonly string[]
  filas: readonly (readonly ReactNode[])[]
}) {
  return <details className="mt-3 text-xs">
    <summary className="w-fit cursor-pointer rounded py-2 font-semibold text-[var(--gi-blue)] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">Ver valores: {titulo}</summary>
    <div className="overflow-x-auto"><table className="w-full text-left">
      <caption className="sr-only">{titulo}</caption>
      <thead><tr>{columnas.map((columna, i) => <th key={columna} scope="col" className={`p-2 ${i === 0 ? '' : 'text-right'}`}>{columna}</th>)}</tr></thead>
      <tbody>{filas.map((fila, i) => <tr key={i} className="border-t border-[var(--gi-line)]">{fila.map((valor, j) => j === 0 ? <th key={j} scope="row" className="p-2 font-medium">{valor}</th> : <td key={j} className="p-2 text-right tabular-nums">{valor}</td>)}</tr>)}</tbody>
    </table></div>
  </details>
}
