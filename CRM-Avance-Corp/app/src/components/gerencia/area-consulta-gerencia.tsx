import { useLayoutEffect, useRef, type ReactNode } from 'react'
import { useConsultaGerencia } from './use-consulta-gerencia'

/** Conserva el lugar de lectura al desmontarse una vista. Espera al contenido
 * diferido; cualquier interacción del usuario cancela la restauración. */
export function AreaConsultaGerencia({ vista, children, habilitada = true }: { vista: string; children: ReactNode; habilitada?: boolean }) {
  const elemento = useRef<HTMLDivElement>(null)
  const posiciones = useConsultaGerencia()?.posiciones

  useLayoutEffect(() => {
    const area = elemento.current
    if (!area || !posiciones || !habilitada) return
    const guardada = posiciones.current.get(vista)
    let restaurando = Boolean(guardada)
    let focoId = guardada?.focoId ?? null
    let observador: MutationObserver | undefined
    let cuadro = 0

    const guardar = () => {
      if (!restaurando) posiciones.current.set(vista, { scrollTop: area.scrollTop, focoId })
    }
    const dejarRestauracion = () => {
      restaurando = false
      observador?.disconnect()
      cancelAnimationFrame(cuadro)
    }
    const restaurar = () => {
      if (!restaurando || !guardada) return
      area.scrollTop = guardada.scrollTop
      let destino = guardada.focoId ? document.getElementById(guardada.focoId) : null
      if (destino && destino.getClientRects().length === 0 && /-(tabla|lista)$/.test(destino.id)) {
        const alternativa = destino.id.endsWith('-tabla')
          ? destino.id.replace(/-tabla$/, '-lista')
          : destino.id.replace(/-lista$/, '-tabla')
        destino = document.getElementById(alternativa)
      }
      // Un mismo analista tiene representación en tabla y lista. Sólo se
      // enfoca un control visible, nunca la variante oculta por el breakpoint.
      const puedeEnfocar = destino && area.contains(destino) && destino.getClientRects().length > 0
      if (puedeEnfocar && destino) destino.focus({ preventScroll: true })
      const scrollDisponible = area.scrollHeight - area.clientHeight >= guardada.scrollTop
      const consultaLista = area.querySelector('[data-consulta-lista="true"]') !== null
      if (consultaLista && !puedeEnfocar && guardada.focoId) {
        area.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]')?.focus({ preventScroll: true })
      }
      if (consultaLista || (scrollDisponible && (!guardada.focoId || puedeEnfocar))) dejarRestauracion()
    }
    const recordarFoco = (evento: FocusEvent) => {
      const destino = evento.target
      if (destino instanceof HTMLElement && destino.id) {
        focoId = destino.id
        guardar()
      }
    }
    const tomarControl = () => { dejarRestauracion(); guardar() }

    if (guardada) {
      observador = new MutationObserver(restaurar)
      observador.observe(area, { childList: true, subtree: true, characterData: true })
      cuadro = requestAnimationFrame(restaurar)
    }
    area.addEventListener('scroll', guardar, { passive: true })
    area.addEventListener('focusin', recordarFoco)
    for (const evento of ['pointerdown', 'keydown', 'wheel', 'touchstart']) {
      area.addEventListener(evento, tomarControl, { passive: true })
    }
    return () => {
      guardar()
      dejarRestauracion()
      area.removeEventListener('scroll', guardar)
      area.removeEventListener('focusin', recordarFoco)
      for (const evento of ['pointerdown', 'keydown', 'wheel', 'touchstart']) {
        area.removeEventListener(evento, tomarControl)
      }
    }
  }, [habilitada, posiciones, vista])

  return <div ref={elemento} data-vista-scroll={vista} className="ac-scroll flex-1 overflow-auto p-3 sm:p-6">{children}</div>
}
