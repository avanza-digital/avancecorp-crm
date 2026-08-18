// lib/foco.ts — ¿el foco quedó huérfano? (F3.1, auditoría del 18/08)
//
// Un botón deshabilitado o desmontado SUELTA el foco: cae a body, o —dentro de
// un Dialog de Radix— al panel (el FocusScope recoge el foco de un elemento
// desmontado en el contenedor, que lleva tabindex="-1"). Nada de eso significa
// «el usuario está trabajando ahí». Un control interactivo con foco, en
// cambio, SÍ es el usuario: robárselo para «rescatarlo» sería peor que no
// rescatar nada.

/**
 * true si el foco actual NO pertenece a un control interactivo ajeno — es
 * decir, si moverlo es un rescate y no un robo. `propio` es el elemento del
 * que partió la acción (su foco «retenido» en un botón deshabilitado también
 * cuenta como huérfano rescatable).
 */
export function esFocoHuerfano(propio?: HTMLElement | null): boolean {
  const activo = document.activeElement
  if (!(activo instanceof HTMLElement)) return true
  if (activo === document.body) return true
  if (propio != null && activo === propio) return true
  return !activo.matches(
    'input, select, textarea, button, [href], [tabindex]:not([tabindex="-1"])',
  )
}
