import { describe, expect, it } from 'vitest'
import { CITAS_CRM, consultarCitas, consultaInicial } from './datos'
import { metaCitas, OBJETIVO_CITAS_POR_LEAD } from './metas'

describe('meta de tres citas por lead en la consulta', () => {
  it('separa el promedio del número de personas que alcanzaron tres citas y no redondea antes de calcular', () => {
    const total = metaCitas(CITAS_CRM)
    expect(total).toMatchObject({ citas: 40, leads: 26, leadsConMeta: 3 })
    expect(total.promedio).toBeCloseTo(1.538461538)
    expect(total.cumplimiento).toBeCloseTo(51.282051282)
    expect(total.cumplimiento).not.toBeCloseTo(1.54 / 3 * 100, 2)
    expect(metaCitas(consultarCitas({ ...consultaInicial(), analista: 'ana' }))).toMatchObject({ citas: 7, leads: 4, promedio: 1.75, leadsConMeta: 1 })
    expect(metaCitas(consultarCitas({ ...consultaInicial(), analista: 'ana', estados: ['realizada'] })).cumplimiento).toBeCloseTo(100 / 3)
  })

  it('llega a 125% con quince citas entre cuatro personas; un lead individual supera el objetivo con cuatro citas enteras', () => {
    const ejemplo = Array.from({ length: 15 }, (_, indice) => ({ ...CITAS_CRM[0]!, id: 'cita-' + indice, leadId: 'lead-' + indice % 4 }))
    expect(metaCitas(ejemplo)).toMatchObject({ citas: 15, leads: 4, promedio: 3.75, cumplimiento: 125, leadsConMeta: 4 })
    expect(OBJETIVO_CITAS_POR_LEAD).toBe(3.75)
    expect(metaCitas(ejemplo.filter(cita => cita.leadId === 'lead-0')).cumplimiento).toBeCloseTo(133.3333333)
    expect(metaCitas(CITAS_CRM.filter(cita => cita.leadId === 'L-031')).cumplimiento).toBeCloseTo(66.6666666)
  })

  it('recalcula leads únicos entre analistas y distingue una consulta sin base', () => {
    const base = CITAS_CRM[0]!
    const ejemplo = [
      { ...base, id: 'a', analista: 'ana', leadId: 'uno' },
      { ...base, id: 'b', analista: 'ana', leadId: 'uno' },
      { ...base, id: 'c', analista: 'diego', leadId: 'uno' },
      { ...base, id: 'd', analista: 'diego', leadId: 'dos' },
    ]
    expect(metaCitas(ejemplo)).toMatchObject({ leads: 2, promedio: 2, leadsConMeta: 1 })
    expect(metaCitas(ejemplo).cumplimiento).toBeCloseTo(200 / 3)
    expect(metaCitas([])).toMatchObject({ leads: 0, promedio: null, cumplimiento: null, leadsConMeta: 0 })
  })
})
