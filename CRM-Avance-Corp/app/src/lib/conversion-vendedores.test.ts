import { describe, expect, it } from 'vitest'
import { conversionEquipoDemo, metricasConversionesDemo } from './demo-inteligencia-comercial'
import {
  adaptarConversionVendedores,
  clasificarRankingCapital,
  clasificarRankingConversion,
} from './conversion-vendedores'

describe('adapter de responsables de conversión', () => {
  it('preserva indisponible cuando la RPC no incluye responsables', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete datos.responsables

    const adaptada = adaptarConversionVendedores(datos, conversionEquipoDemo())

    expect(adaptada.responsablesDisponibles).toBe(false)
    expect(adaptada.tendenciaSemanal).toBeNull()
    expect(adaptada.vendedores[0]).toMatchObject({
      detalle: null,
      estadoConversion: 'indisponible',
    })
    expect(clasificarRankingConversion(adaptada.vendedores)).toMatchObject({
      conPuesto: [],
      sinMuestra: [],
    })
  })

  it('rechaza el bloque completo cuando responsables llega vacío o parcial', () => {
    const vacio = metricasConversionesDemo('2026-08-01', '2026-08-31')
    vacio.responsables = []
    const equipo = conversionEquipoDemo().slice(0, 2)

    const adaptadaVacia = adaptarConversionVendedores(vacio, equipo)
    expect(adaptadaVacia.responsablesDisponibles).toBe(false)
    expect(adaptadaVacia.tendenciaSemanal).toBeNull()
    expect(adaptadaVacia.vendedores.every((fila) => fila.detalle == null)).toBe(true)

    const parcial = metricasConversionesDemo('2026-08-01', '2026-08-31')
    parcial.responsables = [parcial.responsables![0]!]
    const adaptadaParcial = adaptarConversionVendedores(parcial, equipo)
    expect(adaptadaParcial.responsablesDisponibles).toBe(false)
    expect(clasificarRankingConversion(adaptadaParcial.vendedores).conPuesto).toEqual([])
  })

  it('agrega la tendencia del período real y conserva semanas sin muestra como null', () => {
    const datos = metricasConversionesDemo('2026-06-03', '2026-06-23')
    datos.responsables = [
      {
        vendedor_id: 'demo-v1',
        leads: 2,
        contactados: 1,
        reuniones_realizadas: 0,
        clientes: 1,
        conversion_pct: 50,
        capital_pen: 0,
        capital_usd: 0,
        tendencia_semanal: [
          { semana: 1, desde: '2026-06-03', hasta: '2026-06-09', leads: 0, clientes: 0, conversion_pct: null },
          { semana: 2, desde: '2026-06-10', hasta: '2026-06-16', leads: 2, clientes: 1, conversion_pct: 50 },
        ],
      },
    ]

    const adaptada = adaptarConversionVendedores(datos, [conversionEquipoDemo()[0]!])

    expect(adaptada.tendenciaSemanal).toEqual([
      { semana: 1, desde: '2026-06-03', hasta: '2026-06-09', leads: 0, clientes: 0, conversion_pct: null },
      { semana: 2, desde: '2026-06-10', hasta: '2026-06-16', leads: 2, clientes: 1, conversion_pct: 50 },
    ])
  })

  it('deja las filas sin muestra y sin meta fuera de los puestos', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.responsables = [
      datos.responsables![0]!,
      {
        ...datos.responsables![1]!,
        leads: 0,
        clientes: 0,
        conversion_pct: null,
      },
      {
        ...datos.responsables![2]!,
        leads: 3,
        clientes: 1,
        conversion_pct: null,
      },
    ]
    const equipo = conversionEquipoDemo().slice(0, 3)
    const adaptada = adaptarConversionVendedores(datos, equipo)

    const conversion = clasificarRankingConversion(adaptada.vendedores)
    expect(conversion.conPuesto.map((fila) => fila.vendedorId)).toEqual(['demo-v1'])
    expect(conversion.sinMuestra.map((fila) => fila.vendedorId)).toEqual(['demo-v2'])
    expect(conversion.indisponibles.map((fila) => fila.vendedorId)).toEqual(['demo-v3'])

    const capital = clasificarRankingCapital(adaptada.vendedores, {
      'demo-v1': { vendedorId: 'demo-v1', supervisorId: 'demo-s1', capitalObjetivo: 400_000, ventasObjetivo: 5, conversionObjetivo: 15 },
    })
    expect(capital.conPuesto.map((fila) => fila.vendedor.vendedorId)).toEqual(['demo-v1'])
    expect(capital.sinMeta.map((fila) => fila.vendedor.vendedorId)).toEqual(['demo-v2', 'demo-v3'])
    expect(capital.indisponibles).toEqual([])
  })
})
