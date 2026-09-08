import { describe, expect, it } from 'vitest'
import { CITAS_CRM, consultaInicial, consultarCitas, type CitaConLead } from './datos'
import { DEPOSITOS_EJEMPLO, depositosDeInasistencias, type DepositoEjemplo } from './depositos'

describe('depósitos posteriores a inasistencias del ejemplo', () => {
  const original = CITAS_CRM[30]!
  const confirmado = DEPOSITOS_EJEMPLO[0]!

  it('solo cuenta depósitos de quienes completaron reprogramación y asistencia', () => {
    const consulta = consultarCitas({ ...consultaInicial(), semana: '1', estados: ['no_show'] })
    const resumen = depositosDeInasistencias(consulta)
    expect(resumen).toMatchObject({ base: 4, convertidos: 1, porcentaje: 25, montos: { PEN: 35000, USD: 0 } })
    expect([resumen.base, resumen.reprogramadas.length, resumen.recuperadas.length, resumen.convertidos]).toEqual([4, 3, 1, 1])
    expect(resumen.leads.map(lead => lead.original.nombre)).toEqual(['Andrea Peralta'])
    expect(resumen.leads.flatMap(lead => lead.depositos.map(deposito => deposito.id))).toEqual(['DEP-001'])
    // DEP-002 sigue existiendo: se excluye por no completar el flujo, no por borrar el fixture.
    expect(DEPOSITOS_EJEMPLO.find(deposito => deposito.id === 'DEP-002')?.confirmadoEn).toBeTruthy()
    expect(depositosDeInasistencias(consultarCitas({ ...consultaInicial(), analista: 'diego' })).convertidos).toBe(0)
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
      { ...confirmado, id: 'antes-de-asistir', depositadoEn: '2026-09-02T12:00:00-05:00' },
      { ...confirmado, id: 'despues-hora-prevista-pero-antes-asistencia', depositadoEn: '2026-09-03T11:02:00-05:00' },
      { ...confirmado, id: 'al-mismo-instante', depositadoEn: '2026-09-03T11:05:00-05:00' },
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

  it('no sustituye una asistencia vinculada por otra cita, un estado o una fecha futura', () => {
    const asistencia = CITAS_CRM[18]!
    const sinVinculo: CitaConLead = { ...asistencia }
    delete sinVinculo.citaAnteriorId
    const sinAsistencia: CitaConLead = { ...asistencia }
    delete sinAsistencia.asistioEn
    for (const nueva of [
      sinVinculo,
      { ...asistencia, leadId: 'otro-lead' },
      { ...asistencia, estado: 'programada' as const },
      sinAsistencia,
      { ...asistencia, asistioEn: 'inválida' },
      { ...asistencia, asistioEn: '2026-09-08T11:00:00-05:00' },
      { ...asistencia, asistioEn: '2026-09-01T16:00:00-05:00' },
    ]) {
      expect(depositosDeInasistencias([original], [confirmado], undefined, [original, nueva]).convertidos).toBe(0)
    }
  })

  it('conserva la asistencia y el depósito aunque exista una nueva cita posterior', () => {
    const asistencia = CITAS_CRM[18]!
    const siguiente: CitaConLead = { ...asistencia, id: 'nueva-pendiente', estado: 'programada', fecha: '2026-09-10', citaAnteriorId: asistencia.id, reprogramadaEn: '2026-09-04T12:00:00-05:00' }
    delete siguiente.asistioEn
    const flujo = depositosDeInasistencias([original], [confirmado], undefined, [original, asistencia, siguiente])
    expect([flujo.base, flujo.reprogramadas.length, flujo.recuperadas.length, flujo.convertidos]).toEqual([1, 1, 1, 1])
    expect(flujo.reprogramadas[0]?.nueva?.id).toBe(siguiente.id)
    expect(flujo.recuperadas[0]?.nueva?.id).toBe(asistencia.id)
    expect(flujo.leads[0]?.asistencia.id).toBe(asistencia.id)
  })

  it('elige el mismo episodio de cada etapa aunque cambie el orden de las inasistencias', () => {
    const asistencia = CITAS_CRM[18]!
    const anterior: CitaConLead = { ...original, id: 'inasistencia-anterior', fecha: '2026-08-31' }
    const originalVinculada = { ...original, citaAnteriorId: anterior.id, reprogramadaEn: '2026-08-31T17:00:00-05:00' }
    const todas = [anterior, originalVinculada, asistencia]
    const flujo = depositosDeInasistencias([anterior, originalVinculada], [confirmado], undefined, todas)
    const inverso = depositosDeInasistencias([originalVinculada, anterior], [confirmado], undefined, todas)
    for (const etapa of ['inasistencias', 'reprogramadas', 'recuperadas', 'leads'] as const) {
      expect(flujo[etapa]).toEqual(inverso[etapa])
      expect(flujo[etapa][0]?.original.id).toBe(anterior.id)
    }
  })

  it('cada etapa es un subconjunto de la anterior para todos los asesores y semanas', () => {
    for (const analista of ['', ...new Set(CITAS_CRM.map(cita => cita.analista))]) {
      for (const semana of ['', '1', '2', '3', '4']) {
        const citas = consultarCitas({ ...consultaInicial(), analista, semana })
        const flujo = depositosDeInasistencias([...citas, ...citas])
        const etapas = [flujo.inasistencias, flujo.reprogramadas, flujo.recuperadas, flujo.leads].map(filas => filas.map(fila => fila.original.leadId))
        etapas.forEach((ids, indice) => {
          expect(new Set(ids).size).toBe(ids.length)
          if (indice > 0) expect(ids.every(id => etapas[indice - 1]!.includes(id))).toBe(true)
        })
      }
    }
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
