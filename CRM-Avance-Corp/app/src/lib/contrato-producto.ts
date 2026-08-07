import type { ProductoCondicionSeleccion } from './productos-inversion'

export interface TerminosVariablesProducto {
  capital: number
  tasa: number
}

/** Validación de cortesía; el trigger repite las mismas reglas en servidor. */
export function validarRangosProducto(
  condicion: ProductoCondicionSeleccion,
  terminos: TerminosVariablesProducto,
): string | null {
  if (terminos.capital < condicion.capital_minimo || terminos.capital > condicion.capital_maximo) {
    return `El capital debe estar entre ${condicion.capital_minimo} y ${condicion.capital_maximo} ${condicion.moneda} para este producto.`
  }
  if (terminos.tasa < condicion.tasa_minima || terminos.tasa > condicion.tasa_maxima) {
    return `La tasa anual debe estar entre ${condicion.tasa_minima}% y ${condicion.tasa_maxima}% para este producto.`
  }
  return null
}
