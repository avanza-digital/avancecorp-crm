import { describe, expect, it } from 'vitest'
import { rotuloPeriodoPie } from './periodo'

describe('rotuloPeriodoPie', () => {
  it('con el rango igual al mes, una sola ventana', () => {
    const mes = { desde: '2026-09-01', hasta: '2026-09-24' }
    expect(rotuloPeriodoPie(mes, mes)).toBe('2026-09-01 al 2026-09-24')
    expect(rotuloPeriodoPie(mes, null)).toBe('2026-09-01 al 2026-09-24')
  })

  it('con un rango que cruza meses, nombra también la ventana mensual', () => {
    expect(rotuloPeriodoPie({ desde: '2026-08-25', hasta: '2026-09-05' }, { desde: '2026-09-01', hasta: '2026-09-24' }))
      .toBe('2026-08-25 al 2026-09-05 · Capital, metas y mejores analistas: 2026-09-01 al 2026-09-24')
  })
})
