import { describe, expect, it } from 'vitest'
import {
  conversionMensualInteligenciaDemo,
  conversionEquipoDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from './demo-inteligencia-comercial'
import {
  adaptarAporteConversionRango,
  adaptarConversionMensualPorFuente,
  adaptarConversionMensual,
  adaptarConversionVendedores,
  clasificarRankingCapitalTotal,
  clasificarRankingConversion,
} from './conversion-vendedores'

function metricasConNucleo() {
  const datos = metricasConversionesDemo('2026-09-01', '2026-09-07')
  datos.origen_filtrado = null
  datos.nucleo = {
    base: 'llegada_unica',
    atribucion: 'primer_analista',
    llegadas: 110,
    altas_manuales: 9,
    renovaciones: 1,
    upgrades: 1,
    aporte_cartera: 1.15,
    peso_renovacion: 0.15,
    divisor: 100,
    numerador: 4.3,
    conversion_pct: 4.3,
    cierres_no_referidos: 3,
    cierres_referidos: 1,
    referidos_recibidos: 1,
    referidos_cierran_pct: 100,
    operaciones_cartera: 2,
    peso_referido: 0.15,
    mes_peso: '2026-09-01',
    incluye_cartera: true,
  }
  datos.sondas = {
    cuadra: true,
    paridad_nucleo: 0,
    paridad_filas: 6,
    divisor_fuera_del_roster: 0,
    numerador_fuera_del_roster: 0,
    cierres_sin_ficha_convertida: 0,
    cohorte_convertidos_sin_cierre_elegible: 0,
    cartera_fuera_del_rango: 0,
    cierres_anulados: 0,
    episodios_sin_origen: 0,
    origen_ficha_distinto_del_ledger: 0,
  }
  datos.responsables = datos.responsables?.map((fila, indice) => ({
    ...fila,
    nucleo_divisor: indice === 0 ? 25 : 15,
    nucleo_numerador: indice === 0 ? 1.15 : indice === 1 ? 1 : 0,
    nucleo_conversion_pct: indice === 0 ? 4.6 : indice === 1 ? 6.67 : 0,
  }))
  return datos
}

describe('filtro por fuente del índice comercial', () => {
  it('combina Landing, Formulario y Upgrade usando una sola base y los aportes servidos', () => {
    const datos = metricasConNucleo()
    const landing = structuredClone(datos)
    const formulario = structuredClone(datos)
    for (const [lectura, origen, cantidad] of [[landing, 'landing', 2], [formulario, 'formulario', 1]] as const) {
      lectura.origen_filtrado = origen
      Object.assign(lectura.cierres_por_semana!, { origen_filtrado: origen, cierres: cantidad, aporte_cierres: cantidad })
      lectura.responsables = lectura.responsables!.map((fila, indice) => ({
        ...fila, cierres_por_semana: [{ semana: 1, desde: '2026-09-01', hasta: '2026-09-07', cierres: indice === 0 ? cantidad : 0, aporte_cierres: indice === 0 ? cantidad : 0 }],
      }))
    }
    const lectura = adaptarAporteConversionRango(datos, ['landing', 'formulario', 'upgrade'], { landing, formulario })
    expect(lectura).toMatchObject({ divisor: 100, numerador: 4, porcentaje: 4, cierres: 3, operaciones: 1, resultados: 4 })
    expect(lectura?.porVendedor.get('demo-v1')).toMatchObject({ divisor: 25, numerador: 3, porcentaje: 12, cierres: 3, operaciones: 0 })
    expect(lectura?.porVendedor.get('demo-v2')).toMatchObject({ cierres: 0, operaciones: 1 })
    expect(adaptarAporteConversionRango(datos, ['landing', 'formulario', 'upgrade'], { landing })).toBeNull()
    formulario.periodo.hasta = '2026-09-06'
    expect(adaptarAporteConversionRango(datos, ['landing', 'formulario'], { landing, formulario })).toBeNull()
    expect(adaptarAporteConversionRango(datos, [])).toBeNull()
  })

  it('no usa un rango almacenado para sustituir los cierres o el índice mensual', () => {
    const datos = metricasConNucleo()
    const mensual = conversionMensualInteligenciaDemo(Date.parse('2026-09-07T12:00:00-05:00'))
    const lectura = adaptarAporteConversionRango(datos, null)!
    lectura.periodo.desde = '2026-09-04'
    expect(adaptarConversionMensualPorFuente(mensual, conversionEquipoDemo(), null, lectura))
      .toEqual(adaptarConversionMensual(mensual, conversionEquipoDemo()))
  })

  it('rechaza el rango parcial y la lectura viva para un mes sellado', () => {
    const datos = metricasConNucleo()
    const mensual = conversionMensualInteligenciaDemo(Date.parse('2026-09-07T12:00:00-05:00'))
    const lectura = adaptarAporteConversionRango(datos, 'upgrade')!
    lectura.periodo.desde = '2026-09-04'
    expect(adaptarConversionMensualPorFuente(mensual, conversionEquipoDemo(), 'upgrade', lectura).responsablesDisponibles).toBe(false)
    lectura.periodo.desde = '2026-09-01'
    mensual.cierre = { cerrado: true }
    expect(adaptarConversionMensualPorFuente(mensual, conversionEquipoDemo(), 'upgrade', lectura).vendedores.every((fila) => fila.detalle == null)).toBe(true)
    expect(adaptarConversionMensualPorFuente(mensual, conversionEquipoDemo(), null, lectura))
      .toEqual(adaptarConversionMensual(mensual, conversionEquipoDemo()))
  })

  it('conserva el total servido y aísla las operaciones ya ponderadas', () => {
    const datos = metricasConNucleo()

    expect(adaptarAporteConversionRango(datos, null)).toMatchObject({
      etiqueta: 'Todos los aportes',
      divisor: 100,
      numerador: 4.3,
      porcentaje: 4.3,
      resultados: 6,
    })
    expect(adaptarAporteConversionRango(datos, 'upgrade')).toMatchObject({
      etiqueta: 'Upgrade',
      familia: 'cartera',
      divisor: 100,
      numerador: 1,
      porcentaje: 1,
      resultados: 1,
      peso: 1,
    })
    expect(adaptarAporteConversionRango(datos, 'renovacion')).toMatchObject({
      numerador: 0.15,
      porcentaje: 0.15,
      resultados: 1,
      peso: 0.15,
    })
  })

  it('rotula el desglose con el peso VIVO aunque la foto se sellara con otro', () => {
    const datos = metricasConNucleo()
    // Mes sellado: la foto se cerró con 0,73 y el total de arriba es suyo. La
    // tabla viva ya va por 0,11, y el desglose de renovaciones se recalcula con
    // ella. El rótulo sigue al desglose, no a la foto: publicar 0,73 aquí sería
    // rotular lo vivo con la foto. El peso de la foto viaja aparte.
    datos.nucleo = {
      ...datos.nucleo!,
      peso_referido: 0.19,
      peso_renovacion: 0.11,
      ponderacion_oficial: { referido: 0.58, renovacion: 0.73, fuente: 'crm.periodos_cerrados' },
      divisor: 200,
      numerador: 9,
      conversion_pct: 4.5,
      recalculo_vivo: { divisor: 100, numerador: 4.3, conversion_pct: 4.3 },
    }
    expect(adaptarAporteConversionRango(datos, 'renovacion')).toMatchObject({
      numerador: 0.15,
      porcentaje: 0.15,
      peso: 0.11,
    })
    expect(adaptarAporteConversionRango(datos, 'referido')).toBeNull()
  })

  it('publica la base con la que dividió: oficial sin filtro, viva con fuente', () => {
    const datos = metricasConNucleo()
    datos.nucleo = {
      ...datos.nucleo!,
      divisor: 200,
      numerador: 9,
      conversion_pct: 4.5,
      recalculo_vivo: { divisor: 100, numerador: 4.3, conversion_pct: 4.3 },
    }
    expect(adaptarAporteConversionRango(datos, null)).toMatchObject({ divisor: 200, porcentaje: 4.5 })
    // 0,15 ÷ 100 = 0,15 %: el % se calculó sobre la base viva y la publica.
    expect(adaptarAporteConversionRango(datos, 'renovacion')).toMatchObject({ divisor: 100, porcentaje: 0.15 })
    expect(adaptarAporteConversionRango(datos, 'upgrade')).toMatchObject({ divisor: 100 })
    // Antes la cartera devolvía la base oficial (200) y la multiselección, que
    // exige la viva, caía entera a «no disponible».
    expect(adaptarAporteConversionRango(datos, ['upgrade', 'renovacion'])).not.toBeNull()
  })

  it('acepta un origen de prospecto solo cuando el servidor confirma el mismo filtro', () => {
    const datos = metricasConNucleo()
    expect(adaptarAporteConversionRango(datos, 'landing')).toBeNull()

    datos.origen_filtrado = 'landing'
    datos.cierres_por_semana = datos.cierres_por_semana == null ? null : {
      ...datos.cierres_por_semana,
      origen_filtrado: 'landing',
      cierres: 2,
      aporte_cierres: 2,
    }
    const lectura = adaptarAporteConversionRango(datos, 'landing')
    expect(lectura).toMatchObject({
      etiqueta: 'Landing',
      familia: 'prospectos',
      divisor: 100,
      numerador: 2,
      porcentaje: 2,
      resultados: 2,
      peso: 1,
    })
  })

  it('proyecta la misma fuente al ranking por analista sin cambiar la foto mensual', () => {
    const datos = metricasConNucleo()
    const lectura = adaptarAporteConversionRango(datos, 'upgrade')
    const mensual = conversionMensualInteligenciaDemo(Date.parse('2026-09-07T12:00:00-05:00'))
    const adaptada = adaptarConversionMensualPorFuente(
      mensual,
      conversionEquipoDemo(),
      'upgrade',
      lectura,
    )

    expect(adaptada.responsablesDisponibles).toBe(true)
    expect(adaptada.vendedores.find((fila) => fila.vendedorId === 'demo-v2')?.detalle).toMatchObject({
      clientes: 0,
      operacionesCartera: 1,
      numerador: 1,
      divisor: 15,
      conversion_pct: 6.67,
    })
    expect(adaptada.vendedores.find((fila) => fila.vendedorId === 'demo-v1')?.detalle).toMatchObject({
      clientes: 0,
      numerador: 0,
      divisor: 25,
      conversion_pct: 0,
    })
  })
})

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

  it('agrega la tendencia del período sumando SOLO los enteros servidos (sin % fabricado)', () => {
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

    // F3 (H12): la curva del equipo dejó de fabricar conversion_pct en el
    // navegador — el punto trae únicamente los enteros del servidor.
    expect(adaptada.tendenciaSemanal).toEqual([
      { semana: 1, desde: '2026-06-03', hasta: '2026-06-09', leads: 0, clientes: 0 },
      { semana: 2, desde: '2026-06-10', hasta: '2026-06-16', leads: 2, clientes: 1 },
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

  it('usa las categorías monetarias del cumplimiento y recupera los ajustes para el desglose bruto', () => {
    const equipo = conversionEquipoDemo().slice(0, 1)
    const metas = metasConversionEquipoDemo()
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor
    const cumplimiento = cumplimientos[equipo[0]!.vendedorId!]!
    for (const d of cumplimiento.detalles) {
      d.capitalReal = d.categoria === 'renovacion' ? (d.moneda === 'PEN' ? 9900 : 50)
        : d.categoria === 'upgrade' ? (d.moneda === 'PEN' ? 80000 : 500) : 0
      d.capitalAjuste = d.categoria === 'renovacion' && d.moneda === 'PEN' ? 100 : 0
    }
    const fila = clasificarRankingCapitalTotal(equipo, metas, cumplimientos, 3.5).conPuesto[0]!
    expect(fila.cartera).toEqual([
      { categoria: 'renovacion', pen: 10000, usd: 50 },
      { categoria: 'upgrade', pen: 80000, usd: 500 },
    ])
    expect(fila.capitalPen).toBe(89900)
    expect(fila.capitalUsd).toBe(550)
  })

  it('trata un roster vacío como autoritativo y no repuebla bajas desde cumplimiento/metas', () => {
    const meta = metasConversionEquipoDemo()['demo-v1']!
    const cumplimiento = cumplimientoMetasConversionEquipoDemo().porVendedor['demo-v1']!

    const ranking = clasificarRankingCapitalTotal(
      [],
      { 'historico-v1': meta },
      { 'historico-v1': cumplimiento },
      3.5,
    )

    expect(ranking.conPuesto).toEqual([])
    expect(ranking.sinMeta).toEqual([])
    expect(ranking.indisponibles).toEqual([])
  })

  it('un cumplimiento sin detalles degrada a indisponible — jamás a un puesto con S/ 0', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    const equipo = conversionEquipoDemo().slice(0, 1)
    datos.responsables = datos.responsables?.slice(0, 1)
    const adaptada = adaptarConversionVendedores(datos, equipo)
    const metas = metasConversionEquipoDemo()
    const roto = { ...cumplimientoMetasConversionEquipoDemo().porVendedor['demo-v1']!, detalles: [] }

    const total = clasificarRankingCapitalTotal(adaptada.vendedores, metas, { 'demo-v1': roto }, 3.5)
    expect(total.conPuesto).toEqual([])
    expect(total.sinMeta).toEqual([])
    expect(total.indisponibles.map((f) => f.vendedor.vendedorId)).toEqual(['demo-v1'])
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
