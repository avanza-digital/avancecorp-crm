import * as v from 'valibot'

const entero = v.pipe(v.number(), v.integer(), v.minValue(0))
const fecha = v.pipe(v.string(), v.isoDate())

export const DetalleCierresCoordinacionSchema = v.strictObject({
  version: v.literal(1),
  analista_id: v.pipe(v.string(), v.uuid()),
  desde: fecha,
  hasta: fecha,
  disponible: v.boolean(),
  total: entero,
  pagina: entero,
  por_pagina: v.literal(20),
  filas: v.array(v.strictObject({
    nombre: v.string(),
    origen: v.string(),
    fecha,
    registro: v.picklist(['manual', 'sistema', 'cartera']),
    aporte: v.pipe(v.number(), v.minValue(0)),
  })),
})

export type DetalleCierresCoordinacion = v.InferOutput<typeof DetalleCierresCoordinacionSchema>

export function detalleCierresConsistente(d: DetalleCierresCoordinacion): boolean {
  if (!d.disponible) return d.total === 0 && d.pagina === 0 && d.filas.length === 0
  return d.pagina <= Math.max(0, Math.ceil(d.total / d.por_pagina) - 1)
    && d.filas.length === Math.min(d.por_pagina, d.total - d.pagina * d.por_pagina)
    && d.filas.every((f) => f.fecha >= d.desde && f.fecha <= d.hasta)
}
