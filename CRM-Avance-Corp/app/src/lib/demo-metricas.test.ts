import { describe, expect, it } from 'vitest'
import { demoAltasNuevasPorAnalista, demoFacturacionDiaria } from './demo-metricas'
import { CONTRATOS_DEMO } from './demo-clientes'
import { fechaLima } from './agenda-derivada'

it('la facturación demo conserva fechas, tipos y capital de sus contratos, sin inventar ventas recientes', () => {
  const meses = [...new Set(CONTRATOS_DEMO.map(c => `${c.fecha_cierre_comercial!.slice(0, 7)}-01`))]
  const filas = meses.flatMap(mes => demoFacturacionDiaria(mes))
  expect(filas.reduce((s, f) => s + f.operaciones, 0)).toBe(CONTRATOS_DEMO.length)
  for (const moneda of ['PEN', 'USD']) {
    expect(filas.filter(f => f.moneda === moneda).reduce((s, f) => s + f.capital, 0))
      .toBe(CONTRATOS_DEMO.filter(c => c.moneda === moneda).reduce((s, c) => s + c.capital, 0))
  }
  expect(new Set(filas.map(f => f.tipo))).toEqual(new Set(CONTRATOS_DEMO.map(c => `contrato_${c.categoria}`)))
  const hoy = fechaLima(Date.now())
  expect(demoFacturacionDiaria(`${hoy.slice(0, 7)}-01`).filter(f => f.dia === hoy)).toEqual([])
})

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
