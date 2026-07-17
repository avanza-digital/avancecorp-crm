// <nav> de paginación compartido (Clientes/Cartera; Contratos con su rediseño):
// pinta SOLO cuando hay más de una página — con una sola, ni contador ni
// botones (mismo criterio que tenían las copias locales). La matemática
// (clamp, recorte) vive en lib/paginacion.paginar; aquí solo la navegación.
import type { JSX } from 'react'

export function Paginacion({
  paginaActual,
  paginas,
  total,
  onCambio,
  ariaLabel,
}: {
  /** Página vigente YA clampeada (sale de paginar()). */
  paginaActual: number
  paginas: number
  /** Registros tras filtrar — el "· N registros" del contador. */
  total: number
  onCambio: (pagina: number) => void
  /** aria-label del <nav>, por pantalla ('Paginación de clientes', …). */
  ariaLabel: string
}): JSX.Element | null {
  if (paginas <= 1) return null
  return (
    <nav className="flex items-center justify-between gap-3" aria-label={ariaLabel}>
      <p className="text-xs tabular-nums text-muted-foreground">
        Página {paginaActual + 1} de {paginas} · {total} registros
      </p>
      <div className="flex gap-2">
        <button
          type="button"
          className="rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"
          disabled={paginaActual === 0}
          onClick={() => onCambio(Math.max(0, paginaActual - 1))}
        >
          Anterior
        </button>
        <button
          type="button"
          className="rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"
          disabled={paginaActual >= paginas - 1}
          onClick={() => onCambio(Math.min(paginas - 1, paginaActual + 1))}
        >
          Siguiente
        </button>
      </div>
    </nav>
  )
}
