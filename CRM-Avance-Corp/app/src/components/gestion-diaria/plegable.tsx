// Sección plegable de Gestión Diaria (20/09/2026). Nació de la queja de los
// analistas —«demasiada información, muchas letras pequeñas»—: lo que no cambia
// a quién hay que llamar ahora se pliega, pero su CONTEO se queda a la vista en
// el resumen. Los errores que impiden decidir a quién llamar viven FUERA.
// El registro histórico es optativo: su estado de consulta se ve al abrirlo.
import type { JSX, ReactNode, Ref } from 'react'
import { ChevronRight } from 'lucide-react'

export function Plegable({ id, titulo, resumen, abierto, onAbrir, nivel = 'h3', summaryRef, children }: {
  /** Para que quien lo abre desde fuera pueda apuntarlo con `aria-controls`. */
  id?: string | undefined
  titulo: string
  /** Lo que se ve sin abrir: el conteo. Nunca se esconde un dato accionable. */
  resumen?: string | undefined
  abierto: boolean
  onAbrir: (abierto: boolean) => void
  /** Nivel del encabezado DENTRO del summary: el título del bloque tiene que
   *  seguir estando en el índice de encabezados (rotor / tecla H). */
  nivel?: 'h3' | 'h4'
  /** Para devolver aquí el foco cuando una acción de dentro se desmonta. */
  summaryRef?: Ref<HTMLElement> | undefined
  children: ReactNode
}): JSX.Element {
  const Titulo = nivel
  return (
    <details {...(id !== undefined ? { id } : {})} open={abierto} onToggle={(e) => onAbrir(e.currentTarget.open)}
      className="group rounded-xl border border-border bg-card">
      {/* El `display` del summary se queda como lo trae el navegador y el flex
          vive en el encabezado de dentro: alterarlo es la misma clase de cambio
          que ya hizo a Safari+VoiceOver descartar la semántica de lista
          (excepción documentada en .oxlintrc.json). El foco va por `outline`,
          que sí se pinta en alto contraste; el anillo queda de refuerzo. */}
      <summary ref={summaryRef}
        className="cursor-pointer list-none rounded-xl px-4 py-4 transition-colors hover:bg-muted/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:px-6 [&::-webkit-details-marker]:hidden">
        <Titulo className="flex items-start gap-3 text-base font-semibold text-primary">
          <ChevronRight aria-hidden className="mt-0.5 size-5 shrink-0 transition-transform group-open:rotate-90" />
          <span className="min-w-0 flex-1 space-y-1 sm:space-y-0">
            <span className="block sm:inline">{titulo}</span>{' '}
            {resumen !== undefined && (
              <span className="block font-normal text-[var(--muted-foreground-strong)] sm:ml-3 sm:inline">{resumen}</span>
            )}
          </span>
        </Titulo>
      </summary>
      <div className="border-t border-border p-4 sm:p-6">{children}</div>
    </details>
  )
}
