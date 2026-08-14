/**
 * Distintivo del cierre anulado por gerencia. Vive aparte porque lo usan tres
 * sitios con contextos distintos: la lista de cierres en cooperativas, la ficha
 * del lead y las filas de cartera. El asesor tiene que poder explicarse por qué
 * su total bajó, mire donde mire.
 *
 * Es TEXTO y no solo un color o un tachado, y va en `destructive-text` (rojo
 * oscuro): a 10px es el único portador NO cromático del estado, y el rojo puro
 * sobre este fondo se queda en 4,1:1 — por debajo del mínimo legible.
 *
 * `etiqueta` existe porque el rótulo depende de QUÉ lista lo rodea: dentro de una
 * lista de cierres, «ANULADO» es inequívoco; en una fila de cartera, donde lo que
 * se lista son leads, «ANULADO» a secas se leería como «lead anulado» — que no
 * existe y además sería lo contrario de lo que pasó (el cliente sigue ahí).
 */
export function ChipAnulado({ etiqueta = 'ANULADO' }: { etiqueta?: string }) {
  return (
    <span className="inline-flex shrink-0 items-center rounded-full border border-destructive/40 bg-destructive/10 px-2 py-0.5 text-[10px] font-bold tracking-wide text-destructive-text">
      {etiqueta}
    </span>
  )
}
