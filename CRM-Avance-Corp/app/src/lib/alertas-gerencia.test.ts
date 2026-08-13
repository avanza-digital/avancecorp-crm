import { describe, expect, it } from 'vitest'
import {
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from './demo-inteligencia-comercial'
import type { CumplimientoVendedor, ObjetivosPorVendedor } from './objetivos'
import {
  BRECHA_CRITICA_ALERTA_CONVERSION_PP,
  BRECHA_MINIMA_ALERTA_CONVERSION_PP,
  CAIDA_CRITICA_ALERTA_GLOBAL_PP,
  CAIDA_MINIMA_ALERTA_GLOBAL_PP,
  CORTES_ALERTA_CONVERSION_INDIVIDUAL,
  LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL,
  MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR,
  corteVigente,
  cortesDelMes,
  derivarAlertasGerencia,
  periodoAnteriorComparable,
  type DerivarAlertasGerenciaInput,
} from './alertas-gerencia'

/** El primer corte del mes: antes de el no existe aviso individual. */
const PRIMER_CORTE = CORTES_ALERTA_CONVERSION_INDIVIDUAL[0]

function entradaSinFuentes(
  cambios: Partial<DerivarAlertasGerenciaInput> = {},
): DerivarAlertasGerenciaInput {
  return {
    metasVendedores: {},
    cumplimientosVendedores: {},
    diaDelMes: PRIMER_CORTE,
    diasDelMes: 31,
    ...cambios,
  }
}

function fuentesIndividuales(
  conversionObjetivo: number,
  conversionReal: number,
  resueltos: number,
): {
  metasVendedores: ObjetivosPorVendedor
  cumplimientosVendedores: Record<string, CumplimientoVendedor>
} {
  const metaBase = metasConversionEquipoDemo()['demo-v1']!
  const cumplimientoBase = cumplimientoMetasConversionEquipoDemo().porVendedor['demo-v1']!
  return {
    metasVendedores: {
      'demo-v1': { ...metaBase, conversionObjetivo },
    },
    cumplimientosVendedores: {
      'demo-v1': {
        ...cumplimientoBase,
        conversionObjetivo,
        conversionReal,
        convertidos: Math.round((resueltos * conversionReal) / 100),
        resueltos,
      },
    },
  }
}

describe('periodoAnteriorComparable', () => {
  it('conserva el ordinal del corte y cruza correctamente el cambio de año', () => {
    expect(periodoAnteriorComparable('2026-08-06')).toEqual({
      desde: '2026-07-01',
      hasta: '2026-07-06',
    })
    expect(periodoAnteriorComparable('2026-01-15')).toEqual({
      desde: '2025-12-01',
      hasta: '2025-12-15',
    })
  })

  it('recorta al último día real del mes anterior, incluido febrero bisiesto', () => {
    expect(periodoAnteriorComparable('2026-03-31')).toEqual({
      desde: '2026-02-01',
      hasta: '2026-02-28',
    })
    expect(periodoAnteriorComparable('2024-03-31')).toEqual({
      desde: '2024-02-01',
      hasta: '2024-02-29',
    })
    expect(periodoAnteriorComparable('2026-05-31')).toEqual({
      desde: '2026-04-01',
      hasta: '2026-04-30',
    })
  })

  it('rechaza formatos y días calendario inválidos', () => {
    expect(() => periodoAnteriorComparable('2026-8-06')).toThrow(RangeError)
    expect(() => periodoAnteriorComparable('2026-02-30')).toThrow(RangeError)
  })
})

describe('cortes de revisión del mes (7 · 15 · 21 · 30)', () => {
  // Decisión de Miguel 2026-08-13: el avance individual se juzga por semanas
  // cumplidas. El aviso aparece en su corte y SIGUE VISIBLE hasta el siguiente,
  // para que no se pierda un corte por no haber entrado ese día exacto.
  const conAviso = (diaDelMes: number, diasDelMes = 31) => derivarAlertasGerencia(
    entradaSinFuentes({ ...fuentesIndividuales(15, 10, 10), diaDelMes, diasDelMes }),
  ).length > 0

  it('antes del día 7 no hay aviso, por muchos leads repartidos que haya', () => {
    for (const dia of [1, 2, 5, 6]) {
      expect({ dia, avisa: conAviso(dia) }).toEqual({ dia, avisa: false })
    }
  })

  it('el aviso aparece en el corte y NO desaparece al día siguiente', () => {
    // Este es el caso que separa «solo el día del corte» de lo acordado: si el
    // día 8 se apagara, gerencia perdería el corte por no entrar el día 7.
    for (const dia of [7, 8, 14, 15, 16, 21, 29, 30, 31]) {
      expect({ dia, avisa: conAviso(dia) }).toEqual({ dia, avisa: true })
    }
  })

  it('el corte vigente es el último cumplido, no el siguiente', () => {
    expect(corteVigente(6, 31)).toBeNull()
    expect(corteVigente(7, 31)).toBe(7)
    expect(corteVigente(14, 31)).toBe(7)
    expect(corteVigente(15, 31)).toBe(15)
    expect(corteVigente(20, 31)).toBe(15)
    expect(corteVigente(21, 31)).toBe(21)
    expect(corteVigente(30, 31)).toBe(30)
    expect(corteVigente(31, 31)).toBe(30)
  })

  it('febrero corre su último corte al día 28: no se queda sin revisión final', () => {
    expect(cortesDelMes(28)).toEqual([7, 15, 21, 28])
    expect(cortesDelMes(29)).toEqual([7, 15, 21, 29])
    expect(cortesDelMes(31)).toEqual([7, 15, 21, 30])
    // Y el aviso llega el 28 de febrero, que sin el ajuste nunca alcanzaría 30.
    expect(conAviso(28, 28)).toBe(true)
  })

  it('un día imposible para el mes no inventa un corte', () => {
    expect(corteVigente(31, 28)).toBe(28)
    expect(conAviso(31, 28)).toBe(false)
    expect(cortesDelMes(0)).toEqual([])
  })
})

describe('derivarAlertasGerencia', () => {
  it('exporta umbrales ejecutivos explícitos y estables', () => {
    expect({
      dia: PRIMER_CORTE,
      casosResueltosVendedor: MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR,
      brechaVendedor: BRECHA_MINIMA_ALERTA_CONVERSION_PP,
      brechaVendedorCritica: BRECHA_CRITICA_ALERTA_CONVERSION_PP,
      leadsGlobal: LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL,
      caidaGlobal: CAIDA_MINIMA_ALERTA_GLOBAL_PP,
      caidaGlobalCritica: CAIDA_CRITICA_ALERTA_GLOBAL_PP,
    }).toEqual({
      dia: 7,
      casosResueltosVendedor: 10,
      brechaVendedor: 5,
      brechaVendedorCritica: 10,
      leadsGlobal: 30,
      caidaGlobal: 3,
      caidaGlobalCritica: 5,
    })
  })

  it('alerta al vendedor solo desde el primer corte, con muestra suficiente y brecha mínima de 5 pp', () => {
    const fuentes = fuentesIndividuales(15, 10, 10)

    expect(derivarAlertasGerencia(entradaSinFuentes({
      ...fuentes,
      diaDelMes: 6,
    }))).toEqual([])

    const muestraInsuficiente = fuentesIndividuales(15, 10, 9)
    expect(derivarAlertasGerencia(entradaSinFuentes(muestraInsuficiente))).toEqual([])

    const brechaInsuficiente = fuentesIndividuales(15, 10.01, 10)
    expect(derivarAlertasGerencia(entradaSinFuentes(brechaInsuficiente))).toEqual([])

    const alertas = derivarAlertasGerencia(entradaSinFuentes(fuentes))

    expect(alertas).toEqual([
      expect.objectContaining({
        id: 'bajo_meta_conversion:demo-v1',
        severidad: 'atencion',
        responsable: 'Ana Torres',
        valor: 10,
        actual: 10,
        objetivo: 15,
        brechaPp: 5,
        destino: 'ranking-vendedores',
      }),
    ])
  })

  it('eleva a crítica una brecha individual de 10 pp contra una meta publicada', () => {
    const alertas = derivarAlertasGerencia(entradaSinFuentes(
      fuentesIndividuales(15, 5, 10),
    ))

    expect(alertas).toEqual([
      expect.objectContaining({
        id: 'bajo_meta_conversion:demo-v1',
        severidad: 'critica',
        objetivo: 15,
        brechaPp: 10,
      }),
    ])
  })

  it('falla cerrado ante metas/cumplimiento con error, inválidos, ausentes o parciales', () => {
    const completas = fuentesIndividuales(15, 0, 20)
    expect(derivarAlertasGerencia(entradaSinFuentes({
      ...completas,
      objetivosError: true,
    }))).toEqual([])

    expect(derivarAlertasGerencia(entradaSinFuentes({
      ...completas,
      cumplimientoError: true,
    }))).toEqual([])

    const metaInvalida: ObjetivosPorVendedor = {
      'demo-v1': { ...completas.metasVendedores['demo-v1']!, conversionObjetivo: Number.NaN },
    }
    expect(derivarAlertasGerencia(entradaSinFuentes({
      metasVendedores: metaInvalida,
      cumplimientosVendedores: completas.cumplimientosVendedores,
    }))).toEqual([])

    expect(derivarAlertasGerencia(entradaSinFuentes({
      metasVendedores: completas.metasVendedores,
      cumplimientosVendedores: {},
    }))).toEqual([])

    const otraMeta = metasConversionEquipoDemo()['demo-v2']!
    expect(derivarAlertasGerencia(entradaSinFuentes({
      metasVendedores: { ...completas.metasVendedores, 'demo-v2': otraMeta },
      cumplimientosVendedores: completas.cumplimientosVendedores,
    }))).toEqual([])
  })

  it('no crea alertas individuales sin una meta publicada', () => {
    const cumplimiento = fuentesIndividuales(15, 0, 20).cumplimientosVendedores
    expect(derivarAlertasGerencia(entradaSinFuentes({
      metasVendedores: {},
      cumplimientosVendedores: cumplimiento,
    }))).toEqual([])
  })

  it('alerta la caída global solo con 30 leads por periodo y una brecha de al menos 3 pp', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-06')
    const conversionesAnteriores = metricasConversionesDemo('2026-07-01', '2026-07-06')
    conversiones.responsables = undefined
    conversionesAnteriores.responsables = undefined
    conversiones.cohorte.leads = 30
    conversionesAnteriores.cohorte.leads = 30
    conversiones.cohorte.conversion_contratos_pct = 12
    conversionesAnteriores.cohorte.conversion_contratos_pct = 15

    const alertas = derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
    }))

    expect(alertas).toEqual([
      {
        id: 'caida_conversion:global',
        tipo: 'caida_conversion',
        severidad: 'atencion',
        responsableId: null,
        responsable: 'Equipo comercial',
        equipo: 'Todos los equipos',
        valor: 12,
        actual: 12,
        objetivo: 15,
        brechaPp: 3,
        destino: 'conversiones',
      },
    ])

    conversiones.cohorte.leads = 29
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
    }))).toEqual([])

    conversiones.cohorte.leads = 30
    conversionesAnteriores.cohorte.conversion_contratos_pct = 14.99
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
    }))).toEqual([])
  })

  it('eleva a crítica una caída global de 5 pp y la ordena antes de una brecha individual menor', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-10')
    const conversionesAnteriores = metricasConversionesDemo('2026-07-01', '2026-07-10')
    conversiones.cohorte.leads = 30
    conversionesAnteriores.cohorte.leads = 30
    conversiones.cohorte.conversion_contratos_pct = 10
    conversionesAnteriores.cohorte.conversion_contratos_pct = 15

    const alertas = derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
      ...fuentesIndividuales(15, 10, 10),
    }))

    expect(alertas.map(({ id, severidad }) => ({ id, severidad }))).toEqual([
      { id: 'caida_conversion:global', severidad: 'critica' },
      { id: 'bajo_meta_conversion:demo-v1', severidad: 'atencion' },
    ])
  })
})
