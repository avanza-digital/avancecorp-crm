import { describe, expect, it } from 'vitest'
import { coincideFechaRecepcionDemo, periodoFechaCartera, rangoFechaCarteraValido } from './filtro-fecha-cartera'
import type { Lead } from './tipos'

const rango = { desde: '2026-09-01', hasta: '2026-09-03' }

describe('filtro de recepción de la vista local', () => {
  it.each([
    ['2026-09-01T04:59:59Z', false],
    ['2026-09-01T05:00:00Z', true],
    ['2026-09-04T04:59:59Z', true],
    ['2026-09-04T05:00:00Z', false],
  ])('respeta ambos extremos del día de Lima: %s', (tenencia_desde, esperado) => {
    expect(coincideFechaRecepcionDemo({ tenencia_desde } as Lead, rango)).toBe(esperado)
  })

  it('prefiere recepción sobre creación y no usa la última edición', () => {
    expect(coincideFechaRecepcionDemo({
      tenencia_desde: '2026-09-02T12:00:00-05:00', creado_en: '2026-08-01T12:00:00-05:00',
      actualizado_en: '2026-09-13T12:00:00-05:00',
    } as Lead, rango)).toBe(true)
  })

  it('los siete días incluyen hoy y cruzan meses', () => {
    expect(periodoFechaCartera('semana', rango, '2026-09-03'))
      .toEqual({ desde: '2026-08-28', hasta: '2026-09-03' })
    expect(periodoFechaCartera('todas', rango, '2026-09-03')).toBeNull()
  })

  it('rechaza fechas imposibles, vacías, futuras y rangos invertidos', () => {
    for (const invalido of [
      { desde: '', hasta: '2026-09-03' },
      { desde: '2026-02-30', hasta: '2026-09-03' },
      { desde: '2026-09-04', hasta: '2026-09-03' },
      { desde: '2026-09-01', hasta: '2026-09-14' },
    ]) expect(rangoFechaCarteraValido(invalido, '2026-09-13')).toBe(false)
    expect(rangoFechaCarteraValido(rango, '2026-09-13')).toBe(true)
  })
})
