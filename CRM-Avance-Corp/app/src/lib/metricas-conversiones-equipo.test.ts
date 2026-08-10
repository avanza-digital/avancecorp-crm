import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  MetricasConversionesEquipoSchema,
  adaptarConversionEquipo,
  type MetricasConversionesEquipo,
} from './metricas-conversiones-equipo'
import { clasificarRankingConversion } from './conversion-vendedores'
import type { ConversionEquipoVendedor } from './conversion-equipo'

const EQUIPO: ConversionEquipoVendedor[] = [
  { vendedorId: 'v-1', nombre: 'ANA TORRES', supervisorNombre: 'SUP UNO' },
  { vendedorId: 'v-2', nombre: 'LUIS PEREZ', supervisorNombre: 'SUP UNO' },
] as ConversionEquipoVendedor[]

function payload(over: Partial<MetricasConversionesEquipo> = {}): MetricasConversionesEquipo {
  return {
    version: 1,
    generado_en: '2026-08-10T01:00:00Z',
    alcance: 'equipo',
    periodo: { desde: '2026-07-12', hasta: '2026-08-10' },
    responsables: [
      { vendedor_id: 'v-1', leads: 20, clientes: 5, conversion_pct: 25 },
      { vendedor_id: 'v-2', leads: 10, clientes: 4, conversion_pct: 40 },
    ],
    ...over,
  }
}

describe('MetricasConversionesEquipoSchema — fail-closed sobre SU propio contrato', () => {
  it('acepta el payload del equipo', () => {
    expect(v.safeParse(MetricasConversionesEquipoSchema, payload()).success).toBe(true)
  })

  it('acepta conversion_pct nulo: sin muestra no hay porcentaje que afirmar', () => {
    const r = v.safeParse(MetricasConversionesEquipoSchema, payload({
      responsables: [{ vendedor_id: 'v-1', leads: 0, clientes: 0, conversion_pct: null }],
    }))

    expect(r.success).toBe(true)
  })

  it('RECHAZA una version distinta de 1 (cinturón contra un servidor adelantado)', () => {
    expect(v.safeParse(MetricasConversionesEquipoSchema, { ...payload(), version: 2 }).success).toBe(false)
  })

  it('RECHAZA un alcance inventado', () => {
    expect(v.safeParse(MetricasConversionesEquipoSchema, { ...payload(), alcance: 'todo' }).success).toBe(false)
  })

  it('RECHAZA un responsable al que le falte un campo del contrato', () => {
    const r = v.safeParse(MetricasConversionesEquipoSchema, payload({
      responsables: [{ vendedor_id: 'v-1', leads: 20, clientes: 5 } as never],
    }))

    expect(r.success).toBe(false)
  })

  it('NO exige los agregados globales de gerencia: es justo lo que esta RPC no calcula', () => {
    // Si este test se pusiera rojo, significaría que alguien reintrodujo el
    // esquema de gerencia aquí — y el supervisor volvería a ver el banner de
    // «formato inesperado» en vez de su ranking.
    const sinAgregados = payload()

    expect('cohorte' in sinAgregados).toBe(false)
    expect(v.safeParse(MetricasConversionesEquipoSchema, sinAgregados).success).toBe(true)
  })
})

describe('adaptarConversionEquipo', () => {
  it('une cada responsable con su identidad del roster', () => {
    const { vendedores, responsablesDisponibles } = adaptarConversionEquipo(payload(), EQUIPO)

    expect(responsablesDisponibles).toBe(true)
    expect(vendedores.map((x) => x.nombre).sort()).toEqual(['ANA TORRES', 'LUIS PEREZ'])
  })

  it('sin payload NO pone ceros: deja a todos indisponibles', () => {
    // Un 0 % se leería como «no convierte»; «indisponible» es la verdad.
    const { vendedores, responsablesDisponibles } = adaptarConversionEquipo(null, EQUIPO)

    expect(responsablesDisponibles).toBe(false)
    expect(vendedores.every((x) => x.estadoConversion === 'indisponible')).toBe(true)
    expect(vendedores.every((x) => x.detalle === null)).toBe(true)
  })

  it('una respuesta PARCIAL no reparte puestos entre los que llegaron', () => {
    const { responsablesDisponibles, vendedores } = adaptarConversionEquipo(
      payload({ responsables: [{ vendedor_id: 'v-1', leads: 20, clientes: 5, conversion_pct: 25 }] }),
      EQUIPO,
    )

    expect(responsablesDisponibles).toBe(false)
    expect(vendedores.every((x) => x.detalle === null)).toBe(true)
  })

  it('un responsable sin identidad en el roster no desaparece ni expone su UUID', () => {
    const { vendedores } = adaptarConversionEquipo(
      payload({
        responsables: [
          { vendedor_id: 'v-1', leads: 20, clientes: 5, conversion_pct: 25 },
          { vendedor_id: 'v-2', leads: 10, clientes: 4, conversion_pct: 40 },
          { vendedor_id: 'v-fantasma', leads: 3, clientes: 1, conversion_pct: 33 },
        ],
      }),
      EQUIPO,
    )
    const fantasma = vendedores.find((x) => x.vendedorId === 'v-fantasma')

    expect(fantasma?.nombre).toBe('Vendedor no identificado')
    expect(fantasma?.nombre).not.toContain('v-fantasma')
  })

  it('leads 0 es «sin muestra», no «0 % de conversión»', () => {
    const { vendedores } = adaptarConversionEquipo(
      payload({
        responsables: [
          { vendedor_id: 'v-1', leads: 0, clientes: 0, conversion_pct: null },
          { vendedor_id: 'v-2', leads: 10, clientes: 4, conversion_pct: 40 },
        ],
      }),
      EQUIPO,
    )

    expect(vendedores.find((x) => x.vendedorId === 'v-1')?.estadoConversion).toBe('sin_muestra')
  })
})

describe('el payload del equipo alimenta el MISMO clasificador que gerencia', () => {
  // Es la prueba de que no hicieron falta dos rankings: una sola lógica de orden
  // y desempates para los dos roles.
  it('ordena por conversión descendente', () => {
    const { vendedores } = adaptarConversionEquipo(payload(), EQUIPO)
    const ranking = clasificarRankingConversion(vendedores)

    expect(ranking.conPuesto.map((f) => f.vendedorId)).toEqual(['v-2', 'v-1'])
  })

  it('los de sin_muestra no compiten por puesto', () => {
    const { vendedores } = adaptarConversionEquipo(
      payload({
        responsables: [
          { vendedor_id: 'v-1', leads: 0, clientes: 0, conversion_pct: null },
          { vendedor_id: 'v-2', leads: 10, clientes: 4, conversion_pct: 40 },
        ],
      }),
      EQUIPO,
    )
    const ranking = clasificarRankingConversion(vendedores)

    expect(ranking.conPuesto.map((f) => f.vendedorId)).toEqual(['v-2'])
    expect(ranking.sinMuestra.map((f) => f.vendedorId)).toEqual(['v-1'])
  })
})
