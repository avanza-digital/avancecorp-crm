// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { guardarConfiguracionReparto, obtenerConfiguracionReparto } from './reparto-config-api'
const server = setupServer()
const rpc = (nombre: string) => `http://supabase.test/rest/v1/rpc/${nombre}`
const config = { version: 1, coordinacion_libre: true, revision: 2, actualizado_en: '2026-10-07T15:00:00Z' }
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('Contrato HTTP del control de reparto', () => {
  it('consulta el estado confirmado', async () => {
    server.use(http.post(rpc('configuracion_reparto_fn'), () => HttpResponse.json(config)))
    await expect(obtenerConfiguracionReparto()).resolves.toEqual(config)
  })
  it('envía el nuevo estado y la revisión esperada', async () => {
    let cuerpo: unknown
    server.use(http.post(rpc('guardar_configuracion_reparto_fn'), async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json(config)
    }))
    await expect(guardarConfiguracionReparto(true, 1)).resolves.toEqual(config)
    expect(cuerpo).toEqual({ p_libre: true, p_revision: 1 })
  })
  it.each([{}, { ...config, coordinacion_libre: 'true' }, { ...config, revision: 0 }])('rechaza estados incompletos o inválidos', async (payload) => {
    server.use(http.post(rpc('configuracion_reparto_fn'), () => HttpResponse.json(payload)))
    await expect(obtenerConfiguracionReparto()).rejects.toMatchObject({ code: 'CONTRATO_REPARTO_INVALIDO' })
  })
  it('preserva el conflicto de otra sesión', async () => {
    server.use(http.post(rpc('guardar_configuracion_reparto_fn'), () => HttpResponse.json({ code: 'PT409', message: 'Conflicto' }, { status: 409 })))
    await expect(guardarConfiguracionReparto(false, 1)).rejects.toMatchObject({ code: 'PT409', message: expect.stringContaining('Otra sesión') })
  })
  it('un rechazo de permisos no se interpreta como estado apagado', async () => {
    server.use(http.post(rpc('configuracion_reparto_fn'), () => HttpResponse.json({ code: '42501', message: 'Denegado' }, { status: 403 })))
    await expect(obtenerConfiguracionReparto()).rejects.toMatchObject({ code: '42501' })
  })
})
