import { describe, expect, it } from 'vitest'
import type { ConversionEquipoVendedor } from './conversion-equipo'
import {
  conversionEquipoDemo,
  metricasConversionesDemo,
} from './demo-inteligencia-comercial'
import type { ObjetivosPorVendedor } from './objetivos'
import {
  BRECHA_CRITICA_ALERTA_CONVERSION_PP,
  BRECHA_MINIMA_ALERTA_CONVERSION_PP,
  CAIDA_CRITICA_ALERTA_GLOBAL_PP,
  CAIDA_MINIMA_ALERTA_GLOBAL_PP,
  DIA_MINIMO_ALERTA_CONVERSION_INDIVIDUAL,
  LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL,
  LEADS_MINIMOS_ALERTA_CONVERSION_VENDEDOR,
  derivarAlertasGerencia,
  periodoAnteriorComparable,
  type DerivarAlertasGerenciaInput,
} from './alertas-gerencia'

function identidad(
  vendedorId: string,
  nombre: string,
  supervisorNombre: string,
): ConversionEquipoVendedor {
  return {
    vendedorId,
    nombre,
    supervisorNombre,
    leads: 0,
    contactados: 0,
    reunionesPactadas: 0,
    reunionesRealizadas: 0,
    clientes: 0,
    descartados: 0,
    conversionPct: null,
  }
}

function entradaSinFuentes(
  cambios: Partial<DerivarAlertasGerenciaInput> = {},
): DerivarAlertasGerenciaInput {
  return {
    equipoConversion: [],
    metasVendedores: {},
    diaDelMes: DIA_MINIMO_ALERTA_CONVERSION_INDIVIDUAL,
    ...cambios,
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

describe('derivarAlertasGerencia', () => {
  it('exporta umbrales ejecutivos explícitos y estables', () => {
    expect({
      dia: DIA_MINIMO_ALERTA_CONVERSION_INDIVIDUAL,
      leadsVendedor: LEADS_MINIMOS_ALERTA_CONVERSION_VENDEDOR,
      brechaVendedor: BRECHA_MINIMA_ALERTA_CONVERSION_PP,
      brechaVendedorCritica: BRECHA_CRITICA_ALERTA_CONVERSION_PP,
      leadsGlobal: LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL,
      caidaGlobal: CAIDA_MINIMA_ALERTA_GLOBAL_PP,
      caidaGlobalCritica: CAIDA_CRITICA_ALERTA_GLOBAL_PP,
    }).toEqual({
      dia: 10,
      leadsVendedor: 10,
      brechaVendedor: 5,
      brechaVendedorCritica: 10,
      leadsGlobal: 30,
      caidaGlobal: 3,
      caidaGlobalCritica: 5,
    })
  })

  it('alerta al vendedor solo desde el día 10, con 10 leads y brecha mínima de 5 pp', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-06')
    const equipoConversion = conversionEquipoDemo().slice(0, 1)
    conversiones.responsables = [
      { ...conversiones.responsables![0]!, leads: 10, clientes: 1, conversion_pct: 10 },
    ]
    const metasVendedores: ObjetivosPorVendedor = {
      'demo-v1': {
        vendedorId: 'demo-v1',
        supervisorId: 'demo-s1',
        capitalObjetivo: 0,
        ventasObjetivo: 0,
        conversionObjetivo: 15,
      },
    }

    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      equipoConversion,
      metasVendedores,
      diaDelMes: 9,
    }))).toEqual([])

    conversiones.responsables[0]!.leads = 9
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      equipoConversion,
      metasVendedores,
    }))).toEqual([])

    conversiones.responsables[0]!.leads = 10
    conversiones.responsables[0]!.conversion_pct = 10.01
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      equipoConversion,
      metasVendedores,
    }))).toEqual([])

    conversiones.responsables[0]!.conversion_pct = 10
    const alertas = derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      equipoConversion,
      metasVendedores,
    }))

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

  it('eleva a crítica una brecha individual de 10 pp y aplica la meta inicial válida', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-10')
    const equipoConversion = conversionEquipoDemo().slice(0, 1)
    conversiones.responsables = [
      { ...conversiones.responsables![0]!, leads: 10, clientes: 0, conversion_pct: 5 },
    ]

    const alertas = derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      equipoConversion,
      metasVendedores: {},
    }))

    expect(alertas).toEqual([
      expect.objectContaining({
        id: 'bajo_meta_conversion:demo-v1',
        severidad: 'critica',
        objetivo: 15,
        brechaPp: 10,
      }),
    ])
  })

  it('falla cerrado ante objetivos con error o inválidos y responsables ausentes o parciales', () => {
    const equipoConversion = conversionEquipoDemo().slice(0, 2)
    const completas = metricasConversionesDemo('2026-08-01', '2026-08-06')
    completas.responsables = completas.responsables!.slice(0, 2)
    completas.responsables[0] = {
      ...completas.responsables[0]!,
      leads: 20,
      conversion_pct: 0,
    }

    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones: completas,
      equipoConversion,
      objetivosError: true,
    }))).toEqual([])

    const metaInvalida: ObjetivosPorVendedor = {
      'demo-v1': {
        vendedorId: 'demo-v1',
        supervisorId: 'demo-s1',
        capitalObjetivo: 0,
        ventasObjetivo: 0,
        conversionObjetivo: Number.NaN,
      },
    }
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones: completas,
      equipoConversion,
      metasVendedores: metaInvalida,
    }))).toEqual([])

    const ausentes = { ...completas, responsables: undefined }
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones: ausentes,
      equipoConversion,
    }))).toEqual([])

    const parciales = { ...completas, responsables: completas.responsables!.slice(0, 1) }
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones: parciales,
      equipoConversion,
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
    const equipoConversion = [identidad('demo-v1', 'Ana Torres', 'Equipo Norte')]
    conversiones.cohorte.leads = 30
    conversionesAnteriores.cohorte.leads = 30
    conversiones.cohorte.conversion_contratos_pct = 10
    conversionesAnteriores.cohorte.conversion_contratos_pct = 15
    conversiones.responsables = [{
      ...conversiones.responsables![0]!,
      vendedor_id: 'demo-v1',
      leads: 10,
      conversion_pct: 10,
    }]

    const alertas = derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
      equipoConversion,
    }))

    expect(alertas.map(({ id, severidad }) => ({ id, severidad }))).toEqual([
      { id: 'caida_conversion:global', severidad: 'critica' },
      { id: 'bajo_meta_conversion:demo-v1', severidad: 'atencion' },
    ])
  })
})
