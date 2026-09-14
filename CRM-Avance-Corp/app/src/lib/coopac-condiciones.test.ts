import {describe, expect, it} from 'vitest'
import {condicionesCoopac, vencimientoCoopac} from './coopac-condiciones'

describe('Condiciones COOPAC pactadas', () => {
  it.each([
    ['2026-01-31', '1', '2026-02-28'],
    ['2024-01-31', '1', '2024-02-29'],
    ['2024-02-29', '12', '2025-02-28'],
    ['2026-08-31', '6', '2027-02-28'],
    ['2026-09-14', '12', '2027-09-14'],
  ])('calcula %s + %s meses sin saltar el fin de mes', (fecha, plazo, esperado) => {
    expect(vencimientoCoopac(fecha, plazo)).toBe(esperado)
  })
  it('conserva el porcentaje anual: 12 significa 12%, y acepta coma decimal', () => {
    expect(condicionesCoopac('2026-09-14', '12', '12')).toEqual({ok:true, plazoMeses:12, tasaAnual:12, venceEn:'2027-09-14'})
    expect(condicionesCoopac('2026-09-14', '6', '12,50')).toMatchObject({ok:true, tasaAnual:12.5})
  })
  it.each(['', '0', '-1', '1.5', '1201', 'NaN'])('rechaza el plazo inválido %s', plazo => {
    expect(condicionesCoopac('2026-09-14', plazo, '12').ok).toBe(false)
  })
  it.each(['', '0', '-12', '12.345', '1,000', 'Infinity', '12%'])('exige un porcentaje manual válido: %s', tasa => {
    expect(condicionesCoopac('2026-09-14', '12', tasa).ok).toBe(false)
  })
  it('no calcula a partir de una fecha imposible', () => {
    expect(vencimientoCoopac('2026-02-31', '12')).toBeNull()
  })
})
