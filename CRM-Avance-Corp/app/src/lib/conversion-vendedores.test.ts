import { describe, expect, it } from 'vitest'
import {
  conversionEquipoDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from './demo-inteligencia-comercial'
import {
  adaptarConversionVendedores,
  clasificarRankingCapitalTotal,
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

    const todasLasMetas = metasConversionEquipoDemo()
    const capital = clasificarRankingCapitalTotal(
      adaptada.vendedores,
      { 'demo-v1': todasLasMetas['demo-v1']! },
      cumplimientoMetasConversionEquipoDemo().porVendedor,
      3.5,
    )
    expect(capital.conPuesto.map((fila) => fila.vendedor.vendedorId)).toEqual(['demo-v1'])
    // Sin meta se ordena por capital TOTAL desc: v2 = 290k + 16k×3.5 = 346k > v3 = 250k + 18k×3.5 = 313k.
    expect(capital.sinMeta.map((fila) => fila.vendedor.vendedorId)).toEqual(['demo-v2', 'demo-v3'])
    expect(capital.indisponibles).toEqual([])
    expect(capital.conPuesto[0]).toMatchObject({
      capitalPen: 360_000,
      capitalUsd: 20_000,
      capitalTotal: 430_000,
      metaCapital: 390_000,
    })
  })

  it('unifica capital y meta al TC del servidor (PEN + USD convertido, nunca sumado a ciegas)', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    const equipo = conversionEquipoDemo().slice(0, 1)
    datos.responsables = datos.responsables?.slice(0, 1)
    const adaptada = adaptarConversionVendedores(datos, equipo)
    const metas = metasConversionEquipoDemo()
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor

    const total = clasificarRankingCapitalTotal(adaptada.vendedores, metas, cumplimientos, 3.5)

    // demo-v1: real 360k PEN + 20k USD×3.5 = 430k; meta 250k PEN + 40k USD×3.5 = 390k.
    expect(total.tc).toBe(3.5)
    expect(total.conPuesto[0]).toMatchObject({
      capitalPen: 360_000,
      capitalUsd: 20_000,
      capitalTotal: 430_000,
      metaPen: 250_000,
      metaUsd: 40_000,
      metaCapital: 390_000,
    })
    expect(total.conPuesto[0]!.avance).toBeCloseTo((430_000 / 390_000) * 100, 6)
  })

  it('meta 100% en US$ sin TC → queda fuera del ranking pero con el split de la meta para rotularla', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    const equipo = conversionEquipoDemo().slice(0, 1)
    datos.responsables = datos.responsables?.slice(0, 1)
    const adaptada = adaptarConversionVendedores(datos, equipo)
    const metaV1 = metasConversionEquipoDemo()['demo-v1']!
    const soloUsd = { ...metaV1, detalles: metaV1.detalles.filter((d) => d.moneda === 'USD') }
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor

    const sinTc = clasificarRankingCapitalTotal(adaptada.vendedores, { 'demo-v1': soloUsd }, cumplimientos, null)
    // Sin TC no hay objetivo convertible: fuera del ranking, PERO metaUsd viaja
    // para que la UI diga «Meta en US$ · sin TC» y no el falso «Sin meta».
    expect(sinTc.sinMeta.map((f) => f.vendedor.vendedorId)).toEqual(['demo-v1'])
    expect(sinTc.sinMeta[0]).toMatchObject({ metaPen: 0, metaUsd: 40_000, metaCapital: null })

    // Con TC la MISMA meta sí compite.
    const conTc = clasificarRankingCapitalTotal(adaptada.vendedores, { 'demo-v1': soloUsd }, cumplimientos, 3.5)
    expect(conTc.conPuesto.map((f) => f.vendedor.vendedorId)).toEqual(['demo-v1'])
    expect(conTc.conPuesto[0]).toMatchObject({ metaCapital: 140_000 })
  })

  it('sin TC degrada a solo PEN con el USD aparte — jamás inventa una tasa', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    const equipo = conversionEquipoDemo().slice(0, 1)
    datos.responsables = datos.responsables?.slice(0, 1)
    const adaptada = adaptarConversionVendedores(datos, equipo)
    const metas = metasConversionEquipoDemo()
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor

    for (const tcInvalido of [null, 0, -1, Number.NaN]) {
      const total = clasificarRankingCapitalTotal(adaptada.vendedores, metas, cumplimientos, tcInvalido)
      expect(total.tc).toBeNull()
      // El USD sigue viajando (la UI lo rotula «aparte»), pero NO entra al total ni a la meta.
      expect(total.conPuesto[0]).toMatchObject({
        capitalPen: 360_000,
        capitalUsd: 20_000,
        capitalTotal: 360_000,
        metaPen: 250_000,
        metaUsd: 40_000,
        metaCapital: 250_000,
      })
    }
  })
})
