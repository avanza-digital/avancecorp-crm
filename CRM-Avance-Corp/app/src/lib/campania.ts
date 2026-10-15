/** Campañas disponibles en el filtro; el canal comercial permanece independiente. */
export const CAMPANIAS = ['Formulario 3'] as const
export type FiltroCampania = 'todas' | (typeof CAMPANIAS)[number]

export function esFiltroCampania(valor: unknown): valor is FiltroCampania {
  return valor === 'todas' || CAMPANIAS.some((campania) => campania === valor)
}
