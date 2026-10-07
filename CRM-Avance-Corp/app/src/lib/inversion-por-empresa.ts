import {EMPRESAS_INVERSION, type EmpresaInversion, type FichaInversionista} from './inversionistas'

/** Solo para la ficha multiempresa autorizada de inversionista_ficha_fn.
 * Los totales abarcan todas las páginas y conservan el historial aunque el
 * capital activo sea cero. No usar con la ficha antigua que solo conoce Avance.
 * null significa información inconsistente; nunca equivale a una empresa nueva.
 */
export function empresasSinHistorial(ficha: Pick<FichaInversionista, 'inversiones_total' | 'totales'>): EmpresaInversion[] | null {
  if (ficha.totales.reduce((total, fila) => total + fila.cantidad, 0) !== ficha.inversiones_total) return null
  const conocidas = new Set(ficha.totales.filter(fila => fila.cantidad > 0).map(fila => fila.empresa))
  return EMPRESAS_INVERSION.filter(empresa => !conocidas.has(empresa))
}

export const AYUDA_HISTORIAL_INCOMPLETO = 'Falta verificar en qué empresas tiene inversiones. Actualiza la ficha para continuar.'
export const AYUDA_TODAS_LAS_EMPRESAS = 'Este cliente ya tiene inversiones registradas en las tres empresas. Usa la continuidad que corresponda a cada inversión.'
