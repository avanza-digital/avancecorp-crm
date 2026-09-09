// <nav> de paginación compartido (Clientes/Cartera; Contratos con su rediseño):
// pinta SOLO cuando hay más de una página — con una sola, ni contador ni
// botones (mismo criterio que tenían las copias locales). La matemática
// (clamp, recorte) vive en lib/paginacion.paginar; aquí solo la navegación.
import type { JSX } from 'react'
import { Button } from '@/components/ui/button'

export function Paginacion({
  paginaActual,
  paginas,
  total,
  onCambio,
  ariaLabel,
  mostrarSiempre = false,
}: {
  /** Página vigente YA clampeada (sale de paginar()). */
  paginaActual: number
  paginas: number
  /** Registros tras filtrar — el "· N registros" del contador. */
  total: number
  onCambio: (pagina: number) => void
  /** aria-label del <nav>, por pantalla ('Paginación de clientes', …). */
  ariaLabel: string
  /** La cartera con paginación del servidor conserva los controles visibles. */
  mostrarSiempre?: boolean
}): JSX.Element | null {
  if (paginas <= 1 && !mostrarSiempre) return null
  return (
    <nav className="flex flex-wrap items-center justify-between gap-3" aria-label={ariaLabel}>
      <p className="text-xs tabular-nums text-muted-foreground">
        Página {paginaActual + 1} de {paginas} · {total} registros
      </p>
      <div className="flex shrink-0 gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="min-h-10 sm:min-h-8"
          disabled={paginaActual === 0}
          onClick={() => onCambio(Math.max(0, paginaActual - 1))}
        >
          Anterior
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="min-h-10 sm:min-h-8"
          disabled={paginaActual >= paginas - 1}
          onClick={() => onCambio(Math.min(paginas - 1, paginaActual + 1))}
        >
          Siguiente
        </Button>
      </div>
    </nav>
  )
}
