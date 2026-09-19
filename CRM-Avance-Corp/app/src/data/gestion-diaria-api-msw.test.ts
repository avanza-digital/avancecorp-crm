// @vitest-environment node
// Contrato HTTP de `crm.registro_actividad_fn`: los ocho argumentos viajan con
// sus nombres y nulabilidad, la sonda pide limite+1, y una página que no
// corresponde a lo pedido (eco de desde/hasta/limite, o más filas que la sonda)
// NUNCA se pinta: se rechaza con GESTION_DIARIA_CONTRACT.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError } from './crm-api'
import { listarRegistroActividad } from './gestion-diaria-api'

const RPC = 'http://supabase.test/rest/v1/rpc/registro_actividad_fn'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const FILTROS = { dia: '2026-09-19', analistaIds: ['u1'] as const, pestana: 'llamadas' as const, etapa: null }
const ITEM = {
  id: 'a1', lead_id: 'l1', lead_nombre: 'LEAD UNO', lead_etapa: 'contactado', etapa_en_ese_momento: 'nuevo',
  tipo: 'llamada_realizada', detalle: 'Contestó', metadata: { resultado: 'volver_a_llamar' }, creado_por: 'u1',
  autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-19T15:01:00+00:00',
}
const pagina = (extra: Record<string, unknown> = {}) => ({
  version: 1, generado_en: '2026-09-19T18:00:00+00:00', desde: '2026-09-19', hasta: '2026-09-19', zona: 'America/Lima', limite: 26, items: [ITEM], ...extra,
})

describe('registro_actividad_fn (msw)', () => {
  it('manda los ocho argumentos con la sonda limite+1 y devuelve la página validada', async () => {
    let cuerpo: Record<string, unknown> | null = null
    server.use(http.post(RPC, async ({ request }) => { cuerpo = (await request.json()) as Record<string, unknown>; return HttpResponse.json(pagina()) }))
    const r = await listarRegistroActividad(FILTROS, { antes_de: '2026-09-19T15:00:00Z', antes_id: 'a9' }, 25)
    expect(cuerpo).toEqual({
      p_desde: '2026-09-19', p_hasta: '2026-09-19', p_analista_ids: ['u1'], p_tipos: ['llamada_realizada', 'llamada_no_contestada'],
      p_etapa: null, p_limite: 26, p_antes_de: '2026-09-19T15:00:00Z', p_antes_id: 'a9',
    })
    expect(r.items).toHaveLength(1)
    expect(r.items[0]?.metadata).toEqual({ resultado: 'volver_a_llamar' })
  })

  it('«todo» no manda tipos y sin cursor manda nulos', async () => {
    let cuerpo: Record<string, unknown> | null = null
    server.use(http.post(RPC, async ({ request }) => { cuerpo = (await request.json()) as Record<string, unknown>; return HttpResponse.json(pagina()) }))
    await listarRegistroActividad({ ...FILTROS, pestana: 'todo', analistaIds: null }, null, 25)
    expect(cuerpo).toMatchObject({ p_tipos: null, p_analista_ids: null, p_antes_de: null, p_antes_id: null })
  })

  it.each([
    ['eco de límite distinto', pagina({ limite: 50 })],
    ['eco de día distinto', pagina({ desde: '2026-09-18', hasta: '2026-09-18' })],
    ['más filas que la sonda', pagina({ items: Array.from({ length: 27 }, (_, i) => ({ ...ITEM, id: `a${i}` })) })],
    ['tipo fuera del catálogo', pagina({ items: [{ ...ITEM, tipo: 'fax' }] })],
    ['zona que no es Lima', pagina({ zona: 'UTC' })],
  ])('rechaza %s con GESTION_DIARIA_CONTRACT', async (_n, payload) => {
    server.use(http.post(RPC, () => HttpResponse.json(payload)))
    await expect(listarRegistroActividad(FILTROS, null, 25)).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
  })

  it('un 42501 del servidor llega como CrmApiError con su código', async () => {
    server.use(http.post(RPC, () => HttpResponse.json({ code: '42501', message: 'Solo puedes filtrar por analistas activos de tu equipo', details: null, hint: null }, { status: 403 })))
    const error = await listarRegistroActividad(FILTROS, null, 25).catch((e: unknown) => e)
    expect(error).toBeInstanceOf(CrmApiError)
    expect((error as CrmApiError).code).toBe('42501')
  })
})
