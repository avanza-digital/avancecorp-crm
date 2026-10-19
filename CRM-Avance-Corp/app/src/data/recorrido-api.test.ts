// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import { recorridoFixture, recorridoId as id, recorridosFixture } from '@/test/fixtures/recorrido'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
vi.mock('@/lib/observabilidad', async (original) => ({ ...await original<typeof import('@/lib/observabilidad')>(), registrarError: vi.fn() }))
import { obtenerRecorridos } from './recorrido-api'

const URL = 'http://supabase.test/rest/v1/rpc/recorrido_leads_fn'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('lectura del recorrido', () => {
  it('divide páginas acumuladas sin omitir filas ni duplicar IDs', async () => {
    const lotes: string[][] = []
    server.use(http.post(URL, async ({ request }) => {
      const { p_lead_ids } = await request.json() as { p_lead_ids: string[] }
      lotes.push(p_lead_ids)
      return HttpResponse.json(recorridosFixture(p_lead_ids.map((leadId) => recorridoFixture(leadId))))
    }))
    const ids = Array.from({ length: 205 }, (_, n) => id(n))
    const respuesta = await obtenerRecorridos([...ids, id(1)])
    expect(lotes.map((l) => l.length)).toEqual([100, 100, 5])
    expect(respuesta?.filas).toHaveLength(205)
  })
  it('producción anterior: la ausencia de la puerta no rompe las pantallas', async () => {
    server.use(http.post(URL, () => HttpResponse.json({ code: 'PGRST202' }, { status: 404 })))
    await expect(obtenerRecorridos([id(1)])).resolves.toBeNull()
  })
  it('no convierte un rechazo de permisos en apagado ni revela texto del servidor', async () => {
    server.use(http.post(URL, () => HttpResponse.json({ code: '42501', message: 'contenido privado' }, { status: 403 })))
    await expect(obtenerRecorridos([id(1)])).rejects.toMatchObject({ code: '42501', message: 'No se pudo comprobar el recorrido del lead.' })
  })
  it.each([
    ['otra versión', { version: 2 }],
    ['lead ajeno', { filas: [recorridoFixture(id(2))] }],
    ['duplicado', { filas: [recorridoFixture(), recorridoFixture()] }],
    ['evidencia incompleta presentada como completa', { filas: [recorridoFixture(id(1), { habilita_conversion: true, estado: 'completo' })] }],
    ['exigir sin modo exigencia', { filas: [recorridoFixture(id(1), { exigible: true })] }],
  ])('rechaza contrato inconsistente: %s', async (_nombre, sobre) => {
    server.use(http.post(URL, () => HttpResponse.json({ ...recorridosFixture([recorridoFixture()]), ...sobre })))
    await expect(obtenerRecorridos([id(1)])).rejects.toMatchObject({ code: 'RECORRIDO_CONTRACT' })
  })
  it('no mezcla revisiones de configuración durante la paginación', async () => {
    let revision = 0
    server.use(http.post(URL, () => HttpResponse.json(recorridosFixture([], { revision: ++revision }))))
    await expect(obtenerRecorridos(Array.from({ length: 101 }, (_, n) => id(n)))).rejects.toMatchObject({ code: 'RECORRIDO_CONTRACT' })
  })
  it('omite filas fuera de ámbito sin inventar un recorrido vacío para ellas', async () => {
    server.use(http.post(URL, () => HttpResponse.json(recorridosFixture([]))))
    expect((await obtenerRecorridos([id(1)]))?.filas).toEqual([])
  })
  it('no consulta sin IDs y respeta la cancelación', async () => {
    await expect(obtenerRecorridos([])).resolves.toBeNull()
    const control = new AbortController(); control.abort()
    await expect(obtenerRecorridos([id(1)], control.signal)).rejects.toMatchObject({ name: 'AbortError' })
  })
})
