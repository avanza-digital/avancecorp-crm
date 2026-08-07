import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  conversionEquipoDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
  seriesComercialesDemo,
} from './demo-inteligencia-comercial'
import { MetricasConversionesSchema } from './metricas-conversiones'
import { MetricasReunionesSchema } from './metricas-reuniones'

describe('contratos de inteligencia comercial', () => {
  it('mantiene los demos bajo el mismo contrato que las RPC', () => {
    expect(v.safeParse(
      MetricasConversionesSchema,
      metricasConversionesDemo('2026-06-01', '2026-08-05'),
    ).success).toBe(true)
    expect(v.safeParse(
      MetricasReunionesSchema,
      metricasReunionesDemo('2026-06-01', '2026-08-05'),
    ).success).toBe(true)
  })

  it('rechaza conversiones sin embudo atómico', () => {
    const demo = metricasConversionesDemo('2026-06-01', '2026-08-05')
    expect(v.safeParse(MetricasConversionesSchema, { ...demo, embudo: null }).success).toBe(false)
  })

  it('incluye un equipo demo suficiente para comparar y abrir detalle', () => {
    const equipo = conversionEquipoDemo()
    const detalle = metricasConversionesDemo('2026-08-01', '2026-08-31').responsables
    expect(equipo).toHaveLength(6)
    expect(equipo[0]).toMatchObject({ nombre: 'Ana Torres', leads: 42, conversionPct: 11.9 })
    expect(equipo.reduce((total, fila) => total + fila.leads, 0)).toBe(184)
    expect(equipo.reduce((total, fila) => total + fila.clientes, 0)).toBe(17)
    expect(seriesComercialesDemo().conversion).toHaveLength(6)
    expect(detalle).toHaveLength(6)
    expect(detalle?.[0]).toMatchObject({ vendedor_id: 'demo-v1', capital_pen: 360_000 })
    expect(detalle?.[0]?.tendencia_semanal).toHaveLength(4)
  })

  it('mantiene las metas demo explícitas y el cumplimiento confirmado separado del pipeline', () => {
    const metas = metasConversionEquipoDemo()
    const cumplimiento = cumplimientoMetasConversionEquipoDemo()

    expect(metas['demo-v1']?.conversionObjetivo).toBe(25)
    expect(cumplimiento.fuentesReales).toEqual({
      capitalYContratos: 'contratos_confirmados',
      conversion: 'leads_resueltos',
    })
    expect(cumplimiento.porVendedor['demo-v1']?.detalles).toEqual(expect.arrayContaining([
      expect.objectContaining({ moneda: 'PEN', capitalReal: 360_000, contratosReal: 3 }),
      expect.objectContaining({ moneda: 'USD', capitalReal: 20_000, contratosReal: 1 }),
    ]))
    expect(cumplimiento.porVendedor['demo-v1']).toMatchObject({
      convertidos: 5,
      resueltos: 42,
    })
  })

  it('rechaza reuniones con modalidad desconocida', () => {
    const demo = metricasReunionesDemo('2026-06-01', '2026-08-05')
    const payload = {
      ...demo,
      modalidades: [{ ...demo.modalidades[0], modalidad: 'telefonica' }],
    }
    expect(v.safeParse(MetricasReunionesSchema, payload).success).toBe(false)
  })
})
