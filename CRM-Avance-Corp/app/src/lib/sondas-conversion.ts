/**
 * Contrato mínimo compartido por las sondas que comparan una lectura con el
 * núcleo único de conversión. Los productores tienen más campos, pero estas
 * dos señales son las únicas que autorizan a pintar la cifra.
 */
export interface SondasParidadNucleo {
  cuadra?: boolean | null
  paridad_nucleo?: number | null
  paridad_filas?: number | null
}

/**
 * Fail-closed: la cifra solo es publicable cuando AMBAS señales llegaron y
 * confirman exactamente la misma foto (`cuadra=true`, desvío cero).
 *
 * No se usa truthiness ni tolerancia: `null`, una clave ausente, `false`, un
 * número no finito o cualquier desvío distinto de 0 dejan la cifra oculta.
 */
export function sondasNucleoVerificadas(
  sondas: SondasParidadNucleo | null | undefined,
): boolean {
  return sondas?.cuadra === true
    && sondas.paridad_nucleo === 0
    && Number.isInteger(sondas.paridad_filas)
    && Number(sondas.paridad_filas) > 0
}

export type EstadoVerificacionNucleo =
  | 'verificada'
  | 'descuadre'
  | 'sin_verificacion'

/** Distingue un fallo explícito de una verificación que no llegó o no corrió. */
export function estadoVerificacionNucleo(
  sondas: SondasParidadNucleo | null | undefined,
): EstadoVerificacionNucleo {
  if (sondasNucleoVerificadas(sondas)) return 'verificada'
  if (
    sondas == null
    || sondas.cuadra == null
    || sondas.paridad_nucleo == null
    || sondas.paridad_filas == null
  ) {
    return 'sin_verificacion'
  }
  return 'descuadre'
}
