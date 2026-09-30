// @vitest-environment node
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { actualizarLead } from './crm-api'

const ruta = 'http://supabase.test/rest/v1/leads'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

it('la cartera existente presenta el conflicto de reasignación como reintento', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
  server.use(http.patch(ruta, () => HttpResponse.json({
    code: '40001',
    message: 'La reasignación coincidió con otra operación. Vuelve a intentarlo.',
    details: null,
    hint: null,
  }, { status: 500 })))
  await expect(actualizarLead('lead-prueba', { vendedor_id: 'analista-prueba' }))
    .rejects.toMatchObject({ code: 'REINTENTAR', message: expect.stringContaining('Vuelve a intentarlo') })
})

it('conserva el contrato de éxito del UPDATE sin un payload nuevo', async () => {
  server.use(http.patch(ruta, () => HttpResponse.json([{ id: 'lead-prueba' }])))
  await expect(actualizarLead('lead-prueba', { vendedor_id: 'analista-prueba' })).resolves.toBeUndefined()
})
