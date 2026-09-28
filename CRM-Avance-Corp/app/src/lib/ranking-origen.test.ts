import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { RankingOrigenVendedorSchema } from './ranking-origen'

const base = {
  version: 2,
  cartera: null,
  periodo: '2026-09-01',
  vendedor_id: '00000000-0000-4000-8000-000000000001',
  disponible: true,
  filas: [{
    origen: 'referido', capital_pen: '12000.50', capital_usd: '0',
    contratos: 1, leads: 8, cierres: 2, conversion_pct: '3.75',
  }],
}

describe('contrato RPC del desglose de Ranking', () => {
  it('acepta los numeric de PostgREST como texto y preserva el valor', () => {
    const dato = v.parse(RankingOrigenVendedorSchema, base)
    expect(dato.filas[0]).toMatchObject({ capital_pen: 12000.5, conversion_pct: 3.75 })
  })

  it('rechaza importes parciales cuando el servidor marca el desglose no disponible', () => {
    expect(v.safeParse(RankingOrigenVendedorSchema, { ...base, disponible: false }).success).toBe(false)
  })

  it('rechaza un origen repetido, que duplicaría capital en la ficha', () => {
    expect(v.safeParse(RankingOrigenVendedorSchema, {
      ...base, filas: [...base.filas, base.filas[0]],
    }).success).toBe(false)
  })
})

const cartera = [
  { categoria: 'renovacion', pen: 0, usd: 0 },
  { categoria: 'upgrade', pen: '577554', usd: '40000' },
  { categoria: 'nuevo', pen: 0, usd: 0 }, { categoria: 'sin_clasificar', pen: 0, usd: 0 },
]
it('preserva el desglose registrado de cartera legada con PEN y USD', () => {
  expect(v.parse(RankingOrigenVendedorSchema, { ...base, cartera }).cartera?.[1])
    .toEqual({ categoria: 'upgrade', pen: 577554, usd: 40000 })
})
it('rechaza categorías duplicadas o faltantes en cartera', () => {
  expect(v.safeParse(RankingOrigenVendedorSchema, { ...base, cartera: [cartera[0], cartera[1], cartera[1]] }).success).toBe(false)
  expect(v.safeParse(RankingOrigenVendedorSchema, { ...base, cartera: cartera.slice(0, 2) }).success).toBe(false)
})
