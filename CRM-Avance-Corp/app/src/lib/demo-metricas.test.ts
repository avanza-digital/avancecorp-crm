import { describe, expect, it } from 'vitest'
import { demoAltasNuevasPorAnalista } from './demo-metricas'
import { CONTRATOS_DEMO } from './demo-clientes'

describe('demoAltasNuevasPorAnalista (espejo de crm.altas_nuevas_por_analista_fn)', () => {
  it('cuenta SOLO los contratos nuevos con cierre; renovaciones y upgrades no', () => {
    const filas = demoAltasNuevasPorAnalista()
    const esperadas = CONTRATOS_DEMO.filter(
      (c) => c.categoria === 'nuevo' && Boolean(c.fecha_cierre_comercial),
    ).length
    const contadas = filas.reduce((suma, f) => suma + f.altas, 0)
    expect(esperadas).toBeGreaterThan(0) // el fixture trae al menos un 'nuevo'
    expect(contadas).toBe(esperadas) // ni una renovación/upgrade colada
  })

  it('el mes sale del TEXTO de fecha_cierre_comercial (sin Date ni zona horaria)', () => {
    for (const fila of demoAltasNuevasPorAnalista()) {
      expect(fila.mes).toMatch(/^\d{4}-\d{2}-01$/)
      expect(fila.analista_id).toBeTruthy()
      expect(fila.analista_nombre).toBeTruthy()
      expect(fila.altas).toBeGreaterThan(0)
    }
  })
})
