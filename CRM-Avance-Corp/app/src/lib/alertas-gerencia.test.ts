import { describe, expect, it } from 'vitest'
import type { ConversionEquipoVendedor } from './conversion-equipo'
import {
  conversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
} from './demo-inteligencia-comercial'
import { metricasAgendaDemo } from './demo-metricas-agenda'
import type { ObjetivosPorVendedor } from './objetivos'
import {
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
  it('crea rezagos solo para integrantes activos y no convierte ausencias en cero', () => {
    const agenda = metricasAgendaDemo('2026-08-01', '2026-08-06')
    agenda.vendedores = [
      { ...agenda.vendedores[1]!, activo: false, vencidas: 9, leads_sin_accion: 9 },
      { ...agenda.vendedores[2]!, vendedor_id: 'v-b', nombre: 'Bruno', vencidas: 2, leads_sin_accion: 3 },
      { ...agenda.vendedores[0]!, vendedor_id: 's-a', nombre: 'Supervisora', vencidas: 8, leads_sin_accion: 7 },
    ]

    const alertas = derivarAlertasGerencia(entradaSinFuentes({
      agenda,
      equipoConversion: [identidad('v-b', 'Bruno', 'Equipo Norte')],
    }))

    expect(alertas).toEqual([
      expect.objectContaining({
        id: 'tarea_vencida:v-b',
        tipo: 'tarea_vencida',
        severidad: 'atencion',
        responsable: 'Bruno',
        equipo: 'Equipo Norte',
        valor: 2,
        destino: 'rendimiento',
      }),
      expect.objectContaining({
        id: 'sin_proxima_accion:v-b',
        tipo: 'sin_proxima_accion',
        severidad: 'atencion',
        valor: 3,
        destino: 'rendimiento',
      }),
    ])
    expect(derivarAlertasGerencia(entradaSinFuentes())).toEqual([])
  })

  it('excluye responsables nulos y eleva no-shows desde dos casos a crítica', () => {
    const reuniones = metricasReunionesDemo('2026-08-01', '2026-08-06')
    reuniones.responsables = [
      { ...reuniones.responsables[0]!, responsable_id: 'v-uno', nombre: 'Zoe', no_show: 1 },
      { ...reuniones.responsables[1]!, responsable_id: 'v-dos', nombre: 'Ana', no_show: 2 },
      { ...reuniones.responsables[2]!, responsable_id: null, nombre: 'Sin dueño', no_show: 8 },
    ]

    const alertas = derivarAlertasGerencia(entradaSinFuentes({ reuniones }))

    expect(alertas.map(({ id, severidad }) => ({ id, severidad }))).toEqual([
      { id: 'no_show:v-dos', severidad: 'critica' },
      { id: 'no_show:v-uno', severidad: 'atencion' },
    ])
    expect(alertas[0]).toMatchObject({
      responsable: 'Ana',
      equipo: reuniones.responsables[1]!.supervisor_nombre,
      valor: 2,
      destino: 'reuniones',
    })
  })

  it('alerta solo a vendedores comparables bajo su meta individual o la inicial', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-06')
    const equipoConversion = conversionEquipoDemo().slice(0, 2)
    conversiones.responsables = [
      { ...conversiones.responsables![0]!, leads: 10, clientes: 1, conversion_pct: 10 },
      { ...conversiones.responsables![1]!, leads: 0, clientes: 0, conversion_pct: null },
    ]
    const metasVendedores: ObjetivosPorVendedor = {
      'demo-v1': {
        vendedorId: 'demo-v1',
        supervisorId: 'demo-s1',
        capitalObjetivo: 0,
        ventasObjetivo: 0,
        conversionObjetivo: 12,
      },
    }

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
        objetivo: 12,
        brechaPp: 2,
        destino: 'ranking-vendedores',
      }),
    ])

    const conMetaInicial = derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      equipoConversion,
      metasVendedores: {},
    }))
    expect(conMetaInicial[0]).toMatchObject({ objetivo: 15, brechaPp: 5 })
  })

  it('falla cerrado ante objetivos con error o responsables ausentes y parciales', () => {
    const equipoConversion = conversionEquipoDemo().slice(0, 2)
    const completas = metricasConversionesDemo('2026-08-01', '2026-08-06')
    completas.responsables = completas.responsables!.slice(0, 2)

    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones: completas,
      equipoConversion,
      objetivosError: true,
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

  it('detecta solo una caída global con porcentajes disponibles y conserva la referencia', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-06')
    const conversionesAnteriores = metricasConversionesDemo('2026-07-01', '2026-07-06')
    conversiones.responsables = undefined
    conversionesAnteriores.responsables = undefined
    conversiones.cohorte.conversion_contratos_pct = 10
    conversionesAnteriores.cohorte.conversion_contratos_pct = 14.5

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
        valor: 10,
        actual: 10,
        objetivo: 14.5,
        brechaPp: 4.5,
        destino: 'conversiones',
      },
    ])

    conversionesAnteriores.cohorte.conversion_contratos_pct = 10
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
    }))).toEqual([])

    conversionesAnteriores.cohorte.conversion_contratos_pct = null
    expect(derivarAlertasGerencia(entradaSinFuentes({
      conversiones,
      conversionesAnteriores,
    }))).toEqual([])
  })
})
