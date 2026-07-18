// @vitest-environment node
// Contrato HTTP real de las RPC de distribución/capacidad contra Supabase
// simulado: parámetros, abort, payload JSON V1 fail-closed y errores seguros.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { delay, http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  actualizarCapacidadLeadsObjetivo,
  listarMetricasDistribucionLeads,
} from './crm-api'
import { RANGOS_CAPITAL_PEN } from '@/lib/metricas-distribucion'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const ANALISTA_ID = '11111111-1111-4111-8111-111111111111'
const SUPERVISOR_ID = '22222222-2222-4222-8222-222222222222'

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

function rangosCatalogo() {
  const limites: Array<[number | null, number | null]> = [
    [0, 1000],
    [1000, 5000],
    [5000, 10000],
    [10000, 20000],
    [20000, 50000],
    [50000, 100000],
    [100000, null],
    [null, null],
  ]
  return RANGOS_CAPITAL_PEN.map((id, indice) => {
    const [desde_exclusivo, hasta_inclusivo] = limites[indice]!
    return {
      id,
      orden: indice + 1,
      etiqueta: `Rango ${indice + 1}`,
      desde_exclusivo,
      hasta_inclusivo,
    }
  })
}

function rangosAnalista() {
  return RANGOS_CAPITAL_PEN.map((rango_id, indice) => ({
    rango_id,
    cartera_actual: { episodios: indice === 1 ? '2' : 0, capital: indice === 1 ? '7000.50' : 0 },
    cohorte: {
      episodios_recibidos: indice === 1 ? '3' : 0,
      leads_unicos_recibidos: indice === 1 ? 3 : 0,
      convertidos: indice === 1 ? 1 : 0,
      descartados: indice === 1 ? 1 : 0,
      leads_unicos_resueltos: indice === 1 ? 2 : 0,
    },
  }))
}

function rangosCola() {
  return RANGOS_CAPITAL_PEN.map((rango_id, indice) => ({
    rango_id,
    cantidad: indice === 0 ? 1 : 0,
    capital: indice === 0 ? 1000 : 0,
  }))
}

function payloadValido() {
  const penCola = { cantidad: 1, capital: '1000.00', rangos: rangosCola() }
  const usdCola = { cantidad: 0, capital: 0 }
  return {
    version: 1,
    generado_en: '2026-07-17T22:30:00-05:00',
    cohorte: {
      desde_inclusivo: '2026-04-01',
      hasta_inclusivo: '2026-06-30',
      hasta_exclusivo: '2026-07-01',
      criterio: 'episodio_asignado_en',
      zona_horaria: 'America/Lima',
    },
    alcances: {
      matriz: 'PEN',
      capacidad: 'TODAS_LAS_MONEDAS',
      operacion_sla: 'TODAS_LAS_MONEDAS',
    },
    rangos: rangosCatalogo(),
    resumen: {
      leads_operativos_actuales: 3,
      asignados_actuales: 2,
      por_repartir_actuales: 1,
      capital_pen_asignado_actual: '7000.50',
      capital_usd_asignado_actual: 0,
      cohorte_episodios: 3,
      cohorte_leads_unicos: 3,
      convertidos_pen: 1,
      descartados_pen: 1,
      sla_evaluables: 2,
      sla_en_24h: 1,
    },
    analistas: [{
      analista_id: ANALISTA_ID,
      nombre: 'ANA ANALISTA',
      rol: 'vendedor',
      supervisor_id: SUPERVISOR_ID,
      supervisor_nombre: 'SUSANA SUPERVISORA',
      activo: true,
      disponible_para_recibir: true,
      capacidad: { objetivo: 20, carga_activa: 2, carga_pen: 2, carga_usd: 0 },
      pen: {
        cartera_actual: { episodios: 2, capital: '7000.50' },
        cohorte: {
          episodios_recibidos: 3,
          leads_unicos_recibidos: 3,
          convertidos: 1,
          descartados: 1,
          ciclos_resueltos: 2,
          leads_unicos_resueltos: 2,
        },
        rangos: rangosAnalista(),
      },
      usd_no_segmentado: {
        cartera_actual_episodios: 0,
        cartera_actual_capital: 0,
        cohorte_episodios_recibidos: 0,
        cohorte_leads_unicos: 0,
        convertidos: 0,
        descartados: 0,
      },
      operacion: {
        cohorte_episodios: 3,
        contactos: 2,
        sla_evaluables: 2,
        sla_en_24h: 1,
        primer_contacto_mediana_minutos: '35.5',
        transferidos: 1,
        parqueados: 0,
        desactivados: 0,
        sin_tocar_actual: 1,
        estancados_actual: 1,
      },
    }],
    por_repartir: {
      total: { carga_total: 1, pen: penCola, usd: usdCola },
      global: {
        responsabilidad: 'gerencia',
        carga_total: 1,
        pen: penCola,
        usd: usdCola,
      },
      bandejas: [{
        supervisor_id: SUPERVISOR_ID,
        supervisor_nombre: 'SUSANA SUPERVISORA',
        supervisor_activo: true,
        carga_total: 0,
        pen: { cantidad: 0, capital: 0, rangos: rangosCola().map((r) => ({ ...r, cantidad: 0, capital: 0 })) },
        usd: usdCola,
      }],
    },
    calidad: {
      episodios_aproximados_actuales: 0,
      episodios_aproximados_cohorte: 0,
      episodios_sin_monto_actuales: 0,
      episodios_sin_monto_cohorte: 0,
    },
  }
}

describe('listarMetricasDistribucionLeads (msw)', () => {
  it('manda ambas fechas, valida todo el JSON V1 y coerciona sus numeric', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('metricas_distribucion_leads_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(payloadValido())
      }),
    )

    const metricas = await listarMetricasDistribucionLeads('2026-04-01', '2026-06-30')

    expect(cuerpo).toEqual({ p_desde: '2026-04-01', p_hasta: '2026-06-30' })
    expect(metricas.version).toBe(1)
    expect(metricas.rangos).toHaveLength(8)
    expect(metricas.analistas[0]!.pen.cartera_actual.capital).toBe(7000.5)
    expect(metricas.analistas[0]!.operacion.primer_contacto_mediana_minutos).toBe(35.5)
    expect(metricas.por_repartir.total.pen.capital).toBe(1000)
  })

  it('rechaza el payload completo si falta una métrica anidada', async () => {
    const payload = payloadValido()
    const operacion = payload.analistas[0]!.operacion as Record<string, unknown>
    delete operacion.sla_en_24h
    server.use(
      http.post(RPC('metricas_distribucion_leads_fn'), () => HttpResponse.json(payload)),
    )

    await expect(
      listarMetricasDistribucionLeads('2026-04-01', '2026-06-30'),
    ).rejects.toMatchObject({
      code: 'METRICAS_DISTRIBUCION_CONTRACT',
      message: 'Las métricas de distribución no tienen el formato esperado.',
    })
  })

  it('rechaza fechas inválidas antes de tocar la red', async () => {
    await expect(
      listarMetricasDistribucionLeads('2026-07-10', '2026-07-01'),
    ).rejects.toMatchObject({ code: 'PERIODO_METRICAS_INVALIDO' })
  })

  it('propaga la cancelación como AbortError', async () => {
    server.use(
      http.post(RPC('metricas_distribucion_leads_fn'), async () => {
        await delay(200)
        return HttpResponse.json(payloadValido())
      }),
    )
    const controlador = new AbortController()
    const promesa = listarMetricasDistribucionLeads(
      '2026-04-01',
      '2026-06-30',
      controlador.signal,
    )
    controlador.abort()

    await expect(promesa).rejects.toMatchObject({ name: 'AbortError' })
  })
})

describe('actualizarCapacidadLeadsObjetivo (msw)', () => {
  it('manda el payload exacto y valida la única fila de respuesta', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('actualizar_capacidad_leads_objetivo'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([{
          perfil_id: ANALISTA_ID,
          capacidad_leads_objetivo: 25,
        }])
      }),
    )

    const actualizada = await actualizarCapacidadLeadsObjetivo(ANALISTA_ID, 25)

    expect(cuerpo).toEqual({
      p_analista_id: ANALISTA_ID,
      p_capacidad_leads_objetivo: 25,
    })
    expect(actualizada).toEqual({ analistaId: ANALISTA_ID, capacidad: 25 })
  })

  it('envía null para limpiar la capacidad (no lo omite)', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('actualizar_capacidad_leads_objetivo'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([{
          perfil_id: ANALISTA_ID,
          capacidad_leads_objetivo: null,
        }])
      }),
    )

    await actualizarCapacidadLeadsObjetivo(ANALISTA_ID, null)

    expect(cuerpo).toEqual({
      p_analista_id: ANALISTA_ID,
      p_capacidad_leads_objetivo: null,
    })
  })

  it('traduce analista inactivo/inexistente a un error claro', async () => {
    server.use(
      http.post(RPC('actualizar_capacidad_leads_objetivo'), () =>
        HttpResponse.json(
          { message: 'detalle interno', code: 'P0002', details: null, hint: null },
          { status: 400 },
        ),
      ),
    )

    await expect(
      actualizarCapacidadLeadsObjetivo(ANALISTA_ID, 25),
    ).rejects.toMatchObject({
      code: 'ANALISTA_NO_ENCONTRADO',
      message: 'Analista activo no encontrado.',
    })
  })

  it('rechaza capacidad fuera de rango antes de tocar la red', async () => {
    await expect(
      actualizarCapacidadLeadsObjetivo(ANALISTA_ID, 0),
    ).rejects.toMatchObject({ code: 'CAPACIDAD_INVALIDA' })
  })
})
