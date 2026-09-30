// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import muestra from './gestion-diaria-cola-sql.fixture.json'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { obtenerColaTrabajo } from './gestion-diaria-cola-api'
import type { PedidoColaTrabajo } from '@/lib/gestion-diaria-cola'
const server = setupServer()
const rpc = 'http://supabase.test/rest/v1/rpc/gestion_diaria_cola_trabajo_fn'
const pedido: PedidoColaTrabajo = { filtro: 'sin_conversacion', pagina: 0, limite: 8, elegido: muestra.elegido }
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
describe('cola de trabajo: contrato sobre muestra del SQL local', () => {
  it('acepta el ancla de la última página entre 530 y envía sólo navegación', async () => {
    let recibido: unknown
    server.use(http.post(rpc, async ({ request }) => { recibido = await request.json(); return HttpResponse.json(muestra) }))
    const r = await obtenerColaTrabajo(pedido, muestra.analista_id, muestra.dia)
    expect(recibido).toEqual({ p_filtro: 'sin_conversacion', p_pagina: 0, p_limite: 8, p_elegido: muestra.elegido })
    expect(r.pagina).toBe(66)
    expect(r.total).toBe(530)
    expect(r.items.at(-1)?.ultima_gestion?.resultado).toBe('no_contesto')
  })
  it.each([
    ['otro actor', { analista_id: 'ajeno' }], ['otro día', { dia: '2020-01-01' }],
    ['otra zona', { zona: 'UTC' }], ['lista parcial', { items: [] }],
    ['conteo incorrecto', { total: 1 }], ['página incorrecta', { pagina: 0 }],
    ['sin elección pero gestionado propuesto', { elegido: null }],
    ['fin falso', { vuelta_completa: true }], ['siguiente igual', { siguiente: muestra.elegido }],
  ])('rechaza %s y no lo convierte en vacío', async (_caso, cambio) => {
    server.use(http.post(rpc, () => HttpResponse.json({ ...muestra, ...cambio })))
    await expect(obtenerColaTrabajo(pedido, muestra.analista_id, muestra.dia)).rejects.toMatchObject({ code: 'GESTION_COLA_CONTRACT' })
  })
  it('propaga permisos y permite cancelar una petición obsoleta', async () => {
    server.use(http.post(rpc, () => HttpResponse.json({ code: '42501', message: 'No autorizado' }, { status: 403 })))
    await expect(obtenerColaTrabajo(pedido, muestra.analista_id, muestra.dia)).rejects.toMatchObject({ code: '42501' })
    const controller = new AbortController(); controller.abort()
    await expect(obtenerColaTrabajo(pedido, muestra.analista_id, muestra.dia, controller.signal)).rejects.toBeDefined()
  })
})
