import type { Lead } from './tipos'

/** Compatibilidad de preferencias anteriores; los filtros nuevos usan origen. */
export const CAMPANIAS = ['Formulario 3'] as const
export type FiltroCampania = 'todas' | (typeof CAMPANIAS)[number]

export function esFiltroCampania(valor: unknown): valor is FiltroCampania {
  return valor === 'todas' || CAMPANIAS.some((campania) => campania === valor)
}

/** La campaña aporta contexto solo cuando no repite el origen de la ficha. */
export function muestraCampania(lead: Pick<Lead, 'campania_origen' | 'origen'>): boolean {
  return Boolean(lead.campania_origen)
    && !(lead.origen === 'formulario_3' && lead.campania_origen === 'Formulario 3')
}
