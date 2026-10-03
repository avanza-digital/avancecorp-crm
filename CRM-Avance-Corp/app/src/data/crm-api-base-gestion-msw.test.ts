// @vitest-environment node
// Contrato HTTP de crm.obtener_base_gestion (B3, en producción 02/10/2026): el analista pide SU base sin
// parámetros (el servidor resuelve el actor por la sesión); Supervisión puede pedir la de un analista. Las
// cifras pueden llegar como texto y una fila fuera de contrato no se pinta.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, obtenerBaseGestion } from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const FILA = {
  lead_id: '11111111-1111-4111-8111-111111111111',
  nombre_completo: 'ROSA QUISPE',
  telefono: '+51987654321',
  distrito: 'Miraflores',
  origen: 'landing',
  categoria_interes: null,
  monto_estimado: '30000.00',
  moneda: 'USD',
  motivo_descarte: 'no_responde',
  descartado_en: '2026-09-20T14:00:00+00:00',
  dias_desde_descarte: 12,
  etapa_maxima: 'reunion_agendada',
  intentos: '2',
  ultimo_resultado: 'no_contesto',
  ultimo_intento_en: '2026-10-01T15:00:00+00:00',
  proxima_llamada_en: null,
  rellamada_hoy: false,
  enfriado_hasta: null,
  ciclo_n: 1,
  vendedor_id: '22222222-2222-4222-8222-222222222222',
  gestiona: 'CARMEN JARAMILLO',
}

describe('obtenerBaseGestion (msw)', () => {
  it('el analista pide su base SIN parámetros y recibe las cifras como números', async () => {
    let cuerpo: unknown = 'sin-cuerpo'
    server.use(
      http.post(RPC('obtener_base_gestion'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([FILA])
      }),
    )
    const filas = await obtenerBaseGestion()
    expect(cuerpo).toEqual({})
    expect(filas).toEqual([expect.objectContaining({ lead_id: FILA.lead_id, monto_estimado: 30000, intentos: 2, etapa_maxima: 'reunion_agendada' })])
  })

  it('Supervisión pide la base de UN analista con p_vendedor_id', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('obtener_base_gestion'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([])
      }),
    )
    await obtenerBaseGestion(FILA.vendedor_id)
    expect(cuerpo).toEqual({ p_vendedor_id: FILA.vendedor_id })
  })

  it('no pinta filas fuera de contrato (etapa desconocida, intentos negativos, sin booleano)', async () => {
    server.use(
      http.post(RPC('obtener_base_gestion'), () =>
        HttpResponse.json([
          FILA,
          { ...FILA, lead_id: 'etapa-rara', etapa_maxima: 'ganado' },
          { ...FILA, lead_id: 'intentos-negativos', intentos: -1 },
          { ...FILA, lead_id: 'sin-booleano', rellamada_hoy: 'si' },
        ]),
      ),
    )
    const filas = await obtenerBaseGestion()
    expect(filas.map((f) => f.lead_id)).toEqual([FILA.lead_id])
  })

  it('acepta motivos y orígenes nuevos del catálogo: se muestran tal cual, no se pierde la fila', async () => {
    server.use(http.post(RPC('obtener_base_gestion'), () => HttpResponse.json([{ ...FILA, motivo_descarte: 'motivo_nuevo', origen: 'origen_nuevo' }])))
    const filas = await obtenerBaseGestion()
    expect(filas).toHaveLength(1)
    expect(filas[0]).toMatchObject({ motivo_descarte: 'motivo_nuevo', origen: 'origen_nuevo' })
  })

  it('un analista que pide la base de otro recibe SIN_PERMISO (42501 del servidor)', async () => {
    server.use(
      http.post(RPC('obtener_base_gestion'), () =>
        HttpResponse.json({ code: '42501', message: 'Un analista solo consulta su propia base' }, { status: 403 }),
      ),
    )
    const error = await obtenerBaseGestion('33333333-3333-4333-8333-333333333333').catch((e: unknown) => e)
    expect(error).toBeInstanceOf(CrmApiError)
    expect((error as CrmApiError).code).toBe('SIN_PERMISO')
  })
})
