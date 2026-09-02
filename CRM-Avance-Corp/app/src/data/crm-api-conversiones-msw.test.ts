// @vitest-environment node
// Los tres adaptadores de conversión contra supabase-js real y Data API
// simulada: fijan cuerpo HTTP y, sobre todo, los ecos fail-closed de período,
// origen y alcance antes de entregar una cifra a las pantallas.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  listarMetricasConversiones,
  listarMetricasConversionesEquipo,
  obtenerConversionMensual,
} from './crm-api'

const RPC = (funcion: string) => `http://supabase.test/rest/v1/rpc/${funcion}`
const server = setupServer()

const CARTERA_CERO = {
  conversiones_clientes: 0,
  conversiones_renovacion: 0,
  conversiones_upgrade: 0,
  capital_renovado_pen: 0,
  capital_renovado_usd: 0,
  capital_adicional_pen: 0,
  capital_adicional_usd: 0,
  renovaciones_sin_desglose: 0,
  operaciones_renovacion: 0,
  operaciones_upgrade: 0,
}

function conversionMensual(alcance: 'propio' | 'equipo' | 'global', mes = '2026-09') {
  const [anio, numeroMes] = mes.split('-').map(Number)
  const desde = new Date(Date.UTC(anio!, numeroMes! - 1, 1, 5)).toISOString()
  const hasta = new Date(Date.UTC(anio!, numeroMes!, 1, 5)).toISOString()
  return {
    version: 1,
    revision: 3,
    generado_en: '2026-09-02T15:00:00.000Z',
    alcance,
    periodo: { mes, mes_nombre: 'septiembre', anio, zona: 'America/Lima', desde, hasta },
    ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
    fuentes: {
      divisor: 'crm.lead_asignaciones.asignado_en',
      numerador: 'crm.lead_asignaciones.resultado_en',
      referido: 'crm.lead_asignaciones.origen',
    },
    cobertura: {
      medible: true,
      suelo_historico: '2026-08-05T18:19:55.000Z',
      motivo_no_medible: null,
      divisor_aproximado: 0,
      divisor_por_motivo: {},
      cierres_sin_episodio: 0,
      fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
    },
    cierre: { cerrado: false },
    cartera: { ...CARTERA_CERO },
    total: {
      analistas: 0,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 0,
      cierres_de_arrastre: 0,
      referidos_recibidos: 0,
      numerador: 0,
      conversion_pct: null,
      referidos_aporta_pct: null,
      cartera: { ...CARTERA_CERO },
    },
    responsables: [],
  }
}

function metricasConversiones(origen: string | null) {
  return {
    origen_filtrado: origen,
    version: 1,
    generado_en: '2026-09-02T15:00:00.000Z',
    periodo: { desde: '2026-09-01', hasta: '2026-09-30', dias: 30, zona: 'America/Lima' },
    cohorte: {
      leads: 0,
      asignados: 0,
      contactados: 0,
      reuniones_agendadas: 0,
      reuniones_realizadas: 0,
      propuestas: 0,
      clientes: 0,
      contratos: 0,
      descartados: 0,
      conversion_clientes_pct: null,
      conversion_contratos_pct: null,
      conversion_resueltos_pct: null,
    },
    produccion: { clientes: 0, contratos: 0, capital_pen: 0, capital_usd: 0 },
    embudo: [],
    origenes: [],
    categorias: [],
  }
}

function metricasEquipo(alcance: 'equipo' | 'global') {
  return {
    version: 1,
    revision: 3,
    cierre: { cerrado: false },
    generado_en: '2026-09-02T15:00:00.000Z',
    alcance,
    periodo: { desde: '2026-09-01', hasta: '2026-09-30' },
    responsables: [],
  }
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('obtenerConversionMensual — eco de mes y alcance', () => {
  it('manda el primer día y entrega solo el alcance esperado', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('conversion_mensual_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(conversionMensual('global'))
      }),
    )

    const resultado = await obtenerConversionMensual('2026-09-01', 'global')

    expect(cuerpo).toEqual({ p_periodo: '2026-09-01' })
    expect(resultado).toMatchObject({
      alcance: 'global',
      periodo: { mes: '2026-09' },
      revision: 3,
      cierre: { cerrado: false },
    })
  })

  it('rechaza una respuesta válida de otro alcance', async () => {
    server.use(
      http.post(RPC('conversion_mensual_fn'), () => HttpResponse.json(conversionMensual('propio'))),
    )

    await expect(obtenerConversionMensual('2026-09-01', 'global')).rejects.toMatchObject({
      code: 'CONVERSION_MENSUAL_CONTRACT',
    })
  })

  it('rechaza el eco de otro mes aunque ese payload sea internamente válido', async () => {
    server.use(
      http.post(RPC('conversion_mensual_fn'), () => HttpResponse.json(conversionMensual('global', '2026-08'))),
    )

    await expect(obtenerConversionMensual('2026-09-01', 'global')).rejects.toMatchObject({
      code: 'CONVERSION_MENSUAL_CONTRACT',
    })
  })

  it('rechaza un mes calendario imposible antes de tocar la red', async () => {
    await expect(obtenerConversionMensual('2026-13-01', 'global')).rejects.toMatchObject({
      code: 'PERIODO_METRICAS_INVALIDO',
    })
  })
})

describe('listarMetricasConversiones — eco de origen y período', () => {
  it('manda y exige exactamente el origen solicitado', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('metricas_conversiones_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(metricasConversiones('referido'))
      }),
    )

    const resultado = await listarMetricasConversiones(
      '2026-09-01',
      '2026-09-30',
      'referido',
    )

    expect(cuerpo).toEqual({
      p_desde: '2026-09-01',
      p_hasta: '2026-09-30',
      p_origen: 'referido',
    })
    expect(resultado.origen_filtrado).toBe('referido')
  })

  it('rechaza otro origen y también la ausencia del eco cuando se pidieron todos', async () => {
    server.use(
      http.post(RPC('metricas_conversiones_fn'), () => HttpResponse.json(metricasConversiones('landing'))),
    )
    await expect(
      listarMetricasConversiones('2026-09-01', '2026-09-30', 'referido'),
    ).rejects.toMatchObject({ code: 'METRICAS_CONVERSIONES_CONTRACT' })

    const sinEco = metricasConversiones(null) as Record<string, unknown>
    delete sinEco.origen_filtrado
    server.use(
      http.post(RPC('metricas_conversiones_fn'), () => HttpResponse.json(sinEco)),
    )
    await expect(
      listarMetricasConversiones('2026-09-01', '2026-09-30', null),
    ).rejects.toMatchObject({ code: 'METRICAS_CONVERSIONES_CONTRACT' })
  })

  it('rechaza un eco de período distinto aunque conserve el origen', async () => {
    server.use(
      http.post(
        RPC('metricas_conversiones_fn'),
        () => HttpResponse.json(metricasConversiones('referido')),
      ),
    )

    await expect(
      listarMetricasConversiones('2026-09-01', '2026-09-29', 'referido'),
    ).rejects.toMatchObject({ code: 'METRICAS_CONVERSIONES_CONTRACT' })
  })
})

describe('listarMetricasConversionesEquipo — eco de alcance', () => {
  it('acepta únicamente el alcance que el consumidor declaró', async () => {
    server.use(
      http.post(RPC('metricas_conversiones_equipo_fn'), () => HttpResponse.json(metricasEquipo('equipo'))),
    )
    await expect(
      listarMetricasConversionesEquipo('2026-09-01', '2026-09-30', 'equipo'),
    ).resolves.toMatchObject({
      alcance: 'equipo',
      revision: 3,
      cierre: { cerrado: false },
    })

    await expect(
      listarMetricasConversionesEquipo('2026-09-01', '2026-09-30', 'global'),
    ).rejects.toBeInstanceOf(CrmApiError)
  })

  it('rechaza un eco de período distinto', async () => {
    server.use(
      http.post(
        RPC('metricas_conversiones_equipo_fn'),
        () => HttpResponse.json(metricasEquipo('equipo')),
      ),
    )

    await expect(
      listarMetricasConversionesEquipo('2026-09-01', '2026-09-29', 'equipo'),
    ).rejects.toMatchObject({ code: 'METRICAS_CONVERSIONES_EQUIPO_CONTRACT' })
  })
})
