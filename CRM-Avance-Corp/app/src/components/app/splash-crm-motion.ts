type RectanguloSplash = Pick<DOMRect, 'left' | 'top' | 'width' | 'height'>

/**
 * Solo existe un viaje cuando el destino está realmente pintado. Un marcador
 * oculto sirve para conocer el layout, pero no es una marca visual con la cual
 * fusionarse: en ese caso la salida correcta es desvanecer el isotipo.
 */
export function calcularViajeSplash(
  origen: RectanguloSplash,
  destino: RectanguloSplash | undefined,
  destinoVisible: boolean,
): { x: number; y: number; scale: number } | null {
  if (
    !destinoVisible
    || !destino
    || origen.width <= 0
    || destino.width <= 0
    || destino.height <= 0
  ) {
    return null
  }

  return {
    x: destino.left + destino.width / 2 - (origen.left + origen.width / 2),
    y: destino.top + destino.height / 2 - (origen.top + origen.height / 2),
    scale: destino.width / origen.width,
  }
}
