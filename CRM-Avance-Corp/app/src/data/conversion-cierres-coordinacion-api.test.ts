// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { conversionCierresCoordinacion } from './crm-api'
const server = setupServer()
const url = 'http://supabase.test/rest/v1/rpc/conversion_cierres_coordinacion_fn'
const id = '20000000-0000-4000-8000-000000000001'
const datos = { version: 1, analista_id: id, desde: '2026-10-01', hasta: '2026-10-31', disponible: true, total: 0, pagina: 0, por_pagina: 20, filas: [] }
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('puerta de cierres contra cliente HTTP real', () => {
  it('envía analista y mes sin inventar fechas ni pedir tablas', async () => {
    server.use(http.post(url, async ({ request }) => {
      expect(await request.json()).toEqual({ p_analista: id, p_periodo: '2026-10-01', p_pagina: 0 })
      expect(request.headers.get('Content-Profile')).toBe('crm')
      return HttpResponse.json(datos)
    }))
    expect(await conversionCierresCoordinacion(id, { modo: 'mes', mes: '2026-10' })).toEqual(datos)
  })
  it('envía rango y acepta el clamp de página del servidor', async () => {
    server.use(http.post(url, async ({ request }) => {
      expect(await request.json()).toEqual({ p_analista: id, p_desde: '2026-10-01', p_hasta: '2026-10-02', p_pagina: 9 })
      return HttpResponse.json({ ...datos, hasta: '2026-10-02' })
    }))
    expect((await conversionCierresCoordinacion(id, { modo: 'rango', desde: '2026-10-01', hasta: '2026-10-02' }, 9)).pagina).toBe(0)
  })
  it.each([{ analista_id: '20000000-0000-4000-8000-000000000002' }, { desde: '2026-09-01' }, { total: 1 }, { pagina: 1 }])('rechaza una respuesta de otra consulta o incompleta: %j', async (cambio) => {
    server.use(http.post(url, () => HttpResponse.json({ ...datos, ...cambio })))
    await expect(conversionCierresCoordinacion(id, { modo: 'mes', mes: '2026-10' })).rejects.toMatchObject({ code: 'CIERRES_COORDINACION_CONTRACT' })
  })
  it('deniega con mensaje seguro y respeta una consulta abortada', async () => {
    server.use(http.post(url, () => HttpResponse.json({ code: '42501', message: 'privado' }, { status: 403 })))
    await expect(conversionCierresCoordinacion(id, { modo: 'mes', mes: '2026-10' })).rejects.toThrow('No tienes permiso')
    const control = new AbortController(); control.abort()
    await expect(conversionCierresCoordinacion(id, { modo: 'mes', mes: '2026-10' }, 0, control.signal)).rejects.toMatchObject({ name: 'AbortError' })
  })
})
