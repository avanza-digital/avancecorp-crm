// @vitest-environment node
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { listarLeadsRecibidosAnalista } from './crm-api'

const RPC = 'http://supabase.test/rest/v1/rpc/leads_recibidos_analista_fn'
const RESPUESTA = {
  version: 1,
  generado_en: '2026-09-12T15:00:00.000Z',
  periodo: {
    desde: '2026-09-10',
    hasta: '2026-09-12',
    dias: 3,
    zona: 'America/Lima',
  },
  total: 3,
  aproximados: 0,
  dias: [
    { fecha: '2026-09-10', total: 2, aproximados: 0 },
    { fecha: '2026-09-11', total: 0, aproximados: 0 },
    { fecha: '2026-09-12', total: 1, aproximados: 0 },
  ],
}

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('listarLeadsRecibidosAnalista (msw)', () => {
  it('envía ambas fechas y acepta el contrato diario reconciliado', async () => {
    const cuerpos: unknown[] = []
    server.use(http.post(RPC, async ({ request }) => {
      cuerpos.push(await request.json())
      return HttpResponse.json(RESPUESTA)
    }))

    await expect(listarLeadsRecibidosAnalista('2026-09-10', '2026-09-12'))
      .resolves.toMatchObject({ total: 3, dias: [{ total: 2 }, { total: 0 }, { total: 1 }] })
    expect(cuerpos).toEqual([{ p_desde: '2026-09-10', p_hasta: '2026-09-12' }])
  })

  it('rechaza una respuesta cuya suma no coincide con el total', async () => {
    server.use(http.post(RPC, () => HttpResponse.json({ ...RESPUESTA, total: 99 })))

    await expect(listarLeadsRecibidosAnalista('2026-09-10', '2026-09-12'))
      .rejects.toMatchObject({ code: 'LEADS_RECIBIDOS_ANALISTA_CONTRACT' })
  })

  it('presenta el veto de rol sin filtrar el mensaje técnico', async () => {
    server.use(http.post(RPC, () => HttpResponse.json({
      code: '42501',
      message: 'detalle interno',
    }, { status: 403 })))

    await expect(listarLeadsRecibidosAnalista('2026-09-10', '2026-09-12'))
      .rejects.toMatchObject({
        code: '42501',
        message: 'No tienes permiso para consultar este conteo.',
      })
  })

  it('frena un rango inválido antes de tocar la red', async () => {
    const handler = vi.fn()
    server.use(http.post(RPC, handler))

    await expect(listarLeadsRecibidosAnalista('2026-09-12', '2026-09-10'))
      .rejects.toMatchObject({ code: 'RANGO_INVALIDO' })
    expect(handler).not.toHaveBeenCalled()
  })
})
