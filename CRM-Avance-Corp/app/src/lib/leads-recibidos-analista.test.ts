import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import type { Lead } from './tipos'
import {
  LeadsRecibidosAnalistaSchema,
  leadsRecibidosAnalistaConsistente,
  leadsRecibidosAnalistaDesdeAmbito,
} from './leads-recibidos-analista'

const REPORTE = {
  version: 1 as const,
  generado_en: '2026-09-12T15:00:00.000Z',
  periodo: {
    desde: '2026-09-10',
    hasta: '2026-09-12',
    dias: 3,
    zona: 'America/Lima' as const,
  },
  total: 3,
  aproximados: 1,
  dias: [
    { fecha: '2026-09-10', total: 2, aproximados: 1 },
    { fecha: '2026-09-11', total: 0, aproximados: 0 },
    { fecha: '2026-09-12', total: 1, aproximados: 0 },
  ],
}

function lead(sobre: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'LEAD DEMO',
    telefono: '+51999999999',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 10000,
    moneda: 'PEN',
    vendedor_id: 'analista-1',
    creado_en: '2026-09-10T14:00:00.000Z',
    activo: true,
    ...sobre,
  }
}

describe('LeadsRecibidosAnalista', () => {
  it('acepta una serie continua que reconcilia con los totales', () => {
    const reporte = v.parse(LeadsRecibidosAnalistaSchema, REPORTE)
    expect(leadsRecibidosAnalistaConsistente(reporte, '2026-09-10', '2026-09-12')).toBe(true)
  })

  it('rechaza caché cruzada, días ausentes y sumas que no reconcilian', () => {
    expect(leadsRecibidosAnalistaConsistente(REPORTE, '2026-09-09', '2026-09-12')).toBe(false)
    expect(leadsRecibidosAnalistaConsistente({
      ...REPORTE,
      dias: REPORTE.dias.slice(1),
    }, '2026-09-10', '2026-09-12')).toBe(false)
    expect(leadsRecibidosAnalistaConsistente({
      ...REPORTE,
      total: 4,
    }, '2026-09-10', '2026-09-12')).toBe(false)
  })

  it('el espejo demo usa tenencia_desde y conserva los días con cero', () => {
    const reporte = leadsRecibidosAnalistaDesdeAmbito([
      lead({ tenencia_desde: '2026-09-11T04:59:59.000Z' }), // 10/09 en Lima
      lead({
        id: 'lead-2',
        tenencia_desde: '2026-09-12T05:00:00.000Z', // 12/09 en Lima
      }),
      lead({
        id: 'lead-3',
        vendedor_id: 'otro-analista',
        tenencia_desde: '2026-09-12T15:00:00.000Z',
      }),
    ], 'analista-1', '2026-09-10', '2026-09-12', Date.parse('2026-09-12T16:00:00.000Z'))

    expect(reporte).toMatchObject({
      total: 2,
      aproximados: 0,
      dias: [
        { fecha: '2026-09-10', total: 1 },
        { fecha: '2026-09-11', total: 0 },
        { fecha: '2026-09-12', total: 1 },
      ],
    })
    expect(leadsRecibidosAnalistaConsistente(reporte, '2026-09-10', '2026-09-12')).toBe(true)
  })

  it('marca como aproximado el fallback a creado_en del demo', () => {
    const reporte = leadsRecibidosAnalistaDesdeAmbito(
      [lead()],
      'analista-1',
      '2026-09-10',
      '2026-09-10',
      Date.parse('2026-09-12T16:00:00.000Z'),
    )

    expect(reporte).toMatchObject({ total: 1, aproximados: 1 })
  })
})
