import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { metricasReunionesDemo } from './demo-inteligencia-comercial'
import { MetricasReunionesSchema } from './metricas-reuniones'

const CAMPOS_REALIZACION = [
  'divisor_realizacion',
  'canceladas_sistema_vencidas',
  'reprogramadas_vencidas',
] as const

describe('contrato de realización de citas por modalidad', () => {
  it('acepta el payload anterior sin introducir bases ni exclusiones de cero', () => {
    const payload = metricasReunionesDemo('2026-09-01', '2026-09-04')
    for (const modalidad of payload.modalidades) {
      for (const campo of CAMPOS_REALIZACION) delete modalidad[campo]
    }
    const datos = v.parse(MetricasReunionesSchema, payload)

    for (const modalidad of datos.modalidades) {
      for (const campo of CAMPOS_REALIZACION) expect(modalidad).not.toHaveProperty(campo)
    }
  })

  it('conserva el divisor, las exclusiones y el porcentaje recibidos', () => {
    const payload = metricasReunionesDemo('2026-09-01', '2026-09-04')
    Object.assign(payload.modalidades[0]!, {
      realizadas: 4,
      debieron_ocurrir: 21,
      divisor_realizacion: 17,
      canceladas_sistema_vencidas: 4,
      reprogramadas_vencidas: 0,
      pct_realizacion: 23.5,
    })

    expect(v.parse(MetricasReunionesSchema, payload).modalidades[0]).toMatchObject({
      realizadas: 4,
      debieron_ocurrir: 21,
      divisor_realizacion: 17,
      canceladas_sistema_vencidas: 4,
      reprogramadas_vencidas: 0,
      pct_realizacion: 23.5,
    })
  })

  it('normaliza conteos numéricos de la RPC sin inventar campos ausentes', () => {
    const payload = metricasReunionesDemo('2026-09-01', '2026-09-04')
    delete payload.modalidades[0]!.reprogramadas_vencidas
    Object.assign(payload.modalidades[0]!, { divisor_realizacion: '17', canceladas_sistema_vencidas: '4' })
    const modalidad = v.parse(MetricasReunionesSchema, payload).modalidades[0]!

    expect(modalidad.divisor_realizacion).toBe(17)
    expect(modalidad.canceladas_sistema_vencidas).toBe(4)
    expect(modalidad).not.toHaveProperty('reprogramadas_vencidas')
  })

  it('conserva un divisor cero y un porcentaje sin base como null', () => {
    const payload = metricasReunionesDemo('2026-09-01', '2026-09-04')
    Object.assign(payload.modalidades[0]!, {
      debieron_ocurrir: 6,
      realizadas: 0,
      reprogramadas: 2,
      divisor_realizacion: 0,
      canceladas_sistema_vencidas: 4,
      reprogramadas_vencidas: 2,
      pct_realizacion: null,
    })

    expect(v.parse(MetricasReunionesSchema, payload).modalidades[0]).toMatchObject({
      divisor_realizacion: 0,
      canceladas_sistema_vencidas: 4,
      reprogramadas_vencidas: 2,
      pct_realizacion: null,
    })
  })

  it('rechaza un divisor que no corresponde a las exclusiones o reprogramadas vencidas imposibles', () => {
    const divisor = metricasReunionesDemo('2026-09-01', '2026-09-04')
    divisor.modalidades[0]!.divisor_realizacion = 43
    expect(v.safeParse(MetricasReunionesSchema, divisor).success).toBe(false)

    const reprogramadas = metricasReunionesDemo('2026-09-01', '2026-09-04')
    reprogramadas.modalidades[0]!.reprogramadas_vencidas = 3
    expect(v.safeParse(MetricasReunionesSchema, reprogramadas).success).toBe(false)
  })

  it.each(CAMPOS_REALIZACION)('rechaza %s presente si no es un conteo válido', (campo) => {
    for (const valor of [null, -1, 0.5, '', 'no disponible', false, NaN, Infinity]) {
      const payload = metricasReunionesDemo('2026-09-01', '2026-09-04')
      Object.assign(payload.modalidades[0]!, { [campo]: valor })

      expect(v.safeParse(MetricasReunionesSchema, payload).success, `${campo}: ${String(valor)}`).toBe(false)
    }
  })
})

describe('bases y alcance de Citas de Gerencia', () => {
  it('conserva los nuevos campos y sigue aceptando respuestas anteriores', () => {
    const payload = metricasReunionesDemo('2026-09-01', '2026-09-07')
    const datos = v.parse(MetricasReunionesSchema, payload)
    expect(datos.resumen).toMatchObject({ divisor_realizacion: 72, divisor_asistencia: 66 })
    expect(datos.responsables[1]).toMatchObject({ divisor_realizacion: 24, debieron_ocurrir: 26, canceladas_sistema_vencidas: 1, canceladas_ajenas_vencidas: 0, reprogramadas_vencidas: 1, programadas_futuras: 1 })
    expect(datos.conversion.leads_con_cierre_previo).toBe(1)
    for (const campo of [...CAMPOS_REALIZACION, 'divisor_asistencia'] as const) delete payload.resumen[campo]
    for (const fila of payload.responsables) {
      for (const campo of [...CAMPOS_REALIZACION, 'debieron_ocurrir', 'canceladas_ajenas_vencidas', 'programadas_futuras'] as const) delete fila[campo]
    }
    for (const fila of [payload.conversion, ...payload.modalidades, ...payload.origenes]) delete fila.leads_con_cierre_previo
    const anterior = v.parse(MetricasReunionesSchema, payload)
    expect(anterior.resumen.divisor_realizacion).toBeUndefined()
    expect(anterior.responsables[0]!.divisor_realizacion).toBeUndefined()
    expect(anterior.conversion.leads_con_cierre_previo).toBeUndefined()
  })

  it('rechaza bases globales o de analista incompatibles sin corregirlas en el cliente', () => {
    const global = metricasReunionesDemo('2026-09-01', '2026-09-07')
    global.resumen.divisor_realizacion = 71
    expect(v.safeParse(MetricasReunionesSchema, global).success).toBe(false)
    const asistencia = metricasReunionesDemo('2026-09-01', '2026-09-07')
    asistencia.resumen.divisor_asistencia = 82
    expect(v.safeParse(MetricasReunionesSchema, asistencia).success).toBe(false)
    const analista = metricasReunionesDemo('2026-09-01', '2026-09-07')
    analista.responsables[1]!.divisor_realizacion = 27
    expect(v.safeParse(MetricasReunionesSchema, analista).success).toBe(false)
  })

  it('acepta historia fuera del desglose y rechaza filas que exceden el total', () => {
    const payload = metricasReunionesDemo('2026-08-01', '2026-08-31')
    payload.responsables.pop()
    expect(v.safeParse(MetricasReunionesSchema, payload).success).toBe(true)
    payload.responsables[0]!.pactadas = payload.resumen.pactadas + 1
    expect(v.safeParse(MetricasReunionesSchema, payload).success).toBe(false)
  })

  it('no admite que los cierres previos y posteriores dupliquen la base de prospectos', () => {
    const payload = metricasReunionesDemo('2026-09-01', '2026-09-07')
    payload.conversion.leads_con_cierre_previo = payload.conversion.leads_reunidos
    expect(v.safeParse(MetricasReunionesSchema, payload).success).toBe(false)
  })
})
