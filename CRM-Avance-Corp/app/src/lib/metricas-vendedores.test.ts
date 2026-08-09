// Mapper y espejo demo de crm.metricas_vendedores_fn: join con el roster (el
// payload no trae nombres por diseño), ceros para el miembro sin fila, y la
// ventana operativa de 45 días aplicada también en demo.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  MetricasVendedoresSchema,
  mapearMetricasVendedores,
  metricasVendedoresDesdeAmbito,
  type MetricasVendedoresPayload,
} from './metricas-vendedores'
import type { Lead, Miembro } from './tipos'

const AHORA = Date.parse('2026-08-09T15:00:00Z')
const DIA = 86_400_000
const iso = (ms: number): string => new Date(ms).toISOString()

const VEND1: Miembro = { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', supervisor_id: 's-1', activo: true }
const VEND2: Miembro = { perfil_id: 'v-2', nombre_completo: 'JUAN PEREZ', rol_crm: 'vendedor', supervisor_id: 's-1', activo: true }
const SUP: Miembro = { perfil_id: 's-1', nombre_completo: 'SUPERVISORA UNO', rol_crm: 'supervisor', supervisor_id: null, activo: true }
const EQUIPO = [SUP, VEND1, VEND2]

function payload(over: Record<string, unknown> = {}): MetricasVendedoresPayload {
  const r = v.safeParse(MetricasVendedoresSchema, {
    version: 1,
    generado_en: iso(AHORA),
    ventana_convertidos_dias: 45,
    vendedores: [],
    equipos: [],
    ...over,
  })
  if (!r.success) throw new Error('payload de prueba fuera de contrato')
  return r.output
}

function fila(over: Record<string, unknown> = {}) {
  return {
    vendedor_id: 'v-1',
    rol_crm: 'vendedor',
    activo: true,
    activos: 3,
    capital_pen: 30_000,
    capital_usd: 0,
    convertidos: 1,
    conversion_pct: 25,
    sin_tocar: 2,
    dias_sin_actividad_max: 4.5,
    ...over,
  }
}

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: `l-${Math.random().toString(36).slice(2, 8)}`,
    nombre_completo: 'LEAD DEMO',
    telefono: '+51987654321',
    etapa: 'contactado',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: iso(AHORA - DIA * 3),
    activo: true,
    ...over,
  }
}

describe('mapearMetricasVendedores', () => {
  it('une por id con el roster, rellena en ceros al que no tiene fila y ordena por capital PEN', () => {
    const conFilas = payload({
      vendedores: [fila({ vendedor_id: 'v-1', capital_pen: 30_000 })],
    })
    const { filas } = mapearMetricasVendedores(conFilas, [VEND2, VEND1], EQUIPO)
    expect(filas.map((f) => f.m.perfil_id)).toEqual(['v-1', 'v-2'])
    expect(filas[0]).toMatchObject({ capitalPEN: 30_000, conversion: 25, sinTocar: 2 })
    expect(filas[1]).toMatchObject({ activos: 0, capitalPEN: 0, conversion: 0, diasSinActividadMax: 0 })
    expect(filas[1]?.m.nombre_completo).toBe('JUAN PEREZ') // el nombre sale del roster, no del payload
  })

  it('la comparativa une supervisores con el roster completo y descarta filas sin miembro', () => {
    const conEquipos = payload({
      equipos: [
        { supervisor_id: 's-1', vendedores: 2, activos: 5, capital_pen: 50_000, capital_usd: 1_000, convertidos: 2, conversion_pct: 29, parkeados: 3 },
        { supervisor_id: 's-fantasma', vendedores: 1, activos: 1, capital_pen: 99_000, capital_usd: 0, convertidos: 0, conversion_pct: 0, parkeados: 0 },
      ],
    })
    const { equipos } = mapearMetricasVendedores(conEquipos, [], EQUIPO)
    expect(equipos).toHaveLength(1)
    expect(equipos[0]).toMatchObject({
      vendedores: 2,
      activos: 5,
      capitalPEN: 50_000,
      capitalUSD: 1_000,
      conversion: 29,
      parkeados: 3,
    })
    expect(equipos[0]?.supervisor.nombre_completo).toBe('SUPERVISORA UNO')
  })
})

describe('metricasVendedoresDesdeAmbito — espejo demo con ventana', () => {
  it('un convertido con más de 45 días sale del ranking y de la comparativa (mismo corte que el RPC)', () => {
    const leads = [
      lead({ id: 'l-abierto' }),
      lead({ id: 'l-cierre-nuevo', etapa: 'convertido', convertido_en: iso(AHORA - DIA * 10) }),
      lead({ id: 'l-cierre-viejo', etapa: 'convertido', convertido_en: iso(AHORA - DIA * 60) }),
    ]
    const espejo = metricasVendedoresDesdeAmbito([VEND1], EQUIPO, leads, [], AHORA)
    // base = suyos en ventana (abierto + cierre nuevo) → 1 convertido de 2 = 50 %
    expect(espejo.filas[0]).toMatchObject({ convertidos: 1, conversion: 50, activos: 1 })
    expect(espejo.equipos[0]).toMatchObject({ convertidos: 1 })
  })

  it('capital por moneda jamás se suma y los parkeados van aparte', () => {
    const leads = [
      lead({ monto_estimado: 1_000 }),
      lead({ id: 'l-usd', monto_estimado: 500, moneda: 'USD' }),
      lead({ id: 'l-parkeado', vendedor_id: null, asignado_supervisor_id: 's-1', monto_estimado: 700 }),
    ]
    const espejo = metricasVendedoresDesdeAmbito([VEND1], EQUIPO, leads, [], AHORA)
    expect(espejo.filas[0]).toMatchObject({ capitalPEN: 1_000, capitalUSD: 500 })
    expect(espejo.equipos[0]).toMatchObject({ capitalPEN: 1_000, capitalUSD: 500, parkeados: 1 })
  })
})
