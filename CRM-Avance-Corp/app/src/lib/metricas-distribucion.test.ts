import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { MetricasDistribucionLeadsV3Schema } from './metricas-distribucion'
import { metricasDistribucionDemo } from './demo-metricas-distribucion'

// El contrato V3 es de cierre hermético en TODOS los niveles, igual que el V2
// del bundle vivo: una clave de más rompe tan fuerte como una de menos. Estos
// casos vigilan que nadie relaje eso sin darse cuenta.
describe('MetricasDistribucionLeadsV3Schema', () => {
  it('acepta el payload demo completo (espejo de la forma REAL medida en prod)', () => {
    const resultado = v.safeParse(MetricasDistribucionLeadsV3Schema, metricasDistribucionDemo('2026-08-01', '2026-08-27'))
    expect(resultado.success).toBe(true)
  })

  it('rechaza una clave desconocida en la raíz (cierre hermético)', () => {
    const conExtra = { ...metricasDistribucionDemo('2026-08-01', '2026-08-27'), sorpresa: 1 }
    expect(v.safeParse(MetricasDistribucionLeadsV3Schema, conExtra).success).toBe(false)
  })

  it('rechaza un payload V2 (sin conversion ni sondas): la puerta vieja no pasa por la nueva', () => {
    const demo = metricasDistribucionDemo('2026-08-01', '2026-08-27')
    const { sondas: _sondas, ...sinSondas } = demo
    expect(v.safeParse(MetricasDistribucionLeadsV3Schema, sinSondas).success).toBe(false)
    const sinConversion = {
      ...demo,
      version: 2,
      resumen: (({ conversion: _c, ...resto }) => resto)(demo.resumen),
    }
    expect(v.safeParse(MetricasDistribucionLeadsV3Schema, sinConversion).success).toBe(false)
  })

  it('pct NULL sobrevive el parseo («aún no se sabe» no es 0)', () => {
    const demo = metricasDistribucionDemo('2026-08-01', '2026-08-27')
    const primero = demo.analistas[0]
    if (!primero) throw new Error('demo sin analistas')
    const conNull = {
      ...demo,
      analistas: [
        {
          ...primero,
          conversion: {
            ...primero.conversion,
            usd: { convertidos: 0, resueltos: 0, pct: null },
          },
        },
        ...demo.analistas.slice(1),
      ],
    }
    const resultado = v.safeParse(MetricasDistribucionLeadsV3Schema, conNull)
    expect(resultado.success).toBe(true)
    if (resultado.success) {
      expect(resultado.output.analistas[0]?.conversion.usd.pct).toBeNull()
    }
  })

  it('un pct negativo no pasa (el servidor jamás sirve punterías negativas)', () => {
    const demo = metricasDistribucionDemo('2026-08-01', '2026-08-27')
    const roto = {
      ...demo,
      resumen: {
        ...demo.resumen,
        conversion: {
          ...demo.resumen.conversion,
          pen: { ...demo.resumen.conversion.pen, pct: -1 },
        },
      },
    }
    expect(v.safeParse(MetricasDistribucionLeadsV3Schema, roto).success).toBe(false)
  })
})
