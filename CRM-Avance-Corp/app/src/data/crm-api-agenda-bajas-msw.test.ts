// @vitest-environment node
// D-48 (bloque 2.12): la puerta crm.metricas_agenda_fn conserva, si tienen actividad en el período, al analista o supervisor
// dado de baja (`"de_baja": true`, con `activo: false`) y al suspendido en el Portal (`"suspendido": true`, con `activo: true`).
// El contrato de la agenda (`lib/metricas-agenda.ts`) es un objeto ESTRICTO: una clave desconocida tumba el panel entero. Por
// eso la app se publica ANTES que la migración (orden decidido por el Director) y tiene que funcionar con la respuesta de
// antes y con la nueva. Contra un Supabase SIMULADO con msw (contrato HTTP real; el cliente supabase-js es el de verdad).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, listarMetricasAgenda } from './crm-api'

const RPC = 'http://supabase.test/rest/v1/rpc/metricas_agenda_fn'
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  // registrarError escribe en console.error; se silencia para no ensuciar la salida.
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

const DESDE = '2026-10-03'
const HASTA = '2026-10-09'

/** Un miembro con actividad en el período, como lo serializa la RPC. */
function miembro(id: string, nombre: string, extra: Record<string, unknown>): Record<string, unknown> {
  return {
    vendedor_id: id, nombre, rol: 'vendedor', activo: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0,
    completadas: 3, no_asistio: 1, canceladas: 1, canceladas_asesor: 1, canceladas_sistema: 0, canceladas_ajenas: 0,
    pct_completadas: 60, tareas_creadas: 6, reuniones_agendadas: 6, reprogramaciones: 0, pendientes: 0, vencidas: 0,
    leads_sin_accion: 1, ...extra,
  }
}

/** La respuesta NUEVA: la de antes más un analista de baja y una suspendida, en su sitio (orden por nombre). */
function respuestaNueva(cambios: (filas: Record<string, unknown>[]) => Record<string, unknown>[] = (f) => f) {
  const datos = metricasAgendaDemo(DESDE, HASTA)
  const filas: Record<string, unknown>[] = [
    miembro('d-baja', 'ALEJANDRO DE BAJA', { activo: false, de_baja: true }),
    ...datos.vendedores,
    miembro('d-susp', 'SARA SUSPENDIDA', { suspendido: true }),
  ]
  return { ...datos, vendedores: cambios(filas) }
}

describe('listarMetricasAgenda · de baja y suspendidos con actividad (D-48)', () => {
  it('con la respuesta de ANTES (sin marcas) devuelve lo de siempre: la app nueva no depende de la migración', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(metricasAgendaDemo(DESDE, HASTA))
    }))

    const datos = await listarMetricasAgenda(DESDE, HASTA)

    expect(cuerpo).toEqual({ p_desde: DESDE, p_hasta: HASTA })
    expect(datos.vendedores).toEqual(metricasAgendaDemo(DESDE, HASTA).vendedores)
    expect(datos.vendedores.every((fila) => !('de_baja' in fila) && !('suspendido' in fila))).toBe(true)
  })

  it('con la respuesta NUEVA conserva «de baja» y «suspendido» solo en sus filas, sin tocar las demás', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(respuestaNueva())))

    const datos = await listarMetricasAgenda(DESDE, HASTA)

    expect(datos.vendedores.map((fila) => [fila.nombre, fila.activo, fila.de_baja ?? null, fila.suspendido ?? null])).toEqual([
      ['ALEJANDRO DE BAJA', false, true, null],
      ['SUPERVISOR UNO', true, null, null],
      ['ANALISTA DOS', true, null, null],
      ['ANALISTA UNO', true, null, null],
      ['SARA SUSPENDIDA', true, null, true],
    ])
    // Las filas sin marca son exactamente las de siempre.
    expect(datos.vendedores.slice(1, 4)).toEqual(metricasAgendaDemo(DESDE, HASTA).vendedores)
  })

  it('el contrato estricto sigue en pie: una clave desconocida (que no es una marca) tumba la respuesta', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(respuestaNueva((f) => f.map((x, i) => (i === 2 ? { ...x, extra: 1 } : x))))))

    const fallo = await listarMetricasAgenda(DESDE, HASTA).catch((error: unknown) => error)

    expect(fallo).toBeInstanceOf(CrmApiError)
    expect((fallo as CrmApiError).code).toBe('METRICAS_AGENDA_CONTRACT')
  })

  it.each<[string, (filas: Record<string, unknown>[]) => Record<string, unknown>[]]>([
    ['«de_baja» que no es true', (f) => f.map((x) => (x.de_baja ? { ...x, de_baja: false } : x))],
    ['«suspendido» que no es true', (f) => f.map((x) => (x.suspendido ? { ...x, suspendido: 'si' } : x))],
    ['«de baja» con la ficha activa', (f) => f.map((x) => (x.de_baja ? { ...x, activo: true } : x))],
    ['«suspendido» con la ficha inactiva', (f) => f.map((x) => (x.suspendido ? { ...x, activo: false } : x))],
    ['las dos marcas en la misma fila', (f) => f.map((x) => (x.de_baja ? { ...x, suspendido: true } : x))],
  ])('rechaza la respuesta si llega %s (fail-closed)', async (_caso, cambio) => {
    server.use(http.post(RPC, () => HttpResponse.json(respuestaNueva(cambio))))

    const fallo = await listarMetricasAgenda(DESDE, HASTA).catch((error: unknown) => error)

    expect(fallo).toBeInstanceOf(CrmApiError)
    expect((fallo as CrmApiError).code).toBe('METRICAS_AGENDA_CONTRACT')
  })
})
