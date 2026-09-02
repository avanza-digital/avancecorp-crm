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
    const anterior = v.safeParse(MetricasConversionesEquipoSchema, payload())
    expect(anterior.success).toBe(true)
    if (!anterior.success) return
    expect('revision' in anterior.output).toBe(false)
    expect('cierre' in anterior.output).toBe(false)
  })

  it('conserva revisión y cierre de un mes calendario, con rollout compatible', () => {
    const mensual = v.safeParse(MetricasConversionesEquipoSchema, payload({
      periodo: { desde: '2026-08-01', hasta: '2026-08-31' },
      revision: 7,
      cierre: { cerrado: true, cerrado_en: '2026-09-10T14:20:00Z', automatico: true },
    }))
    expect(mensual.success).toBe(true)
    if (!mensual.success) return
    expect(mensual.output.revision).toBe(7)
    expect(mensual.output.cierre?.cerrado).toBe(true)

    // Un rango libre del productor nuevo usa null; el productor anterior omite
    // ambas claves. Los dos contratos conviven durante frontend→backend.
    expect(v.safeParse(MetricasConversionesEquipoSchema, payload({
      revision: null,
      cierre: null,
    })).success).toBe(true)
    expect(v.safeParse(MetricasConversionesEquipoSchema, payload()).success).toBe(true)
  })

  it.each([-1, 1.5, 'siete'])('rechaza una revisión de cosecha inválida: %s', (revision) => {
    expect(v.safeParse(MetricasConversionesEquipoSchema, {
      ...payload(),
      revision,
    }).success).toBe(false)
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

  it.each([
    ['cuadra true sin filas', { cuadra: true, paridad_nucleo: 0, paridad_filas: 0 }],
    ['cuadra null con filas', { cuadra: null, paridad_nucleo: 0, paridad_filas: 1 }],
    ['filas negativas', { cuadra: null, paridad_nucleo: 0, paridad_filas: -1 }],
    ['filas fraccionarias', { cuadra: true, paridad_nucleo: 0, paridad_filas: 1.5 }],
  ])('RECHAZA sondas imposibles: %s', (_caso, base) => {
    const r = v.safeParse(MetricasConversionesEquipoSchema, payload({
      sondas: {
        ...base,
        divisor_fuera_del_roster: 0,
        numerador_fuera_del_roster: 0,
        cierres_anulados: 0,
        clientes_acreditados_a_otro_dueno: 0,
      },
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

    expect(fantasma?.nombre).toBe('Analista no identificado')
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

describe('claves F2.2 (núcleo y sondas) — escritas desde el payload REAL de prod (27/08)', () => {
  it('acepta el payload real completo: nucleo, sondas y las cifras nucleo_* por responsable', () => {
    // Forma medida con la cadena viva (supervisor real) el 2026-08-27; los
    // valores extremos son los de prod: pct nulo sin divisor, numerador
    // fraccionario por la ponderación 0,15.
    const real = payload({
      nucleo: { base: 'asignacion', incluye_cartera: true, peso_referido: 0.15, mes_peso: '2026-08-01' },
      sondas: {
        cuadra: true,
        paridad_nucleo: 0,
        paridad_filas: 9,
        divisor_fuera_del_roster: 0,
        numerador_fuera_del_roster: 1,
        cierres_anulados: 1,
        clientes_acreditados_a_otro_dueno: 0,
      },
      responsables: [
        { vendedor_id: 'v-1', leads: 38, clientes: 5, conversion_pct: 13.2, nucleo_divisor: 38, nucleo_numerador: 6.15, nucleo_conversion_pct: 16.18 },
        { vendedor_id: 'v-2', leads: 0, clientes: 0, conversion_pct: null, nucleo_divisor: 0, nucleo_numerador: 0, nucleo_conversion_pct: null },
      ],
    })
    expect(() => v.parse(MetricasConversionesEquipoSchema, real)).not.toThrow()
  })

  it('un servidor previo a F2.2 (sin nucleo/sondas) sigue validando: las claves son aditivas', () => {
    expect(() => v.parse(MetricasConversionesEquipoSchema, payload())).not.toThrow()
  })

  it('caso vacío: cero responsables valida y el adaptador deja a todos indisponibles, no en 0 %', () => {
    const vacio = v.parse(MetricasConversionesEquipoSchema, payload({ responsables: [] }))
    const adaptada = adaptarConversionEquipo(vacio, EQUIPO)
    // Cero filas ≠ equipo en 0 %: el ranking no es representable y cada
    // analista queda fuera con estado explícito, jamás con un cero fabricado.
    expect(adaptada.responsablesDisponibles).toBe(false)
    expect(adaptada.vendedores.length).toBeGreaterThan(0)
    for (const fila of adaptada.vendedores) {
      expect(fila.estadoConversion).toBe('indisponible')
      expect(fila.detalle).toBeNull()
    }
  })

  it('RECHAZA unas sondas mutiladas: si el bloque viene, viene entero (la red de F3.4 no adivina)', () => {
    const mutilado = payload() as Record<string, unknown>
    mutilado.sondas = { cuadra: true }
    expect(() => v.parse(MetricasConversionesEquipoSchema, mutilado)).toThrow()
  })
})
