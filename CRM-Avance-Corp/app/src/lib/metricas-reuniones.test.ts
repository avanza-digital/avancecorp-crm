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
