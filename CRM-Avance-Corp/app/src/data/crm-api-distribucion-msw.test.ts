// @vitest-environment node
// Contrato HTTP real de las RPC de distribución/capacidad contra Supabase
// simulado: parámetros, abort, payload JSON V2 fail-closed y errores seguros.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  actualizarCapacidadLeadsObjetivo,
} from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const ANALISTA_ID = '11111111-1111-4111-8111-111111111111'
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
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
