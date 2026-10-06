import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake', { auth: { persistSession: false } }) }
})
import { listarLlamadasCelular, listarResueltasCelular, cambiarLlamadaCelular } from './llamadas-celular-api'
import { demoPendientesCelular } from '@/lib/demo-llamadas-celular'
const servidor = setupServer()
const ruta = 'http://supabase.test/rest/v1/rpc/:comando'
beforeAll(() => servidor.listen({ onUnhandledRequest: 'error' }))
afterEach(() => servidor.resetHandlers())
afterAll(() => servidor.close())

it('pasa cursores con microsegundos sin convertirlos a Date y usa crm', async () => {
  const instante = '2026-10-06T15:00:00.123456+00:00'
  const cuerpos: unknown[] = []
  servidor.use(http.post(ruta, async ({ request, params }) => {
    expect(request.headers.get('content-profile')).toBe('crm')
    cuerpos.push(await request.json())
    return HttpResponse.json({ filas: [], siguiente: params.comando === 'llamadas_celular_bandeja_fn'
      ? { recibido_en: instante, evento_id: 'e' } : { resuelto_en: instante, evento_id: 'e' } })
  }))
  const p = await listarLlamadasCelular(null)
  await listarLlamadasCelular(p.siguiente)
  const h = await listarResueltasCelular(null)
  await listarResueltasCelular(h.siguiente)
  expect(cuerpos).toEqual([{ p_limite: 50 }, { p_limite: 50, p_antes_recibido_en: instante, p_antes_id: 'e' },
    { p_limite: 50 }, { p_limite: 50, p_antes_resuelto_en: instante, p_antes_id: 'e' }])
})

it('una lista vieja sin origen y una puerta inaccesible no se interpretan como lista vacía', async () => {
  const fila = { ...demoPendientesCelular(Date.now())[0]!, evento_origen_id: undefined }
  servidor.use(http.post(ruta, () => HttpResponse.json({ filas: [fila], siguiente: null })))
  await expect(listarLlamadasCelular(null)).rejects.toMatchObject({ code: 'LLAMADAS_CONTRACT' })
  servidor.use(http.post(ruta, () => HttpResponse.json({ message: 'Sin ámbito', code: '42501' }, { status: 403 })))
  await expect(listarResueltasCelular(null)).rejects.toMatchObject({ code: '42501' })
})

it('descarte y asociación exigen confirmación del mismo evento', async () => {
  const pedidos: unknown[] = []
  servidor.use(http.post(ruta, async ({ request, params }) => {
    pedidos.push([params.comando, await request.json()])
    return HttpResponse.json({ evento_id: 'e', repetido: false })
  }))
  await cambiarLlamadaCelular('e', { motivo: 'otro', detalle: 'Personal' })
  await cambiarLlamadaCelular('e', { lead: 'l' })
  expect(pedidos).toEqual([
    ['descartar_llamada_celular', { p_evento_id: 'e', p_motivo: 'otro', p_detalle: 'Personal' }],
    ['asociar_llamada_celular', { p_evento_id: 'e', p_lead_id: 'l' }],
  ])
  await expect(cambiarLlamadaCelular('otro', { lead: 'l' })).rejects.toMatchObject({ code: 'LLAMADAS_CONTRACT' })
})
