// El contrato del front con crm.cierres_externos_fn: el esquema tolerante (una
// clave nueva del servidor no rompe bundles viejos), los picklists cerrados (una
// cooperativa nueva SÍ exige tocar el front en el mismo release) y la aritmética
// del desglose (Avance = total − coops, clampada).
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  capitalAvance,
  CierresExternosSchema,
  COOPERATIVAS,
  INFO_COOPERATIVA,
} from './cierres-externos'

const CIERRE = {
  cierre_id: '3c9f0c2e-6cf2-4f4e-9b2e-3f4d5e6a7b8c',
  lead_id: '41000000-0000-4000-8000-000000001101',
  cooperativa: 'qorilazo',
  monto: 10000,
  moneda: 'PEN',
  nombre_completo: 'Cliente Qorilazo Uno',
  documento_tipo: 'DNI',
  documento: '41000001',
  telefono: '+51941001101',
  numero_transaccion: 'OP-2026-000123',
  referencia_externa: 'QOR-2026-001',
  vence_en: '2027-09-01',
  nota: null,
  vendedor_id: '41000000-0000-4000-8000-000000000002',
  vendedor_nombre: 'ORACULO CEXT A',
  creado_en: '2026-08-12T00:39:31.895Z',
  anulado_en: null,
  motivo_anulacion: null,
}

const PAYLOAD = {
  version: 1,
  periodo: '2026-08-01',
  alcance: 'propio',
  cierres: [CIERRE],
  cierres_total: 1,
  cierres_mes: [CIERRE],
  cierres_mes_total: 1,
  totales: [{ cooperativa: 'qorilazo', moneda: 'PEN', capital: 10000, cierres: 1 }],
  por_empresa: [{
    vendedor_id: CIERRE.vendedor_id,
    vendedor_nombre: 'ORACULO CEXT A',
    cooperativa: 'qorilazo',
    moneda: 'PEN',
    capital: 10000,
    cierres: 1,
  }],
}

describe('CierresExternosSchema', () => {
  it('acepta el payload del servidor tal cual', () => {
    const r = v.safeParse(CierresExternosSchema, PAYLOAD)
    expect(r.success).toBe(true)
  })

  it('normaliza los numeric que PostgREST sirva como string', () => {
    const conStrings = {
      ...PAYLOAD,
      cierres: [{ ...CIERRE, monto: '10000.00' }],
      totales: [{ cooperativa: 'qorilazo', moneda: 'PEN', capital: '10000.00', cierres: 1 }],
    }
    const r = v.safeParse(CierresExternosSchema, conStrings)
    expect(r.success).toBe(true)
    if (r.success) {
      expect(r.output.cierres[0]?.monto).toBe(10000)
      expect(r.output.totales[0]?.capital).toBe(10000)
    }
  })

  it('una clave NUEVA del servidor no rompe el bundle viejo (v.object laxo)', () => {
    const r = v.safeParse(CierresExternosSchema, { ...PAYLOAD, clave_futura: true })
    expect(r.success).toBe(true)
  })

  it('una cooperativa desconocida SÍ rechaza: el chip no se inventa solo', () => {
    const r = v.safeParse(CierresExternosSchema, {
      ...PAYLOAD,
      cierres: [{ ...CIERRE, cooperativa: 'coopac_nueva' }],
    })
    expect(r.success).toBe(false)
  })

  it('el lector global llega con cierres vacíos y el esquema lo admite', () => {
    const r = v.safeParse(CierresExternosSchema, {
      ...PAYLOAD,
      alcance: 'global',
      cierres: [],
      cierres_total: 5,
    })
    expect(r.success).toBe(true)
  })
})

describe('catálogo de cooperativas', () => {
  it('INFO_COOPERATIVA cubre EXACTAMENTE las cooperativas del CHECK', () => {
    expect(Object.keys(INFO_COOPERATIVA).sort()).toEqual([...COOPERATIVAS].sort())
  })

  it('ningún chip usa verde (regla de diseño de la casa)', () => {
    for (const info of Object.values(INFO_COOPERATIVA)) {
      expect(info.chipClase).not.toMatch(/green|emerald|lime/)
    }
  })
})

describe('capitalAvance', () => {
  it('resta lo cerrado en coops del total del cumplimiento', () => {
    expect(capitalAvance(13500, 3500)).toBe(10000)
  })

  it('clampa en 0: una carrera entre fotografías no pinta capital negativo', () => {
    expect(capitalAvance(1000, 1500)).toBe(0)
  })
})

describe('cierres anulados', () => {
  it('un cierre anulado viaja en las filas, marcado', () => {
    const r = v.safeParse(CierresExternosSchema, {
      ...PAYLOAD,
      cierres: [{
        ...CIERRE,
        anulado_en: '2026-08-12T10:00:00.000Z',
        motivo_anulacion: 'El depósito no existe',
      }],
    })
    expect(r.success).toBe(true)
    if (r.success) {
      expect(r.output.cierres[0]?.anulado_en).not.toBeNull()
      expect(r.output.cierres[0]?.motivo_anulacion).toBe('El depósito no existe')
    }
  })

  it('el N.° de operación es obligatorio en el contrato: sin él, no se parsea', () => {
    // Es la PRUEBA del cierre. Un payload sin ella significa que el servidor no
    // es el que este bundle cree, y es mejor fallar ruidosamente que pintar una
    // revisión sin el dato que la hace posible.
    const { numero_transaccion: _, ...sinTransaccion } = CIERRE
    const r = v.safeParse(CierresExternosSchema, { ...PAYLOAD, cierres: [sinTransaccion] })
    expect(r.success).toBe(false)
  })
})
