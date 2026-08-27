import type { JSX } from 'react'

export interface AvisoCoberturaConversionProps {
  mensaje: string | null | undefined
}

/** Aviso no accionable del núcleo mensual: provisional o integridad en revisión. */
export function AvisoCoberturaConversion({
  mensaje,
}: AvisoCoberturaConversionProps): JSX.Element | null {
  if (!mensaje) return null
  return (
    <div
      role="status"
      className="rounded-xl border border-warning/30 bg-warning/5 px-3 py-2 text-xs text-warning-text"
    >
      {mensaje}
    </div>
  )
}
