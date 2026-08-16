import { useState, type JSX } from 'react'
import type { DescuentoArrastre } from '@/lib/conversion-mensual'

/**
 * El chip del arrastre con su porqué ALCANZABLE (observación #5 de la revisión
 * externa): el `title` solo existe para el ratón, y el sr-only solo para
 * lectores — teclado y táctil no tenían NINGUNA vía al detalle. Esto es un
 * disclosure de verdad: botón enfocable, tap, `aria-expanded`, y el detalle
 * (mes, motivo, cuánto) se pinta debajo al abrir. El ratón conserva su atajo.
 */
export function ChipArrastre({
  descuento,
  className,
}: {
  descuento: DescuentoArrastre
  className?: string | undefined
}): JSX.Element {
  const [abierto, setAbierto] = useState(false)
  return (
    <span className={className}>
      <button
        type="button"
        aria-expanded={abierto}
        // Abierto, el tooltip repetiría el texto ya pintado debajo (y los
        // lectores lo anunciarían dos veces): solo cerrado.
        title={abierto ? undefined : descuento.detalle}
        onClick={() => setAbierto((actual) => !actual)}
        // hover: punteado→sólido (señal que GANA, sin hundir contraste como
        // opacity); ring pleno (el /40 daba 1.8:1 de indicador); padding con
        // margen negativo compensatorio = target táctil ≥24px sin mover el
        // layout. Todo del revisor a11y (16/08).
        className="-mx-1 -my-1.5 cursor-pointer rounded-sm px-1 py-1.5 font-semibold underline decoration-dotted underline-offset-2 hover:decoration-solid focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        {descuento.etiqueta}
      </button>
      {abierto && (
        <span className="mt-0.5 block whitespace-pre-line font-normal">
          {descuento.detalle}
        </span>
      )}
    </span>
  )
}
