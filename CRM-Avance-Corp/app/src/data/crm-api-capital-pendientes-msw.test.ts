// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import detalle from '../../test-fixtures/capital-pendientes/detalle-pendiente.json'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { obtenerCapitalOperacionesValoradas } from './crm-api'

const rpc = (version: boolean) => `http://supabase.test/rest/v1/rpc/capital_operaciones_valoradas${version ? '_v2' : ''}_fn`
const vendedor = 'f3000000-0000-4000-8000-000000000002'
const consultar = () => obtenerCapitalOperacionesValoradas('2026-10-01', vendedor, detalle.corte_id)
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('detalle de ventas con pendientes propios', () => {
  it('acepta la respuesta SQL con 6000 PEN y 20000 USD aparte, sin consultar v1', async () => {
    const anterior = vi.fn(() => HttpResponse.json({}))
    server.use(http.post(rpc(true), async ({ request }) => {
      expect(request.headers.get('content-profile')).toBe('crm')
      expect(await request.json()).toEqual({ p_periodo: '2026-10-01', p_vendedor_id: vendedor, p_corte_id: detalle.corte_id })
      return HttpResponse.json(detalle)
    }), http.post(rpc(false), anterior))
    const resultado = await consultar()
    expect(resultado.valoracion_activa).toBe(true)
    if (!resultado.valoracion_activa) throw new Error('Falta la valoración')
    expect(resultado.total_pen).toBe(6000)
    expect(resultado.operaciones).toHaveLength(2)
    expect(resultado.cobertura?.pendientes.usd).toBe(20000)
    expect(anterior).not.toHaveBeenCalled()
  })

  it('solo una v2 ausente permite consultar v1 con los mismos parámetros', async () => {
    const { cobertura: _cobertura, ...v1 } = detalle
    const pedidos: unknown[] = []
    server.use(http.post(rpc(true), ({ request }) => {
      return request.json().then((pedido) => {
        pedidos.push(pedido)
        return HttpResponse.json({ code: 'PGRST202' }, { status: 404 })
      })
    }), http.post(rpc(false), async ({ request }) => {
      pedidos.push(await request.json())
      return HttpResponse.json(v1)
    }))
    const resultado = await consultar()
    expect(resultado).toEqual(v1)
    expect(pedidos).toHaveLength(2)
    expect(pedidos[1]).toEqual(pedidos[0])
  })

  it.each(['42501', 'PT409'])('no vuelve a v1 ante %s', async (code) => {
    const anterior = vi.fn(() => HttpResponse.json(detalle))
    server.use(http.post(rpc(true), () => HttpResponse.json({ code }, { status: code === '42501' ? 403 : 409 })),
      http.post(rpc(false), anterior))
    await expect(consultar()).rejects.toMatchObject({ code })
    expect(anterior).not.toHaveBeenCalled()
  })

  it.each([
    { ...detalle, corte_id: 'f3000000-0000-4000-8000-000000000999' },
    { ...detalle, cobertura: { ...detalle.cobertura, ventas_pendientes: [{ monto: 20000 }] } },
  ])('rechaza otro corte o una cobertura incompleta sin fallback', async (respuesta) => {
    const anterior = vi.fn(() => HttpResponse.json(detalle))
    server.use(http.post(rpc(true), () => HttpResponse.json(respuesta)), http.post(rpc(false), anterior))
    await expect(consultar()).rejects.toMatchObject({ code: 'CAPITAL_VALORADO_CONTRACT' })
    expect(anterior).not.toHaveBeenCalled()
  })
})
