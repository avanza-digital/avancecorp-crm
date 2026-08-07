import { describe, expect, it } from 'vitest'
import type { ProductoCondicionSeleccion } from './productos-inversion'
import { validarRangosProducto } from './contrato-producto'

const CONDICION: ProductoCondicionSeleccion = {
  condicion_id: '10000000-0000-4000-8000-000000000001',
  producto_id: '20000000-0000-4000-8000-000000000001',
  producto_codigo: 'RENTA-BASE',
  producto_revision: 1,
  version_id: '30000000-0000-4000-8000-000000000001',
  numero_version: 1,
  version_nombre: 'Plan base',
  vigente_desde: '2026-01-01',
  vigente_hasta: null,
  categoria: 'nuevo',
  moneda: 'PEN',
  plazo_meses: 12,
  modalidad: 'mensual',
  tipo_interes: 'simple',
  capital_minimo: 5_000,
  capital_maximo: 50_000,
  tasa_referencia: 15,
  tasa_minima: 12,
  tasa_maxima: 18,
}

describe('validarRangosProducto', () => {
  it('acepta inclusivamente ambos extremos', () => {
    expect(validarRangosProducto(CONDICION, { capital: 5_000, tasa: 12 })).toBeNull()
    expect(validarRangosProducto(CONDICION, { capital: 50_000, tasa: 18 })).toBeNull()
  })

  it('rechaza capital y tasa fuera del snapshot elegido', () => {
    expect(validarRangosProducto(CONDICION, { capital: 4_999.99, tasa: 15 })).toMatch(/capital/i)
    expect(validarRangosProducto(CONDICION, { capital: 10_000, tasa: 18.01 })).toMatch(/tasa anual/i)
  })
})
