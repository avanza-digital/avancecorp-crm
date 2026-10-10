import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake', { auth: { persistSession: false } }) }
})
import { listarLlamadasCelular, listarResueltasCelular, cambiarLlamadaCelular, enlazarLlamadaCelular, listarResultadosParaUnir } from './llamadas-celular-api'
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

it('unir a mano: pide el historial del lead y las marcas, ofrece solo lo que la puerta aceptaría, y la unión exige el eco de los dos ids', async () => {
  // MARÍA de la demo: llamó hace 16 min (14:44Z); el margen del servidor admite resultados desde 14:34Z.
  const fila = demoPendientesCelular(Date.parse('2026-10-06T15:00:00Z'))[0]!
  const act = (id: string, creado_en: string, extra: Record<string, unknown> = {}) => ({
    id, lead_id: 'l2', tipo: 'llamada_no_contestada', detalle: null, autor_nombre: 'ANA SOTO', creado_en,
    metadata: { evento: 'resultado_llamada', resultado: 'no_contesto' }, ...extra,
  })
  const pedidos: unknown[] = []
  servidor.use(http.post(ruta, async ({ request, params }) => {
    pedidos.push([params.comando, await request.json()])
    if (params.comando === 'actividades_de_lead_fn') {
      return HttpResponse.json({ version: 1, items: [
        act('nuevo', '2026-10-06T14:50:00Z'),
        act('unido', '2026-10-06T14:48:00Z'),
        act('deshecho', '2026-10-06T14:47:00Z', { metadata: { evento: 'resultado_llamada', resultado: 'no_contesto', deshecho_en: '2026-10-06T14:49:00Z' } }),
        act('nota', '2026-10-06T14:46:00Z', { tipo: 'nota', metadata: {} }),
        act('viejo', '2026-10-06T14:20:00Z'),
      ], senales: { tiene_reunion_realizada: false, tiene_contacto: true, ultima_conversacion_en: null } })
    }
    if (params.comando === 'actividades_con_llamada_celular_fn') {
      return HttpResponse.json([{ actividad_id: 'unido', evento_id: 'otra-llamada', etiqueta: 'C1', via: 'al_colgar' }])
    }
    return HttpResponse.json({ evento_id: fila.evento_id, actividad_id: 'nuevo', repetido: false, movido: false })
  }))
  const candidatos = await listarResultadosParaUnir(fila)
  expect(candidatos.map((c) => c.id)).toEqual(['nuevo'])
  expect(pedidos[0]).toEqual(['actividades_de_lead_fn', expect.objectContaining({ p_lead_id: 'l2' })])
  expect(pedidos[1]).toEqual(['actividades_con_llamada_celular_fn', { p_actividad_ids: ['nuevo', 'unido'] }])
  await enlazarLlamadaCelular(fila.evento_id, 'nuevo')
  expect(pedidos[2]).toEqual(['enlazar_llamada_celular', { p_evento_id: fila.evento_id, p_actividad_id: 'nuevo' }])
  await expect(enlazarLlamadaCelular(fila.evento_id, 'otro')).rejects.toMatchObject({ code: 'LLAMADAS_CONTRACT' })
  servidor.use(http.post(ruta, () => HttpResponse.json({ message: 'Ese resultado ya está enlazado a otra llamada', code: '23505' }, { status: 409 })))
  await expect(enlazarLlamadaCelular(fila.evento_id, 'nuevo')).rejects.toMatchObject({ code: '23505', message: 'Ese resultado ya está enlazado a otra llamada' })
})
