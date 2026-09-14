// @vitest-environment node
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://tasas.test', 'anon-fake') }
})
import { resolverTasa } from './crm-api'

const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

function respuesta(sobre: Record<string, unknown> = {}) {
  return { tasa_base: '15', regla: 'primera_inversion', categoria: 'nuevo', cliente_id: null,
    contrato_origen: null, contratos_previos: 0, contratos_activos: 0, prioridad_bandeja: false,
    politica: { id: 'politica', version: 13, modo: 'enforcement', tasa_base_nueva: '15', tope_tecnico: '28', vigencia_solicitud_dias: 1 },
    ...sobre }
}

it('lee el mínimo del servidor para la misma ficha de lead', async () => {
  server.use(http.post('http://tasas.test/rest/v1/rpc/resolver_tasa_lead_fn', async ({ request }) => {
    expect(await request.json()).toEqual({ p_lead_id: 'lead-1', p_categoria: 'nuevo' })
    return HttpResponse.json(respuesta({ tasa_minima_sin_autorizacion: '0.01' }))
  }))
  expect(await resolverTasa('', 'nuevo', null, undefined, 'lead-1')).toMatchObject({ tasa_base: 15, tasa_minima_sin_autorizacion: 0.01 })
})

it('un servidor anterior mantiene la base como mínimo', async () => {
  server.use(http.post('http://tasas.test/rest/v1/rpc/resolver_tasa_fn', () => HttpResponse.json(respuesta())))
  expect(await resolverTasa('cli-1', 'nuevo', null)).toMatchObject({ tasa_base: 15, tasa_minima_sin_autorizacion: 15 })
})

it.each([0, -1, 16, 0.001, 'NaN', 'Infinity'])('rechaza un mínimo inválido: %s', async (minimo) => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
  server.use(http.post('http://tasas.test/rest/v1/rpc/resolver_tasa_fn', () => HttpResponse.json(respuesta({ tasa_minima_sin_autorizacion: minimo }))))
  await expect(resolverTasa('cli-1', 'nuevo', null)).rejects.toThrow()
})

it('no interpreta una base heredada como permiso para bajar la tasa', async () => {
  server.use(http.post('http://tasas.test/rest/v1/rpc/resolver_tasa_fn', () => HttpResponse.json(respuesta({
    categoria: 'renovacion', regla: 'heredada_renovacion', tasa_minima_sin_autorizacion: 0.01,
  }))))
  await expect(resolverTasa('cli-1', 'renovacion', 'origen')).rejects.toMatchObject({ code: 'RESOLVER_TASA_CONTRACT' })
})
