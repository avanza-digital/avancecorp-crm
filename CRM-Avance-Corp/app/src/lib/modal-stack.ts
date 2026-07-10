/** Indica si el elemento es el diálogo modal que está visualmente arriba. */
export function esModalSuperior(elemento: HTMLElement | null): boolean {
  if (!elemento) return false
  const modales = document.querySelectorAll('[aria-modal="true"]')
  return modales.length > 0 && modales[modales.length - 1] === elemento
}
