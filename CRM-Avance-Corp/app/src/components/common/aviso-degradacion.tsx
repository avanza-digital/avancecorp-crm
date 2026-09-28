// aviso-degradacion.tsx — la franja que aparece cuando una fuente de métricas
// se cae: la pantalla NO se bloquea, los indicadores quedan en «—» y aquí se
// explica por qué, con un botón para reintentar (precedente objetivosError).
//
// Fuente ÚNICA a propósito. El patrón vivió clonado en 9 sitios y los defectos
// que arrastraba estaban clonados con él:
//   1. Texto en `muted-foreground` sobre el fondo ámbar: 4,25:1 a 12 px, por
//      debajo del 4,5:1 exigible. Justo el texto que explica por qué faltan
//      los números era el menos legible de la pantalla. Va en `warning-text`
//      (6,34:1 medido sobre el fondo compuesto real).
//   2. El botón se desmonta cuando el reintento SALE BIEN (el aviso desaparece
//      con él) y el foco del teclado caía a <body>: había que retabular la
//      pantalla entera. Lo recoge el ancla de abajo.
// Cualquier aviso nuevo que use este componente nace con ambos resueltos.
import { useEffect, useRef, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

export interface AvisoDegradacionProps {
  /** Si no, no hay nada que avisar (queda solo el ancla de foco, sin pintar). */
  activo: boolean
  /** Qué no se pudo cargar y qué implica. Frase completa, en español. */
  children: ReactNode
  /**
   * Complemento que completa el nombre accesible del botón
   * («Reintentar la carga ___»). Llega YA DECLINADO, con su preposición:
   * «de los indicadores de la cartera», «del reloj SLA». Se pide así para no
   * anteponer un `de` a ciegas y acabar diciendo «de el reloj SLA» en voz alta.
   *
   * Existe porque varias pantallas tienen más de un «Reintentar» a la vez
   * —Pipeline muestra dos avisos, y las listas traen el suyo en el panel de
   * error— y en el rotor del lector se verían botones idénticos.
   */
  queReintenta: string
  onReintentar: () => void
}

export function AvisoDegradacion({
  activo,
  children,
  queReintenta,
  onReintentar,
}: AvisoDegradacionProps) {
  // Ancla SIEMPRE montada, `sr-only` cuando no hay aviso —absoluta y recortada,
  // NUNCA `hidden`: un display:none no se puede enfocar— para que sobreviva al
  // aviso y recoja el foco cuando el botón se va. Al estar en la MISMA posición
  // del DOM, el siguiente Tab continúa por donde tocaba. tabIndex={-1} = destino
  // programático, no alcanzable con Tab, que es lo que hace legítimo el
  // outline-none.
  const ancla = useRef<HTMLDivElement>(null)
  const boton = useRef<HTMLButtonElement>(null)
  const esperandoFoco = useRef(false)
  const activoPrevio = useRef(activo)

  // El rescate del foco se cuelga del cambio de `activo`, NO del click: el
  // reintento es un refetch de red y el aviso desaparece cientos de ms después,
  // no en el par de cuadros siguientes. Colgarlo del click dejaba el rescate en
  // código muerto (lo cazó la revisión de Codex y la de a11y).
  useEffect(() => {
    const desaparecio = activoPrevio.current && !activo
    activoPrevio.current = activo
    if (!desaparecio || !esperandoFoco.current) return
    esperandoFoco.current = false
    // Solo si el foco quedó huérfano: si el usuario ya se movió a otro control
    // —el reintento pudo tardar—, no se lo robamos. Tras un desmontaje algunos
    // motores dejan `activeElement` en null en vez de en <body>.
    const foco = document.activeElement
    if (!foco || foco === document.body) ancla.current?.focus()
  }, [activo])

  return (
    <div ref={ancla} tabIndex={-1} className={cn('outline-none', !activo && 'sr-only')}>
      {/* La región vive SIEMPRE en el DOM y el contenido llega después: es el
          orden fiable para que un lector de pantalla anuncie el cambio.
          `status` (polite) y no `alert`: la pantalla queda operable con «—», no
          hay nada urgente ni con plazo, y un anuncio asertivo interrumpiría la
          lectura en curso sin necesidad. */}
      <div role="status">
        {activo && (
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/5 px-3 py-2 text-xs text-warning-text">
            <span>{children}</span>
            <button
              ref={boton}
              type="button"
              aria-label={`Reintentar la carga ${queReintenta}`}
              // Anillo SÓLIDO (4,62:1): el token /40 de la casa se queda en
              // 1,76:1 y no llega al 3:1 que exige un indicador de foco. El
              // subrayado añade un segundo canal que no depende del color.
              // Área de toque ≥36 px (40 táctil) con un pseudo-elemento: el botón
              // se ve igual y la franja no crece, pero el dedo no falla.
              className="relative rounded font-semibold text-foreground underline-offset-2 after:absolute after:-inset-x-2 after:-inset-y-3 after:content-[''] hover:underline focus-visible:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring pointer-coarse:after:-inset-y-3.5"
              onClick={() => {
                // Solo hay foco que rescatar si el foco estaba de verdad AQUÍ.
                // Con ratón puede no estarlo (Safari no enfoca al hacer clic):
                // inferirlo de <body> daría un falso positivo y movería el foco
                // de quien nunca lo tuvo puesto (hallazgo de Codex).
                esperandoFoco.current = document.activeElement === boton.current
                onReintentar()
              }}
            >
              Reintentar
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
