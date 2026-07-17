// Paginación client-side compartida por las tablas largas del CRM (Clientes,
// Cartera; Contratos la adopta con su rediseño). La lógica PURA vive aquí para
// probarse sin React; el <nav> visual está en components/common/paginacion.tsx.
// El reset a página 0 al filtrar es estado local de cada pantalla, no de esta capa.

/** Tamaño de página único del CRM — mismo criterio en todas las tablas largas. */
export const POR_PAGINA = 50

export interface Paginado<T> {
  visibles: T[]
  paginas: number // mínimo 1 (una "página vacía" para el estado sin items)
  paginaActual: number // ya clampeada a [0, paginas-1]
}

/**
 * Recorta la página pedida. `pagina` fuera de rango se clampea — al filtrar
 * puede quedar apuntando a una página que ya no existe y la pantalla no debe
 * quedarse en blanco.
 */
export function paginar<T>(items: T[], pagina: number, porPagina = POR_PAGINA): Paginado<T> {
  const paginas = Math.max(1, Math.ceil(items.length / porPagina))
  const paginaActual = Math.min(Math.max(pagina, 0), paginas - 1)
  const visibles = items.slice(paginaActual * porPagina, (paginaActual + 1) * porPagina)
  return { visibles, paginas, paginaActual }
}
