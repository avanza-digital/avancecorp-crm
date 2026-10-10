import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake', { auth: { persistSession: false } }) }
})
import { listarLlamadasCelular, listarResueltasCelular, cambiarLlamadaCelular, enlazarLlamadaCelular, listarResultadosParaUnir } from './llamadas-celular-api'
import { demoPendientesCelular } from '@/lib/demo-llamadas-celular'
import { TAMANO_PAGINA_HISTORIAL } from './crm-api'
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

// Revisión del #251 (P2): la búsqueda no puede cortarse a las 500 actividades del lead ni a las 500 marcas por petición.
// El historial sintético responde como crm.actividades_de_lead_fn (del más reciente hacia atrás, cursor por id).
function servirHistorial(filas: Array<Record<string, unknown> & { id: string }>, marcas: (ids: string[]) => unknown[]) {
  const pedidos = { paginas: 0, lotesMarcas: [] as string[][] }
  servidor.use(http.post(ruta, async ({ request, params }) => {
    if (params.comando === 'actividades_con_llamada_celular_fn') {
      const { p_actividad_ids } = await request.json() as { p_actividad_ids: string[] }
      pedidos.lotesMarcas.push(p_actividad_ids)
      return HttpResponse.json(marcas(p_actividad_ids))
    }
    const args = await request.json() as { p_antes_id?: string; p_limite: number }
    const inicio = args.p_antes_id ? filas.findIndex((a) => a.id === args.p_antes_id) + 1 : 0
    pedidos.paginas++
    return HttpResponse.json({ version: 1, items: filas.slice(inicio, inicio + args.p_limite),
      senales: { tiene_reunion_realizada: false, tiene_contacto: true, ultima_conversacion_en: null } })
  }))
  return pedidos
}

it('unir a mano: un resultado válido detrás de 500 actividades más recientes del lead sigue apareciendo', async () => {
  const ahora = Date.parse('2026-10-10T15:00:00Z')
  const fila = { ...demoPendientesCelular(ahora)[0]!, ocurrio_en: '2026-10-01T15:00:00Z', recibido_en: '2026-10-01T15:00:01Z' }
  const filas = Array.from({ length: 501 }, (_, i) => ({
    id: `actividad-${i}`, lead_id: fila.lead_id, tipo: i === 500 ? 'llamada_no_contestada' : 'nota',
    detalle: null, autor_nombre: 'ANALISTA DE PRUEBA', creado_en: new Date(ahora - i * 60_000).toISOString(),
    metadata: i === 500 ? { evento: 'resultado_llamada', resultado: 'no_contesto' } : {},
  }))
  const pedidos = servirHistorial(filas, () => [])
  const resultados = await listarResultadosParaUnir(fila)
  expect(resultados.map((r) => r.id)).toEqual(['actividad-500'])
  expect(pedidos.paginas).toBe(Math.ceil(filas.length / TAMANO_PAGINA_HISTORIAL))
})

it('unir a mano: más de 500 candidatos se consultan en tandas de 500 y una marca de la última tanda también cuenta', async () => {
  const ahora = Date.parse('2026-10-06T15:00:00Z')
  const fila = demoPendientesCelular(ahora)[0]! // llamó hace 16 min: los 501 resultados (uno por segundo) caen en el margen
  const filas = Array.from({ length: 501 }, (_, i) => ({
    id: `r-${i}`, lead_id: fila.lead_id, tipo: 'llamada_no_contestada', detalle: null, autor_nombre: 'ANALISTA DE PRUEBA',
    creado_en: new Date(ahora - i * 1_000).toISOString(), metadata: { evento: 'resultado_llamada', resultado: 'no_contesto' },
  }))
  const pedidos = servirHistorial(filas, (ids) => ids.includes('r-500')
    ? [{ actividad_id: 'r-500', evento_id: 'otra-llamada', etiqueta: 'C1', via: 'al_colgar' }] : [])
  const resultados = await listarResultadosParaUnir(fila)
  expect(pedidos.lotesMarcas.map((lote) => lote.length)).toEqual([500, 1])
  expect(resultados).toHaveLength(500)
  expect(resultados.map((r) => r.id)).not.toContain('r-500')
})
