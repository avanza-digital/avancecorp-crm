// @vitest-environment node
// D-43 (bloque 2.12): la puerta crm.metricas_reuniones_fn marca con `"de_baja": true` al analista dado de baja que sigue
// en el desglose con sus citas. Contra un Supabase SIMULADO con msw (contrato HTTP real; el cliente supabase-js es el de
// verdad): la marca llega a la pantalla, solo cuando el servidor la manda, y una marca fuera de contrato tumba la
// respuesta (fail-closed, como el resto del paquete).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import { metricasReunionesDemo } from '@/lib/demo-inteligencia-comercial'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, listarMetricasReuniones } from './crm-api'

const RPC = 'http://supabase.test/rest/v1/rpc/metricas_reuniones_fn'
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  // registrarError escribe en console.error; se silencia para no ensuciar la salida.
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

const DESDE = '2026-09-01'
const HASTA = '2026-09-07'

/** El payload de ejemplo con la marca del servidor en la fila indicada (tal como la serializa jsonb). */
function respuesta(marcas: Record<number, unknown> = {}) {
  const datos = metricasReunionesDemo(DESDE, HASTA)
  return {
    ...datos,
    responsables: datos.responsables.map((fila, i) => (i in marcas ? { ...fila, de_baja: marcas[i] } : fila)),
  }
}

describe('listarMetricasReuniones · analista dado de baja (D-43)', () => {
  it('conserva "de_baja": true en la fila del analista dado de baja y no marca a los demás', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(respuesta({ 2: true }))
    }))

    const datos = await listarMetricasReuniones(DESDE, HASTA)

    expect(cuerpo).toEqual({ p_desde: DESDE, p_hasta: HASTA })
    expect(datos.responsables.map((fila) => [fila.nombre, fila.de_baja ?? null])).toEqual([
      ['Andrea Salas', null],
      ['Luis Mendoza', null],
      ['Camila Rojas', true],
    ])
    // El desglose, con el de baja dentro, suma el total.
    expect(datos.responsables.reduce((suma, fila) => suma + fila.pactadas, 0)).toBe(datos.resumen.pactadas)
  })

  it('sin bajas, ninguna fila lleva la marca (la respuesta es la de siempre)', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(respuesta())))

    const datos = await listarMetricasReuniones(DESDE, HASTA)

    expect(datos.responsables.every((fila) => !('de_baja' in fila))).toBe(true)
    expect(datos.responsables).toEqual(metricasReunionesDemo(DESDE, HASTA).responsables)
  })

  it.each([
    ['false', false],
    ['un texto', 'si'],
    ['null', null],
  ])('rechaza una marca fuera de contrato (%s): el servidor solo manda true', async (_nombre, marca) => {
    server.use(http.post(RPC, () => HttpResponse.json(respuesta({ 0: marca }))))

    const fallo = await listarMetricasReuniones(DESDE, HASTA).catch((error: unknown) => error)

    expect(fallo).toBeInstanceOf(CrmApiError)
    expect((fallo as CrmApiError).code).toBe('METRICAS_REUNIONES_CONTRACT')
  })
})

// D-46 y D-47 (bloque 2.12, ronda 2): el suspendido en el Portal sale con `"suspendido": true` y lo que el desglose deja fuera
// (citas sin responsable o de quien no es analista ni supervisor) llega como una fila «Otros» con `"otros": true`, la última
// y sin responsable. Así el desglose suma el total.
describe('listarMetricasReuniones · suspendido y fila «Otros» (D-46, D-47)', () => {
  /** El payload de ejemplo con Luis suspendido y la fila de Camila convertida en «Otros» (como la manda el servidor). */
  function respuestaConOtros(cambios: (filas: Record<string, unknown>[]) => Record<string, unknown>[] = (f) => f) {
    const datos = metricasReunionesDemo(DESDE, HASTA)
    const filas: Record<string, unknown>[] = datos.responsables.map((fila) =>
      fila.nombre === 'Luis Mendoza' ? { ...fila, suspendido: true }
        : fila.nombre === 'Camila Rojas'
          ? { ...fila, responsable_id: null, nombre: 'Otros', rol: null, supervisor_id: null, supervisor_nombre: '—', otros: true }
          : fila)
    return { ...datos, responsables: cambios(filas) }
  }

  it('conserva «suspendido» en su fila y la fila «Otros» al final, sin responsable', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(respuestaConOtros())))

    const datos = await listarMetricasReuniones(DESDE, HASTA)

    expect(datos.responsables.map((fila) => [fila.nombre, fila.de_baja ?? null, fila.suspendido ?? null, fila.otros ?? null]))
      .toEqual([
        ['Andrea Salas', null, null, null],
        ['Luis Mendoza', null, true, null],
        ['Otros', null, null, true],
      ])
    expect(datos.responsables.at(-1)?.responsable_id).toBeNull()
    // El desglose, con «Otros», suma el total.
    expect(datos.responsables.reduce((suma, fila) => suma + fila.pactadas, 0)).toBe(datos.resumen.pactadas)
  })

  it('la respuesta de antes (sin marcas ni «Otros») sigue siendo la de siempre', async () => {
    server.use(http.post(RPC, () => HttpResponse.json(metricasReunionesDemo(DESDE, HASTA))))

    const datos = await listarMetricasReuniones(DESDE, HASTA)

    expect(datos.responsables).toEqual(metricasReunionesDemo(DESDE, HASTA).responsables)
    expect(datos.responsables.every((fila) => !('suspendido' in fila) && !('otros' in fila))).toBe(true)
  })

  it.each<[string, (filas: Record<string, unknown>[]) => Record<string, unknown>[]]>([
    ['«Otros» no es la última fila', (f) => [f[2]!, f[0]!, f[1]!]],
    ['«Otros» con responsable', (f) => f.map((x) => (x.otros ? { ...x, responsable_id: 'demo-9' } : x))],
    ['dos filas «Otros»', (f) => f.map((x) => (x.nombre === 'Andrea Salas' ? { ...x, responsable_id: null, otros: true } : x))],
    ['un suspendido sin responsable', (f) => f.map((x) => (x.suspendido ? { ...x, responsable_id: null } : x))],
    ['dos marcas en la misma fila', (f) => f.map((x) => (x.suspendido ? { ...x, de_baja: true } : x))],
    ['«suspendido» que no es true', (f) => f.map((x) => (x.suspendido ? { ...x, suspendido: 'si' } : x))],
    ['«otros» que no es true', (f) => f.map((x) => (x.otros ? { ...x, otros: false } : x))],
  ])('rechaza la respuesta si %s (fail-closed)', async (_caso, cambio) => {
    server.use(http.post(RPC, () => HttpResponse.json(respuestaConOtros(cambio))))

    const fallo = await listarMetricasReuniones(DESDE, HASTA).catch((error: unknown) => error)

    expect(fallo).toBeInstanceOf(CrmApiError)
    expect((fallo as CrmApiError).code).toBe('METRICAS_REUNIONES_CONTRACT')
  })
})
