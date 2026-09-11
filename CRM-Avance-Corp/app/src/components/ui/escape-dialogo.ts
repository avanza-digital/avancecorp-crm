import type { KeyboardEvent as EventoTecladoReact } from 'react'

const selectorCapa = '[data-slot="dialog"], [data-slot="sheet"]'
const escapesAnidados = new WeakSet<KeyboardEvent>()

function capaDelEvento(destino: EventTarget | null) {
  return destino instanceof Element ? destino.closest(selectorCapa) : null
}

// Durante una reapertura Radix puede conservar el listener de la ficha inferior.
// Su captura no debe cerrar una ficha cuando la tecla nació en otro diálogo.
export function protegerEscapeAnidado(evento: KeyboardEvent, contenido: HTMLElement | null) {
  const capa = capaDelEvento(evento.target)
  if (capa && contenido && capa !== contenido) {
    evento.preventDefault()
    escapesAnidados.add(evento)
  }
}

// Solo recupera la tecla detenida por la guarda anterior. El resto de Escape,
// el focus trap y la interacción con controles siguen a cargo de Radix.
export function cerrarEscapeAnidado(evento: EventoTecladoReact<HTMLElement>, cerrar: () => void) {
  if (evento.key !== 'Escape' || !escapesAnidados.has(evento.nativeEvent)
      || capaDelEvento(evento.target) !== evento.currentTarget) return
  escapesAnidados.delete(evento.nativeEvent)
  evento.preventDefault()
  evento.stopPropagation()
  cerrar()
}
