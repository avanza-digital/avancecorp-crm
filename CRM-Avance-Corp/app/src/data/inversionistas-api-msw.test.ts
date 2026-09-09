// @vitest-environment node
// Cliente Supabase real contra HTTP simulado: solo la ausencia de la RPC de
// capacidad permite conservar la cartera anterior, siempre con F5 apagada.
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError } from './crm-api'
import { listarInversionistas, obtenerEstadoCarteraInversionistas } from './inversionistas-api'
import { FILTROS_INVERSIONISTAS_INICIALES } from '@/lib/inversionistas'

const RPC = 'http://supabase.test/rest/v1/rpc/cartera_inversionistas_estado_fn'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

it('RPC de capacidad ausente conserva la cartera anterior sin permitir escritura F5', async () => {
  server.use(http.post(RPC, () => HttpResponse.json({ code: 'PGRST202', message: 'RPC ausente' }, { status: 404 })))
  await expect(obtenerEstadoCarteraInversionistas(new AbortController().signal)).resolves.toEqual({
    version: 1, habilitada: false, escritura_habilitada: false, motivo: null,
  })
})

it.each([{ code: '42501', status: 403 }, { code: 'PGRST000', status: 503 }])(
  'el error $code no se disimula como F5 deshabilitada', async ({ code, status }) => {
    server.use(http.post(RPC, () => HttpResponse.json({ code, message: 'Consulta rechazada' }, { status })))
    const error = await obtenerEstadoCarteraInversionistas(new AbortController().signal).catch(e => e)
    expect(error).toBeInstanceOf(CrmApiError)
    expect(error).toMatchObject({ code })
  },
)

it('la ausencia de la RPC de listado sigue siendo un error', async () => {
  server.use(http.post('http://supabase.test/rest/v1/rpc/cartera_inversionistas_fn', () =>
    HttpResponse.json({ code: 'PGRST202', message: 'RPC de listado ausente' }, { status: 404 })))
  await expect(listarInversionistas(FILTROS_INVERSIONISTAS_INICIALES, new AbortController().signal))
    .rejects.toMatchObject({ code: 'PGRST202' })
})
