// ¿El foco está en un campo donde se ESCRIBE? Contrato de los atajos de un
// carácter (WCAG 2.1.4): ahí un dígito es texto, no un atajo. Los radios y las
// casillas (donde cae el foco inicial de un selector) sí aceptan los atajos.
//
// Vive en lib/ y no junto al selector del resultado de la llamada porque
// `react(only-export-components)` prohíbe exportar no-componentes desde un
// archivo de componentes, y porque lo comparten varias pantallas.
export function esCampoDeTexto(el: EventTarget | null): boolean {
  if (!(el instanceof HTMLElement)) return false
  if (el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable) return true
  return el instanceof HTMLInputElement && !['radio', 'checkbox', 'button', 'submit'].includes(el.type)
}
