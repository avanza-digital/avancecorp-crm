import { describe, expect, it } from 'vitest'
import { CITAS_CRM, consultaInicial, consultarCitas } from './datos'
import { DEPOSITOS_EJEMPLO, depositosDeInasistencias, type DepositoEjemplo } from './depositos'

describe('depósitos posteriores a inasistencias del ejemplo', () => {
  const original = CITAS_CRM[30]!
  const confirmado = DEPOSITOS_EJEMPLO[0]!

  it('incluye leads con y sin nueva cita, excluye pendiente/anulado y separa monedas', () => {
    const consulta = consultarCitas({ ...consultaInicial(), semana: '1', estados: ['no_show'] })
    const resumen = depositosDeInasistencias(consulta)
    expect(resumen).toMatchObject({ base: 4, convertidos: 2, porcentaje: 50, montos: { PEN: 35000, USD: 5000 } })
    expect(resumen.leads.map(lead => lead.original.nombre)).toEqual(['Andrea Peralta', 'Esteban Duarte'])
    expect(resumen.leads.flatMap(lead => lead.depositos.map(deposito => deposito.id))).toEqual(['DEP-001', 'DEP-002'])
    expect(depositosDeInasistencias(consultarCitas({ ...consultaInicial(), analista: 'ana' }))).toMatchObject({ base: 1, convertidos: 1, porcentaje: 100, montos: { PEN: 35000, USD: 0 } })
  })

  it('cuenta una vez al lead aunque tenga varias inasistencias y no duplica movimientos', () => {
    const otra = { ...original, id: 'otra-inasistencia', fecha: '2026-09-03' }
    const adicional: DepositoEjemplo = { ...confirmado, id: 'DEP-ADICIONAL', monto: 1000, moneda: 'USD' }
    const resumen = depositosDeInasistencias([otra, original, original], [confirmado, adicional, confirmado])
    expect(resumen).toMatchObject({ base: 1, convertidos: 1, porcentaje: 100, montos: { PEN: 35000, USD: 1000 } })
    expect(resumen.leads[0]?.original.id).toBe(original.id)
    expect(resumen.leads[0]?.depositos).toHaveLength(2)
  })

  it('un cierre o estimado no basta; excluye depósitos previos, futuros, no confirmados o inválidos', () => {
    const invalidados: DepositoEjemplo[] = [
      { ...confirmado, id: 'previo', depositadoEn: '2026-08-31T12:00:00-05:00' },
      { ...confirmado, id: 'futuro', depositadoEn: '2026-09-08T12:00:00-05:00', confirmadoEn: '2026-09-08T12:05:00-05:00' },
      { ...confirmado, id: 'confirmado-despues', confirmadoEn: '2026-09-08T12:00:00-05:00' },
      { ...confirmado, id: 'pendiente', confirmadoEn: null },
      { ...confirmado, id: 'anulado', anuladoEn: '2026-09-05T12:00:00-05:00' },
      { ...confirmado, id: 'fecha-invalida', depositadoEn: 'inválida' },
      { ...confirmado, id: 'confirmacion-previa', confirmadoEn: '2026-09-03T10:00:00-05:00' },
      { ...confirmado, id: 'sin-monto', monto: 0 },
      { ...confirmado, id: 'no-finito', monto: Infinity },
      { ...confirmado, id: 'otro-lead', leadId: 'fuera-de-la-consulta' },
    ]
    expect(depositosDeInasistencias([{ ...original, cerrado: true, monto: 999999 }], invalidados)).toMatchObject({ base: 1, convertidos: 0, porcentaje: 0, montos: { PEN: 0, USD: 0 } })
  })

  it('sigue depósitos fuera de la semana y solo aplica anulaciones conocidas al corte', () => {
    const posterior = { ...confirmado, depositadoEn: '2026-09-10T09:00:00-05:00', confirmadoEn: '2026-09-10T10:00:00-05:00', anuladoEn: '2026-09-12T09:00:00-05:00' }
    expect(depositosDeInasistencias([original], [posterior]).convertidos).toBe(0)
    expect(depositosDeInasistencias([original], [posterior], '2026-09-11T13:00:00-05:00').convertidos).toBe(1)
    expect(depositosDeInasistencias([original], [posterior], '2026-09-12T13:00:00-05:00').convertidos).toBe(0)
  })

  it('no inventa una tasa sin leads con inasistencia válida', () => {
    expect(depositosDeInasistencias([])).toMatchObject({ base: 0, convertidos: 0, porcentaje: null })
    expect(depositosDeInasistencias([{ ...original, estado: 'realizada' }, { ...original, fecha: '2026-09-20' }])).toMatchObject({ base: 0, convertidos: 0, porcentaje: null })
  })
})
