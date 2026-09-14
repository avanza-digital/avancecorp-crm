import { vencimientoDesdePlazo } from './cronograma'
import { parseMonto } from './numero'

export type CampoCondicionesCoopac = 'fecha' | 'plazo' | 'tasa'
const fechaValida = (fecha: string) => /^\d{4}-\d{2}-\d{2}$/.test(fecha)
  && Number(fecha.slice(0, 4)) >= 1000 && vencimientoDesdePlazo(fecha, 0) === fecha

/** Meses naturales: el mismo ajuste de fin de mes que usan los contratos Avance. */
export function vencimientoCoopac(fecha: string, plazo: string): string | null {
  const meses = Number(plazo)
  if (!/^\d+$/.test(plazo.trim()) || !Number.isInteger(meses) || meses < 1 || meses > 1200) return null
  if (!fechaValida(fecha)) return null
  return vencimientoDesdePlazo(fecha, meses)
}

export function condicionesCoopac(fecha: string, plazo: string, tasa: string) {
  if (!fechaValida(fecha)) return {ok: false, campo: 'fecha', error: 'Indica una fecha de inicio válida.'} as const
  const venceEn = vencimientoCoopac(fecha, plazo)
  if (!venceEn) return {ok: false, campo: 'plazo', error: 'Indica un plazo de 1 a 1200 meses enteros.'} as const
  const tasaAnual = parseMonto(tasa)
  if (tasaAnual === null || tasaAnual <= 0) return {
    ok: false, campo: 'tasa', error: 'Ingresa la rentabilidad anual pactada, con hasta dos decimales. Por ejemplo: 12 para 12% anual.',
  } as const
  return {ok: true, plazoMeses: Number(plazo), tasaAnual, venceEn} as const
}
