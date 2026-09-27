// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { obtenerConversionEstado } from './crm-api'
const lead = '11111111-1111-4111-8111-111111111111'
const ruta = 'http://supabase.test/rest/v1/rpc/conversion_estado_lead_v1'
const pendiente = {
  version: 1, lead_id: lead, estado: 'pendiente_fuente',
  mensaje: 'Pendiente, sin crédito: falta acreditar una operación confirmada y su vínculo.',
  periodo_comercial: null, fecha_comercial: null, plazo_hasta: null,
  confirmado_en: null, vinculado_en: null,
}
const servidor = setupServer()
beforeAll(() => servidor.listen({ onUnhandledRequest: 'error' }))
afterEach(() => servidor.resetHandlers())
afterAll(() => servidor.close())
describe('contrato de estado de conversión', () => {
  it('consulta el esquema CRM y el lead exacto; pendiente es un dato explícito', async () => {
    servidor.use(http.post(ruta, async ({ request }) => {
      expect(request.headers.get('content-profile')).toBe('crm')
      expect(await request.json()).toEqual({ p_lead_id: lead })
      return HttpResponse.json(pendiente)
    }))
    await expect(obtenerConversionEstado(lead)).resolves.toEqual(pendiente)
  })
  it.each([null, {}, { ...pendiente, version: 2 }, { ...pendiente, lead_id: '22222222-2222-4222-8222-222222222222' },
    { ...pendiente, estado: 'estado_desconocido' }, { ...pendiente, fecha_comercial: 'no-fecha' }])(
    'rechaza respuestas inválidas sin afirmar cero crédito (%j)', async (respuesta) => {
      servidor.use(http.post(ruta, () => HttpResponse.json(respuesta)))
      await expect(obtenerConversionEstado(lead)).rejects.toMatchObject({ code: 'CONVERSION_ESTADO_CONTRACT' })
    })
  it('un 403 no se convierte en pendiente', async () => {
    servidor.use(http.post(ruta, () => HttpResponse.json({ code: '42501', message: 'Sin acceso' }, { status: 403 })))
    await expect(obtenerConversionEstado(lead)).rejects.toThrow()
  })
  it('rechaza ID inválido antes de llamar a la red', async () => {
    await expect(obtenerConversionEstado('invalido')).rejects.toMatchObject({ code: 'CONVERSION_LEAD_INVALIDO' })
  })
  it('una señal abortada no devuelve un estado inventado', async () => {
    const controlador = new AbortController()
    controlador.abort()
    await expect(obtenerConversionEstado(lead, controlador.signal)).rejects.toMatchObject({ name: 'AbortError' })
  })
})
