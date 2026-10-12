import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { DetalleCierresCoordinacionSchema, detalleCierresConsistente } from './conversion-cierres-coordinacion'

const datos = { version: 1 as const, analista_id: '20000000-0000-4000-8000-000000000001', desde: '2026-10-01', hasta: '2026-10-31', disponible: true, total: 1, pagina: 0, por_pagina: 20 as const, filas: [{ nombre: 'MANUAL', origen: 'landing', fecha: '2026-10-01', registro: 'manual' as const, aporte: 1 }] }
describe('contrato del detalle mínimo', () => {
  it('admite cierres manuales y rechaza PII extra en la respuesta', () => {
    expect(v.safeParse(DetalleCierresCoordinacionSchema, datos).success).toBe(true)
    expect(v.safeParse(DetalleCierresCoordinacionSchema, { ...datos, filas: [{ ...datos.filas[0], telefono: 'no permitido' }] }).success).toBe(false)
  })
  it('rechaza filas de otras fechas, truncamientos y contenido nominal sellado', () => {
    expect(detalleCierresConsistente(datos)).toBe(true)
    expect(detalleCierresConsistente({ ...datos, total: 2 })).toBe(false)
    expect(detalleCierresConsistente({ ...datos, disponible: false })).toBe(false)
    expect(detalleCierresConsistente({ ...datos, filas: [{ ...datos.filas[0]!, fecha: '2026-09-30' }] })).toBe(false)
    expect(detalleCierresConsistente({ ...datos, total: 0, filas: [], pagina: 1 })).toBe(false)
  })
})
